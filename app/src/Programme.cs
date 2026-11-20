// DigSpill.exe - point d'entree, contexte partage, reglages (moteur\digspill.ini sur la cle OUTILS).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("DigSpill")]
[assembly: AssemblyDescription("Triage forensique Windows : collecte, scellé et analyse")]
[assembly: AssemblyProduct("DigSpill")]
[assembly: AssemblyCompany("DigSpill")]
[assembly: AssemblyCopyright("DigSpill")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]

namespace DigSpill
{
    class Intervention
    {
        public string Prenom = "", Nom = "", Societe = "", Cabinet = "", Present = "", Ticket = "", Motif = "";
        public DateTime? Decouverte;
        public bool Legere, AnalyseSurPlace, Horodater = true;
        public string Technicien { get { return (Prenom + " " + Nom).Trim(); } }
    }

    class Reglages
    {
        readonly Dictionary<string, string> v = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public string Fichier { get; private set; }

        public static Reglages Lire(string racine)
        {
            var r = new Reglages();
            r.Fichier = Path.Combine(racine, "digspill.ini");
            try
            {
                if (!File.Exists(r.Fichier)) return r;
                string section = "";
                foreach (var brut in File.ReadAllLines(r.Fichier, Encoding.UTF8))
                {
                    var l = brut.Trim();
                    if (l.Length == 0 || l.StartsWith(";") || l.StartsWith("#")) continue;
                    if (l.StartsWith("[") && l.EndsWith("]")) { section = l.Substring(1, l.Length - 2).Trim(); continue; }
                    int i = l.IndexOf('=');
                    if (i > 0) r.v[section + "." + l.Substring(0, i).Trim()] = l.Substring(i + 1).Trim();
                }
            }
            catch { }
            return r;
        }

        public string Get(string cle, string defaut)
        {
            string x;
            return v.TryGetValue(cle, out x) && x.Length > 0 ? x : defaut;
        }

        /// <summary>Retient le technicien pour la prochaine fois (cle accessible en ecriture seulement ; sinon rien).</summary>
        public void RetenirTechnicien(string prenom, string nom, string societe)
        {
            if (Get("technicien.prenom", "") == prenom && Get("technicien.nom", "") == nom && Get("technicien.societe", "") == societe) return;
            try
            {
                var sb = new StringBuilder();
                sb.AppendLine("; DigSpill - reglages lus par DigSpill.exe au demarrage (rempli par l'appli, modifiable a la main). Encodage : UTF-8.");
                sb.AppendLine();
                sb.AppendLine("[technicien]");
                sb.AppendLine("prenom=" + prenom);
                sb.AppendLine("nom=" + nom);
                sb.AppendLine("societe=" + societe);
                sb.AppendLine();
                sb.AppendLine("[options]");
                sb.AppendLine("; Autorite d'horodatage RFC 3161 du scelle de fin de collecte (seule l'empreinte est envoyee)");
                sb.AppendLine("horodateur=" + Get("options.horodateur", "http://timestamp.sectigo.com/qualified"));
                File.WriteAllText(Fichier, sb.ToString(), new UTF8Encoding(false));
                v["technicien.prenom"] = prenom; v["technicien.nom"] = nom; v["technicien.societe"] = societe;
            }
            catch { }
        }
    }

    class Contexte
    {
        /// <summary>Dossier du moteur (scripts, interface, outils) : &lt;cle&gt;\moteur, ou la racine dans l'ancien rangement.</summary>
        public string RacineOutils;
        /// <summary>Racine de la cle OUTILS (celle de DigSpill.exe).</summary>
        public string RacineCle { get { return string.Equals(Path.GetFileName(RacineOutils.TrimEnd('\\')), "moteur", StringComparison.OrdinalIgnoreCase) ? Path.GetDirectoryName(RacineOutils.TrimEnd('\\')) : RacineOutils; } }
        /// <summary>Identifiants du compte de la session, lus avant l'elevation (cmdkey, vaultcmd).</summary>
        public string IdentifiantsSession, CompteSession;
        public bool Demo;
        public Reglages Reglages;
        public Intervention Inter = new Intervention();
        public List<Constat> FeuVert;

        // collecte
        public Support Destination;
        public bool AvecPieges = true;
        public Pieges Pieges;
        public DateTime Debut, Fin;
        public string DossierCollecteRacine, NomCollecte;
        public ResultatScelle Scelle;
        public string RaisonAlerte;
        public List<string> ActionsUrgence;
        public bool CollecteOk;

        // analyse
        public string SourceCollecte, DossierTravail, MotDePasse, Interface;
        public bool CopieVerifiee = true, AnalyseComplete = true, AvecInternet = true, Proteger;

        public string Horodateur { get { return Reglages.Get("options.horodateur", "http://timestamp.sectigo.com/qualified"); } }

        public string Script(string nom) { return Path.Combine(RacineOutils, nom); }
        public string Velociraptor
        {
            get
            {
                foreach (var c in new[] { Path.Combine(RacineOutils, "outils", "Collecteur-Velociraptor.exe"), Path.Combine(RacineOutils, "Collecteur-Velociraptor.exe"), Path.Combine(RacineCle, "Collecteur-Velociraptor.exe") })
                    if (File.Exists(c)) return c;
                return Path.Combine(RacineOutils, "outils", "Collecteur-Velociraptor.exe");
            }
        }
    }

    static class Programme
    {
        public const string Version = "1.1";

        /// <summary>Dossier des scripts : &lt;exe&gt;\moteur (cle rangee), l'exe lui-meme (ancien rangement),
        /// ou un parent (pendant le developpement, app\bin).</summary>
        static string TrouverOutils()
        {
            var d = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
            for (var x = d; x != null; x = x.Parent)
            {
                var m = Path.Combine(x.FullName, "moteur");
                if (File.Exists(Path.Combine(m, "Collecte-Exfil.ps1"))) return m;
                if (File.Exists(Path.Combine(x.FullName, "Collecte-Exfil.ps1"))) return x.FullName;
            }
            return Path.Combine(d.FullName, "moteur");
        }

        public static void Relancer(string arguments, bool admin)
        {
            var psi = new ProcessStartInfo(Application.ExecutablePath, arguments) { UseShellExecute = true };
            if (admin) psi.Verb = "runas";
            Process.Start(psi);
        }

        [STAThread]
        static void Main(string[] args)
        {
            var fr = new System.Globalization.CultureInfo("fr-FR");
            System.Threading.Thread.CurrentThread.CurrentCulture = fr;
            System.Threading.Thread.CurrentThread.CurrentUICulture = fr;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            var ctx = new Contexte();
            ctx.Demo = args.Contains("--demo");
            ctx.RacineOutils = TrouverOutils();
            ctx.Reglages = Reglages.Lire(ctx.RacineOutils);
            ctx.Inter.Prenom = ctx.Reglages.Get("technicien.prenom", "");
            ctx.Inter.Nom = ctx.Reglages.Get("technicien.nom", "");
            ctx.Inter.Societe = ctx.Reglages.Get("technicien.societe", "");
            string depart = args.Contains("--collecter") ? "collecter" : args.Contains("--analyser") ? "analyser" : "accueil";
            foreach (var a in args) if (a.StartsWith("--page=")) depart = a.Substring(7);
            string capture = null;
            foreach (var a in args) if (a.StartsWith("--capture=")) capture = a.Substring(10);
            // identifiants lus par l'instance non elevee, juste avant de relancer en administrateur
            foreach (var a in args) if (a.StartsWith("--identifiants=")) ctx.IdentifiantsSession = Identifiants.DepuisBase64(a.Substring(15));
            foreach (var a in args) if (a.StartsWith("--compte=")) ctx.CompteSession = a.Substring(9);
            Application.ThreadException += (s, e) => MessageBox.Show(e.Exception.ToString(), "DigSpill : erreur inattendue", MessageBoxButtons.OK, MessageBoxIcon.Error);
            Application.Run(new Fenetre(ctx, depart, capture));
        }
    }
}
