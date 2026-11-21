# Parcours complet sur un vrai Windows GitHub, sans simulation :
#  1. kit fabrique comme pour une release sur une cle virtuelle OUTILS (S:), cle PREUVES virtuelle exFAT (R:)
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

# ------------------------------------------------------------------ 1. cles
# Deux cles, comme en intervention : OUTILS (S:, le kit) et PREUVES (R:, exFAT, la collecte).
Titre 'Kit et cles virtuelles : OUTILS S: et PREUVES R: (exFAT)'
& (Join-Path $env:GITHUB_WORKSPACE 'app\construire-kit.ps1') -Sortie "$T\kit" | Out-Null
function Nouvelle-Cle([string]$fichier, [int]$mo, [string]$nom, [string]$lettre) {
    @"
create vdisk file="$fichier" maximum=$mo type=expandable
select vdisk file="$fichier"
attach vdisk
convert mbr
create partition primary
format fs=exfat quick label=$nom
assign letter=$lettre
"@ | Set-Content -LiteralPath "$T\diskpart_$nom.txt" -Encoding ASCII
    & diskpart.exe /s "$T\diskpart_$nom.txt" | Out-Null
}
Nouvelle-Cle 'D:\cle_outils.vhdx' 4096 'OUTILS' 'S'
$vhd = 'D:\cle_preuves.vhdx'
Nouvelle-Cle $vhd 65536 'PREUVES' 'R'
Copy-Item -Path "$T\kit\DigSpill\*" -Destination 'S:\' -Recurse
Write-Host ('cle OUTILS : ' + ((Get-ChildItem 'S:\' | ForEach-Object { $_.Name }) -join ', '))
Write-Host ('cle PREUVES : ' + ((Get-Volume -DriveLetter R | ForEach-Object { "$($_.FileSystem), $([math]::Round($_.SizeRemaining / 1GB)) Go libres" })))

# ------------------------------------------------------------------ 2. scenario
Titre 'Scenario d''attaque reel et sans danger'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'scenario.ps1') -Verite "$T\verite.json"
Start-Sleep -Seconds 20

# ------------------------------------------------------------------ 3. DigSpill.exe pilote
Titre 'DigSpill.exe, parcours complet pilote comme par un technicien'
$t0 = Get-Date
# la collecte et l'analyse tournent sur le meme Windows de test : autoriser la lecture de la RAM sur le poste collecte (interdit en vrai)
$env:DIGSPILL_RAM_MEME_POSTE = '1'
$app = Start-Process -FilePath 'S:\DigSpill.exe' -ArgumentList "--auto=$T\captures_appli", '--auto-preuves=R:', '--auto-travail=D:\travail' -PassThru
# Etat toutes les 5 min : derniere ligne des journaux, processus lances par DigSpill, dernier fichier ecrit.
# Si plus rien n'est ecrit pendant 25 min : diagnostic et arret (le test ne doit pas bruler 2 h pour rien).
function Etat-Parcours {
    $j = Get-ChildItem 'R:\Collecte', 'D:\travail' -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $logs = @(Get-ChildItem 'R:\Collecte', 'D:\travail' -Recurse -Filter '*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 2)
    Write-Host ("--- {0} : dernier fichier ecrit {1} a {2:HH:mm:ss}" -f (Get-Date -Format 'HH:mm:ss'), $(if ($j) { $j.FullName } else { '-' }), $(if ($j) { $j.LastWriteTime } else { Get-Date }))
    foreach ($l in $logs) { Write-Host "    $($l.Name) : $((Get-Content -LiteralPath $l.FullName -Tail 2 -ErrorAction SilentlyContinue) -join ' | ')" }
    Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(powershell|Collecteur-Velociraptor|python|7zr|mmc|cmd|conhost|DigSpill)\.exe$' } | ForEach-Object {
        Write-Host ("    {0,6} <- {1,6} {2} cpu {3:N0} s : {4}" -f $_.ProcessId, $_.ParentProcessId, $_.Name, (($_.KernelModeTime + $_.UserModeTime) / 1e7), "$($_.CommandLine)".Substring(0, [Math]::Min(220, "$($_.CommandLine)".Length)))
    }
    return $j
}
$prochainEtat = Get-Date
# si l'ejection detache la cle virtuelle, on la "rebranche au bureau"
while (-not $app.HasExited -and ((Get-Date) - $t0).TotalMinutes -lt 110) {
    Start-Sleep -Seconds 10
    if ((Get-Date) -ge $prochainEtat) {
        $prochainEtat = (Get-Date).AddMinutes(5)
        $dernier = Etat-Parcours
        if ($dernier -and ((Get-Date) - $dernier.LastWriteTime).TotalMinutes -gt 25 -and ((Get-Date) - $t0).TotalMinutes -gt 30) { Write-Host '[!] plus rien d''ecrit depuis 25 min : parcours bloque'; break }
    }
    if (-not (Test-Path 'R:\')) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') cle R: absente apres l'ejection : rebranchement"
        @("select vdisk file=`"$vhd`"", 'attach vdisk') | Set-Content -LiteralPath "$T\rebrancher.txt" -Encoding ASCII
        & diskpart.exe /s "$T\rebrancher.txt" | Out-Null
        Start-Sleep -Seconds 5
        if (-not (Test-Path 'R:\')) { Get-Volume -FileSystemLabel 'PREUVES' -ErrorAction SilentlyContinue | Get-Partition | Set-Partition -NewDriveLetter R -ErrorAction SilentlyContinue }
    }
}
if (-not $app.HasExited) { Write-Host '[!] DigSpill.exe arrete par le test'; Etat-Parcours | Out-Null; $app.Kill() }
Write-Host ("DigSpill.exe termine en {0:N0} min, code {1}" -f ((Get-Date) - $t0).TotalMinutes, $(if ($app.HasExited) { $app.ExitCode } else { '?' }))
Bloc 'auto.log' "$T\captures_appli\auto.log" $null
foreach ($j in Get-ChildItem "$T\captures_appli" -Filter 'journal_*.txt' -ErrorAction SilentlyContinue) { Bloc $j.BaseName $j.FullName '\[!\]|\[\*\]|erreur|Erreur|ERROR|echec|Echec|code|Resultat|Interface|scell' }
$col = Get-ChildItem 'R:\Collecte' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_(scelles|analyse)$' } | Sort-Object LastWriteTime | Select-Object -Last 1
if ($col) { Bloc 'collecte.log' (Join-Path $col.FullName 'collecte.log') $null }
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
