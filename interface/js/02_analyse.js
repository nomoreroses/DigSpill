/* ============================================================================
   02_analyse.js : analyses (tout est calcule dans le navigateur, a partir des tableaux)
   ============================================================================ */
'use strict';

/* ======================================================================== IP */
T.LISTES = {
  tor: { nom: 'Noeuds de sortie Tor', cat: 'Tor', poids: 3 },
  firehol1: { nom: 'FireHOL niveau 1', cat: 'Liste noire', poids: 2 },
  blocklistde: { nom: 'blocklist.de (force brute)', cat: 'Force brute', poids: 2 },
  greensnow: { nom: 'GreenSnow (force brute)', cat: 'Force brute', poids: 2 },
  cins: { nom: 'CINS Army', cat: 'Liste noire', poids: 2 },
  feodo: { nom: 'abuse.ch Feodo (serveurs C2)', cat: 'C2', poids: 3 },
  spamhaus_drop: { nom: 'Spamhaus DROP', cat: 'Reseau hostile', poids: 3 }
};
const RX_FAI = /\b(orange|france telecom|opentransit|sfr|societe francaise du radiotelephone|free sas|proxad|free mobile|bouygues|numericable|completel|nordnet|k-net|coriolis|ozone|wanadoo|deutsche telekom|vodafone|telefonica|proximus|swisscom|comcast|verizon|charter|cox comm|bell canada|videotron|telenet|kpn|ziggo|telia|fastweb|iliad)\b/i;
const RX_HEBERGEUR = /(ovh|hetzner|digitalocean|linode|akamai connected cloud|vultr|choopa|the constant company|m247|leaseweb|contabo|scaleway|online s\.a\.s|ionos|hostinger|datacamp|cdn77|packethub|zenlayer|frantech|buyvm|ponynet|serverius|ipxo|aeza|stark industries|pq hosting|hostkey|selectel|timeweb|gcore|g-core|psychz|quadranet|colocrossing|hostwinds|kamatera|alibaba|tencent|huawei cloud|oracle|amazon|aws|google cloud|microsoft|azure|cloudflare|tor exit|privacy|vpn|proxy|hosting|hoster|server|datacenter|data center|cloud|bulletproof|vps|dedi)/i;
T.classerOperateur = lib => !lib ? '' : RX_FAI.test(lib) ? 'FAI grand public' : RX_HEBERGEUR.test(lib) ? 'Hebergeur / VPN / cloud' : 'Autre operateur';

T.geo = () => T.memo('geo', () => {
  const g = {};
  for (const l of (T.D.geo_asn || [])) {                // "ip \t debut \t fin \t asn \t pays \t libelle"
    const p = l.split('\t'); if (p.length < 6) continue;
    g[p[0]] = Object.assign(g[p[0]] || {}, { asn: p[3], pays: p[4] === 'None' ? '' : p[4], operateur: p[5] === 'Not routed' ? '' : p.slice(5).join(' ') });
  }
  for (const l of (T.D.geo_ville || [])) {              // "ip \t debut,fin,pays,region,,ville,cp,lat,lon,tz"
    const i = l.indexOf('\t'); const ip = l.slice(0, i); const c = T.parseCsv('a,b,c,d,e,f,g,h,i,j\n' + l.slice(i + 1))[0];
    if (!c) continue;
    const lat = parseFloat(c.h), lon = parseFloat(c.i);
    g[ip] = Object.assign(g[ip] || {}, { ville: c.f, region: c.d, lat: isNaN(lat) ? null : lat, lon: isNaN(lon) ? null : lon });
    if (!g[ip].pays) g[ip].pays = c.c;
  }
  for (const ip in g) g[ip].categorie = T.classerOperateur(g[ip].operateur);
  return g;
});

T.listeBlanche = () => (T.reglages().liste_blanche || []).filter(l => l && l.valeur);
T.estBlanche = ip => { for (const l of T.listeBlanche()) if (T.dansCidr(ip, l.valeur.trim())) return l.note || l.valeur; return ''; };

T.ipCollecte = () => T.memo('ipCollecte', () => {
  const ips = {};
  const ajout = (ip, o) => {
    ip = T.nettoyerIp(ip); if (!ip || ['-', '::1', '127.0.0.1', '0.0.0.0'].includes(ip)) return;
    const e = ips[ip] || (ips[ip] = { ip, type: T.typeIp(ip), succes: 0, echecs: 0, premier: '', dernier: '', comptes: new Set(), sources: new Set(), preuves: [], active: false });
    e.succes += o.succes || 0; e.echecs += o.echecs || 0;
    for (const d of [o.premier, o.dernier]) if (d) { if (!e.premier || d < e.premier) e.premier = d; if (!e.dernier || d > e.dernier) e.dernier = d; }
    String(o.comptes || '').split(';').map(x => x.trim()).filter(x => x && x !== '\\').forEach(x => e.comptes.add(x));
    String(o.sources || '').split(';').map(x => x.trim()).filter(Boolean).forEach(x => e.sources.add(x));
    if (o.preuve && e.preuves.length < 12 && !e.preuves.includes(o.preuve)) e.preuves.push(o.preuve);
    if (o.active) e.active = true;
    if (o.activeSuspecte) { e.activeSuspecte = true; e.processus = o.processus; }
  };
  const signature = {}; for (const r of T.table('processus_binaires')) signature[(r.Path || '').toLowerCase()] = r.Signature || '';
  for (const r of T.table('synthese_ip_connexions_reussies')) ajout(r.IP, { succes: T.num(r.NbEvenements, 1), premier: r.Premier, dernier: r.Dernier, comptes: r.Comptes, sources: r.Sources, preuve: r._id });
  for (const r of T.table('echecs_par_ip')) ajout(r.IP, { echecs: T.num(r.NbEchecs, 1), premier: r.Premier, dernier: r.Dernier, comptes: r.Comptes, sources: '4625 echecs', preuve: r._id });
  if (!T.table('echecs_par_ip').length) {          // collecte legere : agregation depuis le detail
    const agg = {};
    for (const r of T.table('echecs_connexion_4625')) { const a = agg[r.IP] || (agg[r.IP] = { n: 0, p: r.Date, d: r.Date, id: r._id }); a.n++; if (r.Date < a.p) a.p = r.Date; if (r.Date > a.d) a.d = r.Date; }
    for (const [ip, a] of Object.entries(agg)) ajout(ip, { echecs: a.n, premier: a.p, dernier: a.d, sources: '4625 echecs', preuve: a.id });
  }
  for (const r of T.table('sessions_reconstituees')) for (const ip of String(r.IP || '').split(/\s*\/\s*/)) ajout(ip, { premier: r.Debut, comptes: r.Compte, sources: 'session ' + (r.Type || ''), preuve: r._id });
  for (const r of T.table('tcp_connexions')) if (T.typeIp(r.RemoteAddress) === 'PUBLIQUE' && /established/i.test(r.State || 'Established')) {
    // suspect = processus lance depuis un dossier a risque, non signe, ou sans chemin connu
    const sig = signature[(r.Path || '').toLowerCase()];
    const suspect = RISQUE.test(r.Path || '') || (sig !== undefined && sig !== 'Valid') || !r.Path;
    ajout(r.RemoteAddress, { sources: `connexion active a la collecte (${r.Process || r.OwningProcess || '?'})`, preuve: r._id, active: true, activeSuspecte: suspect, processus: r.Path || r.Process });
  }
  return ips;
});

T.analyseIp = () => T.memo('analyseIp', () => {
  const geo = T.geo(), listes = T.D.listes || {};
  const lignes = Object.values(T.ipCollecte()).map(e0 => {
    const e = Object.assign({}, e0, { comptes: [...e0.comptes].sort().slice(0, 15), sources: [...e0.sources].sort() });
    Object.assign(e, { pays: '', asn: '', operateur: '', categorie: '', ville: '', lat: null, lon: null }, geo[e.ip] || {});
    e.listes = Object.entries(listes).filter(([id, l]) => (l || []).includes(e.ip)).map(([id]) => Object.assign({ id }, T.LISTES[id] || { nom: id, cat: 'Liste', poids: 2 }));
    e.blanche = T.estBlanche(e.ip);
    let s = 0; const r = [];
    if (e.type === 'PUBLIQUE' && e.succes) { s += 3; r.push('connexion reussie depuis Internet'); }
    if (e.type === 'VPN/CGNAT' && e.succes) { s += 1; r.push('connexion reussie depuis une plage VPN / CGNAT'); }
    if (e.categorie.startsWith('Hebergeur')) { s += 2; r.push('operateur hebergeur / VPN'); }
    if (e.pays && e.pays !== 'FR' && e.type === 'PUBLIQUE') { s += 1; r.push('pays ' + e.pays); }
    for (const l of e.listes) { s += l.poids; r.push('liste ' + l.nom); }
    if (e.echecs >= 100) { s += 1; r.push(`${e.echecs} echecs (force brute)`); }
    if (e.activeSuspecte) { s += 3; r.push(`connexion encore active a la collecte (${(e.processus || '').split('\\').pop()})`); }
    else if (e.active) r.push('connexion active a la collecte (processus signe)');
    if (e.blanche) { s = 0; r.length = 0; r.push('liste blanche : ' + e.blanche); }
    e.score = s; e.raisons = r;
    return e;
  });
  lignes.sort((a, b) => b.score - a.score || b.succes - a.succes || b.echecs - a.echecs);
  const pays = {};
  for (const e of lignes) {
    if (e.type !== 'PUBLIQUE' || !e.pays) continue;
    const p = pays[e.pays] || (pays[e.pays] = { pays: e.pays, ip: 0, succes: 0, echecs: 0 });
    p.ip++; if (e.succes && !e.blanche) p.succes++; p.echecs += e.echecs;
  }
  return { ips: lignes, pays: Object.values(pays).sort((a, b) => b.succes - a.succes || b.echecs - a.echecs) };
});

/* ======================================================================== chronologie */
T.VOIES = ['Sessions', 'Connexions', 'Force brute', 'Comptes', 'Executions', 'Fichiers', 'Navigation', 'Antivirus', 'Rancongiciel', 'Journaux', 'USB'];
const RX_OUTILS = /mimikatz|mimi\.exe|lazagne|procdump|rclone|winscp|filezilla|pscp|megasync|megacmd|anydesk|rustdesk|ngrok|cloudflared|chisel|advanced_(ip|port)_scanner|netscan|nmap|netpass|webbrowserpass|mailpass|chromepass|psexec|vssadmin|bcdedit|wbadmin|cipher|\b7z|winrar|rar\.exe|teamviewer|screenconnect/i;
const EVT_JOURNAUX = { 1102: 'Journal Securite efface', 104: 'Journal efface (System)', 4616: 'Heure systeme modifiee', 4719: "Politique d'audit modifiee",
  5001: 'Protection temps reel Defender desactivee', 5007: 'Configuration Defender modifiee', 7045: 'Service installe', 4697: 'Service installe (4697)',
  4698: 'Tache planifiee creee', 6005: 'Demarrage du poste', 6006: 'Arret propre', 6008: 'Arret inattendu', 1074: 'Arret / redemarrage demande' };

T.chronologie = () => T.memo('chrono', () => {
  const ev = [];
  const add = (t, voie, titre, g, detail, id, x = {}) => {
    const d = T.pdate(t); if (!d) return;
    const fen = T.fenDe(d);
    const e = Object.assign({ t: d, voie, titre, g: Math.min(3, g + (fen && g < 3 ? 1 : 0)), detail: String(detail || '').slice(0, 600), id, fen }, x);
    if (x.fin) { const f = T.pdate(x.fin); e.fin = f && f > d ? f : null; }
    ev.push(e);
  };
  for (const r of T.table('sessions_reconstituees')) {
    const g = r.TypeIP === 'PUBLIQUE' ? 3 : r.TypeIP === 'VPN/CGNAT' ? 2 : 0;
    add(r.Debut, 'Sessions', `Session ${r.Compte || '?'} (${r.Type || ''})`, g, `IP ${r.IP || '-'} (${r.TypeIP || ''}) · fin : ${r.FinPar || '?'} · ${r.DureeMin || '?'} min`, r._id, { fin: r.Fin, ip: r.IP, compte: r.Compte });
  }
  for (const r of T.table('ouvertures_session_4624')) {
    const ti = T.typeIp(r.IP);
    if (r.Type === '7' || (r.Type === '3' && !['PUBLIQUE', 'VPN/CGNAT'].includes(ti))) continue;
    add(r.Date, 'Connexions', `4624 type ${r.Type} ${r.Compte || ''}`, ti === 'PUBLIQUE' ? 3 : ti === 'VPN/CGNAT' ? 2 : 0, `IP ${r.IP || '-'} (${ti}) · poste ${r.Poste || '-'} · ${r.Authentification || ''}`, r._id, { ip: r.IP });
  }
  for (const r of T.table('rdp_authentifications_1149')) add(r.Date, 'Connexions', `1149 authentification RDP ${r.Utilisateur || ''}`, T.typeIp(r.IP) === 'PUBLIQUE' ? 2 : 0, `IP ${r.IP}`, r._id, { ip: r.IP });
  for (const r of T.table('identifiants_explicites_4648')) add(r.Date, 'Comptes', `4648 identifiants explicites : ${r.CompteUtilise || ''}`, 1, `par ${r.Auteur || ''} vers ${r.Serveur || ''} (${r.Processus || ''})`, r._id);
  const agg = {};
  for (const r of T.table('echecs_connexion_4625')) {
    const d = T.pdate(r.Date); if (!d) continue;
    const k = r.Date.slice(0, 13) + '|' + r.IP;
    const a = agg[k] || (agg[k] = { n: 0, t: d, comptes: new Set(), id: r._id, ip: r.IP }); a.n++; a.comptes.add(r.Compte);
  }
  for (const a of Object.values(agg)) add(a.t, 'Force brute', `${a.n} echec(s) depuis ${a.ip || '?'}`, a.n >= 50 ? 2 : 1, 'comptes essayes : ' + [...a.comptes].filter(Boolean).slice(0, 8).join(', '), a.id, { ip: a.ip, n: a.n });
  for (const r of T.table('evenements_comptes')) add(r.Date, 'Comptes', `${r.EventID} ${r.Action || ''} : ${r.CibleOuGroupe || ''} ${r.Membre || ''}`.trim(), ['4720', '4724', '4732', '4728', '4756'].includes(r.EventID) ? 3 : 1, `par ${r.Auteur || ''} ${r.Details || ''}`, r._id);
  let bruit = 0;
  for (const r of T.table('executions_chronologie')) {
    const sensible = r.OutilSensible === 'OUI' || RX_OUTILS.test(r.Programme || '');
    const enFen = !!r.Fenetre;
    if (!sensible && !enFen && ++bruit > 3000) continue;
    add(r.Date, 'Executions', r.Programme || '?', sensible && enFen ? 3 : sensible ? 2 : enFen ? 1 : 0, `${r.Source || ''} · ${r.Chemin || ''} ${r.Detail || ''}`, r._id, { compte: r.Compte });
  }
  const paquets = {};
  for (const r of T.table('usn_fenetres')) {
    const d = T.pdate(r.Date); if (!d) continue;
    if (r.Archive === 'OUI') { add(d, 'Fichiers', `Archive : ${r.Fichier}`, 3, `USN ${r.Raison || ''}`, r._id); continue; }
    const k = r.Date.slice(0, 15);
    const p = paquets[k] || (paquets[k] = { t: new Date(d.getFullYear(), d.getMonth(), d.getDate(), d.getHours(), Math.floor(d.getMinutes() / 10) * 10), n: 0, ex: [], id: r._id });
    p.n++; if (p.ex.length < 5) p.ex.push(r.Fichier);
  }
  for (const p of Object.values(paquets)) add(p.t, 'Fichiers', `${p.n} operation(s) fichier (USN)`, p.n >= 500 ? 2 : 1, p.ex.join(', '), p.id, { n: p.n });
  for (const r of T.table('acces_fichiers_lnk_jumplists_shellbags')) {
    const metier = r.DONNEES_METIER === 'OUI', ts = r.TSCLIENT === 'OUI';
    if (!metier && !ts && !r.Fenetre) continue;
    add(r.Date1 || r.Date2, 'Fichiers', `${ts ? 'Copie via \\\\tsclient' : metier ? 'Acces donnees metier' : 'Fichier ouvert'} : ${(r.Chemin || '').slice(-80)}`, ts ? 3 : metier ? 2 : 1, `${r.Source || ''} (${r.Date1Type || ''}) ${r.Utilisateur || ''}`, r._id);
  }
  for (const r of T.table('navigation_fenetres')) {
    const dom = (/^[a-z]+:\/\/([^/:]+)/i.exec(r.Url || '') || [])[1] || r.Url;
    add(r.Date, 'Navigation', dom + (r.Categorie ? ` (${r.Categorie})` : ''), ['PARTAGE / TRANSFERT', 'OUTILS / ACCES DISTANT'].includes(r.Categorie) ? 2 : r.Categorie ? 1 : 0, r.Titre, r._id);
  }
  for (const r of T.table('telechargements')) add(r.Date, 'Navigation', `Telechargement : ${(r.Fichier || '').split('\\').pop()}`, r.Fenetre ? 2 : 0, r.Url, r._id);
  for (const r of T.table('defender_detections')) add(r.InitialDetectionTime, 'Antivirus', `Defender : detection ${r.ThreatID || ''}`, 3, `${r.ProcessName || ''} ${r.Resources || ''} · action ${r.ActionSuccess || ''}`, r._id);
  for (const r of T.table('fichiers_chiffres_par_extension')) {
    const n = T.num(r.NbFichiers); if (n < 20) continue;
    add(r.Premier, 'Rancongiciel', `Chiffrement : ${T.nb(n)} fichiers ${r.Extension}`, 3, `${T.nb(T.num(r.TailleMo))} Mo en ${r.DureeMinutes} min · ex. ${r.Exemple || ''}`, r._id, { fin: r.Dernier });
  }
  for (const r of T.table('commandes_destructrices_4688')) add(r.Date, 'Rancongiciel', 'Commande destructrice', 3, r.CommandLine || r.Commande || Object.values(r).join(' '), r._id);
  for (const r of T.table('notes_rancon_candidates')) if (T.num(r.NbDossiers) >= 3) add(r.Derniere, 'Rancongiciel', `Note de rancon : ${r.Nom} (${r.NbDossiers} dossiers)`, 3, r.Exemples, r._id);
  for (const r of T.table('resume_evenements_cles')) if (EVT_JOURNAUX[r.EventID]) add(r.Date, 'Journaux', `${r.EventID} ${EVT_JOURNAUX[r.EventID]}`, ['1102', '104', '4616', '4719', '5001'].includes(r.EventID) ? 3 : 1, (r.Message || '').slice(0, 300), r._id);
  for (const r of T.table('usb_chronologie')) add(r.Date, 'USB', `USB : ${(r.Peripherique || '').slice(0, 60)}`, r.Fenetre ? 2 : 0, `${r.Source || ''} · serie ${r.Serie || '-'}`, r._id);
  ev.sort((a, b) => a.t - b.t);
  const compte = {}; ev.forEach(e => { compte[e.voie] = (compte[e.voie] || 0) + 1; });
  return { evenements: ev, voies: T.VOIES.filter(v => compte[v]), compte, tronque: Math.max(0, bruit - 3000) };
});

/* ======================================================================== exfiltration */
T.serieSrum = () => T.memo('srum', () => T.table('srum_total_par_releve').map(r => ({ t: T.pdate(r.Releve), envoye: T.num(r.EnvoyeMo), recu: T.num(r.RecuMo), app: r.PremiereAppliEnvoi || '', appMo: T.num(r.PremiereAppliEnvoyeMo), fen: r.Fenetre || '', id: r._id })).filter(p => p.t));
T.refSrum = () => T.memo('refSrum', () => {
  const r = T.table('srum_reference_par_app').find(x => (x.App || '').startsWith('(TOTAL'));
  return r ? { moyenne: T.num(r.MoyenneEnvoyeMo), p95: T.num(r.P95EnvoyeMo), max: T.num(r.MaxEnvoyeMo), releves: T.num(r.NbReleves), id: r._id } : null;
});
T.basesMetier = () => T.memo('bases', () => {
  const vus = {};
  for (const r of T.table('bases_metier')) {
    const ch = r.Chemin || '', taille = T.num(r.Taille); if (!ch || taille <= 0) continue;
    vus[ch.toLowerCase()] = { chemin: ch, mo: Math.round(taille / 1048576 * 10) / 10, sauvegarde: /sauvegarde|backup|\\save|\\old|\.bak|archive/i.test(ch), modification: r.Modification || '', id: r._id };
  }
  return Object.values(vus).sort((a, b) => b.mo - a.mo);
});
T.NIVEAUX = {
  LEGITIME: { lib: 'Fenêtre légitime (liste blanche)', cls: 'vert', icone: '⭐' },
  HABITUEL: { lib: 'Volume habituel du poste', cls: 'vert', icone: '🟢' },
  PLAUSIBLE: { lib: 'Copie de la base possible', cls: 'rouge', icone: '🔴' },
  PARTIELLE: { lib: 'Copie partielle possible', cls: 'orange', icone: '🟠' },
  EXCLUE_RESEAU: { lib: 'Copie complète exclue (réseau de ce poste)', cls: 'vert', icone: '🟢' },
  IMPOSSIBLE_LIGNE: { lib: 'Impossible par la ligne', cls: 'vert', icone: '🟢' },
  INCONNU: { lib: 'Non mesurable', cls: 'gris', icone: '⚪' }
};
T.exfil = () => T.memo('exfil', () => {
  const R = T.reglages(), serie = T.serieSrum(), ref = T.refSrum(), bases = T.basesMetier();
  const princ = bases.filter(b => !b.sauvegarde); const tailleAuto = (princ[0] || bases[0] || {}).mo || 0;
  const taille = T.num(R.taille_base_mo, 0) || tailleAuto, compression = T.num(R.compression, 0) || 4, debit = T.num(R.debit_montant_mbps, 0);
  const comp = taille ? taille / compression : 0;
  const apps = {};
  for (const r of T.table('srum_fenetres_vs_reference')) {
    if ((r.App || '').startsWith('(TOTAL')) continue;
    const w = apps[r.Fenetre] || (apps[r.Fenetre] = {}); const a = w[r.App] || (w[r.App] = { app: r.App, mo: 0, ecart: '', ids: [] });
    a.mo += T.num(r.EnvoyeMo); if (r.Ecart) a.ecart = r.Ecart; if (a.ids.length < 6) a.ids.push(r._id);
  }
  const d0 = serie.length ? serie[0].t : null, d1 = serie.length ? serie[serie.length - 1].t : null;
  const fenetres = T.fenetres().map(w => {
    let envoye = 0, picMax = 0; const ids = [];
    const finH = new Date(w.fin); finH.setMinutes(0, 0, 0); const lim = new Date(finH.getTime() + T.HEURE);
    for (const p of serie) if (p.fen.split(',').includes(w.id) || (p.t > w.debut && p.t <= lim)) { envoye += p.envoye; picMax = Math.max(picMax, p.envoye); ids.push(p.id); }
    const dureeS = (w.fin - w.debut) / 1e3;
    const capacite = debit ? debit * 1e6 / 8 * dureeS / 1048576 : null;
    const besoin = debit && comp ? comp * 1048576 * 8 / (debit * 1e6) / 60 : null;
    const couvre = !!(d0 && d1 && d0 <= w.debut && d1 >= w.fin);
    const constats = []; let niveau = 'INCONNU';
    // IP a l'origine de la fenetre : celles du motif et des sessions distantes qui la chevauchent
    const ipsFen = new Set((w.motif.match(/\b\d{1,3}(?:\.\d{1,3}){3}\b/g) || []));
    for (const r of T.table('sessions_reconstituees')) { const a = T.pdate(r.Debut), b = T.pdate(r.Fin) || a; if (a && ['PUBLIQUE', 'VPN/CGNAT'].includes(r.TypeIP) && a <= w.fin && b >= w.debut) String(r.IP || '').split(/\s*\/\s*/).forEach(x => x && ipsFen.add(T.nettoyerIp(x))); }
    const notes = [...ipsFen].map(T.estBlanche);
    const legitime = ipsFen.size > 0 && notes.every(Boolean);
    const releves = Math.max(1, ids.length);
    const habituel = ref && ref.p95 && envoye <= ref.p95 * releves && picMax <= ref.max;
    if (couvre) {
      if (comp && envoye >= 0.1 * comp && envoye < comp && habituel) { niveau = 'HABITUEL'; constats.push(`${T.nb(envoye)} Mo envoyés en ${releves} relevé(s) : comparable à l'activité habituelle du poste (≤ P95 × durée). Une petite copie partielle ne peut pas être exclue.`); }
      else if (comp && envoye >= comp) { niveau = 'PLAUSIBLE'; constats.push(`Le poste a envoyé ${T.nb(envoye)} Mo : autant ou plus que la base compressée (~${T.nb(comp)} Mo). Copie complète possible.`); }
      else if (comp && envoye >= 0.1 * comp) { niveau = 'PARTIELLE'; constats.push(`${T.nb(envoye)} Mo envoyés : une copie partielle (~${T.nb(envoye / comp * 100)} % de la base compressée) reste possible.`); }
      else if (comp) { niveau = 'EXCLUE_RESEAU'; constats.push(`Seulement ${T.nb(envoye, 1)} Mo envoyés pour une base de ~${T.nb(comp)} Mo compressée : copie complète par le réseau de ce poste exclue (si SRUM complet).`); }
      else constats.push(`${T.nb(envoye, 1)} Mo envoyés. Taille de la base inconnue : la renseigner dans les réglages pour conclure.`);
      if (ref && ref.max && picMax > ref.max) constats.push(`Pic de ${T.nb(picMax)} Mo/h, au-dessus du maximum habituel (${T.nb(ref.max)} Mo/h sur ${T.nb(ref.releves)} relevés).`);
    } else constats.push("SRUM ne couvre pas cette fenêtre : volume envoyé non mesurable.");
    if (capacite !== null && comp) {
      if (capacite < comp) {
        constats.push(`Débit montant ${T.nb(debit)} Mbit/s × ${T.nb(dureeS / 60)} min = ${T.nb(capacite)} Mo au maximum : physiquement impossible de sortir toute la base (~${T.nb(comp)} Mo) par la ligne.`);
        if (niveau === 'INCONNU') niveau = 'IMPOSSIBLE_LIGNE';
      } else constats.push(`La ligne permettait jusqu'à ${T.nb(capacite)} Mo pendant la fenêtre ; envoyer la base compressée demandait ~${T.nb(besoin)} min.`);
    }
    if (legitime) { niveau = 'LEGITIME'; constats.unshift(`Fenêtre ouverte depuis une IP de la liste blanche (${[...new Set(notes)].join(', ')}) : activité considérée légitime.`); }
    return { id: w.id, debut: w.debut, fin: w.fin, motif: w.motif, duree: Math.round(dureeS / 60), envoye, picMax, capacite, besoin, couvre, niveau, constats, legitime,
      apps: Object.values(apps[w.id] || {}).sort((a, b) => b.mo - a.mo).slice(0, 8), preuves: ids, preuveFenetre: w.preuve };
  });
  return { serie, ref, bases, fenetres, hyp: { taille, tailleAuto, compression, comp, debit } };
});
T.LIMITES_EXFIL = [
  "Un autre poste, un serveur ou un NAS du cabinet a pu servir : la borne ne vaut que pour ce poste.",
  "Les identifiants enregistrés (logiciels web, messagerie, NAS) permettent un accès sans passer par ce poste : non borné ici.",
  "Le taux de compression est une hypothèse (déduction) : une base Firebird ou SQL se compresse souvent de 3 à 10 fois.",
  "SRUM enregistre environ une fois par heure ; un arrêt brutal peut perdre le dernier relevé.",
  "Le trafic RDP inclut l'affichage de la session : un volume RDP élevé n'est pas à lui seul une exfiltration."
];

/* ======================================================================== visibilite */
const NOMS_JOURNAUX = {
  'Security': 'Sécurité (connexions, comptes)', 'System': 'Système (démarrages, services)',
  'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational': 'Sessions RDP (LSM)',
  'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational': 'Authentifications RDP (1149)',
  'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational': 'Connexions TCP RDP (131)',
  'Microsoft-Windows-PowerShell/Operational': 'PowerShell (4104)', 'Microsoft-Windows-Windows Defender/Operational': 'Defender',
  'Microsoft-Windows-SMBServer/Security': 'Partages SMB', 'Microsoft-Windows-Bits-Client/Operational': 'BITS (transferts)',
  'Microsoft-Windows-DNS-Client/Operational': 'Requêtes DNS', 'Microsoft-Windows-Sysmon/Operational': 'Sysmon',
  'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall': 'Pare-feu (événements)', 'Microsoft-Windows-TerminalServices-PnPDevices/Admin': 'Redirections RDP (PnP)'
};
const ANTI = [[/wevtutil(\.exe)?\s+(cl|clear-log)/i, 'Effacement de journal (wevtutil)'], [/clear-eventlog|remove-eventlog/i, 'Effacement de journal (PowerShell)'],
  [/fsutil(\.exe)?\s+usn\s+deletejournal/i, 'Suppression du journal USN'], [/vssadmin(\.exe)?\s+delete\s+shadows|shadowcopy\s+delete|win32_shadowcopy/i, 'Suppression des clichés VSS'],
  [/wbadmin(\.exe)?\s+delete/i, 'Suppression des sauvegardes Windows'], [/bcdedit.*recoveryenabled\s+no/i, 'Réparation au démarrage désactivée'],
  [/cipher(\.exe)?\s+\/w/i, "Effacement de l'espace libre (cipher /w)"], [/sdelete/i, 'Effacement sécurisé (SDelete)'],
  [/set-mppreference.*-disable|add-mppreference.*-exclusion/i, 'Defender modifié en ligne de commande'], [/auditpol(\.exe)?\s+\/(clear|remove|set)/i, "Politique d'audit modifiée"]];
const EVT_ANTI = { 1102: 'Journal Sécurité effacé', 104: 'Journal effacé', 4616: 'Heure système modifiée', 4719: "Politique d'audit modifiée", 5001: 'Protection temps réel Defender désactivée', 5007: 'Configuration Defender modifiée', 5013: 'Falsification de Defender bloquée' };

T.visibilite = () => T.memo('visi', () => {
  const sources = [], vus = new Set(), dateCollecte = T.pdate(T.identite().date);
  for (const r of T.table('journaux_couverture')) {
    vus.add(r.Journal);
    const d = T.pdate(r.PremierEvt), f = T.pdate(r.DernierEvt);
    sources.push({ source: NOMS_JOURNAUX[r.Journal] || r.Journal, detail: r.Journal, debut: d, fin: f, etat: /^oui$/i.test(r.Present) && d ? 'present' : 'absent', id: r._id });
  }
  for (const r of T.table('etat_journaux')) {
    if (vus.has(r.Journal)) { const s = sources.find(x => x.detail === r.Journal); if (s && /^false$/i.test(r.Active)) s.etat = 'desactive'; continue; }
    if (!['Microsoft-Windows-Sysmon/Operational', 'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall', 'Microsoft-Windows-TerminalServices-PnPDevices/Admin', 'Microsoft-Windows-DNS-Client/Operational'].includes(r.Journal)) continue;
    const existe = /^true$/i.test(r.Existe), actif = /^true$/i.test(r.Active), d = T.pdate(r.PlusAncien);
    sources.push({ source: NOMS_JOURNAUX[r.Journal] || r.Journal, detail: r.Journal, debut: d, fin: d ? dateCollecte : null, etat: existe && actif && d ? 'present' : existe ? 'desactive' : 'absent', id: r._id });
  }
  for (const [nom, table, col] of [['SRUM (volumes réseau)', 'srum_total_par_releve', 'Releve'], ['Exécutions (Prefetch / Amcache / BAM)', 'executions_chronologie', 'Date'], ['Navigation web', 'navigation_complete', 'Date'], ['Journal USN (fichiers)', 'usn_fenetres', 'Date']]) {
    let a = null, b = null;
    for (const r of T.table(table)) { const d = T.pdate(r[col]); if (d) { if (!a || d < a) a = d; if (!b || d > b) b = d; } }
    sources.push({ source: nom, detail: table, debut: a, fin: b, etat: a ? 'present' : 'absent', id: a ? `${table}#1` : '' });
  }
  const fw = T.table('parefeu_journalisation');
  if (fw.length) sources.push({ source: 'Journal du pare-feu Windows', detail: 'parefeu_journalisation', debut: null, fin: null, etat: fw.some(r => /^true$/i.test(r.LogAllowed)) ? 'present' : 'desactive', id: fw[0]._id });

  const fen = T.fenetres(); const grille = { heures: [], lignes: [] };
  if (fen.length) {
    let t0 = new Date(Math.min(...fen.map(w => +w.debut))); t0.setMinutes(0, 0, 0); t0 = new Date(+t0 - 24 * T.HEURE);
    let t1 = new Date(Math.max(...fen.map(w => +w.fin))); t1.setMinutes(0, 0, 0); t1 = new Date(+t1 + 12 * T.HEURE);
    if ((t1 - t0) / T.HEURE > 24 * 45) { t0 = new Date(Math.max(...fen.map(w => +w.debut))); t0.setMinutes(0, 0, 0); t0 = new Date(+t0 - 48 * T.HEURE); }
    const heures = []; for (let x = +t0; x <= +t1 && heures.length < 24 * 50; x += T.HEURE) heures.push(new Date(x));
    grille.heures = heures;
    for (const s of sources) grille.lignes.push({ source: s.source, valeurs: heures.map(x => {
      if (s.etat === 'desactive') return -1; if (s.etat === 'absent' || !s.debut) return -2;
      const fin = s.fin || dateCollecte, x1 = new Date(+x + T.HEURE);
      if (s.debut <= x && (!fin || x1 <= fin)) return 1; if (s.debut < x1 && (!fin || x < fin)) return 0.5; return 0; }) });
  }
  const parFenetre = fen.map(w => {
    const lignes = sources.map(s => {
      let st;
      if (s.etat !== 'present' || !s.debut) st = s.etat === 'desactive' ? 'désactivée' : 'absente';
      else if (s.debut <= w.debut && (!s.fin || s.fin >= w.fin)) st = 'couverte';
      else if (s.debut > w.fin || (s.fin && s.fin < w.debut)) st = 'non couverte';
      else st = 'partielle';
      return { source: s.source, statut: st, id: s.id };
    });
    return { id: w.id, debut: w.debut, fin: w.fin, motif: w.motif, sources: lignes, taux: lignes.length ? Math.round(100 * lignes.filter(l => l.statut === 'couverte').length / lignes.length) : 0 };
  });
  const anti = [];
  for (const nom of ['resume_evenements_cles', 'evenements_fenetres']) for (const r of T.table(nom)) if (EVT_ANTI[r.EventID]) anti.push({ date: r.Date || '', trace: `${r.EventID} ${EVT_ANTI[r.EventID]}`, detail: (r.Message || '').slice(0, 300), id: r._id });
  for (const [nom, cols] of [['commandes_destructrices_4688', null], ['executions_chronologie', ['Detail', 'Chemin']]]) for (const r of T.table(nom)) {
    const txt = cols ? cols.map(k => r[k] || '').join(' ') : Object.entries(r).filter(([k]) => k !== '_id').map(([, v]) => v).join(' ');
    for (const [rx, lib] of ANTI) if (rx.test(txt)) { anti.push({ date: r.Date || '', trace: lib, detail: txt.slice(0, 300), id: r._id }); break; }
  }
  const pref = T.texte('defender_preferences.txt');
  for (const m of pref.matchAll(/^(Exclusion\w+)\s*:\s*\{(.+)\}/gim)) if (m[2].trim()) anti.push({ date: '', trace: `Exclusion Defender (${m[1]})`, detail: m[2].trim(), id: 'defender_preferences.txt' });
  const vu = new Set(); const antiU = anti.sort((a, b) => a.date.localeCompare(b.date)).filter(a => { const k = a.date + a.trace; if (vu.has(k)) return false; vu.add(k); return true; });
  return { sources, grille, fenetres: parFenetre, anti: antiU };
});

/* ======================================================================== sante et RGPD */
const C_ID = 'Identité des patients', C_NIR = 'NIR (n° de sécurité sociale)', C_SANTE = 'Données de santé (art. 9 RGPD)', C_COORD = 'Coordonnées', C_IMG = 'Imagerie médicale', C_MAIL = 'Courriels (patients, confrères)', C_BANQUE = 'Règlements / données bancaires';
T.REGLES_SANTE = [
  [/axisante|axi_database|\\axi\\/i, 'AxiSanté (CGM)', [C_ID, C_NIR, C_SANTE, C_COORD]], [/medistory|\.4dd\b|\.4dindx\b/i, 'MediStory (Prokov)', [C_ID, C_NIR, C_SANTE, C_COORD]],
  [/hellodoc/i, 'HelloDoc', [C_ID, C_NIR, C_SANTE, C_COORD]], [/crossway/i, 'Crossway (CGM)', [C_ID, C_NIR, C_SANTE, C_COORD]], [/weda\.fr|\bweda\b/i, 'Weda', [C_ID, C_NIR, C_SANTE, C_COORD]],
  [/logos_?w/i, 'Logos_w (dentaire)', [C_ID, C_NIR, C_SANTE, C_COORD, C_BANQUE]], [/\\julie\\|julie\.fdb|juliesolutions/i, 'Julie (dentaire)', [C_ID, C_NIR, C_SANTE, C_COORD, C_BANQUE]],
  [/desmos/i, 'Desmos (dentaire)', [C_ID, C_NIR, C_SANTE, C_COORD]], [/visiodent|veasy/i, 'Visiodent / Veasy (dentaire)', [C_ID, C_NIR, C_SANTE, C_COORD]],
  [/sidexis|carestream|\\rvg|vatech|ez.?dent|romexis|dentalimaging/i, 'Imagerie dentaire', [C_ID, C_IMG, C_SANTE]], [/\.dcm\b|dicom|\\pacs\\/i, 'Imagerie DICOM', [C_ID, C_IMG, C_SANTE]],
  [/doctolib/i, 'Doctolib (agenda en ligne)', [C_ID, C_COORD, C_SANTE]], [/maiia|keldoc/i, 'Agenda en ligne', [C_ID, C_COORD, C_SANTE]],
  [/amelipro|espacepro\.ameli|ameli\./i, 'Ameli / Espace pro', [C_ID, C_NIR, C_SANTE]], [/mssante|apicrypt|lifen/i, 'Messagerie sécurisée de santé', [C_ID, C_SANTE, C_MAIL]],
  [/dmp\.fr|monespacesante/i, 'DMP / Mon espace santé', [C_ID, C_NIR, C_SANTE]], [/ordonnance/i, 'Ordonnances', [C_ID, C_SANTE]], [/compte.?rendu/i, 'Comptes rendus', [C_ID, C_SANTE]],
  [/patient/i, "Fichiers « patients »", [C_ID]], [/\.pst\b|\.ost\b/i, 'Boîte Outlook', [C_MAIL, C_ID]], [/\.fdb\b|\.gdb\b/i, 'Base Firebird (logiciel métier probable)', [C_ID, C_SANTE]],
  [/\.mdf\b|\.ldf\b|\.ndf\b/i, 'Base SQL Server (logiciel métier probable)', [C_ID, C_SANTE]], [/\.accdb\b|\.mdb\b/i, 'Base Access', [C_ID]]];
const SOURCES_SANTE = [['bases_metier', 'Base présente sur le disque', ['Chemin']], ['acces_donnees_metier', 'Accès aux données métier', null],
  ['acces_fichiers_lnk_jumplists_shellbags', 'Fichier ouvert (LNK / ShellBags)', ['Chemin']], ['usn_fenetres', 'Fichier modifié pendant une fenêtre', ['Fichier']],
  ['navigation_fenetres', 'Site consulté pendant une fenêtre', ['Url', 'Titre']], ['navigation_sites_sensibles', 'Site santé / métier consulté', ['Url']],
  ['telechargements', 'Téléchargement', ['Fichier', 'Url']], ['identifiants_navigateurs', 'Identifiant enregistré', ['Site']]];
T.JOURS = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
T.ouvert = (d, horaires) => {
  const j = (d.getDay() + 6) % 7, plage = String(horaires[j] ?? horaires[String(j)] ?? '');
  for (const p of plage.split(',')) { const m = /(\d{1,2}):(\d\d)\s*-\s*(\d{1,2}):(\d\d)/.exec(p); if (m) { const a = +m[1] * 60 + +m[2], b = +m[3] * 60 + +m[4], x = d.getHours() * 60 + d.getMinutes(); if (x >= a && x < b) return true; } }
  return false;
};
T.sante = () => T.memo('sante', () => {
  const trouves = {};
  for (const [table, lib, cols] of SOURCES_SANTE) for (const r of T.table(table)) {
    const txt = cols ? cols.map(k => r[k] || '').join(' ') : Object.entries(r).filter(([k]) => k !== '_id').map(([, v]) => v).join(' ');
    for (const [rx, logiciel, cats] of T.REGLES_SANTE) if (rx.test(txt)) {
      const t = trouves[logiciel] || (trouves[logiciel] = { logiciel, categories: cats, traces: {}, preuves: [] });
      t.traces[lib] = (t.traces[lib] || 0) + 1;
      if (t.preuves.length < 8) t.preuves.push({ id: r._id, ou: lib, extrait: txt.slice(0, 160), date: r.Date || r.Date1 || r.Modification || '', fen: !!r.Fenetre });
      break;
    }
  }
  const cats = {};
  for (const t of Object.values(trouves)) for (const c of t.categories) (cats[c] = cats[c] || new Set()).add(t.logiciel);
  const horaires = T.reglages().horaires || T.REGLAGES_DEFAUT.horaires;
  const sessions = T.table('sessions_reconstituees').map(r => {
    const d = T.pdate(r.Debut), f = T.pdate(r.Fin); if (!d) return null;
    return { debut: d, fin: f, compte: r.Compte, ip: r.IP, typeIp: r.TypeIP, jour: T.JOURS[(d.getDay() + 6) % 7], hors: !T.ouvert(d, horaires) || (f && !T.ouvert(f, horaires)), id: r._id };
  }).filter(Boolean);
  return { logiciels: Object.values(trouves).sort((a, b) => Object.values(b.traces).reduce((x, y) => x + y, 0) - Object.values(a.traces).reduce((x, y) => x + y, 0)),
    categories: Object.entries(cats).map(([c, s]) => ({ categorie: c, logiciels: [...s] })),
    pendant: Object.values(trouves).filter(t => t.preuves.some(p => p.fen)).map(t => t.logiciel),
    sessions, horsHoraires: sessions.filter(s => s.hors && ['PUBLIQUE', 'VPN/CGNAT'].includes(s.typeIp)) };
});

/* ======================================================================== IOC, chasse, memoire */
const HEX = /^[0-9a-f]+$/i;
const normHash = h => { h = String(h || '').trim().toUpperCase(); if (h.startsWith('0000') && h.length === 44) h = h.slice(4); return HEX.test(h) && [32, 40, 64].includes(h.length) ? h : ''; };
T.hachages = () => T.memo('hachages', () => {
  const vus = {};
  const add = (h, nom, chemin, source, date, id, rem = '') => {
    h = normHash(h); if (!h) return;
    const e = vus[h] || (vus[h] = { hash: h, type: { 32: 'MD5', 40: 'SHA1', 64: 'SHA256' }[h.length], noms: [], chemins: [], sources: [], date, preuves: [], remarque: rem });
    for (const [l, v] of [[e.noms, nom], [e.chemins, chemin], [e.sources, source]]) if (v && !l.includes(v)) l.push(v);
    if (!e.preuves.includes(id)) e.preuves.push(id);
  };
  for (const r of T.table('ioc_hachages')) for (const c of ['SHA256', 'SHA1']) add(r[c], r.Nom, r.Chemin, r.Source, r.Date, r._id, r.Remarque);
  for (const r of T.table('binaires_suspects')) add(r.SHA256, (r.Chemin || '').split('\\').pop(), r.Chemin, `Binaire suspect (${r.Source || ''})`, r.Creation, r._id, `signature ${r.Signature || '?'}`);
  for (const r of T.table('outils_suspects')) add(r.SHA256, (r.Chemin || '').split('\\').pop(), r.Chemin, 'Outil présent sur le disque', r.Creation, r._id);
  for (const r of T.table('processus_binaires')) if (r.Signature !== 'Valid') add(r.SHA256, (r.Path || '').split('\\').pop(), r.Path, `Processus en cours (signature ${r.Signature || 'absente'})`, '', r._id);
  return Object.values(vus).sort((a, b) => (a.type !== 'SHA256') - (b.type !== 'SHA256') || String(a.noms[0]).localeCompare(String(b.noms[0])));
});
const RISQUE = /\\(users\\public|programdata|perflogs|windows\\temp|appdata\\local\\temp|\$recycle\.bin|music|downloads|t[ée]l[ée]chargements)\\/i;
T.iocs = () => T.memo('iocs', () => {
  const h = T.hachages(), noms = new Set();
  for (const e of h) for (const n of e.noms) if (n && /\.\w{2,4}$/.test(n) && !/^(\(menace|svchost\.exe$|explorer\.exe$)/i.test(n)) noms.add(n);
  const taches = [], services = [], comptes = [];
  for (const r of T.table('taches_planifiees')) {
    const cmd = Object.entries(r).filter(([k]) => /task to run|t.che . ex.cuter|actions?$|arguments/i.test(k)).map(([, v]) => v).join(' ');
    if (RISQUE.test(cmd) || /-enc(odedcommand)?\s|frombase64|iex\s*\(|downloadstring|mshta|rundll32.*\\users\\/i.test(cmd)) {
      const nom = (Object.entries(r).find(([k]) => /^taskname$|nom de la t/i.test(k)) || [])[1]; if (nom) taches.push({ nom, commande: cmd.slice(0, 200), id: r._id });
    }
  }
  for (const r of T.table('services')) { const ch = r.PathName || ''; if (RISQUE.test(ch)) services.push({ nom: r.Name || '', chemin: ch.slice(0, 200), id: r._id }); }
  const fen = T.fenetres();
  for (const r of T.table('evenements_comptes')) if (r.EventID === '4720') {
    const d = T.pdate(r.Date), nom = (r.CibleOuGroupe || '').split('\\').pop();
    if (nom && (!fen.length || fen.some(w => d && d >= w.debut && d <= w.fin))) comptes.push({ nom, date: r.Date, id: r._id });
  }
  const ext = T.table('fichiers_chiffres_par_extension').filter(r => T.num(r.NbFichiers) >= 50).map(r => r.Extension).filter(Boolean).slice(0, 5);
  const notes = T.table('notes_rancon_candidates').filter(r => T.num(r.NbDossiers) >= 10).map(r => r.Nom).filter(Boolean).slice(0, 5);
  const pub = T.analyseIp().ips.filter(e => e.type === 'PUBLIQUE' && !e.blanche);
  const ip = pub.filter(e => e.succes || e.activeSuspecte).map(e => ({ ip: e.ip, pays: e.pays, score: e.score }));
  const ipBrute = pub.filter(e => !e.succes && !e.activeSuspecte && e.echecs >= 20 && e.score >= 3).map(e => ({ ip: e.ip, pays: e.pays, score: e.score }));
  return { ip: ip.slice(0, 200), ipBrute: ipBrute.slice(0, 500), hachages: h.slice(0, 500).map(e => ({ hash: e.hash, type: e.type, nom: e.noms[0] || '' })), fichiers: [...noms].sort().slice(0, 200), taches, services, comptes, extensions: ext, notes };
});
T.dejaVu = () => T.memo('dejaVu', () => {
  const i = T.iocs(), moi = { ip: new Set([...i.ip, ...i.ipBrute].map(x => x.ip)), sha256: new Set(i.hachages.filter(x => x.type === 'SHA256').map(x => x.hash)),
    sha1: new Set(i.hachages.filter(x => x.type === 'SHA1').map(x => x.hash)), fichiers: new Set(i.fichiers.map(x => x.toLowerCase())) };
  const out = [];
  for (const [cid, a] of Object.entries(T.D.memoire || {})) {
    if (cid === T.D.collecte.nom) continue;
    const communs = [];
    for (const k of Object.keys(moi)) for (const v of [].concat(a[k] || [])) {
      const cle = k === 'fichiers' ? String(v).toLowerCase() : k === 'ip' ? String(v) : String(v).toUpperCase();
      if (moi[k].has(cle)) communs.push({ type: k, valeur: cle });
    }
    if (communs.length) out.push({ collecte: cid, poste: a.poste || '', client: a.client || '', date: a.date || '', communs });
  }
  return out;
});
const psListe = vals => { const p = [...vals].map(v => `'${String(v).replace(/[^\x20-\x7e]/g, '?').replace(/'/g, "''")}'`); return p.length ? `@(${p.join(', ')})` : '@()'; };
T.scriptChasse = () => {
  const i = T.iocs(), id = T.identite(), ref = `${id.poste}_${(id.date || '').slice(0, 10)}`.replace(/[^\w.-]/g, '_');
  const sha256 = i.hachages.filter(x => x.type === 'SHA256').map(x => x.hash), sha1 = i.hachages.filter(x => x.type === 'SHA1').map(x => x.hash);
  return `<#
  Chasse aux IOC - incident ${ref}
  Genere le ${T.fdate(new Date()).slice(0, 16)} par l'interface de triage forensique.
  Composant Datto RMM (PowerShell, a executer en SYSTEM). LECTURE SEULE : ne supprime et ne modifie rien.
  Variables de composant facultatives :
    JoursEvt (defaut 30) : profondeur de recherche dans les journaux
    UdfNum   (ex. 10)    : numero du champ personnalise ou ecrire le resume (vide = pas d'ecriture)
  Sortie : resume dans la sortie standard + C:\\ProgramData\\TriageIOC\\chasse_${ref}.csv
  Code retour : 0 = rien trouve, 1 = au moins une correspondance.
#>
$ErrorActionPreference = 'SilentlyContinue'
$Jours = if ($env:JoursEvt) { [int]$env:JoursEvt } else { 30 }
$Depuis = (Get-Date).AddDays(-$Jours)
$IpIoc   = ${psListe(i.ip.map(x => x.ip))}
$IpBrute = ${psListe(i.ipBrute.map(x => x.ip))}
$Sha256  = ${psListe(sha256)}
$Sha1    = ${psListe(sha1)}
$Noms    = ${psListe(i.fichiers)}
$Taches  = ${psListe(i.taches.map(t => t.nom.split('\\').pop()))}
$Svcs    = ${psListe(i.services.map(s => s.nom))}
$Comptes = ${psListe(i.comptes.map(x => x.nom))}
$Ext     = ${psListe(i.extensions)}
$Notes   = ${psListe(i.notes)}
$Trouve = New-Object System.Collections.Generic.List[object]
function Hit($type, $valeur, $detail) { $Trouve.Add([pscustomobject]@{ Poste = $env:COMPUTERNAME; Type = $type; IOC = $valeur; Detail = "$detail" }) }

# 1. Fichiers : noms connus, puis hachage des executables des dossiers a risque
$sha256Set = @{}; foreach ($h in $Sha256) { $sha256Set[$h] = 1 }
$sha1Set = @{}; foreach ($h in $Sha1) { $sha1Set[$h] = 1 }
$nomSet = @{}; foreach ($n in $Noms) { $nomSet[$n.ToLower()] = 1 }
foreach ($r in @('C:\\Users', 'C:\\ProgramData', 'C:\\Windows\\Temp', 'C:\\PerfLogs')) {
    Get-ChildItem -LiteralPath $r -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -lt 200MB -and ($nomSet.ContainsKey($_.Name.ToLower()) -or $_.Extension -in '.exe', '.dll', '.ps1', '.bat', '.scr') } |
        ForEach-Object {
            $f = $_
            $connu = $nomSet.ContainsKey($f.Name.ToLower())
            if ($connu) { Hit 'Nom de fichier' $f.Name $f.FullName }
            if ($connu -or $f.FullName -match '\\\\(Users\\\\Public|ProgramData|Temp|Music|Downloads)\\\\') {
                if ($sha256Set.Count) { $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash; if ($h -and $sha256Set.ContainsKey($h)) { Hit 'SHA256' $h $f.FullName } }
                if ($sha1Set.Count) { $h1 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA1).Hash; if ($h1 -and $sha1Set.ContainsKey($h1)) { Hit 'SHA1' $h1 $f.FullName } }
            }
        }
}

# 2. Reseau : connexions actives, journaux de connexion (4624 / 4625 / RDP 1149), journal du pare-feu
if ($IpIoc.Count) {
    $ipSet = @{}; foreach ($i in $IpIoc) { $ipSet[$i] = 1 }
    Get-NetTCPConnection | Where-Object { $ipSet.ContainsKey($_.RemoteAddress) } | ForEach-Object { Hit 'Connexion TCP active' $_.RemoteAddress "port $($_.RemotePort) pid $($_.OwningProcess)" }
    foreach ($q in @(@{ L = 'Security'; I = 4624, 4625 }, @{ L = 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'; I = 1149 })) {
        Get-WinEvent -FilterHashtable @{ LogName = $q.L; Id = $q.I; StartTime = $Depuis } -MaxEvents 50000 | ForEach-Object {
            $x = [xml]$_.ToXml(); $d = @{}; foreach ($n in $x.Event.EventData.Data) { $d[$n.Name] = $n.'#text' }
            foreach ($n in $x.Event.UserData.EventXML.ChildNodes) { $d[$n.LocalName] = $n.InnerText }
            $ip = if ($d['IpAddress']) { $d['IpAddress'] } else { $d['Param3'] }
            if ($ip -and $ipSet.ContainsKey($ip)) { Hit "Evenement $($_.Id)" $ip "$($_.TimeCreated.ToString('yyyy-MM-dd HH:mm')) $($d['TargetUserName'])$($d['Param1'])" }
        }
    }
    $fw = "$env:SystemRoot\\System32\\LogFiles\\Firewall\\pfirewall.log"
    if (Test-Path -LiteralPath $fw) { Select-String -LiteralPath $fw -SimpleMatch -Pattern $IpIoc | Select-Object -First 50 | ForEach-Object { Hit 'Journal pare-feu' '' $_.Line } }
}

# 2 bis. IP de force brute vues sur ce poste : seules les connexions REUSSIES comptent (4624 / 1149)
if ($IpBrute.Count) {
    $bfSet = @{}; foreach ($i in $IpBrute) { $bfSet[$i] = 1 }
    foreach ($q in @(@{ L = 'Security'; I = 4624 }, @{ L = 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'; I = 1149 })) {
        Get-WinEvent -FilterHashtable @{ LogName = $q.L; Id = $q.I; StartTime = $Depuis } -MaxEvents 50000 | ForEach-Object {
            $x = [xml]$_.ToXml(); $d = @{}; foreach ($n in $x.Event.EventData.Data) { $d[$n.Name] = $n.'#text' }
            foreach ($n in $x.Event.UserData.EventXML.ChildNodes) { $d[$n.LocalName] = $n.InnerText }
            $ip = if ($d['IpAddress']) { $d['IpAddress'] } else { $d['Param3'] }
            if ($ip -and $bfSet.ContainsKey($ip)) { Hit "Connexion REUSSIE depuis une IP de force brute ($($_.Id))" $ip "$($_.TimeCreated.ToString('yyyy-MM-dd HH:mm')) $($d['TargetUserName'])$($d['Param1'])" }
        }
    }
}

# 3. Persistance et comptes
foreach ($t in $Taches) { Get-ScheduledTask | Where-Object { $_.TaskName -eq $t } | ForEach-Object { Hit 'Tache planifiee' $t (($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ; ') } }
foreach ($s in $Svcs) { Get-CimInstance Win32_Service | Where-Object { $_.Name -eq $s } | ForEach-Object { Hit 'Service' $s $_.PathName } }
foreach ($c in $Comptes) { Get-LocalUser | Where-Object { $_.Name -eq $c } | ForEach-Object { Hit 'Compte local' $c "active=$($_.Enabled) derniere connexion=$($_.LastLogon)" } }

# 4. Traces de rancongiciel (extensions, notes), 4 niveaux de dossiers par disque
if ($Ext.Count -or $Notes.Count) {
    $noteSet = @{}; foreach ($n in $Notes) { $noteSet[$n.ToLower()] = 1 }
    foreach ($v in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
        Get-ChildItem -LiteralPath ($v.DeviceID + '\\') -Recurse -File -Force -Depth 4 -ErrorAction SilentlyContinue |
            Where-Object { $nm = $_.Name; $noteSet.ContainsKey($nm.ToLower()) -or ($Ext | Where-Object { $_ -and $nm -like "*$_" }) } |
            Select-Object -First 20 | ForEach-Object { Hit 'Trace rancongiciel' $_.Name $_.FullName }
    }
}

# Resultat
$dir = 'C:\\ProgramData\\TriageIOC'; New-Item -ItemType Directory -Path $dir -Force | Out-Null
$Trouve | Export-Csv -LiteralPath (Join-Path $dir 'chasse_${ref}.csv') -NoTypeInformation -Encoding UTF8
$resume = if ($Trouve.Count) { "IOC ${ref} : $($Trouve.Count) correspondance(s) - " + (($Trouve | Group-Object Type | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ') } else { "IOC ${ref} : rien trouve ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))" }
Write-Output $resume
$Trouve | Select-Object -First 40 | Format-Table -AutoSize | Out-String -Width 220 | Write-Output
if ($env:UdfNum -match '^\\d+$') { Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\CentraStage' -Name ('Custom' + $env:UdfNum) -Value ($resume.Substring(0, [math]::Min(250, $resume.Length))) }
if ($Trouve.Count) { exit 1 } else { exit 0 }
`.replace(/\n/g, '\r\n');
};

/* ======================================================================== fuites et identifiants */
const RX_EMAIL = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
T.identifiants = () => T.memo('idents', () => {
  const comptes = T.table('comptes_a_changer').map(r => ({ utilisateur: r.Utilisateur, site: r.Site, identifiants: r.Identifiants, navigateurs: r.Navigateurs, id: r._id }));
  const emails = {};
  for (const r of T.table('identifiants_navigateurs')) if (RX_EMAIL.test(r.Identifiant || '')) {
    const e = emails[r.Identifiant.toLowerCase()] || (emails[r.Identifiant.toLowerCase()] = { email: r.Identifiant.toLowerCase(), sites: [], utilisateurs: [], preuves: [] });
    const site = (/^[a-z]+:\/\/([^/]+)/i.exec(r.Site || '') || [])[1] || r.Site; if (site && !e.sites.includes(site)) e.sites.push(site);
    if (r.Utilisateur && !e.utilisateurs.includes(r.Utilisateur)) e.utilisateurs.push(r.Utilisateur);
    if (e.preuves.length < 8) e.preuves.push(r._id);
  }
  return { comptes, emails: Object.values(emails).sort((a, b) => b.sites.length - a.sites.length), wifi: (T.texte('wifi_profils.txt').match(/^\s*(Profil Tous les utilisateurs|All User Profile)\s*:/gim) || []).length };
});
const normTxt = s => String(s || '').normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
const MOTS_VIDES = new Set(['cabinet', 'dentaire', 'medical', 'medecin', 'docteur', 'dr', 'sante', 'centre', 'de', 'du', 'des', 'la', 'le', 'les', 'et', 'sas', 'sarl', 'selarl', 'scm', 'demo', 'www', 'com', 'fr', 'net', 'org', 'eu', 'example', 'http', 'https']);
T.victimes = () => T.memo('victimes', () => (T.D.ransomware || []).filter(x => x && typeof x === 'object'));
T.chercherVictimes = mots => {
  const victimes = T.victimes(), res = [], vus = new Set();
  const cibles = (mots || []).map(m => String(m).trim()).filter(Boolean).map(m => { const n = normTxt(m); return { m, n, jetons: n.split(' ').filter(j => j.length >= 3 && !MOTS_VIDES.has(j)) }; });
  for (const v of victimes) {
    const nom = v.victim || v.post_title || v.name || '';
    const txt = ' ' + normTxt(['victim', 'post_title', 'name', 'domain', 'website', 'description'].map(k => v[k] || '').join(' ')) + ' ';
    for (const c of cibles) {
      if (!c.n) continue;
      const exact = txt.includes(' ' + c.n + ' ') || txt.includes(c.n);
      const part = c.jetons.length && c.jetons.filter(j => txt.includes(' ' + j + ' ')).length >= (c.jetons.length <= 2 ? c.jetons.length : c.jetons.length - 1);
      if (exact || part) {
        const k = nom + '|' + (v.group || v.group_name); if (vus.has(k)) break; vus.add(k);
        res.push({ victime: nom, groupe: v.group || v.group_name || '', date: v.discovered || v.attackdate || v.published || '', pays: v.country || '', site: v.domain || v.website || '', mot: c.m, exact, lien: v.url || v.post_url || '' });
        break;
      }
    }
  }
  return { nb: victimes.length, resultats: res.slice(0, 100) };
};
/** Have I Been Pwned - mots de passe (k-anonymat) : seul le debut du SHA1 part, la comparaison se fait ici */
T.pwned = async motDePasse => {
  const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(motDePasse));
  const hex = [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
  const r = await fetch('https://api.pwnedpasswords.com/range/' + hex.slice(0, 5), { headers: { 'Add-Padding': 'true' } });
  if (!r.ok) throw new Error('HTTP ' + r.status);
  const suffixe = hex.slice(5);
  for (const l of (await r.text()).split('\n')) { const [s, n] = l.trim().split(':'); if (s === suffixe) return +n; }
  return 0;
};

/* ======================================================================== vue d'ensemble */
T.vue = () => T.memo('vue', () => {
  const ip = T.analyseIp(), ex = T.exfil(), vis = T.visibilite(), deja = T.dejaVu();
  const pub = ip.ips.filter(e => e.type === 'PUBLIQUE'), succes = pub.filter(e => e.succes && !e.blanche);
  const chiffres = T.table('fichiers_chiffres_par_extension').filter(r => T.num(r.NbFichiers) >= 20).reduce((s, r) => s + T.num(r.NbFichiers), 0);
  const sessionsDist = T.table('sessions_reconstituees').filter(r => ['PUBLIQUE', 'VPN/CGNAT'].includes(r.TypeIP) && !T.estBlanche(T.nettoyerIp((r.IP || '').split('/')[0])));
  // outils sensibles lances pendant des fenetres qui ne sont pas toutes en liste blanche (ex. NetBird du technicien exclu)
  const legit = new Set(ex.fenetres.filter(f => f.legitime).map(f => f.id));
  const outils = [...new Set(T.table('executions_fenetres').filter(r => r.OutilSensible === 'OUI' && String(r.Fenetre || '').split(',').some(w => w && !legit.has(w))).map(r => (r.Programme || '').toLowerCase()).filter(Boolean))];
  const actives = ip.ips.filter(e => e.activeSuspecte && !e.blanche);
  const pire = ex.fenetres.reduce((m, f) => (!m || f.envoye > m.envoye) ? f : m, null);
  const R = T.reglages(), dec = T.pdate(R.decouverte);
  const cnil = dec ? { decouverte: dec, echeance: new Date(+dec + 72 * T.HEURE), restantH: (+dec + 72 * T.HEURE - Date.now()) / T.HEURE } : null;
  const ordre = { 'INDICE': 0, 'A FAIRE': 1, 'A LIRE': 2, 'NON VERIFIABLE': 3, 'RAS': 4 };
  const grille = T.table('grille_verification').map(r => ({ canal: r.Canal, statut: r.Statut, constat: r.Constat, fichier: r.Fichier, id: r._id })).sort((a, b) => (ordre[a.statut] ?? 5) - (ordre[b.statut] ?? 5));
  const alertes = [];
  if (actives.length) alertes.push({ niv: 3, icone: '🚨', texte: `Connexion encore active vers ${actives.map(a => `${a.ip} (${(a.processus || '?').split('\\').pop()})`).join(', ')} au moment de la collecte : l'attaquant est peut-être toujours là. Isoler le poste du réseau.`, preuves: actives.flatMap(a => a.preuves.filter(x => x.startsWith('tcp_')).slice(0, 2)) });
  if (chiffres) alertes.push({ niv: 3, icone: '🔒', texte: `${T.nb(chiffres)} fichiers chiffrés par un rançongiciel.`, preuves: T.table('fichiers_chiffres_par_extension').slice(0, 1).map(r => r._id) });
  for (const f of ex.fenetres) if (f.niveau === 'PLAUSIBLE') alertes.push({ niv: 3, icone: '📤', texte: `Fenêtre ${f.id} : ${T.nb(f.envoye)} Mo envoyés sur Internet, compatible avec une copie de la base patients.`, preuves: f.preuves.slice(0, 3), onglet: 'exfil' });
  for (const a of vis.anti.slice(0, 3)) alertes.push({ niv: 2, icone: '🧽', texte: `Anti-forensique : ${a.trace}${a.date ? ' (' + T.fcourt(a.date) + ')' : ''}`, preuves: a.id.includes('#') ? [a.id] : [], onglet: 'visibilite' });
  if (deja.length) alertes.push({ niv: 2, icone: '🔁', texte: `Indicateurs déjà vus dans ${deja.length} autre(s) incident(s) : ${deja.map(d => d.client || d.poste).join(', ')}.`, preuves: [], onglet: 'ioc' });
  const vict = T.chercherVictimes(R.mots_cles_fuite && R.mots_cles_fuite.length ? R.mots_cles_fuite : (R.client ? [R.client] : []));
  if (vict.resultats.length) alertes.push({ niv: 3, icone: '🕵️', texte: `Nom proche du client publié sur un site de fuite : ${vict.resultats.map(r => `${r.victime} (${r.groupe})`).slice(0, 3).join(', ')}.`, preuves: [], onglet: 'fuites' });
  return { cnil, grille, alertes, actives, deja, vict, kpi: {
    sessions: sessionsDist.length, ipSucces: succes.length, pays: [...new Set(succes.map(e => e.pays).filter(Boolean))],
    echecs: ip.ips.reduce((s, e) => s + e.echecs, 0), ipBrute: ip.ips.filter(e => e.echecs >= 20).length, outils, chiffres,
    envoyeMax: pire ? pire.envoye : 0, envoyeFen: pire ? pire.id : '', anti: vis.anti.length, defender: T.table('defender_detections').length,
    fenetres: T.fenetres().length, comptesNav: T.table('comptes_a_changer').length } };
});
