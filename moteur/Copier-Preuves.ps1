#Requires -Version 5.1
<#
    DigSpill - Copier-Preuves.ps1 - Seconde copie des preuves, verifiee par hachage, avec proces-verbal.

      powershell -ExecutionPolicy Bypass -File Copier-Preuves.ps1 -Source E:\Collecte -Destination F:\PREUVES_cabinet

    - Copie tout le dossier source (collectes, analyses, conteneurs Velociraptor, RAM...) vers la destination.
    - Calcule le SHA256 de chaque fichier source et copie, et le compare au manifeste de la collecte s'il existe.
    - Ecrit PV_COPIE_<date>.txt et hachages_<date>.csv dans la destination (et une copie du PV dans la source).
    La destination doit etre un support distinct (disque externe chiffre, NAS hors reseau du client), conserve a part.

    -Collecte POSTE_AAAAMMJJ_HHMMSS : ne copie que cette collecte (dossiers _analyse et _scelles, interface,
    reglages et conteneurs Velociraptor du meme poste), et pose aussi le PV dans la collecte copiee (chaine de possession).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [string]$Operateur = "$env:USERDOMAIN\$env:USERNAME",
    [string]$Collecte
)
$ErrorActionPreference = 'Stop'
$Source = (Resolve-Path -LiteralPath $Source).ProviderPath.TrimEnd('\')
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$Destination = (Resolve-Path -LiteralPath $Destination).ProviderPath.TrimEnd('\')
if ($Destination.StartsWith($Source, [StringComparison]::OrdinalIgnoreCase)) { throw 'La destination ne peut pas etre dans la source.' }
if ((Split-Path $Source -Qualifier) -eq (Split-Path $Destination -Qualifier)) { Write-Warning 'Source et destination sur le meme volume : la copie ne protege pas contre la perte du support.' }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$dst = Join-Path $Destination (Split-Path $Source -Leaf)
if ($Collecte) {
    $poste = $Collecte -replace '_\d{8}_\d{6}(_leger)?$', ''
    $files = @()
    foreach ($d in @($Collecte, "${Collecte}_analyse", "${Collecte}_scelles")) {
        $p = Join-Path $Source $d
        if (Test-Path -LiteralPath $p -PathType Container) { $files += @(Get-ChildItem -LiteralPath $p -Recurse -File -Force) }
    }
    $files += @(Get-ChildItem -LiteralPath $Source -File -Force | Where-Object { $_.Name -like "${Collecte}_*" })
    $pv = Join-Path $Source 'Velociraptor'
    if (Test-Path -LiteralPath $pv) { $files += @(Get-ChildItem -LiteralPath $pv -File -Force | Where-Object { $_.Name -like "Velociraptor-$poste-*" }) }
    if (-not (Test-Path -LiteralPath (Join-Path $Source $Collecte))) { throw "Collecte $Collecte introuvable dans $Source" }
} else {
    $files = @(Get-ChildItem -LiteralPath $Source -Recurse -File -Force)
}
$total = ($files | Measure-Object Length -Sum).Sum
$free = (Get-PSDrive -Name (Split-Path $Destination -Qualifier).TrimEnd(':')).Free
if ($free -lt $total) { throw ('Espace insuffisant : {0:N1} Go necessaires, {1:N1} Go libres' -f ($total / 1GB), ($free / 1GB)) }
$fs = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$(Split-Path $Destination -Qualifier)'").FileSystem
$big = @($files | Where-Object { $_.Length -ge 4GB })
if ($fs -match '^FAT' -and $big.Count) { throw "Destination FAT32 : $($big.Count) fichier(s) de 4 Go ou plus ne peuvent pas y etre copies. Utiliser NTFS ou exFAT." }

Write-Host ('Copie de {0} fichiers ({1:N1} Go) de {2} vers {3}' -f $files.Count, ($total / 1GB), $Source, $dst)
Write-Host ('  copie de {0:N1} Go en cours' -f ($total / 1GB))
if ($Collecte) {
    $copies = @()
    foreach ($d in @($Collecte, "${Collecte}_analyse", "${Collecte}_scelles")) {
        if (Test-Path -LiteralPath (Join-Path $Source $d) -PathType Container) { $copies += ,@((Join-Path $Source $d), (Join-Path $dst $d), '*', '/E') }
    }
    $copies += ,@($Source, $dst, "${Collecte}_*", '/LEV:1')
    if (Test-Path -LiteralPath (Join-Path $Source 'Velociraptor')) { $copies += ,@((Join-Path $Source 'Velociraptor'), (Join-Path $dst 'Velociraptor'), "Velociraptor-$poste-*", '/LEV:1') }
    foreach ($c in $copies) {
        & robocopy.exe $c[0] $c[1] $c[2] $c[3] /COPY:DT /DCOPY:T /R:2 /W:2 /NP /NFL /NDL /NJH | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy a echoue (code $LASTEXITCODE) pour $($c[0])" }
    }
} else {
    & robocopy.exe $Source $dst /E /COPY:DT /DCOPY:T /R:2 /W:2 /NP /NFL /NDL /NJH | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy a echoue (code $LASTEXITCODE)" }
}

# Manifestes de collecte (SHA256 attendus)
$expected = @{}
# -Include est ignore avec -LiteralPath sous PowerShell 5.1 (sinon chaque fichier, image RAM comprise, etait lu comme un CSV)
foreach ($m in ($files | Where-Object { $_.Name -eq 'manifeste_sha256.csv' -or $_.Name -eq 'manifeste_analyse_sha256.csv' })) {
    $base = Split-Path $m.FullName -Parent
    foreach ($r in (Import-Csv -LiteralPath $m.FullName -Encoding UTF8)) { $expected[(Join-Path $base $r.Fichier).ToLower()] = $r.SHA256 }
}

# SHA256 avec avancement en octets toutes les 2 s : une image RAM de 18 Go se re-hache en plusieurs minutes,
# l'appli doit montrer que ca avance (avant : « 1000 / 1131 » fige). Meme resultat que Get-FileHash.
$script:aHacher = 2 * $total; $script:hache = [int64]0; $script:palier = [datetime]::MinValue
function Get-Sha256Suivi([string]$Chemin) {
    $fs = $null
    try {
        $fs = [IO.File]::OpenRead($Chemin)
        $h = [Security.Cryptography.SHA256]::Create(); $buf = New-Object byte[] (4MB)
        while (($n = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
            [void]$h.TransformBlock($buf, 0, $n, $null, 0)
            $script:hache += $n
            if (([datetime]::Now - $script:palier).TotalSeconds -ge 2) {
                $script:palier = [datetime]::Now
                Write-Host ('  octets {0} / {1} Mo' -f [int64]($script:hache / 1MB), [int64]($script:aHacher / 1MB))
            }
        }
        [void]$h.TransformFinalBlock($buf, 0, 0)
        return ([BitConverter]::ToString($h.Hash) -replace '-', '')
    } catch { return $null } finally { if ($fs) { $fs.Dispose() } }
}

$rows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($f in $files) {
    $i++
    if ($i % 200 -eq 0) { Write-Host "  verification $i / $($files.Count)" }
    $rel = $f.FullName.Substring($Source.Length + 1)
    $c = Join-Path $dst $rel
    $hs = Get-Sha256Suivi $f.FullName
    $hc = if (Test-Path -LiteralPath $c) { Get-Sha256Suivi $c } else { '' }
    $exp = $expected[$f.FullName.ToLower()]
    $etat = if (-not $hc) { 'ABSENT DE LA COPIE' } elseif ($hs -ne $hc) { 'COPIE DIFFERENTE' } elseif ($exp -and $exp -ne $hs) { 'SOURCE DIFFERENTE DU MANIFESTE' } else { 'OK' }
    $rows.Add([pscustomobject]@{ Fichier = $rel; Octets = $f.Length; SHA256 = $hs; SHA256Copie = $hc; SHA256Manifeste = $exp; Etat = $etat })
}
$csv = Join-Path $Destination "hachages_$stamp.csv"
$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
$bad = @($rows | Where-Object { $_.Etat -ne 'OK' })
$csvHash = (Get-FileHash -LiteralPath $csv -Algorithm SHA256).Hash
$vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$(Split-Path $Destination -Qualifier)'"
$pv = @(
    'PROCES-VERBAL DE COPIE DE PREUVES'
    '================================================================='
    "Date / heure     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
    "Operateur        : $Operateur"
    "Poste de copie   : $env:COMPUTERNAME"
    "Source           : $Source"
    "Destination      : $dst"
    "Support          : $($vol.VolumeName) ($fs), n. de serie de volume $($vol.VolumeSerialNumber)"
    "Fichiers         : $($files.Count) ($('{0:N0}' -f $total) octets)"
    "Verification     : SHA256 de chaque fichier source et copie ; comparaison aux manifestes de collecte ($($expected.Count) empreintes)"
    "Resultat         : $(if ($bad.Count) { "$($bad.Count) ANOMALIE(S) - voir hachages_$stamp.csv" } else { 'toutes les copies sont identiques aux originaux' })"
    "Liste des hachages : hachages_$stamp.csv  SHA256 $csvHash"
    ''
    'Conteneurs et captures (empreintes completes) :'
) + @($rows | Where-Object { $_.Fichier -match '(?i)\.(zip|raw|7z|aff4)$' } | ForEach-Object { "  $($_.SHA256)  $($_.Fichier)  ($('{0:N0}' -f $_.Octets) octets) $($_.Etat)" }) + @(
    ''
    'Conserver ce support separement de la cle de collecte (lieu different, acces restreint).'
    'Signature : ____________________'
)
$pvFile = Join-Path $Destination "PV_COPIE_$stamp.txt"
$pv | Out-File -LiteralPath $pvFile -Encoding utf8
try { Copy-Item -LiteralPath $pvFile -Destination (Join-Path $Source "PV_COPIE_$stamp.txt") -ErrorAction Stop } catch { Write-Warning "PV non copie dans la source (support protege en ecriture ?)" }
if ($Collecte) { Copy-Item -LiteralPath $pvFile -Destination (Join-Path (Join-Path $dst $Collecte) "PV_COPIE_$stamp.txt") -ErrorAction SilentlyContinue }
$pv | ForEach-Object { Write-Host $_ }
if ($bad.Count) { exit 2 }
