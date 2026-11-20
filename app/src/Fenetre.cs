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
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            // ---------------------------------------------------------- barre laterale
            laterale = new Panel { Dock = DockStyle.Left, Width = 270, BackColor = Theme.Nuit };
            var logo = new Logo { Bounds = new Rectangle(26, 28, 236, 76) };
            etapes = new ListeEtapes { Bounds = new Rectangle(26, 138, 230, 280), Anchor = AnchorStyles.Top | AnchorStyles.Left };
            infoCle = Mise.Texte("", Theme.Police(8.5f), Theme.DouxNuit);
            infoCle.Dock = DockStyle.Bottom; infoCle.Height = 112; infoCle.Padding = new Padding(26, 0, 16, 18);
            laterale.Controls.Add(logo); laterale.Controls.Add(etapes); laterale.Controls.Add(infoCle);

            // ---------------------------------------------------------- zone principale
            zone = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Papier, Padding = new Padding(44, 30, 40, 0) };
            entete = new Panel { Dock = DockStyle.Top, Height = 92, BackColor = Theme.Papier };
            titre = Mise.Texte("", Theme.Police(21f, FontStyle.Bold), Theme.Encre);
            sousTitre = Mise.Texte("", Theme.Police(10.5f), Theme.Doux);
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

        class Logo : Control
        {
            readonly Font f = Theme.Police(22f, FontStyle.Bold), s = Theme.Police(7.5f, FontStyle.Bold);
            public Logo() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true); }
            protected override void OnPaint(PaintEventArgs e)
            {
                var g = e.Graphics;
                g.Clear(Theme.Nuit);
                Theme.Qualite(g);
                using (var b = new SolidBrush(Theme.Accent)) g.FillRectangle(b, 0, 6, 6, 40);
                TextRenderer.DrawText(g, "DigSpill", f, new Point(16, 0), Color.White, TextFormatFlags.NoPadding);
                TextRenderer.DrawText(g, "COLLECTER · COMPRENDRE · PROUVER", s, new Point(18, 52), Theme.Accent, TextFormatFlags.NoPadding);
            }
        }

        class LignePied : Panel
        {
            public LignePied() { BackColor = Theme.Papier; SetStyle(ControlStyles.ResizeRedraw, true); }
        }
    }
}
