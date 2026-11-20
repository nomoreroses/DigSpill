@echo off
REM SECOURS : a utiliser seulement si DigSpill.exe ne se lance pas (poste qui bloque les .exe non signes...).
REM Rangement de la cle : <cle>\DigSpill.exe, <cle>\moteur\ (ce dossier : moteur\secours), resultats dans <cle>\Collecte\.
REM Liste les cibles du gestionnaire d'identifiants Windows du compte COURANT (noms de serveurs / sites, pas les mots de passe).
REM A lancer SANS elevation, dans la session de CHAQUE compte du poste (Admin, Utilisateur, secretariat...).
REM Resultat : <cle>\Collecte\Identifiants\cmdkey_<POSTE>_<COMPTE>.txt, lu par Analyse-Exfil.ps1.
cd /d "%~dp0"
for %%I in ("%~dp0..") do set "MOTEUR=%%~fI"
for %%I in ("%~dp0..\..") do set "CLE=%%~fI"
if "%CLE:~-1%"=="\" set "CLE=%CLE:~0,-1%"
if not exist "%CLE%\Collecte\Identifiants" mkdir "%CLE%\Collecte\Identifiants"
set "OUT=%CLE%\Collecte\Identifiants\cmdkey_%COMPUTERNAME%_%USERNAME%.txt"
echo Poste   : %COMPUTERNAME%> "%OUT%"
echo Compte  : %USERDOMAIN%\%USERNAME%>> "%OUT%"
echo Date    : %DATE% %TIME%>> "%OUT%"
echo.>> "%OUT%"
cmdkey /list >> "%OUT%" 2>&1
echo.>> "%OUT%"
echo ### Coffre Web (vaultcmd)>> "%OUT%"
vaultcmd /listcreds:"Web Credentials" /all >> "%OUT%" 2>&1
vaultcmd /listcreds:"Windows Credentials" /all >> "%OUT%" 2>&1
echo.
echo  Cibles enregistrees pour %USERNAME% ecrites dans :
echo  %OUT%
echo  Recommencer dans la session de chaque autre compte.
echo.
pause
