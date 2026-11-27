using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace DigSpill
{
    /// <summary>
    /// Mise a jour du kit (DigSpill.exe + moteur\) depuis les releases publiques du depot GitHub.
    /// Au bureau seulement : sur un poste examine, DigSpill ne doit pas aller sur Internet.
    /// Le remplacement se fait apres la fermeture de DigSpill, par moteur\Remplacer-Kit.ps1 (copie dans %TEMP%) qui garde
    /// l'ancienne version jusqu'au bout (retour en arriere si une etape echoue) et conserve digspill.ini et les bases telechargees.
    /// </summary>
    static class MiseAJour
    {
        public const string Depot = "nomoreroses/DigSpill";
        public const string PageReleases = "https://github.com/" + Depot + "/releases";
        public static string Dossier { get { return Path.Combine(Path.GetTempPath(), "DigSpill-maj"); } }
        public static string JournalRemplacement { get { return Path.Combine(Dossier, "journal.txt"); } }

        /// <summary>Marque de « PC de bureau » : ecrite quand on ouvre la page Mises a jour ou qu'une analyse se termine.
        /// Seul un PC qui la porte cherche les mises a jour au demarrage : un poste examine ne va jamais sur Internet tout seul.</summary>
        static string Marque { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DigSpill", "pc_de_bureau.txt"); } }
        public static bool PcDeBureau { get { try { return File.Exists(Marque); } catch { return false; } } }
        public static void MarquerPcDeBureau()
        {
            try
            {
                if (File.Exists(Marque)) return;
                Directory.CreateDirectory(Path.GetDirectoryName(Marque));
                File.WriteAllText(Marque, "PC de bureau DigSpill depuis le " + DateTime.Now.ToString("dd/MM/yyyy HH:mm") + " : recherche des mises à jour au démarrage.\r\nSupprimer ce fichier pour l'arrêter.\r\n");
            }
            catch { }
        }

        /// <summary>Demonstration : une version « suivante » fictive, pour montrer la pastille et la page.</summary>
        public static Release Demo(string version)
        {
            var v = Numero(version) ?? new Version(2, 9, 4);
            var n = new Version(v.Major, v.Minor, Math.Max(0, v.Build) + 1);
            return new Release { Tag = "v" + n, Numero = n, Notes = "- Démonstration : notes de version.", Taille = 180L << 20, Date = DateTime.Now, Beta = true };
        }

        /// <summary>Vrai si la release est plus recente que la version du kit.</summary>
        public static bool PlusRecente(Release r, string version)
        {
            if (r == null || r.Numero == null) return false;
            var ici = Numero(version);
            return ici == null || r.Numero > ici;
        }

        public class Release
        {
            public string Tag = "", Notes = "", Url = "", Sha256;
            public Version Numero;
            public long Taille;
            public DateTime Date;
            public bool Beta;
        }

        /// <summary>Version du kit : 1re ligne de moteur\VERSION.txt (ecrit par construire-kit.ps1). Null pour un kit plus ancien.</summary>
        public static string VersionKit(string moteur)
        {
            try
            {
                var f = Path.Combine(moteur ?? "", "VERSION.txt");
                if (File.Exists(f))
                {
                    var l = File.ReadAllLines(f);
                    if (l.Length > 0 && l[0].Trim() != "") return l[0].Trim();
                }
            }
            catch { }
            return null;
        }

        public static Version Numero(string v)
        {
            if (string.IsNullOrEmpty(v)) return null;
            var m = Regex.Match(v, @"\d+(\.\d+){1,3}");
            Version r;
            return m.Success && Version.TryParse(m.Value, out r) ? r : null;
        }

        /// <summary>Le kit a mettre a jour : dossier de DigSpill.exe, qui contient moteur\. Null si DigSpill ne tourne pas depuis un kit.</summary>
        public static string Kit(string moteur)
        {
            try
            {
                // kit a la racine d'une cle (F:\moteur) : le dossier de DigSpill.exe vaut « F:\ » et le parent de moteur aussi.
                // Comparer sans la barre finale des deux cotes (avant 2.9.6 : « F: » contre « F:\ », mise a jour refusee).
                string exe = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
                string parent = Path.GetDirectoryName(Path.GetFullPath(moteur).TrimEnd('\\'));
                if (parent == null || !string.Equals(exe.TrimEnd('\\'), parent.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)) return null;
                if (!string.Equals(Path.GetFileName(Path.GetFullPath(moteur).TrimEnd('\\')), "moteur", StringComparison.OrdinalIgnoreCase)) return null;
                return exe;
            }
            catch { return null; }
        }

        static HttpWebRequest Requete(string url, string accept)
        {
            ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072;   // TLS 1.2 (.NET 4.x)
            var w = (HttpWebRequest)WebRequest.Create(url);
            w.UserAgent = "DigSpill-mise-a-jour";
            w.Accept = accept;
            w.Timeout = 20000;
            w.ReadWriteTimeout = 60000;
            return w;
        }

        /// <summary>Plus haute version publiee (beta comprises) qui contient DigSpill.zip. Null si aucune.</summary>
        public static Release Derniere()
        {
            string json;
            using (var r = Requete("https://api.github.com/repos/" + Depot + "/releases?per_page=30", "application/vnd.github+json").GetResponse())
            using (var s = new StreamReader(r.GetResponseStream(), Encoding.UTF8)) json = s.ReadToEnd();
            return Lire(json);
        }

        /// <summary>Choix dans la reponse de l'API des releases (separe pour etre teste sans reseau).</summary>
        public static Release Lire(string json)
        {
            var liste = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<List<Dictionary<string, object>>>(json);
            Release meilleure = null;
            foreach (var d in liste)
            {
                if (Vrai(d, "draft")) continue;
                var num = Numero(Texte(d, "tag_name"));
                if (num == null || (meilleure != null && num <= meilleure.Numero)) continue;
                object a;
                if (!d.TryGetValue("assets", out a) || !(a is IEnumerable)) continue;
                foreach (var o in (IEnumerable)a)
                {
                    var asset = o as Dictionary<string, object>;
                    if (asset == null || Texte(asset, "name") != "DigSpill.zip") continue;
                    string dig = Texte(asset, "digest");
                    DateTime date;
                    DateTime.TryParse(Texte(d, "published_at"), out date);
                    meilleure = new Release
                    {
                        Tag = Texte(d, "tag_name"), Numero = num, Notes = Texte(d, "body"), Url = Texte(asset, "browser_download_url"),
                        Taille = Nombre(asset, "size"), Sha256 = dig.StartsWith("sha256:") ? dig.Substring(7).ToUpperInvariant() : null,
                        Date = date, Beta = Vrai(d, "prerelease")
                    };
                }
            }
            return meilleure;
        }

        static string Texte(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) && v != null ? v.ToString() : ""; }
        static bool Vrai(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) && v is bool && (bool)v; }
        static long Nombre(Dictionary<string, object> d, string k) { object v; try { return d.TryGetValue(k, out v) && v != null ? Convert.ToInt64(v) : 0; } catch { return 0; } }

        /// <summary>Telecharge DigSpill.zip et verifie l'empreinte publiee par GitHub (et la taille). Renvoie le SHA256.</summary>
        public static string Telecharger(Release r, string fichier, Action<long, long> progres, Func<bool> annule)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(fichier));
            long lu = 0, total;
            byte[] empreinte;
            using (var rep = Requete(r.Url, "application/octet-stream").GetResponse())
            using (var s = rep.GetResponseStream())
            using (var f = File.Create(fichier))
            using (var h = SHA256.Create())
            {
                total = rep.ContentLength > 0 ? rep.ContentLength : r.Taille;
                var buf = new byte[1 << 16];
                int n;
                while ((n = s.Read(buf, 0, buf.Length)) > 0)
                {
                    if (annule()) throw new OperationCanceledException();
                    f.Write(buf, 0, n);
                    h.TransformBlock(buf, 0, n, null, 0);
                    lu += n;
                    progres(lu, total);
                }
                h.TransformFinalBlock(buf, 0, 0);
                empreinte = h.Hash;
            }
            string sha = BitConverter.ToString(empreinte).Replace("-", "");
            if (r.Taille > 0 && lu != r.Taille) throw new InvalidDataException("téléchargement incomplet (" + lu + " octets sur " + r.Taille + ")");
            if (r.Sha256 != null && sha != r.Sha256) throw new InvalidDataException("l'empreinte SHA256 ne correspond pas à celle publiée par GitHub");
            return sha;
        }

        /// <summary>Extrait l'archive, controle son contenu et l'ecriture sur le kit, puis lance le remplacement
        /// (qui attend la fermeture de DigSpill). L'appelant ferme DigSpill ensuite.</summary>
        public static void Preparer(string zip, string kit)
        {
            string nouveau = Path.Combine(Dossier, "nouveau");
            if (Directory.Exists(nouveau)) Directory.Delete(nouveau, true);
            ZipFile.ExtractToDirectory(zip, nouveau);
            if (!File.Exists(Path.Combine(nouveau, "DigSpill.exe")) || !File.Exists(Path.Combine(Path.Combine(nouveau, "moteur"), "Collecte-Exfil.ps1")))
                throw new InvalidDataException("archive inattendue : DigSpill.exe ou moteur\\ absent");
            // cle OUTILS en lecture seule (interrupteur) : on le dit avant de fermer DigSpill
            string essai = Path.Combine(kit, ".digspill-essai-ecriture");
            File.WriteAllText(essai, "");
            File.Delete(essai);
            // le script de remplacement tourne depuis %TEMP% (moteur\ va etre remplace) ; celui de la nouvelle version
            // d'abord, pour qu'une correction du remplacement serve des cette mise a jour
            string script = Path.Combine(Dossier, "Remplacer-Kit.ps1");
            string source = Path.Combine(Path.Combine(nouveau, "moteur"), "Remplacer-Kit.ps1");
            if (!File.Exists(source)) source = Path.Combine(Path.Combine(kit, "moteur"), "Remplacer-Kit.ps1");
            File.Copy(source, script, true);
            if (File.Exists(JournalRemplacement)) File.Delete(JournalRemplacement);
            var psi = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\" -Attendre " + Process.GetCurrentProcess().Id +
                " -Nouveau \"" + nouveau + "\" -Kit \"" + kit.TrimEnd('\\') + "\"") { UseShellExecute = false, CreateNoWindow = true };
            Process.Start(psi);
        }

        /// <summary>Message a montrer au redemarrage (argument --maj=ok|echec).</summary>
        public static void Annoncer(string resultat, IWin32Window parent, string version)
        {
            if (resultat == "ok")
                Notif.Afficher(parent as Form, Niveau.Ok, "Mise à jour installée", "DigSpill " + (version ?? ""));
            else
            {
                string j = "";
                try { j = File.Exists(JournalRemplacement) ? "\r\n\r\n" + File.ReadAllText(JournalRemplacement) : ""; } catch { }
                Boite.Informer(parent, Niveau.Attention, "Mise à jour non installée", "L'ancienne version est conservée et fonctionne." + j);
            }
        }

    }

    // ====================================================================== page
    class PageMiseAJour : Page
    {
        readonly LigneInfo etat;
        readonly Barre barre = new Barre { Visible = false };
        readonly Carte notes;
        readonly Label texteNotes;
        MiseAJour.Release trouvee;
        bool occupe, annule;
        readonly string version;

        public PageMiseAJour(Fenetre f) : base(f)
        {
            Titre = "Mises à jour";
            SousTitre = "Au bureau seulement, jamais sur un poste examiné.";
            Details = "Chercher une mise à jour fait aller DigSpill sur Internet depuis ce poste. Une fois cette page ouverte, ce PC est reconnu comme PC de bureau : DigSpill y cherche les nouvelles versions à chaque démarrage (fichier pc_de_bureau.txt dans %LOCALAPPDATA%\\DigSpill, à supprimer pour arrêter).";
            version = MiseAJour.VersionKit(Ctx.RacineOutils);
            var c = Corps.Ajouter(NouvelleCarte());
            c.Contenu.Ajouter(new LigneInfo(Niveau.Info, "Version installée : " + (version ?? "antérieure à 2.9.1"), MiseAJour.Kit(Ctx.RacineOutils) ?? Ctx.RacineOutils));
            etat = c.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "Recherche de la dernière version…", MiseAJour.PageReleases));
            c.Contenu.Ajouter(barre);
            notes = Corps.Ajouter(NouvelleCarte());
            notes.Contenu.Ajouter(Intertitre("Nouveautés"));
            texteNotes = notes.Contenu.Ajouter(Paragraphe(""));
            notes.Visible = false;
        }

        public override void Affichee() { if (!Ctx.Demo) MiseAJour.MarquerPcDeBureau(); Chercher(); }
        public override void Quittee() { annule = true; }

        void Ui(Action a) { if (IsDisposed) return; if (InvokeRequired) BeginInvoke(a); else a(); }

        async void Chercher()
        {
            if (Ctx.Demo)
            {
                trouvee = MiseAJour.Demo(version);
                Afficher(); return;
            }
            try { trouvee = await Task.Run(() => MiseAJour.Derniere()); Afficher(); }
            catch (Exception ex)
            {
                etat.Definir(Niveau.Attention, "Pas de réponse de GitHub", ex.Message + " · Sans Internet : téléchargez DigSpill.zip sur " + MiseAJour.PageReleases);
                Ajuster();
            }
        }

        bool PlusRecente() { return MiseAJour.PlusRecente(trouvee, version); }

        void Afficher()
        {
            F.ResultatMiseAJour(trouvee);
            if (trouvee == null) etat.Definir(Niveau.Attention, "Aucune version publiée", MiseAJour.PageReleases);
            else if (!PlusRecente()) etat.Definir(Niveau.Ok, "DigSpill est à jour", "Dernière version publiée : " + trouvee.Tag + (trouvee.Date > DateTime.MinValue ? " du " + trouvee.Date.ToString("dd/MM/yyyy") : ""));
            else
            {
                etat.Definir(Niveau.Info, "Nouvelle version : " + trouvee.Tag + (trouvee.Beta ? " (bêta)" : ""),
                    string.Format("Publiée le {0:dd/MM/yyyy} · {1:0} Mo à télécharger{2}", trouvee.Date, trouvee.Taille / 1048576.0,
                        trouvee.Sha256 != null ? " · empreinte vérifiée après téléchargement" : ""));
                if (!string.IsNullOrWhiteSpace(trouvee.Notes))
                {
                    texteNotes.Text = trouvee.Notes.Replace("\r\n", "\n").Replace("\n", "\r\n").Replace("**", "").Replace("`", "");
                    notes.Visible = true;
                }
            }
            F.MajEntete();
            Ajuster();
        }

        public override IEnumerable<Control> Boutons()
        {
            var r = new BoutonPlat("Retour", BoutonPlat.Genre.Discret, Ic.Retour) { Enabled = !occupe };
            r.Click += delegate { F.Aller(new PageAccueil(F)); };
            var l = new List<Control> { r };
            if (PlusRecente())
            {
                var i = new BoutonPlat("Installer " + trouvee.Tag, BoutonPlat.Genre.Primaire, Ic.Actualiser) { Enabled = !occupe };
                i.Click += delegate { Installer(); };
                l.Add(i);
            }
            return l;
        }

        async void Installer()
        {
            string kit = MiseAJour.Kit(Ctx.RacineOutils);
            if (!Ctx.Demo && kit == null)
            {
                Boite.Informer(F, Niveau.Info, "Mise à jour automatique impossible", "DigSpill ne tourne pas depuis un kit (DigSpill.exe à côté du dossier moteur). Téléchargez DigSpill.zip sur " + MiseAJour.PageReleases + ".");
                return;
            }
            occupe = true; Occupee = true; F.MajEntete();
            barre.Visible = true; barre.Vivante = true; Ajuster();
            try
            {
                string zip = Path.Combine(MiseAJour.Dossier, "DigSpill.zip");
                if (Ctx.Demo) { for (int k = 1; k <= 20; k++) { await Task.Delay(100); barre.Valeur = k / 20.0; } }
                else
                {
                    long dernier = -(4L << 20);
                    await Task.Run(() => MiseAJour.Telecharger(trouvee, zip, (lu, tot) =>
                    {
                        if (lu - dernier < (4L << 20) && lu != tot) return;   // tous les 4 Mo
                        dernier = lu;
                        Ui(() =>
                        {
                            barre.Valeur = tot > 0 ? (double)lu / tot : 0;
                            etat.Definir(Niveau.EnCours, "Téléchargement de " + trouvee.Tag, string.Format("{0:0} / {1:0} Mo", lu / 1048576.0, tot / 1048576.0));
                        });
                    }, () => annule));
                    Ui(() => etat.Definir(Niveau.EnCours, "Préparation", "Archive vérifiée, extraction…"));
                    await Task.Run(() => MiseAJour.Preparer(zip, kit));
                }
                barre.Vivante = false; barre.Valeur = 1;
                etat.Definir(Niveau.Ok, "Prêt", "DigSpill va se fermer, remplacer ses fichiers et se rouvrir tout seul (quelques secondes à une minute sur une clé).");
                Ajuster();
                if (Ctx.Demo) { occupe = false; Occupee = false; F.MajEntete(); return; }
                await Task.Delay(1500);
                Occupee = false;
                F.Close();
            }
            catch (Exception ex)
            {
                occupe = false; Occupee = false;
                barre.Vivante = false; barre.Visible = false;
                string cause = ex is UnauthorizedAccessException || ex is IOException
                    ? ex.Message + " · Clé OUTILS en lecture seule ? Basculez son interrupteur, puis recommencez."
                    : ex.Message;
                etat.Definir(Niveau.Danger, "Mise à jour impossible", cause + " · L'ancienne version est intacte.");
                F.MajEntete();
                Ajuster();
            }
        }
    }
}
