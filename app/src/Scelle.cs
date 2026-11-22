// DigSpill - scelle de fin de collecte (meme format que Generer-Interface.ps1) et horodatage RFC 3161.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace DigSpill
{
    class ResultatScelle
    {
        public string Fichier, Empreinte, Erreur;
        public int NombreElements;
        public string DateJeton, Horodateur, ErreurHorodatage;
    }

    static class Scelle
    {
        public static string Sha256(string chemin, Action<long, long> progres)
        {
            using (var s = new FileStream(chemin, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20))
            using (var h = SHA256.Create())
            {
                var tampon = new byte[1 << 20];
                long total = s.Length, lu = 0; int n;
                while ((n = s.Read(tampon, 0, tampon.Length)) > 0)
                {
                    h.TransformBlock(tampon, 0, n, null, 0);
                    lu += n;
                    if (progres != null) progres(lu, total);
                }
                h.TransformFinalBlock(tampon, 0, 0);
                return BitConverter.ToString(h.Hash).Replace("-", "");
            }
        }

        /// <summary>
        /// Scelle ecrit sur place, juste apres la collecte : manifeste, journal, conteneurs Velociraptor de la session.
        /// Les chemins sont relatifs au dossier Collecte (comme dans le scelle du generateur).
        /// </summary>
        public static ResultatScelle Creer(string dossierCollecteRacine, string nomCollecte, string par, DateTime debut, Action<string> etat)
        {
            var r = new ResultatScelle();
            string collecte = Path.Combine(dossierCollecteRacine, nomCollecte);
            var fichiers = new List<string>();
            foreach (var n in new[] { "manifeste_sha256.csv", "collecte.log", "infos_collecte.txt" })
            {
                var p = Path.Combine(collecte, n);
                if (File.Exists(p)) fichiers.Add(p);
            }
            var velo = Path.Combine(dossierCollecteRacine, "Velociraptor");
            if (Directory.Exists(velo))
                fichiers.AddRange(Directory.GetFiles(velo, "*.zip").Where(f => File.GetLastWriteTime(f) >= debut.AddMinutes(-1)));
            var lignes = new List<string>();
            int k = 0;
            foreach (var f in fichiers)
            {
                k++;
                var fi = new FileInfo(f);
                string nom = fi.Name;
                bool gros = fi.Length > 50L << 20;
                string rang = fichiers.Count > 1 ? string.Format(" (fichier {0}/{1})", k, fichiers.Count) : "";
                // ouverture : un antivirus peut analyser une grosse archive avant de la laisser lire
                if (gros) etat(string.Format("Empreinte de {0}{1} : ouverture…", nom, rang));
                int dernier = -1;
                string h = Sha256(f, (lu, tot) =>
                {
                    if (!gros) return;
                    int pm = (int)(1000 * lu / Math.Max(1, tot));          // pour mille : 1 000 mises a jour au plus, l'interface suit
                    if (pm == dernier) return;
                    dernier = pm;
                    etat(string.Format("Empreinte de {0}{1} : {2:0.0} / {3:0.0} Go ({4:0.0} %)", nom, rang, lu / 1073741824.0, tot / 1073741824.0, pm / 10.0));
                });
                if (gros) etat(string.Format("Empreinte de {0}{1} : terminée", nom, rang));
                lignes.Add(string.Format("{0}  {1}  {2}", h, fi.Length, f.Substring(dossierCollecteRacine.TrimEnd('\\').Length + 1)));
            }
            etat("écriture du fichier de scellé…");
            lignes = lignes.OrderBy(l => l.Split(new[] { "  " }, 3, StringSplitOptions.None)[2], StringComparer.OrdinalIgnoreCase).ToList();
            r.NombreElements = lignes.Count;
            if (lignes.Count == 0) { r.Erreur = "aucun fichier à sceller (manifeste absent ?)"; return r; }

            var maintenant = DateTimeOffset.Now;
            string decalage = maintenant.ToString("zzz");
            var contenu = new List<string> {
                "DIGSPILL - SCELLE DES PREUVES (v1)", "==================================================",
                "Collecte   : " + nomCollecte,
                "Cree le    : " + maintenant.ToString("yyyy-MM-dd HH:mm:ss ") + decalage + " (horloge de " + Environment.MachineName + ")",
                "Par        : " + par,
                "Outil      : DigSpill.exe v" + Programme.Version + " (sur le poste, fin de collecte)", "",
                "Empreintes SHA256, tailles (octets) et chemins des fichiers scelles :" };
            contenu.AddRange(lignes);
            contenu.AddRange(new[] { "",
                "Verification : Get-FileHash -Algorithm SHA256 <fichier> doit redonner chaque empreinte ci-dessus.",
                "L'empreinte SHA256 de CE fichier est celle qui est horodatee dans le jeton .tsr du meme nom.",
                "Chaque manifeste liste a son tour l'empreinte de tous les fichiers de la collecte ou de l'analyse." });
            string dossier = collecte + "_scelles";
            Directory.CreateDirectory(dossier);
            r.Fichier = Path.Combine(dossier, "SCELLE_" + maintenant.ToString("yyyyMMdd_HHmmss") + ".txt");
            File.WriteAllText(r.Fichier, string.Join("\r\n", contenu.ToArray()) + "\r\n", new UTF8Encoding(false));
            r.Empreinte = Sha256(r.Fichier, null);
            return r;
        }

        // ------------------------------------------------------------------ RFC 3161
        static byte[] Der(byte tag, byte[] contenu)
        {
            int n = contenu.Length;
            byte[] l = n < 128 ? new[] { (byte)n } : n < 256 ? new byte[] { 0x81, (byte)n } : new byte[] { 0x82, (byte)(n >> 8), (byte)(n & 255) };
            return new[] { tag }.Concat(l).Concat(contenu).ToArray();
        }

        static int[] Entete(byte[] b, int i)
        {
            int l = b[i + 1], d = i + 2;
            if ((l & 0x80) != 0) { int k = l & 0x7F; l = 0; for (int j = 0; j < k; j++) l = l * 256 + b[d + j]; d += k; }
            return new[] { b[i], l, d };
        }

        static string Hex(byte[] b) { return BitConverter.ToString(b).Replace("-", ""); }

        public static void Horodater(ResultatScelle r, string url)
        {
            r.Horodateur = url;
            try
            {
                var empreinte = Enumerable.Range(0, 32).Select(i => Convert.ToByte(r.Empreinte.Substring(i * 2, 2), 16)).ToArray();
                var nonce = new byte[8];
                new RNGCryptoServiceProvider().GetBytes(nonce);
                nonce[0] = (byte)((nonce[0] & 0x7F) | 0x01);
                var algo = Der(0x30, new byte[] { 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00 });
                var imprint = Der(0x30, algo.Concat(Der(0x04, empreinte)).ToArray());
                var req = Der(0x30, new byte[] { 0x02, 0x01, 0x01 }.Concat(imprint).Concat(Der(0x02, nonce)).Concat(new byte[] { 0x01, 0x01, 0xFF }).ToArray());

                var w = (HttpWebRequest)WebRequest.Create(url);
                w.Method = "POST";
                w.ContentType = "application/timestamp-query";
                w.UserAgent = "DigSpill";
                w.Timeout = 20000;
                w.ContentLength = req.Length;
                using (var s = w.GetRequestStream()) s.Write(req, 0, req.Length);
                byte[] rep;
                using (var resp = w.GetResponse()) using (var s = resp.GetResponseStream()) using (var m = new MemoryStream()) { s.CopyTo(m); rep = m.ToArray(); }

                var e1 = Entete(rep, 0); var e2 = Entete(rep, e1[2]); var e3 = Entete(rep, e2[2]);
                int statut = e3[0] == 2 ? rep[e3[2]] : -1;
                if (statut != 0 && statut != 1) throw new Exception("réponse refusée par l'horodateur (statut " + statut + ")");
                string hx = Hex(rep);
                if (!hx.Contains(Hex(empreinte))) throw new Exception("le jeton ne contient pas l'empreinte demandée");
                if (!hx.Contains(Hex(nonce))) throw new Exception("le jeton ne reprend pas le nonce de la requête");
                for (int i = 0; i < rep.Length - 20; i++)
                {
                    if (rep[i] != 0x18 || rep[i + 1] < 15 || rep[i + 1] > 23) continue;
                    var t = Encoding.ASCII.GetString(rep, i + 2, rep[i + 1]);
                    var m = Regex.Match(t, @"^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\.\d+)?Z$");
                    if (m.Success) { r.DateJeton = string.Format("{0}-{1}-{2} {3}:{4}:{5} UTC", m.Groups[1], m.Groups[2], m.Groups[3], m.Groups[4], m.Groups[5], m.Groups[6]); break; }
                }
                File.WriteAllBytes(Path.ChangeExtension(r.Fichier, ".tsq"), req);
                File.WriteAllBytes(Path.ChangeExtension(r.Fichier, ".tsr"), rep);
                string baseNom = Path.GetFileNameWithoutExtension(r.Fichier);
                File.WriteAllText(Path.ChangeExtension(r.Fichier, ".horodatage.txt"),
                    "Horodateur : " + url + "\r\nDate du jeton : " + r.DateJeton + "\r\nEmpreinte horodatee : " + r.Empreinte + "\r\n" +
                    "Controle : openssl ts -reply -in " + baseNom + ".tsr -text\r\n" +
                    "Verification complete : openssl ts -verify -data " + baseNom + ".txt -in " + baseNom + ".tsr -CAfile <chaine de certificats de l'horodateur>\r\n",
                    new UTF8Encoding(false));
            }
            catch (Exception e) { r.ErreurHorodatage = e.Message; }
        }
    }
}
