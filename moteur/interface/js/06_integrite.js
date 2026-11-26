/* ============================================================================
   06_integrite.js : scelle, horodatage par un tiers, chaine de possession,
   verification des fichiers dans le navigateur, PV de collecte imprimable
   ============================================================================ */
'use strict';


/* ---------------------------------------------------------------- lecture minimale d'un jeton RFC 3161 (DER) */
const derLire = (b, i) => {
  const tag = b[i]; let l = b[i + 1], d = i + 2;
  if (l & 0x80) { const k = l & 0x7f; l = 0; for (let j = 0; j < k; j++) l = l * 256 + b[d + j]; d += k; }
  return { tag, debut: i, contenu: d, fin: d + l, long: l };
};
const derEnfants = (b, n) => { const out = []; let i = n.contenu; while (i < n.fin) { const c = derLire(b, i); out.push(c); i = c.fin; } return out; };
const hexDe = (b, a, z) => [...b.slice(a, z)].map(x => x.toString(16).padStart(2, '0')).join('').toUpperCase();
const asciiDe = (b, n) => new TextDecoder(n.tag === 0x1e ? 'utf-16be' : 'utf-8').decode(b.slice(n.contenu, n.fin));
const OID_TSTINFO = [0x06, 0x0b, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x10, 0x01, 0x04];
const OID_CN = [0x06, 0x03, 0x55, 0x04, 0x03], OID_O = [0x06, 0x03, 0x55, 0x04, 0x0a];
const chercher = (b, motif, depuis = 0) => { outer: for (let i = depuis; i <= b.length - motif.length; i++) { for (let j = 0; j < motif.length; j++) if (b[i + j] !== motif[j]) continue outer; return i; } return -1; };
const noms = (b, oid, a, z) => { const out = []; let i = a; while ((i = chercher(b, oid, i)) >= 0 && i < z) { const s = derLire(b, i + oid.length); if ([0x0c, 0x13, 0x14, 0x16, 0x1e].includes(s.tag)) out.push(asciiDe(b, s)); i += oid.length; } return out; };

T.lireJeton = b64 => {
  try {
    const b = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
    const racine = derLire(b, 0), [infoStatut] = derEnfants(b, racine), statut = b[derEnfants(b, infoStatut)[0].contenu];
    const p = chercher(b, OID_TSTINFO); if (p < 0) return { statut, erreur: 'TSTInfo introuvable' };
    let n = derLire(b, p + OID_TSTINFO.length);            // [0] EXPLICIT
    n = derLire(b, n.contenu);                                // OCTET STRING
    const tst = derLire(b, n.contenu), ch = derEnfants(b, tst);
    const imprint = derEnfants(b, ch[2]), hash = hexDe(b, imprint[1].contenu, imprint[1].fin);
    const g = asciiDe(b, ch[4]), m = /^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/.exec(g);
    const date = m ? new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6])) : null;
    const serie = hexDe(b, ch[3].contenu, ch[3].fin).replace(/^0+(?=.)/, '');
    let tsa = '', org = '';
    const champTsa = ch.find(c => c.tag === 0xa0);
    if (champTsa) { tsa = noms(b, OID_CN, champTsa.contenu, champTsa.fin)[0] || ''; org = noms(b, OID_O, champTsa.contenu, champTsa.fin)[0] || ''; }
    if (!tsa) { const cns = noms(b, OID_CN, tst.fin, b.length); tsa = cns.find(c => /time|horodat|tsa|stamp/i.test(c)) || cns[1] || cns[0] || ''; }
    return { statut, accorde: statut === 0 || statut === 1, hash, date, serie, tsa, org };
  } catch (e) { return { erreur: 'jeton illisible : ' + e.message }; }
};

/* ---------------------------------------------------------------- scelles embarques */
T.sha256Hex = async donnees => [...new Uint8Array(await crypto.subtle.digest('SHA-256', typeof donnees === 'string' ? new TextEncoder().encode(donnees) : donnees))].map(x => x.toString(16).padStart(2, '0')).join('').toUpperCase();
T.scelles = () => T.memo('scelles', () => (T.D.scelles || []).map(s => {
  const elements = (s.texte || '').split(/\r?\n/).filter(l => /^[0-9A-F]{64}  \d+  /.test(l)).map(l => { const [h, t, ...c] = l.split('  '); return { sha256: h, taille: +t, chemin: c.join('  ') }; });
  const cree = (/Cree le\s*:\s*(.+)/.exec(s.texte || '') || [])[1] || '', par = (/Par\s*:\s*(.+)/.exec(s.texte || '') || [])[1] || '';
  const jeton = s.tsr ? T.lireJeton(s.tsr) : null;
  const horodateur = (/Horodateur\s*:\s*(.+)/.exec(s.horodatage || '') || [])[1] || '';
  return Object.assign({}, s, { elements, cree, par, jeton, horodateur, jetonConforme: !!(jeton && jeton.hash && jeton.hash === s.sha256 && jeton.accorde) });
}));
T.scelleActuel = () => { const s = T.scelles(); return s.find(x => x.actuel) || s[s.length - 1] || null; };
T.qrSvg = (texte, taille = 4) => { try { const q = qrcode(0, 'M'); q.addData(texte); q.make(); return q.createSvgTag({ cellSize: taille, margin: 2, scalable: true }); } catch (e) { return ''; } };

/* ---------------------------------------------------------------- chaine de possession */
T.chaine = () => T.memo('chaine', () => {
  const ev = [], add = (date, acteur, action, detail, preuve, icone) => { const d = T.pdate(date); ev.push({ date: d, brut: date, acteur, action, detail, preuve, icone }); };
  const info = T.texte('infos_collecte.txt'), champ = k => ((new RegExp('^' + k + '\\s*:\\s*(.+)$', 'mi')).exec(info) || [])[1] || '';
  const qui = champ('Technicien') ? `${champ('Technicien')}${champ('Societe') ? ' (' + champ('Societe') + ')' : ''}` : champ('Lance par');
  const log = T.texte('collecte.log').split(/\r?\n/).filter(Boolean);
  const debut = log[0], fin = log.reverse().find(l => /Collecte terminee/i.test(l)) || '';
  if (debut) add(debut.slice(0, 19), qui || '?', 'Collecte démarrée sur le poste', `${champ('Poste')} · mode ${champ('Mode') || '?'} · DigSpill ${champ('Version script') || '?'}`, 'collecte.log', '');
  const man = (T.D.fichiers || {}).manifeste_sha256;
  if (man) add(man.modifie || T.identite().date, qui || '?', 'Manifeste SHA256 de la collecte', `${T.nb(T.table('manifeste_sha256').length)} fichiers, chacun avec son empreinte`, 'manifeste_sha256#1', '');
  if (fin) add(fin.slice(0, 19), qui || '?', 'Collecte terminée', fin.slice(21).replace(/^=+\s*|\s*=+$/g, ''), 'collecte.log', '');
  const alog = T.texte('analyse.log').split(/\r?\n/).filter(Boolean);
  if (alog.length) add(alog[alog.length - 1].slice(0, 19), '?', "Analyse terminée (dossier _analyse, la collecte n'est pas modifiée)", `${T.nb(T.table('manifeste_analyse_sha256').length)} fichiers d'analyse dans leur propre manifeste`, 'analyse.log', '');
  for (const [k, f] of Object.entries(T.D.fichiers || {})) if (/^PV_COPIE_.*\.txt$/i.test(k)) {
    const t = f.texte || '', g = x => ((new RegExp(x + '\\s*:\\s*(.+)')).exec(t) || [])[1] || '';
    add(g('Date / heure').slice(0, 19), g('Operateur'), 'Seconde copie vérifiée (Copier-Preuves.ps1)', `${g('Destination')} · ${g('Resultat')}`, k, '');
  }
  for (const s of T.scelles()) {
    add(s.cree.slice(0, 19), s.par, `Scellé ${s.nom}`, `${s.elements.length} fichiers scellés · empreinte ${s.sha256.slice(0, 16)}…`, '', '');
    if (s.jeton && s.jeton.date) add(T.fdate(new Date(s.jeton.date)), s.jeton.tsa || s.horodateur || 'tiers', 'Horodatage par un tiers (jeton RFC 3161)', `${s.jetonConforme ? 'jeton conforme au scellé' : 'jeton NON conforme au scellé'} · n° ${s.jeton.serie}`, '', '');
  }
  add(/^\d{4}-\d\d-\d\d \d\d:\d\d$/.test(T.D.genere_le || '') ? T.D.genere_le + ':59' : T.D.genere_le, (T.D.generateur || '').replace(/^.* sur /, ''), "Fichier d'interface généré", T.D.generateur || '', '', '');
  return ev.filter(e => e.date).sort((a, b) => a.date - b.date);
});

/* ---------------------------------------------------------------- verification des fichiers dans le navigateur */
const MAX_NAVIGATEUR = 400 * 1024 * 1024;
T.verifierDossier = async (fichiers, progres) => {
  const nom = T.D.collecte.nom, carte = new Map();
  for (const f of fichiers) {
    const p = (f.webkitRelativePath || f.name).split('/'), i = p.findIndex(x => x === nom || x === nom + '_analyse' || x === nom + '_scelles');
    if (i >= 0) carte.set(p.slice(i).join('\\').toLowerCase(), f);
  }
  const attendus = [];
  for (const [table, racine] of [['manifeste_sha256', nom], ['manifeste_analyse_sha256', nom + '_analyse']])
    for (const r of T.table(table)) attendus.push({ chemin: racine + '\\' + r.Fichier, sha256: (r.SHA256 || '').toUpperCase(), taille: T.num(r.Taille), source: table, id: r._id });
  const sc = T.scelleActuel();
  if (sc) for (const e of sc.elements) attendus.push({ chemin: e.chemin, sha256: e.sha256, taille: e.taille, source: 'scellé ' + sc.nom, id: '' });
  if (sc) attendus.push({ chemin: (sc.chemin || ''), sha256: sc.sha256, taille: 0, source: 'fichier du scellé', id: '' });
  const res = { conformes: 0, modifies: [], manquants: [], tropGros: [], total: attendus.length };
  let k = 0;
  for (const a of attendus) {
    k++; if (progres && (k % 5 === 0 || k === attendus.length)) progres(k, attendus.length, a.chemin);
    const f = carte.get(a.chemin.toLowerCase());
    if (!f) { res.manquants.push(a); continue; }
    if (f.size > MAX_NAVIGATEUR) { res.tropGros.push(Object.assign({ octets: f.size }, a)); continue; }
    const h = await T.sha256Hex(await f.arrayBuffer());
    if (h === a.sha256) res.conformes++; else res.modifies.push(Object.assign({ obtenu: h }, a));
  }
  return res;
};

/* ---------------------------------------------------------------- ecran */
T.ECRANS.integrite = c => {
  const sc = T.scelleActuel(), ch = T.chaine(), R = T.reglages(), id = T.identite();
  c.append(h('h1', {}, 'Intégrité et preuve'), h('p', { class: 'sous-titre' }, "Prouver que les preuves n'ont pas bougé depuis la collecte, et dire qui les a eues entre les mains."));
  if (!sc) {
    c.append(h('div', { class: 'alerte n2' }, h('div', { class: 'ic' }, ''), h('div', {}, "Aucun scellé dans ce rapport : DigSpill → « Analyser une collecte » crée le scellé et le fait horodater.")));
  } else {
    const j = sc.jeton, qr = T.qrSvg(`DIGSPILL SCELLE ${sc.nom} SHA256 ${sc.sha256}`, 5);
    const etatJeton = !j ? h('span', { class: 'pill orange' }, 'pas encore horodaté') : j.erreur ? h('span', { class: 'pill rouge' }, '' + j.erreur)
      : sc.jetonConforme ? h('span', { class: 'pill vert' }, `horodaté le ${T.flong(new Date(j.date))}`) : h('span', { class: 'pill rouge' }, 'jeton non conforme au scellé');
    const zoneVerif = h('div', { class: 'petit', style: 'margin-top:8px' });
    c.append(h('div', { class: 'carte scelle-carte' },
      h('div', { class: 'scelle-grille' },
        h('div', {},
          h('div', { class: 'pale petit gras', style: 'letter-spacing:.6px;text-transform:uppercase' }, 'Empreinte du scellé (SHA-256)'),
          h('div', { class: 'mono scelle-empreinte', title: 'Cliquer pour copier', onclick: async () => T.toast(await T.copier(sc.sha256) ? 'Empreinte copiée' : 'Copie impossible') }, sc.sha256.replace(/(.{16})/g, '$1 ').trim()),
          h('div', { class: 'filtres', style: 'margin-top:10px' }, etatJeton, h('span', { class: 'pill gris' }, `${sc.elements.length} fichiers scellés`),
            h('span', { class: 'pill gris' }, `${T.nb(T.table('manifeste_sha256').length + T.table('manifeste_analyse_sha256').length)} fichiers sous manifeste`)),
          h('ul', { class: 'lignes', style: 'margin-top:8px' },
            h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, `Scellé ${sc.nom} créé le ${sc.cree || '?'} par ${sc.par || '?'}`)),
            j && !j.erreur ? h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, `Autorité : ${j.tsa || sc.horodateur || '?'}${j.org ? ' (' + j.org + ')' : ''} · jeton n° ${j.serie}`)) : '',
            h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, h('button', { class: 'btn petit', onclick: async () => {
              const ok = (await T.sha256Hex(sc.texte.replace(/\r?\n/g, '\r\n'))) === sc.sha256 || (await T.sha256Hex(sc.texte)) === sc.sha256;
              zoneVerif.innerHTML = '';
              zoneVerif.append(h('div', {}, ok ? 'Le texte du scellé embarqué redonne bien son empreinte.' : 'Le texte embarqué ne redonne pas l\'empreinte annoncée.'),
                j && !j.erreur ? h('div', {}, sc.jetonConforme ? 'Le jeton d\'horodatage porte sur cette empreinte exacte.' : 'Le jeton porte sur une autre empreinte.') : '',
                h('div', { class: 'pale' }, 'La signature du jeton se vérifie avec : openssl ts -verify -data ' + sc.nom + '.txt -in ' + sc.nom + '.tsr -CAfile <chaîne de l\'autorité>'));
            } }, 'Contrôler le scellé et son jeton'))), zoneVerif)),
        h('div', { class: 'scelle-qr', html: qr, title: 'Empreinte du scellé en QR code' })),
      h('details', { style: 'margin-top:10px' }, h('summary', { class: 'petit gras', style: 'cursor:pointer' }, 'Contenu exact du scellé'), h('pre', { class: 'apercu', style: 'margin-top:8px' }, sc.texte))));
  }
  // chaine de possession
  c.append(T.carte('Chaîne de possession', 'reconstituée depuis les journaux, manifestes, PV et scellés', ch.length ? h('ol', { class: 'chaine' }, ch.map(e => h('li', {},
    h('span', { class: 'chaine-ic' }, e.icone), h('div', {}, h('div', { class: 'gras' }, e.action), h('div', { class: 'petit doux' }, `${T.flong(e.date)} · ${e.acteur || '?'}`), h('div', { class: 'petit' }, e.detail)),
    h('div', { class: 'droite' }, e.preuve ? T.bp(e.preuve) : '')))) : T.vide('Journaux de DigSpill absents : impossible de retracer qui a eu les preuves.')));
  // verification des fichiers
  const etat = h('div', { class: 'petit doux', style: 'margin-top:8px' }), resultat = h('div');
  const choix = h('input', { type: 'file', webkitdirectory: true, multiple: true, style: 'display:none', onchange: async e => {
    resultat.innerHTML = ''; etat.textContent = 'Calcul des empreintes…';
    const r = await T.verifierDossier([...e.target.files], (k, n, p) => { etat.textContent = `${k} / ${n} · ${p.split('\\').pop()}`; });
    etat.textContent = `Terminé : ${T.nb(r.total)} empreintes attendues.`;
    resultat.append(h('div', { class: 'grille g4', style: 'margin:10px 0' }, T.kpi('', T.nb(r.conformes), 'fichiers conformes', 'vert'), T.kpi('', T.nb(r.modifies.length), 'fichiers modifiés', r.modifies.length ? 'rouge' : ''),
      T.kpi('', T.nb(r.manquants.length), 'absents de la sélection', r.manquants.length ? 'orange' : ''), T.kpi('', T.nb(r.tropGros.length), 'trop gros pour le navigateur')));
    const lignes = [...r.modifies.map(x => ({ e: 'modifié', ...x })), ...r.tropGros.map(x => ({ e: 'à vérifier avec Get-FileHash', ...x })), ...r.manquants.slice(0, 200).map(x => ({ e: 'absent', ...x }))];
    if (lignes.length) resultat.append(T.tableau([{ t: 'État', v: x => x.e }, { t: 'Fichier', v: x => h('span', { class: 'mono petit' }, x.chemin) }, { t: 'Attendu', v: x => h('span', { class: 'mono petit', title: x.sha256 }, x.sha256.slice(0, 16) + '…') },
      { t: 'Source', v: x => x.id ? T.bp(x.id) : x.source }], lignes, { hauteur: '360px' }));
    if (r.tropGros.length) resultat.append(h('pre', { class: 'apercu', style: 'margin-top:8px' }, r.tropGros.map(x => `(Get-FileHash -Algorithm SHA256 -LiteralPath '${x.chemin}').Hash -eq '${x.sha256}'`).join('\n')));
  } });
  c.append(T.carte('Vérifier les fichiers de preuve', 'dans ce navigateur, rien n\'est envoyé', h('ul', { class: 'lignes' },
    h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, 'Branchez le support des preuves (clé de collecte ou seconde copie).')),
    h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, `Choisissez le dossier Collecte (celui qui contient ${T.D.collecte.nom}).`)),
    h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, "DigSpill calcule ici l'empreinte de chaque fichier et la compare aux listes d'empreintes de la collecte et au scellé."))),
    h('button', { class: 'btn primaire', style: 'margin-top:8px', onclick: () => choix.click() }, 'Choisir le dossier et vérifier'), choix, etat, resultat));
  // valeur probante
  c.append(T.carte('Ce que vaut ce dossier', 'à valider avec un avocat ou l\'assureur', h('ul', { class: 'lignes' },
    h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, 'Manifestes SHA256 + scellé : on peut démontrer qu\'aucun fichier n\'a changé depuis sa collecte.')),
    h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, "Horodatage par un tiers : date opposable. Délivré par un prestataire qualifié eIDAS, il est présumé exact (art. 41 du règlement eIDAS).")),
    h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, 'PV de collecte signé (technicien, représentant du client) : qui a fait quoi, quand, avec quels outils.')),
    h('li', {}, h('span', { class: 'ic' }, ''), h('span', {}, "Pour aller plus loin : constat d'un commissaire de justice, ou prestataire de réponse à incident qualifié PRIS par l'ANSSI."))),
    h('div', { class: 'filtres', style: 'margin-top:10px' }, h('button', { class: 'btn primaire', onclick: () => T.imprimer('pv') }, 'PV de collecte et certificat d\'intégrité'))));
};

/* ---------------------------------------------------------------- PV imprimable + section du rapport technique */
T.sectionIntegriteHtml = () => {
  const sc = T.scelleActuel(), ch = T.chaine();
  if (!sc && !ch.length) return '';
  let html = '<h2>Intégrité et chaîne de possession</h2>';
  if (sc) html += `<div class="bloc"><b>Scellé ${esc(sc.nom)}</b> · empreinte SHA-256 <span class="pid">${esc(sc.sha256)}</span><br>${sc.jeton && sc.jetonConforme ? `Horodaté par un tiers le ${esc(T.flong(new Date(sc.jeton.date)))} (${esc(sc.jeton.tsa || sc.horodateur || '')}, jeton n° ${esc(sc.jeton.serie)}).` : 'Non horodaté par un tiers.'}</div>`;
  html += `<table><tr><th>Date</th><th>Action</th><th>Par</th><th>Détail</th></tr>${ch.map(e => `<tr><td>${esc(T.fcourt(e.date))}</td><td>${esc(e.action)}</td><td>${esc(e.acteur || '')}</td><td>${esc(e.detail)}</td></tr>`).join('')}</table>`;
  return html;
};
const rapportBase = T.rapportHtml;
T.rapportHtml = type => {
  if (type === 'pv') return T.pvHtml();
  const html = rapportBase(type);
  return type === 'technique' ? html.replace('<h2>Index des preuves citées</h2>', T.sectionIntegriteHtml() + '<h2>Index des preuves citées</h2>') : html;
};
T.pvHtml = () => {
  const id = T.identite(), R = T.reglages(), sc = T.scelleActuel(), ch = T.chaine(), info = T.texte('infos_collecte.txt');
  const champ = k => ((new RegExp('^' + k + '\\s*:\\s*(.+)$', 'mi')).exec(info) || [])[1] || '';
  const man = T.table('manifeste_sha256').length, mana = T.table('manifeste_analyse_sha256').length;
  const conteneurs = T.table('manifeste_sha256').filter(r => /\.(zip|raw|7z|aff4|mem|dmp)$/i.test(r.Fichier || '')).slice(0, 12);
  const qr = sc ? T.qrSvg(`DIGSPILL SCELLE ${sc.nom} SHA256 ${sc.sha256}`, 3) : '';
  const ligne = (k, v) => `<tr><th style="width:34%">${esc(k)}</th><td>${v}</td></tr>`;
  return `<div class="pv">
  <div class="pv-tete"><div><div class="pv-marque">DigSpill</div><h1>Procès-verbal de collecte et certificat d'intégrité</h1>
  <div class="note">Collecte ${esc(id.nom)} · document établi le ${esc(T.flong(new Date()))}</div></div><div class="pv-qr">${qr}</div></div>
  <h2>1. Identification</h2><table>
  ${ligne('Client (responsable de traitement)', esc(champ('Cabinet') || R.client || '……………………………………………'))}
  ${champ('Present') ? ligne('Présent pour le client', esc(champ('Present'))) : ''}
  ${champ('Ticket') ? ligne('N° de ticket', esc(champ('Ticket'))) : ''}
  ${champ('Motif') ? ligne('Motif de l\'intervention', esc(champ('Motif'))) : ''}
  ${ligne('Poste examiné', esc(champ('Poste') || id.poste))}
  ${ligne('Date et heure de la collecte', esc(champ('Date locale') || id.date) + (champ('Date UTC') ? ' · UTC ' + esc(champ('Date UTC')) : '') + (champ('Fuseau') ? ' · ' + esc(champ('Fuseau')) : ''))}
  ${ligne('Découverte de l\'incident', esc(R.decouverte ? T.flong(R.decouverte) : (champ('Decouverte') || '……………………………………………')))}
  </table>
  <h2>2. Intervenant et méthode</h2><table>
  ${ligne('Technicien', esc(champ('Technicien') || R.technicien || '……………………………………………') + (champ('Societe') ? ' · ' + esc(champ('Societe')) : '') + ' · compte utilisé : ' + esc(champ('Lance par') || '?'))}
  ${ligne('Outils', `DigSpill ${esc(champ('Version script') || '?')}` + (champ('Velociraptor') ? '<br>Velociraptor : ' + esc(champ('Velociraptor')) : ''))}
  ${ligne('Méthode', 'Exécution depuis une clé USB dédiée ; copie des journaux et artefacts sans les modifier ; manifeste SHA-256 de chaque fichier collecté ; analyse dans un dossier séparé, la collecte n\'étant pas modifiée.')}
  </table>
  <h2>3. Empreintes</h2><table>
  ${ligne('Scellé', sc ? `<span class="pid">${esc(sc.sha256)}</span><br>${esc(sc.nom)} · ${sc.elements.length} fichiers scellés` : 'non créé')}
  ${ligne('Horodatage par un tiers', sc && sc.jeton && sc.jetonConforme ? `${esc(T.flong(new Date(sc.jeton.date)))} · ${esc(sc.jeton.tsa || sc.horodateur || '')} · jeton n° ${esc(sc.jeton.serie)}` : 'aucun')}
  ${ligne('Manifestes', `${T.nb(man)} fichiers de collecte, ${T.nb(mana)} fichiers d'analyse, chacun avec son empreinte SHA-256`)}
  ${sc ? sc.elements.map(e => ligne(e.chemin.split('\\').pop(), `<span class="pid">${esc(e.sha256)}</span>`)).join('') : ''}
  ${conteneurs.map(r => ligne(r.Fichier, `<span class="pid">${esc(r.SHA256)}</span>`)).join('')}
  </table>
  <h2>4. Chaîne de possession</h2><table><tr><th>Date</th><th>Action</th><th>Par</th><th>Détail</th></tr>
  ${ch.map(e => `<tr><td>${esc(T.fcourt(e.date))}</td><td>${esc(e.action)}</td><td>${esc(e.acteur || '')}</td><td>${esc(e.detail)}</td></tr>`).join('')}</table>
  <h2>5. Vérification par un tiers</h2><div class="bloc note">Chaque fichier : <b>Get-FileHash -Algorithm SHA256</b> doit redonner l'empreinte du manifeste. Le scellé : son empreinte SHA-256 doit être celle ci-dessus. Le jeton : <b>openssl ts -verify -data ${esc(sc ? sc.nom : 'SCELLE')}.txt -in ${esc(sc ? sc.nom : 'SCELLE')}.tsr -CAfile &lt;chaîne de l'autorité&gt;</b>. Le fichier d'interface permet aussi de recalculer toutes les empreintes (écran « Intégrité et preuve »).</div>
  <h2>6. Observations</h2><div class="pv-lignes"></div>
  <h2>7. Signatures</h2><div class="pv-signatures">
  ${[['Le technicien', champ('Technicien') || R.technicien], ['Le représentant du client', champ('Present')], ['Témoin (facultatif)', '']].map(([x, n]) => `<div class="pv-sig"><b>${x}</b><div>Nom, qualité : ${esc(n || '')}</div><div>Date :</div><div class="pv-zone">Signature</div></div>`).join('')}</div>
  <p class="note" style="margin-top:14px">Document établi par un prestataire informatique. Il ne constitue pas un constat de commissaire de justice ; sa force probante est appréciée par le juge. Lorsque l'horodatage est délivré par un prestataire qualifié, le règlement (UE) n° 910/2014 « eIDAS » (art. 41) lui attache une présomption d'exactitude de la date et de l'heure et d'intégrité des données concernées.</p></div>`;
};
