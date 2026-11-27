// DigSpill - fenetre principale : barre laterale, en-tete, page, boutons.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace DigSpill
{
    abstract class Page : Panel
    {
        protected readonly Fenetre F;
        protected readonly Contexte Ctx;
        protected readonly Colonne Corps = new Colonne();
        public string Titre = "", SousTitre = "";
        /// <summary>Explications repliees sous le sous-titre (« En savoir plus ») : le sous-titre ne garde qu'une phrase d'action.</summary>
        public string Details = "";
        public string[] Parcours;
        public int Etape = -1;
        public bool Occupee;
        /// <summary>Fabrique de la page vers laquelle revenir en cliquant sur une etape precedente du parcours (null : etape non cliquable).</summary>
        public virtual Func<Page> EtapePrecedente(int etape) { return null; }

        public static readonly string[] ParcoursCollecte = { "Intervention", "Feu vert", "Support PREUVES", "Collecte", "Scellé et éjection" };
        public static readonly string[] ParcoursAnalyse = { "Collecte à analyser", "Analyse", "Rapport" };

        protected Page(Fenetre f)
        {
            F = f; Ctx = f.Ctx;
            AutoScroll = true;
            BackColor = Theme.Papier;
            Corps.Espace = 16;
            Corps.Padding = new Padding(0, 4, 8, 16);
            Controls.Add(Corps);
            Theme.Sombre(this);
        }

        public virtual IEnumerable<Control> Boutons() { return new Control[0]; }
        public virtual void Affichee() { }
        public virtual void Quittee() { }

        protected override void OnLayout(LayoutEventArgs e) { base.OnLayout(e); Ajuster(); }

        public void Ajuster()
        {
            int w = ClientSize.Width;
            int h = Corps.HauteurPour(w);
            if (h > ClientSize.Height) { w -= SystemInformation.VerticalScrollBarWidth; h = Corps.HauteurPour(w); }
            Corps.SetBounds(AutoScrollPosition.X, AutoScrollPosition.Y, Math.Max(100, w), h);
            Corps.Disposer();
        }

        protected static Label Paragraphe(string t) { return Mise.Texte(t, Theme.Police(10.5f), Theme.Doux); }
        protected static Label Intertitre(string t) { return Mise.Texte(t, Theme.Police(12.5f, FontStyle.Bold), Theme.Encre); }
        protected static Carte NouvelleCarte() { return new Carte(); }
    }

    class Fenetre : Form
    {
        public readonly Contexte Ctx;
        readonly Panel laterale, zone, entete, pied, hote;
        readonly Label titre, sousTitre, lienDetails, texteDetails;
        bool detailsOuverts;
        readonly EtatPoste infoCle = new EtatPoste();
        readonly ListeEtapes etapes;
        readonly FlowLayoutPanel boutons;
        Page courante;
        readonly Timer rebond = new Timer { Interval = 900 };
        // pendant une collecte ou une analyse : ni veille ni ecran eteint (rappel toutes les 30 s, rien a defaire ensuite)
        readonly Timer eveil = new Timer { Interval = 30000 };
        [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint etat);
        const uint ES_SYSTEM_REQUIRED = 0x1, ES_DISPLAY_REQUIRED = 0x2;
        public void GarderEveille() { if (courante != null && courante.Occupee) try { SetThreadExecutionState(ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED); } catch (EntryPointNotFoundException) { } catch (DllNotFoundException) { } }   // hors Windows (tests sous Mono) : sans effet
        public event Action SupportsChanges;

        public Fenetre(Contexte ctx, string depart, string capture)
        {
            Ctx = ctx;
            Text = "DigSpill" + (ctx.Demo ? "  (démonstration)" : "");
            Font = Theme.Police(10f);
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(1200, 780);
            MinimumSize = new Size(1000, 680);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Theme.Papier;
            Theme.BarreTitreSombre(this);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            // ---------------------------------------------------------- barre laterale
            laterale = new Panel { Dock = DockStyle.Left, Width = 270, BackColor = Theme.Fond };
            var logo = new Logo { Bounds = new Rectangle(28, 30, 160, 40) };
            etapes = new ListeEtapes { Bounds = new Rectangle(28, 118, 228, 280), Anchor = AnchorStyles.Top | AnchorStyles.Left };
            infoCle.Dock = DockStyle.Bottom; infoCle.Padding = new Padding(18, 0, 18, 18);
            laterale.Controls.Add(logo); laterale.Controls.Add(etapes); laterale.Controls.Add(infoCle);
            laterale.Controls.Add(new Panel { Dock = DockStyle.Right, Width = 1, BackColor = Theme.Ligne }); // filet sur toute la hauteur (ajoute en dernier : ancre en premier)

            // ---------------------------------------------------------- zone principale
            zone = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Papier, Padding = new Padding(44, 30, 40, 0) };
            entete = new Panel { Dock = DockStyle.Top, Height = 92, BackColor = Theme.Papier };
            titre = Mise.Texte("", Theme.Police(22f, FontStyle.Bold), Theme.Texte);
            sousTitre = Mise.Texte("", Theme.Police(11f), Theme.Texte);
            // le detail de la page reste replie : une phrase d'action en haut, le reste au clic
            lienDetails = Mise.Texte("", Theme.Police(10f), Theme.Texte2);
            lienDetails.Cursor = Cursors.Hand; lienDetails.AccessibleRole = AccessibleRole.Link;
            lienDetails.Click += delegate { detailsOuverts = !detailsOuverts; MajDetails(); };
            lienDetails.MouseEnter += delegate { lienDetails.ForeColor = Theme.Texte; };
            lienDetails.MouseLeave += delegate { lienDetails.ForeColor = Theme.Texte2; };
            texteDetails = Mise.Texte("", Theme.Police(10f), Theme.Texte2);
            entete.Controls.Add(titre); entete.Controls.Add(sousTitre); entete.Controls.Add(lienDetails); entete.Controls.Add(texteDetails);
            entete.Layout += delegate
            {
                int w = entete.ClientSize.Width;
                int ht = Mise.HauteurTexte(titre.Text, titre.Font, w) + 2;
                titre.SetBounds(0, 0, w, ht);
                int hs = Mise.HauteurTexte(sousTitre.Text, sousTitre.Font, w) + 2;
                sousTitre.SetBounds(0, ht + 4, w, hs);
                int y = ht + 4 + hs;
                if (lienDetails.Visible)
                {
                    int hl = TextRenderer.MeasureText(lienDetails.Text, lienDetails.Font).Height;
                    lienDetails.SetBounds(0, y + 6, TextRenderer.MeasureText(lienDetails.Text, lienDetails.Font).Width + 6, hl);
                    y += 6 + hl;
                    if (texteDetails.Visible)
                    {
                        int hd = Mise.HauteurTexte(texteDetails.Text, texteDetails.Font, Math.Min(w, 760)) + 2;
                        texteDetails.SetBounds(0, y + 6, Math.Min(w, 760), hd);
                        y += 6 + hd;
                    }
                }
                int total = y + 20;
                if (entete.Height != total) entete.Height = total;
            };
            pied = new LignePied { Dock = DockStyle.Bottom, Height = 76 };
            // haut a 17 px : 8 de marge + 9 de place pour une pastille (BoutonPlat.Debord)
            boutons = new FlowLayoutPanel { Dock = DockStyle.Right, AutoSize = true, FlowDirection = FlowDirection.RightToLeft, WrapContents = false, Padding = new Padding(0, 17 - BoutonPlat.Debord, 0, 0), BackColor = Theme.Papier };
            pied.Controls.Add(boutons);
            pied.Controls.Add(new Panel { Dock = DockStyle.Top, Height = 1, BackColor = Theme.Trait });
            hote = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Papier };
            zone.Controls.Add(hote); zone.Controls.Add(pied); zone.Controls.Add(entete);
            Controls.Add(zone); Controls.Add(laterale);

            rebond.Tick += delegate { rebond.Stop(); MajInfoCle(); var a = SupportsChanges; if (a != null) a(); };
            eveil.Tick += delegate { GarderEveille(); };
            eveil.Start();
            etapes.EtapeCliquee += i =>
            {
                if (courante == null || courante.Occupee || i >= courante.Etape) return;
                var fabrique = courante.EtapePrecedente(i);
                if (fabrique != null) Aller(fabrique());
            };
            MajInfoCle();
            FormClosing += (s, e) =>
            {
                if (courante != null && courante.Occupee && e.CloseReason == CloseReason.UserClosing &&
                    !Boite.Confirmer(this, Niveau.Attention, "Quitter pendant l'opération en cours ?", "La collecte ou l'analyse en cours sera incomplète. Ce qui est déjà écrit reste sur le support.", "Quitter quand même", "Continuer", true))
                    e.Cancel = true;
            };

            FormClosed += delegate { if (courante != null) courante.Quittee(); };
            Load += delegate { Aller(Pages.Depart(this, depart)); };
            // recherche de mise a jour au demarrage : seulement sur un PC de bureau deja reconnu, jamais sur un poste examine
            Shown += delegate
            {
                if (ctx.Demo) ResultatMiseAJour(MiseAJour.Demo(MiseAJour.VersionKit(ctx.RacineOutils) ?? Programme.VersionKit));
                else if (!ctx.SansInternetAuDemarrage && MiseAJour.PcDeBureau) ChercherMiseAJour();
            };
            if (!string.IsNullOrEmpty(capture))
            {
                var t = new Timer { Interval = 2600 };
                t.Tick += delegate
                {
                    t.Stop();
                    using (var bmp = new Bitmap(Width, Height))
                    {
                        DrawToBitmap(bmp, new Rectangle(0, 0, Width, Height));
                        bmp.Save(capture, ImageFormat.Png);
                    }
                    Environment.Exit(0);
                };
                Shown += delegate { t.Start(); };
            }
        }

        /// <summary>Page affichee et boutons du pied de page (lus par le pilote automatique).</summary>
        public Page Courante { get { return courante; } }
        public IEnumerable<Control> BoutonsPied { get { return boutons.Controls.Cast<Control>().ToList(); } }

        /// <summary>Derniere version publiee, si elle est plus recente que le kit (pastille « 1 » sur « Mises à jour »).</summary>
        public MiseAJour.Release MiseAJourDispo;
        bool versionVerifiee;

        async void ChercherMiseAJour()
        {
            try { var r = await System.Threading.Tasks.Task.Run(() => MiseAJour.Derniere()); ResultatMiseAJour(r); }
            catch { }   // pas d'Internet : rien a signaler, le bouton reste disponible
        }

        /// <summary>Resultat d'une recherche (au demarrage ou sur la page Mises a jour).</summary>
        public void ResultatMiseAJour(MiseAJour.Release r)
        {
            if (IsDisposed) return;
            versionVerifiee = true;
            MiseAJourDispo = MiseAJour.PlusRecente(r, MiseAJour.VersionKit(Ctx.RacineOutils) ?? Programme.VersionKit) ? r : null;
            MajEntete();
            MajInfoCle();
        }

        /// <summary>Bas de la barre laterale : support des outils, droits, version. Orange seulement la ou ca compte : pendant une collecte.</summary>
        public void MajInfoCle()
        {
            bool collecte = courante != null && courante.Parcours == Page.ParcoursCollecte;
            string r = Path.GetPathRoot(Ctx.RacineOutils) ?? "";
            string lettre = r.TrimEnd('\\');
            bool ro = Ctx.Demo || Supports.LectureSeule(r), admin = Ctx.Demo || Supports.EstAdmin();
            bool cle = Ctx.Demo;
            if (!Ctx.Demo) try { cle = new DriveInfo(r).DriveType == DriveType.Removable; } catch { }
            if (Ctx.Demo) lettre = "F:";
            var lignes = new List<EtatPoste.Ligne>();
            if (cle && ro) lignes.Add(new EtatPoste.Ligne(Niveau.Ok, "Clé " + lettre + " protégée en écriture", "Outils intègres"));
            else if (cle) lignes.Add(collecte ? new EtatPoste.Ligne(Niveau.Attention, "Clé " + lettre + " non protégée", "Activer la protection en écriture")
                                              : new EtatPoste.Ligne(Niveau.Attente, "Clé " + lettre + " non protégée", "Requis seulement pour collecter"));
            else lignes.Add(collecte ? new EtatPoste.Ligne(Niveau.Attention, "Exécution depuis " + lettre, "Lancer DigSpill depuis une clé protégée")
                                     : new EtatPoste.Ligne(Niveau.Attente, "Exécution depuis " + lettre, "Mode analyse"));
            if (admin) lignes.Add(new EtatPoste.Ligne(Niveau.Ok, "Droits administrateur", "Collecte complète possible"));
            else lignes.Add(collecte ? new EtatPoste.Ligne(Niveau.Attention, "Droits administrateur absents", "Relancer en tant qu'administrateur")
                                     : new EtatPoste.Ligne(Niveau.Attente, "Droits standard", "Suffisants pour l'analyse"));
            string v = "Version " + Programme.VersionKit;
            if (MiseAJourDispo != null) lignes.Add(new EtatPoste.Ligne(Niveau.Danger, v, MiseAJourDispo.Tag.TrimStart('v') + " disponible"));
            else if (versionVerifiee) lignes.Add(new EtatPoste.Ligne(Niveau.Ok, v, "À jour"));
            else lignes.Add(new EtatPoste.Ligne(Niveau.Attente, v, Ctx.Demo ? "Démonstration" : "Kit de la clé"));
            infoCle.Definir(lignes);
        }

        public void Aller(Page p)
        {
            if (courante != null) { courante.Quittee(); hote.Controls.Remove(courante); courante.Dispose(); }
            courante = p;
            detailsOuverts = false;
            p.Dock = DockStyle.Fill;
            hote.Controls.Add(p);
            MajEntete();
            p.Affichee();
            p.Ajuster();
            GarderEveille();
        }

        void MajDetails()
        {
            bool d = courante != null && !string.IsNullOrEmpty(courante.Details);
            lienDetails.Visible = d;
            texteDetails.Visible = d && detailsOuverts;
            lienDetails.Text = (detailsOuverts ? "▾  Moins de détails" : "▸  En savoir plus");
            texteDetails.Text = d ? courante.Details : "";
            entete.PerformLayout();
        }

        public void MajEntete()
        {
            if (courante == null) return;
            titre.Text = courante.Titre;
            sousTitre.Text = courante.SousTitre;
            MajDetails();
            boutons.Controls.Clear();
            foreach (var b in courante.Boutons().Reverse())
            {
                // tous les boutons alignes : ceux sans pastille descendent de la place qu'elle prendrait
                var bp = b as BoutonPlat;
                b.Margin = new Padding(b.Margin.Left, bp != null && bp.Pastille > 0 ? 0 : BoutonPlat.Debord, b.Margin.Right, b.Margin.Bottom);
                boutons.Controls.Add(b);
            }
            MajInfoCle();
            etapes.Definir(courante.Parcours, courante.Etape);
            var cliquables = new HashSet<int>();
            for (int i = 0; i < courante.Etape; i++) if (!courante.Occupee && courante.EtapePrecedente(i) != null) cliquables.Add(i);
            etapes.Cliquables = cliquables;
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x0219) { rebond.Stop(); rebond.Start(); } // WM_DEVICECHANGE : cle branchee ou retiree
            base.WndProc(ref m);
        }

        /// <summary>Logo « digspill » au point rouge, vectoriel (meme trace que le SVG de l'interface HTML).</summary>
        class Logo : Control
        {
            public Logo() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
            protected override void OnPaint(PaintEventArgs e)
            {
                e.Graphics.Clear(Theme.Fond);
                Theme.DessinerLogo(e.Graphics, new PointF(0, 4), Math.Min(Height - 8, Width / 3.6f), Theme.Texte);
            }
        }

        class LignePied : Panel
        {
            public LignePied() { BackColor = Theme.Papier; SetStyle(ControlStyles.ResizeRedraw, true); }
        }
    }
}
