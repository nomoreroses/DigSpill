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
                    c.RaisonAlerte = "Fichier piège modifié : !!!_0_Dossiers_patients_2026.xlsx";
                    c.ActionsUrgence = new List<string> { "Collecte arrêtée (PowerShell et ses programmes)", "Écriture bloquée sur le disque (lecture seule)", "Volume démonté de force (un autre programme l'utilisait)", "Lettre F: retirée : le support n'est plus visible des programmes" };
                    return new PageAlerte(f);
                case "analyser": return new PageSource(f);
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
            Color fond = choisie ? Theme.AccentClair : (survol && Utilisable ? Color.White : Theme.Blanc);
            using (var p = Theme.Arrondi(r, 12))
            using (var b = new SolidBrush(fond))
            using (var pen = new Pen(choisie ? Theme.Accent : Theme.Trait, choisie ? 2.5f : 1.2f))
            { g.FillPath(b, p); g.DrawPath(pen, p); }
            // bouton radio
            var rd = new Rectangle(18, 22, 20, 20);
            using (var pen = new Pen(choisie ? Theme.AccentEncre : Theme.Doux, 2f)) g.DrawEllipse(pen, rd);
            if (choisie) using (var b = new SolidBrush(Theme.AccentEncre)) g.FillEllipse(b, rd.X + 5, rd.Y + 5, 10, 10);
            TextRenderer.DrawText(g, icone, fI, new Rectangle(50, 14, 36, 36), Utilisable ? Theme.AccentEncre : Theme.Doux, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
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
            SousTitre = "DigSpill collecte les traces d'un poste Windows suspect sans les modifier, les scelle, puis produit le rapport sur un autre PC.";
            var g = Corps.Ajouter(new Grille { Colonnes = 2, Espace = 20 });
            var col = new CarteChoix(Ic.Collecter, "Collecter sur ce poste", "Sur le poste suspect. Saisie de l'intervention, contrôle « feu vert », collecte sur la clé PREUVES gardée par des fichiers pièges, scellé de fin de collecte.", "Droits administrateur demandés");
            var ana = new CarteChoix(Ic.Analyser, "Analyser une collecte", "Sur votre PC, plus tard. Copie vérifiée des preuves, analyse complète, interface et rapports, PV de collecte à faire signer.", "Sans droits administrateur");
            g.Controls.Add(col); g.Controls.Add(ana);
            col.Click += delegate { Collecter(); };
            ana.Click += delegate { F.Aller(new PageSource(F)); };

            var c = Corps.Ajouter(NouvelleCarte());
            c.Contenu.Ajouter(Intertitre("Deux clés, c'est plus sûr"));
            c.Contenu.Ajouter(new LigneInfo(Niveau.Info, "Clé OUTILS", "DigSpill et ses scripts. Clé à interrupteur, en position lecture seule : rien ne peut la modifier."));
            c.Contenu.Ajouter(new LigneInfo(Niveau.Info, "Clé PREUVES", "Chiffrée, branchée seulement après le feu vert, surveillée pendant la collecte, passée en lecture seule ensuite."));
            c.Contenu.Ajouter(new LigneInfo(Niveau.Info, "Une seule clé ?", "Possible : DigSpill pose quand même ses fichiers pièges et coupe la clé au moindre signe de chiffrement."));
        }

        public override IEnumerable<Control> Boutons()
        {
            var b = new BoutonPlat("Identifiants de ce compte", BoutonPlat.Genre.Secondaire, Ic.Personne);
            b.Click += delegate { ListerIdentifiants(); };
            return new Control[] { b };
        }

        /// <summary>Pour les autres comptes du poste : ouvrir leur session, lancer DigSpill.exe, ce bouton.</summary>
        void ListerIdentifiants()
        {
            if (Ctx.Demo) { MessageBox.Show(F, "Démonstration : en vrai, les cibles du gestionnaire d'identifiants de " + Identifiants.Compte + " seraient écrites dans F:\\Collecte\\Identifiants.", "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
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
                MessageBox.Show(F, "Cibles enregistrées pour " + Identifiants.Compte + " écrites dans :\r\n" + f + "\r\n\r\nRecommencer dans la session de chaque autre compte du poste.", "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex) { MessageBox.Show(F, "Écriture impossible dans " + cible + " : " + ex.Message, "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
        }

        void Collecter()
        {
            // les identifiants se lisent dans la session de l'utilisateur, SANS elevation : on les lit maintenant
            if (!Ctx.Demo && Ctx.IdentifiantsSession == null) { Ctx.IdentifiantsSession = Identifiants.Lister(); Ctx.CompteSession = Identifiants.Compte; }
            if (!Ctx.Demo && !Supports.EstAdmin())
            {
                string texte = Ctx.IdentifiantsSession.Length > 18000 ? Ctx.IdentifiantsSession.Substring(0, 18000) + "\r\n[tronqué]" : Ctx.IdentifiantsSession;
                try { Programme.Relancer("--collecter --identifiants=" + Identifiants.VersBase64(texte) + " --compte=" + Executeur.Echapper(Ctx.CompteSession), true); Application.Exit(); }
                catch (Win32Exception) { MessageBox.Show(F, "Les droits administrateur sont nécessaires pour collecter.", "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Information); }
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
            SousTitre = "Ces informations vont dans infos_collecte.txt, dans le scellé et dans le PV de collecte. Ne branchez pas encore la clé PREUVES.";
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
            var cb = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, FlatStyle = FlatStyle.Flat, BackColor = Color.White };
            cb.Items.AddRange(new object[] { "Rançongiciel ou chiffrement", "Intrusion ou prise en main à distance", "Fuite de données suspectée", "Comportement anormal du poste", "Autre" });
            cb.SelectedIndex = Math.Max(0, cb.Items.IndexOf(i.Motif));
            g2.Controls.Add(motif = new Champ("Motif", cb, false));
            g2.Controls.Add(ticket = Champ.Texte("N° de ticket", i.Ticket, false));
            var dtp = new DateTimePicker { Format = DateTimePickerFormat.Custom, CustomFormat = "dd/MM/yyyy HH:mm", ShowCheckBox = true, Checked = i.Decouverte.HasValue, Value = i.Decouverte ?? DateTime.Now };
            g2.Controls.Add(decouverte = new Champ("Découverte de l'incident (si connue)", dtp, false));
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
            if (manque.Count > 0) { MessageBox.Show(F, "À compléter : " + string.Join(", ", manque.ToArray()) + ".", "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            var i = Ctx.Inter;
            i.Prenom = prenom.Valeur; i.Nom = nom.Valeur; i.Societe = societe.Valeur; i.Cabinet = cabinet.Valeur;
            i.Present = present.Valeur; i.Ticket = ticket.Valeur; i.Motif = motif.Saisie.Text;
            var dtp = (DateTimePicker)decouverte.Saisie;
            i.Decouverte = dtp.Checked ? (DateTime?)dtp.Value : null;
            i.Legere = legere.Checked; i.AnalyseSurPlace = surPlace.Checked; i.Horodater = horodater.Checked;
            if (!Ctx.Demo) Ctx.Reglages.RetenirTechnicien(i.Prenom, i.Nom, i.Societe);
            F.Aller(new PageFeuVert(F));
        }
    }

    // ====================================================================== 2. feu vert
    class PageFeuVert : Page
    {
        readonly Carte bandeau, liste;
        readonly Label bTitre, bTexte, bEtape;
        readonly Barre barre = new Barre();
        readonly Case malgre;
        BoutonPlat continuer, relancer;
        bool enCours;

        public PageFeuVert(Fenetre f) : base(f)
        {
            Titre = "Feu vert avant de brancher la clé PREUVES";
            SousTitre = "DigSpill vérifie, sans rien modifier sur le poste, qu'aucun chiffrement n'est en cours. Ne branchez pas encore la clé PREUVES.";
            Parcours = ParcoursCollecte; Etape = 1;
            bandeau = Corps.Ajouter(NouvelleCarte());
            bTitre = bandeau.Contenu.Ajouter(Mise.Texte("Vérifications en cours…", Theme.Police(14f, FontStyle.Bold), Theme.Encre));
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
            bandeau.Couleurs(Theme.AccentClair, Theme.Accent);
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
            if (n == Niveau.Danger)
            {
                bTitre.Text = "Danger : ne branchez pas la clé PREUVES";
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
            liste.Contenu.Controls.Clear();
            foreach (var c in res.OrderByDescending(x => x.Niveau == Niveau.Danger ? 3 : x.Niveau == Niveau.Attention ? 2 : 0))
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

        public PageSupport(Fenetre f) : base(f)
        {
            Titre = "Branchez la clé PREUVES";
            SousTitre = "Clé chiffrée, déverrouillée, en lecture-écriture. DigSpill la détecte dès qu'elle est branchée.";
            Parcours = ParcoursCollecte; Etape = 2;
            liste = Corps.Ajouter(NouvelleCarte());
            remarque = Corps.Ajouter(new LigneInfo(Niveau.Info, "", ""));
            remarque.Visible = false;
            pieges = Corps.Ajouter(new Case("Poser des fichiers pièges sur la clé et la couper aussitôt si un programme y touche (recommandé)", Ctx.AvecPieges));
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
                    new Support { Lettre = "E:", Etiquette = "OUTILS", Systeme = "NTFS", Libre = 21L << 30, Total = 32L << 30, Usb = true, Amovible = true, EstOutils = true, LectureSeule = true } };
            return Supports.Lister(Ctx.RacineOutils);
        }

        void Remplir()
        {
            var l = Candidats();
            liste.Contenu.Controls.Clear();
            liste.Contenu.Ajouter(Intertitre("Supports détectés"));
            if (l.Count == 0) liste.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "En attente d'une clé USB…", "Branchez la clé PREUVES et déverrouillez-la (code PIN) : elle apparaît ici."));
            CarteSelection premiere = null;
            foreach (var s in l)
            {
                var b = new List<Tuple<string, Niveau>>();
                if (s.EstOutils) b.Add(Tuple.Create("Clé OUTILS", Niveau.Info));
                if (s.LectureSeule) b.Add(Tuple.Create("Protégée en écriture", s.EstOutils ? Niveau.Ok : Niveau.Danger));
                if (s.Systeme.StartsWith("FAT", StringComparison.OrdinalIgnoreCase)) b.Add(Tuple.Create("FAT32 : fichiers limités à 4 Go", Niveau.Attention));
                if (s.Libre < (16L << 30)) b.Add(Tuple.Create("Moins de 16 Go libres", Niveau.Attention));
                var c = new CarteSelection(Ic.Usb, s.Nom, s.Description, b) { Valeur = s, Utilisable = !s.LectureSeule };
                c.Choisie += (o, e) => Choisir((CarteSelection)o);
                liste.Contenu.Ajouter(c);
                if (premiere == null && c.Utilisable && !s.EstOutils) premiere = c;
                if (choisi != null && choisi.Lettre == s.Lettre && c.Utilisable) premiere = c;
            }
            choisi = null;
            if (premiere != null) Choisir(premiere); else MajRemarque();
            Ajuster();
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
            if (choisi != null && choisi.EstOutils)
            {
                remarque.Definir(Niveau.Attention, "Mode une seule clé", "La collecte ira sur la clé des outils. Possible, mais moins sûr : un rançongiciel pourrait atteindre les outils et les preuves à la fois.");
                remarque.Visible = true;
            }
            else if (choisi == null) remarque.Visible = false;
            else
            {
                remarque.Definir(Niveau.Ok, "La collecte ira dans " + choisi.Lettre + "\\Collecte\\", "Le dossier est créé s'il n'existe pas. Les fichiers pièges sont retirés à la fin, sauf en cas d'alerte.");
                remarque.Visible = true;
            }
            Ajuster();
        }

        void Lancer()
        {
            if (choisi == null) return;
            if (!Ctx.Demo)
            {
                if (choisi.Systeme.StartsWith("FAT", StringComparison.OrdinalIgnoreCase) &&
                    MessageBox.Show(F, "Clé en FAT32 : la capture de la mémoire et les conteneurs de plus de 4 Go ne pourront pas y être écrits.\r\n\r\nContinuer quand même ?", "DigSpill", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
                string err;
                if (!Supports.EssaiEcriture(Path.Combine(choisi.Racine, "Collecte"), out err))
                { MessageBox.Show(F, "Impossible d'écrire sur " + choisi.Lettre + " : " + err + "\r\n\r\nVérifiez que la clé est déverrouillée et en lecture-écriture.", "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Error); return; }
            }
            Ctx.Destination = choisi;
            Ctx.AvecPieges = pieges.Checked;
            F.Aller(new PageCollecte(F));
        }
    }

    // ====================================================================== 4. collecte
    class PageCollecte : Page
    {
        readonly Barre barre = new Barre();
        readonly Label etat, chrono;
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
            SousTitre = "Ne retirez pas les clés et ne fermez pas DigSpill. La clé PREUVES est surveillée en continu.";
            Parcours = ParcoursCollecte; Etape = 3;
            var c = Corps.Ajouter(NouvelleCarte());
            etat = c.Contenu.Ajouter(Mise.Texte("Préparation…", Theme.Police(12f, FontStyle.Bold), Theme.Encre));
            c.Contenu.Ajouter(barre);
            chrono = c.Contenu.Ajouter(Mise.Texte("", Theme.Police(9.5f), Theme.Doux));
            garde = Corps.Ajouter(new LigneInfo(Niveau.Attente, "Surveillance de la clé PREUVES", ""));
            var e = Corps.Ajouter(NouvelleCarte());
            e.Contenu.Ajouter(Intertitre("Étapes"));
            ePs = e.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "1. Collecte PowerShell", "Mémoire vive, journaux, comptes, connexions, persistance, traces de rançongiciel."));
            eVelo = e.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "2. Collecte Velociraptor", "$MFT, journal USN, registre, SRUM, Autoruns (lecture NTFS brute)."));
            eAna = e.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "3. Analyse rapide sur place", "Sessions, volumes envoyés, exécutions et navigation pendant les fenêtres suspectes."));
            eScelle = e.Contenu.Ajouter(new LigneInfo(Niveau.Attente, "4. Scellé de fin de collecte", "Empreinte SHA-256 du manifeste, du journal et des conteneurs ; horodatage si Internet."));
            Corps.Ajouter(journal);
            horloge.Tick += delegate { MajGarde(); if (Ctx.Debut != DateTime.MinValue) chrono.Text = "Démarrée à " + Ctx.Debut.ToString("HH:mm:ss") + " · " + Pages.Duree(DateTime.Now - Ctx.Debut) + " · destination " + Ctx.Destination.Racine + "Collecte"; };
        }

        public override IEnumerable<Control> Boutons()
        {
            var u = new BoutonPlat("Arrêt d'urgence", BoutonPlat.Genre.Danger, Ic.Arret);
            u.Click += delegate
            {
                if (MessageBox.Show(F, "Arrêter la collecte et couper la clé PREUVES immédiatement ?", "DigSpill", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes)
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
            if (!Ctx.AvecPieges) garde.Definir(Niveau.Attention, "Surveillance désactivée", "Aucun fichier piège sur la clé PREUVES.");
            else if (p == null) garde.Definir(Niveau.Attente, "Surveillance de la clé PREUVES", "Mise en place…");
            else garde.Definir(Niveau.Ok, "Clé PREUVES surveillée", string.Format("{0} fichiers pièges intacts · dernier contrôle {1:HH:mm:ss} · coupure automatique au premier signe", Ctx.Demo ? 4 : p.Nombre, p.DernierControle == DateTime.MinValue ? DateTime.Now : p.DernierControle));
        }

        void Progression(double v) { Ui(() => barre.Valeur = v); }

        void Ligne(string l)
        {
            Log(l);
            var m = Regex.Match(l, @"\[\*\]\s+(.+)$");
            if (m.Success)
            {
                etapesVues++;
                int prevu = Ctx.Inter.Legere ? 24 : 36;
                if (etapesVues >= prevu) prevu = etapesVues + 2;
                Etat("Collecte PowerShell : " + m.Groups[1].Value);
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
                etat.Text = "Erreur : " + ex.Message;
                Titre = "Collecte interrompue"; F.MajEntete(); Ajuster();
            }
        }

        async Task Derouler()
        {
            Occupee = true;
            Ctx.Debut = DateTime.Now;
            horloge.Start();
            var d = Ctx.Destination;
            Ctx.DossierCollecteRacine = Path.Combine(d.Racine, "Collecte");
            var i = Ctx.Inter;
            Log(string.Format("DigSpill {0} · {1} · technicien {2} · cabinet {3} · destination {4}", Programme.Version, Environment.MachineName, i.Technicien, i.Cabinet, d.Racine));
            if (Ctx.FeuVert != null && Verifications.Global(Ctx.FeuVert) == Niveau.Danger) Log("[!] Feu vert en DANGER : le technicien a choisi de continuer.");

            // --- pieges
            if (Ctx.AvecPieges)
            {
                try
                {
                    Ctx.Pieges = new Pieges(d.Racine);
                    if (!Ctx.Demo) { Ctx.Pieges.Poser(); Ctx.Pieges.Alerte += r => BeginInvoke(new Action(() => Urgence(r))); Ctx.Pieges.Surveiller(); }
                    Log("Fichiers pièges posés et surveillés sur " + d.Racine);
                }
                catch (Exception ex) { Log("[!] Fichiers pièges impossibles : " + ex.Message); Ctx.Pieges = null; Ctx.AvecPieges = false; }
            }
            MajGarde();

            // --- 1. PowerShell
            ePs.Etat(Niveau.EnCours);
            baseProgression = 0; partProgression = i.Legere ? 0.85 : 0.55;
            // powershell.exe -File perd les arguments vides : on ne passe que les champs remplis
            var ap = new List<string> { "-Mode", i.Legere ? "Leger" : "Complet", "-Destination", Executeur.Echapper(d.Racine) };
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
            ePs.Definir(code == 0 && Ctx.NomCollecte != null ? Niveau.Ok : Niveau.Attention, "1. Collecte PowerShell", Ctx.NomCollecte != null ? "Dossier " + Ctx.NomCollecte + (code == 0 ? "" : " (code de sortie " + code + ", voir collecte.log)") : "Dossier de collecte introuvable : voir le journal ci-dessous.");

            // --- 2. Velociraptor
            if (i.Legere) eVelo.Definir(Niveau.Ignore, "2. Collecte Velociraptor", "Pas en collecte légère.");
            else if (!Ctx.Demo && !File.Exists(Ctx.Velociraptor)) eVelo.Definir(Niveau.Attention, "2. Collecte Velociraptor", "Collecteur-Velociraptor.exe absent de la clé OUTILS : étape sautée.");
            else
            {
                eVelo.Etat(Niveau.EnCours);
                Etat("Collecte Velociraptor : $MFT, registre, journaux (plusieurs minutes)…");
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
                eVelo.Definir(cv == 0 ? Niveau.Ok : Niveau.Attention, "2. Collecte Velociraptor", cv == 0 ? "Conteneur écrit dans " + dv : "Code de sortie " + cv + " : voir le journal.");
            }
            Progression(0.9);

            // --- 3. analyse sur place
            if (!i.AnalyseSurPlace) eAna.Definir(Niveau.Ignore, "3. Analyse rapide sur place", "Non demandée : à faire au bureau (DigSpill → Analyser une collecte).");
            else
            {
                eAna.Etat(Niveau.EnCours);
                baseProgression = 0.9; partProgression = 0;
                int ca = await Executer("Analyse-Exfil.ps1", new List<string> { "-Collecte", Executeur.Echapper(Ctx.DossierCollecteRacine), "-DerniereDuPoste", "-SansMFT", "-SansHashConteneurs" }, "Analyse rapide");
                if (urgence) return;
                eAna.Definir(ca == 0 ? Niveau.Ok : Niveau.Attention, "3. Analyse rapide sur place", ca == 0 ? "Synthèse dans " + Ctx.NomCollecte + "_analyse\\SYNTHESE_EXFILTRATION.txt" : "Analyse en échec (code " + ca + ") : la refaire au bureau.");
            }

            // --- 4. scelle
            eScelle.Etat(Niveau.EnCours);
            Etat("Scellé : calcul des empreintes…");
            Ui(() => barre.Indeterminee = true);
            string par = i.Technicien + (i.Societe != "" ? " (" + i.Societe + ")" : "") + " - " + Environment.UserDomainName + "\\" + Environment.UserName;
            if (Ctx.Demo) { await Task.Delay(1200); Pages.RemplirDemo(Ctx); }
            else if (Ctx.NomCollecte != null)
            {
                Ctx.Scelle = await Task.Run(() => Scelle.Creer(Ctx.DossierCollecteRacine, Ctx.NomCollecte, par, Ctx.Debut, s => Etat("Scellé : " + s)));
                if (Ctx.Scelle.Erreur == null && i.Horodater)
                {
                    Etat("Scellé : horodatage par " + Ctx.Horodateur + "…");
                    await Task.Run(() => Scelle.Horodater(Ctx.Scelle, Ctx.Horodateur));
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
                return Simuler(new[] { "[*] Informations sur le poste", "[*] Processus et connexions réseau", "[*] Mémoire vive (winpmem) et fichiers d'échange", "[*] Journaux d'événements",
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
            if (!Ctx.Demo) faits.AddRange(Supports.VerrouillageUrgence(Ctx.Destination.Lettre));
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
            Titre = Ctx.CollecteOk ? "Collecte terminée" : "Collecte terminée avec des avertissements";
            SousTitre = "Photographiez l'empreinte ci-dessous avec votre téléphone, puis éjectez la clé PREUVES avant de la débrancher.";
            Parcours = ParcoursCollecte; Etape = 4;

            sombre = Corps.Ajouter(NouvelleCarte());
            sombre.Couleurs(Theme.Nuit, Theme.Nuit);
            sombre.Padding = new Padding(26, 22, 26, 22);
            sombre.Contenu.Ajouter(Mise.Texte("EMPREINTE DU SCELLÉ (SHA-256)", Theme.Police(9f, FontStyle.Bold), Theme.Accent));
            var emp = sombre.Contenu.Ajouter(new Empreinte());
            emp.Text = sc != null && sc.Empreinte != null ? sc.Empreinte : "aucun scellé";
            sombre.Contenu.Ajouter(pastilles);
            fichierScelle = sombre.Contenu.Ajouter(Mise.Texte(sc != null && sc.Fichier != null ? sc.Fichier : "", Theme.Police(9f), Theme.DouxNuit));
            MajPastilles();

            var a = Corps.Ajouter(NouvelleCarte());
            a.Contenu.Ajouter(Intertitre("Avant de partir"));
            a.Contenu.Ajouter(new LigneInfo(Niveau.Info, "Photographier l'empreinte", "Avec la date et l'heure du téléphone : une trace indépendante de la clé, au cas où elle serait perdue ou abîmée."));
            a.Contenu.Ajouter(new LigneInfo(Niveau.Info, "Identifiants enregistrés", "Ce compte (" + (Ctx.CompteSession ?? Identifiants.Compte) + ") : déjà listé. Autres comptes du poste : ouvrir leur session, lancer DigSpill.exe, « Identifiants de ce compte »."));
            a.Contenu.Ajouter(new LigneInfo(Niveau.Info, "Clé PREUVES en lecture seule", "Après l'éjection : passez la clé en mode lecture seule (clé à code : voir sa notice) et rangez-la à part."));
            a.Contenu.Ajouter(new LigneInfo(Niveau.Info, "Au bureau", "DigSpill → Analyser une collecte : copie vérifiée, analyse complète, rapport, PV de collecte à faire signer."));
        }

        void MajPastilles()
        {
            var sc = Ctx.Scelle;
            pastilles.Controls.Clear();
            if (sc != null && sc.DateJeton != null) pastilles.Controls.Add(new Pastille("Horodaté le " + sc.DateJeton, Theme.Nuit, Theme.VertFond));
            else pastilles.Controls.Add(new Pastille("À horodater au bureau" + (sc != null && sc.ErreurHorodatage != null ? " · " + sc.ErreurHorodatage : ""), Theme.Nuit, Theme.OrangeFond));
            if (sc != null) pastilles.Controls.Add(new Pastille(sc.NombreElements + " fichiers scellés", Theme.Nuit, Theme.BleuFond));
            if (Ctx.Fin > Ctx.Debut) pastilles.Controls.Add(new Pastille("Durée " + Pages.Duree(Ctx.Fin - Ctx.Debut), Theme.Nuit, Theme.BleuFond));
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
                    if (sc.DateJeton == null && sc.ErreurHorodatage != null) MessageBox.Show(F, "Horodatage impossible : " + sc.ErreurHorodatage + "\r\n\r\nLe scellé reste valable : il sera horodaté au bureau.", "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    MajPastilles();
                };
                l.Add(horodater);
            }
            ejecter = new BoutonPlat("Éjecter la clé PREUVES", BoutonPlat.Genre.Primaire, Ic.Verrou);
            ejecter.Click += delegate { if (ejectee) F.Close(); else Ejecter(); };
            l.Add(ejecter);
            return l;
        }

        void Ejecter()
        {
            if (Ctx.Pieges != null) Ctx.Pieges.Retirer();
            string err = Ctx.Demo ? null : Supports.Ejecter(Ctx.Destination.Lettre, false);
            if (err != null)
            {
                var r = MessageBox.Show(F, err + "\r\n\r\nOui : forcer l'éjection (les données sont déjà écrites).\r\nNon : je ferme les fenêtres et je réessaie.", "DigSpill", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                if (r != DialogResult.Yes) return;
                err = Supports.Ejecter(Ctx.Destination.Lettre, true);
                if (err != null) { MessageBox.Show(F, "Éjection impossible : " + err + "\r\nUtilisez « Retirer le périphérique en toute sécurité » de Windows.", "DigSpill", MessageBoxButtons.OK, MessageBoxIcon.Error); return; }
            }
            ejectee = true;
            Titre = "Clé PREUVES éjectée";
            SousTitre = "Vous pouvez la débrancher. Passez-la en lecture seule et rangez-la séparément de la clé OUTILS.";
            ejecter.Text = "Fermer DigSpill";
            ejecter.Icone = Ic.Ok;
            pastilles.Controls.Add(new Pastille("Clé éjectée", Theme.Nuit, Theme.VertFond));
            F.MajEntete();
            Ajuster();
        }
    }

    // ====================================================================== alerte
    class PageAlerte : Page
    {
        public PageAlerte(Fenetre f) : base(f)
        {
            Titre = "Clé PREUVES coupée";
            SousTitre = "DigSpill a détecté une activité suspecte sur la clé et l'a déconnectée aussitôt.";
            Parcours = ParcoursCollecte; Etape = 3;
            var r = Corps.Ajouter(NouvelleCarte());
            r.Couleurs(Theme.RougeFond, Theme.Rouge);
            r.Epaisseur = 2f;
            r.Contenu.Ajouter(Mise.Texte("Activité détectée", Theme.Police(14f, FontStyle.Bold), Theme.Rouge));
            r.Contenu.Ajouter(Mise.Texte(Ctx.RaisonAlerte ?? "", Theme.Police(11f), Theme.Encre));
            r.Contenu.Ajouter(Mise.Texte("Détectée le " + DateTime.Now.ToString("dd/MM/yyyy à HH:mm:ss") + " sur " + Environment.MachineName + ".", Theme.Police(9.5f), Theme.Doux));

            var a = Corps.Ajouter(NouvelleCarte());
            a.Contenu.Ajouter(Intertitre("Ce que DigSpill a fait"));
            foreach (var x in Ctx.ActionsUrgence ?? new List<string>())
                a.Contenu.Ajouter(new LigneInfo(x.Contains("impossible") || x.Contains("refus") ? Niveau.Attention : Niveau.Ok, x, null));

            var t = Corps.Ajouter(NouvelleCarte());
            t.Contenu.Ajouter(Intertitre("À faire maintenant"));
            t.Contenu.Ajouter(new LigneInfo(Niveau.Danger, "Retirez la clé PREUVES maintenant", "Ne la rebranchez que sur un PC sain et isolé, pour voir ce qui a été touché. Les fichiers pièges restent : ce sont des preuves."));
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
