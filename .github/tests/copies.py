"""Garde-fous : regles recopiees a la main entre la collecte, l'analyse et l'interface.

Chaque script doit tourner seul depuis la cle, d'ou ces copies. Ce test echoue si elles divergent :
  1. motif des noms de fichiers chiffres par un rancongiciel : Collecte-Exfil.ps1, Analyse-Exfil.ps1, 02_analyse.js
  2. fonction Get-IpType (privee, VPN/CGNAT, publique) : Collecte-Exfil.ps1 et Analyse-Exfil.ps1
  3. Get-Evtx rend sa liste en un seul objet (return ,@(...)) : la passer directement a un pipeline
     donne toute la liste a chaque $_ (erreur op_Subtraction de la 2.9.1). Ecrire (Get-Evtx ...) | ...
  4. motif d'extension a l'aspect aleatoire (.Fa2a2yMH) : Collecte-Exfil.ps1, Analyse-Exfil.ps1, 02_analyse.js
Usage : python -I .github/tests/copies.py   (depuis la racine du depot)
"""
import re
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parents[2]
lire = lambda p: (RACINE / p).read_bytes().decode("utf-8-sig").replace("\r\n", "\n")
collecte, analyse, js = lire("moteur/Collecte-Exfil.ps1"), lire("moteur/Analyse-Exfil.ps1"), lire("moteur/interface/js/02_analyse.js")
erreurs = []


def un(motif, texte, ou):
    m = re.search(motif, texte, re.M)
    if not m:
        erreurs.append(f"{ou} : introuvable ({motif[:40]}...)")
        return None
    return m.group(1)


# 1. motif rancongiciel (en JS, les groupes sont non capturants : meme correspondance)
rx = [un(r"RxRanconNom = New-Object Text\.RegularExpressions\.Regex\('\(\?i\)\((.*)\)', 'Compiled", analyse, "Analyse-Exfil.ps1"),
      un(r"\$ransomRx = New-Object Text\.RegularExpressions\.Regex\('\(\?i\)\((.*)\)'", collecte, "Collecte-Exfil.ps1"),
      un(r"^const RX_RANCON_NOM = /(.*)/i;$", js, "02_analyse.js")]
if all(rx):
    norm = [x.replace("(?:", "(") for x in rx]
    if len(set(norm)) != 1:
        erreurs.append("motif rancongiciel different entre Analyse-Exfil.ps1, Collecte-Exfil.ps1 et 02_analyse.js")

# 2. Get-IpType identique dans les deux scripts
fn = [un(r"(?s)^(function Get-IpType\(.*?\n\})", t, n) for t, n in ((collecte, "Collecte-Exfil.ps1"), (analyse, "Analyse-Exfil.ps1"))]
if all(fn) and fn[0] != fn[1]:
    erreurs.append("Get-IpType different entre Collecte-Exfil.ps1 et Analyse-Exfil.ps1")

# 3. Get-Evtx passe directement a un pipeline
for i, ligne in enumerate(analyse.split("\n"), 1):
    if re.search(r"Get-Evtx '[^']*' @\([^)]*\) \$Since(?: \"[^\"]*\")?\s*\|", ligne):
        erreurs.append(f"Analyse-Exfil.ps1:{i} : Get-Evtx passe directement a un pipeline, ecrire (Get-Evtx ...) | ...")

# 4. extension a l'aspect aleatoire
ea = [un(r"^\$script:RxExtAleatoire = '(.*)'$", analyse, "Analyse-Exfil.ps1"),
      un(r"^\$RxExtAleatoire = '(.*)'$", collecte, "Collecte-Exfil.ps1"),
      un(r"^const RX_EXT_ALEATOIRE = /(.*)/;$", js, "02_analyse.js")]
if all(ea) and len(set(ea)) != 1:
    erreurs.append("motif d'extension aleatoire different entre Analyse-Exfil.ps1, Collecte-Exfil.ps1 et 02_analyse.js")

for e in erreurs:
    print("::error::" + e)
print(f"{len(erreurs)} ecart(s) entre les copies")
sys.exit(1 if erreurs else 0)
