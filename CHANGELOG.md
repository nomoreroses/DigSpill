# Journal des versions

## 2.9.4 (bêta)
Corrections tirées d'une vraie collecte (serveur chiffré par un rançongiciel) :
- **Chiffrement manqué, maintenant vu** : les fichiers renommés en `<aléatoire>.[e-mail].extension` (sans l'ancienne extension) sont reconnus. Et une extension inconnue à l'aspect aléatoire (ex. `.Fa2a2yMH`) posée sur 500 fichiers ou plus en moins de 2 h est signalée comme chiffrement, même sans e-mail dans le nom.
- **Fausse alerte supprimée** : les doubles extensions de documents (`facture.pdf.pdf`, `.pdf.xlsx`, copies faites par une mise à jour du logiciel métier) ne comptent plus comme fichiers chiffrés.
- Dates du chiffrement : la plus récente de création / modification (certains rançongiciels remettent l'ancienne date de modification).
- **Bases du cabinet** : les fichiers livrés avec Windows (WinSxS…) ne sont plus listés. Le dossier « Données Axilog\Data » (documents patients) apparaît avec sa taille totale.
- **Notes de rançon** : les fichiers d'aide de Windows, des applis du Store et de OneDrive ne sont plus candidats ; « help » ne prend plus `GetHelpWindow` ni `dbghelp`.
- **Binaires suspects** : les bibliothèques que Java recopie dans Temp à chaque lancement (carte CPS, USB, SQLite) sont écartées (83 → 14 lignes sur le cas réel) ; un même fichier n'est archivé qu'une fois.
- **Mémoire vive** : son SHA256 n'est plus recalculé pour le manifeste (plusieurs minutes gagnées).
- **Nouvelles alertes rouges** (vu sur le serveur : rien ne s'affichait en haut du Résumé à part le chiffrement) :
  - « Connexion réussie depuis Internet » avec l'adresse, le pays et les comptes, si un autre signe s'ajoute (pays étranger, hébergeur, liste malveillante, essais en masse, compte Invité). Une connexion depuis la France sans autre signe (praticien chez lui) reste dans la page Adresses IP.
  - « Outil de pirate déposé pendant l'attaque » (scanner de ports…) : sur un serveur, Windows ne garde pas la trace des programmes lancés (Prefetch désactivé), la date de dépôt est souvent le seul indice. Ces outils comptent aussi dans « outils à risque ».
- Réglages du bureau à distance (copier-coller, disques) : si les ruches ne peuvent pas être lues, l'analyse reprend les valeurs relevées pendant la collecte au lieu d'afficher « Impossible à vérifier ».
- **Plus de fenêtres CMD en rafale** (#12) : Velociraptor, robocopy et esentutl sont lancés sans fenêtre. Les fichiers verrouillés d'un dossier (quarantaine Defender, journaux Datto RMM, Splashtop, TSplus…) sont lus en une seule fois au lieu d'un lancement par fichier.
- **Antivirus** (#11) : `Analyse-Exfil.ps1` était mis en quarantaine comme rançongiciel (« Ransom.Rhysida »). Les noms de familles de rançongiciels, motifs de notes de rançon, adresses .onion / Bitcoin et liens de veille sont sortis des scripts, dans `moteur\indicateurs.json` (comme les noms d'outils en 2.9.2). Un test vérifie qu'ils n'y reviennent pas.

## 2.9.3 (bêta)
- **Données du cabinet** : l'analyse reconnaît maintenant les dossiers et bases de MediStory, AxiSanté, HelloDoc, Crossway, Weda, Logos_w, Julie, Desmos, Visiodent/Veasy (avant : Axilog seulement). Dans ces cabinets, « Données du cabinet ouvertes pendant l'attaque » ne dit plus « Rien de suspect » sans avoir regardé. Le lancement du logiciel (.exe) n'est pas compté comme une ouverture de données.
- **Une seule version partout** : scellé, journaux, PV de collecte et identifiants indiquent la version du kit (ex. 2.9.3) au lieu de « v1.1 », « 2.2 » ou « interface 1.2-beta ».
- Résumé texte de l'analyse : plus de dates du premier incident (« du 14 au 21/10 », « jusqu'au 25/10/2026 »).
- Alerte mémoire vive : le lien « Voir → » ouvre bien la page Mémoire vive (il ouvrait le Résumé).
- Nettoyage : base des villes retirée (jamais fournie par le kit ni l'appli : la carte place les IP par pays), code mort supprimé, déclencheurs de tests sur des branches disparues retirés, nom du fichier-appât à l'année en cours.
- **Garde-fous dans les tests** : le générateur Python et le générateur PowerShell doivent produire les mêmes données (pas seulement la même page) ; les copies du motif rançongiciel et du classement des IP doivent rester identiques ; `Get-Evtx` ne doit plus être passé directement à un pipeline (cause de l'erreur `op_Subtraction` de la 2.9.1).

## 2.9.2 (bêta)
- **Textes du rapport réécrits en clair**, page par page, sans jargon :
  - Rubriques renommées : *Points vérifiés* (ex-grille par canal), *Périodes suspectes* (ex-fenêtres d'analyse), *Adresses IP et pays*, *Données sorties du poste* (ex-exfiltration), *Angles morts* (ex-visibilité), *Mots de passe et fuites*, *Traces à chercher ailleurs* (ex-IOC et chasse), *Résumé de la collecte* (ex-SYNTHESE.txt).
  - Statuts lisibles : *Indice trouvé*, *À vérifier vous-même*, *À lire*, *Impossible à vérifier*, *Rien de suspect*, chacun expliqué en une ligne.
  - Chaque point vérifié dit ce qu'il cherche et ce qu'on en conclut (« Fichiers compressés créés pendant l'attaque », « Copier-coller vers le PC de l'attaquant »…), avec les nombres accordés (« 1 journal », « 3 journaux »).
  - Chronologie : titres en mots (« Connexion réussie de … (bureau à distance) », « Compte créé : … », « Journal Sécurité effacé ») ; le numéro d'événement Windows reste en fin de titre. Catégories : *Programmes lancés*, *Connexions ratées*, *Sites web*…
  - Réglage de Defender modifié : la fonction coupée est nommée (« surveillance réseau des programmes ») à côté de la clé.
- **Mémoire vive** : quand elle n'est pas lue, la page dit pourquoi en une phrase et donne les trois conditions pour la lire (copie en collecte complète, analyse sur un autre PC que le poste examiné, « Analyse complète » et « Utiliser Internet » cochées). Le détail technique est replié. Les anciens messages (« Image RAM présente mais non lue… ») sont redits en clair.
- **Appli** : options d'analyse reformulées (« Analyse complète : lit aussi l'index du disque ($MFT) et la mémoire vive »).
- **Poste sain : rapports adaptés**. Si l'examen ne trouve ni intrusion, ni envoi de données, ni chiffrement, ni outil de pirate :
  - le rapport s'appelle « Examen de sécurité » (et non « Incident ») ;
  - le **rapport client** (ex-rapport praticien) dit ce qui a été trouvé, ses limites et quoi faire, sans « données potentiellement concernées », ni plainte, ni « ne pas rallumer » ;
  - bloc CNIL : « aucune violation de données constatée sur ce poste, rien à notifier sur cette base » ;
  - Résumé : une seule action, « Rien d'urgent sur ce poste », au lieu de CNIL, assureur et chasse sur le parc.
- **Rapport technique** : conclusion en tête ; adresses IP limitées à celles qui comptent (connexion réussie ou ratée, liste malveillante, connexion suspecte), les connexions habituelles de programmes signés sont seulement comptées ; plus de tableaux vides ; « Angles morts » distingue les sources désactivées et les sources absentes.
- **Fichiers de DigSpill lui-même** (kit, copie du dépôt dans Téléchargements) retirés des empreintes suspectes et des processus non signés.
- **« Fichier ouvert - Avertissement de sécurité » à chaque lancement de Velociraptor** : un kit extrait d'un zip téléchargé garde la « marque du Web ». DigSpill la retire de ses propres fichiers au démarrage, et l'analyse pour ses outils.
- **Defender bloquait `Analyse-Exfil.ps1`** (`Trojan:PowerShell/PSAttackTool.A`) : les noms d'outils d'attaque que l'analyse cherche (Mimikatz et ses commandes, outils de vol de mots de passe, outils d'envoi) sont sortis du script vers `moteur\indicateurs.json`. L'analyse s'arrête avec un message clair si ce fichier manque.
- **Analyse, étape IOC** : erreur « op_Subtraction » quand Defender avait des détections ; la quarantaine Defender n'était pas reprise. Même cause corrigée dans l'étape Mimikatz.

## 2.9.1 (bêta)
- **Mise à jour depuis l'appli** : accueil › *Mises à jour*. Dernière release GitHub, empreinte SHA256 vérifiée, remplacement après fermeture avec retour à l'ancienne version si une étape échoue ; `digspill.ini` et les bases téléchargées sont gardés. Jamais de connexion au démarrage (poste examiné). La version du kit (`moteur\VERSION.txt`) s'affiche dans la barre latérale.
- **Releases automatiques** : chaque nouvelle version de ce journal fusionnée dans main est publiée avec `DigSpill.zip`.
- **Analyse** : un conteneur Velociraptor de plus de 4 Go est lu (NTFS, exFAT). Avant, il était ignoré sans le dire : SRUM, Prefetch, Amcache et `$MFT` jamais analysés sur une collecte complète d'un gros poste (13,6 Go sur le poste d'essai). Seul un conteneur coupé par FAT32 (exactement 4 Gio − 1 octet) est écarté.
- **Analyse en échec** : l'appli affiche la fin du journal du script, et dit si l'antivirus a bloqué le script d'analyse.
- **Kit** : plus de double fabrication en échec quand une release est créée sur le site ; le test complet tourne sur chaque demande de fusion.

## 2.9 (bêta)
- **Support PREUVES au choix** : clé USB, **disque dur ou SSD externe** (USB, y compris USB 3 « UASP » qui se déclare SCSI à Windows et n'était pas reconnu, FireWire, carte SD), ou, à défaut, **un disque de ce poste** (celui de Windows compris). Le bus et le modèle du disque sont affichés.
- **Disque du poste** : choix jamais automatique, avertissement avant de lancer (l'écriture peut effacer des fichiers supprimés récupérables, un rançongiciel actif peut chiffrer les preuves), ni fichiers pièges, ni coupure, ni éjection. Le disque reste examiné : seul le dossier `Collecte\` est sauté (`-DestinationSurLePoste`, automatique sur le disque de Windows). Noté dans `infos_collecte.txt`. Fin de collecte : « Copier la collecte hors du poste ».
- **DigSpill lancé depuis le disque de Windows** (dossier Téléchargements, par exemple) : le disque `C:` n'est plus retiré des recherches ; seul le dossier de DigSpill est sauté.
- **Releases** : une release publiée depuis GitHub reçoit `DigSpill.zip` automatiquement.
- **Icône de DigSpill.exe** refaite au format attendu par Windows (images bitmap de 16 à 128 px, PNG seulement en 256 px) ; le kit vérifie l'icône telle que l'explorateur l'affiche.
- **Fausses alertes sur un poste sain (essai réel) corrigées** :
  - « 260 fichiers chiffrés » : icônes `icone@2x.png` (OneDrive, Steam), torrent `Film.[Groupe Release].torrent`, fichier `adresse@exemple.fr_identity_provider`. Un nom chiffré doit maintenant garder l'extension d'origine suivie de l'ajout du rançongiciel (identifiant avec un chiffre, adresse e-mail, extension connue), et il faut au moins 20 fichiers de la même extension modifiés en 24 h. Même règle dans la collecte, l'analyse et l'interface.
  - « Isoler le poste » : Defender (`MsMpEng.exe`, dont Windows cache le chemin) parlait au cloud Microsoft, Battle.net (signé) tournait depuis `ProgramData`. Le chemin des processus protégés est lu ; un programme signé dans un dossier à risque n'est suspect que s'il s'agit d'un outil d'accès ou de transfert.
  - Note de rançon : `help.html` de tailles différentes dans 26 dossiers (aide de logiciels) n'en est plus une, dans la synthèse de collecte comme dans l'interface.
  - Defender 5007 : seuls les changements qui l'affaiblissent comptent (exclusion, protection coupée), pas ses changements internes ; la clé modifiée est nommée ; alertes anti-forensique regroupées (avant : trois fois la même ligne).
- **Appli** :
  - « Fichiers pièges » devient « fichiers-appâts », expliqués sous la case.
  - Mise en veille et extinction de l'écran bloquées pendant une collecte ou une analyse.
  - Scellé : chaque étape est affichée (ouverture, Go hachés, terminé, écriture, horodatage avec les secondes) ; l'horodateur a 45 s pour répondre.
  - Copie vérifiée : avancement en Go pendant le re-hachage des gros fichiers (image RAM, conteneur Velociraptor) et barre animée tant que le travail continue.
  - Analyse arrêtée ou en échec : bouton et étape 1 « Collecte à analyser » pour revenir, sans quitter DigSpill.
  - Dossier de travail par défaut : `%USERPROFILE%\DigSpill` (et non `Documents`, protégé par l'« Accès contrôlé aux dossiers » de Defender qui bloquait PowerShell, 7-Zip et Python) ; avertissement si le dossier choisi est protégé.
  - « Ouvrir le rapport » : le rapport s'ouvre dans sa propre fenêtre, sans onglets ni barre d'adresse (Edge en mode application) ; « Dans le navigateur » reste possible.

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
