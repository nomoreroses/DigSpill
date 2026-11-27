<#
.SYNOPSIS
    DigSpill - remplace le kit par une nouvelle version, une fois DigSpill.exe ferme (lance par Mises a jour).
.DESCRIPTION
    Copie de travail dans %TEMP%\DigSpill-maj (le dossier moteur\ est remplace). La nouvelle version est copiee
    a cote de l'ancienne (moteur.nouveau), les fichiers propres a ce kit sont repris (digspill.ini, bases
    telechargees, symboles), puis les versions sont echangees par renommage. Au moindre echec, l'ancienne
    version revient. DigSpill est relance avec --maj=ok ou --maj=echec ; journal : %TEMP%\DigSpill-maj\journal.txt
#>
param([int]$Attendre, [string]$Nouveau, [string]$Kit)
$journal = Join-Path (Split-Path $PSCommandPath) 'journal.txt'
function J([string]$m) { Add-Content -LiteralPath $journal -Value ((Get-Date -Format 'HH:mm:ss') + '  ' + $m) -Encoding UTF8 }
function Renommer([string]$de, [string]$vers) {
    for ($i = 0; $i -lt 10; $i++) { try { Rename-Item -LiteralPath $de -NewName $vers -ErrorAction Stop; return } catch { Start-Sleep -Seconds 1 } }
    throw "renommage impossible : $de"
}
J "attente de la fermeture de DigSpill ($Attendre)"
try { Wait-Process -Id $Attendre -Timeout 120 -ErrorAction Stop } catch {}
Start-Sleep -Seconds 1
if ($Kit -match '^[A-Za-z]:$') { $Kit += '\' }   # kit a la racine de la cle : « F: » seul designerait le dossier courant de F:
$m = Join-Path $Kit 'moteur'; $mN = "$m.nouveau"; $mA = "$m.ancien"
$e = Join-Path $Kit 'DigSpill.exe'; $eN = "$e.nouveau"; $eA = "$e.ancien"
$ok = $false; $etape = 0
try {
    foreach ($x in $mN, $mA, $eN, $eA) { if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Recurse -Force -ErrorAction Stop } }
    J 'copie de la nouvelle version a cote de l''ancienne'
    & robocopy.exe (Join-Path $Nouveau 'moteur') $mN /E /R:2 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "copie de moteur impossible (robocopy $LASTEXITCODE)" }
    Copy-Item -LiteralPath (Join-Path $Nouveau 'DigSpill.exe') -Destination $eN -Force -ErrorAction Stop
    J 'reprise des fichiers propres a ce kit (reglages, bases telechargees)'
    foreach ($g in 'digspill.ini', 'outils\bases', 'outils\symboles') {
        $src = Join-Path $m $g; $dst = Join-Path $mN $g
        if (-not (Test-Path -LiteralPath $src)) { continue }
        if ((Get-Item -LiteralPath $src).PSIsContainer) { & robocopy.exe $src $dst /E /XC /XN /XO /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null }
        elseif (-not (Test-Path -LiteralPath $dst)) { Copy-Item -LiteralPath $src -Destination $dst -ErrorAction SilentlyContinue }
    }
    J 'echange des versions'
    Renommer $m 'moteur.ancien'; $etape = 1
    Renommer $mN 'moteur'; $etape = 2
    Renommer $e 'DigSpill.exe.ancien'; $etape = 3
    Renommer $eN 'DigSpill.exe'; $etape = 4
    $ok = $true
    J 'nouvelle version en place'
    Remove-Item -LiteralPath $mA, $eA -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    J "ECHEC : $($_.Exception.Message)"
    try {
        if ($etape -ge 3) { Renommer $eA 'DigSpill.exe' }
        if ($etape -ge 2) { Renommer $m 'moteur.nouveau' }
        if ($etape -ge 1) { Renommer $mA 'moteur' }
        J 'ancienne version remise en place'
    } catch { J "retour en arriere incomplet : $($_.Exception.Message) - voir $Kit" }
    Remove-Item -LiteralPath $mN, $eN -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $Nouveau, (Join-Path (Split-Path $PSCommandPath) 'DigSpill.zip') -Recurse -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $e -ArgumentList $(if ($ok) { '--maj=ok' } else { '--maj=echec' })
