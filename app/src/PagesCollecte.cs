// DigSpill - accueil et parcours "Collecter" (sur le poste suspect).
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace DigSpill
{
    static class Pages
    {
        public static Page Depart(Fenetre f, string nom)
        {
            var c = f.Ctx;
            if (c.Demo && nom != "accueil" && nom != "collecter" && nom != "intervention" && nom != "analyser") RemplirDemo(c);
            switch (nom)
            {
                case "collecter": case "intervention": return new PageIntervention(f);
                case "feuvert": return new PageFeuVert(f);
                case "support": return new PageSupport(f);
                case "collecte": return new PageCollecte(f);
                case "fin": return new PageFin(f);
                case "alerte":
                    c.RaisonAlerte = "Fichier-appât modifié : !!!_0_Dossiers_patients_" + DateTime.Now.Year + ".xlsx";
                    c.ActionsUrgence = new List<string> { "Collecte arrêtée (PowerShell et ses programmes)", "Écriture bloquée sur le disque (lecture seule)", "Volume démonté de force (un autre programme l'utilisait)", "Lettre F: retirée : le support n'est plus visible des programmes" };
                    return new PageAlerte(f);
                case "analyser": return new PageSource(f);
                case "maj": return new PageMiseAJour(f);
                case "analyse": return new PageAnalyse(f);
                case "rapport": c.Interface = @"D:\DigSpill\SECRETARIAT-01_20261119_102233\Collecte\SECRETARIAT-01_20261119_102233_INTERFACE.html"; return new PageRapport(f);
                default: return new PageAccueil(f);
            }
        }

        public static void RemplirDemo(Contexte c)
        {
            var i = c.Inter;
            if (i.Nom == "") { i.Prenom = "Camille"; i.Nom = "Martin"; i.Societe = "MSP Démo"; }
            i.Cabinet = "Cabinet dentaire des Lilas (démo)"; i.Present = "Dr Durand, praticienne"; i.Ticket = "T-2026-1142"; i.Motif = "Rançongiciel ou chiffrement";
            c.Destination = new Support { Lettre = "F:", Etiquette = "PREUVES", Systeme = "exFAT", Libre = 241L << 30, Total = 256L << 30, Usb = true, Amovible = true };
            c.DossierCollecteRacine = @"F:\Collecte";
            c.NomCollecte = "SECRETARIAT-01_20261119_102233";
            c.Debut = DateTime.Now.AddMinutes(-27); c.Fin = DateTime.Now;
            c.Scelle = new ResultatScelle { Empreinte = "5B91D6E85BF65927B88091D9DE43ED0290E97854776E2F8E2E1DDFCA20695B3F", NombreElements = 4, Fichier = @"F:\Collecte\SECRETARIAT-01_20261119_102233_scelles\SCELLE_20261119_105012.txt", ErreurHorodatage = "poste isolé du réseau" };
            c.CollecteOk = true;
            c.SourceCollecte = @"F:\Collecte\SECRETARIAT-01_20261119_102233";
            c.DossierTravail = @"D:\DigSpill";
        }

        public static string Duree(TimeSpan t) { return t.TotalHours >= 1 ? string.Format("{0} h {1:00} min", (int)t.TotalHours, t.Minutes) : string.Format("{0} min {1:00} s", (int)t.TotalMinutes, t.Seconds); }

        public static void OuvrirDossier(string chemin)
        {
            try { Process.Start("explorer.exe", "\"" + chemin + "\""); } catch { }
        }

        /// <summary>Rapport dans sa propre fenetre, sans onglets ni barre d'adresse (Edge en mode application, present sur Windows 10 et 11).
        /// Sans Edge : le navigateur par defaut.</summary>
        public static void OuvrirRapport(string chemin, bool navigateur)
        {
            if (!navigateur)
            {
                foreach (var pf in new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) })
                {
                    if (string.IsNullOrEmpty(pf)) continue;
                    var edge = Path.Combine(pf, @"Microsoft\Edge\Application\msedge.exe");
                    if (!File.Exists(edge)) continue;
                    try
                    {
                        Process.Start(new ProcessStartInfo(edge, "--app=\"" + new Uri(chemin).AbsoluteUri + "\" --window-size=1440,900 --no-first-run") { UseShellExecute = false });
                        return;
                    }
                    catch { }
                }
            }
            Process.Start(chemin);
        }
    }

    /// <summary>Carte selectionnable (support de preuves, collecte a analyser).</summary>
    class CarteSelection : Control, IHauteur
    {
        readonly string icone, titre, detail;
        readonly List<Tuple<string, Niveau>> badges;
        bool choisie, survol;
        public object Valeur;
        public bool Utilisable = true;
        readonly Font fI = Theme.Icones(16f), fT = Theme.Police(11.5f, FontStyle.Bold), fD = Theme.Police(9.5f), fB = Theme.Police(8.5f, FontStyle.Bold);
        public event EventHandler Choisie;

        public CarteSelection(string icone, string titre, string detail, List<Tuple<string, Niveau>> badges)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            this.icone = icone; this.titre = titre; this.detail = detail; this.badges = badges ?? new List<Tuple<string, Niveau>>();
            Cursor = Cursors.Hand; TabStop = true;
            AccessibleName = titre; AccessibleDescription = detail; AccessibleRole = AccessibleRole.RadioButton;
        }
        public bool Choix { get { return choisie; } set { choisie = value; Invalidate(); } }
        public int HauteurPour(int largeur) { return 24 + 26 + Mise.HauteurTexte(detail, fD, largeur - 120) + (badges.Count > 0 ? 34 : 0) + 6; }
        protected override void OnMouseEnter(EventArgs e) { survol = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { survol = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnClick(EventArgs e) { base.OnClick(e); if (!Utilisable) return; var a = Choisie; if (a != null) a(this, EventArgs.Empty); }
        protected override void OnKeyDown(KeyEventArgs e) { if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) OnClick(EventArgs.Empty); base.OnKeyDown(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Carte.FondDe(Parent));
            Theme.Qualite(g);
            var r = new RectangleF(1, 1, Width - 3, Height - 3);
            Color fond = choisie ? Theme.Panneau2 : (survol && Utilisable ? Theme.Panneau2 : Theme.Panneau);
            using (var p = Theme.Arrondi(r, 10))
            using (var b = new SolidBrush(fond))
            using (var pen = new Pen(choisie ? Theme.Texte : survol ? Theme.Ligne2 : Theme.Ligne, choisie ? 1.5f : 1f))
            { g.FillPath(b, p); g.DrawPath(pen, p); }
            // bouton radio
            var rd = new Rectangle(18, 22, 20, 20);
            using (var pen = new Pen(choisie ? Theme.Texte : Theme.Texte3, 1.5f)) g.DrawEllipse(pen, rd);
            if (choisie) using (var b = new SolidBrush(Theme.Texte)) g.FillEllipse(b, rd.X + 5, rd.Y + 5, 10, 10);
            TextRenderer.DrawText(g, icone, fI, new Rectangle(50, 14, 36, 36), Utilisable ? Theme.Texte : Theme.Texte3, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            int x = 96, w = Width - x - 20;
            TextRenderer.DrawText(g, titre, fT, new Rectangle(x, 14, w, 26), Utilisable ? Theme.Encre : Theme.Doux, TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
            int hd = Mise.HauteurTexte(detail, fD, w);
            TextRenderer.DrawText(g, detail, fD, new Rectangle(x, 42, w, hd + 2), Theme.Doux, Mise.Flux);
            int bx = x, by = 46 + hd + 4;
            foreach (var bd in badges)
            {
                var s = TextRenderer.MeasureText(bd.Item1, fB);
                var br = new RectangleF(bx, by, s.Width + 18, 24);
                using (var p = Theme.Arrondi(br, 12)) using (var b = new SolidBrush(Niveaux.Fond(bd.Item2))) g.FillPath(b, p);
                TextRenderer.DrawText(g, bd.Item1, fB, Rectangle.Round(br), Niveaux.Couleur(bd.Item2), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                bx += (int)br.Width + 8;
            }
        }
    }

    // ====================================================================== accueil
    class PageAccueil : Page
    {
        public PageAccueil(Fenetre f) : base(f)
        {
            Titre = "Que voulez-vous faire ?";
            SousTitre = "Collecter les traces d'un poste suspect, ou analyser une collecte.";
            Details = "DigSpill collecte les traces d'un poste Windows suspect sans les modifier, les scelle, puis produit le rapport sur un autre PC.";
            var g = Corps.Ajouter(new Grille { Colonnes = 2, Espace = 20 });
            var col = new CarteChoix(Ic.Collecter, "Collecter sur ce poste", "Chez le client, sur le poste suspect. Rien n'est modifié, tout est scellé.", Theme.RougeTexte,
                Tuple.Create("Poste suspect", Niveau.Attente), Tuple.Create("Droits administrateur", Niveau.Attention));
            var ana = new CarteChoix(Ic.Analyser, "Analyser une collecte", "Au bureau, sur votre PC. Rapport, PV de collecte et rapport client.", Theme.Bleu,
                Tuple.Create("Votre PC", Niveau.Attente), Tuple.Create("Sans droits administrateur", Niveau.Attente));
            g.Controls.Add(col); g.Controls.Add(ana);
            col.Click += delegate { Collecter(); };
            ana.Click += delegate { F.Aller(new PageSource(F)); };
            var l = Corps.Ajouter(Mise.Lien("ⓘ  Pourquoi deux clés (OUTILS et PREUVES) ?", () => Boite.Informer(F, Niveau.Info, "Deux clés, c'est plus sûr",
                "Clé OUTILS : DigSpill et ses scripts. Clé à interrupteur, en position lecture seule : rien ne peut la modifier.\r\n\r\n" +
                "Clé PREUVES : chiffrée, branchée seulement après le feu vert, surveillée pendant la collecte, passée en lecture seule ensuite.\r\n\r\n" +
                "Une seule clé ? Possible : DigSpill pose quand même ses fichiers-appâts et coupe la clé au moindre signe de chiffrement.")));
            l.Margin = new Padding(4, 4, 0, 0);
        }

        public override IEnumerable<Control> Boutons()
        {
            var b = new BoutonPlat("Identifiants de ce compte", BoutonPlat.Genre.Secondaire, Ic.Personne);
            b.Click += delegate { ListerIdentifiants(); };
            // au bureau : DigSpill va sur Internet (jamais au demarrage, pour ne rien envoyer depuis un poste examine)
            var m = new BoutonPlat("Mises à jour", BoutonPlat.Genre.Secondaire, Ic.Actualiser) { Pastille = F.MiseAJourDispo != null ? 1 : 0 };
            if (F.MiseAJourDispo != null) m.AccessibleName = "Mises à jour : " + F.MiseAJourDispo.Tag + " disponible";
            m.Click += delegate { F.Aller(new PageMiseAJour(F)); };
            return new Control[] { m, b };
        }

        /// <summary>Pour les autres comptes du poste : ouvrir leur session, lancer DigSpill.exe, ce bouton.</summary>
        void ListerIdentifiants()
        {
            if (Ctx.Demo) { Boite.Informer(F, Niveau.Info, "Démonstration", "En vrai, les cibles du gestionnaire d'identifiants de " + Identifiants.Compte + " seraient écrites dans F:\\Collecte\\Identifiants."); return; }
            var dossiers = Identifiants.DossiersCollecte(Ctx.RacineOutils);
            string cible = null;
            if (dossiers.Count == 1) cible = dossiers[0];
            else
            {
                using (var fb = new FolderBrowserDialog { Description = "Dossier Collecte de la clé PREUVES (là où la collecte de ce poste a été écrite)", ShowNewFolderButton = false })
                {
                    if (dossiers.Count > 0) fb.SelectedPath = dossiers[0];
                    if (fb.ShowDialog(F) != DialogResult.OK) return;
                    cible = fb.SelectedPath;
                }
            }
            try
            {
                var f = Identifiants.Ecrire(cible, Identifiants.Lister(), Identifiants.Compte);
                Boite.Informer(F, Niveau.Ok, "Identifiants de " + Identifiants.Compte + " enregistrés", "Écrits dans " + f + ".\r\n\r\nÀ refaire dans la session de chaque autre compte du poste.");
            }
            catch (Exception ex) { Boite.Informer(F, Niveau.Danger, "Écriture impossible", cible + " : " + ex.Message); }
        }

        void Collecter()
        {
            // les identifiants se lisent dans la session de l'utilisateur, SANS elevation : on les lit maintenant
            if (!Ctx.Demo && Ctx.IdentifiantsSession == null) { Ctx.IdentifiantsSession = Identifiants.Lister(); Ctx.CompteSession = Identifiants.Compte; }
            if (!Ctx.Demo && !Supports.EstAdmin())
            {
                string texte = Ctx.IdentifiantsSession.Length > 18000 ? Ctx.IdentifiantsSession.Substring(0, 18000) + "\r\n[tronqué]" : Ctx.IdentifiantsSession;
                try { Programme.Relancer("--collecter --identifiants=" + Identifiants.VersBase64(texte) + " --compte=" + Executeur.Echapper(Ctx.CompteSession), true); Application.Exit(); }
                catch (Win32Exception) { Boite.Informer(F, Niveau.Info, "Droits administrateur nécessaires", "Pour collecter, acceptez la demande de Windows « Autoriser cette application à apporter des modifications »."); }
                return;
            }
            F.Aller(new PageIntervention(F));
        }
    }

    // ====================================================================== 1. intervention
    class PageIntervention : Page
    {
        readonly Champ prenom, nom, societe, cabinet, present, ticket, motif, decouverte;
        readonly Choix complete, legere;
        readonly Case surPlace, horodater;

        public PageIntervention(Fenetre f) : base(f)
        {
            Titre = "Intervention";
            SousTitre = "Qui intervient, chez qui et pourquoi. Ne branchez pas encore la clé PREUVES.";
            Details = "Ces informations vont dans infos_collecte.txt, dans le scellé et dans le PV de collecte.";
            Parcours = ParcoursCollecte; Etape = 0;
            var i = Ctx.Inter;

            var c1 = Corps.Ajouter(NouvelleCarte());
            c1.Contenu.Ajouter(Intertitre("Technicien"));
            var g1 = c1.Contenu.Ajouter(new Grille { Colonnes = 3 });
            g1.Controls.Add(prenom = Champ.Texte("Prénom", i.Prenom, true));
            g1.Controls.Add(nom = Champ.Texte("Nom", i.Nom, true));
            g1.Controls.Add(societe = Champ.Texte("Société", i.Societe, false));

            var c2 = Corps.Ajouter(NouvelleCarte());
            c2.Contenu.Ajouter(Intertitre("Client"));
            var g2 = c2.Contenu.Ajouter(new Grille { Colonnes = 2 });
            g2.Controls.Add(cabinet = Champ.Texte("Cabinet ou structure", i.Cabinet, true));
            g2.Controls.Add(present = Champ.Texte("Personne présente (nom, qualité)", i.Present, false));
            var cb = new ListeSombre();
            cb.Items.AddRange(new object[] { "Rançongiciel ou chiffrement", "Intrusion ou prise en main à distance", "Fuite de données suspectée", "Comportement anormal du poste", "Autre" });
            cb.SelectedIndex = Math.Max(0, cb.Items.IndexOf(i.Motif));
            g2.Controls.Add(motif = new Champ("Motif", cb, false));
            g2.Controls.Add(ticket = Champ.Texte("N° de ticket", i.Ticket, false));
            // champ texte plutot qu'un calendrier Windows (clair, impossible a passer en noir) : JJ/MM/AAAA HH:MM, vide si inconnue
            var dtp = new TextBox { Text = i.Decouverte.HasValue ? i.Decouverte.Value.ToString("dd/MM/yyyy HH:mm") : "" };
            g2.Controls.Add(decouverte = new Champ("Découverte de l'incident (JJ/MM/AAAA HH:MM, si connue)", dtp, false));
            var poste = Mise.Texte("Poste examiné : " + Environment.MachineName + "   ·   " + DateTime.Now.ToString("dddd d MMMM yyyy, HH:mm"), Theme.Police(9.5f), Theme.Doux);
            g2.Controls.Add(poste);

            var c3 = Corps.Ajouter(NouvelleCarte());
            c3.Contenu.Ajouter(Intertitre("Collecte"));
            c3.Contenu.Espace = 8;
            c3.Contenu.Ajouter(complete = new Choix("Complète : poste suspect (mémoire vive, journaux, $MFT, Velociraptor). 20 à 60 min.", !i.Legere));
            c3.Contenu.Ajouter(legere = new Choix("Légère : autres postes du réseau (connexions, exécutions, identifiants). 5 à 15 min.", i.Legere));
            c3.Contenu.Ajouter(surPlace = new Case("Analyse rapide sur place (ajoute 5 à 20 min). Sinon : au bureau, avec DigSpill → Analyser.", i.AnalyseSurPlace));
            c3.Contenu.Ajouter(horodater = new Case("Horodater le scellé si Internet est disponible (seule l'empreinte est envoyée)", i.Horodater));
        }

        public override IEnumerable<Control> Boutons()
        {
            var r = new BoutonPlat("Retour", BoutonPlat.Genre.Discret, Ic.Retour);
            r.Click += delegate { F.Aller(new PageAccueil(F)); };
            var s = new BoutonPlat("Suivant : feu vert", BoutonPlat.Genre.Primaire, Ic.Suivant);
            s.Click += delegate { Valider(); };
            return new Control[] { r, s };
        }

        void Valider()
        {
            var manque = new List<string>();
            if (prenom.Valeur == "") manque.Add("prénom");
            if (nom.Valeur == "") manque.Add("nom");
            if (cabinet.Valeur == "") manque.Add("cabinet");
            if (manque.Count > 0) { Boite.Informer(F, Niveau.Info, "Champs à compléter", string.Join(", ", manque.ToArray()) + "."); return; }
            DateTime dDec = DateTime.MinValue;
            bool decOk = decouverte.Valeur == "" || DateTime.TryParseExact(decouverte.Valeur, new[] { "dd/MM/yyyy HH:mm", "dd/MM/yyyy H:mm", "dd/MM/yyyy" }, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out dDec);
            if (!decOk) { Boite.Informer(F, Niveau.Info, "Date de découverte à corriger", "Écrire JJ/MM/AAAA HH:MM (par exemple 17/11/2026 08:10), ou laisser vide."); decouverte.Saisie.Focus(); return; }
            var i = Ctx.Inter;
            i.Prenom = prenom.Valeur; i.Nom = nom.Valeur; i.Societe = societe.Valeur; i.Cabinet = cabinet.Valeur;
            i.Present = present.Valeur; i.Ticket = ticket.Valeur; i.Motif = motif.Saisie.Text;
            i.Decouverte = decouverte.Valeur == "" ? (DateTime?)null : dDec;
            i.Legere = legere.Checked; i.AnalyseSurPlace = surPlace.Checked; i.Horodater = horodater.Checked;
            if (!Ctx.Demo) Ctx.Reglages.RetenirTechnicien(i.Prenom, i.Nom, i.Societe);
            F.Aller(new PageFeuVert(F));
        }
    }

    // ====================================================================== 2. feu vert
    class PageFeuVert : Page
    {
        readonly Carte bandeau, liste;
        readonly Feux feux = new Feux();
        readonly Label bTitre, bTexte, bEtape;
        readonly Barre barre = new Barre();
        readonly Case malgre;
        BoutonPlat continuer, relancer;
        bool enCours;

        public PageFeuVert(Fenetre f) : base(f)
        {
            Titre = "Feu vert avant de brancher la clé PREUVES";
            SousTitre = "Ne branchez pas encore la clé PREUVES : DigSpill vérifie d'abord qu'aucun chiffrement n'est en cours.";
            Details = "Rien n'est modifié sur le poste : DigSpill lit les notes de rançon, les fichiers modifiés à l'instant, les programmes qui écrivent sur le disque, l'antivirus et le réseau. Environ 30 secondes.";
            Parcours = ParcoursCollecte; Etape = 1;
            bandeau = Corps.Ajouter(NouvelleCarte());
            bandeau.Contenu.Ajouter(feux);
            bTitre = bandeau.Contenu.Ajouter(Mise.Texte("Vérifications en cours…", Theme.Police(16f, FontStyle.Bold), Theme.Encre));
            bTexte = bandeau.Contenu.Ajouter(Paragraphe(""));
            bEtape = bandeau.Contenu.Ajouter(Mise.Texte("", Theme.Police(9.5f), Theme.Doux));
            bandeau.Contenu.Ajouter(barre);
            liste = Corps.Ajouter(NouvelleCarte());
            liste.Visible = false;
            malgre = Corps.Ajouter(new Case("Je continue malgré le danger (décision du technicien, notée dans le journal). DigSpill surveillera la clé et la coupera au premier signe.", false));
            malgre.Visible = false;
            malgre.CheckedChanged += delegate { MajBoutons(); };
        }

        public override IEnumerable<Control> Boutons()
        {
            var r = new BoutonPlat("Retour", BoutonPlat.Genre.Discret, Ic.Retour);
            r.Click += delegate { if (!enCours) F.Aller(new PageIntervention(F)); };
            relancer = new BoutonPlat("Relancer", BoutonPlat.Genre.Secondaire, Ic.Actualiser);
            relancer.Click += delegate { Lancer(); };
            continuer = new BoutonPlat("Suivant : clé PREUVES", BoutonPlat.Genre.Primaire, Ic.Suivant);
            continuer.Click += delegate { F.Aller(new PageSupport(F)); };
            MajBoutons();
            return new Control[] { r, relancer, continuer };
        }

        public override void Affichee() { Lancer(); }

        void MajBoutons()
        {
            if (continuer == null) return;
            var n = Ctx.FeuVert == null ? Niveau.Attente : Verifications.Global(Ctx.FeuVert);
            continuer.Enabled = !enCours && Ctx.FeuVert != null && (n != Niveau.Danger || malgre.Checked);
            relancer.Enabled = !enCours;
        }

        async void Lancer()
        {
            if (enCours) return;
            enCours = true; Occupee = true;
            Ctx.FeuVert = null;
            liste.Visible = false; malgre.Visible = false;
            bandeau.Couleurs(Theme.Panneau, Theme.Ligne);
            feux.Niveau = Niveau.Attente;
            bTitre.Text = "Vérifications en cours…";
            bTexte.Text = "Notes de rançon, fichiers modifiés à l'instant, programmes qui écrivent sur le disque, antivirus, réseau. Environ 30 secondes.";
            barre.Visible = true; barre.Indeterminee = true; bEtape.Visible = true;
            MajBoutons(); Ajuster();
            List<Constat> res;
            try { res = await Task.Run(() => Verifications.Tout(Ctx, e => BeginInvoke(new Action(() => bEtape.Text = e)))); }
            catch (Exception ex) { res = new List<Constat> { new Constat(Niveau.Attention, "Vérifications incomplètes", ex.Message) }; }
            if (IsDisposed) return;
            Ctx.FeuVert = res;
            enCours = false; Occupee = false;
            barre.Indeterminee = false; barre.Visible = false; bEtape.Visible = false;
            var n = Verifications.Global(res);
            bandeau.Couleurs(Niveaux.Fond(n), Niveaux.Couleur(n));
            feux.Niveau = n == Niveau.Danger || n == Niveau.Attention ? n : Niveau.Ok;
            if (n == Niveau.Danger)
            {
                bTitre.Text = "Feu rouge : ne branchez pas la clé PREUVES";
                bTexte.Text = "Un chiffrement semble actif. Isolez le poste du réseau sans l'éteindre, prévenez le responsable, le client et l'assureur. Si la collecte reste nécessaire, cochez la case en bas de page.";
                malgre.Visible = true;
            }
            else if (n == Niveau.Attention)
            {
                bTitre.Text = "Feu orange : vous pouvez continuer, avec prudence";
                bTexte.Text = "Rien n'indique un chiffrement en cours, mais certains points sont à corriger ou à vérifier (voir ci-dessous).";
            }
            else
            {
                bTitre.Text = "Feu vert : vous pouvez brancher la clé PREUVES";
                bTexte.Text = "Aucun signe de chiffrement en cours.";
            }
            // d'abord ce qui demande une action, puis les points conformes regroupes en une ligne (detail au clic)
            liste.Contenu.Controls.Clear();
            var aVoir = res.Where(x => x.Niveau == Niveau.Danger || x.Niveau == Niveau.Attention).OrderByDescending(x => x.Niveau == Niveau.Danger).ToList();
            var bons = res.Where(x => x.Niveau == Niveau.Ok).ToList();
            if (aVoir.Count > 0) liste.Contenu.Ajouter(Intertitre(aVoir.Count == 1 ? "À vérifier" : aVoir.Count + " points à vérifier"));
            foreach (var c in aVoir) liste.Contenu.Ajouter(new LigneInfo(c.Niveau, c.Titre, c.Detail));
            if (bons.Count > 0)
            {
                liste.Contenu.Ajouter(new LigneInfo(Niveau.Ok, bons.Count == 1 ? "1 vérification conforme" : bons.Count + " vérifications conformes", string.Join(", ", bons.Select(x => x.Titre).ToArray()) + "."));
                var detail = new Colonne { Visible = false, Espace = 12 };
                foreach (var c in bons) detail.Ajouter(new LigneInfo(c.Niveau, c.Titre, c.Detail));
                Label lien = null;
                lien = Mise.Lien("▸  Voir le détail des vérifications conformes", () =>
                {
                    detail.Visible = !detail.Visible;
                    lien.Text = (detail.Visible ? "▾  Masquer" : "▸  Voir") + " le détail des vérifications conformes";
                    Ajuster();
                });
                lien.Margin = new Padding(46, 0, 0, 0);
                liste.Contenu.Ajouter(lien);
                liste.Contenu.Ajouter(detail);
            }
            foreach (var c in res.Where(x => x.Niveau != Niveau.Ok && x.Niveau != Niveau.Danger && x.Niveau != Niveau.Attention))
                liste.Contenu.Ajouter(new LigneInfo(c.Niveau, c.Titre, c.Detail));
            liste.Visible = true;
            MajBoutons();
            Ajuster();
        }
    }

    // ====================================================================== 3. cle PREUVES
    class PageSupport : Page
    {
        readonly Carte liste;
        readonly Case pieges;
        readonly LigneInfo remarque;
        BoutonPlat lancer;
        Support choisi;
        Action abonnement;
        bool piegesVoulus;
        readonly Control explicationPieges;

        public PageSupport(Fenetre f) : base(f)
        {
            Titre = "Où écrire les preuves ?";
            SousTitre = "Branchez la clé ou le disque PREUVES, chiffré et déverrouillé.";
            Details = "DigSpill le détecte dès qu'il est branché, en lecture-écriture. Sans clé ni disque externe, un disque de ce poste peut servir : à éviter, l'écriture peut effacer des fichiers supprimés récupérables (choix noté dans infos_collecte.txt).";
            Parcours = ParcoursCollecte; Etape = 2;
            liste = Corps.Ajouter(NouvelleCarte());
            remarque = Corps.Ajouter(new LigneInfo(Niveau.Info, "", ""));
            remarque.Visible = false;
            pieges = Corps.Ajouter(new Case("Protéger les preuves d'un rançongiciel actif : poser des fichiers-appâts (recommandé)", Ctx.AvecPieges));
            explicationPieges = Corps.Ajouter(Paragraphe("DigSpill dépose 4 faux fichiers (des leurres) sur le support. Un rançongiciel encore actif les chiffrerait comme le reste : " +
                "au moindre changement, DigSpill déconnecte le support pour sauver les preuves déjà écrites. Les leurres sont retirés à la fin."));
            piegesVoulus = Ctx.AvecPieges;
            pieges.CheckedChanged += delegate { if (pieges.Enabled) piegesVoulus = pieges.Checked; };
        }

        public override IEnumerable<Control> Boutons()
        {
            var r = new BoutonPlat("Retour", BoutonPlat.Genre.Discret, Ic.Retour);
            r.Click += delegate { F.Aller(new PageFeuVert(F)); };
            var a = new BoutonPlat("Actualiser", BoutonPlat.Genre.Secondaire, Ic.Actualiser);
            a.Click += delegate { Remplir(); };
            lancer = new BoutonPlat("Lancer la collecte", BoutonPlat.Genre.Primaire, Ic.Lecture);
            lancer.Enabled = false;
            lancer.Click += delegate { Lancer(); };
            return new Control[] { r, a, lancer };
        }

        public override void Affichee()
        {
            abonnement = () => { if (!IsDisposed) Remplir(); };
            F.SupportsChanges += abonnement;
            Remplir();
        }
        public override void Quittee() { if (abonnement != null) F.SupportsChanges -= abonnement; }

        List<Support> Candidats()
        {
            if (Ctx.Demo)
                return new List<Support> {
                    new Support { Lettre = "F:", Etiquette = "PREUVES", Systeme = "exFAT", Libre = 241L << 30, Total = 256L << 30, Usb = true, Amovible = true },
                    new Support { Lettre = "E:", Etiquette = "OUTILS", Systeme = "NTFS", Libre = 21L << 30, Total = 32L << 30, Usb = true, Amovible = true, EstOutils = true, LectureSeule = true },
                    new Support { Lettre = "C:", Etiquette = "Windows", Systeme = "NTFS", Libre = 180L << 30, Total = 476L << 30, Bus = "NVMe", Modele = "Samsung SSD 980", EstSysteme = true, Genre = GenreSupport.DisquePoste } };
            return Supports.Lister(Ctx.RacineOutils);
        }

        void Remplir()
        {
            var l = Candidats();
            var externes = l.Where(x => x.Externe).ToList();
            var poste = l.Where(x => !x.Externe).ToList();
            liste.Contenu.Controls.Clear();
            liste.Contenu.Ajouter(Intertitre("Clés et disques externes"));
            if (externes.Count == 0) liste.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "En attente d'une clé ou d'un disque externe…", "Branchez la clé ou le disque PREUVES et déverrouillez-le (code PIN) : il apparaît ici."));
            CarteSelection premiere = null, precedente = null;
            foreach (var s in externes) Ajouter(s, ref premiere, ref precedente);
            if (poste.Count > 0)
            {
                liste.Contenu.Ajouter(Intertitre("Disques de ce poste (sans clé ni disque externe)"));
                foreach (var s in poste) Ajouter(s, ref premiere, ref precedente);
            }
            choisi = null;
            if (precedente != null) Choisir(precedente);
            else if (premiere != null) Choisir(premiere);
            else MajRemarque();
            Ajuster();
        }

        void Ajouter(Support s, ref CarteSelection premiere, ref CarteSelection precedente)
        {
            var b = new List<Tuple<string, Niveau>>();
            if (s.EstOutils) b.Add(Tuple.Create(s.Externe ? "Clé OUTILS" : "DigSpill est ici", Niveau.Info));
            if (s.LectureSeule) b.Add(Tuple.Create("Protégée en écriture", s.EstOutils ? Niveau.Ok : Niveau.Danger));
            if (!s.Externe) b.Add(Tuple.Create("Sur le poste examiné", Niveau.Attention));
            if (s.Systeme.StartsWith("FAT", StringComparison.OrdinalIgnoreCase)) b.Add(Tuple.Create("FAT32 : fichiers limités à 4 Go", Niveau.Attention));
            if (s.Libre < (16L << 30)) b.Add(Tuple.Create("Moins de 16 Go libres", Niveau.Attention));
            var c = new CarteSelection(s.Externe ? Ic.Usb : Ic.Poste, s.Nom, s.Description, b) { Valeur = s, Utilisable = !s.LectureSeule };
            c.Choisie += (o, e) => Choisir((CarteSelection)o);
            liste.Contenu.Ajouter(c);
            // choix automatique : jamais un disque du poste ni la cle des outils, il faut cliquer dessus
            if (premiere == null && c.Utilisable && s.Externe && !s.EstOutils) premiere = c;
            if (choisi != null && choisi.Lettre == s.Lettre && c.Utilisable) precedente = c;
        }

        void Choisir(CarteSelection c)
        {
            foreach (var x in liste.Contenu.Controls.OfType<CarteSelection>()) x.Choix = x == c;
            choisi = (Support)c.Valeur;
            MajRemarque();
        }

        void MajRemarque()
        {
            if (lancer != null) lancer.Enabled = choisi != null;
            // pieges : seulement sur un support separe, que l'on peut couper sans toucher au poste
            bool possibles = choisi == null || choisi.Externe;
            pieges.Enabled = possibles;
            pieges.Checked = possibles && piegesVoulus;
            explicationPieges.Visible = possibles;
            if (choisi != null && !choisi.Externe)
            {
                remarque.Definir(Niveau.Attention, "Preuves sur le disque du poste : à défaut seulement",
                    "La collecte ira dans " + choisi.Lettre + "\\Collecte\\, sur le poste examiné. Écrire dessus peut effacer des fichiers supprimés encore récupérables, " +
                    "et un rançongiciel actif peut chiffrer les preuves. Ni fichiers-appâts, ni coupure, ni éjection. Copiez la collecte sur un support externe dès que possible.");
                remarque.Visible = true;
            }
            else if (choisi != null && choisi.EstOutils)
            {
                remarque.Definir(Niveau.Attention, "Mode une seule clé", "La collecte ira sur la clé des outils. Possible, mais moins sûr : un rançongiciel pourrait atteindre les outils et les preuves à la fois.");
                remarque.Visible = true;
            }
            else if (choisi == null) remarque.Visible = false;
            else
            {
                remarque.Definir(Niveau.Ok, "La collecte ira dans " + choisi.Lettre + "\\Collecte\\", "Le dossier est créé s'il n'existe pas. Les fichiers-appâts sont retirés à la fin, sauf en cas d'alerte.");
                remarque.Visible = true;
            }
            Ajuster();
        }

        void Lancer()
        {
            if (choisi == null) return;
            if (!Ctx.Demo)
            {
                if (!choisi.Externe &&
                    !Boite.Confirmer(F, Niveau.Attention, "Écrire les preuves sur " + choisi.Appellation + " ?", "À faire seulement sans clé ni disque externe : l'écriture peut effacer des fichiers supprimés récupérables, " +
                        "et un rançongiciel actif peut chiffrer les preuves. Pas de fichiers-appâts ni d'éjection.\r\n\r\nCe choix est noté dans infos_collecte.txt.", "Écrire sur ce disque", "Choisir un autre support", true)) return;
                if (choisi.Systeme.StartsWith("FAT", StringComparison.OrdinalIgnoreCase) &&
                    !Boite.Confirmer(F, Niveau.Attention, "Support en FAT32", "La capture de la mémoire et les conteneurs de plus de 4 Go ne pourront pas y être écrits.", "Continuer quand même", "Choisir un autre support", true)) return;
                string err;
                if (!Supports.EssaiEcriture(Path.Combine(choisi.Racine, "Collecte"), out err))
                { Boite.Informer(F, Niveau.Danger, "Écriture impossible sur " + choisi.Lettre, err + "\r\n\r\nVérifiez que le support est déverrouillé et en lecture-écriture."); return; }
            }
            Ctx.Destination = choisi;
            Ctx.AvecPieges = choisi.Externe && pieges.Checked;
            F.Aller(new PageCollecte(F));
        }
    }

    // ====================================================================== 4. collecte
    class PageCollecte : Page
    {
        readonly Barre barre = new Barre();
        readonly Label numero, phase, etat, chrono;
        readonly LigneInfo ePs, eVelo, eAna, eScelle, garde;
        readonly Journal journal = new Journal { Hauteur = 230 };
        readonly System.Windows.Forms.Timer horloge = new System.Windows.Forms.Timer { Interval = 1000 };
        Executeur exec;
        bool urgence;
        int etapesVues;
        double baseProgression, partProgression;

        public PageCollecte(Fenetre f) : base(f)
        {
            Titre = "Collecte en cours";
            SousTitre = Ctx.Destination != null && !Ctx.Destination.Externe ? "Ne fermez pas DigSpill." : "Ne retirez pas les clés et ne fermez pas DigSpill.";
            Details = (Ctx.Destination != null && !Ctx.Destination.Externe ? "Les preuves sont écrites sur " + Ctx.Destination.Appellation + ". "
                : Ctx.AvecPieges ? (Ctx.Destination != null && Ctx.Destination.Genre == GenreSupport.DisqueExterne ? "Le disque PREUVES est surveillé en continu. " : "La clé PREUVES est surveillée en continu. ") : "")
                + "Mise en veille bloquée pendant la collecte (ne fermez pas le capot d'un portable).";
            Parcours = ParcoursCollecte; Etape = 3;
            var c = Corps.Ajouter(NouvelleCarte());
            c.Couleurs(Theme.Panneau, Theme.Ligne);
            numero = c.Contenu.Ajouter(Mise.Texte("", Theme.MonoMoyen(8.5f), Theme.Texte3));
            phase = c.Contenu.Ajouter(Mise.Texte("Préparation…", Theme.Police(18f, FontStyle.Bold), Theme.Encre));
            etat = c.Contenu.Ajouter(Mise.Texte("", Theme.Police(10.5f), Theme.Doux));
            barre.Epaisseur = 10; barre.Couleur = Theme.Rouge;
            c.Contenu.Ajouter(barre);
            chrono = c.Contenu.Ajouter(Mise.Texte("", Theme.Police(10f), Theme.Doux));
            garde = Corps.Ajouter(new LigneInfo(Niveau.Attente, "Surveillance de la clé PREUVES", ""));
            var e = Corps.Ajouter(NouvelleCarte());
            e.Contenu.Ajouter(Intertitre("Étapes"));
            ePs = e.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "1. Traces du poste", "Mémoire vive, journaux, comptes, connexions, persistance, traces de rançongiciel (PowerShell)."));
            eVelo = e.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "2. Disque et registre", "$MFT, journal USN, registre, SRUM, Autoruns, en lecture NTFS brute (Velociraptor)."));
            eAna = e.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "3. Analyse rapide sur place", "Sessions, volumes envoyés, exécutions et navigation pendant les fenêtres suspectes."));
            eScelle = e.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "4. Scellé de fin de collecte", "Empreinte SHA-256 du manifeste, du journal et des conteneurs ; horodatage si Internet."));
            // journal technique replie : on suit l'etape en cours, le detail est a un clic
            Label lien = null;
            lien = Corps.Ajouter(Mise.Lien("▸  Journal détaillé", () => { journal.Visible = !journal.Visible; lien.Text = (journal.Visible ? "▾" : "▸") + "  Journal détaillé"; Ajuster(); }));
            journal.Visible = false;
            Corps.Ajouter(journal);
            horloge.Tick += delegate { MajGarde(); if (Ctx.Debut != DateTime.MinValue) chrono.Text = Avancement(); };
        }

        public override IEnumerable<Control> Boutons()
        {
            var u = new BoutonPlat("Arrêt d'urgence", BoutonPlat.Genre.Danger, Ic.Arret);
            u.Click += delegate
            {
                if (Boite.Confirmer(F, Niveau.Danger, "Arrêt d'urgence ?", "La collecte s'arrête et la clé PREUVES est coupée immédiatement.", "Arrêter et couper la clé", "Continuer la collecte", false))
                    Urgence("Arrêt d'urgence demandé par le technicien");
            };
            return new Control[] { u };
        }

        public override void Affichee() { Demarrer(); }
        public override void Quittee()
        {
            horloge.Stop();
            if (Occupee && exec != null) exec.Tuer(); // fenetre fermee pendant la collecte : rien ne doit continuer sans surveillance
            if (Occupee && Ctx.Pieges != null) Ctx.Pieges.Arreter();
        }

        void Log(string l) { journal.Ajouter(l); }
        void Ui(Action a) { if (IsDisposed) return; if (InvokeRequired) BeginInvoke(a); else a(); }
        void Etat(string t) { Ui(() => { etat.Text = t; Ajuster(); }); }

        void MajGarde()
        {
            var p = Ctx.Pieges;
            var d = Ctx.Destination;
            if (d != null && !d.Externe) garde.Definir(Niveau.Attention, "Pas de surveillance", "Preuves sur le disque du poste (" + d.Lettre + ") : ni fichiers-appâts ni coupure possibles.");
            else if (!Ctx.AvecPieges) garde.Definir(Niveau.Attention, "Surveillance désactivée", "Aucun fichier-appât sur " + (d != null ? d.Appellation : "la clé PREUVES") + ".");
            else if (p == null) garde.Definir(Niveau.Attente, "Surveillance : " + (d != null ? d.Appellation : "la clé PREUVES"), "Mise en place…");
            else garde.Definir(Niveau.Ok, d != null && d.Genre == GenreSupport.DisqueExterne ? "Disque PREUVES surveillé" : "Clé PREUVES surveillée", string.Format("{0} fichiers-appâts intacts · dernier contrôle {1:HH:mm:ss} · coupure automatique au premier signe", Ctx.Demo ? 4 : p.Nombre, p.DernierControle == DateTime.MinValue ? DateTime.Now : p.DernierControle));
        }

        void Progression(double v) { Ui(() => barre.Valeur = v); }

        /// <summary>Grande etape en cours (1 a 4) affichee en haut de la page.</summary>
        void Phase(int n, string nom) { Ui(() => { numero.Text = "ÉTAPE " + n + " / 4"; phase.Text = nom; etat.Text = ""; Ajuster(); }); }

        /// <summary>« 46 % · environ 25 min restantes · démarrée à 11:19 (14 min) · destination F:\Collecte » ; le reste est estime d'apres le temps deja passe.</summary>
        string Avancement()
        {
            var ecoule = DateTime.Now - Ctx.Debut;
            var l = new List<string>();
            double v = barre.Valeur;
            if (!barre.Indeterminee && v > 0) l.Add(Math.Round(v * 100) + " %");
            if (!barre.Indeterminee && v >= 0.05 && v < 1 && ecoule.TotalSeconds >= 60)
            {
                double min = Math.Ceiling(ecoule.TotalMinutes * (1 - v) / v);
                l.Add(min <= 1 ? "moins d'une minute restante" : min < 90 ? "environ " + min + " min restantes" : string.Format("environ {0} h {1:00} restantes", (int)(min / 60), (int)(min % 60)));
            }
            else if (barre.Indeterminee) l.Add("durée de cette étape inconnue");
            else if (v < 1) l.Add("temps restant en cours d'estimation");
            l.Add("démarrée à " + Ctx.Debut.ToString("HH:mm") + " (" + Pages.Duree(ecoule) + ")");
            if (Ctx.Destination != null) l.Add("destination " + Ctx.Destination.Racine + "Collecte");
            return string.Join(" · ", l.ToArray());
        }

        void Ligne(string l)
        {
            Log(l);
            var m = Regex.Match(l, @"\[\*\]\s+(.+)$");
            if (m.Success)
            {
                etapesVues++;
                int prevu = Ctx.Inter.Legere ? 24 : 36;
                if (etapesVues >= prevu) prevu = etapesVues + 2;
                Etat(m.Groups[1].Value);
                Progression(baseProgression + partProgression * etapesVues / prevu);
            }
        }

        async void Demarrer()
        {
            try { await Derouler(); }
            catch (Exception ex)
            {
                Log("[!] " + ex);
                Occupee = false; horloge.Stop();
                if (IsDisposed) return;
                barre.Vivante = false;
                etat.Text = "Erreur : " + ex.Message;
                Titre = "Collecte interrompue"; F.MajEntete(); Ajuster();
            }
        }

        async Task Derouler()
        {
            Occupee = true;
            F.GarderEveille();
            Ui(() => barre.Vivante = true);
            Ctx.Debut = DateTime.Now;
            horloge.Start();
            var d = Ctx.Destination;
            Ctx.DossierCollecteRacine = Path.Combine(d.Racine, "Collecte");
            var i = Ctx.Inter;
            Log(string.Format("DigSpill {0} · {1} · technicien {2} · cabinet {3} · destination {4}", Programme.VersionKit, Environment.MachineName, i.Technicien, i.Cabinet, d.Racine));
            if (Ctx.FeuVert != null && Verifications.Global(Ctx.FeuVert) == Niveau.Danger) Log("[!] Feu vert en DANGER : le technicien a choisi de continuer.");

            // --- pieges
            if (Ctx.AvecPieges)
            {
                try
                {
                    Ctx.Pieges = new Pieges(d.Racine);
                    if (!Ctx.Demo) { Ctx.Pieges.Poser(); Ctx.Pieges.Alerte += r => BeginInvoke(new Action(() => Urgence(r))); Ctx.Pieges.Surveiller(); }
                    Log("Fichiers-appâts posés et surveillés sur " + d.Racine);
                }
                catch (Exception ex) { Log("[!] Fichiers-appâts impossibles : " + ex.Message); Ctx.Pieges = null; Ctx.AvecPieges = false; }
            }
            MajGarde();

            // --- 1. PowerShell
            ePs.Etat(Niveau.EnCours);
            Phase(1, "Traces du poste");
            baseProgression = 0; partProgression = i.Legere ? 0.85 : 0.55;
            // powershell.exe -File perd les arguments vides : on ne passe que les champs remplis
            var ap = new List<string> { "-Mode", i.Legere ? "Leger" : "Complet", "-Destination", Executeur.Echapper(d.Racine) };
            if (!d.Externe) ap.Add("-DestinationSurLePoste");   // le disque reste examine, seul le dossier Collecte est saute
            var champs = new[] { Tuple.Create("-Technicien", i.Technicien), Tuple.Create("-Societe", i.Societe), Tuple.Create("-Client", i.Cabinet), Tuple.Create("-Present", i.Present),
                Tuple.Create("-Ticket", i.Ticket), Tuple.Create("-Motif", i.Motif), Tuple.Create("-Decouverte", i.Decouverte.HasValue ? i.Decouverte.Value.ToString("yyyy-MM-dd HH:mm") : "") };
            foreach (var t in champs) if (!string.IsNullOrWhiteSpace(t.Item2)) { ap.Add(t.Item1); ap.Add(Executeur.Echapper(t.Item2)); }
            // identifiants de la session (lus avant l'elevation) : ecrits par le script dans exposition\, donc sous manifeste
            Dictionary<string, string> env = null;
            if (!string.IsNullOrEmpty(Ctx.IdentifiantsSession))
                env = new Dictionary<string, string> { { "DIGSPILL_IDENTIFIANTS", Ctx.IdentifiantsSession }, { "DIGSPILL_COMPTE_SESSION", Ctx.CompteSession ?? Identifiants.Compte } };
            int code = await Executer("Collecte-Exfil.ps1", ap, "Collecte PowerShell", env);
            if (urgence) return;
            Ctx.NomCollecte = TrouverCollecte();
            Ctx.ProblemeCollecte = Ctx.NomCollecte != null ? null : "La collecte PowerShell s'est arrêtée sans créer de dossier (code de sortie " + code + ") : ni journaux, ni mémoire vive, ni manifeste. Relancez la collecte ; le détail est dans le journal de la page Collecte.";
            ePs.Definir(code == 0 && Ctx.NomCollecte != null ? Niveau.Ok : Niveau.Attention, "1. Traces du poste", Ctx.NomCollecte != null ? "Dossier " + Ctx.NomCollecte + (code == 0 ? "" : " (code de sortie " + code + ", voir collecte.log)") : "Dossier de collecte introuvable : voir le journal ci-dessous.");

            // --- 2. Velociraptor
            if (i.Legere) eVelo.Definir(Niveau.Ignore, "2. Disque et registre", "Pas en collecte légère.");
            else if (!Ctx.Demo && !File.Exists(Ctx.Velociraptor)) eVelo.Definir(Niveau.Attention, "2. Disque et registre", "Collecteur-Velociraptor.exe absent de la clé OUTILS : étape sautée.");
            else
            {
                eVelo.Etat(Niveau.EnCours);
                Phase(2, "Disque et registre");
                Etat("$MFT, registre, journaux en lecture NTFS brute (plusieurs minutes)…");
                Ui(() => barre.Indeterminee = true);
                string dv = Path.Combine(Ctx.DossierCollecteRacine, "Velociraptor");
                int cv;
                if (Ctx.Demo) cv = await Simuler(new[] { "[INFO] Starting collection of Windows.Triage.Targets", "[INFO] Collected 1 482 files (3.1 GB)", "[INFO] Windows.Forensics.SRUM: 14 rows", "[INFO] Container written: Velociraptor-SECRETARIAT-01-2026-11-19T10_41_09Z.zip" });
                else
                {
                    Directory.CreateDirectory(dv);
                    exec = new Executeur();
                    exec.Ligne += Log;
                    cv = await exec.Lancer(Ctx.Velociraptor, "", dv, System.Text.Encoding.UTF8, null);
                }
                if (urgence) return;
                eVelo.Definir(cv == 0 ? Niveau.Ok : Niveau.Attention, "2. Disque et registre", cv == 0 ? "Conteneur écrit dans " + dv : "Code de sortie " + cv + " : voir le journal.");
            }
            Progression(0.9);

            // --- 3. analyse sur place
            if (!i.AnalyseSurPlace) eAna.Definir(Niveau.Ignore, "3. Analyse rapide sur place", "Non demandée : à faire au bureau (DigSpill → Analyser une collecte).");
            else
            {
                eAna.Etat(Niveau.EnCours);
                Phase(3, "Analyse rapide sur place");
                baseProgression = 0.9; partProgression = 0;
                int ca = await Executer("Analyse-Exfil.ps1", new List<string> { "-Collecte", Executeur.Echapper(Ctx.DossierCollecteRacine), "-DerniereDuPoste", "-SansMFT", "-SansHashConteneurs" }, "Analyse rapide");
                if (urgence) return;
                eAna.Definir(ca == 0 ? Niveau.Ok : Niveau.Attention, "3. Analyse rapide sur place", ca == 0 ? "Synthèse dans " + Ctx.NomCollecte + "_analyse\\SYNTHESE_EXFILTRATION.txt" : "Analyse en échec (code " + ca + ") : la refaire au bureau.");
            }

            // --- 4. scelle
            eScelle.Etat(Niveau.EnCours);
            Phase(4, "Scellé de fin de collecte");
            Etat("Calcul des empreintes…");
            Ui(() => barre.Indeterminee = true);
            string par = i.Technicien + (i.Societe != "" ? " (" + i.Societe + ")" : "") + " - " + Environment.UserDomainName + "\\" + Environment.UserName;
            if (Ctx.Demo) { await Task.Delay(1200); Pages.RemplirDemo(Ctx); }
            else if (Ctx.NomCollecte != null)
            {
                Ctx.Scelle = await Task.Run(() => Scelle.Creer(Ctx.DossierCollecteRacine, Ctx.NomCollecte, par, Ctx.Debut, s => Etat(s)));
                if (Ctx.Scelle.Erreur == null && i.Horodater)
                {
                    // l'horodateur peut ne pas repondre (DNS, proxy, pare-feu) : 45 s au plus, secondes affichees
                    var t = Task.Run(() => Scelle.Horodater(Ctx.Scelle, Ctx.Horodateur));
                    var debutH = DateTime.Now;
                    while (!t.IsCompleted && (DateTime.Now - debutH).TotalSeconds < 45)
                    {
                        Etat(string.Format("Horodatage par {0}… ({1:0} s)", Ctx.Horodateur, (DateTime.Now - debutH).TotalSeconds));
                        await Task.WhenAny(t, Task.Delay(1000));
                    }
                    if (!t.IsCompleted) { Ctx.Scelle.ErreurHorodatage = "l'horodateur n'a pas répondu en 45 s"; Log("[!] Horodatage : pas de réponse en 45 s, à refaire au bureau"); }
                }
                else if (Ctx.Scelle.Erreur == null) Ctx.Scelle.ErreurHorodatage = "non demandé";
            }
            if (urgence) return;
            var sc = Ctx.Scelle;
            if (sc == null || sc.Erreur != null) eScelle.Definir(Niveau.Attention, "4. Scellé de fin de collecte", "Scellé non créé : " + (sc == null ? "collecte introuvable" : sc.Erreur));
            else eScelle.Definir(Niveau.Ok, "4. Scellé de fin de collecte", sc.NombreElements + " fichiers scellés · " + (sc.DateJeton != null ? "horodaté le " + sc.DateJeton : "horodatage au bureau (" + sc.ErreurHorodatage + ")"));
            Log("Scellé : " + (sc != null ? sc.Empreinte + "  " + sc.Fichier : "aucun"));
            Ctx.Fin = DateTime.Now;
            Ctx.CollecteOk = Ctx.NomCollecte != null;
            Progression(1);
            Ui(() => barre.Vivante = false);
            horloge.Stop();
            Occupee = false;
            await Task.Delay(600);
            if (!IsDisposed) F.Aller(new PageFin(F));
        }

        string TrouverCollecte()
        {
            if (Ctx.Demo) return "SECRETARIAT-01_20261119_102233";
            try
            {
                var rx = new Regex("^" + Regex.Escape(Environment.MachineName) + @"_\d{8}_\d{6}(_leger)?$", RegexOptions.IgnoreCase);
                return new DirectoryInfo(Ctx.DossierCollecteRacine).GetDirectories()
                    .Where(x => rx.IsMatch(x.Name) && x.CreationTime >= Ctx.Debut.AddMinutes(-2))
                    .OrderByDescending(x => x.Name).Select(x => x.Name).FirstOrDefault();
            }
            catch { return null; }
        }

        Task<int> Executer(string script, List<string> args, string nom, IDictionary<string, string> env = null)
        {
            if (Ctx.Demo)
                return Simuler(new[] { "[*] Informations sur le poste", "[*] Processus et connexions réseau", "[*] Mémoire vive et fichiers d'échange", "[*] Journaux d'événements",
                    "[*] Comptes et sessions", "[*] Persistance (tâches, services, Run)", "[*] Traces de rançongiciel", "[*] Calcul du manifeste SHA256 des éléments collectés" });
            exec = new Executeur();
            exec.Ligne += Ligne;
            Log("> " + script + " " + string.Join(" ", args.ToArray()));
            return exec.Lancer("powershell.exe", Executeur.ArgumentsPowerShell(Ctx.Script(script), args), Ctx.RacineOutils, Executeur.Console850(), env);
        }

        async Task<int> Simuler(string[] lignes)
        {
            foreach (var l in lignes) { await Task.Delay(700); if (urgence) return -1; Ligne(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + l); }
            return 0;
        }

        void Urgence(string raison)
        {
            if (urgence) return;
            urgence = true;
            horloge.Stop();
            Ctx.RaisonAlerte = raison;
            var faits = new List<string>();
            if (exec != null) { exec.Tuer(); faits.Add("Collecte arrêtée (PowerShell, Velociraptor et leurs programmes)"); }
            if (Ctx.Pieges != null) Ctx.Pieges.Arreter();
            if (!Ctx.Demo && Ctx.Destination.Externe) faits.AddRange(Supports.VerrouillageUrgence(Ctx.Destination.Lettre));
            else faits.Add("Volume démonté (démonstration)");
            Ctx.ActionsUrgence = faits;
            Occupee = false;
            F.Aller(new PageAlerte(F));
        }
    }

    // ====================================================================== 5. fin
    class PageFin : Page
    {
        readonly Carte sombre;
        readonly Rangee pastilles = new Rangee();
        readonly Label fichierScelle;
        BoutonPlat ejecter, horodater;
        bool ejectee;

        public PageFin(Fenetre f) : base(f)
        {
            var sc = Ctx.Scelle;
            bool scelle = sc != null && sc.Erreur == null && sc.Empreinte != null;
            Titre = !Ctx.CollecteOk ? "Collecte incomplète" : scelle ? "Collecte terminée" : "Collecte terminée sans scellé";
            var d = Ctx.Destination;
            bool externe = d == null || d.Externe;
            string nom = d != null ? d.Appellation : "la clé PREUVES";
            SousTitre = !externe ? (scelle ? "Photographiez l'empreinte ci-dessous avec votre téléphone, puis copiez la collecte sur un support externe." : "Lisez le problème ci-dessous, puis copiez la collecte sur un support externe.")
                : scelle ? "Photographiez l'empreinte ci-dessous avec votre téléphone, puis éjectez " + nom + " avant de le débrancher."
                : "Lisez le problème ci-dessous avant d'éjecter " + nom + ".";
            Parcours = ParcoursCollecte; Etape = 4;

            if (!scelle)
            {
                var pb = Corps.Ajouter(NouvelleCarte());
                pb.Contenu.Ajouter(new LigneInfo(Niveau.Danger, Ctx.CollecteOk ? "Scellé non créé" : "Collecte incomplète",
                    Ctx.ProblemeCollecte ?? ("Le scellé n'a pas pu être créé" + (sc != null && sc.Erreur != null ? " : " + sc.Erreur : "") + ". Il pourra être créé au bureau (DigSpill → Analyser une collecte).")));
            }
            sombre = Corps.Ajouter(NouvelleCarte());
            sombre.Couleurs(Theme.Panneau, Theme.Ligne);
            sombre.Visible = scelle;
            sombre.Padding = new Padding(26, 22, 26, 22);
            sombre.Contenu.Ajouter(Mise.Texte("EMPREINTE DU SCELLÉ (SHA-256)", Theme.MonoMoyen(8.5f), Theme.Texte3));
            var emp = sombre.Contenu.Ajouter(new Empreinte());
            emp.Text = sc != null && sc.Empreinte != null ? sc.Empreinte : "aucun scellé";
            sombre.Contenu.Ajouter(pastilles);
            fichierScelle = sombre.Contenu.Ajouter(Mise.Texte(sc != null && sc.Fichier != null ? sc.Fichier : "", Theme.Mono(8.5f), Theme.Texte3));
            MajPastilles();

            var a = Corps.Ajouter(NouvelleCarte());
            a.Contenu.Ajouter(Intertitre("Avant de partir"));
            a.Contenu.Ajouter(new LigneInfo(Niveau.Info, "Photographier l'empreinte", "Avec la date et l'heure du téléphone : une trace indépendante du support, au cas où il serait perdu ou abîmé."));
            a.Contenu.Ajouter(new LigneInfo(Niveau.Info, "Identifiants enregistrés", "Ce compte (" + (Ctx.CompteSession ?? Identifiants.Compte) + ") : déjà listé. Autres comptes du poste : ouvrir leur session, lancer DigSpill.exe, « Identifiants de ce compte »."));
            if (externe) a.Contenu.Ajouter(new LigneInfo(Niveau.Info, (d != null ? d.NomCourt : "Clé PREUVES") + " en lecture seule", "Après l'éjection : passez le support en mode lecture seule (clé ou disque à code : voir sa notice) et rangez-le à part."));
            else a.Contenu.Ajouter(new LigneInfo(Niveau.Attention, "Copier la collecte hors du poste", "Elle est dans " + Ctx.DossierCollecteRacine + ", sur le poste examiné. Copiez ce dossier sur un support externe dès que possible, " +
                "puis vérifiez la copie au bureau (DigSpill → Analyser une collecte → copie vérifiée). Le scellé prouve que la copie est identique."));
            a.Contenu.Ajouter(new LigneInfo(Niveau.Info, "Au bureau", "DigSpill → Analyser une collecte : copie vérifiée, analyse complète, rapport, PV de collecte à faire signer."));
        }

        void MajPastilles()
        {
            var sc = Ctx.Scelle;
            pastilles.Controls.Clear();
            if (sc != null && sc.DateJeton != null) pastilles.Controls.Add(new Pastille("Horodaté le " + sc.DateJeton, Niveau.Ok));
            else pastilles.Controls.Add(new Pastille("À horodater au bureau" + (sc != null && sc.ErreurHorodatage != null ? " · " + sc.ErreurHorodatage : ""), Niveau.Attention));
            if (sc != null) pastilles.Controls.Add(new Pastille(sc.NombreElements + " fichiers scellés", Niveau.Info));
            if (Ctx.Fin > Ctx.Debut) pastilles.Controls.Add(new Pastille("Durée " + Pages.Duree(Ctx.Fin - Ctx.Debut), Niveau.Info));
            Ajuster();
        }

        public override IEnumerable<Control> Boutons()
        {
            var l = new List<Control>();
            var o = new BoutonPlat("Ouvrir le dossier", BoutonPlat.Genre.Secondaire, Ic.Dossier);
            o.Click += delegate { if (Ctx.DossierCollecteRacine != null) Pages.OuvrirDossier(Ctx.DossierCollecteRacine); };
            l.Add(o);
            var sc = Ctx.Scelle;
            if (sc != null && sc.Fichier != null && sc.DateJeton == null)
            {
                horodater = new BoutonPlat("Horodater maintenant", BoutonPlat.Genre.Secondaire, Ic.Horloge);
                horodater.Click += async delegate
                {
                    horodater.Enabled = false; horodater.Text = "Horodatage…";
                    if (!Ctx.Demo) await Task.Run(() => Scelle.Horodater(sc, Ctx.Horodateur)); else await Task.Delay(800);
                    horodater.Text = sc.DateJeton != null ? "Horodaté" : "Réessayer l'horodatage";
                    horodater.Enabled = sc.DateJeton == null;
                    if (sc.DateJeton == null && sc.ErreurHorodatage != null) Boite.Informer(F, Niveau.Info, "Horodatage impossible", sc.ErreurHorodatage + "\r\n\r\nLe scellé reste valable : il sera horodaté au bureau.");
                    MajPastilles();
                };
                l.Add(horodater);
            }
            var d = Ctx.Destination;
            if (d != null && !d.Externe)
            {
                var fermer = new BoutonPlat("Fermer DigSpill", BoutonPlat.Genre.Primaire, Ic.Ok);
                fermer.Click += delegate { F.Close(); };
                l.Add(fermer);
                return l;
            }
            ejecter = new BoutonPlat(d != null && d.Genre == GenreSupport.DisqueExterne ? "Éjecter le disque PREUVES" : "Éjecter la clé PREUVES", BoutonPlat.Genre.Primaire, Ic.Verrou);
            ejecter.Click += delegate { if (ejectee) F.Close(); else Ejecter(); };
            l.Add(ejecter);
            return l;
        }

        void Ejecter()
        {
            if (Ctx.Pieges != null) Ctx.Pieges.Retirer();
            if (!Ctx.Demo && Ctx.Destination.EstOutils)
            {
                // DigSpill.exe tourne depuis cette cle : l'ejecter maintenant ferait planter l'appli
                if (!Boite.Confirmer(F, Niveau.Info, "Fermer DigSpill pour éjecter la clé ?", "Mode une seule clé : DigSpill tourne depuis cette clé et ne peut pas l'éjecter lui-même. Une fois DigSpill fermé, Windows éjecte la clé (quelques secondes).", "Fermer et éjecter", "Rester sur cette page", false)) return;
                try { Supports.EjecterApresFermeture(Ctx.Destination.Lettre); }
                catch (Exception e) { Boite.Informer(F, Niveau.Info, "Éjection automatique impossible", e.Message + "\r\n\r\nFermez DigSpill puis utilisez « Retirer le périphérique en toute sécurité » de Windows."); }
                F.Close();
                return;
            }
            string err = Ctx.Demo ? null : Supports.Ejecter(Ctx.Destination.Lettre, false);
            if (err != null)
            {
                if (!Boite.Confirmer(F, Niveau.Attention, "Windows refuse d'éjecter la clé", err + "\r\n\r\nLes données sont déjà écrites : forcer l'éjection ne les abîme pas.", "Forcer l'éjection", "Je ferme les fenêtres et je réessaie", true)) return;
                err = Supports.Ejecter(Ctx.Destination.Lettre, true);
                if (err != null) { Boite.Informer(F, Niveau.Danger, "Éjection impossible", err + "\r\n\r\nUtilisez « Retirer le périphérique en toute sécurité » de Windows."); return; }
            }
            ejectee = true;
            bool disque = Ctx.Destination != null && Ctx.Destination.Genre == GenreSupport.DisqueExterne;
            Titre = disque ? "Disque PREUVES éjecté" : "Clé PREUVES éjectée";
            SousTitre = disque ? "Vous pouvez le débrancher." : "Vous pouvez la débrancher.";
            Details = disque ? "Passez-le en lecture seule si possible et rangez-le séparément de la clé OUTILS." : "Passez-la en lecture seule et rangez-la séparément de la clé OUTILS.";
            ejecter.Text = "Fermer DigSpill";
            ejecter.Icone = Ic.Ok;
            pastilles.Controls.Add(new Pastille(disque ? "Disque éjecté" : "Clé éjectée", Niveau.Ok));
            F.MajEntete();
            Ajuster();
        }
    }

    // ====================================================================== alerte
    class PageAlerte : Page
    {
        public PageAlerte(Fenetre f) : base(f)
        {
            bool disque = Ctx.Destination != null && Ctx.Destination.Genre == GenreSupport.DisqueExterne;
            Titre = disque ? "Disque PREUVES coupé" : "Clé PREUVES coupée";
            SousTitre = disque ? "DigSpill a détecté une activité suspecte sur le disque PREUVES et l'a déconnecté aussitôt."
                : "DigSpill a détecté une activité suspecte sur la clé PREUVES et l'a déconnectée aussitôt.";
            Parcours = ParcoursCollecte; Etape = 3;
            var r = Corps.Ajouter(NouvelleCarte());
            r.Couleurs(Theme.RougeFond, Theme.Rouge);
            r.Epaisseur = 2f;
            r.Contenu.Ajouter(Mise.Texte("Activité détectée", Theme.Police(14f, FontStyle.Bold), Theme.RougeTexte));
            r.Contenu.Ajouter(Mise.Texte(Ctx.RaisonAlerte ?? "", Theme.Police(11f), Theme.Encre));
            r.Contenu.Ajouter(Mise.Texte("Détectée le " + DateTime.Now.ToString("dd/MM/yyyy à HH:mm:ss") + " sur " + Environment.MachineName + ".", Theme.Police(9.5f), Theme.Doux));

            var a = Corps.Ajouter(NouvelleCarte());
            a.Contenu.Ajouter(Intertitre("Ce que DigSpill a fait"));
            foreach (var x in Ctx.ActionsUrgence ?? new List<string>())
                a.Contenu.Ajouter(new LigneInfo(x.Contains("impossible") || x.Contains("refus") ? Niveau.Attention : Niveau.Ok, x, null));

            var t = Corps.Ajouter(NouvelleCarte());
            t.Contenu.Ajouter(Intertitre("À faire maintenant"));
            t.Contenu.Ajouter(new LigneInfo(Niveau.Danger, disque ? "Retirez le disque PREUVES maintenant" : "Retirez la clé PREUVES maintenant", "Ne le rebranchez que sur un PC sain et isolé, pour voir ce qui a été touché. Les fichiers-appâts restent : ce sont des preuves."));
            t.Contenu.Ajouter(new LigneInfo(Niveau.Attention, "Isolez le poste du réseau, sans l'éteindre", "Câble et Wi-Fi. Un chiffrement est probablement actif : il peut atteindre les partages et les sauvegardes."));
            t.Contenu.Ajouter(new LigneInfo(Niveau.Attention, "Prévenez", "Le responsable, le client et l'assureur. Notez l'heure de cette alerte dans le ticket."));
        }

        public override IEnumerable<Control> Boutons()
        {
            var c = new BoutonPlat("Fermer DigSpill", BoutonPlat.Genre.Secondaire, Ic.Ok);
            c.Click += delegate { F.Close(); };
            return new Control[] { c };
        }
    }
}
