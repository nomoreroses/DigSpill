@echo off
REM SECOURS : a utiliser seulement si DigSpill.exe ne se lance pas (poste qui bloque les .exe non signes...).
REM Rangement de la cle : <cle>\DigSpill.exe, <cle>\moteur\ (ce dossier : moteur\secours), resultats dans <cle>\Collecte\.
REM Collecte LEGERE pour les autres postes du reseau : connexions RDP, executions, identifiants exposes.
REM Pas de RAM, pas de journal USN, pas de listing complet, pas de Velociraptor. Environ 5 a 15 minutes.
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
title DigSpill - Collecte forensique LEGERE - NE PAS RETIRER LA CLE
echo.
echo  === Collecte legere (connexions, executions, identifiants) ===
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%MOTEUR%\Collecte-Exfil.ps1" -Mode Leger

echo.
echo  === Analyse exfiltration (sessions, SRUM, executions, navigation) ===
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%MOTEUR%\Analyse-Exfil.ps1" -Collecte "%CLE%\Collecte" -DerniereDuPoste -SansMFT -SansHashConteneurs

echo.
echo  ===================================================================
echo   COLLECTE LEGERE TERMINEE. Vous pouvez retirer la cle.
echo  ===================================================================
echo.
pause
