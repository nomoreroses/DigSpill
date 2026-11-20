# Signer DigSpill.exe

Sans signature, Windows affiche **« Éditeur : Inconnu »** quand on lance l'appli en administrateur.
Avec une signature d'un certificat reconnu par Windows, il affiche **le nom de l'éditeur** (ex. Sémaphors).

> ⚠️ Le code ne peut pas régler ça tout seul : il faut **un certificat de signature de code** à votre nom.

## 🧭 Les options

| Option | Pour qui | À savoir |
|---|---|---|
| ☁️ **Azure Artifact Signing** (ex-Trusted Signing) | Une **société** de l'UE | Pas ouvert aux particuliers en France. Abonnement mensuel. Signature depuis GitHub Actions ou `signtool`. |
| 🔑 **Certificat OV** (Certum, Sectigo, GlobalSign…) | Société ou entrepreneur | Clé privée **sur jeton USB ou HSM** obligatoire. Validité de 460 jours au plus depuis mars 2026. |
| 🏠 **Certificat interne** poussé par Datto RMM | Parc géré seulement | Gratuit. Nom affiché seulement sur les PC qui ont reçu le certificat. Ailleurs : « Inconnu ». |

## 🛡️ Et SmartScreen ?

- Un fichier signé **téléchargé** peut encore afficher « Windows a protégé votre ordinateur » le temps que sa réputation se construise. Même avec un certificat EV.
- DigSpill.exe est lancé **depuis la clé OUTILS**, pas téléchargé. Sur une clé en FAT32 ou exFAT, Windows ne peut pas poser la marque « venu d'Internet » (flux NTFS) : SmartScreen ne devrait pas intervenir. *À vérifier sur un premier poste.*
- Chaque nouvelle version du `.exe` doit être **signée à nouveau** : la signature couvre le fichier exact.

## 🛠️ Procédure

1. `app\CONSTRUIRE.bat` → construit `DigSpill.exe` (compilateur C# déjà présent dans Windows, rien à installer).
2. Brancher le jeton du certificat (ou configurer le service de signature).
3. `app\SIGNER.bat` → signe avec le meilleur certificat trouvé.
   `app\SIGNER.bat "Sémaphors"` → impose le certificat dont le nom contient « Sémaphors ».
4. Vérifier : clic droit sur `DigSpill.exe` → Propriétés → **Signatures numériques**.
5. Copier `DigSpill.exe` à la racine de la clé OUTILS, **puis** la passer en lecture seule.

`SIGNER.bat` demande `signtool.exe` (Windows SDK, composant « Signing Tools »). La signature est contre-signée par l'horodateur Sectigo : elle reste valable après l'expiration du certificat.

## 🤖 Construction automatique

Le workflow GitHub `Appli DigSpill.exe` construit un `DigSpill.exe` **non signé** à chaque modification de `app/`, le lance en mode démonstration et publie l'exécutable et une capture d'écran. La signature reste à faire avec `SIGNER.bat` sur votre poste, ou en ajoutant une étape de signature au workflow une fois le certificat choisi.
