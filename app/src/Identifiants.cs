// DigSpill - cibles du gestionnaire d'identifiants Windows du compte de la session (noms de serveurs et de sites,
// jamais les mots de passe). Remplace LISTER_IDENTIFIANTS.bat : meme contenu, meme nom de fichier.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

namespace DigSpill
{
    static class Identifiants
    {
        /// <summary>Compte de la session, au format du .bat (pour le nom du fichier).</summary>
        public static string Compte { get { return Environment.UserName; } }

        /// <summary>cmdkey /list et vaultcmd, sans elevation : c'est le coffre de l'utilisateur de la session qui est lu.</summary>
        public static string Lister()
        {
            var sb = new StringBuilder();
            sb.AppendLine("Poste   : " + Environment.MachineName);
            sb.AppendLine("Compte  : " + Environment.UserDomainName + "\\" + Environment.UserName);
            sb.AppendLine("Date    : " + DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss"));
            sb.AppendLine("Outil   : DigSpill.exe " + Programme.VersionKit + " (avant élévation, dans la session de ce compte)");
            sb.AppendLine();
            sb.Append(Commande("cmdkey.exe", "/list"));
            sb.AppendLine();
            sb.AppendLine("### Coffre Web (vaultcmd)");
            sb.Append(Commande("vaultcmd.exe", "/listcreds:\"Web Credentials\" /all"));
            sb.Append(Commande("vaultcmd.exe", "/listcreds:\"Windows Credentials\" /all"));
            return sb.ToString();
        }

        static string Commande(string exe, string args)
        {
            try
            {
                var psi = new ProcessStartInfo(exe, args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Executeur.Console850(), StandardErrorEncoding = Executeur.Console850() };
                using (var p = Process.Start(psi))
                {
                    string o = p.StandardOutput.ReadToEnd(), e = p.StandardError.ReadToEnd();
                    p.WaitForExit(15000);
                    return o + e;
                }
            }
            catch (Exception ex) { return exe + " : " + ex.Message + Environment.NewLine; }
        }

        public static string NomFichier(string compte) { return "cmdkey_" + Environment.MachineName + "_" + Nettoyer(compte) + ".txt"; }

        static string Nettoyer(string s)
        {
            foreach (var c in Path.GetInvalidFileNameChars()) s = s.Replace(c, '_');
            return s;
        }

        /// <summary>Ecrit le fichier dans &lt;dossier Collecte&gt;\Identifiants (lu par Analyse-Exfil.ps1). Renvoie le chemin.</summary>
        public static string Ecrire(string dossierCollecteRacine, string texte, string compte)
        {
            var d = Path.Combine(dossierCollecteRacine, "Identifiants");
            Directory.CreateDirectory(d);
            var f = Path.Combine(d, NomFichier(compte));
            File.WriteAllText(f, texte, new UTF8Encoding(true));
            return f;
        }

        /// <summary>Dossiers Collecte des supports branches (hors cle OUTILS) : la ou ecrire les identifiants d'un autre compte.</summary>
        public static List<string> DossiersCollecte(string racineOutils)
        {
            string outils = Path.GetPathRoot(racineOutils) ?? "";
            var l = new List<string>();
            foreach (var d in DriveInfo.GetDrives())
            {
                try
                {
                    if (!d.IsReady || (d.DriveType != DriveType.Removable && d.DriveType != DriveType.Fixed)) continue;
                    if (string.Equals(d.RootDirectory.FullName, outils, StringComparison.OrdinalIgnoreCase)) continue;
                    var c = Path.Combine(d.RootDirectory.FullName, "Collecte");
                    if (Directory.Exists(c)) l.Add(c);
                }
                catch { }
            }
            return l;
        }

        public static string VersBase64(string s) { return Convert.ToBase64String(Encoding.UTF8.GetBytes(s ?? "")); }
        public static string DepuisBase64(string s) { try { return Encoding.UTF8.GetString(Convert.FromBase64String(s)); } catch { return null; } }
    }
}
