// DigSpill - fichiers pieges sur la cle PREUVES : si un programme les touche, la cle est coupee aussitot.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace DigSpill
{
    class Pieges : IDisposable
    {
        class Piege { public string Chemin, Empreinte; public long Taille; public DateTime Ecriture; }

        // annee en cours : un appât daté de l'an passé attire moins
        static readonly string[] Noms = {
            "!!!_0_Dossiers_patients_" + DateTime.Now.Year + ".xlsx", "!!!_0_Ordonnances_a_signer.docx", "!!!_0_Comptabilite_cabinet.pdf", "!!!_0_Scan_cartes_vitale.jpg" };
        static readonly Regex Rancon = new Regex(@"(?i)(read[\s_\-\.]*me|restore|recover|decrypt|how[\s_\-]*to|ransom|unlock).*\.(txt|html?|hta|rtf)$");

        readonly List<Piege> pieges = new List<Piege>();
        readonly string racine;
        FileSystemWatcher veille;
        System.Threading.Timer controle;
        readonly Queue<DateTime> renommages = new Queue<DateTime>();
        int declenche;

        /// <summary>Declenche une seule fois, depuis un fil quelconque.</summary>
        public event Action<string> Alerte;
        public int Nombre { get { return pieges.Count; } }
        public bool Declenche { get { return declenche != 0; } }
        public DateTime DernierControle { get; private set; }

        public Pieges(string racineSupport) { racine = racineSupport; }

        public void Poser()
        {
            var rnd = new RNGCryptoServiceProvider();
            var dossiers = new[] { racine, Path.Combine(racine, "Collecte") };
            int i = 0;
            foreach (var nom in Noms)
            {
                string d = dossiers[i++ % dossiers.Length];
                Directory.CreateDirectory(d);
                var octets = new byte[64 * 1024];
                rnd.GetBytes(octets);
                string p = Path.Combine(d, nom);
                File.WriteAllBytes(p, octets);
                var fi = new FileInfo(p);
                pieges.Add(new Piege { Chemin = p, Taille = fi.Length, Ecriture = fi.LastWriteTimeUtc, Empreinte = Hacher(p) });
            }
        }

        public void Surveiller()
        {
            veille = new FileSystemWatcher(racine) { IncludeSubdirectories = true, InternalBufferSize = 64 * 1024, NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName };
            veille.Renamed += (s, e) => Renomme(e.OldFullPath, e.FullPath);
            veille.Deleted += (s, e) => { if (EstPiege(e.FullPath)) Declencher("Fichier-appât supprimé : " + Path.GetFileName(e.FullPath)); };
            veille.Created += (s, e) => { if (Rancon.IsMatch(e.Name) && !e.FullPath.StartsWith(Path.Combine(racine, "Collecte") + "\\", StringComparison.OrdinalIgnoreCase)) Declencher("Note de rançon créée sur la clé : " + e.Name); };
            veille.Error += (s, e) => Verifier();
            veille.EnableRaisingEvents = true;
            controle = new System.Threading.Timer(_ => Verifier(), null, 1000, 2000);
        }

        bool EstPiege(string chemin) { return pieges.Any(p => string.Equals(p.Chemin, chemin, StringComparison.OrdinalIgnoreCase)); }

        void Renomme(string ancien, string nouveau)
        {
            if (EstPiege(ancien)) { Declencher("Fichier-appât renommé : " + Path.GetFileName(ancien) + " → " + Path.GetFileName(nouveau)); return; }
            // motif typique : rapport.csv -> rapport.csv.lockbit (une extension ajoutee a un fichier existant)
            if (nouveau.Length > ancien.Length + 1 && nouveau.StartsWith(ancien + ".", StringComparison.OrdinalIgnoreCase))
            {
                lock (renommages)
                {
                    renommages.Enqueue(DateTime.UtcNow);
                    while (renommages.Count > 0 && (DateTime.UtcNow - renommages.Peek()).TotalSeconds > 10) renommages.Dequeue();
                    if (renommages.Count >= 3) Declencher("Fichiers de la clé renommés avec une extension ajoutée (ex. " + Path.GetFileName(nouveau) + ")");
                }
            }
        }

        void Verifier()
        {
            if (declenche != 0) return;
            foreach (var p in pieges)
            {
                try
                {
                    var fi = new FileInfo(p.Chemin);
                    if (!fi.Exists) { Declencher("Fichier-appât disparu : " + Path.GetFileName(p.Chemin)); return; }
                    if (fi.Length != p.Taille || fi.LastWriteTimeUtc != p.Ecriture) { Declencher("Fichier-appât modifié : " + Path.GetFileName(p.Chemin)); return; }
                    if (Hacher(p.Chemin) != p.Empreinte) { Declencher("Contenu d'un fichier-appât modifié : " + Path.GetFileName(p.Chemin)); return; }
                }
                catch (IOException) { /* fichier ouvert par un autre programme : on regarde au prochain passage */ }
                catch (UnauthorizedAccessException) { Declencher("Accès refusé à un fichier-appât : " + Path.GetFileName(p.Chemin)); return; }
            }
            DernierControle = DateTime.Now;
        }

        void Declencher(string raison)
        {
            if (System.Threading.Interlocked.Exchange(ref declenche, 1) != 0) return;
            Arreter();
            var a = Alerte;
            if (a != null) a(raison);
        }

        static string Hacher(string chemin)
        {
            using (var s = new FileStream(chemin, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (var h = SHA256.Create())
                return BitConverter.ToString(h.ComputeHash(s)).Replace("-", "");
        }

        public void Arreter()
        {
            if (controle != null) { controle.Dispose(); controle = null; }
            if (veille != null) { veille.EnableRaisingEvents = false; veille.Dispose(); veille = null; }
        }

        /// <summary>Fin normale : on retire les pieges (ils ne font pas partie des preuves).</summary>
        public void Retirer()
        {
            Arreter();
            foreach (var p in pieges) { try { File.Delete(p.Chemin); } catch { } }
        }

        public void Dispose() { Arreter(); }
    }
}
