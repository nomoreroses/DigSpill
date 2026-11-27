// DigSpill - boites de dialogue et notifications au theme (remplacent les MessageBox grises de Windows).
// Une question dit l'action sur ses boutons (« Forcer l'éjection », « Continuer la collecte ») au lieu de « Oui / Non ».
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace DigSpill
{
    /// <summary>Un bouton de boite de dialogue : son libelle et son style.</summary>
    class Reponse
    {
        public readonly string Libelle;
        public readonly BoutonPlat.Genre Genre;
        public Reponse(string libelle, BoutonPlat.Genre genre) { Libelle = libelle; Genre = genre; }
    }

    static class Boite
    {
        /// <summary>Message avec un seul bouton.</summary>
        public static void Informer(IWin32Window parent, Niveau n, string titre, string texte)
        {
            Choisir(parent, n, titre, texte, 0, new Reponse("OK", BoutonPlat.Genre.Primaire));
        }

        /// <summary>Question a deux reponses ; vrai si l'action est choisie.
        /// <paramref name="risque"/> : l'action est la reponse dangereuse (contour rouge), l'autre est le bouton principal et le choix par defaut.</summary>
        public static bool Confirmer(IWin32Window parent, Niveau n, string titre, string texte, string action, string annuler, bool risque)
        {
            var a = new Reponse(action, risque ? BoutonPlat.Genre.Risque : n == Niveau.Danger ? BoutonPlat.Genre.Danger : BoutonPlat.Genre.Primaire);
            var b = new Reponse(annuler, risque ? BoutonPlat.Genre.Primaire : BoutonPlat.Genre.Secondaire);
            // comme dans le pied de page : l'action a droite
            return Choisir(parent, n, titre, texte, risque ? 0 : 1, b, a) == 1;
        }

        /// <summary>Rend l'indice de la reponse choisie, -1 si la boite est fermee par Echap.</summary>
        public static int Choisir(IWin32Window parent, Niveau n, string titre, string texte, int parDefaut, params Reponse[] reponses)
        {
            var proprietaire = parent as Form;
            Form voile = null;
            if (proprietaire != null && proprietaire.Visible && proprietaire.WindowState != FormWindowState.Minimized)
            {
                // assombrit la fenetre derriere la question, comme dans l'interface HTML
                voile = new Form { FormBorderStyle = FormBorderStyle.None, ShowInTaskbar = false, BackColor = Color.Black, Opacity = 0.5, StartPosition = FormStartPosition.Manual, Bounds = proprietaire.Bounds };
                voile.Show(proprietaire);
            }
            try
            {
                using (var d = new Dialogue(n, titre, texte, parDefaut, reponses))
                {
                    d.ShowDialog((IWin32Window)voile ?? parent);
                    return d.Choix;
                }
            }
            finally { if (voile != null) { voile.Close(); voile.Dispose(); } }
        }
    }

    /// <summary>Boite de dialogue sombre : icone du niveau, titre, texte, boutons a droite.</summary>
    class Dialogue : Form
    {
        public int Choix = -1;
        readonly Niveau niveau;
        readonly string titre, message;
        readonly List<BoutonPlat> boutons = new List<BoutonPlat>();
        readonly Font fTitre = Theme.Police(14f, FontStyle.Bold), fTexte = Theme.Police(10.5f), fIcone = Theme.Icones(13f);
        const int Marge = 26, Largeur = 480, Rond = 38;

        public Dialogue(Niveau n, string titre, string message, int parDefaut, Reponse[] reponses)
        {
            niveau = n; this.titre = titre ?? ""; this.message = message ?? "";
            Text = this.titre;
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterParent;
            ShowInTaskbar = false;
            KeyPreview = true;
            BackColor = Theme.Panneau2;
            Font = Theme.Police(10f);
            AutoScaleMode = AutoScaleMode.None;   // tailles calculees a partir des polices : deja a l'echelle de l'ecran
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            Theme.CoinsArrondis(this);

            for (int i = 0; i < reponses.Length; i++)
            {
                int k = i;
                var b = new BoutonPlat(reponses[i].Libelle, reponses[i].Genre);
                b.Click += delegate { Choix = k; Close(); };
                boutons.Add(b);
                Controls.Add(b);
            }
            int largeurBoutons = boutons.Sum(b => b.Width) + 10 * Math.Max(0, boutons.Count - 1);
            int largeur = Math.Max(Largeur, largeurBoutons + 2 * Marge);
            int lt = largeur - 2 * Marge;
            int ht = Math.Max(Rond, Mise.HauteurTexte(this.titre, fTitre, lt - Rond - 14));
            int hm = Mise.HauteurTexte(this.message, fTexte, lt);
            int yb = Marge + ht + (hm > 0 ? 14 + hm : 0) + 24;
            ClientSize = new Size(largeur, yb + 44 + Marge);
            // boutons alignes a droite, dans l'ordre donne
            int x = largeur - Marge - largeurBoutons;
            foreach (var b in boutons) { b.Location = new Point(x, yb); x += b.Width + 10; }
            if (parDefaut >= 0 && parDefaut < boutons.Count) { var b = boutons[parDefaut]; Shown += delegate { b.Focus(); }; }
        }

        /// <summary>Titre, texte et boutons (lus par le pilote automatique des tests).</summary>
        public string Contenu { get { return titre + " : " + message + " [" + string.Join(" | ", boutons.Select(b => b.Text).ToArray()) + "]"; } }

        /// <summary>Clique sur le bouton dont le libelle contient ce texte (pilote automatique).</summary>
        public bool Repondre(string libelle)
        {
            var b = boutons.FirstOrDefault(x => x.Text.IndexOf(libelle, StringComparison.OrdinalIgnoreCase) >= 0);
            if (b == null) return false;
            b.PerformClickPublic();
            return true;
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape) { Choix = -1; Close(); e.Handled = true; }
            base.OnKeyDown(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Theme.Panneau2);
            Theme.Qualite(g);
            using (var p = new Pen(Theme.Ligne2, 1f)) g.DrawRectangle(p, 0, 0, ClientSize.Width - 1, ClientSize.Height - 1);
            int lt = ClientSize.Width - 2 * Marge;
            int ht = Math.Max(Rond, Mise.HauteurTexte(titre, fTitre, lt - Rond - 14));
            var rond = new Rectangle(Marge, Marge + (ht - Rond) / 2, Rond, Rond);
            using (var b = new SolidBrush(Niveaux.Fond(niveau))) g.FillEllipse(b, rond);
            TextRenderer.DrawText(g, Niveaux.Icone(niveau), fIcone, rond, Niveaux.Couleur(niveau), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            int hTitre = Mise.HauteurTexte(titre, fTitre, lt - Rond - 14);
            TextRenderer.DrawText(g, titre, fTitre, new Rectangle(Marge + Rond + 14, Marge + (ht - hTitre) / 2, lt - Rond - 14, hTitre + 2), Theme.Texte, Mise.Flux);
            if (message.Length > 0)
                TextRenderer.DrawText(g, message, fTexte, new Rectangle(Marge, Marge + ht + 14, lt, Mise.HauteurTexte(message, fTexte, lt) + 2), Theme.Texte2, Mise.Flux);
        }
    }

    /// <summary>Petite notification en bas a droite de la fenetre, qui disparait seule (information sans decision).</summary>
    class Notif : Form
    {
        readonly Niveau niveau;
        readonly string titre, detail;
        readonly Font fTitre = Theme.Police(10.5f, FontStyle.Bold), fDetail = Theme.Police(9.5f), fIcone = Theme.Icones(11f);
        readonly Timer fin = new Timer();
        const int L = 340;

        Notif(Niveau n, string titre, string detail, int secondes)
        {
            niveau = n; this.titre = titre ?? ""; this.detail = detail ?? "";
            FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; StartPosition = FormStartPosition.Manual;
            BackColor = Theme.Panneau2; Cursor = Cursors.Hand;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
            Theme.CoinsArrondis(this);
            int h = 14 + Mise.HauteurTexte(this.titre, fTitre, L - 60) + (this.detail.Length > 0 ? 2 + Mise.HauteurTexte(this.detail, fDetail, L - 60) : 0) + 14;
            ClientSize = new Size(L, Math.Max(52, h));
            fin.Interval = Math.Max(2, secondes) * 1000;
            fin.Tick += delegate { fin.Stop(); Close(); };
            Click += delegate { Close(); };
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        /// <summary>Affiche la notification au-dessus des boutons du pied de page de <paramref name="fenetre"/>.</summary>
        public static void Afficher(Form fenetre, Niveau n, string titre, string detail, int secondes = 7)
        {
            if (fenetre == null || fenetre.IsDisposed) return;
            var t = new Notif(n, titre, detail, secondes);
            var zone = fenetre.RectangleToScreen(fenetre.ClientRectangle);
            t.Location = new Point(zone.Right - t.Width - 24, zone.Bottom - t.Height - 96);
            t.FormClosed += delegate { t.fin.Dispose(); t.Dispose(); };
            t.Show(fenetre);
            t.fin.Start();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Theme.Panneau2);
            Theme.Qualite(g);
            using (var p = new Pen(Theme.Ligne2, 1f)) g.DrawRectangle(p, 0, 0, ClientSize.Width - 1, ClientSize.Height - 1);
            var rond = new Rectangle(14, (ClientSize.Height - 28) / 2, 28, 28);
            using (var b = new SolidBrush(Niveaux.Fond(niveau))) g.FillEllipse(b, rond);
            TextRenderer.DrawText(g, Niveaux.Icone(niveau), fIcone, rond, Niveaux.Couleur(niveau), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            int ht = Mise.HauteurTexte(titre, fTitre, L - 60), hd = detail.Length > 0 ? Mise.HauteurTexte(detail, fDetail, L - 60) : 0;
            int y = (ClientSize.Height - ht - (hd > 0 ? hd + 2 : 0)) / 2;
            TextRenderer.DrawText(g, titre, fTitre, new Rectangle(52, y, L - 60, ht + 2), Theme.Texte, Mise.Flux);
            if (hd > 0) TextRenderer.DrawText(g, detail, fDetail, new Rectangle(52, y + ht + 2, L - 60, hd + 2), Theme.Texte2, Mise.Flux);
        }
    }
}
