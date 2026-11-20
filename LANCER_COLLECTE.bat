@echo off
REM Lanceur de la collecte de triage - demande l'elevation administrateur puis enchaine tout sans intervention
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Elevation administrateur requise, validez l'invite UAC...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
cd /d "%~dp0"
title DigSpill - Collecte forensique - NE PAS RETIRER LA CLE
echo.
echo  === ETAPE 1/3 : collecte PowerShell (volatile, RAM, journaux, comptes, rancongiciel, listing) ===
echo  Capture RAM : brancher AVANT un disque externe NTFS/exFAT avec un dossier MEMOIRE a la racine.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collecte-Exfil.ps1"

echo.
echo  === ETAPE 2/3 : collecte Velociraptor (SANS Triage : $MFT, $J, registre, evtx, SRUM, Autoruns) ===
echo.
fsutil fsinfo volumeinfo %~d0 2>nul | find /i "FAT32" >nul
if %errorlevel% equ 0 (
    echo  ATTENTION : cle en FAT32, archive limitee a 4 Go. Index Search et OneDrive exclus,
    echo  la collecte devrait tenir, mais une cle NTFS ou exFAT est recommandee.
    echo  Une archive arrivee a 4 Go est TRONQUEE : l'analyse le signale dans conteneurs_velociraptor.csv.
    echo.
)
if not exist "%~dp0Collecte\Velociraptor" mkdir "%~dp0Collecte\Velociraptor"
pushd "%~dp0Collecte\Velociraptor"
"%~dp0Collecteur-Velociraptor.exe"
popd

echo.
echo  === ETAPE 3/3 : analyse exfiltration (sessions, SRUM, executions, navigation, \\tsclient, IOC) ===
echo  Tout est ecrit sur la cle. L'analyse de la $MFT se fait ensuite sur le poste d'analyse.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Analyse-Exfil.ps1" -Collecte "%~dp0Collecte" -DerniereDuPoste -SansMFT
if %errorlevel% neq 0 echo  Analyse en echec : lancer ANALYSER_COLLECTE.bat plus tard sur le poste d'analyse.

echo.
echo  Interface autonome sur la cle (sans Internet depuis ce poste : bases deja presentes sur la cle)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Generer-Interface.ps1" -Collecte "%~dp0Collecte" -SansInternet -SansOuvrir

echo.
echo  ===================================================================
echo   COLLECTE TERMINEE. Vous pouvez retirer la cle (ejection securisee).
echo.
echo   A FAIRE SUR PLACE : remplir A_COMPLETER_TECHNICIEN.txt dans le
echo   dossier de collecte (decouverte, patients, heure de la box, journaux box).
echo   Dans la session de CHAQUE compte : LISTER_IDENTIFIANTS.bat
echo.
echo   AU BUREAU : seconde copie hachee des preuves (Copier-Preuves.ps1),
echo   puis ANALYSER_COLLECTE.bat pour l'analyse complete ($MFT).
echo   Lecture rapide sur un autre PC : Collecte\^<POSTE^>_^<date^>_INTERFACE.html
echo  ===================================================================
echo.
pause
