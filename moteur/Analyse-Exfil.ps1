#Requires -Version 5.1
<#
    DigSpill - Analyse-Exfil.ps1 v2.2 - Analyse d'une collecte (Collecte-Exfil.ps1) orientee EXFILTRATION.
    Lance automatiquement en fin de collecte, ou a posteriori sur une collecte existante (poste d'analyse) :

      powershell -ExecutionPolicy Bypass -File Analyse-Exfil.ps1 -Collecte E:\Collecte\POSTE_20261117_150121

    Parametres :
      -Collecte <dossier>        dossier de collecte (obligatoire)
      -Sortie <dossier>          defaut : <Collecte>_analyse (la collecte d'origine n'est pas modifiee)
      -Fenetres 'debut;fin',...  fenetres a analyser en plus des sessions suspectes detectees
                                 ex. '2026-10-18 22:00;2026-10-19 06:00'
      -Velociraptor <zip>        conteneur Velociraptor de la meme collecte (defaut : detection automatique
                                 dans <Collecte>\..\Velociraptor). Sert a completer ce qui manque (ruches, $MFT, journaux).
      -MargeMinutes 30           marge autour des sessions suspectes
      -ReferenceJours 21         base de reference SRUM : N jours avant la premiere fenetre
      -SansMFT                   ne pas extraire / analyser la $MFT (1 a 2 Go, plusieurs minutes)
      -SansHashConteneurs        ne pas calculer le SHA256 complet des conteneurs Velociraptor
      -Ram <fichier.raw>         image RAM (defaut : memoire\ de la collecte, ou <disque>\MEMOIRE\<collecte>)
      -SansRam                   ne pas lire l'image RAM (Volatility 3, 5 a 20 min)
      -SansInternet              ne rien telecharger (symboles du noyau : seulement ceux deja dans outils\symboles)

    Toutes les heures sont en heure locale de la machine d'analyse (voir 00_LISEZMOI.txt pour le fuseau).
    Le script ne conclut pas : il produit des tableaux chiffres et une grille de verification.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Collecte,
    [string]$Sortie,
    [string[]]$Fenetres = @(),
    [string]$Velociraptor,
    [int]$MargeMinutes = 30,
    [int]$ReferenceJours = 21,
    [string]$Velo,
    [switch]$SansMFT,
    [switch]$SansHashConteneurs,
    [string[]]$Etapes = @(),
    [switch]$DerniereDuPoste,
    [switch]$GarderExtraits,
    [string]$Ram,
    [switch]$SansRam,
    [switch]$SansInternet
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$Version   = '2.2'
$T0        = Get-Date
$Inv       = [Globalization.CultureInfo]::InvariantCulture
$Fr        = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')

$Collecte = (Resolve-Path -LiteralPath $Collecte -ErrorAction Stop).ProviderPath.TrimEnd('\')
if ($DerniereDuPoste) {
    # -Collecte designe le dossier Collecte de la cle : on prend la collecte la plus recente de ce poste
    $last = Get-ChildItem -LiteralPath $Collecte -Directory | Where-Object { $_.Name -match ('^' + [regex]::Escape($env:COMPUTERNAME) + '_\d{8}_\d{6}(_leger)?$') } | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $last) { throw "Aucune collecte de $env:COMPUTERNAME dans $Collecte" }
    $Collecte = $last.FullName
}
if (-not $Sortie) { $Sortie = "${Collecte}_analyse" }
New-Item -ItemType Directory -Force -Path $Sortie | Out-Null
$Sortie = (Resolve-Path -LiteralPath $Sortie).ProviderPath.TrimEnd('\')
$Work = Join-Path $Sortie '_extraits'
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$LogFile = Join-Path $Sortie 'analyse.log'
$EvtxDir = Join-Path $Collecte 'evenements\evtx'

# noms d'outils d'attaque : dans moteur\indicateurs.json, pas dans ce script (sinon Defender le prend pour un outil
# d'attaque : Trojan:PowerShell/PSAttackTool.A)
$Ind = $null
try { $Ind = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'indicateurs.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
$manque = @('outils', 'outils_lancement_4688', 'sites_outils', 'mimikatz', 'menaces_mimikatz', 'detections_mimikatz', 'outils_mots_de_passe', 'outils_envoi') | Where-Object { -not $Ind -or -not $Ind.$_ }
if ($manque) {
    $m = "[!] Fichier moteur\indicateurs.json absent ou incomplet ($($manque -join ', ')) : refaites la clé avec le kit complet."
    Add-Content -LiteralPath $LogFile -Value $m -Encoding UTF8; Write-Output $m; exit 2
}

if (-not $Velo) {
    $racineCollecte = Split-Path (Split-Path $Collecte -Parent) -Parent
    foreach ($cand in @((Join-Path $PSScriptRoot 'outils\Collecteur-Velociraptor.exe'), (Join-Path $PSScriptRoot 'Collecteur-Velociraptor.exe'), (Join-Path $racineCollecte 'moteur\outils\Collecteur-Velociraptor.exe'), (Join-Path $racineCollecte 'Collecteur-Velociraptor.exe'))) {
        if (Test-Path -LiteralPath $cand) { $Velo = $cand; break }
    }
}
# kit extrait d'un zip telecharge : sans la « marque du Web », Windows ne demande plus confirmation a chaque lancement
# de Velociraptor, 7zr ou Python (seuls les outils du kit sont touches, jamais la collecte)
foreach ($d in @((Join-Path $PSScriptRoot 'outils'), $(if ($Velo) { Split-Path $Velo -Parent }))) {
    if ($d -and (Test-Path -LiteralPath $d)) { Get-ChildItem -LiteralPath $d -Recurse -File -Include *.exe, *.dll, *.pyd -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue }
}

# ----------------------------------------------------------------- helpers
function Log([string]$m) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Write-Host $line
    try { [IO.File]::AppendAllText($LogFile, $line + "`r`n", (New-Object Text.UTF8Encoding($false))) } catch {}
}
function P([string]$rel) { Join-Path $Sortie $rel }
function Leaf([string]$p) { if ($p) { ($p.TrimEnd('\') -split '[\\/]')[-1] } else { '' } }
function C([string]$rel) { Join-Path $Collecte $rel }
function Step([string]$name, [scriptblock]$sb) {
    # -Etapes : ne relancer que certaines etapes (les sessions et fenetres sont toujours calculees)
    if ($Etapes.Count -and $name -notmatch '^(Reconstitution|Fenetres|Synthese|Manifeste)' -and -not ($Etapes | Where-Object { $name -match [regex]::Escape($_) })) { return }
    Log "[*] $name"
    try { & $sb } catch {
        Log "    [!] Erreur : $($_.Exception.Message) (ligne $($_.InvocationInfo.ScriptLineNumber))"
        Log "        $((($_.ScriptStackTrace -split "`n") | Select-Object -First 3) -join ' <- ')"
    }
}
function Out-Csv($rows, [string]$rel) {
    # Copie explicite : @() sur une List[object] generique echoue parfois en PS 5.1 ("types des arguments")
    $a = New-Object System.Collections.ArrayList
    foreach ($r in $rows) { if ($null -ne $r) { [void]$a.Add($r) } }
    if ($a.Count) { $a | Export-Csv -Path (P $rel) -NoTypeInformation -Encoding UTF8 }
    else { 'Aucune ligne' | Out-File (P $rel) -Encoding utf8 }
}
# Nom typique d'un fichier chiffre (meme regle que la collecte 2.9 et l'interface)
$script:RxRanconNom = New-Object Text.RegularExpressions.Regex('(?i)(\.[a-z0-9]{2,5}\.\[(?=[^\]]*[0-9@])[^\]\s]{3,80}\]\.[^.]{2,15}$|\.[a-z0-9]{2,5}\.(?:[^@]*[\[{(=.])?[a-z0-9._%+-]+@[a-z][a-z0-9-]*(?:\.[a-z0-9-]+)*\.[a-z]{2,10}[\]})]?(?:\.[a-z0-9]{1,15})?$|\.(?:docx?|xlsx?|xlsm|pptx?|pdf|odt|ods|rtf|mdb|accdb|fdb)\.(?!(?:lnk|tmp|bak|old|orig|part|crdownload|download|sav|backup|gz|bz2|xz|7z|zip|rar|sig|asc|sha256|md5|json|xml|url|ini|log|dll|exe|data?|cache|db|js|map|config|mui|pdb|resources|sys|bin|idx|meta|lock|html?|txt|cs|py)$)[a-z0-9]{3,12}$|\.(locked|encrypted|crypted|lockbit\d?|phobos|elbie|eking|faust|devos|makop|mallox|akira|royal|blacksuit|medusa|basta|8base|rhysida|djvu)$|\.id[-_][0-9a-f]{6,})', 'Compiled')
# Chiffrement retenu : au moins 20 fichiers au nom typique, meme extension, modifies en 24 h.
# Une installation de jeu (icones @2x) ou des fichiers etales sur des mois ne sont pas un chiffrement.
function Get-Chiffrement {
    if ($null -ne $script:Chiffrement) { return $script:Chiffrement }
    $g = @{}
    foreach ($r in (Read-Csv (C 'rancon\fichiers_chiffres_suspects.csv'))) {
        $nom = "$($r.Chemin)" -replace '^.*\\', ''
        if (-not $script:RxRanconNom.IsMatch($nom)) { continue }
        $ext = [IO.Path]::GetExtension($nom).ToLowerInvariant()
        if (-not $g.ContainsKey($ext)) { $g[$ext] = [pscustomobject]@{ N = 0; Dates = (New-Object System.Collections.Generic.List[datetime]) } }
        $g[$ext].N++
        $d = Parse-Date "$($r.Modification)"; if (-not $d) { $d = Parse-Date "$($r.Creation)" }
        if ($d) { $g[$ext].Dates.Add($d) }
    }
    $res = New-Object System.Collections.Generic.List[object]
    foreach ($k in $g.Keys) {
        $t = @($g[$k].Dates | Sort-Object); $pic = 0; $deb = $null; $fin = $null; $i = 0
        for ($j = 0; $j -lt $t.Count; $j++) {
            while (($t[$j] - $t[$i]).TotalHours -gt 24) { $i++ }
            if ($j - $i + 1 -gt $pic) { $pic = $j - $i + 1; $deb = $t[$i]; $fin = $t[$j] }
        }
        if ($pic -ge 20) { $res.Add([pscustomobject]@{ Extension = $k; NbFichiers = $g[$k].N; Pic = $pic; Premier = $deb.ToString('yyyy-MM-dd HH:mm:ss'); Dernier = $fin.ToString('yyyy-MM-dd HH:mm:ss') }) }
    }
    $script:Chiffrement = @($res | Sort-Object NbFichiers -Descending)
    return $script:Chiffrement
}

function Read-Csv([string]$path) {
    if ($path -and (Test-Path -LiteralPath $path)) {
        $first = Get-Content -LiteralPath $path -TotalCount 1 -Encoding UTF8
        if ($first -and $first.StartsWith('"')) { return @(Import-Csv -LiteralPath $path -Encoding UTF8) }
    }
    return @()
}
function Fmt($d) { if ($d -is [datetime]) { $d.ToString('yyyy-MM-dd HH:mm:ss') } else { "$d" } }
function Mo([double]$b) { [math]::Round($b / 1MB, 2) }
function To-Local([string]$s) {
    # Dates Velociraptor (ISO, UTC 'Z') -> heure locale
    if (-not $s -or $s -match '^1601-01-01|^0001-01-01') { return $null }
    $o = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($s, $Inv, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$o)) { return $o.LocalDateTime }
    return $null
}
function Parse-Date([string]$s) {
    if (-not $s) { return $null }
    $d = [datetime]::MinValue
    foreach ($c in $Fr, $Inv, [Globalization.CultureInfo]::CurrentCulture) {
        if ([datetime]::TryParse($s, $c, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    }
    return $null
}
function Conv-Webkit($v) { $n = [int64]0; if ([int64]::TryParse("$v", [ref]$n) -and $n -gt 0) { [DateTime]::FromFileTimeUtc($n * 10).ToLocalTime() } }
function Conv-UnixUs($v) { $n = [int64]0; if ([int64]::TryParse("$v", [ref]$n) -and $n -gt 0) { [DateTimeOffset]::FromUnixTimeMilliseconds([int64]($n / 1000)).LocalDateTime } }
function Get-IpType([string]$ip) {
    if (-not $ip -or $ip -eq '-') { return '-' }
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
function Get-EvFields($ev) {
    $h = @{}
    try {
        $x = [xml]$ev.ToXml()
        if ($x.Event.EventData) { foreach ($d in @($x.Event.EventData.Data)) { if ($d -is [Xml.XmlElement] -and $d.Name) { $h[$d.Name] = $d.InnerText } } }
        if ($x.Event.UserData)  { foreach ($n in $x.Event.UserData.FirstChild.ChildNodes) { $h[$n.LocalName] = $n.InnerText } }
    } catch {}
    $h
}
function Invoke-Vql([string]$vql, [switch]$Json) {
    if (-not $Velo -or -not (Test-Path -LiteralPath $Velo)) { return @() }
    $prev = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        $fmt = if ($Json) { 'jsonl' } else { 'csv' }
        $o = & $Velo query --format $fmt $vql 2>$null
    } finally { [Console]::OutputEncoding = $prev }
    if (-not $o) { return @() }
    if ($Json) { return @($o | Where-Object { $_ -and $_.StartsWith('{') } | ForEach-Object { $_ | ConvertFrom-Json }) }
    return @($o | ConvertFrom-Csv)
}
function RegRoot([string]$hive) { "pathspec(DelegateAccessor='file', DelegatePath='''$hive''', Path='/')" }

# ----------------------------------------------------------------- conteneur Velociraptor (complement)
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
$script:Zip = $null
$CollStamp = $null
if ((Split-Path $Collecte -Leaf) -match '_(\d{8}_\d{6})') { $CollStamp = [datetime]::ParseExact($matches[1], 'yyyyMMdd_HHmmss', $Inv) }
$VeloDir = Join-Path (Split-Path $Collecte -Parent) 'Velociraptor'
if (-not $Velociraptor -and $CollStamp -and (Test-Path -LiteralPath $VeloDir)) {
    # Conteneur produit juste apres la collecte PowerShell (meme lancement). Un conteneur coupe par FAT32 fait
    # exactement 4 Gio - 1 octet : ecarte. Au-dela (NTFS, exFAT), il est lu : avant, tout conteneur de plus de 4 Go
    # etait ignore (13,6 Go sur un poste d'essai : SRUM, Prefetch, Amcache, $MFT jamais analyses).
    $Velociraptor = Get-ChildItem -LiteralPath $VeloDir -Filter '*.zip' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $CollStamp -and $_.LastWriteTime -le $CollStamp.AddHours(6) -and $_.Length -ne 4294967295 } |
        Sort-Object LastWriteTime | Select-Object -First 1 -ExpandProperty FullName
}
if ($Velociraptor -and (Test-Path -LiteralPath $Velociraptor)) {
    try { $script:Zip = [IO.Compression.ZipFile]::OpenRead($Velociraptor) } catch { $script:Zip = $null }
}
function Get-ZipName([string]$entry) {
    $n = $entry -replace '^uploads/[^/]+/', ''
    $n = (($n -split '/') | ForEach-Object { [uri]::UnescapeDataString($_) }) -join '\'
    $n -replace '^\\\\\.\\', ''
}
function Get-FromZip([string]$rx, [int]$max = 500) {
    # Extrait du conteneur Velociraptor les fichiers dont le chemin d'origine correspond a $rx
    if (-not $script:Zip) { return @() }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($e in $script:Zip.Entries) {
        if (-not $e.FullName.StartsWith('uploads/') -or $e.FullName.EndsWith('.idx')) { continue }
        $orig = Get-ZipName $e.FullName
        if ($orig -notmatch $rx) { continue }
        $dst = Join-Path $Work ('velociraptor\' + ($orig -replace ':', ''))
        if (-not (Test-Path -LiteralPath $dst)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
            try { [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dst, $true) } catch { continue }
        }
        $out.Add($dst)
        if ($out.Count -ge $max) { break }
    }
    return $out.ToArray()
}
function Find-Evtx([string]$channel) {
    $p = Join-Path $EvtxDir (($channel -replace '[\\/:\s]', '_') + '.evtx')
    if (Test-Path -LiteralPath $p) { return $p }
    $leaf = [regex]::Escape(($channel -replace '/', '%4') + '.evtx')
    $z = @(Get-FromZip "\\winevt\\Logs\\$leaf$" 1)
    if ($z.Count) { return $z[0] }
    return $null
}
function Get-Evtx([string]$channel, [int[]]$ids, [datetime]$from, [string]$extra = '') {
    # Renvoie toujours un tableau (vide si le journal est absent : tester la presence avec Find-Evtx)
    $p = Find-Evtx $channel
    if (-not $p) { return ,@() }
    $idq = ($ids | ForEach-Object { "EventID=$_" }) -join ' or '
    $iso = $from.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.000Z')
    $xp  = "*[System[($idq) and TimeCreated[@SystemTime>='$iso']]]$extra"
    try { return ,@(Get-WinEvent -Path $p -FilterXPath $xp -ErrorAction Stop) } catch { return ,@() }
}
function Get-EvtxRange([string]$channel) {
    $p = Find-Evtx $channel
    if (-not $p) { return $null }
    try {
        $old = Get-WinEvent -Path $p -Oldest -MaxEvents 1 -ErrorAction Stop
        $new = Get-WinEvent -Path $p -MaxEvents 1 -ErrorAction Stop
        return [pscustomobject]@{ Fichier = $p; Debut = $old.TimeCreated; Fin = $new.TimeCreated }
    } catch { return [pscustomobject]@{ Fichier = $p; Debut = $null; Fin = $null } }
}

# ----------------------------------------------------------------- contexte de la collecte
$Info = @{}
if (Test-Path -LiteralPath (C 'infos_collecte.txt')) {
    foreach ($l in Get-Content -LiteralPath (C 'infos_collecte.txt') -Encoding UTF8) { if ($l -match '^\s*([^:]+?)\s*:\s*(.*)$') { $Info[$matches[1]] = $matches[2] } }
}
$Since = $null
if ($Info['Periode analysee'] -match 'depuis (\d{4}-\d\d-\d\d)') { $Since = [datetime]::ParseExact($matches[1], 'yyyy-MM-dd', $Inv) }
if (-not $Since) { $Since = $(if ($CollStamp) { $CollStamp } else { Get-Date }).AddDays(-60) }
$Computer = if ($Info['Poste']) { $Info['Poste'] } else { (Split-Path $Collecte -Leaf) -replace '_\d{8}_\d{6}.*$', '' }

# Correspondance SID -> compte (profils collectes)
$SidName = @{ 'S-1-5-18' = 'SYSTEM'; 'S-1-5-19' = 'SERVICE LOCAL'; 'S-1-5-20' = 'SERVICE RESEAU' }
foreach ($p in (Read-Csv (C 'systeme\profils.csv'))) { if ($p.SID) { $SidName[$p.SID] = Split-Path $p.LocalPath -Leaf } }
foreach ($u in (Read-Csv (C 'comptes\inventaire_comptes.csv'))) { if ($u.SID -and -not $SidName[$u.SID]) { $SidName[$u.SID] = $u.Nom } }
function SidToName([string]$s) { if ($SidName[$s]) { $SidName[$s] } else { $s } }

# Grille de verification (alimente SYNTHESE_EXFILTRATION.txt)
$Grid = New-Object System.Collections.Generic.List[object]
# « 1 fichier », « 3 fichiers » : les constats de la grille sont lus tels quels dans l'interface
function Nb([int64]$n, [string]$un, [string]$plusieurs) { if ($n -le 1) { "$n $un" } else { "$n $plusieurs" } }
function G([string]$canal, [string]$statut, [string]$constat, [string]$fichier) {
    $Grid.Add([pscustomobject]@{ Canal = $canal; Statut = $statut; Constat = $constat; Fichier = $fichier })
}

Log "=== DigSpill - analyse exfiltration v$Version - $Computer ==="
Log "    Collecte : $Collecte"
Log "    Sortie   : $Sortie"
Log "    Conteneur Velociraptor : $(if ($script:Zip) { $Velociraptor } else { 'aucun (complements indisponibles)' })"
Log "    Moteur VQL : $(if ($Velo) { $Velo } else { 'ABSENT (SRUM, Prefetch, LNK, ShellBags, Amcache non analyses)' })"

# =================================================================== 1. SESSIONS ET FENETRES D'ANALYSE
$script:Sessions = New-Object System.Collections.Generic.List[object]
$script:Win = New-Object System.Collections.Generic.List[object]
Step 'Reconstitution des sessions (4624/4634/4647, LSM 21-25, RCM 1149, RdpCoreTS 131)' {
    $sys = '^(DWM-|UMFD-|ANONYMOUS|.*\$$)'
    $lt = "*[EventData[Data[@Name='LogonType']='2' or Data[@Name='LogonType']='10' or Data[@Name='LogonType']='11']]"
    if (-not (Find-Evtx 'Security')) { Log '    [!] Security.evtx absent : sessions non reconstituees'; G 'Connexions au poste (journal de sécurité de Windows)' 'NON VERIFIABLE' 'Le journal de sécurité de Windows (Security.evtx) manque dans la collecte : impossible de savoir qui s''est connecté et quand.' ''; return }
    $on = Get-Evtx 'Security' @(4624) $Since " and $lt"
    $ends = @{}
    foreach ($e in @(Get-Evtx 'Security' @(4634) $Since " and $lt") + @(Get-Evtx 'Security' @(4647) $Since)) {
        $f = Get-EvFields $e; $id = $f['TargetLogonId']
        if ($id -and (-not $ends[$id] -or $e.TimeCreated -lt $ends[$id].Date)) { $ends[$id] = @{ Date = $e.TimeCreated; Par = $(if ($e.Id -eq 4647) { '4647 deconnexion utilisateur' } else { '4634 fermeture' }) } }
    }
    $seen = @{}
    foreach ($e in $on) {
        $f = Get-EvFields $e
        $user = "$($f['TargetUserName'])"
        if ($user -match $sys -or $f['TargetDomainName'] -match 'Window Manager|Font Driver') { continue }
        $k = "$user|$($e.TimeCreated.ToString('yyyyMMddHHmmss'))"
        if ($seen[$k]) { continue }; $seen[$k] = 1
        $end = $ends[$f['TargetLogonId']]
        if (-not $end -and $f['TargetLinkedLogonId'] -and $f['TargetLinkedLogonId'] -ne '0x0') { $end = $ends[$f['TargetLinkedLogonId']] }
        $script:Sessions.Add([pscustomobject]@{ Debut = $e.TimeCreated; Fin = $(if ($end) { $end.Date }); FinPar = $(if ($end) { $end.Par } else { 'inconnue' })
            Compte = $user; Type = "4624 type $($f['LogonType'])"; IP = $f['IpAddress']; TypeIP = Get-IpType $f['IpAddress']; Poste = $f['WorkstationName']; Session = $f['TargetLogonId']; Source = 'Security' })
    }

    # Sessions Bureau a distance (LocalSessionManager) : ouverture 21 -> fermeture 23, deconnexions 24 / reconnexions 25
    $lsm = Get-Evtx 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational' @(21, 23, 24, 25) $Since
    if (@($lsm).Count) {
        $open = @{}
        foreach ($e in ($lsm | Sort-Object TimeCreated)) {
            $f = Get-EvFields $e; $sid = $f['SessionID']
            switch ($e.Id) {
                21 { $open[$sid] = [pscustomobject]@{ Debut = $e.TimeCreated; Fin = $null; FinPar = 'inconnue'; Compte = ($f['User'] -replace '^.*\\', ''); Type = 'RDP (LSM)'; IP = $f['Address']; TypeIP = Get-IpType $f['Address']; Poste = ''; Session = "LSM $sid"; Source = 'LocalSessionManager'; Evts = @('21') }
                     $script:Sessions.Add($open[$sid]) }
                24 { if ($open[$sid]) { $open[$sid].Evts += "24 deconnexion $($e.TimeCreated.ToString('HH:mm'))" } }
                25 { if ($open[$sid]) { $open[$sid].Evts += "25 reconnexion $($e.TimeCreated.ToString('HH:mm')) depuis $($f['Address'])"; if ((Get-IpType $f['Address']) -eq 'PUBLIQUE') { $open[$sid].TypeIP = 'PUBLIQUE'; $open[$sid].IP = "$($open[$sid].IP) / $($f['Address'])" } } }
                23 { if ($open[$sid]) { $open[$sid].Fin = $e.TimeCreated; $open[$sid].FinPar = '23 fermeture'; $open.Remove($sid) } }
            }
        }
    }
    # Fin estimee quand 4634 manque (journal tourne, audit Logoff absent) : premiere deconnexion RDP 4779 ou 4647
    # du meme compte avant sa connexion suivante, sinon arret / redemarrage du poste (4608, 1100, 6005, 6006, 6008)
    $byUser = @{}
    foreach ($e in @(Get-Evtx 'Security' @(4779, 4647) $Since)) {
        $f = Get-EvFields $e; $u = "$(if ($e.Id -eq 4779) { $f['AccountName'] } else { $f['TargetUserName'] })"
        if (-not $u) { continue }
        if (-not $byUser[$u]) { $byUser[$u] = New-Object System.Collections.Generic.List[object] }
        $byUser[$u].Add([pscustomobject]@{ Date = $e.TimeCreated; Par = $(if ($e.Id -eq 4779) { "estimee : 4779 deconnexion RDP de $u ($($f['ClientAddress']))" } else { "estimee : 4647 deconnexion de $u" }) })
    }
    $boots = @(@(Get-Evtx 'Security' @(4608, 1100) $Since) + @(Get-Evtx 'System' @(6005, 6006, 6008) $Since) | ForEach-Object { $_.TimeCreated } | Sort-Object)
    $all = @($script:Sessions | Sort-Object Debut)
    foreach ($s in $all) {
        if ($s.Fin) { continue }
        $next = $all | Where-Object { $_.Compte -eq $s.Compte -and $_.Debut -gt $s.Debut } | Select-Object -First 1
        $lim = if ($next) { $next.Debut } else { $s.Debut.AddDays(2) }
        $c = if ($byUser[$s.Compte]) { $byUser[$s.Compte] | Where-Object { $_.Date -gt $s.Debut -and $_.Date -le $lim } | Sort-Object Date | Select-Object -First 1 }
        $b = $boots | Where-Object { $_ -gt $s.Debut -and $_ -le $lim } | Select-Object -First 1
        if ($c -and (-not $b -or $c.Date -le $b)) { $s.Fin = $c.Date; $s.FinPar = $c.Par }
        elseif ($b) { $s.Fin = $b; $s.FinPar = 'estimee : arret / redemarrage du poste' }
    }
    $rows = $script:Sessions | Sort-Object Debut | Select-Object @{n='Debut';e={ Fmt $_.Debut }}, @{n='Fin';e={ Fmt $_.Fin }},
        @{n='DureeMin';e={ if ($_.Fin) { [math]::Round(($_.Fin - $_.Debut).TotalMinutes, 1) } }}, FinPar, Compte, Type, IP, TypeIP, Poste, Session, Source,
        @{n='Evenements';e={ if ($_.PSObject.Properties['Evts']) { $_.Evts -join ' | ' } }}
    Out-Csv $rows 'sessions_reconstituees.csv'
    Log "    $($script:Sessions.Count) sessions interactives / RDP reconstituees"

    # Points de connexion isoles (authentifications RDP 1149, connexions TCP 131) pour la chronologie
    $pts = New-Object System.Collections.Generic.List[object]
    foreach ($e in @(Get-Evtx 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational' @(1149) $Since)) {
        $f = Get-EvFields $e; $pts.Add([pscustomobject]@{ Date = Fmt $e.TimeCreated; Evenement = '1149 authentification RDP'; Compte = $f['Param1']; IP = $f['Param3']; TypeIP = Get-IpType $f['Param3'] })
    }
    foreach ($e in @(Get-Evtx 'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational' @(131) $Since)) {
        $f = Get-EvFields $e; $ip = ($f['ClientIP'] -replace ':\d+$', '' -replace '^\[|\]$', '')
        $pts.Add([pscustomobject]@{ Date = Fmt $e.TimeCreated; Evenement = '131 connexion TCP RDP'; Compte = ''; IP = $ip; TypeIP = Get-IpType $ip })
    }
    Out-Csv ($pts | Sort-Object Date) 'connexions_rdp_points.csv'
}

Step "Fenetres d'analyse (sessions depuis IP publique / VPN, compte Invite, indices forts, fenetres manuelles)" {
    $cand = New-Object System.Collections.Generic.List[object]
    foreach ($s in $script:Sessions) {
        $why = $null
        if ($s.TypeIP -eq 'PUBLIQUE') { $why = "connexion de $($s.Compte) depuis Internet ($($s.IP))" }
        elseif ($s.TypeIP -eq 'VPN/CGNAT') { $why = "connexion de $($s.Compte) depuis $($s.IP) (adresse de VPN ou d'opérateur partagé, NetBird ?)" }
        elseif ($s.Compte -match '^(Invit|Guest)') { $why = "connexion du compte invité $($s.Compte) depuis $($s.IP)" }
        if (-not $why) { continue }
        $fin = if ($s.Fin) { $s.Fin } else { $s.Debut.AddHours(2) }
        $cand.Add([pscustomobject]@{ Debut = $s.Debut.AddMinutes(-$MargeMinutes); Fin = $fin.AddMinutes($MargeMinutes); Motif = $why + $(if (-not $s.Fin) { ' (heure de fin inconnue : 2 h comptées)' } else { '' }) })
    }
    # Indices forts horodates : une attaque menee sur place ou par un outil d'acces distant n'ouvre pas de session
    # RDP depuis Internet ; sans eux il n'y aurait pas de fenetre, donc rien a raconter.
    $ind = New-Object System.Collections.Generic.List[object]
    function Indice($date, [string]$quoi) { $d = Parse-Date $date; if ($d) { $ind.Add([pscustomobject]@{ T = $d; Quoi = $quoi }) } }
    foreach ($r in (Read-Csv (C 'comptes\evenements_comptes.csv'))) {
        if ($r.EventID -eq '4720') { Indice $r.Date "compte $($r.CibleOuGroupe) créé" }
        elseif ($r.EventID -match '^(4728|4732|4756)$' -and "$($r.CibleOuGroupe)" -match '(?i)admin') { Indice $r.Date "$($r.Membre) ajouté au groupe $($r.CibleOuGroupe)" }
    }
    foreach ($r in (Read-Csv (C 'evenements\resume_evenements_cles.csv'))) {
        $m = "$($r.Message)"
        switch ("$($r.EventID)") {
            '1102' { Indice $r.Date 'journal Sécurité effacé' }
            '104'  { Indice $r.Date ('journal effacé' + $(if ($m -match '(?i)the (\S+) log file') { " ($($Matches[1]))" })) }
            '5001' { Indice $r.Date 'protection en temps réel de Defender coupée' }
            '4688' { if ($m -match $Ind.outils_lancement_4688) { Indice $r.Date "$($Matches[1]) lancé" } }
        }
    }
    foreach ($r in (Read-Csv (C 'rancon\commandes_destructrices_4688.csv'))) { $l = "$($r.LigneDeCommande)"; Indice $r.Date ('commande ' + $l.Substring(0, [Math]::Min(70, $l.Length))) }
    foreach ($r in (Get-Chiffrement)) { Indice $r.Premier "début du chiffrement ($($r.NbFichiers) fichiers $($r.Extension))"; Indice $r.Dernier "fin du chiffrement $($r.Extension)" }
    $grp = $null
    foreach ($x in ($ind | Sort-Object T)) {
        if ($grp -and ($x.T - $grp.Fin).TotalMinutes -le 60) { $grp.Fin = $x.T; $grp.Quoi.Add($x.Quoi) }
        else {
            if ($grp) { $cand.Add([pscustomobject]@{ Debut = $grp.Debut.AddMinutes(-$MargeMinutes); Fin = $grp.Fin.AddMinutes($MargeMinutes); Motif = "activité suspecte : $(@($grp.Quoi | Select-Object -Unique | Select-Object -First 3) -join ', ')$(if ($grp.Quoi.Count -gt 3) { " ($($grp.Quoi.Count) indices)" })" }) }
            $grp = [pscustomobject]@{ Debut = $x.T; Fin = $x.T; Quoi = (New-Object System.Collections.Generic.List[string]) }; $grp.Quoi.Add($x.Quoi)
        }
    }
    if ($grp) { $cand.Add([pscustomobject]@{ Debut = $grp.Debut.AddMinutes(-$MargeMinutes); Fin = $grp.Fin.AddMinutes($MargeMinutes); Motif = "activité suspecte : $(@($grp.Quoi | Select-Object -Unique | Select-Object -First 3) -join ', ')$(if ($grp.Quoi.Count -gt 3) { " ($($grp.Quoi.Count) indices)" })" }) }
    if ($ind.Count) { Log "    $($ind.Count) indice(s) fort(s) horodate(s) : comptes, journaux effaces, Defender, outils, commandes, chiffrement" }
    foreach ($f in $Fenetres) {
        $parts = $f -split '[;|]'
        $d1 = Parse-Date $parts[0]; $d2 = Parse-Date $parts[-1]
        if ($d1 -and $d2 -and $d2 -gt $d1) { $cand.Add([pscustomobject]@{ Debut = $d1; Fin = $d2; Motif = 'période ajoutée à la main' }) }
        else { Log "    [!] Fenetre ignoree (format attendu 'aaaa-mm-jj hh:mm;aaaa-mm-jj hh:mm') : $f" }
    }
    # Fusion des fenetres qui se chevauchent
    $i = 0
    foreach ($c in ($cand | Sort-Object Debut)) {
        $last = if ($script:Win.Count) { $script:Win[$script:Win.Count - 1] } else { $null }
        if ($last -and $c.Debut -le $last.Fin) {
            if ($c.Fin -gt $last.Fin) { $last.Fin = $c.Fin }
            if ($last.Motif -notlike "*$($c.Motif)*") { $last.Motif += " + $($c.Motif)" }
        } else { $i++; $script:Win.Add([pscustomobject]@{ Id = "F$i"; Debut = $c.Debut; Fin = $c.Fin; Motif = $c.Motif }) }
    }
    Out-Csv ($script:Win | Select-Object Id, @{n='Debut';e={ Fmt $_.Debut }}, @{n='Fin';e={ Fmt $_.Fin }}, @{n='DureeMin';e={ [math]::Round(($_.Fin - $_.Debut).TotalMinutes) }}, Motif) 'fenetres_analyse.csv'
    Log "    $($script:Win.Count) fenetre(s) d'analyse (marge $MargeMinutes min)"
    foreach ($w in $script:Win) { Log "      $($w.Id) $(Fmt $w.Debut) -> $(Fmt $w.Fin) : $($w.Motif)" }
    # Couverture des journaux utiles vs fenetres : un journal qui commence apres une fenetre ne prouve rien pour elle
    $cov = foreach ($ch in 'Security', 'System', 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational', 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational',
            'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational', 'Microsoft-Windows-PowerShell/Operational', 'Microsoft-Windows-Windows Defender/Operational',
            'Microsoft-Windows-SMBServer/Security', 'Microsoft-Windows-Bits-Client/Operational', 'Microsoft-Windows-DNS-Client/Operational') {
        $r = Get-EvtxRange $ch
        $o = [ordered]@{ Journal = $ch; Present = $(if ($r) { 'oui' } else { 'NON' }); PremierEvt = Fmt $(if ($r) { $r.Debut }); DernierEvt = Fmt $(if ($r) { $r.Fin }) }
        foreach ($w in $script:Win) { $o[$w.Id] = $(if (-not $r -or -not $r.Debut) { 'absent' } elseif ($r.Debut -le $w.Debut -and $r.Fin -ge $w.Fin) { 'couvert' } elseif ($r.Debut -gt $w.Fin -or $r.Fin -lt $w.Debut) { 'NON COUVERT' } else { 'partiel' }) }
        [pscustomobject]$o
    }
    Out-Csv $cov 'journaux_couverture.csv'
    $nc = @($cov | Where-Object { $p = $_; @($script:Win | Where-Object { $p.($_.Id) -ne 'couvert' }).Count })
    if ($script:Win.Count -and $nc.Count) { G 'Journaux de Windows assez anciens pour couvrir l''attaque ?' 'A LIRE' "$(Nb $nc.Count 'journal ne remonte' 'journaux ne remontent') pas jusqu'au début de l'attaque (Windows efface les plus anciens événements). Pour ces journaux, ne rien trouver ne prouve rien." 'journaux_couverture.csv' }
    if (-not $script:Win.Count) { G 'Périodes de l''attaque (fenêtres d''analyse)' 'A FAIRE' 'DigSpill n''a trouvé ni connexion suspecte ni indice daté : il ne sait pas quand chercher. Si vous connaissez la date de l''attaque, relancez l''analyse en la donnant (-Fenetres).' 'fenetres_analyse.csv' }
}
function WinOf($d) {
    if (-not ($d -is [datetime])) { return '' }
    (@($script:Win | Where-Object { $d -ge $_.Debut -and $d -le $_.Fin } | ForEach-Object { $_.Id }) -join ',')
}

$ToolRx = $Ind.outils

# =================================================================== 2. SRUM : VOLUMES PAR APPLICATION ET PAR HEURE
Step 'SRUM : volumes reseau et disque par application, fenetres vs base de reference' {
    $db = C 'artefacts\srum\SRUDB.dat'
    if (-not (Test-Path -LiteralPath $db)) { $db = @(Get-FromZip '\\System32\\sru\\SRUDB\.dat$' 1) | Select-Object -First 1 }
    if (-not $db -or -not $Velo) { G 'Quantité de données envoyées sur Internet (SRUM)' 'NON VERIFIABLE' 'Le relevé de Windows qui compte les données envoyées par chaque programme (SRUM) n''a pas pu être lu : fichier SRUDB.dat ou outil de lecture (Velociraptor) absent.' ''; return }
    $tmp = Join-Path $Work 'SRUDB.dat'
    Copy-Item -LiteralPath $db -Destination $tmp -Force
    $net = Invoke-Vql "SELECT TimeStamp, srum_lookup_id(file='''$tmp''', id=AppId) AS App, UserId, InterfaceLuid, BytesSent, BytesRecvd FROM parse_ese(file='''$tmp''', table='{973F5D5C-1D90-4944-BE8E-24B94231A174}')"
    $rows = foreach ($r in $net) {
        $d = To-Local $r.TimeStamp
        if (-not $d) { continue }
        [pscustomobject]@{ Releve = $d; App = $(if ($r.App) { $r.App } else { "(AppId inconnu)" }); UserId = $r.UserId; Interface = $r.InterfaceLuid; Envoye = [double]$r.BytesSent; Recu = [double]$r.BytesRecvd }
    }
    $rows = @($rows)
    if (-not $rows.Count) { G 'Quantité de données envoyées sur Internet (SRUM)' 'NON VERIFIABLE' 'Le relevé de Windows qui compte les données envoyées par chaque programme (SRUM) est vide ou illisible. C''est fréquent sur Windows Server, où il n''est pas actif.' ''; return }
    $userMap = @{}
    foreach ($u in (Invoke-Vql "SELECT UserId, srum_lookup_id(file='''$tmp''', id=UserId) AS Sid FROM parse_ese(file='''$tmp''', table='{973F5D5C-1D90-4944-BE8E-24B94231A174}') GROUP BY UserId")) { $userMap["$($u.UserId)"] = SidToName $u.Sid }
    $first = ($rows | Measure-Object -Property Releve -Minimum).Minimum
    $last  = ($rows | Measure-Object -Property Releve -Maximum).Maximum
    Out-Csv ($rows | Sort-Object Releve | Select-Object @{n='Releve';e={ Fmt $_.Releve }}, App, @{n='Utilisateur';e={ $userMap["$($_.UserId)"] }}, Interface,
        @{n='EnvoyeOctets';e={ $_.Envoye }}, @{n='RecuOctets';e={ $_.Recu }}, @{n='Fenetre';e={ WinOf $_.Releve }}) 'srum_reseau_brut.csv'

    # Agregation par releve (environ horaire) et par application, toutes interfaces confondues
    $byKey = @{}
    foreach ($r in $rows) {
        $k = "$($r.Releve.Ticks)|$($r.App)"
        if (-not $byKey[$k]) { $byKey[$k] = [pscustomobject]@{ Releve = $r.Releve; App = $r.App; Envoye = 0.0; Recu = 0.0 } }
        $byKey[$k].Envoye += $r.Envoye; $byKey[$k].Recu += $r.Recu
    }
    $agg = @($byKey.Values)
    $tot = @($agg | Group-Object { $_.Releve.Ticks } | ForEach-Object {
        $top = $_.Group | Sort-Object Envoye -Descending | Select-Object -First 1
        [pscustomobject]@{ Releve = $_.Group[0].Releve; Envoye = ($_.Group | Measure-Object Envoye -Sum).Sum; Recu = ($_.Group | Measure-Object Recu -Sum).Sum; TopApp = $top.App; TopAppEnvoye = $top.Envoye }
    } | Sort-Object Releve)
    Out-Csv ($tot | Select-Object @{n='Releve';e={ Fmt $_.Releve }}, @{n='EnvoyeMo';e={ Mo $_.Envoye }}, @{n='RecuMo';e={ Mo $_.Recu }}, @{n='PremiereAppliEnvoi';e={ $_.TopApp }}, @{n='PremiereAppliEnvoyeMo';e={ Mo $_.TopAppEnvoye }}, @{n='Fenetre';e={ WinOf $_.Releve }}) 'srum_total_par_releve.csv'
    Out-Csv ($tot | Sort-Object Envoye -Descending | Select-Object -First 30 | Select-Object @{n='Releve';e={ Fmt $_.Releve }}, @{n='EnvoyeMo';e={ Mo $_.Envoye }}, @{n='RecuMo';e={ Mo $_.Recu }}, @{n='PremiereAppliEnvoi';e={ $_.TopApp }}, @{n='PremiereAppliEnvoyeMo';e={ Mo $_.TopAppEnvoye }}, @{n='Fenetre';e={ WinOf $_.Releve }}) 'srum_30_plus_gros_envois.csv'

    $inWin = { param($d) foreach ($w in $script:Win) { if ($d -gt $w.Debut -and $d -le $w.Fin.AddMinutes(60)) { return $w.Id } }; return $null }
    $refEnd = if ($script:Win.Count) { ($script:Win | Measure-Object Debut -Minimum).Minimum } else { $last }
    $refStart = $refEnd.AddDays(-$ReferenceJours)
    $ref = @($agg | Where-Object { $_.Releve -ge $refStart -and $_.Releve -lt $refEnd -and -not (& $inWin $_.Releve) })
    $refTot = @($tot | Where-Object { $_.Releve -ge $refStart -and $_.Releve -lt $refEnd -and -not (& $inWin $_.Releve) })
    $refStats = @{}
    foreach ($g in ($ref | Group-Object App)) {
        $v = @($g.Group | ForEach-Object { $_.Envoye } | Sort-Object)
        $refStats[$g.Name] = [pscustomobject]@{ App = $g.Name; NbReleves = $v.Count; MoyenneEnvoyeMo = Mo (($v | Measure-Object -Average).Average); P95EnvoyeMo = Mo ($v[[math]::Max(0, [int][math]::Ceiling($v.Count * 0.95) - 1)]); MaxEnvoyeMo = Mo ($v[-1])
            MoyenneRecuMo = Mo (($g.Group | Measure-Object Recu -Average).Average); MaxRecuMo = Mo (($g.Group | Measure-Object Recu -Maximum).Maximum) }
    }
    $tv = @($refTot | ForEach-Object { $_.Envoye } | Sort-Object)
    $refAll = if ($tv.Count) { [pscustomobject]@{ App = '(TOTAL toutes applis)'; NbReleves = $tv.Count; MoyenneEnvoyeMo = Mo (($tv | Measure-Object -Average).Average); P95EnvoyeMo = Mo ($tv[[math]::Max(0, [int][math]::Ceiling($tv.Count * 0.95) - 1)]); MaxEnvoyeMo = Mo ($tv[-1]); MoyenneRecuMo = Mo (($refTot | Measure-Object Recu -Average).Average); MaxRecuMo = Mo (($refTot | Measure-Object Recu -Maximum).Maximum) } }
    Out-Csv (@($refAll) + @($refStats.Values | Sort-Object MaxEnvoyeMo -Descending) | Where-Object { $_ }) 'srum_reference_par_app.csv'

    $cmp = New-Object System.Collections.Generic.List[object]
    foreach ($w in $script:Win) {
        $wt = @($tot | Where-Object { $_.Releve -gt $w.Debut -and $_.Releve -le $w.Fin.AddMinutes(60) })
        foreach ($t in $wt) {
            $ecart = if ($refAll -and (Mo $t.Envoye) -gt $refAll.MaxEnvoyeMo) { 'AU-DESSUS DU MAX DE REFERENCE' } elseif ($refAll -and (Mo $t.Envoye) -gt $refAll.P95EnvoyeMo) { 'au-dessus du 95e centile' } else { '' }
            $cmp.Add([pscustomobject]@{ Fenetre = $w.Id; Releve = Fmt $t.Releve; App = '(TOTAL toutes applis)'; EnvoyeMo = Mo $t.Envoye; RecuMo = Mo $t.Recu
                RefMoyenneEnvoyeMo = $refAll.MoyenneEnvoyeMo; RefP95EnvoyeMo = $refAll.P95EnvoyeMo; RefMaxEnvoyeMo = $refAll.MaxEnvoyeMo; Ecart = $ecart })
            foreach ($a in ($agg | Where-Object { $_.Releve -eq $t.Releve -and ($_.Envoye -gt 0 -or $_.Recu -gt 0) } | Sort-Object Envoye -Descending)) {
                $rs = $refStats[$a.App]
                $ecart = if (-not $rs) { 'APPLI ABSENTE DE LA REFERENCE' } elseif ((Mo $a.Envoye) -gt $rs.MaxEnvoyeMo) { 'AU-DESSUS DU MAX DE REFERENCE' } else { '' }
                $cmp.Add([pscustomobject]@{ Fenetre = $w.Id; Releve = Fmt $a.Releve; App = $a.App; EnvoyeMo = Mo $a.Envoye; RecuMo = Mo $a.Recu
                    RefMoyenneEnvoyeMo = $(if ($rs) { $rs.MoyenneEnvoyeMo }); RefP95EnvoyeMo = $(if ($rs) { $rs.P95EnvoyeMo }); RefMaxEnvoyeMo = $(if ($rs) { $rs.MaxEnvoyeMo }); Ecart = $ecart })
            }
        }
    }
    Out-Csv $cmp 'srum_fenetres_vs_reference.csv'

    # Volume attribue au Bureau a distance par fenetre (methode explicite pour le rapport)
    $rdpRx = '(?i)TermService|rdpcore|rdp'
    $meth = New-Object System.Collections.Generic.List[string]
    $meth.Add("METHODE DE MESURE SRUM - $Computer")
    $meth.Add('=========================================================================')
    $meth.Add("Source : SRUDB.dat, table reseau {973F5D5C-1D90-4944-BE8E-24B94231A174}, lue par Velociraptor (parse_ese).")
    $meth.Add("Couverture : du $(Fmt $first) au $(Fmt $last) ($($rows.Count) enregistrements).")
    $meth.Add('Chaque enregistrement = octets envoyes / recus par une application, sur une interface, pendant l''intervalle')
    $meth.Add('qui precede la date du releve (environ 1 h ; SRUM ecrit sa base a peu pres toutes les heures).')
    $meth.Add('Un releve date de 18:38 couvre donc environ 17:38 -> 18:38. Les fenetres incluent le releve suivant leur fin.')
    $meth.Add('Le trafic RDP est compte sous le service TermService (svchost) : il melange affichage, presse-papier et lecteurs')
    $meth.Add('rediriges. SRUM ne distingue pas le trafic local du trafic Internet ; seule la box / le pare-feu le peut.')
    $meth.Add('Limites : donnees de la derniere heure perdues si arret brutal ; un processus termine avant l''ecriture est compte')
    $meth.Add('sous son AppId ; pas de destination (IP) dans SRUM.')
    $meth.Add('')
    $meth.Add("Base de reference : $ReferenceJours jours avant la premiere fenetre, soit du $(Fmt $refStart) au $(Fmt $refEnd), fenetres exclues.")
    if ($first -gt $refStart) { $meth.Add("  ATTENTION : SRUM ne commence que le $(Fmt $first) : reference reduite a $([math]::Round(($refEnd - $first).TotalDays, 1)) jours.") }
    if ($refAll) { $meth.Add("  Total toutes applis par releve : moyenne $($refAll.MoyenneEnvoyeMo) Mo envoyes, 95e centile $($refAll.P95EnvoyeMo) Mo, max $($refAll.MaxEnvoyeMo) Mo ($($refAll.NbReleves) releves).") }
    $meth.Add('')
    foreach ($w in $script:Win) {
        $wa = @($agg | Where-Object { $_.Releve -gt $w.Debut -and $_.Releve -le $w.Fin.AddMinutes(60) })
        $wr = @($wa | Where-Object { $_.App -match $rdpRx })
        $meth.Add("$($w.Id) $(Fmt $w.Debut) -> $(Fmt $w.Fin) ($($w.Motif))")
        if (-not $wa.Count) { $meth.Add('    Aucun releve SRUM dans cette fenetre (hors couverture ou poste eteint).'); continue }
        $rel = ($wa | ForEach-Object { $_.Releve } | Sort-Object -Unique)
        $meth.Add(("    Releves pris en compte : {0} (de {1} a {2})" -f @($rel).Count, (Fmt $rel[0]), (Fmt $rel[-1])))
        $meth.Add(("    Toutes applis : {0} Mo envoyes, {1} Mo recus" -f (Mo (($wa | Measure-Object Envoye -Sum).Sum)), (Mo (($wa | Measure-Object Recu -Sum).Sum))))
        $meth.Add(("    Bureau a distance (TermService) : {0} Mo envoyes, {1} Mo recus" -f (Mo (($wr | Measure-Object Envoye -Sum).Sum)), (Mo (($wr | Measure-Object Recu -Sum).Sum))))
        $hotW = @($cmp | Where-Object { $_.Fenetre -eq $w.Id -and $_.Ecart })
        $hot = @($hotW | Where-Object { $_.EnvoyeMo -ge 1 -or $_.App -match $ToolRx })
        $meth.Add("    Depassements de la reference (>= 1 Mo ou outil sensible) : $(if ($hot.Count) { ($hot | ForEach-Object { "$($_.Releve) $(Leaf $_.App) $($_.EnvoyeMo) Mo ($($_.Ecart))" }) -join ' ; ' } else { 'aucun' })$(if ($hotW.Count -gt $hot.Count) { " (+ $($hotW.Count - $hot.Count) petit(s) ecart(s) < 1 Mo, voir srum_fenetres_vs_reference.csv)" })")
    }
    $meth | Out-File (P 'srum_METHODE.txt') -Encoding utf8

    $hotAll = @($cmp | Where-Object { $_.Ecart -eq 'AU-DESSUS DU MAX DE REFERENCE' })
    $newApp = @($cmp | Where-Object { $_.Ecart -eq 'APPLI ABSENTE DE LA REFERENCE' -and $_.EnvoyeMo -ge 1 })
    if (-not $script:Win.Count) { G 'Quantité de données envoyées sur Internet (SRUM)' 'A FAIRE' "Relevé lu (du $(Fmt $first) au $(Fmt $last)), mais aucune période d'attaque n'est connue : rien à comparer. Donnez la date de l'attaque pour mesurer ce qui est parti." 'srum_total_par_releve.csv' }
    elseif ($hotAll.Count -or $newApp.Count) { G 'Quantité de données envoyées sur Internet (SRUM)' 'INDICE' "Pendant l'attaque, $(Nb $hotAll.Count 'heure a dépassé' 'heures ont dépassé') le plus gros envoi habituel du poste, et $(Nb $newApp.Count 'programme inhabituel a envoyé' 'programmes inhabituels ont envoyé') au moins 1 Mo. Détail par programme et par heure dans Détails › Données sorties du poste." 'srum_fenetres_vs_reference.csv, srum_METHODE.txt' }
    else { G 'Quantité de données envoyées sur Internet (SRUM)' 'RAS' "Pendant l'attaque, le poste n'a pas envoyé plus que d'habitude (comparaison avec ses $ReferenceJours jours précédents). Détail par programme et par heure dans Détails › Données sorties du poste." 'srum_fenetres_vs_reference.csv, srum_METHODE.txt' }

    # Disque : octets lus / ecrits par application dans les fenetres (lecture massive avant archivage ?)
    $disk = Invoke-Vql "SELECT TimeStamp, srum_lookup_id(file='''$tmp''', id=AppId) AS App, ForegroundBytesRead + BackgroundBytesRead AS Lu, ForegroundBytesWritten + BackgroundBytesWritten AS Ecrit FROM parse_ese(file='''$tmp''', table='{D10CA2FE-6FCF-4F6D-848E-B2E99266FA89}')"
    $dk = @(foreach ($r in $disk) { $d = To-Local $r.TimeStamp; if ($d) { [pscustomobject]@{ Releve = $d; App = $r.App; Lu = [double]$r.Lu; Ecrit = [double]$r.Ecrit } } })
    $dref = @{}
    foreach ($g in ($dk | Where-Object { $_.Releve -ge $refStart -and $_.Releve -lt $refEnd -and -not (& $inWin $_.Releve) } | Group-Object App)) { $dref[$g.Name] = ($g.Group | Measure-Object Lu -Maximum).Maximum }
    Out-Csv (@(foreach ($w in $script:Win) {
        $dk | Where-Object { $_.Releve -gt $w.Debut -and $_.Releve -le $w.Fin.AddMinutes(60) -and ($_.Lu -ge 1MB -or $_.Ecrit -ge 1MB) } | Sort-Object Lu -Descending | ForEach-Object {
            [pscustomobject]@{ Fenetre = $w.Id; Releve = Fmt $_.Releve; App = $_.App; LuMo = Mo $_.Lu; EcritMo = Mo $_.Ecrit; RefMaxLuMo = $(if ($dref.ContainsKey($_.App)) { Mo $dref[$_.App] } else { 'absente' })
                Ecart = $(if (-not $dref.ContainsKey($_.App)) { 'APPLI ABSENTE DE LA REFERENCE' } elseif ($_.Lu -gt $dref[$_.App]) { 'AU-DESSUS DU MAX DE REFERENCE' } else { '' }) }
        }
    })) 'srum_disque_fenetres.csv'
    Log "    SRUM : $($rows.Count) enregistrements reseau du $(Fmt $first) au $(Fmt $last)"
}

# =================================================================== 3. EXECUTIONS (Prefetch, Amcache, BAM, 4688)
$script:Exec = New-Object System.Collections.Generic.List[object]
# $ToolRx defini avant la section SRUM
Step 'Executions : Prefetch, Amcache, BAM, 4688 / Sysmon' {
    if (-not $Velo) { G 'Programmes lancés pendant l''attaque' 'NON VERIFIABLE' 'L''outil de lecture des traces de lancement (Velociraptor) manque dans le kit : refaites la clé avec le kit complet.' ''; return }
    $pfDir = C 'artefacts\prefetch'
    if (-not (Get-ChildItem -LiteralPath $pfDir -Filter '*.pf' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        $z = @(Get-FromZip '\\Windows\\Prefetch\\[^\\]+\.pf$' 5000); if ($z.Count) { $pfDir = Split-Path $z[0] -Parent }
    }
    foreach ($r in (Invoke-Vql "SELECT Executable, RunCount, LastRunTimes, ExecutablePath FROM Artifact.Windows.Forensics.Prefetch(prefetchGlobs='''$pfDir\*.pf''')" -Json)) {
        foreach ($t in @($r.LastRunTimes)) {
            $d = To-Local "$t"; if (-not $d) { continue }
            $script:Exec.Add([pscustomobject]@{ Date = $d; Source = 'Prefetch (execution)'; Programme = $r.Executable; Chemin = $r.ExecutablePath; Compte = ''; Detail = "RunCount=$($r.RunCount)"; SHA1 = '' })
        }
    }
    $am = C 'artefacts\amcache\Amcache.hve'
    if (-not (Test-Path -LiteralPath $am)) { $am = @(Get-FromZip '\\appcompat\\Programs\\Amcache\.hve$' 1) | Select-Object -First 1 }
    if ($am) {
        $tmp = Join-Path $Work 'Amcache.hve'; Copy-Item -LiteralPath $am -Destination $tmp -Force
        foreach ($r in (Invoke-Vql "SELECT Key.Mtime AS M, LowerCaseLongPath, FileId, Size, Publisher, LinkDate FROM read_reg_key(globs='/Root/InventoryApplicationFile/*', accessor='raw_reg', root=$(RegRoot $tmp))")) {
            $d = To-Local $r.M; if (-not $d -or $d -lt $Since) { continue }
            $sha1 = if ("$($r.FileId)".Length -ge 44) { "$($r.FileId)".Substring(4).ToUpper() } else { '' }
            $script:Exec.Add([pscustomobject]@{ Date = $d; Source = 'Amcache (inventaire, ~1re execution)'; Programme = (Leaf "$($r.LowerCaseLongPath)"); Chemin = $r.LowerCaseLongPath; Compte = ''; Detail = "Taille=$($r.Size) Editeur=$($r.Publisher)"; SHA1 = $sha1 })
        }
    }
    $sysH = C 'artefacts\registre\SYSTEM'
    if (-not (Test-Path -LiteralPath $sysH)) { $sysH = @(Get-FromZip '\\System32\\config\\SYSTEM$' 1) | Select-Object -First 1 }
    if ($sysH) {
        foreach ($r in (Invoke-Vql "SELECT OSPath.Components[-2] AS Sid, Name AS Binaire, timestamp(winfiletime=parse_binary(filename=Data.value, accessor='data', profile='[]', struct='int64')) AS D FROM glob(globs=['/ControlSet001/Services/bam/State/UserSettings/*/*','/ControlSet001/Services/bam/UserSettings/*/*'], accessor='raw_reg', root=$(RegRoot $sysH)) WHERE Data.type =~ 'BINARY'")) {
            $d = To-Local $r.D; if (-not $d -or $d -lt $Since) { continue }
            $script:Exec.Add([pscustomobject]@{ Date = $d; Source = 'BAM (derniere execution)'; Programme = (Leaf "$($r.Binaire)"); Chemin = $r.Binaire; Compte = SidToName $r.Sid; Detail = ''; SHA1 = '' })
        }
    }
    $p4688 = Get-Evtx 'Security' @(4688) $Since
    foreach ($e in @($p4688)) {
        $f = Get-EvFields $e
        $script:Exec.Add([pscustomobject]@{ Date = $e.TimeCreated; Source = '4688 creation de processus'; Programme = (Leaf "$($f['NewProcessName'])"); Chemin = $f['NewProcessName']; Compte = $f['SubjectUserName']; Detail = "$($f['CommandLine'])"; SHA1 = '' })
    }
    foreach ($e in @(Get-Evtx 'Microsoft-Windows-Sysmon/Operational' @(1) $Since)) {
        $f = Get-EvFields $e
        $script:Exec.Add([pscustomobject]@{ Date = $e.TimeCreated; Source = 'Sysmon 1'; Programme = (Leaf "$($f['Image'])"); Chemin = $f['Image']; Compte = $f['User']; Detail = "$($f['CommandLine'])"; SHA1 = "$($f['Hashes'])" })
    }
    $all = $script:Exec | Sort-Object Date | Select-Object @{n='Date';e={ Fmt $_.Date }}, Source, Programme, Chemin, Compte, Detail, SHA1, @{n='Fenetre';e={ WinOf $_.Date }}, @{n='OutilSensible';e={ if ("$($_.Programme) $($_.Chemin)" -match $ToolRx) { 'OUI' } }}
    Out-Csv $all 'executions_chronologie.csv'
    Out-Csv ($all | Where-Object { $_.Fenetre }) 'executions_fenetres.csv'
    Out-Csv ($all | Where-Object { $_.OutilSensible }) 'executions_outils_sensibles.csv'
    $n4688 = @($p4688).Count
    Log "    $($script:Exec.Count) traces d'execution ($n4688 evenements 4688 ; audit des processus $(if ($n4688) { 'actif' } else { 'INACTIF ou journal absent' }))"
    $inW = @($all | Where-Object { $_.Fenetre })
    G 'Programmes lancés pendant l''attaque' $(if ($inW.Count) { 'A LIRE' } else { 'RAS' }) "$(Nb $inW.Count 'lancement de programme trouvé' 'lancements de programmes trouvés') pendant l'attaque : à parcourir dans Détails › Tous les événements.$(if (-not $n4688) { ' Windows ne notait pas chaque lancement (audit 4688 inactif) : la liste peut être incomplète.' })" 'executions_fenetres.csv'
}

# =================================================================== 4. NAVIGATION WEB COMPLETE
$CatRx = [ordered]@{
    'SANTE / METIER'      = '(?i)doctolib|ameli|amelipro|espacepro\.ameli|apicrypt|mssante|monespacesante|dmp\.fr|sesam-vitale|vidal|cgm|axisante|maiia|weda|medistory|hellodoc|lifen|pharmagest|leo2|winpharma|ordoclic'
    'MESSAGERIE'          = '(?i)webmail|outlook\.(live|office)|mail\.google|gmail|mail\.yahoo|laposte\.net|mail\.ovh|ovhcloud.*mail|zimbra|roundcube|protonmail|messagerie|orange\.fr/.*mail|sfr\.fr/.*mail|free\.fr/.*(mail|imp)'
    'PARTAGE / TRANSFERT' = '(?i)mega\.(nz|io)|wetransfer|swisstransfer|smash|dropbox|drive\.google|docs\.google|onedrive|1drv\.ms|sharepoint|box\.com|pcloud|gofile|file\.io|anonfiles|transfer\.sh|temp\.sh|bashupload|sendspace|mediafire|pastebin|ghostbin|catbox|filemail|uploadfiles|limewire|rapidgator|krakenfiles|send\.vis\.ee|wormhole|tmpfiles|qu\.ax|0x0\.st'
    'OUTILS / ACCES DISTANT' = $Ind.sites_outils
}
function Cat-Url([string]$u) { foreach ($k in $CatRx.Keys) { if ($u -match $CatRx[$k]) { return $k } }; '' }
Step 'Navigation web complete (Chrome, Edge, Brave, Opera, Firefox) et telechargements' {
    if (-not $Velo) { G 'Sites web visités pendant l''attaque' 'NON VERIFIABLE' 'L''outil de lecture des historiques (Velociraptor) manque dans le kit : refaites la clé avec le kit complet.' ''; return }
    $hist = New-Object System.Collections.Generic.List[object]; $dl = New-Object System.Collections.Generic.List[object]
    $files = @(Get-ChildItem -LiteralPath (C 'utilisateurs') -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -in 'History', 'places.sqlite' -and $_.FullName -match '\\navigateurs\\' })
    foreach ($f in $files) {
        $rel = $f.FullName.Substring((C 'utilisateurs').Length + 1)
        $u = $rel.Split('\')[0]; $b = Split-Path (Split-Path $f.FullName -Parent) -Leaf
        $tmp = Join-Path $Work (('nav_{0}_{1}_{2}' -f $u, $b, $f.Name) -replace '[^\w.\-]', '_')
        Copy-Item -LiteralPath $f.FullName -Destination $tmp -Force
        if ($f.Name -eq 'History') {
            foreach ($r in (Invoke-Vql "SELECT * FROM sqlite(file='''$tmp''', query='SELECT v.visit_time AS t, u.url AS url, u.title AS title, v.transition AS tr FROM visits v JOIN urls u ON u.id = v.url')")) {
                $d = Conv-Webkit $r.t; if (-not $d -or $d -lt $Since) { continue }
                $hist.Add([pscustomobject]@{ Date = $d; Utilisateur = $u; Navigateur = $b; Url = $r.url; Titre = $r.title; Categorie = Cat-Url $r.url })
            }
            foreach ($r in (Invoke-Vql "SELECT * FROM sqlite(file='''$tmp''', query='SELECT start_time, target_path, tab_url, received_bytes, total_bytes FROM downloads')")) {
                $d = Conv-Webkit $r.start_time
                $dl.Add([pscustomobject]@{ Date = Fmt $d; Utilisateur = $u; Navigateur = $b; Fichier = $r.target_path; Url = $r.tab_url; Octets = $r.received_bytes; Fenetre = WinOf $d })
            }
        } else {
            foreach ($r in (Invoke-Vql "SELECT * FROM sqlite(file='''$tmp''', query='SELECT v.visit_date AS t, p.url AS url, p.title AS title FROM moz_historyvisits v JOIN moz_places p ON p.id = v.place_id')")) {
                $d = Conv-UnixUs $r.t; if (-not $d -or $d -lt $Since) { continue }
                $hist.Add([pscustomobject]@{ Date = $d; Utilisateur = $u; Navigateur = $b; Url = $r.url; Titre = $r.title; Categorie = Cat-Url $r.url })
            }
        }
    }
    $rows = $hist | Sort-Object Date | Select-Object @{n='Date';e={ Fmt $_.Date }}, Utilisateur, Navigateur, Categorie, Url, Titre, @{n='Fenetre';e={ WinOf $_.Date }}
    Out-Csv $rows 'navigation_complete.csv'
    Out-Csv ($rows | Where-Object { $_.Fenetre }) 'navigation_fenetres.csv'
    Out-Csv ($rows | Where-Object { $_.Categorie }) 'navigation_sites_sensibles.csv'
    Out-Csv ($dl | Sort-Object Date) 'telechargements.csv'
    $inW = @($rows | Where-Object { $_.Fenetre }); $inWs = @($inW | Where-Object { $_.Categorie -in 'SANTE / METIER', 'MESSAGERIE', 'PARTAGE / TRANSFERT' })
    Log "    $($hist.Count) visites ($($files.Count) historiques), $($inW.Count) dans les fenetres dont $($inWs.Count) sur des sites sante / messagerie / partage"
    $prof = ($files | ForEach-Object { $_.FullName.Substring((C 'utilisateurs').Length + 1).Split('\')[0] } | Select-Object -Unique) -join ', '
    G 'Sites web visités pendant l''attaque (Doctolib, Ameli, messagerie, partage de fichiers)' $(if ($inWs.Count) { 'INDICE' } elseif ($inW.Count) { 'A LIRE' } else { 'RAS' }) "$(Nb $inW.Count 'page visitée' 'pages visitées') pendant l'attaque, dont $($inWs.Count) sur un site de santé, de messagerie ou de partage de fichiers (où un attaquant peut consulter ou envoyer des données). Historiques lus : $prof." 'navigation_fenetres.csv, navigation_sites_sensibles.csv'
}

# =================================================================== 5. ACCES AUX FICHIERS : LNK, JUMP LISTS, RECENTDOCS, SHELLBAGS, \\tsclient
$script:Acc = New-Object System.Collections.Generic.List[object]
$DataRx = '(?i)Axilog|AXI_DATABASE|AxiSoftware\\Database|\.fdb\b|\.fdp\b|\.gdb\b|\\HNDB\\|Donn[e\u00e9]es? patients?'
$TsRx   = '(?i)tsclient'
Step 'Acces aux fichiers : LNK, Jump Lists, RecentDocs, ShellBags (redirection \\tsclient, donnees metier)' {
    if (-not $Velo) { G 'Fichiers copiés vers le PC de l''attaquant (bureau à distance)' 'NON VERIFIABLE' 'L''outil de lecture des fichiers ouverts (Velociraptor) manque dans le kit : refaites la clé avec le kit complet.' ''; return }
    $users = @(Get-ChildItem -LiteralPath (C 'utilisateurs') -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    function Add-Acc($u, $src, $path, $d1, $lbl1, $d2, $lbl2) {
        $p = "$path"
        $script:Acc.Add([pscustomobject]@{ Utilisateur = $u; Source = $src; Chemin = $p; Date1 = Fmt $d1; Date1Type = $lbl1; Date2 = Fmt $d2; Date2Type = $lbl2
            Fenetre = ((@((WinOf $d1), (WinOf $d2)) | Where-Object { $_ } | Select-Object -Unique) -join ',')
            TSCLIENT = $(if ($p -match $TsRx) { 'OUI' }); DONNEES_METIER = $(if ($p -match $DataRx) { 'OUI' }); RESEAU = $(if ($p -match '^\\\\') { 'OUI' }) })
    }
    $missingHives = @()
    foreach ($u in $users) {
        $ud = C "utilisateurs\$u"
        $rec = Join-Path $ud 'recent'
        if (Test-Path -LiteralPath $rec) {
            foreach ($r in (Invoke-Vql "SELECT SourceFile.OSPath AS F, SourceFile.Mtime AS M, LinkTarget.LinkTarget AS Cible, StringData.TargetPath AS TP, StringData.RelativePath AS RP, StringData.Arguments AS Args, ShellLinkHeader.CreationTime AS TC, ShellLinkHeader.AccessTime AS TA FROM Artifact.Windows.Forensics.Lnk(TargetGlob='''$rec\*.lnk''')" -Json)) {
                $cible = @($r.Cible, $r.TP, $r.RP) | Where-Object { $_ } | Select-Object -First 1
                Add-Acc $u 'LNK (Recent)' "$cible $(if ($r.Args) { "[$($r.Args)]" })" (To-Local $r.M) 'lnk modifie (dernier acces)' (To-Local $r.TA) 'cible : acces'
            }
            foreach ($r in (Invoke-Vql "SELECT Application, LinkTarget, CreationTime, AccessTime, WriteTime FROM Artifact.Windows.Forensics.JumpLists(Globs='''$rec\AutomaticDestinations\*''')" -Json)) {
                Add-Acc $u "Jump List ($($r.Application))" $r.LinkTarget (To-Local $r.AccessTime) 'cible : acces' (To-Local $r.CreationTime) 'cible : creation'
            }
        }
        $nt = Join-Path $ud 'registre\NTUSER.DAT'; $uc = Join-Path $ud 'registre\UsrClass.dat'
        if (-not (Test-Path -LiteralPath $nt)) { $nt = @(Get-FromZip ("\\Users\\" + [regex]::Escape($u) + "\\NTUSER\.DAT$") 1) | Select-Object -First 1 }
        if (-not $uc -or -not (Test-Path -LiteralPath $uc)) { $uc = @(Get-FromZip ("\\Users\\" + [regex]::Escape($u) + "\\AppData\\Local\\Microsoft\\Windows\\UsrClass\.dat$") 1) | Select-Object -First 1 }
        if (-not $nt) { $missingHives += $u }
        if ($nt) {
            $t = Join-Path $Work "NTUSER_$u.DAT"; Copy-Item -LiteralPath $nt -Destination $t -Force
            foreach ($r in (Invoke-Vql "SELECT LastWriteTime, Type, MruEntries FROM Artifact.Windows.Registry.RecentDocs(HiveGlob='''$t''')" -Json)) {
                $i = 0
                foreach ($m in @($r.MruEntries)) { $i++; Add-Acc $u "RecentDocs ($($r.Type))" ("$m" -replace '^\d+ := ', '') $(if ($i -eq 1) { To-Local $r.LastWriteTime }) $(if ($i -eq 1) { 'cle modifiee (element le plus recent)' }) $null '' }
            }
            foreach ($k in 'TypedPaths', 'RunMRU') {
                foreach ($r in (Invoke-Vql "SELECT Name, Data.value AS V, Mtime FROM glob(globs='/Software/Microsoft/Windows/CurrentVersion/Explorer/$k/*', accessor='raw_reg', root=$(RegRoot $t))")) {
                    if ($r.Name -ne 'MRUList') { Add-Acc $u $k $r.V (To-Local $r.Mtime) 'cle modifiee' $null '' }
                }
            }
            foreach ($r in (Invoke-Vql "SELECT FullPath, ModTime FROM Artifact.Windows.Forensics.Shellbags(SearchSpecs=dict(HiveGlob='''$t''', KeyGlob='''\Software\Microsoft\Windows\Shell\BagMRU\**'''))")) { Add-Acc $u 'ShellBags (NTUSER)' $r.FullPath (To-Local $r.ModTime) 'cle modifiee' $null '' }
        }
        if ($uc) {
            $t = Join-Path $Work "UsrClass_$u.dat"; Copy-Item -LiteralPath $uc -Destination $t -Force
            foreach ($r in (Invoke-Vql "SELECT FullPath, ModTime FROM Artifact.Windows.Forensics.Shellbags(SearchSpecs=dict(HiveGlob='''$t''', KeyGlob='''\Local Settings\Software\Microsoft\Windows\Shell\BagMRU\**'''))")) { Add-Acc $u 'ShellBags (UsrClass)' $r.FullPath (To-Local $r.ModTime) 'cle modifiee' $null '' }
        }
    }
    # Recherche brute (ASCII et UTF-16) dans les ruches, LNK et Jump Lists : complete le parsing structure
    $raw = New-Object System.Collections.Generic.List[object]
    $l1 = [Text.Encoding]::GetEncoding(28591)
    $targets = @(Get-ChildItem -LiteralPath (C 'utilisateurs') -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 64MB -and $_.FullName -match '\\(registre|recent)\\' }) +
               @(Get-ChildItem -LiteralPath $Work -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(NTUSER|UsrClass)_' })
    foreach ($f in $targets) {
        $bytes = [IO.File]::ReadAllBytes($f.FullName)
        $texts = @($l1.GetString($bytes), [Text.Encoding]::Unicode.GetString($bytes))
        if ($bytes.Length -gt 1) { $texts += [Text.Encoding]::Unicode.GetString($bytes, 1, $bytes.Length - 1) }
        foreach ($tx in $texts) {
            foreach ($m in [regex]::Matches($tx, '(?i)[\x20-\x7E\u00C0-\u00FF]{0,100}(tsclient|axilog|axi_database)[\x20-\x7E\u00C0-\u00FF]{0,140}')) {
                $raw.Add([pscustomobject]@{ Fichier = $f.FullName.Replace($Collecte, '<collecte>').Replace($Work, '<extraits>'); Motif = $m.Groups[1].Value.ToLower(); Contexte = $m.Value.Trim() })
            }
        }
    }
    $raw = @($raw | Sort-Object Fichier, Contexte -Unique)
    Out-Csv $raw 'recherche_brute_tsclient_axilog.csv'
    $rows = @($script:Acc | Sort-Object Utilisateur, Date1)
    Out-Csv $rows 'acces_fichiers_lnk_jumplists_shellbags.csv'
    $ts = @($rows | Where-Object { $_.TSCLIENT }) ; $tsRaw = @($raw | Where-Object { $_.Motif -eq 'tsclient' })
    $dm = @($rows | Where-Object { $_.DONNEES_METIER }); $dmW = @($dm | Where-Object { $_.Fenetre })
    Out-Csv $dm 'acces_donnees_metier.csv'
    Log "    $($rows.Count) traces d'acces, $($ts.Count) + $($tsRaw.Count) (brut) \\tsclient, $($dm.Count) donnees metier dont $($dmW.Count) dans les fenetres"
    if ($missingHives.Count) { Log "    [!] Ruche NTUSER absente pour : $($missingHives -join ', ') (RecentDocs / ShellBags non analyses pour ces comptes)" }
    $lim = if ($missingHives.Count) { " ; ruche absente pour $($missingHives -join ', ')" } else { '' }
    G 'Fichiers copiés vers le PC de l''attaquant (bureau à distance)' $(if ($ts.Count -or $tsRaw.Count) { 'INDICE' } else { 'RAS' }) "$(if ($ts.Count -or $tsRaw.Count) { "$(Nb ($ts.Count + $tsRaw.Count) 'trace' 'traces') d'accès aux disques de l'ordinateur distant (\\tsclient) : en bureau à distance, c'est par là qu'on copie des fichiers vers son propre PC." } else { "Aucune trace d'accès aux disques de l'ordinateur distant (\\tsclient), le chemin habituel pour copier des fichiers en bureau à distance." })$lim" 'acces_fichiers_lnk_jumplists_shellbags.csv, recherche_brute_tsclient_axilog.csv'
    G 'Données du cabinet ouvertes pendant l''attaque (logiciel métier, base patients)' $(if ($dmW.Count) { 'INDICE' } elseif ($dm.Count) { 'A LIRE' } else { 'RAS' }) "$(Nb $dm.Count 'trace d''ouverture' 'traces d''ouverture') des données du cabinet, dont $($dmW.Count) pendant l'attaque.$lim" 'acces_donnees_metier.csv'
}

Step 'Parametres de redirection RDP (lecteurs, presse-papier) et usage de rdpclip' {
    $lines = New-Object System.Collections.Generic.List[string]
    $sysH = C 'artefacts\registre\SYSTEM'; $swH = C 'artefacts\registre\SOFTWARE'
    if (-not (Test-Path -LiteralPath $swH)) { $swH = @(Get-FromZip '\\System32\\config\\SOFTWARE$' 1) | Select-Object -First 1 }
    $vals = @{}
    if ($Velo -and (Test-Path -LiteralPath "$sysH")) {
        foreach ($r in (Invoke-Vql "SELECT Name, Data.value AS V FROM glob(globs='/ControlSet001/Control/Terminal Server/WinStations/RDP-Tcp/fDisable*', accessor='raw_reg', root=$(RegRoot $sysH))")) { $vals["RDP-Tcp\$($r.Name)"] = $r.V }
    }
    if ($Velo -and $swH -and (Test-Path -LiteralPath "$swH")) {
        foreach ($r in (Invoke-Vql "SELECT Name, Data.value AS V FROM glob(globs='/Policies/Microsoft/Windows NT/Terminal Services/fDisable*', accessor='raw_reg', root=$(RegRoot $swH))")) { $vals["Strategie\$($r.Name)"] = $r.V }
    }
    $lbl = [ordered]@{ fDisableCdm = 'Redirection des lecteurs (\\tsclient)'; fDisableClip = 'Presse-papier'; fDisableCcm = 'Ports COM'; fDisableLPT = 'Ports LPT'; fDisablePNPRedir = 'Peripheriques PnP / USB'; fDisableCpm = 'Imprimantes' }
    $lines.Add('Valeur 0 ou absente = redirection AUTORISEE ; 1 = interdite. La strategie (GPO) prime sur RDP-Tcp.')
    $driveOk = $true; $clipOk = $true
    foreach ($k in $lbl.Keys) {
        $pol = $vals["Strategie\$k"]; $tcp = $vals["RDP-Tcp\$k"]
        $eff = if ("$pol" -ne '') { $pol } else { $tcp }
        if ($k -eq 'fDisableCdm' -and "$eff" -eq '1') { $driveOk = $false }
        if ($k -eq 'fDisableClip' -and "$eff" -eq '1') { $clipOk = $false }
        $lines.Add(('{0,-40} strategie={1,-6} RDP-Tcp={2,-6} => {3}' -f $lbl[$k], $(if ("$pol" -ne '') { $pol } else { '-' }), $(if ("$tcp" -ne '') { $tcp } else { '-' }), $(if ("$eff" -eq '1') { 'interdite' } else { 'AUTORISEE' })))
    }
    $clip = @($script:Exec | Where-Object { $_.Programme -match '(?i)^rdpclip' })
    $clipW = @($clip | Where-Object { WinOf $_.Date })
    $lines.Add('')
    $lines.Add("rdpclip.exe (presse-papier RDP) : $($clip.Count) execution(s) connue(s), dont $($clipW.Count) dans les fenetres : $((($clipW | ForEach-Object { Fmt $_.Date }) -join ', '))")
    $pnp = Get-Evtx 'Microsoft-Windows-TerminalServices-PnPDevices/Admin' @(20001, 20002, 20003, 36, 37) $Since
    $lines.Add("Journal TerminalServices-PnPDevices : $(if (-not (Find-Evtx 'Microsoft-Windows-TerminalServices-PnPDevices/Admin')) { 'absent de la collecte' } else { "$(@($pnp).Count) evenement(s)" })")
    $lines | Out-File (P 'rdp_redirections.txt') -Encoding utf8
    if (-not $vals.Count) { G 'Copier-coller vers le PC de l''attaquant (bureau à distance)' 'NON VERIFIABLE' 'La configuration de Windows (ruches SYSTEM et SOFTWARE) manque dans la collecte.' '' }
    else {
        G 'Copier-coller vers le PC de l''attaquant (bureau à distance)' $(if ($clipW.Count) { 'A LIRE' } else { 'RAS' }) "Le copier-coller en bureau à distance était $(if ($clipOk) { 'autorisé' } else { 'interdit' }). Le programme qui le permet (rdpclip.exe) a tourné $($clipW.Count) fois pendant l'attaque. Windows ne garde pas ce qui a été copié." 'rdp_redirections.txt'
        if (-not $driveOk) { G 'Fichiers copiés vers le PC de l''attaquant (bureau à distance)' 'RAS' 'Windows interdisait l''accès aux disques de l''ordinateur distant pendant le bureau à distance.' 'rdp_redirections.txt' }
    }
}

# =================================================================== 6. $MFT ET JOURNAL USN : FICHIERS CREES / MODIFIES PENDANT LES FENETRES
Step 'Journal USN et $MFT : fichiers crees ou modifies pendant les fenetres (archives, profils)' {
    $arcRx = '(?i)\.(zip|7z|rar|tar|gz|tgz|cab|iso|vhdx?|bak|pst|sql|csv|xlsx?|pdf)$'
    $ransomRx = $script:RxRanconNom.ToString()
    foreach ($x in (Get-Chiffrement)) { $ransomRx += '|' + [regex]::Escape($x.Extension) + '$' }
    # USN (fsutil)
    $usnFiles = @(Get-ChildItem -LiteralPath (C 'artefacts') -Filter 'usn_journal_*.csv' -ErrorAction SilentlyContinue)
    $cov = New-Object System.Collections.Generic.List[string]
    $usnRows = New-Object System.Collections.Generic.List[object]
    foreach ($uf in $usnFiles) {
        $rd = New-Object IO.StreamReader($uf.FullName, [Text.Encoding]::GetEncoding(850))
        $min = $null; $max = $null; $n = 0; $skipped = 0
        $lineRx = New-Object Text.RegularExpressions.Regex('^\d+,"((?:[^"]|"")*)",\d+,0x[0-9a-fA-F]+,"([^"]*)","([^"]+)"', 'Compiled')
        while ($null -ne ($l = $rd.ReadLine())) {
            $mm = $lineRx.Match($l); if (-not $mm.Success) { continue }
            $d = [datetime]::MinValue
            if (-not [datetime]::TryParseExact($mm.Groups[3].Value, 'dd/MM/yyyy HH:mm:ss', $Inv, [Globalization.DateTimeStyles]::None, [ref]$d)) { $d = Parse-Date $mm.Groups[3].Value; if (-not $d) { continue } }
            $n++; if (-not $min -or $d -lt $min) { $min = $d }; if (-not $max -or $d -gt $max) { $max = $d }
            $w = WinOf $d
            if ($w) {
                $name = $mm.Groups[1].Value -replace '""', '"'
                if ($name -match $ransomRx) { $skipped++; continue }
                if ($usnRows.Count -lt 200000) { $usnRows.Add([pscustomobject]@{ Date = Fmt $d; Volume = ($uf.BaseName -replace 'usn_journal_', ''); Fichier = $name; Raison = $mm.Groups[2].Value; Fenetre = $w; Archive = $(if ($name -match $arcRx) { 'OUI' }) }) }
            }
        }
        $rd.Close()
        $cov.Add("$($uf.Name) : $n entrees du $(Fmt $min) au $(Fmt $max)$(if ($skipped) { " ; $skipped entrees de fichiers chiffres ignorees" })")
    }
    Out-Csv $usnRows 'usn_fenetres.csv'
    $winStart = if ($script:Win.Count) { ($script:Win | Measure-Object Debut -Minimum).Minimum } else { $null }

    # $MFT du conteneur Velociraptor : horodatages de creation / modification / acces des fichiers des profils et des donnees
    $mftRows = @()
    if (-not $SansMFT -and $script:Zip -and $Velo -and $script:Win.Count) {
        $mftEntry = $script:Zip.Entries | Where-Object { $_.FullName -match '/\$MFT$' -and $_.FullName -match 'C%3A' } | Select-Object -First 1
        if ($mftEntry) {
            $mft = Join-Path $Work 'MFT_C'   # jamais dans %TEMP% : ne pas ecrire sur le disque du poste analyse
            Log "    Extraction de la `$MFT ($([math]::Round($mftEntry.Length / 1MB)) Mo) vers $mft..."
            try {
                [IO.Compression.ZipFileExtensions]::ExtractToFile($mftEntry, $mft, $true)
                $conds = ($script:Win | ForEach-Object {
                    $a = $_.Debut.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); $b = $_.Fin.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                    foreach ($fld in 'Created0x10', 'Created0x30', 'LastModified0x10', 'LastAccess0x10') { "($fld > timestamp(string='$a') AND $fld < timestamp(string='$b'))" }
                }) -join ' OR '
                $q = "SELECT OSPath, FileSize, IsDir, InUse, Created0x10, Created0x30, LastModified0x10, LastAccess0x10 FROM parse_mft(filename='''$mft''', accessor='file') WHERE ($conds) AND OSPath =~ '(?i)^(Users|ProgramData|Temp|PerfLogs|Public)\\\\'"
                $mftRows = @(Invoke-Vql $q | ForEach-Object {
                    $p = "$($_.OSPath)"
                    if ($p -match $ransomRx) { return }
                    $c1 = To-Local $_.Created0x10; $m1 = To-Local $_.LastModified0x10; $a1 = To-Local $_.LastAccess0x10
                    [pscustomobject]@{ Chemin = $p; Taille = $_.FileSize; Dossier = $_.IsDir; EnUsage = $_.InUse; Creation = Fmt $c1; CreationFN = Fmt (To-Local $_.Created0x30); Modification = Fmt $m1; Acces = Fmt $a1
                        Fenetre = ((@((WinOf $c1), (WinOf $m1), (WinOf $a1)) | Where-Object { $_ } | Select-Object -Unique) -join ',')
                        Archive = $(if ($p -match $arcRx) { 'OUI' }); DONNEES_METIER = $(if ($p -match $DataRx) { 'OUI' }); Supprime = $(if ("$($_.InUse)" -eq 'false') { 'OUI' }) }
                })
                $cov.Add("`$MFT (conteneur Velociraptor) : $($mftRows.Count) fichier(s) des profils / ProgramData horodate(s) dans les fenetres (fichiers chiffres exclus)")
            } catch { Log "    [!] `$MFT : $($_.Exception.Message)" }
            finally { Remove-Item -LiteralPath $mft -Force -ErrorAction SilentlyContinue }
        }
    }
    Out-Csv $mftRows 'mft_fenetres.csv'
    $cov | Out-File (P 'usn_mft_couverture.txt') -Encoding utf8
    $arcs = @($usnRows | Where-Object { $_.Archive }) + @($mftRows | Where-Object { $_.Archive })
    $covers = $false
    foreach ($c in $cov) { if ($c -match 'du (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)' -and $winStart -and ([datetime]$matches[1]) -le $winStart) { $covers = $true } }
    if ($mftRows.Count) { $covers = $true }
    $msg = ($cov -join ' | ')
    if (-not $covers) { G 'Fichiers compressés (.zip, .7z, .rar) créés pendant l''attaque' 'NON VERIFIABLE' "Le journal des fichiers du disque ne remonte pas jusqu'à l'attaque ($msg). Relancez l'analyse avec « Analyse complète » pour lire l'index du disque (`$MFT)." 'usn_mft_couverture.txt' }
    else { G 'Fichiers compressés (.zip, .7z, .rar) créés pendant l''attaque' $(if ($arcs.Count) { 'INDICE' } else { 'A LIRE' }) "$(Nb $arcs.Count 'archive ou export créé ou modifié' 'archives ou exports créés ou modifiés') pendant l'attaque. Un attaquant regroupe souvent les fichiers dans une archive avant de les envoyer. $msg" 'mft_fenetres.csv, usn_fenetres.csv' }
}

# =================================================================== 7. OUTILS D'ACCES DISTANT
Step "Outils d'acces distant (NetBird, Splashtop, TSplus, Datto RMM, AnyDesk...) : installation, executions, journaux" {
    $rx = '(?i)netbird|wiretrustee|splashtop|tsplus|centrastage|datto|aemagent|anydesk|teamviewer|rustdesk|screenconnect|connectwise|atera|supremo|ammyy|vnc|zerotier|tailscale|wireguard|ngrok|cloudflared|parsec|meshagent|action1|kaseya|n-able|logmein|gotoassist|dwagent|remotepc|chrome remote'
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($s in (Read-Csv (C 'systeme\logiciels_installes.csv') | Where-Object { "$($_.DisplayName) $($_.Publisher) $($_.InstallLocation)" -match $rx })) {
        $rows.Add([pscustomobject]@{ Outil = $s.DisplayName; Source = 'Logiciel installe'; Date = $(if ($s.CleModifiee) { $s.CleModifiee } else { $s.InstallDate }); Detail = "Version $($s.DisplayVersion) - $($s.InstallLocation)" })
    }
    foreach ($s in (Read-Csv (C 'persistance\services.csv') | Where-Object { "$($_.Name) $($_.DisplayName) $($_.PathName)" -match $rx })) {
        $rows.Add([pscustomobject]@{ Outil = $s.DisplayName; Source = 'Service'; Date = ''; Detail = "$($s.State) / $($s.StartMode) / $($s.StartName) - $($s.PathName)" })
    }
    foreach ($s in (Read-Csv (C 'systeme\installations_desinstallations_msi.csv') | Where-Object { $_.Message -match $rx })) {
        $rows.Add([pscustomobject]@{ Outil = ([regex]::Match($s.Message, $rx)).Value; Source = "MSI $($s.Action)"; Date = $s.Date; Detail = "par $($s.Utilisateur) : $($s.Message)" })
    }
    foreach ($e in @($script:Exec | Where-Object { "$($_.Programme) $($_.Chemin)" -match $rx })) {
        $rows.Add([pscustomobject]@{ Outil = $e.Programme; Source = $e.Source; Date = Fmt $e.Date; Detail = "$($e.Chemin) $($e.Compte)" })
    }
    foreach ($e in (Read-Csv (C 'evenements\resume_evenements_cles.csv') | Where-Object { $_.EventID -eq '7045' -and $_.Message -match $rx })) {
        $rows.Add([pscustomobject]@{ Outil = ([regex]::Match($e.Message, $rx)).Value; Source = '7045 service installe'; Date = $e.Date; Detail = $e.Message })
    }
    Out-Csv ($rows | Sort-Object Date) 'outils_distants_inventaire.csv'

    # Journaux propres aux outils : collecte v2.2 (outils_distants\) puis conteneur Velociraptor
    $logs = @(Get-ChildItem -LiteralPath (C 'outils_distants'), (C 'artefacts\acces_distant') -Recurse -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    $logs += @(Get-FromZip '(?i)(Splashtop|Netbird|TSplus|CentraStage|AnyDesk|TeamViewer|RustDesk|ScreenConnect).*\.(log|txt|json|sqlite3?|trace)$' 300)
    $dayPats = @(foreach ($w in $script:Win) { for ($d = $w.Debut.Date; $d -le $w.Fin.Date; $d = $d.AddDays(1)) { $d.ToString('yyyy-MM-dd'); $d.ToString('yyyy/MM/dd'); $d.ToString('dd/MM/yyyy'); $d.ToString('MM/dd/yyyy'); $d.ToString('yyyyMMdd') } }) | Select-Object -Unique
    $hits = New-Object System.Collections.Generic.List[string]
    $sumLogs = New-Object System.Collections.Generic.List[object]
    foreach ($lf in ($logs | Select-Object -Unique)) {
        if ($lf -match '\.(sqlite3?)$' -or (Get-Item -LiteralPath $lf).Length -gt 50MB) { $sumLogs.Add([pscustomobject]@{ Journal = $lf; Lignes = ''; LignesFenetres = '(non lu : base ou trop gros)' }); continue }
        $txt = @(Get-Content -LiteralPath $lf -ErrorAction SilentlyContinue)
        $m = @($txt | Where-Object { $l = $_; @($dayPats | Where-Object { $l.Contains($_) }).Count -gt 0 })
        $sumLogs.Add([pscustomobject]@{ Journal = $lf.Replace($Work, '<extraits>').Replace($Collecte, '<collecte>'); Lignes = $txt.Count; LignesFenetres = $m.Count })
        if ($m.Count) { $hits.Add("===== $lf ($($m.Count) lignes aux dates des fenetres)"); $m | Select-Object -First 2000 | ForEach-Object { $hits.Add($_) } }
    }
    Out-Csv $sumLogs 'outils_distants_journaux.csv'
    $hits | Out-File (P 'outils_distants_lignes_fenetres.txt') -Encoding utf8
    # Journaux d'evenements Splashtop
    $sp = New-Object System.Collections.Generic.List[object]
    foreach ($ch in 'Splashtop-Splashtop Streamer-Remote Session/Operational', 'Splashtop-Splashtop Streamer-Status/Operational') {
        $p = Find-Evtx $ch
        if ($p) { try { Get-WinEvent -Path $p -ErrorAction Stop | Where-Object { $_.TimeCreated -ge $Since } | ForEach-Object { $sp.Add([pscustomobject]@{ Date = Fmt $_.TimeCreated; Journal = $ch; EventID = $_.Id; Donnees = ((Get-EvFields $_).GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ; '; Fenetre = WinOf $_.TimeCreated }) } } catch {} }
    }
    Out-Csv $sp 'splashtop_evenements.csv'
    $nb = @(Get-ChildItem -LiteralPath (C 'outils_distants') -Filter 'netbird_status*.txt' -ErrorAction SilentlyContinue)
    $nbLog = @($logs | Where-Object { $_ -match '(?i)netbird' -and $_ -match '\.log$' })
    $tools = ($rows | ForEach-Object { ([regex]::Match("$($_.Outil) $($_.Detail)", $rx)).Value.ToLower() } | Where-Object { $_ } | Select-Object -Unique) -join ', '
    Log "    Outils detectes : $tools ; $($logs.Count) journal(aux) d'outils, $($hits.Count) ligne(s) aux dates des fenetres"
    G 'Logiciels de prise en main à distance (AnyDesk, TeamViewer, Splashtop…)' $(if ($hits.Count -or @($sp | Where-Object { $_.Fenetre }).Count) { 'A LIRE' } elseif ($logs.Count) { 'RAS' } else { 'NON VERIFIABLE' }) "Installés : $tools. $(Nb $logs.Count 'journal lu' 'journaux lus'), $(Nb $hits.Count 'ligne datée' 'lignes datées') pendant l'attaque, $(Nb (@($sp | Where-Object { $_.Fenetre }).Count) 'événement Splashtop' 'événements Splashtop') pendant l'attaque." 'outils_distants_inventaire.csv, outils_distants_lignes_fenetres.txt'
    if ($tools -match 'netbird') {
        G 'Réseau privé NetBird : machines reliées au poste' $(if ($nb.Count) { 'A LIRE' } else { 'A FAIRE' }) $(if ($nb.Count) { "Liste des machines reliées : $($nb[0].Name). Vérifiez chacune et à qui elle appartient." } else { "Machines reliées inconnues (journaux NetBird $(if ($nbLog.Count) { 'présents' } else { 'non collectés' })). Regardez la console d'administration NetBird du compte qui l'a installé." }) 'outils_distants\'
    }
}

# =================================================================== 8. SOURCES DEJA COLLECTEES : PARE-FEU, BITS, USB, SMB, DNS
Step 'Sources collectees : journal du pare-feu, BITS, USB, SMBServer, DNS-Client' {
    $ver = New-Object System.Collections.Generic.List[object]
    function V($src, $etat, $couv, $nbW, $constat, $fic) { $ver.Add([pscustomobject]@{ Source = $src; Etat = $etat; Couverture = $couv; EvenementsFenetres = $nbW; Constat = $constat; Fichier = $fic }) }

    # Pare-feu Windows : journal texte pfirewall.log
    $prof = if (Test-Path -LiteralPath (C 'reseau\parefeu_profils.txt')) { Get-Content -LiteralPath (C 'reseau\parefeu_profils.txt') -Raw -Encoding UTF8 } else { '' }
    $allowLog = @([regex]::Matches($prof, 'LogAllowedConnections\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
    $dropLog  = @([regex]::Matches($prof, 'LogDroppedConnections\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
    $isOn = { param($v) -not ($v -match '(?i)sactiv|disable') -and ($v -match '(?i)activ|enable') }
    $aOn = @($allowLog | Where-Object { & $isOn $_ }).Count; $dOn = @($dropLog | Where-Object { & $isOn $_ }).Count
    $fwFiles = @(Get-ChildItem -LiteralPath (C 'connexions\parefeu_journal') -File -ErrorAction SilentlyContinue)
    $fwRows = New-Object System.Collections.Generic.List[object]
    foreach ($f in $fwFiles) {
        foreach ($l in (Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue)) {
            if ($l -match '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) .* (SEND|RECEIVE)') {
                $d = [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss', $Inv)
                $fwRows.Add([pscustomobject]@{ Date = $matches[1]; Action = $matches[2]; Proto = $matches[3]; IPsrc = $matches[4]; IPdst = $matches[5]; PortSrc = $matches[6]; PortDst = $matches[7]; Taille = $matches[8]; Sens = $matches[10]; TypeIPdst = Get-IpType $matches[5]; Fenetre = WinOf $d })
            }
        }
    }
    Out-Csv ($fwRows | Where-Object { $_.Fenetre }) 'parefeu_fenetres.csv'
    $fwState = if (-not $prof) { 'réglages du pare-feu non collectés' } elseif ($aOn -eq 0 -and $dOn -eq 0) { 'Le pare-feu ne notait aucune connexion (journal désactivé, réglage par défaut de Windows)' } else { "Le pare-feu notait les connexions autorisées sur $aOn profils sur 3 et les connexions bloquées sur $dOn sur 3" }
    V 'Journal du pare-feu de Windows (connexions du poste)' $fwState $(if ($fwRows.Count) { "du $($fwRows[0].Date) au $($fwRows[-1].Date)" } else { 'journal absent ou vide' }) @($fwRows | Where-Object { $_.Fenetre }).Count $(if ($aOn -eq 0) { 'Le poste ne garde donc aucune trace de ses connexions vers Internet : seule la box internet peut dire où des données ont été envoyées.' } else { 'Les envois vers Internet pendant l''attaque sont listés dans parefeu_fenetres.csv.' }) 'parefeu_fenetres.csv'
    $fwEv = Get-Evtx 'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall' @(2004, 2005, 2006, 2033, 2052, 2097, 2099) $Since
    V 'Règles du pare-feu modifiées' $(if (-not (Find-Evtx 'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall')) { 'journal absent' } else { 'journal présent' }) '' @($fwEv | Where-Object { WinOf $_.TimeCreated }).Count "$(Nb (@($fwEv).Count) 'modification des règles' 'modifications des règles') du pare-feu sur la période (un attaquant peut ouvrir un accès)." 'evenements_fenetres.csv'

    # BITS
    $bitsTxt = if (Test-Path -LiteralPath (C 'persistance\bits_jobs.txt')) { Get-Content -LiteralPath (C 'persistance\bits_jobs.txt') -Raw -Encoding UTF8 } else { '' }
    $jobs = @([regex]::Matches($bitsTxt, '(?ms)^JobId\s*:.*?(?=^JobId\s*:|\z)') | ForEach-Object {
        $b = $_.Value
        [pscustomobject]@{ Nom = ([regex]::Match($b, 'DisplayName\s*:\s*(.*)')).Groups[1].Value.Trim(); Type = ([regex]::Match($b, 'TransferType\s*:\s*(.*)')).Groups[1].Value.Trim(); Etat = ([regex]::Match($b, 'JobState\s*:\s*(.*)')).Groups[1].Value.Trim()
            Proprietaire = ([regex]::Match($b, 'OwnerAccount\s*:\s*(.*)')).Groups[1].Value.Trim(); Creation = ([regex]::Match($b, 'CreationTime\s*:\s*(.*)')).Groups[1].Value.Trim(); Octets = ([regex]::Match($b, 'BytesTransferred\s*:\s*(.*)')).Groups[1].Value.Trim()
            Url = (([regex]::Match($b, 'FileList\s*:\s*\{([^}\s]*)')).Groups[1].Value -replace '\?.*$', '') }
    })
    Out-Csv $jobs 'bits_taches.csv'
    $bev = Get-Evtx 'Microsoft-Windows-Bits-Client/Operational' @(3, 59, 60, 61) $Since
    $brow = @(foreach ($e in @($bev)) { $f = Get-EvFields $e; [pscustomobject]@{ Date = Fmt $e.TimeCreated; EventID = $e.Id; Tache = $f['name']; Url = $f['url']; Octets = $f['bytesTransferred']; Fenetre = WinOf $e.TimeCreated } })
    Out-Csv $brow 'bits_evenements.csv'
    $up = @($jobs | Where-Object { $_.Type -match 'Upload' })
    $bnonms = @($brow | Where-Object { $_.Url -and $_.Url -notmatch '(?i)microsoft\.com|windowsupdate|msedge|office|bing\.com|live\.com|skype|xbox|msn\.com|google(apis)?\.com|gvt1\.com' })
    V 'Transferts en arrière-plan de Windows (BITS)' $(if ($bitsTxt) { "$(Nb $jobs.Count 'transfert en cours' 'transferts en cours'), dont $($up.Count) en envoi" } else { 'non collecté' }) $(if (-not (Find-Evtx 'Microsoft-Windows-Bits-Client/Operational')) { 'journal absent' } else { Nb (@($bev).Count) 'événement' 'événements' }) @($brow | Where-Object { $_.Fenetre }).Count "$(Nb $bnonms.Count 'transfert' 'transferts') vers un autre site que Microsoft ou Google (un attaquant peut s'en servir pour envoyer des fichiers discrètement)." 'bits_taches.csv, bits_evenements.csv'

    # USB
    $usb = Read-Csv (C 'artefacts\usb_stockage.csv'); $usbDet = Read-Csv (C 'artefacts\usb_peripheriques_dates.csv')
    $usbRows = New-Object System.Collections.Generic.List[object]
    foreach ($e in @(Get-Evtx 'Microsoft-Windows-Partition/Diagnostic' @(1006) $Since)) {
        $f = Get-EvFields $e
        $usbRows.Add([pscustomobject]@{ Date = Fmt $e.TimeCreated; Source = 'Partition 1006'; Peripherique = "$($f['Manufacturer']) $($f['Model'])".Trim(); Serie = $f['SerialNumber']; Capacite = $f['Capacity']; Fenetre = WinOf $e.TimeCreated })
    }
    foreach ($e in @(Get-Evtx 'Microsoft-Windows-Kernel-PnP/Configuration' @(400, 410, 420, 430) $Since)) {
        $f = Get-EvFields $e
        if ("$($f['DeviceInstanceId'])" -match '(?i)USBSTOR|SWD\\WPDBUSENUM|USB\\VID') { $usbRows.Add([pscustomobject]@{ Date = Fmt $e.TimeCreated; Source = "Kernel-PnP $($e.Id)"; Peripherique = $f['DeviceInstanceId']; Serie = ''; Capacite = ''; Fenetre = WinOf $e.TimeCreated }) }
    }
    $setup = C 'artefacts\setupapi.dev.log'
    if (Test-Path -LiteralPath $setup) {
        $lines = Get-Content -LiteralPath $setup -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '>>>\s+\[Device Install.*-\s*(USBSTOR\\[^\]]+)\]' -and ($i + 1) -lt $lines.Count -and $lines[$i + 1] -match '>>>\s+Section start (\d{4}/\d\d/\d\d \d\d:\d\d:\d\d)') {
                $d = [datetime]::ParseExact($matches[1], 'yyyy/MM/dd HH:mm:ss', $Inv)
                $dev = ([regex]::Match($lines[$i], 'USBSTOR\\[^\]]+')).Value
                $usbRows.Add([pscustomobject]@{ Date = Fmt $d; Source = 'setupapi (1re installation)'; Peripherique = $dev; Serie = ''; Capacite = ''; Fenetre = WinOf $d })
            }
        }
    }
    Out-Csv ($usbRows | Sort-Object Date) 'usb_chronologie.csv'
    $usbW = @($usbRows | Where-Object { $_.Fenetre })
    V 'Clés et disques USB branchés' "$(Nb $usb.Count 'clé ou disque USB connu' 'clés ou disques USB connus') de Windows$(if ($usbDet.Count) { ', avec les dates de branchement' })" (Nb $usbRows.Count 'branchement daté' 'branchements datés') $usbW.Count $(if ($usbW.Count) { 'Un support USB a été branché pendant l''attaque : vérifiez qui (technicien ou attaquant).' } else { 'Aucun support USB branché pendant l''attaque (normal pour une attaque à distance).' }) 'usb_chronologie.csv'

    # SMBServer/Security et partages (5140/5145)
    $smb = Get-Evtx 'Microsoft-Windows-SMBServer/Security' @(551, 1006, 1007, 1009, 1015, 1016, 1020, 1021, 1022, 3000) $Since
    $smbR = Get-EvtxRange 'Microsoft-Windows-SMBServer/Security'
    $sh = Get-Evtx 'Security' @(5140, 5145) $Since
    $shRows = @(foreach ($e in @($sh)) { $f = Get-EvFields $e; [pscustomobject]@{ Date = Fmt $e.TimeCreated; EventID = $e.Id; Compte = $f['SubjectUserName']; IP = $f['IpAddress']; Partage = $f['ShareName']; Fichier = $f['RelativeTargetName']; Fenetre = WinOf $e.TimeCreated } })
    Out-Csv $shRows 'partages_acces_5140_5145.csv'
    V 'Dossiers partagés du poste : accès refusés (SMB)' $(if (-not (Find-Evtx 'Microsoft-Windows-SMBServer/Security')) { 'journal absent' } else { Nb (@($smb).Count) 'événement' 'événements' }) $(if ($smbR) { "du $(Fmt $smbR.Debut) au $(Fmt $smbR.Fin)" }) @($smb | Where-Object { WinOf $_.TimeCreated }).Count 'Erreurs et refus d''accès aux dossiers que ce poste partage sur le réseau.' 'evenements_fenetres.csv'
    V 'Accès aux dossiers partagés du poste (journal de sécurité)' $(if (@($sh).Count) { Nb (@($sh).Count) 'accès noté' 'accès notés' } else { 'aucun accès noté (Windows ne les notait probablement pas : audit inactif)' }) '' @($shRows | Where-Object { $_.Fenetre }).Count $(if (@($shRows).Count) { "Adresses IP qui y ont accédé : $((($shRows | Select-Object -ExpandProperty IP -Unique) -join ', '))." } else { 'Aucune adresse IP à vérifier.' }) 'partages_acces_5140_5145.csv'

    # DNS-Client/Operational
    $dns = Get-Evtx 'Microsoft-Windows-DNS-Client/Operational' @(3006, 3008, 3020) $Since
    $dnsRows = @(foreach ($e in @($dns)) { $f = Get-EvFields $e; $d = WinOf $e.TimeCreated; if ($d) { [pscustomobject]@{ Date = Fmt $e.TimeCreated; EventID = $e.Id; Domaine = $f['QueryName']; Resultat = $f['QueryResults']; Fenetre = $d } } })
    Out-Csv $dnsRows 'dns_requetes_fenetres.csv'
    $etat = Read-Csv (C 'evenements\etat_journaux.csv') | Where-Object { $_.Journal -match 'DNS-Client' } | Select-Object -First 1
    V 'Sites contactés par le poste (journal DNS)' $(if ($etat) { "journal $(if ("$($etat.Active)" -eq 'True') { 'actif' } else { 'désactivé' }), $(Nb ([int64]("0$($etat.NbEvenements)" -replace '\D', '')) 'événement' 'événements')" } elseif (-not (Find-Evtx 'Microsoft-Windows-DNS-Client/Operational') -or -not @($dns).Count) { 'journal vide ou désactivé (il l''est par défaut dans Windows)' } else { Nb (@($dns).Count) 'demande' 'demandes' }) '' $dnsRows.Count $(if ($dnsRows.Count) { "Sites contactés pendant l'attaque : $((($dnsRows | Select-Object -ExpandProperty Domaine -Unique | Select-Object -First 40) -join ', '))." } else { 'Aucun nom de site enregistré pendant l''attaque : voir les sites relevés en direct pendant la collecte (cache DNS) et la box internet.' }) 'dns_requetes_fenetres.csv'

    # Evenements de tous les journaux exportes, dans les fenetres (lecture directe)
    $evw = New-Object System.Collections.Generic.List[object]
    foreach ($f in (Get-ChildItem -LiteralPath $EvtxDir -Filter '*.evtx' -ErrorAction SilentlyContinue)) {
        foreach ($w in $script:Win) {
            $a = $w.Debut.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.000Z'); $b = $w.Fin.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.000Z')
            try {
                Get-WinEvent -Path $f.FullName -FilterXPath "*[System[TimeCreated[@SystemTime>='$a' and @SystemTime<='$b']]]" -MaxEvents 20000 -ErrorAction Stop | ForEach-Object {
                    $evw.Add([pscustomobject]@{ Date = Fmt $_.TimeCreated; Fenetre = $w.Id; Journal = $f.BaseName; EventID = $_.Id; Source = $_.ProviderName
                        Donnees = (((Get-EvFields $_).GetEnumerator() | Where-Object { $_.Value -and $_.Value -ne '-' } | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ; ') })
                }
            } catch {}
        }
    }
    Out-Csv ($evw | Sort-Object Date) 'evenements_fenetres.csv'
    Out-Csv $ver 'verifications_sources.csv'
    foreach ($v in $ver) { G $v.Source $(if ($v.EvenementsFenetres -gt 0) { 'A LIRE' } elseif ($v.Etat -match '(?i)absent|d[eé]sactiv|ne notait|non collect|aucun') { 'NON VERIFIABLE' } else { 'RAS' }) "$($v.Etat). $($v.Constat)" $v.Fichier }
    Log "    $($evw.Count) evenements (tous journaux) dans les fenetres"
}

# =================================================================== 9. NOTE DE RANCON ET VEILLE
Step 'Note de rancon : contacts, revendication de vol de donnees, pistes de veille' {
    $notes = @(Get-ChildItem -LiteralPath (C 'rancon\notes') -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)recover|readme|decrypt|restore|how.?to|ransom|instruction|unlock|lisez' -and $_.Length -lt 200KB })
    if (-not $notes.Count) { $notes = @(Get-ChildItem -LiteralPath (C 'utilisateurs') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)recover|decrypt|how.?to' -and $_.Extension -match '\.(txt|html?|hta)$' } | Select-Object -First 1) }
    if (-not $notes.Count) { G 'Demande de rançon : vol de données revendiqué ?' 'NON VERIFIABLE' 'Aucune note de rançon dans la collecte.' ''; return }
    $byHash = $notes | Group-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    $out = New-Object System.Collections.Generic.List[string]
    $theftRx = '(?i)(stole|stolen|steal|exfiltrat|download(ed)?\s+(all\s+)?(your|the)\s+data|we\s+have\s+(copied|downloaded|your)|copied|leak|publish|publicly|blog|dark\s?web|tor\s+site|sell\s+(your|the)\s+data|confidential|sensitive\s+data|data\s+will\s+be|personal\s+data|vol[e\u00e9]|t[e\u00e9]l[e\u00e9]charg[e\u00e9]|publi[e\u00e9]|divulg|fuite|donn[e\u00e9]es\s+(personnelles|sensibles|vol))'
    $claim = $false
    foreach ($g in $byHash) {
        $f = $g.Group[0]
        $t = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        $mails = @([regex]::Matches($t, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}') | ForEach-Object { $_.Value } | Select-Object -Unique)
        $tg    = @([regex]::Matches($t, '(?<![A-Za-z0-9._%+-])@[A-Za-z0-9_]{4,}(?![A-Za-z0-9_]*\.)') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
        $tox   = @([regex]::Matches($t, '\b[0-9A-Fa-f]{76}\b') | ForEach-Object { $_.Value } | Select-Object -Unique)
        $onion = @([regex]::Matches($t, '(?i)[a-z2-7]{16,56}\.onion\S*') | ForEach-Object { $_.Value } | Select-Object -Unique)
        $urls  = @([regex]::Matches($t, '(?i)https?://\S+') | ForEach-Object { $_.Value } | Select-Object -Unique)
        $ids   = @([regex]::Matches($t, '(?i)(system\s*id|personal\s*id|your\s*id|id)\s*:\s*\S{6,}') | ForEach-Object { $_.Value } | Select-Object -Unique)
        $btc   = @([regex]::Matches($t, '\b(bc1[a-z0-9]{25,60}|[13][a-km-zA-HJ-NP-Z1-9]{25,34})\b') | ForEach-Object { $_.Value } | Select-Object -Unique)
        $th    = @([regex]::Matches($t, "[^\r\n]{0,80}$theftRx[^\r\n]{0,80}") | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
        if ($th.Count) { $claim = $true }
        $out.Add("NOTE : $($f.Name)  ($($g.Count) copie(s) identique(s) dans la collecte)")
        $out.Add("  SHA256        : $($g.Name)")
        $out.Add("  Taille        : $($f.Length) octets ; date : $(Fmt $f.LastWriteTime)")
        $out.Add("  E-mails       : $($mails -join ', ')")
        $out.Add("  Telegram / @  : $($tg -join ', ')")
        $out.Add("  Tox / .onion  : $((@($tox) + @($onion)) -join ', ')")
        $out.Add("  URL           : $($urls -join ', ')")
        $out.Add("  Identifiant   : $($ids -join ' | ')")
        $out.Add("  Bitcoin       : $($btc -join ', ')")
        $out.Add("  Revendication de vol de donnees : $(if ($th.Count) { 'OUI - extraits :' } else { 'AUCUNE mention (vol, publication, fuite, site, copie de donnees...)' })")
        foreach ($x in $th) { $out.Add("      > $x") }
        $out.Add('')
    }
    $ext = @(Get-Chiffrement | Select-Object -First 3)
    $out.Add("Extension(s) des fichiers chiffres : $(($ext | ForEach-Object { "$($_.Extension) ($($_.NbFichiers) fichiers, $($_.Premier) -> $($_.Dernier))" }) -join ' ; ')")
    $out.Add('')
    $out.Add('VEILLE A FAIRE A LA MAIN (ne pas automatiser : ne jamais envoyer le nom du cabinet a un service tiers sans accord)')
    $out.Add('  [ ] ID Ransomware : https://id-ransomware.malwarehunterteam.com/ - soumettre la note + 1 fichier chiffre NON sensible')
    $out.Add('      (identifie la famille, indique si un dechiffreur existe).')
    $out.Add('  [ ] ransomware.live : https://www.ransomware.live/ - rechercher le contact (adresse e-mail, @Telegram), l''extension,')
    $out.Add('      puis la famille identifiee : publie-t-elle des donnees volees (site de fuite / double extorsion) ?')
    $out.Add('  [ ] ransomlook.io : https://www.ransomlook.io/ - meme recherche, liste des victimes par groupe.')
    $out.Add('  [ ] Nomoreransom : https://www.nomoreransom.org/fr/decryption-tools.html - dechiffreur disponible ?')
    $out.Add('  [ ] Rechercher le nom du cabinet et des praticiens sur ransomware.live / ransomlook (victimes recentes).')
    $out.Add('  [ ] Surveillance dans le temps : refaire la recherche chaque semaine pendant 3 mois (les publications peuvent etre')
    $out.Add('      tardives), noter date et resultat dans le dossier. Alerte possible via les flux RSS de ransomware.live.')
    $out.Add('  [ ] Signalement : cybermalveillance.gouv.fr ; plainte (le contact de l''attaquant est un element utile).')
    $out | Out-File (P 'note_rancon_analyse.txt') -Encoding utf8
    G 'Demande de rançon : vol de données revendiqué ?' $(if ($claim) { 'INDICE' } else { 'RAS' }) $(if ($claim) { 'La note de rançon affirme que des données ont été volées ou seront publiées : voir les extraits.' } else { 'La note de rançon ne parle ni de vol ni de publication de données. Cela n''exclut pas un vol : surveillez les sites où les attaquants publient.' }) 'note_rancon_analyse.txt'
}

# =================================================================== 10. IDENTIFIANTS : MIMIKATZ, OUTILS NIRSOFT, GESTIONNAIRE D'IDENTIFIANTS
Step "Exposition des identifiants : mimikatz execute ?, outils NirSoft, gestionnaire d'identifiants" {
    $o = New-Object System.Collections.Generic.List[string]
    $mk = $Ind.mimikatz
    $o.Add('MIMIKATZ : PRESENCE ET EXECUTION')
    $o.Add('-----------------------------------------------------------------')
    $pf  = @($script:Exec | Where-Object { $_.Source -like 'Prefetch*' -and "$($_.Programme)" -match $mk })
    $am  = @($script:Exec | Where-Object { $_.Source -like 'Amcache*' -and "$($_.Chemin)" -match $mk })
    $bam = @($script:Exec | Where-Object { $_.Source -like 'BAM*' -and "$($_.Chemin)" -match $mk })
    $p48 = @($script:Exec | Where-Object { $_.Source -match '4688|Sysmon' -and "$($_.Chemin) $($_.Detail)" -match $mk })
    $ps  = @((Get-Evtx 'Microsoft-Windows-PowerShell/Operational' @(4104) $Since) | Where-Object { $_.Message -match $mk -or (Get-EvFields $_)['ScriptBlockText'] -match $mk })
    $det = Read-Csv (C 'systeme\defender_detections.csv') | Where-Object { $_.Resources -match $mk }
    $thr = Read-Csv (C 'systeme\defender_menaces.csv') | Where-Object { $_.ThreatName -match $Ind.menaces_mimikatz }
    $dev = @((Get-Evtx 'Microsoft-Windows-Windows Defender/Operational' @(1116, 1117) $Since) | ForEach-Object { $f = Get-EvFields $_; [pscustomobject]@{ Date = $_.TimeCreated; Id = $_.Id; Nom = $f['Threat Name']; Chemin = $f['Path']; Action = $f['Action Name']; Processus = $f['Process Name']; Utilisateur = $f['Detection User'] } })
    $devMk = @($dev | Where-Object { "$($_.Nom) $($_.Chemin)" -match $Ind.detections_mimikatz })
    $lsass = @((Get-Evtx 'Microsoft-Windows-Sysmon/Operational' @(10) $Since) | Where-Object { (Get-EvFields $_)['TargetImage'] -match '(?i)lsass\.exe' })
    $dmp = @(Select-String -LiteralPath (C 'fichiers\listing_complet.csv') -Pattern '(?i)lsass[^"\\]*\.dmp"|\.dmp",\d+,' -ErrorAction SilentlyContinue | Select-Object -First 30 | ForEach-Object { $_.Line })
    $o.Add("Fichiers presents sur le disque                : $(@(Read-Csv (C 'fichiers\outils_suspects.csv') | Where-Object { $_.Chemin -match $mk }).Count) (fichiers\outils_suspects.csv)")
    $o.Add("Detections Defender (fichier)                  : $(@($det).Count) ; menaces : $((@($thr) | ForEach-Object { "$($_.ThreatName) execute=$($_.DidThreatExecute)" }) -join ' ; ')")
    $o.Add("Detections Defender (journal 1116/1117)        : $(($devMk | ForEach-Object { "$(Fmt $_.Date) $($_.Nom) par $($_.Processus) ($($_.Action))" }) -join ' ; ')")
    $o.Add("Prefetch (execution)                           : $(if ($pf.Count) { ($pf | ForEach-Object { "$($_.Programme) $(Fmt $_.Date)" }) -join ' ; ' } else { 'aucune' })")
    $o.Add("Amcache (fichier inventorie)                   : $(if ($am.Count) { ($am | ForEach-Object { "$($_.Chemin) $(Fmt $_.Date) SHA1 $($_.SHA1)" }) -join ' ; ' } else { 'aucune entree' })")
    $o.Add("BAM (execution par utilisateur)                : $(if ($bam.Count) { ($bam | ForEach-Object { "$($_.Chemin) $(Fmt $_.Date) $($_.Compte)" }) -join ' ; ' } else { 'aucune' })")
    $o.Add("4688 / Sysmon 1                                : $(if ($p48.Count) { "$($p48.Count) evenement(s)" } else { 'aucun' })")
    $o.Add("PowerShell 4104 (commandes de Mimikatz) : $($ps.Count) bloc(s)")
    $o.Add("Acces a LSASS (Sysmon 10)                      : $(if ($null -eq (Find-Evtx 'Microsoft-Windows-Sysmon/Operational')) { 'Sysmon absent : non verifiable' } else { $lsass.Count })")
    $o.Add("Fichiers .dmp (vidage LSASS ?)                 : $($dmp.Count) $(if ($dmp.Count) { '(voir listing)' })")
    $exec = ($pf.Count + $bam.Count + $p48.Count + $ps.Count) -gt 0
    $audit = if (@($script:Exec | Where-Object { $_.Source -like '4688*' }).Count) { 'actif' } else { 'INACTIF : pas de preuve par 4688' }
    $constat = if ($exec) { 'des traces d''EXECUTION de mimikatz existent : considerer comme compromis les hachages / mots de passe de TOUS les comptes ayant ouvert une session sur le poste (LSASS), et les secrets LSA.' }
               else { "aucune trace d'execution de mimikatz dans Prefetch, BAM, PowerShell et 4688 (audit des processus $audit). Le Prefetch enregistre toute execution d'un .exe : son absence est un bon indicateur, sans etre une preuve absolue (binaire renomme, execution en memoire, Prefetch purge)." }
    $o.Add('')
    $o.Add("CONSTAT : $constat")
    $o.Add('')
    $o.Add('OUTILS DE RECUPERATION DE MOTS DE PASSE EXECUTES')
    $o.Add('-----------------------------------------------------------------')
    $nir = @($script:Exec | Where-Object { "$($_.Programme) $($_.Chemin)" -match $Ind.outils_mots_de_passe -and "$($_.Chemin)" -notmatch '(?i)\\windows\\(winsxs|system32)|passkey|passwordonwake|genpass|umpass' } | Sort-Object Date)
    foreach ($n in $nir) { $o.Add("  $(Fmt $n.Date)  $($n.Source)  $($n.Programme)  $($n.Compte)  $($n.SHA1)") }
    if (-not $nir.Count) { $o.Add('  aucun') }
    $o.Add('')
    $o.Add('Portee des outils NirSoft vus :')
    $o.Add('  netpass             : mots de passe reseau / RDP enregistres dans le GESTIONNAIRE D''IDENTIFIANTS du compte qui l''a lance')
    $o.Add('  ChromePass / WebBrowserPassView / PasswordFox / OperaPassView : mots de passe enregistres dans les navigateurs (compte courant)')
    $o.Add('  BulletsPassView     : mots de passe affiches masques dans des fenetres ouvertes')
    $o.Add('  RouterPassView      : fichiers de sauvegarde de box / routeur')
    $o.Add('  dialupass / WirelessKeyView : connexions VPN / numerotation, cles Wi-Fi (Wi-Fi : tous comptes, en administrateur)')
    $o.Add('')
    $o.Add('GESTIONNAIRE D''IDENTIFIANTS WINDOWS : CIBLES A IDENTIFIER')
    $o.Add('-----------------------------------------------------------------')
    $cm = Read-Csv (C 'exposition\gestionnaire_identifiants_fichiers.csv')
    foreach ($g in ($cm | Group-Object Utilisateur)) { $o.Add("  $($g.Name) : $($g.Count) fichier(s) (Credentials / Vault), dernier modifie le $((($g.Group | Sort-Object { Parse-Date $_.LastWriteTime } | Select-Object -Last 1).LastWriteTime))") }
    $ck = if (Test-Path -LiteralPath (C 'exposition\cmdkey_compte_courant.txt')) { (Get-Content -LiteralPath (C 'exposition\cmdkey_compte_courant.txt') -Encoding UTF8 | Where-Object { $_ -match '(?i)cible|target' }) -join ' | ' } else { '' }
    $o.Add("  cmdkey (compte qui a lance la collecte) : $(if ($ck) { $ck } else { 'aucune cible' })")
    $ckFiles = @(Get-ChildItem -LiteralPath (C 'exposition') -Filter 'cmdkey_*.txt' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'cmdkey_compte_courant.txt' }) +
               @(Get-ChildItem -LiteralPath (Join-Path (Split-Path $Collecte -Parent) 'Identifiants') -Filter "cmdkey_$($Computer)_*.txt" -ErrorAction SilentlyContinue)
    foreach ($f in $ckFiles) {
        $o.Add("  $($f.BaseName) : $(((Get-Content -LiteralPath $f.FullName -Encoding UTF8) | Where-Object { $_ -match '(?i)cible|target' }) -join ' | ')")
    }
    $o.Add('  Indices de cibles (serveurs utilises avec des identifiants explicites ou en RDP sortant) :')
    foreach ($r in (Read-Csv (C 'connexions\identifiants_explicites_4648.csv') | Where-Object { $_.Serveur -and $_.Serveur -notmatch '^(localhost|-)$' } | Group-Object Serveur, CompteUtilise)) { $o.Add("    4648 : $($r.Name) ($($r.Count) fois)") }
    foreach ($r in (Read-Csv (C 'reseau\rdp_connexions_sortantes.csv'))) { $o.Add("    RDP sortant : $($r.Serveur) ($($r.UsernameHint))") }
    foreach ($r in (Read-Csv (C 'reseau\lecteurs_mappes.csv'))) { $o.Add("    Lecteur reseau : $($r.LocalPath) -> $($r.RemotePath)") }
    $o.Add('  A FAIRE : dans la session de CHAQUE compte, lancer DigSpill.exe > Identifiants de ce compte (ou "cmdkey /list") pour obtenir')
    $o.Add('  les cibles (NAS, serveur Lina, sites web). Si elles donnent acces a des donnees hors du serveur, l''exfiltration a pu')
    $o.Add('  se faire depuis ces systemes : verifier leurs journaux d''acces sur la periode, puis changer les mots de passe.')
    $o | Out-File (P 'identifiants_exposition.txt') -Encoding utf8
    G 'Vol de mots de passe (Mimikatz)' $(if ($exec) { 'INDICE' } else { 'RAS' }) $(if ($exec) { 'Mimikatz a été lancé : considérez les mots de passe de tous les comptes de ce poste comme volés et changez-les.' } else { "Mimikatz était sur le disque (repéré par Defender), mais rien ne montre qu'il a été lancé." }) 'identifiants_exposition.txt'
    $netp = @($nir | Where-Object { $_.Programme -match '(?i)netpass' })
    G 'Mots de passe enregistrés dans Windows' 'A FAIRE' "$(Nb (@($cm | Group-Object Utilisateur).Count) 'compte a' 'comptes ont') des mots de passe enregistrés dans Windows. $(if ($netp.Count) { 'L''outil netpass a été lancé : considérez les mots de passe réseau et bureau à distance de ce compte comme volés. ' })Pour la liste complète, ouvrez chaque session et cliquez sur « Identifiants de ce compte » dans DigSpill." 'identifiants_exposition.txt'
}

# =================================================================== 10 bis. COMPTES DE STOCKAGE / TRANSFERT CONFIGURES
# rclone, FileZilla, WinSCP : vers quel compte ou quel serveur les donnees pouvaient partir. On montre l'identifiant
# (adresse, utilisateur, serveur) ; les mots de passe et jetons ne sont JAMAIS lus ni decodes : seulement "present".
Step 'Comptes de stockage et de transfert configures (rclone, FileZilla, WinSCP)' {
    $secrets = '(?i)^(pass|password|pass2|token|secret|secret_access_key|client_secret|key|key_file|service_account_credentials|sas_url|session_token|access_token|refresh_token|private_key|password2)$'
    $identite = '(?i)^(user|username|account|email|host|url|endpoint|bucket|tenant|client_id|drive_id|region|provider)$'
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($f in @(Get-ChildItem -LiteralPath (C 'utilisateurs') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^(rclone\.conf|sitemanager\.xml|recentservers\.xml|winscp\.ini)$' })) {
        $prof = ($f.FullName.Substring((C 'utilisateurs').Length + 1) -split '\\')[0]
        if ($f.Name -ieq 'rclone.conf') {
            $sec = $null; $h = $null
            $lignes = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)
            if ($lignes.Count -and $lignes[0] -match '^RCLONE_ENCRYPT_V0') { $rows.Add([pscustomobject]@{ Profil = $prof; Outil = 'rclone'; Nom = '(configuration chiffree)'; Type = ''; Compte = ''; Secrets = 'configuration entiere chiffree (non dechiffree)'; Modifie = Fmt $f.LastWriteTime; Fichier = $f.FullName.Substring($Collecte.Length + 1) }); continue }
            foreach ($l in ($lignes + '[]')) {
                if ($l -match '^\s*\[(.*)\]\s*$') {
                    if ($sec) { $rows.Add([pscustomobject]@{ Profil = $prof; Outil = 'rclone'; Nom = $sec; Type = $h['type']; Compte = (($h.Keys | Where-Object { $_ -match $identite } | ForEach-Object { "$_=$($h[$_])" }) -join ' ; ')
                        Secrets = (($h.Keys | Where-Object { $_ -match $secrets } | ForEach-Object { "$_ present (non decode)" }) -join ' ; '); Modifie = Fmt $f.LastWriteTime; Fichier = $f.FullName.Substring($Collecte.Length + 1) }) }
                    $sec = $Matches[1]; $h = [ordered]@{}
                } elseif ($sec -and $l -match '^\s*([^=#;]+?)\s*=\s*(.*)$') {
                    $k = $Matches[1].Trim().ToLower(); $val = $Matches[2].Trim()
                    $h[$k] = $(if ($k -match $secrets) { '' } else { $val })   # valeur d'un secret jamais gardee
                }
            }
        } elseif ($f.Name -match '(?i)\.xml$') {
            try { [xml]$x = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 } catch { continue }
            foreach ($srv in @($x.SelectNodes('//Server'))) {
                $rows.Add([pscustomobject]@{ Profil = $prof; Outil = 'FileZilla'; Nom = "$($srv.Name)"; Type = $(switch ("$($srv.Protocol)") { '1' { 'sftp' } '0' { 'ftp' } default { "protocole $($srv.Protocol)" } })
                    Compte = "host=$($srv.Host):$($srv.Port) ; user=$($srv.User)"; Secrets = $(if ($srv.Pass) { 'mot de passe present (non decode)' } else { '' }); Modifie = Fmt $f.LastWriteTime; Fichier = $f.FullName.Substring($Collecte.Length + 1) })
            }
        } else {
            $sec = $null; $h = @{}
            foreach ($l in (@(Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue) + '[]')) {
                if ($l -match '^\[(.*)\]$') {
                    if ($sec -and $h['HostName']) { $rows.Add([pscustomobject]@{ Profil = $prof; Outil = 'WinSCP'; Nom = [uri]::UnescapeDataString(($sec -replace '^Sessions\\', '')); Type = 'session'; Compte = "host=$($h['HostName']) ; user=$($h['UserName'])"; Secrets = $(if ($h['Password']) { 'mot de passe present (non decode)' } else { '' }); Modifie = Fmt $f.LastWriteTime; Fichier = $f.FullName.Substring($Collecte.Length + 1) }) }
                    $sec = $Matches[1]; $h = @{}
                } elseif ($l -match '^([^=]+)=(.*)$') { $k = $Matches[1]; $val = $Matches[2]; $h[$k] = $(if ($k -match '(?i)pass') { 'x' } else { $val }) }
            }
        }
    }
    Out-Csv $rows 'comptes_transfert.csv'
    $txt = if ($rows.Count) { "$(Nb $rows.Count 'compte configuré' 'comptes configurés') pour envoyer des fichiers vers un stockage en ligne ou un serveur : " + (($rows | Select-Object -First 4 | ForEach-Object { "$($_.Outil) $($_.Type) $($_.Compte)".Trim() }) -join ' | ') + '. Seul le nom du compte est relevé, jamais le mot de passe.' } else { 'Aucun compte rclone, FileZilla ou WinSCP configuré sur le poste.' }
    G 'Comptes de stockage en ligne configurés (rclone, FileZilla, WinSCP)' $(if ($rows.Count) { 'INDICE' } else { 'RAS' }) $txt 'comptes_transfert.csv'
    Log "    $txt"
}

# =================================================================== 11. IOC : HACHAGES DES OUTILS DE L'ATTAQUANT
Step 'IOC : hachages SHA256 / SHA1 (fichiers presents, Amcache, quarantaine Defender)' {
    $ioc = New-Object System.Collections.Generic.List[object]
    foreach ($r in (Read-Csv (C 'fichiers\outils_suspects.csv'))) { $ioc.Add([pscustomobject]@{ Nom = Leaf $r.Chemin; Chemin = $r.Chemin; SHA256 = $r.SHA256; SHA1 = ''; Source = 'Fichier present (outils_suspects)'; Date = $r.Creation; Remarque = $(if (-not $r.SHA256) { 'hash non calcule (fichier verrouille / supprime par Defender ?)' }) }) }
    foreach ($r in (Read-Csv (C 'rancon\binaires_suspects.csv'))) { $ioc.Add([pscustomobject]@{ Nom = Leaf $r.Chemin; Chemin = $r.Chemin; SHA256 = $r.SHA256; SHA1 = ''; Source = "Binaire suspect ($($r.Source))"; Date = $r.Creation; Remarque = "Signature $($r.Signature)" }) }
    foreach ($e in ($script:Exec | Where-Object { $_.Source -like 'Amcache*' -and $_.SHA1 -and "$($_.Chemin)" -match $ToolRx -and "$($_.Chemin)" -notmatch '(?i)\\windows\\(winsxs|system32|syswow64)\\' })) {
        $ioc.Add([pscustomobject]@{ Nom = $e.Programme; Chemin = $e.Chemin; SHA256 = ''; SHA1 = $e.SHA1; Source = 'Amcache (SHA1 du fichier execute / inventorie)'; Date = Fmt $e.Date; Remarque = '' })
    }
    # Quarantaine Defender : le nom de chaque fichier ResourceData est le SHA1 du fichier d'origine
    $q = C 'rancon\defender_quarantaine\ResourceData'
    $dev = @((Get-Evtx 'Microsoft-Windows-Windows Defender/Operational' @(1116, 1117) $Since) | ForEach-Object { $f = Get-EvFields $_; [pscustomobject]@{ Date = $_.TimeCreated; Nom = $f['Threat Name']; Chemin = $f['Path'] } })
    foreach ($f in (Get-ChildItem -LiteralPath $q -Recurse -File -ErrorAction SilentlyContinue)) {
        $near = @($dev | Where-Object { [math]::Abs(($_.Date - $f.LastWriteTime).TotalSeconds) -le 120 })
        $ioc.Add([pscustomobject]@{ Nom = $(if ($near.Count) { (($near | ForEach-Object { $_.Nom } | Select-Object -Unique) -join ' / ') } else { '(menace non rapprochee)' }); Chemin = (($near | ForEach-Object { $_.Chemin -replace '^file:_', '' } | Select-Object -Unique) -join ' | ')
            SHA256 = ''; SHA1 = $f.Name.ToUpper(); Source = 'Quarantaine Defender (nom = SHA1 d''origine)'; Date = Fmt $f.LastWriteTime; Remarque = "rapprochement par horodatage (+/- 2 min) avec 1116/1117 : $($near.Count) detection(s) ; un meme horodatage peut couvrir plusieurs fichiers" })
    }
    $rows = @($ioc | Sort-Object Source, Nom)
    Out-Csv $rows 'ioc_hachages.csv'
    # Executes sans hachage connu
    $hashed = @($rows | Where-Object { $_.SHA256 -or $_.SHA1 } | ForEach-Object { (Leaf "$($_.Chemin)").ToLower(); "$($_.Nom)".ToLower() })
    $miss = @($script:Exec | Where-Object { $_.Source -match 'Prefetch|BAM' -and "$($_.Programme) $($_.Chemin)" -match $ToolRx } | ForEach-Object { "$($_.Programme)" } | Select-Object -Unique | Where-Object { $hashed -notcontains $_.ToLower() })
    $miss | Out-File (P 'ioc_executes_sans_hachage.txt') -Encoding utf8
    Log "    $($rows.Count) IOC ; executes sans hachage rapproche : $($miss.Count)"
    G 'Empreintes des fichiers suspects (à transmettre à un expert ou à VirusTotal)' $(if ($miss.Count) { 'A FAIRE' } else { 'RAS' }) "$(Nb $rows.Count 'empreinte relevée' 'empreintes relevées').$(if ($miss.Count) { " Programmes lancés dont l'empreinte manque : $(($miss | Select-Object -First 15) -join ', ')." })" 'ioc_hachages.csv, ioc_executes_sans_hachage.txt'
}

# =================================================================== 12. CONTENEURS VELOCIRAPTOR : HACHAGE COMPLET ET INTEGRITE
Step 'Conteneurs Velociraptor : SHA256 complet et controle de la fin d''archive (troncature FAT32)' {
    $zips = @(Get-ChildItem -LiteralPath $VeloDir -Filter '*.zip' -ErrorAction SilentlyContinue)
    if ($Velociraptor -and (Test-Path -LiteralPath $Velociraptor) -and -not ($zips | Where-Object { $_.FullName -eq $Velociraptor })) { $zips += Get-Item -LiteralPath $Velociraptor }
    $rows = foreach ($z in $zips) {
        $fs = [IO.File]::OpenRead($z.FullName)
        try {
            $len = [math]::Min([int64]70000, $fs.Length); $buf = New-Object byte[] $len
            [void]$fs.Seek(-$len, [IO.SeekOrigin]::End); [void]$fs.Read($buf, 0, $len)
        } finally { $fs.Close() }
        $hex = [BitConverter]::ToString($buf)
        $eocd = $hex.Contains('50-4B-05-06'); $z64 = $hex.Contains('50-4B-06-07')
        $side = "$($z.FullName).sha256"
        $h = if (Test-Path -LiteralPath $side) { ((Get-Content -LiteralPath $side -TotalCount 1) -split '\s+')[0] }
             elseif ($SansHashConteneurs) { '(non calcule)' }
             else {
                 Log "    SHA256 de $($z.Name) ($([math]::Round($z.Length / 1MB)) Mo)..."
                 $hh = (Get-FileHash -LiteralPath $z.FullName -Algorithm SHA256).Hash
                 try { "$hh  $($z.Name)  $($z.Length) octets  calcule le $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz') sur $env:COMPUTERNAME" | Out-File -LiteralPath $side -Encoding ascii -ErrorAction Stop } catch {}
                 $hh
             }
        [pscustomobject]@{ Conteneur = $z.Name; Octets = $z.Length; Date = Fmt $z.LastWriteTime; SHA256 = $h
            FinArchive = $(if ($eocd -or $z64) { 'presente' } else { 'ABSENTE' })
            Diagnostic = $(if (-not ($eocd -or $z64)) { 'Archive TRONQUEE (fin du zip absente)' + $(if ($z.Length -ge 4290000000) { ' : taille au plafond FAT32 de 4 Go' }) + '. Contenu partiellement exploitable ; ne pas citer comme preuve complete.' } elseif ($z.Length -ge 4290000000) { 'Taille proche de 4 Go : verifier l''integrite' } else { 'OK' }) }
    }
    Out-Csv $rows 'conteneurs_velociraptor.csv'
    $bad = @($rows | Where-Object { $_.FinArchive -eq 'ABSENTE' })
    if ($rows) { G 'Archive de collecte Velociraptor complète et intacte ?' $(if ($bad.Count) { 'A FAIRE' } else { 'RAS' }) $(if ($bad.Count) { "$(Nb $bad.Count 'archive est coupée' 'archives sont coupées') (support FAT32 limité à 4 Go) : $(($bad | ForEach-Object { $_.Conteneur }) -join ', '). Refaites la collecte sur un support NTFS ou exFAT." } else { "$(Nb (@($rows).Count) 'archive vérifiée' 'archives vérifiées') en entier : complète et intacte." }) 'conteneurs_velociraptor.csv' }
}

# =================================================================== 12 bis. MEMOIRE VIVE (Volatility 3, au bureau seulement)
function Get-Osa([string]$a, [string]$b) {
    # distance d'edition avec transposition (svhost / svchost = 1, scvhost / svchost = 1)
    # tableau a une dimension : PowerShell 5.1 refuse $d[$i, $j] dans les arguments d'une methode
    $n = $a.Length; $m = $b.Length; $w = $m + 1
    $d = New-Object int[] (($n + 1) * $w)
    for ($i = 0; $i -le $n; $i++) { $d[$i * $w] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[$j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        for ($j = 1; $j -le $m; $j++) {
            $c = 1; if ($a[$i - 1] -eq $b[$j - 1]) { $c = 0 }
            $sup = $d[($i - 1) * $w + $j] + 1
            $gau = $d[$i * $w + $j - 1] + 1
            $dia = $d[($i - 1) * $w + $j - 1] + $c
            $v = $sup; if ($gau -lt $v) { $v = $gau }; if ($dia -lt $v) { $v = $dia }
            if ($i -gt 1 -and $j -gt 1 -and $a[$i - 1] -eq $b[$j - 2] -and $a[$i - 2] -eq $b[$j - 1]) {
                $tr = $d[($i - 2) * $w + $j - 2] + 1; if ($tr -lt $v) { $v = $tr }
            }
            $d[$i * $w + $j] = $v
        }
    }
    return $d[$n * $w + $m]
}
function Invoke-Py([string]$exe, [string[]]$arguments, [string]$stdout, [int]$minutes) {
    $ligne = ($arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $pr = Start-Process -FilePath $exe -ArgumentList $ligne -RedirectStandardOutput $stdout -RedirectStandardError "$stdout.err" -NoNewWindow -PassThru
    $null = $pr.Handle
    if (-not $pr.WaitForExit($minutes * 60000)) { try { $pr.Kill() } catch {}; return 'delai depasse' }
    $pr.WaitForExit()
    return $pr.ExitCode
}
function From-VolDate([string]$s) {
    # '2026-11-21 15:30:12.000000 UTC' -> heure locale
    if ($s -notmatch '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)') { return '' }
    $u = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $Inv)
    return Fmt ([DateTime]::SpecifyKind($u, 'Utc').ToLocalTime())
}
Step 'Memoire vive : processus, lignes de commande et connexions lus dans l''image RAM (Volatility 3)' {
    $ramDir = P 'ram'
    New-Item -ItemType Directory -Force -Path $ramDir | Out-Null
    $lect = New-Object System.Collections.Generic.List[string]
    $lect.Add("Lecture de la memoire vive - $Computer - $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    $nomCol = Split-Path $Collecte -Leaf
    $infoMem = C 'memoire\memoire_info.txt'
    if (Test-Path -LiteralPath $infoMem) { $lect.Add(''); $lect.Add('Copie sur le poste (memoire_info.txt) :'); Get-Content -LiteralPath $infoMem -Encoding UTF8 | ForEach-Object { $lect.Add("  $_") } }
    # image : -Ram, memoire\ de la collecte, chemin note a la collecte, ou <disque>\MEMOIRE\<collecte>
    $cands = @()
    if ($Ram) { $cands += $Ram }
    $cands += @(Get-ChildItem -LiteralPath (C 'memoire') -Filter '*.raw' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    if (Test-Path -LiteralPath $infoMem) { foreach ($l in (Get-Content -LiteralPath $infoMem -Encoding UTF8)) { if ($l -match '^RAM capturee : (.+?\.raw) \(') { $cands += $Matches[1] } } }
    foreach ($dl in [IO.DriveInfo]::GetDrives()) { if ($dl.IsReady) { $cands += @(Get-ChildItem -LiteralPath (Join-Path $dl.RootDirectory.FullName "MEMOIRE\$nomCol") -Filter '*.raw' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) } }
    $img = $cands | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    $etat = $null
    if ($SansRam) { $etat = 'Mémoire vive non lue : la lecture n''a pas été demandée. Relancez l''analyse en cochant « Analyse complète ».' }
    elseif (-not $img) { $etat = 'Pas de copie de la mémoire vive dans cette collecte. Elle n''est faite qu''en collecte complète, sur un support NTFS ou exFAT assez grand (détail : memoire_info.txt).' }
    elseif ($Computer -ieq $env:COMPUTERNAME -and $env:DIGSPILL_RAM_MEME_POSTE -ne '1') { $etat = "Mémoire vive copiée, mais pas lue : cette analyse tourne sur le poste examiné lui-même ($env:COMPUTERNAME). Par sécurité, DigSpill ne lit la mémoire que sur un autre PC, sain : elle peut contenir le programme malveillant. Relancez l'analyse sur votre PC, à partir de la copie des preuves." }
    $py = Join-Path $PSScriptRoot 'outils\python\python.exe'
    if (-not $etat -and -not (Test-Path -LiteralPath $py)) { $etat = "Mémoire vive non lue : les outils de lecture (Python et Volatility 3) manquent dans le kit. Téléchargez le kit complet (onglet Releases du dépôt) et relancez l'analyse." }
    if ($etat) {
        Log "    [i] $etat"
        $lect.Add(''); $lect.Add($etat)
        $lect | Out-File (Join-Path $ramDir 'ram_lecture.txt') -Encoding utf8
        G 'Mémoire vive : programmes en cours au moment de la collecte' $(if ($img -and -not $SansRam) { 'A FAIRE' } else { 'NON VERIFIABLE' }) $etat 'ram\ram_lecture.txt'
        return
    }
    if ($Computer -ieq $env:COMPUTERNAME) { Log '    [i] DIGSPILL_RAM_MEME_POSTE=1 : lecture de la RAM sur le poste collecte (recette uniquement)' }
    $imgItem = Get-Item -LiteralPath $img
    $lect.Add(''); $lect.Add(('Image lue : {0} ({1:N1} Go)' -f $img, ($imgItem.Length / 1GB)))
    Log ('    Image RAM : {0} ({1:N1} Go)' -f $img, ($imgItem.Length / 1GB))
    $vol = Join-Path (Split-Path $py -Parent) 'vol.py'
    $env:PYTHONIOENCODING = 'utf-8'; $env:PYTHONUTF8 = '1'
    $cache = Join-Path $Work 'volatility_cache'; New-Item -ItemType Directory -Force -Path $cache | Out-Null

    # symboles du noyau : outils\symboles (garde d'une analyse a l'autre), sinon dossier de travail
    $symb = Join-Path $PSScriptRoot 'outils\symboles'
    try { New-Item -ItemType Directory -Force -Path $symb -ErrorAction Stop | Out-Null; [IO.File]::WriteAllText((Join-Path $symb '.ecriture'), ''); Remove-Item -LiteralPath (Join-Path $symb '.ecriture') -Force }
    catch { $symb = Join-Path $Work 'symboles'; New-Item -ItemType Directory -Force -Path $symb | Out-Null }
    $noyauF = C 'memoire\noyau.json'
    $horsLigne = $false
    if (Test-Path -LiteralPath $noyauF) {
        $noyau = Get-Content -LiteralPath $noyauF -Raw -Encoding UTF8 | ConvertFrom-Json
        $lect.Add("Windows du poste : $($noyau.Windows) (build $($noyau.Build).$($noyau.Ubr))")
        $horsLigne = $true
        foreach ($mod in @($noyau.Modules)) {
            $dirS = Join-Path $symb "windows\$($mod.Pdb)"; New-Item -ItemType Directory -Force -Path $dirS | Out-Null
            $isf = Join-Path $dirS ('{0}-{1}.json.xz' -f $mod.Guid, $mod.Age)
            if (-not (Test-Path -LiteralPath $isf) -and -not $SansInternet) {
                for ($n = 1; $n -le 3 -and -not (Test-Path -LiteralPath $isf); $n++) {
                    Log "    Symboles $($mod.Pdb) $($mod.Guid)-$($mod.Age) : serveur de symboles Microsoft (essai $n)"
                    $null = Invoke-Py $py @('-m', 'volatility3.framework.symbols.windows.pdbconv', '-p', $mod.Pdb, '-g', ($mod.Guid + ('{0:X}' -f [int]$mod.Age)), '-o', $isf) (Join-Path $Work 'pdbconv.txt') 10
                    if (-not (Test-Path -LiteralPath $isf)) { Start-Sleep -Seconds 15 }
                }
            }
            $ok = Test-Path -LiteralPath $isf
            $lect.Add("Symboles $($mod.Pdb) $($mod.Guid)-$($mod.Age) : $(if ($ok) { 'prets' } elseif ($SansInternet) { 'ABSENTS (analyse sans Internet)' } else { 'ECHEC du telechargement' })")
            if (-not $ok -and $mod.Pdb -match '^ntkrnl') { $horsLigne = $false }
        }
    } else { $lect.Add('noyau.json absent (collecte anterieure a DigSpill 2.8) : Volatility cherche lui-meme les symboles en ligne.') }
    if (-not $horsLigne -and $SansInternet) {
        $etat = 'Mémoire vive non lue : il faut la description du noyau de Windows (les « symboles »), téléchargée chez Microsoft, et l''analyse a été lancée sans Internet. Relancez-la une fois avec Internet : les symboles sont ensuite gardés dans le kit.'
        Log "    [!] $etat"; $lect.Add($etat); $lect | Out-File (Join-Path $ramDir 'ram_lecture.txt') -Encoding utf8
        G 'Mémoire vive : programmes en cours au moment de la collecte' 'A FAIRE' $etat 'ram\ram_lecture.txt'
        return
    }

    $res = @{}
    $lect.Add(''); $lect.Add('Modules Volatility 3 :')
    # Un module qui echoue ecrit son message (ex. "Unsatisfied requirement") au lieu du CSV : on le garde dans
    # ram_lecture.txt, et on refait un essai sans --offline (Volatility cherche alors lui-meme les symboles).
    function Lancer-Vol([string]$pl, [bool]$hl, [bool]$vider = $false) {
        $out = Join-Path $Work "$pl.csv"
        Remove-Item -LiteralPath $out, "$out.err" -ErrorAction SilentlyContinue
        $argv = @($vol, '-q', '-r', 'csv', '--cache-path', $cache, '-s', $symb)
        if ($vider) { $argv += '--clear-cache' }   # un echec est garde en cache : sinon le nouvel essai echoue en 3 s
        if ($hl) { $argv += '--offline' }
        $argv += @('-f', $img, $pl)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Log "    Volatility $pl$(if (-not $hl) { ' (symboles en ligne)' })..."
        $code = Invoke-Py $py $argv $out 30
        $brut = @(); foreach ($f in $out, "$out.err") { if (Test-Path -LiteralPath $f) { $brut += @(Get-Content -LiteralPath $f -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { "$_".Trim() }) } }
        $lignes = @()
        if ("$($brut | Select-Object -First 1)" -match '^TreeDepth,') { try { $lignes = @(Import-Csv -LiteralPath $out -Encoding UTF8) } catch {} }
        $msg = if (-not $lignes.Count -and "$($brut | Select-Object -First 1)" -notmatch '^TreeDepth,') { @($brut | Where-Object { $_ -notmatch '^Volatility 3 Framework' } | Select-Object -Last 6) } else { @() }
        $lect.Add(('  {0,-16} {1,5} lignes, {2,4} s, code {3}{4}' -f $pl, $lignes.Count, [int]$sw.Elapsed.TotalSeconds, $code, $(if (-not $hl) { ', symboles en ligne' })))
        foreach ($x in $msg) { $lect.Add("      | $x") }
        Log ('    {0} : {1} lignes en {2} s{3}' -f $pl, $lignes.Count, [int]$sw.Elapsed.TotalSeconds, $(if ($msg.Count) { ' : ' + ($msg -join ' / ') }))
        return ,$lignes
    }
    $noyauIntrouvable = $false
    foreach ($pl in 'windows.info', 'windows.pslist', 'windows.cmdline', 'windows.netscan', 'windows.netstat') {
        # netstat seulement si netscan n'a rien donne de lisible (table inconnue sur les Windows tres recents)
        if ($pl -eq 'windows.netstat' -and @($res['windows.netscan'] | Where-Object { "$($_.LocalAddr)" -match '^[0-9a-fA-F:.*]+$' }).Count) { continue }
        $lignes = Lancer-Vol $pl $horsLigne
        if (-not $lignes.Count -and $pl -eq 'windows.info') {
            # nouvel essai cache vide, puis en laissant Volatility chercher lui-meme les symboles
            $lignes = Lancer-Vol $pl $horsLigne $true
            if (-not $lignes.Count -and $horsLigne -and -not $SansInternet) { $lignes = Lancer-Vol $pl $false $true; if ($lignes.Count) { $horsLigne = $false } }
            if (-not $lignes.Count) { $noyauIntrouvable = $true; $res[$pl] = $lignes; break }
        }
        $res[$pl] = $lignes
    }
    $infoV = $res['windows.info']
    if ($infoV.Count) { $infoV | Select-Object Variable, Value | Export-Csv (Join-Path $ramDir 'ram_info.csv') -NoTypeInformation -Encoding UTF8 }
    $ps = $res['windows.pslist']
    if (-not $ps.Count) {
        $etat = if ($noyauIntrouvable) { 'Mémoire vive non lue : le cœur de Windows (le noyau) n''a pas été retrouvé dans la copie, ce qui arrive quand elle est faite pendant que Windows tourne. Les programmes et connexions relevés en direct pendant la collecte restent visibles (Détails › Adresses IP et pays, et Tous les événements).' }
                 else { 'Mémoire vive non lue : la liste des programmes n''a pas pu être extraite de la copie (format de la copie ou symboles). Détail technique : ram_lecture.txt.' }
        Log "    [!] $etat"; $lect.Add(''); $lect.Add($etat); $lect | Out-File (Join-Path $ramDir 'ram_lecture.txt') -Encoding utf8
        G 'Mémoire vive : programmes en cours au moment de la collecte' 'A FAIRE' $etat 'ram\ram_lecture.txt'
        return
    }

    # ------- processus : lignes valides, lignes de commande, indices
    $cmd = @{}
    foreach ($r in $res['windows.cmdline']) { $a = ("$($r.Args)" -replace '\\\\', '\').Trim(); if ($a -and $a -notmatch '^(Required memory|Process .* (is|was) |N/A)') { $cmd["$($r.PID)"] = $a } }
    # processus releves en direct pendant la collecte : chemin et ligne de commande quand la RAM ne les donne pas
    $vivants = @{}
    foreach ($r in (Read-Csv (C 'volatile\processus.csv'))) { $vivants["$($r.ProcessId)|$("$($r.Name)".ToLower())"] = $r }
    $valides = @($ps | Where-Object { $_.CreateTime -match '^\d{4}-' -and $_.ImageFileName -match '^[\x20-\x7E]+$' })
    $rejetes = $ps.Count - $valides.Count
    $noms = @{}; foreach ($r in $valides) { $noms["$($r.PID)"] = "$($r.ImageFileName)" }
    $systeme = 'svchost.exe', 'lsass.exe', 'csrss.exe', 'services.exe', 'winlogon.exe', 'wininit.exe', 'smss.exe', 'explorer.exe', 'spoolsv.exe', 'taskhostw.exe', 'dllhost.exe', 'conhost.exe', 'rundll32.exe', 'sihost.exe', 'dashost.exe', 'runtimebroker.exe', 'searchindexer.exe', 'msmpeng.exe', 'ctfmon.exe', 'dwm.exe', 'userinit.exe', 'fontdrvhost.exe', 'lsaiso.exe', 'regsvr32.exe', 'taskmgr.exe', 'audiodg.exe', 'wmiprvse.exe'
    $rxEnvoi = $Ind.outils_envoi
    $rxAcces = 'anydesk|rustdesk|ngrok|cloudflared|chisel|teamviewer|screenconnect|plink|psexe'
    $rxNav = '^(chrome|msedge|firefox|brave|opera|iexplore|msedgewebview2|onedrive|teams|ms-teams)\.exe$'
    $procs = foreach ($r in $valides) {
        $nom = "$($r.ImageFileName)"; $pidS = "$($r.PID)"; $ligneCmd = $cmd[$pidS]; $niv = 0
        # Windows ne garde que 14 caracteres du nom (fontdrvhost.exe -> fontdrvhost.ex) : nom complet repris de la ligne de commande
        $exe = if ($ligneCmd -match '^\s*"?([^"]*?\\)?([^\\"]+\.(exe|com|scr))\b') { $Matches[2] } else { '' }
        if ($nom.Length -ge 14 -and $exe -and $exe.StartsWith($nom, [StringComparison]::OrdinalIgnoreCase)) { $nom = $exe }
        $vu = $vivants["$pidS|$($nom.ToLower())"]
        if (-not $vu -and $nom.Length -ge 14) { $vu = $vivants.Keys | Where-Object { $_ -like "$pidS|$($nom.ToLower())*" } | Select-Object -First 1 | ForEach-Object { $vivants[$_] } }
        if ($vu -and $nom.Length -ge 14 -and "$($vu.Name)".StartsWith($nom, [StringComparison]::OrdinalIgnoreCase)) { $nom = "$($vu.Name)" }
        $chemin = if ($vu -and $vu.ExecutablePath) { "$($vu.ExecutablePath)" } else { '' }
        if ((-not $ligneCmd -or $ligneCmd -eq '-') -and $vu -and $vu.CommandLine) { $ligneCmd = "$($vu.CommandLine)" }
        $bas = $nom.ToLower()
        $ind = New-Object System.Collections.Generic.List[string]
        if ($systeme -notcontains $bas -and -not ($bas.Length -ge 14 -and @($systeme | Where-Object { $_.StartsWith($bas) }).Count)) {
            $proche = $systeme | Where-Object { $_.Length -ge 7 -and [Math]::Abs($_.Length - $bas.Length) -le 1 -and (Get-Osa $bas $_) -eq 1 } | Select-Object -First 1
            if ($proche) { $ind.Add("nom qui imite $proche, un programme de Windows (une lettre de différence)"); $niv = [Math]::Max($niv, 3) }
        }
        # l'outil se reconnait a son nom ou a son chemin, pas a une adresse (curl vers rclone.org n'est pas rclone)
        $exeCmd = if ($ligneCmd -match '^\s*"?([^"]+?\.(exe|com|scr))\b') { $Matches[1] } else { '' }
        if ("$bas $chemin $exeCmd" -match $rxEnvoi) { $ind.Add("outil pour envoyer des fichiers ou voler des mots de passe ($($Matches[0]))"); $niv = [Math]::Max($niv, 3) }
        elseif ("$bas $chemin $exeCmd" -match $rxAcces) { $ind.Add("logiciel de prise en main à distance ($($Matches[0]))"); $niv = [Math]::Max($niv, 2) }
        if ("$chemin $ligneCmd" -match '(?i)\\Users\\Public\\|\\Windows\\Temp\\|\\AppData\\Local\\Temp\\|\\PerfLogs\\|\\\$Recycle') { $ind.Add('lancé depuis un dossier où tout le monde peut écrire'); $niv = [Math]::Max($niv, 2) }
        if ($ligneCmd -match '(?i)\s-e(nc|ncodedcommand)?\s+[A-Za-z0-9+/=]{20,}') { $ind.Add('PowerShell avec une commande cachée (encodée)'); $niv = [Math]::Max($niv, 2) }
        if ($ligneCmd -match '(?i)https?://([^/\s"]+)' -and $bas -notmatch $rxNav) { $ind.Add("adresse Internet dans la commande lancée ($($Matches[1]))"); $niv = [Math]::Max($niv, 1) }
        $par = $noms["$($r.PPID)"]
        if ($bas -eq 'svchost.exe' -and $par -and $par -ne 'services.exe') { $ind.Add("svchost.exe lancé par $par (normalement : services.exe)"); $niv = [Math]::Max($niv, 2) }
        if ($bas -eq 'lsass.exe' -and $par -and $par -ne 'wininit.exe') { $ind.Add("lsass.exe lancé par $par (normalement : wininit.exe)"); $niv = [Math]::Max($niv, 3) }
        [pscustomobject]@{ PID = $r.PID; PPID = $r.PPID; Parent = $par; Processus = $nom; Debut = (From-VolDate $r.CreateTime); Fin = (From-VolDate $r.ExitTime)
            Threads = $r.Threads; Chemin = $chemin; LigneDeCommande = $ligneCmd; Niveau = $niv; Indices = ($ind -join ' ; ') }
    }
    $nLsass = @($procs | Where-Object { $_.Processus -ieq 'lsass.exe' -and -not $_.Fin }).Count
    if ($nLsass -gt 1) { foreach ($x in ($procs | Where-Object { $_.Processus -ieq 'lsass.exe' })) { $x.Niveau = 3; $x.Indices = (@($x.Indices, "$nLsass programmes lsass.exe ouverts (normalement un seul)") | Where-Object { $_ }) -join ' ; ' } }
    Out-Csv ($procs | Sort-Object Debut) 'ram\ram_processus.csv'

    # ------- reseau
    $src = if (@($res['windows.netscan'] | Where-Object { "$($_.LocalAddr)" -match '^[0-9a-fA-F:.*]+$' }).Count -or -not $res.ContainsKey('windows.netstat')) { 'windows.netscan' } else { 'windows.netstat' }
    $reseau = foreach ($r in $res[$src]) {
        $loc = "$($r.LocalAddr)"; $dist = "$($r.ForeignAddr)"
        if ($loc -notmatch '^[0-9a-fA-F:.*]+$') { continue }
        $p = $procs | Where-Object { "$($_.PID)" -eq "$($r.PID)" } | Select-Object -First 1
        [pscustomobject]@{ Protocole = $r.Proto; Local = "${loc}:$($r.LocalPort)"; IP = $dist; Port = $r.ForeignPort; Etat = $r.State; PID = $r.PID
            Processus = $(if ($p) { $p.Processus } else { "$($r.Owner)" }); Cree = (From-VolDate "$($r.Created)"); Niveau = $(if ($p) { $p.Niveau } else { 0 }); Source = $src }
    }
    $reseau = @($reseau)
    Out-Csv $reseau 'ram\ram_reseau.csv'
    $etablies = @($reseau | Where-Object { $_.Etat -match 'ESTABLISHED' -and $_.IP -notmatch '^(0\.0\.0\.0|::|\*|127\.|::1)' })

    $susp = @($procs | Where-Object { $_.Niveau -ge 2 })
    $lect.Add('')
    $lect.Add(('Programmes lus : {0} ({1} lignes illisibles écartées : normal, la copie est faite pendant que Windows tourne)' -f @($procs).Count, $rejetes))
    $lect.Add(('Commandes lancées lues : {0}' -f $cmd.Count))
    $lect.Add(('Connexions lues ({0}) : {1}, dont {2} active(s) vers une autre machine' -f $src, $reseau.Count, $etablies.Count))
    if (-not $etablies.Count) { $lect.Add('  Aucune connexion active lue dans la mémoire : sur Windows 11 24H2 et Windows Server 2025 (build 26100), Volatility 3 ne sait pas encore lire la liste des connexions. Voir les connexions relevées en direct pendant la collecte (Détails › Adresses IP et pays).') }
    $lect.Add(('Programmes suspects : {0}' -f $susp.Count))
    foreach ($x in $susp) { $lect.Add("  PID $($x.PID) $($x.Processus) : $($x.Indices)") }
    $lect | Out-File (Join-Path $ramDir 'ram_lecture.txt') -Encoding utf8
    $txt = "$(Nb (@($procs).Count) 'programme lu' 'programmes lus') dans la mémoire vive, $(if ($susp.Count) { "dont $(Nb $susp.Count 'suspect' 'suspects') : " + (($susp | Select-Object -First 4 | ForEach-Object { "$($_.Processus) (n° $($_.PID))" }) -join ', ') } else { 'aucun suspect' }). $(Nb $reseau.Count 'connexion lue' 'connexions lues')."
    G 'Mémoire vive : programmes en cours au moment de la collecte' $(if ($susp.Count) { 'INDICE' } else { 'RAS' }) $txt 'ram\ram_processus.csv'
    Log "    $txt"
}

# =================================================================== 13. SYNTHESE
Step 'Synthese (SYNTHESE_EXFILTRATION.txt) et lisez-moi' {
    $tzc = $Info['Fuseau']; $tza = [TimeZoneInfo]::Local
    $off = foreach ($w in $script:Win) { "$($w.Id) : UTC$(if ($tza.GetUtcOffset($w.Debut) -ge [TimeSpan]::Zero) { '+' })$($tza.GetUtcOffset($w.Debut).ToString('hh\:mm'))" }
    $S = New-Object System.Collections.Generic.List[string]
    $S.Add("DigSpill - SYNTHESE EXFILTRATION - $Computer - analyse du $(Get-Date -Format 'yyyy-MM-dd HH:mm') (v$Version)")
    $S.Add('Grille de verification, pas une conclusion. Chaque ligne renvoie a un fichier chiffre.')
    $S.Add("Heures : heure locale de la machine d'analyse ($($tza.Id)). $($off -join ' ; ')$(if ($tzc -and $tzc -ne $tza.Id) { " ATTENTION : fuseau du poste collecte = $tzc" })")
    $S.Add("Horloge du poste : voir A_COMPLETER_TECHNICIEN.txt de la collecte (ecart avec la box / serveur de temps).")
    $S.Add('')
    $S.Add('FENETRES ANALYSEES')
    foreach ($w in $script:Win) { $S.Add("  $($w.Id)  $(Fmt $w.Debut) -> $(Fmt $w.Fin)  $($w.Motif)") }
    if (-not $script:Win.Count) { $S.Add('  aucune : relancer avec -Fenetres') }
    $S.Add('')
    $order = @{ 'INDICE' = 0; 'A FAIRE' = 1; 'A LIRE' = 2; 'NON VERIFIABLE' = 3; 'RAS' = 4 }
    $S.Add('GRILLE PAR CANAL  (INDICE = element a expliquer ; A LIRE = traces a relire ; RAS = verifie, rien d''anormal ; NON VERIFIABLE = source absente)')
    foreach ($g in ($Grid | Sort-Object { $order[$_.Statut] }, Canal)) {
        $S.Add(('  [{0,-14}] {1}' -f $g.Statut, $g.Canal))
        $S.Add("                   $($g.Constat)")
        if ($g.Fichier) { $S.Add("                   -> $($g.Fichier)") }
    }
    $nI = @($Grid | Where-Object { $_.Statut -eq 'INDICE' }).Count; $nN = @($Grid | Where-Object { $_.Statut -eq 'NON VERIFIABLE' }).Count
    $S.Add('')
    $S.Add('PROPOSITION DE CONCLUSION GRADUEE (a valider par l''analyste ; la decision d''informer appartient au cabinet et a son DPO)')
    if ($nI -eq 0) {
        $S.Add('  "Exfiltration massive peu probable (confiance moyenne) ; exfiltration ciblee de faible volume non exclue."')
        $S.Add("  Confiance moyenne et non elevee : $nN source(s) non verifiable(s), pas de journal de flux cote box / pare-feu,")
        $S.Add('  et des canaux sans volume (presse-papier, sessions web ouvertes) ne laissent pas de trace de contenu.')
    } else {
        $S.Add("  $nI indice(s) a expliquer avant toute conclusion. Si l'un d'eux est confirme : `"exfiltration de donnees probable`",")
        $S.Add('  a qualifier (quelles donnees, quel volume, quels patients).')
    }
    $S.Add('  Ce qui ferait evoluer cette position :')
    $S.Add('    - journaux / compteurs de la box (volume montant WAN par jour du 14 au 21/10, connexions sortantes inconnues) ;')
    $S.Add('    - revendication de vol dans la note ou publication sur un site de fuite (veille : note_rancon_analyse.txt) ;')
    $S.Add('    - journaux des systemes atteignables avec les identifiants exposes (NAS, logiciels web, messagerie) ;')
    $S.Add('    - pairs NetBird et journaux des outils d''acces distant.')
    $S.Add('')
    $S.Add('ELEMENTS A FAIRE FIGURER DANS LE RAPPORT / LA NOTIFICATION (art. 33 RGPD)')
    $S.Add('  [ ] Date et heure de DECOUVERTE de l''incident (depart du delai de 72 h) - voir A_COMPLETER_TECHNICIEN.txt')
    $S.Add('  [ ] Nombre estime de PATIENTS concernes (et non de fichiers) et categories de donnees (identite, NIR, sante...)')
    $S.Add('  [ ] Fuseau horaire des heures citees (UTC+2 jusqu''au 25/10/2026, UTC+1 ensuite) et verification de l''horloge')
    $S.Add('  [ ] IOC complets (ioc_hachages.csv) ; hachage COMPLET des conteneurs (conteneurs_velociraptor.csv)')
    $S.Add('  [ ] Seconde copie des preuves, hachee et conservee separement (Copier-Preuves.ps1)')
    $S | Out-File (P 'SYNTHESE_EXFILTRATION.txt') -Encoding utf8
    Out-Csv $Grid 'grille_verification.csv'
    @(
        "ANALYSE EXFILTRATION v$Version - $Computer"
        "Collecte analysee : $Collecte"
        "Conteneur Velociraptor : $(if ($script:Zip) { $Velociraptor } else { 'aucun' })"
        "Heures en heure locale de la machine d'analyse ($([TimeZoneInfo]::Local.Id)) ; fuseau du poste collecte : $tzc"
        ''
        'Lire dans cet ordre :'
        '  SYNTHESE_EXFILTRATION.txt         grille par canal + proposition de conclusion graduee'
        '  fenetres_analyse.csv              fenetres derivees des sessions suspectes'
        '  sessions_reconstituees.csv        sessions avec debut, fin, duree, IP (4624/4634/4647, LSM)'
        '  srum_fenetres_vs_reference.csv    volumes par appli et par heure vs moyenne / max de reference'
        '  srum_METHODE.txt                  comment les volumes sont mesures, sur quelle plage'
        '  executions_fenetres.csv           programmes lances pendant les fenetres'
        '  navigation_fenetres.csv           navigation web pendant les fenetres'
        '  acces_fichiers_*.csv / acces_donnees_metier.csv / recherche_brute_tsclient_axilog.csv'
        '  verifications_sources.csv         pare-feu, BITS, USB, SMB, DNS : etat de chaque source'
        '  note_rancon_analyse.txt           contacts, revendication de vol, veille'
        '  identifiants_exposition.txt       mimikatz, outils NirSoft, gestionnaire d''identifiants'
        '  comptes_transfert.csv             comptes rclone / FileZilla / WinSCP configures (identifiants, jamais les mots de passe)'
        '  ioc_hachages.csv                  IOC'
        '  conteneurs_velociraptor.csv       hachage complet et integrite des conteneurs'
        '  ram\ram_processus.csv              processus lus dans l''image RAM (Volatility 3), avec indices'
        '  ram\ram_reseau.csv                 connexions lues dans l''image RAM ; ram\ram_lecture.txt : comment'
        ''
        '_extraits\ : copies de travail (fichiers extraits du conteneur, bases copiees) ; peut etre supprime.'
    ) | Out-File (P '00_LISEZMOI.txt') -Encoding utf8
}

if ($script:Zip) { $script:Zip.Dispose() }
if (-not $GarderExtraits) { Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue }
Step 'Manifeste SHA256 de l''analyse' {
    $m = P 'manifeste_analyse_sha256.csv'
    Get-ChildItem -LiteralPath $Sortie -Recurse -File | Where-Object { $_.FullName -ne $m -and $_.FullName -notlike "$Work\*" } |
        ForEach-Object { [pscustomobject]@{ Fichier = $_.FullName.Substring($Sortie.Length + 1); Taille = $_.Length; SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } } |
        Export-Csv $m -NoTypeInformation -Encoding UTF8
}
$d = (Get-Date) - $T0
Log "=== Analyse terminee en $([int][math]::Floor($d.TotalMinutes)) min $($d.Seconds) s - lire $(P 'SYNTHESE_EXFILTRATION.txt') ==="
