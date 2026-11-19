/* ============================================================================
   05_vues.js : ecrans de l'interface
   ============================================================================ */
'use strict';
const h = T.h, esc = T.esc;

T.ONGLETS = [
  { id: 'vue', ic: '🏠', nom: "Vue d'ensemble" }, { id: 'chrono', ic: '🕒', nom: 'Chronologie' }, { id: 'ip', ic: '🌍', nom: 'IP et pays' },
  { id: 'exfil', ic: '📤', nom: 'Exfiltration' }, { id: 'visibilite', ic: '👁️', nom: 'Visibilité' }, { id: 'sante', ic: '🏥', nom: 'Santé et RGPD' },
  { id: 'fuites', ic: '🔑', nom: 'Identifiants et fuites' }, { id: 'ioc', ic: '🧬', nom: 'IOC et chasse' }, { id: 'ia', ic: '🤖', nom: 'Analyse IA' },
  { id: 'rapport', ic: '🖨️', nom: 'Rapports' }];
T.onglet = 'vue';

/* ---------------------------------------------------------------- petits composants */
T.toast = (m, ms = 2600) => { const t = h('div', { class: 'toast' }, m); document.body.append(t); setTimeout(() => t.remove(), ms); };
T.bp = id => id ? h('button', { class: 'preuve', 'data-preuve': id, title: 'Voir la ligne source' }, id) : '';
T.bps = (ids, max = 3) => { ids = (ids || []).filter(Boolean); return h('span', {}, ids.slice(0, max).map(i => [T.bp(i), ' ']), ids.length > max ? h('span', { class: 'pale petit' }, `+${ids.length - max}`) : ''); };
T.pillStatut = s => h('span', { class: 'pill st-' + String(s || '').replace(/\s+/g, '_') }, s || '?');
T.pillNiveau = n => { const x = T.NIVEAUX[n] || T.NIVEAUX.INCONNU; return h('span', { class: 'pill st-' + n }, x.icone + ' ' + x.lib); };
T.carte = (titre, aide, ...contenu) => h('div', { class: 'carte' }, titre ? h('h2', {}, titre, aide ? h('span', { class: 'aide' }, aide) : '') : '', ...contenu);
T.vide = txt => h('div', { class: 'vide' }, txt || 'Rien à afficher.');
T.tableau = (cols, lignes, opts = {}) => {
  if (!lignes.length) return T.vide(opts.vide);
  const t = h('table', { class: 'tableau' }, h('thead', {}, h('tr', {}, cols.map(c => h('th', { style: c.l ? `width:${c.l}` : null }, c.t)))),
    h('tbody', {}, lignes.slice(0, opts.max || 1000).map(r => h('tr', { class: opts.cls ? opts.cls(r) : null }, cols.map(c => { const v = c.v(r); return h('td', { class: c.c || null }, v === undefined || v === null ? '' : v); })))));
  const enveloppe = h('div', { class: opts.defile === false ? '' : 'defile', style: opts.hauteur ? `max-height:${opts.hauteur}` : null }, t);
  return lignes.length > (opts.max || 1000) ? h('div', {}, enveloppe, h('div', { class: 'pale petit' }, `${T.nb(lignes.length - (opts.max || 1000))} ligne(s) non affichée(s)`)) : enveloppe;
};
T.kpi = (ic, valeur, libelle, cls = '', titre = '') => h('div', { class: 'kpi ' + cls, title: titre || null }, h('div', { class: 'ic' }, ic), h('div', {}, h('b', {}, valeur), h('span', {}, libelle)));
T.nomPays = cc => (T.MONDE.noms && T.MONDE.noms[cc]) || cc || '';

/* ---------------------------------------------------------------- panneau de preuve */
T.ouvrirPreuve = (id, contexte) => {
  const p = T.$('.panneau'), v = T.$('.voile'), c = T.$('.panneau .corps');
  const nom = String(id).split('#')[0], r = T.preuve(id), inf = T.infoFichier(nom);
  c.innerHTML = '';
  if (contexte) c.append(h('div', { class: 'carte' }, h('div', { class: 'gras' }, contexte.titre), h('div', { class: 'pale petit' }, T.flong(contexte.t), contexte.fen ? ` · fenêtre ${contexte.fen}` : ''), h('div', { class: 'petit', style: 'margin-top:6px' }, contexte.detail)));
  c.append(h('dl', {}, h('dt', {}, 'Preuve'), h('dd', { class: 'mono' }, id),
    h('dt', {}, 'Fichier'), h('dd', { class: 'mono' }, inf ? inf.chemin : nom),
    h('dt', {}, 'Ligne du fichier'), h('dd', {}, String(id).includes('#') ? `${+String(id).split('#')[1] + 1} (en-tête = ligne 1)` : '–'),
    h('dt', {}, 'SHA256 (manifeste)'), h('dd', { class: 'mono', style: 'font-size:11px' }, inf && inf.sha256 ? inf.sha256 : 'non listé dans le manifeste'),
    inf && inf.tronque ? [h('dt', {}, '⚠️'), h('dd', {}, 'Fichier tronqué à la génération (trop volumineux) : seules les premières lignes sont présentes.')] : ''));
  if (r) {
    c.append(h('h3', { style: 'margin:16px 0 8px;font-size:14px' }, 'Contenu de la ligne'));
    c.append(h('dl', {}, Object.entries(r).filter(([k]) => k !== '_id').map(([k, val]) => [h('dt', {}, k), h('dd', { class: /chemin|path|url|commandline|sha|hash/i.test(k) ? 'mono' : '' }, val || '–')])));
  } else if (id && !String(id).includes('#')) {
    c.append(h('pre', { class: 'apercu' }, T.texte(id).slice(0, 20000) || 'Fichier texte absent.'));
  }
  c.append(h('div', { style: 'margin-top:14px' }, h('button', { class: 'btn', onclick: async () => T.toast(await T.copier(id) ? 'Identifiant copié' : 'Copie impossible') }, '📋 Copier l\'identifiant')));
  p.classList.add('ouvert'); v.classList.add('ouvert');
};
T.fermerPanneau = () => { T.$('.panneau').classList.remove('ouvert'); T.$('.voile').classList.remove('ouvert'); };

/* ---------------------------------------------------------------- squelette */
T.rendreSquelette = () => {
  const app = T.$('#app'); app.innerHTML = '';
  if (T.D.demo) app.append(h('div', { class: 'demo-bandeau' }, '🧪 Démonstration : collecte FICTIVE (adresses de documentation, cabinet inventé). Aucune donnée réelle.'));
  app.append(h('header', { class: 'entete' },
    h('div', { class: 'logo' }, '🛡️', h('span', {}, 'DigSpill'), h('small', {}, 'v' + T.VERSION)),
    h('div', { class: 'ident', id: 'ident' }), h('div', { class: 'espace' }),
    h('button', { class: 'puce-cnil', id: 'puceCnil', onclick: () => T.aller('sante') }),
    h('button', { class: 'btn-entete', onclick: () => T.ouvrirReglages() }, '⚙️ Réglages'),
    h('button', { class: 'btn-entete', onclick: () => T.aller('rapport') }, '🖨️ Rapports')));
  const menu = h('nav', { class: 'menu' }, T.ONGLETS.map(o => h('button', { 'data-onglet': o.id, onclick: () => T.aller(o.id) }, h('span', { class: 'ic' }, o.ic), o.nom, h('span', { class: 'badge', id: 'badge-' + o.id }))),
    h('div', { class: 'sep' }), h('div', { class: 'pied' }, `Généré le ${T.D.genere_le || '?'}`, h('br'), `par ${T.D.generateur || '?'}`, h('br'), 'Fichier autonome : aucune donnée ne sort sans action de votre part.'));
  app.append(h('div', { class: 'cadre' }, menu, h('main', { id: 'contenu' })));
  app.append(h('div', { class: 'voile', onclick: T.fermerPanneau }), h('aside', { class: 'panneau' }, h('header', {}, h('h3', {}, '🔎 Preuve'), h('button', { class: 'fermer', onclick: T.fermerPanneau }, '✕')), h('div', { class: 'corps' })));
  app.append(h('div', { class: 'modale', id: 'modale' }));
  document.addEventListener('click', e => { const b = e.target.closest('[data-preuve]'); if (b) { e.preventDefault(); T.ouvrirPreuve(b.dataset.preuve); } });
  document.addEventListener('keydown', e => { if (e.key === 'Escape') { T.fermerPanneau(); T.$('#modale').classList.remove('ouvert'); } });
};
T.majEntete = () => {
  const id = T.identite(), R = T.reglages(), v = T.vue();
  T.$('#ident').innerHTML = '';
  T.$('#ident').append(h('b', {}, R.client || id.poste), h('span', {}, `Poste ${id.poste} · collecte du ${T.flong(id.date)}${id.leger ? ' · collecte légère' : ''}`));
  const p = T.$('#puceCnil'); p.className = 'puce-cnil';
  if (!v.cnil) p.textContent = '⏱️ CNIL : date de découverte à saisir';
  else if (v.cnil.restantH < 0) { p.classList.add('depasse'); p.textContent = `⏱️ CNIL : délai de 72 h dépassé (échéance ${T.fcourt(v.cnil.echeance)})`; }
  else { if (v.cnil.restantH < 24) p.classList.add('urgent'); p.textContent = `⏱️ CNIL : ${Math.floor(v.cnil.restantH)} h ${p2m(v.cnil.restantH)} restantes (échéance ${T.fcourt(v.cnil.echeance)})`; }
  const nIndices = v.grille.filter(g => g.statut === 'INDICE').length;
  T.$('#badge-vue').innerHTML = ''; if (v.alertes.length) T.$('#badge-vue').append(h('span', { class: 'pill rouge' }, v.alertes.length));
  T.$('#badge-ip').innerHTML = ''; if (v.kpi.ipSucces) T.$('#badge-ip').append(h('span', { class: 'pill rouge' }, v.kpi.ipSucces));
  T.$('#badge-exfil').innerHTML = ''; const pl = T.exfil().fenetres.filter(f => f.niveau === 'PLAUSIBLE').length; if (pl) T.$('#badge-exfil').append(h('span', { class: 'pill rouge' }, pl));
  T.$('#badge-ioc').innerHTML = ''; if (v.deja.length) T.$('#badge-ioc').append(h('span', { class: 'pill orange' }, '🔁 ' + v.deja.length));
  void nIndices;
};
const p2m = hh => String(Math.floor((hh % 1) * 60)).padStart(2, '0') + ' min';

T.aller = id => {
  T.onglet = id; location.hash = id;
  T.$$('nav.menu button').forEach(b => b.classList.toggle('actif', b.dataset.onglet === id));
  Object.values(T._graphs).forEach(g => { try { g.dispose(); } catch (e) { /* */ } }); T._graphs = {};
  const c = T.$('#contenu'); c.innerHTML = '';
  try { (T.ECRANS[id] || T.ECRANS.vue)(c); } catch (e) { console.error(e); c.append(h('div', { class: 'alerte n3' }, h('div', { class: 'ic' }, '⚠️'), h('div', {}, 'Erreur d\'affichage : ' + e.message))); }
  window.scrollTo(0, 0);
};
T.rafraichir = () => { T.invalider(); T.majEntete(); T.aller(T.onglet); };

/* ======================================================================== ECRANS */
T.ECRANS = {};

/* ---------------------------------------------------------------- vue d'ensemble */
T.ECRANS.vue = c => {
  const v = T.vue(), k = v.kpi, id = T.identite(), R = T.reglages();
  c.append(h('h1', {}, "Vue d'ensemble"), h('p', { class: 'sous-titre' }, `${R.client ? R.client + ' · ' : ''}poste ${id.poste} · ${T.fenetres().length} fenêtre(s) d'analyse`));
  if (!T.D.collecte.analyse) c.append(h('div', { class: 'alerte n2' }, h('div', { class: 'ic' }, 'ℹ️'), h('div', {}, "Le dossier d'analyse (_analyse) est absent : lancez ANALYSER_COLLECTE.bat puis régénérez ce fichier pour avoir sessions, SRUM, exécutions et grille.")));
  for (const a of v.alertes) c.append(h('div', { class: 'alerte n' + a.niv }, h('div', { class: 'ic' }, a.icone), h('div', {}, a.texte), h('div', { class: 'actions' }, T.bps(a.preuves, 2), a.onglet ? h('button', { class: 'btn petit', onclick: () => T.aller(a.onglet) }, 'Voir →') : '')));
  if (!v.alertes.length) c.append(h('div', { class: 'alerte n1' }, h('div', { class: 'ic' }, '✅'), h('div', {}, 'Aucune alerte majeure calculée. Lire quand même la grille par canal.')));
  c.append(h('div', { class: 'grille g4', style: 'margin:14px 0 16px' },
    T.kpi('🌐', T.nb(k.sessions), 'sessions depuis Internet / VPN', k.sessions ? 'rouge' : 'vert'),
    T.kpi('🎯', T.nb(k.ipSucces), 'IP publiques avec connexion réussie' + (k.pays.length ? ' · ' + k.pays.map(T.drapeau).join(' ') : ''), k.ipSucces ? 'rouge' : 'vert'),
    T.kpi('🔨', T.nb(k.echecs), `échecs de connexion · ${k.ipBrute} IP en force brute`, k.echecs > 500 ? 'orange' : ''),
    T.kpi('🧰', T.nb(k.outils.length), 'outils sensibles lancés pendant les fenêtres', k.outils.length ? 'rouge' : 'vert', k.outils.join(', ')),
    T.kpi('📤', T.nb(k.envoyeMax) + ' Mo', `envoyés au maximum${k.envoyeFen ? ' (fenêtre ' + k.envoyeFen + ')' : ''}`, k.envoyeMax > 500 ? 'rouge' : ''),
    T.kpi('🔒', T.nb(k.chiffres), 'fichiers chiffrés', k.chiffres ? 'rouge' : 'vert'),
    T.kpi('🧽', T.nb(k.anti), "traces d'anti-forensique", k.anti ? 'orange' : 'vert'),
    T.kpi('🛡️', T.nb(k.defender), 'détections Defender', k.defender ? 'orange' : '')));
  const fen = T.exfil().fenetres;
  const aFaire = [];
  if (v.actives.length) aFaire.push(['🚨', "Isoler le poste du réseau (connexion de l'attaquant encore active)"]);
  aFaire.push(['⏱️', v.cnil ? `Notification CNIL avant le ${T.flong(v.cnil.echeance)} (décision du cabinet et de son DPO)` : 'Saisir la date de découverte (Réglages) pour calculer le délai CNIL']);
  if (k.comptesNav) aFaire.push(['🔑', `Faire changer ${k.comptesNav} mot(s) de passe enregistré(s) dans les navigateurs`]);
  if (k.outils.some(o => /mimi|netpass|lazagne/.test(o))) aFaire.push(['🧨', "Vol d'identifiants : considérer TOUS les comptes du poste comme compromis"]);
  if (T.iocs().ip.length || T.iocs().hachages.length) aFaire.push(['🛰️', 'Lancer la chasse Datto RMM sur tout le parc (onglet IOC)']);
  aFaire.push(['📄', 'Prévenir l\'assureur cyber, proposer le dépôt de plainte']);
  c.append(h('div', { class: 'grille g2' },
    T.carte('🧭 Grille par canal', 'produite par Analyse-Exfil.ps1', v.grille.length ? h('ul', { class: 'lignes' }, v.grille.map(g => h('li', {}, h('div', { style: 'min-width:120px' }, T.pillStatut(g.statut)), h('div', {}, h('div', { class: 'gras' }, g.canal), h('div', { class: 'doux petit' }, g.constat)), h('div', { class: 'droite' }, T.bp(g.id)))))
      : T.vide('Grille absente (analyse non lancée).')),
    h('div', {},
      T.carte('✅ À faire maintenant', '', h('ul', { class: 'lignes' }, aFaire.map(([i, t]) => h('li', {}, h('span', { class: 'ic' }, i), h('span', {}, t))))),
      T.carte("🪟 Fenêtres d'analyse", 'sessions suspectes ± marge', fen.length ? h('ul', { class: 'lignes' }, fen.map(f => h('li', {}, h('span', { class: 'ic gras' }, f.id),
        h('div', {}, h('div', {}, `${T.fcourt(f.debut)} → ${T.fcourt(f.fin)} · ${f.duree} min`), h('div', { class: 'doux petit' }, f.motif)),
        h('div', { class: 'droite' }, T.pillNiveau(f.niveau), h('button', { class: 'btn petit', onclick: () => { T.zoomFenetre = f.id; T.aller('chrono'); } }, '🕒'))))) : T.vide('Aucune fenêtre.')))));
  const s = T.texte('SYNTHESE.txt');
  if (s) c.append(h('details', { class: 'carte' }, h('summary', { class: 'gras', style: 'cursor:pointer' }, '📄 SYNTHESE.txt de la collecte'), h('pre', { class: 'apercu', style: 'margin-top:10px' }, s)));
};

/* ---------------------------------------------------------------- chronologie */
T.filtreChrono = { g: 0, q: '', voies: null };
T.ECRANS.chrono = c => {
  const ch = T.chronologie(), F = T.filtreChrono, fen = T.fenetres();
  if (!F.voies) F.voies = new Set(ch.voies);
  c.append(h('h1', {}, 'Chronologie'), h('p', { class: 'sous-titre' }, `${T.nb(ch.evenements.length)} événements sur ${ch.voies.length} voies · zones rouges = fenêtres de l'attaquant · clic sur un point = preuve`));
  const graphEl = h('div', { class: 'graph haut', id: 'gFrise' });
  const liste = h('div');
  const filtrer = () => ch.evenements.filter(e => e.g >= F.g && F.voies.has(e.voie) && (!F.q || (e.titre + ' ' + e.detail + ' ' + (e.ip || '')).toLowerCase().includes(F.q)));
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
    liste.append(T.carte(`📋 Événements (${T.nb(vis.length)})`, zoom ? 'limités à la période zoomée' : '', T.tableau([
      { t: '', l: '18px', v: e => h('span', { title: 'gravité ' + e.g, style: `display:inline-block;width:10px;height:10px;border-radius:50%;background:${T.COUL['g' + e.g]}` }) },
      { t: 'Date', l: '120px', v: e => h('span', { class: 'mono' }, T.fcourt(e.t)) }, { t: 'Voie', l: '110px', v: e => e.voie },
      { t: 'Événement', v: e => h('div', {}, h('div', { class: e.g >= 2 ? 'gras' : '' }, e.titre), h('div', { class: 'pale petit' }, e.detail.slice(0, 180))) },
      { t: 'Fen.', l: '50px', v: e => e.fen ? h('span', { class: 'pill rouge' }, e.fen) : '' }, { t: 'Preuve', l: '200px', v: e => T.bp(e.id) }],
      vis, { max: 600, cls: e => e.g >= 3 ? 'attention' : '' })));
  };
  const seg = h('div', { class: 'seg' }, [['Tout', 0], ['Notable', 1], ['Important', 2], ['Critique', 3]].map(([l, g]) => h('button', { class: F.g === g ? 'actif' : '', onclick: e => { F.g = g; T.$$('button', seg).forEach(b => b.classList.remove('actif')); e.target.classList.add('actif'); dessiner(); } }, l)));
  const zooms = h('div', { class: 'seg' }, h('button', { onclick: () => { zoom = null; dessiner(); } }, 'Tout'), fen.map(w => h('button', { title: w.motif, onclick: () => { zoom = [+w.debut - 30 * 60e3, +w.fin + 30 * 60e3]; dessiner(); } }, w.id)));
  const voies = h('div', { class: 'filtres' }, ch.voies.map(v => h('label', { class: 'pill gris', style: 'cursor:pointer' }, h('input', { type: 'checkbox', checked: F.voies.has(v), onchange: e => { e.target.checked ? F.voies.add(v) : F.voies.delete(v); dessiner(); } }), ` ${v} (${ch.compte[v]})`)));
  const rech = h('input', { class: 'texte', placeholder: '🔎 Rechercher (IP, programme, compte…)', style: 'max-width:280px', value: F.q, oninput: e => { F.q = e.target.value.toLowerCase().trim(); clearTimeout(rech._t); rech._t = setTimeout(dessiner, 250); } });
  c.append(T.carte('', '', h('div', { class: 'filtres' }, h('span', { class: 'pale petit' }, 'Gravité'), seg, h('span', { class: 'pale petit', style: 'margin-left:10px' }, 'Zoom'), zooms, rech), voies, graphEl,
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
    T.kpi('🌍', T.nb(pub.length), 'IP publiques vues'), T.kpi('🗺️', T.nb(a.pays.length), 'pays'),
    T.kpi('🎯', T.nb(pub.filter(e => e.succes && !e.blanche).length), 'avec connexion réussie', pub.some(e => e.succes && !e.blanche) ? 'rouge' : 'vert'),
    T.kpi('🚫', T.nb(pub.filter(e => e.listes.length).length), 'sur une liste noire publique', pub.some(e => e.listes.length) ? 'orange' : '')));
  const carte = h('div', { class: 'graph carte-monde', id: 'gCarte' });
  c.append(T.carte('🗺️ Origine des connexions', 'rouge = connexion réussie · orange = échecs seulement', carte,
    h('div', { class: 'pale petit' }, b.asn ? `Base pays/opérateur : ${b.asn.source} du ${b.asn.date}` : '⚠️ Base de géolocalisation absente à la génération : relancer le .bat avec Internet.',
      b.ville ? ` · villes : ${b.ville.source} du ${b.ville.date}` : '', ' · ', (b.listes || []).filter(l => l.date).length ? `listes : ${(b.listes || []).filter(l => l.date).map(l => l.nom).join(', ')}` : 'listes noires non téléchargées')));
  requestAnimationFrame(() => T.graphCarte(carte, a));
  const tbl = h('div');
  const rendre = () => {
    const f = T.filtreIp;
    const lignes = a.ips.filter(e => f === 'toutes' ? true : f === 'succes' ? e.succes : f === 'brute' ? e.echecs >= 20 : f === 'listes' ? e.listes.length : (e.type !== 'Privee' && (e.succes || e.echecs || e.active)));
    tbl.innerHTML = '';
    tbl.append(T.tableau([
      { t: 'Score', l: '60px', v: e => h('span', { class: 'pill ' + (e.blanche ? 'vert' : e.score >= 5 ? 'rouge' : e.score >= 3 ? 'orange' : 'gris'), title: e.raisons.join('\n') }, e.blanche ? '✓' : e.score) },
      { t: 'IP', v: e => h('div', {}, h('div', { class: 'mono gras' }, e.ip), h('div', { class: 'pale petit' }, e.type)) },
      { t: 'Pays', v: e => e.pays ? h('span', {}, T.drapeau(e.pays), ' ', T.nomPays(e.pays), e.ville ? h('div', { class: 'pale petit' }, e.ville) : '') : '–' },
      { t: 'Opérateur', v: e => h('div', {}, h('div', {}, e.operateur || '–'), e.categorie ? h('span', { class: 'pill ' + (e.categorie.startsWith('Heb') ? 'rouge' : e.categorie.startsWith('FAI') ? 'bleu' : 'gris') }, e.categorie) : '') },
      { t: 'Succès', l: '60px', v: e => e.succes ? h('b', { style: 'color:#b42318' }, T.nb(e.succes)) : '0' }, { t: 'Échecs', l: '70px', v: e => T.nb(e.echecs) },
      { t: 'Période', v: e => h('span', { class: 'petit' }, T.fcourt(e.premier), e.dernier && e.dernier !== e.premier ? ' → ' + T.fcourt(e.dernier) : '') },
      { t: 'Comptes', v: e => h('span', { class: 'petit' }, e.comptes.slice(0, 4).join(', ')) },
      { t: 'Pourquoi', v: e => h('div', { class: 'petit' }, e.listes.map(l => h('span', { class: 'pill rouge', style: 'margin:1px' }, '🚫 ' + l.nom)), h('div', { class: 'doux' }, e.raisons.filter(r => !r.startsWith('liste ')).join(' · '))) },
      { t: 'Preuves', v: e => T.bps(e.preuves, 2) },
      { t: '', l: '96px', v: e => h('div', {}, e.type === 'PUBLIQUE' || e.type === 'VPN/CGNAT' ? h('button', { class: 'btn petit', title: 'Ajouter / retirer de la liste blanche (IP légitime : box du cabinet, technicien…)', onclick: () => T.basculerBlanche(e.ip) }, e.blanche ? '↩️' : '⭐') : '',
          e.type === 'PUBLIQUE' ? h('button', { class: 'btn petit', title: 'Interroger Shodan InternetDB (envoie uniquement cette IP)', onclick: ev => T.internetDb(e.ip, ev.target) }, '🔎') : '') }],
      lignes, { max: 400, cls: e => e.score >= 5 ? 'attention' : '', vide: 'Aucune IP pour ce filtre.' }));
  };
  const seg = h('div', { class: 'seg' }, [['interessantes', 'À regarder'], ['succes', 'Connexions réussies'], ['brute', 'Force brute'], ['listes', 'Sur une liste'], ['toutes', 'Toutes']].map(([k, l]) =>
    h('button', { class: T.filtreIp === k ? 'actif' : '', onclick: ev => { T.filtreIp = k; T.$$('button', seg).forEach(x => x.classList.remove('actif')); ev.target.classList.add('actif'); rendre(); } }, l)));
  c.append(T.carte('📋 Adresses IP', '⭐ = liste blanche (partagée via Réglages) · 🔎 = InternetDB', h('div', { class: 'filtres' }, seg,
    h('button', { class: 'btn', style: 'margin-left:auto', onclick: () => T.telecharger(`${T.identite().poste}_ip.csv`, T.versCsv(a.ips.map(e => ({ IP: e.ip, Type: e.type, Pays: e.pays, Ville: e.ville, ASN: e.asn, Operateur: e.operateur, Categorie: e.categorie, Succes: e.succes, Echecs: e.echecs, Premier: e.premier, Dernier: e.dernier, Score: e.score, Raisons: e.raisons.join(' | '), Listes: e.listes.map(l => l.nom).join(' | ') })))) }, '⬇️ CSV')), tbl));
  rendre();
  const g = h('div', { class: 'graph bas', id: 'gBrute', style: 'height:200px' });
  c.append(T.carte('🔨 Force brute : échecs de connexion par jour', '4625', g));
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
    td.append(h('div', { class: 'petit', style: 'margin-top:4px;background:#f9fafb;border-radius:6px;padding:4px 6px' }, r.status === 404 || j.detail ? 'InternetDB : aucune donnée' :
      `InternetDB : ports ${(j.ports || []).join(', ') || '–'} · ${(j.tags || []).join(', ') || 'pas de tag'}${(j.hostnames || []).length ? ' · ' + j.hostnames.slice(0, 2).join(', ') : ''}${(j.vulns || []).length ? ' · ' + j.vulns.length + ' CVE' : ''}`));
    bouton.textContent = '✓';
  } catch (e) { bouton.textContent = '🔎'; bouton.disabled = false; T.toast("InternetDB injoignable depuis ce navigateur (hors ligne ou bloqué)."); }
};
T.versCsv = lignes => { if (!lignes.length) return ''; const k = Object.keys(lignes[0]); const q = v => '"' + String(v ?? '').replace(/"/g, '""') + '"'; return '\ufeff' + [k.map(q).join(','), ...lignes.map(l => k.map(x => q(l[x])).join(','))].join('\r\n'); };

/* ---------------------------------------------------------------- exfiltration */
T.ECRANS.exfil = c => {
  const ex = T.exfil(), R = T.reglages(), hy = ex.hyp;
  c.append(h('h1', {}, 'Exfiltration'), h('p', { class: 'sous-titre' }, 'On ne peut pas toujours prouver ce qui est sorti. Mais on peut souvent borner ce qui a pu sortir.'));
  const maj = (k, v) => { T.majReglages({ [k]: v }); T.rafraichir(); };
  c.append(T.carte('🧮 Test de plausibilité : hypothèses', 'à ajuster avec le cabinet', h('div', { class: 'champs' },
    h('div', { class: 'champ' }, h('label', {}, '📶 Débit montant de la box (Mbit/s)'), h('input', { type: 'number', min: 0, step: 0.1, value: R.debit_montant_mbps, placeholder: 'ex. 1 (ADSL), 40 (VDSL), 300 (fibre)', onchange: e => maj('debit_montant_mbps', e.target.value) }),
      h('div', { class: 'aide' }, 'Test de débit ou contrat FAI. Sert à la borne physique.')),
    h('div', { class: 'champ' }, h('label', {}, '🗄️ Taille de la base patients (Mo)'), h('input', { type: 'number', min: 0, value: R.taille_base_mo, placeholder: hy.tailleAuto ? `auto : ${T.nb(hy.tailleAuto)} Mo` : 'inconnue', onchange: e => maj('taille_base_mo', e.target.value) }),
      h('div', { class: 'aide' }, hy.tailleAuto ? `Plus grosse base trouvée sur le disque : ${T.nb(hy.tailleAuto)} Mo.` : 'Aucune base métier trouvée par la collecte.')),
    h('div', { class: 'champ' }, h('label', {}, '🗜️ Compression supposée (×)'), h('input', { type: 'number', min: 1, step: 0.5, value: R.compression || 4, onchange: e => maj('compression', e.target.value) }),
      h('div', { class: 'aide' }, h('span', { class: 'deduction' }, 'déduction'), ' Une base se compresse souvent de 3 à 10 fois.'))),
    h('div', { class: 'petit doux', style: 'margin-top:8px' }, `➡️ Base compressée estimée : ${hy.comp ? T.nb(hy.comp) + ' Mo' : 'inconnue'}`)));
  if (!ex.fenetres.length) c.append(T.vide('Aucune fenêtre d\'analyse : rien à borner.'));
  for (const f of ex.fenetres) {
    const g = h('div', { class: 'graph bas', id: 'gPl' + f.id });
    c.append(h('div', { class: 'carte' }, h('h2', {}, `🪟 ${f.id}`, h('span', { class: 'pale', style: 'font-weight:500' }, `${T.fcourt(f.debut)} → ${T.fcourt(f.fin)} · ${f.duree} min`), h('span', { style: 'margin-left:auto' }, T.pillNiveau(f.niveau))),
      h('div', { class: 'doux petit', style: 'margin:-4px 0 8px' }, f.motif),
      h('div', { class: 'grille g2' }, g, h('ul', { class: 'lignes' }, f.constats.map(x => h('li', {}, h('span', { class: 'ic' }, '➡️'), h('span', {}, x))))),
      f.apps.length ? h('details', { style: 'margin-top:8px' }, h('summary', { class: 'petit gras', style: 'cursor:pointer' }, `Applications qui ont envoyé (${f.apps.length})`),
        T.tableau([{ t: 'Application', v: a => h('span', { class: 'mono' }, a.app) }, { t: 'Envoyé', v: a => T.nb(a.mo, 1) + ' Mo' }, { t: 'Écart à la référence', v: a => a.ecart ? h('span', { class: 'pill rouge' }, a.ecart) : '' }, { t: 'Preuves', v: a => T.bps(a.ids, 2) }], f.apps, { defile: false })) : '',
      h('div', { class: 'petit', style: 'margin-top:6px' }, 'Preuves : ', T.bp(f.preuveFenetre), ' ', T.bps(f.preuves, 4))));
    requestAnimationFrame(() => T.graphPlausibilite(g, f, hy));
  }
  const gs = h('div', { class: 'graph', id: 'gSrum' });
  c.append(T.carte('📈 Volumes envoyés par le poste (SRUM)', ex.ref ? `référence : moyenne ${T.nb(ex.ref.moyenne, 1)} · P95 ${T.nb(ex.ref.p95, 1)} · max ${T.nb(ex.ref.max, 1)} Mo/h` : '', ex.serie.length ? gs : T.vide('SRUM absent de l\'analyse.')));
  if (ex.serie.length) requestAnimationFrame(() => T.graphSrum(gs, ex));
  c.append(h('div', { class: 'grille g2' },
    T.carte('🗄️ Bases métier sur le disque', '', T.tableau([{ t: 'Chemin', v: b => h('span', { class: 'mono petit' }, b.chemin) }, { t: 'Taille', l: '90px', v: b => T.nb(b.mo) + ' Mo' }, { t: '', v: b => b.sauvegarde ? h('span', { class: 'pill gris' }, 'sauvegarde') : '' }, { t: 'Preuve', v: b => T.bp(b.id) }], ex.bases, { vide: 'Aucune base métier trouvée (rancon\\bases_metier.csv).', defile: false })),
    T.carte('⚠️ Limites du test', '', h('ul', { class: 'lignes' }, T.LIMITES_EXFIL.map(x => h('li', {}, h('span', { class: 'ic' }, '•'), h('span', { class: 'petit' }, x)))))));
};

/* ---------------------------------------------------------------- visibilite */
T.ECRANS.visibilite = c => {
  const v = T.visibilite();
  c.append(h('h1', {}, 'Visibilité'), h('p', { class: 'sous-titre' }, "Une absence de trace ne prouve rien si la source ne regardait pas à ce moment. Cette carte montre ce qu'on ne pourra jamais savoir."));
  const g = h('div', { class: 'graph', id: 'gVisi', style: `height:${Math.max(260, 70 + v.sources.length * 26 + 90)}px` });
  c.append(T.carte('👁️ Couverture des sources, heure par heure', 'cadres rouges = fenêtres de l\'attaquant', v.grille.heures.length ? g : T.vide('Aucune fenêtre d\'analyse.')));
  if (v.grille.heures.length) requestAnimationFrame(() => T.graphVisibilite(g, v));
  c.append(h('div', { class: 'grille g2' },
    T.carte('🪟 Par fenêtre', '', v.fenetres.length ? h('ul', { class: 'lignes' }, v.fenetres.map(w => h('li', {}, h('span', { class: 'ic gras' }, w.id),
      h('div', {}, h('div', {}, h('b', {}, w.taux + ' %'), ' des sources couvrent la fenêtre'), h('div', { class: 'petit doux' }, w.sources.filter(s => s.statut !== 'couverte').map(s => `${s.source} : ${s.statut}`).join(' · ') || 'toutes couvertes'))))) : T.vide()),
    T.carte("🧽 Traces d'anti-forensique", 'effacements, désactivations, exclusions', v.anti.length ? h('ul', { class: 'lignes' }, v.anti.map(a => h('li', {}, h('span', { class: 'ic' }, '⚠️'), h('div', {}, h('div', { class: 'gras' }, a.trace), h('div', { class: 'petit doux' }, (a.date ? T.fcourt(a.date) + ' · ' : '') + a.detail.slice(0, 160))), h('div', { class: 'droite' }, T.bp(a.id))))) : h('div', {}, '✅ Aucune trace détectée.'))));
  c.append(T.carte('📚 Sources', '', T.tableau([{ t: 'Source', v: s => s.source }, { t: 'État', v: s => h('span', { class: 'pill ' + (s.etat === 'present' ? 'vert' : s.etat === 'desactive' ? 'rouge' : 'gris') }, s.etat === 'present' ? 'présente' : s.etat === 'desactive' ? 'désactivée' : 'absente') },
    { t: 'Du', v: s => T.fcourt(s.debut) }, { t: 'Au', v: s => T.fcourt(s.fin) }, { t: 'Preuve', v: s => T.bp(s.id) }], v.sources, { defile: false })));
};

/* ---------------------------------------------------------------- sante et RGPD */
T.ECRANS.sante = c => {
  const s = T.sante(), v = T.vue(), R = T.reglages(), ex = T.exfil();
  c.append(h('h1', {}, 'Santé et RGPD'), h('p', { class: 'sous-titre' }, 'Ce qui aide le cabinet à décider de la notification. La décision appartient au responsable de traitement et à son DPO.'));
  const dec = h('input', { type: 'datetime-local', value: (R.decouverte || '').replace(' ', 'T').slice(0, 16), onchange: e => { T.majReglages({ decouverte: e.target.value.replace('T', ' ') }); T.rafraichir(); } });
  const pire = ex.fenetres.reduce((m, f) => (!m || f.envoye > m.envoye) ? f : m, null);
  c.append(h('div', { class: 'grille g2' },
    T.carte('⏱️ Délai CNIL (art. 33 RGPD : 72 h après la découverte)', '', h('div', { class: 'champ' }, h('label', {}, 'Date et heure de découverte'), dec,
      h('div', { class: 'aide' }, R.decouverte && T.decouverteFiche() === R.decouverte ? 'Reprise de A_COMPLETER_TECHNICIEN.txt' : 'Saisie dans cette interface')),
      v.cnil ? h('div', { style: 'margin-top:12px;font-size:18px' }, v.cnil.restantH < 0 ? h('b', { style: 'color:#b42318' }, `Délai dépassé depuis ${Math.floor(-v.cnil.restantH)} h`) : h('span', {}, '⏳ ', h('b', {}, `${Math.floor(v.cnil.restantH)} h ${p2m(v.cnil.restantH)}`), ' restantes'),
        h('div', { class: 'petit doux' }, `Échéance : ${T.flong(v.cnil.echeance)}`)) : '',
      h('div', { class: 'petit', style: 'margin-top:10px' }, '🔗 Téléservice : ', h('a', { href: 'https://notifications.cnil.fr/notifications/index', target: '_blank', rel: 'noopener' }, 'notifications.cnil.fr'))),
    T.carte('📝 Éléments pour le formulaire CNIL', 'pré-rempli, à vérifier', h('ul', { class: 'lignes' },
      h('li', {}, h('span', { class: 'ic' }, '🧨'), h('div', {}, h('b', {}, 'Nature : '), [T.vue().kpi.chiffres ? 'rançongiciel (chiffrement)' : '', T.vue().kpi.sessions ? 'accès à distance non autorisé' : '', pire && ['PLAUSIBLE', 'PARTIELLE'].includes(pire.niveau) ? 'exfiltration possible' : ''].filter(Boolean).join(', ') || 'à préciser')),
      h('li', {}, h('span', { class: 'ic' }, '🗂️'), h('div', {}, h('b', {}, 'Catégories de données : '), s.categories.map(x => x.categorie).join(', ') || 'à préciser', ' ', h('span', { class: 'deduction' }, 'déduction'))),
      h('li', {}, h('span', { class: 'ic' }, '👥'), h('div', {}, h('b', {}, 'Nombre de personnes : '), 'à demander au cabinet (nombre de patients dans la base, pas de fichiers)')),
      h('li', {}, h('span', { class: 'ic' }, '📤'), h('div', {}, h('b', {}, 'Exfiltration : '), pire ? `${T.NIVEAUX[pire.niveau].lib.toLowerCase()} (fenêtre ${pire.id}, ${T.nb(pire.envoye)} Mo envoyés)` : 'non évaluée')),
      h('li', {}, h('span', { class: 'ic' }, '🛠️'), h('div', {}, h('b', {}, 'Mesures prises : '), 'isolement, collecte forensique, changement des mots de passe, chasse sur le parc (à compléter)'))))));
  c.append(T.carte('🏥 Logiciels et données de santé repérés', 'déduits des chemins et des sites : à confirmer avec le cabinet', s.logiciels.length ? T.tableau([
    { t: 'Logiciel / source', v: t => h('div', {}, h('b', {}, t.logiciel), s.pendant.includes(t.logiciel) ? h('div', {}, h('span', { class: 'pill rouge' }, 'touché pendant une fenêtre')) : '') },
    { t: 'Données probables', v: t => h('div', {}, t.categories.map(x => h('span', { class: 'pill violet', style: 'margin:1px' }, x))) },
    { t: 'Traces', v: t => h('div', { class: 'petit' }, Object.entries(t.traces).map(([k, n]) => h('div', {}, `${n} × ${k}`))) },
    { t: 'Preuves', v: t => T.bps(t.preuves.map(p => p.id), 3) }], s.logiciels, { defile: false }) : T.vide('Aucun logiciel métier ni site santé repéré.')));
  const H = Object.assign({}, T.REGLAGES_DEFAUT.horaires, R.horaires || {});
  const horaires = h('div', { class: 'champs' }, T.JOURS.map((j, i) => h('div', { class: 'champ' }, h('label', {}, j), h('input', { value: H[i] || '', placeholder: 'fermé', onchange: e => { const n = Object.assign({}, H, { [i]: e.target.value }); T.majReglages({ horaires: n }); T.rafraichir(); } }))));
  const distantes = s.sessions.filter(x => ['PUBLIQUE', 'VPN/CGNAT'].includes(x.typeIp));
  c.append(T.carte("🕘 Horaires du cabinet et sessions à distance", 'format 08:00-12:00,14:00-19:00', horaires,
    h('div', { style: 'margin-top:12px' }, T.tableau([{ t: 'Début', v: x => T.fcourt(x.debut) }, { t: 'Jour', v: x => x.jour }, { t: 'Fin', v: x => T.fcourt(x.fin) }, { t: 'Compte', v: x => x.compte }, { t: 'IP', v: x => h('span', { class: 'mono' }, x.ip) },
      { t: '', v: x => x.hors ? h('span', { class: 'pill rouge' }, '🌙 hors horaires') : h('span', { class: 'pill gris' }, 'heures d\'ouverture') }, { t: 'Preuve', v: x => T.bp(x.id) }], distantes, { vide: 'Aucune session depuis Internet / VPN.', defile: false }))));
};

/* ---------------------------------------------------------------- identifiants et fuites */
T.ECRANS.fuites = c => {
  const id = T.identifiants(), R = T.reglages(), b = (T.D.bases || {}).ransomware;
  c.append(h('h1', {}, 'Identifiants et fuites'), h('p', { class: 'sous-titre' }, 'Les mots de passe ne sont jamais lus par la collecte : seuls les sites et identifiants enregistrés sont listés.'));
  c.append(T.carte(`🔑 Comptes à faire changer (${id.comptes.length})`, 'enregistrés dans les navigateurs du poste', T.tableau([{ t: 'Utilisateur', v: x => x.utilisateur }, { t: 'Site', v: x => h('b', {}, x.site) }, { t: 'Identifiant(s)', v: x => h('span', { class: 'mono petit' }, x.identifiants) }, { t: 'Navigateur', v: x => x.navigateurs }, { t: 'Preuve', v: x => T.bp(x.id) }], id.comptes, { vide: 'Aucun (ou LISTER_IDENTIFIANTS.bat non lancé).', defile: false }),
    id.comptes.length ? h('button', { class: 'btn', style: 'margin-top:8px', onclick: async () => T.toast(await T.copier(id.comptes.map(x => `☐ ${x.site} (${x.identifiants})`).join('\n')) ? 'Liste copiée (à coller dans un mail ou une fiche)' : 'Copie impossible') }, '📋 Copier la liste à cocher') : '',
    id.wifi ? h('div', { class: 'petit doux', style: 'margin-top:8px' }, `📶 ${id.wifi} profil(s) Wi-Fi enregistré(s) : clés lisibles par un administrateur du poste, à changer si le compte était admin.`) : ''));
  const res = h('div', { style: 'margin-top:10px' }), mdp = h('input', { type: 'password', class: 'texte', placeholder: 'Mot de passe à tester (jamais envoyé)', style: 'max-width:320px', autocomplete: 'off' });
  const tester = async () => {
    if (!mdp.value) return; res.innerHTML = '⏳ Vérification…';
    try { const n = await T.pwned(mdp.value); res.innerHTML = ''; res.append(n ? h('div', { class: 'alerte n3' }, h('div', { class: 'ic' }, '🚨'), h('div', {}, `Ce mot de passe apparaît ${T.nb(n)} fois dans des fuites publiques. Il a pu servir à entrer : le changer partout.`)) : h('div', { class: 'alerte n1' }, h('div', { class: 'ic' }, '✅'), h('div', {}, 'Absent des fuites connues de Have I Been Pwned (ça ne prouve pas qu\'il est sûr).'))); }
    catch (e) { res.textContent = '⚠️ Service injoignable depuis ce navigateur (' + e.message + '). Vérifier la connexion Internet.'; }
    mdp.value = '';
  };
  c.append(h('div', { class: 'grille g2' },
    T.carte('🧪 Mot de passe dans une fuite publique ?', 'Have I Been Pwned · k-anonymat', h('ul', { class: 'lignes' },
      h('li', {}, h('span', { class: 'ic' }, '🔒'), h('span', { class: 'petit' }, 'Le mot de passe est haché ici (SHA-1). Seuls les 5 premiers caractères du hachage partent sur Internet.')),
      h('li', {}, h('span', { class: 'ic' }, '🎯'), h('span', { class: 'petit' }, 'Utile pour expliquer l\'entrée : un mot de passe RDP déjà fuité = force brute réussie.'))),
      h('div', { class: 'filtres', style: 'margin-top:8px' }, mdp, h('button', { class: 'btn primaire', onclick: tester }, 'Vérifier')), res),
    T.carte(`📧 Adresses e-mail trouvées (${id.emails.length})`, 'à vérifier sur haveibeenpwned.com', id.emails.length ? h('ul', { class: 'lignes' }, id.emails.map(e => h('li', {}, h('span', { class: 'ic' }, '📧'), h('div', {}, h('div', { class: 'mono gras' }, e.email), h('div', { class: 'petit doux' }, e.sites.join(', '))),
      h('div', { class: 'droite' }, h('a', { class: 'btn petit', href: 'https://haveibeenpwned.com/', target: '_blank', rel: 'noopener', title: 'Ouvre le site : saisir l\'adresse vous-même' }, 'HIBP ↗'), T.bp(e.preuves[0]))))) : T.vide('Aucune adresse e-mail parmi les identifiants enregistrés.'))));
  const mots = h('input', { class: 'texte', value: (R.mots_cles_fuite && R.mots_cles_fuite.length ? R.mots_cles_fuite : (R.client ? [R.client] : [])).join(', '), placeholder: 'Nom du cabinet, domaine, ville…', style: 'max-width:480px' });
  const zone = h('div', { style: 'margin-top:10px' });
  const chercher = () => {
    const m = mots.value.split(',').map(x => x.trim()).filter(Boolean); T.majReglages({ mots_cles_fuite: m });
    const r = T.chercherVictimes(m); zone.innerHTML = '';
    if (!r.nb) { zone.append(T.vide('Liste des victimes absente : relancer le .bat avec Internet pour la télécharger.')); return; }
    zone.append(h('div', { class: 'petit doux', style: 'margin-bottom:6px' }, `${T.nb(r.nb)} victimes publiées dans la liste embarquée${b && b.date ? ' (téléchargée le ' + b.date + ')' : ''}.`));
    zone.append(r.resultats.length ? T.tableau([{ t: 'Victime publiée', v: x => h('b', {}, x.victime) }, { t: 'Groupe', v: x => h('span', { class: 'pill rouge' }, x.groupe) }, { t: 'Date', v: x => T.fcourt(x.date) || x.date }, { t: 'Site', v: x => x.site },
      { t: 'Correspondance', v: x => h('span', { class: 'pill ' + (x.exact ? 'rouge' : 'orange') }, (x.exact ? 'exacte' : 'partielle') + ' : ' + x.mot) }], r.resultats, { defile: false }) : h('div', { class: 'alerte n1' }, h('div', { class: 'ic' }, '✅'), h('div', {}, 'Aucune victime correspondante dans la liste embarquée.')));
  };
  c.append(T.carte('🕵️ Sites de fuite des rançongiciels', 'ransomware.live · recherche faite DANS ce fichier', h('div', { class: 'petit doux', style: 'margin-bottom:8px' }, 'Le nom du client n\'est jamais envoyé : la liste publique des victimes (France et récentes) a été téléchargée par le .bat, la recherche se fait ici.'),
    h('div', { class: 'filtres' }, mots, h('button', { class: 'btn primaire', onclick: chercher }, 'Chercher')), zone));
  chercher();
};

/* ---------------------------------------------------------------- IOC et chasse */
T.ECRANS.ioc = c => {
  const i = T.iocs(), hs = T.hachages(), deja = T.dejaVu();
  c.append(h('h1', {}, 'IOC et chasse'), h('p', { class: 'sous-titre' }, 'Indicateurs de compromission de cet incident, à chercher sur tout le parc.'));
  if (deja.length) c.append(T.carte('🔁 Déjà vus dans d\'autres incidents', 'mémoire tenue par le .bat sur la clé', h('ul', { class: 'lignes' }, deja.map(d => h('li', {}, h('span', { class: 'ic' }, '🔁'),
    h('div', {}, h('div', { class: 'gras' }, `${d.client || 'client ?'} · ${d.poste}`), h('div', { class: 'petit doux' }, `collecte du ${T.fcourt(d.date)} · en commun : ` + d.communs.map(x => `${x.type} ${x.valeur.length > 20 ? x.valeur.slice(0, 16) + '…' : x.valeur}`).join(', ')))))),
    h('div', { class: 'petit doux' }, 'Même attaquant ou même outillage : prévenir les autres clients concernés et comparer les chronologies.')));
  const script = h('pre', { class: 'apercu', style: 'display:none;margin-top:10px' });
  c.append(T.carte('🛰️ Chasse sur tout le parc (Datto RMM)', 'lecture seule sur les postes', h('div', { class: 'grille g4', style: 'margin-bottom:12px' },
    T.kpi('🌐', i.ip.length, `IP de l'attaquant · + ${i.ipBrute.length} IP de force brute`), T.kpi('🧬', i.hachages.length, 'hachages'), T.kpi('📄', i.fichiers.length, 'noms de fichiers'), T.kpi('⏰', i.taches.length + i.services.length + i.comptes.length, 'tâches, services, comptes')),
    h('ul', { class: 'lignes' }, h('li', {}, h('span', { class: 'ic' }, '1️⃣'), h('span', {}, 'Télécharger le composant ci-dessous.')), h('li', {}, h('span', { class: 'ic' }, '2️⃣'), h('span', {}, 'Datto RMM : nouveau composant PowerShell, coller le script, exécuter en SYSTEM.')),
      h('li', {}, h('span', { class: 'ic' }, '3️⃣'), h('span', {}, 'Lancer en tâche sur tous les sites. Code retour 1 = correspondance (résumé dans la sortie, CSV dans C:\\ProgramData\\TriageIOC).'))),
    h('div', { class: 'filtres', style: 'margin-top:10px' }, h('button', { class: 'btn primaire', onclick: () => T.telecharger(`Chasse_IOC_${T.identite().poste}.ps1`, '\ufeff' + T.scriptChasse()) }, '⬇️ Télécharger le composant (.ps1)'),
      h('button', { class: 'btn', onclick: () => { script.style.display = script.style.display === 'none' ? 'block' : 'none'; script.textContent = T.scriptChasse(); } }, '👀 Voir le script'),
      h('button', { class: 'btn', onclick: async () => T.toast(await T.copier(T.scriptChasse()) ? 'Script copié' : 'Copie impossible') }, '📋 Copier')), script));
  c.append(T.carte(`🧬 Hachages (${hs.length})`, 'liens externes : le hachage part uniquement si vous cliquez', T.tableau([
    { t: 'Type', l: '70px', v: e => h('span', { class: 'pill gris' }, e.type) }, { t: 'Hachage', v: e => h('span', { class: 'mono', title: e.hash, style: 'font-size:11.5px' }, e.hash.slice(0, 20) + '…') },
    { t: 'Nom', v: e => h('b', {}, e.noms.slice(0, 2).join(', ')) }, { t: 'Source', v: e => h('span', { class: 'petit' }, e.sources.slice(0, 2).join(' · '), e.remarque ? h('div', { class: 'pale' }, e.remarque) : '') },
    { t: 'Preuves', v: e => T.bps(e.preuves, 2) },
    { t: '', l: '170px', v: e => h('div', {}, h('button', { class: 'btn petit', onclick: async () => T.toast(await T.copier(e.hash) ? 'Copié' : 'Copie impossible') }, '📋'),
        ' ', h('a', { class: 'btn petit', href: 'https://www.virustotal.com/gui/file/' + e.hash.toLowerCase(), target: '_blank', rel: 'noopener' }, 'VT ↗'),
        ' ', h('a', { class: 'btn petit', href: 'https://bazaar.abuse.ch/browse.php?search=' + (e.type === 'SHA256' ? 'sha256%3A' : e.type === 'SHA1' ? 'sha1%3A' : 'md5%3A') + e.hash.toLowerCase(), target: '_blank', rel: 'noopener' }, 'MB ↗')) }],
    hs, { vide: 'Aucun hachage collecté.' })));
  c.append(h('div', { class: 'grille g2' },
    T.carte('⏰ Persistance suspecte', 'tâches et services lancés depuis des dossiers à risque', T.tableau([{ t: 'Type', v: x => x.t }, { t: 'Nom', v: x => h('b', {}, x.nom) }, { t: 'Commande', v: x => h('span', { class: 'mono petit' }, x.cmd) }, { t: 'Preuve', v: x => T.bp(x.id) }],
      [...i.taches.map(t => ({ t: 'Tâche', nom: t.nom, cmd: t.commande, id: t.id })), ...i.services.map(s => ({ t: 'Service', nom: s.nom, cmd: s.chemin, id: s.id }))], { vide: 'Rien de suspect repéré.', defile: false })),
    T.carte('👤 Comptes créés pendant les fenêtres', '', T.tableau([{ t: 'Compte', v: x => h('b', {}, x.nom) }, { t: 'Date', v: x => T.fcourt(x.date) }, { t: 'Preuve', v: x => T.bp(x.id) }], i.comptes, { vide: 'Aucun.', defile: false }))));
};

/* ---------------------------------------------------------------- analyse IA */
T.ECRANS.ia = c => {
  const cleSauv = T.stockage.lire('digspill:cle-anthropic') || '';
  c.append(h('h1', {}, 'Analyse IA (Claude)'), h('p', { class: 'sous-titre' }, 'Claude lit une synthèse filtrée, cite une preuve pour chaque phrase, et ce fichier vérifie chaque citation.'));
  c.append(h('div', { class: 'grille g3', style: 'margin-bottom:16px' },
    T.kpi('🙈', 'Masqué', 'comptes (U1, U2…), noms de fichiers, e-mails, chemins des URL'), T.kpi('🔗', 'Sourcé', 'chaque phrase doit citer [fichier#ligne]'), T.kpi('✅', 'Vérifié', 'citation existante et valeurs retrouvées dans la ligne')));
  const cle = h('input', { type: 'password', class: 'texte', placeholder: 'sk-ant-…', value: cleSauv, autocomplete: 'off' });
  const memo = h('input', { type: 'checkbox', checked: !!cleSauv });
  const modele = h('select', { class: 'texte' }, [['claude-sonnet-5-5', 'Claude Sonnet 5.5 (conseillé)'], ['claude-opus-5-5', 'Claude Opus 5.5 (plus fin)'], ['claude-haiku-5-5', 'Claude Haiku 5.5 (rapide)']].map(([v, l]) => h('option', { value: v }, l)));
  const apercu = h('pre', { class: 'apercu', style: 'display:none' }), info = h('div', { class: 'petit doux' }), sortie = h('div');
  const voir = () => { const a = T.apercuIA(); apercu.style.display = 'block'; apercu.textContent = a.texte; info.textContent = `${a.ko} Ko · ~${T.nb(a.tokens)} jetons · ${a.comptes} compte(s) pseudonymisé(s). C'est exactement ce qui partira.`; };
  const lancer = async ev => {
    if (!cle.value.trim()) { T.toast('Saisir une clé API Anthropic'); return; }
    if (memo.checked) T.stockage.ecrire('digspill:cle-anthropic', cle.value.trim()); else localStorage.removeItem('digspill:cle-anthropic');
    ev.target.disabled = true; ev.target.textContent = '⏳ Analyse en cours (1 à 2 min)…';
    try { const r = await T.lancerIA(cle.value.trim(), modele.value); T.stockage.ecrire(T.cleStockage() + ':ia', r); afficher(r); }
    catch (e) { sortie.innerHTML = ''; sortie.append(h('div', { class: 'alerte n3' }, h('div', { class: 'ic' }, '⚠️'), h('div', {}, 'Échec : ' + e.message))); }
    ev.target.disabled = false; ev.target.textContent = '🚀 Lancer l\'analyse';
  };
  const coller = h('textarea', { class: 'texte', rows: 5, placeholder: 'Ou collez ici une réponse obtenue ailleurs (claude.ai…) pour vérifier ses citations' });
  c.append(T.carte('⚙️ Lancer', 'la clé reste dans ce navigateur', h('div', { class: 'champs' },
    h('div', { class: 'champ' }, h('label', {}, '🔑 Clé API Anthropic'), cle, h('label', { class: 'petit', style: 'font-weight:400;margin-top:4px' }, memo, ' mémoriser dans ce navigateur')),
    h('div', { class: 'champ' }, h('label', {}, '🧠 Modèle'), modele)),
    h('div', { class: 'filtres', style: 'margin-top:12px' }, h('button', { class: 'btn', onclick: voir }, '👀 Voir ce qui sera envoyé'), h('button', { class: 'btn primaire', onclick: lancer }, '🚀 Lancer l\'analyse'),
      h('button', { class: 'btn', title: 'Pour utiliser claude.ai sans clé API : copier, coller dans une conversation, puis recoller la réponse ci-dessous', onclick: async () => T.toast(await T.copier(T.PROMPT_SYSTEME + '\n\nSynthese de la collecte :\n' + T.apercuIA().texte) ? 'Consignes + synthèse copiées : à coller dans claude.ai' : 'Copie impossible') }, '📋 Copier consignes + synthèse')),
    info, apercu,
    h('div', { style: 'margin-top:12px' }, coller, h('button', { class: 'btn', style: 'margin-top:6px', onclick: () => { if (!coller.value.trim()) return; const r = T.verifierIA(coller.value); T.stockage.ecrire(T.cleStockage() + ':ia', r); afficher(r); } }, '🔍 Vérifier ce texte'))));
  c.append(sortie);
  const afficher = r => {
    sortie.innerHTML = '';
    const b = r.bilan, leg = [['verifiee', '✅ vérifiées', 'vert'], ['a_controler', '🟠 à contrôler', 'orange'], ['non_sourcee', '🔴 non sourcées', 'rouge'], ['citation_invalide', '❌ citation inconnue', 'rouge'], ['deduction', '🟣 déductions', 'violet']];
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
    sortie.append(T.carte('📄 Résultat', r.modele ? `${r.modele}${r.usage ? ' · ' + T.nb(r.usage.input_tokens) + ' jetons lus' : ''}` : 'texte vérifié',
      h('div', { class: 'filtres' }, leg.filter(([k]) => b[k]).map(([k, l, cl]) => h('span', { class: 'pill ' + cl }, `${l} : ${b[k]}`))),
      h('div', { class: 'petit doux', style: 'margin-bottom:8px' }, 'Survoler une phrase surlignée pour voir le problème. Les pseudonymes sont rétablis ici, localement.'), corps,
      h('div', { class: 'filtres', style: 'margin-top:12px' }, h('button', { class: 'btn', onclick: async () => T.toast(await T.copier(r.texte) ? 'Texte copié' : 'Copie impossible') }, '📋 Copier le texte brut'))));
  };
  const prec = T.stockage.lire(T.cleStockage() + ':ia'); if (prec) afficher(prec);
};

/* ---------------------------------------------------------------- rapports */
T.ECRANS.rapport = c => {
  c.append(h('h1', {}, 'Rapports'), h('p', { class: 'sous-titre' }, 'Impression ou PDF (« Enregistrer au format PDF » dans la fenêtre d\'impression).'));
  c.append(h('div', { class: 'grille g2' },
    T.carte('👩‍⚕️ Rapport praticien', '1 page, sans jargon', h('ul', { class: 'lignes' }, ['Ce qui s\'est passé, en 5 lignes', 'Ce que le cabinet doit faire', 'Échéance CNIL'].map(x => h('li', {}, h('span', { class: 'ic' }, '•'), x))),
      h('button', { class: 'btn primaire', onclick: () => T.imprimer('praticien') }, '🖨️ Imprimer / PDF')),
    T.carte('🧑‍💻 Rapport technique sourcé', 'pour l\'assureur, l\'expert ou la plainte', h('ul', { class: 'lignes' }, ['Indicateurs, grille, IP, exfiltration, visibilité', 'Chaque constat avec sa preuve [fichier#ligne]', 'Index des fichiers avec leur SHA256'].map(x => h('li', {}, h('span', { class: 'ic' }, '•'), x))),
      h('button', { class: 'btn primaire', onclick: () => T.imprimer('technique') }, '🖨️ Imprimer / PDF'))));
  c.append(T.carte('💾 Exports', '', h('div', { class: 'filtres' },
    h('button', { class: 'btn', onclick: () => T.telecharger(`${T.D.collecte.nom}_reglages.json`, JSON.stringify(T.stockage.lire(T.cleStockage()) || {}, null, 1), 'application/json') }, '⚙️ Réglages (.json)'),
    h('button', { class: 'btn', onclick: () => T.telecharger(`${T.identite().poste}_chronologie.csv`, T.versCsv(T.chronologie().evenements.map(e => ({ Date: T.fdate(e.t), Fin: e.fin ? T.fdate(e.fin) : '', Voie: e.voie, Gravite: e.g, Evenement: e.titre, Detail: e.detail, Fenetre: e.fen, Preuve: e.id })))) }, '🕒 Chronologie (.csv)'),
    h('button', { class: 'btn', onclick: () => T.telecharger(`Chasse_IOC_${T.identite().poste}.ps1`, '\ufeff' + T.scriptChasse()) }, '🛰️ Script de chasse (.ps1)')),
    h('div', { class: 'petit doux' }, 'Astuce : enregistrer le fichier de réglages à côté du dossier de collecte. Le .bat le reprendra à la prochaine génération.')));
};

/* ---------------------------------------------------------------- reglages */
T.ouvrirReglages = () => {
  const R = T.reglages(), m = T.$('#modale'); m.innerHTML = '';
  const ch = (lib, input, aide) => h('div', { class: 'champ' }, h('label', {}, lib), input, aide ? h('div', { class: 'aide' }, aide) : '');
  const f = {
    client: h('input', { value: R.client || '' }), technicien: h('input', { value: R.technicien || '' }),
    decouverte: h('input', { type: 'datetime-local', value: (R.decouverte || '').replace(' ', 'T').slice(0, 16) }),
    debit: h('input', { type: 'number', step: 0.1, value: R.debit_montant_mbps || '' }), taille: h('input', { type: 'number', value: R.taille_base_mo || '' }), compression: h('input', { type: 'number', step: 0.5, value: R.compression || 4 }),
    mots: h('input', { value: (R.mots_cles_fuite || []).join(', ') }),
    lb: h('textarea', { rows: 4 }, (R.liste_blanche || []).map(l => `${l.valeur} ; ${l.note || ''}`).join('\n')),
    fm: h('textarea', { rows: 3 }, (R.fenetres_manuelles || []).map(w => `${w.debut} ; ${w.fin} ; ${w.motif || ''}`).join('\n')),
    notes: h('textarea', { rows: 3 }, R.notes || '')
  };
  const enregistrer = () => {
    T.majReglages({ client: f.client.value.trim(), technicien: f.technicien.value.trim(), decouverte: f.decouverte.value.replace('T', ' '), debit_montant_mbps: f.debit.value, taille_base_mo: f.taille.value, compression: f.compression.value,
      mots_cles_fuite: f.mots.value.split(',').map(x => x.trim()).filter(Boolean),
      liste_blanche: f.lb.value.split('\n').map(l => l.split(';')).filter(p => p[0].trim()).map(p => ({ valeur: p[0].trim(), note: (p[1] || '').trim() })),
      fenetres_manuelles: f.fm.value.split('\n').map(l => l.split(';')).filter(p => p.length >= 2 && T.pdate(p[0]) && T.pdate(p[1])).map(p => ({ debut: p[0].trim(), fin: p[1].trim(), motif: (p[2] || '').trim() })),
      notes: f.notes.value });
    m.classList.remove('ouvert'); T.rafraichir(); T.toast('Réglages enregistrés dans ce navigateur');
  };
  const importer = h('input', { type: 'file', accept: '.json', style: 'display:none', onchange: async e => { try { const j = JSON.parse(await e.target.files[0].text()); T.majReglages(j); m.classList.remove('ouvert'); T.rafraichir(); T.toast('Réglages importés'); } catch (er) { T.toast('Fichier illisible'); } } });
  m.append(h('div', { class: 'boite' }, h('header', {}, h('h3', {}, '⚙️ Réglages de cet incident'), h('button', { class: 'fermer', onclick: () => m.classList.remove('ouvert') }, '✕')),
    h('div', { class: 'corps' }, h('div', { class: 'champs' }, ch('🏥 Client (cabinet)', f.client), ch('🧑‍🔧 Technicien', f.technicien), ch('⏱️ Découverte de l\'incident', f.decouverte, 'Point de départ des 72 h CNIL')),
      h('h4', {}, '📤 Exfiltration'), h('div', { class: 'champs' }, ch('Débit montant (Mbit/s)', f.debit), ch('Taille base patients (Mo)', f.taille, 'vide = automatique'), ch('Compression (×)', f.compression)),
      h('h4', {}, '🕵️ Sites de fuite'), ch('Mots-clés (séparés par des virgules)', f.mots, 'Nom du cabinet, domaine, ville. Recherche locale uniquement.'),
      h('h4', {}, '⭐ Liste blanche'), ch('Une IP ou plage par ligne : IP ; note', f.lb, 'ex. 100.64.0.0/10 ; NetBird techniciens'),
      h('h4', {}, '🪟 Fenêtres en plus'), ch('Une par ligne : début ; fin ; motif', f.fm, 'ex. 2026-11-16 20:00 ; 2026-11-17 04:00 ; signalement du praticien'),
      h('h4', {}, '🗒️ Notes'), f.notes),
    h('footer', {}, importer, h('button', { class: 'btn', onclick: () => importer.click() }, '📂 Importer'),
      h('button', { class: 'btn', onclick: () => T.telecharger(`${T.D.collecte.nom}_reglages.json`, JSON.stringify(T.stockage.lire(T.cleStockage()) || {}, null, 1), 'application/json') }, '💾 Exporter'),
      h('button', { class: 'btn danger', onclick: () => { if (confirm('Effacer les réglages saisis dans ce navigateur ?')) { localStorage.removeItem(T.cleStockage()); T.invalider(); m.classList.remove('ouvert'); T.rafraichir(); } } }, 'Effacer'),
      h('button', { class: 'btn primaire', onclick: enregistrer }, 'Enregistrer'))));
  m.classList.add('ouvert');
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
  const tete = `<h1>Incident de sécurité – ${esc(R.client || id.poste)}</h1><div class="note">Poste ${esc(id.poste)} · collecte du ${esc(T.flong(id.date))} · rapport du ${esc(T.flong(new Date()))}${R.technicien ? ' · technicien ' + esc(R.technicien) : ''}</div>`;
  const cnil = `<div class="bloc"><b>⏱️ Notification CNIL (art. 33 RGPD)</b> : découverte le ${v.cnil ? esc(T.flong(v.cnil.decouverte)) : 'à renseigner'}${v.cnil ? ` · échéance des 72 h : <b>${esc(T.flong(v.cnil.echeance))}</b>` : ''}.<br><span class="note">La décision de notifier et d'informer les patients (art. 34) appartient au cabinet (responsable de traitement) et à son DPO.</span></div>`;
  const pire = ex.fenetres.reduce((m, f) => (!m || f.envoye > m.envoye) ? f : m, null);
  if (type === 'praticien') {
    const l = [];
    if (k.sessions) l.push(`🔓 Des connexions à distance ont été faites sur ce poste depuis Internet (${k.pays.map(T.nomPays).join(', ') || 'pays non déterminé'}).`);
    if (k.chiffres) l.push(`🔒 ${T.nb(k.chiffres)} fichiers ont été chiffrés par un rançongiciel.`);
    if (pire && ['PLAUSIBLE', 'PARTIELLE'].includes(pire.niveau)) l.push(`📤 Le volume envoyé sur Internet pendant l'intrusion (${T.nb(pire.envoye)} Mo) rend possible une copie des données patients.`);
    else if (pire) l.push('📤 Les volumes mesurés ne permettent pas une copie complète de la base patients depuis ce poste.');
    if (k.outils.length) l.push(`🧰 Des outils sensibles ont été lancés pendant l'intrusion (${esc(k.outils.slice(0, 6).join(', '))}).`);
    if (s.categories.length) l.push(`🏥 Données potentiellement concernées : ${esc(s.categories.map(x => x.categorie).slice(0, 4).join(', '))} (à confirmer).`);
    const a = ['Ne pas rallumer ni utiliser le poste concerné sans accord du technicien.', 'Changer les mots de passe listés par le technicien (logiciels en ligne, messagerie, banque).', 'Prévenir votre assureur cyber ; un dépôt de plainte est conseillé.', 'Décider avec votre DPO de la notification CNIL avant l\'échéance.'];
    return tete + cnil + `<h2>Ce qui s'est passé</h2><div class="bloc">${l.map(x => `<div>${esc(x)}</div>`).join('') || 'Analyse en cours.'}</div><h2>Ce que vous devez faire</h2><div class="bloc">${a.map(x => `<div>✅ ${esc(x)}</div>`).join('')}</div><p class="note">Ce document résume une analyse technique. Le rapport technique détaillé et sourcé est disponible auprès de votre prestataire.</p>`;
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
  const o = (location.hash || '').slice(1); T.aller(T.ONGLETS.some(x => x.id === o) ? o : 'vue');
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
  app.append(h('div', { class: 'accueil' }, h('div', { style: 'font-size:46px' }, '🛡️'), h('h1', {}, 'DigSpill'),
    h('p', { class: 'doux' }, 'Ce fichier ne contient pas encore de collecte. Le plus simple : glisser le dossier de collecte sur GENERER_INTERFACE.bat.'),
    h('div', { class: 'zone' }, h('p', {}, 'Ou ouvrir directement le dossier Collecte (contenant POSTE_date et POSTE_date_analyse) :'), h('button', { class: 'btn primaire', onclick: () => choix.click() }, '📂 Choisir le dossier'), choix,
      h('p', { class: 'petit pale' }, 'Lecture locale dans le navigateur. Sans le .bat : pas de pays des IP, ni listes noires, ni sites de fuite.'))));
};
/** fichier protege par mot de passe : PBKDF2-SHA256 + AES-256-CBC + HMAC-SHA256 (chiffrer puis authentifier) */
T.ecranMotDePasse = d => {
  const app = T.$('#app'), mdp = h('input', { type: 'password', class: 'texte', style: 'max-width:300px', placeholder: 'Mot de passe', autofocus: true }), msg = h('div', { class: 'petit', style: 'margin-top:8px;color:#b42318' });
  const ouvrir = async () => {
    msg.textContent = '⏳ Déchiffrement…';
    try {
      const b64 = s => Uint8Array.from(atob(s), c => c.charCodeAt(0)), sel = b64(d.sel), iv = b64(d.iv), donnees = b64(d.donnees), mac = b64(d.mac);
      const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(mdp.value), 'PBKDF2', false, ['deriveBits']);
      const bits = new Uint8Array(await crypto.subtle.deriveBits({ name: 'PBKDF2', salt: sel, iterations: d.iterations, hash: 'SHA-256' }, base, 512));
      const cleMac = await crypto.subtle.importKey('raw', bits.slice(32), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
      const aVerifier = new Uint8Array(iv.length + donnees.length); aVerifier.set(iv); aVerifier.set(donnees, iv.length);
      if (!await crypto.subtle.verify('HMAC', cleMac, mac, aVerifier)) { msg.textContent = '❌ Mot de passe incorrect (ou fichier modifié).'; return; }
      const cleAes = await crypto.subtle.importKey('raw', bits.slice(0, 32), { name: 'AES-CBC' }, false, ['decrypt']);
      const clair = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, cleAes, donnees);
      T.lancer(JSON.parse(new TextDecoder().decode(clair)));
    } catch (e) { msg.textContent = '❌ Déchiffrement impossible : ' + e.message; }
  };
  mdp.addEventListener('keydown', e => { if (e.key === 'Enter') ouvrir(); });
  app.innerHTML = '';
  app.append(h('div', { class: 'accueil' }, h('div', { style: 'font-size:46px' }, '🔐'), h('h1', {}, 'Fichier protégé'),
    h('p', { class: 'doux' }, `Collecte ${d.collecte || ''} · généré le ${d.genere_le || '?'}`), h('div', { class: 'zone' }, mdp, ' ', h('button', { class: 'btn primaire', onclick: ouvrir }, 'Ouvrir'), msg)));
};
document.addEventListener('DOMContentLoaded', T.demarrer);
