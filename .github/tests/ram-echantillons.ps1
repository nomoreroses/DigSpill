# Lit des copies de RAM publiques, infectees et documentees (liste Volatility, Malware Analyst's Cookbook)
# avec moteur\Lire-Ram.ps1 du kit, et compare les processus signales aux reponses publiees (ram-attendus.json).
# Les echantillons sont de vieux Windows XP : ils testent les indices de DigSpill, pas la copie de la RAM.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$T = 'C:\ram_test'
New-Item -ItemType Directory -Force -Path $T | Out-Null

Write-Host "===== $(Get-Date -Format 'HH:mm:ss') Kit (Python + Volatility 3)"
& (Join-Path $env:GITHUB_WORKSPACE 'app\construire-kit.ps1') -Sortie "$T\kit" | Out-Null
$lire = "$T\kit\DigSpill\moteur\Lire-Ram.ps1"
if (-not (Test-Path $lire)) { Write-Host '[!] kit incomplet'; exit 1 }

# Pack de symboles de la Volatility Foundation : les noyaux de Windows XP n'ont pas de symboles complets
# sur le serveur de Microsoft ("_ETHREAD" absent). Inutile pour les vrais postes (Windows 10/11 : noyau.json).
$pack = "$T\kit\DigSpill\moteur\outils\symboles\windows.zip"
New-Item -ItemType Directory -Force -Path (Split-Path $pack) | Out-Null
try { Invoke-WebRequest -UseBasicParsing 'https://downloads.volatilityfoundation.org/volatility3/symbols/windows.zip' -OutFile $pack -TimeoutSec 900; Write-Host ("pack de symboles : {0:N0} Mo" -f ((Get-Item $pack).Length / 1MB)) }
catch { Write-Host "[!] pack de symboles : $($_.Exception.Message)" }

$cas = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ram-attendus.json') -Raw | ConvertFrom-Json
$bilan = New-Object System.Collections.Generic.List[object]
foreach ($c in $cas) {
    Write-Host ''
    Write-Host "===== $(Get-Date -Format 'HH:mm:ss') $($c.Nom) : $($c.Description)"
    $dir = Join-Path $T $c.Nom; New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $zip = Join-Path $dir 'echantillon.zip'
    $ok = $false
    foreach ($u in $c.Urls) {
        try { Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $zip -TimeoutSec 600; $ok = (Get-Item $zip).Length -gt 1MB; Write-Host ("telecharge : {0} ({1:N0} Mo)" -f $u, ((Get-Item $zip).Length / 1MB)) }
        catch { Write-Host "[!] $u : $($_.Exception.Message)" }
        if ($ok) { break }
    }
    if (-not $ok -and $c.Parts) {
        # archive coupee en morceaux dans un depot GitHub : on les met bout a bout
        try {
            $fs = [IO.File]::Create($zip)
            foreach ($u in $c.Parts) { $part = "$zip.part"; Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $part -TimeoutSec 600; $b = [IO.File]::ReadAllBytes($part); $fs.Write($b, 0, $b.Length); Write-Host "morceau : $u" }
            $fs.Close(); $ok = (Get-Item $zip).Length -gt 1MB
        } catch { try { $fs.Close() } catch {}; Write-Host "[!] morceaux : $($_.Exception.Message)" }
    }
    if (-not $ok) { $bilan.Add([pscustomobject]@{ Cas = $c.Nom; Resultat = 'NON TELECHARGE'; Attendus = ($c.Attendus -join ','); Signales = ''; Manquants = ''; EnPlus = '' }); continue }
    try { Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $dir 'x') -Force } catch { Write-Host "[!] decompression : $($_.Exception.Message)" }
    $img = Get-ChildItem -LiteralPath (Join-Path $dir 'x') -Recurse -File | Where-Object { $_.Extension -match '^\.(vmem|raw|mem|img|bin|dmp)$' } | Sort-Object Length -Descending | Select-Object -First 1
    if (-not $img) { $img = Get-ChildItem -LiteralPath (Join-Path $dir 'x') -Recurse -File | Sort-Object Length -Descending | Select-Object -First 1 }
    Write-Host ("image : {0} ({1:N0} Mo), SHA256 {2}" -f $img.Name, ($img.Length / 1MB), (Get-FileHash -LiteralPath $img.FullName -Algorithm SHA256).Hash)
    $sortie = Join-Path $dir 'ram'
    & $lire -Image $img.FullName -Sortie $sortie
    Write-Host "@@DEBUT ram_lecture_$($c.Nom)"
    Get-Content -LiteralPath (Join-Path $sortie 'ram_lecture.txt') -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
    Write-Host "@@FIN ram_lecture_$($c.Nom)"
    Write-Host "@@DEBUT injections_$($c.Nom)"
    Get-Content -LiteralPath (Join-Path $sortie 'ram_injections.csv') -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
    Write-Host "@@FIN injections_$($c.Nom)"
    $rs = $null; try { $rs = Get-Content -LiteralPath (Join-Path $sortie 'ram_resume.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    if (-not $rs -or $rs.Etat -ne 'lue') { $bilan.Add([pscustomobject]@{ Cas = $c.Nom; Resultat = 'ILLISIBLE'; Attendus = ($c.Attendus -join ','); Signales = ''; Manquants = ''; EnPlus = $(if ($rs) { $rs.Message }) }); continue }
    $signales = @($rs.Liste | ForEach-Object { [int]$_.PID })
    $manq = @($c.Attendus | Where-Object { $signales -notcontains [int]$_ })
    $plus = @($rs.Liste | Where-Object { $c.Attendus -notcontains [int]$_.PID } | ForEach-Object { "$($_.Processus) $($_.PID)" })
    $bilan.Add([pscustomobject]@{ Cas = $c.Nom; Resultat = $(if ($manq.Count) { 'MANQUE' } else { 'TROUVE' }); Attendus = ($c.Attendus -join ','); Signales = ($signales -join ','); Manquants = ($manq -join ','); EnPlus = ($plus -join ' | ') })
}
Write-Host ''
Write-Host '@@DEBUT bilan'
$bilan | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
Write-Host '@@FIN bilan'
if (@($bilan | Where-Object { $_.Resultat -in 'MANQUE', 'ILLISIBLE' }).Count -or -not @($bilan | Where-Object { $_.Resultat -eq 'TROUVE' }).Count) { exit 1 }
exit 0
