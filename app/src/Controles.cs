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
                case Genre.Primaire: fond = Theme.Rouge; texte = Color.White; bord = fond; break;
                case Genre.Danger: fond = Theme.Rouge; texte = Color.White; bord = fond; break;
                case Genre.Succes: fond = Theme.Texte; texte = Theme.Fond; bord = fond; break;
                case Genre.Discret: fond = Carte.FondDe(Parent); texte = Theme.Texte2; bord = fond; break;
                default: fond = Carte.FondDe(Parent); texte = Theme.Texte; bord = Theme.Ligne2; break;
            }
            bool clair = genre == Genre.Secondaire || genre == Genre.Discret;
            if (Enabled && (survol || appui)) { if (clair) { fond = Theme.Panneau2; if (genre == Genre.Discret) texte = Theme.Texte; } else fond = Melanger(fond, Color.White, appui ? 0.04f : 0.1f); }
            if (!Enabled) { fond = Theme.Panneau2; texte = Theme.Texte3; bord = fond; }
            var r = new RectangleF(1, 1, Width - 3, Height - 3);
            using (var p = Theme.Arrondi(r, 10))
            using (var b = new SolidBrush(fond))
            {
                g.FillPath(b, p);
                if (bord != fond) using (var pen = new Pen(bord, 1f)) g.DrawPath(pen, p);
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
        public Color Couleur = Theme.Texte;
        public Barre()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            minuterie.Tick += delegate { phase = (phase + 6) % 1000; Invalidate(); };
        }
        public int HauteurPour(int largeur) { return 6; }
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
            using (var p = Theme.Arrondi(r, Height / 2f)) using (var b = new SolidBrush(Theme.Ligne)) g.FillPath(b, p);
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
        readonly Font f = Theme.Police(10.5f), fg = Theme.Police(10.5f, FontStyle.Bold), fn = Theme.Mono(8.5f);
        public ListeEtapes() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
        public void Definir(string[] e, int c) { etapes = e ?? new string[0]; courante = c; Invalidate(); }
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
                TextRenderer.DrawText(g, etapes[i], cour ? fg : f, new Rectangle(54, y, Width - 56, 26), cour ? Theme.Texte : (fait ? Theme.Texte2 : Theme.Texte3), TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
            }
        }
    }

    /// <summary>Grande carte cliquable de l'accueil.</summary>
    class CarteChoix : Control, IHauteur
    {
        readonly string icone, titre, texte, note;
        bool survol;
        readonly Font fIcone = Theme.Icones(17f), fTitre = Theme.Police(15f, FontStyle.Bold), fTexte = Theme.Police(10.5f), fNote = Theme.Mono(8.5f);
        public CarteChoix(string icone, string titre, string texte, string note)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            this.icone = icone; this.titre = titre; this.texte = texte; this.note = note;
            Cursor = Cursors.Hand; TabStop = true;
            AccessibleName = titre; AccessibleDescription = texte; AccessibleRole = AccessibleRole.PushButton;
        }
        public int HauteurPour(int largeur) { return 124 + Mise.HauteurTexte(texte, fTexte, largeur - 56) + (string.IsNullOrEmpty(note) ? 24 : 58); }
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
            var rond = new Rectangle(28, 28, 44, 44);
            using (var b = new SolidBrush(survol ? Theme.Ligne2 : Theme.Panneau2)) g.FillEllipse(b, rond);
            TextRenderer.DrawText(g, icone, fIcone, rond, Theme.Texte, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, titre, fTitre, new Rectangle(28, 88, Width - 56, 34), Theme.Texte, TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, texte, fTexte, new Rectangle(28, 124, Width - 56, Mise.HauteurTexte(texte, fTexte, Width - 56) + 4), Theme.Texte2, Mise.Flux);
            if (!string.IsNullOrEmpty(note))
                TextRenderer.DrawText(g, note.ToUpperInvariant(), fNote, new Rectangle(28, Height - 36, Width - 56, 24), Theme.Texte3, TextFormatFlags.NoPadding);
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
        readonly Font f = Theme.MonoMoyen(15f);
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
            TextRenderer.DrawText(e.Graphics, Groupes(), f, ClientRectangle, Theme.Texte, Mise.Flux);
        }
    }
}
