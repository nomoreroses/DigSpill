@echo off
REM DigSpill - signe DigSpill.exe (Authenticode SHA-256 + contre-signature horodatee).
REM Le certificat de signature de code doit etre installe (jeton USB ou HSM du fournisseur).
REM   SIGNER.bat                  : choisit automatiquement le meilleur certificat de signature de code
REM   SIGNER.bat "Semaphors"      : certificat dont le sujet contient ce nom
setlocal
cd /d "%~dp0"
set "EXE=%~dp0bin\DigSpill.exe"
if not exist "%EXE%" (
    echo Lancer d'abord CONSTRUIRE.bat.
    exit /b 1
)
set "SIGNTOOL="
for /f "delims=" %%s in ('dir /b /s "%ProgramFiles(x86)%\Windows Kits\10\bin\*signtool.exe" 2^>nul ^| findstr /i "\\x64\\"') do set "SIGNTOOL=%%s"
if not defined SIGNTOOL (
    echo signtool.exe introuvable : installer le "Windows SDK" ^(composant Signing Tools^).
    exit /b 1
)
if "%~1"=="" (
    "%SIGNTOOL%" sign /fd sha256 /tr http://timestamp.sectigo.com /td sha256 /a "%EXE%"
) else (
    "%SIGNTOOL%" sign /fd sha256 /tr http://timestamp.sectigo.com /td sha256 /n "%~1" "%EXE%"
)
if errorlevel 1 (
    echo  ECHEC de la signature.
    exit /b 1
)
"%SIGNTOOL%" verify /pa /v "%EXE%"
copy /y "%EXE%" ..\DigSpill.exe >nul
echo.
echo  DigSpill.exe signe (copie a la racine du depot).
endlocal
