"""Equivalent Python de Generer-Interface.ps1, pour le developpement et les tests (pas utile en intervention).

  python -I interface/dev/assembler.py --collecte <dossier POSTE_date> --bases <dossier bases> --sortie fichier.html [--demo] [--mot-de-passe X]

Produit exactement la meme charge utile que le script PowerShell : fichiers CSV/TXT bruts,
lignes des bases IP correspondant aux IP de la collecte, correspondances avec les listes,
JSON bruts (victimes, memoire, reglages).
"""
from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
import hmac
import ipaddress
import json
import os
import re
from datetime import datetime
from pathlib import Path

INTERFACE = Path(__file__).resolve().parent.parent
JS = sorted(p.name for p in (Path(__file__).resolve().parent.parent / "js").glob("*.js"))
IGNORER = {"evtx", "utilisateurs", "registre", "prefetch", "srum", "amcache", "defender_logs", "defender_quarantaine", "binaires_neutralises",
           "memoire", "navigateurs", "parefeu_journal", "lnk", "jumplists", "usn", "_extraits", "tasks_xml"}
MAX_OCTETS = 12 * 1024 * 1024
LISTES = {"tor": "Noeuds de sortie Tor", "firehol1": "FireHOL niveau 1", "blocklistde": "blocklist.de", "greensnow": "GreenSnow", "cins": "CINS Army",
          "feodo": "abuse.ch Feodo", "spamhaus_drop": "Spamhaus DROP"}


def lire_texte(p: Path, limite=MAX_OCTETS):
    b = p.read_bytes()
    tronque = len(b) > limite
    if tronque:
        b = b[:limite]
        b = b[: b.rfind(b"\n") + 1]
    for enc in ("utf-8-sig", "cp1252"):
        try:
            return b.decode(enc), tronque
        except UnicodeDecodeError:
            pass
    return b.decode("utf-8", "replace"), tronque


def fichiers(collecte: Path):
    out = {}
    analyse = collecte.parent / (collecte.name + "_analyse")
    for racine, prefixe in ((collecte, ""), (analyse, "a.")):
        if not racine.is_dir():
            continue
        for p in sorted(racine.iterdir(), key=lambda x: x.name.lower()):
            liste = [p] if p.is_file() else (sorted(p.iterdir(), key=lambda x: x.name.lower()) if p.is_dir() and p.name.lower() not in IGNORER else [])
            for f in liste:
                journal = f.suffix.lower() == ".log" and f.parent == racine
                if not f.is_file() or (f.suffix.lower() not in (".csv", ".txt") and not journal) or f.name.lower().startswith("listing_complet"):
                    continue
                cle = f.stem if f.suffix.lower() == ".csv" else f.name
                if cle in out:
                    cle = prefixe + cle if prefixe else cle
                if cle in out:
                    continue
                texte, tronque = lire_texte(f)
                out[cle] = {"chemin": str(f.relative_to(collecte.parent)).replace("/", "\\"), "taille": f.stat().st_size, "tronque": tronque,
                            "modifie": datetime.fromtimestamp(f.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S"), "texte": texte}
    return out, analyse.is_dir()


def ips_collecte(fich) -> list[str]:
    import csv
    import io
    vus = set()
    for cle, cols in (("synthese_ip_connexions_reussies", ["IP"]), ("echecs_par_ip", ["IP"]), ("echecs_connexion_4625", ["IP"]), ("sessions_reconstituees", ["IP"]),
                      ("tcp_connexions", ["RemoteAddress"]), ("ouvertures_session_4624", ["IP"]), ("rdp_authentifications_1149", ["IP"])):
        f = fich.get(cle)
        if not f or not f["texte"].startswith('"'):
            continue
        for r in csv.DictReader(io.StringIO(f["texte"])):
            for c in cols:
                for ip in re.split(r"\s*/\s*", r.get(c) or ""):
                    ip = ip.strip()
                    if ip and ip != "-":
                        vus.add(ip)
    return sorted(vus)


def _int(ip):
    try:
        a = ipaddress.ip_address(ip)
        return a.version, int(a)
    except ValueError:
        return None, None


def plages(chemin: Path, ips, sep):
    cibles = [(v, n, ip) for ip in ips for v, n in [_int(ip)] if v]
    res = []
    if not chemin.is_file() or not cibles:
        return res
    ouvrir = gzip.open if chemin.suffix == ".gz" else open
    with ouvrir(chemin, "rt", encoding="utf-8", errors="replace") as f:
        for l in f:
            l = l.rstrip("\r\n")
            p = l.split(sep, 2)
            if len(p) < 3:
                continue
            v1, a = _int(p[0])
            v2, b = _int(p[1])
            if not v1 or v1 != v2:
                continue
            for v, n, ip in cibles:
                if v == v1 and a <= n <= b:
                    res.append(ip + "\t" + l)
    return res


def listes(bases: Path, ips):
    out, meta = {}, []
    for lid, nom in LISTES.items():
        p = bases / f"ip_{lid}.txt"
        if not p.is_file():
            continue
        meta.append({"id": lid, "nom": nom, "date": datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%d")})
        reseaux = []
        for l in p.read_text(encoding="utf-8", errors="replace").splitlines():
            l = l.strip()
            if not l or l[0] in "#;":
                continue
            m = re.search(r"(?<![\d.])(\d{1,3}(?:\.\d{1,3}){3}(?:/\d{1,2})?)(?![\d.])", l)
            if m:
                try:
                    reseaux.append(ipaddress.ip_network(m.group(1), strict=False))
                except ValueError:
                    pass
        trouves = []
        for ip in ips:
            try:
                a = ipaddress.ip_address(ip)
            except ValueError:
                continue
            if a.version == 4 and any(a in n for n in reseaux):
                trouves.append(ip)
        if trouves:
            out[lid] = trouves
    return out, meta


def entete(html):
    """<!--ICONE--> : favicon SVG en data URI ; <!--POLICES--> : polices.css avec chaque url(x.woff2) en data URI."""
    import base64, re as _re
    ico = base64.b64encode((INTERFACE / "assets" / "favicon.svg").read_bytes()).decode("ascii")
    html = html.replace("<!--ICONE-->", '<link rel="icon" type="image/svg+xml" href="data:image/svg+xml;base64,' + ico + '">', 1)
    dossier = INTERFACE / "vendor" / "polices"
    css = (dossier / "polices.css").read_text(encoding="utf-8")
    css = _re.sub(r"url\(([A-Za-z0-9._-]+\.woff2)\)", lambda m: "url(data:font/woff2;base64," + base64.b64encode((dossier / m.group(1)).read_bytes()).decode("ascii") + ")", css)
    return html.replace("<!--POLICES-->", "<style>\n" + css + "</style>", 1)


def charge_utile(collecte: Path, bases: Path, demo=False, tsa: Path | None = None):
    fich, analyse = fichiers(collecte)
    ips = ips_collecte(fich)
    asn = bases / "ip2asn-combined.tsv.gz"
    l, meta = listes(bases, ips)
    # octets tels quels (fins de ligne comprises), comme Generer-Interface.ps1 : read_text changerait \r\n en \n
    lire = lambda p: p.read_bytes().decode("utf-8-sig", errors="replace") if p.is_file() else ""
    date = lambda p: datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%d")
    return {
        "format": 1, "genere_le": datetime.now().strftime("%Y-%m-%d %H:%M"), "generateur": "assembler.py (developpement)" if not demo else "Generer-Interface (demonstration)",
        "demo": demo, "collecte": {"nom": collecte.name, "analyse": analyse}, "fichiers": fich,
        "geo_asn": plages(asn, ips, "\t"), "listes": l,
        "bases": {"asn": {"source": "IPtoASN", "date": date(asn)} if asn.is_file() else None,
                  "listes": meta, "ransomware": {"date": date(bases / "ransomware_live_FR.json")} if (bases / "ransomware_live_FR.json").is_file() else None},
        "ransomware_brut": lire(bases / "ransomware_live_FR.json"), "ransomware_recent_brut": lire(bases / "ransomware_live_recent.json"),
        "memoire_brut": lire(bases / "memoire_incidents.json"), "reglages_brut": lire(collecte.parent / (collecte.name + "_reglages.json")),
        "scelles": sceller(collecte, tsa),
    }


# ==================================================================== scelle (meme format que le .ps1)
def _der(tag: int, contenu: bytes) -> bytes:
    n = len(contenu)
    l = bytes([n]) if n < 128 else bytes([0x81, n]) if n < 256 else bytes([0x82, n >> 8, n & 255])
    return bytes([tag]) + l + contenu


def requete_tsa(empreinte: bytes, nonce: bytes) -> bytes:
    algo = _der(0x30, bytes([0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00]))
    imprint = _der(0x30, algo + _der(0x04, empreinte))
    return _der(0x30, bytes([0x02, 0x01, 0x01]) + imprint + _der(0x02, nonce) + bytes([0x01, 0x01, 0xFF]))


def sceller(collecte: Path, tsa_openssl: Path | None = None, date_fixe: str | None = None):
    """Cree le scelle si les fichiers scelles ont change ; horodatage par une AUTORITE DE DEMONSTRATION (openssl) en dev."""
    import subprocess
    collecte = collecte.resolve()
    tsa_openssl = tsa_openssl.resolve() if tsa_openssl else None
    parent, nom = collecte.parent, collecte.name
    analyse = parent / (nom + "_analyse")
    dossier = parent / (nom + "_scelles")
    dossier.mkdir(exist_ok=True)
    cand = [collecte / "manifeste_sha256.csv", collecte / "collecte.log", analyse / "manifeste_analyse_sha256.csv", analyse / "analyse.log"]
    cand += sorted(collecte.glob("PV_COPIE_*.txt"))
    lignes = []
    for p in cand:
        if p.is_file():
            lignes.append(f"{hashlib.sha256(p.read_bytes()).hexdigest().upper()}  {p.stat().st_size}  {str(p.relative_to(parent)).replace('/', chr(92))}")
    lignes.sort(key=lambda l: l.split("  ", 2)[2])
    existants = sorted(x for x in dossier.glob("SCELLE_*.txt") if not x.name.endswith(".horodatage.txt"))
    actuel = None
    if existants:
        anc = [l for l in existants[-1].read_text(encoding="utf-8").splitlines() if re.match(r"^[0-9A-F]{64}  \d+  ", l)]
        if anc == lignes:
            actuel = existants[-1]
    if actuel is None and lignes:
        d = datetime.strptime(date_fixe, "%Y-%m-%d %H:%M:%S") if date_fixe else datetime.now()
        contenu = ["DIGSPILL - SCELLE DES PREUVES (v1)", "=" * 50, f"Collecte   : {nom}", f"Cree le    : {d.strftime('%Y-%m-%d %H:%M:%S')} +01:00 (horloge de PC-ANALYSE-DEMO)",
                   "Par        : MSP-DEMO\\technicien", "Outil      : Generer-Interface.ps1 v1.1", "", "Empreintes SHA256, tailles (octets) et chemins des fichiers scelles :"] + lignes + [
                   "", "Verification : Get-FileHash -Algorithm SHA256 <fichier> doit redonner chaque empreinte ci-dessus.",
                   "L'empreinte SHA256 de CE fichier est celle qui est horodatee dans le jeton .tsr du meme nom.",
                   "Chaque manifeste liste a son tour l'empreinte de tous les fichiers de la collecte ou de l'analyse."]
        actuel = dossier / f"SCELLE_{d.strftime('%Y%m%d_%H%M%S')}.txt"
        actuel.write_bytes(("\r\n".join(contenu) + "\r\n").encode("utf-8"))
    if actuel and tsa_openssl and not actuel.with_suffix(".tsr").exists():
        emp = hashlib.sha256(actuel.read_bytes()).digest()
        tsq = requete_tsa(emp, bytes([0x5A]) + os.urandom(7))
        actuel.with_suffix(".tsq").write_bytes(tsq)
        subprocess.run(["openssl", "ts", "-reply", "-config", str(tsa_openssl / "tsa.cnf"), "-queryfile", str(actuel.with_suffix(".tsq")),
                        "-out", str(actuel.with_suffix(".tsr"))], check=True, capture_output=True, cwd=tsa_openssl)
        txt = subprocess.run(["openssl", "ts", "-reply", "-in", str(actuel.with_suffix(".tsr")), "-text"], capture_output=True, text=True).stdout
        m = re.search(r"Time stamp: (.+)", txt)
        g = datetime.strptime(m.group(1).strip().replace(" GMT", ""), "%b %d %H:%M:%S %Y") if m else None
        (dossier / (actuel.stem + ".horodatage.txt")).write_text(
            f"Horodateur : AUTORITE DE DEMONSTRATION (fictive, non qualifiee)\r\nDate du jeton : {g.strftime('%Y-%m-%d %H:%M:%S') + ' UTC' if g else ''}\r\n"
            f"Empreinte horodatee : {emp.hex().upper()}\r\n", encoding="utf-8")
    out = []
    for sc in sorted(x for x in dossier.glob("SCELLE_*.txt") if not x.name.endswith(".horodatage.txt")):
        tsr, inf = sc.with_suffix(".tsr"), dossier / (sc.stem + ".horodatage.txt")
        out.append({"nom": sc.stem, "chemin": str(sc.relative_to(parent)).replace("/", "\\"), "sha256": hashlib.sha256(sc.read_bytes()).hexdigest().upper(),
                    "texte": sc.read_text(encoding="utf-8"), "tsr": base64.b64encode(tsr.read_bytes()).decode() if tsr.exists() else None,
                    "horodatage": inf.read_text(encoding="utf-8") if inf.exists() else None, "actuel": sc == actuel})
    return out


def chiffrer(texte: str, mot_de_passe: str) -> dict:
    """PBKDF2-SHA256 (200 000 iterations) -> 64 octets : AES-256-CBC (32) + HMAC-SHA256 (32). Meme format que le .ps1."""
    from cryptography.hazmat.primitives import padding
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    sel, iv, it = os.urandom(16), os.urandom(16), 200_000
    cles = hashlib.pbkdf2_hmac("sha256", mot_de_passe.encode(), sel, it, 64)
    pad = padding.PKCS7(128).padder()
    clair = pad.update(texte.encode()) + pad.finalize()
    e = Cipher(algorithms.AES(cles[:32]), modes.CBC(iv)).encryptor()
    chiffre = e.update(clair) + e.finalize()
    mac = hmac.new(cles[32:], iv + chiffre, hashlib.sha256).digest()
    b = lambda x: base64.b64encode(x).decode()
    return {"chiffre": True, "iterations": it, "sel": b(sel), "iv": b(iv), "donnees": b(chiffre), "mac": b(mac)}


def assembler(charge: dict, sortie: Path, mot_de_passe: str | None = None):
    lire = lambda p: (INTERFACE / p).read_text(encoding="utf-8")
    donnees = json.dumps(charge, ensure_ascii=False, separators=(",", ":"))
    if mot_de_passe:
        enveloppe = chiffrer(donnees, mot_de_passe)
        enveloppe.update({"collecte": charge["collecte"]["nom"], "genere_le": charge["genere_le"]})
        donnees = json.dumps(enveloppe)
    donnees = donnees.replace("<", "\\u003c")
    app = "\n".join(lire("js/" + j) for j in JS).replace("</script", "<\\/script")
    html = entete(lire("modele.html"))
    html = html.replace("<!--STYLE-->", "<style>\n" + lire("style.css") + "\n</style>", 1)
    html = html.replace("<!--MONDE-->", '<script type="application/json" id="monde">' + lire("vendor/monde.json") + "</script>", 1)
    html = html.replace("<!--DONNEES-->", '<script type="application/json" id="donnees">' + donnees + "</script>", 1)
    vendor = "\n;\n".join(p.read_text(encoding="utf-8") for p in sorted((INTERFACE / "vendor").glob("*.js")))
    html = html.replace("<!--ECHARTS-->", "<script>\n" + vendor.replace("</script", "<\\/script") + "\n</script>", 1)
    html = html.replace("<!--APP-->", "<script>\n" + app + "\n</script>", 1)
    sortie.write_text(html, encoding="utf-8")
    return sortie


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--collecte", required=True)
    ap.add_argument("--bases", default="")
    ap.add_argument("--sortie", required=True)
    ap.add_argument("--demo", action="store_true")
    ap.add_argument("--mot-de-passe", default="")
    ap.add_argument("--vide", action="store_true", help="modele sans donnees (ecran d'ouverture)")
    ap.add_argument("--tsa-demo", default="", help="dossier d'une autorite d'horodatage de DEMONSTRATION (openssl), voir tsa_demo.sh")
    a = ap.parse_args()
    if a.vide:
        charge = None
        lire = lambda p: (INTERFACE / p).read_text(encoding="utf-8")
        html = entete(lire("modele.html")).replace("<!--STYLE-->", "<style>\n" + lire("style.css") + "\n</style>").replace("<!--MONDE-->", '<script type="application/json" id="monde">' + lire("vendor/monde.json") + "</script>")
        vendor = "\n;\n".join(p.read_text(encoding="utf-8") for p in sorted((INTERFACE / "vendor").glob("*.js")))
        html = html.replace("<!--DONNEES-->", '<script type="application/json" id="donnees"></script>').replace("<!--ECHARTS-->", "<script>\n" + vendor + "\n</script>")
        html = html.replace("<!--APP-->", "<script>\n" + "\n".join(lire("js/" + j) for j in JS) + "\n</script>")
        Path(a.sortie).write_text(html, encoding="utf-8")
    else:
        charge = charge_utile(Path(a.collecte), Path(a.bases) if a.bases else Path("/nonexistent"), a.demo, Path(a.tsa_demo) if a.tsa_demo else None)
        assembler(charge, Path(a.sortie), a.mot_de_passe or None)
    print(a.sortie, round(Path(a.sortie).stat().st_size / 1024), "Ko")
