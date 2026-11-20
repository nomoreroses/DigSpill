# Clés USB et rançongiciel

Le risque : brancher une clé sur un poste où un rançongiciel tourne encore. Il peut chiffrer **les outils** et **les preuves**.

## 🔌 Deux clés

| Clé | Contenu | Protection |
|---|---|---|
| 🧰 **OUTILS** | `DigSpill.exe` et `moteur\` (scripts, interface, outils, `digspill.ini`) | **Interrupteur matériel en lecture seule**. Rien ne peut l'écrire, même un administrateur. |
| 🗄️ **PREUVES** | `Collecte\` | **Chiffrée** (code PIN), branchée **après** le feu vert, **surveillée** pendant la collecte, passée **en lecture seule** ensuite. |

Exemples de matériel (à comparer, prix variables) :
- 🧰 OUTILS : clé à interrupteur physique, ex. **Kanguru FlashTrust**.
- 🗄️ PREUVES : clé chiffrée à clavier avec mode lecture seule, ex. **iStorage datAshur PRO²**. Le mode lecture seule peut être imposé par l'administrateur de la clé.

## 🧰 Préparer la clé OUTILS (au bureau)

1. Dézipper `DigSpill.zip` (Releases du dépôt, déjà débloqué) à la racine : `DigSpill.exe` + `moteur\`.
2. Optionnel : signer `DigSpill.exe` ([SIGNATURE.md](SIGNATURE.md)).
3. Lancer DigSpill.exe une fois, interrupteur en écriture : le technicien saisi est retenu dans `moteur\digspill.ini`. Les bases publiques se téléchargent à la première analyse au bureau.
4. **Basculer l'interrupteur en lecture seule.** DigSpill le vérifie au feu vert.

## 🛡️ Ce que fait DigSpill.exe

| Étape | Protection |
|---|---|
| 🚦 **Feu vert** (avant de brancher PREUVES) | Cherche, sans rien écrire sur le poste : notes de rançon, fichiers renommés en masse, extensions inconnues récentes, programme qui écrit beaucoup depuis AppData / Temp / ProgramData, antivirus coupé, réseau actif. |
| 🪤 **Fichiers pièges** | 4 faux documents posés sur la clé PREUVES (« Dossiers patients », « Ordonnances »…). Vérifiés toutes les 2 secondes, empreinte comprise. |
| 👀 **Surveillance** | Coupure aussi si des fichiers de la clé reçoivent une extension en plus (`rapport.csv` → `rapport.csv.lock`) ou si une note de rançon y apparaît. |
| ✂️ **Coupure immédiate** | Arrêt de la collecte, disque passé **en lecture seule**, volume **démonté**, lettre **retirée** : les programmes ne voient plus la clé. Écran rouge : « Retirez la clé ». |
| 🔏 **Scellé sur place** | Empreinte SHA-256 du manifeste, du journal et des conteneurs, affichée en grand : **photographiez-la**. Horodatée si Internet, sinon au bureau. |
| ⏏️ **Éjection propre** | Vidage des caches, démontage, éjection. Les pièges sont retirés (sauf après une alerte : ce sont des preuves). |

## ⚠️ Limites (à dire honnêtement)

- Les pièges détectent un chiffrement **quand il atteint la clé**. Quelques fichiers peuvent être touchés avant la coupure.
- Un rançongiciel très ciblé pourrait éviter les pièges. La vraie protection des outils reste **l'interrupteur matériel**.
- Le feu vert réduit le risque, il ne le supprime pas. En cas de **danger**, ne pas brancher la clé PREUVES : isoler le poste sans l'éteindre et prévenir.
- Toutes ces fonctions sont **à valider sur un vrai poste Windows** avant usage en intervention (elles n'ont été testées qu'en mode démonstration).
