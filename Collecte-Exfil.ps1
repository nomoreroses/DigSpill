#Requires -Version 5.1
<#
    DigSpill - Collecte-Exfil.ps1 v2.2 - Collecte de triage forensique pour suspicion d'intrusion / exfiltration / rancongiciel.
    A lancer EN ADMINISTRATEUR sur le poste suspect (via LANCER_COLLECTE.bat ou LANCER_COLLECTE_LEGERE.bat).
    Les resultats sont ecrits sur la cle : <cle>\Collecte\<NOMPC>_<date>\

    Parametres :
      -Mode Complet|Leger   Complet (defaut) : tout. Leger : autres postes du reseau (connexions RDP,
                            executions, identifiants exposes) sans RAM, USN ni listing complet des disques.
      -Days 60              Periode d'analyse pour les evenements et fichiers recents
      -SkipFileSearch       Ne pas rechercher les archives / outils suspects
      -SkipFullListing      Ne pas faire le listing complet des disques (mode Complet)

    Memoire vive : brancher un disque externe NTFS ou exFAT contenant un dossier MEMOIRE a la racine
    AVANT de lancer. Sinon la RAM est capturee sur la cle seulement si elle est NTFS/exFAT et assez grande.

    Outils attendus dans <cle>\outils\ : winpmem_mini_x64_rc2.exe, 7zr.exe
    Velociraptor (<cle>\Collecteur-Velociraptor.exe) sert aussi de moteur SQLite / lecture NTFS brute.

    L'analyse orientee exfiltration (Analyse-Exfil.ps1) est lancee par LANCER_COLLECTE.bat apres Velociraptor,
    ou a posteriori par ANALYSER_COLLECTE.bat (glisser-deposer d'un dossier de collecte).
#>
[CmdletBinding()]
param(
    [ValidateSet('Complet','Leger')][string]$Mode = 'Complet',
    [int]$Days = 60,
    [switch]$SkipFileSearch,
    [switch]$SkipFullListing
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$ScriptVersion = '2.2'
$StartTime = Get-Date
$Full = ($Mode -eq 'Complet')

$Root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$Tools    = Join-Path $Root 'outils'
$Velo     = Join-Path $Root 'Collecteur-Velociraptor.exe'
$Computer = $env:COMPUTERNAME
$Stamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$Out      = Join-Path $Root ("Collecte\{0}_{1}{2}" -f $Computer, $Stamp, $(if ($Full) { '' } else { '_leger' }))
$Since    = (Get-Date).AddDays(-$Days)
$UsbQ     = Split-Path $Root -Qualifier
$IsAdmin  = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

foreach ($d in 'volatile','memoire','systeme','comptes','connexions','exposition','persistance','reseau','evenements','evenements\evtx','artefacts','utilisateurs','fichiers','rancon','outils_distants') {
    New-Item -ItemType Directory -Force -Path (Join-Path $Out $d) | Out-Null
}
$LogFile = Join-Path $Out 'collecte.log'

# ----------------------------------------------------------------- helpers
function Log([string]$m) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}
function P([string]$rel) { Join-Path $Out $rel }
function Step([string]$name, [scriptblock]$sb) {
    Log "[*] $name"
    try { & $sb } catch { Log "    [!] Erreur : $($_.Exception.Message)" }
}
function Save-Text([string]$rel, [scriptblock]$sb) {
    try { & $sb 2>&1 | Out-String -Width 4096 | Out-File -FilePath (P $rel) -Encoding utf8 }
    catch { Log "    [!] $rel : $($_.Exception.Message)" }
}
function Save-Csv([string]$rel, [scriptblock]$sb) {
    try { & $sb | Export-Csv -Path (P $rel) -NoTypeInformation -Encoding UTF8 }
    catch { Log "    [!] $rel : $($_.Exception.Message)" }
}
function Copy-Locked([string]$src, [string]$destDir) {
    # Copie normale, puis cliche VSS (esentutl), puis lecture NTFS brute (Velociraptor).
    # Chaque echec est journalise : un fichier absent de la collecte ne doit jamais passer inapercu.
    if (-not (Test-Path -LiteralPath $src)) { return }
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $dst = Join-Path $destDir (Split-Path $src -Leaf)
    $how = 'copie'
    try { Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop } catch {}
    if (-not (Test-Path -LiteralPath $dst) -and $IsAdmin) {
        $how = 'VSS'
        & esentutl.exe /y "$src" /vss /d "$dst" 2>&1 | Out-Null
    }
    if (-not (Test-Path -LiteralPath $dst) -and $IsAdmin -and (Test-Path -LiteralPath $Velo)) {
        $how = 'NTFS brut'
        $q = Split-Path $src -Qualifier; $rest = $src.Substring($q.Length)
        Invoke-Vql "SELECT copy(filename='''\\.\$q$rest''', accessor='ntfs', dest='''$dst''') AS Copie FROM scope()" | Out-Null
    }
    if (Test-Path -LiteralPath $dst) { if ($how -ne 'copie') { Log "    [i] $src copie par $how" } }
    else { Log "    [!] Copie impossible (copie, VSS et NTFS brut en echec$(if (-not $IsAdmin) { ', pas admin' })) : $src" }
}
function Copy-Dir([string]$src, [string]$dst) {
    if (Test-Path -LiteralPath $src) {
        New-Item -ItemType Directory -Force -Path $dst | Out-Null
        Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Copy-Backup([string]$src, [string]$dst) {
    # robocopy en mode sauvegarde (/B) : lit les dossiers proteges par ACL (quarantaine Defender...).
    # Les fichiers verrouilles (journaux en cours d'ecriture) sont ensuite repris via cliche VSS.
    if (-not (Test-Path -LiteralPath $src)) { return }
    & robocopy.exe "$src" "$dst" /E /B /COPY:DT /R:0 /W:0 /NP /NFL /NDL /NJH /NJS | Out-Null
    if ($LASTEXITCODE -lt 8) { return }
    $missing = 0
    Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $rel    = $_.FullName.Substring($src.TrimEnd('\').Length + 1)
        $target = Join-Path $dst $rel
        if (-not (Test-Path -LiteralPath $target)) {
            Copy-Locked $_.FullName (Split-Path $target -Parent)
            if (-not (Test-Path -LiteralPath $target)) { $missing++ }
        }
    }
    if ($missing) { Log "    [!] $src : $missing fichier(s) non copie(s)" }
}
function Find-SystemFile([string]$path) {
    # Get-Item echoue parfois sur pagefile.sys / hiberfil.sys : on passe par l'enumeration du dossier
    $dir  = Split-Path $path -Parent
    $leaf = Split-Path $path -Leaf
    try { ([IO.DirectoryInfo]$dir).GetFiles($leaf) | Select-Object -First 1 } catch { $null }
}
function Resolve-Sid([string]$s) {
    try { (New-Object Security.Principal.SecurityIdentifier($s)).Translate([Security.Principal.NTAccount]).Value } catch { $s }
}
function Get-Ev([string]$log, [string]$filter, [int]$max = 20000, [string]$extra = '') {
    $ms = [int64]$Days * 86400000
    $xp = "*[System[($filter) and TimeCreated[timediff(@SystemTime) <= $ms]]]$extra"
    try { @(Get-WinEvent -LogName $log -FilterXPath $xp -MaxEvents $max -ErrorAction Stop) } catch { @() }
}
function Get-EvFields($ev) {
    $h = @{}
    try {
        $x = [xml]$ev.ToXml()
        if ($x.Event.EventData) { foreach ($d in @($x.Event.EventData.Data)) { if ($d -is [Xml.XmlElement] -and $d.Name) { $h[$d.Name] = $d.InnerText } } }
        if ($x.Event.UserData)  { foreach ($n in $x.Event.UserData.FirstChild.ChildNodes) { $h[$n.LocalName] = $n.InnerText } }
    } catch {}
    $h
}
function Get-IpType([string]$ip) {
    if (-not $ip -or $ip -eq '-' ) { return '-' }
    $a = $null
    if (-not [Net.IPAddress]::TryParse($ip, [ref]$a)) { return '?' }
    if ($a.IsIPv4MappedToIPv6) { $a = $a.MapToIPv4() }
    if ([Net.IPAddress]::IsLoopback($a)) { return 'Locale' }
    $b = $a.GetAddressBytes()
    if ($b.Length -eq 4) {
        if ($b[0] -eq 10 -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168) -or ($b[0] -eq 169 -and $b[1] -eq 254)) { return 'Privee' }
        if ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127) { return 'VPN/CGNAT' }
        return 'PUBLIQUE'
    }
    if ($a.IsIPv6LinkLocal -or $a.IsIPv6SiteLocal -or ($b[0] -band 0xFE) -eq 0xFC) { return 'Privee' }
    return 'PUBLIQUE'
}
function Invoke-Vql([string]$vql) {
    # Velociraptor (collecteur) utilise comme moteur de requete : SQLite, lecture NTFS brute
    if (-not (Test-Path -LiteralPath $Velo)) { return $null }
    $prev = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        $o = & $Velo query --format csv $vql 2>$null
    } finally { [Console]::OutputEncoding = $prev }
    if ($o) { $o | ConvertFrom-Csv }
}
function Get-FreeBytes([string]$dl) { [int64](Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$dl'").FreeSpace }
function Test-Fits([string]$dl, [int64]$size, [int64]$margin) {
    $fs = "$((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$dl'").FileSystem)"
    if ($fs -match '^FAT' -and $size -ge 4GB) { return $false }   # limite FAT32 : 4 Go par fichier
    return ((Get-FreeBytes $dl) -gt ($size + $margin))
}

# Moteur C# : listing rapide des disques, date de modification des cles de registre, neutralisation XOR
$CsCode = @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

public class ExtStat { public long Count; public long Bytes; public DateTime First = DateTime.MaxValue; public DateTime Last = DateTime.MinValue; public string Sample; }
public class NoteStat { public int Count; public long Size; public DateTime Last = DateTime.MinValue; public List<string> Samples = new List<string>(); }

public class FsWalker {
    public long Files, Dirs, Errors, RansomHits, BaseHits;
    public Dictionary<string, ExtStat> Ext = new Dictionary<string, ExtStat>(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, ExtStat> RansomExt = new Dictionary<string, ExtStat>(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, NoteStat> Notes = new Dictionary<string, NoteStat>(StringComparer.OrdinalIgnoreCase);
    static readonly HashSet<string> NoteExt = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".txt", ".hta", ".html", ".htm", ".rtf", ".url" };

    static string Q(string s) { return "\"" + s.Replace("\"", "\"\"") + "\""; }
    static string D(DateTime d) { return d.ToString("yyyy-MM-dd HH:mm:ss"); }
    static void Add(Dictionary<string, ExtStat> dic, string ext, long len, DateTime t, string path) {
        ExtStat s;
        if (!dic.TryGetValue(ext, out s)) { s = new ExtStat(); s.Sample = path; dic[ext] = s; }
        s.Count++; s.Bytes += len;
        if (t < s.First) s.First = t;
        if (t > s.Last) s.Last = t;
    }

    public void Walk(string root, DateTime since, Regex ransomRx, Regex baseRx, StreamWriter all, StreamWriter ransom, StreamWriter bases) {
        Stack<DirectoryInfo> stack = new Stack<DirectoryInfo>();
        stack.Push(new DirectoryInfo(root));
        while (stack.Count > 0) {
            DirectoryInfo dir = stack.Pop();
            Dirs++;
            try {
                foreach (FileSystemInfo fsi in dir.EnumerateFileSystemInfos()) {
                    try {
                        DirectoryInfo di = fsi as DirectoryInfo;
                        if (di != null) {
                            if ((di.Attributes & FileAttributes.ReparsePoint) == 0) stack.Push(di);
                            continue;
                        }
                        FileInfo f = (FileInfo)fsi;
                        Files++;
                        DateTime c = f.CreationTime, m = f.LastWriteTime, a = f.LastAccessTime;
                        long len = f.Length;
                        string name = f.Name;
                        string line = Q(f.FullName) + "," + len + "," + D(c) + "," + D(m) + "," + D(a) + "," + Q(f.Attributes.ToString());
                        all.WriteLine(line);
                        string ext = Path.GetExtension(name);
                        if (String.IsNullOrEmpty(ext)) ext = "(aucune)";
                        DateTime t = m > c ? m : c;
                        if (ransomRx.IsMatch(name)) { ransom.WriteLine(line); RansomHits++; Add(RansomExt, ext, len, t, f.FullName); }
                        if (baseRx.IsMatch(name)) { bases.WriteLine(line); BaseHits++; }
                        if (t < since) continue;
                        Add(Ext, ext, len, t, f.FullName);
                        if (len < 102400 && NoteExt.Contains(ext)) {
                            NoteStat n;
                            if (!Notes.TryGetValue(name, out n)) { n = new NoteStat(); Notes[name] = n; }
                            n.Count++; n.Size = len;
                            if (t > n.Last) n.Last = t;
                            if (n.Samples.Count < 3) n.Samples.Add(f.FullName);
                        }
                    } catch (Exception) { Errors++; }
                }
            } catch (Exception) { Errors++; }
        }
    }
}

public static class RegTools {
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
    static extern int RegQueryInfoKey(SafeRegistryHandle hKey, IntPtr lpClass, IntPtr lpcchClass, IntPtr lpReserved, IntPtr lpcSubKeys,
        IntPtr lpcbMaxSubKeyLen, IntPtr lpcbMaxClassLen, IntPtr lpcValues, IntPtr lpcbMaxValueNameLen, IntPtr lpcbMaxValueLen,
        IntPtr lpcbSecurityDescriptor, out long lpftLastWriteTime);
    public static string LastWrite(RegistryKey k) {
        if (k == null) return "";
        long ft;
        if (RegQueryInfoKey(k.Handle, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, out ft) == 0)
            return DateTime.FromFileTime(ft).ToString("yyyy-MM-dd HH:mm:ss");
        return "";
    }
}

public static class XorTool {
    public static void XorCopy(string src, string dst, byte key) {
        using (FileStream i = new FileStream(src, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        using (FileStream o = new FileStream(dst, FileMode.Create, FileAccess.Write)) {
            byte[] b = new byte[65536]; int n;
            while ((n = i.Read(b, 0, b.Length)) > 0) { for (int j = 0; j < n; j++) b[j] ^= key; o.Write(b, 0, n); }
        }
    }
}
'@
$script:CsOk = $false
try {
    if (-not ('FsWalker' -as [type])) { Add-Type -TypeDefinition $CsCode -Language CSharp -ErrorAction Stop }
    $script:CsOk = $true
} catch { }

# Lecteurs USB (cle de collecte, disque memoire) : jamais parcourus ni listes
$script:UsbLetters = @()
try {
    $script:UsbLetters = @(Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -eq 'USB' } | Get-Partition -ErrorAction SilentlyContinue |
        Where-Object { "$($_.DriveLetter)" -match '^[A-Za-z]$' } | ForEach-Object { "$($_.DriveLetter):".ToUpper() })
} catch {}
if ($script:UsbLetters -notcontains $UsbQ.ToUpper()) { $script:UsbLetters += $UsbQ.ToUpper() }

# ----------------------------------------------------------------- en-tete
Log "=== Collecte de triage v$ScriptVersion ($Mode) sur $Computer ==="
if (-not $IsAdmin)       { Log "[!] ATTENTION : pas lance en administrateur, la collecte sera tres incomplete." }
if (-not $script:CsOk)   { Log "[!] Moteur C# indisponible : listing complet et neutralisation XOR desactives." }
if (-not (Test-Path -LiteralPath $Velo)) { Log "[!] Collecteur-Velociraptor.exe absent : identifiants navigateurs et pagefile non traites." }

Save-Text 'infos_collecte.txt' {
    "Poste            : $Computer"
    "Mode             : $Mode"
    "Domaine          : $env:USERDOMAIN"
    "Lance par        : $env:USERDOMAIN\$env:USERNAME"
    "Administrateur   : $IsAdmin"
    "Date locale      : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
    "Date UTC         : $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))"
    "Fuseau           : $([TimeZoneInfo]::Local.Id)"
    "Dernier demarrage: $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"
    "RAM              : {0:N1} Go" -f ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    "Periode analysee : $Days jours (depuis $($Since.ToString('yyyy-MM-dd')))"
    "Lecteurs USB     : $($script:UsbLetters -join ', ')"
    "Version script   : $ScriptVersion"
    "Velociraptor     : $(if (Test-Path -LiteralPath $Velo) { "SHA256 $((Get-FileHash -LiteralPath $Velo -Algorithm SHA256).Hash)" } else { 'absent' })"
    ''
    '### Decalage horaire sur la periode analysee (pour convertir les heures du rapport en UTC)'
    $tz = [TimeZoneInfo]::Local; $prev = $null
    for ($d = $Since.Date; $d -le (Get-Date).Date.AddDays(1); $d = $d.AddDays(1)) {
        $o = $tz.GetUtcOffset($d.AddHours(12))
        if ($o -ne $prev) { "  a partir du {0} : UTC{1}{2}" -f $d.ToString('yyyy-MM-dd'), $(if ($o -ge [TimeSpan]::Zero) { '+' } else { '-' }), $o.ToString('hh\:mm'); $prev = $o }
    }
}

# =================================================================== 1. VOLATILE (en premier)
Step 'Processus (ligne de commande, parent, proprietaire)' {
    $script:Procs = @{}
    $all = Get-CimInstance Win32_Process
    foreach ($p in $all) { $script:Procs[[int]$p.ProcessId] = $p }
    $owners = @{}
    if ($IsAdmin) { Get-Process -IncludeUserName -ErrorAction SilentlyContinue | ForEach-Object { $owners[[int]$_.Id] = $_.UserName } }
    Save-Csv 'volatile\processus.csv' {
        $all | Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine, CreationDate,
            @{n='Owner';e={
                if ($IsAdmin) { $owners[[int]$_.ProcessId] }
                else { try { $o = Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction Stop; if ($o.User) { "$($o.Domain)\$($o.User)" } } catch {} }
            }}
    }
    Save-Text 'volatile\tasklist_svc.txt' { tasklist /svc }
}

Step 'Connexions reseau actives' {
    Save-Csv 'volatile\tcp_connexions.csv' {
        Get-NetTCPConnection | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess, CreationTime,
            @{n='TypeIP';e={ Get-IpType $_.RemoteAddress }},
            @{n='Process';e={ $script:Procs[[int]$_.OwningProcess].Name }},
            @{n='Path';e={ $script:Procs[[int]$_.OwningProcess].ExecutablePath }},
            @{n='CommandLine';e={ $script:Procs[[int]$_.OwningProcess].CommandLine }}
    }
    Save-Csv 'volatile\udp_endpoints.csv' {
        Get-NetUDPEndpoint | Select-Object LocalAddress, LocalPort, OwningProcess, CreationTime,
            @{n='Process';e={ $script:Procs[[int]$_.OwningProcess].Name }}
    }
    Save-Text 'volatile\netstat_anob.txt' { netstat -anob }
}

Step 'Cache DNS, ARP, routes' {
    Save-Csv  'volatile\dns_cache.csv' { Get-DnsClientCache | Select-Object Entry, Name, Type, Status, Data, TimeToLive }
    Save-Text 'volatile\dns_cache_ipconfig.txt' { ipconfig /displaydns }
    Save-Text 'volatile\arp.txt' { arp -a }
    Save-Text 'volatile\routes.txt' { route print }
}

Step 'Sessions ouvertes, partages et fichiers ouverts' {
    Save-Text 'volatile\sessions_utilisateurs.txt' { query user }
    Save-Text 'volatile\net_session.txt' { net session }
    Save-Text 'volatile\net_use.txt' { net use }
    Save-Csv  'volatile\smb_sessions.csv' { Get-SmbSession -ErrorAction Stop }
    Save-Csv  'volatile\smb_fichiers_ouverts.csv' { Get-SmbOpenFile -ErrorAction Stop }
    Save-Csv  'volatile\smb_connexions_sortantes.csv' { Get-SmbConnection -ErrorAction Stop }
}

Step 'Hash et signature des executables en cours' {
    Save-Csv 'volatile\processus_binaires.csv' {
        $script:Procs.Values | Where-Object { $_.ExecutablePath } | Select-Object -ExpandProperty ExecutablePath -Unique | ForEach-Object {
            $sig = $null; $h = $null
            try { $sig = Get-AuthenticodeSignature -LiteralPath $_ -ErrorAction Stop } catch {}
            try { $h   = Get-FileHash -LiteralPath $_ -Algorithm SHA256 -ErrorAction Stop } catch {}
            [pscustomobject]@{ Path = $_; SHA256 = $h.Hash; Signature = $sig.Status; Signataire = $sig.SignerCertificate.Subject }
        }
    }
}

# =================================================================== 2. MEMOIRE (mode complet)
$script:MemDrive = $null
if ($Full) {
    Step "Memoire vive (winpmem) et fichiers d'echange (pagefile / hiberfil)" {
        $info = New-Object System.Collections.Generic.List[string]
        $ram  = [int64](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
        $info.Add(('RAM physique : {0:N1} Go' -f ($ram / 1GB)))

        # Destination : disque USB avec dossier MEMOIRE a la racine, sinon la cle si NTFS/exFAT et assez grande
        foreach ($dl in $script:UsbLetters) {
            if ($dl -ne $UsbQ.ToUpper() -and (Test-Path -LiteralPath "$dl\MEMOIRE" -PathType Container) -and (Test-Fits $dl $ram 512MB)) { $script:MemDrive = $dl; break }
        }
        $memDir = $null
        if ($script:MemDrive) { $memDir = "$($script:MemDrive)\MEMOIRE\${Computer}_$Stamp" }
        elseif (Test-Fits $UsbQ $ram 3GB) { $memDir = P 'memoire' }

        $pmem = Join-Path $Tools 'winpmem_mini_x64_rc2.exe'
        if (-not $memDir) {
            Log '    [i] RAM non capturee : pas de disque externe avec dossier MEMOIRE, et la cle est FAT32 ou trop petite'
            $info.Add('RAM non capturee : aucun support adapte. Brancher un disque NTFS/exFAT avec un dossier MEMOIRE a la racine avant de lancer.')
        } elseif (-not (Test-Path -LiteralPath $pmem)) {
            Log "    [!] winpmem absent ($pmem)"
            $info.Add("RAM non capturee : $pmem absent.")
        } else {
            New-Item -ItemType Directory -Force -Path $memDir | Out-Null
            $raw = Join-Path $memDir "${Computer}_$Stamp.raw"
            Log "    Capture RAM vers $raw (plusieurs minutes)..."
            $t0 = Get-Date
            & $pmem $raw 2>&1 | Out-File (P 'memoire\winpmem.log') -Encoding utf8
            if ((Test-Path -LiteralPath $raw) -and (Get-Item -LiteralPath $raw).Length -gt 0) {
                $len = (Get-Item -LiteralPath $raw).Length
                Log '    Calcul du SHA256 de la capture...'
                $h = (Get-FileHash -LiteralPath $raw -Algorithm SHA256).Hash
                $info.Add(('RAM capturee : {0} ({1:N1} Go) de {2} a {3}' -f $raw, ($len / 1GB), $t0.ToString('HH:mm:ss'), (Get-Date).ToString('HH:mm:ss')))
                $info.Add("SHA256 : $h")
                Log ('    RAM capturee : {0:N1} Go' -f ($len / 1GB))
            } else {
                $info.Add('Echec de winpmem (voir winpmem.log : integrite memoire/HVCI ou antivirus peuvent bloquer le pilote).')
                Log '    [!] Echec winpmem, voir memoire\winpmem.log'
            }
        }

        # Fichiers d'echange : restes de memoire. Lecture NTFS brute via Velociraptor (fichiers verrouilles)
        $swap = @()
        try { $swap += @(Get-CimInstance Win32_PageFileUsage -ErrorAction Stop | ForEach-Object { $_.Name }) } catch {}
        $swap += "$env:SystemDrive\hiberfil.sys", "$env:SystemDrive\swapfile.sys"
        foreach ($f in ($swap | Where-Object { $_ } | Select-Object -Unique)) {
            $it = Find-SystemFile $f
            if (-not $it) { $info.Add("$f : absent"); continue }
            $len  = [int64]$it.Length
            $dest = $null
            if ($script:MemDrive -and (Test-Fits $script:MemDrive $len 512MB)) { $dest = "$($script:MemDrive)\MEMOIRE\${Computer}_$Stamp" }
            elseif (Test-Fits $UsbQ $len 3GB) { $dest = P 'memoire' }
            if (-not $dest) {
                $msg = '{0} ({1:N1} Go) non copie : pas assez de place ou limite FAT32 de 4 Go' -f $f, ($len / 1GB)
                $info.Add($msg); Log "    [i] $msg"; continue
            }
            if (-not (Test-Path -LiteralPath $Velo)) { $info.Add("$f non copie : Velociraptor absent"); continue }
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            $dst = Join-Path $dest $it.Name
            Log ('    Copie {0} ({1:N1} Go)...' -f $f, ($len / 1GB))
            $q = Split-Path $f -Qualifier
            $rest = $f.Substring($q.Length)
            Invoke-Vql "SELECT copy(filename='''\\.\$q$rest''', accessor='ntfs', dest='''$dst''') AS Copie FROM scope()" | Out-Null
            if (Test-Path -LiteralPath $dst) {
                $msg = '{0} copie vers {1} ({2:N1} Go)' -f $f, $dst, ((Get-Item -LiteralPath $dst).Length / 1GB)
                $info.Add($msg); Log "    $msg"
            } else { $info.Add("$f : echec de copie"); Log "    [!] $f : echec de copie" }
        }
        $info | Out-File (P 'memoire\memoire_info.txt') -Encoding utf8
    }
}

# =================================================================== 3. SYSTEME / LOGICIELS / ANTIVIRUS
Step 'Informations systeme' {
    Save-Text 'systeme\systeminfo.txt' { systeminfo }
    Save-Csv  'systeme\correctifs.csv' { Get-HotFix | Select-Object HotFixID, Description, InstalledOn, InstalledBy }
    Save-Csv  'systeme\profils.csv' { Get-CimInstance Win32_UserProfile | Select-Object LocalPath, SID, LastUseTime, Loaded, Special }
}

Step 'Logiciels installes et historique installations / desinstallations' {
    Save-Csv 'systeme\logiciels_installes.csv' {
        $keys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
        Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_Classes$' } | ForEach-Object {
            $keys += "Registry::$($_.Name)\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        }
        foreach ($k in $keys) {
            Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } |
                Select-Object DisplayName, DisplayVersion, Publisher, InstallDate,
                    @{n='CleModifiee';e={ if ($script:CsOk) { try { [RegTools]::LastWrite((Get-Item -LiteralPath $_.PSPath -ErrorAction Stop)) } catch { '' } } }},
                    InstallLocation, UninstallString, @{n='Cle';e={ $_.PSChildName }}, @{n='Ruche';e={ $k }}
        }
    }
    Save-Csv 'systeme\installations_desinstallations_msi.csv' {
        foreach ($e in (Get-Ev 'Application' "Provider[@Name='MsiInstaller'] and (EventID=1033 or EventID=1034 or EventID=11707 or EventID=11708 or EventID=11724)" 5000)) {
            $act = switch ($e.Id) { 1033 {'Installation'} 11707 {'Installation'} 1034 {'Desinstallation'} 11724 {'Desinstallation'} 11708 {'Echec installation'} }
            [pscustomobject]@{ Date = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'); Action = $act; EventID = $e.Id
                Utilisateur = $(if ($e.UserId) { Resolve-Sid $e.UserId.Value }); Message = ("$($e.Message)" -replace '\s+', ' ') }
        }
    }
    Save-Csv 'systeme\fiabilite_installations.csv' {
        Get-CimInstance Win32_ReliabilityRecords -ErrorAction Stop | Where-Object { $_.TimeGenerated -ge $Since } |
            Select-Object TimeGenerated, SourceName, EventIdentifier, ProductName, @{n='Message';e={ "$($_.Message)" -replace '\s+', ' ' }}
    }
    Save-Csv 'systeme\program_files_dossiers.csv' {
        Get-ChildItem 'C:\Program Files', 'C:\Program Files (x86)', 'C:\ProgramData' -Directory -Force -ErrorAction SilentlyContinue |
            Select-Object FullName, CreationTime, LastWriteTime
    }
}

Step 'Antivirus (Defender : etat, exclusions, detections, journaux)' {
    Save-Text 'systeme\defender_etat.txt' { Get-MpComputerStatus }
    Save-Text 'systeme\defender_preferences.txt' {
        Get-MpPreference | Select-Object ExclusionPath, ExclusionExtension, ExclusionProcess, ExclusionIpAddress,
            DisableRealtimeMonitoring, DisableBehaviorMonitoring, DisableIOAVProtection, DisableScriptScanning, MAPSReporting, SubmitSamplesConsent | Format-List
    }
    Save-Csv 'systeme\defender_detections.csv' { Get-MpThreatDetection | Select-Object DetectionID, ThreatID, InitialDetectionTime, LastThreatStatusChangeTime, ProcessName, DomainUser, @{n='Resources';e={$_.Resources -join ' | '}}, ActionSuccess }
    Save-Csv 'systeme\defender_menaces.csv' { Get-MpThreat | Select-Object ThreatID, ThreatName, SeverityID, IsActive, DidThreatExecute, @{n='Resources';e={$_.Resources -join ' | '}} }
    Copy-Backup 'C:\ProgramData\Microsoft\Windows Defender\Support' (P 'systeme\defender_logs')
    Save-Text 'systeme\antivirus_securitycenter.txt' { Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | Format-List displayName, pathToSignedProductExe, productState, timestamp }
}

# =================================================================== 4. CONNEXIONS A DISTANCE ET COMPTES
$script:RdpLogons = New-Object System.Collections.Generic.List[object]
Step "Connexions a distance : RDP, ouvertures de session, echecs ($Days jours)" {
    $ipRows = New-Object System.Collections.Generic.List[object]
    function Add-Ip($ip, $date, $src, $acct) {
        $ip = "$ip".Trim()
        if ($ip -match '^\[?([0-9a-fA-F:]+)\]?:\d+$' -and $ip.Contains('.') -eq $false) { $ip = $matches[1] }
        elseif ($ip -match '^(\d+\.\d+\.\d+\.\d+):\d+$') { $ip = $matches[1] }
        if (-not $ip -or $ip -eq '-' -or $ip -eq '::1' -or $ip -eq '127.0.0.1') { return }
        $ipRows.Add([pscustomobject]@{ IP = $ip; Date = $date; Source = $src; Compte = $acct })
    }

    $r = foreach ($e in (Get-Ev 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational' 'EventID=1149' 10000)) {
        $f = Get-EvFields $e; $d = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
        Add-Ip $f['Param3'] $d 'RDP 1149' $f['Param1']
        [pscustomobject]@{ Date = $d; Utilisateur = $f['Param1']; Domaine = $f['Param2']; IP = $f['Param3'] }
    }
    $r | Export-Csv (P 'connexions\rdp_authentifications_1149.csv') -NoTypeInformation -Encoding UTF8

    $lsmLbl = @{ 21 = 'Ouverture session'; 22 = 'Bureau charge'; 23 = 'Fermeture session'; 24 = 'Deconnexion'; 25 = 'Reconnexion' }
    $r = foreach ($e in (Get-Ev 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational' 'EventID=21 or EventID=22 or EventID=23 or EventID=24 or EventID=25' 10000)) {
        $f = Get-EvFields $e; $d = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
        if ($e.Id -in 21, 25) { Add-Ip $f['Address'] $d "RDP LSM $($e.Id)" $f['User'] }
        [pscustomobject]@{ Date = $d; EventID = $e.Id; Action = $lsmLbl[[int]$e.Id]; Utilisateur = $f['User']; Session = $f['SessionID']; IP = $f['Address'] }
    }
    $r | Export-Csv (P 'connexions\rdp_sessions_LSM.csv') -NoTypeInformation -Encoding UTF8

    $r = foreach ($e in (Get-Ev 'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational' 'EventID=131 or EventID=140' 20000)) {
        $f = Get-EvFields $e; $d = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
        $ip = if ($e.Id -eq 131) { $f['ClientIP'] } else { $f['IPString'] }
        if ($e.Id -eq 131) { Add-Ip $ip $d 'RDP 131 (connexion TCP)' '' }
        [pscustomobject]@{ Date = $d; EventID = $e.Id; Action = $(if ($e.Id -eq 131) { 'Connexion TCP acceptee' } else { 'Echec identification' }); IP = $ip }
    }
    $r | Export-Csv (P 'connexions\rdp_connexions_tcp_rdpcorets.csv') -NoTypeInformation -Encoding UTF8

    # 4624 : type 10 (RDP) en totalite, type 3 (reseau) plafonne ; 7 = deverrouillage
    $logon = New-Object System.Collections.Generic.List[object]
    foreach ($lt in @(@{T='10'; M=20000}, @{T='7'; M=5000}, @{T='3'; M=20000})) {
        foreach ($e in (Get-Ev 'Security' 'EventID=4624' $lt.M " and *[EventData[Data[@Name='LogonType']='$($lt.T)']]")) {
            $f = Get-EvFields $e; $d = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
            $acct = "$($f['TargetDomainName'])\$($f['TargetUserName'])"
            if ($lt.T -eq '10') { $script:RdpLogons.Add([pscustomobject]@{ Compte = "$($f['TargetUserName'])".ToLower(); Date = $d }) }
            if ($lt.T -ne '7') { Add-Ip $f['IpAddress'] $d "4624 type $($lt.T)" $acct }
            $logon.Add([pscustomobject]@{ Date = $d; Type = $lt.T; Compte = $acct; IP = $f['IpAddress']; TypeIP = Get-IpType $f['IpAddress']; Poste = $f['WorkstationName']
                Processus = $f['ProcessName']; Authentification = $f['AuthenticationPackageName']; Eleve = $f['ElevatedToken']; LogonId = $f['TargetLogonId'] })
        }
    }
    $logon | Sort-Object Date | Export-Csv (P 'connexions\ouvertures_session_4624.csv') -NoTypeInformation -Encoding UTF8

    $r = foreach ($e in (Get-Ev 'Security' 'EventID=4778 or EventID=4779' 10000)) {
        $f = Get-EvFields $e; $d = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
        if ($e.Id -eq 4778) { Add-Ip $f['ClientAddress'] $d '4778 reconnexion' "$($f['AccountDomain'])\$($f['AccountName'])" }
        [pscustomobject]@{ Date = $d; EventID = $e.Id; Action = $(if ($e.Id -eq 4778) { 'Reconnexion' } else { 'Deconnexion' }); Compte = "$($f['AccountDomain'])\$($f['AccountName'])"; PosteClient = $f['ClientName']; IP = $f['ClientAddress']; Session = $f['SessionName'] }
    }
    $r | Export-Csv (P 'connexions\rdp_reconnexions_4778_4779.csv') -NoTypeInformation -Encoding UTF8

    $r = foreach ($e in (Get-Ev 'Security' 'EventID=4648' 10000)) {
        $f = Get-EvFields $e
        [pscustomobject]@{ Date = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'); Auteur = "$($f['SubjectDomainName'])\$($f['SubjectUserName'])"; CompteUtilise = "$($f['TargetDomainName'])\$($f['TargetUserName'])"; Serveur = $f['TargetServerName']; IP = $f['IpAddress']; Processus = $f['ProcessName'] }
    }
    $r | Export-Csv (P 'connexions\identifiants_explicites_4648.csv') -NoTypeInformation -Encoding UTF8

    # Echecs : detail + synthese par IP (force brute)
    $fail = foreach ($e in (Get-Ev 'Security' 'EventID=4625' 50000)) {
        $f = Get-EvFields $e
        [pscustomobject]@{ Date = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'); Type = $f['LogonType']; Compte = "$($f['TargetDomainName'])\$($f['TargetUserName'])"; IP = $f['IpAddress']; Poste = $f['WorkstationName']; Statut = $f['Status']; SousStatut = $f['SubStatus'] }
    }
    $fail | Export-Csv (P 'connexions\echecs_connexion_4625.csv') -NoTypeInformation -Encoding UTF8
    $fail | Group-Object IP | ForEach-Object {
        $s = $_.Group | Sort-Object Date
        [pscustomobject]@{ IP = $_.Name; TypeIP = Get-IpType $_.Name; NbEchecs = $_.Count; Premier = $s[0].Date; Dernier = $s[-1].Date
            Comptes = (($s | Select-Object -ExpandProperty Compte -Unique | Select-Object -First 15) -join ' ; '); Postes = (($s | Select-Object -ExpandProperty Poste -Unique | Select-Object -First 5) -join ' ; ') }
    } | Sort-Object NbEchecs -Descending | Export-Csv (P 'connexions\echecs_par_ip.csv') -NoTypeInformation -Encoding UTF8

    # Synthese : toutes les IP ayant ouvert une connexion reussie
    $ipRows | Group-Object IP | ForEach-Object {
        $s = $_.Group | Sort-Object Date
        [pscustomobject]@{ IP = $_.Name; TypeIP = Get-IpType $_.Name; NbEvenements = $_.Count; Premier = $s[0].Date; Dernier = $s[-1].Date
            Sources = (($s | Select-Object -ExpandProperty Source -Unique) -join ' ; '); Comptes = (($s | Where-Object { $_.Compte } | Select-Object -ExpandProperty Compte -Unique) -join ' ; ') }
    } | Sort-Object @{e={ $_.TypeIP -ne 'PUBLIQUE' }}, @{e='NbEvenements'; Descending=$true} | Export-Csv (P 'connexions\synthese_ip_connexions_reussies.csv') -NoTypeInformation -Encoding UTF8

    $pub = @($ipRows | Where-Object { (Get-IpType $_.IP) -eq 'PUBLIQUE' } | Select-Object -ExpandProperty IP -Unique)
    Log "    $($logon.Count) ouvertures de session, $(@($fail).Count) echecs, $($pub.Count) IP publiques avec connexion reussie"
    Copy-Backup 'C:\Windows\System32\LogFiles\Firewall' (P 'connexions\parefeu_journal')
}

Step "Evenements de comptes (creation, groupes, mots de passe) ($Days jours)" {
    $lbl = @{ 4720='Creation compte'; 4722='Activation compte'; 4723='Changement mdp par le titulaire'; 4724='REINITIALISATION mdp'; 4725='Desactivation compte'
              4726='Suppression compte'; 4738='Modification compte'; 4740='Verrouillage compte'; 4767='Deverrouillage compte'; 4781='Renommage compte'
              4728='Ajout groupe global'; 4732='Ajout groupe local'; 4756='Ajout groupe universel'; 4729='Retrait groupe global'; 4733='Retrait groupe local'; 4757='Retrait groupe universel' }
    $ids = ($lbl.Keys | ForEach-Object { "EventID=$_" }) -join ' or '
    Save-Csv 'comptes\evenements_comptes.csv' {
        @(foreach ($e in (Get-Ev 'Security' $ids 20000)) {
            $f = Get-EvFields $e
            $membre = $f['MemberName']
            if ((-not $membre -or $membre -eq '-') -and $f['MemberSid']) { $membre = Resolve-Sid $f['MemberSid'] }
            $det = @()
            foreach ($k in 'OldTargetUserName','NewTargetUserName','UserAccountControl','PasswordLastSet','AccountExpires','SamAccountName') { if ($f[$k] -and $f[$k] -ne '-') { $det += "$k=$($f[$k])" } }
            [pscustomobject]@{ Date = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'); EventID = $e.Id; Action = $lbl[[int]$e.Id]
                Auteur = "$($f['SubjectDomainName'])\$($f['SubjectUserName'])"; CibleOuGroupe = "$($f['TargetDomainName'])\$($f['TargetUserName'])"; Membre = $membre; Details = ($det -join ' ; ') }
        }) | Sort-Object Date
    }
}

Step 'Inventaire des comptes locaux (groupes, droits RDP, mots de passe)' {
    # Groupes locaux et membres via ADSI (tolere les SID orphelins)
    $grpMembers = @{}; $grpNames = @{}
    foreach ($g in Get-LocalGroup) {
        $gs = $g.SID.Value; $grpNames[$gs] = $g.Name; $grpMembers[$gs] = @()
        try {
            $adsi = [ADSI]"WinNT://$env:COMPUTERNAME/$($g.Name),group"
            foreach ($m in @($adsi.psbase.Invoke('Members'))) {
                $bytes = $m.GetType().InvokeMember('objectSid', 'GetProperty', $null, $m, $null)
                $grpMembers[$gs] += (New-Object Security.Principal.SecurityIdentifier($bytes, 0)).Value
            }
        } catch {}
    }
    Save-Csv 'comptes\groupes_locaux_membres.csv' {
        foreach ($gs in $grpMembers.Keys) {
            foreach ($m in $grpMembers[$gs]) { [pscustomobject]@{ Groupe = $grpNames[$gs]; GroupeSID = $gs; Membre = Resolve-Sid $m; MembreSID = $m } }
        }
    }

    # Droits d'ouverture de session (secedit)
    $rights = @{}
    $tmp = Join-Path $env:TEMP "ur_$Stamp.inf"
    & secedit.exe /export /areas USER_RIGHTS /cfg "$tmp" /quiet | Out-Null
    if (Test-Path -LiteralPath $tmp) {
        foreach ($line in Get-Content -LiteralPath $tmp) {
            if ($line -match '^(Se\w+)\s*=\s*(.*)$') {
                $rights[$matches[1]] = @($matches[2].Split(',') | ForEach-Object {
                    $v = $_.Trim()
                    if ($v.StartsWith('*')) { $v.Substring(1) } else { try { (New-Object Security.Principal.NTAccount($v)).Translate([Security.Principal.SecurityIdentifier]).Value } catch { $v } }
                })
            }
        }
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    $allow = @($rights['SeRemoteInteractiveLogonRight']); $deny = @($rights['SeDenyRemoteInteractiveLogonRight'])

    $lastRdp = @{}
    foreach ($r in $script:RdpLogons) { if (-not $lastRdp[$r.Compte] -or $r.Date -gt $lastRdp[$r.Compte]) { $lastRdp[$r.Compte] = $r.Date } }

    Save-Csv 'comptes\inventaire_comptes.csv' {
        foreach ($u in Get-LocalUser) {
            $us = $u.SID.Value
            $princ = @($us, 'S-1-1-0')
            if ($us -notmatch '-501$') { $princ += 'S-1-5-11' }      # Invite : pas "Utilisateurs authentifies"
            $memberOf = @()
            foreach ($gs in $grpMembers.Keys) { foreach ($m in $grpMembers[$gs]) { if ($princ -contains $m) { $memberOf += $gs; break } } }
            $princ += $memberOf
            $via    = @($allow | Where-Object { $princ -contains $_ } | ForEach-Object { Resolve-Sid $_ })
            $denied = @($deny  | Where-Object { $princ -contains $_ }).Count -gt 0
            $rdp = if (-not $u.Enabled) { 'Non (compte desactive)' } elseif ($denied) { 'Non (refus explicite)' } elseif ($via.Count) { 'OUI via ' + ($via -join ', ') } else { 'Non' }
            [pscustomobject]@{ Nom = $u.Name; Actif = $u.Enabled; DerniereConnexion = $u.LastLogon; DerniereConnexionRDP = $lastRdp["$($u.Name)".ToLower()]
                MdpDernierChangement = $u.PasswordLastSet; MdpObligatoire = $u.PasswordRequired; MdpExpire = $u.PasswordExpires
                Groupes = (($memberOf | ForEach-Object { $grpNames[$_] }) -join ', '); AccesRDP = $rdp; SID = $us; Description = $u.Description }
        }
    }

    Save-Text 'comptes\parametres_securite.txt' {
        $ts  = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue
        $tcp = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -ErrorAction SilentlyContinue
        $lsa = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -ErrorAction SilentlyContinue
        '### Bureau a distance'
        "RDP active (fDenyTSConnections=0)          : $($ts.fDenyTSConnections -eq 0)"
        "Port RDP                                   : $($tcp.PortNumber)"
        "NLA exigee (UserAuthentication=1)          : $($tcp.UserAuthentication -eq 1)"
        "SecurityLayer (2 = TLS)                    : $($tcp.SecurityLayer)"
        "Mdp vide interdit a distance (LimitBlankPasswordUse=1) : $($lsa.LimitBlankPasswordUse)"
        "Compte Invite actif                        : $((Get-LocalUser | Where-Object { $_.SID.Value -match '-501$' }).Enabled)"
        ''
        "### Droits d'ouverture de session"
        foreach ($k in 'SeRemoteInteractiveLogonRight','SeDenyRemoteInteractiveLogonRight','SeInteractiveLogonRight','SeNetworkLogonRight','SeDenyNetworkLogonRight','SeBackupPrivilege','SeDebugPrivilege') {
            "{0,-36}: {1}" -f $k, ((@($rights[$k]) | Where-Object { $_ } | ForEach-Object { Resolve-Sid $_ }) -join ', ')
        }
        ''
        '### Politique de mots de passe et de verrouillage (seuil 0 = force brute illimitee)'
        net accounts
    }
}

# =================================================================== 5. PERSISTANCE
Step 'Services' {
    Save-Csv 'persistance\services.csv' { Get-CimInstance Win32_Service | Select-Object Name, DisplayName, State, StartMode, StartName, PathName, Description }
}

Step 'Taches planifiees' {
    Save-Text 'persistance\taches_planifiees.csv' { schtasks /query /fo csv /v }
    Copy-Dir 'C:\Windows\System32\Tasks' (P 'persistance\Tasks_xml')
}

Step 'Cles Run / Winlogon / IFEO' {
    Save-Csv 'persistance\cles_demarrage.csv' {
        $sub = @('Software\Microsoft\Windows\CurrentVersion\Run', 'Software\Microsoft\Windows\CurrentVersion\RunOnce',
                 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
                 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run', 'Software\Microsoft\Windows NT\CurrentVersion\Winlogon',
                 'Software\Microsoft\Windows NT\CurrentVersion\Windows')
        $paths = @($sub | ForEach-Object { "HKLM:\$_" })
        Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_Classes$' } | ForEach-Object {
            $h = $_.Name; $paths += ($sub | ForEach-Object { "Registry::$h\$_" })
        }
        foreach ($p in $paths) {
            if (Test-Path $p) {
                $kt = if ($script:CsOk) { try { [RegTools]::LastWrite((Get-Item $p -ErrorAction Stop)) } catch { '' } }
                $props = Get-ItemProperty $p -ErrorAction SilentlyContinue
                $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } |
                    ForEach-Object { [pscustomobject]@{ Cle = $p; CleModifiee = $kt; Nom = $_.Name; Valeur = "$($_.Value)" } }
            }
        }
        Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' -ErrorAction SilentlyContinue | ForEach-Object {
            $dbg = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).Debugger
            if ($dbg) { [pscustomobject]@{ Cle = $_.Name; CleModifiee = ''; Nom = 'Debugger'; Valeur = $dbg } }
        }
    }
}

Step 'Dossiers Demarrage' {
    Save-Csv 'persistance\dossiers_demarrage.csv' {
        $dirs = @('C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp')
        Get-ChildItem 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $dirs += Join-Path $_.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
        }
        foreach ($d in $dirs) { Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | Select-Object FullName, CreationTime, LastWriteTime, Length }
    }
}

Step 'Abonnements WMI (persistance furtive)' {
    Save-Text 'persistance\wmi_abonnements.txt' {
        '### __EventFilter';               Get-CimInstance -Namespace root\subscription -ClassName __EventFilter | Format-List *
        '### CommandLineEventConsumer';    Get-CimInstance -Namespace root\subscription -ClassName CommandLineEventConsumer | Format-List *
        '### ActiveScriptEventConsumer';   Get-CimInstance -Namespace root\subscription -ClassName ActiveScriptEventConsumer | Format-List *
        '### __FilterToConsumerBinding';   Get-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding | Format-List *
    }
}

Step 'Transferts BITS' {
    Save-Text 'persistance\bits_jobs.txt' { Get-BitsTransfer -AllUsers | Format-List * }
}

# =================================================================== 6. CONFIGURATION RESEAU
Step 'Configuration reseau, proxy, hosts, partages, pare-feu' {
    Save-Text 'reseau\ipconfig_all.txt' { ipconfig /all }
    Save-Text 'reseau\proxy_winhttp.txt' { netsh winhttp show proxy }
    Save-Csv  'reseau\proxy_utilisateurs.csv' {
        Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_Classes$' } | ForEach-Object {
            $k = "Registry::$($_.Name)\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
            $v = Get-ItemProperty $k -ErrorAction SilentlyContinue
            if ($v) { [pscustomobject]@{ Hive = $_.Name; ProxyEnable = $v.ProxyEnable; ProxyServer = $v.ProxyServer; AutoConfigURL = $v.AutoConfigURL } }
        }
    }
    Copy-Item 'C:\Windows\System32\drivers\etc\hosts' (P 'reseau\hosts.txt') -ErrorAction SilentlyContinue
    Save-Csv  'reseau\vpn.csv' { Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue; Get-VpnConnection -ErrorAction SilentlyContinue }
    Save-Csv  'reseau\partages_smb.csv' { Get-SmbShare | Select-Object Name, Path, Description, ScopeName }
    Save-Csv  'reseau\lecteurs_mappes.csv' { Get-SmbMapping -ErrorAction Stop }
    Save-Csv  'reseau\rdp_connexions_sortantes.csv' {
        Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_Classes$' } | ForEach-Object {
            $h = $_.Name
            Get-ChildItem "Registry::$h\Software\Microsoft\Terminal Server Client\Servers" -ErrorAction SilentlyContinue | ForEach-Object {
                [pscustomobject]@{ Hive = $h; Serveur = $_.PSChildName; UsernameHint = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).UsernameHint }
            }
        }
    }
    Save-Text 'reseau\parefeu_profils.txt' { netsh advfirewall show allprofiles }
    Save-Text 'reseau\parefeu_regles.txt' { netsh advfirewall firewall show rule name=all verbose }
    # Journalisation du pare-feu : activee ou non, et copie du journal s'il est hors du dossier par defaut
    Save-Csv 'reseau\parefeu_journalisation.csv' {
        Get-NetFirewallProfile -ErrorAction Stop | Select-Object Name, Enabled, DefaultOutboundAction, LogAllowed, LogBlocked, LogIgnored, LogFileName, LogMaxSizeKilobytes,
            @{n='FichierPresent';e={ Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($_.LogFileName)) }}
    }
    foreach ($fw in @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)) {
        $lf = [Environment]::ExpandEnvironmentVariables("$($fw.LogFileName)")
        if ($lf -and $lf -notlike '*\System32\LogFiles\Firewall\*') { Copy-Locked $lf (P 'connexions\parefeu_journal') }
    }
    # Redirections Bureau a distance (lecteurs \\tsclient, presse-papier...) : 0 ou absent = autorise
    Save-Text 'reseau\rdp_redirections.txt' {
        foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services', 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp') {
            "### $k"
            $v = Get-ItemProperty $k -ErrorAction SilentlyContinue
            foreach ($n in 'fDisableCdm', 'fDisableClip', 'fDisableCcm', 'fDisableLPT', 'fDisablePNPRedir', 'fDisableCpm', 'fDisableAudioCapture', 'fDisableCam') {
                '{0,-22}: {1}' -f $n, $(if ($v -and $null -ne $v.$n) { $v.$n } else { '(absent)' })
            }
        }
    }
}

Step 'Etat des journaux et politique d''audit (journal desactive = piste verifiee mais non exploitable)' {
    Save-Csv 'evenements\etat_journaux.csv' {
        foreach ($l in @('Security', 'System', 'Microsoft-Windows-DNS-Client/Operational', 'Microsoft-Windows-SMBServer/Security', 'Microsoft-Windows-SMBServer/Operational',
                         'Microsoft-Windows-SMBClient/Security', 'Microsoft-Windows-Bits-Client/Operational', 'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall',
                         'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational', 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational',
                         'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational', 'Microsoft-Windows-TerminalServices-PnPDevices/Admin',
                         'Microsoft-Windows-PowerShell/Operational', 'Microsoft-Windows-Sysmon/Operational', 'Microsoft-Windows-Partition/Diagnostic',
                         'Microsoft-Windows-Kernel-PnP/Configuration', 'Microsoft-Windows-Windows Defender/Operational')) {
            $i = Get-WinEvent -ListLog $l -ErrorAction SilentlyContinue
            $old = if ($i -and $i.RecordCount) { try { (Get-WinEvent -LogName $l -Oldest -MaxEvents 1 -ErrorAction Stop).TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') } catch { '' } }
            [pscustomobject]@{ Journal = $l; Existe = [bool]$i; Active = $(if ($i) { $i.IsEnabled }); NbEvenements = $(if ($i) { $i.RecordCount }); PlusAncien = $old
                TailleMo = $(if ($i) { [math]::Round($i.FileSize / 1MB, 1) }); TailleMaxMo = $(if ($i) { [math]::Round($i.MaximumSizeInBytes / 1MB, 1) }); Mode = $(if ($i) { $i.LogMode }) }
        }
    }
    Save-Text 'systeme\auditpol.txt' { auditpol /get /category:* }
}

# =================================================================== 7. JOURNAUX D'EVENEMENTS
Step 'Export des journaux .evtx' {
    $logs = @('Security', 'System', 'Application', 'Windows PowerShell',
        'Microsoft-Windows-PowerShell/Operational', 'Microsoft-Windows-Sysmon/Operational',
        'Microsoft-Windows-TaskScheduler/Operational', 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational',
        'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational', 'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational',
        'Microsoft-Windows-Windows Defender/Operational', 'Microsoft-Windows-Bits-Client/Operational', 'Microsoft-Windows-WinRM/Operational',
        'Microsoft-Windows-SMBClient/Security', 'Microsoft-Windows-SMBServer/Security', 'Microsoft-Windows-DNS-Client/Operational',
        'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall', 'Microsoft-Windows-Partition/Diagnostic',
        'Microsoft-Windows-DriverFrameworks-UserMode/Operational', 'Microsoft-Windows-Kernel-PnP/Configuration',
        'Microsoft-Windows-WMI-Activity/Operational', 'Microsoft-Windows-NTLM/Operational', 'Microsoft-Windows-Shell-Core/Operational',
        'Microsoft-Windows-CodeIntegrity/Operational', 'Microsoft-Windows-WLAN-AutoConfig/Operational', 'OpenSSH/Operational',
        'Microsoft-Windows-VolumeSnapshot-Driver/Operational', 'Microsoft-Windows-SMBServer/Operational', 'Microsoft-Windows-SMBServer/Audit',
        'Microsoft-Windows-SmbClient/Connectivity', 'Microsoft-Windows-TerminalServices-PnPDevices/Admin', 'Microsoft-Windows-TerminalServices-PnPDevices/Operational',
        'Microsoft-Windows-TerminalServices-RDPClient/Operational', 'Microsoft-Windows-TerminalServices-Printers/Admin',
        'Splashtop-Splashtop Streamer-Remote Session/Operational', 'Splashtop-Splashtop Streamer-Status/Operational')
    foreach ($l in $logs) {
        $info = Get-WinEvent -ListLog $l -ErrorAction SilentlyContinue
        if ($info -and $info.RecordCount -gt 0) {
            $name = ($l -replace '[\\/:\s]', '_') + '.evtx'
            & wevtutil.exe epl "$l" (P "evenements\evtx\$name") 2>$null
            if ($LASTEXITCODE -ne 0) { Log "    [!] Export impossible : $l" }
        }
    }
}

Step "Extraction des evenements cles ($Days jours)" {
    $q = @(
        @{L='Security'; I='EventID=4625 or EventID=4648 or EventID=4720 or EventID=4722 or EventID=4724 or EventID=4728 or EventID=4732 or EventID=4738 or EventID=4756 or EventID=1102 or EventID=4697 or EventID=4698 or EventID=4702 or EventID=4778 or EventID=4779 or EventID=5140'; M=20000},
        @{L='Security'; I='EventID=4688'; M=30000},
        @{L='System'; I='EventID=7045 or EventID=7040 or EventID=104 or EventID=6005 or EventID=6006 or EventID=6008 or EventID=1074'; M=5000},
        @{L='Microsoft-Windows-PowerShell/Operational'; I='EventID=4104'; M=5000},
        @{L='Windows PowerShell'; I='EventID=400'; M=5000},
        @{L='Microsoft-Windows-Windows Defender/Operational'; I='EventID=1116 or EventID=1117 or EventID=5001 or EventID=5007 or EventID=5013'; M=5000},
        @{L='Microsoft-Windows-Bits-Client/Operational'; I='EventID=59 or EventID=60'; M=5000},
        @{L='Microsoft-Windows-Partition/Diagnostic'; I='EventID=1006'; M=5000},
        @{L='Microsoft-Windows-TaskScheduler/Operational'; I='EventID=106 or EventID=140 or EventID=141'; M=5000},
        @{L='Microsoft-Windows-WinRM/Operational'; I='EventID=6 or EventID=91'; M=5000},
        @{L='Microsoft-Windows-Sysmon/Operational'; I='EventID=1 or EventID=3 or EventID=11 or EventID=22'; M=50000}
    )
    $res = New-Object System.Collections.Generic.List[object]
    foreach ($e in $q) {
        foreach ($ev in (Get-Ev $e.L $e.I $e.M)) {
            $msg = "$($ev.Message)" -replace '\s+', ' '
            if ($msg.Length -gt 4000) { $msg = $msg.Substring(0, 4000) + '...' }
            $res.Add([pscustomobject]@{ Date = $ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'); Journal = $e.L; EventID = $ev.Id; Source = $ev.ProviderName; Message = $msg })
        }
    }
    $res | Sort-Object Date | Export-Csv (P 'evenements\resume_evenements_cles.csv') -NoTypeInformation -Encoding UTF8
    Log "    $($res.Count) evenements cles extraits"
}

# =================================================================== 8. ARTEFACTS SYSTEME
Step 'Ruches de registre SYSTEM, SOFTWARE, SAM' {
    New-Item -ItemType Directory -Force -Path (P 'artefacts\registre') | Out-Null
    & reg.exe save HKLM\SYSTEM   (P 'artefacts\registre\SYSTEM')   /y | Out-Null
    & reg.exe save HKLM\SOFTWARE (P 'artefacts\registre\SOFTWARE') /y | Out-Null
    & reg.exe save HKLM\SAM      (P 'artefacts\registre\SAM')      /y | Out-Null
}

Step 'Amcache, SRUM (volumes reseau par application), Prefetch' {
    Copy-Locked 'C:\Windows\appcompat\Programs\Amcache.hve' (P 'artefacts\amcache')
    Copy-Locked 'C:\Windows\System32\sru\SRUDB.dat'         (P 'artefacts\srum')
    Copy-Dir    'C:\Windows\Prefetch'                         (P 'artefacts\prefetch')
    Save-Csv 'artefacts\prefetch_liste.csv' {
        Get-ChildItem 'C:\Windows\Prefetch' -Filter '*.pf' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending |
            Select-Object @{n='Programme';e={ $_.Name -replace '-[0-9A-F]{8}\.pf$', '' }}, @{n='PremiereExecution_approx';e={ $_.CreationTime }}, @{n='DerniereExecution';e={ $_.LastWriteTime }}, Name
    }
}

if ($Full) {
    Step 'Journal USN via fsutil (creations / suppressions / renommages de fichiers)' {
        Get-CimInstance Win32_Volume -Filter "DriveType=3 AND FileSystem='NTFS'" | Where-Object { $_.DriveLetter -and $script:UsbLetters -notcontains $_.DriveLetter.ToUpper() } | ForEach-Object {
            $dl  = $_.DriveLetter
            $tag = $dl.TrimEnd(':')
            & fsutil.exe usn queryjournal $dl 2>&1 | Out-File (P "artefacts\usn_${tag}_infos.txt") -Encoding utf8
            $dst = P "artefacts\usn_journal_${tag}.csv"
            & cmd.exe /c "fsutil usn readjournal $dl csv > `"$dst`""
            if (Test-Path -LiteralPath $dst) { Log ("    {0} : {1} Mo" -f $dl, [math]::Round((Get-Item -LiteralPath $dst).Length / 1MB, 1)) }
        }
    }
}

Step 'Historique peripheriques USB, cache URL certutil, corbeille' {
    Copy-Item 'C:\Windows\INF\setupapi.dev.log' (P 'artefacts\setupapi.dev.log') -ErrorAction SilentlyContinue
    Save-Csv 'artefacts\usb_stockage.csv' {
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR' -ErrorAction SilentlyContinue | ForEach-Object {
            $type = $_.PSChildName
            Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
                [pscustomobject]@{ Type = $type; Serie = $_.PSChildName; Nom = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).FriendlyName }
            }
        }
    }
    # Dates de premiere installation, dernier branchement et dernier retrait de chaque stockage USB / appareil portable
    Save-Csv 'artefacts\usb_peripheriques_dates.csv' {
        $keys = 'DEVPKEY_Device_FirstInstallDate', 'DEVPKEY_Device_InstallDate', 'DEVPKEY_Device_LastArrivalDate', 'DEVPKEY_Device_LastRemovalDate'
        Get-PnpDevice -ErrorAction Stop | Where-Object { $_.InstanceId -match '^(USBSTOR|SWD\\WPDBUSENUM|USB\\VID)' -and ($_.InstanceId -notmatch '^USB\\VID' -or $_.Class -in 'WPD', 'DiskDrive', 'Image') } | ForEach-Object {
            $p = @{}
            foreach ($x in @(Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName $keys -ErrorAction SilentlyContinue)) { $p[$x.KeyName] = $x.Data }
            [pscustomobject]@{ Nom = $_.FriendlyName; Classe = $_.Class; Present = $_.Present; InstanceId = $_.InstanceId
                PremiereInstallation = $p['DEVPKEY_Device_FirstInstallDate']; Installation = $p['DEVPKEY_Device_InstallDate']
                DernierBranchement = $p['DEVPKEY_Device_LastArrivalDate']; DernierRetrait = $p['DEVPKEY_Device_LastRemovalDate'] }
        }
    }
    Save-Text 'artefacts\certutil_urlcache.txt' { certutil -urlcache * }
    Save-Csv  'artefacts\corbeille.csv' { Get-ChildItem 'C:\$Recycle.Bin' -Recurse -Force -File -ErrorAction SilentlyContinue | Select-Object FullName, Length, CreationTime, LastWriteTime }
}

# =================================================================== 9. ARTEFACTS PAR UTILISATEUR
$script:UserProfiles = @(Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.LocalPath -and (Test-Path $_.LocalPath) })
$Chromium = [ordered]@{ 'chrome' = 'Local\Google\Chrome\User Data'; 'edge' = 'Local\Microsoft\Edge\User Data'; 'brave' = 'Local\BraveSoftware\Brave-Browser\User Data'; 'opera' = 'Roaming\Opera Software' }

Step 'Artefacts utilisateurs (registre, historiques, navigateurs, outils distants)' {
    foreach ($pr in $script:UserProfiles) {
        $lp = $pr.LocalPath
        $u  = Split-Path $lp -Leaf
        $d  = P "utilisateurs\$u"
        Log "    - $u"
        New-Item -ItemType Directory -Force -Path $d | Out-Null

        Copy-Locked "$lp\NTUSER.DAT" "$d\registre"
        Copy-Locked "$lp\AppData\Local\Microsoft\Windows\UsrClass.dat" "$d\registre"
        if (-not (Test-Path -LiteralPath "$d\registre\NTUSER.DAT")) { Log "    [!] $u : NTUSER.DAT NON collecte (RecentDocs, ShellBags, TypedPaths indisponibles hors conteneur Velociraptor)" }
        Copy-Locked "$lp\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" "$d\powershell"
        Copy-Dir "$lp\AppData\Roaming\Microsoft\Windows\Recent" "$d\recent"

        # Navigateurs : historique (inclut les telechargements). Pas de mots de passe ni cookies.
        foreach ($b in $Chromium.Keys) {
            $base = Join-Path "$lp\AppData" $Chromium[$b]
            Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if (Test-Path -LiteralPath "$($_.FullName)\History") { Copy-Locked "$($_.FullName)\History" "$d\navigateurs\${b}_$($_.Name)" }
            }
        }
        Get-ChildItem "$lp\AppData\Roaming\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Locked "$($_.FullName)\places.sqlite" "$d\navigateurs\firefox_$($_.Name)"
        }

        # Outils de transfert / acces distant souvent utilises pour l'exfiltration
        $tl = @(
            "$lp\AppData\Roaming\rclone\rclone.conf", "$lp\.config\rclone\rclone.conf",
            "$lp\AppData\Roaming\FileZilla\recentservers.xml", "$lp\AppData\Roaming\FileZilla\sitemanager.xml",
            "$lp\AppData\Roaming\WinSCP.ini", "$lp\AppData\Roaming\AnyDesk\ad.trace", "$lp\AppData\Roaming\AnyDesk\connection_trace.txt",
            "$lp\AppData\Roaming\TeamViewer\Connections.txt", "$lp\.ssh\known_hosts", "$lp\.ssh\config"
        )
        foreach ($t in $tl) { Copy-Locked $t "$d\outils" }
        Get-ChildItem "$lp\AppData\Roaming\TeamViewer" -Filter '*.log' -ErrorAction SilentlyContinue | ForEach-Object { Copy-Locked $_.FullName "$d\outils" }
        foreach ($rd in "$lp\AppData\Roaming\RustDesk\log", "$lp\AppData\Local\Splashtop", "$lp\AppData\Roaming\Netbird") {
            Get-ChildItem -LiteralPath $rd -Recurse -File -Include '*.log', '*.txt' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $Since -and $_.Length -lt 50MB } |
                ForEach-Object { Copy-Locked $_.FullName "$d\outils\$(Split-Path $rd -Leaf)" }
        }

        Save-Csv "utilisateurs\$u\appdata_dossiers.csv" {
            Get-ChildItem "$lp\AppData\Local", "$lp\AppData\Roaming", "$lp\AppData\LocalLow" -Directory -Force -ErrorAction SilentlyContinue |
                Select-Object FullName, CreationTime, LastWriteTime
        }
    }
    foreach ($t in 'C:\ProgramData\AnyDesk\ad_svc.trace', 'C:\ProgramData\AnyDesk\connection_trace.txt',
                   'C:\Program Files\TeamViewer\Connections_incoming.txt', 'C:\Program Files (x86)\TeamViewer\Connections_incoming.txt') {
        Copy-Locked $t (P 'artefacts\acces_distant')
    }
    Get-ChildItem 'C:\Program Files\TeamViewer', 'C:\Program Files (x86)\TeamViewer' -Filter '*.log' -ErrorAction SilentlyContinue |
        ForEach-Object { Copy-Locked $_.FullName (P 'artefacts\acces_distant') }
}

Step "Outils d'acces distant : journaux propres (NetBird, Splashtop, TSplus, Datto RMM, RustDesk...) et pairs NetBird" {
    # Journaux texte modifies sur la periode, 50 Mo max par fichier, 400 Mo max au total
    $script:ToolBytes = [int64]0
    function Copy-ToolLogs([string]$src, [string]$name, [string[]]$inc = @('*.log', '*.txt', '*.log.*', '*.trace', '*.csv', '*.sqlite3', '*.db')) {
        if (-not (Test-Path -LiteralPath $src)) { return }
        Get-ChildItem -LiteralPath $src -Recurse -File -Force -Include $inc -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $Since -and $_.Length -lt 50MB -and $_.Name -notmatch '(?i)HowToRecover|readme' -and $_.FullName -notmatch '\\(Packages|Cache|Code Cache)\\' } | ForEach-Object {
                if (($script:ToolBytes + $_.Length) -gt 400MB) { return }
                $script:ToolBytes += $_.Length
                Copy-Locked $_.FullName (Join-Path (P "outils_distants\$name") (Split-Path $_.FullName.Substring($src.TrimEnd('\').Length) -Parent))
            }
    }
    $pf = $env:ProgramFiles; $pf86 = ${env:ProgramFiles(x86)}; $pd = $env:ProgramData
    Copy-ToolLogs "$pd\Netbird" 'netbird'
    Copy-ToolLogs "$pf\Netbird" 'netbird'
    Copy-ToolLogs "$pf86\Splashtop\Splashtop Remote\Server\log" 'splashtop'
    Copy-ToolLogs "$pf86\Splashtop\Splashtop Remote\Server\db" 'splashtop_db'
    Copy-ToolLogs "$pd\Splashtop" 'splashtop_programdata'
    foreach ($r in "$pf86\TSplus", "$pf\TSplus", "$pf86\TSplus-Security", "$pf\TSplus-Security") { Copy-ToolLogs $r ("tsplus_" + (Split-Path $r -Leaf)) }
    Copy-ToolLogs "$pd\CentraStage" 'datto_rmm'
    Copy-ToolLogs "$pf86\CentraStage" 'datto_rmm_programfiles'
    Copy-ToolLogs "$pd\RustDesk" 'rustdesk'
    Get-ChildItem $pf86, $pf -Directory -Filter 'ScreenConnect Client*' -ErrorAction SilentlyContinue | ForEach-Object { Copy-ToolLogs $_.FullName "screenconnect_$($_.Name)" }

    # NetBird : configuration (cles privees masquees) et liste des pairs du tunnel
    foreach ($cfg in @(Get-ChildItem "$pd\Netbird" -Filter '*.json' -ErrorAction SilentlyContinue)) {
        try {
            (Get-Content -LiteralPath $cfg.FullName -Raw -ErrorAction Stop) -replace '"(PrivateKey|PreSharedKey|SSHKey|PrivateSSHKey|SetupKey)"\s*:\s*"[^"]*"', '"$1": "<masque>"' |
                Out-File (P "outils_distants\netbird\$($cfg.Name)") -Encoding utf8
        } catch { Log "    [!] NetBird $($cfg.Name) : $($_.Exception.Message)" }
    }
    $nb = @((Get-Command netbird.exe -ErrorAction SilentlyContinue).Source, "$pf\Netbird\netbird.exe") | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($nb) {
        New-Item -ItemType Directory -Force -Path (P 'outils_distants') | Out-Null
        $job = Start-Job -ScriptBlock { param($exe) & $exe status --detail 2>&1; '====== JSON'; & $exe status --json 2>&1 } -ArgumentList $nb
        if (Wait-Job $job -Timeout 30) { Receive-Job $job | Out-File (P 'outils_distants\netbird_status.txt') -Encoding utf8 }
        else { 'netbird status : pas de reponse en 30 s (service arrete ?)' | Out-File (P 'outils_distants\netbird_status.txt') -Encoding utf8 }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Log '    NetBird : etat et pairs dans outils_distants\netbird_status.txt'
    }
    # Splashtop : parametres du serveur (identifiants de compte, derniers clients connectes)
    foreach ($k in 'HKLM\SOFTWARE\WOW6432Node\Splashtop Inc.', 'HKLM\SOFTWARE\Splashtop Inc.') {
        & reg.exe query $k /s 2>$null | Out-File -Append (P 'outils_distants\splashtop_registre.txt') -Encoding utf8
    }
    Log ("    {0:N1} Mo de journaux d'outils d'acces distant copies" -f ($script:ToolBytes / 1MB))
}

# =================================================================== 10. IDENTIFIANTS EXPOSES (sans lire les mots de passe)
Step 'Identifiants exposes : sites enregistres dans les navigateurs, Wi-Fi, gestionnaire Windows' {
    $rows = New-Object System.Collections.Generic.List[object]
    $tmpRoot = Join-Path $env:TEMP "cx_$Stamp"
    function Conv-Webkit($v) { $n = [int64]0; if ([int64]::TryParse("$v", [ref]$n) -and $n -gt 0) { [DateTime]::FromFileTimeUtc($n * 10).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') } }
    function Conv-UnixMs($v) { $n = [int64]0; if ([int64]::TryParse("$v", [ref]$n) -and $n -gt 0) { [DateTimeOffset]::FromUnixTimeMilliseconds($n).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss') } }

    foreach ($pr in $script:UserProfiles) {
        $lp = $pr.LocalPath; $u = Split-Path $lp -Leaf
        foreach ($b in $Chromium.Keys) {
            $base = Join-Path "$lp\AppData" $Chromium[$b]
            foreach ($dir in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue)) {
                foreach ($fn in 'Login Data', 'Login Data For Account') {
                    $src = Join-Path $dir.FullName $fn
                    if (-not (Test-Path -LiteralPath $src)) { continue }
                    if (-not (Test-Path -LiteralPath $Velo)) { $rows.Add([pscustomobject]@{ Utilisateur = $u; Navigateur = $b; Profil = $dir.Name; Fichier = $fn; Site = '(non analyse : Velociraptor absent)' }); continue }
                    # Copie temporaire hors cle (la base contient les mots de passe chiffres), supprimee juste apres
                    $tmp = Join-Path $tmpRoot ([guid]::NewGuid().ToString('N'))
                    Copy-Locked $src $tmp
                    $db = Join-Path $tmp $fn
                    if (Test-Path -LiteralPath $db) {
                        $res = Invoke-Vql "SELECT * FROM sqlite(file='''$db''', query='SELECT origin_url, username_value, date_created, date_last_used, times_used, blacklisted_by_user FROM logins')"
                        if (-not $res) { $res = Invoke-Vql "SELECT * FROM sqlite(file='''$db''', query='SELECT origin_url, username_value, date_created, times_used, blacklisted_by_user FROM logins')" }
                        foreach ($x in @($res)) {
                            if (-not $x) { continue }
                            $rows.Add([pscustomobject]@{ Utilisateur = $u; Navigateur = $b; Profil = $dir.Name; Fichier = $fn; Site = $x.origin_url; Identifiant = $x.username_value
                                Cree = Conv-Webkit $x.date_created; DerniereUtilisation = Conv-Webkit $x.date_last_used; NbUtilisations = $x.times_used
                                JamaisEnregistre = ("$($x.blacklisted_by_user)" -eq '1') })
                        }
                    }
                    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        foreach ($ff in @(Get-ChildItem "$lp\AppData\Roaming\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue)) {
            $lj = Join-Path $ff.FullName 'logins.json'
            if (-not (Test-Path -LiteralPath $lj)) { continue }
            try {
                foreach ($x in @((Get-Content -LiteralPath $lj -Raw -Encoding UTF8 | ConvertFrom-Json).logins)) {
                    $rows.Add([pscustomobject]@{ Utilisateur = $u; Navigateur = 'firefox'; Profil = $ff.Name; Fichier = 'logins.json'; Site = $x.hostname; Identifiant = '(chiffre)'
                        Cree = Conv-UnixMs $x.timeCreated; DerniereUtilisation = Conv-UnixMs $x.timeLastUsed; NbUtilisations = $x.timesUsed; JamaisEnregistre = $false })
                }
            } catch { Log "    [!] Firefox $($ff.Name) : $($_.Exception.Message)" }
        }
    }
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    $rows | Export-Csv (P 'exposition\identifiants_navigateurs.csv') -NoTypeInformation -Encoding UTF8
    $saved = @($rows | Where-Object { -not $_.JamaisEnregistre -and $_.Site -notmatch '^\(non analyse' })
    $saved | ForEach-Object {
            $h = "$($_.Site)"; try { $h = ([uri]$_.Site).Host } catch {}
            $_ | Add-Member -NotePropertyName Domaine -NotePropertyValue $h -PassThru
        } | Group-Object Utilisateur, Domaine | ForEach-Object {
            [pscustomobject]@{ Utilisateur = $_.Group[0].Utilisateur; Site = $_.Group[0].Domaine; NbIdentifiants = $_.Count
                Identifiants = (($_.Group | Select-Object -ExpandProperty Identifiant -Unique) -join ' ; '); Navigateurs = (($_.Group | Select-Object -ExpandProperty Navigateur -Unique) -join ', ') }
        } | Sort-Object Utilisateur, Site | Export-Csv (P 'exposition\comptes_a_changer.csv') -NoTypeInformation -Encoding UTF8
    Log "    $($saved.Count) mots de passe enregistres dans les navigateurs (sites listes, mots de passe non lus)"

    # Wi-Fi : profils et type de securite (la cle n'est pas affichee)
    Save-Text 'exposition\wifi_profils.txt' {
        $names = @(netsh wlan show profiles 2>$null | Where-Object { $_ -match '^\s{4}\S.*\s:\s(.+)$' } | ForEach-Object { $matches[1].Trim() })
        "### $($names.Count) profils Wi-Fi enregistres (leurs cles sont lisibles par un administrateur local)"
        foreach ($n in $names) { "=============== $n"; netsh wlan show profile name="$n" }
    }
    # Gestionnaire d'identifiants Windows : noms et dates des fichiers uniquement
    Save-Csv 'exposition\gestionnaire_identifiants_fichiers.csv' {
        foreach ($pr in $script:UserProfiles) {
            foreach ($sub in 'AppData\Local\Microsoft\Credentials', 'AppData\Roaming\Microsoft\Credentials', 'AppData\Local\Microsoft\Vault', 'AppData\Roaming\Microsoft\Vault') {
                Get-ChildItem -LiteralPath (Join-Path $pr.LocalPath $sub) -Recurse -Force -File -ErrorAction SilentlyContinue |
                    Select-Object @{n='Utilisateur';e={ Split-Path $pr.LocalPath -Leaf }}, FullName, Length, CreationTime, LastWriteTime
            }
        }
    }
    Save-Text 'exposition\cmdkey_compte_courant.txt' { cmdkey /list }
}

# =================================================================== 11. RECHERCHE DE FICHIERS SUSPECTS
$script:ExecsFound = @(); $script:ToolsFound = @()
if (-not $SkipFileSearch) {
    Step "Recherche d'archives, executables et outils suspects (peut prendre plusieurs minutes)" {
        $roots = @('C:\Users', 'C:\ProgramData', 'C:\Windows\Temp', 'C:\PerfLogs', 'C:\Temp', 'C:\tmp', 'C:\Intel') | Where-Object { Test-Path $_ }
        $archExt = '.zip','.7z','.rar','.tar','.gz','.tgz','.cab','.iso','.vhd','.vhdx','.bak','.pst','.ost'
        $execExt = '.exe','.dll','.ps1','.bat','.cmd','.vbs','.js','.jse','.hta','.scr','.msi','.lnk','.py','.sys'
        $toolRx  = '^(rclone|mega(cmd|sync|client)?|winscp|filezilla|pscp|psftp|plink|putty|anydesk|teamviewer|rustdesk|ngrok|chisel|frpc?|cloudflared|mimikatz|procdump|psexec(64)?|paexec|7za?|7zg|rar|winrar|restic|syncthing|gdrive|dropbox|ncat|netcat|nc(64)?|lazagne|sharphound|adfind|advanced_ip_scanner|advanced_port_scanner.*|netscan|nmap|screenconnect.*|splashtop.*|atera.*|supremo|tightvnc.*|ultravnc|winvnc|tor|wget|curl|azcopy|s3browser.*|cyberduck|goodsync.*|freefilesync|passwordfox.*|chromepass.*|netpass.*|wirelesskeyview.*|bulletspassview.*|sniffpass.*|mailpassview.*|webbrowserpassview.*|stub)$'
        $skipHashMask = 0x441000   # fichiers OneDrive/cloud non presents localement : ne pas forcer leur telechargement

        $archives = New-Object System.Collections.Generic.List[object]
        $execs    = New-Object System.Collections.Generic.List[object]
        $tools    = New-Object System.Collections.Generic.List[object]
        $big      = New-Object System.Collections.Generic.List[object]

        foreach ($r in $roots) {
            Get-ChildItem -LiteralPath $r -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $f = $_
                $ext = $f.Extension.ToLowerInvariant()
                $recent = ($f.LastWriteTime -ge $Since) -or ($f.CreationTime -ge $Since)
                if ($recent -and $archExt -contains $ext -and $archives.Count -lt 20000) {
                    $archives.Add([pscustomobject]@{ Chemin = $f.FullName; TailleMo = [math]::Round($f.Length / 1MB, 2); Creation = $f.CreationTime; Modification = $f.LastWriteTime; Acces = $f.LastAccessTime })
                }
                if ($recent -and $f.Length -ge 100MB -and $big.Count -lt 20000) {
                    $big.Add([pscustomobject]@{ Chemin = $f.FullName; TailleMo = [math]::Round($f.Length / 1MB, 2); Creation = $f.CreationTime; Modification = $f.LastWriteTime })
                }
                $isTool = ($f.BaseName -match $toolRx) -and ($execExt -contains $ext)
                $isExec = $recent -and ($execExt -contains $ext) -and ($f.FullName -notmatch '\\(WindowsApps|Packages\\Microsoft\.|Microsoft\\Windows Defender\\Platform|Package Cache)\\')
                if ($isTool -or $isExec) {
                    $hash = $null
                    if ((([int]$f.Attributes) -band $skipHashMask) -eq 0 -and $f.Length -lt 100MB) {
                        $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                    }
                    $row = [pscustomobject]@{ Chemin = $f.FullName; TailleKo = [math]::Round($f.Length / 1KB, 1); Creation = $f.CreationTime; Modification = $f.LastWriteTime; SHA256 = $hash }
                    if ($isTool -and $tools.Count -lt 20000) { $tools.Add($row) }
                    if ($isExec -and $execs.Count -lt 20000) { $execs.Add($row) }
                }
            }
        }
        $archives | Sort-Object Creation -Descending | Export-Csv (P 'fichiers\archives_recentes.csv') -NoTypeInformation -Encoding UTF8
        $big      | Sort-Object Creation -Descending | Export-Csv (P 'fichiers\gros_fichiers_recents.csv') -NoTypeInformation -Encoding UTF8
        $tools    | Sort-Object Creation -Descending | Export-Csv (P 'fichiers\outils_suspects.csv') -NoTypeInformation -Encoding UTF8
        $execs    | Sort-Object Creation -Descending | Export-Csv (P 'fichiers\executables_scripts_recents.csv') -NoTypeInformation -Encoding UTF8
        $script:ExecsFound = $execs.ToArray(); $script:ToolsFound = $tools.ToArray()
        Log "    Archives: $($archives.Count)  Gros fichiers: $($big.Count)  Outils suspects: $($tools.Count)  Executables/scripts recents: $($execs.Count)"

        Save-Csv 'fichiers\racines_disques.csv' {
            Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -and $script:UsbLetters -notcontains $_.Root.Substring(0, 2).ToUpper() } | ForEach-Object {
                Get-ChildItem -LiteralPath $_.Root -Force -ErrorAction SilentlyContinue | Select-Object FullName, Length, CreationTime, LastWriteTime, Attributes
            }
        }
    }
}

# =================================================================== 12. TRACES DU RANCONGICIEL
Step 'Cliches instantanes (VSS), options de recuperation, commandes destructrices' {
    Save-Text 'rancon\cliches_instantanes.txt' {
        '### vssadmin list shadows';        vssadmin list shadows
        '### vssadmin list shadowstorage';  vssadmin list shadowstorage
        '### Win32_ShadowCopy';             Get-CimInstance Win32_ShadowCopy -ErrorAction SilentlyContinue | Format-List ID, InstallDate, VolumeName, DeviceObject, Persistent, ClientAccessible
        '### bcdedit (recoveryenabled No = desactive par un rancongiciel ?)'; bcdedit /enum
        '### reagentc /info';               reagentc /info
        '### wbadmin get versions';         wbadmin get versions
    }
    $rx = '(?i)vssadmin.*(delete|resize)|shadowcopy.*delete|bcdedit.*(recoveryenabled|bootstatuspolicy|safeboot)|wbadmin.*delete|wevtutil.*\s(cl|clear-log)\s|cipher(\.exe)?\s+/w|(Set|Add)-MpPreference|DisableRealtimeMonitoring|netsh.*(firewall|advfirewall).*(off|disable|state)|taskkill.*/f|net\s+stop|sc\s+(stop|config)|reg(\.exe)?\s+add.*(Defender|Terminal Server)|net\s+user\s+\S+\s+\S+|net\s+localgroup.*/add'
    Save-Csv 'rancon\commandes_destructrices_4688.csv' {
        @(foreach ($e in (Get-Ev 'Security' 'EventID=4688' 50000)) {
            $f = Get-EvFields $e
            if ("$($f['CommandLine']) $($f['NewProcessName'])" -match $rx) {
                [pscustomobject]@{ Date = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'); Compte = "$($f['SubjectDomainName'])\$($f['SubjectUserName'])"; Processus = $f['NewProcessName']; Parent = $f['ParentProcessName']; LigneDeCommande = $f['CommandLine'] }
            }
        }) | Sort-Object Date
    }
    Save-Csv 'rancon\evenements_vss_volsnap.csv' {
        foreach ($l in 'System', 'Application') {
            foreach ($e in (Get-Ev $l "Provider[@Name='volsnap' or @Name='VSS' or @Name='Microsoft-Windows-Backup']" 3000)) {
                [pscustomobject]@{ Date = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'); Journal = $l; Source = $e.ProviderName; EventID = $e.Id; Message = ("$($e.Message)" -replace '\s+', ' ') }
            }
        }
    }
}

Step 'Binaires suspects : hash + archive chiffree (mot de passe : infected) + quarantaine Defender' {
    $cand = [ordered]@{}
    # 1) Fichiers detectes par Defender et encore presents
    try {
        foreach ($d in @(Get-MpThreatDetection)) {
            foreach ($r in @($d.Resources)) {
                if ("$r" -match '^(file|containerfile):_(.+?)(->.*)?$') {
                    $p = $matches[2]
                    if ((Test-Path -LiteralPath $p -PathType Leaf) -and -not $cand.Contains($p)) { $cand[$p] = 'Defender' }
                }
            }
        }
    } catch {}
    # 2) Executables / scripts recents dans les dossiers a risque, et outils connus, non signes
    $risk = '(?i)\\(Desktop|Downloads|Documents|Music|Pictures|Videos)\\|\\AppData\\Local\\Temp\\|\\AppData\\Roaming\\[^\\]+$|\\Windows\\Temp\\|\\Users\\Public\\|^C:\\ProgramData\\[^\\]+(\\[^\\]+)?$|^C:\\(Temp|tmp|PerfLogs|Intel)\\'
    foreach ($e in @($script:ToolsFound) + @($script:ExecsFound)) {
        if (-not $e -or $cand.Contains($e.Chemin)) { continue }
        $isTool = @($script:ToolsFound | Where-Object { $_.Chemin -eq $e.Chemin }).Count -gt 0
        if (($isTool -or $e.Chemin -match $risk) -and $e.Chemin -notmatch '\.lnk$') { $cand[$e.Chemin] = $(if ($isTool) { 'Outil connu' } else { 'Dossier a risque' }) }
    }
    $list = New-Object System.Collections.Generic.List[object]
    $total = [int64]0
    foreach ($p in $cand.Keys) {
        $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if (-not $it) { continue }
        $sig = $null; try { $sig = Get-AuthenticodeSignature -LiteralPath $p -ErrorAction Stop } catch {}
        if ($cand[$p] -ne 'Defender' -and $sig -and $sig.Status -eq 'Valid') { continue }
        $h = $null; try { $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash } catch {}
        $take = ($it.Length -le 30MB -and ($total + $it.Length) -le 500MB -and $list.Count -lt 300)
        if ($take) { $total += $it.Length }
        $list.Add([pscustomobject]@{ Chemin = $p; TailleKo = [math]::Round($it.Length / 1KB, 1); Creation = $it.CreationTime; Modification = $it.LastWriteTime
            SHA256 = $h; Signature = $(if ($sig) { $sig.Status }); Signataire = $(if ($sig) { $sig.SignerCertificate.Subject }); Source = $cand[$p]; Archive = $take })
    }
    $list | Export-Csv (P 'rancon\binaires_suspects.csv') -NoTypeInformation -Encoding UTF8
    $toArc = @($list | Where-Object { $_.Archive } | Select-Object -ExpandProperty Chemin)
    Log "    $($list.Count) binaires suspects, $($toArc.Count) a archiver ($([math]::Round($total / 1MB, 1)) Mo)"

    if ($toArc.Count) {
        $z = Join-Path $Tools '7zr.exe'
        $arc = P 'rancon\binaires_suspects.7z'
        $ok = $false
        if (Test-Path -LiteralPath $z) {
            $lst = Join-Path $env:TEMP "lst_$Stamp.txt"
            [IO.File]::WriteAllLines($lst, [string[]]$toArc, (New-Object Text.UTF8Encoding($false)))
            & $z a -t7z -pinfected -mhe=on -mx=5 -spf2 -ssw -scsUTF-8 -y "$arc" "@$lst" 2>&1 | Out-File (P 'rancon\7z.log') -Encoding utf8
            $ok = ($LASTEXITCODE -le 1) -and (Test-Path -LiteralPath $arc)
            Remove-Item -LiteralPath $lst -Force -ErrorAction SilentlyContinue
        }
        if (-not $ok -and $script:CsOk) {
            # Repli : copie neutralisee (XOR 0x5A) pour que l'antivirus ne la supprime pas
            Log '    [i] 7zr indisponible ou en echec : copie neutralisee XOR 0x5A'
            $nd = P 'rancon\binaires_neutralises'
            New-Item -ItemType Directory -Force -Path $nd | Out-Null
            foreach ($b in @($list | Where-Object { $_.Archive -and $_.SHA256 })) {
                try { [XorTool]::XorCopy($b.Chemin, (Join-Path $nd "$($b.SHA256).bin"), 0x5A) } catch { Log "    [!] XOR $($b.Chemin) : $($_.Exception.Message)" }
            }
        }
        @(
            'Echantillons des binaires suspects du poste. NE PAS EXECUTER, ne pas ouvrir sur un poste de production.'
            '- binaires_suspects.7z : archive 7-Zip chiffree, mot de passe : infected (noms de fichiers chiffres aussi).'
            '- binaires_neutralises\<SHA256>.bin (si present) : chaque octet XOR 0x5A. Correspondance chemin/SHA256 dans binaires_suspects.csv.'
            '- defender_quarantaine : quarantaine Defender (fichiers deja chiffres par Defender).'
        ) | Out-File (P 'rancon\LISEZMOI.txt') -Encoding utf8
    }
    Copy-Backup 'C:\ProgramData\Microsoft\Windows Defender\Quarantine' (P 'rancon\defender_quarantaine')
}

if ($Full -and -not $SkipFullListing) {
    Step 'Listing complet des disques + fichiers chiffres, notes de rancon, bases metier (plusieurs minutes)' {
        if (-not $script:CsOk) { Log '    [!] Moteur C# indisponible : listing ignore'; return }
        $ransomRx = New-Object Text.RegularExpressions.Regex('(?i)(\.\[[^\]]{3,80}\]\.[^.]{2,15}$|[a-z0-9._%+-]+@[a-z0-9-]+\.[a-z]{2,}|\.(locked|encrypted|crypted|lockbit|phobos|elbie|eking|faust|devos|makop|mallox|akira|royal|blacksuit|medusa|basta|8base|rhysida|djvu)$|\.id[-_][0-9a-f]{6,})', 'Compiled')
        $baseRx   = New-Object Text.RegularExpressions.Regex('(?i)(\.(fdp|fdb|gdb|mdf|ldf|ndf|accdb|mdb|4dd|4dindx|dbf)(\.|$)|axi_database)', 'Compiled')
        $enc = New-Object Text.UTF8Encoding($true)
        $hdr = 'Chemin,Taille,Creation,Modification,Acces,Attributs'
        $wAll = New-Object IO.StreamWriter((P 'fichiers\listing_complet.csv'), $false, $enc, 65536)
        $wRan = New-Object IO.StreamWriter((P 'rancon\fichiers_chiffres_suspects.csv'), $false, $enc, 65536)
        $wBas = New-Object IO.StreamWriter((P 'rancon\bases_metier.csv'), $false, $enc, 65536)
        $wAll.WriteLine($hdr); $wRan.WriteLine($hdr); $wBas.WriteLine($hdr)
        $w = New-Object FsWalker
        try {
            $vols = Get-CimInstance Win32_Volume -Filter 'DriveType=3' | Where-Object { $_.DriveLetter -and $script:UsbLetters -notcontains $_.DriveLetter.ToUpper() }
            foreach ($v in $vols) { Log "    Listing $($v.DriveLetter)..."; $w.Walk($v.DriveLetter + '\', $Since, $ransomRx, $baseRx, $wAll, $wRan, $wBas) }
        } finally { $wAll.Close(); $wRan.Close(); $wBas.Close() }
        Log "    $($w.Files) fichiers, $($w.Dirs) dossiers ($($w.Errors) inaccessibles) - $($w.RansomHits) noms de fichiers chiffres suspects - $($w.BaseHits) bases metier"

        $fmt = { param($dic) foreach ($k in $dic.Keys) { $s = $dic[$k]
            [pscustomobject]@{ Extension = $k; NbFichiers = $s.Count; TailleMo = [math]::Round($s.Bytes / 1MB, 1); Premier = $s.First.ToString('yyyy-MM-dd HH:mm:ss'); Dernier = $s.Last.ToString('yyyy-MM-dd HH:mm:ss')
                DureeMinutes = [math]::Round(($s.Last - $s.First).TotalMinutes, 1); Exemple = $s.Sample } } }
        & $fmt $w.RansomExt | Sort-Object NbFichiers -Descending | Export-Csv (P 'rancon\fichiers_chiffres_par_extension.csv') -NoTypeInformation -Encoding UTF8
        # Extensions des fichiers modifies sur la periode : une extension inconnue avec beaucoup de fichiers en peu de minutes = chiffrement
        & $fmt $w.Ext | Sort-Object NbFichiers -Descending | Select-Object -First 400 | Export-Csv (P 'rancon\extensions_fichiers_recents.csv') -NoTypeInformation -Encoding UTF8

        # Notes de rancon : petits fichiers texte recents au nom evocateur ou repetes dans de nombreux dossiers
        $noteRx = '(?i)(read.?me|decrypt|restore|recover|how.?to|ransom|instruction|unlock|encrypted|crypted|files?.?back|^info\.|attention|warning|help|rancon|lisez)'
        $notes = foreach ($k in $w.Notes.Keys) {
            $n = $w.Notes[$k]; $m = $k -match $noteRx
            if (($m -and $n.Count -ge 1) -or $n.Count -ge 5) {
                [pscustomobject]@{ Nom = $k; NbDossiers = $n.Count; NomEvocateur = $m; TailleOctets = $n.Size; Derniere = $n.Last.ToString('yyyy-MM-dd HH:mm:ss'); Exemples = ($n.Samples -join ' | '); _p = $n.Samples[0]
                    _score = $(if ($m -and $n.Count -ge 3) { 3 } elseif ($m) { 2 } else { 1 }) }
            }
        }
        $notes = @($notes | Sort-Object @{e='_score'; Descending=$true}, @{e='NbDossiers'; Descending=$true})
        $notes | Select-Object Nom, NbDossiers, NomEvocateur, TailleOctets, Derniere, Exemples | Export-Csv (P 'rancon\notes_rancon_candidates.csv') -NoTypeInformation -Encoding UTF8
        $nd = P 'rancon\notes'
        New-Item -ItemType Directory -Force -Path $nd | Out-Null
        $i = 0
        foreach ($n in ($notes | Select-Object -First 15)) {
            $i++
            Copy-Item -LiteralPath $n._p -Destination (Join-Path $nd ('{0:D2}_{1}' -f $i, $n.Nom)) -Force -ErrorAction SilentlyContinue
        }
        Log "    $($notes.Count) notes de rancon candidates (15 premieres copiees dans rancon\notes)"
    }
}

# =================================================================== 13. FICHE HORS POSTE (box / pare-feu)
Step 'Fiche a completer par le technicien (heure, box, pare-feu)' {
    $gw = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
    $gwMac = if ($gw) { (Get-NetNeighbor -IPAddress $gw.NextHop -ErrorAction SilentlyContinue | Select-Object -First 1).LinkLayerAddress }
    $pubIp = try { Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 5 -UseBasicParsing } catch { 'inconnue (poste isole ?)' }
    # Ecart d'horloge mesure contre l'en-tete Date d'un serveur web (independant de la configuration NTP)
    $skew = try {
        $r = Invoke-WebRequest 'https://www.google.com' -Method Head -UseBasicParsing -TimeoutSec 5
        $srv = [datetime]::Parse("$($r.Headers['Date'])", [Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
        '{0:+0;-0;0} s (heure du poste moins heure du serveur web, precision ~1 s)' -f ((Get-Date).ToUniversalTime() - $srv).TotalSeconds
    } catch { 'non mesure (poste isole ?) : noter l''heure d''une horloge de reference ci-dessous' }
    $now = Get-Date
    $offs = @(for ($d = $Since.Date; $d -le $now.Date; $d = $d.AddDays(1)) { [TimeZoneInfo]::Local.GetUtcOffset($d.AddHours(12)) }) | Select-Object -Unique
    $offTxt = ($offs | ForEach-Object { 'UTC' + $(if ($_ -ge [TimeSpan]::Zero) { '+' } else { '-' }) + $_.ToString('hh\:mm') }) -join ' puis '
    $txt = @"
FICHE A COMPLETER SUR PLACE - $Computer
=======================================================================
Releve automatique au moment de la collecte
  Heure locale du poste : $($now.ToString('yyyy-MM-dd HH:mm:ss'))  (fuseau $([TimeZoneInfo]::Local.Id), UTC$($now.ToString('zzz')))
  Heure UTC du poste    : $($now.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))
  Passerelle (box)      : $(if ($gw) { "$($gw.NextHop) via $($gw.InterfaceAlias)" })  MAC $gwMac
  IP publique vue       : $pubIp
  Ecart d'horloge       : $skew
  Decalage UTC          : $offTxt sur la periode analysee (detail dans infos_collecte.txt)
  Synchronisation NTP   : voir plus bas (w32tm)

A completer par le technicien
  [ ] Heure affichee par la box / le pare-feu, notee au meme moment : ____:____:____
      Ecart avec le poste : ______  (indispensable pour recouper les journaux)
  [ ] Fuseau et serveur NTP configures sur la box : ______________________
  [ ] Modele de box / pare-feu et operateur : ______________________
  [ ] Redirections de ports (NAT/PAT) : capture d'ecran. Port 3389 ou autre port RDP ouvert ?  OUI / NON
  [ ] Export des journaux de la box / du pare-feu du $($Since.ToString('dd/MM/yyyy')) a aujourd'hui :
      connexions entrantes et sortantes, volumes montants par IP, alertes. Format fichier, pas de capture.
  [ ] Compteurs de trafic de la box (page statistiques) : capture des volumes montants / descendants.
  [ ] Autres postes du reseau a controler (mode leger) : ______________________

Incident (necessaire a la notification CNIL : le delai de 72 h court a partir de la DECOUVERTE)
  [ ] Date et heure de decouverte : ____/____/______ a ____:____   par : ______________________
      Comment (ecran de rancon, appel du cabinet, alerte antivirus...) : ______________________
  [ ] Logiciel metier et base(s) concernee(s) : ______________________
  [ ] Nombre estime de PATIENTS dans la base (pas de fichiers) : ________  source : ______________
  [ ] Categories de donnees : identite / NIR / donnees de sante / documents scannes / courriers / autres : ______
  [ ] Comptes de l'identifiant Windows a lister : ouvrir la session de chaque compte et lancer
      LISTER_IDENTIFIANTS.bat (cibles du gestionnaire d'identifiants : NAS, serveur, sites web).

Preuves
  [ ] Seconde copie des preuves sur un autre support, hachee et verifiee (Copier-Preuves.ps1),
      conservee separement de la cle. Support : ______________  lieu : ______________

Demande a l'operateur (FAI) si la box ne garde pas d'historique - a envoyer vite, la retention est courte
  "Pour la ligne ______________ (IP publique $pubIp), merci de nous communiquer, du ____/____ au ____/____ :
   - le volume de donnees MONTANT (upload) par jour, et si possible par heure les jours ____ et ____ ;
   - les connexions sortantes vers des adresses IP inhabituelles ou etrangeres (adresse, port, volume) ;
   - les connexions entrantes sur le port ______ (Bureau a distance) avec leur adresse source.
   Contexte : incident de securite (rancongiciel), plainte deposee / en cours."

Ces journaux sont la seule source capable de trancher sur une exfiltration vers Internet :
le poste ne distingue pas le trafic local du trafic Internet.

=======================================================================
w32tm /query /status /verbose
$((& w32tm.exe /query /status /verbose 2>&1) -join "`r`n")

w32tm /stripchart /computer:time.windows.com /samples:3 /dataonly
$((& w32tm.exe /stripchart /computer:time.windows.com /samples:3 /dataonly 2>&1) -join "`r`n")
"@
    $txt | Out-File (P 'A_COMPLETER_TECHNICIEN.txt') -Encoding utf8
}

# =================================================================== 14. SYNTHESE AUTOMATIQUE
Step 'Synthese automatique (SYNTHESE.txt)' {
    function Read-Out([string]$rel) { $p = P $rel; if (Test-Path -LiteralPath $p) { @(Import-Csv -LiteralPath $p -Encoding UTF8) } else { @() } }
    $S = New-Object System.Collections.Generic.List[string]
    $alerts = 0; $everyone = $false
    function A([string]$m) { $S.Add("  [!] $m"); Set-Variable -Name alerts -Value ($alerts + 1) -Scope 1 }
    function I([string]$m) { $S.Add("      $m") }

    $S.Add("SYNTHESE AUTOMATIQUE - $Computer - $(Get-Date -Format 'yyyy-MM-dd HH:mm') - mode $Mode")
    $S.Add('Pistes a verifier, pas des conclusions. Chaque ligne renvoie au fichier de detail.')
    $S.Add('')

    $S.Add('RANCONGICIEL  (rancon\)')
    # Un chiffrement touche beaucoup de fichiers en peu de temps : fenetre <= 12 h
    foreach ($x in (Read-Out 'rancon\fichiers_chiffres_par_extension.csv' | Where-Object { [int64]$_.NbFichiers -ge 50 })) {
        $dur = 0.0; [void][double]::TryParse(("$($x.DureeMinutes)" -replace ',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$dur)
        $m = "$($x.NbFichiers) fichiers '$($x.Extension)' ($($x.TailleMo) Mo) du $($x.Premier) au $($x.Dernier)"
        if ($dur -le 720) { A "CHIFFREMENT : $m" } else { I "Noms suspects mais etales dans le temps (faux positif probable) : $m" }
    }
    foreach ($n in (Read-Out 'rancon\notes_rancon_candidates.csv' | Where-Object { [int]$_.NbDossiers -ge 10 } | Select-Object -First 5)) {
        if ($n.NomEvocateur -eq 'True') { A "Note de rancon probable : $($n.Nom) dans $($n.NbDossiers) dossiers (copie dans rancon\notes)" }
        else { I "Fichier texte repete : $($n.Nom) dans $($n.NbDossiers) dossiers" }
    }
    $vss = @(Get-CimInstance Win32_ShadowCopy -ErrorAction SilentlyContinue).Count
    if ($vss -eq 0) { A 'Aucun cliche instantane VSS sur le poste' } else { I "$vss cliche(s) instantane(s) VSS disponible(s)" }
    if ((Get-Content -LiteralPath (P 'rancon\cliches_instantanes.txt') -Raw -ErrorAction SilentlyContinue) -match 'recoveryenabled\s+No') { A 'Recuperation Windows desactivee (bcdedit recoveryenabled No)' }
    $cmd = Read-Out 'rancon\commandes_destructrices_4688.csv'
    if ($cmd.Count) { A "$($cmd.Count) commande(s) destructrice(s) dans l'audit 4688 (commandes_destructrices_4688.csv)" }
    $bin = Read-Out 'rancon\binaires_suspects.csv'
    if ($bin.Count) { I "$($bin.Count) binaire(s) suspect(s) hashe(s), echantillons dans rancon\ (mot de passe infected)" }
    $S.Add('')

    $S.Add('ACCES A DISTANCE  (connexions\, comptes\)')
    $ts  = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue
    $lsa = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -ErrorAction SilentlyContinue
    if ($ts.fDenyTSConnections -eq 0) { I 'Bureau a distance active' }
    if ($lsa.LimitBlankPasswordUse -eq 0) { A 'LimitBlankPasswordUse = 0 : connexion a distance possible avec un mot de passe VIDE' }
    foreach ($ip in (Read-Out 'connexions\synthese_ip_connexions_reussies.csv' | Where-Object { $_.TypeIP -eq 'PUBLIQUE' })) {
        A "Connexion reussie depuis IP publique $($ip.IP) : $($ip.Comptes) (du $($ip.Premier) au $($ip.Dernier))"
    }
    $bf = @(Read-Out 'connexions\echecs_par_ip.csv' | Where-Object { $_.TypeIP -eq 'PUBLIQUE' })
    if ($bf.Count) {
        $tot = ($bf | Measure-Object -Property NbEchecs -Sum).Sum
        A "$tot echecs de connexion depuis $($bf.Count) IP publiques (force brute ?) - top : $((($bf | Select-Object -First 3) | ForEach-Object { "$($_.IP) ($($_.NbEchecs))" }) -join ', ')"
    }
    foreach ($u in (Read-Out 'comptes\inventaire_comptes.csv' | Where-Object { $_.Actif -eq 'True' -and $_.AccesRDP -like 'OUI*' })) {
        if ($u.MdpObligatoire -eq 'False') { A "Compte '$($u.Nom)' : acces RDP et mot de passe NON obligatoire" }
        if ($u.AccesRDP -match 'Tout le monde|Everyone') { $everyone = $true }
    }
    if ($everyone) { A "'Tout le monde' a le droit d'ouvrir une session RDP" }
    $resets = @(Read-Out 'comptes\evenements_comptes.csv' | Where-Object { $_.EventID -in '4720', '4724', '4732' })
    foreach ($e in ($resets | Select-Object -First 10)) { A "$($e.Date) $($e.Action) : $($e.CibleOuGroupe) $($e.Membre) par $($e.Auteur)" }
    $S.Add('')

    $S.Add('ANTIVIRUS  (systeme\)')
    foreach ($t in (Read-Out 'systeme\defender_menaces.csv')) { A ("Defender : $($t.ThreatName)" + $(if ($t.Resources) { " - $($t.Resources)" })) }
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if (-not $mp.RealTimeProtectionEnabled) { A 'Protection en temps reel Defender DESACTIVEE' }
        I "Signatures Defender du $($mp.AntivirusSignatureLastUpdated)"
    } catch { I 'Etat Defender indisponible' }
    $S.Add('')

    $S.Add('EXPOSITION / OUTILS  (exposition\, fichiers\)')
    $pw = @(Read-Out 'exposition\identifiants_navigateurs.csv' | Where-Object { $_.JamaisEnregistre -ne 'True' -and $_.Site -notmatch '^\(non analyse' })
    I "$($pw.Count) mot(s) de passe enregistre(s) dans les navigateurs (liste des sites : exposition\comptes_a_changer.csv)"
    $tools = @(Read-Out 'fichiers\outils_suspects.csv')
    if ($tools.Count) {
        $names = ($tools | ForEach-Object { Split-Path $_.Chemin -Leaf } | Select-Object -Unique | Select-Object -First 15) -join ', '
        A "$($tools.Count) outil(s) sensible(s) trouve(s) : $names"
    }
    $S.Add('')
    $S.Add("$alerts alerte(s). Penser a remplir A_COMPLETER_TECHNICIEN.txt (decouverte, patients, journaux box / pare-feu).")
    $S.Add("Exfiltration : voir $(Split-Path $Out -Leaf)_analyse\SYNTHESE_EXFILTRATION.txt (Analyse-Exfil.ps1, lance apres Velociraptor).")
    $S | Out-File (P 'SYNTHESE.txt') -Encoding utf8
    Log "    $alerts alerte(s) dans SYNTHESE.txt"
}

# =================================================================== 15. MANIFESTE D'INTEGRITE
Step 'Calcul du manifeste SHA256 des elements collectes' {
    $manifest = P 'manifeste_sha256.csv'
    Get-ChildItem $Out -Recurse -File -Force | Where-Object { $_.FullName -ne $manifest -and $_.FullName -ne $LogFile } |
        ForEach-Object { [pscustomobject]@{ Fichier = $_.FullName.Substring($Out.Length + 1); Taille = $_.Length; SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } } |
        Export-Csv $manifest -NoTypeInformation -Encoding UTF8
}

$dur = (Get-Date) - $StartTime
$size = [math]::Round(((Get-ChildItem $Out -Recurse -File -Force | Measure-Object Length -Sum).Sum) / 1MB, 1)
Log "=== Collecte terminee en $([int][math]::Floor($dur.TotalMinutes)) min $($dur.Seconds) s - $size Mo dans $Out ==="
Log "=== Penser a completer $(P 'A_COMPLETER_TECHNICIEN.txt') ==="
Write-Host ''
