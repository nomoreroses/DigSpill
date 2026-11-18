# Collecte de triage forensique Windows (bêta)

Clé USB de collecte à lancer sur un poste Windows suspecté d'intrusion, d'exfiltration ou de rançongiciel. Un double-clic, une validation UAC, aucune autre interaction. La collecte est suivie d'une analyse orientée exfiltration, qu'on peut relancer plus tard sur le poste d'analyse.

> Bêta : testée sur un cas réel, à valider sur d'autres environnements avant usage en production.

## Contenu de la clé

```
LANCER_COLLECTE.bat           collecte complète : PowerShell, Velociraptor, puis analyse exfiltration
LANCER_COLLECTE_LEGERE.bat    autres postes du réseau : connexions, exécutions, identifiants
LISTER_IDENTIFIANTS.bat       cibles du gestionnaire d'identifiants (à lancer dans chaque session, sans élévation)
ANALYSER_COLLECTE.bat         analyse a posteriori d'une collecte (glisser-déposer le dossier)
Collecte-Exfil.ps1            script de collecte (PowerShell 5.1)
Analyse-Exfil.ps1             analyse exfiltration (lit la collecte et le conteneur Velociraptor)
Copier-Preuves.ps1            seconde copie des preuves vérifiée par SHA256, procès-verbal
Collecteur-Velociraptor.exe   à générer, voir plus bas (non versionné)
outils\7zr.exe                https://www.7-zip.org/a/7zr.exe (non versionné)
outils\winpmem_mini_x64_rc2.exe  https://github.com/Velocidex/WinPmem/releases (non versionné)
```

Les résultats sont écrits dans `Collecte\<POSTE>_<date>\` sur la clé, avec un manifeste SHA256. L'analyse est écrite à côté, dans `Collecte\<POSTE>_<date>_analyse\` : la collecte d'origine n'est pas modifiée.

**Commencer la lecture par `SYNTHESE.txt`** (alertes de la collecte), **puis `SYNTHESE_EXFILTRATION.txt`** (grille par canal de sortie et proposition de conclusion graduée). Remplir `A_COMPLETER_TECHNICIEN.txt` sur place.

## Déroulé conseillé

1. Sur le poste suspect : `LANCER_COLLECTE.bat` (environ 15 à 30 min).
2. Toujours sur place : remplir `A_COMPLETER_TECHNICIEN.txt` (date de découverte, heure de la box, journaux de la box), puis lancer `LISTER_IDENTIFIANTS.bat` dans la session de chaque compte.
3. Au bureau : `Copier-Preuves.ps1 -Source E:\Collecte -Destination F:\PREUVES_<client>` (support NTFS/exFAT distinct, conservé à part).
4. Sur le poste d'analyse : `ANALYSER_COLLECTE.bat` (analyse complète, avec la $MFT du conteneur Velociraptor). Ajouter des fenêtres si besoin : `ANALYSER_COLLECTE.bat "E:\Collecte\POSTE_20261117_150121" "2026-10-18 22:00;2026-10-19 06:00"`.

## Arborescence

```
Collecte\
  <POSTE>_<date>\               collecte (ne pas modifier)
    SYNTHESE.txt                alertes à vérifier en premier
    A_COMPLETER_TECHNICIEN.txt  découverte, patients, heure de la box, demande au FAI, copie des preuves
    volatile\ memoire\ systeme\ comptes\ connexions\ exposition\ persistance\ reseau\
    evenements\ artefacts\ utilisateurs\ fichiers\ rancon\ outils_distants\
    manifeste_sha256.csv
  <POSTE>_<date>_analyse\       analyse exfiltration
    SYNTHESE_EXFILTRATION.txt   grille par canal + conclusion graduée proposée
    00_LISEZMOI.txt             ordre de lecture des tableaux
  Velociraptor\                 conteneurs .zip (+ .sha256)
  Identifiants\                 sorties de LISTER_IDENTIFIANTS.bat
```

## Ce qui est collecté

- **Volatile** : processus (ligne de commande, propriétaire, hash, signature), connexions, DNS, ARP, sessions, SMB.
- **Mémoire** : winpmem vers un disque externe NTFS/exFAT contenant un dossier `MEMOIRE` à la racine ; sinon `pagefile.sys` / `hiberfil.sys` si la place le permet (lecture NTFS brute).
- **Connexions à distance** : RDP (1149, 21/24/25, 131, 4778), ouvertures de session 4624, échecs 4625 agrégés par IP, 4648, synthèse des IP publiques.
- **Comptes** : événements (création, groupes, réinitialisation de mot de passe), inventaire avec accès RDP effectif, politique de verrouillage, politique d'audit.
- **Identifiants exposés** : sites et identifiants enregistrés dans les navigateurs (mots de passe non lus), profils Wi-Fi, gestionnaire d'identifiants.
- **Rançongiciel** : fichiers chiffrés par extension avec fenêtre de chiffrement, notes de rançon, bases métier, clichés VSS, commandes destructrices, binaires suspects en archive 7z chiffrée (mot de passe `infected`), quarantaine Defender.
- **Outils d'accès distant** : journaux NetBird (avec `netbird status`, clés privées masquées), Splashtop, TSplus, Datto RMM, RustDesk, ScreenConnect, AnyDesk, TeamViewer.
- **Réseau** : configuration, journalisation du pare-feu (activée ou non) et journal, redirections RDP (lecteurs, presse-papier).
- **Artefacts** : evtx et état de chaque journal, ruches (copie normale, VSS, puis NTFS brut), Amcache, SRUM, Prefetch, journal USN, historiques navigateurs, LNK et Jump Lists, USB avec dates, persistance (services, tâches, Run, WMI, BITS), logiciels installés et désinstallés.
- **Listing complet des disques** (dates, tailles).
- **Fiche à compléter** par le technicien : découverte de l'incident, patients concernés, heure de la box et écart d'horloge, redirections de ports, journaux de la box, demande type au FAI.
- **Velociraptor** : `_SANS_Triage` ($MFT, $J, registre, evtx…), Autoruns, SRUM.

## Ce que fait l'analyse exfiltration

| Question | Sources | Fichiers |
|---|---|---|
| Quand l'attaquant était-il connecté, combien de temps ? | 4624/4634/4647, LSM 21-25, 1149, 131 | `sessions_reconstituees.csv`, `fenetres_analyse.csv` |
| Y a-t-il eu un pic d'envoi ? | SRUM par appli et par heure vs référence de 21 j | `srum_fenetres_vs_reference.csv`, `srum_METHODE.txt` |
| Qu'a-t-il lancé ? | Prefetch, Amcache, BAM, 4688, Sysmon | `executions_fenetres.csv` |
| A-t-il utilisé les sessions web ouvertes ? | Historiques Chrome, Edge, Firefox | `navigation_fenetres.csv` |
| A-t-il copié via `\\tsclient` ou consulté la base ? | LNK, Jump Lists, RecentDocs, ShellBags, recherche brute | `acces_fichiers_*.csv`, `acces_donnees_metier.csv` |
| A-t-il créé des archives ? | USN, $MFT | `usn_fenetres.csv`, `mft_fenetres.csv` |
| Par quels outils distants ? | Logiciels, services, journaux propres | `outils_distants_*` |
| Pare-feu, BITS, USB, SMB, DNS ? | Sources déjà collectées, avec une ligne même si le résultat est vide | `verifications_sources.csv` |
| La note revendique-t-elle un vol ? | Note de rançon | `note_rancon_analyse.txt` |
| Quels identifiants sont exposés ? | mimikatz, NirSoft, gestionnaire d'identifiants | `identifiants_exposition.txt` |
| IOC et intégrité | SHA256, SHA1 Amcache et quarantaine, conteneurs | `ioc_hachages.csv`, `conteneurs_velociraptor.csv` |

Paramètres : `-Fenetres 'debut;fin'`, `-Velociraptor <zip>`, `-MargeMinutes 30`, `-ReferenceJours 21`, `-SansMFT`, `-SansHashConteneurs`, `-GarderExtraits`.

L'analyse ne conclut pas à la place de l'analyste. La proposition de conclusion graduée est un point de départ. La décision d'informer les personnes concernées (art. 34 RGPD) appartient au responsable de traitement et à son DPO.

## Générer le collecteur Velociraptor

1. Télécharger `velociraptor-v0.77.x-windows-amd64.exe` (https://github.com/Velocidex/velociraptor/releases).
2. Récupérer la définition `Windows.Triage.Targets` (https://github.com/Velocidex/velociraptor-triage-collector, branche `gh-pages`, `artifacts/Windows.Triage.Targets.zip`) et l'extraire dans un dossier `defs`.
3. `velociraptor.exe collector --definitions defs velociraptor\spec.yaml`
4. Copier `Collecteur-Velociraptor.exe` (généré dans `%TEMP%\gui_datastore`) à la racine de la clé.

Le `spec.yaml` exclut l'index Windows Search et les binaires OneDrive (plusieurs Go) pour rester sous la limite FAT32 de 4 Go par fichier. Une clé NTFS ou exFAT reste recommandée : une archive qui atteint 4 Go sur FAT32 est tronquée, et l'analyse le signale.

Le collecteur sert aussi de moteur d'analyse (ESE/SRUM, SQLite, registre hors ligne, Prefetch, LNK, ShellBags, $MFT) : `Analyse-Exfil.ps1` le cherche à côté du script ou à la racine de la clé.

## Paramètres de la collecte

```
-Mode Complet|Leger   (défaut Complet)
-Days 60              période analysée
-SkipFileSearch       pas de recherche d'archives / outils suspects
-SkipFullListing      pas de listing complet des disques
```

## Prérequis

- Windows 10 / 11 ou Server 2016+, PowerShell 5.1, compte administrateur local.
- Clé USB de 32 Go minimum, NTFS ou exFAT de préférence (FAT32 limite chaque fichier à 4 Go).
- Pour la RAM : disque externe NTFS/exFAT, dossier `MEMOIRE` à la racine, espace libre supérieur à la RAM du poste.

## Précautions

- Les collectes contiennent des données personnelles et de santé potentielles, ainsi que la ruche SAM : chiffrer ou protéger la clé, ne jamais versionner le dossier `Collecte\`.
- Les preuves ne doivent pas exister en un seul exemplaire : faire une seconde copie hachée avec `Copier-Preuves.ps1` et la conserver séparément.
- La collecte n'écrit sur le poste que des fichiers temporaires (`%TEMP%`), supprimés après usage. L'analyse écrit uniquement sur la clé ou le dossier de sortie.
- La veille sur les sites de fuite se fait à la main (`note_rancon_analyse.txt`) : le script n'envoie jamais le nom du client à un service tiers.
