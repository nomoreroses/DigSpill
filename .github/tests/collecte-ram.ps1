# Test de bout en bout sur un Windows GitHub : vraie collecte DigSpill (mode complet) depuis une cle exFAT,
# puis verification de la copie de la RAM et lecture de l'image par Volatility 3 (symboles prepares, hors ligne).
# Les resultats complets sont ecrits dans le journal du job, entre des balises @@DEBUT / @@FIN.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

function Titre([string]$t) { Write-Host ''; Write-Host "===== $t" }
function Bloc([string]$nom, [string]$fichier) {
    Write-Host "@@DEBUT $nom"
    if (Test-Path -LiteralPath $fichier) { Get-Content -LiteralPath $fichier -Encoding UTF8 | ForEach-Object { Write-Host $_ } } else { Write-Host '(absent)' }
    Write-Host "@@FIN $nom"
}
function EtatPmem([string]$quand) {
    $sd = Get-CimInstance Win32_SystemDriver -Filter "Name='pmem'" -ErrorAction SilentlyContinue
    $reg = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\pmem' -ErrorAction SilentlyContinue
    $flag = if ($reg -and $reg.PSObject.Properties['DeleteFlag']) { " | DeleteFlag $($reg.DeleteFlag)" } else { '' }
    if ($sd) { Write-Host ("pilote Windows 'pmem' {0} : {1} | etat {2} | demarrage {3}{4}" -f $quand, $sd.DisplayName, $sd.State, $sd.StartMode, $flag) }
    else { Write-Host "pilote Windows 'pmem' $quand : absent" }
}
function Lire-Rsds([string]$chemin) {
    $b = [IO.File]::ReadAllBytes($chemin)
    $pe = [BitConverter]::ToInt32($b, 0x3C); $nsec = [BitConverter]::ToUInt16($b, $pe + 6)
    $opt = $pe + 24; $tailleOpt = [BitConverter]::ToUInt16($b, $pe + 20)
    $dirDebug = $opt + 112 + 6 * 8
    $rvaDbg = [BitConverter]::ToUInt32($b, $dirDebug); $tailleDbg = [BitConverter]::ToUInt32($b, $dirDebug + 4)
    $sec = $opt + $tailleOpt; $p = $null
    for ($i = 0; $i -lt $nsec; $i++) {
        $s = $sec + 40 * $i
        $va = [BitConverter]::ToUInt32($b, $s + 12); $vs = [Math]::Max([BitConverter]::ToUInt32($b, $s + 8), [BitConverter]::ToUInt32($b, $s + 16))
        if ($rvaDbg -ge $va -and $rvaDbg -lt $va + $vs) { $p = $rvaDbg - $va + [BitConverter]::ToUInt32($b, $s + 20) }
    }
    for ($k = 0; $k -lt $tailleDbg / 28; $k++) {
        $e = $p + 28 * $k
        if ([BitConverter]::ToUInt32($b, $e + 12) -eq 2) {
            $cv = [BitConverter]::ToUInt32($b, $e + 24)
            $g = New-Object Guid (, [byte[]]$b[($cv + 4)..($cv + 19)])
            $age = [BitConverter]::ToUInt32($b, $cv + 20)
            $fin = [Array]::IndexOf($b, [byte]0, $cv + 24)
            return [pscustomobject]@{ Pdb = [Text.Encoding]::ASCII.GetString($b, $cv + 24, $fin - $cv - 24); Guid = $g.ToString('N').ToUpper(); Age = $age }
        }
    }
    throw "CodeView absent : $chemin"
}

# ------------------------------------------------------------------ 1. cle exFAT avec le kit
Titre 'Cle de test : disque virtuel exFAT R:, kit DigSpill fabrique comme pour une release'
& (Join-Path $env:GITHUB_WORKSPACE 'app\construire-kit.ps1') -Sortie 'C:\test\kit' | Out-Null
$vhd = 'D:\cle_test.vhdx'
@"
create vdisk file="$vhd" maximum=61440 type=expandable
select vdisk file="$vhd"
attach vdisk
convert mbr
create partition primary
format fs=exfat quick label=CLE_TEST
assign letter=R
"@ | Set-Content -LiteralPath 'C:\test\diskpart.txt' -Encoding ASCII
& diskpart.exe /s 'C:\test\diskpart.txt' | Out-Null
$vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='R:'"
Write-Host ("R: {0}, {1:N0} Go libres" -f $vol.FileSystem, ($vol.FreeSpace / 1GB))
Copy-Item -LiteralPath 'C:\test\kit\DigSpill' -Destination 'R:\DigSpill' -Recurse
Write-Host ('outils de la cle : ' + ((Get-ChildItem 'R:\DigSpill\moteur\outils' -File | ForEach-Object { $_.Name }) -join ', '))
$ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
Write-Host ("RAM : {0:N1} Go" -f ($ram / 1GB))
EtatPmem 'avant la collecte'
$tmpAvant = @(Get-ChildItem -LiteralPath $env:TEMP, "$env:SystemRoot\Temp" -Filter '*.sys' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })

# ------------------------------------------------------------------ 2. vraie collecte
Titre 'Collecte DigSpill, mode complet (sans listing complet ni recherche de fichiers, pour gagner du temps)'
$t0 = Get-Date
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'R:\DigSpill\moteur\Collecte-Exfil.ps1' -Mode Complet -SkipFullListing -SkipFileSearch -Technicien 'Test GitHub' -Motif 'Test de la copie RAM'
Write-Host ("collecte terminee en {0:N0} min" -f ((Get-Date) - $t0).TotalMinutes)
$col = Get-ChildItem -LiteralPath 'R:\DigSpill\Collecte' -Directory | Sort-Object LastWriteTime | Select-Object -Last 1
Write-Host "dossier : $($col.FullName)"

Titre 'Controles apres la collecte'
EtatPmem 'apres la collecte'
& sc.exe query digspill_pmem 2>&1 | Out-Null
Write-Host "service digspill_pmem : $(if ($LASTEXITCODE -eq 1060) { 'absent (retire)' } else { 'ENCORE INSTALLE' })"
$sysMem = @(Get-ChildItem -LiteralPath (Join-Path $col.FullName 'memoire') -Filter '*.sys' -File -ErrorAction SilentlyContinue)
Write-Host "pilote laisse dans memoire\ : $(if ($sysMem.Count) { ($sysMem | ForEach-Object { $_.Name }) -join ', ' } else { 'aucun' })"
$tmpApres = @(Get-ChildItem -LiteralPath $env:TEMP, "$env:SystemRoot\Temp" -Filter '*.sys' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$nouveaux = @($tmpApres | Where-Object { $tmpAvant -notcontains $_ })
Write-Host "pilote laisse dans les dossiers temporaires du poste : $(if ($nouveaux.Count) { $nouveaux -join ', ' } else { 'aucun' })"
Bloc 'memoire_info.txt' (Join-Path $col.FullName 'memoire\memoire_info.txt')
Bloc 'winpmem.log' (Join-Path $col.FullName 'memoire\winpmem.log')
Write-Host '@@DEBUT etapes_collecte'
Get-Content -LiteralPath (Join-Path $col.FullName 'collecte.log') -Encoding UTF8 | Where-Object { $_ -match '\[\*\]|\[!\]|RAM|Memoire' } | ForEach-Object { Write-Host $_ }
Write-Host '@@FIN etapes_collecte'

# ------------------------------------------------------------------ 3. Volatility 3 sur l'image de la collecte
$raw = Get-ChildItem -LiteralPath (Join-Path $col.FullName 'memoire') -Filter '*.raw' -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $raw) { throw 'Pas d''image RAM dans la collecte' }
Titre ("Volatility 3 sur {0} ({1:N2} Go)" -f $raw.Name, ($raw.Length / 1GB))
& python -m pip install --quiet volatility3 pefile 2>&1 | Out-Null
$py = (Get-Command python).Source
$symb = 'C:\test\symboles'
foreach ($bin in "$env:SystemRoot\System32\ntoskrnl.exe", "$env:SystemRoot\System32\drivers\tcpip.sys") {
    $id = Lire-Rsds $bin
    $dir = Join-Path $symb ("windows\{0}" -f $id.Pdb); New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $isf = Join-Path $dir ("{0}-{1}.json.xz" -f $id.Guid, $id.Age)
    for ($n = 1; $n -le 3 -and -not (Test-Path $isf); $n++) {
        & $py -m volatility3.framework.symbols.windows.pdbconv -p $id.Pdb -g ($id.Guid + ('{0:X}' -f $id.Age)) -o $isf 2>&1 | Out-Null
        if (-not (Test-Path $isf)) { Start-Sleep -Seconds 20 }
    }
    Write-Host ("symboles {0} : {1}" -f $id.Pdb, $(if (Test-Path $isf) { 'prets' } else { 'ECHEC' }))
}
$vol = (Get-Command vol).Source
foreach ($m in 'windows.info', 'windows.pslist', 'windows.cmdline', 'windows.netstat') {
    $out = "C:\test\$m.csv"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $vol -q -r csv --offline -s $symb -f $raw.FullName $m 2>$null | Set-Content -LiteralPath $out -Encoding UTF8
    Write-Host ("{0} : {1} s" -f $m, [math]::Round($sw.Elapsed.TotalSeconds))
    Bloc $m $out
}
