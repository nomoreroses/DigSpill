@echo off
REM Cree UN fichier HTML autonome (interface + graphiques + donnees) pour lire une collecte sur n'importe quel PC.
REM Usage : double-clic (collecte la plus recente du dossier Collecte) ou glisser-deposer un dossier de collecte.
REM Resultat : Collecte\<POSTE>_<date>_INTERFACE.html (double-clic pour l'ouvrir, sans installation, meme hors ligne)
cd /d "%~dp0"
title DigSpill - Interface autonome
if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Generer-Interface.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Generer-Interface.ps1" -Collecte "%~1"
)
if %errorlevel% neq 0 echo  Echec de la generation : voir le message ci-dessus.
echo.
pause
