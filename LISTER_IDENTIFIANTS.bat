@echo off
REM Liste les cibles du gestionnaire d'identifiants Windows du compte COURANT (noms de serveurs / sites, pas les mots de passe).
REM A lancer SANS elevation, dans la session de CHAQUE compte du poste (Admin, Utilisateur, secretariat...).
REM Resultat : <cle>\Collecte\Identifiants\cmdkey_<POSTE>_<COMPTE>.txt, lu par Analyse-Exfil.ps1.
cd /d "%~dp0"
if not exist "%~dp0Collecte\Identifiants" mkdir "%~dp0Collecte\Identifiants"
set "OUT=%~dp0Collecte\Identifiants\cmdkey_%COMPUTERNAME%_%USERNAME%.txt"
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
