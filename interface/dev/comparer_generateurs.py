"""Compare les fichiers HTML produits par assembler.py (Python) et Generer-Interface.ps1 (PowerShell).

Seules les donnees de la collecte (<script id="donnees">) different d'un generateur a l'autre
(date de generation, nom du generateur) : on les retire, tout le reste doit etre identique
(style, polices, favicon, carte, ECharts, code de l'interface).
Usage : python comparer_generateurs.py python.html powershell.html
"""
import re
import sys
from pathlib import Path

RX_DONNEES = re.compile(r'<script type="application/json" id="donnees">.*?</script>', re.S)


def lire(p):
    t = Path(p).read_bytes().decode("utf-8-sig").replace("\r\n", "\n")
    return RX_DONNEES.sub('<script type="application/json" id="donnees"></script>', t, count=1)


a, b = lire(sys.argv[1]), lire(sys.argv[2])
if a == b:
    print(f"Identiques hors donnees ({len(a)} caracteres).")
    sys.exit(0)
i = next((k for k, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
print(f"DIFFERENTS a partir du caractere {i} (longueurs {len(a)} / {len(b)})")
print("python     :", repr(a[max(0, i - 120):i + 120]))
print("powershell :", repr(b[max(0, i - 120):i + 120]))
sys.exit(1)
