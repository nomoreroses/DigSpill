// DigSpill - fenetre principale : barre laterale, en-tete, page, boutons.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace DigSpill
{
    abstract class Page : Panel
    {
        protected readonly Fenetre F;
        protected readonly Contexte Ctx;
        protected readonly Colonne Corps = new Colonne();
        public string Titre = "", SousTitre = "";
        public string[] Parcours;
        public int Etape = -1;
        public bool Occupee;

        public static readonly string[] ParcoursCollecte = { "Intervention", "Feu vert", "Clé PREUVES", "Collecte", "Scellé et éjection" };
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
        readonly Label titre, sousTitre, infoCle;
        readonly ListeEtapes etapes;
        readonly FlowLayoutPanel boutons;
        Page courante;
        readonly Timer rebond = new Timer { Interval = 900 };
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
            infoCle = Mise.Texte("", Theme.Mono(8f), Theme.Texte3);
            infoCle.Dock = DockStyle.Bottom; infoCle.Height = 112; infoCle.Padding = new Padding(26, 0, 16, 18);
            laterale.Controls.Add(logo); laterale.Controls.Add(etapes); laterale.Controls.Add(infoCle);
            laterale.Controls.Add(new Panel { Dock = DockStyle.Right, Width = 1, BackColor = Theme.Ligne }); // filet sur toute la hauteur (ajoute en dernier : ancre en premier)

            // ---------------------------------------------------------- zone principale
            zone = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Papier, Padding = new Padding(44, 30, 40, 0) };
            entete = new Panel { Dock = DockStyle.Top, Height = 92, BackColor = Theme.Papier };
            titre = Mise.Texte("", Theme.Police(22f, FontStyle.Bold), Theme.Texte);
            sousTitre = Mise.Texte("", Theme.Police(11f), Theme.Texte2);
            entete.Controls.Add(titre); entete.Controls.Add(sousTitre);
            entete.Layout += delegate
            {
                int w = entete.ClientSize.Width;
                int ht = Mise.HauteurTexte(titre.Text, titre.Font, w) + 2;
                titre.SetBounds(0, 0, w, ht);
                int hs = Mise.HauteurTexte(sousTitre.Text, sousTitre.Font, w) + 2;
                sousTitre.SetBounds(0, ht + 4, w, hs);
                int total = ht + 4 + hs + 20;
                if (entete.Height != total) entete.Height = total;
            };
            pied = new LignePied { Dock = DockStyle.Bottom, Height = 76 };
            boutons = new FlowLayoutPanel { Dock = DockStyle.Right, AutoSize = true, FlowDirection = FlowDirection.RightToLeft, WrapContents = false, Padding = new Padding(0, 17, 0, 0), BackColor = Theme.Papier };
            pied.Controls.Add(boutons);
            pied.Controls.Add(new Panel { Dock = DockStyle.Top, Height = 1, BackColor = Theme.Trait });
            hote = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Papier };
            zone.Controls.Add(hote); zone.Controls.Add(pied); zone.Controls.Add(entete);
            Controls.Add(zone); Controls.Add(laterale);

            rebond.Tick += delegate { rebond.Stop(); MajInfoCle(); var a = SupportsChanges; if (a != null) a(); };
            MajInfoCle();
            FormClosing += (s, e) =>
            {
                if (courante != null && courante.Occupee && e.CloseReason == CloseReason.UserClosing &&
                    MessageBox.Show(this, "Une opération est en cours. Quitter quand même ?\r\n\r\nLa collecte en cours sera incomplète.", "DigSpill", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                    e.Cancel = true;
            };

            FormClosed += delegate { if (courante != null) courante.Quittee(); };
            Load += delegate { Aller(Pages.Depart(this, depart)); };
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

        public void MajInfoCle()
        {
            string r = Path.GetPathRoot(Ctx.RacineOutils);
            bool ro = Ctx.Demo || Supports.LectureSeule(r);
            infoCle.Text = "Outils : " + r + (ro ? "  · lecture seule ✓" : "  · accessible en écriture") + "\r\n" +
                           (Supports.EstAdmin() || Ctx.Demo ? "Administrateur ✓" : "Sans droits administrateur") + "\r\n" +
                           "DigSpill " + Programme.Version + (Ctx.Demo ? " · démonstration" : "");
        }

        public void Aller(Page p)
        {
            if (courante != null) { courante.Quittee(); hote.Controls.Remove(courante); courante.Dispose(); }
            courante = p;
            p.Dock = DockStyle.Fill;
            hote.Controls.Add(p);
            MajEntete();
            p.Affichee();
            p.Ajuster();
        }

        public void MajEntete()
        {
            if (courante == null) return;
            titre.Text = courante.Titre;
            sousTitre.Text = courante.SousTitre;
            entete.PerformLayout();
            boutons.Controls.Clear();
            foreach (var b in courante.Boutons().Reverse()) boutons.Controls.Add(b);
            etapes.Definir(courante.Parcours, courante.Etape);
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
