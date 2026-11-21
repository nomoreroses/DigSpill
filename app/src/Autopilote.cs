// DigSpill - pilote automatique pour le test de bout en bout sur un vrai Windows.
// DigSpill.exe --auto=<dossier> [--auto-preuves=R:] [--auto-travail=C:\travail]
// Il clique dans les vraies pages, comme un technicien : vraie collecte, vraie analyse, vraie interface.
// Il ne remplit aucune donnee : seuls les champs de l'intervention sont saisis, comme le ferait le technicien.
// Une capture de chaque page et un journal (auto.log) sont ecrits dans <dossier>.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace DigSpill
{
    class Autopilote
    {
        readonly Fenetre f;
        readonly string dossier, preuves;
        readonly Timer horloge = new Timer { Interval = 1000 };
        Page vue;
        DateTime depuis;
        readonly HashSet<string> faits = new HashSet<string>();
        int numero, phase;   // phase 0 : collecte sur le poste ; phase 1 : analyse au bureau
        DateTime derniereCapture;
        bool ejectionTentee;
        Journal journalVu; string nomJournal;

        public Autopilote(Fenetre fenetre, string dossier, string preuves, string travail)
        {
            f = fenetre; this.dossier = dossier; this.preuves = (preuves ?? "").TrimEnd('\\');
            Directory.CreateDirectory(dossier);
            var c = f.Ctx;
            // saisie du technicien sur la page Intervention
            c.Inter.Prenom = "Recette"; c.Inter.Nom = "GitHub"; c.Inter.Societe = "Test de bout en bout";
            c.Inter.Cabinet = "Poste de test GitHub"; c.Inter.Present = "Aucune (test automatique)";
            c.Inter.Motif = "Intrusion ou prise en main à distance"; c.Inter.Ticket = "RECETTE";
            c.Inter.Horodater = true;
            if (!string.IsNullOrEmpty(travail)) c.DossierTravail = travail;
            Log("Pilote automatique : captures dans " + dossier + " ; clé PREUVES " + this.preuves + " ; dossier de travail " + c.DossierTravail);
            horloge.Tick += delegate { try { Tic(); } catch (Exception e) { Log("[!] " + e); Quitter(9); } };
            f.Shown += delegate { horloge.Start(); };
        }

        void Log(string m)
        {
            string l = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + m;
            try { File.AppendAllText(Path.Combine(dossier, "auto.log"), l + "\r\n", Encoding.UTF8); } catch { }
        }

        void Capturer(string nom)
        {
            numero++;
            string chemin = Path.Combine(dossier, string.Format("{0:00}_{1}.png", numero, nom));
            try
            {
                using (var bmp = new Bitmap(f.Width, f.Height))
                {
                    f.DrawToBitmap(bmp, new Rectangle(0, 0, f.Width, f.Height));
                    bmp.Save(chemin, ImageFormat.Png);
                }
                Log("capture " + Path.GetFileName(chemin) + " : « " + (f.Courante != null ? f.Courante.Titre : "") + " »");
            }
            catch (Exception e) { Log("[!] capture " + nom + " : " + e.Message); }
            derniereCapture = DateTime.Now;
        }

        /// <summary>Journal affiche par la page (sorties des scripts et de Velociraptor), ecrit a cote des captures.</summary>
        void SauverJournal()
        {
            if (journalVu == null) return;
            try { File.WriteAllText(Path.Combine(dossier, "journal_" + nomJournal + ".txt"), journalVu.Tout(), Encoding.UTF8); } catch { }
            journalVu = null;
        }

        void Quitter(int code)
        {
            horloge.Stop();
            SauverJournal();
            Log("fin du pilote automatique, code " + code);
            File.WriteAllText(Path.Combine(dossier, "auto_code.txt"), code.ToString());
            Environment.Exit(code);
        }

        bool UneFois(string cle) { return faits.Add(phase + ":" + cle); }

        // ------------------------------------------------------------------ recherche et clic dans les vrais controles
        static IEnumerable<Control> Tous(Control racine)
        {
            foreach (Control c in racine.Controls)
            {
                yield return c;
                foreach (var x in Tous(c)) yield return x;
            }
        }

        BoutonPlat Bouton(string debutTexte)
        {
            return f.BoutonsPied.OfType<BoutonPlat>().FirstOrDefault(b => b.Text.StartsWith(debutTexte, StringComparison.OrdinalIgnoreCase));
        }

        static readonly MethodInfo SurClic = typeof(Control).GetMethod("OnClick", BindingFlags.Instance | BindingFlags.NonPublic);
        void Cliquer(Control c, string quoi)
        {
            Log("clic : " + quoi);
            SurClic.Invoke(c, new object[] { EventArgs.Empty });
        }

        bool CliquerBouton(string texte)
        {
            var b = Bouton(texte);
            if (b == null || !b.Enabled) return false;
            Cliquer(b, "bouton « " + b.Text + " »");
            return true;
        }

        // ------------------------------------------------------------------ boites de dialogue Windows (MessageBox)
        delegate bool EnumProc(IntPtr h, IntPtr p);
        [DllImport("user32.dll")] static extern bool EnumThreadWindows(uint thread, EnumProc proc, IntPtr p);
        [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc proc, IntPtr p);
        [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);

        [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
        const uint BM_CLICK = 0x00F5;

        /// <summary>Boite de dialogue Windows ouverte par DigSpill : texte et boutons (null si aucune).</summary>
        string Dialogue(out Dictionary<string, IntPtr> boutons)
        {
            string texte = null;
            var bt = new Dictionary<string, IntPtr>();
            EnumThreadWindows(GetCurrentThreadId(), (h, p) =>
            {
                var cl = new StringBuilder(64); GetClassName(h, cl, 64);
                if (cl.ToString() != "#32770" || !IsWindowVisible(h)) return true;
                var sb = new StringBuilder();
                var t = new StringBuilder(512); GetWindowText(h, t, 512); sb.Append(t).Append(" : ");
                EnumChildWindows(h, (c, q) =>
                {
                    var cc = new StringBuilder(64); GetClassName(c, cc, 64);
                    var s = new StringBuilder(2048); GetWindowText(c, s, 2048);
                    if (cc.ToString() == "Static") sb.Append(s).Append(' ');
                    else if (cc.ToString() == "Button") bt[s.ToString().Replace("&", "")] = c;
                    return true;
                }, IntPtr.Zero);
                texte = sb.ToString().Trim();
                return false;
            }, IntPtr.Zero);
            boutons = bt;
            return texte;
        }

        // ------------------------------------------------------------------ le parcours
        void Tic()
        {
            Dictionary<string, IntPtr> bt;
            var d = Dialogue(out bt);
            if (d != null)
            {
                // seules les boites prevues dans le parcours reel ont une reponse ; les autres arretent le test
                if (d.Contains("forcer l'éjection") && bt.ContainsKey("Oui") && UneFois("forcer")) { Log("boîte de dialogue : " + d + " -> Oui"); Capturer("ejection_forcer"); PostMessage(bt["Oui"], BM_CLICK, IntPtr.Zero, IntPtr.Zero); return; }
                if (d.Contains("Éjection impossible") && bt.ContainsKey("OK") && UneFois("ejection_impossible")) { Log("[!] boîte de dialogue : " + d + " -> OK"); Capturer("ejection_impossible"); PostMessage(bt["OK"], BM_CLICK, IntPtr.Zero, IntPtr.Zero); ejectionTentee = true; return; }
                if (faits.Contains(phase + ":forcer") || faits.Contains(phase + ":ejection_impossible")) return; // reponse envoyee, la boite se ferme
                Log("[!] boîte de dialogue inattendue : " + d); Capturer("dialogue"); Quitter(6); return;
            }

            var p = f.Courante;
            if (p == null) return;
            if (!ReferenceEquals(p, vue))
            {
                SauverJournal();
                vue = p; depuis = DateTime.Now; Log("page " + p.GetType().Name + " : « " + p.Titre + " »");
                journalVu = Tous(p).OfType<Journal>().FirstOrDefault(); nomJournal = p.GetType().Name;
            }
            double age = (DateTime.Now - depuis).TotalSeconds;
            if (age < 2) return;

            switch (p.GetType().Name)
            {
                case "PageAccueil":
                    if (UneFois("accueil")) Capturer(phase == 0 ? "accueil" : "accueil_bureau");
                    var carte = Tous(p).OfType<CarteChoix>().FirstOrDefault(x => x.AccessibleName == (phase == 0 ? "Collecter sur ce poste" : "Analyser une collecte"));
                    if (carte != null && UneFois("carte")) Cliquer(carte, "carte « " + carte.AccessibleName + " »");
                    break;

                case "PageIntervention":
                    if (UneFois("intervention")) { Capturer("intervention"); CliquerBouton("Suivant"); }
                    break;

                case "PageFeuVert":
                    var suivant = Bouton("Suivant");
                    if (suivant == null || p.Occupee || f.Ctx.FeuVert == null) { if (age > 600) { Capturer("feu_vert_bloque"); Quitter(7); } break; }
                    if (!suivant.Enabled)
                    {
                        var malgre = Tous(p).OfType<Case>().FirstOrDefault(x => x.Text.StartsWith("Je continue malgré"));
                        if (malgre != null && malgre.Visible && !malgre.Checked && UneFois("malgre")) { Capturer("feu_vert_danger"); Log("feu vert en DANGER : case « je continue malgré le danger » cochée"); malgre.Checked = true; }
                        break;
                    }
                    if (UneFois("feuvert")) { Capturer("feu_vert"); CliquerBouton("Suivant"); }
                    break;

                case "PageSupport":
                    if (age < 3) break;
                    var cartes = Tous(p).OfType<CarteSelection>().ToList();
                    var cible = cartes.FirstOrDefault(x => x.Valeur is Support && string.Equals(((Support)x.Valeur).Lettre, preuves, StringComparison.OrdinalIgnoreCase));
                    if (cible == null) { if (age > 120) { Log("[!] clé PREUVES " + preuves + " absente de la liste : " + string.Join(", ", cartes.Select(x => x.AccessibleName).ToArray())); Capturer("cle_absente"); Quitter(8); } break; }
                    if (UneFois("support")) { Cliquer(cible, "support « " + cible.AccessibleName + " »"); break; }
                    if (UneFois("lancer")) { Capturer("cle_preuves"); CliquerBouton("Lancer la collecte"); }
                    break;

                case "PageCollecte":
                    if (p.Titre.StartsWith("Collecte interrompue")) { Capturer("collecte_interrompue"); Quitter(3); break; }
                    if (age > 8 && UneFois("collecte_debut")) Capturer("collecte");
                    else if ((DateTime.Now - derniereCapture).TotalMinutes >= 4) Capturer("collecte_suite");
                    break;

                case "PageAlerte":
                    Capturer("alerte"); Quitter(4);
                    break;

                case "PageFin":
                    if (age < 3) break;
                    if (UneFois("fin"))
                    {
                        Capturer("fin_collecte");
                        Log("collecte : " + f.Ctx.NomCollecte + " ; scellé " + (f.Ctx.Scelle != null ? f.Ctx.Scelle.Empreinte + " (" + f.Ctx.Scelle.NombreElements + " fichiers, horodatage : " + (f.Ctx.Scelle.DateJeton ?? f.Ctx.Scelle.ErreurHorodatage) + ")" : "aucun"));
                        CliquerBouton("Éjecter");
                        break;
                    }
                    if (p.Titre.StartsWith("Clé PREUVES éjectée") && UneFois("ejectee")) { Capturer("cle_ejectee"); ejectionTentee = true; Log("clé éjectée : en attente qu'elle soit rebranchée au bureau"); }
                    if (!ejectionTentee) { if (age > 120) { Log("[!] éjection sans réponse"); ejectionTentee = true; } break; }
                    // au bureau : la clé PREUVES est rebranchée, le technicien relance DigSpill et choisit « Analyser une collecte »
                    if (Directory.Exists(preuves + "\\Collecte"))
                    {
                        Log("clé PREUVES de nouveau visible : " + preuves);
                        phase = 1;
                        f.Aller(new PageAccueil(f));
                    }
                    else if (age > 600) { Log("[!] clé PREUVES pas rebranchée"); Quitter(10); }
                    break;

                case "PageSource":
                    if (age < 4) break;
                    if (UneFois("source")) { Capturer("analyser"); CliquerBouton("Lancer l'analyse"); }
                    break;

                case "PageAnalyse":
                    if (p.Titre.StartsWith("Analyse interrompue")) { Capturer("analyse_interrompue"); Quitter(5); break; }
                    if (age > 8 && UneFois("analyse_debut")) Capturer("analyse");
                    else if ((DateTime.Now - derniereCapture).TotalMinutes >= 4) Capturer("analyse_suite");
                    break;

                case "PageRapport":
                    if (UneFois("rapport"))
                    {
                        Capturer("rapport");
                        File.WriteAllText(Path.Combine(dossier, "interface.txt"), f.Ctx.Interface ?? "", Encoding.UTF8);
                        Log("interface : " + f.Ctx.Interface);
                        Quitter(0);
                    }
                    break;
            }
        }
    }
}
