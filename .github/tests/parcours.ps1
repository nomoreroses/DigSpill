# Parcours complet sur un vrai Windows GitHub, sans simulation :
#  1. kit fabrique comme pour une release, copie a la racine d'une cle virtuelle exFAT R: (mode une seule cle)
#  2. scenario d'attaque reel et sans danger (scenario.ps1), verite terrain dans C:\test\verite.json
#  3. DigSpill.exe pilote comme par un technicien (--auto) : intervention, feu vert, cle PREUVES, collecte,
#     scelle, ejection ; puis au bureau : copie verifiee, analyse complete, interface
#  4. interface ouverte dans Chrome : chaque ecran capture, erreurs relevees, comparaison avec la verite terrain
# Les captures sont ecrites dans le journal du job en base64, entre @@PNG <nom> et @@FINPNG.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$T = 'C:\test'
New-Item -ItemType Directory -Force -Path $T, "$T\captures_appli", "$T\captures_interface" | Out-Null
function Titre([string]$t) { Write-Host ''; Write-Host "===== $(Get-Date -Format 'HH:mm:ss') $t" }
function Bloc([string]$nom, [string]$fichier, [string]$filtre) {
    Write-Host "@@DEBUT $nom"
    if (Test-Path -LiteralPath $fichier) {
        $l = Get-Content -LiteralPath $fichier -Encoding UTF8
        if ($filtre) { $l = $l | Where-Object { $_ -match $filtre } }
        $l | ForEach-Object { Write-Host $_ }
    } else { Write-Host '(absent)' }
    Write-Host "@@FIN $nom"
}
function Png([string]$dossier, [string]$prefixe) {
    foreach ($f in Get-ChildItem -LiteralPath $dossier -Filter '*.png' -ErrorAction SilentlyContinue | Sort-Object Name) {
        $b = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.FullName))
        Write-Host "@@PNG $prefixe$($f.Name)"
        for ($i = 0; $i -lt $b.Length; $i += 4000) { Write-Host $b.Substring($i, [Math]::Min(4000, $b.Length - $i)) }
        Write-Host '@@FINPNG'
    }
}

# ------------------------------------------------------------------ 1. cle
Titre 'Kit et cle virtuelle exFAT R: (OUTILS et PREUVES sur la meme cle)'
& (Join-Path $env:GITHUB_WORKSPACE 'app\construire-kit.ps1') -Sortie "$T\kit" | Out-Null
$vhd = 'D:\cle_digspill.vhdx'
@"
create vdisk file="$vhd" maximum=65536 type=expandable
select vdisk file="$vhd"
attach vdisk
convert mbr
create partition primary
format fs=exfat quick label=PREUVES
assign letter=R
"@ | Set-Content -LiteralPath "$T\diskpart.txt" -Encoding ASCII
& diskpart.exe /s "$T\diskpart.txt" | Out-Null
Copy-Item -Path "$T\kit\DigSpill\*" -Destination 'R:\' -Recurse
Write-Host ('racine de la cle : ' + ((Get-ChildItem 'R:\' | ForEach-Object { $_.Name }) -join ', '))

# ------------------------------------------------------------------ 2. scenario
Titre 'Scenario d''attaque reel et sans danger'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'scenario.ps1') -Verite "$T\verite.json"
Start-Sleep -Seconds 20

# ------------------------------------------------------------------ 3. DigSpill.exe pilote
Titre 'DigSpill.exe, parcours complet pilote comme par un technicien'
$t0 = Get-Date
$app = Start-Process -FilePath 'R:\DigSpill.exe' -ArgumentList "--auto=$T\captures_appli", '--auto-preuves=R:', '--auto-travail=D:\travail' -PassThru
# si l'ejection detache la cle virtuelle, on la "rebranche au bureau"
while (-not $app.HasExited -and ((Get-Date) - $t0).TotalMinutes -lt 140) {
    Start-Sleep -Seconds 10
    if (-not (Test-Path 'R:\')) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') cle R: absente apres l'ejection : rebranchement"
        @("select vdisk file=`"$vhd`"", 'attach vdisk') | Set-Content -LiteralPath "$T\rebrancher.txt" -Encoding ASCII
        & diskpart.exe /s "$T\rebrancher.txt" | Out-Null
        Start-Sleep -Seconds 5
        if (-not (Test-Path 'R:\')) { Get-Volume -FileSystemLabel 'PREUVES' -ErrorAction SilentlyContinue | Get-Partition | Set-Partition -NewDriveLetter R -ErrorAction SilentlyContinue }
    }
}
if (-not $app.HasExited) { Write-Host '[!] DigSpill.exe toujours en cours apres 140 min : arrete'; $app.Kill() }
Write-Host ("DigSpill.exe termine en {0:N0} min, code {1}" -f ((Get-Date) - $t0).TotalMinutes, $(if ($app.HasExited) { $app.ExitCode } else { '?' }))
Bloc 'auto.log' "$T\captures_appli\auto.log" $null
foreach ($j in Get-ChildItem "$T\captures_appli" -Filter 'journal_*.txt' -ErrorAction SilentlyContinue) { Bloc $j.BaseName $j.FullName '\[!\]|\[\*\]|erreur|Erreur|ERROR|echec|Echec|code|Resultat|Interface|scell' }
$col = Get-ChildItem 'R:\Collecte' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_(scelles|analyse)$' } | Sort-Object LastWriteTime | Select-Object -Last 1
if ($col) { Bloc 'collecte.log' (Join-Path $col.FullName 'collecte.log') '\[!\]|\[\*\]|RAM' }
$ana = Get-ChildItem 'D:\travail' -Recurse -Filter 'analyse.log' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($ana) { Bloc 'analyse.log' $ana.FullName '\[!\]|\[\*\]|erreur|Erreur' }

# ------------------------------------------------------------------ 4. interface
$html = if (Test-Path "$T\captures_appli\interface.txt") { (Get-Content "$T\captures_appli\interface.txt" -Raw).Trim() } else { '' }
Titre "Interface : $html"
if ($html -and (Test-Path -LiteralPath $html)) {
    Write-Host ("taille : {0:N1} Mo" -f ((Get-Item -LiteralPath $html).Length / 1MB))
    Push-Location (Join-Path $PSScriptRoot '.')
    & npm.cmd install --silent --no-audit --no-fund puppeteer-core@23 2>&1 | Out-Null
    & node.exe (Join-Path $PSScriptRoot 'interface.js') $html "$T\verite.json" "$T\captures_interface"
    Pop-Location
} else { Write-Host '[!] pas d''interface produite' }

Titre 'Captures'
Png "$T\captures_appli" 'appli_'
Png "$T\captures_interface" 'interface_'
if (-not (Test-Path "$T\captures_appli\auto_code.txt") -or (Get-Content "$T\captures_appli\auto_code.txt" -Raw).Trim() -ne '0') { exit 1 }
