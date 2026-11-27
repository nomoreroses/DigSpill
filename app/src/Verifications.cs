// DigSpill - "feu vert" : signes d'un chiffrement en cours avant de brancher la cle PREUVES.
// Tout est en lecture : on ne cree ni ne modifie aucun fichier sur le poste examine.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace DigSpill
{
    class Constat
    {
        public Niveau Niveau;
        public string Titre, Detail;
        public Constat(Niveau n, string t, string d) { Niveau = n; Titre = t; Detail = d; }
    }

    static class Verifications
    {
        public static Niveau Global(IEnumerable<Constat> l)
        {
            if (l.Any(c => c.Niveau == Niveau.Danger)) return Niveau.Danger;
            if (l.Any(c => c.Niveau == Niveau.Attention)) return Niveau.Attention;
            return Niveau.Ok;
        }

        public static List<Constat> Tout(Contexte ctx, Action<string> etape)
        {
            if (ctx.Demo) return Demo(etape);
            var l = new List<Constat>();
            etape("Droits administrateur…"); l.Add(Admin());
            etape("Clé des outils…"); l.Add(CleOutils(ctx.RacineOutils));
            var dossiers = DossiersUtilisateurs();
            etape("Notes de rançon…"); l.Add(NotesRancon(dossiers));
            etape("Fichiers modifiés récemment…"); l.Add(ChiffrementRecent(dossiers));
            etape("Programmes qui écrivent sur le disque (3 s)…"); l.Add(Ecritures());
            etape("Antivirus…"); l.Add(Antivirus());
            etape("Réseau…"); l.Add(Reseau());
            etape("Supports déjà branchés…"); l.Add(SupportsBranches(ctx));
            return l;
        }

        static List<Constat> Demo(Action<string> etape)
        {
            foreach (var e in new[] { "Droits administrateur…", "Notes de rançon…", "Fichiers modifiés récemment…", "Programmes qui écrivent sur le disque (3 s)…" }) { etape(e); Thread.Sleep(350); }
            return new List<Constat> {
                new Constat(Niveau.Ok, "Droits administrateur", "DigSpill tourne en administrateur : la collecte sera complète."),
                new Constat(Niveau.Ok, "Clé OUTILS protégée en écriture", "Interrupteur en position lecture seule : un programme malveillant ne peut pas modifier les outils."),
                new Constat(Niveau.Ok, "Aucune note de rançon récente", "Bureau, Documents, Images et Téléchargements de 3 profils examinés."),
                new Constat(Niveau.Ok, "Pas de chiffrement massif en cours", "4 812 fichiers examinés : 37 modifiés depuis 2 h, aucune extension suspecte."),
                new Constat(Niveau.Ok, "Pas d'écriture anormale", "Aucun programme n'écrit massivement sur le disque en ce moment."),
                new Constat(Niveau.Ok, "Antivirus actif", "Microsoft Defender : protection en temps réel activée."),
                new Constat(Niveau.Attention, "Poste connecté au réseau", "Ethernet actif. Isolez le poste (câble, Wi-Fi) sans l'éteindre avant de brancher la clé PREUVES, sauf consigne contraire."),
                new Constat(Niveau.Ok, "Aucun autre support branché", "La clé PREUVES sera branchée à l'étape suivante.")
            };
        }

        static Constat Admin()
        {
            return Supports.EstAdmin()
                ? new Constat(Niveau.Ok, "Droits administrateur", "DigSpill tourne en administrateur : la collecte sera complète.")
                : new Constat(Niveau.Danger, "Pas de droits administrateur", "Relancez DigSpill et acceptez l'invite Windows : sans cela, la collecte est très incomplète.");
        }

        static Constat CleOutils(string racine)
        {
            string r = Path.GetPathRoot(racine);
            if (Supports.LectureSeule(r))
                return new Constat(Niveau.Ok, "Clé OUTILS protégée en écriture", "Le support " + r + " est en lecture seule : un programme malveillant ne peut pas modifier les outils.");
            return new Constat(Niveau.Attention, "Clé OUTILS non protégée en écriture", "Le support " + r + " n'est pas protégé. Idéal : une clé à interrupteur, en position lecture seule avant de la brancher.");
        }

        // ------------------------------------------------------------------ dossiers a examiner
        static List<string> DossiersUtilisateurs()
        {
            var l = new List<string>();
            try
            {
                string users = Path.Combine(Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)), "Users");
                foreach (var p in Directory.GetDirectories(users))
                {
                    string n = Path.GetFileName(p);
                    if (n == "Default" || n == "Default User" || n == "All Users" || n == "defaultuser0") continue;
                    foreach (var s in new[] { "Desktop", "Documents", "Pictures", "Downloads", "OneDrive" })
                    {
                        var d = Path.Combine(p, s);
                        if (Directory.Exists(d)) l.Add(d);
                    }
                }
                foreach (var d in DriveInfo.GetDrives())
                    if (d.IsReady && d.DriveType == DriveType.Fixed) l.Add(d.RootDirectory.FullName);
            }
            catch { }
            return l;
        }

        static IEnumerable<FileInfo> Fichiers(string racine, int profondeur, int max, Stopwatch chrono, int limiteMs)
        {
            var pile = new Stack<KeyValuePair<string, int>>();
            pile.Push(new KeyValuePair<string, int>(racine, 0));
            int n = 0;
            bool racineVolume = racine.Length <= 3;
            while (pile.Count > 0 && n < max && chrono.ElapsedMilliseconds < limiteMs)
            {
                var cur = pile.Pop();
                FileInfo[] fs = null; DirectoryInfo[] ds = null;
                try { var di = new DirectoryInfo(cur.Key); fs = di.GetFiles(); if (cur.Value < profondeur && !racineVolume) ds = di.GetDirectories(); }
                catch { continue; }
                foreach (var f in fs) { n++; yield return f; }
                if (ds != null)
                    foreach (var d in ds)
                        if ((d.Attributes & FileAttributes.ReparsePoint) == 0) pile.Push(new KeyValuePair<string, int>(d.FullName, cur.Value + 1));
            }
        }

        static readonly Regex Rancon = new Regex(@"(?i)^(.*(read[\s_\-\.]*me|restore|recover|decrypt|how[\s_\-]*to|instruction|ransom|unlock|help[\s_\-]*(files?|decrypt|restore)|lire[\s_\-\.]*(moi|pour)|lisez|restaur|d[eé]chiffr|r[eé]cup[eé]r|vos[\s_\-]*fichiers)|!!!).*\.(txt|html?|hta|rtf|url)$");

        static Constat NotesRancon(List<string> dossiers)
        {
            var chrono = Stopwatch.StartNew();
            var parNom = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
            var limite = DateTime.UtcNow.AddDays(-7);
            foreach (var d in dossiers)
                foreach (var f in Fichiers(d, 2, 20000, chrono, 12000))
                {
                    if (!Rancon.IsMatch(f.Name)) continue;
                    DateTime c; try { c = f.CreationTimeUtc; } catch { continue; }
                    if (c < limite) continue;
                    HashSet<string> s;
                    if (!parNom.TryGetValue(f.Name, out s)) parNom[f.Name] = s = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    s.Add(f.DirectoryName);
                }
            if (parNom.Count == 0) return new Constat(Niveau.Ok, "Aucune note de rançon récente", string.Format("{0} dossiers examinés (bureau, documents, images, téléchargements, racines des disques).", dossiers.Count));
            var pire = parNom.OrderByDescending(k => k.Value.Count).First();
            string detail = string.Format("« {0} » créé depuis moins de 7 jours dans {1} dossier(s), dont {2}.", pire.Key, pire.Value.Count, pire.Value.First());
            return pire.Value.Count >= 3
                ? new Constat(Niveau.Danger, "Notes de rançon présentes", detail)
                : new Constat(Niveau.Attention, "Fichier ressemblant à une note de rançon", detail + " À ouvrir pour vérifier (avec le Bloc-notes).");
        }

        static readonly HashSet<string> Connues = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
            ".doc", ".docx", ".docm", ".dot", ".dotx", ".xls", ".xlsx", ".xlsm", ".xlsb", ".csv", ".ppt", ".pptx", ".odt", ".ods", ".odp", ".rtf", ".txt", ".pdf",
            ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tif", ".tiff", ".heic", ".webp", ".svg", ".ico", ".raw", ".dng",
            ".mp3", ".wav", ".m4a", ".mp4", ".mov", ".avi", ".mkv", ".wmv", ".zip", ".7z", ".rar", ".gz", ".tar", ".iso", ".img", ".cab",
            ".exe", ".msi", ".dll", ".lnk", ".url", ".ini", ".log", ".tmp", ".dat", ".db", ".sqlite", ".json", ".xml", ".html", ".htm", ".css", ".js",
            ".ps1", ".bat", ".cmd", ".vbs", ".py", ".md", ".eml", ".msg", ".pst", ".ost", ".vcf", ".ics", ".bak", ".old", ".dmp", ".etl", ".evtx",
            ".crdownload", ".part", ".partial", ".torrent", ".jar", ".ttf", ".otf", ".woff", ".woff2", ".accdb", ".mdb", ".ldb", ".laccdb", ".dbf",
            ".odb", ".xps", ".oxps", ".one", ".onetoc2", ".vsd", ".vsdx", ".pub", ".xml", ".hl7", ".dcm", ".p7m", ".p7s", ".cer", ".crt", ".pfx", ".key",
            ".blf", ".regtrans-ms", ".lock", ".sys", ".nfo", ".sav", ".cfg", ".conf", ".yaml", ".yml", ".tsv", ".xlt", ".xltx", ".pot", ".potx", ".mpp" };

        static Constat ChiffrementRecent(List<string> dossiers)
        {
            var chrono = Stopwatch.StartNew();
            var deux = DateTime.UtcNow.AddHours(-2);
            var dix = DateTime.UtcNow.AddMinutes(-10);
            int vus = 0, recents = 0, tresRecents = 0;
            var ajoutees = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            var inconnues = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            foreach (var d in dossiers)
                foreach (var f in Fichiers(d, 3, 40000, chrono, 15000))
                {
                    vus++;
                    DateTime m; try { m = f.LastWriteTimeUtc; } catch { continue; }
                    if (m < deux) continue;
                    recents++;
                    if (m >= dix) tresRecents++;
                    string ext = f.Extension;
                    if (string.IsNullOrEmpty(ext) || Connues.Contains(ext)) continue;
                    string sansExt = Path.GetFileNameWithoutExtension(f.Name);
                    string avant = Path.GetExtension(sansExt);
                    var cible = (!string.IsNullOrEmpty(avant) && Connues.Contains(avant)) ? ajoutees : inconnues;
                    int n; cible.TryGetValue(ext, out n); cible[ext] = n + 1;
                }
            string bilan = string.Format("{0:N0} fichiers examinés en {1:0} s : {2:N0} modifiés depuis 2 h, dont {3:N0} depuis 10 min.", vus, chrono.Elapsed.TotalSeconds, recents, tresRecents);
            var a = ajoutees.OrderByDescending(k => k.Value).FirstOrDefault();
            var i = inconnues.OrderByDescending(k => k.Value).FirstOrDefault();
            if (a.Value >= 20) return new Constat(Niveau.Danger, "Chiffrement probablement en cours", string.Format("{0} fichiers récents ont reçu l'extension « {1} » en plus de la leur (ex. rapport.docx{1}). {2}", a.Value, a.Key, bilan));
            if (i.Value >= 50) return new Constat(Niveau.Danger, "Extension inconnue sur de nombreux fichiers récents", string.Format("{0} fichiers modifiés depuis 2 h portent l'extension « {1} ». {2}", i.Value, i.Key, bilan));
            if (a.Value >= 5) return new Constat(Niveau.Attention, "Extensions ajoutées à des fichiers", string.Format("{0} fichiers récents finissent par « {1} » après leur extension. {2}", a.Value, a.Key, bilan));
            if (tresRecents > 400) return new Constat(Niveau.Attention, "Beaucoup de fichiers modifiés à l'instant", bilan + " Vérifiez qu'une synchronisation (OneDrive, sauvegarde) explique ce volume.");
            return new Constat(Niveau.Ok, "Pas de chiffrement massif en cours", bilan);
        }

        // ------------------------------------------------------------------ ecritures disque par processus
        [StructLayout(LayoutKind.Sequential)]
        struct IO_COUNTERS { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint acces, bool herite, int pid);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetProcessIoCounters(IntPtr h, out IO_COUNTERS c);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr h, int flags, StringBuilder nom, ref int taille);

        static Dictionary<int, KeyValuePair<ulong, string>> Releve()
        {
            var r = new Dictionary<int, KeyValuePair<ulong, string>>();
            foreach (var p in Process.GetProcesses())
            {
                try
                {
                    if (p.Id == Process.GetCurrentProcess().Id || p.Id <= 4) continue;
                    IntPtr h = OpenProcess(0x1000, false, p.Id);
                    if (h == IntPtr.Zero) continue;
                    try
                    {
                        IO_COUNTERS c;
                        if (!GetProcessIoCounters(h, out c)) continue;
                        var sb = new StringBuilder(1024); int t = sb.Capacity;
                        string chemin = QueryFullProcessImageName(h, 0, sb, ref t) ? sb.ToString() : p.ProcessName;
                        r[p.Id] = new KeyValuePair<ulong, string>(c.WriteBytes, chemin);
                    }
                    finally { CloseHandle(h); }
                }
                catch { }
                finally { p.Dispose(); }
            }
            return r;
        }

        static readonly Regex CheminUtilisateur = new Regex(@"(?i)\\(AppData|Temp|Users\\Public|Downloads|Téléchargements|Desktop|Bureau|PerfLogs)\\|\\ProgramData\\(?!Microsoft\\)");

        static Constat Ecritures()
        {
            var a = Releve();
            Thread.Sleep(3000);
            var b = Releve();
            var debits = new List<KeyValuePair<string, double>>();
            foreach (var k in b)
            {
                KeyValuePair<ulong, string> av;
                if (!a.TryGetValue(k.Key, out av) || k.Value.Key < av.Key) continue;
                double mo = (k.Value.Key - av.Key) / 3.0 / (1 << 20);
                if (mo >= 1) debits.Add(new KeyValuePair<string, double>(k.Value.Value, mo));
            }
            debits = debits.OrderByDescending(x => x.Value).ToList();
            var suspects = debits.Where(x => x.Value >= 3 && CheminUtilisateur.IsMatch(x.Key)).ToList();
            if (suspects.Count > 0)
                return new Constat(Niveau.Danger, "Programme inconnu qui écrit beaucoup", string.Join(" ; ", suspects.Take(3).Select(x => string.Format("{0} : {1:0.0} Mo/s", x.Key, x.Value)).ToArray()) + ". Un rançongiciel tourne souvent depuis AppData, Temp ou ProgramData.");
            var gros = debits.Where(x => x.Value >= 40).ToList();
            if (gros.Count > 0)
                return new Constat(Niveau.Attention, "Écritures importantes sur le disque", string.Join(" ; ", gros.Take(3).Select(x => string.Format("{0} : {1:0} Mo/s", Path.GetFileName(x.Key), x.Value)).ToArray()) + ". Souvent normal (mise à jour, antivirus) : à vérifier.");
            return new Constat(Niveau.Ok, "Pas d'écriture anormale", debits.Count == 0 ? "Aucun programme n'écrit plus de 1 Mo/s." : "Plus gros écrivain : " + Path.GetFileName(debits[0].Key) + string.Format(" ({0:0.0} Mo/s).", debits[0].Value));
        }

        static Constat Antivirus()
        {
            try
            {
                using (var s = new ManagementObjectSearcher(@"root\Microsoft\Windows\Defender", "SELECT RealTimeProtectionEnabled, AntivirusEnabled FROM MSFT_MpComputerStatus"))
                    foreach (ManagementObject o in s.Get())
                    {
                        bool tr = Convert.ToBoolean(o["RealTimeProtectionEnabled"]), av = Convert.ToBoolean(o["AntivirusEnabled"]);
                        if (av && tr) return new Constat(Niveau.Ok, "Antivirus actif", "Microsoft Defender : protection en temps réel activée.");
                        if (av && !tr) return new Constat(Niveau.Attention, "Protection en temps réel désactivée", "Microsoft Defender est installé mais sa protection en temps réel est coupée : possible action de l'attaquant.");
                    }
            }
            catch { }
            try
            {
                var noms = new List<string>();
                using (var s = new ManagementObjectSearcher(@"root\SecurityCenter2", "SELECT displayName, productState FROM AntiVirusProduct"))
                    foreach (ManagementObject o in s.Get())
                    {
                        int etat = Convert.ToInt32(o["productState"]);
                        noms.Add(Convert.ToString(o["displayName"]) + (((etat >> 12) & 0xF) == 1 ? " (actif)" : " (inactif)"));
                    }
                if (noms.Count > 0)
                    return new Constat(noms.Any(n => n.EndsWith("(actif)")) ? Niveau.Ok : Niveau.Attention, "Antivirus", string.Join(", ", noms.ToArray()));
            }
            catch { }
            return new Constat(Niveau.Info, "Antivirus non identifié", "État de l'antivirus illisible sur ce poste.");
        }

        static Constat Reseau()
        {
            try
            {
                var actifs = NetworkInterface.GetAllNetworkInterfaces().Where(n => n.OperationalStatus == OperationalStatus.Up
                    && n.NetworkInterfaceType != NetworkInterfaceType.Loopback && n.NetworkInterfaceType != NetworkInterfaceType.Tunnel
                    && n.GetIPProperties().GatewayAddresses.Count > 0).Select(n => n.Name).ToList();
                if (actifs.Count > 0)
                    return new Constat(Niveau.Attention, "Poste connecté au réseau", "Actif : " + string.Join(", ", actifs.ToArray()) + ". Isolez le poste (câble, Wi-Fi) sans l'éteindre avant de brancher la clé PREUVES, sauf consigne contraire. L'horodatage du scellé se fera au bureau.");
                return new Constat(Niveau.Ok, "Poste isolé du réseau", "Aucune connexion active avec passerelle.");
            }
            catch { return new Constat(Niveau.Info, "Réseau", "État du réseau illisible."); }
        }

        static Constat SupportsBranches(Contexte ctx)
        {
            var autres = Supports.Lister(ctx.RacineOutils).Where(s => s.Externe && !s.EstOutils).ToList();
            if (autres.Count == 0) return new Constat(Niveau.Ok, "Aucun autre support branché", "La clé PREUVES sera branchée à l'étape suivante.");
            return new Constat(Niveau.Info, "Support déjà branché", string.Join(", ", autres.Select(s => s.Nom).ToArray()) + ". Idéalement, ne brancher la clé PREUVES qu'après ce contrôle.");
        }
    }
}
