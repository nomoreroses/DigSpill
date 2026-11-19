@echo off
REM Analyse exfiltration d'une collecte existante, sur le poste d'analyse (pas sur le poste suspect).
REM Usage : glisser-deposer un dossier Collecte\<POSTE>_<date> sur ce fichier, ou :
REM         ANALYSER_COLLECTE.bat "E:\Collecte\POSTE_20261117_150121" ["2026-10-18 22:00;2026-10-19 06:00"]
REM Le conteneur Velociraptor de la meme collecte est detecte automatiquement dans Collecte\Velociraptor.
REM Resultat : <dossier>_analyse\SYNTHESE_EXFILTRATION.txt (la collecte d'origine n'est pas modifiee)
REM            + <dossier>_INTERFACE.html : interface autonome a ouvrir sur n'importe quel PC.
cd /d "%~dp0"
if "%~1"=="" (
    echo Glisser-deposer un dossier de collecte sur ce fichier.
    pause
    exit /b 1
)
title Analyse exfiltration - %~nx1
if "%~2"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Analyse-Exfil.ps1" -Collecte "%~1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Analyse-Exfil.ps1" -Collecte "%~1" -Fenetres "%~2"
)
echo.
echo  === Interface autonome (un seul fichier HTML) ===
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Generer-Interface.ps1" -Collecte "%~1"
echo.
echo  Lire : %~1_analyse\SYNTHESE_EXFILTRATION.txt
echo  Ouvrir : %~1_INTERFACE.html
echo.
pause
