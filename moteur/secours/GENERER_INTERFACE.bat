@echo off
REM SECOURS : a utiliser seulement si DigSpill.exe ne se lance pas (poste qui bloque les .exe non signes...).
REM Rangement de la cle : <cle>\DigSpill.exe, <cle>\moteur\ (ce dossier : moteur\secours), resultats dans <cle>\Collecte\.
REM Cree UN fichier HTML autonome (interface + graphiques + donnees) pour lire une collecte sur n'importe quel PC.
REM Usage : double-clic (collecte la plus recente du dossier Collecte) ou glisser-deposer un dossier de collecte.
REM Resultat : Collecte\<POSTE>_<date>_INTERFACE.html (double-clic pour l'ouvrir, sans installation, meme hors ligne)
cd /d "%~dp0"
for %%I in ("%~dp0..") do set "MOTEUR=%%~fI"
for %%I in ("%~dp0..\..") do set "CLE=%%~fI"
if "%CLE:~-1%"=="\" set "CLE=%CLE:~0,-1%"
title DigSpill - Interface autonome
if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%MOTEUR%\Generer-Interface.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%MOTEUR%\Generer-Interface.ps1" -Collecte "%~1"
)
if %errorlevel% neq 0 echo  Echec de la generation : voir le message ci-dessus.
echo.
pause
