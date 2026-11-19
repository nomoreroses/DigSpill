@echo off
REM Comme GENERER_INTERFACE.bat, mais le fichier HTML est protege par un mot de passe
REM (a utiliser pour l'envoyer a un assureur, un expert ou un enqueteur). Le mot de passe se transmet a part.
cd /d "%~dp0"
title DigSpill - Interface autonome protegee
if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Generer-Interface.ps1" -Proteger
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Generer-Interface.ps1" -Collecte "%~1" -Proteger
)
if %errorlevel% neq 0 echo  Echec de la generation : voir le message ci-dessus.
echo.
pause
