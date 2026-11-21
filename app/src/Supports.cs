// DigSpill - supports de stockage : liste, protection en ecriture, verrouillage d'urgence, ejection.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Management;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace DigSpill
{
    class Support
    {
        public string Lettre;          // "E:"
        public string Etiquette = "";
        public string Systeme = "";    // NTFS, exFAT, FAT32
        public long Libre, Total;
        public bool Amovible, Usb, LectureSeule, EstOutils, EstSysteme;
        public string Racine { get { return Lettre + "\\"; } }
        public string Nom { get { return string.IsNullOrEmpty(Etiquette) ? Lettre : Lettre + "  " + Etiquette; } }
        public string Description
        {
            get
            {
                var t = new List<string>();
                t.Add(Usb ? "USB" : (Amovible ? "Amovible" : "Disque"));
                if (!string.IsNullOrEmpty(Systeme)) t.Add(Systeme);
                if (Total > 0) t.Add(string.Format("{0} libres sur {1}", Taille(Libre), Taille(Total)));
                return string.Join(" · ", t.ToArray());
            }
        }
        public static string Taille(long o)
        {
            if (o >= 1L << 40) return string.Format("{0:0.0} To", o / (double)(1L << 40));
            if (o >= 1L << 30) return string.Format("{0:0.0} Go", o / (double)(1L << 30));
            return string.Format("{0:0} Mo", o / (double)(1L << 20));
        }
    }

    static class Supports
    {
        // ------------------------------------------------------------------ API Windows
        const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000, FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, OPEN_EXISTING = 3;
        const uint FSCTL_LOCK_VOLUME = 0x00090018, FSCTL_DISMOUNT_VOLUME = 0x00090020;
        const uint IOCTL_STORAGE_EJECT_MEDIA = 0x002D4808, IOCTL_STORAGE_MEDIA_REMOVAL = 0x002D4804, IOCTL_STORAGE_GET_DEVICE_NUMBER = 0x002D1080;
        const uint IOCTL_DISK_SET_DISK_ATTRIBUTES = 0x0007C0F4;
        const uint FILE_READ_ONLY_VOLUME = 0x00080000;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern SafeFileHandle CreateFile(string nom, uint acces, uint partage, IntPtr securite, uint disposition, uint attributs, IntPtr modele);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] entree, int tailleEntree, byte[] sortie, int tailleSortie, out int retour, IntPtr ov);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool FlushFileBuffers(SafeFileHandle h);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool DeleteVolumeMountPoint(string pointMontage);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool GetVolumeInformation(string racine, StringBuilder nom, int tailleNom, out uint serie, out uint longueurMax, out uint drapeaux, StringBuilder fs, int tailleFs);

        public static bool EstAdmin()
        {
            try { return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator); }
            catch { return false; }
        }

        public static bool LectureSeule(string racine)
        {
            try
            {
                uint serie, lmax, drapeaux;
                var n = new StringBuilder(261); var fs = new StringBuilder(261);
                if (GetVolumeInformation(racine, n, n.Capacity, out serie, out lmax, out drapeaux, fs, fs.Capacity))
                    return (drapeaux & FILE_READ_ONLY_VOLUME) != 0;
            }
            catch { }
            return false;
        }

        static HashSet<string> LettresUsb()
        {
            var l = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                using (var disques = new ManagementObjectSearcher("SELECT DeviceID FROM Win32_DiskDrive WHERE InterfaceType='USB'"))
                    foreach (ManagementObject d in disques.Get())
                        foreach (ManagementObject p in d.GetRelated("Win32_DiskPartition"))
                            foreach (ManagementObject v in p.GetRelated("Win32_LogicalDisk"))
                                l.Add(Convert.ToString(v["DeviceID"]));
            }
            catch { }
            return l;
        }

        /// <summary>Lecteurs acceptes comme destination meme s'ils ne sont pas USB (test de bout en bout : disques virtuels).</summary>
        public static readonly HashSet<string> Ajoutees = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        public static List<Support> Lister(string racineOutils)
        {
            var res = new List<Support>();
            var usb = LettresUsb();
            string systeme = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)).TrimEnd('\\');
            string outils = string.IsNullOrEmpty(racineOutils) ? "" : Path.GetPathRoot(racineOutils).TrimEnd('\\');
            foreach (var d in DriveInfo.GetDrives())
            {
                try
                {
                    if (!d.IsReady) continue;
                    if (d.DriveType != DriveType.Removable && d.DriveType != DriveType.Fixed) continue;
                    var s = new Support();
                    s.Lettre = d.Name.TrimEnd('\\');
                    s.Etiquette = d.VolumeLabel;
                    s.Systeme = d.DriveFormat;
                    s.Libre = d.AvailableFreeSpace;
                    s.Total = d.TotalSize;
                    s.Amovible = d.DriveType == DriveType.Removable;
                    s.Usb = usb.Contains(s.Lettre) || s.Amovible;
                    s.EstSysteme = string.Equals(s.Lettre, systeme, StringComparison.OrdinalIgnoreCase);
                    s.EstOutils = string.Equals(s.Lettre, outils, StringComparison.OrdinalIgnoreCase);
                    s.LectureSeule = LectureSeule(d.Name);
                    if (s.EstSysteme) continue;
                    if (Ajoutees.Contains(s.Lettre)) s.Usb = true;
                    if (!s.Usb && !s.EstOutils) continue; // seuls les supports externes servent de destination
                    res.Add(s);
                }
                catch { }
            }
            return res.OrderBy(x => x.EstOutils).ThenBy(x => x.Lettre).ToList();
        }

        public static bool EssaiEcriture(string dossier, out string erreur)
        {
            erreur = null;
            try
            {
                Directory.CreateDirectory(dossier);
                var f = Path.Combine(dossier, ".digspill_essai_" + Guid.NewGuid().ToString("N").Substring(0, 8));
                File.WriteAllText(f, "essai");
                File.Delete(f);
                return true;
            }
            catch (Exception e) { erreur = e.Message; return false; }
        }

        static SafeFileHandle Ouvrir(string chemin)
        {
            var h = CreateFile(chemin, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
            if (h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            return h;
        }

        static bool Ioctl(SafeFileHandle h, uint code, byte[] entree, byte[] sortie)
        {
            int r;
            return DeviceIoControl(h, code, entree, entree == null ? 0 : entree.Length, sortie, sortie == null ? 0 : sortie.Length, out r, IntPtr.Zero);
        }

        static int NumeroDisque(string lettre)
        {
            using (var h = Ouvrir(@"\\.\" + lettre))
            {
                var sortie = new byte[12];
                if (!Ioctl(h, IOCTL_STORAGE_GET_DEVICE_NUMBER, null, sortie)) return -1;
                return BitConverter.ToInt32(sortie, 4);
            }
        }

        /// <summary>Bloque toute ecriture sur le disque physique (attribut lecture seule, non persistant).</summary>
        static bool DisqueLectureSeule(int numero)
        {
            using (var h = Ouvrir(@"\\.\PhysicalDrive" + numero))
            {
                // SET_DISK_ATTRIBUTES : Version(4) Persist(1) Reserved(3) Attributes(8) Mask(8) Reserved(16) = 40 octets
                var s = new byte[40];
                BitConverter.GetBytes(40).CopyTo(s, 0);
                s[4] = 0;                                   // non persistant : la cle redevient normale au prochain branchement
                BitConverter.GetBytes(2UL).CopyTo(s, 8);   // DISK_ATTRIBUTE_READ_ONLY
                BitConverter.GetBytes(2UL).CopyTo(s, 16);
                return Ioctl(h, IOCTL_DISK_SET_DISK_ATTRIBUTES, s, null);
            }
        }

        /// <summary>Arret d'urgence : plus aucune ecriture, volume demonte, lettre retiree.</summary>
        public static List<string> VerrouillageUrgence(string lettre)
        {
            var fait = new List<string>();
            try
            {
                int n = NumeroDisque(lettre);
                if (n >= 0 && DisqueLectureSeule(n)) fait.Add("Écriture bloquée sur le disque (lecture seule)");
                else fait.Add("Lecture seule du disque : refusée par Windows");
            }
            catch (Exception e) { fait.Add("Lecture seule du disque impossible : " + e.Message); }
            try
            {
                using (var h = Ouvrir(@"\\.\" + lettre))
                {
                    bool verrou = Ioctl(h, FSCTL_LOCK_VOLUME, null, null);
                    bool demonte = Ioctl(h, FSCTL_DISMOUNT_VOLUME, null, null);
                    fait.Add(demonte ? (verrou ? "Volume verrouillé et démonté" : "Volume démonté de force (un autre programme l'utilisait)") : "Démontage refusé par Windows");
                    var pmr = new byte[1];
                    Ioctl(h, IOCTL_STORAGE_MEDIA_REMOVAL, pmr, null);
                    if (Ioctl(h, IOCTL_STORAGE_EJECT_MEDIA, null, null)) fait.Add("Média éjecté");
                }
            }
            catch (Exception e) { fait.Add("Démontage impossible : " + e.Message); }
            try { if (DeleteVolumeMountPoint(lettre + "\\")) fait.Add("Lettre " + lettre + " retirée : le support n'est plus visible des programmes"); }
            catch { }
            return fait;
        }

        /// <summary>Mode une seule cle : DigSpill tourne depuis la cle et ne peut pas l'ejecter lui-meme.
        /// Un PowerShell lance depuis System32 attend la fermeture de DigSpill puis demande l'ejection a Windows.</summary>
        public static void EjecterApresFermeture(string lettre)
        {
            var sys = Environment.GetFolderPath(Environment.SpecialFolder.System);
            var cmd = "Wait-Process -Id " + System.Diagnostics.Process.GetCurrentProcess().Id + " -Timeout 60 -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; " +
                      "(New-Object -ComObject Shell.Application).Namespace(17).ParseName('" + lettre.TrimEnd('\\') + "\\').InvokeVerb('Eject')";
            var psi = new System.Diagnostics.ProcessStartInfo(Path.Combine(sys, @"WindowsPowerShell\v1.0\powershell.exe"), "-NoProfile -WindowStyle Hidden -Command \"" + cmd + "\"")
            { WorkingDirectory = sys, UseShellExecute = false, CreateNoWindow = true };
            System.Diagnostics.Process.Start(psi);
        }

        /// <summary>Fin normale : vide les caches, demonte et ejecte. Renvoie null si tout va bien, sinon le probleme.</summary>
        public static string Ejecter(string lettre, bool forcer)
        {
            try
            {
                using (var h = Ouvrir(@"\\.\" + lettre))
                {
                    FlushFileBuffers(h);
                    bool verrou = Ioctl(h, FSCTL_LOCK_VOLUME, null, null);
                    if (!verrou && !forcer) return "La clé est encore utilisée par un autre programme (fenêtre de l'explorateur, antivirus…). Fermez-le puis réessayez, ou forcez.";
                    if (!Ioctl(h, FSCTL_DISMOUNT_VOLUME, null, null)) return "Windows refuse de démonter la clé (code " + Marshal.GetLastWin32Error() + ").";
                    var pmr = new byte[1];
                    Ioctl(h, IOCTL_STORAGE_MEDIA_REMOVAL, pmr, null);
                    Ioctl(h, IOCTL_STORAGE_EJECT_MEDIA, null, null);
                }
                return null;
            }
            catch (Exception e) { return e.Message; }
        }
    }
}
