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
    [switch]$GarderExtraits
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

if (-not $Velo) {
    foreach ($cand in @((Join-Path $PSScriptRoot 'Collecteur-Velociraptor.exe'), (Join-Path (Split-Path (Split-Path $Collecte -Parent) -Parent) 'Collecteur-Velociraptor.exe'))) {
        if (Test-Path -LiteralPath $cand) { $Velo = $cand; break }
    }
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
    # Conteneur produit juste apres la collecte PowerShell (meme lancement), hors conteneurs tronques par FAT32
    $Velociraptor = Get-ChildItem -LiteralPath $VeloDir -Filter '*.zip' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $CollStamp -and $_.LastWriteTime -le $CollStamp.AddHours(6) -and $_.Length -lt 4290000000 } |
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
    if (-not (Find-Evtx 'Security')) { Log '    [!] Security.evtx absent : sessions non reconstituees'; G 'Sessions (Security)' 'NON VERIFIABLE' 'Security.evtx absent de la collecte' ''; return }
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

Step "Fenetres d'analyse (sessions depuis IP publique / VPN, compte Invite, fenetres manuelles)" {
    $cand = New-Object System.Collections.Generic.List[object]
    foreach ($s in $script:Sessions) {
        $why = $null
        if ($s.TypeIP -eq 'PUBLIQUE') { $why = "session $($s.Compte) depuis IP publique $($s.IP)" }
        elseif ($s.TypeIP -eq 'VPN/CGNAT') { $why = "session $($s.Compte) depuis $($s.IP) (plage VPN/CGNAT, NetBird ?)" }
        elseif ($s.Compte -match '^(Invit|Guest)') { $why = "session du compte $($s.Compte) depuis $($s.IP)" }
        if (-not $why) { continue }
        $fin = if ($s.Fin) { $s.Fin } else { $s.Debut.AddHours(2) }
        $cand.Add([pscustomobject]@{ Debut = $s.Debut.AddMinutes(-$MargeMinutes); Fin = $fin.AddMinutes($MargeMinutes); Motif = $why + $(if (-not $s.Fin) { ' (fin inconnue : +2 h)' } else { '' }) })
    }
    foreach ($f in $Fenetres) {
        $parts = $f -split '[;|]'
        $d1 = Parse-Date $parts[0]; $d2 = Parse-Date $parts[-1]
        if ($d1 -and $d2 -and $d2 -gt $d1) { $cand.Add([pscustomobject]@{ Debut = $d1; Fin = $d2; Motif = 'fenetre manuelle' }) }
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
    if ($script:Win.Count -and $nc.Count) { G 'Couverture des journaux' 'A LIRE' "$($nc.Count) journal(aux) ne couvrent pas toutes les fenetres (rotation, journal recent) : absence d'evenement non probante" 'journaux_couverture.csv' }
    if (-not $script:Win.Count) { G 'Fenetres d analyse' 'A FAIRE' 'Aucune session suspecte detectee : preciser les fenetres avec -Fenetres' 'fenetres_analyse.csv' }
}
function WinOf($d) {
    if (-not ($d -is [datetime])) { return '' }
    (@($script:Win | Where-Object { $d -ge $_.Debut -and $d -le $_.Fin } | ForEach-Object { $_.Id }) -join ',')
}

$ToolRx = '(?i)mimikatz|chromepass|bulletspass|webbrowserpass|netpass|mailpass|passwordfox|operapass|routerpass|sniffpass|dialupass|wirelesskey|lazagne|procdump|rclone|winscp|filezilla|pscp|psftp|megasync|megacmd|anydesk|rustdesk|ngrok|cloudflared|chisel|7z|winrar|rar\.exe|advanced_(ip|port)_scanner|netscan|nmap|stub\.exe|\\s\.exe$|^s\.exe$|netbird|splashtop|tsplus|teamviewer|screenconnect|psexec|wmic|vssadmin|bcdedit|wbadmin|cipher'

# =================================================================== 2. SRUM : VOLUMES PAR APPLICATION ET PAR HEURE
Step 'SRUM : volumes reseau et disque par application, fenetres vs base de reference' {
    $db = C 'artefacts\srum\SRUDB.dat'
    if (-not (Test-Path -LiteralPath $db)) { $db = @(Get-FromZip '\\System32\\sru\\SRUDB\.dat$' 1) | Select-Object -First 1 }
    if (-not $db -or -not $Velo) { G 'Volumes reseau (SRUM)' 'NON VERIFIABLE' 'SRUDB.dat ou moteur Velociraptor absent' ''; return }
    $tmp = Join-Path $Work 'SRUDB.dat'
    Copy-Item -LiteralPath $db -Destination $tmp -Force
    $net = Invoke-Vql "SELECT TimeStamp, srum_lookup_id(file='''$tmp''', id=AppId) AS App, UserId, InterfaceLuid, BytesSent, BytesRecvd FROM parse_ese(file='''$tmp''', table='{973F5D5C-1D90-4944-BE8E-24B94231A174}')"
    $rows = foreach ($r in $net) {
        $d = To-Local $r.TimeStamp
        if (-not $d) { continue }
        [pscustomobject]@{ Releve = $d; App = $(if ($r.App) { $r.App } else { "(AppId inconnu)" }); UserId = $r.UserId; Interface = $r.InterfaceLuid; Envoye = [double]$r.BytesSent; Recu = [double]$r.BytesRecvd }
    }
    $rows = @($rows)
    if (-not $rows.Count) { G 'Volumes reseau (SRUM)' 'NON VERIFIABLE' 'Table reseau SRUM illisible ou vide' ''; return }
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
    if (-not $script:Win.Count) { G 'Volumes reseau (SRUM)' 'A FAIRE' "SRUM lu ($(Fmt $first) -> $(Fmt $last)) mais aucune fenetre a comparer" 'srum_total_par_releve.csv' }
    elseif ($hotAll.Count -or $newApp.Count) { G 'Volumes reseau (SRUM)' 'INDICE' "$($hotAll.Count) depassement(s) du max de reference, $($newApp.Count) appli(s) inconnue(s) ayant envoye >= 1 Mo dans les fenetres" 'srum_fenetres_vs_reference.csv, srum_METHODE.txt' }
    else { G 'Volumes reseau (SRUM)' 'RAS' "Aucun releve des fenetres au-dessus du max de reference ($ReferenceJours j). Detail chiffre par appli et par heure." 'srum_fenetres_vs_reference.csv, srum_METHODE.txt' }

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
    if (-not $Velo) { G 'Executions (Prefetch / Amcache / BAM)' 'NON VERIFIABLE' 'Moteur Velociraptor absent' ''; return }
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
    G 'Processus lances pendant les fenetres' $(if ($inW.Count) { 'A LIRE' } else { 'RAS' }) "$($inW.Count) trace(s) d'execution dans les fenetres (Prefetch, Amcache, BAM$(if ($n4688) { ', 4688' }))$(if (-not $n4688) { ' ; audit 4688 inactif : liste non exhaustive' })" 'executions_fenetres.csv'
}

# =================================================================== 4. NAVIGATION WEB COMPLETE
$CatRx = [ordered]@{
    'SANTE / METIER'      = '(?i)doctolib|ameli|amelipro|espacepro\.ameli|apicrypt|mssante|monespacesante|dmp\.fr|sesam-vitale|vidal|cgm|axisante|maiia|weda|medistory|hellodoc|lifen|pharmagest|leo2|winpharma|ordoclic'
    'MESSAGERIE'          = '(?i)webmail|outlook\.(live|office)|mail\.google|gmail|mail\.yahoo|laposte\.net|mail\.ovh|ovhcloud.*mail|zimbra|roundcube|protonmail|messagerie|orange\.fr/.*mail|sfr\.fr/.*mail|free\.fr/.*(mail|imp)'
    'PARTAGE / TRANSFERT' = '(?i)mega\.(nz|io)|wetransfer|swisstransfer|smash|dropbox|drive\.google|docs\.google|onedrive|1drv\.ms|sharepoint|box\.com|pcloud|gofile|file\.io|anonfiles|transfer\.sh|temp\.sh|bashupload|sendspace|mediafire|pastebin|ghostbin|catbox|filemail|uploadfiles|limewire|rapidgator|krakenfiles|send\.vis\.ee|wormhole|tmpfiles|qu\.ax|0x0\.st'
    'OUTILS / ACCES DISTANT' = '(?i)port-scanner|ip-scanner|nirsoft|mimikatz|github\.com|raw\.githubusercontent|anydesk|rustdesk|teamviewer|ngrok|rclone|netbird|splashtop|tsplus|screenconnect|7-zip|winrar|filezilla|winscp|putty'
}
function Cat-Url([string]$u) { foreach ($k in $CatRx.Keys) { if ($u -match $CatRx[$k]) { return $k } }; '' }
Step 'Navigation web complete (Chrome, Edge, Brave, Opera, Firefox) et telechargements' {
    if (-not $Velo) { G 'Navigation web' 'NON VERIFIABLE' 'Moteur Velociraptor absent' ''; return }
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
    G 'Navigation web (sessions ouvertes : Doctolib, Ameli, Apicrypt, webmail, partage)' $(if ($inWs.Count) { 'INDICE' } elseif ($inW.Count) { 'A LIRE' } else { 'RAS' }) "$($inW.Count) visite(s) dans les fenetres, dont $($inWs.Count) sur des sites sante / messagerie / partage. Historiques lus : $prof" 'navigation_fenetres.csv, navigation_sites_sensibles.csv'
}

# =================================================================== 5. ACCES AUX FICHIERS : LNK, JUMP LISTS, RECENTDOCS, SHELLBAGS, \\tsclient
$script:Acc = New-Object System.Collections.Generic.List[object]
$DataRx = '(?i)Axilog|AXI_DATABASE|AxiSoftware\\Database|\.fdb\b|\.fdp\b|\.gdb\b|\\HNDB\\|Donn[e\u00e9]es? patients?'
$TsRx   = '(?i)tsclient'
Step 'Acces aux fichiers : LNK, Jump Lists, RecentDocs, ShellBags (redirection \\tsclient, donnees metier)' {
    if (-not $Velo) { G 'Acces aux donnees / \\tsclient' 'NON VERIFIABLE' 'Moteur Velociraptor absent' ''; return }
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
    G 'Redirection de lecteurs RDP (\\tsclient)' $(if ($ts.Count -or $tsRaw.Count) { 'INDICE' } else { 'RAS' }) "$($ts.Count) trace(s) structuree(s) et $($tsRaw.Count) occurrence(s) brute(s) de \\tsclient (LNK, Jump Lists, RecentDocs, ShellBags, ruches)$lim" 'acces_fichiers_lnk_jumplists_shellbags.csv, recherche_brute_tsclient_axilog.csv'
    G 'Consultation des donnees metier (Axilog / base) avant chiffrement' $(if ($dmW.Count) { 'INDICE' } elseif ($dm.Count) { 'A LIRE' } else { 'RAS' }) "$($dm.Count) trace(s) d'acces aux donnees metier, dont $($dmW.Count) datee(s) dans les fenetres de l'attaquant$lim" 'acces_donnees_metier.csv'
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
    if (-not $vals.Count) { G 'Presse-papier / redirections RDP' 'NON VERIFIABLE' 'Ruches SYSTEM / SOFTWARE absentes' '' }
    else {
        G 'Presse-papier RDP' $(if ($clipW.Count) { 'A LIRE' } else { 'RAS' }) "Presse-papier $(if ($clipOk) { 'AUTORISE' } else { 'interdit' }) ; rdpclip.exe execute $($clipW.Count) fois dans les fenetres (copier-coller de texte ou de fichiers possible, sans trace de contenu)" 'rdp_redirections.txt'
        if (-not $driveOk) { G 'Redirection de lecteurs RDP (\\tsclient)' 'RAS' 'Redirection des lecteurs interdite par la configuration' 'rdp_redirections.txt' }
    }
}

# =================================================================== 6. $MFT ET JOURNAL USN : FICHIERS CREES / MODIFIES PENDANT LES FENETRES
Step 'Journal USN et $MFT : fichiers crees ou modifies pendant les fenetres (archives, profils)' {
    $arcRx = '(?i)\.(zip|7z|rar|tar|gz|tgz|cab|iso|vhdx?|bak|pst|sql|csv|xlsx?|pdf)$'
    $ransomRx = '(?i)\.\[[^\]]{3,80}\]\.[^.]{2,15}$|[a-z0-9._%+-]+@[a-z0-9-]+\.[a-z]{2,}'
    foreach ($x in (Read-Csv (C 'rancon\fichiers_chiffres_par_extension.csv') | Where-Object { [int64]$_.NbFichiers -ge 50 })) { $ransomRx += '|' + [regex]::Escape($x.Extension) + '$' }
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
    if (-not $covers) { G 'Creation d archives / fichiers pendant les fenetres (USN, $MFT)' 'NON VERIFIABLE' "Le journal USN collecte ne couvre pas les fenetres ($msg). Fournir le conteneur Velociraptor ($MFT) ou retirer -SansMFT." 'usn_mft_couverture.txt' }
    else { G 'Creation d archives / fichiers pendant les fenetres (USN, $MFT)' $(if ($arcs.Count) { 'INDICE' } else { 'A LIRE' }) "$($arcs.Count) archive(s) / export(s) cree(s) ou modifie(s) dans les fenetres. $msg" 'mft_fenetres.csv, usn_fenetres.csv' }
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
    G "Outils d'acces distant (journaux propres)" $(if ($hits.Count -or @($sp | Where-Object { $_.Fenetre }).Count) { 'A LIRE' } elseif ($logs.Count) { 'RAS' } else { 'NON VERIFIABLE' }) "Detectes : $tools. $($logs.Count) journal(aux) lu(s), $($hits.Count) ligne(s) aux dates des fenetres, $(@($sp | Where-Object { $_.Fenetre }).Count) evenement(s) Splashtop dans les fenetres." 'outils_distants_inventaire.csv, outils_distants_lignes_fenetres.txt'
    if ($tools -match 'netbird') {
        G 'NetBird : pairs du tunnel' $(if ($nb.Count) { 'A LIRE' } else { 'A FAIRE' }) $(if ($nb.Count) { "Liste des pairs : $($nb[0].Name) (verifier chaque pair et son proprietaire)" } else { "Pairs inconnus : journaux NetBird $(if ($nbLog.Count) { 'presents' } else { 'NON collectes' }). Relancer la collecte v2.2 (netbird status -d) ou consulter la console d'administration NetBird du compte qui l'a installe." }) 'outils_distants\'
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
    $fwState = if (-not $prof) { 'configuration non collectee' } elseif ($aOn -eq 0 -and $dOn -eq 0) { 'JOURNALISATION DESACTIVEE (connexions autorisees et bloquees, 3 profils)' } else { "journalisation active : autorisees $aOn/3 profils, bloquees $dOn/3" }
    V 'Journal du pare-feu Windows (pfirewall.log)' $fwState $(if ($fwRows.Count) { "$($fwRows[0].Date) -> $($fwRows[-1].Date)" } else { 'aucun fichier ou fichier vide' }) @($fwRows | Where-Object { $_.Fenetre }).Count $(if ($aOn -eq 0) { 'Pas de trace des connexions sortantes cote poste : seule la box peut renseigner les flux.' } else { 'Lire parefeu_fenetres.csv (flux SEND vers IP publiques).' }) 'parefeu_fenetres.csv'
    $fwEv = Get-Evtx 'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall' @(2004, 2005, 2006, 2033, 2052, 2097, 2099) $Since
    V 'Journal Firewall (modifications de regles 2004/2005/2006/2097)' $(if (-not (Find-Evtx 'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall')) { 'absent' } else { 'present' }) '' @($fwEv | Where-Object { WinOf $_.TimeCreated }).Count "$(@($fwEv).Count) modification(s) de regles sur la periode" 'evenements_fenetres.csv'

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
    V 'Transferts BITS' $(if ($bitsTxt) { "$($jobs.Count) tache(s) en cours, $($up.Count) en envoi (Upload)" } else { 'non collecte' }) $(if (-not (Find-Evtx 'Microsoft-Windows-Bits-Client/Operational')) { 'journal Bits-Client absent' } else { "$(@($bev).Count) evenement(s)" }) @($brow | Where-Object { $_.Fenetre }).Count "$($bnonms.Count) transfert(s) vers des URL non Microsoft / Google" 'bits_taches.csv, bits_evenements.csv'

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
    V 'Peripheriques USB (USBSTOR, setupapi, Partition 1006, Kernel-PnP)' "$($usb.Count) stockage(s) USB connu(s) dans USBSTOR$(if ($usbDet.Count) { ", dates detaillees collectees" })" "$($usbRows.Count) evenement(s) date(s)" $usbW.Count $(if ($usbW.Count) { 'Branchement USB pendant une fenetre : verifier qui (technicien ou attaquant).' } else { 'Aucun branchement USB date dans les fenetres (acces a distance : peu attendu).' }) 'usb_chronologie.csv'

    # SMBServer/Security et partages (5140/5145)
    $smb = Get-Evtx 'Microsoft-Windows-SMBServer/Security' @(551, 1006, 1007, 1009, 1015, 1016, 1020, 1021, 1022, 3000) $Since
    $smbR = Get-EvtxRange 'Microsoft-Windows-SMBServer/Security'
    $sh = Get-Evtx 'Security' @(5140, 5145) $Since
    $shRows = @(foreach ($e in @($sh)) { $f = Get-EvFields $e; [pscustomobject]@{ Date = Fmt $e.TimeCreated; EventID = $e.Id; Compte = $f['SubjectUserName']; IP = $f['IpAddress']; Partage = $f['ShareName']; Fichier = $f['RelativeTargetName']; Fenetre = WinOf $e.TimeCreated } })
    Out-Csv $shRows 'partages_acces_5140_5145.csv'
    V 'SMBServer/Security' $(if (-not (Find-Evtx 'Microsoft-Windows-SMBServer/Security')) { 'absent' } else { "$(@($smb).Count) evenement(s)" }) $(if ($smbR) { "$(Fmt $smbR.Debut) -> $(Fmt $smbR.Fin)" }) @($smb | Where-Object { WinOf $_.TimeCreated }).Count 'Erreurs / refus d''acces SMB du serveur de fichiers' 'evenements_fenetres.csv'
    V 'Acces aux partages (Security 5140 / 5145)' $(if (@($sh).Count) { "$(@($sh).Count) evenement(s)" } else { 'aucun (audit du partage de fichiers inactif ?)' }) '' @($shRows | Where-Object { $_.Fenetre }).Count "IP distinctes : $((($shRows | Select-Object -ExpandProperty IP -Unique) -join ', '))" 'partages_acces_5140_5145.csv'

    # DNS-Client/Operational
    $dns = Get-Evtx 'Microsoft-Windows-DNS-Client/Operational' @(3006, 3008, 3020) $Since
    $dnsRows = @(foreach ($e in @($dns)) { $f = Get-EvFields $e; $d = WinOf $e.TimeCreated; if ($d) { [pscustomobject]@{ Date = Fmt $e.TimeCreated; EventID = $e.Id; Domaine = $f['QueryName']; Resultat = $f['QueryResults']; Fenetre = $d } } })
    Out-Csv $dnsRows 'dns_requetes_fenetres.csv'
    $etat = Read-Csv (C 'evenements\etat_journaux.csv') | Where-Object { $_.Journal -match 'DNS-Client' } | Select-Object -First 1
    V 'DNS-Client/Operational' $(if ($etat) { "Active=$($etat.Active), $($etat.NbEvenements) evenement(s)" } elseif (-not (Find-Evtx 'Microsoft-Windows-DNS-Client/Operational') -or -not @($dns).Count) { 'journal vide ou desactive (desactive par defaut sous Windows)' } else { "$(@($dns).Count) requete(s)" }) '' $dnsRows.Count $(if ($dnsRows.Count) { "Domaines : $((($dnsRows | Select-Object -ExpandProperty Domaine -Unique | Select-Object -First 40) -join ', '))" } else { 'Pas de resolution DNS exploitable : se reporter au cache DNS (volatile) et a la box.' }) 'dns_requetes_fenetres.csv'

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
    foreach ($v in $ver) { G "Source : $($v.Source)" $(if ($v.EvenementsFenetres -gt 0) { 'A LIRE' } elseif ($v.Etat -match '(?i)absent|desactiv|non collecte|aucun') { 'NON VERIFIABLE' } else { 'RAS' }) "$($v.Etat). $($v.Constat)" $v.Fichier }
    Log "    $($evw.Count) evenements (tous journaux) dans les fenetres"
}

# =================================================================== 9. NOTE DE RANCON ET VEILLE
Step 'Note de rancon : contacts, revendication de vol de donnees, pistes de veille' {
    $notes = @(Get-ChildItem -LiteralPath (C 'rancon\notes') -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)recover|readme|decrypt|restore|how.?to|ransom|instruction|unlock|lisez' -and $_.Length -lt 200KB })
    if (-not $notes.Count) { $notes = @(Get-ChildItem -LiteralPath (C 'utilisateurs') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)recover|decrypt|how.?to' -and $_.Extension -match '\.(txt|html?|hta)$' } | Select-Object -First 1) }
    if (-not $notes.Count) { G 'Note de rancon' 'NON VERIFIABLE' 'Aucune note collectee' ''; return }
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
    $ext = @(Read-Csv (C 'rancon\fichiers_chiffres_par_extension.csv') | Sort-Object { [int64]$_.NbFichiers } -Descending | Select-Object -First 3)
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
    G 'Note de rancon (double extorsion revendiquee ?)' $(if ($claim) { 'INDICE' } else { 'RAS' }) $(if ($claim) { 'La note REVENDIQUE un vol / une publication de donnees : voir extraits' } else { 'La note ne revendique ni vol ni publication de donnees (absence de mention : n''exclut pas un vol). Veille a faire.' }) 'note_rancon_analyse.txt'
}

# =================================================================== 10. IDENTIFIANTS : MIMIKATZ, OUTILS NIRSOFT, GESTIONNAIRE D'IDENTIFIANTS
Step "Exposition des identifiants : mimikatz execute ?, outils NirSoft, gestionnaire d'identifiants" {
    $o = New-Object System.Collections.Generic.List[string]
    $mk = '(?i)mimikatz|mimilib|mimidrv|sekurlsa|lsadump|kiwi|Invoke-Mimikatz|privilege::debug'
    $o.Add('MIMIKATZ : PRESENCE ET EXECUTION')
    $o.Add('-----------------------------------------------------------------')
    $pf  = @($script:Exec | Where-Object { $_.Source -like 'Prefetch*' -and "$($_.Programme)" -match $mk })
    $am  = @($script:Exec | Where-Object { $_.Source -like 'Amcache*' -and "$($_.Chemin)" -match $mk })
    $bam = @($script:Exec | Where-Object { $_.Source -like 'BAM*' -and "$($_.Chemin)" -match $mk })
    $p48 = @($script:Exec | Where-Object { $_.Source -match '4688|Sysmon' -and "$($_.Chemin) $($_.Detail)" -match $mk })
    $ps  = @(Get-Evtx 'Microsoft-Windows-PowerShell/Operational' @(4104) $Since | Where-Object { $_.Message -match $mk -or (Get-EvFields $_)['ScriptBlockText'] -match $mk })
    $det = Read-Csv (C 'systeme\defender_detections.csv') | Where-Object { $_.Resources -match $mk }
    $thr = Read-Csv (C 'systeme\defender_menaces.csv') | Where-Object { $_.ThreatName -match '(?i)mimikatz|lsadump|HackTool' }
    $dev = @(Get-Evtx 'Microsoft-Windows-Windows Defender/Operational' @(1116, 1117) $Since | ForEach-Object { $f = Get-EvFields $_; [pscustomobject]@{ Date = $_.TimeCreated; Id = $_.Id; Nom = $f['Threat Name']; Chemin = $f['Path']; Action = $f['Action Name']; Processus = $f['Process Name']; Utilisateur = $f['Detection User'] } })
    $devMk = @($dev | Where-Object { "$($_.Nom) $($_.Chemin)" -match '(?i)mimikatz|lsadump' })
    $lsass = @(Get-Evtx 'Microsoft-Windows-Sysmon/Operational' @(10) $Since | Where-Object { (Get-EvFields $_)['TargetImage'] -match '(?i)lsass\.exe' })
    $dmp = @(Select-String -LiteralPath (C 'fichiers\listing_complet.csv') -Pattern '(?i)lsass[^"\\]*\.dmp"|\.dmp",\d+,' -ErrorAction SilentlyContinue | Select-Object -First 30 | ForEach-Object { $_.Line })
    $o.Add("Fichiers presents sur le disque                : $(@(Read-Csv (C 'fichiers\outils_suspects.csv') | Where-Object { $_.Chemin -match $mk }).Count) (fichiers\outils_suspects.csv)")
    $o.Add("Detections Defender (fichier)                  : $(@($det).Count) ; menaces : $((@($thr) | ForEach-Object { "$($_.ThreatName) execute=$($_.DidThreatExecute)" }) -join ' ; ')")
    $o.Add("Detections Defender (journal 1116/1117)        : $(($devMk | ForEach-Object { "$(Fmt $_.Date) $($_.Nom) par $($_.Processus) ($($_.Action))" }) -join ' ; ')")
    $o.Add("Prefetch (execution)                           : $(if ($pf.Count) { ($pf | ForEach-Object { "$($_.Programme) $(Fmt $_.Date)" }) -join ' ; ' } else { 'aucune' })")
    $o.Add("Amcache (fichier inventorie)                   : $(if ($am.Count) { ($am | ForEach-Object { "$($_.Chemin) $(Fmt $_.Date) SHA1 $($_.SHA1)" }) -join ' ; ' } else { 'aucune entree' })")
    $o.Add("BAM (execution par utilisateur)                : $(if ($bam.Count) { ($bam | ForEach-Object { "$($_.Chemin) $(Fmt $_.Date) $($_.Compte)" }) -join ' ; ' } else { 'aucune' })")
    $o.Add("4688 / Sysmon 1                                : $(if ($p48.Count) { "$($p48.Count) evenement(s)" } else { 'aucun' })")
    $o.Add("PowerShell 4104 (Invoke-Mimikatz, sekurlsa...) : $($ps.Count) bloc(s)")
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
    $nir = @($script:Exec | Where-Object { "$($_.Programme) $($_.Chemin)" -match '(?i)pass|dialupass|wirelesskey|sniffpass|lazagne|credential' -and "$($_.Chemin)" -notmatch '(?i)\\windows\\(winsxs|system32)|passkey|passwordonwake|genpass|umpass' } | Sort-Object Date)
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
    $o.Add('  A FAIRE : dans la session de CHAQUE compte, lancer "cmdkey /list" (ou LISTER_IDENTIFIANTS.bat de la cle) pour obtenir')
    $o.Add('  les cibles (NAS, serveur Lina, sites web). Si elles donnent acces a des donnees hors du serveur, l''exfiltration a pu')
    $o.Add('  se faire depuis ces systemes : verifier leurs journaux d''acces sur la periode, puis changer les mots de passe.')
    $o | Out-File (P 'identifiants_exposition.txt') -Encoding utf8
    G 'Mimikatz (execution, perimetre des identifiants)' $(if ($exec) { 'INDICE' } else { 'RAS' }) $(if ($exec) { 'Execution de mimikatz tracee : identifiants de tous les comptes du poste a considerer comme compromis' } else { "Present sur le disque, detecte par Defender ; aucune trace d'execution (Prefetch, BAM, PowerShell)" }) 'identifiants_exposition.txt'
    $netp = @($nir | Where-Object { $_.Programme -match '(?i)netpass' })
    G "Gestionnaire d'identifiants (cibles hors serveur)" 'A FAIRE' "$(@($cm | Group-Object Utilisateur).Count) compte(s) avec entrees ; $(if ($netp.Count) { 'netpass EXECUTE : les identifiants reseau / RDP du compte qui l''a lance sont a considerer comme exposes. ' })Cibles a lister avec cmdkey dans chaque session." 'identifiants_exposition.txt'
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
    $dev = @(Get-Evtx 'Microsoft-Windows-Windows Defender/Operational' @(1116, 1117) $Since | ForEach-Object { $f = Get-EvFields $_; [pscustomobject]@{ Date = $_.TimeCreated; Nom = $f['Threat Name']; Chemin = $f['Path'] } })
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
    G 'IOC (hachages)' $(if ($miss.Count) { 'A FAIRE' } else { 'RAS' }) "$($rows.Count) hachages (SHA256 fichiers, SHA1 Amcache et quarantaine). Executes sans hachage rapproche : $(($miss | Select-Object -First 15) -join ', ')" 'ioc_hachages.csv, ioc_executes_sans_hachage.txt'
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
    if ($rows) { G 'Conteneurs Velociraptor (hachage complet, integrite)' $(if ($bad.Count) { 'A FAIRE' } else { 'RAS' }) "$(@($rows).Count) conteneur(s) hache(s) en entier ; $($bad.Count) tronque(s) : $(($bad | ForEach-Object { $_.Conteneur }) -join ', ')" 'conteneurs_velociraptor.csv' }
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
        '  ioc_hachages.csv                  IOC'
        '  conteneurs_velociraptor.csv       hachage complet et integrite des conteneurs'
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
