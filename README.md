# Collecte de triage forensique Windows (bêta)

Clé USB de collecte à lancer sur un poste Windows suspecté d'intrusion, d'exfiltration ou de rançongiciel. Un double-clic, une validation UAC, aucune autre interaction.

> Bêta : testée sur un cas réel, à valider sur d'autres environnements avant usage en production.

## Contenu de la clé

```
LANCER_COLLECTE.bat           collecte complète (PowerShell puis Velociraptor)
LANCER_COLLECTE_LEGERE.bat    autres postes du réseau : connexions, exécutions, identifiants
Collecte-Exfil.ps1            script de collecte (PowerShell 5.1)
Collecteur-Velociraptor.exe   à générer, voir plus bas (non versionné)
outils\7zr.exe                https://www.7-zip.org/a/7zr.exe (non versionné)
outils\winpmem_mini_x64_rc2.exe  https://github.com/Velocidex/WinPmem/releases (non versionné)
```

Les résultats sont écrits dans `Collecte\<POSTE>_<date>\` sur la clé, avec un manifeste SHA256.

**Commencer la lecture par `SYNTHESE.txt`** : il liste les alertes (chiffrement, notes de rançon, IP publiques connectées, comptes RDP sans mot de passe, détections antivirus…) et renvoie aux fichiers de détail. Voir aussi `A_COMPLETER_TECHNICIEN.txt`.

## Arborescence d'une collecte

```
SYNTHESE.txt                  alertes à vérifier en premier
A_COMPLETER_TECHNICIEN.txt    heure de la box, journaux box / pare-feu
volatile\    memoire\    systeme\    comptes\    connexions\    exposition\
persistance\ reseau\     evenements\ artefacts\  utilisateurs\  fichiers\   rancon\
manifeste_sha256.csv          intégrité de tous les fichiers collectés
```

## Ce qui est collecté

- **Volatile** : processus (ligne de commande, propriétaire, hash, signature), connexions, DNS, ARP, sessions, SMB.
- **Mémoire** : winpmem vers un disque externe NTFS/exFAT contenant un dossier `MEMOIRE` à la racine ; sinon `pagefile.sys` / `hiberfil.sys` si la place le permet (lecture NTFS brute).
- **Connexions à distance** : RDP (1149, 21/24/25, 131, 4778), ouvertures de session 4624, échecs 4625 agrégés par IP, 4648, synthèse des IP publiques.
- **Comptes** : événements (création, groupes, réinitialisation de mot de passe), inventaire avec accès RDP effectif, politique de verrouillage.
- **Identifiants exposés** : sites et identifiants enregistrés dans les navigateurs (mots de passe non lus), profils Wi-Fi, gestionnaire d'identifiants.
- **Rançongiciel** : fichiers chiffrés par extension avec fenêtre de chiffrement, notes de rançon, bases métier, clichés VSS, commandes destructrices, binaires suspects en archive 7z chiffrée (mot de passe `infected`), quarantaine Defender.
- **Artefacts** : evtx, ruches, Amcache, SRUM, Prefetch, journal USN, historiques navigateurs, persistance (services, tâches, Run, WMI, BITS), logiciels installés et désinstallés.
- **Listing complet des disques** (dates, tailles).
- **Fiche à compléter** par le technicien : heure de la box, redirections de ports, export des journaux box / pare-feu.
- **Velociraptor** : `_SANS_Triage` ($MFT, $J, registre, evtx…), Autoruns, SRUM.

## Générer le collecteur Velociraptor

1. Télécharger `velociraptor-v0.77.x-windows-amd64.exe` (https://github.com/Velocidex/velociraptor/releases).
2. Récupérer la définition `Windows.Triage.Targets` (https://github.com/Velocidex/velociraptor-triage-collector, branche `gh-pages`, `artifacts/Windows.Triage.Targets.zip`) et l'extraire dans un dossier `defs`.
3. `velociraptor.exe collector --definitions defs velociraptor\spec.yaml`
4. Copier `Collecteur-Velociraptor.exe` (généré dans `%TEMP%\gui_datastore`) à la racine de la clé.

Le `spec.yaml` exclut l'index Windows Search et les binaires OneDrive (plusieurs Go) pour rester sous la limite FAT32 de 4 Go par fichier. Une clé NTFS ou exFAT reste recommandée.

## Paramètres du script

```
-Mode Complet|Leger   (défaut Complet)
-Days 60              période analysée
-SkipFileSearch       pas de recherche d'archives / outils suspects
-SkipFullListing      pas de listing complet des disques
```

## Prérequis

- Windows 10 / 11 ou Server 2016+, PowerShell 5.1, compte administrateur local.
- Clé USB de 16 Go minimum, NTFS ou exFAT de préférence (FAT32 limite chaque fichier à 4 Go).
- Pour la RAM : disque externe NTFS/exFAT, dossier `MEMOIRE` à la racine, espace libre supérieur à la RAM du poste.

## Précautions

- Les collectes contiennent des données personnelles et de santé potentielles, ainsi que la ruche SAM : chiffrer ou protéger la clé, ne jamais versionner le dossier `Collecte\`.
- Le script n'écrit sur le poste que des fichiers temporaires (`%TEMP%`), supprimés après usage.
