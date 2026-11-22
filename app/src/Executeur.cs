// DigSpill - lancement des scripts PowerShell et de Velociraptor, sortie lue ligne a ligne.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace DigSpill
{
    class Executeur
    {
        Process p;
        public event Action<string> Ligne;
        public bool Interrompu { get; private set; }

        public static string Echapper(string v)
        {
            // argument d'une ligne de commande Windows : guillemets doubles, sans guillemet interne
            v = (v ?? "").Replace("\"", "'").Replace("\r", " ").Replace("\n", " ");
            if (v.EndsWith("\\")) v += "\\";
            return "\"" + v + "\"";
        }

        public static string ArgumentsPowerShell(string script, IEnumerable<string> args)
        {
            return "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Echapper(script) + " " + string.Join(" ", args.ToArray());
        }

        public Task<int> Lancer(string fichier, string arguments, string dossier, Encoding encodage, IDictionary<string, string> env)
        {
            var psi = new ProcessStartInfo(fichier, arguments)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                RedirectStandardInput = true,
                WorkingDirectory = dossier ?? Environment.CurrentDirectory
            };
            if (encodage != null) { psi.StandardOutputEncoding = encodage; psi.StandardErrorEncoding = encodage; }
            if (env != null) foreach (var kv in env) psi.EnvironmentVariables[kv.Key] = kv.Value;
            p = new Process { StartInfo = psi, EnableRaisingEvents = true };
            var fin = new TaskCompletionSource<int>();
            var finSortie = new System.Threading.ManualResetEvent(false);
            var finErreurs = new System.Threading.ManualResetEvent(false);
            p.OutputDataReceived += (s, e) => { if (e.Data != null) Emettre(e.Data); else finSortie.Set(); };
            p.ErrorDataReceived += (s, e) => { if (e.Data != null) Emettre("[!] " + e.Data); else finErreurs.Set(); };
            // Pas de WaitForExit() sans delai : il attend aussi la fin des sorties, et un programme lance par le script
            // qui reste ouvert (ex. une console MMC) les garde ouvertes pour toujours. On laisse 10 s aux dernieres lignes.
            p.Exited += (s, e) =>
            {
                try
                {
                    p.WaitForExit(2000);
                    var t0 = DateTime.Now;
                    bool ok = finSortie.WaitOne(10000);
                    ok = finErreurs.WaitOne(Math.Max(0, 10000 - (int)(DateTime.Now - t0).TotalMilliseconds)) && ok;
                    if (!ok)
                        Emettre("[i] Un programme lancé par le script garde sa sortie ouverte : DigSpill passe à la suite.");
                    fin.TrySetResult(p.ExitCode);
                }
                catch { fin.TrySetResult(-1); }
            };
            p.Start();
            p.StandardInput.Close(); // aucun script ne doit attendre une saisie
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            return fin.Task;
        }

        [System.Runtime.InteropServices.DllImport("kernel32.dll")] static extern uint GetOEMCP();

        /// <summary>Page de code de la console Windows (850 en France) : celle de la sortie de powershell.exe redirigee.</summary>
        public static Encoding Console850()
        {
            try { return Encoding.GetEncoding((int)GetOEMCP()); }
            catch { try { return Encoding.GetEncoding(850); } catch { return Encoding.Default; } }
        }

        void Emettre(string l) { var a = Ligne; if (a != null) a(l); }

        /// <summary>Arrete le processus et tous ses enfants (winpmem, 7zr, Velociraptor...).</summary>
        public void Tuer()
        {
            Interrompu = true;
            try
            {
                if (p == null || p.HasExited) return;
                var k = Process.Start(new ProcessStartInfo("taskkill.exe", "/PID " + p.Id + " /T /F") { CreateNoWindow = true, UseShellExecute = false });
                if (k != null) k.WaitForExit(5000);
            }
            catch { try { p.Kill(); } catch { } }
        }
    }
}
