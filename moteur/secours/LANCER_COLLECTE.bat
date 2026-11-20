@echo off
REM SECOURS : a utiliser seulement si DigSpill.exe ne se lance pas (poste qui bloque les .exe non signes...).
REM Rangement de la cle : <cle>\DigSpill.exe, <cle>\moteur\ (ce dossier : moteur\secours), resultats dans <cle>\Collecte\.
REM Lanceur de la collecte de triage - demande l'elevation administrateur puis enchaine tout sans intervention
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Elevation administrateur requise, validez l'invite UAC...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
cd /d "%~dp0"
for %%I in ("%~dp0..") do set "MOTEUR=%%~fI"
for %%I in ("%~dp0..\..") do set "CLE=%%~fI"
if "%CLE:~-1%"=="\" set "CLE=%CLE:~0,-1%"
title DigSpill - Collecte forensique - NE PAS RETIRER LA CLE
echo.
echo  === ETAPE 1/3 : collecte PowerShell (volatile, RAM, journaux, comptes, rancongiciel, listing) ===
echo  Capture RAM : brancher AVANT un disque externe NTFS/exFAT avec un dossier MEMOIRE a la racine.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%MOTEUR%\Collecte-Exfil.ps1"

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
if not exist "%CLE%\Collecte\Velociraptor" mkdir "%CLE%\Collecte\Velociraptor"
pushd "%CLE%\Collecte\Velociraptor"
"%MOTEUR%\outils\Collecteur-Velociraptor.exe"
popd

echo.
echo  === ETAPE 3/3 : analyse exfiltration (sessions, SRUM, executions, navigation, \\tsclient, IOC) ===
echo  Tout est ecrit sur la cle. L'analyse de la $MFT se fait ensuite sur le poste d'analyse.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%MOTEUR%\Analyse-Exfil.ps1" -Collecte "%CLE%\Collecte" -DerniereDuPoste -SansMFT
if %errorlevel% neq 0 echo  Analyse en echec : lancer DigSpill.exe, Analyser une collecte, plus tard sur le poste d'analyse.

echo.
echo  Interface autonome sur la cle (sans Internet depuis ce poste : bases deja presentes sur la cle)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%MOTEUR%\Generer-Interface.ps1" -Collecte "%CLE%\Collecte" -SansInternet -SansOuvrir

echo.
echo  ===================================================================
echo   COLLECTE TERMINEE. Vous pouvez retirer la cle (ejection securisee).
echo.
echo   A FAIRE SUR PLACE : remplir A_COMPLETER_TECHNICIEN.txt dans le
echo   dossier de collecte (decouverte, patients, heure de la box, journaux box).
echo   Dans la session de CHAQUE compte : DigSpill.exe, Identifiants de ce compte
echo.
echo   AU BUREAU : seconde copie hachee des preuves (Copier-Preuves.ps1),
echo   puis DigSpill.exe, Analyser une collecte (analyse complete, $MFT).
echo   Lecture rapide sur un autre PC : Collecte\^<POSTE^>_^<date^>_INTERFACE.html
echo  ===================================================================
echo.
pause
