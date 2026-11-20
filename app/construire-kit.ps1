<#
.SYNOPSIS
    DigSpill - fabrique le kit de la cle OUTILS : DigSpill.exe + moteur\, outils tiers compris, et DigSpill.zip.
.DESCRIPTION
    Utilise par le workflow GitHub "Kit DigSpill" ; peut aussi tourner sur un PC Windows avec Internet.
      powershell -ExecutionPolicy Bypass -File app\construire-kit.ps1            kit complet
      powershell -ExecutionPolicy Bypass -File app\construire-kit.ps1 -SansOutilsTiers

    Resultat : kit\DigSpill\DigSpill.exe, kit\DigSpill\moteur\..., kit\DigSpill.zip
    Outils tiers telecharges depuis leurs sources officielles, avec leur licence et leur SHA256 :
      7zr.exe (7-Zip, Igor Pavlov, LGPL)                      https://www.7-zip.org
      winpmem_mini_x64_rc2.exe (WinPmem, Velocidex, Apache 2.0) https://github.com/Velocidex/WinPmem
      Collecteur-Velociraptor.exe : collecteur hors ligne genere avec moteur\velociraptor\spec.yaml
        (Velociraptor, Velocidex / Rapid7, AGPL 3.0)          https://github.com/Velocidex/velociraptor
#>
param(
    [string]$Sortie,
    [switch]$SansOutilsTiers
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Depot = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
if (-not $Sortie) { $Sortie = Join-Path $Depot 'kit' }
$Kit    = Join-Path $Sortie 'DigSpill'
$Moteur = Join-Path $Kit 'moteur'
$Outils = Join-Path $Moteur 'outils'
$Tmp    = Join-Path $Sortie '_tmp'
function Info([string]$m) { Write-Host "  $m" }

if (Test-Path -LiteralPath $Sortie) { Remove-Item -LiteralPath $Sortie -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Kit, $Tmp | Out-Null

# ---------------------------------------------------------------- 1. DigSpill.exe
Info '1. Compilation de DigSpill.exe'
& cmd.exe /c (Join-Path $Depot 'app\CONSTRUIRE.bat')
if ($LASTEXITCODE -ne 0) { throw 'Compilation de DigSpill.exe en echec' }
Copy-Item -LiteralPath (Join-Path $Depot 'app\bin\DigSpill.exe') -Destination $Kit

# ---------------------------------------------------------------- 2. moteur (sans les outils de developpement)
Info '2. Moteur : scripts, interface, secours'
Copy-Item -LiteralPath (Join-Path $Depot 'moteur') -Destination $Moteur -Recurse
foreach ($x in 'interface\dev', 'outils\bases', 'outils\.gitkeep', 'digspill.ini') {
    $p = Join-Path $Moteur $x
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
}
New-Item -ItemType Directory -Force -Path $Outils | Out-Null

# ---------------------------------------------------------------- 3. outils tiers
$entetes = @{ 'User-Agent' = 'DigSpill-kit'; 'Accept' = 'application/vnd.github+json' }
if ($env:GITHUB_TOKEN) { $entetes['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
function Telecharger([string]$url, [string]$dest) {
    Info "   $url"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest -Headers @{ 'User-Agent' = 'DigSpill-kit' }
    if (-not (Test-Path -LiteralPath $dest) -or (Get-Item -LiteralPath $dest).Length -eq 0) { throw "Telechargement vide : $url" }
}
function Release([string]$depot, [string]$tag) {
    $u = if ($tag) { "https://api.github.com/repos/$depot/releases/tags/$tag" } else { "https://api.github.com/repos/$depot/releases/latest" }
    Invoke-RestMethod -Uri $u -Headers $entetes
}
function Sha([string]$f) { (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash }
$notes = New-Object System.Collections.Generic.List[string]
$notes.Add('DigSpill - outils tiers embarques dans moteur\outils')
$notes.Add('==============================================')
$notes.Add("Kit fabrique le $((Get-Date).ToString('yyyy-MM-dd HH:mm')) par app\construire-kit.ps1, depuis les sources officielles.")
$notes.Add('Chaque outil garde sa propre licence. Ils ne sont pas modifies (le collecteur Velociraptor est genere par Velociraptor lui-meme).')
$notes.Add('')

if (-not $SansOutilsTiers) {
    Info '3. Outils tiers'
    # 7zr.exe
    $f = Join-Path $Outils '7zr.exe'
    Telecharger 'https://www.7-zip.org/a/7zr.exe' $f
    $notes.Add('7zr.exe')
    $notes.Add('  7-Zip (version console reduite), Igor Pavlov - GNU LGPL. https://www.7-zip.org  Source : https://www.7-zip.org/download.html')
    $notes.Add("  SHA256 $(Sha $f)")
    $notes.Add('')

    # WinPmem (memoire vive)
    $rel = Release 'Velocidex/WinPmem' 'v4.0.rc1'
    $a = $rel.assets | Where-Object { $_.name -match '^winpmem_mini_x64.*\.exe$' } | Select-Object -First 1
    if (-not $a) { throw 'WinPmem : asset winpmem_mini_x64*.exe introuvable dans la release v4.0.rc1' }
    $f = Join-Path $Outils 'winpmem_mini_x64_rc2.exe'
    Telecharger $a.browser_download_url $f
    $lic = Join-Path $Outils 'LICENCE-WinPmem.txt'
    try { Telecharger 'https://raw.githubusercontent.com/Velocidex/WinPmem/master/LICENSE' $lic } catch { Info "   [!] licence WinPmem non telechargee : $($_.Exception.Message)" }
    $notes.Add('winpmem_mini_x64_rc2.exe')
    $notes.Add("  WinPmem $($rel.tag_name) ($($a.name)), Velocidex - Apache License 2.0 (LICENCE-WinPmem.txt). https://github.com/Velocidex/WinPmem")
    $notes.Add("  SHA256 $(Sha $f)")
    $notes.Add('')

    # Velociraptor : binaire officiel + definitions Windows.Triage.Targets, puis collecteur genere avec spec.yaml
    # derniere release stable qui publie un binaire Windows 64 bits (une release de correctif peut n'avoir que quelques plateformes)
    $rel = $null; $a = $null
    # PowerShell 5.1 ne deroule pas un tableau JSON renvoye par Invoke-RestMethod : passer par une variable
    $liste = Invoke-RestMethod -Uri 'https://api.github.com/repos/Velocidex/velociraptor/releases?per_page=15' -Headers $entetes
    foreach ($r in $liste) {
        if ($r.prerelease -or $r.draft) { continue }
        $exe = @($r.assets | Where-Object { $_.name -match '(?i)windows-amd64.*\.exe$' -and $_.name -notmatch '(?i)legacy|debug|\.sig' })
        Info "   Velociraptor $($r.tag_name) : $(@($r.assets).Count) fichiers, $($exe.Count) binaire(s) Windows 64 bits"
        if (-not $exe.Count) { Info ('     ' + ((@($r.assets) | ForEach-Object { $_.name }) -join ', ')) }
        if ($exe.Count) { $rel = $r; $a = ($exe | Sort-Object @{ Expression = { $_.name -match '(?i)-windows-amd64\.exe$' }; Descending = $true } | Select-Object -First 1); break }
    }
    if (-not $a) { throw 'Velociraptor : aucun binaire windows-amd64 dans les 15 dernieres releases' }
    $velo = Join-Path $Tmp $a.name
    Telecharger $a.browser_download_url $velo
    $defs = Join-Path $Tmp 'defs'
    New-Item -ItemType Directory -Force -Path $defs | Out-Null
    $zdef = Join-Path $Tmp 'Windows.Triage.Targets.zip'
    try { Telecharger 'https://raw.githubusercontent.com/Velocidex/velociraptor-triage-collector/gh-pages/artifacts/Windows.Triage.Targets.zip' $zdef }
    catch { Telecharger 'https://triage.velocidex.com/artifacts/Windows.Triage.Targets.zip' $zdef }
    Expand-Archive -LiteralPath $zdef -DestinationPath $defs -Force
    $ds = Join-Path $Tmp 'datastore'
    New-Item -ItemType Directory -Force -Path $ds | Out-Null
    $debut = (Get-Date).AddSeconds(-5)
    Info "   Generation du collecteur ($($rel.tag_name))"
    Push-Location $Tmp
    try {
        $ErrorActionPreference = 'Continue'
        & $velo --definitions $defs collector --datastore $ds (Join-Path $Depot 'moteur\velociraptor\spec.yaml') 2>&1 | ForEach-Object { Info "   | $_" }
        Info "   code de sortie : $LASTEXITCODE"
    } finally { $ErrorActionPreference = 'Stop'; Pop-Location }
    # le collecteur repacke garde la date du binaire d'origine : pas de filtre sur la date dans le dossier temporaire du kit (neuf a chaque fois)
    $cands = @(Get-ChildItem -LiteralPath $Tmp -Recurse -File -Filter '*.exe' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $velo }) +
             @(Get-ChildItem -LiteralPath (Join-Path $env:TEMP 'gui_datastore') -Recurse -File -Filter '*.exe' -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -ge $debut })
    $c = $cands | Sort-Object @{ Expression = { $_.Name -like '*Collecteur*' }; Descending = $true }, LastWriteTime -Descending | Select-Object -First 1
    if (-not $c) { throw 'Collecteur Velociraptor non genere (aucun .exe dans le datastore)' }
    $f = Join-Path $Outils 'Collecteur-Velociraptor.exe'
    Copy-Item -LiteralPath $c.FullName -Destination $f
    $lic = Join-Path $Outils 'LICENCE-Velociraptor.txt'
    try { Telecharger 'https://raw.githubusercontent.com/Velocidex/velociraptor/master/LICENSE' $lic } catch { Info "   [!] licence Velociraptor non telechargee : $($_.Exception.Message)" }
    $notes.Add('Collecteur-Velociraptor.exe')
    $notes.Add("  Collecteur hors ligne genere par Velociraptor $($rel.tag_name) ($($a.name)) avec moteur\velociraptor\spec.yaml")
    $notes.Add('  et les definitions Windows.Triage.Targets (Velocidex/velociraptor-triage-collector).')
    $notes.Add('  Velociraptor, Velocidex / Rapid7 - GNU AGPL 3.0 (LICENCE-Velociraptor.txt). Source : https://github.com/Velocidex/velociraptor')
    $notes.Add("  SHA256 binaire officiel $(Sha $velo)")
    $notes.Add("  SHA256 collecteur       $(Sha $f)")
    $notes.Add('')
} else {
    Info '3. Outils tiers : non inclus (-SansOutilsTiers)'
    $notes.Add('Kit fabrique SANS outils tiers : ajouter 7zr.exe, winpmem_mini_x64_rc2.exe et Collecteur-Velociraptor.exe dans ce dossier.')
}
[IO.File]::WriteAllLines((Join-Path $Outils 'LISEZ-MOI-OUTILS.txt'), $notes, (New-Object Text.UTF8Encoding($true)))

# ---------------------------------------------------------------- 4. zip
Info '4. DigSpill.zip'
Remove-Item -LiteralPath $Tmp -Recurse -Force
$zip = Join-Path $Sortie 'DigSpill.zip'
# le collecteur repacke porte une date anterieure a 1980, que le format zip ne sait pas stocker
Get-ChildItem -LiteralPath $Kit -Recurse -File | Where-Object { $_.LastWriteTime.Year -lt 1980 } | ForEach-Object { $_.LastWriteTime = Get-Date }
Compress-Archive -Path (Join-Path $Kit '*') -DestinationPath $zip -CompressionLevel Optimal
Get-ChildItem -LiteralPath $Kit -Recurse -File | ForEach-Object { '{0,12:N0}  {1}' -f $_.Length, $_.FullName.Substring($Kit.Length + 1) } | Write-Host
Info ("Kit pret : {0} ({1:N1} Mo)" -f $zip, ((Get-Item -LiteralPath $zip).Length / 1MB))
