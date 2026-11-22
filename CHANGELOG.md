# Journal des versions

## 2.8 (bêta)
Testé de A à Z sur un vrai Windows : l'appli pilotée comme par un technicien, sur des traces d'attaque réelles.

- **Test du parcours complet** (workflow `Test parcours complet`) : kit de release sur une clé OUTILS, clé PREUVES exFAT, scénario d'attaque réel et sans danger (outil renommé et antidaté, compte administrateur ajouté, tâche planifiée, exclusion Defender, rclone avec un compte MEGA fictif, archive, visites de sites de partage, échecs de connexion, journal effacé, fichiers `.lockbit3`), puis `DigSpill.exe --auto` clique dans les vraies pages : intervention, feu vert, collecte, scellé horodaté, éjection, copie vérifiée, analyse, interface. Chaque écran est capturé et les données de l'interface sont comparées à ce que le scénario a vraiment fait.
- **Collecte bloquée à la fin sur Windows Server : corrigé.** Sans la Sauvegarde Windows Server, `wbadmin get versions` ouvrait la console `wbadmin.msc`, qui ne se ferme jamais ; DigSpill attendait sa sortie. `wbadmin.exe` est appelé par son chemin, et DigSpill n'attend plus plus de 10 s une sortie qu'un programme garde ouverte.
- **Copie vérifiée : corrigé.** Sous PowerShell 5.1, `-Include` est ignoré avec `-LiteralPath` : la copie lisait chaque fichier de la clé (image RAM comprise) comme un CSV et s'arrêtait faute de mémoire. Même erreur corrigée pour les journaux des outils d'accès distant à la collecte.
- **Mémoire vive lue au bureau** : Python embarquable 3.12.10 et Volatility 3 (2.28.2) dans le kit (roues PyPI vérifiées par SHA256). La collecte note l'identité des symboles du noyau (`memoire\noyau.json`) ; l'analyse prépare les symboles (gardés dans `moteur\outils\symboles`), lit les processus, lignes de commande et connexions, et signale les indices (nom imitant un processus Windows, outil d'envoi, dossier public, commande encodée, parent anormal). Jamais sur le poste collecté.
- **Interface** : rubrique « Mémoire vive », voie « Mémoire vive » dans la chronologie, alerte si un programme suspect était encore actif, recherche Ctrl K des processus.
- **Fin de collecte honnête** : « Collecte incomplète » avec la raison quand la collecte PowerShell n'a pas produit de dossier (avant : « avec des avertissements » et une empreinte « aucun scellé » découpée en blocs).
- **Mode une seule clé** : DigSpill ne s'éjecte plus lui-même (l'exe tourne depuis la clé) ; il se ferme et Windows éjecte la clé juste après.
- **Fenêtres d'analyse sur indices forts** : une attaque menée sur place ou par un outil d'accès distant n'ouvre pas de session RDP depuis Internet. Les fenêtres se forment aussi sur les indices horodatés (compte créé ou ajouté aux administrateurs, journal effacé, Defender coupé, rclone ou mimikatz lancé, commandes destructrices, chiffrement) : la chronologie a de nouveau quelque chose à raconter.
- **Comptes de transfert configurés** (`comptes_transfert.csv`) : rclone, FileZilla, WinSCP. Identifiant, serveur, type ; mots de passe et jetons jamais lus ni décodés. Alerte, chronologie et carte dans Exfiltration.
- **Mémoire vive** : nom complet malgré la limite de 14 caractères de Windows (`fontdrvhost.ex` n'est plus pris pour une imitation), chemin repris du relevé en direct, message de Volatility gardé quand un module échoue, nouvel essai cache vidé puis avec les symboles en ligne. Si le noyau reste introuvable dans l'image (2 copies sur 7 sur le Windows de test), l'analyse le dit et renvoie au relevé en direct.
- **Chronologie** : étapes identiques regroupées (« Efface des journaux Windows (× 18) »), « Autres événements » limités à 40 avec un lien vers Tous les événements. **Visibilité** : traces identiques regroupées.
- **Récit plus juste** : « Supprime les sauvegardes Windows » seulement sur une vraie suppression (`vssadmin delete`, `wbadmin delete`, `bcdedit recoveryenabled`…), plus sur un simple `vssadmin list shadows` ; note de rançon retenue si son nom est évocateur ou si le même fichier est dans 20 dossiers (les README d'un poste de développeur n'en sont pas) ; chiffrement reconnu aussi par une extension inconnue ajoutée à un document bureautique, PDF ou base (`facture.xlsx.x7k2m9`), hors extensions de logiciels (`.dll`, `.data`…).
- **Bases métier** : modèles SQL Server, fichiers de Windows et des outils de développement (Visual Studio, .NET, NuGet, R…) ignorés, bases de moins de 1 Mo non retenues pour la taille de la base patients (elle était estimée sur un fichier système).
- **Récit sans le bruit de Windows ni de DigSpill** : services créés par Windows à chaque ouverture de session (`Nom_1a2b3c`) et service de copie de la RAM de DigSpill (`digspill_pmem`) retirés de la chronologie et des actions ; « Volume envoyé non mesurable » quand SRUM n'a rien relevé, au lieu de « Jusqu'à 0 Mo envoyés ».
- **Appli** : avancement réel pendant la copie vérifiée (fichiers re-hachés) et l'analyse (étape en cours) ; « Rapport partiel » et étape en rouge si l'analyse échoue.
- Liste « Motif » en sombre (la liste de Windows restait blanche) ; manifeste de collecte avec progression (volume, gros fichiers, avancement chaque minute) ; option « Analyse complète » qui inclut la mémoire vive ; `-SansInternet` transmis à l'analyse.

## 2.7.1 (bêta)
Correction importante de la copie de la RAM.

- **La copie de la RAM ne touche plus au pilote de Windows.** `winpmem_mini_x64_rc2.exe` installait son pilote sous le nom de service `pmem`, déjà pris par le pilote Windows de mémoire persistante (`pmem.sys`). Constaté sur un Windows de test : la copie échouait (0 octet) et le pilote de Windows passait en « Désactivé », marqué pour suppression au redémarrage. La collecte utilise maintenant la fonction `winpmem()` du collecteur Velociraptor (même pilote, signé par Microsoft), sous le nom `digspill_pmem`. Le pilote est déposé à côté de l'image, sur le support de destination, puis retiré ; second essai depuis le dossier temporaire de Windows s'il ne se charge pas. Le service est vérifié et retiré à la fin.
- `winpmem_mini_x64_rc2.exe` n'est plus dans le kit (la licence WinPmem reste, pour le pilote intégré à Velociraptor).
- Place demandée pour la RAM : RAM + 5 Go (l'image couvre tout l'espace d'adresses, trous compris, souvent 1 à 3 Go de plus que la RAM).
- `memoire_info.txt` indique l'outil, le service et l'endroit où le pilote a été déposé ; alerte si l'image est plus petite que la RAM.
- README : section « Mémoire vive : test réel » avec 4 captures des résultats (copie, processus, lignes de commande, réseau).
- Nouveau test GitHub `Test collecte et RAM` : vraie collecte en mode complet depuis une clé exFAT, contrôles (pilote Windows intact, service retiré, aucun pilote laissé sur le poste), lecture de l'image par Volatility 3.

## 2.7 (bêta)
Un seul clic : la clé ne montre plus que `DigSpill.exe` et un dossier `moteur\`.

- **Kit prêt à l'emploi** fabriqué par GitHub (workflow `Kit DigSpill`, script `app\construire-kit.ps1`) : DigSpill.exe compilé, 7zr.exe, WinPmem et collecteur Velociraptor généré avec `spec.yaml`, téléchargés depuis leurs sources officielles avec licences et SHA256 (`moteur\outils\LISEZ-MOI-OUTILS.txt`). Artefact `DigSpill-cle` ; `DigSpill.zip` en release sur un tag `v*`.
- **Rangement** : scripts, interface, outils, `spec.yaml` et `digspill.ini` dans `moteur\` ; `Collecteur-Velociraptor.exe` dans `moteur\outils\`. Les résultats restent dans `Collecte\` à la racine de la clé. L'ancien rangement (tout à la racine) fonctionne encore.
- Les `.bat` passent dans `moteur\secours\`, chemins ajustés, pour un poste qui bloquerait DigSpill.exe.
- **DigSpill.exe 1.1** : lit les identifiants enregistrés du compte de la session avant l'élévation (sous manifeste, dans `exposition\`) ; bouton « Identifiants de ce compte » pour les autres sessions (remplace LISTER_IDENTIFIANTS.bat) ; technicien retenu dans `moteur\digspill.ini`.
- **DigSpill.exe en noir**, même direction artistique que l'interface HTML : fond `#0b0b0c`, logo vectoriel au point rouge, polices Geist et Geist Mono embarquées dans l'exe (OFL), sections à filets au lieu de cartes, bouton principal rouge, étapes à puces comme la Chronologie, pastilles en Geist Mono, barre de titre et barres de défilement sombres sous Windows 10/11. La date de découverte se saisit au clavier (JJ/MM/AAAA HH:MM) au lieu du calendrier Windows, resté clair.
- `SIGNER.bat E:\DigSpill.exe` signe directement l'exe de la clé. Les messages des scripts et de l'interface renvoient à DigSpill.exe au lieu des `.bat`.

## 2.6 (bêta)
Nouvelle interface : répondre d'abord à « que faire maintenant ? ».

- **4 onglets au lieu de 11** : Résumé, Chronologie, Détails, Preuves. Les anciens écrans deviennent des rubriques de Détails et de Preuves ; les anciens liens (`#ip`, `#exfil`, `#integrite`, `#rapport`…) sont redirigés.
- **Résumé** : une phrase de faits, les actions à faire (3 visibles, les autres repliées, cases cochées gardées dans le navigateur), compte à rebours CNIL, procédure « Isoler le poste » (débrancher, couper le Wi-Fi, ne pas éteindre, noter l'heure), ce que la collecte ne peut pas voir.
- **Chronologie racontée** en 4 chapitres (il entre, il s'installe, il emporte les données, il détruit) par des règles fixes, sans IA. Chaque étape montre ses preuves (ligne, fichier, n° de ligne, SHA256) et les traces liées ; un événement important non reconnu va dans « Autres événements ». Fenêtre en liste blanche : chapitres aux noms neutres.
- **Recherche Ctrl K** : IP, empreintes, comptes, étapes, rubriques, identifiants de preuve.
- Logo « digspill » au point rouge, favicon, **thème sombre** par défaut et thème clair dans Réglages ; polices Geist, Geist Mono et Doto embarquées (sous-ensembles latins, 82 Ko, OFL) ; plus aucun emoji dans l'interface ; graphiques aux couleurs du thème.
- Rapport imprimé : toujours clair, avec le logo noir.
- Icône de DigSpill.exe refaite à partir du nouveau logo.
- Workflow `Interface HTML` : vérifie sur Windows que `Generer-Interface.ps1` et `assembler.py` produisent le même fichier.

## 2.5 (bêta)
Appli Windows **DigSpill.exe** et protection de la clé contre un rançongiciel.

- **DigSpill.exe** (nouveau, `app\`) : deux parcours. *Collecter* : saisie de l'intervention, feu vert, choix de la clé PREUVES, collecte suivie étape par étape, scellé affiché en grand, éjection. *Analyser* : copie vérifiée, analyse complète, interface et PV. Élévation demandée seulement pour collecter. Mode `--demo`.
- **Feu vert** avant de brancher la clé PREUVES : notes de rançon, extensions ajoutées ou inconnues sur des fichiers récents, programme qui écrit beaucoup depuis un dossier utilisateur, antivirus coupé, réseau actif, clé OUTILS protégée ou non.
- **Fichiers pièges** et surveillance de la clé PREUVES ; **coupure d'urgence** : arrêt de la collecte, disque en lecture seule, volume démonté, lettre retirée.
- **Scellé de fin de collecte** écrit sur place (manifeste, journal, conteneurs Velociraptor), horodaté si Internet. Le générateur horodate ensuite tous les scellés qui n'ont pas encore de jeton.
- `Collecte-Exfil.ps1` : `-Destination` (clé PREUVES distincte de la clé OUTILS) et champs d'intervention (`-Technicien`, `-Societe`, `-Client`, `-Present`, `-Ticket`, `-Motif`, `-Decouverte`) écrits dans `infos_collecte.txt` et repris dans le PV.
- `Copier-Preuves.ps1 -Collecte <nom>` : copie une seule collecte (et ses conteneurs) et pose le PV de copie dans la collecte copiée.
- `Generer-Interface.ps1 -Bases <dossier>` ; mot de passe de `-Proteger` transmis par l'appli sans saisie.
- Signature : `app\SIGNER.bat`, guide `docs/SIGNATURE.md`. Clés USB : `docs/CLES_USB.md`. Workflow GitHub qui construit l'exe non signé.

## 2.4 (bêta)
Scellé de preuve : montrer que le dossier n'a pas bougé, depuis quand, et qui l'a eu entre les mains.

- **Scellé** (`Generer-Interface.ps1` 1.1) : `SCELLE_<date>.txt` dans `<POSTE>_<date>_scelles\` résume en une empreinte SHA-256 les manifestes, les journaux de collecte et d'analyse et les PV de copie. Il est réutilisé tant que rien ne change.
- **Horodatage par un tiers** (RFC 3161) : requête construite sans outil externe, envoyée à `http://timestamp.sectigo.com/qualified` par défaut (`-Horodateur`, `-SansHorodatage`). Jeton `.tsr` + fiche `.horodatage.txt` avec les commandes OpenSSL de vérification. Seule l'empreinte part.
- Écran **🔏 Intégrité et preuve** : empreinte et QR code du scellé, lecture du jeton (date, autorité, n° de série, correspondance avec le scellé), chaîne de possession, vérification des fichiers dans le navigateur (WebCrypto, rien n'est envoyé ; commandes Get-FileHash pour les fichiers trop gros).
- **PV de collecte et certificat d'intégrité** imprimable : identification, intervenant et méthode, empreintes, chaîne de possession, vérification par un tiers, observations, signatures. Section « Intégrité et chaîne de possession » ajoutée au rapport technique.
- Les journaux `.log` à la racine de la collecte sont embarqués ; date de modification de chaque fichier conservée.

## 2.3 (bêta)
Le projet s'appelle désormais **DigSpill** (dépôt, interface, rapports, titres des fenêtres).

Interface autonome : un seul fichier HTML pour lire une collecte sur n'importe quel PC, sans serveur ni installation.

- **`GENERER_INTERFACE.bat`** / **`Generer-Interface.ps1`** (nouveaux) : assemblent `Collecte\<POSTE>_<date>_INTERFACE.html` (interface, graphiques ECharts, carte du monde et données embarquées). Lancé aussi à la fin de `ANALYSER_COLLECTE.bat` et de `LANCER_COLLECTE.bat` (sans Internet depuis le poste suspect).
- Bases publiques téléchargées entières dans `outils\bases` puis comparées en local : pays et opérateur (IPtoASN), villes (DB-IP Lite, option `-AvecVilles`), Tor, FireHOL, blocklist.de, GreenSnow, CINS, Feodo, Spamhaus DROP, victimes publiées sur ransomware.live. Aucune donnée de la collecte n'est envoyée.
- Écrans : vue d'ensemble (alertes, compte à rebours CNIL), chronologie unifiée, IP et pays, exfiltration, visibilité, santé et RGPD, identifiants et fuites, IOC et chasse, analyse IA, rapports.
- **Test de plausibilité de l'exfiltration** : volume envoyé (SRUM) et capacité de la ligne (débit montant × durée) comparés à la base patients compressée ; fenêtres en liste blanche et volumes habituels distingués.
- **Carte de visibilité** : couverture de chaque source heure par heure autour des fenêtres, traces d'anti-forensique (journaux effacés, Defender désactivé ou exclu, VSS supprimés).
- **Lecture santé** : logiciels métier (AxiSanté, MediStory, Logos_w, Julie…) et sites santé repérés, catégories de données déduites et sourcées, sessions hors horaires du cabinet.
- **Chasse sur tout le parc** : composant PowerShell Datto RMM généré (lecture seule) ; mémoire des incidents (`memoire_incidents.json`) pour signaler les IOC déjà vus chez un autre client.
- **Analyse IA vérifiable** : synthèse filtrée (comptes pseudonymisés, fichiers masqués), Claude cite une preuve par phrase, chaque citation est contrôlée (identifiant existant, valeurs présentes dans la ligne).
- Have I Been Pwned par k-anonymat, Shodan InternetDB sur clic, liens VirusTotal / MalwareBazaar.
- `GENERER_INTERFACE_PROTEGEE.bat` : fichier chiffré (AES-256-CBC + HMAC-SHA256, PBKDF2 200 000 itérations).
- Rapports praticien (1 page) et technique sourcé (index des preuves avec SHA256 du manifeste), en PDF par l'impression.

## 2.2 (bêta)
Analyse orientée exfiltration, pour une conclusion chiffrée et graduée plutôt qu'un « pas d'indice ».

- **`Analyse-Exfil.ps1`** (nouveau), lancé après Velociraptor ou a posteriori (`ANALYSER_COLLECTE.bat`, glisser-déposer). Il complète ce qui manque à la collecte à partir du conteneur Velociraptor (ruches, $MFT, journaux) et produit `SYNTHESE_EXFILTRATION.txt` : une grille par canal (INDICE / À LIRE / RAS / NON VÉRIFIABLE) et une proposition de conclusion graduée, avec ce qui ferait évoluer la position.
  - Sessions reconstituées (4624/4634/4647, LSM 21-25, 1149, 131) avec durée et IP. Fenêtres d'analyse dérivées automatiquement : IP publiques, plage VPN/CGNAT, compte Invité, plus `-Fenetres` manuelles.
  - SRUM : volumes par application et par relevé horaire, comparés à une base de référence (moyenne, 95e centile, max sur 21 jours). Méthode de mesure écrite noir sur blanc (`srum_METHODE.txt`), volume attribué au Bureau à distance.
  - Exécutions pendant les fenêtres : Prefetch, Amcache (SHA1), BAM, 4688, Sysmon.
  - Navigation web complète par fenêtre, avec repérage des sites santé, messagerie et partage de fichiers.
  - Canaux sans volume : `\\tsclient` et accès aux données métier dans les LNK, Jump Lists, RecentDocs, TypedPaths et ShellBags (analyse structurée et recherche brute). Paramètres de redirection RDP, exécutions de `rdpclip`.
  - Fichiers créés ou modifiés pendant les fenêtres : journal USN, avec indication de sa couverture réelle, et $MFT du conteneur.
  - Outils d'accès distant : inventaire, journaux propres, événements Splashtop, pairs NetBird.
  - Sources déjà collectées, avec une ligne même si le résultat est vide : journal du pare-feu (activé ou non), BITS, USB, SMBServer, partages 5140/5145, DNS-Client.
  - Note de rançon : contacts, identifiant, revendication de vol de données (oui / aucune mention), check-list de veille (ID Ransomware, ransomware.live, ransomlook).
  - Identifiants : mimikatz exécuté ou non (Prefetch, Amcache, BAM, 4688, 4104, Defender, LSASS), outils NirSoft exécutés et leur portée, cibles du gestionnaire d'identifiants.
  - IOC : SHA256 des fichiers présents, SHA1 Amcache, SHA1 de la quarantaine Defender rapprochés des détections 1116/1117.
  - Conteneurs Velociraptor : SHA256 complet (fichier `.sha256` à côté) et détection d'archive tronquée (limite FAT32 de 4 Go).
- Collecte : journaux NetBird (configuration avec clés masquées, `netbird status`), Splashtop, TSplus, Datto RMM, RustDesk et ScreenConnect. Ajout de l'état des journaux et de la politique d'audit, de la journalisation du pare-feu, des redirections RDP, des dates USB (première installation, dernier branchement et dernier retrait), de nouveaux journaux evtx (SMB, PnP RDP, Splashtop) et du hachage du collecteur Velociraptor.
- Ruches utilisateurs : une copie impossible n'est plus silencieuse. Repli par lecture NTFS brute, et chaque ruche manquante est signalée.
- Fiche technicien : date de découverte (délai CNIL de 72 h), nombre de patients et catégories de données, écart d'horloge mesuré, décalage UTC sur la période, demande type au FAI, seconde copie des preuves.
- `LISTER_IDENTIFIANTS.bat` : cibles du gestionnaire d'identifiants, à lancer dans chaque session.
- `Copier-Preuves.ps1` : seconde copie vérifiée par SHA256 (comparaison aux manifestes) et procès-verbal de copie.

## 2.1 (bêta)
- `SYNTHESE.txt` généré en fin de collecte : chiffrement détecté (fenêtre courte), notes de rançon, VSS, IP publiques avec connexion réussie, force brute, comptes RDP sans mot de passe obligatoire, `LimitBlankPasswordUse`, détections Defender, outils sensibles.
- Fichiers d'échange (`pagefile.sys`, `hiberfil.sys`) : détection fiable (Get-Item échouait), copie journalisée.
- Copie des dossiers protégés (journaux et quarantaine Defender) : reprise des fichiers verrouillés via cliché VSS.

## 2.0
- Mode léger pour les autres postes du réseau.
- Capture RAM (winpmem) vers un disque externe `MEMOIRE`, sinon pagefile / hiberfil.
- Traces du rançongiciel : fichiers chiffrés par extension, notes de rançon, bases métier, VSS, commandes destructrices, binaires suspects en archive chiffrée, quarantaine Defender.
- Listing complet des disques (moteur C# rapide).
- Connexions RDP et comptes : CSV structurés, synthèse par IP, inventaire avec accès RDP effectif.
- Identifiants exposés dans les navigateurs (sites seulement, mots de passe non lus).
- Fiche à compléter par le technicien (heure, box, pare-feu).

## 1.1
- Velociraptor lancé par le même `.bat`, journal USN via `fsutil`.
- Exclusion de l'index Windows Search et des binaires OneDrive (limite FAT32 de 4 Go).
