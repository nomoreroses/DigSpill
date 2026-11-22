<#
.SYNOPSIS
    DigSpill - lit une copie de la memoire vive (RAM) avec Volatility 3, AU BUREAU, jamais sur le poste suspect.

.DESCRIPTION
    Processus, lignes de commande, code injecte et connexions lus dans l'image, avec des indices simples :
    nom qui imite un processus Windows, outil d'envoi ou d'acces distant, lancement depuis un dossier public,
    PowerShell encode, parent anormal (svchost hors services.exe, lsass hors wininit/winlogon), plusieurs lsass,
    code executable injecte (en-tete MZ dans une zone memoire privee).

    Appele par Analyse-Exfil.ps1 (etape Memoire vive), ou seul sur n'importe quelle copie de RAM :
      .\Lire-Ram.ps1 -Image D:\cridex.vmem -Sortie D:\cridex_ram

    Ecrit dans -Sortie : ram_lecture.txt (comment), ram_processus.csv, ram_reseau.csv, ram_injections.csv,
    ram_info.csv et ram_resume.json (etat, chiffres, pour la grille). Code de sortie : 0 lue, 2 illisible.

.PARAMETER Image       copie de la RAM (.raw, .vmem, .mem, .img...)
.PARAMETER Sortie      dossier des resultats
.PARAMETER Travail     dossier de travail (defaut : <Sortie>\_travail, efface a la fin)
.PARAMETER Noyau       memoire\noyau.json de la collecte DigSpill : symboles exacts, prepares hors ligne
.PARAMETER Vivants     volatile\processus.csv de la collecte : chemin et ligne de commande releves en direct
.PARAMETER Entete      lignes ajoutees en tete de ram_lecture.txt (ex. memoire_info.txt de la collecte)
.PARAMETER SansInternet  ne rien telecharger (symboles : seulement ceux deja dans outils\symboles)
.PARAMETER SansInjections  ne pas chercher le code injecte (windows.malware.malfind, le module le plus long)
#>
param(
    [Parameter(Mandatory = $true)][string]$Image,
    [Parameter(Mandatory = $true)][string]$Sortie,
    [string]$Travail,
    [string]$Noyau,
    [string]$Vivants,
    [string[]]$Entete,
    [string]$Journal,
    [switch]$SansInternet,
    [switch]$SansInjections
)
$ErrorActionPreference = 'Continue'
$Inv = [Globalization.CultureInfo]::InvariantCulture
New-Item -ItemType Directory -Force -Path $Sortie | Out-Null
$Sortie = (Resolve-Path -LiteralPath $Sortie).Path
$garderTravail = [bool]$Travail
if (-not $Travail) { $Travail = Join-Path $Sortie '_travail' }
New-Item -ItemType Directory -Force -Path $Travail | Out-Null

function Log([string]$m) {
    $l = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Write-Host $l
    if ($Journal) { try { [IO.File]::AppendAllText($Journal, $l + "`r`n", (New-Object Text.UTF8Encoding($false))) } catch {} }
}
function Fmt($d) { if ($d -is [datetime]) { $d.ToString('yyyy-MM-dd HH:mm:ss') } else { "$d" } }
function Ecrire-Csv($rows, [string]$nom) {
    $a = New-Object System.Collections.ArrayList
    foreach ($r in $rows) { if ($null -ne $r) { [void]$a.Add($r) } }
    $f = Join-Path $Sortie $nom
    if ($a.Count) { $a | Export-Csv -Path $f -NoTypeInformation -Encoding UTF8 } else { 'Aucune ligne' | Out-File $f -Encoding utf8 }
}
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

$lect = New-Object System.Collections.Generic.List[string]
$resume = [ordered]@{ Etat = 'illisible'; Image = $Image; Processus = 0; Suspects = 0; Injections = 0; Connexions = 0; Etablies = 0; Message = ''; Liste = @() }
function Terminer([int]$code) {
    $lect | Out-File (Join-Path $Sortie 'ram_lecture.txt') -Encoding utf8
    $resume | ConvertTo-Json -Depth 4 | Out-File (Join-Path $Sortie 'ram_resume.json') -Encoding utf8
    if (-not $garderTravail) { Remove-Item -LiteralPath $Travail -Recurse -Force -ErrorAction SilentlyContinue }
    exit $code
}
function Echec([string]$msg) { Log "    [!] $msg"; $lect.Add(''); $lect.Add($msg); $resume.Message = $msg; Terminer 2 }

$lect.Add("Lecture de la memoire vive - $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
foreach ($l in @($Entete)) { if ($null -ne $l) { $lect.Add($l) } }
if (-not (Test-Path -LiteralPath $Image)) { Echec "Image introuvable : $Image" }
$imgItem = Get-Item -LiteralPath $Image
$lect.Add(''); $lect.Add(('Image lue : {0} ({1:N1} Go)' -f $Image, ($imgItem.Length / 1GB)))
Log ('    Image RAM : {0} ({1:N1} Go)' -f $Image, ($imgItem.Length / 1GB))

$py = Join-Path $PSScriptRoot 'outils\python\python.exe'
if (-not (Test-Path -LiteralPath $py)) { Echec "Python et Volatility 3 absents du kit ($py) : refaire la cle avec le kit complet." }
$vol = Join-Path (Split-Path $py -Parent) 'vol.py'
$env:PYTHONIOENCODING = 'utf-8'; $env:PYTHONUTF8 = '1'
$cache = Join-Path $Travail 'volatility_cache'; New-Item -ItemType Directory -Force -Path $cache | Out-Null

# symboles du noyau : outils\symboles (garde d'une analyse a l'autre), sinon dossier de travail
$symb = Join-Path $PSScriptRoot 'outils\symboles'
try { New-Item -ItemType Directory -Force -Path $symb -ErrorAction Stop | Out-Null; [IO.File]::WriteAllText((Join-Path $symb '.ecriture'), ''); Remove-Item -LiteralPath (Join-Path $symb '.ecriture') -Force }
catch { $symb = Join-Path $Travail 'symboles'; New-Item -ItemType Directory -Force -Path $symb | Out-Null }
$horsLigne = $false
if ($Noyau -and (Test-Path -LiteralPath $Noyau)) {
    $ny = Get-Content -LiteralPath $Noyau -Raw -Encoding UTF8 | ConvertFrom-Json
    $lect.Add("Windows du poste : $($ny.Windows) (build $($ny.Build).$($ny.Ubr))")
    $horsLigne = $true
    foreach ($mod in @($ny.Modules)) {
        $dirS = Join-Path $symb "windows\$($mod.Pdb)"; New-Item -ItemType Directory -Force -Path $dirS | Out-Null
        $isf = Join-Path $dirS ('{0}-{1}.json.xz' -f $mod.Guid, $mod.Age)
        if (-not (Test-Path -LiteralPath $isf) -and -not $SansInternet) {
            for ($n = 1; $n -le 3 -and -not (Test-Path -LiteralPath $isf); $n++) {
                Log "    Symboles $($mod.Pdb) $($mod.Guid)-$($mod.Age) : serveur de symboles Microsoft (essai $n)"
                $null = Invoke-Py $py @('-m', 'volatility3.framework.symbols.windows.pdbconv', '-p', $mod.Pdb, '-g', ($mod.Guid + ('{0:X}' -f [int]$mod.Age)), '-o', $isf) (Join-Path $Travail 'pdbconv.txt') 10
                if (-not (Test-Path -LiteralPath $isf)) { Start-Sleep -Seconds 15 }
            }
        }
        $ok = Test-Path -LiteralPath $isf
        $lect.Add("Symboles $($mod.Pdb) $($mod.Guid)-$($mod.Age) : $(if ($ok) { 'prets' } elseif ($SansInternet) { 'ABSENTS (analyse sans Internet)' } else { 'ECHEC du telechargement' })")
        if (-not $ok -and $mod.Pdb -match '^ntkrnl') { $horsLigne = $false }
    }
} else { $lect.Add('Pas de noyau.json (copie hors DigSpill ou collecte anterieure a 2.8) : Volatility cherche lui-meme les symboles en ligne.') }
if (-not $horsLigne -and $SansInternet) { Echec 'Symboles du noyau absents et analyse sans Internet : RAM non lue. Relancer une fois avec Internet (les symboles sont ensuite gardes dans outils\symboles).' }

# ------------------------------------------------------------------ modules Volatility
$res = @{}
$lect.Add(''); $lect.Add('Modules Volatility 3 :')
# Un module qui echoue ecrit son message (ex. "Unsatisfied requirement") au lieu du CSV : on le garde.
function Lancer-Vol([string]$pl, [bool]$hl, [bool]$vider = $false) {
    $out = Join-Path $Travail "$pl.csv"
    Remove-Item -LiteralPath $out, "$out.err" -ErrorAction SilentlyContinue
    $argv = @($vol, '-q', '-r', 'csv', '--cache-path', $cache, '-s', $symb)
    if ($vider) { $argv += '--clear-cache' }   # un echec est garde en cache : sinon le nouvel essai echoue en 3 s
    if ($hl) { $argv += '--offline' }
    $argv += @('-f', $Image, $pl)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Log "    Volatility $pl$(if (-not $hl) { ' (symboles en ligne)' })..."
    $code = Invoke-Py $py $argv $out 30
    $brut = @(); foreach ($f in $out, "$out.err") { if (Test-Path -LiteralPath $f) { $brut += @(Get-Content -LiteralPath $f -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { "$_".Trim() }) } }
    $lignes = @()
    if ("$($brut | Select-Object -First 1)" -match '^TreeDepth,') { try { $lignes = @(Import-Csv -LiteralPath $out -Encoding UTF8) } catch {} }
    $msg = if (-not $lignes.Count -and "$($brut | Select-Object -First 1)" -notmatch '^TreeDepth,') { @($brut | Where-Object { $_ -notmatch '^Volatility 3 Framework' } | Select-Object -Last 6) } else { @() }
    $lect.Add(('  {0,-26} {1,5} lignes, {2,4} s, code {3}{4}' -f $pl, $lignes.Count, [int]$sw.Elapsed.TotalSeconds, $code, $(if (-not $hl) { ', symboles en ligne' })))
    foreach ($x in $msg) { $lect.Add("      | $x") }
    Log ('    {0} : {1} lignes en {2} s{3}' -f $pl, $lignes.Count, [int]$sw.Elapsed.TotalSeconds, $(if ($msg.Count) { ' : ' + ($msg -join ' / ') }))
    return ,$lignes
}
$modules = @('windows.info', 'windows.pslist', 'windows.cmdline', 'windows.netscan', 'windows.netstat')
if (-not $SansInjections) { $modules += 'windows.malware.malfind' }
$noyauIntrouvable = $false
foreach ($pl in $modules) {
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
$info = @{}
foreach ($r in $infoV) { $info["$($r.Variable)"] = "$($r.Value)" }
if ($infoV.Count) { $infoV | Select-Object Variable, Value | Export-Csv (Join-Path $Sortie 'ram_info.csv') -NoTypeInformation -Encoding UTF8 }
$ps = $res['windows.pslist']
if (-not $ps.Count) {
    if ($noyauIntrouvable) { Echec 'Volatility n''a pas retrouvé le noyau de Windows dans cette image (cela arrive avec une copie faite pendant que Windows tourne). Les processus et connexions relevés en direct pendant la collecte restent dans volatile\processus.csv et volatile\tcp_connexions.csv.' }
    Echec 'Volatility n''a pas pu lire la liste des processus (symboles ou format de l''image) : voir ram_lecture.txt.'
}
$majeur = 0; [void][int]::TryParse("$($info['NtMajorVersion'])", [ref]$majeur)
# parent attendu de lsass.exe : wininit.exe depuis Vista (NT 6), winlogon.exe sur XP / 2003 (NT 5)
$parentLsass = if ($majeur -ge 6 -or $majeur -eq 0) { 'wininit.exe' } else { 'winlogon.exe' }
if ($majeur) { $lect.Add("Windows lu dans l'image : NT $majeur.$($info['NtMinorVersion']), $(if ($info['Is64Bit'] -eq 'True') { '64' } else { '32' }) bits, heure de la copie $(From-VolDate $info['SystemTime'])") }

# ------------------------------------------------------------------ code injecte (malfind)
# Une zone memoire privee, executable et inscriptible qui commence par 'MZ' : un programme entier charge a la main
# dans un autre processus (Zeus, Cridex, Stuxnet...). Les autres zones signalees par malfind (code genere par .NET,
# les navigateurs) sont trop frequentes sur un Windows sain pour etre des indices.
$injections = @(foreach ($r in $res['windows.malware.malfind']) {
    $hex = "$($r.Hexdump)" -replace '\s+', ' '
    $mz = "$($r.Notes)" -match 'MZ' -or $hex -match '^(0x[0-9a-f]+\s+)?4d 5a\b'
    if (-not $mz) { continue }
    [pscustomobject]@{ PID = $r.PID; Processus = $r.Process; Debut = $r.'Start VPN'; Fin = $r.'End VPN'; Protection = $r.Protection; Notes = $r.Notes }
})
Ecrire-Csv $injections 'ram_injections.csv'

# ------------------------------------------------------------------ processus : lignes valides, lignes de commande, indices
$cmd = @{}
foreach ($r in $res['windows.cmdline']) { $a = ("$($r.Args)" -replace '\\\\', '\').Trim(); if ($a -and $a -notmatch '^(Required memory|Process .* (is|was) |N/A)') { $cmd["$($r.PID)"] = $a } }
# processus releves en direct pendant la collecte : chemin et ligne de commande quand la RAM ne les donne pas
$vivantsH = @{}
if ($Vivants -and (Test-Path -LiteralPath $Vivants)) {
    $prem = Get-Content -LiteralPath $Vivants -TotalCount 1 -Encoding UTF8
    if ($prem -and $prem.StartsWith('"')) { foreach ($r in (Import-Csv -LiteralPath $Vivants -Encoding UTF8)) { $vivantsH["$($r.ProcessId)|$("$($r.Name)".ToLower())"] = $r } }
}
$valides = @($ps | Where-Object { $_.CreateTime -match '^\d{4}-' -and $_.ImageFileName -match '^[\x20-\x7E]+$' })
$rejetes = $ps.Count - $valides.Count
$noms = @{}; foreach ($r in $valides) { $noms["$($r.PID)"] = "$($r.ImageFileName)" }
$systeme = 'svchost.exe', 'lsass.exe', 'csrss.exe', 'services.exe', 'winlogon.exe', 'wininit.exe', 'smss.exe', 'explorer.exe', 'spoolsv.exe', 'taskhostw.exe', 'dllhost.exe', 'conhost.exe', 'rundll32.exe', 'sihost.exe', 'dashost.exe', 'runtimebroker.exe', 'searchindexer.exe', 'msmpeng.exe', 'ctfmon.exe', 'dwm.exe', 'userinit.exe', 'fontdrvhost.exe', 'lsaiso.exe', 'regsvr32.exe', 'taskmgr.exe', 'audiodg.exe', 'wmiprvse.exe'
$rxEnvoi = 'rclone|megasync|megacmd|winscp|filezilla|pscp|restic|mimikatz|lazagne|procdump|netpass|webbrowserpass|mailpass|chromepass'
$rxAcces = 'anydesk|rustdesk|ngrok|cloudflared|chisel|teamviewer|screenconnect|plink|psexe'
$rxNav = '^(chrome|msedge|firefox|brave|opera|iexplore|msedgewebview2|onedrive|teams|ms-teams)\.exe$'
$procs = foreach ($r in $valides) {
    $nom = "$($r.ImageFileName)"; $pidS = "$($r.PID)"; $ligneCmd = $cmd[$pidS]; $niv = 0
    # Windows ne garde que 14 caracteres du nom (fontdrvhost.exe -> fontdrvhost.ex) : nom complet repris de la ligne de commande
    $exe = if ($ligneCmd -match '^\s*"?([^"]*?\\)?([^\\"]+\.(exe|com|scr))\b') { $Matches[2] } else { '' }
    if ($nom.Length -ge 14 -and $exe -and $exe.StartsWith($nom, [StringComparison]::OrdinalIgnoreCase)) { $nom = $exe }
    $vu = $vivantsH["$pidS|$($nom.ToLower())"]
    if (-not $vu -and $nom.Length -ge 14) { $vu = $vivantsH.Keys | Where-Object { $_ -like "$pidS|$($nom.ToLower())*" } | Select-Object -First 1 | ForEach-Object { $vivantsH[$_] } }
    if ($vu -and $nom.Length -ge 14 -and "$($vu.Name)".StartsWith($nom, [StringComparison]::OrdinalIgnoreCase)) { $nom = "$($vu.Name)" }
    $chemin = if ($vu -and $vu.ExecutablePath) { "$($vu.ExecutablePath)" } else { '' }
    if ((-not $ligneCmd -or $ligneCmd -eq '-') -and $vu -and $vu.CommandLine) { $ligneCmd = "$($vu.CommandLine)" }
    $bas = $nom.ToLower()
    $ind = New-Object System.Collections.Generic.List[string]
    if ($systeme -notcontains $bas -and -not ($bas.Length -ge 14 -and @($systeme | Where-Object { $_.StartsWith($bas) }).Count)) {
        $proche = $systeme | Where-Object { $_.Length -ge 7 -and [Math]::Abs($_.Length - $bas.Length) -le 1 -and (Get-Osa $bas $_) -eq 1 } | Select-Object -First 1
        if ($proche) { $ind.Add("nom presque identique à $proche (processus de Windows)"); $niv = [Math]::Max($niv, 3) }
    }
    # l'outil se reconnait a son nom ou a son chemin, pas a une adresse (curl vers rclone.org n'est pas rclone)
    $exeCmd = if ($ligneCmd -match '^\s*"?([^"]+?\.(exe|com|scr))\b') { $Matches[1] } else { '' }
    if ("$bas $chemin $exeCmd" -match $rxEnvoi) { $ind.Add("outil d'envoi ou de vol d'identifiants ($($Matches[0]))"); $niv = [Math]::Max($niv, 3) }
    elseif ("$bas $chemin $exeCmd" -match $rxAcces) { $ind.Add("outil d'accès à distance ($($Matches[0]))"); $niv = [Math]::Max($niv, 2) }
    if ("$chemin $ligneCmd" -match '(?i)\\Users\\Public\\|\\Windows\\Temp\\|\\AppData\\Local\\Temp\\|\\PerfLogs\\|\\\$Recycle') { $ind.Add('lancé depuis un dossier où tout le monde peut écrire'); $niv = [Math]::Max($niv, 2) }
    if ($ligneCmd -match '(?i)\s-e(nc|ncodedcommand)?\s+[A-Za-z0-9+/=]{20,}') { $ind.Add('PowerShell avec une commande encodée'); $niv = [Math]::Max($niv, 2) }
    if ($ligneCmd -match '(?i)https?://([^/\s"]+)' -and $bas -notmatch $rxNav) { $ind.Add("adresse Internet dans la ligne de commande ($($Matches[1]))"); $niv = [Math]::Max($niv, 1) }
    $par = $noms["$($r.PPID)"]
    if ($bas -eq 'svchost.exe' -and $par -and $par -ne 'services.exe') { $ind.Add("svchost.exe lancé par $par (attendu : services.exe)"); $niv = [Math]::Max($niv, 2) }
    if ($bas -eq 'lsass.exe' -and $par -and $par -ne $parentLsass) { $ind.Add("lsass.exe lancé par $par (attendu : $parentLsass)"); $niv = [Math]::Max($niv, 3) }
    $inj = @($injections | Where-Object { "$($_.PID)" -eq $pidS })
    if ($inj.Count) { $ind.Add("programme injecté dans sa mémoire ($($inj.Count) zone$(if ($inj.Count -gt 1) { 's' }) exécutable$(if ($inj.Count -gt 1) { 's' }) commençant par MZ)"); $niv = [Math]::Max($niv, 3) }
    [pscustomobject]@{ PID = $r.PID; PPID = $r.PPID; Parent = $par; Processus = $nom; Debut = (From-VolDate $r.CreateTime); Fin = (From-VolDate $r.ExitTime)
        Threads = $r.Threads; Chemin = $chemin; LigneDeCommande = $ligneCmd; Niveau = $niv; Indices = ($ind -join ' ; ') }
}
$procs = @($procs)
$nLsass = @($procs | Where-Object { $_.Processus -ieq 'lsass.exe' -and -not $_.Fin }).Count
if ($nLsass -gt 1) { foreach ($x in ($procs | Where-Object { $_.Processus -ieq 'lsass.exe' })) { $x.Niveau = [Math]::Max([int]$x.Niveau, 2); $x.Indices = (@($x.Indices, "$nLsass processus lsass.exe actifs (un seul attendu)") | Where-Object { $_ }) -join ' ; ' } }
Ecrire-Csv ($procs | Sort-Object Debut) 'ram_processus.csv'

# ------------------------------------------------------------------ reseau
$src = if (@($res['windows.netscan'] | Where-Object { "$($_.LocalAddr)" -match '^[0-9a-fA-F:.*]+$' }).Count -or -not $res.ContainsKey('windows.netstat')) { 'windows.netscan' } else { 'windows.netstat' }
$reseau = @(foreach ($r in $res[$src]) {
    $loc = "$($r.LocalAddr)"; $dist = "$($r.ForeignAddr)"
    if ($loc -notmatch '^[0-9a-fA-F:.*]+$') { continue }
    $p = $procs | Where-Object { "$($_.PID)" -eq "$($r.PID)" } | Select-Object -First 1
    [pscustomobject]@{ Protocole = $r.Proto; Local = "${loc}:$($r.LocalPort)"; IP = $dist; Port = $r.ForeignPort; Etat = $r.State; PID = $r.PID
        Processus = $(if ($p) { $p.Processus } else { "$($r.Owner)" }); Cree = (From-VolDate "$($r.Created)"); Niveau = $(if ($p) { $p.Niveau } else { 0 }); Source = $src }
})
Ecrire-Csv $reseau 'ram_reseau.csv'
$etablies = @($reseau | Where-Object { $_.Etat -match 'ESTABLISHED' -and $_.IP -notmatch '^(0\.0\.0\.0|::|\*|127\.|::1)' })

$susp = @($procs | Where-Object { $_.Niveau -ge 2 })
$lect.Add('')
$lect.Add(('Processus lus : {0} ({1} lignes illisibles ecartees)' -f $procs.Count, $rejetes))
$lect.Add(('Lignes de commande lues : {0}' -f $cmd.Count))
$lect.Add($(if ($SansInjections) { 'Code injecté : non cherché (-SansInjections)' } else { "Zones de code injecté (MZ) : $($injections.Count)" }))
$lect.Add(('Connexions lues ({0}) : {1}, dont {2} etablie(s) vers l''exterieur' -f $src, $reseau.Count, $etablies.Count))
if (-not $etablies.Count -and $majeur -ge 10) { $lect.Add('  Aucune connexion établie lue dans la RAM : sur Windows 11 24H2 / Server 2025 (build 26100), Volatility 3 ne lit pas encore la table des connexions. Voir les connexions relevées en direct pendant la collecte (tcp_connexions.csv).') }
elseif (-not $reseau.Count -and $majeur -gt 0 -and $majeur -lt 6) { $lect.Add('  Windows XP / 2003 : Volatility 3 ne lit pas les connexions de ces anciens Windows.') }
$lect.Add(('Processus avec indice fort : {0}' -f $susp.Count))
foreach ($x in $susp) { $lect.Add("  PID $($x.PID) $($x.Processus) : $($x.Indices)") }
$resume.Etat = 'lue'; $resume.Processus = $procs.Count; $resume.Suspects = $susp.Count; $resume.Injections = $injections.Count
$resume.Connexions = $reseau.Count; $resume.Etablies = $etablies.Count
$resume.Liste = @($susp | ForEach-Object { [ordered]@{ PID = "$($_.PID)"; Processus = $_.Processus; Niveau = $_.Niveau; Indices = $_.Indices } })
$resume.Message = "$($procs.Count) processus et $($reseau.Count) connexions lus dans la RAM ; $($susp.Count) processus avec indice fort$(if ($susp.Count) { ' : ' + (($susp | Select-Object -First 4 | ForEach-Object { "$($_.Processus) (PID $($_.PID))" }) -join ', ') })"
Log "    $($resume.Message)"
Terminer 0
