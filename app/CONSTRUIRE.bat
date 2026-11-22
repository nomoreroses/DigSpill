@echo off
REM DigSpill - construit DigSpill.exe avec le compilateur C# integre a Windows (.NET Framework 4.x).
REM Aucun SDK ni Visual Studio requis. Resultat : app\bin\DigSpill.exe, copie a la racine du depot.
setlocal
cd /d "%~dp0"
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
    echo Compilateur introuvable : .NET Framework 4.x est-il installe ?
    exit /b 1
)
if not exist bin mkdir bin
"%CSC%" /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 ^
  /win32manifest:app.manifest /win32icon:digspill.ico /out:bin\DigSpill.exe ^
  /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Management.dll ^
  /r:System.Web.Extensions.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll ^
  /resource:polices\Geist-Regular.ttf,DigSpill.Geist-Regular.ttf /resource:polices\Geist-SemiBold.ttf,DigSpill.Geist-SemiBold.ttf ^
  /resource:polices\GeistMono-Regular.ttf,DigSpill.GeistMono-Regular.ttf /resource:polices\GeistMono-Medium.ttf,DigSpill.GeistMono-Medium.ttf ^
  src\*.cs
if errorlevel 1 (
    echo.
    echo  ECHEC de la compilation.
    exit /b 1
)
copy /y bin\DigSpill.exe ..\DigSpill.exe >nul
echo.
echo  DigSpill.exe construit : %~dp0bin\DigSpill.exe (copie a la racine du depot)
echo  Etape suivante : SIGNER.bat pour que Windows affiche le nom de l'editeur.
endlocal
