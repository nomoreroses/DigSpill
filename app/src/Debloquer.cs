// DigSpill - retire la « marque du Web » (flux Zone.Identifier) des fichiers du kit.
// Un kit extrait d'un zip téléchargé avec un navigateur garde cette marque sur chaque fichier :
// Windows demande alors « Fichier ouvert - Avertissement de sécurité » à chaque lancement de
// Collecteur-Velociraptor.exe, de 7zr.exe ou de python.exe, et l'antivirus examine les scripts plus durement.
// Seuls le dossier moteur\ et les fichiers posés à côté de DigSpill.exe sont touchés : jamais un dossier Collecte.
using System;
using System.IO;
using System.Runtime.InteropServices;

namespace DigSpill
{
    static class Debloquer
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool DeleteFileW(string chemin);

        static readonly string[] Racine = { ".exe", ".bat", ".cmd" };
        static readonly string[] Extensions = { ".exe", ".dll", ".ps1", ".psm1", ".bat", ".cmd", ".pyd", ".py", ".js", ".html", ".zip" };

        /// <summary>Retire la marque sur le kit. Rend le nombre de fichiers débloqués ; jamais d'exception
        /// (clé en lecture seule, exFAT ou FAT32 sans flux : rien à faire).</summary>
        public static int Kit(string moteur)
        {
            int n = 0;
            try
            {
                if (string.IsNullOrEmpty(moteur) || !Directory.Exists(moteur)) return 0;
                var racine = Directory.GetParent(moteur.TrimEnd('\\'));
                if (racine != null)
                    foreach (var f in Directory.GetFiles(racine.FullName))
                        if (Array.IndexOf(Racine, Path.GetExtension(f).ToLowerInvariant()) >= 0) n += Un(f);
                foreach (var f in Directory.EnumerateFiles(moteur, "*", SearchOption.AllDirectories)) n += Un(f);
            }
            catch { }
            return n;
        }

        static int Un(string f)
        {
            if (Array.IndexOf(Extensions, Path.GetExtension(f).ToLowerInvariant()) < 0) return 0;
            try { return DeleteFileW(f + ":Zone.Identifier") ? 1 : 0; } catch { return 0; }
        }
    }
}
