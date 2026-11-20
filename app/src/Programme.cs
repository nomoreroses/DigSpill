// DigSpill.exe - point d'entree, contexte partage, reglages (digspill.ini sur la cle OUTILS).
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
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

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
    }

    class Contexte
    {
        public string RacineOutils;
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
        public string Velociraptor { get { return Path.Combine(RacineOutils, "Collecteur-Velociraptor.exe"); } }
    }

    static class Programme
    {
        public const string Version = "1.0";

        /// <summary>Dossier des scripts : celui de l'exe, ou un parent (pendant le developpement, app\bin).</summary>
        static string TrouverOutils()
        {
            var d = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
            for (var x = d; x != null; x = x.Parent)
                if (File.Exists(Path.Combine(x.FullName, "Collecte-Exfil.ps1"))) return x.FullName;
            return d.FullName;
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
            Application.ThreadException += (s, e) => MessageBox.Show(e.Exception.ToString(), "DigSpill : erreur inattendue", MessageBoxButtons.OK, MessageBoxIcon.Error);
            Application.Run(new Fenetre(ctx, depart, capture));
        }
    }
}
