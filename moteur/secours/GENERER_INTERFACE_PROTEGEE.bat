@echo off
REM SECOURS : a utiliser seulement si DigSpill.exe ne se lance pas (poste qui bloque les .exe non signes...).
REM Rangement de la cle : <cle>\DigSpill.exe, <cle>\moteur\ (ce dossier : moteur\secours), resultats dans <cle>\Collecte\.
REM Comme GENERER_INTERFACE.bat, mais le fichier HTML est protege par un mot de passe
REM (a utiliser pour l'envoyer a un assureur, un expert ou un enqueteur). Le mot de passe se transmet a part.
cd /d "%~dp0"
for %%I in ("%~dp0..") do set "MOTEUR=%%~fI"
for %%I in ("%~dp0..\..") do set "CLE=%%~fI"
if "%CLE:~-1%"=="\" set "CLE=%CLE:~0,-1%"
title DigSpill - Interface autonome protegee
if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%MOTEUR%\Generer-Interface.ps1" -Proteger
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%MOTEUR%\Generer-Interface.ps1" -Collecte "%~1" -Proteger
)
if %errorlevel% neq 0 echo  Echec de la generation : voir le message ci-dessus.
echo.
pause
