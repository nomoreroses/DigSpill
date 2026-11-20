/* ============================================================================
   DigSpill - interface de triage forensique, fichier autonome (aucun serveur, aucun CDN)
   01_base.js : lecture des donnees embarquees, CSV, dates, IP, preuves, reglages
   ============================================================================ */
'use strict';

const T = {};                       // espace de noms global de l'interface
T.VERSION = '1.1-beta';

/* ---------------------------------------------------------------- DOM */
T.$ = (s, r = document) => r.querySelector(s);
T.$$ = (s, r = document) => Array.from(r.querySelectorAll(s));
T.esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
T.h = (tag, attrs = {}, ...enfants) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === null || v === undefined || v === false) continue;
    if (k === 'class') e.className = v;
    else if (k === 'html') e.innerHTML = v;
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const c of enfants.flat(9)) if (c !== null && c !== undefined && c !== false) e.append(c.nodeType ? c : document.createTextNode(String(c)));
  return e;
};
T.nb = (x, dec = 0) => (x === null || x === undefined || isNaN(x)) ? '–' : Number(x).toLocaleString('fr-FR', { maximumFractionDigits: dec, minimumFractionDigits: dec });

/* ---------------------------------------------------------------- CSV (RFC 4180, ecrit par Export-Csv) */
T.parseCsv = texte => {
  if (!texte) return [];
  if (texte.charCodeAt(0) === 0xFEFF) texte = texte.slice(1);
  const premiere = texte.slice(0, texte.indexOf('\n') >>> 0 || texte.length);
  if (!premiere.trim() || (premiere[0] !== '"' && premiere.indexOf(',') < 0)) return [];   // 'Aucune ligne'
  const lignes = []; let champ = '', ligne = [], i = 0, guil = false; const n = texte.length;
  while (i < n) {
    const c = texte[i];
    if (guil) {
      if (c === '"') { if (texte[i + 1] === '"') { champ += '"'; i += 2; continue; } guil = false; i++; continue; }
      champ += c; i++; continue;
    }
    if (c === '"') { guil = true; i++; continue; }
    if (c === ',') { ligne.push(champ); champ = ''; i++; continue; }
    if (c === '\r') { i++; continue; }
    if (c === '\n') { ligne.push(champ); lignes.push(ligne); ligne = []; champ = ''; i++; continue; }
    champ += c; i++;
  }
  if (champ !== '' || ligne.length) { ligne.push(champ); lignes.push(ligne); }
  const tete = (lignes.shift() || []).map(x => x.trim());
  return lignes.filter(l => l.length > 1 || (l[0] || '').trim()).map(l => {
    const o = {}; tete.forEach((k, j) => { o[k] = (l[j] ?? '').trim(); }); return o;
  });
};

/* ---------------------------------------------------------------- dates (heure locale du poste collecte, sans fuseau) */
const RX_ISO = /^(\d{4})-(\d\d)-(\d\d)(?:[ T](\d\d):(\d\d)(?::(\d\d))?)?/;
const RX_FR = /^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{1,2}):(\d\d)(?::(\d\d))?)?/;
T.pdate = s => {
  if (!s) return null;
  if (s instanceof Date) return s;
  s = String(s).trim();
  if (!s || s.startsWith('1601-01-01') || s.startsWith('0001-01-01')) return null;
  let m = RX_ISO.exec(s);
  if (m) return new Date(+m[1], +m[2] - 1, +m[3], +(m[4] || 0), +(m[5] || 0), +(m[6] || 0));
  m = RX_FR.exec(s);
  if (m) return new Date(+m[3], +m[2] - 1, +m[1], +(m[4] || 0), +(m[5] || 0), +(m[6] || 0));
  return null;
};
const p2 = x => String(x).padStart(2, '0');
T.fdate = d => d ? `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())} ${p2(d.getHours())}:${p2(d.getMinutes())}:${p2(d.getSeconds())}` : '';
T.fcourt = d => { d = T.pdate(d); return d ? `${p2(d.getDate())}/${p2(d.getMonth() + 1)} ${p2(d.getHours())}:${p2(d.getMinutes())}` : ''; };
T.flong = d => { d = T.pdate(d); return d ? d.toLocaleString('fr-FR', { weekday: 'short', day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : ''; };
T.num = (s, def = 0) => { if (s === null || s === undefined || s === '') return def; const v = parseFloat(String(s).replace(/[\s ]/g, '').replace(',', '.')); return isNaN(v) ? def : v; };
T.HEURE = 3600e3;

/* ---------------------------------------------------------------- IP */
T.nettoyerIp = ip => {
  ip = String(ip ?? '').trim();
  let m = /^\[?([0-9a-fA-F:]+)\]?:\d+$/.exec(ip); if (m && !ip.includes('.')) return m[1];
  m = /^(\d+\.\d+\.\d+\.\d+):\d+$/.exec(ip); if (m) return m[1];
  if (/^::ffff:\d+\.\d+\.\d+\.\d+$/i.test(ip)) return ip.slice(7);
  return ip;
};
T.ip4 = ip => { const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(ip); if (!m) return null; const b = m.slice(1).map(Number); if (b.some(x => x > 255)) return null; return ((b[0] << 24) >>> 0) + (b[1] << 16) + (b[2] << 8) + b[3]; };
/** Meme classement que Get-IpType des scripts PowerShell */
T.typeIp = ip => {
  ip = T.nettoyerIp(ip);
  if (!ip || ip === '-') return '-';
  const v = T.ip4(ip);
  if (v !== null) {
    const a = v >>> 24, b = (v >>> 16) & 255;
    if (a === 127) return 'Locale';
    if (a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 169 && b === 254)) return 'Privee';
    if (a === 100 && b >= 64 && b <= 127) return 'VPN/CGNAT';
    return 'PUBLIQUE';
  }
  if (!/^[0-9a-f:]+$/i.test(ip) || !ip.includes(':')) return '?';
  const l = ip.toLowerCase();
  if (l === '::1') return 'Locale';
  if (l.startsWith('fe8') || l.startsWith('fe9') || l.startsWith('fea') || l.startsWith('feb') || l.startsWith('fc') || l.startsWith('fd') || l.startsWith('fec')) return 'Privee';
  return 'PUBLIQUE';
};
T.dansCidr = (ip, cidr) => {
  const [net, len] = String(cidr).split('/'); const a = T.ip4(T.nettoyerIp(ip)), b = T.ip4(net);
  if (a === null || b === null) return T.nettoyerIp(ip) === net;
  const n = len === undefined ? 32 : +len; if (n === 0) return true;
  const masque = n >= 32 ? 0xFFFFFFFF : (~((1 << (32 - n)) - 1)) >>> 0;
  return ((a & masque) >>> 0) === ((b & masque) >>> 0);
};
T.drapeau = cc => (cc && /^[A-Z]{2}$/.test(cc)) ? String.fromCodePoint(...[...cc].map(c => 0x1F1E6 + c.charCodeAt(0) - 65)) : '';

/* ---------------------------------------------------------------- donnees embarquees */
T.D = null;          // charge utile generee par Generer-Interface.ps1
T._tables = {};
const lireJson = (txt, def) => { if (!txt) return def; try { return JSON.parse(txt); } catch (e) { console.warn('JSON embarque illisible', e); return def; } };
T.charger = obj => {
  T.D = obj; T._tables = {}; T._cache = {};
  // champs bruts embarques par le .bat : parses ici (un fichier abime ne bloque pas le reste)
  if (!T.D.reglages) T.D.reglages = lireJson(T.D.reglages_brut, {});
  if (!T.D.memoire) T.D.memoire = lireJson(T.D.memoire_brut, {});
  const listeVict = x => { const d = lireJson(x, []); return Array.isArray(d) ? d : (d && (d.victims || d.data)) || []; };
  if (!T.D.ransomware) T.D.ransomware = [...listeVict(T.D.ransomware_brut), ...listeVict(T.D.ransomware_recent_brut)];
  T.D.fichiers = T.D.fichiers || {}; T.D.collecte = T.D.collecte || { nom: '' };
  T.MONDE = JSON.parse(document.getElementById('monde').textContent);
};
T.table = nom => {
  if (T._tables[nom]) return T._tables[nom];
  const f = T.D.fichiers[nom];
  const lignes = f && f.texte && nom.indexOf('.txt') < 0 ? T.parseCsv(f.texte) : [];
  lignes.forEach((r, i) => { r._id = `${nom}#${i + 1}`; });
  return (T._tables[nom] = lignes);
};
T.texte = nom => (T.D.fichiers[nom] || T.D.fichiers['a.' + nom] || {}).texte || '';
T.preuve = id => {
  const [nom, n] = String(id).split('#'); if (!n || !/^\d+$/.test(n)) return null;
  const t = T.table(nom); return t[+n - 1] || null;
};
T.infoFichier = nom => {
  const f = T.D.fichiers[nom]; if (!f) return null;
  const rel = (f.chemin || '').toLowerCase();
  let sha = '';
  for (const m of ['manifeste_sha256', 'manifeste_analyse_sha256']) {
    const racine = m === 'manifeste_sha256' ? T.D.collecte.nom : (T.D.collecte.nom + '_analyse');
    for (const r of T.table(m)) if ((racine + '\\' + (r.Fichier || '')).toLowerCase() === rel) { sha = r.SHA256; break; }
    if (sha) break;
  }
  return { chemin: f.chemin, taille: f.taille, tronque: !!f.tronque, sha256: sha };
};
/** memoisation par cle (les analyses sont recalculees quand les reglages changent) */
T._cache = {};
T.memo = (cle, fn) => (cle in T._cache) ? T._cache[cle] : (T._cache[cle] = fn());
T.invalider = () => { T._cache = {}; };

/* ---------------------------------------------------------------- identite de la collecte */
T.identite = () => T.memo('identite', () => {
  const nom = T.D.collecte.nom || '';
  const m = /^(.+?)_(\d{4})(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)(_leger)?$/.exec(nom);
  return { nom, poste: m ? m[1] : nom, date: m ? `${m[2]}-${m[3]}-${m[4]} ${m[5]}:${m[6]}:${m[7]}` : '', leger: !!(m && m[8]) };
});

/* ---------------------------------------------------------------- reglages (saisis dans l'interface) */
T.REGLAGES_DEFAUT = {
  client: '', technicien: '', decouverte: '', debit_montant_mbps: '', taille_base_mo: '', compression: 4,
  horaires: { 0: '08:00-19:00', 1: '08:00-19:00', 2: '08:00-19:00', 3: '08:00-19:00', 4: '08:00-19:00', 5: '08:00-12:00', 6: '' },
  mots_cles_fuite: [], liste_blanche: [], fenetres_manuelles: [], notes: ''
};
T.cleStockage = () => 'digspill:' + (T.D.collecte.nom || 'sans-nom');
T.stockage = {
  lire(k) { try { return JSON.parse(localStorage.getItem(k) || 'null'); } catch (e) { return null; } },
  ecrire(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); return true; } catch (e) { return false; } }
};
T.reglages = () => T.memo('reglages', () => {
  const base = JSON.parse(JSON.stringify(T.REGLAGES_DEFAUT));
  const emb = T.D.reglages || {};
  const loc = T.stockage.lire(T.cleStockage()) || {};
  const r = Object.assign(base, emb, loc);
  if (!r.decouverte) r.decouverte = T.decouverteFiche();
  return r;
});
T.majReglages = maj => {
  const loc = T.stockage.lire(T.cleStockage()) || {};
  Object.assign(loc, maj);
  T.stockage.ecrire(T.cleStockage(), loc);
  T.invalider();
};
T.decouverteFiche = () => {
  const t = T.texte('A_COMPLETER_TECHNICIEN.txt');
  const m = /decouverte\s*:\s*(\d{1,2})\s*\/\s*(\d{1,2})\s*\/\s*(\d{4})\s*a\s*(\d{1,2})\s*[:h]\s*(\d{2})/i.exec(t);
  return m ? `${m[3]}-${p2(m[2])}-${p2(m[1])} ${p2(m[4])}:${m[5]}` : '';
};

/* ---------------------------------------------------------------- fenetres d'analyse */
T.fenetres = () => T.memo('fenetres', () => {
  const out = [];
  for (const r of T.table('fenetres_analyse')) {
    const d = T.pdate(r.Debut), f = T.pdate(r.Fin);
    if (d && f) out.push({ id: r.Id || `F${out.length + 1}`, debut: d, fin: f, motif: r.Motif || '', duree: Math.round((f - d) / 60e3), preuve: r._id });
  }
  (T.reglages().fenetres_manuelles || []).forEach((m, i) => {
    const d = T.pdate(m.debut), f = T.pdate(m.fin);
    if (d && f && f > d) out.push({ id: `M${i + 1}`, debut: d, fin: f, motif: m.motif || 'fenetre manuelle', duree: Math.round((f - d) / 60e3), preuve: '' });
  });
  return out.sort((a, b) => a.debut - b.debut);
});
T.fenDe = d => { d = T.pdate(d); if (!d) return ''; return T.fenetres().filter(w => d >= w.debut && d <= w.fin).map(w => w.id).join(','); };

/* ---------------------------------------------------------------- telechargement d'un fichier genere */
T.telecharger = (nom, contenu, type = 'text/plain;charset=utf-8') => {
  const b = contenu instanceof Blob ? contenu : new Blob([contenu], { type });
  const a = T.h('a', { href: URL.createObjectURL(b), download: nom });
  document.body.append(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 2000);
};
T.copier = async texte => { try { await navigator.clipboard.writeText(texte); return true; } catch (e) { return false; } };
