// DigSpill - theme graphique (couleurs, polices, icones). C# 5 : compilable par le csc integre a Windows.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Linq;

namespace DigSpill
{
    static class Theme
    {
        public static readonly Color Nuit = Color.FromArgb(11, 18, 32);
        public static readonly Color Nuit2 = Color.FromArgb(20, 29, 48);
        public static readonly Color TraitNuit = Color.FromArgb(42, 53, 80);
        public static readonly Color DouxNuit = Color.FromArgb(180, 191, 208);
        public static readonly Color Papier = Color.FromArgb(245, 242, 234);
        public static readonly Color Blanc = Color.FromArgb(252, 250, 245);
        public static readonly Color Trait = Color.FromArgb(217, 209, 191);
        public static readonly Color Encre = Color.FromArgb(17, 24, 39);
        public static readonly Color Doux = Color.FromArgb(74, 84, 102);
        public static readonly Color Accent = Color.FromArgb(255, 138, 61);
        public static readonly Color AccentEncre = Color.FromArgb(168, 56, 10);
        public static readonly Color AccentClair = Color.FromArgb(255, 237, 224);
        public static readonly Color Vert = Color.FromArgb(22, 120, 64);
        public static readonly Color VertFond = Color.FromArgb(228, 244, 233);
        public static readonly Color Orange = Color.FromArgb(166, 77, 0);
        public static readonly Color OrangeFond = Color.FromArgb(254, 241, 222);
        public static readonly Color Rouge = Color.FromArgb(185, 28, 38);
        public static readonly Color RougeFond = Color.FromArgb(253, 233, 233);
        public static readonly Color Bleu = Color.FromArgb(29, 78, 160);
        public static readonly Color BleuFond = Color.FromArgb(230, 238, 252);

        static bool init;
        static string familleTexte, familleIcones, familleMono;

        static void Init()
        {
            if (init) return;
            init = true;
            var noms = new HashSet<string>(new InstalledFontCollection().Families.Select(f => f.Name), StringComparer.OrdinalIgnoreCase);
            familleTexte = Premier(noms, "Segoe UI", "Noto Sans", "DejaVu Sans") ?? FontFamily.GenericSansSerif.Name;
            familleIcones = Premier(noms, "Segoe Fluent Icons", "Segoe MDL2 Assets");
            familleMono = Premier(noms, "Cascadia Mono", "Consolas", "DejaVu Sans Mono") ?? FontFamily.GenericMonospace.Name;
        }

        static string Premier(HashSet<string> noms, params string[] candidats)
        {
            foreach (var c in candidats) if (noms.Contains(c)) return c;
            return null;
        }

        public static Font Police(float taille) { return Police(taille, FontStyle.Regular); }
        public static Font Police(float taille, FontStyle style) { Init(); return new Font(familleTexte, taille, style, GraphicsUnit.Point); }
        public static Font Mono(float taille) { Init(); return new Font(familleMono, taille, FontStyle.Regular, GraphicsUnit.Point); }
        public static bool IconesDispo { get { Init(); return familleIcones != null; } }
        public static Font Icones(float taille) { Init(); return new Font(familleIcones ?? familleTexte, taille, FontStyle.Regular, GraphicsUnit.Point); }

        public static GraphicsPath Arrondi(RectangleF r, float rayon)
        {
            var p = new GraphicsPath();
            float d = Math.Min(rayon * 2, Math.Min(r.Width, r.Height));
            if (d <= 1) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        public static void Qualite(Graphics g)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        }
    }

    /// <summary>Icones Segoe MDL2 / Fluent (Windows 10 et 11), avec un caractere de repli.</summary>
    static class Ic
    {
        static string I(string mdl2, string repli) { return Theme.IconesDispo ? mdl2 : repli; }
        public static string Collecter { get { return I("", "▼"); } }
        public static string Analyser { get { return I("", "◎"); } }
        public static string Verrou { get { return I("", "■"); } }
        public static string Ok { get { return I("", "✓"); } }
        public static string Attention { get { return I("", "!"); } }
        public static string Erreur { get { return I("", "✖"); } }
        public static string Dossier { get { return I("", "▤"); } }
        public static string Usb { get { return I("", "▭"); } }
        public static string Bouclier { get { return I("", "◆"); } }
        public static string Personne { get { return I("", "●"); } }
        public static string Info { get { return I("", "i"); } }
        public static string Arret { get { return I("", "■"); } }
        public static string Lecture { get { return I("", "▶"); } }
        public static string Recherche { get { return I("", "○"); } }
        public static string Document { get { return I("", "□"); } }
        public static string Actualiser { get { return I("", "↻"); } }
        public static string Copier { get { return I("", "❐"); } }
        public static string Horloge { get { return I("", "◷"); } }
        public static string Retour { get { return I("", "←"); } }
        public static string Suivant { get { return I("", "→"); } }
        public static string Attente { get { return "○"; } }
    }
}
