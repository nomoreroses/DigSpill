<picture>
  <source media="(prefers-color-scheme: dark)" srcset="interface/assets/digspill-logo-blanc.svg">
  <img src="interface/assets/digspill-logo-noir.svg" alt="digspill" width="220">
</picture>

# DigSpill (bêta)

**Collecte et analyse forensique Windows : ce que l'attaquant a pu creuser (*dig*) et faire sortir (*spill*).**

Clé USB de collecte à lancer sur un poste Windows suspecté d'intrusion, d'exfiltration ou de rançongiciel. Un double-clic, une validation UAC, aucune autre interaction. La collecte est suivie d'une analyse orientée exfiltration, qu'on peut relancer plus tard sur le poste d'analyse.

> Bêta : testée sur un cas réel, à valider sur d'autres environnements avant usage en production.

## Contenu de la clé

```
DigSpill.exe                  appli Windows : collecter (poste suspect) ou analyser (votre PC), à construire avec app\CONSTRUIRE.bat
digspill.ini                  technicien et réglages lus par DigSpill.exe (modèle : digspill.ini.exemple)
LANCER_COLLECTE.bat           collecte complète : PowerShell, Velociraptor, puis analyse exfiltration
LANCER_COLLECTE_LEGERE.bat    autres postes du réseau : connexions, exécutions, identifiants
LISTER_IDENTIFIANTS.bat       cibles du gestionnaire d'identifiants (à lancer dans chaque session, sans élévation)
ANALYSER_COLLECTE.bat         analyse a posteriori d'une collecte (glisser-déposer le dossier), puis interface HTML
GENERER_INTERFACE.bat         crée UN fichier HTML autonome pour lire la collecte sur n'importe quel PC
GENERER_INTERFACE_PROTEGEE.bat  idem, fichier protégé par mot de passe (pour un assureur, un expert)
Collecte-Exfil.ps1            script de collecte (PowerShell 5.1)
Analyse-Exfil.ps1             analyse exfiltration (lit la collecte et le conteneur Velociraptor)
Copier-Preuves.ps1            seconde copie des preuves vérifiée par SHA256, procès-verbal
Generer-Interface.ps1         assemble le fichier HTML autonome (interface\ + données de la collecte)
interface\                    code de l'interface (HTML, CSS, JavaScript, ECharts, carte du monde)
outils\bases\                 bases publiques téléchargées par le .bat et mémoire des incidents (non versionné)
Collecteur-Velociraptor.exe   à générer, voir plus bas (non versionné)
outils\7zr.exe                https://www.7-zip.org/a/7zr.exe (non versionné)
outils\winpmem_mini_x64_rc2.exe  https://github.com/Velocidex/WinPmem/releases (non versionné)
```

Les résultats sont écrits dans `Collecte\<POSTE>_<date>\` sur la clé, avec un manifeste SHA256. L'analyse est écrite à côté, dans `Collecte\<POSTE>_<date>_analyse\` : la collecte d'origine n'est pas modifiée.

**Commencer la lecture par `SYNTHESE.txt`** (alertes de la collecte), **puis `SYNTHESE_EXFILTRATION.txt`** (grille par canal de sortie et proposition de conclusion graduée). Remplir `A_COMPLETER_TECHNICIEN.txt` sur place.

## Appli DigSpill.exe

Une vraie fenêtre Windows à la place de la console : on saisit l'intervention, on suit la collecte, on repart avec le scellé.

![DigSpill.exe : accueil](docs/captures/appli_accueil.png)

| 🔌 Collecter (sur le poste suspect) | 💻 Analyser (sur votre PC) |
|---|---|
| 1. **Intervention** : technicien, cabinet, personne présente, ticket, motif | 1. **Collecte à analyser** : détectée sur la clé PREUVES (même en lecture seule) |
| 2. **Feu vert** : signes de chiffrement en cours, sans rien écrire sur le poste | 2. **Copie vérifiée** dans un dossier de travail (SHA-256, PV de copie) |
| 3. **Clé PREUVES** : branchée seulement maintenant, fichiers pièges posés | 3. **Analyse complète** ($MFT) puis **interface HTML** et scellé horodaté |
| 4. **Collecte** surveillée : coupure immédiate de la clé au moindre signe | 4. **Rapport** : interface, PV de collecte à imprimer et faire signer |
| 5. **Scellé** affiché en grand (à photographier), puis **éjection** propre | |

- 🧰 Deux clés : OUTILS en lecture seule (interrupteur), PREUVES chiffrée. Détails et limites : [docs/CLES_USB.md](docs/CLES_USB.md).
- ✍️ Signature de l'exe (pour afficher le nom de l'éditeur au lieu de « Inconnu ») : [docs/SIGNATURE.md](docs/SIGNATURE.md).
- 🛠️ Construire : `app\CONSTRUIRE.bat` (compilateur C# déjà présent dans Windows, rien à installer), puis `app\SIGNER.bat`.
- 🧪 Démonstration sans rien toucher : `DigSpill.exe --demo`.
- Les `.bat` restent utilisables tels quels (mode console).

<details>
<summary>Autres écrans (rendu de test sous Linux : les polices diffèrent de Windows)</summary>

![Feu vert](docs/captures/appli_feuvert.png)
![Collecte en cours](docs/captures/appli_collecte.png)
![Fin de collecte : scellé et éjection](docs/captures/appli_fin.png)

</details>

## Déroulé conseillé

1. Sur le poste suspect : `LANCER_COLLECTE.bat` (environ 15 à 30 min).
2. Toujours sur place : remplir `A_COMPLETER_TECHNICIEN.txt` (date de découverte, heure de la box, journaux de la box), puis lancer `LISTER_IDENTIFIANTS.bat` dans la session de chaque compte.
3. Au bureau : `Copier-Preuves.ps1 -Source E:\Collecte -Destination F:\PREUVES_<client>` (support NTFS/exFAT distinct, conservé à part).
4. Sur le poste d'analyse : `ANALYSER_COLLECTE.bat` (analyse complète, avec la $MFT du conteneur Velociraptor). Ajouter des fenêtres si besoin : `ANALYSER_COLLECTE.bat "E:\Collecte\POSTE_20261117_150121" "2026-10-18 22:00;2026-10-19 06:00"`.
5. À la fin de l'analyse, le fichier `Collecte\<POSTE>_<date>_INTERFACE.html` est créé et s'ouvre : c'est lui qu'on lit, qu'on présente et qu'on archive avec le dossier. Pour le régénérer (après avoir saisi des réglages, par exemple) : glisser le dossier de collecte sur `GENERER_INTERFACE.bat`.

## Interface autonome (un seul fichier HTML)

`GENERER_INTERFACE.bat` crée **un seul fichier** `<POSTE>_<date>_INTERFACE.html` qui contient l'interface, les graphiques, la carte du monde et toutes les données de la collecte et de l'analyse. On le copie sur n'importe quel PC et on l'ouvre d'un double-clic (Edge, Chrome ou Firefox) : pas de serveur, pas d'installation, ça fonctionne hors ligne.

![Résumé : que faire maintenant ?](docs/captures/resume.png)

Quatre onglets, trois niveaux de lecture : la phrase en haut (5 secondes), les actions et le récit (30 secondes), la preuve (un clic).

| Onglet | Ce qu'il montre |
|---|---|
| 🎯 Résumé | Une phrase de faits (« Une connexion à distance depuis la Roumanie, 1,9 Go envoyés sur Internet, puis 48 213 fichiers chiffrés. »), les **actions à faire maintenant** (cases à cocher, compte à rebours CNIL, procédure « Isoler le poste »), ce que la collecte ne peut pas voir |
| 🕒 Chronologie | La fenêtre de l'attaquant **racontée en 4 chapitres** : il entre, il s'installe, il emporte les données, il détruit. Chaque étape s'ouvre sur ses preuves : ce que dit la ligne, fichier, n° de ligne, SHA256 du manifeste |
| 🔎 Détails | Grille par canal, fenêtres, chiffres clés et alertes, IP et pays, exfiltration, visibilité, santé et RGPD, identifiants et fuites, IOC et chasse, analyse IA, tous les événements (frise), SYNTHESE.txt |
| 🔏 Preuves | Intégrité (scellé horodaté, chaîne de possession, vérification des fichiers) et rapports à imprimer (praticien, technique, PV de collecte) |

- **Ctrl K** : recherche dans les IP, empreintes, comptes, étapes du récit, rubriques, et identifiants de preuve (`executions_fenetres#14`).
- Thème sombre par défaut, **thème clair** dans Réglages (engrenage en haut à droite). Le rapport imprimé reste clair.
- Polices Geist, Geist Mono et Doto **embarquées** (sous-ensembles latins, licence OFL) : aucune requête réseau à l'ouverture.
- Les anciens liens (`#ip`, `#exfil`, `#integrite`, `#rapport`…) ouvrent la bonne rubrique.

Chaque constat renvoie à sa preuve : un identifiant `fichier#ligne` cliquable qui affiche la ligne du CSV d'origine et le SHA256 du fichier dans le manifeste.

![Chronologie racontée : l'étape MEGA ouverte sur ses 8 preuves](docs/captures/chrono.png)

<details>
<summary>Autres captures (collecte fictive de démonstration)</summary>

![Recherche Ctrl K](docs/captures/recherche.png)
![Isoler le poste : procédure](docs/captures/isoler.png)
![Grille par canal](docs/captures/grille.png)
![IP et pays](docs/captures/ip.png)
![Exfiltration](docs/captures/exfil.png)
![Visibilité](docs/captures/visibilite.png)
![Santé et RGPD](docs/captures/sante.png)
![Identifiants et fuites](docs/captures/fuites.png)
![IOC et chasse](docs/captures/ioc.png)
![Analyse IA : réponse d'exemple passée au vérificateur](docs/captures/ia.png)
![Tous les événements](docs/captures/evenements.png)
![Thème clair](docs/captures/clair.png)
<img src="docs/captures/mobile.png" alt="Téléphone (390 px)" width="300">

</details>

### Scellé et valeur de preuve

![Intégrité et preuve](docs/captures/integrite.png)

| | Ce que fait DigSpill | Ce que ça prouve |
|---|---|---|
| 🧾 | Manifeste SHA-256 de chaque fichier collecté et analysé | Aucun fichier n'a changé depuis |
| 🔏 | **Scellé** `SCELLE_<date>.txt` : empreintes des manifestes, journaux et PV de copie | Un seul code de 64 caractères résume tout le dossier |
| ⏱️ | Scellé **horodaté par un tiers** (jeton RFC 3161, `.tsr`) | Le dossier existait tel quel à cette date |
| 🔗 | Chaîne de possession reconstituée (journaux, manifestes, PV de copie, scellés) | Qui a eu les preuves, quand, pour faire quoi |
| 🧪 | Vérification dans le navigateur : on choisit le dossier, chaque fichier est re-haché | N'importe qui peut refaire le contrôle |
| ✍️ | **PV de collecte et certificat d'intégrité** imprimable, à signer (technicien, cabinet, témoin) | Qui a fait quoi, avec quels outils |

- Le scellé est écrit dans `Collecte\<POSTE>_<date>_scelles\`. Il n'est recréé que si un élément a changé : le premier horodatage reste valable.
- Horodateur par défaut : `http://timestamp.sectigo.com/qualified` (Sectigo, annoncé conforme eIDAS ; conditions d'usage et éventuels frais à vérifier). Autre autorité : `-Horodateur <url>`. Sans horodatage : `-SansHorodatage`. Seule l'empreinte du scellé est envoyée.
- Vérifier le jeton : `openssl ts -verify -data SCELLE_<date>.txt -in SCELLE_<date>.tsr -CAfile <chaîne de l'autorité>`.
- ⚖️ En France la preuve est libre au pénal (art. 427 CPP) ; un écrit électronique vaut s'il identifie son auteur et garantit son intégrité (art. 1366 C. civ.). Un horodatage **qualifié** eIDAS est présumé exact (art. 41 du règlement UE 910/2014). Le PV reste un document de prestataire, pas un constat de commissaire de justice. À valider avec un avocat ou l'assureur.

### Ce qui part sur Internet (et ce qui ne part pas)

- **Rien ne sort du fichier sans un clic.** Les données de la collecte restent dans le fichier.
- **Bases publiques** : le `.bat` télécharge des listes publiques entières dans `outils\bases` (pays et opérateur IPtoASN, Tor, FireHOL, blocklist.de, GreenSnow, CINS, Feodo, Spamhaus DROP, victimes publiées sur ransomware.live) et les compare **en local**. Le nom du client et ses IP ne sont jamais envoyés. Option `-AvecVilles` : base des villes DB-IP Lite (~40 Mo). Option `-SansInternet` : utilise seulement les bases déjà présentes.
- **Horodatage** : seule l'empreinte SHA-256 du scellé part vers l'autorité d'horodatage (désactivable).
- **Sur clic seulement** : Have I Been Pwned (seuls les 5 premiers caractères du hachage SHA-1 du mot de passe), Shodan InternetDB (l'IP choisie), liens VirusTotal / MalwareBazaar (le hachage choisi), Claude (la synthèse filtrée, affichée avant l'envoi : comptes pseudonymisés U1, U2…, noms de fichiers et dossiers masqués, URL réduites au domaine, e-mails masqués).
- Sans clé API, le bouton « Copier consignes + synthèse » permet d'utiliser claude.ai, puis de recoller la réponse pour en vérifier les citations.

### Réglages et mémoire des incidents

- Les réglages saisis dans l'interface (client, date de découverte, débit de la box, liste blanche, horaires du cabinet…) sont gardés dans le navigateur. « Exporter les réglages » produit `<POSTE>_<date>_reglages.json` : posé à côté du dossier de collecte, il est repris à la prochaine génération.
- `outils\bases\memoire_incidents.json` garde les IOC (IP, hachages, noms d'outils) de chaque collecte traitée : l'interface signale un indicateur déjà vu chez un autre client.

### Sécurité du fichier

Le fichier HTML est **aussi sensible que la collecte** (comptes, chemins, sites consultés). Pour l'envoyer : `GENERER_INTERFACE_PROTEGEE.bat` (AES-256 + HMAC-SHA256, clé dérivée du mot de passe par PBKDF2, 200 000 itérations ; .NET 4.7.2 minimum), et le mot de passe par un autre canal.

### Développement

Le code de l'appli Windows est dans `app\` (C# 5, WinForms, .NET Framework 4.x : `app\CONSTRUIRE.bat`). Le code de l'interface est dans `interface\` (`modele.html`, `style.css`, `js\01_base.js` à `06_integrite.js`, ECharts, la carte et les polices dans `vendor\`, le logo dans `assets\`). Le récit de la Chronologie et les actions du Résumé sont calculés par des règles fixes (`T.recit`, `T.actions` dans `02_analyse.js`), sans IA. `interface\dev\generer_demo.py` crée une collecte fictive (adresses de documentation RFC 5737, domaines `.example`) et `interface\dev\assembler.py` produit le même fichier que le `.ps1`, pour tester sans Windows ; le workflow `Interface HTML` vérifie sur Windows que les deux générateurs produisent le même fichier (`interface\dev\comparer_generateurs.py`). `interface\dev\tsa_demo.sh` crée une autorité d'horodatage **fictive** (OpenSSL) pour la démo : `assembler.py --tsa-demo demo/tsa`.

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
  <POSTE>_<date>_scelles\       SCELLE_<date>.txt + jeton d'horodatage (.tsq, .tsr, .horodatage.txt)
  <POSTE>_<date>_INTERFACE.html interface autonome
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
- Interface autonome : Windows PowerShell 5.1 pour la générer ; un navigateur récent (Edge, Chrome, Firefox) pour la lire, sur n'importe quel système.

## Précautions

- Les collectes contiennent des données personnelles et de santé potentielles, ainsi que la ruche SAM : chiffrer ou protéger la clé, ne jamais versionner le dossier `Collecte\`.
- Les preuves ne doivent pas exister en un seul exemplaire : faire une seconde copie hachée avec `Copier-Preuves.ps1` et la conserver séparément.
- La collecte n'écrit sur le poste que des fichiers temporaires (`%TEMP%`), supprimés après usage. L'analyse écrit uniquement sur la clé ou le dossier de sortie.
- La veille sur les sites de fuite se fait à la main (`note_rancon_analyse.txt`) : le script n'envoie jamais le nom du client à un service tiers.
