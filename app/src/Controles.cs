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

    /// <summary>Carte arrondie qui contient une colonne.</summary>
    class Carte : Panel, IHauteur
    {
        public readonly Colonne Contenu = new Colonne();
        Color fond = Theme.Blanc, bord = Theme.Trait;
        public int Rayon = 12;
        public float Epaisseur = 1f;

        public Carte()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            Padding = new Padding(20, 18, 20, 18);
            BackColor = fond;
            Contenu.Dock = DockStyle.Fill;
            Controls.Add(Contenu);
        }

        public Carte Couleurs(Color f, Color b) { fond = f; bord = b; BackColor = f; Invalidate(true); return this; }
        public Color Fond { get { return fond; } }

        public int HauteurPour(int largeur) { return Padding.Vertical + Contenu.HauteurPour(largeur - Padding.Horizontal); }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Parent != null ? FondDe(Parent) : Theme.Papier);
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
        public enum Genre { Primaire, Secondaire, Danger, Discret, Succes }
        Genre genre;
        string icone;
        bool survol, appui;

        public BoutonPlat(string texte, Genre g) : this(texte, g, null) { }
        public BoutonPlat(string texte, Genre g, string icone)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint |
                     ControlStyles.ResizeRedraw | ControlStyles.Selectable | ControlStyles.StandardClick, true);
            genre = g;
            this.icone = icone;
            Font = Theme.Police(10f, FontStyle.Bold);
            Cursor = Cursors.Hand;
            TabStop = true;
            Margin = new Padding(10, 0, 0, 0);
            Text = texte;
            Height = 42;
            Ajuster();
        }

        public Genre Style { get { return genre; } set { genre = value; Invalidate(); } }
        public string Icone { get { return icone; } set { icone = value; Ajuster(); Invalidate(); } }

        void Ajuster()
        {
            var t = TextRenderer.MeasureText(Text ?? "", Font);
            Width = Math.Max(120, t.Width + 44 + (string.IsNullOrEmpty(icone) ? 0 : 26));
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
                case Genre.Primaire: fond = Theme.Accent; texte = Theme.Nuit; bord = fond; break;
                case Genre.Danger: fond = Theme.Rouge; texte = Color.White; bord = fond; break;
                case Genre.Succes: fond = Theme.Vert; texte = Color.White; bord = fond; break;
                case Genre.Discret: fond = Carte.FondDe(Parent); texte = Theme.Doux; bord = fond; break;
                default: fond = Theme.Blanc; texte = Theme.Encre; bord = Theme.Trait; break;
            }
            if (Enabled && (survol || appui)) fond = Melanger(fond, genre == Genre.Secondaire || genre == Genre.Discret ? Theme.Trait : Color.Black, appui ? 0.18f : 0.08f);
            if (!Enabled) { fond = Color.FromArgb(228, 224, 214); texte = Color.FromArgb(140, 140, 140); bord = fond; }
            var r = new RectangleF(1, 1, Width - 3, Height - 3);
            using (var p = Theme.Arrondi(r, 9))
            using (var b = new SolidBrush(fond))
            {
                g.FillPath(b, p);
                if (bord != fond) using (var pen = new Pen(bord, 1.5f)) g.DrawPath(pen, p);
                if (Focused && ShowFocusCues) using (var pen = new Pen(Theme.Bleu, 2f)) g.DrawPath(pen, p);
            }
            var tt = TextRenderer.MeasureText(Text ?? "", Font);
            int largeurTotale = tt.Width + (string.IsNullOrEmpty(icone) ? 0 : 26);
            int x = (Width - largeurTotale) / 2;
            if (!string.IsNullOrEmpty(icone))
            {
                using (var fi = Theme.Icones(11f))
                    TextRenderer.DrawText(g, icone, fi, new Rectangle(x, 0, 24, Height), texte, TextFormatFlags.VerticalCenter | TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding);
                x += 26;
            }
            TextRenderer.DrawText(g, Text ?? "", Font, new Rectangle(x, 0, tt.Width + 4, Height), texte, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding);
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
                case Niveau.EnCours: return Theme.AccentEncre;
                case Niveau.Info: return Theme.Bleu;
                default: return Theme.Doux;
            }
        }
        public static Color Fond(Niveau n)
        {
            switch (n)
            {
                case Niveau.Ok: return Theme.VertFond;
                case Niveau.Attention: return Theme.OrangeFond;
                case Niveau.Danger: return Theme.RougeFond;
                case Niveau.EnCours: return Theme.AccentClair;
                case Niveau.Info: return Theme.BleuFond;
                default: return Color.FromArgb(236, 232, 222);
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

    /// <summary>Pastille : petit libelle arrondi colore.</summary>
    class Pastille : Control
    {
        Color fond, texte;
        public Pastille(string t, Color texte, Color fond)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
            Font = Theme.Police(9f, FontStyle.Bold);
            Margin = new Padding(0, 0, 8, 6);
            Definir(t, texte, fond);
        }
        public Pastille(string t, Niveau n) : this(t, Niveaux.Couleur(n), Niveaux.Fond(n)) { }
        public void Definir(string t, Color texte, Color fond)
        {
            this.texte = texte; this.fond = fond; Text = t;
            var s = TextRenderer.MeasureText(t ?? "", Font);
            Size = new Size(s.Width + 22, Math.Max(26, s.Height + 8));
            Invalidate();
        }
        public void Definir(string t, Niveau n) { Definir(t, Niveaux.Couleur(n), Niveaux.Fond(n)); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Carte.FondDe(Parent));
            Theme.Qualite(g);
            using (var p = Theme.Arrondi(new RectangleF(0, 0, Width - 1, Height - 1), Height / 2f))
            using (var b = new SolidBrush(fond)) g.FillPath(b, p);
            TextRenderer.DrawText(g, Text, Font, ClientRectangle, texte, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
    }

    /// <summary>Ligne d'etat : icone dans un rond + titre + detail (texte qui passe a la ligne).</summary>
    class LigneInfo : Control, IHauteur
    {
        Niveau niveau;
        string titre, detail;
        readonly Font fTitre = Theme.Police(10.5f, FontStyle.Bold), fDetail = Theme.Police(9.5f), fIcone = Theme.Icones(11f);
        public LigneInfo(Niveau n, string titre, string detail)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            niveau = n; this.titre = titre; this.detail = detail;
        }
        public Niveau Niveau { get { return niveau; } }
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
            TextRenderer.DrawText(g, Niveaux.Icone(niveau), fIcone, rond, Niveaux.Couleur(niveau), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
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
        bool indeterminee;
        int phase;
        readonly Timer minuterie = new Timer { Interval = 40 };
        public Color Couleur = Theme.Accent;
        public Barre()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            minuterie.Tick += delegate { phase = (phase + 6) % 1000; Invalidate(); };
        }
        public int HauteurPour(int largeur) { return 10; }
        public double Valeur { get { return valeur; } set { valeur = Math.Max(0, Math.Min(1, value)); if (indeterminee) Indeterminee = false; Invalidate(); } }
        public bool Indeterminee
        {
            get { return indeterminee; }
            set
            {
                if (value == indeterminee) return;
                indeterminee = value;
                if (value) minuterie.Start(); else minuterie.Stop();
                Invalidate();
            }
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Carte.FondDe(Parent));
            Theme.Qualite(g);
            var r = new RectangleF(0, 0, Width - 1, Height - 1);
            using (var p = Theme.Arrondi(r, Height / 2f)) using (var b = new SolidBrush(Color.FromArgb(232, 226, 212))) g.FillPath(b, p);
            RectangleF plein;
            if (indeterminee) { float l = Width * 0.25f; float x = (Width + l) * phase / 1000f - l; plein = new RectangleF(Math.Max(0, x), 0, Math.Min(l, Width - Math.Max(0, x)), Height - 1); }
            else plein = new RectangleF(0, 0, (float)((Width - 1) * valeur), Height - 1);
            if (plein.Width > 2) using (var p = Theme.Arrondi(plein, Height / 2f)) using (var b = new SolidBrush(Couleur)) g.FillPath(b, p);
        }
        protected override void Dispose(bool d) { if (d) minuterie.Dispose(); base.Dispose(d); }
    }

    /// <summary>Liste des etapes dans la barre laterale.</summary>
    class ListeEtapes : Control
    {
        string[] etapes = new string[0];
        int courante = -1;
        readonly Font f = Theme.Police(10.5f), fg = Theme.Police(10.5f, FontStyle.Bold), fn = Theme.Police(9f, FontStyle.Bold), fi = Theme.Icones(9f);
        public ListeEtapes() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
        public void Definir(string[] e, int c) { etapes = e ?? new string[0]; courante = c; Invalidate(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Theme.Nuit);
            Theme.Qualite(g);
            for (int i = 0; i < etapes.Length; i++)
            {
                int y = i * 52;
                bool fait = i < courante, cour = i == courante;
                if (i < etapes.Length - 1) using (var p = new Pen(fait ? Theme.Accent : Theme.TraitNuit, 2f)) g.DrawLine(p, 15, y + 30, 15, y + 52);
                var rond = new Rectangle(1, y, 28, 28);
                if (cour || fait) using (var b = new SolidBrush(Theme.Accent)) g.FillEllipse(b, rond);
                else using (var p = new Pen(Theme.TraitNuit, 2f)) g.DrawEllipse(p, rond);
                if (fait) TextRenderer.DrawText(g, Ic.Ok, fi, rond, Theme.Nuit, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                else TextRenderer.DrawText(g, (i + 1).ToString(), fn, rond, cour ? Theme.Nuit : Theme.DouxNuit, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                TextRenderer.DrawText(g, etapes[i], cour ? fg : f, new Rectangle(42, y, Width - 44, 28), cour ? Color.White : (fait ? Theme.DouxNuit : Color.FromArgb(130, 142, 162)), TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
            }
        }
    }

    /// <summary>Grande carte cliquable de l'accueil.</summary>
    class CarteChoix : Control, IHauteur
    {
        readonly string icone, titre, texte, note;
        bool survol;
        readonly Font fIcone = Theme.Icones(26f), fTitre = Theme.Police(15f, FontStyle.Bold), fTexte = Theme.Police(10.5f), fNote = Theme.Police(9f, FontStyle.Bold);
        public CarteChoix(string icone, string titre, string texte, string note)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            this.icone = icone; this.titre = titre; this.texte = texte; this.note = note;
            Cursor = Cursors.Hand; TabStop = true;
        }
        public int HauteurPour(int largeur) { return 140 + Mise.HauteurTexte(texte, fTexte, largeur - 56) + (string.IsNullOrEmpty(note) ? 24 : 58); }
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
            using (var p = Theme.Arrondi(r, 16))
            using (var b = new SolidBrush(survol ? Color.White : Theme.Blanc))
            using (var pen = new Pen(survol || Focused ? Theme.Accent : Theme.Trait, survol || Focused ? 2.5f : 1.5f))
            { g.FillPath(b, p); g.DrawPath(pen, p); }
            var rond = new Rectangle(28, 28, 60, 60);
            using (var b = new SolidBrush(Theme.AccentClair)) g.FillEllipse(b, rond);
            TextRenderer.DrawText(g, icone, fIcone, rond, Theme.AccentEncre, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, titre, fTitre, new Rectangle(28, 104, Width - 56, 34), Theme.Encre, TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, texte, fTexte, new Rectangle(28, 140, Width - 56, Mise.HauteurTexte(texte, fTexte, Width - 56) + 4), Theme.Doux, Mise.Flux);
            if (!string.IsNullOrEmpty(note))
                TextRenderer.DrawText(g, note, fNote, new Rectangle(28, Height - 36, Width - 56, 24), Theme.AccentEncre, TextFormatFlags.NoPadding);
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
            etiquette = Mise.Texte(libelle + (obligatoire ? " *" : ""), Theme.Police(9.5f, FontStyle.Bold), Theme.Encre);
            cadre = new CadreSaisie();
            Saisie = saisie;
            saisie.Font = Theme.Police(10.5f);
            var tb = saisie as TextBox;
            if (tb != null) { tb.BorderStyle = BorderStyle.None; tb.BackColor = Color.White; }
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
                BackColor = Color.White;
            }
            protected override void OnPaintBackground(PaintEventArgs e)
            {
                var g = e.Graphics;
                g.Clear(Carte.FondDe(Parent));
                Theme.Qualite(g);
                bool focus = Controls.Count > 0 && Controls[0].ContainsFocus;
                using (var p = Theme.Arrondi(new RectangleF(1, 1, Width - 3, Height - 3), 8))
                using (var b = new SolidBrush(Color.White))
                using (var pen = new Pen(focus ? Theme.Accent : Theme.Trait, focus ? 2f : 1.2f))
                { g.FillPath(b, p); g.DrawPath(pen, p); }
            }
        }
    }

    /// <summary>Case a cocher sur fond transparent, avec texte qui passe a la ligne.</summary>
    class Case : CheckBox, IHauteur
    {
        public Case(string texte, bool coche)
        {
            Text = texte; Checked = coche; Font = Theme.Police(10f); ForeColor = Theme.Encre;
            BackColor = Color.Transparent; AutoSize = false; UseMnemonic = false; TextAlign = ContentAlignment.TopLeft; CheckAlign = ContentAlignment.TopLeft;
        }
        public int HauteurPour(int largeur) { return Math.Max(24, Mise.HauteurTexte(Text, Font, largeur - 24) + 6); }
    }

    class Choix : RadioButton, IHauteur
    {
        public Choix(string texte, bool coche)
        {
            Text = texte; Checked = coche; Font = Theme.Police(10f); ForeColor = Theme.Encre;
            BackColor = Color.Transparent; AutoSize = false; UseMnemonic = false; TextAlign = ContentAlignment.TopLeft; CheckAlign = ContentAlignment.TopLeft;
        }
        public int HauteurPour(int largeur) { return Math.Max(24, Mise.HauteurTexte(Text, Font, largeur - 24) + 6); }
    }

    /// <summary>Journal defilant (fond sombre).</summary>
    class Journal : Panel, IHauteur
    {
        readonly TextBox boite;
        public int Hauteur = 200;
        readonly Queue<string> lignes = new Queue<string>();
        readonly Timer vidage = new Timer { Interval = 150 };
        readonly List<string> enAttente = new List<string>();
        public Journal()
        {
            BackColor = Theme.Nuit2;
            Padding = new Padding(12, 10, 6, 10);
            boite = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, BorderStyle = BorderStyle.None, BackColor = Theme.Nuit2, ForeColor = Theme.DouxNuit, Font = Theme.Mono(8.5f), Dock = DockStyle.Fill, WordWrap = false };
            Controls.Add(boite);
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
            foreach (var l in neuves) { lignes.Enqueue(l); while (lignes.Count > 400) lignes.Dequeue(); }
            boite.Text = string.Join("\r\n", lignes.ToArray());
            boite.SelectionStart = boite.TextLength;
            boite.ScrollToCaret();
        }
        public string Tout() { return string.Join("\r\n", lignes.ToArray()); }
        protected override void Dispose(bool d) { if (d) vidage.Dispose(); base.Dispose(d); }
    }

    /// <summary>Texte d'empreinte en gros caracteres a chasse fixe.</summary>
    class Empreinte : Control, IHauteur
    {
        readonly Font f = Theme.Mono(15f);
        public Empreinte() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
        string Groupes()
        {
            var t = Text ?? "";
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < t.Length; i++) { if (i > 0 && i % 16 == 0) sb.Append(i % 32 == 0 ? "\n" : "   "); else if (i > 0 && i % 4 == 0) sb.Append(' '); sb.Append(t[i]); }
            return sb.ToString();
        }
        public int HauteurPour(int largeur) { return Mise.HauteurTexte(Groupes(), f, largeur) + 6; }
        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); if (Parent != null) Parent.PerformLayout(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(Carte.FondDe(Parent));
            TextRenderer.DrawText(e.Graphics, Groupes(), f, ClientRectangle, Color.White, Mise.Flux);
        }
    }
}
