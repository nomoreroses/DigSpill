#Requires -Version 5.1
<#
    Generer-Interface.ps1 v1.0 - Cree UN fichier HTML autonome pour lire une collecte sur n'importe quel PC.

      powershell -ExecutionPolicy Bypass -File Generer-Interface.ps1 -Collecte E:\Collecte\POSTE_20261117_150121

    Le fichier <POSTE>_<date>_INTERFACE.html contient l'interface, les graphiques, la carte et les donnees :
    double-clic pour l'ouvrir, sans serveur, sans installation, meme hors ligne.

    Parametres :
      -Collecte <dossier>   dossier de collecte (POSTE_date), son dossier _analyse, ou le dossier Collecte
                            (dans ce cas : la collecte la plus recente). Defaut : Collecte\ a cote du script.
      -Sortie <fichier>     defaut : <dossier Collecte>\<POSTE>_<date>_INTERFACE.html
      -SansInternet         ne telecharge rien (utilise les bases deja presentes dans outils\bases)
      -MajBases             force le telechargement des bases publiques (sinon : si absentes ou > 7 jours)
      -Proteger             demande un mot de passe et chiffre les donnees du fichier (AES-256 + HMAC, PBKDF2)
      -SansOuvrir           ne pas ouvrir le fichier a la fin
      -SansHorodatage       ne pas faire horodater le scelle par un tiers
      -Horodateur <url>     autorite d'horodatage RFC 3161 (defaut : service annonce conforme eIDAS par Sectigo)
      -MaxMoParFichier 12   au-dela, un tableau est tronque (premieres lignes seulement, signale dans l'interface)

    Bases publiques (outils\bases, reutilisees d'une fois sur l'autre) : AUCUNE donnee de la collecte n'est
    envoyee. On telecharge des listes publiques entieres et on les compare ici, en local.
      - IPtoASN (pays + operateur, domaine public)
      - listes : Tor, FireHOL niveau 1, blocklist.de, GreenSnow, CINS, abuse.ch Feodo, Spamhaus DROP
      - ransomware.live : victimes publiees (France + recentes), cherchees en local par l'interface
    Memoire des incidents (outils\bases\memoire_incidents.json) : IOC de chaque collecte traitee, pour signaler
    les indicateurs deja vus chez un autre client.

    Scelle (dossier <POSTE>_<date>_scelles a cote de la collecte) : liste des empreintes SHA256 des manifestes,
    journaux et proces-verbaux de copie ; l'empreinte du scelle est horodatee par un tiers (jeton RFC 3161 .tsr).
    Un nouveau scelle n'est cree que si ces fichiers ont change : le premier horodatage est conserve.

    Le fichier HTML est aussi sensible que la collecte : ne pas l'envoyer en clair (utiliser -Proteger).
#>
[CmdletBinding()]
param(
    [string]$Collecte,
    [string]$Sortie,
    [switch]$SansInternet,
    [switch]$MajBases,
    [switch]$Proteger,
    [switch]$SansOuvrir,
    [switch]$SansHorodatage,
    [string]$Horodateur = 'http://timestamp.sectigo.com/qualified',
    [string]$Bases,
    [int]$MaxMoParFichier = 12
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# version du kit (moteur\VERSION.txt, ecrit par construire-kit.ps1), notee dans les journaux, le scelle et le PV ; 'dev' hors kit
$Version = 'dev'
try { $v = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION.txt') -TotalCount 1 -ErrorAction Stop)[0]; if ("$v".Trim()) { $Version = "$v".Trim() } } catch { }
$Ici = $PSScriptRoot
$Interface = Join-Path $Ici 'interface'
if (-not $Bases) { $Bases = Join-Path $Ici 'outils\bases' }
try { New-Item -ItemType Directory -Force -Path $Bases -ErrorAction Stop | Out-Null } catch { Write-Host "  [!] dossier des bases inaccessible en ecriture ($Bases) : bases deja presentes seulement" }
Add-Type -AssemblyName System.Web
$Utf8 = [System.Text.UTF8Encoding]::new($false)

function Info([string]$m) { Write-Host "  $m" }
function J([string]$s) { '"' + [System.Web.HttpUtility]::JavaScriptStringEncode($s) + '"' }
function JB([bool]$b) { if ($b) { 'true' } else { 'false' } }

# ------------------------------------------------------------------ 1. collecte a traiter
$motif = '^.+_\d{8}_\d{6}(_leger)?$'
# cle rangee : <cle>\DigSpill.exe + <cle>\moteur\ ; les collectes sont dans <cle>\Collecte
$Cle = if ((Split-Path $Ici -Leaf) -eq 'moteur') { Split-Path $Ici -Parent } else { $Ici }
if (-not $Collecte) { $Collecte = Join-Path $Cle 'Collecte' }
$Collecte = (Resolve-Path -LiteralPath $Collecte).ProviderPath.TrimEnd('\')
$nom = Split-Path $Collecte -Leaf
if ($nom -match '_analyse$') { $Collecte = $Collecte -replace '_analyse$', ''; $nom = Split-Path $Collecte -Leaf }
if ($nom -notmatch $motif) {
    $der = Get-ChildItem -LiteralPath $Collecte -Directory | Where-Object { $_.Name -match $motif } | Sort-Object { $_.Name -replace '^.+_(\d{8}_\d{6}).*$', '$1' } -Descending | Select-Object -First 1
    if (-not $der) { throw "Aucun dossier de collecte (POSTE_AAAAMMJJ_HHMMSS) dans $Collecte" }
    $Collecte = $der.FullName; $nom = $der.Name
}
$Parent = Split-Path $Collecte -Parent
$Analyse = "${Collecte}_analyse"
if (-not $Sortie) { $Sortie = Join-Path $Parent "${nom}_INTERFACE.html" }
Write-Host ""
Write-Host "  === Interface autonome v$Version : $nom ===" -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Analyse)) { Info "[!] Pas de dossier _analyse : lancer DigSpill.exe > Analyser une collecte pour une interface complete." }

# ------------------------------------------------------------------ 2. tableaux et textes de la collecte
$ignorer = @('evtx', 'utilisateurs', 'registre', 'prefetch', 'srum', 'amcache', 'defender_logs', 'defender_quarantaine', 'binaires_neutralises',
    'memoire', 'navigateurs', 'parefeu_journal', 'lnk', 'jumplists', 'usn', '_extraits', 'tasks_xml')
$maxOctets = $MaxMoParFichier * 1MB
$fichiers = [ordered]@{}
function Lire-Texte([IO.FileInfo]$f) {
    if ($f.Length -le $maxOctets) { return @([IO.File]::ReadAllText($f.FullName), $false) }
    $sr = [IO.StreamReader]::new($f.FullName, $true)
    try { $buf = New-Object char[] $maxOctets; $n = $sr.ReadBlock($buf, 0, $maxOctets); $t = [string]::new($buf, 0, $n) } finally { $sr.Close() }
    $i = $t.LastIndexOf("`n"); if ($i -gt 0) { $t = $t.Substring(0, $i + 1) }
    return @($t, $true)
}
foreach ($racine in @(@{ D = $Collecte; P = '' }, @{ D = $Analyse; P = 'a.' })) {
    if (-not (Test-Path -LiteralPath $racine.D)) { continue }
    $liste = @(Get-ChildItem -LiteralPath $racine.D -File -Force)
    foreach ($sd in (Get-ChildItem -LiteralPath $racine.D -Directory -Force | Where-Object { $ignorer -notcontains $_.Name.ToLower() })) { $liste += @(Get-ChildItem -LiteralPath $sd.FullName -File -Force) }
    foreach ($f in $liste) {
        $ext = $f.Extension.ToLower()
        $journal = ($ext -eq '.log' -and $f.DirectoryName -eq $racine.D)
        if (($ext -ne '.csv' -and $ext -ne '.txt' -and -not $journal) -or $f.Name -like 'listing_complet*') { continue }
        $cle = if ($ext -eq '.csv') { [IO.Path]::GetFileNameWithoutExtension($f.Name) } else { $f.Name }
        if ($fichiers.Contains($cle)) { if ($racine.P) { $cle = $racine.P + $cle } else { continue } }
        if ($fichiers.Contains($cle)) { continue }
        try { $lu = Lire-Texte $f } catch { Info "[!] $($f.Name) illisible : $($_.Exception.Message)"; continue }
        $fichiers[$cle] = @{ chemin = $f.FullName.Substring($Parent.Length + 1); plein = $f.FullName; taille = $f.Length; tronque = $lu[1]; texte = $lu[0]; modifie = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') }
        if ($lu[1]) { Info "[i] $($f.Name) tronque a $MaxMoParFichier Mo" }
    }
}
Info "$($fichiers.Count) tableaux et textes"

# ------------------------------------------------------------------ 3. IP de la collecte
function Lignes([string]$cle) {
    # lignes d'un tableau CSV (vide si absent ou 'Aucune ligne')
    if (-not $fichiers.Contains($cle) -or -not $fichiers[$cle].texte.StartsWith('"')) { return @() }
    try { return @(Import-Csv -LiteralPath $fichiers[$cle].plein -Encoding UTF8) } catch { Info "[!] $cle illisible : $($_.Exception.Message)"; return @() }
}
$ips = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($c in @(@('synthese_ip_connexions_reussies', 'IP'), @('echecs_par_ip', 'IP'), @('echecs_connexion_4625', 'IP'), @('sessions_reconstituees', 'IP'),
        @('tcp_connexions', 'RemoteAddress'), @('ouvertures_session_4624', 'IP'), @('rdp_authentifications_1149', 'IP'))) {
    foreach ($r in (Lignes $c[0])) { foreach ($ip in ("$($r.($c[1]))" -split '\s*/\s*')) { $ip = $ip.Trim(); if ($ip -and $ip -ne '-') { [void]$ips.Add($ip) } } }
}
$ipsTab = [string[]]@($ips)
Info "$($ipsTab.Count) adresses IP distinctes"

# ------------------------------------------------------------------ 4. bases publiques (telechargees entieres, comparees ici)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$sources = @(
    @{ F = 'ip2asn-combined.tsv.gz'; U = 'https://iptoasn.com/data/ip2asn-combined.tsv.gz'; N = 'IPtoASN (pays, operateur)' },
    @{ F = 'ip_tor.txt'; U = 'https://check.torproject.org/torbulkexitlist'; N = 'Tor' },
    @{ F = 'ip_firehol1.txt'; U = 'https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset'; N = 'FireHOL niveau 1' },
    @{ F = 'ip_blocklistde.txt'; U = 'https://lists.blocklist.de/lists/all.txt'; N = 'blocklist.de' },
    @{ F = 'ip_greensnow.txt'; U = 'https://blocklist.greensnow.co/greensnow.txt'; N = 'GreenSnow' },
    @{ F = 'ip_cins.txt'; U = 'https://cinsscore.com/list/ci-badguys.txt'; N = 'CINS Army' },
    @{ F = 'ip_feodo.txt'; U = 'https://feodotracker.abuse.ch/downloads/ipblocklist.txt'; N = 'abuse.ch Feodo' },
    @{ F = 'ip_spamhaus_drop.txt'; U = 'https://www.spamhaus.org/drop/drop_v4.json'; N = 'Spamhaus DROP' },
    @{ F = 'ransomware_live_FR.json'; U = 'https://api.ransomware.live/v2/countryvictims/FR'; N = 'ransomware.live (victimes France)' },
    @{ F = 'ransomware_live_recent.json'; U = 'https://api.ransomware.live/v2/recentvictims'; N = 'ransomware.live (victimes recentes)' })
if (-not $SansInternet) {
    foreach ($s in $sources) {
        $dest = Join-Path $Bases $s.F
        $age = if (Test-Path -LiteralPath $dest) { ((Get-Date) - (Get-Item -LiteralPath $dest).LastWriteTime).TotalDays } else { 999 }
        if (-not $MajBases -and $age -lt 7) { continue }
        try {
            Invoke-WebRequest -Uri $s.U -OutFile "$dest.tmp" -UseBasicParsing -TimeoutSec 120 -UserAgent 'DigSpill'
            if ((Get-Item -LiteralPath "$dest.tmp").Length -gt 50) { Move-Item -LiteralPath "$dest.tmp" -Destination $dest -Force; Info "[+] $($s.N)" }
            else { Remove-Item -LiteralPath "$dest.tmp" -Force; Info "[!] $($s.N) : reponse vide" }
        } catch { Info "[!] $($s.N) : $($_.Exception.Message)"; Remove-Item -LiteralPath "$dest.tmp" -Force -ErrorAction SilentlyContinue }
    }
}

if (-not ('TriageIp' -as [type])) {
Add-Type -Language CSharp -TypeDefinition @'
using System; using System.IO; using System.IO.Compression; using System.Net; using System.Text; using System.Collections.Generic;
public static class TriageIp {
    static bool V4(string s, out uint v) {
        v = 0; IPAddress a;
        if (!IPAddress.TryParse(s, out a) || a.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork) return false;
        byte[] b = a.GetAddressBytes(); v = ((uint)b[0] << 24) | ((uint)b[1] << 16) | ((uint)b[2] << 8) | b[3]; return true;
    }
    static bool Dans(uint v, uint net, int len) { uint m = len == 0 ? 0u : (0xFFFFFFFFu << (32 - len)); return (v & m) == (net & m); }
    static bool Publique(uint v) {
        return !(Dans(v, 0x00000000u, 8) || Dans(v, 0x0A000000u, 8) || Dans(v, 0x64400000u, 10) || Dans(v, 0x7F000000u, 8) || Dans(v, 0xA9FE0000u, 16)
            || Dans(v, 0xAC100000u, 12) || Dans(v, 0xC0A80000u, 16) || Dans(v, 0xC0000000u, 24) || Dans(v, 0xC6120000u, 15) || v >= 0xE0000000u);
    }
    static int Cmp(byte[] x, byte[] y) { for (int i = 0; i < 16; i++) if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1; return 0; }
    static TextReader Ouvrir(string chemin) {
        Stream f = File.OpenRead(chemin);
        if (chemin.EndsWith(".gz", StringComparison.OrdinalIgnoreCase)) f = new GZipStream(f, CompressionMode.Decompress);
        return new StreamReader(f, Encoding.UTF8);
    }
    // Lignes "debut<sep>fin<sep>..." d'une base de plages contenant les IP demandees ; resultat : "ip<TAB>ligne"
    public static string[] Plages(string chemin, string[] ips, char sep) {
        var v4 = new List<KeyValuePair<uint, string>>(); var v6 = new List<KeyValuePair<byte[], string>>();
        foreach (string ip in ips) {
            uint u; IPAddress a;
            if (V4(ip, out u)) v4.Add(new KeyValuePair<uint, string>(u, ip));
            else if (IPAddress.TryParse(ip, out a) && a.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6) v6.Add(new KeyValuePair<byte[], string>(a.GetAddressBytes(), ip));
        }
        v4.Sort((p, q) => p.Key.CompareTo(q.Key));
        uint[] cles = new uint[v4.Count]; for (int i = 0; i < v4.Count; i++) cles[i] = v4[i].Key;
        var res = new List<string>();
        using (TextReader tr = Ouvrir(chemin)) {
            string l;
            while ((l = tr.ReadLine()) != null) {
                int i1 = l.IndexOf(sep); if (i1 <= 0) continue;
                int i2 = l.IndexOf(sep, i1 + 1); if (i2 < 0) continue;
                string s1 = l.Substring(0, i1), s2 = l.Substring(i1 + 1, i2 - i1 - 1);
                if (s1.IndexOf(':') < 0) {
                    uint a1, a2; if (cles.Length == 0 || !V4(s1, out a1) || !V4(s2, out a2)) continue;
                    int k = Array.BinarySearch(cles, a1); if (k < 0) k = ~k;
                    while (k > 0 && cles[k - 1] == a1) k--;
                    while (k < cles.Length && cles[k] <= a2) { res.Add(v4[k].Value + "\t" + l); k++; }
                } else if (v6.Count > 0) {
                    IPAddress b1, b2; if (!IPAddress.TryParse(s1, out b1) || !IPAddress.TryParse(s2, out b2)) continue;
                    byte[] x1 = b1.GetAddressBytes(), x2 = b2.GetAddressBytes();
                    foreach (var p in v6) if (Cmp(p.Key, x1) >= 0 && Cmp(p.Key, x2) <= 0) res.Add(p.Value + "\t" + l);
                }
            }
        }
        return res.ToArray();
    }
    // IP (v4) presentes dans une liste publique (une IP ou un reseau CIDR par ligne, commentaires # ;)
    public static string[] Listes(string chemin, string[] ips) {
        var cibles = new List<KeyValuePair<uint, string>>();
        // Seules les IP publiques sont comparees : FireHOL niveau 1 contient les plages reservees (bogons),
        // sans ce filtre les IP locales, VPN/CGNAT et 127.0.0.1 ressortiraient "sur liste noire"
        foreach (string ip in ips) { uint u; if (V4(ip, out u) && Publique(u)) cibles.Add(new KeyValuePair<uint, string>(u, ip)); }
        var trouve = new HashSet<string>();
        if (cibles.Count == 0) return new string[0];
        var rx = new System.Text.RegularExpressions.Regex(@"(?<![\d.])(\d{1,3}(?:\.\d{1,3}){3})(?:/(\d{1,2}))?(?![\d.])");
        using (TextReader tr = Ouvrir(chemin)) {
            string l;
            while ((l = tr.ReadLine()) != null) {
                l = l.Trim(); if (l.Length == 0 || l[0] == '#' || l[0] == ';') continue;
                var m = rx.Match(l); if (!m.Success) continue;
                uint net; if (!V4(m.Groups[1].Value, out net)) continue;
                int len = m.Groups[2].Success ? int.Parse(m.Groups[2].Value) : 32; if (len > 32) continue;
                uint masque = len == 0 ? 0u : (0xFFFFFFFFu << (32 - len));
                foreach (var c in cibles) if ((c.Key & masque) == (net & masque)) trouve.Add(c.Value);
            }
        }
        var r = new string[trouve.Count]; trouve.CopyTo(r); return r;
    }
}
'@
}

function Date-Fichier($p) { (Get-Item -LiteralPath $p).LastWriteTime.ToString('yyyy-MM-dd') }
$geoAsn = @(); $basesJson = New-Object System.Collections.Generic.List[string]
$fAsn = Join-Path $Bases 'ip2asn-combined.tsv.gz'
if ((Test-Path -LiteralPath $fAsn) -and $ipsTab.Count) { try { $geoAsn = [TriageIp]::Plages($fAsn, $ipsTab, "`t"[0]); Info "[+] pays / operateur : $($geoAsn.Count) correspondance(s)" } catch { Info "[!] base IPtoASN illisible : $($_.Exception.Message)" } }
$listesJson = New-Object System.Collections.Generic.List[string]
$listesMeta = New-Object System.Collections.Generic.List[string]
foreach ($l in @(@('tor', 'Noeuds de sortie Tor'), @('firehol1', 'FireHOL niveau 1'), @('blocklistde', 'blocklist.de'), @('greensnow', 'GreenSnow'), @('cins', 'CINS Army'), @('feodo', 'abuse.ch Feodo'), @('spamhaus_drop', 'Spamhaus DROP'))) {
    $f = Join-Path $Bases "ip_$($l[0]).txt"
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $listesMeta.Add('{"id":' + (J $l[0]) + ',"nom":' + (J $l[1]) + ',"date":' + (J (Date-Fichier $f)) + '}')
    try { $t = [TriageIp]::Listes($f, $ipsTab) } catch { Info "[!] liste $($l[0]) illisible"; continue }
    if ($t.Count) { $listesJson.Add((J $l[0]) + ':[' + (($t | ForEach-Object { J $_ }) -join ',') + ']'); Info "[+] liste $($l[1]) : $($t.Count) IP" }
}
function Brut($f) { $p = Join-Path $Bases $f; if (Test-Path -LiteralPath $p) { [IO.File]::ReadAllText($p) } else { '' } }

# ------------------------------------------------------------------ 5. reglages et memoire des incidents
$fReg = Join-Path $Parent "${nom}_reglages.json"
$reglagesBrut = if (Test-Path -LiteralPath $fReg) { [IO.File]::ReadAllText($fReg) } else { '' }
$fMem = Join-Path $Bases 'memoire_incidents.json'
$memoireBrut = if (Test-Path -LiteralPath $fMem) { [IO.File]::ReadAllText($fMem) } else { '' }
try {
    $mem = if ($memoireBrut.Trim()) { $memoireBrut | ConvertFrom-Json } else { New-Object PSObject }
    $client = ''; if ($reglagesBrut) { try { $client = ($reglagesBrut | ConvertFrom-Json).client } catch { } }
    $ipMem = New-Object 'System.Collections.Generic.HashSet[string]'; $s256 = New-Object 'System.Collections.Generic.HashSet[string]'
    $s1 = New-Object 'System.Collections.Generic.HashSet[string]'; $noms = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($r in (Lignes 'synthese_ip_connexions_reussies')) { if ($r.TypeIP -eq 'PUBLIQUE') { [void]$ipMem.Add($r.IP) } }
    foreach ($c in @('ioc_hachages', 'binaires_suspects', 'outils_suspects')) {
        foreach ($r in (Lignes $c)) {
            if ($r.SHA256 -match '^[0-9A-Fa-f]{64}$') { [void]$s256.Add($r.SHA256.ToUpper()) }
            if ($r.SHA1 -match '^[0-9A-Fa-f]{40}$') { [void]$s1.Add($r.SHA1.ToUpper()) }
            $n = if ($r.Nom) { $r.Nom } else { Split-Path "$($r.Chemin)" -Leaf }
            if ($n -match '\.(exe|dll|ps1|bat|scr)$') { [void]$noms.Add($n.ToLower()) }
        }
    }
    $entree = [pscustomobject]@{ poste = ($nom -replace '_\d{8}_\d{6}.*$', ''); date = (Get-Date).ToString('yyyy-MM-dd HH:mm'); client = "$client"
        ip = [string[]]@($ipMem); sha256 = [string[]]@($s256); sha1 = [string[]]@($s1); fichiers = [string[]]@($noms) }
    $mem | Add-Member -NotePropertyName $nom -NotePropertyValue $entree -Force
    [IO.File]::WriteAllText($fMem, ($mem | ConvertTo-Json -Depth 5), $Utf8)
} catch { Info "[!] memoire des incidents non mise a jour : $($_.Exception.Message)" }

# ------------------------------------------------------------------ 5 bis. scelle : empreinte globale + horodatage par un tiers (RFC 3161)
$DossierScelles = "${Collecte}_scelles"
function Hex([byte[]]$b) { [BitConverter]::ToString($b).Replace('-', '') }
function Der([int]$tag, [byte[]]$contenu) {
    $n = $contenu.Length
    if ($n -lt 128) { $l = @($n) } elseif ($n -lt 256) { $l = @(0x81, $n) } else { $l = @(0x82, ($n -shr 8), ($n -band 255)) }
    return [byte[]](@($tag) + $l + $contenu)
}
function DerEntete([byte[]]$b, [int]$i) {
    # @(tag, longueur, position du contenu)
    $l = [int]$b[$i + 1]; $d = $i + 2
    if ($l -band 0x80) { $k = $l -band 0x7F; $l = 0; for ($j = 0; $j -lt $k; $j++) { $l = $l * 256 + $b[$d + $j] }; $d += $k }
    return @([int]$b[$i], $l, $d)
}
function Horodater([byte[]]$empreinte, [string]$url) {
    $nonce = New-Object byte[] 8
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($nonce)
    $nonce[0] = [byte](($nonce[0] -band 0x7F) -bor 0x01)
    $algo = Der 0x30 ([byte[]](@(0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00)))
    $imprint = Der 0x30 ([byte[]]($algo + (Der 0x04 $empreinte)))
    $req = Der 0x30 ([byte[]](@(0x02, 0x01, 0x01) + $imprint + (Der 0x02 $nonce) + @(0x01, 0x01, 0xFF)))
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('Content-Type', 'application/timestamp-query')
    $wc.Headers.Add('User-Agent', 'DigSpill')
    [byte[]]$rep = $wc.UploadData($url, 'POST', $req)
    # TimeStampResp ::= SEQUENCE { status PKIStatusInfo ::= SEQUENCE { status INTEGER ... }, timeStampToken }
    $e1 = DerEntete $rep 0; $e2 = DerEntete $rep $e1[2]; $e3 = DerEntete $rep $e2[2]
    $statut = if ($e3[0] -eq 2) { [int]$rep[$e3[2]] } else { -1 }
    if ($statut -ne 0 -and $statut -ne 1) { throw "reponse refusee par l'horodateur (statut $statut)" }
    if (-not (Hex $rep).Contains((Hex $empreinte))) { throw "le jeton ne contient pas l'empreinte demandee" }
    if (-not (Hex $rep).Contains((Hex $nonce))) { throw "le jeton ne reprend pas le nonce de la requete" }
    $date = ''
    for ($i = 0; $i -lt $rep.Length - 20; $i++) {
        if ($rep[$i] -eq 0x18 -and $rep[$i + 1] -ge 15 -and $rep[$i + 1] -le 23) {
            $t = [Text.Encoding]::ASCII.GetString($rep, $i + 2, $rep[$i + 1])
            if ($t -match '^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\.\d+)?Z$') { $date = "$($matches[1])-$($matches[2])-$($matches[3]) $($matches[4]):$($matches[5]):$($matches[6]) UTC"; break }
        }
    }
    return @{ requete = $req; reponse = $rep; date = $date }
}
try {
    New-Item -ItemType Directory -Force -Path $DossierScelles | Out-Null
    $elements = New-Object System.Collections.Generic.List[string]
    $candidats = @(
        (Join-Path $Collecte 'manifeste_sha256.csv'), (Join-Path $Collecte 'collecte.log'),
        (Join-Path $Analyse 'manifeste_analyse_sha256.csv'), (Join-Path $Analyse 'analyse.log'))
    $candidats += @(Get-ChildItem -LiteralPath $Collecte -File -Filter 'PV_COPIE_*.txt' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($p in $candidats) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $fi = Get-Item -LiteralPath $p
        $elements.Add(('{0}  {1}  {2}' -f (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash, $fi.Length, $fi.FullName.Substring($Parent.Length + 1)))
    }
    $lignes = @($elements | Sort-Object { ($_ -split '  ', 3)[2] })
    # meme contenu que le dernier scelle : on le garde (le premier horodatage fait foi)
    $dernier = Get-ChildItem -LiteralPath $DossierScelles -File -Filter 'SCELLE_*.txt' | Where-Object { $_.Name -notlike '*.horodatage.txt' } | Sort-Object Name | Select-Object -Last 1
    $actuel = $null
    if ($dernier) {
        $anciennes = @([IO.File]::ReadAllLines($dernier.FullName) | Where-Object { $_ -match '^[0-9A-F]{64}  \d+  ' })
        if (($anciennes -join "`n") -eq ($lignes -join "`n")) { $actuel = $dernier.FullName }
    }
    if (-not $actuel -and $lignes.Count) {
        $stampS = Get-Date -Format 'yyyyMMdd_HHmmss'
        $contenu = @('DIGSPILL - SCELLE DES PREUVES (v1)', '==================================================',
            "Collecte   : $nom", "Cree le    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz') (horloge de $env:COMPUTERNAME)",
            "Par        : $env:USERDOMAIN\$env:USERNAME", "Outil      : Generer-Interface.ps1 v$Version", '',
            'Empreintes SHA256, tailles (octets) et chemins des fichiers scelles :') + $lignes + @('',
            'Verification : Get-FileHash -Algorithm SHA256 <fichier> doit redonner chaque empreinte ci-dessus.',
            "L'empreinte SHA256 de CE fichier est celle qui est horodatee dans le jeton .tsr du meme nom.",
            'Chaque manifeste liste a son tour l''empreinte de tous les fichiers de la collecte ou de l''analyse.')
        $actuel = Join-Path $DossierScelles "SCELLE_$stampS.txt"
        [IO.File]::WriteAllText($actuel, (($contenu -join "`r`n") + "`r`n"), $Utf8)
        Info "[+] scelle cree : $(Split-Path $actuel -Leaf)"
    }
    # tous les scelles sans jeton (dont celui ecrit sur place par DigSpill.exe hors ligne), le plus recent en dernier
    $aHorodater = @(Get-ChildItem -LiteralPath $DossierScelles -File -Filter 'SCELLE_*.txt' | Where-Object { $_.Name -notlike '*.horodatage.txt' } | Sort-Object Name | ForEach-Object { $_.FullName })
    foreach ($actuelH in $aHorodater) {
    if (-not $SansInternet -and -not $SansHorodatage -and -not (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($actuelH, '.tsr')))) {
        $actuel0 = $actuel; $actuel = $actuelH
        try {
            $emp = [byte[]]::new(32)
            $hx = (Get-FileHash -LiteralPath $actuel -Algorithm SHA256).Hash
            for ($i = 0; $i -lt 32; $i++) { $emp[$i] = [Convert]::ToByte($hx.Substring($i * 2, 2), 16) }
            $h = Horodater $emp $Horodateur
            [IO.File]::WriteAllBytes([IO.Path]::ChangeExtension($actuel, '.tsq'), $h.requete)
            [IO.File]::WriteAllBytes([IO.Path]::ChangeExtension($actuel, '.tsr'), $h.reponse)
            [IO.File]::WriteAllText([IO.Path]::ChangeExtension($actuel, '.horodatage.txt'), ("Horodateur : $Horodateur`r`nDate du jeton : $($h.date)`r`nEmpreinte horodatee : $hx`r`n" +
                "Controle : openssl ts -reply -in $([IO.Path]::GetFileNameWithoutExtension($actuel)).tsr -text`r`n" +
                "Verification complete : openssl ts -verify -data $(Split-Path $actuel -Leaf) -in $([IO.Path]::GetFileNameWithoutExtension($actuel)).tsr -CAfile <chaine de certificats de l'horodateur>`r`n"), $Utf8)
            Info "[+] scelle horodate par un tiers : $($h.date)"
        } catch { Info "[!] horodatage impossible ($Horodateur) : $($_.Exception.Message). Le scelle reste valable, relancer plus tard avec Internet." }
        $actuel = $actuel0
    }
    }
} catch { Info "[!] scelle non cree : $($_.Exception.Message)" }
$scellesJson = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $DossierScelles) {
    foreach ($sc in (Get-ChildItem -LiteralPath $DossierScelles -File -Filter 'SCELLE_*.txt' | Where-Object { $_.Name -notlike '*.horodatage.txt' } | Sort-Object Name)) {
        $tsr = [IO.Path]::ChangeExtension($sc.FullName, '.tsr'); $inf = [IO.Path]::ChangeExtension($sc.FullName, '.horodatage.txt')
        $scellesJson.Add('{"nom":' + (J $sc.BaseName) + ',"chemin":' + (J $sc.FullName.Substring($Parent.Length + 1)) + ',"sha256":' + (J (Get-FileHash -LiteralPath $sc.FullName -Algorithm SHA256).Hash) +
            ',"texte":' + (J ([IO.File]::ReadAllText($sc.FullName))) + ',"tsr":' + $(if (Test-Path -LiteralPath $tsr) { J ([Convert]::ToBase64String([IO.File]::ReadAllBytes($tsr))) } else { 'null' }) +
            ',"horodatage":' + $(if (Test-Path -LiteralPath $inf) { J ([IO.File]::ReadAllText($inf)) } else { 'null' }) + ',"actuel":' + (JB ($sc.FullName -eq $actuel)) + '}')
    }
}

# ------------------------------------------------------------------ 6. charge utile JSON
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append('{"format":1,"genere_le":' + (J (Get-Date).ToString('yyyy-MM-dd HH:mm')) + ',"generateur":' + (J "Generer-Interface.ps1 v$Version sur $env:COMPUTERNAME") + ',"demo":false')
[void]$sb.Append(',"collecte":{"nom":' + (J $nom) + ',"analyse":' + (JB (Test-Path -LiteralPath $Analyse)) + '},"fichiers":{')
$premier = $true
foreach ($k in $fichiers.Keys) {
    $f = $fichiers[$k]
    if (-not $premier) { [void]$sb.Append(',') }; $premier = $false
    [void]$sb.Append((J $k) + ':{"chemin":' + (J $f.chemin) + ',"taille":' + $f.taille + ',"tronque":' + (JB $f.tronque) + ',"modifie":' + (J $f.modifie) + ',"texte":' + (J $f.texte) + '}')
}
[void]$sb.Append('},"geo_asn":[' + (($geoAsn | ForEach-Object { J $_ }) -join ',') + ']')
[void]$sb.Append(',"listes":{' + ($listesJson -join ',') + '},"bases":{"asn":' + $(if (Test-Path -LiteralPath $fAsn) { '{"source":"IPtoASN","date":' + (J (Date-Fichier $fAsn)) + '}' } else { 'null' }))
$fRw = Join-Path $Bases 'ransomware_live_FR.json'
[void]$sb.Append(',"listes":[' + ($listesMeta -join ',') + '],"ransomware":' + $(if (Test-Path -LiteralPath $fRw) { '{"date":' + (J (Date-Fichier $fRw)) + '}' } else { 'null' }) + '}')
[void]$sb.Append(',"ransomware_brut":' + (J (Brut 'ransomware_live_FR.json')) + ',"ransomware_recent_brut":' + (J (Brut 'ransomware_live_recent.json')))
[void]$sb.Append(',"memoire_brut":' + (J $memoireBrut) + ',"reglages_brut":' + (J $reglagesBrut) + ',"scelles":[' + ($scellesJson -join ',') + ']}')
$donnees = $sb.ToString()

# ------------------------------------------------------------------ 7. protection par mot de passe (facultative)
if ($Proteger) {
    if ($env:DIGSPILL_MDP) {
        # fourni par DigSpill.exe (variable du seul processus enfant), jamais ecrit sur disque
        $clair1 = $env:DIGSPILL_MDP; $clair2 = $env:DIGSPILL_MDP
    } else {
        $m1 = Read-Host '  Mot de passe du fichier' -AsSecureString
        $m2 = Read-Host '  Confirmer' -AsSecureString
        $clair1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($m1))
        $clair2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($m2))
    }
    if (-not $clair1 -or $clair1 -ne $clair2) { throw 'Mots de passe vides ou differents.' }
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $sel = New-Object byte[] 16; $rng.GetBytes($sel); $iv = New-Object byte[] 16; $rng.GetBytes($iv)
    $iter = 200000
    # PBKDF2-SHA256 -> 64 octets : 32 pour AES-256-CBC, 32 pour HMAC-SHA256 (chiffrer puis authentifier). .NET 4.7.2 minimum.
    $kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($Utf8.GetBytes($clair1), $sel, $iter, [Security.Cryptography.HashAlgorithmName]::SHA256)
    [byte[]]$cles = $kdf.GetBytes(64)
    $aes = [Security.Cryptography.Aes]::Create(); $aes.Mode = [Security.Cryptography.CipherMode]::CBC; $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7; $aes.KeySize = 256
    $aes.Key = [byte[]]$cles[0..31]; $aes.IV = $iv
    [byte[]]$octets = $Utf8.GetBytes($donnees)
    [byte[]]$chiffre = $aes.CreateEncryptor().TransformFinalBlock($octets, 0, $octets.Length)
    $hm = [Security.Cryptography.HMACSHA256]::new([byte[]]$cles[32..63])
    [byte[]]$mac = $hm.ComputeHash([byte[]]($iv + $chiffre))
    $donnees = '{"chiffre":true,"iterations":' + $iter + ',"sel":' + (J ([Convert]::ToBase64String($sel))) + ',"iv":' + (J ([Convert]::ToBase64String($iv))) +
        ',"donnees":' + (J ([Convert]::ToBase64String($chiffre))) + ',"mac":' + (J ([Convert]::ToBase64String($mac))) + ',"collecte":' + (J $nom) + ',"genere_le":' + (J (Get-Date).ToString('yyyy-MM-dd HH:mm')) + '}'
    $clair1 = $null; $clair2 = $null
    Info '[+] donnees chiffrees (AES-256-CBC + HMAC-SHA256, PBKDF2 200 000 iterations)'
}

# ------------------------------------------------------------------ 8. assemblage du fichier unique
function Lire([string]$rel) { [IO.File]::ReadAllText((Join-Path $Interface $rel), [Text.Encoding]::UTF8) }
$app = (Get-ChildItem -LiteralPath (Join-Path $Interface 'js') -Filter '*.js' | Sort-Object Name | ForEach-Object { [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8) }) -join "`n"
$html = (Lire 'modele.html')
# favicon et polices (Geist, Geist Mono, Doto) en data URI : le fichier reste autonome, aucun appel reseau
$ico = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $Interface 'assets\favicon.svg')))
$html = $html.Replace('<!--ICONE-->', '<link rel="icon" type="image/svg+xml" href="data:image/svg+xml;base64,' + $ico + '">')
$dPol = Join-Path $Interface 'vendor\polices'
$cssPol = [IO.File]::ReadAllText((Join-Path $dPol 'polices.css'), [Text.Encoding]::UTF8)
$cssPol = [regex]::Replace($cssPol, 'url\(([A-Za-z0-9._-]+\.woff2)\)', { param($m) 'url(data:font/woff2;base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $dPol $m.Groups[1].Value))) + ')' })
$html = $html.Replace('<!--POLICES-->', "<style>`n" + $cssPol + "</style>")
$html = $html.Replace('<!--STYLE-->', "<style>`n" + (Lire 'style.css') + "`n</style>")
$html = $html.Replace('<!--MONDE-->', '<script type="application/json" id="monde">' + (Lire 'vendor\monde.json') + '</script>')
$html = $html.Replace('<!--DONNEES-->', '<script type="application/json" id="donnees">' + $donnees + '</script>')
$vendor = (Get-ChildItem -LiteralPath (Join-Path $Interface 'vendor') -Filter '*.js' | Sort-Object Name | ForEach-Object { [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8) }) -join "`n;`n"
$html = $html.Replace('<!--ECHARTS-->', "<script>`n" + $vendor.Replace('</script', '<\/script') + "`n</script>")
$html = $html.Replace('<!--APP-->', "<script>`n" + $app.Replace('</script', '<\/script') + "`n</script>")
[IO.File]::WriteAllText($Sortie, $html, $Utf8)
$mo = [math]::Round((Get-Item -LiteralPath $Sortie).Length / 1MB, 1)
Write-Host ""
Write-Host "  Fichier cree ($mo Mo) : $Sortie" -ForegroundColor Green
Write-Host "  A ouvrir dans Edge, Chrome ou Firefox, sur n'importe quel PC (double-clic)."
if (-not $Proteger) { Write-Host "  [!] Fichier aussi sensible que la collecte : ne pas l'envoyer en clair (option -Proteger)." -ForegroundColor Yellow }
if (-not $SansOuvrir) { Start-Process $Sortie }
