// DigSpill - theme graphique : la meme direction artistique que l'interface HTML (fond noir, Geist, point rouge).
// C# 5 : compilable par le csc integre a Windows. Polices Geist embarquees (OFL), chargees en memoire : rien n'est installe.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace DigSpill
{
    static class Theme
    {
        // jetons de l'interface HTML (style.css) : --bg, --panel, --panel2, --line, --line2, --fg, --fg2, --fg3, --accent, --red, --blue
        public static readonly Color Fond = Color.FromArgb(0x0b, 0x0b, 0x0c);
        public static readonly Color Panneau = Color.FromArgb(0x11, 0x11, 0x13);
        public static readonly Color Panneau2 = Color.FromArgb(0x18, 0x18, 0x1b);
        public static readonly Color Ligne = Color.FromArgb(0x22, 0x22, 0x26);
        public static readonly Color Ligne2 = Color.FromArgb(0x2e, 0x2e, 0x33);
        public static readonly Color Texte = Color.FromArgb(0xed, 0xed, 0xef);
        public static readonly Color Texte2 = Color.FromArgb(0xa9, 0xa9, 0xb1);
        public static readonly Color Texte3 = Color.FromArgb(0x8b, 0x8b, 0x94);
        public static readonly Color Rouge = Color.FromArgb(0xd7, 0x19, 0x21);      // accent : bouton principal, point du logo, etape en cours
        public static readonly Color RougeTexte = Color.FromArgb(0xff, 0x6a, 0x5f);
        public static readonly Color Bleu = Color.FromArgb(0x7c, 0xb0, 0xff);
        public static readonly Color Vert = Color.FromArgb(0x5b, 0xd6, 0x8a);
        public static readonly Color Orange = Color.FromArgb(0xf5, 0xa5, 0x24);

        // noms historiques, gardes pour les pages : ils pointent vers les jetons ci-dessus
        public static readonly Color Nuit = Fond, Nuit2 = Panneau, TraitNuit = Ligne2, DouxNuit = Texte2;
        public static readonly Color Papier = Fond, Blanc = Fond, Trait = Ligne, Encre = Texte, Doux = Texte2, Pale = Texte3;
        public static readonly Color Accent = Rouge, AccentEncre = RougeTexte, AccentClair = Panneau2;
        public static readonly Color VertFond = Teinte(Vert), OrangeFond = Teinte(Orange), RougeFond = Teinte(RougeTexte), BleuFond = Teinte(Bleu);

        /// <summary>Couleur a 14 % sur le fond noir (comme un fond de pastille).</summary>
        public static Color Teinte(Color c)
        {
            const float a = 0.14f;
            return Color.FromArgb((int)(c.R * a + Fond.R * (1 - a)), (int)(c.G * a + Fond.G * (1 - a)), (int)(c.B * a + Fond.B * (1 - a)));
        }

        // ------------------------------------------------------------------ polices
        static bool init;
        static string familleIcones, repliTexte, repliMono;
        static readonly PrivateFontCollection embarquees = new PrivateFontCollection();
        static readonly Dictionary<string, FontFamily> familles = new Dictionary<string, FontFamily>(StringComparer.OrdinalIgnoreCase);

        [DllImport("gdi32.dll")]
        static extern IntPtr AddFontMemResourceEx(IntPtr pbFont, uint cbFont, IntPtr pdv, [In] ref uint pcFonts);

        static void Charger(string ressource)
        {
            try
            {
                using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream(ressource))
                {
                    if (s == null) return;
                    var octets = new byte[s.Length];
                    int lu = 0; while (lu < octets.Length) { int n = s.Read(octets, lu, octets.Length - lu); if (n <= 0) break; lu += n; }
                    // memoire jamais liberee : GDI et GDI+ lisent la police tant que l'appli tourne
                    IntPtr p = Marshal.AllocCoTaskMem(octets.Length);
                    Marshal.Copy(octets, 0, p, octets.Length);
                    embarquees.AddMemoryFont(p, octets.Length);
                    try { uint nb = 0; AddFontMemResourceEx(p, (uint)octets.Length, IntPtr.Zero, ref nb); } catch { } // TextRenderer (GDI) : hors Windows, sans effet
                }
            }
            catch { }
        }

        static void Init()
        {
            if (init) return;
            init = true;
            foreach (var r in new[] { "Geist-Regular.ttf", "Geist-SemiBold.ttf", "GeistMono-Regular.ttf", "GeistMono-Medium.ttf" }) Charger("DigSpill." + r);
            foreach (var f in embarquees.Families)
            {
                // une police en memoire que GDI+ ne sait pas mesurer (Mono, certains Windows) : on l'ignore et on passe au repli
                try { using (var t = new Font(f, 10f, FontStyle.Regular, GraphicsUnit.Point)) { if (t.GetHeight() > 0) familles[f.Name] = f; } } catch { }
            }
            var noms = new HashSet<string>(new InstalledFontCollection().Families.Select(f => f.Name), StringComparer.OrdinalIgnoreCase);
            installees = noms;
            repliTexte = Premier(noms, "Segoe UI", "Noto Sans", "DejaVu Sans") ?? FontFamily.GenericSansSerif.Name;
            repliMono = Premier(noms, "Cascadia Mono", "Consolas", "DejaVu Sans Mono") ?? FontFamily.GenericMonospace.Name;
            familleIcones = Premier(noms, "Segoe Fluent Icons", "Segoe MDL2 Assets");
        }

        static string Premier(HashSet<string> noms, params string[] candidats)
        {
            foreach (var c in candidats) if (noms.Contains(c)) return c;
            return null;
        }

        static HashSet<string> installees = new HashSet<string>();
        static bool Dispo(string famille) { return familles.ContainsKey(famille) || installees.Contains(famille); }

        static Font Creer(string famille, string repli, float taille)
        {
            FontFamily f;
            if (familles.TryGetValue(famille, out f)) return new Font(f, taille, FontStyle.Regular, GraphicsUnit.Point);
            if (installees.Contains(famille)) return new Font(famille, taille, FontStyle.Regular, GraphicsUnit.Point);
            return new Font(repli, taille, FontStyle.Regular, GraphicsUnit.Point);
        }

        /// <summary>Geist ; « gras » = Geist SemiBold (600), comme les titres de l'interface HTML.</summary>
        public static Font Police(float taille) { return Police(taille, FontStyle.Regular); }
        public static Font Police(float taille, FontStyle style)
        {
            Init();
            bool gras = (style & FontStyle.Bold) != 0;
            if (gras && Dispo("Geist SemiBold")) return Creer("Geist SemiBold", repliTexte, taille);
            if (!gras && Dispo("Geist")) return Creer("Geist", repliTexte, taille);
            return new Font(repliTexte, taille, style, GraphicsUnit.Point);
        }
        /// <summary>Geist Mono : heures, empreintes, libelles en capitales.</summary>
        public static Font Mono(float taille) { Init(); return Creer("Geist Mono", repliMono, taille); }
        public static Font MonoMoyen(float taille) { Init(); return Creer(Dispo("Geist Mono Medium") ? "Geist Mono Medium" : "Geist Mono", repliMono, taille); }
        public static bool IconesDispo { get { Init(); return familleIcones != null; } }
        public static Font Icones(float taille) { Init(); return familleIcones != null ? new Font(familleIcones, taille, FontStyle.Regular, GraphicsUnit.Point) : Police(taille); }

        // ------------------------------------------------------------------ formes
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

        // ------------------------------------------------------------------ Windows en mode sombre (barre de titre, barres de defilement, listes)
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
        static extern int SetWindowTheme(IntPtr hWnd, string appName, string idList);
        [DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribut, ref int valeur, int taille);
        static bool SurWindows { get { return Environment.OSVersion.Platform == PlatformID.Win32NT; } }

        /// <summary>Barres de defilement et listes deroulantes sombres (Windows 10 1809 et plus ; sans effet ailleurs).</summary>
        public static void Sombre(System.Windows.Forms.Control c, string theme = "DarkMode_Explorer")
        {
            if (!SurWindows) return;
            c.HandleCreated += delegate { try { SetWindowTheme(c.Handle, theme, null); } catch { } };
            if (c.IsHandleCreated) try { SetWindowTheme(c.Handle, theme, null); } catch { }
        }

        /// <summary>Barre de titre sombre (Windows 10 2004 et plus, Windows 11).</summary>
        public static void BarreTitreSombre(System.Windows.Forms.Form f)
        {
            if (!SurWindows) return;
            f.HandleCreated += delegate { try { int v = 1; if (DwmSetWindowAttribute(f.Handle, 20, ref v, 4) != 0) DwmSetWindowAttribute(f.Handle, 19, ref v, 4); } catch { } };
        }

        public static void Qualite(Graphics g)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        }

        // ------------------------------------------------------------------ logo « digspill » au point rouge (vectoriel, comme le SVG)
        const string LogoMot =
            "M260 12Q192 12 142.5 -22Q93 -56 66 -118.5Q39 -181 39 -267Q39 -352 66.5 -415Q94 -478 143.5 -512Q193 -546 260 -546Q316 -546 358.5 -523Q401 -500 423 -458V-710H551V0H429L426 -79Q404 -3" +
            "6 360 -12Q316 12 260 12ZM299 -92Q358 -92 390.5 -137.5Q423 -183 423 -267Q423 -352 391 -397Q359 -442 299 -442Q241 -442 206.5 -395.5Q172 -349 172 -267Q172 -187 206.5 -139.5Q241 -92 29" +
            "9 -92ZM656 0V-534H784V0ZM654 -605V-719H787V-605ZM1118 162Q1013 162 953 120Q893 78 875 10L1007 1Q1017 32 1041.5 48.5Q1066 65 1118 65Q1177 65 1209 38.5Q1241 12 1241 -44V-112Q1222 -73" +
            " 1180 -49.5Q1138 -26 1086 -26Q1020 -26 968.5 -58.5Q917 -91 888 -149.5Q859 -208 859 -285Q859 -362 888 -420.5Q917 -479 967.5 -512.5Q1018 -546 1084 -546Q1141 -546 1183 -520Q1225 -494 " +
            "1245 -451V-534H1370V-47Q1370 56 1301 109Q1232 162 1118 162ZM1116 -126Q1173 -126 1207.5 -168.5Q1242 -211 1242 -286Q1243 -360 1208.5 -403Q1174 -446 1116 -446Q1057 -446 1024.5 -402.5Q" +
            "992 -359 992 -286Q992 -213 1025.5 -169.5Q1059 -126 1116 -126ZM1692 12Q1570 12 1510 -39Q1450 -90 1444 -168L1575 -174Q1582 -132 1608.5 -109Q1635 -86 1693 -86Q1738 -86 1761.5 -100.5Q1" +
            "785 -115 1785 -146Q1785 -164 1776.5 -176Q1768 -188 1743.5 -197Q1719 -206 1672 -215Q1591 -229 1545 -249.5Q1499 -270 1480.5 -301Q1462 -332 1462 -378Q1462 -452 1519.5 -499Q1577 -546 1" +
            "688 -546Q1765 -546 1814.5 -521.5Q1864 -497 1889.5 -456.5Q1915 -416 1919 -366L1789 -360Q1787 -398 1763 -423Q1739 -448 1686 -448Q1641 -448 1617.5 -430Q1594 -412 1594 -382Q1594 -350 1" +
            "616.5 -334.5Q1639 -319 1699 -309Q1781 -297 1829 -276Q1877 -255 1897.5 -223.5Q1918 -192 1918 -148Q1918 -71 1856.5 -29.5Q1795 12 1692 12ZM1993 150V-534H2116L2118 -454Q2141 -499 2183 " +
            "-522.5Q2225 -546 2278 -546Q2354 -546 2404.5 -508.5Q2455 -471 2480 -407.5Q2505 -344 2505 -267Q2505 -190 2479.5 -127Q2454 -64 2403.5 -26Q2353 12 2277 12Q2226 12 2184.5 -10.5Q2143 -33" +
            " 2121 -73V150ZM2247 -92Q2305 -92 2338.5 -138.5Q2372 -185 2372 -267Q2372 -349 2338.5 -395.5Q2305 -442 2247 -442Q2189 -442 2155 -398Q2121 -354 2121 -267Q2121 -180 2154.5 -136Q2188 -9" +
            "2 2247 -92ZM2579 0V-534H2707V0ZM2941 0Q2882 0 2847.5 -30Q2813 -60 2813 -126V-710H2941V-139Q2941 -99 2981 -99H3020V0ZM3203 0Q3144 0 3109.5 -30Q3075 -60 3075 -126V-710H3203V-139Q3203" +
            " -99 3243 -99H3282V0Z";
        const string LogoPoint = "M2596.5 184V70H2729.5V184Z";
        static readonly RectangleF LogoVue = new RectangleF(39, -719, 3243, 903);

        /// <summary>Lit un trace SVG en coordonnees absolues (M, L, H, V, Q, Z), comme ceux du logo.</summary>
        static GraphicsPath Trace(string d)
        {
            var p = new GraphicsPath(FillMode.Winding);
            var jetons = Regex.Matches(d, @"[MLHVQZ]|-?\d*\.?\d+").Cast<Match>().Select(m => m.Value).ToList();
            int i = 0; char cmd = 'M';
            PointF cour = PointF.Empty, depart = PointF.Empty;
            Func<float> nb = () => float.Parse(jetons[i++], CultureInfo.InvariantCulture);
            while (i < jetons.Count)
            {
                if (char.IsLetter(jetons[i][0])) cmd = jetons[i++][0];
                switch (cmd)
                {
                    case 'M': cour = depart = new PointF(nb(), nb()); p.StartFigure(); cmd = 'L'; break;
                    case 'L': { var q = new PointF(nb(), nb()); p.AddLine(cour, q); cour = q; break; }
                    case 'H': { var q = new PointF(nb(), cour.Y); p.AddLine(cour, q); cour = q; break; }
                    case 'V': { var q = new PointF(cour.X, nb()); p.AddLine(cour, q); cour = q; break; }
                    case 'Q':
                        {
                            var c = new PointF(nb(), nb()); var q = new PointF(nb(), nb());
                            p.AddBezier(cour, new PointF(cour.X + 2f / 3 * (c.X - cour.X), cour.Y + 2f / 3 * (c.Y - cour.Y)),
                                              new PointF(q.X + 2f / 3 * (c.X - q.X), q.Y + 2f / 3 * (c.Y - q.Y)), q);
                            cour = q; break;
                        }
                    case 'Z': p.CloseFigure(); cour = depart; break;
                    default: i++; break;
                }
            }
            return p;
        }

        static GraphicsPath mot, point;

        /// <summary>Dessine le logo dans la hauteur donnee (largeur = hauteur x 3,6), le mot en <paramref name="couleurMot"/>.</summary>
        public static SizeF DessinerLogo(Graphics g, PointF origine, float hauteur, Color couleurMot)
        {
            if (mot == null) { mot = Trace(LogoMot); point = Trace(LogoPoint); }
            float k = hauteur / LogoVue.Height;
            var etat = g.Save();
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TranslateTransform(origine.X - LogoVue.X * k, origine.Y - LogoVue.Y * k);
            g.ScaleTransform(k, k);
            using (var b = new SolidBrush(couleurMot)) g.FillPath(b, mot);
            using (var b = new SolidBrush(Rouge)) g.FillPath(b, point);
            g.Restore(etat);
            return new SizeF(LogoVue.Width * k, hauteur);
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
