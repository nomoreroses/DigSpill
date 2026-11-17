@echo off
REM Lanceur de la collecte de triage - demande l'elevation administrateur puis enchaine tout sans intervention
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Elevation administrateur requise, validez l'invite UAC...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
cd /d "%~dp0"
title Collecte forensique - NE PAS RETIRER LA CLE
echo.
echo  === ETAPE 1/2 : collecte PowerShell (volatile, RAM, journaux, comptes, rancongiciel, listing) ===
echo  Capture RAM : brancher AVANT un disque externe NTFS/exFAT avec un dossier MEMOIRE a la racine.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collecte-Exfil.ps1"

echo.
echo  === ETAPE 2/2 : collecte Velociraptor (SANS Triage : $MFT, $J, registre, evtx, SRUM, Autoruns) ===
echo.
fsutil fsinfo volumeinfo %~d0 2>nul | find /i "FAT32" >nul
if %errorlevel% equ 0 (
    echo  ATTENTION : cle en FAT32, archive limitee a 4 Go. Index Search et OneDrive exclus,
    echo  la collecte devrait tenir, mais une cle NTFS ou exFAT est recommandee.
    echo.
)
if not exist "%~dp0Collecte\Velociraptor" mkdir "%~dp0Collecte\Velociraptor"
pushd "%~dp0Collecte\Velociraptor"
"%~dp0Collecteur-Velociraptor.exe"
popd

echo.
echo  ===================================================================
echo   COLLECTE TERMINEE. Vous pouvez retirer la cle (ejection securisee).
echo.
echo   A FAIRE SUR PLACE : remplir A_COMPLETER_TECHNICIEN.txt dans le
echo   dossier de collecte (heure de la box, journaux box / pare-feu).
echo  ===================================================================
echo.
pause
