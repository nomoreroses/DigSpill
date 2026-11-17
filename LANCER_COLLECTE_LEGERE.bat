@echo off
REM Collecte LEGERE pour les autres postes du reseau : connexions RDP, executions, identifiants exposes.
REM Pas de RAM, pas de journal USN, pas de listing complet, pas de Velociraptor. Environ 5 a 15 minutes.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Elevation administrateur requise, validez l'invite UAC...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
cd /d "%~dp0"
title Collecte forensique LEGERE - NE PAS RETIRER LA CLE
echo.
echo  === Collecte legere (connexions, executions, identifiants) ===
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collecte-Exfil.ps1" -Mode Leger

echo.
echo  ===================================================================
echo   COLLECTE LEGERE TERMINEE. Vous pouvez retirer la cle.
echo  ===================================================================
echo.
pause
