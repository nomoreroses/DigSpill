# Journal des versions

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
