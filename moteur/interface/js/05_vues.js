/* ============================================================================
   05_vues.js : ecrans de l'interface
   ============================================================================ */
'use strict';
const h = T.h, esc = T.esc;

T.ONGLETS = [{ id: 'resume', nom: 'Résumé' }, { id: 'chrono', nom: 'Chronologie' }, { id: 'details', nom: 'Détails' }, { id: 'preuves', nom: 'Preuves' }];
T.onglet = 'resume';

/* ---------------------------------------------------------------- petits composants */
T.toast = (m, ms = 2600) => { const t = h('div', { class: 'toast' }, m); document.body.append(t); setTimeout(() => t.remove(), ms); };
T.bp = id => id ? h('button', { class: 'preuve', 'data-preuve': id, title: 'Voir la ligne source' }, id) : '';
T.bps = (ids, max = 3) => { ids = (ids || []).filter(Boolean); return h('span', {}, ids.slice(0, max).map(i => [T.bp(i), ' ']), ids.length > max ? h('span', { class: 'pale petit' }, `+${ids.length - max}`) : ''); };
T.pillStatut = s => h('span', { class: 'pill st-' + String(s || '').replace(/\s+/g, '_') }, s || '?');
T.pillNiveau = n => { const x = T.NIVEAUX[n] || T.NIVEAUX.INCONNU; return h('span', { class: 'pill st-' + n }, x.lib); };
T.carte = (titre, aide, ...contenu) => h('div', { class: 'carte' }, titre ? h('h2', {}, titre, aide ? h('span', { class: 'aide' }, aide) : '') : '', ...contenu);
T.vide = txt => h('div', { class: 'vide' }, txt || 'Rien à afficher.');
T.tableau = (cols, lignes, opts = {}) => {
  if (!lignes.length) return T.vide(opts.vide);
  const t = h('table', { class: 'tableau' }, h('thead', {}, h('tr', {}, cols.map(c => h('th', { style: c.l ? `width:${c.l}` : null }, c.t)))),
    h('tbody', {}, lignes.slice(0, opts.max || 1000).map(r => h('tr', { class: opts.cls ? opts.cls(r) : null }, cols.map(c => { const v = c.v(r); return h('td', { class: c.c || null }, v === undefined || v === null ? '' : v); })))));
  const enveloppe = h('div', { class: opts.defile === false ? '' : 'defile', style: opts.hauteur ? `max-height:${opts.hauteur}` : null }, t);
  return lignes.length > (opts.max || 1000) ? h('div', {}, enveloppe, h('div', { class: 'pale petit' }, `${T.nb(lignes.length - (opts.max || 1000))} ligne(s) non affichée(s)`)) : enveloppe;
};
T.kpi = (ic, valeur, libelle, cls = '', titre = '') => h('div', { class: 'kpi ' + cls, title: titre || null }, h('div', {}, h('b', {}, valeur), h('span', {}, libelle)));
T.nomPays = cc => (T.MONDE.noms && T.MONDE.noms[cc]) || cc || '';

/* ---------------------------------------------------------------- icones SVG (trait 1.8, 16 px) et logo */
const ICONES = {
  loupe: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
  reglages: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
  chevron: '<path d="m6 9 6 6 6-6"/>',
  fermer: '<path d="M18 6 6 18M6 6l12 12"/>',
  copier: '<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/>',
  prise: '<path d="M9 2v5M15 2v5M6 7h12v4a6 6 0 0 1-12 0zM12 17v5"/>'
};
T.ic = (nom, cls = '') => { const t = document.createElement('template'); t.innerHTML = `<svg class="ic-svg ${cls}" viewBox="0 0 24 24" aria-hidden="true" focusable="false">${ICONES[nom] || ''}</svg>`; return t.content.firstChild; };
T.LOGO_MOT = 'M260 12Q192 12 142.5 -22Q93 -56 66 -118.5Q39 -181 39 -267Q39 -352 66.5 -415Q94 -478 143.5 -512Q193 -546 260 -546Q316 -546 358.5 -523Q401 -500 423 -458V-710H551V0H429L426 -79Q404 -36 360 -12Q316 12 260 12ZM299 -92Q358 -92 390.5 -137.5Q423 -183 423 -267Q423 -352 391 -397Q359 -442 299 -442Q241 -442 206.5 -395.5Q172 -349 172 -267Q172 -187 206.5 -139.5Q241 -92 299 -92ZM656 0V-534H784V0ZM654 -605V-719H787V-605ZM1118 162Q1013 162 953 120Q893 78 875 10L1007 1Q1017 32 1041.5 48.5Q1066 65 1118 65Q1177 65 1209 38.5Q1241 12 1241 -44V-112Q1222 -73 1180 -49.5Q1138 -26 1086 -26Q1020 -26 968.5 -58.5Q917 -91 888 -149.5Q859 -208 859 -285Q859 -362 888 -420.5Q917 -479 967.5 -512.5Q1018 -546 1084 -546Q1141 -546 1183 -520Q1225 -494 1245 -451V-534H1370V-47Q1370 56 1301 109Q1232 162 1118 162ZM1116 -126Q1173 -126 1207.5 -168.5Q1242 -211 1242 -286Q1243 -360 1208.5 -403Q1174 -446 1116 -446Q1057 -446 1024.5 -402.5Q992 -359 992 -286Q992 -213 1025.5 -169.5Q1059 -126 1116 -126ZM1692 12Q1570 12 1510 -39Q1450 -90 1444 -168L1575 -174Q1582 -132 1608.5 -109Q1635 -86 1693 -86Q1738 -86 1761.5 -100.5Q1785 -115 1785 -146Q1785 -164 1776.5 -176Q1768 -188 1743.5 -197Q1719 -206 1672 -215Q1591 -229 1545 -249.5Q1499 -270 1480.5 -301Q1462 -332 1462 -378Q1462 -452 1519.5 -499Q1577 -546 1688 -546Q1765 -546 1814.5 -521.5Q1864 -497 1889.5 -456.5Q1915 -416 1919 -366L1789 -360Q1787 -398 1763 -423Q1739 -448 1686 -448Q1641 -448 1617.5 -430Q1594 -412 1594 -382Q1594 -350 1616.5 -334.5Q1639 -319 1699 -309Q1781 -297 1829 -276Q1877 -255 1897.5 -223.5Q1918 -192 1918 -148Q1918 -71 1856.5 -29.5Q1795 12 1692 12ZM1993 150V-534H2116L2118 -454Q2141 -499 2183 -522.5Q2225 -546 2278 -546Q2354 -546 2404.5 -508.5Q2455 -471 2480 -407.5Q2505 -344 2505 -267Q2505 -190 2479.5 -127Q2454 -64 2403.5 -26Q2353 12 2277 12Q2226 12 2184.5 -10.5Q2143 -33 2121 -73V150ZM2247 -92Q2305 -92 2338.5 -138.5Q2372 -185 2372 -267Q2372 -349 2338.5 -395.5Q2305 -442 2247 -442Q2189 -442 2155 -398Q2121 -354 2121 -267Q2121 -180 2154.5 -136Q2188 -92 2247 -92ZM2579 0V-534H2707V0ZM2941 0Q2882 0 2847.5 -30Q2813 -60 2813 -126V-710H2941V-139Q2941 -99 2981 -99H3020V0ZM3203 0Q3144 0 3109.5 -30Q3075 -60 3075 -126V-710H3203V-139Q3203 -99 3243 -99H3282V0Z';
T.LOGO_POINT = 'M2596.5 184V70H2729.5V184Z';
/** logo « digspill » : le mot suit la couleur du texte, le point est rouge */
T.logoSvg = (cls = '', mot = 'currentColor', point = 'var(--accent)') => `<svg class="${cls}" viewBox="39 -719 3243 903" role="img" aria-label="DigSpill"><path class="lw" fill="${mot}" d="${T.LOGO_MOT}"/><path class="ld" fill="${point}" d="${T.LOGO_POINT}"/></svg>`;
T.logo = cls => { const t = document.createElement('template'); t.innerHTML = T.logoSvg(cls); return t.content.firstChild; };

/* ---------------------------------------------------------------- theme (sombre par defaut) */
T.theme = () => { try { return localStorage.getItem('digspill:theme') === 'clair' ? 'clair' : 'sombre'; } catch (e) { return 'sombre'; } };
T.appliquerTheme = t => {
  try { localStorage.setItem('digspill:theme', t); } catch (e) { /* stockage indisponible : theme pour cette session seulement */ }
  document.documentElement.classList.toggle('clair', t === 'clair');
  if (T.majCouleurs) T.majCouleurs();
};

/* ---------------------------------------------------------------- panneau de preuve */
/** ce que dit la ligne, avec les valeurs exactes du CSV */
T.texteLigne = (r, max = 220) => {
  if (!r) return '';
  // valeurs exactes du CSV ; un nombre ou un OUI/NON isole est precede du nom de sa colonne pour rester lisible
  const t = Object.entries(r).filter(([k, v]) => k !== '_id' && v !== '' && v !== null && v !== undefined && !/^(Fenetre|OutilSensible)$/i.test(k))
    .map(([k, v]) => /^(-?[\d.,]+|OUI|NON|True|False)$/i.test(String(v)) ? `${k} ${v}` : String(v)).join(' · ');
  return t.length > max ? t.slice(0, max - 1) + '…' : t;
};
T.sourcePreuve = id => {
  const nom = String(id).split('#')[0], n = +String(id).split('#')[1], inf = T.infoFichier(nom);
  return { fichier: inf && inf.chemin ? inf.chemin.split('\\').pop() : (/\.(txt|log)$/i.test(nom) ? nom : nom + '.csv'), ligne: isNaN(n) ? null : n + 1, sha: (inf && inf.sha256) || '', chemin: inf ? inf.chemin : nom, tronque: inf && inf.tronque };
};
T.lignePreuve = (id, ctx) => {
  const s = T.sourcePreuve(id), r = T.preuve(id);
  return h('button', { class: 'pf', type: 'button', onclick: () => T.ouvrirPreuve(id, ctx) },
    h('div', { class: 'pf-texte', title: T.texteLigne(r, 5000) || null }, T.texteLigne(r) || id),
    h('div', { class: 'pf-src' }, s.fichier, s.ligne ? ` · ligne ${s.ligne}` : '', s.sha ? [' · SHA256 ', h('span', { title: s.sha }, s.sha.slice(0, 6) + '…' + s.sha.slice(-4))] : ' · hors manifeste'));
};
T.ouvrirPreuve = (id, contexte) => {
  const p = T.$('.panneau'), v = T.$('.voile'), c = T.$('.panneau .corps');
  const r = T.preuve(id), s = T.sourcePreuve(id);
  T._focusAvant = document.activeElement;
  c.innerHTML = '';
  if (contexte) c.append(h('div', { class: 'contexte-preuve' }, h('div', { class: 'gras' }, contexte.titre), h('div', { class: 'pale petit mono' }, contexte.t ? T.fcourt(contexte.t) : '', contexte.fen ? ` · fenêtre ${contexte.fen}` : ''), contexte.detail ? h('div', { class: 'doux petit', style: 'margin-top:6px' }, contexte.detail) : ''));
  c.append(h('dl', {}, h('dt', {}, 'Preuve'), h('dd', { class: 'mono' }, id),
    h('dt', {}, 'Fichier'), h('dd', { class: 'mono' }, s.chemin),
    h('dt', {}, 'Ligne du fichier'), h('dd', {}, s.ligne ? `${s.ligne} (en-tête = ligne 1)` : '–'),
    h('dt', {}, 'SHA256 (manifeste)'), h('dd', { class: 'mono', style: 'font-size:11px' }, s.sha || 'non listé dans le manifeste'),
    s.tronque ? [h('dt', {}, 'Attention'), h('dd', {}, 'Fichier tronqué à la génération (trop volumineux) : seules les premières lignes sont présentes.')] : ''));
  if (r) {
    c.append(h('p', { class: 'lbl', style: 'margin:22px 0 10px' }, 'Contenu de la ligne'));
    c.append(h('dl', {}, Object.entries(r).filter(([k]) => k !== '_id').map(([k, val]) => [h('dt', {}, k), h('dd', { class: /chemin|path|url|commandline|sha|hash|detail|message/i.test(k) ? 'mono' : '' }, val || '–')])));
  } else if (id && !String(id).includes('#')) {
    c.append(h('pre', { class: 'apercu' }, T.texte(id).slice(0, 20000) || 'Fichier texte absent.'));
  }
  c.append(h('div', { style: 'margin-top:18px' }, h('button', { class: 'btn', onclick: async () => T.toast(await T.copier(id) ? 'Identifiant copié' : 'Copie impossible') }, T.ic('copier'), "Copier l'identifiant")));
  p.classList.add('ouvert'); v.classList.add('ouvert'); p.setAttribute('aria-hidden', 'false');
  T.$('.panneau .fermer').focus();
};
T.fermerPanneau = () => {
  const p = T.$('.panneau'); if (!p || !p.classList.contains('ouvert')) return;
  p.classList.remove('ouvert'); T.$('.voile').classList.remove('ouvert'); p.setAttribute('aria-hidden', 'true');
  if (T._focusAvant && T._focusAvant.focus) T._focusAvant.focus();
};

/* ---------------------------------------------------------------- squelette : barre du haut + contenu */
T.rendreSquelette = () => {
  const app = T.$('#app'); app.innerHTML = '';
  app.append(h('header', { class: 'top' },
    h('a', { class: 'brand', href: '#resume', 'aria-label': 'DigSpill : retour au résumé' }, T.logo()),
    h('nav', { class: 'tabs', 'aria-label': 'Sections' }, T.ONGLETS.map(o => h('a', { class: 'tab', href: '#' + o.id, 'data-onglet': o.id }, o.nom))),
    h('div', { class: 'tools' },
      h('button', { class: 'find', type: 'button', onclick: () => T.ouvrirPalette(), 'aria-label': 'Rechercher (Ctrl K)' }, T.ic('loupe'), h('span', { class: 'libelle' }, 'Rechercher'), h('span', { class: 'kbd' }, 'Ctrl K')),
      h('button', { class: 'icbtn', type: 'button', title: 'Réglages', 'aria-label': 'Réglages', onclick: () => T.ouvrirReglages() }, T.ic('reglages')))));
  app.append(h('div', { id: 'contenu' }));
  app.append(h('div', { class: 'voile', onclick: T.fermerPanneau }),
    h('aside', { class: 'panneau', 'aria-hidden': 'true', 'aria-label': 'Preuve' }, h('header', {}, h('h3', {}, 'Preuve'), h('button', { class: 'fermer', type: 'button', 'aria-label': 'Fermer', onclick: T.fermerPanneau }, T.ic('fermer'))), h('div', { class: 'corps' })));
  app.append(h('div', { class: 'modale', id: 'modale', onclick: e => { if (e.target.id === 'modale') T.fermerModale(); } }), h('div', { class: 'palette', id: 'palette', onclick: e => { if (e.target.id === 'palette') T.fermerPalette(); } }));
  if (!T._ecoute) {
    T._ecoute = true;
    document.addEventListener('click', e => { const b = e.target.closest('[data-preuve]'); if (b) { e.preventDefault(); T.ouvrirPreuve(b.dataset.preuve); } });
    document.addEventListener('keydown', e => {
      if ((e.ctrlKey || e.metaKey) && !e.altKey && e.key.toLowerCase() === 'k') { e.preventDefault(); T.ouvrirPalette(); return; }
      if (e.key === 'Escape') { if (T.$('#palette.ouvert')) T.fermerPalette(); else if (T.$('#modale.ouvert')) T.fermerModale(); else T.fermerPanneau(); }
    });
    window.addEventListener('hashchange', () => { const r = T.route(location.hash); if (r !== T.routeActuelle) T.aller(r); });
  }
};
T.fermerModale = () => { const m = T.$('#modale'); if (m) m.classList.remove('ouvert'); if (T._focusModale && T._focusModale.focus) T._focusModale.focus(); };
T.ouvrirModale = contenu => { const m = T.$('#modale'); T._focusModale = document.activeElement; m.innerHTML = ''; m.append(contenu); m.classList.add('ouvert'); const f = m.querySelector('input, select, textarea, button.primaire, button'); if (f) f.focus(); };
T.majEntete = () => { /* l'entete ne porte plus de puce CNIL : l'echeance est dans les actions du Resume */ };

/* ---------------------------------------------------------------- navigation : 4 onglets, anciens liens rediriges */
T.ANCIENS = { vue: 'resume', ip: 'details/ip', exfil: 'details/exfil', visibilite: 'details/visibilite', sante: 'details/sante', fuites: 'details/fuites', ioc: 'details/ioc', ia: 'details/ia', integrite: 'preuves/integrite', rapport: 'preuves/rapports' };
T.route = id => {
  id = decodeURIComponent(String(id || '').replace(/^#/, ''));
  const [o, s] = id.split('/');
  if (T.ANCIENS[o]) return T.ANCIENS[o];
  if (!T.ONGLETS.some(x => x.id === o)) return 'resume';
  return s ? `${o}/${s}` : o;
};
T._minuteries = [];
T.aller = id => {
  const r = T.route(id), [o, s] = r.split('/');
  T.onglet = o; T.sous = s || ''; T.routeActuelle = r;
  if (location.hash.slice(1) !== r) { try { history.replaceState(null, '', '#' + r); } catch (e) { location.hash = r; } }
  T.$$('.tab').forEach(b => { if (b.dataset.onglet === o) b.setAttribute('aria-current', 'page'); else b.removeAttribute('aria-current'); });
  Object.values(T._graphs).forEach(g => { try { g.dispose(); } catch (e) { /* */ } }); T._graphs = {};
  T._minuteries.forEach(clearInterval); T._minuteries = [];
  T.fermerPanneau();
  const c = T.$('#contenu'); c.innerHTML = '';
  try { T.ECRANS[o](c, s); } catch (e) { console.error(e); c.append(h('main', { class: 'col' }, h('div', { class: 'alerte n3' }, h('div', {}, "Erreur d'affichage : " + e.message)))); }
  window.scrollTo(0, 0);
};
T.rafraichir = () => { T.invalider(); const y = window.scrollY; T.aller(T.routeActuelle || T.onglet); window.scrollTo(0, y); };

/* ======================================================================== ECRANS */
T.ECRANS = {};

/* ---------------------------------------------------------------- Resume : que faire maintenant ? */
T.etatActions = () => T.stockage.lire(T.cleStockage() + ':actions') || {};
T.cocherAction = (id, oui) => { const e = T.etatActions(); if (oui) e[id] = T.fdate(new Date()).slice(0, 16); else delete e[id]; T.stockage.ecrire(T.cleStockage() + ':actions', e); };
T.compteCnil = () => {
  const el = h('div', { class: 'compte', role: 'timer', 'aria-live': 'off' }, h('div', { class: 'chiffres' }), h('div', { class: 'unite' }));
  const maj = () => {
    const v = T.vue().cnil; if (!v) return;
    const ms = v.echeance - Date.now(), a = Math.abs(ms), hh = Math.floor(a / 36e5), mm = Math.floor(a % 36e5 / 6e4);
    el.firstChild.textContent = `${ms < 0 ? '-' : ''}${p2(hh)}:${p2(mm)}`;
    el.lastChild.textContent = ms < 0 ? 'heures de retard' : 'heures restantes';
    el.setAttribute('aria-label', ms < 0 ? `Délai dépassé de ${hh} h ${mm} min` : `${hh} h ${mm} min restantes`);
  };
  maj(); T._minuteries.push(setInterval(maj, 30e3));
  return el;
};
T.ligneAction = (a, etat) => {
  const coche = h('input', { type: 'checkbox', checked: !!etat[a.id], 'aria-label': `${a.titre} : fait`, onchange: e => { T.cocherAction(a.id, e.target.checked); } });
  const sous = h('span', { class: 's' }, a.sous);
  if (a.saisir) sous.append(' ', h('button', { class: 'lk', type: 'button', onclick: e => { e.preventDefault(); T.ouvrirReglages('decouverte'); } }, 'Saisir la date de découverte'));
  if (a.lien) sous.append(' ', h('a', { class: 'lk doux', href: '#' + a.lien }, 'Voir les indicateurs'));
  const li = h('li', { class: 'act' }, h('label', { class: 'actl' }, coche, h('span', {}, h('span', { class: 't' }, a.titre), sous)));
  if (a.bouton === 'isoler') li.append(h('button', { class: 'btn-principal', type: 'button', onclick: () => T.ouvrirIsoler() }, T.ic('prise'), 'Isoler le poste'));
  if (a.compte) li.append(T.compteCnil());
  return li;
};
T.ECRANS.resume = c => {
  const id = T.identite(), R = T.reglages(), sit = T.situation(), fg = T.fenetreGrave(), rc = fg ? T.recit(fg.id) : null;
  const m = h('main', { class: 'col', id: 'principal' }); c.append(m);
  const d = T.pdate(id.date);
  m.append(h('div', { class: 'contexte' }, h('span', {}, [R.client, id.poste, d ? `collecte du ${T.jm(d)} à ${T.hm(d)}` : ''].filter(Boolean).join(' · ')),
    T.D.demo ? h('span', { class: 'etiquette', title: 'Collecte fictive : adresses de documentation, cabinet inventé. Aucune donnée réelle.' }, 'DÉMO') : '',
    id.leger ? h('span', { class: 'etiquette' }, 'COLLECTE LÉGÈRE') : ''));
  const h1 = h('h1', { class: 'situation' });
  sit.morceaux.forEach((p, i) => { if (i) h1.append(', '); if (p.prefixe) h1.append(p.prefixe); if (p.texte) h1.append(p.texte); if (p.fort) h1.append(h('b', {}, p.fort)); if (p.suite) h1.append(p.suite); });
  if (!sit.vide) h1.append('.');
  m.append(h1);
  if (rc && rc.etapes.length) m.append(h('p', { class: 'intro' }, `${rc.periode.dans}, de ${T.hm(rc.debut)} à ${T.hm(rc.fin)}. `, h('a', { class: 'lk', href: '#chrono/' + fg.id }, `Voir ${rc.periode.nom} en ${rc.etapes.length} étape${rc.etapes.length > 1 ? 's' : ''} →`)));
  else if (sit.vide) m.append(h('p', { class: 'intro' }, h('a', { class: 'lk', href: '#details/visibilite' }, 'Ce que chaque source voyait →')));
  if (!T.D.collecte.analyse) m.append(h('p', { class: 'intro' }, "Le dossier d'analyse (_analyse) est absent : lancer DigSpill.exe › Analyser une collecte puis régénérer ce fichier pour avoir les sessions, SRUM, exécutions et la grille."));
  // a faire maintenant
  const acts = T.actions(), etat = T.etatActions(), VISIBLES = 3;
  const sec = h('section', { class: 'section', 'aria-labelledby': 'tAFaire' }, h('h2', { class: 'lbl', id: 'tAFaire' }, 'À faire maintenant'));
  sec.append(h('ul', { class: 'actions-liste' }, acts.slice(0, VISIBLES).map(a => T.ligneAction(a, etat))));
  if (acts.length > VISIBLES) {
    const reste = h('ul', { class: 'actions-liste', id: 'autresActions', hidden: true }, acts.slice(VISIBLES).map(a => T.ligneAction(a, etat)));
    const n = acts.length - VISIBLES, chev = T.ic('chevron', 'chev');
    const bouton = h('button', { class: 'more', type: 'button', 'aria-expanded': 'false', 'aria-controls': 'autresActions', onclick: () => {
      const o = reste.hidden; reste.hidden = !o; bouton.setAttribute('aria-expanded', String(o)); chev.classList.toggle('up', o);
      bouton.firstChild.textContent = o ? 'Masquer les autres actions' : `${n} autre${n > 1 ? 's' : ''} action${n > 1 ? 's' : ''}`;
    } }, h('span', {}, `${n} autre${n > 1 ? 's' : ''} action${n > 1 ? 's' : ''}`), chev);
    sec.append(h('div', { class: 'plus' }, bouton), reste);
  }
  m.append(sec);
  // limites de la collecte
  const lim = T.limites();
  m.append(h('section', { class: 'section', 'aria-labelledby': 'tLimites' }, h('h2', { class: 'lbl', id: 'tLimites' }, "Ce qu'on ne peut pas savoir"),
    h('p', { class: 'limites' }, lim ? lim.phrase : "Les sources attendues enregistraient. Une absence de trace reste une absence de trace, pas une preuve."),
    h('a', { class: 'lk doux', href: '#details/visibilite' }, 'Ce que chaque source voyait →')));
  const g = T.pdate(T.D.genere_le);
  m.append(h('footer', { class: 'pied-page' }, h('span', {}, `${g ? `Analyse du ${T.jm(g)}/${g.getFullYear()} à ${T.hm(g)}` : 'Analyse'} · fichier autonome, rien ne sort sans votre clic.`), h('a', { class: 'lk doux droite', href: '#details' }, 'Tous les détails →')));
};

/* ---------------------------------------------------------------- Chronologie racontee */
T.ligneEtape = (s, f) => {
  const k = 'det-' + (T._nEtape = (T._nEtape || 0) + 1);
  const det = h('div', { class: 'det', id: k, hidden: true });
  const chev = T.ic('chevron', 'chev');
  const ctx = { titre: s.titre, t: s.t, fen: f.id, detail: s.sens };
  const remplir = () => {
    det.append(h('p', { class: 'sens' }, s.sens));
    if (s.ded) det.append(h('div', { class: 'ded' }, h('span', { class: 'tag' }, 'Déduction'), h('span', {}, s.ded)));
    det.append(h('div', { class: 'preuves' }, h('p', { class: 'lbl' }, `Preuves · ${s.preuves.length}`), s.preuves.map(i => T.lignePreuve(i, ctx))));
    if (s.liees.length) det.append(h('div', { class: 'preuves liees' }, h('p', { class: 'lbl' }, `Aussi lié à cette étape · ${s.liees.length}`), s.liees.map(i => T.lignePreuve(i, ctx))));
  };
  const btn = h('button', { class: 'st', type: 'button', 'aria-expanded': 'false', 'aria-controls': k, 'data-etape': s.cle }, h('span', { class: 'tm' }, T.hm(s.t)), h('span', { class: 'bul', 'aria-hidden': 'true' }), h('span', { class: 'tt' }, s.titre), chev);
  btn.addEventListener('click', () => { const o = btn.getAttribute('aria-expanded') !== 'true'; if (o && !det.childElementCount) remplir(); btn.setAttribute('aria-expanded', String(o)); det.hidden = !o; chev.classList.toggle('up', o); });
  return h('li', {}, btn, det);
};
T.ECRANS.chrono = (c, fenId) => {
  const fens = T.fenetres(), f = fens.find(x => x.id === fenId) || T.fenetreGrave() || fens[0], id = T.identite();
  const m = h('main', { class: 'col', id: 'principal' }); c.append(m);
  if (!f) { m.append(h('h1', { class: 'recit-titre' }, 'Chronologie'), h('p', { class: 'intro' }, "Aucune fenêtre d'analyse : il n'y a pas de nuit à raconter. Tous les événements restent consultables."), h('p', { class: 'intro' }, h('a', { class: 'lk', href: '#details/evenements' }, 'Tous les événements →'))); return; }
  const r = T.recit(f.id), n = r.etapes.length;
  m.append(h('p', { class: 'lbl', title: f.motif || null }, `Fenêtre ${f.id} · poste ${id.poste}`), h('h1', { class: 'recit-titre' }, r.periode.titre),
    h('p', { class: 'intro' }, n ? `De ${T.hm(r.debut)} à ${T.hm(r.fin)}, en ${n} étape${n > 1 ? 's' : ''}. Cliquez sur une étape pour voir ce qui la prouve.` : `De ${T.hm(f.debut)} à ${T.hm(f.fin)}. Aucun événement important dans cette fenêtre.`));
  for (const ch of r.chapitres) {
    m.append(h('section', { class: 'chap', 'aria-label': `${ch.n} ${ch.nom}` }, h('h2', { class: 'cht' }, h('span', { class: 'chn' }, ch.n), ch.nom, h('span', { class: 'rng' }, ch.plage)),
      h('ol', { class: 'tl' }, ch.etapes.map(s => T.ligneEtape(s, f)))));
  }
  const autres = fens.filter(x => x.id !== f.id);
  m.append(h('footer', { class: 'pied-page' }, autres.length ? h('span', {}, 'Autres fenêtres : ', autres.map((x, i) => [i ? ', ' : '', h('a', { class: 'lk doux', href: '#chrono/' + x.id, title: x.motif || null }, `${x.id} · ${T.jm(x.debut)}`)])) : h('span', {}, "Une seule fenêtre d'analyse."),
    h('a', { class: 'lk doux droite', href: '#details/evenements' }, 'Tous les événements, sans récit →')));
  if (T.etapeOuverte) {
    const b = m.querySelector(`[data-etape="${CSS.escape(T.etapeOuverte)}"]`); T.etapeOuverte = null;
    if (b) requestAnimationFrame(() => { b.click(); b.scrollIntoView({ block: 'center' }); b.focus({ preventScroll: true }); });
  }
};

/* ---------------------------------------------------------------- Details et Preuves : rubriques */
T.RUBRIQUES = {
  details: [['grille', 'Grille par canal'], ['fenetres', "Fenêtres d'analyse"], ['chiffres', 'Chiffres clés et alertes'], ['ip', 'IP et pays'], ['exfil', 'Exfiltration'], ['memoire', 'Mémoire vive'], ['visibilite', 'Visibilité'],
    ['sante', 'Santé et RGPD'], ['fuites', 'Identifiants et fuites'], ['ioc', 'IOC et chasse'], ['ia', 'Analyse IA'], ['evenements', 'Tous les événements'], ['synthese', 'SYNTHESE.txt']],
  preuves: [['integrite', 'Intégrité'], ['rapports', 'Rapports']]
};
T.RENDUS = { rapports: 'rapport' };
const pl = (n, mot, motPl) => `${T.nb(n)} ${n > 1 ? (motPl || mot + 's') : mot}`;
const LIB_STATUT = { INDICE: 'avec un indice', 'A FAIRE': 'à vérifier à la main', 'A LIRE': 'à lire', 'NON VERIFIABLE': 'non vérifiables', RAS: 'sans indice' };
T.CONSTATS = {
  grille: () => { const g = T.vue().grille; if (!g.length) return "Grille absente : l'analyse n'a pas été lancée."; const parts = Object.keys(LIB_STATUT).map(s => [s, g.filter(x => x.statut === s).length]).filter(([, n]) => n).map(([s, n]) => `${n} ${LIB_STATUT[s]}`); return `${pl(g.length, 'canal vérifié', 'canaux vérifiés')} : ${parts.join(', ')}.`; },
  fenetres: () => { const f = T.exfil().fenetres; if (!f.length) return "Aucune fenêtre d'analyse."; const p = f.filter(x => x.niveau === 'PLAUSIBLE').map(x => x.id); return `${pl(f.length, "fenêtre d'analyse", "fenêtres d'analyse")}, du ${T.jm(f[0].debut)} au ${T.jm(f[f.length - 1].fin)}.${p.length ? ` Copie de la base possible pendant ${p.join(', ')}.` : ''}`; },
  chiffres: () => { const a = T.vue().alertes; return a.length ? `${pl(a.length, 'alerte calculée', 'alertes calculées')} à partir des traces.` : 'Aucune alerte majeure calculée à partir des traces.'; },
  ip: () => { const a = T.analyseIp().ips.filter(e => e.type === 'PUBLIQUE'), s = a.filter(e => e.succes && !e.blanche), p = [...new Set(s.map(e => T.nomPays(e.pays)).filter(Boolean))]; return `${pl(a.length, 'IP publique vue', 'IP publiques vues')}, dont ${s.length} avec une connexion réussie${p.length ? ` (${p.join(', ')})` : ''}.`; },
  exfil: () => { const f = T.exfil().fenetres, m = f.reduce((x, y) => !x || y.envoye > x.envoye ? y : x, null); return m ? `Jusqu'à ${T.volume(m.envoye)} envoyés pendant la fenêtre ${m.id} : ${(T.NIVEAUX[m.niveau] || T.NIVEAUX.INCONNU).lib.toLowerCase()}.` : "Aucune fenêtre d'analyse : rien à borner."; },
  memoire: () => { const m = T.memoireVive(); if (!m.lue) return m.raison || "La mémoire vive n'a pas été lue pour cette collecte."; return `${pl(m.procs.length, 'processus lu', 'processus lus')} dans la RAM, ${m.suspects.length ? `dont ${pl(m.suspects.length, 'avec un indice fort', 'avec un indice fort')}` : 'aucun avec un indice fort'} ; ${pl(m.etablies.length, 'connexion établie lue', 'connexions établies lues')}.`; },
  visibilite: () => { const l = T.limites(); return l ? l.phrase.split('. ')[0] + '.' : 'Les sources attendues enregistraient.'; },
  sante: () => { const v = T.vue().cnil; if (!v) return 'Date de découverte à saisir pour calculer le délai CNIL de 72 h.'; const e = v.echeance, q = `${JOURS[e.getDay()]} ${T.jm(e)} à ${T.hm(e)}`; return v.restantH >= 0 ? `Notification CNIL, si le cabinet la décide, avant le ${q}.` : `Le délai CNIL de 72 h a expiré le ${q}.`; },
  fuites: () => { const n = T.identifiants().comptes.length; return n ? `${pl(n, 'compte enregistré', 'comptes enregistrés')} dans les navigateurs du poste, à faire changer.` : 'Aucun identifiant enregistré dans les navigateurs (ou liste non collectée).'; },
  ioc: () => { const i = T.iocs(); return `${pl(i.ip.length, 'IP', 'IP')} et ${pl(T.hachages().length, 'empreinte')} à chercher sur tout le parc.`; },
  ia: () => 'Facultatif : Claude lit une synthèse filtrée, et chaque phrase est vérifiée contre ses preuves.',
  evenements: () => { const ch = T.chronologie(); return `${pl(ch.evenements.length, 'événement')} sur ${pl(ch.voies.length, 'voie')}, sans récit.`; },
  synthese: () => T.texte('SYNTHESE.txt') ? 'Résumé texte écrit par la collecte, sur le poste.' : 'SYNTHESE.txt absent de la collecte.',
  integrite: () => { const s = T.scelleActuel(); if (!s) return 'Aucun scellé dans ce fichier.'; return `${pl(s.elements.length, 'fichier scellé', 'fichiers scellés')}, ${s.jeton && !s.jeton.erreur && s.jetonConforme ? `horodaté par un tiers le ${T.jm(new Date(s.jeton.date))}` : 'pas encore horodaté par un tiers'}.`; },
  rapports: () => 'Trois documents à imprimer ou à enregistrer en PDF.'
};
const ecranRubriques = (onglet, titre) => (c, sous) => {
  const liste = T.RUBRIQUES[onglet], cle = liste.some(x => x[0] === sous) ? sous : liste[0][0], lib = liste.find(x => x[0] === cle)[1];
  const m = h('main', { class: 'large', id: 'principal' }); c.append(m);
  m.append(h('nav', { class: 'rubriques', 'aria-label': titre }, h('p', { class: 'lbl' }, titre), liste.map(([k, l]) => h('a', { class: 'rub', href: `#${onglet}/${k}`, 'aria-current': k === cle ? 'true' : null }, l))));
  const zone = h('section', { class: 'rubrique', 'aria-label': lib }); m.append(zone);
  T.ECRANS[T.RENDUS[cle] || cle](zone);
  let h1 = zone.querySelector('h1');
  if (h1) h1.textContent = lib; else { h1 = h('h1', {}, lib); zone.prepend(h1); }
  let constat = ''; try { constat = T.CONSTATS[cle] ? T.CONSTATS[cle]() : ''; } catch (e) { console.error(e); }
  if (constat) h1.after(h('p', { class: 'constat' }, constat));
};
T.ECRANS.details = ecranRubriques('details', 'Détails');
T.ECRANS.preuves = ecranRubriques('preuves', 'Preuves');

/* rubriques reprises de l'ancienne vue d'ensemble */
T.ECRANS.grille = c => {
  const g = T.vue().grille;
  c.append(h('h1', {}, 'Grille par canal'), h('p', { class: 'sous-titre' }, "Chaque canal par lequel des données peuvent sortir, et ce que les traces en disent. Produite par Analyse-Exfil.ps1."));
  if (!g.length) { c.append(T.vide('Grille absente (analyse non lancée).')); return; }
  const ordre = [...Object.keys(LIB_STATUT), ...new Set(g.map(x => x.statut).filter(s => !LIB_STATUT[s]))];
  for (const st of ordre) {
    const l = g.filter(x => x.statut === st); if (!l.length) continue;
    c.append(T.carte(h('span', {}, T.pillStatut(st), ' ', l.length), '', h('ul', { class: 'lignes' }, l.map(r => h('li', {}, h('div', {}, h('div', { class: 'gras' }, r.canal), h('div', { class: 'doux petit' }, r.constat)), h('div', { class: 'droite' }, T.bp(r.id)))))));
  }
};
T.ECRANS.fenetres = c => {
  const fen = T.exfil().fenetres;
  c.append(h('h1', {}, "Fenêtres d'analyse"), h('p', { class: 'sous-titre' }, 'Sessions suspectes, plus une marge avant et après. La Chronologie raconte chacune.'));
  c.append(fen.length ? h('ul', { class: 'lignes' }, fen.map(f => h('li', {}, h('span', { class: 'mono gras', style: 'min-width:34px' }, f.id),
    h('div', {}, h('div', {}, `${T.fcourt(f.debut)} → ${T.fcourt(f.fin)} · ${f.duree} min`), h('div', { class: 'doux petit' }, f.motif)),
    h('div', { class: 'droite' }, T.pillNiveau(f.niveau), T.bp(f.preuveFenetre), h('a', { class: 'lk doux petit', href: '#chrono/' + f.id }, 'Raconter →'))))) : T.vide('Aucune fenêtre.'));
};
T.ECRANS.chiffres = c => {
  const v = T.vue(), k = v.kpi;
  c.append(h('h1', {}, 'Chiffres clés et alertes'), h('p', { class: 'sous-titre' }, 'Comptés sur toute la collecte. Chaque alerte renvoie à ses preuves.'));
  c.append(h('div', { class: 'grille g4', style: 'margin:0 0 32px' },
    T.kpi('', T.nb(k.sessions), 'sessions depuis Internet ou un VPN', k.sessions ? 'rouge' : ''),
    T.kpi('', T.nb(k.ipSucces), 'IP publiques avec connexion réussie' + (k.pays.length ? ' · ' + k.pays.map(T.nomPays).join(', ') : ''), k.ipSucces ? 'rouge' : ''),
    T.kpi('', T.nb(k.echecs), `échecs de connexion · ${k.ipBrute} IP en force brute`, k.echecs > 500 ? 'orange' : ''),
    T.kpi('', T.nb(k.outils.length), 'outils sensibles lancés pendant les fenêtres', k.outils.length ? 'rouge' : '', k.outils.join(', ')),
    T.kpi('', T.volume(k.envoyeMax), `envoyés au maximum${k.envoyeFen ? ' (fenêtre ' + k.envoyeFen + ')' : ''}`, k.envoyeMax > 500 ? 'rouge' : ''),
    T.kpi('', T.nb(k.chiffres), 'fichiers chiffrés', k.chiffres ? 'rouge' : ''),
    T.kpi('', T.nb(k.anti), "traces d'anti-forensique", k.anti ? 'orange' : ''),
    T.kpi('', T.nb(k.defender), 'détections Defender', k.defender ? 'orange' : '')));
  c.append(h('p', { class: 'lbl', style: 'margin-bottom:6px' }, `Alertes · ${v.alertes.length}`));
  for (const a of v.alertes) c.append(h('div', { class: 'alerte n' + a.niv }, h('div', {}, a.texte), h('div', { class: 'actions' }, T.bps(a.preuves, 2), a.onglet ? h('a', { class: 'lk doux petit', href: '#' + T.route(a.onglet) }, 'Voir →') : '')));
  if (!v.alertes.length) c.append(T.vide('Aucune alerte majeure calculée. Lire quand même la grille par canal.'));
};
/* ---------------------------------------------------------------- memoire vive */
const pillRam = n => n >= 3 ? h('span', { class: 'pill rouge' }, 'fort') : n >= 2 ? h('span', { class: 'pill orange' }, 'à vérifier') : n >= 1 ? h('span', { class: 'pill gris' }, 'à noter') : '';
T.filtreRam = '';
T.ECRANS.memoire = c => {
  const m = T.memoireVive();
  c.append(h('h1', {}, 'Mémoire vive'), h('p', { class: 'sous-titre' }, "Ce qui tournait sur le poste au moment de la collecte, lu au bureau dans la copie de la RAM (Volatility 3). Montre aussi ce qui n'a laissé aucune trace sur le disque."));
  if (!m.lue) { c.append(T.vide(m.raison || "La mémoire vive n'a pas été lue pour cette collecte.")); if (m.lecture) c.append(T.carte('Comment la RAM a été traitée', 'ram_lecture.txt', h('pre', { class: 'apercu' }, m.lecture))); return; }
  c.append(h('div', { class: 'grille g4', style: 'margin-bottom:16px' },
    T.kpi('', T.nb(m.procs.length), 'processus lus dans la RAM', '', m.ecartees ? `${m.ecartees} lignes illisibles écartées (copie faite pendant que Windows tournait)` : ''),
    T.kpi('', T.nb(m.suspects.length), 'avec un indice fort', m.suspects.length ? 'rouge' : 'vert'),
    T.kpi('', T.nb(m.procs.filter(p => !p.fin).length), 'encore actifs à la collecte'),
    T.kpi('', T.nb(m.etablies.length), 'connexions établies lues', m.etablies.some(x => x.niveau >= 2) ? 'rouge' : '')));
  const aRegarder = m.procs.filter(p => p.niveau >= 1).sort((a, b) => b.niveau - a.niveau || (T.pdate(a.debut) - T.pdate(b.debut)));
  c.append(T.carte(`À regarder · ${aRegarder.length}`, 'processus qui portent un indice : nom imité, outil d\'envoi, dossier public, commande encodée…', T.tableau([
    { t: '', l: '84px', v: p => pillRam(p.niveau) },
    { t: 'Processus', v: p => h('div', {}, h('div', { class: 'mono gras' }, p.nom), h('div', { class: 'pale petit' }, `PID ${p.pid} · parent ${p.parent || '?'} (${p.ppid})`)) },
    { t: 'Lancé', l: '110px', v: p => h('div', {}, h('div', { class: 'mono' }, T.fcourt(p.debut)), h('div', { class: 'pale petit' }, p.fin ? 'terminé ' + T.fcourt(p.fin) : 'actif à la collecte')) },
    { t: 'Pourquoi', v: p => h('ul', { class: 'petit', style: 'margin:0;padding-left:16px' }, p.indices.map(i => h('li', {}, i))) },
    { t: 'Ligne de commande', v: p => h('div', { class: 'mono petit', style: 'word-break:break-all' }, p.cmd.slice(0, 260) || '–') },
    { t: 'Preuve', l: '150px', v: p => T.bp(p.id) }], aRegarder, { vide: 'Aucun processus ne porte d\'indice.', cls: p => p.niveau >= 3 ? 'attention' : '' })));
  const ext = m.reseau.filter(x => x.ip && !/^(0\.0\.0\.0|::|\*|127\.|::1$)/.test(x.ip)).sort((a, b) => b.niveau - a.niveau);
  const note = m.lecture.split(/\r?\n/).find(l => /ne lit pas encore la table des connexions/.test(l));
  c.append(T.carte(`Connexions lues dans la RAM · ${ext.length}`, m.reseau.length ? `module ${m.reseau[0].source} · ${m.reseau.length} lignes au total (ports en écoute compris)` : '',
    note ? h('div', { class: 'alerte n1' }, h('div', {}, note.trim(), ' ', h('a', { class: 'lk', href: '#details/ip' }, 'Connexions relevées en direct →'))) : '',
    T.tableau([{ t: '', l: '84px', v: x => pillRam(x.niveau) }, { t: 'Distant', v: x => h('span', { class: 'mono' }, `${x.ip}:${x.port}`) }, { t: 'État', l: '110px', v: x => x.etat },
      { t: 'Processus', v: x => h('span', {}, h('span', { class: 'mono' }, x.nom || '?'), h('span', { class: 'pale petit' }, ` PID ${x.pid}`)) }, { t: 'Local', v: x => h('span', { class: 'mono petit' }, x.local) },
      { t: 'Créée', l: '110px', v: x => h('span', { class: 'mono' }, T.fcourt(x.cree)) }, { t: 'Preuve', l: '150px', v: x => T.bp(x.id) }], ext, { max: 300, vide: 'Aucune connexion vers une autre machine lue dans la RAM.' })));
  const tous = h('div');
  const rendre = () => {
    const q = T.filtreRam.toLowerCase();
    const l = m.procs.filter(p => !q || (p.nom + ' ' + p.cmd + ' ' + p.pid).toLowerCase().includes(q));
    tous.innerHTML = '';
    tous.append(T.tableau([{ t: 'PID', l: '64px', v: p => h('span', { class: 'mono' }, p.pid) }, { t: 'Processus', v: p => h('span', { class: 'mono' + (p.niveau >= 2 ? ' gras' : '') }, p.nom) },
      { t: 'Parent', v: p => h('span', { class: 'petit' }, `${p.parent || '?'} (${p.ppid})`) }, { t: 'Lancé', l: '110px', v: p => h('span', { class: 'mono' }, T.fcourt(p.debut)) },
      { t: 'Fin', l: '110px', v: p => h('span', { class: 'mono pale' }, p.fin ? T.fcourt(p.fin) : 'actif') },
      { t: 'Ligne de commande', v: p => h('span', { class: 'mono petit', style: 'word-break:break-all' }, p.cmd.slice(0, 200)) }, { t: '', l: '84px', v: p => pillRam(p.niveau) }],
      l, { max: 600, hauteur: '520px', vide: 'Aucun processus pour ce filtre.' }));
  };
  c.append(T.carte(`Tous les processus · ${m.procs.length}`, 'triés par heure de lancement', h('div', { class: 'filtres' },
    h('input', { type: 'search', placeholder: 'Filtrer : nom, PID, ligne de commande', value: T.filtreRam, 'aria-label': 'Filtrer les processus', style: 'min-width:280px', oninput: e => { T.filtreRam = e.target.value; rendre(); } }),
    h('button', { class: 'btn', style: 'margin-left:auto', onclick: () => T.telecharger(`${T.identite().poste}_ram_processus.csv`, T.texte('ram_processus')) }, 'CSV')), tous));
  rendre();
  c.append(T.carte('Comment la RAM a été lue', 'ram_lecture.txt : image, symboles, modules Volatility, limites', h('pre', { class: 'apercu' }, m.lecture)));
};
T.ECRANS.synthese = c => {
  const s = T.texte('SYNTHESE.txt');
  c.append(h('h1', {}, 'SYNTHESE.txt'), h('p', { class: 'sous-titre' }, 'Tel qu\'écrit par Collecte-Exfil.ps1, sans retouche.'), s ? h('pre', { class: 'apercu', style: 'max-height:none' }, s) : T.vide('Fichier absent.'));
};

/* ---------------------------------------------------------------- tous les evenements (ancienne chronologie, sans champ de recherche) */
T.filtreChrono = { g: 0, q: '', voies: null };
T.ECRANS.evenements = c => {
  const ch = T.chronologie(), F = T.filtreChrono, fen = T.fenetres();
  if (!F.voies) F.voies = new Set(ch.voies);
  c.append(h('h1', {}, 'Tous les événements'), h('p', { class: 'sous-titre' }, `Zones rouges = fenêtres d'analyse · clic sur un point = sa preuve · Ctrl K pour chercher une IP, un compte ou un programme.`));
  const graphEl = h('div', { class: 'graph haut', id: 'gFrise' });
  const liste = h('div');
  const filtrer = () => ch.evenements.filter(e => e.g >= F.g && F.voies.has(e.voie) && (!F.q || (e.titre + ' ' + e.detail + ' ' + (e.ip || '') + ' ' + (e.compte || '')).toLowerCase().includes(F.q)));
  let graphe = null, zoom = null;
  const dessiner = () => {
    const evts = filtrer();
    graphe = T.graphFrise(graphEl, evts, ch.voies.filter(v => F.voies.has(v)), fen, e => T.ouvrirPreuve(e.id, e));
    if (zoom) graphe.dispatchAction({ type: 'dataZoom', startValue: zoom[0], endValue: zoom[1] });
    graphe.on('datazoom', () => { const o = graphe.getOption().dataZoom[0]; zoom = [o.startValue, o.endValue]; tableau(evts); });
    tableau(evts);
  };
  const tableau = evts => {
    const vis = zoom ? evts.filter(e => +e.t >= zoom[0] && +e.t <= zoom[1]) : evts;
    liste.innerHTML = '';
    liste.append(T.carte(`Événements · ${T.nb(vis.length)}`, zoom ? 'limités à la période zoomée' : '', T.tableau([
      { t: '', l: '18px', v: e => h('span', { title: 'gravité ' + e.g, style: `display:inline-block;width:8px;height:8px;border-radius:50%;background:${T.COUL['g' + e.g]}` }) },
      { t: 'Date', l: '120px', v: e => h('span', { class: 'mono' }, T.fcourt(e.t)) }, { t: 'Voie', l: '110px', v: e => e.voie },
      { t: 'Événement', v: e => h('div', {}, h('div', { class: e.g >= 2 ? 'gras' : '' }, e.titre), h('div', { class: 'pale petit' }, e.detail.slice(0, 180))) },
      { t: 'Fen.', l: '50px', v: e => e.fen ? h('span', { class: 'pill rouge' }, e.fen) : '' }, { t: 'Preuve', l: '200px', v: e => T.bp(e.id) }],
      vis, { max: 600 })));
  };
  const seg = h('div', { class: 'seg', role: 'group', 'aria-label': 'Gravité' }, [['Tout', 0], ['Notable', 1], ['Important', 2], ['Critique', 3]].map(([l, g]) => h('button', { type: 'button', class: F.g === g ? 'actif' : '', 'aria-pressed': String(F.g === g), onclick: e => { F.g = g; T.$$('button', seg).forEach(b => { b.classList.remove('actif'); b.setAttribute('aria-pressed', 'false'); }); e.target.classList.add('actif'); e.target.setAttribute('aria-pressed', 'true'); dessiner(); } }, l)));
  const zooms = h('div', { class: 'seg', role: 'group', 'aria-label': 'Zoom' }, h('button', { type: 'button', onclick: () => { zoom = null; dessiner(); } }, 'Tout'), fen.map(w => h('button', { type: 'button', title: w.motif, onclick: () => { zoom = [+w.debut - 30 * 60e3, +w.fin + 30 * 60e3]; dessiner(); } }, w.id)));
  const voies = h('div', { class: 'filtres' }, ch.voies.map(v => h('label', { class: 'pill gris', style: 'cursor:pointer' }, h('input', { type: 'checkbox', checked: F.voies.has(v), onchange: e => { e.target.checked ? F.voies.add(v) : F.voies.delete(v); dessiner(); } }), ` ${v} (${ch.compte[v]})`)));
  const filtreQ = F.q ? h('span', { class: 'pill bleu' }, `Filtre : ${F.q} `, h('button', { type: 'button', class: 'lk', 'aria-label': 'Retirer le filtre', onclick: () => { F.q = ''; T.rafraichir(); } }, 'retirer')) : '';
  c.append(T.carte('', '', h('div', { class: 'filtres' }, h('span', { class: 'pale petit' }, 'Gravité'), seg, h('span', { class: 'pale petit', style: 'margin-left:10px' }, 'Zoom'), zooms, filtreQ), voies, graphEl,
    ch.tronque ? h('div', { class: 'pale petit' }, `${T.nb(ch.tronque)} exécutions ordinaires hors fenêtres non affichées (bruit).`) : ''), liste);
  if (T.zoomFenetre) { const w = fen.find(x => x.id === T.zoomFenetre); if (w) zoom = [+w.debut - 30 * 60e3, +w.fin + 30 * 60e3]; T.zoomFenetre = null; }
  requestAnimationFrame(dessiner);
};

/* ---------------------------------------------------------------- IP et pays */
T.filtreIp = 'interessantes';
T.ECRANS.ip = c => {
  const a = T.analyseIp(), pub = a.ips.filter(e => e.type === 'PUBLIQUE'), b = T.D.bases || {};
  c.append(h('h1', {}, 'IP et pays'), h('p', { class: 'sous-titre' }, 'Pays et opérateur trouvés hors ligne · listes publiques comparées en local · rien n\'est envoyé sans clic'));
  c.append(h('div', { class: 'grille g4', style: 'margin-bottom:16px' },
    T.kpi('', T.nb(pub.length), 'IP publiques vues'), T.kpi('', T.nb(a.pays.length), 'pays'),
    T.kpi('', T.nb(pub.filter(e => e.succes && !e.blanche).length), 'avec connexion réussie', pub.some(e => e.succes && !e.blanche) ? 'rouge' : 'vert'),
    T.kpi('', T.nb(pub.filter(e => e.listes.length).length), 'sur une liste noire publique', pub.some(e => e.listes.length) ? 'orange' : '')));
  const carte = h('div', { class: 'graph carte-monde', id: 'gCarte' });
  c.append(T.carte('Origine des connexions', 'rouge = connexion réussie · orange = échecs seulement', carte,
    h('div', { class: 'pale petit' }, b.asn ? `Base pays/opérateur : ${b.asn.source} du ${b.asn.date}` : 'Base de géolocalisation absente à la génération : régénérer le fichier avec Internet.',
      b.ville ? ` · villes : ${b.ville.source} du ${b.ville.date}` : '', ' · ', (b.listes || []).filter(l => l.date).length ? `listes : ${(b.listes || []).filter(l => l.date).map(l => l.nom).join(', ')}` : 'listes noires non téléchargées')));
  requestAnimationFrame(() => T.graphCarte(carte, a));
  const tbl = h('div');
  const rendre = () => {
    const f = T.filtreIp;
    const lignes = a.ips.filter(e => f === 'toutes' ? true : f === 'succes' ? e.succes : f === 'brute' ? e.echecs >= 20 : f === 'listes' ? e.listes.length : (e.type !== 'Privee' && (e.succes || e.echecs || e.active)));
    tbl.innerHTML = '';
    tbl.append(T.tableau([
      { t: 'Score', l: '60px', v: e => h('span', { class: 'pill ' + (e.blanche ? 'vert' : e.score >= 5 ? 'rouge' : e.score >= 3 ? 'orange' : 'gris'), title: e.raisons.join('\n') }, e.blanche ? 'blanche' : e.score) },
      { t: 'IP', v: e => h('div', {}, h('div', { class: 'mono gras' }, e.ip), h('div', { class: 'pale petit' }, e.type)) },
      { t: 'Pays', v: e => e.pays ? h('span', {}, T.drapeau(e.pays), ' ', T.nomPays(e.pays), e.ville ? h('div', { class: 'pale petit' }, e.ville) : '') : '–' },
      { t: 'Opérateur', v: e => h('div', {}, h('div', {}, e.operateur || '–'), e.categorie ? h('span', { class: 'pill ' + (e.categorie.startsWith('Heb') ? 'rouge' : e.categorie.startsWith('FAI') ? 'bleu' : 'gris') }, e.categorie) : '') },
      { t: 'Succès', l: '60px', v: e => e.succes ? h('b', { style: 'color:var(--red)' }, T.nb(e.succes)) : '0' }, { t: 'Échecs', l: '70px', v: e => T.nb(e.echecs) },
      { t: 'Période', v: e => h('span', { class: 'petit' }, T.fcourt(e.premier), e.dernier && e.dernier !== e.premier ? ' → ' + T.fcourt(e.dernier) : '') },
      { t: 'Comptes', v: e => h('span', { class: 'petit' }, e.comptes.slice(0, 4).join(', ')) },
      { t: 'Pourquoi', v: e => h('div', { class: 'petit' }, e.listes.map(l => h('span', { class: 'pill rouge', style: 'margin:1px' }, '' + l.nom)), h('div', { class: 'doux' }, e.raisons.filter(r => !r.startsWith('liste ')).join(' · '))) },
      { t: 'Preuves', v: e => T.bps(e.preuves, 2) },
      { t: '', l: '170px', v: e => h('div', { style: 'display:flex;gap:6px;flex-wrap:wrap' }, e.type === 'PUBLIQUE' || e.type === 'VPN/CGNAT' ? h('button', { class: 'btn petit', title: 'Ajouter / retirer de la liste blanche (IP légitime : box du cabinet, technicien…)', onclick: () => T.basculerBlanche(e.ip) }, e.blanche ? 'Retirer' : 'Légitime') : '',
          e.type === 'PUBLIQUE' ? h('button', { class: 'btn petit', title: 'Interroger Shodan InternetDB (envoie uniquement cette IP)', onclick: ev => T.internetDb(e.ip, ev.target) }, 'InternetDB') : '') }],
      lignes, { max: 400, cls: e => e.score >= 5 ? 'attention' : '', vide: 'Aucune IP pour ce filtre.' }));
  };
  const seg = h('div', { class: 'seg' }, [['interessantes', 'À regarder'], ['succes', 'Connexions réussies'], ['brute', 'Force brute'], ['listes', 'Sur une liste'], ['toutes', 'Toutes']].map(([k, l]) =>
    h('button', { class: T.filtreIp === k ? 'actif' : '', onclick: ev => { T.filtreIp = k; T.$$('button', seg).forEach(x => x.classList.remove('actif')); ev.target.classList.add('actif'); rendre(); } }, l)));
  c.append(T.carte('Adresses IP', 'Légitime = liste blanche, partagée via Réglages · InternetDB = envoie cette IP seulement', h('div', { class: 'filtres' }, seg,
    h('button', { class: 'btn', style: 'margin-left:auto', onclick: () => T.telecharger(`${T.identite().poste}_ip.csv`, T.versCsv(a.ips.map(e => ({ IP: e.ip, Type: e.type, Pays: e.pays, Ville: e.ville, ASN: e.asn, Operateur: e.operateur, Categorie: e.categorie, Succes: e.succes, Echecs: e.echecs, Premier: e.premier, Dernier: e.dernier, Score: e.score, Raisons: e.raisons.join(' | '), Listes: e.listes.map(l => l.nom).join(' | ') })))) }, 'CSV')), tbl));
  rendre();
  const g = h('div', { class: 'graph bas', id: 'gBrute', style: 'height:200px' });
  c.append(T.carte('Force brute : échecs de connexion par jour', '4625', g));
  requestAnimationFrame(() => { if (!T.graphBrute(g)) g.replaceWith(T.vide('Aucun échec de connexion collecté.')); });
};
T.basculerBlanche = ip => {
  const R = T.reglages(), lb = (R.liste_blanche || []).slice();
  const i = lb.findIndex(l => T.nettoyerIp(l.valeur) === ip);
  if (i >= 0) lb.splice(i, 1); else { const note = prompt(`Pourquoi ${ip} est légitime ? (ex. box du cabinet, domicile du praticien, technicien)`, ''); if (note === null) return; lb.push({ valeur: ip, note: note || 'légitime' }); }
  T.majReglages({ liste_blanche: lb }); T.rafraichir();
};
T.internetDb = async (ip, bouton) => {
  bouton.disabled = true; bouton.textContent = '…';
  try {
    const r = await fetch('https://internetdb.shodan.io/' + encodeURIComponent(ip));
    const j = await r.json();
    const td = bouton.closest('tr').children[8];
    td.append(h('div', { class: 'petit', style: 'margin-top:4px;background:var(--panel2);border-radius:6px;padding:4px 6px' }, r.status === 404 || j.detail ? 'InternetDB : aucune donnée' :
      `InternetDB : ports ${(j.ports || []).join(', ') || '–'} · ${(j.tags || []).join(', ') || 'pas de tag'}${(j.hostnames || []).length ? ' · ' + j.hostnames.slice(0, 2).join(', ') : ''}${(j.vulns || []).length ? ' · ' + j.vulns.length + ' CVE' : ''}`));
    bouton.textContent = 'fait';
  } catch (e) { bouton.textContent = 'InternetDB'; bouton.disabled = false; T.toast("InternetDB injoignable depuis ce navigateur (hors ligne ou bloqué)."); }
};
T.versCsv = lignes => { if (!lignes.length) return ''; const k = Object.keys(lignes[0]); const q = v => '"' + String(v ?? '').replace(/"/g, '""') + '"'; return '\ufeff' + [k.map(q).join(','), ...lignes.map(l => k.map(x => q(l[x])).join(','))].join('\r\n'); };

/* ---------------------------------------------------------------- exfiltration */
T.ECRANS.exfil = c => {
  const ex = T.exfil(), R = T.reglages(), hy = ex.hyp;
  c.append(h('h1', {}, 'Exfiltration'), h('p', { class: 'sous-titre' }, 'On ne peut pas toujours prouver ce qui est sorti. Mais on peut souvent borner ce qui a pu sortir.'));
  const maj = (k, v) => { T.majReglages({ [k]: v }); T.rafraichir(); };
  c.append(T.carte('Test de plausibilité : hypothèses', 'à ajuster avec le cabinet', h('div', { class: 'champs' },
    h('div', { class: 'champ' }, h('label', {}, 'Débit montant de la box (Mbit/s)'), h('input', { type: 'number', min: 0, step: 0.1, value: R.debit_montant_mbps, placeholder: 'ex. 1 (ADSL), 40 (VDSL), 300 (fibre)', onchange: e => maj('debit_montant_mbps', e.target.value) }),
      h('div', { class: 'aide' }, 'Test de débit ou contrat FAI. Sert à la borne physique.')),
    h('div', { class: 'champ' }, h('label', {}, 'Taille de la base patients (Mo)'), h('input', { type: 'number', min: 0, value: R.taille_base_mo, placeholder: hy.tailleAuto ? `auto : ${T.nb(hy.tailleAuto)} Mo` : 'inconnue', onchange: e => maj('taille_base_mo', e.target.value) }),
      h('div', { class: 'aide' }, hy.tailleAuto ? `Plus grosse base trouvée sur le disque : ${T.nb(hy.tailleAuto)} Mo.` : 'Aucune base métier trouvée par la collecte.')),
    h('div', { class: 'champ' }, h('label', {}, 'Compression supposée (×)'), h('input', { type: 'number', min: 1, step: 0.5, value: R.compression || 4, onchange: e => maj('compression', e.target.value) }),
      h('div', { class: 'aide' }, h('span', { class: 'deduction' }, 'déduction'), ' Une base se compresse souvent de 3 à 10 fois.'))),
    h('div', { class: 'petit doux', style: 'margin-top:8px' }, `Base compressée estimée : ${hy.comp ? T.nb(hy.comp) + ' Mo' : 'inconnue'}`)));
  if (!ex.fenetres.length) c.append(T.vide('Aucune fenêtre d\'analyse : rien à borner.'));
  for (const f of ex.fenetres) {
    const g = h('div', { class: 'graph bas', id: 'gPl' + f.id });
    c.append(h('div', { class: 'carte' }, h('h2', {}, `${f.id}`, h('span', { class: 'pale', style: 'font-weight:500' }, `${T.fcourt(f.debut)} → ${T.fcourt(f.fin)} · ${f.duree} min`), h('span', { style: 'margin-left:auto' }, T.pillNiveau(f.niveau))),
      h('div', { class: 'doux petit', style: 'margin:-4px 0 8px' }, f.motif),
      h('div', { class: 'grille g2' }, g, h('ul', { class: 'lignes' }, f.constats.map(x => h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, x))))),
      f.apps.length ? h('details', { style: 'margin-top:8px' }, h('summary', { class: 'petit gras', style: 'cursor:pointer' }, `Applications qui ont envoyé (${f.apps.length})`),
        T.tableau([{ t: 'Application', v: a => h('span', { class: 'mono' }, a.app) }, { t: 'Envoyé', v: a => T.nb(a.mo, 1) + ' Mo' }, { t: 'Écart à la référence', v: a => a.ecart ? h('span', { class: 'pill rouge' }, a.ecart) : '' }, { t: 'Preuves', v: a => T.bps(a.ids, 2) }], f.apps, { defile: false })) : '',
      h('div', { class: 'petit', style: 'margin-top:6px' }, 'Preuves : ', T.bp(f.preuveFenetre), ' ', T.bps(f.preuves, 4))));
    requestAnimationFrame(() => T.graphPlausibilite(g, f, hy));
  }
  const gs = h('div', { class: 'graph', id: 'gSrum' });
  c.append(T.carte('Volumes envoyés par le poste (SRUM)', ex.ref ? `référence : moyenne ${T.nb(ex.ref.moyenne, 1)} · P95 ${T.nb(ex.ref.p95, 1)} · max ${T.nb(ex.ref.max, 1)} Mo/h` : '', ex.serie.length ? gs : T.vide('SRUM absent de l\'analyse.')));
  if (ex.serie.length) requestAnimationFrame(() => T.graphSrum(gs, ex));
  c.append(h('div', { class: 'grille g2' },
    T.carte('Bases métier sur le disque', '', T.tableau([{ t: 'Chemin', v: b => h('span', { class: 'mono petit' }, b.chemin) }, { t: 'Taille', l: '90px', v: b => T.nb(b.mo) + ' Mo' }, { t: '', v: b => b.sauvegarde ? h('span', { class: 'pill gris' }, 'sauvegarde') : '' }, { t: 'Preuve', v: b => T.bp(b.id) }], ex.bases, { vide: 'Aucune base métier trouvée (rancon\\bases_metier.csv).', defile: false })),
    T.carte('Limites du test', '', h('ul', { class: 'lignes' }, T.LIMITES_EXFIL.map(x => h('li', {}, h('span', { class: 'ic' }, '•'), h('span', { class: 'petit' }, x)))))));
};

/* ---------------------------------------------------------------- visibilite */
T.ECRANS.visibilite = c => {
  const v = T.visibilite();
  c.append(h('h1', {}, 'Visibilité'), h('p', { class: 'sous-titre' }, "Une absence de trace ne prouve rien si la source ne regardait pas à ce moment. Cette carte montre ce qu'on ne pourra jamais savoir."));
  const g = h('div', { class: 'graph', id: 'gVisi', style: `height:${Math.max(260, 70 + v.sources.length * 26 + 90)}px` });
  c.append(T.carte('Couverture des sources, heure par heure', 'cadres rouges = fenêtres de l\'attaquant', v.grille.heures.length ? g : T.vide('Aucune fenêtre d\'analyse.')));
  if (v.grille.heures.length) requestAnimationFrame(() => T.graphVisibilite(g, v));
  c.append(h('div', { class: 'grille g2' },
    T.carte('Par fenêtre', '', v.fenetres.length ? h('ul', { class: 'lignes' }, v.fenetres.map(w => h('li', {}, h('span', { class: 'ic gras' }, w.id),
      h('div', {}, h('div', {}, h('b', {}, w.taux + ' %'), ' des sources couvrent la fenêtre'), h('div', { class: 'petit doux' }, w.sources.filter(s => s.statut !== 'couverte').map(s => `${s.source} : ${s.statut}`).join(' · ') || 'toutes couvertes'))))) : T.vide()),
    T.carte("Traces d'anti-forensique", 'effacements, désactivations, exclusions', v.anti.length ? h('ul', { class: 'lignes' }, v.anti.map(a => h('li', {}, h('span', { class: 'ic' }, ''), h('div', {}, h('div', { class: 'gras' }, a.trace), h('div', { class: 'petit doux' }, (a.date ? T.fcourt(a.date) + ' · ' : '') + a.detail.slice(0, 160))), h('div', { class: 'droite' }, T.bp(a.id))))) : h('div', {}, 'Aucune trace détectée.'))));
  c.append(T.carte('Sources', '', T.tableau([{ t: 'Source', v: s => s.source }, { t: 'État', v: s => h('span', { class: 'pill ' + (s.etat === 'present' ? 'vert' : s.etat === 'desactive' ? 'rouge' : 'gris') }, s.etat === 'present' ? 'présente' : s.etat === 'desactive' ? 'désactivée' : 'absente') },
    { t: 'Du', v: s => T.fcourt(s.debut) }, { t: 'Au', v: s => T.fcourt(s.fin) }, { t: 'Preuve', v: s => T.bp(s.id) }], v.sources, { defile: false })));
};

/* ---------------------------------------------------------------- sante et RGPD */
T.ECRANS.sante = c => {
  const s = T.sante(), v = T.vue(), R = T.reglages(), ex = T.exfil();
  c.append(h('h1', {}, 'Santé et RGPD'), h('p', { class: 'sous-titre' }, 'Ce qui aide le cabinet à décider de la notification. La décision appartient au responsable de traitement et à son DPO.'));
  const dec = h('input', { type: 'datetime-local', value: (R.decouverte || '').replace(' ', 'T').slice(0, 16), onchange: e => { T.majReglages({ decouverte: e.target.value.replace('T', ' ') }); T.rafraichir(); } });
  const pire = ex.fenetres.reduce((m, f) => (!m || f.envoye > m.envoye) ? f : m, null);
  c.append(h('div', { class: 'grille g2' },
    T.carte('Délai CNIL (art. 33 RGPD : 72 h après la découverte)', '', h('div', { class: 'champ' }, h('label', {}, 'Date et heure de découverte'), dec,
      h('div', { class: 'aide' }, R.decouverte && T.decouverteFiche() === R.decouverte ? 'Reprise de A_COMPLETER_TECHNICIEN.txt' : 'Saisie dans cette interface')),
      v.cnil ? h('div', { style: 'margin-top:12px;font-size:18px' }, v.cnil.restantH < 0 ? h('b', { style: 'color:var(--red)' }, `Délai dépassé depuis ${Math.floor(-v.cnil.restantH)} h`) : h('span', {}, '', h('b', {}, `${Math.floor(v.cnil.restantH)} h ${p2m(v.cnil.restantH)}`), ' restantes'),
        h('div', { class: 'petit doux' }, `Échéance : ${T.flong(v.cnil.echeance)}`)) : '',
      h('div', { class: 'petit', style: 'margin-top:10px' }, 'Téléservice : ', h('a', { href: 'https://notifications.cnil.fr/notifications/index', target: '_blank', rel: 'noopener' }, 'notifications.cnil.fr'))),
    T.carte('Éléments pour le formulaire CNIL', 'pré-rempli, à vérifier', h('ul', { class: 'lignes' },
      h('li', {}, h('span', { class: 'ic' }, ''), h('div', {}, h('b', {}, 'Nature : '), [T.vue().kpi.chiffres ? 'rançongiciel (chiffrement)' : '', T.vue().kpi.sessions ? 'accès à distance non autorisé' : '', pire && ['PLAUSIBLE', 'PARTIELLE'].includes(pire.niveau) ? 'exfiltration possible' : ''].filter(Boolean).join(', ') || 'à préciser')),
      h('li', {}, h('span', { class: 'ic' }, ''), h('div', {}, h('b', {}, 'Catégories de données : '), s.categories.map(x => x.categorie).join(', ') || 'à préciser', ' ', h('span', { class: 'deduction' }, 'déduction'))),
      h('li', {}, h('span', { class: 'ic' }, ''), h('div', {}, h('b', {}, 'Nombre de personnes : '), 'à demander au cabinet (nombre de patients dans la base, pas de fichiers)')),
      h('li', {}, h('span', { class: 'ic' }, ''), h('div', {}, h('b', {}, 'Exfiltration : '), pire ? `${T.NIVEAUX[pire.niveau].lib.toLowerCase()} (fenêtre ${pire.id}, ${T.nb(pire.envoye)} Mo envoyés)` : 'non évaluée')),
      h('li', {}, h('span', { class: 'ic' }, ''), h('div', {}, h('b', {}, 'Mesures prises : '), 'isolement, collecte forensique, changement des mots de passe, chasse sur le parc (à compléter)'))))));
  c.append(T.carte('Logiciels et données de santé repérés', 'déduits des chemins et des sites : à confirmer avec le cabinet', s.logiciels.length ? T.tableau([
    { t: 'Logiciel / source', v: t => h('div', {}, h('b', {}, t.logiciel), s.pendant.includes(t.logiciel) ? h('div', {}, h('span', { class: 'pill rouge' }, 'touché pendant une fenêtre')) : '') },
    { t: 'Données probables', v: t => h('div', {}, t.categories.map(x => h('span', { class: 'pill violet', style: 'margin:1px' }, x))) },
    { t: 'Traces', v: t => h('div', { class: 'petit' }, Object.entries(t.traces).map(([k, n]) => h('div', {}, `${n} × ${k}`))) },
    { t: 'Preuves', v: t => T.bps(t.preuves.map(p => p.id), 3) }], s.logiciels, { defile: false }) : T.vide('Aucun logiciel métier ni site santé repéré.')));
  const H = Object.assign({}, T.REGLAGES_DEFAUT.horaires, R.horaires || {});
  const horaires = h('div', { class: 'champs' }, T.JOURS.map((j, i) => h('div', { class: 'champ' }, h('label', {}, j), h('input', { value: H[i] || '', placeholder: 'fermé', onchange: e => { const n = Object.assign({}, H, { [i]: e.target.value }); T.majReglages({ horaires: n }); T.rafraichir(); } }))));
  const distantes = s.sessions.filter(x => ['PUBLIQUE', 'VPN/CGNAT'].includes(x.typeIp));
  c.append(T.carte("Horaires du cabinet et sessions à distance", 'format 08:00-12:00,14:00-19:00', horaires,
    h('div', { style: 'margin-top:12px' }, T.tableau([{ t: 'Début', v: x => T.fcourt(x.debut) }, { t: 'Jour', v: x => x.jour }, { t: 'Fin', v: x => T.fcourt(x.fin) }, { t: 'Compte', v: x => x.compte }, { t: 'IP', v: x => h('span', { class: 'mono' }, x.ip) },
      { t: '', v: x => x.hors ? h('span', { class: 'pill rouge' }, 'hors horaires') : h('span', { class: 'pill gris' }, 'heures d\'ouverture') }, { t: 'Preuve', v: x => T.bp(x.id) }], distantes, { vide: 'Aucune session depuis Internet / VPN.', defile: false }))));
};

/* ---------------------------------------------------------------- identifiants et fuites */
T.ECRANS.fuites = c => {
  const id = T.identifiants(), R = T.reglages(), b = (T.D.bases || {}).ransomware;
  c.append(h('h1', {}, 'Identifiants et fuites'), h('p', { class: 'sous-titre' }, 'Les mots de passe ne sont jamais lus par la collecte : seuls les sites et identifiants enregistrés sont listés.'));
  c.append(T.carte(`Comptes à faire changer (${id.comptes.length})`, 'enregistrés dans les navigateurs du poste', T.tableau([{ t: 'Utilisateur', v: x => x.utilisateur }, { t: 'Site', v: x => h('b', {}, x.site) }, { t: 'Identifiant(s)', v: x => h('span', { class: 'mono petit' }, x.identifiants) }, { t: 'Navigateur', v: x => x.navigateurs }, { t: 'Preuve', v: x => T.bp(x.id) }], id.comptes, { vide: 'Aucun (ou identifiants non listés : DigSpill.exe › Identifiants de ce compte).', defile: false }),
    id.comptes.length ? h('button', { class: 'btn', style: 'margin-top:8px', onclick: async () => T.toast(await T.copier(id.comptes.map(x => `☐ ${x.site} (${x.identifiants})`).join('\n')) ? 'Liste copiée (à coller dans un mail ou une fiche)' : 'Copie impossible') }, 'Copier la liste à cocher') : '',
    id.wifi ? h('div', { class: 'petit doux', style: 'margin-top:8px' }, `${id.wifi} profil(s) Wi-Fi enregistré(s) : clés lisibles par un administrateur du poste, à changer si le compte était admin.`) : ''));
  const res = h('div', { style: 'margin-top:10px' }), mdp = h('input', { type: 'password', class: 'texte', placeholder: 'Mot de passe à tester (jamais envoyé)', style: 'max-width:320px', autocomplete: 'off' });
  const tester = async () => {
    if (!mdp.value) return; res.innerHTML = 'Vérification…';
    try { const n = await T.pwned(mdp.value); res.innerHTML = ''; res.append(n ? h('div', { class: 'alerte n3' }, h('div', { class: 'ic' }, ''), h('div', {}, `Ce mot de passe apparaît ${T.nb(n)} fois dans des fuites publiques. Il a pu servir à entrer : le changer partout.`)) : h('div', { class: 'alerte n1' }, h('div', { class: 'ic' }, ''), h('div', {}, 'Absent des fuites connues de Have I Been Pwned (ça ne prouve pas qu\'il est sûr).'))); }
    catch (e) { res.textContent = 'Service injoignable depuis ce navigateur (' + e.message + '). Vérifier la connexion Internet.'; }
    mdp.value = '';
  };
  c.append(h('div', { class: 'grille g2' },
    T.carte('Mot de passe dans une fuite publique ?', 'Have I Been Pwned · k-anonymat', h('ul', { class: 'lignes' },
      h('li', {}, h('span', { class: 'ic' }, ''), h('span', { class: 'petit' }, 'Le mot de passe est haché ici (SHA-1). Seuls les 5 premiers caractères du hachage partent sur Internet.')),
      h('li', {}, h('span', { class: 'ic' }, ''), h('span', { class: 'petit' }, 'Utile pour expliquer l\'entrée : un mot de passe RDP déjà fuité = force brute réussie.'))),
      h('div', { class: 'filtres', style: 'margin-top:8px' }, mdp, h('button', { class: 'btn primaire', onclick: tester }, 'Vérifier')), res),
    T.carte(`Adresses e-mail trouvées (${id.emails.length})`, 'à vérifier sur haveibeenpwned.com', id.emails.length ? h('ul', { class: 'lignes' }, id.emails.map(e => h('li', {}, h('span', { class: 'ic' }, ''), h('div', {}, h('div', { class: 'mono gras' }, e.email), h('div', { class: 'petit doux' }, e.sites.join(', '))),
      h('div', { class: 'droite' }, h('a', { class: 'btn petit', href: 'https://haveibeenpwned.com/', target: '_blank', rel: 'noopener', title: 'Ouvre le site : saisir l\'adresse vous-même' }, 'HIBP ↗'), T.bp(e.preuves[0]))))) : T.vide('Aucune adresse e-mail parmi les identifiants enregistrés.'))));
  const mots = h('input', { class: 'texte', value: (R.mots_cles_fuite && R.mots_cles_fuite.length ? R.mots_cles_fuite : (R.client ? [R.client] : [])).join(', '), placeholder: 'Nom du cabinet, domaine, ville…', style: 'max-width:480px' });
  const zone = h('div', { style: 'margin-top:10px' });
  const chercher = () => {
    const m = mots.value.split(',').map(x => x.trim()).filter(Boolean); T.majReglages({ mots_cles_fuite: m });
    const r = T.chercherVictimes(m); zone.innerHTML = '';
    if (!r.nb) { zone.append(T.vide('Liste des victimes absente : régénérer le fichier avec Internet pour la télécharger.')); return; }
    zone.append(h('div', { class: 'petit doux', style: 'margin-bottom:6px' }, `${T.nb(r.nb)} victimes publiées dans la liste embarquée${b && b.date ? ' (téléchargée le ' + b.date + ')' : ''}.`));
    zone.append(r.resultats.length ? T.tableau([{ t: 'Victime publiée', v: x => h('b', {}, x.victime) }, { t: 'Groupe', v: x => h('span', { class: 'pill rouge' }, x.groupe) }, { t: 'Date', v: x => T.fcourt(x.date) || x.date }, { t: 'Site', v: x => x.site },
      { t: 'Correspondance', v: x => h('span', { class: 'pill ' + (x.exact ? 'rouge' : 'orange') }, (x.exact ? 'exacte' : 'partielle') + ' : ' + x.mot) }], r.resultats, { defile: false }) : h('div', { class: 'alerte n1' }, h('div', { class: 'ic' }, ''), h('div', {}, 'Aucune victime correspondante dans la liste embarquée.')));
  };
  c.append(T.carte('Sites de fuite des rançongiciels', 'ransomware.live · recherche faite DANS ce fichier', h('div', { class: 'petit doux', style: 'margin-bottom:8px' }, 'Le nom du client n\'est jamais envoyé : la liste publique des victimes (France et récentes) a été téléchargée par DigSpill, la recherche se fait ici.'),
    h('div', { class: 'filtres' }, mots, h('button', { class: 'btn primaire', onclick: chercher }, 'Chercher')), zone));
  chercher();
};

/* ---------------------------------------------------------------- IOC et chasse */
T.ECRANS.ioc = c => {
  const i = T.iocs(), hs = T.hachages(), deja = T.dejaVu();
  c.append(h('h1', {}, 'IOC et chasse'), h('p', { class: 'sous-titre' }, 'Indicateurs de compromission de cet incident, à chercher sur tout le parc.'));
  if (deja.length) c.append(T.carte('Déjà vus dans d\'autres incidents', 'mémoire tenue par DigSpill sur la clé', h('ul', { class: 'lignes' }, deja.map(d => h('li', {}, h('span', { class: 'ic' }, ''),
    h('div', {}, h('div', { class: 'gras' }, `${d.client || 'client ?'} · ${d.poste}`), h('div', { class: 'petit doux' }, `collecte du ${T.fcourt(d.date)} · en commun : ` + d.communs.map(x => `${x.type} ${x.valeur.length > 20 ? x.valeur.slice(0, 16) + '…' : x.valeur}`).join(', ')))))),
    h('div', { class: 'petit doux' }, 'Même attaquant ou même outillage : prévenir les autres clients concernés et comparer les chronologies.')));
  const script = h('pre', { class: 'apercu', style: 'display:none;margin-top:10px' });
  c.append(T.carte('Chasse sur tout le parc (Datto RMM)', 'lecture seule sur les postes', h('div', { class: 'grille g4', style: 'margin-bottom:12px' },
    T.kpi('', i.ip.length, `IP de l'attaquant · + ${i.ipBrute.length} IP de force brute`), T.kpi('', i.hachages.length, 'hachages'), T.kpi('', i.fichiers.length, 'noms de fichiers'), T.kpi('', i.taches.length + i.services.length + i.comptes.length, 'tâches, services, comptes')),
    h('ul', { class: 'lignes' }, h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, 'Télécharger le composant ci-dessous.')), h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, 'Datto RMM : nouveau composant PowerShell, coller le script, exécuter en SYSTEM.')),
      h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, 'Lancer en tâche sur tous les sites. Code retour 1 = correspondance (résumé dans la sortie, CSV dans C:\\ProgramData\\TriageIOC).'))),
    h('div', { class: 'filtres', style: 'margin-top:10px' }, h('button', { class: 'btn primaire', onclick: () => T.telecharger(`Chasse_IOC_${T.identite().poste}.ps1`, '\ufeff' + T.scriptChasse()) }, 'Télécharger le composant (.ps1)'),
      h('button', { class: 'btn', onclick: () => { script.style.display = script.style.display === 'none' ? 'block' : 'none'; script.textContent = T.scriptChasse(); } }, 'Voir le script'),
      h('button', { class: 'btn', onclick: async () => T.toast(await T.copier(T.scriptChasse()) ? 'Script copié' : 'Copie impossible') }, 'Copier')), script));
  c.append(T.carte(`Hachages (${hs.length})`, 'liens externes : le hachage part uniquement si vous cliquez', T.tableau([
    { t: 'Type', l: '70px', v: e => h('span', { class: 'pill gris' }, e.type) }, { t: 'Hachage', v: e => h('span', { class: 'mono', title: e.hash, style: 'font-size:11.5px' }, e.hash.slice(0, 20) + '…') },
    { t: 'Nom', v: e => h('b', {}, e.noms.slice(0, 2).join(', ')) }, { t: 'Source', v: e => h('span', { class: 'petit' }, e.sources.slice(0, 2).join(' · '), e.remarque ? h('div', { class: 'pale' }, e.remarque) : '') },
    { t: 'Preuves', v: e => T.bps(e.preuves, 2) },
    { t: '', l: '170px', v: e => h('div', {}, h('button', { class: 'btn petit', onclick: async () => T.toast(await T.copier(e.hash) ? 'Copié' : 'Copie impossible') }, 'Copier'),
        ' ', h('a', { class: 'btn petit', href: 'https://www.virustotal.com/gui/file/' + e.hash.toLowerCase(), target: '_blank', rel: 'noopener' }, 'VT ↗'),
        ' ', h('a', { class: 'btn petit', href: 'https://bazaar.abuse.ch/browse.php?search=' + (e.type === 'SHA256' ? 'sha256%3A' : e.type === 'SHA1' ? 'sha1%3A' : 'md5%3A') + e.hash.toLowerCase(), target: '_blank', rel: 'noopener' }, 'MB ↗')) }],
    hs, { vide: 'Aucun hachage collecté.' })));
  c.append(h('div', { class: 'grille g2' },
    T.carte('Persistance suspecte', 'tâches et services lancés depuis des dossiers à risque', T.tableau([{ t: 'Type', v: x => x.t }, { t: 'Nom', v: x => h('b', {}, x.nom) }, { t: 'Commande', v: x => h('span', { class: 'mono petit' }, x.cmd) }, { t: 'Preuve', v: x => T.bp(x.id) }],
      [...i.taches.map(t => ({ t: 'Tâche', nom: t.nom, cmd: t.commande, id: t.id })), ...i.services.map(s => ({ t: 'Service', nom: s.nom, cmd: s.chemin, id: s.id }))], { vide: 'Rien de suspect repéré.', defile: false })),
    T.carte('Comptes créés pendant les fenêtres', '', T.tableau([{ t: 'Compte', v: x => h('b', {}, x.nom) }, { t: 'Date', v: x => T.fcourt(x.date) }, { t: 'Preuve', v: x => T.bp(x.id) }], i.comptes, { vide: 'Aucun.', defile: false }))));
};

/* ---------------------------------------------------------------- analyse IA */
T.ECRANS.ia = c => {
  const cleSauv = T.stockage.lire('digspill:cle-anthropic') || '';
  c.append(h('h1', {}, 'Analyse IA (Claude)'), h('p', { class: 'sous-titre' }, 'Claude lit une synthèse filtrée, cite une preuve pour chaque phrase, et ce fichier vérifie chaque citation.'));
  c.append(h('div', { class: 'grille g3', style: 'margin-bottom:16px' },
    T.kpi('', 'Masqué', 'comptes (U1, U2…), noms de fichiers, e-mails, chemins des URL'), T.kpi('', 'Sourcé', 'chaque phrase doit citer [fichier#ligne]'), T.kpi('', 'Vérifié', 'citation existante et valeurs retrouvées dans la ligne')));
  const cle = h('input', { type: 'password', class: 'texte', placeholder: 'sk-ant-…', value: cleSauv, autocomplete: 'off' });
  const memo = h('input', { type: 'checkbox', checked: !!cleSauv });
  const modele = h('select', { class: 'texte' }, [['claude-sonnet-5-5', 'Claude Sonnet 5.5 (conseillé)'], ['claude-opus-5-5', 'Claude Opus 5.5 (plus fin)'], ['claude-haiku-5-5', 'Claude Haiku 5.5 (rapide)']].map(([v, l]) => h('option', { value: v }, l)));
  const apercu = h('pre', { class: 'apercu', style: 'display:none' }), info = h('div', { class: 'petit doux' }), sortie = h('div');
  const voir = () => { const a = T.apercuIA(); apercu.style.display = 'block'; apercu.textContent = a.texte; info.textContent = `${a.ko} Ko · ~${T.nb(a.tokens)} jetons · ${a.comptes} compte(s) pseudonymisé(s). C'est exactement ce qui partira.`; };
  const lancer = async ev => {
    if (!cle.value.trim()) { T.toast('Saisir une clé API Anthropic'); return; }
    if (memo.checked) T.stockage.ecrire('digspill:cle-anthropic', cle.value.trim()); else localStorage.removeItem('digspill:cle-anthropic');
    ev.target.disabled = true; ev.target.textContent = 'Analyse en cours (1 à 2 min)…';
    try { const r = await T.lancerIA(cle.value.trim(), modele.value); T.stockage.ecrire(T.cleStockage() + ':ia', r); afficher(r); }
    catch (e) { sortie.innerHTML = ''; sortie.append(h('div', { class: 'alerte n3' }, h('div', { class: 'ic' }, ''), h('div', {}, 'Échec : ' + e.message))); }
    ev.target.disabled = false; ev.target.textContent = 'Lancer l\'analyse';
  };
  const coller = h('textarea', { class: 'texte', rows: 5, placeholder: 'Ou collez ici une réponse obtenue ailleurs (claude.ai…) pour vérifier ses citations' });
  c.append(T.carte('Lancer', 'la clé reste dans ce navigateur', h('div', { class: 'champs' },
    h('div', { class: 'champ' }, h('label', {}, 'Clé API Anthropic'), cle, h('label', { class: 'petit', style: 'font-weight:400;margin-top:4px' }, memo, ' mémoriser dans ce navigateur')),
    h('div', { class: 'champ' }, h('label', {}, 'Modèle'), modele)),
    h('div', { class: 'filtres', style: 'margin-top:12px' }, h('button', { class: 'btn', onclick: voir }, 'Voir ce qui sera envoyé'), h('button', { class: 'btn primaire', onclick: lancer }, 'Lancer l\'analyse'),
      h('button', { class: 'btn', title: 'Pour utiliser claude.ai sans clé API : copier, coller dans une conversation, puis recoller la réponse ci-dessous', onclick: async () => T.toast(await T.copier(T.PROMPT_SYSTEME + '\n\nSynthese de la collecte :\n' + T.apercuIA().texte) ? 'Consignes + synthèse copiées : à coller dans claude.ai' : 'Copie impossible') }, 'Copier consignes + synthèse')),
    info, apercu,
    h('div', { style: 'margin-top:12px' }, coller, h('button', { class: 'btn', style: 'margin-top:6px', onclick: () => { if (!coller.value.trim()) return; const r = T.verifierIA(coller.value); T.stockage.ecrire(T.cleStockage() + ':ia', r); afficher(r); } }, 'Vérifier ce texte'))));
  c.append(sortie);
  const afficher = r => {
    sortie.innerHTML = '';
    const b = r.bilan, leg = [['verifiee', 'vérifiées', 'vert'], ['a_controler', 'à contrôler', 'orange'], ['non_sourcee', 'non sourcées', 'rouge'], ['citation_invalide', 'citation inconnue', 'rouge'], ['deduction', 'déductions', 'violet']];
    const corps = h('div', { class: 'ia-texte' });
    let ul = null;
    for (const p of r.phrases) {
      if (p.statut === 'titre') { ul = null; corps.append(h('h4', {}, p.texte)); continue; }
      if (p.statut === 'vide') { ul = null; continue; }
      const titre = [p.inconnues && p.inconnues.length ? 'Citation inconnue : ' + p.inconnues.join(', ') : '', p.absentes && p.absentes.length ? 'Valeur absente des preuves citées : ' + p.absentes.join(', ') : '', p.statut === 'non_sourcee' ? 'Aucune preuve citée' : ''].filter(Boolean).join('\n');
      let txt = p.texte; for (const [code, vrai] of Object.entries(r.correspondance || {})) txt = txt.replace(new RegExp('\\b' + code + '\\b', 'g'), `${code} (${vrai})`);
      const morceaux = []; let dernier = 0;
      for (const m of txt.matchAll(/\[([A-Za-z0-9_.]+#\d+)\]/g)) { morceaux.push(txt.slice(dernier, m.index)); morceaux.push(T.bp(m[1])); dernier = m.index + m[0].length; }
      morceaux.push(txt.slice(dernier));
      const span = h('span', { class: 'ia-phrase ' + p.statut, title: titre || 'Vérifiée' }, morceaux.map(x => typeof x === 'string' ? x.replace(/\*\*/g, '') : x));
      if (p.puce) { ul = h('ul', { style: 'margin:4px 0;padding-left:20px' }); corps.append(ul); ul.append(h('li', {}, span)); }
      else if (ul) { ul.lastChild.append(' ', span); } else corps.append(span, ' ');
    }
    sortie.append(T.carte('Résultat', r.modele ? `${r.modele}${r.usage ? ' · ' + T.nb(r.usage.input_tokens) + ' jetons lus' : ''}` : 'texte vérifié',
      h('div', { class: 'filtres' }, leg.filter(([k]) => b[k]).map(([k, l, cl]) => h('span', { class: 'pill ' + cl }, `${l} : ${b[k]}`))),
      h('div', { class: 'petit doux', style: 'margin-bottom:8px' }, 'Survoler une phrase surlignée pour voir le problème. Les pseudonymes sont rétablis ici, localement.'), corps,
      h('div', { class: 'filtres', style: 'margin-top:12px' }, h('button', { class: 'btn', onclick: async () => T.toast(await T.copier(r.texte) ? 'Texte copié' : 'Copie impossible') }, 'Copier le texte brut'))));
  };
  const prec = T.stockage.lire(T.cleStockage() + ':ia'); if (prec) afficher(prec);
};

/* ---------------------------------------------------------------- rapports */
T.ECRANS.rapport = c => {
  c.append(h('h1', {}, 'Rapports'), h('p', { class: 'sous-titre' }, 'Impression ou PDF (« Enregistrer au format PDF » dans la fenêtre d\'impression).'));
  c.append(h('div', { class: 'grille g2' },
    T.carte('Rapport praticien', '1 page, sans jargon', h('ul', { class: 'lignes' }, ['Ce qui s\'est passé, en 5 lignes', 'Ce que le cabinet doit faire', 'Échéance CNIL'].map(x => h('li', {}, h('span', { class: 'ic' }, '•'), x))),
      h('button', { class: 'btn primaire', onclick: () => T.imprimer('praticien') }, 'Imprimer / PDF')),
    T.carte('Rapport technique sourcé', 'pour l\'assureur, l\'expert ou la plainte', h('ul', { class: 'lignes' }, ['Indicateurs, grille, IP, exfiltration, visibilité', 'Chaque constat avec sa preuve [fichier#ligne]', 'Index des fichiers avec leur SHA256'].map(x => h('li', {}, h('span', { class: 'ic' }, '•'), x))),
      h('button', { class: 'btn primaire', onclick: () => T.imprimer('technique') }, 'Imprimer / PDF')),
    T.carte('PV de collecte et certificat d\'intégrité', 'à signer, pour la plainte ou l\'assureur', h('ul', { class: 'lignes' }, ['Qui a collecté, quand, avec quels outils', 'Empreinte du scellé, horodatage, chaîne de possession', 'Cases de signature technicien, cabinet, témoin'].map(x => h('li', {}, h('span', { class: 'ic' }, '•'), x))),
      h('button', { class: 'btn primaire', onclick: () => T.imprimer('pv') }, 'Imprimer / PDF'))));
  c.append(T.carte('Exports', '', h('div', { class: 'filtres' },
    h('button', { class: 'btn', onclick: () => T.telecharger(`${T.D.collecte.nom}_reglages.json`, JSON.stringify(T.stockage.lire(T.cleStockage()) || {}, null, 1), 'application/json') }, 'Réglages (.json)'),
    h('button', { class: 'btn', onclick: () => T.telecharger(`${T.identite().poste}_chronologie.csv`, T.versCsv(T.chronologie().evenements.map(e => ({ Date: T.fdate(e.t), Fin: e.fin ? T.fdate(e.fin) : '', Voie: e.voie, Gravite: e.g, Evenement: e.titre, Detail: e.detail, Fenetre: e.fen, Preuve: e.id })))) }, 'Chronologie (.csv)'),
    h('button', { class: 'btn', onclick: () => T.telecharger(`Chasse_IOC_${T.identite().poste}.ps1`, '\ufeff' + T.scriptChasse()) }, 'Script de chasse (.ps1)')),
    h('div', { class: 'petit doux' }, 'Astuce : enregistrer le fichier de réglages à côté du dossier de collecte. DigSpill le reprendra à la prochaine génération.')));
};

/* ---------------------------------------------------------------- reglages */
T.ouvrirReglages = focus => {
  const R = T.reglages();
  let n = 0;
  const ch = (lib, input, aide) => { const id = 'rg' + (++n); input.id = id; return h('div', { class: 'champ' }, h('label', { for: id }, lib), input, aide ? h('div', { class: 'aide' }, aide) : ''); };
  const f = {
    client: h('input', { value: R.client || '' }), technicien: h('input', { value: R.technicien || '' }),
    decouverte: h('input', { type: 'datetime-local', value: (R.decouverte || '').replace(' ', 'T').slice(0, 16) }),
    debit: h('input', { type: 'number', step: 0.1, value: R.debit_montant_mbps || '' }), taille: h('input', { type: 'number', value: R.taille_base_mo || '' }), compression: h('input', { type: 'number', step: 0.5, value: R.compression || 4 }),
    mots: h('input', { value: (R.mots_cles_fuite || []).join(', ') }),
    lb: h('textarea', { rows: 4 }, (R.liste_blanche || []).map(l => `${l.valeur} ; ${l.note || ''}`).join('\n')),
    fm: h('textarea', { rows: 3 }, (R.fenetres_manuelles || []).map(w => `${w.debut} ; ${w.fin} ; ${w.motif || ''}`).join('\n')),
    notes: h('textarea', { rows: 3 }, R.notes || '')
  };
  const theme = T.theme();
  const choixTheme = h('div', { class: 'seg', role: 'radiogroup', 'aria-label': 'Thème' }, [['sombre', 'Sombre'], ['clair', 'Clair']].map(([v, l]) =>
    h('label', { class: 'pill', style: 'cursor:pointer;padding:4px 10px;margin-right:6px' }, h('input', { type: 'radio', name: 'theme', value: v, checked: theme === v }), ' ', l)));
  const enregistrer = () => {
    T.majReglages({ client: f.client.value.trim(), technicien: f.technicien.value.trim(), decouverte: f.decouverte.value.replace('T', ' '), debit_montant_mbps: f.debit.value, taille_base_mo: f.taille.value, compression: f.compression.value,
      mots_cles_fuite: f.mots.value.split(',').map(x => x.trim()).filter(Boolean),
      liste_blanche: f.lb.value.split('\n').map(l => l.split(';')).filter(p => p[0].trim()).map(p => ({ valeur: p[0].trim(), note: (p[1] || '').trim() })),
      fenetres_manuelles: f.fm.value.split('\n').map(l => l.split(';')).filter(p => p.length >= 2 && T.pdate(p[0]) && T.pdate(p[1])).map(p => ({ debut: p[0].trim(), fin: p[1].trim(), motif: (p[2] || '').trim() })),
      notes: f.notes.value });
    const t = (choixTheme.querySelector('input:checked') || {}).value || 'sombre';
    if (t !== T.theme()) T.appliquerTheme(t);
    T.fermerModale(); T.rafraichir(); T.toast('Réglages enregistrés dans ce navigateur');
  };
  const importer = h('input', { type: 'file', accept: '.json', style: 'display:none', onchange: async e => { try { const j = JSON.parse(await e.target.files[0].text()); T.majReglages(j); T.fermerModale(); T.rafraichir(); T.toast('Réglages importés'); } catch (er) { T.toast('Fichier illisible'); } } });
  T.ouvrirModale(h('div', { class: 'boite', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'tReglages' }, h('header', {}, h('h3', { id: 'tReglages' }, 'Réglages'), h('button', { class: 'fermer', type: 'button', 'aria-label': 'Fermer', onclick: T.fermerModale }, T.ic('fermer'))),
    h('div', { class: 'corps' },
      h('p', { class: 'lbl', style: 'margin-bottom:10px' }, 'Apparence'), choixTheme, h('div', { class: 'aide petit pale', style: 'margin-top:6px' }, 'Le rapport imprimé reste toujours clair.'),
      h('p', { class: 'lbl', style: 'margin:26px 0 10px' }, 'Cet incident'), h('div', { class: 'champs' }, ch('Client (cabinet)', f.client), ch('Technicien', f.technicien), ch("Découverte de l'incident", f.decouverte, 'Point de départ des 72 h CNIL')),
      h('p', { class: 'lbl', style: 'margin:26px 0 10px' }, 'Exfiltration'), h('div', { class: 'champs' }, ch('Débit montant (Mbit/s)', f.debit), ch('Taille base patients (Mo)', f.taille, 'vide = automatique'), ch('Compression (×)', f.compression)),
      h('p', { class: 'lbl', style: 'margin:26px 0 10px' }, 'Sites de fuite'), ch('Mots-clés (séparés par des virgules)', f.mots, 'Nom du cabinet, domaine, ville. Recherche locale uniquement.'),
      h('p', { class: 'lbl', style: 'margin:26px 0 10px' }, 'Liste blanche'), ch('Une IP ou plage par ligne : IP ; note', f.lb, 'ex. 100.64.0.0/10 ; NetBird techniciens'),
      h('p', { class: 'lbl', style: 'margin:26px 0 10px' }, 'Fenêtres en plus'), ch('Une par ligne : début ; fin ; motif', f.fm, 'ex. 2026-11-16 20:00 ; 2026-11-17 04:00 ; signalement du praticien'),
      h('p', { class: 'lbl', style: 'margin:26px 0 10px' }, 'Notes'), ch('Notes libres', f.notes)),
    h('footer', {}, importer, h('button', { class: 'btn', type: 'button', onclick: () => importer.click() }, 'Importer'),
      h('button', { class: 'btn', type: 'button', onclick: () => T.telecharger(`${T.D.collecte.nom}_reglages.json`, JSON.stringify(T.stockage.lire(T.cleStockage()) || {}, null, 1), 'application/json') }, 'Exporter'),
      h('button', { class: 'btn danger', type: 'button', onclick: () => { if (confirm('Effacer les réglages saisis dans ce navigateur ?')) { try { localStorage.removeItem(T.cleStockage()); } catch (e) { /* */ } T.invalider(); T.fermerModale(); T.rafraichir(); } } }, 'Effacer'),
      h('button', { class: 'btn primaire', type: 'button', onclick: enregistrer }, 'Enregistrer'))));
  if (focus === 'decouverte') f.decouverte.focus();
};

/* ---------------------------------------------------------------- impression */
T.imprimer = type => {
  const z = T.$('#impression'); z.innerHTML = T.rapportHtml(type);
  document.body.classList.add('imprime');
  const fin = () => { document.body.classList.remove('imprime'); window.removeEventListener('afterprint', fin); };
  window.addEventListener('afterprint', fin);
  setTimeout(() => { window.print(); setTimeout(fin, 500); }, 50);
};
T.rapportHtml = type => {
  const v = T.vue(), k = v.kpi, id = T.identite(), R = T.reglages(), ex = T.exfil(), s = T.sante(), ip = T.analyseIp();
  const tete = T.logoSvg('logo-imp', '#111113', '#D71921') + `<h1>Incident de sécurité – ${esc(R.client || id.poste)}</h1><div class="note">Poste ${esc(id.poste)} · collecte du ${esc(T.flong(id.date))} · rapport du ${esc(T.flong(new Date()))}${R.technicien ? ' · technicien ' + esc(R.technicien) : ''}</div>`;
  const cnil = `<div class="bloc"><b>Notification CNIL (art. 33 RGPD)</b> : découverte le ${v.cnil ? esc(T.flong(v.cnil.decouverte)) : 'à renseigner'}${v.cnil ? ` · échéance des 72 h : <b>${esc(T.flong(v.cnil.echeance))}</b>` : ''}.<br><span class="note">La décision de notifier et d'informer les patients (art. 34) appartient au cabinet (responsable de traitement) et à son DPO.</span></div>`;
  const pire = ex.fenetres.reduce((m, f) => (!m || f.envoye > m.envoye) ? f : m, null);
  if (type === 'praticien') {
    const l = [];
    if (k.sessions) l.push(`Des connexions à distance ont été faites sur ce poste depuis Internet (${k.pays.map(T.nomPays).join(', ') || 'pays non déterminé'}).`);
    if (k.chiffres) l.push(`${T.nb(k.chiffres)} fichiers ont été chiffrés par un rançongiciel.`);
    if (pire && ['PLAUSIBLE', 'PARTIELLE'].includes(pire.niveau)) l.push(`Le volume envoyé sur Internet pendant l'intrusion (${T.nb(pire.envoye)} Mo) rend possible une copie des données patients.`);
    else if (pire) l.push('Les volumes mesurés ne permettent pas une copie complète de la base patients depuis ce poste.');
    if (k.outils.length) l.push(`Des outils sensibles ont été lancés pendant l'intrusion (${esc(k.outils.slice(0, 6).join(', '))}).`);
    if (s.categories.length) l.push(`Données potentiellement concernées : ${esc(s.categories.map(x => x.categorie).slice(0, 4).join(', '))} (à confirmer).`);
    const a = ['Ne pas rallumer ni utiliser le poste concerné sans accord du technicien.', 'Changer les mots de passe listés par le technicien (logiciels en ligne, messagerie, banque).', 'Prévenir votre assureur cyber ; un dépôt de plainte est conseillé.', 'Décider avec votre DPO de la notification CNIL avant l\'échéance.'];
    return tete + cnil + `<h2>Ce qui s'est passé</h2><div class="bloc">${l.map(x => `<div>${esc(x)}</div>`).join('') || 'Analyse en cours.'}</div><h2>Ce que vous devez faire</h2><div class="bloc">${a.map(x => `<div>${esc(x)}</div>`).join('')}</div><p class="note">Ce document résume une analyse technique. Le rapport technique détaillé et sourcé est disponible auprès de votre prestataire.</p>`;
  }
  const t = (cols, lignes) => `<table><tr>${cols.map(c => `<th>${esc(c[0])}</th>`).join('')}</tr>${lignes.map(r => `<tr>${cols.map(c => `<td>${c[1](r)}</td>`).join('')}</tr>`).join('')}</table>`;
  const pid = x => `<span class="pid">${esc(x || '')}</span>`;
  let html = tete + cnil;
  html += `<h2>Indicateurs</h2><div class="bloc">Sessions depuis Internet / VPN : <b>${k.sessions}</b> · IP publiques avec connexion réussie : <b>${k.ipSucces}</b> · échecs : <b>${T.nb(k.echecs)}</b> · fichiers chiffrés : <b>${T.nb(k.chiffres)}</b> · envoi maximal : <b>${T.nb(k.envoyeMax)} Mo</b> · anti-forensique : <b>${k.anti}</b> · Defender : <b>${k.defender}</b></div>`;
  html += `<h2>Grille de vérification par canal</h2>` + t([['Statut', g => esc(g.statut)], ['Canal', g => esc(g.canal)], ['Constat', g => esc(g.constat)], ['Preuve', g => pid(g.id)]], v.grille);
  html += `<h2>IP et origine des connexions</h2>` + t([['IP', e => `<b>${esc(e.ip)}</b>`], ['Pays', e => esc(T.nomPays(e.pays))], ['Opérateur', e => esc(`${e.operateur || ''} ${e.categorie ? '(' + e.categorie + ')' : ''}`)], ['Succès', e => e.succes], ['Échecs', e => e.echecs], ['Période', e => esc(`${T.fcourt(e.premier)} → ${T.fcourt(e.dernier)}`)], ['Attention', e => esc(e.raisons.join(', '))], ['Preuves', e => pid(e.preuves.slice(0, 2).join(' '))]], ip.ips.filter(e => e.type !== 'Privee' && (e.succes || e.score >= 3)).slice(0, 40));
  const b = T.D.bases || {};
  html += `<p class="note">Géolocalisation : ${b.asn ? esc(b.asn.source + ' du ' + b.asn.date) : 'non disponible'}${b.ville ? ' ; ' + esc(b.ville.source) : ''}. Listes publiques à leur date de téléchargement.</p>`;
  html += `<h2>Exfiltration : volumes et plausibilité</h2>` + ex.fenetres.map(f => `<div class="bloc"><b>${esc(f.id)}</b> ${esc(T.fcourt(f.debut))} → ${esc(T.fcourt(f.fin))} (${f.duree} min) – <b>${esc(T.NIVEAUX[f.niveau].lib)}</b><br>${esc(f.motif)}<ul>${f.constats.map(x => `<li>${esc(x)}</li>`).join('')}</ul>${pid('preuves : ' + [f.preuveFenetre, ...f.preuves.slice(0, 6)].join(' '))}</div>`).join('');
  html += `<p class="note">Hypothèses (déductions) : base ${T.nb(ex.hyp.taille)} Mo, compression ×${esc(ex.hyp.compression)}, débit montant ${ex.hyp.debit ? esc(ex.hyp.debit) + ' Mbit/s' : 'non renseigné'}. ${T.LIMITES_EXFIL.map(esc).join(' ')}</p>`;
  const vis = T.visibilite();
  html += `<h2>Visibilité des sources</h2>` + vis.fenetres.map(w => `<div class="bloc"><b>${esc(w.id)}</b> : ${w.taux} % des sources couvrent la fenêtre. ${esc(w.sources.filter(x => x.statut !== 'couverte').map(x => x.source + ' : ' + x.statut).join(' · '))}</div>`).join('');
  if (vis.anti.length) html += `<h3>Traces d'anti-forensique</h3>` + t([['Date', a => esc(a.date)], ['Trace', a => esc(a.trace)], ['Détail', a => esc(a.detail)], ['Preuve', a => pid(a.id)]], vis.anti);
  html += `<h2>Données de santé potentiellement concernées</h2>` + t([['Catégorie (déduction)', x => esc(x.categorie)], ['Logiciels / sources', x => esc(x.logiciels.join(', '))]], s.categories) + `<p class="note">Catégories déduites des noms de fichiers et de sites : à confirmer avec le cabinet.</p>`;
  html += `<h2>IOC (hachages)</h2>` + t([['Type', e => e.type], ['Hachage', e => pid(e.hash)], ['Nom', e => esc(e.noms.slice(0, 2).join(', '))], ['Source', e => esc(e.sources.slice(0, 2).join(', '))]], T.hachages().slice(0, 60));
  const ia = T.stockage.lire(T.cleStockage() + ':ia');
  if (ia) html += `<h2>Analyse assistée (Claude), phrases vérifiées automatiquement</h2><div class="bloc">${ia.phrases.filter(p => p.statut !== 'vide').map(p => p.statut === 'titre' ? `<h3>${esc(p.texte)}</h3>` : `<div style="border-left:3px solid ${{ verifiee: '#12b76a', a_controler: '#f79009', deduction: '#7a5af8' }[p.statut] || '#f04438'};padding-left:6px;margin:2px 0">${esc(p.texte)}</div>`).join('')}</div><p class="note">Vert = citation vérifiée ; orange = à contrôler ; violet = déduction déclarée ; rouge = non sourcé.</p>`;
  const cites = new Set(); v.grille.forEach(g => cites.add(g.id)); ip.ips.slice(0, 40).forEach(e => e.preuves.slice(0, 2).forEach(x => cites.add(x))); ex.fenetres.forEach(f => [f.preuveFenetre, ...f.preuves.slice(0, 6)].forEach(x => cites.add(x)));
  const fich = [...new Set([...cites].filter(x => x && x.includes('#')).map(x => x.split('#')[0]))].sort();
  html += `<h2>Index des preuves citées</h2>` + t([['Identifiant', f => esc(f)], ['Fichier source', f => esc((T.infoFichier(f) || {}).chemin || '')], ['SHA256 (manifeste)', f => pid((T.infoFichier(f) || {}).sha256 || 'non listé')]], fich);
  html += `<p class="note">Chaque identifiant [fichier#n] désigne la ligne n (sous l'en-tête) du CSV de la collecte ou de l'analyse ; l'intégrité se vérifie avec le manifeste SHA256. Ce rapport aide l'analyse : il ne remplace pas la conclusion de l'analyste.</p>`;
  return html;
};

/* ======================================================================== demarrage */
T.demarrer = () => {
  const brut = (document.getElementById('donnees') || {}).textContent || '';
  if (!brut.trim()) return T.ecranOuverture();
  let d; try { d = JSON.parse(brut); } catch (e) { document.body.innerHTML = '<p style="padding:30px">Données illisibles dans ce fichier.</p>'; return; }
  if (d.chiffre) return T.ecranMotDePasse(d);
  T.lancer(d);
};
T.lancer = d => {
  T.charger(d); T.rendreSquelette(); T.majEntete();
  T.aller(location.hash || 'resume');
};
/** fichier ouvert sans donnees (modele) : lecture directe d'un dossier de collecte */
T.ecranOuverture = () => {
  const app = T.$('#app');
  const choix = h('input', { type: 'file', webkitdirectory: true, multiple: true, style: 'display:none', onchange: async e => {
    const fichiers = [...e.target.files], d = { genere_le: T.fdate(new Date()).slice(0, 16), generateur: 'lecture directe du dossier (navigateur)', collecte: { nom: '', analyse: false }, fichiers: {}, bases: {}, listes: {}, memoire: {} };
    for (const f of fichiers) {
      const p = (f.webkitRelativePath || f.name).split('/');
      const i = p.findIndex(x => /_\d{8}_\d{6}(_leger)?(_analyse)?$/.test(x)); if (i < 0) continue;
      const racine = p[i], analyse = racine.endsWith('_analyse'), prof = p.length - i - 1;
      if (prof > 2 || !/\.(csv|txt)$/i.test(f.name) || f.size > 30e6 || /^listing_complet/i.test(f.name)) continue;
      if (!analyse && !d.collecte.nom) d.collecte.nom = racine;
      if (analyse) d.collecte.analyse = true;
      let cle = f.name.toLowerCase().endsWith('.csv') ? f.name.slice(0, -4) : f.name;
      if (d.fichiers[cle]) cle = 'a.' + cle;
      d.fichiers[cle] = { chemin: p.slice(i).join('\\'), taille: f.size, texte: await f.text() };
    }
    if (!d.collecte.nom) { T.toast('Aucun dossier de collecte (POSTE_AAAAMMJJ_HHMMSS) dans la sélection'); return; }
    T.lancer(d);
  } });
  app.innerHTML = '';
  app.append(h('div', { class: 'accueil' }, h('div', { class: 'brand', style: 'color:var(--fg)' }, T.logo()), h('h1', { class: 'recit-titre' }, 'Ouvrir une collecte'),
    h('p', { class: 'doux' }, 'Ce fichier ne contient pas encore de collecte. Le plus simple : DigSpill.exe › Analyser une collecte.'),
    h('div', { class: 'zone' }, h('p', {}, 'Ou ouvrir directement le dossier Collecte, qui contient POSTE_date et POSTE_date_analyse.'), h('button', { class: 'btn primaire', onclick: () => choix.click() }, 'Choisir le dossier'), choix,
      h('p', { class: 'petit pale' }, 'Lecture locale dans le navigateur. Sans DigSpill.exe : pas de pays des IP, ni listes noires, ni sites de fuite.'))));
};
/** fichier protege par mot de passe : PBKDF2-SHA256 + AES-256-CBC + HMAC-SHA256 (chiffrer puis authentifier) */
T.ecranMotDePasse = d => {
  const app = T.$('#app'), mdp = h('input', { type: 'password', class: 'texte', style: 'max-width:300px', placeholder: 'Mot de passe', autofocus: true }), msg = h('div', { class: 'petit', style: 'margin-top:8px;color:#b42318' });
  const ouvrir = async () => {
    msg.textContent = 'Déchiffrement…';
    try {
      const b64 = s => Uint8Array.from(atob(s), c => c.charCodeAt(0)), sel = b64(d.sel), iv = b64(d.iv), donnees = b64(d.donnees), mac = b64(d.mac);
      const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(mdp.value), 'PBKDF2', false, ['deriveBits']);
      const bits = new Uint8Array(await crypto.subtle.deriveBits({ name: 'PBKDF2', salt: sel, iterations: d.iterations, hash: 'SHA-256' }, base, 512));
      const cleMac = await crypto.subtle.importKey('raw', bits.slice(32), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
      const aVerifier = new Uint8Array(iv.length + donnees.length); aVerifier.set(iv); aVerifier.set(donnees, iv.length);
      if (!await crypto.subtle.verify('HMAC', cleMac, mac, aVerifier)) { msg.textContent = 'Mot de passe incorrect (ou fichier modifié).'; return; }
      const cleAes = await crypto.subtle.importKey('raw', bits.slice(0, 32), { name: 'AES-CBC' }, false, ['decrypt']);
      const clair = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, cleAes, donnees);
      T.lancer(JSON.parse(new TextDecoder().decode(clair)));
    } catch (e) { msg.textContent = 'Déchiffrement impossible : ' + e.message; }
  };
  mdp.addEventListener('keydown', e => { if (e.key === 'Enter') ouvrir(); });
  app.innerHTML = '';
  app.append(h('div', { class: 'accueil' }, h('div', { class: 'brand', style: 'color:var(--fg)' }, T.logo()), h('h1', { class: 'recit-titre' }, 'Fichier protégé'),
    h('p', { class: 'doux' }, `Collecte ${d.collecte || ''} · généré le ${d.genere_le || '?'}`), h('div', { class: 'zone' }, mdp, ' ', h('button', { class: 'btn primaire', onclick: ouvrir }, 'Ouvrir'), msg)));
};
/* ---------------------------------------------------------------- isoler le poste : procedure (ce fichier ne coupe rien lui-meme) */
T.ouvrirIsoler = () => {
  const v = T.vue();
  const fermer = h('button', { class: 'fermer', type: 'button', 'aria-label': 'Fermer', onclick: T.fermerModale }, T.ic('fermer'));
  T.ouvrirModale(h('div', { class: 'boite isoler', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'tIsoler' },
    h('header', {}, h('h3', { id: 'tIsoler' }, 'Isoler le poste du réseau'), fermer),
    h('div', { class: 'corps' },
      v.actives.length ? h('p', { class: 'constat' }, `Une connexion vers ${v.actives.map(a => a.ip).join(', ')} était encore ouverte au moment de la collecte.`) : '',
      v.actives.map(a => h('div', { class: 'petit doux' }, `${(a.processus || '?').split('\\').pop()} → ${a.ip} `, T.bps(a.preuves.filter(x => x.startsWith('tcp_')), 2))),
      h('p', { class: 'lbl', style: 'margin:22px 0 8px' }, 'Procédure'),
      h('ol', {},
        h('li', {}, h('b', {}, 'Débrancher le câble réseau'), ' du poste, ou couper son port sur le switch.'),
        h('li', {}, h('b', {}, 'Couper le Wi-Fi'), ' : mode avion, ou interrupteur Wi-Fi du portable.'),
        h('li', {}, h('b', {}, 'Ne pas éteindre le poste'), ' ni le redémarrer : la mémoire garde des traces utiles.'),
        h('li', {}, h('b', {}, "Noter l'heure de l'isolement"), ' : elle ira dans le PV de collecte.')),
      h('p', { class: 'petit pale', style: 'margin-top:16px' }, "Ce fichier fonctionne hors ligne : il n'agit pas sur le poste.")),
    h('footer', {}, h('button', { class: 'btn', type: 'button', onclick: T.fermerModale }, 'Fermer'),
      h('button', { class: 'btn primaire', type: 'button', onclick: () => { T.cocherAction('isoler', true); T.fermerModale(); T.rafraichir(); T.toast(`Isolement noté à ${T.hm(new Date())}`); } }, "C'est fait : noter l'heure"))));
};

/* ---------------------------------------------------------------- recherche Ctrl K */
const sansAccent = s => String(s || '').normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase();
T.indexRecherche = () => T.memo('indexRecherche', () => {
  const L = [], ajouter = (type, texte, cible) => L.push(Object.assign({ type, texte, cle: sansAccent(type + ' ' + texte) }, cible));
  T.ONGLETS.forEach(o => ajouter('Onglet', o.nom, { aller: o.id }));
  T.RUBRIQUES.details.forEach(([k, l]) => ajouter('Rubrique', `Détails · ${l}`, { aller: 'details/' + k }));
  T.RUBRIQUES.preuves.forEach(([k, l]) => ajouter('Rubrique', `Preuves · ${l}`, { aller: 'preuves/' + k }));
  for (const f of T.fenetres()) { const r = T.recit(f.id); if (r) r.etapes.forEach(s => ajouter('Étape', `${f.id} · ${T.hm(s.t)} · ${s.titre}`, { aller: 'chrono/' + f.id, etape: s.cle, plus: s.sens })); }
  for (const e of T.analyseIp().ips.filter(x => x.type !== 'Privee')) ajouter('IP', `${e.ip}${e.pays ? ' · ' + T.nomPays(e.pays) : ''}${e.succes ? ` · ${e.succes} connexion(s) réussie(s)` : ''}${e.echecs ? ` · ${T.nb(e.echecs)} échecs` : ''}${e.active ? ' · connexion ouverte' : ''}`, { aller: 'details/ip', preuve: e.preuves[0] });
  for (const p of T.memoireVive().procs.filter(x => x.niveau >= 1)) ajouter('Processus', `${p.nom} · PID ${p.pid} · en mémoire${p.indices.length ? ' · ' + p.indices[0] : ''}`, { aller: 'details/memoire', preuve: p.id });
  for (const e of T.hachages()) ajouter('Empreinte', `${e.hash} · ${e.noms.slice(0, 2).join(', ')}`, { aller: 'details/ioc', preuve: e.preuves[0] });
  const comptes = new Set();
  T.analyseIp().ips.forEach(e => (e.comptes || []).forEach(c => comptes.add(String(c).split('\\').pop())));
  T.chronologie().evenements.forEach(e => { if (e.compte) comptes.add(String(e.compte).split('\\').pop()); });
  T.iocs().comptes.forEach(c => comptes.add(c.nom));
  [...comptes].filter(c => c && c !== '-' && c.length > 1).sort().forEach(c => ajouter('Compte', c, { recherche: c.toLowerCase() }));
  return L;
});
T.ouvrirPalette = () => {
  const p = T.$('#palette'); if (!p) return;
  T._focusPalette = document.activeElement; p.innerHTML = '';
  const input = h('input', { type: 'text', placeholder: 'IP, empreinte, compte, preuve (fichier#n), étape, rubrique', 'aria-label': 'Rechercher', autocomplete: 'off', spellcheck: 'false', role: 'combobox', 'aria-expanded': 'true', 'aria-controls': 'resultatsRecherche' });
  const ul = h('ul', { role: 'listbox', id: 'resultatsRecherche' });
  let res = [], sel = 0;
  const choisir = r => {
    if (!r) return; T.fermerPalette();
    if (r.idPreuve) { T.ouvrirPreuve(r.idPreuve); return; }
    if (r.recherche) { T.filtreChrono.q = r.recherche; T.aller('details/evenements'); return; }
    if (r.etape) T.etapeOuverte = r.etape;
    if (r.aller) T.aller(r.aller);
    if (r.preuve && !r.etape) setTimeout(() => T.ouvrirPreuve(r.preuve), 60);
  };
  const rendre = () => {
    const q = sansAccent(input.value.trim()), idx = T.indexRecherche();
    const mots = q.split(/\s+/).filter(Boolean);
    const ORDRE = ['IP', 'Empreinte', 'Compte', 'Étape', 'Rubrique', 'Onglet'], rang = x => (sansAccent(x.texte).startsWith(q) ? 0 : 10) + ORDRE.indexOf(x.type);
    res = mots.length ? idx.filter(x => mots.every(m => x.cle.includes(m) || sansAccent(x.plus || '').includes(m))).map((x, i) => [x, i]).sort((a, b) => rang(a[0]) - rang(b[0]) || a[1] - b[1]).map(a => a[0]).slice(0, 50)
      : idx.filter(x => x.type === 'Étape' && x.aller === 'chrono/' + ((T.fenetreGrave() || {}).id) || x.type === 'Rubrique').slice(0, 50);
    const brut = input.value.trim();
    if (/^[\w.]+#\d+$/.test(brut) && T.preuve(brut)) res.unshift({ type: 'Preuve', texte: `${brut} · ${T.texteLigne(T.preuve(brut), 90)}`, idPreuve: brut });
    sel = Math.min(sel, Math.max(0, res.length - 1));
    ul.innerHTML = '';
    res.forEach((r, i) => ul.append(h('li', { role: 'none' }, h('button', { type: 'button', role: 'option', id: 'rr' + i, 'aria-selected': String(i === sel), class: i === sel ? 'sel' : '', tabindex: '-1', onclick: () => choisir(r), onmousemove: () => { if (sel !== i) { sel = i; marquer(); } } }, h('span', { class: 'lbl' }, r.type), h('span', { class: 'res' }, r.texte)))));
    if (!res.length) ul.append(h('li', { class: 'vide', style: 'padding:10px 12px' }, 'Aucun résultat.'));
    input.setAttribute('aria-activedescendant', res.length ? 'rr' + sel : '');
  };
  const marquer = () => { T.$$('button', ul).forEach((b, i) => { b.classList.toggle('sel', i === sel); b.setAttribute('aria-selected', String(i === sel)); }); input.setAttribute('aria-activedescendant', 'rr' + sel); const b = T.$('#rr' + sel); if (b) b.scrollIntoView({ block: 'nearest' }); };
  input.addEventListener('input', () => { sel = 0; rendre(); });
  input.addEventListener('keydown', e => {
    if (e.key === 'ArrowDown') { e.preventDefault(); sel = Math.min(res.length - 1, sel + 1); marquer(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); sel = Math.max(0, sel - 1); marquer(); }
    else if (e.key === 'Enter') { e.preventDefault(); choisir(res[sel]); }
    else if (e.key === 'Tab') e.preventDefault();
  });
  p.append(h('div', { class: 'boite', role: 'dialog', 'aria-modal': 'true', 'aria-label': 'Recherche' }, input, ul, h('div', { class: 'aide' }, '↑ ↓ pour choisir · Entrée pour ouvrir · Échap pour fermer')));
  p.classList.add('ouvert'); rendre(); input.focus();
};
T.fermerPalette = () => { const p = T.$('#palette'); if (!p) return; p.classList.remove('ouvert'); p.innerHTML = ''; if (T._focusPalette && T._focusPalette.focus) T._focusPalette.focus(); };

try { if (localStorage.getItem('digspill:theme') === 'clair') document.documentElement.classList.add('clair'); } catch (e) { /* stockage indisponible */ }
document.addEventListener('DOMContentLoaded', T.demarrer);
