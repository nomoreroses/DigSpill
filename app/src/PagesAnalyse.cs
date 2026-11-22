// DigSpill - parcours "Analyser" (sur le PC du technicien, jamais sur le poste suspect).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace DigSpill
{
    class PageSource : Page
    {
        static readonly Regex Motif = new Regex(@"^(?<poste>.+)_(?<d>\d{8})_(?<h>\d{6})(_leger)?$");
        readonly Carte collectes;
        readonly Champ travail, mdp1, mdp2;
        readonly Case copie, complete, internet, proteger;
        Action abonnement;
        string choisie;

        public PageSource(Fenetre f) : base(f)
        {
            Titre = "Analyser une collecte";
            SousTitre = "Sur votre PC, pas sur le poste suspect. Les preuves sont d'abord copiées et vérifiées : l'analyse travaille sur la copie.";
            Parcours = ParcoursAnalyse; Etape = 0;
            collectes = Corps.Ajouter(NouvelleCarte());

            var t = Corps.Ajouter(NouvelleCarte());
            t.Contenu.Ajouter(Intertitre("Dossier de travail"));
            t.Contenu.Ajouter(Paragraphe("Sur un disque de ce PC (chiffré de préférence). La copie, l'analyse et l'interface y sont écrites."));
            travail = t.Contenu.Ajouter(Champ.Texte("Dossier", Ctx.DossierTravail ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "DigSpill"), true));
            var rt = t.Contenu.Ajouter(new Rangee());
            var parc = new BoutonPlat("Choisir…", BoutonPlat.Genre.Secondaire, Ic.Dossier) { Margin = new Padding(0) };
            parc.Click += delegate
            {
                using (var d = new FolderBrowserDialog { Description = "Dossier de travail DigSpill", SelectedPath = travail.Valeur })
                    if (d.ShowDialog(F) == DialogResult.OK) travail.Valeur = d.SelectedPath;
            };
            rt.Controls.Add(parc);

            var o = Corps.Ajouter(NouvelleCarte());
            o.Contenu.Ajouter(Intertitre("Options"));
            o.Contenu.Espace = 8;
            copie = o.Contenu.Ajouter(new Case("Copie vérifiée des preuves avant l'analyse (SHA-256 de chaque fichier, PV de copie). Recommandé.", Ctx.CopieVerifiee));
            complete = o.Contenu.Ajouter(new Case("Analyse complète, avec la $MFT et la mémoire vive (plus longue)", Ctx.AnalyseComplete));
            internet = o.Contenu.Ajouter(new Case("Utiliser Internet : bases publiques à jour, symboles Windows pour la mémoire vive, horodatage du scellé (seules des empreintes sont envoyées)", Ctx.AvecInternet));
            proteger = o.Contenu.Ajouter(new Case("Protéger l'interface par un mot de passe (pour l'envoyer)", Ctx.Proteger));
            var g = o.Contenu.Ajouter(new Grille { Colonnes = 2 });
            g.Controls.Add(mdp1 = new Champ("Mot de passe", new TextBox { UseSystemPasswordChar = true }, true));
            g.Controls.Add(mdp2 = new Champ("Confirmer", new TextBox { UseSystemPasswordChar = true }, true));
            g.Visible = proteger.Checked;
            proteger.CheckedChanged += delegate { g.Visible = proteger.Checked; Ajuster(); };
        }

        public override IEnumerable<Control> Boutons()
        {
            var r = new BoutonPlat("Retour", BoutonPlat.Genre.Discret, Ic.Retour);
            r.Click += delegate { F.Aller(new PageAccueil(F)); };
            var p = new BoutonPlat("Autre dossier…", BoutonPlat.Genre.Secondaire, Ic.Dossier);
            p.Click += delegate
            {
                using (var d = new FolderBrowserDialog { Description = "Dossier d'une collecte (POSTE_AAAAMMJJ_HHMMSS)" })
                    if (d.ShowDialog(F) == DialogResult.OK)
                    {
                        if (!Motif.IsMatch(Path.GetFileName(d.SelectedPath.TrimEnd('\\'))))
                            MessageBox.Show(F, "Choisissez le dossier d'une collecte, nommé POSTE_AAAAMMJJ_HHMMSS.", "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Information);
                        else { choisie = d.SelectedPath.TrimEnd('\\'); Remplir(); }
                    }
            };
            var l = new BoutonPlat("Lancer l'analyse", BoutonPlat.Genre.Primaire, Ic.Lecture);
            l.Click += delegate { Lancer(); };
            return new Control[] { r, p, l };
        }

        public override void Affichee()
        {
            abonnement = () => { if (!IsDisposed) Remplir(); };
            F.SupportsChanges += abonnement;
            Remplir();
        }
        public override void Quittee() { if (abonnement != null) F.SupportsChanges -= abonnement; }

        List<string> Trouver()
        {
            if (Ctx.Demo) return new List<string> { @"F:\Collecte\SECRETARIAT-01_20261119_102233", @"F:\Collecte\ACCUEIL-02_20261119_113005_leger", @"F:\Collecte\SECRETARIAT-01_20261104_091512" };
            var l = new List<string>();
            var racines = new List<string> { Ctx.RacineCle, Ctx.RacineOutils };
            foreach (var d in DriveInfo.GetDrives()) { try { if (d.IsReady && (d.DriveType == DriveType.Removable || d.DriveType == DriveType.Fixed)) racines.Add(d.RootDirectory.FullName); } catch { } }
            foreach (var r in racines.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                try
                {
                    var c = Path.Combine(r, "Collecte");
                    if (!Directory.Exists(c)) continue;
                    l.AddRange(Directory.GetDirectories(c).Where(x => Motif.IsMatch(Path.GetFileName(x))));
                }
                catch { }
            }
            if (choisie != null && !l.Contains(choisie, StringComparer.OrdinalIgnoreCase)) l.Insert(0, choisie);
            return l.Distinct(StringComparer.OrdinalIgnoreCase).OrderByDescending(x => Motif.Match(Path.GetFileName(x)).Groups["d"].Value + Motif.Match(Path.GetFileName(x)).Groups["h"].Value).ToList();
        }

        void Remplir()
        {
            var l = Trouver();
            collectes.Contenu.Controls.Clear();
            collectes.Contenu.Ajouter(Intertitre("Collecte"));
            if (l.Count == 0) collectes.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "Aucune collecte trouvée", "Branchez la clé PREUVES (elle peut rester en lecture seule) ou choisissez un dossier avec « Autre dossier… »."));
            if (choisie == null && l.Count > 0) choisie = l[0];
            foreach (var x in l)
            {
                var m = Motif.Match(Path.GetFileName(x));
                string d = m.Groups["d"].Value, h = m.Groups["h"].Value;
                string quand = string.Format("{0}/{1}/{2} à {3}:{4}", d.Substring(6, 2), d.Substring(4, 2), d.Substring(0, 4), h.Substring(0, 2), h.Substring(2, 2));
                var b = new List<Tuple<string, Niveau>>();
                if (x.EndsWith("_leger")) b.Add(Tuple.Create("Collecte légère", Niveau.Info));
                bool ro = !Ctx.Demo && Supports.LectureSeule(Path.GetPathRoot(x));
                if (ro || Ctx.Demo) b.Add(Tuple.Create("Support en lecture seule", Niveau.Ok));
                if (Directory.Exists(x + "_scelles") || (Ctx.Demo && x.Contains("102233"))) b.Add(Tuple.Create("Scellé présent", Niveau.Ok));
                if (Directory.Exists(x + "_analyse")) b.Add(Tuple.Create("Déjà analysée", Niveau.Info));
                var c = new CarteSelection(Ic.Document, m.Groups["poste"].Value + "  ·  " + quand, x, b) { Valeur = x };
                c.Choix = string.Equals(x, choisie, StringComparison.OrdinalIgnoreCase);
                c.Choisie += (o, e) => { choisie = (string)((CarteSelection)o).Valeur; foreach (var y in collectes.Contenu.Controls.OfType<CarteSelection>()) y.Choix = y == o; };
                collectes.Contenu.Ajouter(c);
            }
            Ajuster();
        }

        void Lancer()
        {
            if (choisie == null) { MessageBox.Show(F, "Choisissez une collecte.", "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            if (travail.Valeur == "") { MessageBox.Show(F, "Indiquez un dossier de travail.", "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            if (proteger.Checked && (mdp1.Valeur.Length < 10 || mdp1.Valeur != mdp2.Valeur))
            { MessageBox.Show(F, "Mot de passe : 10 caractères minimum, identique dans les deux champs.", "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            if (!copie.Checked && !Ctx.Demo && Supports.LectureSeule(Path.GetPathRoot(choisie)))
            { MessageBox.Show(F, "La collecte est sur un support en lecture seule : l'analyse ne peut pas y écrire. Cochez la copie vérifiée.", "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            if (!Ctx.Demo && string.Equals(Path.GetPathRoot(choisie), Path.GetPathRoot(travail.Valeur), StringComparison.OrdinalIgnoreCase) && copie.Checked
                && MessageBox.Show(F, "Le dossier de travail est sur le même support que les preuves : la copie ne protège pas contre la perte du support.\r\n\r\nContinuer ?", "DigSpill", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            string err;
            if (!Ctx.Demo && !Supports.EssaiEcriture(travail.Valeur, out err)) { MessageBox.Show(F, "Impossible d'écrire dans " + travail.Valeur + " : " + err, "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Error); return; }
            Ctx.SourceCollecte = choisie; Ctx.DossierTravail = travail.Valeur;
            Ctx.CopieVerifiee = copie.Checked; Ctx.AnalyseComplete = complete.Checked; Ctx.AvecInternet = internet.Checked;
            Ctx.Proteger = proteger.Checked; Ctx.MotDePasse = proteger.Checked ? mdp1.Valeur : null;
            F.Aller(new PageAnalyse(F));
        }
    }

    class PageAnalyse : Page
    {
        readonly Barre barre = new Barre();
        readonly Label etat;
        readonly LigneInfo eCopie, eAna, eInt;
        readonly Journal journal = new Journal { Hauteur = 260 };
        Executeur exec;
        bool arret;

        public PageAnalyse(Fenetre f) : base(f)
        {
            Titre = "Analyse en cours";
            SousTitre = Path.GetFileName(Ctx.SourceCollecte ?? "") + " → " + Ctx.DossierTravail;
            Parcours = ParcoursAnalyse; Etape = 1;
            var c = Corps.Ajouter(NouvelleCarte());
            etat = c.Contenu.Ajouter(Mise.Texte("Préparation…", Theme.Police(12f, FontStyle.Bold), Theme.Encre));
            c.Contenu.Ajouter(barre);
            var e = Corps.Ajouter(NouvelleCarte());
            e.Contenu.Ajouter(Intertitre("Étapes"));
            eCopie = e.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "1. Copie vérifiée", "Chaque fichier copié est re-haché et comparé au manifeste de la collecte. PV de copie."));
            eAna = e.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "2. Analyse exfiltration", "Sessions, volumes envoyés (SRUM), exécutions, navigation, \\\\tsclient, $MFT, mémoire vive."));
            eInt = e.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "3. Interface et scellé", "Fichier HTML autonome, bases publiques, scellé horodaté, PV de collecte."));
            Corps.Ajouter(journal);
        }

        public override IEnumerable<Control> Boutons()
        {
            var a = new BoutonPlat("Arrêter", BoutonPlat.Genre.Secondaire, Ic.Arret);
            a.Click += delegate { arret = true; if (exec != null) exec.Tuer(); };
            return new Control[] { a };
        }

        public override void Affichee() { Demarrer(); }
        public override void Quittee() { if (Occupee && exec != null) { arret = true; exec.Tuer(); } }

        void Etat(string t, double v) { if (!IsDisposed) BeginInvoke(new Action(() => { etat.Text = t; if (v >= 0) barre.Valeur = v; else barre.Indeterminee = true; Ajuster(); })); }

        Task<int> Ps(string script, List<string> args, IDictionary<string, string> env, Action<string> suivi = null)
        {
            if (Ctx.Demo) return Simuler(script);
            exec = new Executeur();
            exec.Ligne += l => journal.Ajouter(l);
            if (suivi != null) exec.Ligne += suivi;
            journal.Ajouter("> " + script + " " + string.Join(" ", args.ToArray()));
            return exec.Lancer("powershell.exe", Executeur.ArgumentsPowerShell(Ctx.Script(script), args), Ctx.RacineOutils, Executeur.Console850(), env);
        }

        async Task<int> Simuler(string script)
        {
            var l = script.StartsWith("Copier") ? new[] { "Copie de 1 534 fichiers (3,4 Go)", "  verification 1000 / 1534", "Resultat : toutes les copies sont identiques aux originaux" }
                : script.StartsWith("Analyse") ? new[] { "[*] Sessions reconstituees", "[*] SRUM : volumes par application", "[*] Executions pendant les fenetres", "[*] Navigation", "[*] $MFT du conteneur", "[*] Memoire vive : processus et connexions" }
                : new[] { "  [+] bases publiques a jour", "  [+] scelle cree : SCELLE_20261119_183512", "  [+] scelle horodate par un tiers : 2026-11-19 17:35:13 UTC", "  Interface : SECRETARIAT-01_20261119_102233_INTERFACE.html" };
            foreach (var x in l) { await Task.Delay(700); journal.Ajouter(x); }
            return 0;
        }

        async void Demarrer()
        {
            try { await Derouler(); }
            catch (Exception ex) { journal.Ajouter("[!] " + ex); Fin(false); }
        }

        async Task Derouler()
        {
            Occupee = true;
            string nom = Path.GetFileName(Ctx.SourceCollecte);
            string parent = Path.GetDirectoryName(Ctx.SourceCollecte);
            string dossier = Path.Combine(Ctx.DossierTravail, nom);
            string analysee = Ctx.SourceCollecte;
            string tech = Ctx.Inter.Technicien;

            if (Ctx.CopieVerifiee)
            {
                eCopie.Etat(Niveau.EnCours);
                Etat("Copie vérifiée des preuves…", -1);
                var a = new List<string> { "-Source", Executeur.Echapper(parent), "-Destination", Executeur.Echapper(dossier), "-Collecte", Executeur.Echapper(nom) };
                if (tech != "") { a.Add("-Operateur"); a.Add(Executeur.Echapper(tech + " - " + Environment.UserDomainName + "\\" + Environment.UserName)); }
                // "  verification 200 / 420" : avancement de la copie verifiee
                var rxV = new System.Text.RegularExpressions.Regex(@"verification (\d+) / (\d+)");
                int c = await Ps("Copier-Preuves.ps1", a, null, l =>
                {
                    var m = rxV.Match(l);
                    if (m.Success) Etat("Copie vérifiée : " + m.Groups[1].Value + " / " + m.Groups[2].Value + " fichiers re-hachés…", 0.3 * int.Parse(m.Groups[1].Value) / Math.Max(1, int.Parse(m.Groups[2].Value)));
                });
                if (arret) { Fin(false); return; }
                analysee = Path.Combine(dossier, Path.GetFileName(parent), nom);
                eCopie.Definir(c == 0 ? Niveau.Ok : Niveau.Danger, "1. Copie vérifiée", c == 0 ? "Copie identique aux originaux : " + Path.Combine(dossier, Path.GetFileName(parent)) : (c == 2 ? "ANOMALIES : des fichiers diffèrent du manifeste. Voir hachages_*.csv avant toute conclusion." : "Copie en échec (code " + c + ")."));
                if (c != 0 && c != 2) { Fin(false); return; }
            }
            else eCopie.Definir(Niveau.Ignore, "1. Copie vérifiée", "Non demandée : l'analyse écrit à côté de la collecte d'origine.");

            eAna.Etat(Niveau.EnCours);
            Etat("Analyse exfiltration" + (Ctx.AnalyseComplete ? " (avec la $MFT et la mémoire vive : plusieurs minutes)" : "") + "…", -1);
            var aa = new List<string> { "-Collecte", Executeur.Echapper(analysee) };
            if (!Ctx.AnalyseComplete) { aa.Add("-SansMFT"); aa.Add("-SansRam"); }
            if (!Ctx.AvecInternet) aa.Add("-SansInternet");
            // "[*] Etape" : chaque etape de l'analyse fait avancer la barre (19 etapes environ)
            int etapes = 0;
            int ca = await Ps("Analyse-Exfil.ps1", aa, null, l =>
            {
                int i = l.IndexOf("[*] ", StringComparison.Ordinal);
                if (i < 0) return;
                etapes++;
                string nomEtape = l.Substring(i + 4);
                int par = nomEtape.IndexOf(" (", StringComparison.Ordinal);
                Etat("Analyse : " + (par > 0 ? nomEtape.Substring(0, par) : nomEtape) + "…", 0.3 + 0.6 * Math.Min(1.0, etapes / 19.0));
            });
            if (arret) { Fin(false); return; }
            bool synthese = Ctx.Demo || File.Exists(Path.Combine(analysee + "_analyse", "SYNTHESE_EXFILTRATION.txt"));
            Ctx.ProblemeAnalyse = synthese ? null : "L'analyse s'est arrêtée (code " + ca + ") sans écrire sa synthèse : l'interface montre la collecte brute, sans chronologie racontée, grille ni mémoire vive. Voir le journal de l'analyse.";
            eAna.Definir(!synthese ? Niveau.Danger : ca == 0 ? Niveau.Ok : Niveau.Attention, "2. Analyse exfiltration",
                !synthese ? "Analyse en échec (code " + ca + ") : voir le journal ci-dessous." : ca == 0 ? "Synthèse : " + nom + "_analyse\\SYNTHESE_EXFILTRATION.txt" : "Analyse terminée avec des erreurs (code " + ca + ") : voir analyse.log.");

            eInt.Etat(Niveau.EnCours);
            Etat("Interface, bases publiques et scellé…", -1);
            string bases = Path.Combine(Ctx.DossierTravail, "bases");
            if (!Ctx.Demo) PreparerBases(bases);
            var ai = new List<string> { "-Collecte", Executeur.Echapper(analysee), "-Bases", Executeur.Echapper(bases), "-SansOuvrir" };
            if (!Ctx.AvecInternet) ai.Add("-SansInternet");
            if (Ctx.Horodateur != "") { ai.Add("-Horodateur"); ai.Add(Executeur.Echapper(Ctx.Horodateur)); }
            Dictionary<string, string> env = null;
            if (Ctx.Proteger) { ai.Add("-Proteger"); env = new Dictionary<string, string> { { "DIGSPILL_MDP", Ctx.MotDePasse } }; }
            int ci = await Ps("Generer-Interface.ps1", ai, env);
            Ctx.MotDePasse = null;
            if (arret) { Fin(false); return; }
            Ctx.Interface = Ctx.Demo ? Path.Combine(dossier, "Collecte", nom + "_INTERFACE.html") : Path.Combine(Path.GetDirectoryName(analysee), nom + "_INTERFACE.html");
            bool ok = ci == 0 && (Ctx.Demo || File.Exists(Ctx.Interface));
            eInt.Definir(ok ? Niveau.Ok : Niveau.Danger, "3. Interface et scellé", ok ? Path.GetFileName(Ctx.Interface) : "Interface non générée (code " + ci + ") : voir le journal.");
            Fin(ok);
        }

        void PreparerBases(string bases)
        {
            try
            {
                Directory.CreateDirectory(bases);
                var src = Path.Combine(Ctx.RacineOutils, "outils", "bases");
                if (!Directory.Exists(src)) return;
                foreach (var f in Directory.GetFiles(src))
                {
                    var d = Path.Combine(bases, Path.GetFileName(f));
                    if (!File.Exists(d) || File.GetLastWriteTimeUtc(d) < File.GetLastWriteTimeUtc(f)) File.Copy(f, d, true);
                }
            }
            catch (Exception e) { journal.Ajouter("[!] bases publiques non copiées : " + e.Message); }
        }

        void Fin(bool ok)
        {
            Occupee = false;
            if (IsDisposed) return;
            barre.Valeur = 1;
            if (ok) { F.Aller(new PageRapport(F)); return; }
            etat.Text = arret ? "Analyse arrêtée" : "Analyse incomplète : voir le journal";
            Titre = "Analyse interrompue";
            F.MajEntete();
            Ajuster();
        }
    }

    class PageRapport : Page
    {
        public PageRapport(Fenetre f) : base(f)
        {
            Titre = Ctx.ProblemeAnalyse == null ? "Rapport prêt" : "Rapport partiel";
            SousTitre = "Un seul fichier HTML : il s'ouvre sur n'importe quel PC, sans installation ni Internet.";
            Parcours = ParcoursAnalyse; Etape = 2;
            if (Ctx.ProblemeAnalyse != null) Corps.Ajouter(NouvelleCarte()).Contenu.Ajouter(new LigneInfo(Niveau.Danger, "Analyse en échec", Ctx.ProblemeAnalyse));
            var c = Corps.Ajouter(NouvelleCarte());
            c.Couleurs(Theme.Panneau, Theme.Ligne);
            c.Contenu.Ajouter(Mise.Texte("INTERFACE", Theme.MonoMoyen(8.5f), Theme.Texte3));
            c.Contenu.Ajouter(Mise.Texte(Path.GetFileName(Ctx.Interface ?? ""), Theme.Police(14f, FontStyle.Bold), Theme.Texte));
            c.Contenu.Ajouter(Mise.Texte(Ctx.Interface ?? "", Theme.Mono(8.5f), Theme.Texte3));
            var a = Corps.Ajouter(NouvelleCarte());
            a.Contenu.Ajouter(Intertitre("Ensuite"));
            a.Contenu.Ajouter(new LigneInfo(Niveau.Info, "PV de collecte", "Dans l'interface : onglet Preuves › Rapports › « PV de collecte ». À imprimer et faire signer."));
            a.Contenu.Ajouter(new LigneInfo(Niveau.Info, "Rapports", "Onglet Preuves › Rapports : rapport praticien (1 page) et rapport technique sourcé, en PDF."));
            a.Contenu.Ajouter(new LigneInfo(Niveau.Attention, "Fichier sensible", "Il contient les traces du poste (comptes, chemins, sites). Pour l'envoyer : version protégée par mot de passe, mot de passe par un autre canal."));
        }

        public override IEnumerable<Control> Boutons()
        {
            var d = new BoutonPlat("Ouvrir le dossier", BoutonPlat.Genre.Secondaire, Ic.Dossier);
            d.Click += delegate { if (Ctx.Interface != null) Pages.OuvrirDossier(Path.GetDirectoryName(Ctx.Interface)); };
            var n = new BoutonPlat("Nouvelle analyse", BoutonPlat.Genre.Secondaire, Ic.Actualiser);
            n.Click += delegate { F.Aller(new PageSource(F)); };
            var o = new BoutonPlat("Ouvrir l'interface", BoutonPlat.Genre.Primaire, Ic.Lecture);
            o.Click += delegate { try { if (!Ctx.Demo) Process.Start(Ctx.Interface); } catch (Exception e) { MessageBox.Show(F, e.Message, "DigSpill"); } };
            return new Control[] { d, n, o };
        }
    }
}
