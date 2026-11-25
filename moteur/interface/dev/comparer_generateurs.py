"""Compare les fichiers HTML produits par assembler.py (Python) et Generer-Interface.ps1 (PowerShell).

1. La page (style, polices, favicon, carte, ECharts, code de l'interface) doit etre identique octet pour octet.
2. Les donnees de la collecte (<script id="donnees">) aussi, sauf ce qui depend du generateur ou de l'heure :
   date de generation, nom du generateur, scelles (crees a la volee), date de modification des fichiers.
   Les listes sont comparees sans tenir compte de l'ordre (ordre de lecture des IP different en Python et en PowerShell).
Les deux generateurs choisissent seuls les fichiers a reprendre, les coupent et cherchent les IP : sans le point 2,
un ecart dans cette logique passerait inapercu.
Usage : python comparer_generateurs.py python.html powershell.html
"""
import json
import re
import sys
from pathlib import Path

RX_DONNEES = re.compile(r'<script type="application/json" id="donnees">(.*?)</script>', re.S)
VOLATILES = {"genere_le", "generateur", "scelles"}


def lire(p):
    t = Path(p).read_bytes().decode("utf-8-sig").replace("\r\n", "\n")
    m = RX_DONNEES.search(t)
    donnees = json.loads(m.group(1).replace("<\\/", "</")) if m else None
    return RX_DONNEES.sub('<script type="application/json" id="donnees"></script>', t, count=1), donnees


def normaliser(x, chemin=""):
    if isinstance(x, dict):
        return {k: normaliser(v, f"{chemin}.{k}") for k, v in x.items() if not (chemin == "" and k in VOLATILES) and not (chemin.startswith(".fichiers.") and k == "modifie")}
    if isinstance(x, list):
        return sorted((normaliser(v, chemin + "[]") for v in x), key=lambda v: json.dumps(v, sort_keys=True, ensure_ascii=False))
    return x


def ecarts(a, b, chemin="donnees", out=None):
    out = [] if out is None else out
    if len(out) >= 15:
        return out
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b:
                out.append(f"{chemin}.{k} : present seulement dans {'python' if k in a else 'powershell'}")
            else:
                ecarts(a[k], b[k], f"{chemin}.{k}", out)
    elif a != b:
        out.append(f"{chemin} : python={json.dumps(a, ensure_ascii=False)[:150]} | powershell={json.dumps(b, ensure_ascii=False)[:150]}")
    return out


(pa, da), (pb, db) = lire(sys.argv[1]), lire(sys.argv[2])
code = 0
if pa == pb:
    print(f"Page identique ({len(pa)} caracteres).")
else:
    i = next((k for k, (x, y) in enumerate(zip(pa, pb)) if x != y), min(len(pa), len(pb)))
    print(f"PAGE DIFFERENTE a partir du caractere {i} (longueurs {len(pa)} / {len(pb)})")
    print("python     :", repr(pa[max(0, i - 120):i + 120]))
    print("powershell :", repr(pb[max(0, i - 120):i + 120]))
    code = 1
e = ecarts(normaliser(da), normaliser(db))
if e:
    print(f"DONNEES DIFFERENTES ({len(e)} ecart(s) affiches) :")
    for x in e:
        print("  " + x)
    code = 1
else:
    print(f"Donnees identiques hors date, generateur et scelles ({len(da.get('fichiers', {}))} fichiers).")
sys.exit(code)
