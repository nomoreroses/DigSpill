// DigSpill - controles dessines (boutons, cartes, pastilles, lignes d'etat...) et mise en page verticale simple.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace DigSpill
{
    /// <summary>Un controle qui sait dire sa hauteur pour une largeur donnee.</summary>
    interface IHauteur { int HauteurPour(int largeur); }

    static class Mise
    {
        public const TextFormatFlags Flux = TextFormatFlags.WordBreak | TextFormatFlags.TextBoxControl | TextFormatFlags.NoPadding;

        public static int HauteurTexte(string texte, Font f, int largeur)
        {
            if (string.IsNullOrEmpty(texte)) return 0;
            return TextRenderer.MeasureText(texte, f, new Size(Math.Max(1, largeur), int.MaxValue), Flux).Height;
        }

        public static int HauteurDe(Control c, int largeur)
        {
            var ih = c as IHauteur;
            if (ih != null) return ih.HauteurPour(largeur);
            var l = c as Label;
            if (l != null) return HauteurTexte(l.Text, l.Font, largeur - l.Padding.Horizontal) + l.Padding.Vertical;
            var fl = c as FlowLayoutPanel;
            if (fl != null) return fl.GetPreferredSize(new Size(largeur, 0)).Height;
            return c.Height;
        }

        public static Label Texte(string texte, Font f, Color c)
        {
            return new Label { Text = texte, Font = f, ForeColor = c, BackColor = Color.Transparent, AutoSize = false, UseMnemonic = false };
        }

        /// <summary>Lien discret (gris, blanc au survol) qui lance une action.</summary>
        public static Label Lien(string texte, Action action)
        {
            var l = Texte(texte, Theme.Police(10.5f), Theme.Texte2);
            l.Cursor = Cursors.Hand; l.AccessibleRole = AccessibleRole.Link;
            l.MouseEnter += delegate { l.ForeColor = Theme.Texte; };
            l.MouseLeave += delegate { l.ForeColor = Theme.Texte2; };
            l.Click += delegate { action(); };
            return l;
        }
    }

    /// <summary>Empile ses enfants de haut en bas, chacun sur toute la largeur.</summary>
    class Colonne : Panel, IHauteur
    {
        public int Espace = 12;

        public Colonne()
        {
            SetStyle(ControlStyles.SupportsTransparentBackColor | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
            BackColor = Color.Transparent;
        }

        public T Ajouter<T>(T c) where T : Control { Controls.Add(c); return c; }

        IEnumerable<Control> Visibles() { return Controls.Cast<Control>().Where(c => c.Visible); }

        public int HauteurPour(int largeur)
        {
            int h = Padding.Vertical, n = 0;
            foreach (var c in Visibles())
            {
                if (n++ > 0) h += Espace;
                h += c.Margin.Vertical + Mise.HauteurDe(c, largeur - Padding.Horizontal - c.Margin.Horizontal);
            }
            return h;
        }

        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e);
            Disposer();
        }

        public void Disposer()
        {
            int w = ClientSize.Width - Padding.Horizontal, y = Padding.Top, n = 0;
            foreach (var c in Visibles())
            {
                if (n++ > 0) y += Espace;
                int cw = Math.Max(10, w - c.Margin.Horizontal);
                int ch = Mise.HauteurDe(c, cw);
                c.SetBounds(Padding.Left + c.Margin.Left, y + c.Margin.Top, cw, ch);
                if (c is Colonne || c is Carte || c is Grille) c.PerformLayout();
                y += c.Margin.Vertical + ch;
            }
        }
    }

    /// <summary>Section de page : un filet de 1 px en haut, pas de cadre (comme l'interface HTML).
    /// Avec Couleurs(), un bloc plein arrondi (scelle, alerte).</summary>
    class Carte : Panel, IHauteur
    {
        public readonly Colonne Contenu = new Colonne();
        Color fond = Theme.Fond, bord = Theme.Ligne;
        bool plein;
        public int Rayon = 10;
        public float Epaisseur = 1f;

        public Carte()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            Padding = new Padding(0, 20, 0, 6);
            BackColor = fond;
            Contenu.Dock = DockStyle.Fill;
            Controls.Add(Contenu);
        }

        public Carte Couleurs(Color f, Color b) { fond = f; bord = b; plein = true; BackColor = f; Padding = new Padding(26, 22, 26, 22); Invalidate(true); return this; }
        public Color Fond { get { return fond; } }

        public int HauteurPour(int largeur) { return Padding.Vertical + Contenu.HauteurPour(largeur - Padding.Horizontal); }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Parent != null ? FondDe(Parent) : Theme.Papier);
            if (!plein) { using (var pen = new Pen(bord, 1f)) g.DrawLine(pen, 0, 0, Width, 0); return; }
            Theme.Qualite(g);
            var r = new RectangleF(Epaisseur / 2, Epaisseur / 2, Width - Epaisseur - 1, Height - Epaisseur - 1);
            using (var p = Theme.Arrondi(r, Rayon))
            using (var b = new SolidBrush(fond))
            using (var pen = new Pen(bord, Epaisseur))
            {
                g.FillPath(b, p);
                g.DrawPath(pen, p);
            }
        }

        protected override void OnPaint(PaintEventArgs e) { }

        public static Color FondDe(Control c)
        {
            while (c != null)
            {
                var ca = c as Carte;
                if (ca != null) return ca.fond;
                if (c.BackColor.A == 255) return c.BackColor;
                c = c.Parent;
            }
            return Theme.Papier;
        }
    }

    /// <summary>Grille de champs a n colonnes.</summary>
    class Grille : Panel, IHauteur
    {
        public int Colonnes = 2, Espace = 16, EspaceV = 12;
        public Grille() { BackColor = Color.Transparent; SetStyle(ControlStyles.SupportsTransparentBackColor, true); }

        int LargeurCellule(int largeur) { return (largeur - Padding.Horizontal - Espace * (Colonnes - 1)) / Colonnes; }

        public int HauteurPour(int largeur)
        {
            int cw = LargeurCellule(largeur), h = Padding.Vertical, i = 0, ligne = 0;
            var vis = Controls.Cast<Control>().Where(c => c.Visible).ToList();
            foreach (var c in vis)
            {
                int span = (c.Tag as string) == "large" ? Colonnes : 1;
                if (i % Colonnes + span > Colonnes) { h += ligne + EspaceV; ligne = 0; i += Colonnes - i % Colonnes; }
                ligne = Math.Max(ligne, Mise.HauteurDe(c, cw * span + Espace * (span - 1)));
                i += span;
                if (i % Colonnes == 0) { h += ligne + EspaceV; ligne = 0; }
            }
            if (ligne > 0) h += ligne + EspaceV;
            return Math.Max(0, h - EspaceV);
        }

        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e);
            int cw = LargeurCellule(ClientSize.Width), y = Padding.Top, i = 0;
            var ligne = new List<KeyValuePair<Control, Rectangle>>();
            Action poser = () =>
            {
                int h = ligne.Count == 0 ? 0 : ligne.Max(k => k.Value.Height);
                foreach (var k in ligne) k.Key.SetBounds(k.Value.X, y, k.Value.Width, (k.Key is IHauteur && !(k.Key is Champ)) ? h : k.Value.Height);
                y += h + EspaceV;
                ligne.Clear();
            };
            foreach (var c in Controls.Cast<Control>().Where(x => x.Visible))
            {
                int span = (c.Tag as string) == "large" ? Colonnes : 1;
                if (i % Colonnes + span > Colonnes) { poser(); i += Colonnes - i % Colonnes; }
                int col = i % Colonnes, w = cw * span + Espace * (span - 1);
                ligne.Add(new KeyValuePair<Control, Rectangle>(c, new Rectangle(Padding.Left + col * (cw + Espace), 0, w, Mise.HauteurDe(c, w))));
                i += span;
                if (i % Colonnes == 0) poser();
            }
            if (ligne.Count > 0) poser();
        }
    }

    /// <summary>Rangee horizontale (boutons, pastilles) qui passe a la ligne si besoin.</summary>
    class Rangee : FlowLayoutPanel, IHauteur
    {
        public Rangee()
        {
            FlowDirection = FlowDirection.LeftToRight;
            WrapContents = true;
            BackColor = Color.Transparent;
            Margin = Padding.Empty;
            Padding = Padding.Empty;
        }
        public int HauteurPour(int largeur)
        {
            int x = 0, y = 0, ligne = 0;
            foreach (Control c in Controls)
            {
                if (!c.Visible) continue;
                int w = c.Width + c.Margin.Horizontal;
                if (x > 0 && x + w > largeur) { y += ligne; x = 0; ligne = 0; }
                x += w; ligne = Math.Max(ligne, c.Height + c.Margin.Vertical);
            }
            return y + ligne;
        }
    }

    class BoutonPlat : Control
    {
        public enum Genre { Primaire, Secondaire, Danger, Discret, Succes, Risque }
        Genre genre;
        string icone;
        bool survol, appui;
        int pastille;
        /// <summary>Place laissee en haut et a droite pour la pastille (le bouton grandit d'autant).</summary>
        public const int Debord = 9;

        public BoutonPlat(string texte, Genre g) : this(texte, g, null) { }
        public BoutonPlat(string texte, Genre g, string icone)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint |
                     ControlStyles.ResizeRedraw | ControlStyles.Selectable | ControlStyles.StandardClick, true);
            genre = g;
            this.icone = icone;
            Font = Theme.Police(10.5f, FontStyle.Bold);
            Cursor = Cursors.Hand;
            TabStop = true;
            Margin = new Padding(10, 0, 0, 0);
            Text = texte;
            AccessibleRole = AccessibleRole.PushButton;
            Height = 44;
            Ajuster();
        }

        public Genre Style { get { return genre; } set { genre = value; Invalidate(); } }
        /// <summary>Pastille rouge avec un nombre (ex. 1 mise a jour), a cheval sur le coin haut droit ; 0 : aucune.</summary>
        public int Pastille { get { return pastille; } set { if (value == pastille) return; pastille = value; Ajuster(); Invalidate(); } }
        public void PerformClickPublic() { OnClick(EventArgs.Empty); }
        Rectangle Corps { get { return pastille > 0 ? new Rectangle(0, Debord, Width - Debord, Height - Debord) : ClientRectangle; } }
        public string Icone { get { return icone; } set { icone = value; Ajuster(); Invalidate(); } }

        void Ajuster()
        {
            var t = TextRenderer.MeasureText(Text ?? "", Font);
            Width = Math.Max(120, t.Width + 44 + (string.IsNullOrEmpty(icone) ? 0 : 26)) + (pastille > 0 ? Debord : 0);
            Height = 44 + (pastille > 0 ? Debord : 0);
        }

        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Ajuster(); Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnMouseEnter(EventArgs e) { survol = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { survol = false; appui = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { appui = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { appui = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space) { OnClick(EventArgs.Empty); e.Handled = true; }
            base.OnKeyDown(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Carte.FondDe(Parent));
            Theme.Qualite(g);
            Color fond, texte, bord;
            switch (genre)
            {
                case Genre.Primaire: fond = Theme.Rouge; texte = Color.White; bord = fond; break;
                case Genre.Danger: fond = Theme.Rouge; texte = Color.White; bord = fond; break;
                case Genre.Succes: fond = Theme.Texte; texte = Theme.Fond; bord = fond; break;
                case Genre.Discret: fond = Carte.FondDe(Parent); texte = Theme.Texte2; bord = fond; break;
                case Genre.Risque: fond = Carte.FondDe(Parent); texte = Theme.RougeTexte; bord = Color.FromArgb(0x5a, 0x24, 0x22); break;
                default: fond = Carte.FondDe(Parent); texte = Theme.Texte; bord = Theme.Ligne2; break;
            }
            bool clair = genre == Genre.Secondaire || genre == Genre.Discret || genre == Genre.Risque;
            if (Enabled && (survol || appui)) { if (clair) { fond = Theme.Panneau2; if (genre == Genre.Discret) texte = Theme.Texte; } else fond = Melanger(fond, Color.White, appui ? 0.04f : 0.1f); }
            if (!Enabled) { fond = Theme.Panneau2; texte = Theme.Texte3; bord = fond; }
            var c = Corps;
            var r = new RectangleF(c.X + 1, c.Y + 1, c.Width - 3, c.Height - 3);
            using (var p = Theme.Arrondi(r, 10))
            using (var b = new SolidBrush(fond))
            {
                g.FillPath(b, p);
                if (bord != fond) using (var pen = new Pen(bord, 1f)) g.DrawPath(pen, p);
                if (Focused && ShowFocusCues) using (var pen = new Pen(Theme.Bleu, 2f)) g.DrawPath(pen, p);
            }
            var tt = TextRenderer.MeasureText(Text ?? "", Font);
            int largeurTotale = tt.Width + (string.IsNullOrEmpty(icone) ? 0 : 26);
            int x = c.X + (c.Width - largeurTotale) / 2;
            if (!string.IsNullOrEmpty(icone))
            {
                using (var fi = Theme.Icones(11f))
                    TextRenderer.DrawText(g, icone, fi, new Rectangle(x, c.Y, 24, c.Height), texte, TextFormatFlags.VerticalCenter | TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding);
                x += 26;
            }
            TextRenderer.DrawText(g, Text ?? "", Font, new Rectangle(x, c.Y, tt.Width + 4, c.Height), texte, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding);
            if (pastille > 0)
            {
                // rond rouge cerne de la couleur du fond, comme sur un telephone
                var rp = new RectangleF(Width - 22, 0, 21, 21);
                using (var b = new SolidBrush(Theme.Rouge)) g.FillEllipse(b, rp);
                using (var pen = new Pen(Carte.FondDe(Parent), 2f)) g.DrawEllipse(pen, rp);
                using (var fp = Theme.Police(8.5f, FontStyle.Bold))
                    TextRenderer.DrawText(g, pastille > 9 ? "9+" : pastille.ToString(), fp, Rectangle.Round(rp), Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            }
        }

        static Color Melanger(Color a, Color b, float t)
        {
            return Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
        }
    }

    enum Niveau { Ok, Info, Attention, Danger, EnCours, Attente, Ignore }

    static class Niveaux
    {
        public static Color Couleur(Niveau n)
        {
            switch (n)
            {
                case Niveau.Ok: return Theme.Vert;
                case Niveau.Attention: return Theme.Orange;
                case Niveau.Danger: return Theme.Rouge;
                case Niveau.EnCours: return Theme.Texte;
                case Niveau.Info: return Theme.Bleu;
                default: return Theme.Texte3;
            }
        }
        public static Color Fond(Niveau n)
        {
            switch (n)
            {
                case Niveau.Ok: return Theme.VertFond;
                case Niveau.Attention: return Theme.OrangeFond;
                case Niveau.Danger: return Theme.RougeFond;
                case Niveau.EnCours: return Theme.Panneau2;
                case Niveau.Info: return Theme.BleuFond;
                default: return Theme.Panneau2;
            }
        }
        public static string Icone(Niveau n)
        {
            switch (n)
            {
                case Niveau.Ok: return Ic.Ok;
                case Niveau.Attention: return Ic.Attention;
                case Niveau.Danger: return Ic.Erreur;
                case Niveau.EnCours: return Ic.Lecture;
                case Niveau.Info: return Ic.Info;
                case Niveau.Ignore: return "–";
                default: return Ic.Attente;
            }
        }
        public static string Mot(Niveau n)
        {
            switch (n)
            {
                case Niveau.Ok: return "OK";
                case Niveau.Attention: return "À vérifier";
                case Niveau.Danger: return "Danger";
                case Niveau.EnCours: return "En cours";
                case Niveau.Info: return "Info";
                case Niveau.Ignore: return "Ignoré";
                default: return "En attente";
            }
        }
    }

    /// <summary>Pastille : petite etiquette en Geist Mono, contour et texte de la couleur du niveau (comme .pill).</summary>
    class Pastille : Control
    {
        Color fond, texte;
        public Pastille(string t, Color texte, Color fond)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
            Font = Theme.MonoMoyen(8.5f);
            Margin = new Padding(0, 0, 8, 6);
            Definir(t, texte, fond);
        }
        public Pastille(string t, Niveau n) : this(t, Niveaux.Couleur(n), Niveaux.Fond(n)) { }
        public void Definir(string t, Color texte, Color fond)
        {
            this.texte = texte; this.fond = fond; Text = t;
            var s = TextRenderer.MeasureText(t ?? "", Font);
            Size = new Size(s.Width + 16, Math.Max(24, s.Height + 8));
            Invalidate();
        }
        public void Definir(string t, Niveau n) { Definir(t, Niveaux.Couleur(n), Niveaux.Fond(n)); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Carte.FondDe(Parent));
            Theme.Qualite(g);
            using (var p = Theme.Arrondi(new RectangleF(0.5f, 0.5f, Width - 2, Height - 2), 5))
            using (var b = new SolidBrush(fond))
            using (var pen = new Pen(Color.FromArgb(150, texte), 1f)) { g.FillPath(b, p); g.DrawPath(pen, p); }
            TextRenderer.DrawText(g, Text, Font, ClientRectangle, texte, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
    }

    /// <summary>Ligne d'etat : icone dans un rond + titre + detail (texte qui passe a la ligne).</summary>
    class LigneInfo : Control, IHauteur
    {
        Niveau niveau;
        string titre, detail;
        readonly Font fTitre = Theme.Police(11f, FontStyle.Bold), fDetail = Theme.Police(10f), fIcone = Theme.Icones(10.5f);
        public LigneInfo(Niveau n, string titre, string detail)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            niveau = n; this.titre = titre; this.detail = detail;
        }
        public Niveau Niveau { get { return niveau; } }
        /// <summary>Texte a la place de l'icone du niveau (numero d'etape : « 1 », « 2 »).</summary>
        public string IconeTexte;
        public void Definir(Niveau n, string t, string d)
        {
            bool h = (d ?? "") != (detail ?? "") || (t ?? "") != (titre ?? "");
            niveau = n; titre = t; detail = d; Invalidate();
            if (h && Parent != null) Parent.PerformLayout();
        }
        public void Detail(string d) { Definir(niveau, titre, d); }
        public void Etat(Niveau n) { Definir(n, titre, detail); }

        const int Gauche = 46;
        public int HauteurPour(int largeur)
        {
            int h = Mise.HauteurTexte(titre, fTitre, largeur - Gauche);
            if (!string.IsNullOrEmpty(detail)) h += 3 + Mise.HauteurTexte(detail, fDetail, largeur - Gauche);
            return Math.Max(34, h + 4);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Carte.FondDe(Parent));
            Theme.Qualite(g);
            var rond = new Rectangle(0, 1, 32, 32);
            using (var b = new SolidBrush(Niveaux.Fond(niveau))) g.FillEllipse(b, rond);
            if (IconeTexte != null) using (var fn = Theme.Police(10.5f, FontStyle.Bold))
                TextRenderer.DrawText(g, IconeTexte, fn, rond, Theme.Texte, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            else TextRenderer.DrawText(g, Niveaux.Icone(niveau), fIcone, rond, Niveaux.Couleur(niveau), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            int w = Width - Gauche;
            int ht = Mise.HauteurTexte(titre, fTitre, w);
            TextRenderer.DrawText(g, titre, fTitre, new Rectangle(Gauche, 2, w, ht + 2), Theme.Encre, Mise.Flux);
            if (!string.IsNullOrEmpty(detail))
                TextRenderer.DrawText(g, detail, fDetail, new Rectangle(Gauche, 5 + ht, w, Height), Theme.Doux, Mise.Flux);
        }
    }

    /// <summary>Barre de progression plate (valeur 0..1, ou animation si indeterminee).</summary>
    class Barre : Control, IHauteur
    {
        double valeur;
        bool indeterminee, vivante;
        int phase;
        readonly Timer minuterie = new Timer { Interval = 40 };
        public Color Couleur = Theme.Texte;
        public int Epaisseur = 6;
        public Barre()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            minuterie.Tick += delegate { phase = (phase + 6) % 1000; Invalidate(); };
        }
        public int HauteurPour(int largeur) { return Epaisseur; }
        public double Valeur { get { return valeur; } set { valeur = Math.Max(0, Math.Min(1, value)); if (indeterminee) Indeterminee = false; Invalidate(); } }
        public bool Indeterminee
        {
            get { return indeterminee; }
            set
            {
                if (value == indeterminee) return;
                indeterminee = value;
                if (value || vivante) minuterie.Start(); else minuterie.Stop();
                Invalidate();
            }
        }
        /// <summary>Travail en cours : un reflet parcourt la partie remplie, meme quand le pourcentage ne bouge pas (gros fichier).</summary>
        public bool Vivante
        {
            get { return vivante; }
            set
            {
                if (value == vivante) return;
                vivante = value;
                if (value || indeterminee) minuterie.Start(); else minuterie.Stop();
                Invalidate();
            }
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Carte.FondDe(Parent));
            Theme.Qualite(g);
            var r = new RectangleF(0, 0, Width - 1, Height - 1);
            using (var p = Theme.Arrondi(r, Height / 2f)) using (var b = new SolidBrush(Theme.Ligne)) g.FillPath(b, p);
            RectangleF plein;
            if (indeterminee) { float l = Width * 0.25f; float x = (Width + l) * phase / 1000f - l; plein = new RectangleF(Math.Max(0, x), 0, Math.Min(l, Width - Math.Max(0, x)), Height - 1); }
            else plein = new RectangleF(0, 0, (float)((Width - 1) * valeur), Height - 1);
            if (plein.Width > 2) using (var p = Theme.Arrondi(plein, Height / 2f)) using (var b = new SolidBrush(Couleur))
            {
                g.FillPath(b, p);
                if (vivante && !indeterminee && plein.Width > 12)
                {
                    float l = Math.Min(70f, plein.Width * 0.5f), x = (plein.Width + l) * phase / 1000f - l;
                    g.SetClip(p);
                    using (var r2 = new SolidBrush(Color.FromArgb(90, Carte.FondDe(Parent)))) g.FillRectangle(r2, x, 0, l, Height);
                    g.ResetClip();
                }
            }
        }
        protected override void Dispose(bool d) { if (d) minuterie.Dispose(); base.Dispose(d); }
    }

    /// <summary>Liste des etapes dans la barre laterale.</summary>
    class ListeEtapes : Control
    {
        string[] etapes = new string[0];
        int courante = -1;
        readonly Font f = Theme.Police(10.5f), fg = Theme.Police(10.5f, FontStyle.Bold), fn = Theme.Mono(8.5f);
        HashSet<int> cliquables = new HashSet<int>();
        int survol = -1;
        public event Action<int> EtapeCliquee;
        public ListeEtapes() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
        public void Definir(string[] e, int c) { etapes = e ?? new string[0]; courante = c; Invalidate(); }
        /// <summary>Etapes precedentes ou l'on peut revenir (soulignees au survol, curseur main).</summary>
        public HashSet<int> Cliquables { set { cliquables = value ?? new HashSet<int>(); survol = -1; Cursor = Cursors.Default; Invalidate(); } }
        int Ligne(Point p) { int i = p.Y / 44; return p.Y % 44 < 26 && i >= 0 && i < etapes.Length ? i : -1; }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            int i = Ligne(e.Location); if (!cliquables.Contains(i)) i = -1;
            if (i != survol) { survol = i; Cursor = i >= 0 ? Cursors.Hand : Cursors.Default; Invalidate(); }
            base.OnMouseMove(e);
        }
        protected override void OnMouseLeave(EventArgs e) { if (survol >= 0) { survol = -1; Cursor = Cursors.Default; Invalidate(); } base.OnMouseLeave(e); }
        protected override void OnMouseClick(MouseEventArgs e)
        {
            int i = Ligne(e.Location);
            if (cliquables.Contains(i) && EtapeCliquee != null) EtapeCliquee(i);
            base.OnMouseClick(e);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Theme.Nuit);
            Theme.Qualite(g);
            for (int i = 0; i < etapes.Length; i++)
            {
                int y = i * 44;
                bool fait = i < courante, cour = i == courante;
                if (i < etapes.Length - 1) using (var p = new Pen(Theme.Ligne2, 1f)) g.DrawLine(p, 36, y + 18, 36, y + 44 + 8);
                TextRenderer.DrawText(g, (i + 1).ToString("00"), fn, new Rectangle(0, y, 24, 26), cour ? Theme.Texte : Theme.Texte3, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding);
                var puce = new RectangleF(32, y + 8.5f, 9, 9);
                using (var b = new SolidBrush(cour ? Theme.Rouge : fait ? Theme.Texte2 : Theme.Fond)) g.FillEllipse(b, puce);
                if (!cour && !fait) using (var p = new Pen(Theme.Texte3, 1.5f)) g.DrawEllipse(p, puce);
                bool lien = cliquables.Contains(i);
                using (var fl = lien && i == survol ? new Font(f, FontStyle.Underline) : null)
                    TextRenderer.DrawText(g, etapes[i], cour ? fg : (fl ?? f), new Rectangle(54, y, Width - 56, 26), cour ? Theme.Texte : lien && i == survol ? Theme.Texte : (fait ? Theme.Texte2 : Theme.Texte3), TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
            }
        }
    }

    /// <summary>Grande carte cliquable de l'accueil : icone dans un carre teinte, titre, une phrase, etiquettes.</summary>
    class CarteChoix : Control, IHauteur
    {
        readonly string icone, titre, texte;
        readonly Color teinte;
        readonly Tuple<string, Niveau>[] etiquettes;
        bool survol;
        readonly Font fIcone = Theme.Icones(17f), fTitre = Theme.Police(16f, FontStyle.Bold), fTexte = Theme.Police(10.5f), fNote = Theme.Police(9f);
        const int M = 28;
        public CarteChoix(string icone, string titre, string texte, Color teinte, params Tuple<string, Niveau>[] etiquettes)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            this.icone = icone; this.titre = titre; this.texte = texte; this.teinte = teinte; this.etiquettes = etiquettes ?? new Tuple<string, Niveau>[0];
            Cursor = Cursors.Hand; TabStop = true;
            AccessibleName = titre; AccessibleDescription = texte; AccessibleRole = AccessibleRole.PushButton;
        }
        public int HauteurPour(int largeur) { return M + 52 + 18 + 30 + Mise.HauteurTexte(texte, fTexte, largeur - 2 * M) + (etiquettes.Length > 0 ? 18 + 26 : 0) + M; }
        protected override void OnMouseEnter(EventArgs e) { survol = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { survol = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnKeyDown(KeyEventArgs e) { if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space) OnClick(EventArgs.Empty); base.OnKeyDown(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Carte.FondDe(Parent));
            Theme.Qualite(g);
            var r = new RectangleF(1, 1, Width - 3, Height - 3);
            using (var p = Theme.Arrondi(r, 10))
            using (var b = new SolidBrush(survol ? Theme.Panneau2 : Theme.Panneau))
            using (var pen = new Pen(Focused && ShowFocusCues ? Theme.Bleu : survol ? Theme.Ligne2 : Theme.Ligne, Focused && ShowFocusCues ? 2f : 1f))
            { g.FillPath(b, p); g.DrawPath(pen, p); }
            var carre = new RectangleF(M, M, 52, 52);
            using (var p = Theme.Arrondi(carre, 13)) using (var b = new SolidBrush(Theme.Teinte(teinte))) g.FillPath(b, p);
            TextRenderer.DrawText(g, icone, fIcone, Rectangle.Round(carre), teinte, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            int y = M + 52 + 18;
            TextRenderer.DrawText(g, titre, fTitre, new Rectangle(M, y, Width - 2 * M, 30), Theme.Texte, TextFormatFlags.NoPadding);
            y += 30;
            int ht = Mise.HauteurTexte(texte, fTexte, Width - 2 * M);
            TextRenderer.DrawText(g, texte, fTexte, new Rectangle(M, y, Width - 2 * M, ht + 4), Theme.Texte2, Mise.Flux);
            y += ht + 18;
            int x = M;
            foreach (var et in etiquettes)
            {
                // etiquette neutre (gris) ou d'attention (orange), comme les pastilles de l'interface HTML
                bool neutre = et.Item2 == Niveau.Attente || et.Item2 == Niveau.Info;
                var s = TextRenderer.MeasureText(et.Item1, fNote);
                var r2 = new RectangleF(x, y, s.Width + 20, 26);
                using (var p = Theme.Arrondi(r2, 13)) using (var b = new SolidBrush(neutre ? Theme.Ligne : Niveaux.Fond(et.Item2))) g.FillPath(b, p);
                TextRenderer.DrawText(g, et.Item1, fNote, Rectangle.Round(r2), neutre ? Theme.Texte2 : Niveaux.Couleur(et.Item2), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                x += (int)r2.Width + 8;
            }
        }
    }

    /// <summary>Liste deroulante sombre : la ComboBox de Windows reste blanche en style Flat, on la dessine nous-memes.</summary>
    class ListeSombre : ComboBox
    {
        public ListeSombre()
        {
            DropDownStyle = ComboBoxStyle.DropDownList; FlatStyle = FlatStyle.Flat;
            DrawMode = DrawMode.OwnerDrawFixed; ItemHeight = 22;
            BackColor = Theme.Panneau; ForeColor = Theme.Texte;
        }
        protected override void OnDrawItem(DrawItemEventArgs e)
        {
            if (e.Index < 0) return;
            bool survol = (e.State & DrawItemState.Selected) != 0 && (e.State & DrawItemState.ComboBoxEdit) == 0;
            using (var b = new SolidBrush(survol ? Theme.Panneau2 : Theme.Panneau)) e.Graphics.FillRectangle(b, e.Bounds);
            TextRenderer.DrawText(e.Graphics, GetItemText(Items[e.Index]), Font, new Rectangle(e.Bounds.X + 6, e.Bounds.Y, e.Bounds.Width - 6, e.Bounds.Height), Theme.Texte,
                TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }
        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            if (m.Msg != 0x000F) return;   // WM_PAINT : partie fermee (texte + chevron) repeinte en sombre
            using (var g = Graphics.FromHwnd(Handle))
            {
                var r = ClientRectangle;
                using (var b = new SolidBrush(Theme.Panneau)) g.FillRectangle(b, r);
                TextRenderer.DrawText(g, Text, Font, new Rectangle(2, 0, r.Width - 26, r.Height), Theme.Texte, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
                int cx = r.Width - 12, cy = r.Height / 2;
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                using (var p = new Pen(Theme.Texte2, 1.6f)) g.DrawLines(p, new[] { new Point(cx - 4, cy - 2), new Point(cx, cy + 2), new Point(cx + 4, cy - 2) });
            }
        }
    }

    /// <summary>Champ de saisie : libelle au-dessus, zone bordee.</summary>
    class Champ : Panel, IHauteur
    {
        readonly Label etiquette;
        readonly Panel cadre;
        public readonly Control Saisie;
        public Champ(string libelle, Control saisie, bool obligatoire)
        {
            BackColor = Color.Transparent;
            SetStyle(ControlStyles.SupportsTransparentBackColor | ControlStyles.OptimizedDoubleBuffer, true);
            etiquette = Mise.Texte((libelle + (obligatoire ? " *" : "")).ToUpperInvariant(), Theme.MonoMoyen(8f), Theme.Texte3);
            cadre = new CadreSaisie();
            Saisie = saisie;
            saisie.Font = Theme.Police(10.5f);
            saisie.BackColor = Theme.Panneau; saisie.ForeColor = Theme.Texte;
            var tb = saisie as TextBox;
            if (tb != null) tb.BorderStyle = BorderStyle.None;
            Theme.Sombre(saisie, saisie is ComboBox ? "DarkMode_CFD" : "DarkMode_Explorer");
            var dtp = saisie as DateTimePicker;
            if (dtp != null) { dtp.CalendarMonthBackground = Theme.Panneau; dtp.CalendarForeColor = Theme.Texte; dtp.CalendarTitleBackColor = Theme.Panneau2; dtp.CalendarTitleForeColor = Theme.Texte; }
            cadre.Controls.Add(saisie);
            Controls.Add(etiquette);
            Controls.Add(cadre);
            saisie.GotFocus += delegate { cadre.Invalidate(); };
            saisie.LostFocus += delegate { cadre.Invalidate(); };
        }
        public static Champ Texte(string libelle, string valeur, bool obligatoire)
        {
            return new Champ(libelle, new TextBox { Text = valeur ?? "" }, obligatoire);
        }
        public string Valeur { get { return Saisie.Text.Trim(); } set { Saisie.Text = value ?? ""; } }
        public int HauteurPour(int largeur) { return 24 + 40; }
        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e);
            etiquette.SetBounds(0, 0, Width, 22);
            cadre.SetBounds(0, 24, Width, 40);
            int h = Saisie.PreferredSize.Height;
            if (Saisie is TextBox) Saisie.SetBounds(12, (40 - h) / 2, Width - 24, h);
            else Saisie.SetBounds(4, (40 - Saisie.Height) / 2, Width - 8, Saisie.Height);
        }

        class CadreSaisie : Panel
        {
            public CadreSaisie()
            {
                SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
                BackColor = Theme.Panneau;
            }
            protected override void OnPaintBackground(PaintEventArgs e)
            {
                var g = e.Graphics;
                g.Clear(Carte.FondDe(Parent));
                Theme.Qualite(g);
                bool focus = Controls.Count > 0 && Controls[0].ContainsFocus;
                using (var p = Theme.Arrondi(new RectangleF(1, 1, Width - 3, Height - 3), 8))
                using (var b = new SolidBrush(Theme.Panneau))
                using (var pen = new Pen(focus ? Theme.Bleu : Theme.Ligne2, focus ? 2f : 1f))
                { g.FillPath(b, p); g.DrawPath(pen, p); }
            }
        }
    }

    /// <summary>Dessin commun des cases et des choix : marque a gauche, texte qui passe a la ligne.</summary>
    static class Coche
    {
        public const int Marge = 30;
        public static void Dessiner(ButtonBase c, Graphics g, bool coche, bool rond, bool focus)
        {
            g.Clear(Carte.FondDe(c.Parent));
            Theme.Qualite(g);
            var r = new RectangleF(1, 2, 18, 18);
            using (var p = rond ? new System.Drawing.Drawing2D.GraphicsPath() : Theme.Arrondi(r, 4))
            {
                if (rond) p.AddEllipse(r);
                using (var b = new SolidBrush(coche && !rond ? Theme.Texte : Theme.Fond)) g.FillPath(b, p);
                using (var pen = new Pen(focus ? Theme.Bleu : coche ? Theme.Texte : Theme.Texte3, focus ? 2f : 1.5f)) g.DrawPath(pen, p);
            }
            if (coche && rond) using (var b = new SolidBrush(Theme.Texte)) g.FillEllipse(b, r.X + 5, r.Y + 5, 8, 8);
            if (coche && !rond) using (var pen = new Pen(Theme.Fond, 2f)) g.DrawLines(pen, new[] { new PointF(r.X + 4.5f, r.Y + 9.5f), new PointF(r.X + 7.8f, r.Y + 12.8f), new PointF(r.X + 13.5f, r.Y + 6) });
            TextRenderer.DrawText(g, c.Text, c.Font, new Rectangle(Marge, 2, c.Width - Marge, c.Height), c.Enabled ? Theme.Texte : Theme.Texte3, Mise.Flux);
        }
        public static void Preparer(ButtonBase c)
        {
            c.Font = Theme.Police(10.5f); c.ForeColor = Theme.Texte; c.Cursor = Cursors.Hand;
            c.BackColor = Color.Transparent; c.AutoSize = false; c.UseMnemonic = false;
        }
    }

    /// <summary>Case a cocher sur fond noir, avec texte qui passe a la ligne.</summary>
    class Case : CheckBox, IHauteur
    {
        public Case(string texte, bool coche)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.SupportsTransparentBackColor, true);
            Text = texte; Checked = coche; Coche.Preparer(this);
        }
        public int HauteurPour(int largeur) { return Math.Max(24, Mise.HauteurTexte(Text, Font, largeur - Coche.Marge) + 6); }
        protected override void OnPaint(PaintEventArgs e) { Coche.Dessiner(this, e.Graphics, Checked, false, Focused && ShowFocusCues); }
        protected override void OnCheckedChanged(EventArgs e) { base.OnCheckedChanged(e); Invalidate(); }
    }

    class Choix : RadioButton, IHauteur
    {
        public Choix(string texte, bool coche)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.SupportsTransparentBackColor, true);
            Text = texte; Checked = coche; Coche.Preparer(this);
        }
        public int HauteurPour(int largeur) { return Math.Max(24, Mise.HauteurTexte(Text, Font, largeur - Coche.Marge) + 6); }
        protected override void OnPaint(PaintEventArgs e) { Coche.Dessiner(this, e.Graphics, Checked, true, Focused && ShowFocusCues); }
        protected override void OnCheckedChanged(EventArgs e) { base.OnCheckedChanged(e); Invalidate(); }
    }

    /// <summary>Journal defilant (fond sombre).</summary>
    class Journal : Panel, IHauteur
    {
        readonly TextBox boite;
        public int Hauteur = 200;
        readonly Queue<string> lignes = new Queue<string>();
        readonly List<string> toutes = new List<string>();   // tout le journal, pour l'enregistrer (l'ecran n'en garde que 400 lignes)
        readonly Timer vidage = new Timer { Interval = 150 };
        readonly List<string> enAttente = new List<string>();
        public Journal()
        {
            BackColor = Theme.Panneau;
            Padding = new Padding(14, 12, 6, 12);
            boite = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, BorderStyle = BorderStyle.None, BackColor = Theme.Panneau, ForeColor = Theme.Texte2, Font = Theme.Mono(9f), Dock = DockStyle.Fill, WordWrap = false };
            Controls.Add(boite);
            Theme.Sombre(boite);
            vidage.Tick += delegate { Vider(); };
            vidage.Start();
        }
        public int HauteurPour(int largeur) { return Hauteur; }
        public void Ajouter(string ligne)
        {
            lock (enAttente) enAttente.Add(ligne ?? "");
        }
        void Vider()
        {
            string[] neuves;
            lock (enAttente) { if (enAttente.Count == 0) return; neuves = enAttente.ToArray(); enAttente.Clear(); }
            foreach (var l in neuves) { lignes.Enqueue(l); while (lignes.Count > 400) lignes.Dequeue(); if (toutes.Count < 200000) toutes.Add(l); }
            boite.Text = string.Join("\r\n", lignes.ToArray());
            boite.SelectionStart = boite.TextLength;
            boite.ScrollToCaret();
        }
        public string Tout() { Vider(); return string.Join("\r\n", toutes.ToArray()); }
        protected override void Dispose(bool d) { if (d) vidage.Dispose(); base.Dispose(d); }
    }

    /// <summary>Texte d'empreinte en gros caracteres a chasse fixe.</summary>
    class Empreinte : Control, IHauteur
    {
        readonly Font f = Theme.MonoMoyen(15f);
        public Empreinte() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
        string Groupes()
        {
            var t = Text ?? "";
            if (!System.Text.RegularExpressions.Regex.IsMatch(t, "^[0-9A-Fa-f]{32,}$")) return t;
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < t.Length; i++) { if (i > 0 && i % 16 == 0) sb.Append(i % 32 == 0 ? "\n" : "   "); else if (i > 0 && i % 4 == 0) sb.Append(' '); sb.Append(t[i]); }
            return sb.ToString();
        }
        public int HauteurPour(int largeur) { return Mise.HauteurTexte(Groupes(), f, largeur) + 6; }
        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); if (Parent != null) Parent.PerformLayout(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(Carte.FondDe(Parent));
            TextRenderer.DrawText(e.Graphics, Groupes(), f, ClientRectangle, Theme.Texte, Mise.Flux);
        }
    }

    /// <summary>Bas de la barre laterale : une petite carte, une ligne par etat (point de couleur, titre, precision).</summary>
    class EtatPoste : Control
    {
        public class Ligne
        {
            public readonly Niveau Niveau; public readonly string Titre, Detail;
            public Ligne(Niveau n, string titre, string detail) { Niveau = n; Titre = titre; Detail = detail; }
        }
        List<Ligne> lignes = new List<Ligne>();
        readonly Font fTitre = Theme.Police(9.5f, FontStyle.Bold), fDetail = Theme.Police(8.5f);
        const int Pad = 14, Ecart = 12, Retrait = 18;

        public EtatPoste() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }

        public void Definir(List<Ligne> l)
        {
            lignes = l ?? new List<Ligne>();
            AccessibleName = string.Join(" ; ", lignes.Select(x => x.Titre + " : " + x.Detail).ToArray());
            Height = HauteurPour(Width > 0 ? Width : 270);
            Invalidate();
        }

        int LargeurTexte(int largeur) { return Math.Max(40, largeur - Padding.Horizontal - 2 * Pad - Retrait); }
        int HauteurLigne(Ligne l, int lt) { return Mise.HauteurTexte(l.Titre, fTitre, lt) + 2 + Mise.HauteurTexte(l.Detail, fDetail, lt); }

        public int HauteurPour(int largeur)
        {
            int lt = LargeurTexte(largeur), h = 2 * Pad;
            for (int i = 0; i < lignes.Count; i++) h += (i > 0 ? Ecart : 0) + HauteurLigne(lignes[i], lt);
            return h + Padding.Vertical;
        }

        protected override void OnResize(EventArgs e) { base.OnResize(e); int h = HauteurPour(Width); if (h != Height) Height = h; }

        static Color Point(Niveau n)
        {
            switch (n)
            {
                case Niveau.Ok: return Theme.Vert;
                case Niveau.Attention: return Theme.Orange;
                case Niveau.Danger: return Theme.RougeTexte;
                default: return Theme.Texte3;
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Theme.Fond);
            Theme.Qualite(g);
            bool alerte = lignes.Any(l => l.Niveau == Niveau.Attention);
            var cadre = new RectangleF(Padding.Left + 0.5f, Padding.Top + 0.5f, Width - Padding.Horizontal - 1, Height - Padding.Vertical - 1);
            using (var p = Theme.Arrondi(cadre, 12))
            using (var b = new SolidBrush(Theme.Panneau))
            using (var pen = new Pen(alerte ? Color.FromArgb(0x3a, 0x2a, 0x12) : Theme.Ligne, 1f)) { g.FillPath(b, p); g.DrawPath(pen, p); }
            int lt = LargeurTexte(Width), x = Padding.Left + Pad, y = Padding.Top + Pad;
            foreach (var l in lignes)
            {
                using (var b = new SolidBrush(Point(l.Niveau))) g.FillEllipse(b, x, y + 5, 8, 8);
                int ht = Mise.HauteurTexte(l.Titre, fTitre, lt), hd = Mise.HauteurTexte(l.Detail, fDetail, lt);
                TextRenderer.DrawText(g, l.Titre, fTitre, new Rectangle(x + Retrait, y, lt, ht + 2), Theme.Texte, Mise.Flux);
                TextRenderer.DrawText(g, l.Detail, fDetail, new Rectangle(x + Retrait, y + ht + 2, lt, hd + 2), Theme.Texte2, Mise.Flux);
                y += ht + 2 + hd + Ecart;
            }
        }
    }

    /// <summary>Trois feux (rouge, orange, vert) : celui du verdict est allume. Niveau.Attente : tous eteints.</summary>
    class Feux : Control, IHauteur
    {
        Niveau niveau = Niveau.Attente;
        public Feux() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
        public Niveau Niveau { get { return niveau; } set { niveau = value; AccessibleName = Niveaux.Mot(value); Invalidate(); } }
        public int HauteurPour(int largeur) { return 30; }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            var fond = Carte.FondDe(Parent);
            g.Clear(fond);
            Theme.Qualite(g);
            var feux = new[] { Tuple.Create(Niveau.Danger, Theme.Rouge), Tuple.Create(Niveau.Attention, Theme.Orange), Tuple.Create(Niveau.Ok, Theme.Vert) };
            for (int i = 0; i < 3; i++)
            {
                var r = new RectangleF(4 + i * 34, 4, 22, 22);
                bool allume = feux[i].Item1 == niveau;
                if (allume) using (var b = new SolidBrush(Color.FromArgb(70, feux[i].Item2))) g.FillEllipse(b, r.X - 4, r.Y - 4, r.Width + 8, r.Height + 8);
                using (var b = new SolidBrush(allume ? feux[i].Item2 : Color.FromArgb(0x2b, 0x2b, 0x2f))) g.FillEllipse(b, r);
            }
        }
    }
}
