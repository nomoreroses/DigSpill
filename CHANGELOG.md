# Journal des versions

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
