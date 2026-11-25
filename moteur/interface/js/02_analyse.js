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
T.classerOperateur = lib => !lib ? '' : RX_FAI.test(lib) ? 'Fournisseur d\'accès grand public' : RX_HEBERGEUR.test(lib) ? 'Hébergeur, VPN ou cloud' : 'Autre opérateur';

T.geo = () => T.memo('geo', () => {
  const g = {};
  for (const l of (T.D.geo_asn || [])) {                // "ip \t debut \t fin \t asn \t pays \t libelle"
    const p = l.split('\t'); if (p.length < 6) continue;
    g[p[0]] = Object.assign(g[p[0]] || {}, { asn: p[3], pays: p[4] === 'None' ? '' : p[4], operateur: p[5] === 'Not routed' ? '' : p.slice(5).join(' ') });
  }
  for (const ip in g) g[ip].categorie = T.classerOperateur(g[ip].operateur);
  return g;
});

T.listeBlanche = () => (T.reglages().liste_blanche || []).filter(l => l && l.valeur);
T.estBlanche = ip => { for (const l of T.listeBlanche()) if (T.dansCidr(ip, l.valeur.trim())) return l.note || l.valeur; return ''; };

/** processus proteges dont Windows ne donne pas le chemin, meme a un administrateur (antivirus, noyau) */
const RX_PROCESSUS_PROTEGES = /^(msmpeng|nissrv|mssense|sensendr|sensecncproxy|mpdefendercoreservice|securityhealthservice|memory compression|registry|secure system)(\.exe)?$/i;
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
    // suspect = programme non signe, ou sans chemin connu (hors processus proteges de Windows et de Defender),
    // ou lance depuis un dossier a risque sans signature valide ou s'il s'agit d'un outil d'acces / de transfert.
    // Pas suspect : Defender (MsMpEng, chemin illisible) vers le cloud Microsoft, Battle.net signe dans ProgramData.
    const sig = signature[(r.Path || '').toLowerCase()], signe = sig === 'Valid';
    const protege = !r.Path && RX_PROCESSUS_PROTEGES.test(r.Process || '');
    const suspect = (sig !== undefined && !signe) || (!r.Path && !protege) || (RISQUE.test(r.Path || '') && (!signe || RX_OUTILS.test(r.Path)));
    ajout(r.RemoteAddress, { sources: `connexion active a la collecte (${r.Process || r.OwningProcess || '?'})`, preuve: r._id, active: true, activeSuspecte: suspect, processus: r.Path || r.Process });
  }
  return ips;
});

T.analyseIp = () => T.memo('analyseIp', () => {
  const geo = T.geo(), listes = T.D.listes || {};
  const lignes = Object.values(T.ipCollecte()).map(e0 => {
    const e = Object.assign({}, e0, { comptes: [...e0.comptes].sort().slice(0, 15), sources: [...e0.sources].sort() });
    Object.assign(e, { pays: '', asn: '', operateur: '', categorie: '' }, geo[e.ip] || {});
    e.listes = Object.entries(listes).filter(([id, l]) => (l || []).includes(e.ip)).map(([id]) => Object.assign({ id }, T.LISTES[id] || { nom: id, cat: 'Liste', poids: 2 }));
    e.blanche = T.estBlanche(e.ip);
    let s = 0; const r = [];
    if (e.type === 'PUBLIQUE' && e.succes) { s += 3; r.push('connexion réussie depuis Internet'); }
    if (e.type === 'VPN/CGNAT' && e.succes) { s += 1; r.push("connexion réussie depuis une adresse de VPN ou d'opérateur partagé"); }
    if (e.categorie.startsWith('Hébergeur')) { s += 2; r.push('hébergeur, VPN ou cloud'); }
    if (e.pays && e.pays !== 'FR' && e.type === 'PUBLIQUE') { s += 1; r.push('pays : ' + (T.nomPays(e.pays) || e.pays)); }
    for (const l of e.listes) { s += l.poids; r.push('liste ' + l.nom); }
    if (e.echecs >= 100) { s += 1; r.push(`${e.echecs} connexions ratées (essais de mots de passe en masse)`); }
    if (e.activeSuspecte) { s += 3; r.push(`connexion encore ouverte à la collecte (${(e.processus || '').split('\\').pop()})`); }
    else if (e.active) r.push('connexion ouverte à la collecte par un programme signé (habituel)');
    if (e.blanche) { s = 0; r.length = 0; r.push('déclarée légitime : ' + e.blanche); }
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

/* ======================================================================== rancongiciel */
// Nom typique d'un fichier chiffre : extension d'origine PUIS ajout du rancongiciel (identifiant entre crochets avec un chiffre,
// adresse e-mail, extension connue) ou document bureautique suivi d'une extension inconnue.
// Ecartes : « icone@2x.png », « Film.[Groupe Release].torrent », « compte@exemple.fr_identity_provider » (meme regle que la collecte 2.9).
const RX_RANCON_NOM = /\.[a-z0-9]{2,5}\.\[(?=[^\]]*[0-9@])[^\]\s]{3,80}\]\.[^.]{2,15}$|\.[a-z0-9]{2,5}\.(?:[^@]*[\[{(=.])?[a-z0-9._%+-]+@[a-z][a-z0-9-]*(?:\.[a-z0-9-]+)*\.[a-z]{2,10}[\]})]?(?:\.[a-z0-9]{1,15})?$|\.(?:docx?|xlsx?|xlsm|pptx?|pdf|odt|ods|rtf|mdb|accdb|fdb)\.(?!(?:lnk|tmp|bak|old|orig|part|crdownload|download|sav|backup|gz|bz2|xz|7z|zip|rar|sig|asc|sha256|md5|json|xml|url|ini|log|dll|exe|data?|cache|db|js|map|config|mui|pdb|resources|sys|bin|idx|meta|lock|html?|txt|cs|py)$)[a-z0-9]{3,12}$|\.(?:locked|encrypted|crypted|lockbit\d?|phobos|elbie|eking|faust|devos|makop|mallox|akira|royal|blacksuit|medusa|basta|8base|rhysida|djvu)$|\.id[-_][0-9a-f]{6,}/i;
/** Chiffrement retenu : extension dont au moins 20 fichiers au nom typique ont ete modifies en 24 h.
 *  Un rancongiciel chiffre en minutes ou en heures ; une installation de jeu ou des icones etalees sur des mois, non. */
T.chiffrement = () => T.memo('chiffrement', () => {
  const parExt = new Map();
  for (const r of T.table('fichiers_chiffres_suspects')) {
    const nom = (r.Chemin || '').split('\\').pop();
    if (!RX_RANCON_NOM.test(nom)) continue;
    const ext = ((/\.[^.]+$/.exec(nom) || [''])[0]).toLowerCase();
    const d = T.pdate(r.Modification) || T.pdate(r.Creation);
    const g = parExt.get(ext) || { ext, n: 0, octets: 0, dates: [], exemple: r.Chemin, ids: [] };
    g.n++; g.octets += T.num(r.Taille); if (d) g.dates.push(+d); if (g.ids.length < 3) g.ids.push(r._id);
    parExt.set(ext, g);
  }
  const groupes = [...parExt.values()].map(g => {
    g.dates.sort((a, b) => a - b);
    let pic = 0, debut = null, fin = null;
    for (let i = 0, j = 0; j < g.dates.length; j++) {
      while (g.dates[j] - g.dates[i] > 24 * T.HEURE) i++;
      if (j - i + 1 > pic) { pic = j - i + 1; debut = g.dates[i]; fin = g.dates[j]; }
    }
    return { ext: g.ext, n: g.n, pic, mo: g.octets / 1048576, debut: debut ? new Date(debut) : null, fin: fin ? new Date(fin) : null, exemple: g.exemple, ids: g.ids };
  });
  // detail absent ou tronque (tres gros chiffrement) : le resume par extension, si les fichiers tiennent en 24 h
  const detail = T.table('fichiers_chiffres_suspects').length, tronque = !!(T.infoFichier('fichiers_chiffres_suspects') || {}).tronque;
  for (const r of T.table('fichiers_chiffres_par_extension')) {
    const ext = (r.Extension || '').toLowerCase(), n = T.num(r.NbFichiers), g = groupes.find(x => x.ext === ext);
    if (g) { if (tronque && n > g.n) g.n = n; continue; }
    if (detail && !tronque) continue;
    if (!RX_RANCON_NOM.test((r.Exemple || '').split('\\').pop())) continue;
    groupes.push({ ext, n, pic: T.num(r.DureeMinutes) <= 1440 ? n : 0, mo: T.num(r.TailleMo), debut: T.pdate(r.Premier), fin: T.pdate(r.Dernier), exemple: r.Exemple || '', ids: [r._id] });
  }
  const retenus = groupes.filter(g => g.pic >= 20).sort((a, b) => b.n - a.n);
  return { groupes: retenus, ecartes: groupes.filter(g => g.pic < 20), total: retenus.reduce((s, g) => s + g.n, 0) };
});
/** Note de rancon : nom evocateur dans 3 dossiers ou plus avec la meme taille, ou meme fichier dans 20 dossiers ou plus.
 *  Les README, help.html et LICENSE de tailles differentes (logiciels, extensions de navigateur) n'en sont pas. */
T.notesRancon = () => T.memo('notesRancon', () => T.table('notes_rancon_candidates').filter(r => {
  const n = T.num(r.NbDossiers), evoc = r.NomEvocateur === 'True', meme = r.TailleIdentique === undefined ? null : r.TailleIdentique === 'True';
  return (evoc && n >= 3 && meme !== false) || (meme === true && n >= 20);
}));

/* ======================================================================== chronologie */
T.VOIES = ['Sessions', 'Connexions', 'Force brute', 'Comptes', 'Executions', 'Mémoire vive', 'Fichiers', 'Navigation', 'Antivirus', 'Rancongiciel', 'Journaux', 'USB'];
/** nom affiche de chaque categorie (la cle reste celle des regles du recit) */
T.NOM_VOIE = { Sessions: 'Sessions', Connexions: 'Connexions réussies', 'Force brute': 'Connexions ratées', Comptes: 'Comptes', Executions: 'Programmes lancés', 'Mémoire vive': 'Mémoire vive',
  Fichiers: 'Fichiers', Navigation: 'Sites web', Antivirus: 'Antivirus', Rancongiciel: 'Rançongiciel', Journaux: 'Journaux Windows', USB: 'Clés USB' };
T.nomVoie = v => T.NOM_VOIE[v] || v;
const RX_OUTILS = /mimikatz|mimi\.exe|lazagne|procdump|rclone|winscp|filezilla|pscp|megasync|megacmd|anydesk|rustdesk|ngrok|cloudflared|chisel|advanced_(ip|port)_scanner|netscan|nmap|netpass|webbrowserpass|mailpass|chromepass|psexec|vssadmin|bcdedit|wbadmin|cipher|\b7z|winrar|rar\.exe|teamviewer|screenconnect/i;
const EVT_JOURNAUX = { 1102: 'Journal Sécurité effacé', 104: 'Journal effacé', 4616: 'Heure du poste modifiée', 4719: 'Règles de journalisation modifiées',
  5001: 'Protection en temps réel de Defender coupée', 5007: 'Réglage de Defender modifié', 7045: 'Service installé', 4697: 'Service installé',
  4698: 'Tâche planifiée créée', 6005: 'Démarrage du poste', 6006: 'Arrêt normal du poste', 6008: 'Arrêt brutal du poste (coupure, plantage)', 1074: 'Arrêt ou redémarrage demandé' };
/** numero d'evenement Windows ecrit en fin de titre « (événement 4624) » : les regles du recit le retrouvent avec evt(4624) */
const evt = (...ids) => new RegExp(`\\(événement (${ids.join('|')})\\)`);
const LIB_OUVERTURE = { 2: 'au clavier', 3: 'par le réseau', 4: 'tâche planifiée', 5: 'service', 7: 'déverrouillage', 8: 'par le réseau, mot de passe en clair', 9: 'autres identifiants', 10: 'bureau à distance', 11: 'identifiants en cache' };
const LIB_COMPTES = { 4720: 'Compte créé', 4722: 'Compte activé', 4723: 'Mot de passe changé par son titulaire', 4724: 'Mot de passe réinitialisé', 4725: 'Compte désactivé', 4726: 'Compte supprimé',
  4738: 'Compte modifié', 4740: 'Compte verrouillé', 4767: 'Compte déverrouillé', 4781: 'Compte renommé', 4728: 'Ajouté au groupe', 4732: 'Ajouté au groupe', 4756: 'Ajouté au groupe',
  4729: 'Retiré du groupe', 4733: 'Retiré du groupe', 4757: 'Retiré du groupe' };

/** services crees par Windows a chaque ouverture de session (Nom_1a2b3c) et service de copie de la RAM de DigSpill :
 *  ni l'un ni l'autre n'est une action de l'attaquant */
T.serviceOrdinaire = (svc, bin) => /^digspill_pmem$|^pmem$/i.test(svc || '') || (/^[a-z0-9]+_[0-9a-f]{4,8}$/i.test(svc || '') && /^"?%?(systemroot%|[a-z]:\\windows)\\system32\\/i.test(bin || ''));

/* ======================================================================== memoire vive (Analyse-Exfil : Volatility 3 sur l'image RAM) */
/** messages ecrits par les analyses d'avant 2.9.2, redits en clair */
const ancienneRaisonRam = r => /^Image RAM presente mais non lue/.test(r) ? "Mémoire vive copiée, mais pas lue : l'analyse a tourné sur le poste examiné lui-même. Par sécurité, DigSpill ne lit la mémoire que sur un autre PC, sain : elle peut contenir le programme malveillant. Relancez l'analyse sur votre PC, à partir de la copie des preuves."
  : /^Pas d'image RAM/.test(r) ? "Pas de copie de la mémoire vive dans cette collecte. Elle n'est faite qu'en collecte complète, sur un support NTFS ou exFAT assez grand."
  : /^Lecture de la RAM non demandee/.test(r) ? "Mémoire vive non lue : la lecture n'a pas été demandée. Relancez l'analyse en cochant « Analyse complète »." : r;
T.memoireVive = () => T.memo('memoireVive', () => {
  const lecture = T.texte('ram_lecture.txt');
  const procs = T.table('ram_processus').filter(r => r.PID).map(r => ({ pid: r.PID, ppid: r.PPID, parent: r.Parent, nom: r.Processus, debut: r.Debut, fin: r.Fin, threads: r.Threads,
    cmd: (r.LigneDeCommande && r.LigneDeCommande !== '-' ? r.LigneDeCommande : '') || r.Chemin || '', chemin: r.Chemin || '', niveau: T.num(r.Niveau), indices: String(r.Indices || '').split(' ; ').filter(Boolean), id: r._id }));
  const reseau = T.table('ram_reseau').filter(r => r.PID !== undefined).map(r => ({ proto: r.Protocole, local: r.Local, ip: r.IP, port: r.Port, etat: r.Etat, pid: r.PID, nom: r.Processus,
    cree: r.Cree, niveau: T.num(r.Niveau), source: r.Source, id: r._id }));
  const etablies = reseau.filter(c => /ESTABLISHED/i.test(c.etat || '') && !/^(0\.0\.0\.0|::|\*|127\.|::1$)/.test(c.ip || ''));
  const n = (rx) => { const m = rx.exec(lecture); return m ? T.num(m[1]) : 0; };
  const image = (/^Image lue : (.+?) \(([\d,. ]+) Go\)/m.exec(lecture) || []);
  const info = {}; T.table('ram_info').forEach(r => { info[r.Variable] = r.Value; });
  return { lue: procs.length > 0, lecture, procs, reseau, etablies, info, image: image[1] || '', go: image[2] || '',
    ecartees: n(/\((\d+) lignes illisibles/), suspects: procs.filter(p => p.niveau >= 2).sort((a, b) => b.niveau - a.niveau),
    raison: procs.length ? '' : ancienneRaisonRam(lecture.split(/\r?\n/).filter(l => l.trim() && !/^(Lecture de la m[eé]moire|Copie sur le poste|  )/.test(l)).pop() || '') };
});

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
    add(r.Debut, 'Sessions', `Session de ${r.Compte || '?'} (${r.Type || ''})`, g, `IP ${r.IP || '-'} (${T.typeIpLib(r.TypeIP)}) · fin : ${r.FinPar || '?'} · ${r.DureeMin || '?'} min`, r._id, { fin: r.Fin, ip: r.IP, compte: r.Compte });
  }
  for (const r of T.table('ouvertures_session_4624')) {
    const ti = T.typeIp(r.IP);
    if (r.Type === '7' || (r.Type === '3' && !['PUBLIQUE', 'VPN/CGNAT'].includes(ti))) continue;
    add(r.Date, 'Connexions', `Connexion réussie de ${r.Compte || '?'} (${LIB_OUVERTURE[r.Type] || 'type ' + r.Type}) (événement 4624)`, ti === 'PUBLIQUE' ? 3 : ti === 'VPN/CGNAT' ? 2 : 0, `IP ${r.IP || '-'} (${T.typeIpLib(ti)}) · poste ${r.Poste || '-'} · ${r.Authentification || ''} · ouverture de type ${r.Type}`, r._id, { ip: r.IP, compte: r.Compte });
  }
  for (const r of T.table('rdp_authentifications_1149')) add(r.Date, 'Connexions', `Bureau à distance : mot de passe accepté pour ${r.Utilisateur || '?'} (événement 1149)`, T.typeIp(r.IP) === 'PUBLIQUE' ? 2 : 0, `IP ${r.IP}`, r._id, { ip: r.IP });
  for (const r of T.table('identifiants_explicites_4648')) add(r.Date, 'Comptes', `Identifiants saisis pour un autre compte : ${r.CompteUtilise || ''} (événement 4648)`, 1, `par ${r.Auteur || ''} vers ${r.Serveur || ''} (${r.Processus || ''})`, r._id);
  const agg = {};
  for (const r of T.table('echecs_connexion_4625')) {
    const d = T.pdate(r.Date); if (!d) continue;
    const k = r.Date.slice(0, 13) + '|' + r.IP;
    const a = agg[k] || (agg[k] = { n: 0, t: d, comptes: new Set(), id: r._id, ip: r.IP }); a.n++; a.comptes.add(r.Compte);
  }
  for (const a of Object.values(agg)) add(a.t, 'Force brute', `${a.n} connexion${a.n > 1 ? 's' : ''} ratée${a.n > 1 ? 's' : ''} depuis ${a.ip || '?'}`, a.n >= 50 ? 2 : 1, 'comptes essayés : ' + [...a.comptes].filter(Boolean).slice(0, 8).join(', '), a.id, { ip: a.ip, n: a.n });
  for (const r of T.table('evenements_comptes')) add(r.Date, 'Comptes', `${LIB_COMPTES[r.EventID] || r.Action || 'Compte'} : ${`${r.CibleOuGroupe || ''} ${r.Membre || ''}`.trim()} (événement ${r.EventID})`, ['4720', '4724', '4732', '4728', '4756'].includes(r.EventID) ? 3 : 1, `par ${r.Auteur || ''} ${r.Details || ''}`, r._id);
  let bruit = 0;
  for (const r of T.table('executions_chronologie')) {
    const sensible = r.OutilSensible === 'OUI' || RX_OUTILS.test(r.Programme || '');
    const enFen = !!r.Fenetre;
    if (!sensible && !enFen && ++bruit > 3000) continue;
    add(r.Date, 'Executions', r.Programme || '?', sensible && enFen ? 3 : sensible ? 2 : enFen ? 1 : 0, `${r.Source || ''} · ${r.Chemin || ''} ${r.Detail || ''}`, r._id, { compte: r.Compte });
  }
  // comptes de stockage / transfert configures (rclone, FileZilla, WinSCP) : date du fichier de configuration
  for (const r of T.table('comptes_transfert')) if (r.Outil) add(r.Modifie, 'Comptes', `Compte ${r.Outil}${r.Type ? ' ' + r.Type : ''} configuré${r.Nom ? ' (« ' + r.Nom + ' »)' : ''}`, 3, `${r.Compte || ''}${r.Secrets ? ' · ' + r.Secrets : ''} · ${r.Fichier || ''}`, r._id, { compte: r.Profil });
  // processus lus dans l'image RAM : seulement ceux qui portent un indice (le reste est le fonctionnement normal de Windows)
  for (const p of T.memoireVive().procs.filter(x => x.niveau >= 1)) add(p.debut, 'Mémoire vive', `En mémoire : ${p.nom} (n° ${p.pid})${p.fin ? '' : ', encore ouvert à la collecte'}`, p.niveau, `${p.indices.join(' · ')}${p.cmd ? ' · ' + p.cmd : ''}`, p.id);
  const paquets = {};
  for (const r of T.table('usn_fenetres')) {
    const d = T.pdate(r.Date); if (!d) continue;
    if (r.Archive === 'OUI') { add(d, 'Fichiers', `Archive créée : ${r.Fichier}`, 3, `USN ${r.Raison || ''}`, r._id); continue; }
    const k = r.Date.slice(0, 15);
    const p = paquets[k] || (paquets[k] = { t: new Date(d.getFullYear(), d.getMonth(), d.getDate(), d.getHours(), Math.floor(d.getMinutes() / 10) * 10), n: 0, ex: [], id: r._id });
    p.n++; if (p.ex.length < 5) p.ex.push(r.Fichier);
  }
  for (const p of Object.values(paquets)) add(p.t, 'Fichiers', `${p.n} modification${p.n > 1 ? 's' : ''} de fichiers`, p.n >= 500 ? 2 : 1, p.ex.join(', '), p.id, { n: p.n });
  for (const r of T.table('acces_fichiers_lnk_jumplists_shellbags')) {
    const metier = r.DONNEES_METIER === 'OUI', ts = r.TSCLIENT === 'OUI';
    if (!metier && !ts && !r.Fenetre) continue;
    add(r.Date1 || r.Date2, 'Fichiers', `${ts ? 'Copie vers le PC distant (\\\\tsclient)' : metier ? 'Données du cabinet ouvertes' : 'Fichier ouvert'} : ${(r.Chemin || '').slice(-80)}`, ts ? 3 : metier ? 2 : 1, `${r.Source || ''} (${r.Date1Type || ''}) ${r.Utilisateur || ''}`, r._id);
  }
  for (const r of T.table('navigation_fenetres')) {
    const dom = (/^[a-z]+:\/\/([^/:]+)/i.exec(r.Url || '') || [])[1] || r.Url;
    add(r.Date, 'Navigation', dom + (r.Categorie ? ` (${r.Categorie})` : ''), ['PARTAGE / TRANSFERT', 'OUTILS / ACCES DISTANT'].includes(r.Categorie) ? 2 : r.Categorie ? 1 : 0, r.Titre, r._id);
  }
  for (const r of T.table('telechargements')) add(r.Date, 'Navigation', `Téléchargement : ${(r.Fichier || '').split('\\').pop()}`, r.Fenetre ? 2 : 0, r.Url, r._id);
  for (const r of T.table('defender_detections')) add(r.InitialDetectionTime, 'Antivirus', `Defender : menace détectée (n° ${r.ThreatID || '?'})`, 3, `${r.ProcessName || ''} ${r.Resources || ''} · traitée : ${/^true$/i.test(r.ActionSuccess || '') ? 'oui' : /^false$/i.test(r.ActionSuccess || '') ? 'non' : r.ActionSuccess || '?'}`, r._id);
  for (const g of T.chiffrement().groupes)
    add(g.debut, 'Rancongiciel', `Chiffrement : ${T.nb(g.n)} fichiers ${g.ext}`, 3, `${T.nb(g.mo, 1)} Mo · ${T.nb(g.pic)} en 24 h au plus · ex. ${g.exemple}`, g.ids[0], { fin: g.fin });
  for (const r of T.table('commandes_destructrices_4688')) add(r.Date, 'Rancongiciel', 'Commande destructrice', 3, r.CommandLine || r.Commande || Object.values(r).join(' '), r._id);
  // note de rancon : nom evocateur dans 3 dossiers ou plus, ou meme fichier (meme taille) dans 20 dossiers ou plus.
  // Les README et LICENSE de tailles differentes d'un poste de developpeur ne sont pas des notes.
  for (const r of T.notesRancon()) add(r.Derniere, 'Rancongiciel', `Note de rançon : ${r.Nom} (${r.NbDossiers} dossiers)`, 3, r.Exemples, r._id);
  for (const r of T.table('resume_evenements_cles')) if (EVT_JOURNAUX[r.EventID]) add(r.Date, 'Journaux', `${EVT_JOURNAUX[r.EventID]} (événement ${r.EventID})`, ['1102', '104', '4616', '4719', '5001'].includes(r.EventID) ? 3 : 1, (r.Message || '').slice(0, 300), r._id);
  for (const r of T.table('usb_chronologie')) add(r.Date, 'USB', `USB : ${(r.Peripherique || '').slice(0, 60)}`, r.Fenetre ? 2 : 0, `${r.Source || ''} · n° de série ${r.Serie || '-'}`, r._id);
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
// bases livrees avec Windows ou SQL Server (modeles, composants) : ce ne sont pas des donnees du cabinet
const RX_BASES_SYSTEME = /^[a-z]:\\windows\\|\\microsoft visual studio\\|\\dotnet\\packs\\|\\chocolatey\\|\\nugetpackages\\|\\microsoft sdks\\|\\(item|project)templates\\|\\r\\r-[\d.]+\\library\\|\\node_modules\\|\\hostedtoolcache\\|\\microsoft sql server\\[^\\]+\\(localdb\\)?binn\\|\\microsoft sql server\\[^\\]+\\mssql\\binn\\templates\\|\\windowsapps\\|\\\$recycle\.bin\\/i;
T.basesMetier = () => T.memo('bases', () => {
  const vus = {};
  for (const r of T.table('bases_metier')) {
    const ch = r.Chemin || '', taille = T.num(r.Taille); if (!ch || taille <= 0 || RX_BASES_SYSTEME.test(ch)) continue;
    vus[ch.toLowerCase()] = { chemin: ch, mo: Math.round(taille / 1048576 * 10) / 10, sauvegarde: /sauvegarde|backup|\\save|\\old|\.bak|archive/i.test(ch), modification: r.Modification || '', id: r._id };
  }
  return Object.values(vus).sort((a, b) => b.mo - a.mo);
});
T.NIVEAUX = {
  LEGITIME: { lib: 'Période légitime (adresse connue)', cls: 'vert', icone: '' },
  HABITUEL: { lib: 'Envois habituels du poste', cls: 'vert', icone: '' },
  PLAUSIBLE: { lib: 'Copie de la base possible', cls: 'rouge', icone: '' },
  PARTIELLE: { lib: 'Copie partielle possible', cls: 'orange', icone: '' },
  EXCLUE_RESEAU: { lib: 'Copie complète impossible depuis ce poste', cls: 'vert', icone: '' },
  IMPOSSIBLE_LIGNE: { lib: 'Copie complète trop lourde pour la box', cls: 'vert', icone: '' },
  INCONNU: { lib: 'Impossible à mesurer', cls: 'gris', icone: '' }
};
T.exfil = () => T.memo('exfil', () => {
  const R = T.reglages(), serie = T.serieSrum(), ref = T.refSrum(), bases = T.basesMetier();
  const princ = bases.filter(b => !b.sauvegarde && b.mo >= 1); const tailleAuto = (princ[0] || {}).mo || 0;
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
      if (comp && envoye >= 0.1 * comp && envoye < comp && habituel) { niveau = 'HABITUEL'; constats.push(`${T.nb(envoye)} Mo envoyés en ${releves} heure${releves > 1 ? 's' : ''} : comme d'habitude pour ce poste. Une petite copie partielle reste possible.`); }
      else if (comp && envoye >= comp) { niveau = 'PLAUSIBLE'; constats.push(`Le poste a envoyé ${T.nb(envoye)} Mo sur Internet : autant ou plus que la base patients compressée (environ ${T.nb(comp)} Mo). Une copie complète est possible.`); }
      else if (comp && envoye >= 0.1 * comp) { niveau = 'PARTIELLE'; constats.push(`${T.nb(envoye)} Mo envoyés : de quoi copier environ ${T.nb(envoye / comp * 100)} % de la base patients compressée.`); }
      else if (comp) { niveau = 'EXCLUE_RESEAU'; constats.push(`Seulement ${T.nb(envoye, 1)} Mo envoyés, pour une base patients d'environ ${T.nb(comp)} Mo compressée : ce poste n'a pas pu l'envoyer en entier par Internet (si le relevé de Windows est complet).`); }
      else constats.push(`${T.nb(envoye, 1)} Mo envoyés. Taille de la base patients inconnue : indiquez-la plus haut pour conclure.`);
      if (ref && ref.max && picMax > ref.max) constats.push(`Pic de ${T.nb(picMax)} Mo en une heure : plus que le maximum habituel du poste (${T.nb(ref.max)} Mo par heure, sur ${T.nb(ref.releves)} heures relevées).`);
    } else constats.push("Windows n'a pas relevé les envois pendant cette période (SRUM) : impossible de mesurer ce qui est parti.");
    if (capacite !== null && comp) {
      if (capacite < comp) {
        constats.push(`En ${T.nb(dureeS / 60)} min, la box (${T.nb(debit)} Mbit/s en envoi) pouvait envoyer ${T.nb(capacite)} Mo au plus : pas assez pour toute la base patients (environ ${T.nb(comp)} Mo).`);
        if (niveau === 'INCONNU') niveau = 'IMPOSSIBLE_LIGNE';
      } else constats.push(`La box pouvait envoyer jusqu'à ${T.nb(capacite)} Mo pendant la période. Envoyer toute la base patients compressée prenait environ ${T.nb(besoin)} min.`);
    }
    if (legitime) { niveau = 'LEGITIME'; constats.unshift(`Période ouverte depuis une adresse déclarée légitime : ${[...new Set(notes)].join(', ')}. Activité considérée comme normale.`); }
    return { id: w.id, debut: w.debut, fin: w.fin, motif: w.motif, duree: Math.round(dureeS / 60), envoye, picMax, capacite, besoin, couvre, niveau, constats, legitime,
      apps: Object.values(apps[w.id] || {}).sort((a, b) => b.mo - a.mo).slice(0, 8), preuves: ids, preuveFenetre: w.preuve };
  });
  return { serie, ref, bases, fenetres, hyp: { taille, tailleAuto, compression, comp, debit } };
});
T.LIMITES_EXFIL = [
  "Ce calcul ne vaut que pour ce poste : un autre poste, un serveur ou un NAS du cabinet a pu servir.",
  "Avec les mots de passe enregistrés (logiciels en ligne, messagerie, NAS), on peut accéder aux données sans passer par ce poste : ce calcul ne le couvre pas.",
  "La compression est une hypothèse (déduction) : une base de données se compresse souvent de 3 à 10 fois.",
  "Windows relève les envois environ une fois par heure (SRUM) : un arrêt brutal peut faire perdre le dernier relevé.",
  "En bureau à distance, l'image de l'écran compte aussi dans les envois : un gros volume ne veut pas dire à lui seul que des données sont sorties."
];

/* ======================================================================== visibilite */
const NOMS_JOURNAUX = {
  'Security': 'Sécurité (connexions, comptes)', 'System': 'Système (démarrages, services)',
  'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational': 'Sessions de bureau à distance',
  'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational': 'Mots de passe acceptés en bureau à distance',
  'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational': 'Connexions réseau du bureau à distance',
  'Microsoft-Windows-PowerShell/Operational': 'PowerShell (4104)', 'Microsoft-Windows-Windows Defender/Operational': 'Defender',
  'Microsoft-Windows-SMBServer/Security': 'Dossiers partagés (SMB)', 'Microsoft-Windows-Bits-Client/Operational': 'Transferts en arrière-plan (BITS)',
  'Microsoft-Windows-DNS-Client/Operational': 'Sites contactés (DNS)', 'Microsoft-Windows-Sysmon/Operational': 'Sysmon',
  'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall': 'Règles du pare-feu', 'Microsoft-Windows-TerminalServices-PnPDevices/Admin': 'Disques et imprimantes partagés en bureau à distance'
};
const ANTI = [[/wevtutil(\.exe)?\s+(cl|clear-log)/i, 'Effacement de journal (wevtutil)'], [/clear-eventlog|remove-eventlog/i, 'Effacement de journal (PowerShell)'],
  [/fsutil(\.exe)?\s+usn\s+deletejournal/i, 'Suppression du journal USN'], [/vssadmin(\.exe)?\s+delete\s+shadows|shadowcopy\s+delete|win32_shadowcopy/i, 'Suppression des copies de sauvegarde de Windows (clichés VSS)'],
  [/wbadmin(\.exe)?\s+delete/i, 'Suppression des sauvegardes Windows'], [/bcdedit.*recoveryenabled\s+no/i, 'Réparation au démarrage désactivée'],
  [/cipher(\.exe)?\s+\/w/i, "Effacement de l'espace libre (cipher /w)"], [/sdelete/i, 'Effacement sécurisé (SDelete)'],
  [/set-mppreference.*-disable|add-mppreference.*-exclusion/i, 'Defender modifié en ligne de commande'], [/auditpol(\.exe)?\s+\/(clear|remove|set)/i, 'Règles de journalisation modifiées']];
/** 5007 : Defender ecrit ses changements internes (demarrage, mises a jour, notifications) ; seuls ceux-ci l'affaiblissent */
const RX_DEFENDER_AFFAIBLI = /\\Exclusions\\|\\Disable\w*\s*=\s*0x1\b|TamperProtection\s*=\s*0x[04]\b|SpyNetReporting\s*=\s*0x0\b|SubmitSamplesConsent\s*=\s*0x2\b|EnableControlledFolderAccess\s*=\s*0x0\b|PUAProtection\s*=\s*0x0\b/i;
/** cle de Defender modifiee (ou dont la modification a ete bloquee), pour le libelle : « DisableBmNetworkSensor = 0x1 » */
const REGLAGES_DEFENDER = { DisableRealtimeMonitoring: 'protection en temps réel', DisableBehaviorMonitoring: 'surveillance du comportement des programmes', DisableBmNetworkSensor: 'surveillance réseau des programmes',
  DisableIOAVProtection: 'analyse des fichiers téléchargés', DisableScriptScanning: 'analyse des scripts', DisableAntiSpyware: 'antivirus', DisableAntiVirus: 'antivirus', TamperProtection: 'protection contre les modifications',
  SpyNetReporting: 'protection dans le cloud', SubmitSamplesConsent: "envoi d'échantillons à Microsoft", EnableControlledFolderAccess: 'protection des dossiers contre les rançongiciels', PUAProtection: 'blocage des logiciels indésirables' };
const cleDefender = m => {
  const x = /.*\\([^\\=]+?)\s*=\s*(0x[0-9a-f]+)?/i.exec(String(m || '').replace(/\s+/g, ' ')); if (!x) return '';
  const cle = x[1].trim(), brut = cle + (x[2] ? ' = ' + x[2] : ''), lib = REGLAGES_DEFENDER[cle];
  if (/\\Exclusions\\/i.test(String(m || ''))) return `dossier ou programme exclu de l'analyse (${brut})`;
  return lib ? (/^Disable/i.test(cle) && x[2] === '0x1' ? `fonction « ${lib} » arrêtée (${brut})` : `fonction « ${lib} » (${brut})`) : brut;
};
const EVT_ANTI = { 1102: 'Journal Sécurité effacé', 104: 'Journal effacé', 4616: 'Heure du poste modifiée', 4719: 'Règles de journalisation modifiées', 5001: 'Protection en temps réel de Defender coupée', 5007: 'Réglage de Defender modifié', 5013: 'Tentative de modifier Defender bloquée' };

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
  for (const [nom, table, col] of [['Relevé des envois (SRUM)', 'srum_total_par_releve', 'Releve'], ['Programmes lancés (Prefetch, Amcache, BAM)', 'executions_chronologie', 'Date'], ['Historique web', 'navigation_complete', 'Date'], ...(T.fenetres().length ? [['Journal USN (fichiers)', 'usn_fenetres', 'Date']] : [])]) {
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
      else if (s.debut > w.fin || (s.fin && s.fin < w.debut)) st = 'ne remonte pas jusque-là';
      else st = 'en partie seulement';
      return { source: s.source, statut: st, id: s.id };
    });
    return { id: w.id, debut: w.debut, fin: w.fin, motif: w.motif, sources: lignes, taux: lignes.length ? Math.round(100 * lignes.filter(l => l.statut === 'couverte').length / lignes.length) : 0 };
  });
  const anti = [];
  for (const nom of ['resume_evenements_cles', 'evenements_fenetres']) for (const r of T.table(nom)) if (EVT_ANTI[r.EventID] && (!['5007', '5013'].includes(r.EventID) || RX_DEFENDER_AFFAIBLI.test(r.Message || ''))) anti.push({ date: r.Date || '', trace: `${EVT_ANTI[r.EventID]}${['5007', '5013'].includes(r.EventID) && cleDefender(r.Message) ? ' : ' + cleDefender(r.Message) : ''} (événement ${r.EventID})`, detail: (r.Message || '').slice(0, 300), id: r._id });
  for (const [nom, cols] of [['commandes_destructrices_4688', null], ['executions_chronologie', ['Detail', 'Chemin']]]) for (const r of T.table(nom)) {
    const txt = cols ? cols.map(k => r[k] || '').join(' ') : Object.entries(r).filter(([k]) => k !== '_id').map(([, v]) => v).join(' ');
    for (const [rx, lib] of ANTI) if (rx.test(txt)) { anti.push({ date: r.Date || '', trace: lib, detail: txt.slice(0, 300), id: r._id }); break; }
  }
  const pref = T.texte('defender_preferences.txt');
  for (const m of pref.matchAll(/^(Exclusion\w+)\s*:\s*\{(.+)\}/gim)) if (m[2].trim()) anti.push({ date: '', trace: `Dossier, programme ou extension exclu de l'analyse de Defender (${m[1]})`, detail: m[2].trim(), id: 'defender_preferences.txt' });
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
  ['acces_fichiers_lnk_jumplists_shellbags', 'Fichier ouvert (LNK / ShellBags)', ['Chemin']], ['usn_fenetres', 'Fichier modifié pendant une période suspecte', ['Fichier']],
  ['navigation_fenetres', 'Site consulté pendant une période suspecte', ['Url', 'Titre']], ['navigation_sites_sensibles', 'Site santé / métier consulté', ['Url']],
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
/** dossiers de DigSpill lui-même (kit lancé, copie du dépôt) : un DigSpill.exe avec ses scripts dans moteur\,
 *  ou un DigSpill.exe identique à celui-là. Leurs fichiers ne sont pas des traces de l'attaquant. */
T.dossiersDigSpill = () => T.memo('dossiersDigSpill', () => {
  const bas = [...T.table('binaires_suspects').map(r => [r.Chemin, r.SHA256]), ...T.table('outils_suspects').map(r => [r.Chemin, r.SHA256]), ...T.table('processus_binaires').map(r => [r.Path, r.SHA256])]
    .filter(x => x[0]).map(([c, x]) => [String(c).toLowerCase(), normHash(x)]);
  const racine = c => c.replace(/\\[^\\]+$/, '').replace(/\\app\\bin$/, '');
  const scripts = /\\moteur\\(collecte-exfil|analyse-exfil|copier-preuves|generer-interface)\.ps1$/;
  const sures = new Set(), empreintes = new Set();
  for (const [c, x] of bas) if (/\\digspill\.exe$/.test(c)) { const r = racine(c); if (bas.some(([y]) => y.startsWith(r + '\\moteur\\') && scripts.test(y))) { sures.add(r); if (x) empreintes.add(x); } }
  for (const [c, x] of bas) if (/\\digspill\.exe$/.test(c) && x && empreintes.has(x)) sures.add(racine(c));
  return [...sures];
});
T.estDigSpill = chemin => { const c = String(chemin || '').toLowerCase(); return !!c && T.dossiersDigSpill().some(r => c.startsWith(r + '\\')); };
T.hachages = () => T.memo('hachages', () => {
  const vus = {};
  const add = (h, nom, chemin, source, date, id, rem = '') => {
    h = normHash(h); if (!h) return;
    const e = vus[h] || (vus[h] = { hash: h, type: { 32: 'MD5', 40: 'SHA1', 64: 'SHA256' }[h.length], noms: [], chemins: [], sources: [], date, preuves: [], remarque: rem });
    for (const [l, v] of [[e.noms, nom], [e.chemins, chemin], [e.sources, source]]) if (v && !l.includes(v)) l.push(v);
    if (!e.preuves.includes(id)) e.preuves.push(id);
  };
  for (const r of T.table('ioc_hachages')) for (const c of ['SHA256', 'SHA1']) add(r[c], r.Nom, r.Chemin, r.Source, r.Date, r._id, r.Remarque);
  for (const r of T.table('binaires_suspects')) if (!T.estDigSpill(r.Chemin)) add(r.SHA256, (r.Chemin || '').split('\\').pop(), r.Chemin, `Binaire suspect (${r.Source || ''})`, r.Creation, r._id, `signature ${r.Signature || '?'}`);
  for (const r of T.table('outils_suspects')) if (!T.estDigSpill(r.Chemin)) add(r.SHA256, (r.Chemin || '').split('\\').pop(), r.Chemin, 'Outil présent sur le disque', r.Creation, r._id);
  for (const r of T.table('processus_binaires')) if (r.Signature !== 'Valid' && !T.estDigSpill(r.Path)) add(r.SHA256, (r.Path || '').split('\\').pop(), r.Path, `Processus en cours (signature ${r.Signature || 'absente'})`, '', r._id);
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
  const ext = T.chiffrement().groupes.map(g => g.ext).filter(Boolean).slice(0, 5);
  const notes = T.notesRancon().map(r => r.Nom).filter(Boolean).slice(0, 5);
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
  Genere le ${T.fdate(new Date()).slice(0, 16)} par DigSpill.
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
  const chiffres = T.chiffrement().total;
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
  if (actives.length) alertes.push({ niv: 3, icone: '', texte: `Connexion encore active vers ${actives.map(a => `${a.ip} (${(a.processus || '?').split('\\').pop()})`).join(', ')} au moment de la collecte : l'attaquant est peut-être toujours là. Isoler le poste du réseau.`, preuves: actives.flatMap(a => a.preuves.filter(x => x.startsWith('tcp_')).slice(0, 2)) });
  if (chiffres) alertes.push({ niv: 3, icone: '', texte: `${T.nb(chiffres)} fichiers chiffrés par un rançongiciel (${T.chiffrement().groupes.slice(0, 3).map(g => g.ext).join(', ')}).`, preuves: T.chiffrement().groupes.slice(0, 2).map(g => g.ids[0]) });
  for (const f of ex.fenetres) if (f.niveau === 'PLAUSIBLE') alertes.push({ niv: 3, icone: '', texte: `Période ${f.id} : ${T.nb(f.envoye)} Mo envoyés sur Internet, assez pour copier la base patients.`, preuves: f.preuves.slice(0, 3), onglet: 'details/exfil' });
  const antiVus = new Map(); for (const a of vis.anti) { const x = antiVus.get(a.trace); if (x) x.n++; else antiVus.set(a.trace, Object.assign({ n: 1 }, a)); }
  for (const a of [...antiVus.values()].slice(0, 3)) alertes.push({ niv: 2, icone: '', texte: `Trace effacée ou protection coupée : ${a.trace}${a.n > 1 ? ` · ${a.n} fois, dès le ${T.fcourt(a.date)}` : a.date ? ' · le ' + T.fcourt(a.date) : ''}`, preuves: a.id.includes('#') ? [a.id] : [], onglet: 'details/visibilite' });
  const transf = T.table('comptes_transfert').filter(r => r.Outil);
  if (transf.length) alertes.push({ niv: 3, icone: '', texte: `Compte de stockage ou de transfert configuré sur le poste : ${transf.slice(0, 3).map(r => `${r.Outil} ${r.Type || ''} ${(r.Compte || '').replace(/ ; /g, ', ')}`.replace(/\s+/g, ' ').trim()).join(' ; ')}. Mots de passe non lus.`, preuves: transf.slice(0, 3).map(r => r._id), onglet: 'details/exfil' });
  const ram = T.memoireVive(), ramActifs = ram.procs.filter(p => p.niveau >= 3 && !p.fin);
  if (ramActifs.length) alertes.push({ niv: 3, icone: '', texte: `Programme suspect encore en mémoire à la collecte : ${ramActifs.slice(0, 3).map(p => `${p.nom} (n° ${p.pid}, ${p.indices[0]})`).join(' ; ')}.`, preuves: ramActifs.slice(0, 3).map(p => p.id), onglet: 'details/memoire' });
  if (deja.length) alertes.push({ niv: 2, icone: '', texte: `Traces déjà vues dans ${deja.length > 1 ? deja.length + ' autres incidents' : 'un autre incident'} : ${deja.map(d => d.client || d.poste).join(', ')}.`, preuves: [], onglet: 'details/ioc' });
  const vict = T.chercherVictimes(R.mots_cles_fuite && R.mots_cles_fuite.length ? R.mots_cles_fuite : (R.client ? [R.client] : []));
  if (vict.resultats.length) alertes.push({ niv: 3, icone: '', texte: `Nom proche du client publié sur un site de fuite : ${vict.resultats.map(r => `${r.victime} (${r.groupe})`).slice(0, 3).join(', ')}.`, preuves: [], onglet: 'details/fuites' });
  return { cnil, grille, alertes, actives, deja, vict, kpi: {
    sessions: sessionsDist.length, ipSucces: succes.length, pays: [...new Set(succes.map(e => e.pays).filter(Boolean))],
    echecs: ip.ips.reduce((s, e) => s + e.echecs, 0), ipBrute: ip.ips.filter(e => e.echecs >= 20).length, outils, chiffres,
    envoyeMax: pire ? pire.envoye : 0, envoyeFen: pire ? pire.id : '', anti: vis.anti.length, defender: T.table('defender_detections').length,
    fenetres: T.fenetres().length, comptesNav: T.table('comptes_a_changer').length } };
});

/* ======================================================================== resume : phrase, actions, limites
   Regles fixes ecrites ici : des faits, aucun verdict, aucune IA. */
const ARTICLE_MASC_E = /^(Mexique|Cambodge|Mozambique|Zimbabwe|Belize|Suriname)$/;
T.depuisPays = nom => {
  if (!nom) return '';
  if (/^(Pays-Bas|États-Unis|Emirats|Émirats|Philippines|Seychelles|Comores|Maldives|Bahamas)/.test(nom)) return 'depuis les ' + nom;
  if (/^[AEIOUYÉÈÊÂÎ]/i.test(nom)) return "depuis l'" + nom;
  return (nom.endsWith('e') && !ARTICLE_MASC_E.test(nom) ? 'depuis la ' : 'depuis le ') + nom;
};
T.volume = (mo, dec = 1) => mo >= 1000 ? `${(mo / 1000).toLocaleString('fr-FR', { minimumFractionDigits: dec, maximumFractionDigits: dec })}\u00a0Go` : `${T.nb(Math.round(mo))}\u00a0Mo`;
T.hm = d => d ? `${p2(d.getHours())}:${p2(d.getMinutes())}` : '';
T.jm = d => d ? `${p2(d.getDate())}/${p2(d.getMonth() + 1)}` : '';
const MOIS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
const JOURS = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'];
/** « La nuit du 16 au 17 novembre » / « Le 12 novembre » / « Du 3 au 5 novembre » */
T.periode = (d, f) => {
  const j0 = new Date(d.getFullYear(), d.getMonth(), d.getDate()), j1 = new Date(f.getFullYear(), f.getMonth(), f.getDate());
  const jours = Math.round((j1 - j0) / 864e5);
  const nd = n => `${n.getDate() === 1 ? '1er' : n.getDate()}`;
  if (jours === 0) return { titre: `Le ${nd(d)} ${MOIS[d.getMonth()]}`, dans: `Le ${nd(d)} ${MOIS[d.getMonth()]}`, nom: 'la journée' };
  const fin = `${nd(f)} ${MOIS[f.getMonth()]}`, debut = d.getMonth() === f.getMonth() ? nd(d) : `${nd(d)} ${MOIS[d.getMonth()]}`;
  if (jours === 1 && d.getHours() >= 17 && f.getHours() < 10) return { titre: `La nuit du ${debut} au ${fin}`, dans: `Dans la nuit du ${debut} au ${fin}`, nom: 'la nuit' };
  return { titre: `Du ${debut} au ${fin}`, dans: `Du ${debut} au ${fin}`, nom: 'la période' };
};

/** fenetre la plus grave : la plus chargee en evenements critiques (puis le volume envoye) */
T.fenetreGrave = () => T.memo('fenGrave', () => {
  const ev = T.chronologie().evenements, ex = T.exfil().fenetres;
  let best = null;
  for (const f of T.fenetres()) {
    const crit = ev.filter(e => e.g >= 3 && (e.fen || '').split(',').includes(f.id)).length;
    const env = (ex.find(x => x.id === f.id) || {}).envoye || 0;
    const legit = (ex.find(x => x.id === f.id) || {}).legitime;
    const s = (legit ? -1e6 : 0) + crit * 1000 + env;
    if (!best || s > best.s) best = { s, f };
  }
  return best ? best.f : null;
});

/** bilan des rapports : un incident est constaté (intrusion, envoi, chiffrement, outil de pirate, alerte grave) ou non */
T.bilan = () => T.memo('bilan', () => {
  const v = T.vue(), k = v.kpi, sit = T.situation();
  const graves = v.alertes.filter(a => a.niv >= 3);
  return { incident: !sit.vide || graves.length > 0 || k.outils.length > 0, graves, k };
});
T.situation = () => T.memo('situation', () => {
  const v = T.vue(), k = v.kpi, ip = T.analyseIp(), fg = T.fenetreGrave(), ex = T.exfil();
  const morceaux = [];
  // connexion reussie depuis une IP publique : pays des IP de la fenetre la plus grave d'abord
  const recit = fg ? T.recit(fg.id) : null;
  let paysCodes = [];
  if (recit) paysCodes = [...new Set(recit.ipsEntree.map(a => (ip.ips.find(e => e.ip === a) || {}).pays).filter(Boolean))];
  if (!paysCodes.length) paysCodes = k.pays || [];
  if (k.ipSucces) {
    const noms = paysCodes.map(T.nomPays).filter(Boolean);
    const lieux = noms.map(n => T.depuisPays(n).replace(/^depuis /, ''));
    if (lieux.length) morceaux.push({ texte: `Une connexion à distance depuis `, fort: lieux.length > 1 ? lieux.slice(0, -1).join(', ') + ' et ' + lieux[lieux.length - 1] : lieux[0] });
    else morceaux.push({ texte: 'Une connexion à distance ', fort: 'depuis Internet' });
  }
  const pire = ex.fenetres.find(f => f.id === k.envoyeFen);
  if (pire && ['PLAUSIBLE', 'PARTIELLE'].includes(pire.niveau)) morceaux.push({ fort: `${T.volume(k.envoyeMax, 1)} envoyés`, suite: ' sur Internet' });
  if (k.chiffres) morceaux.push({ prefixe: morceaux.length ? 'puis ' : '', fort: `${T.nb(k.chiffres)} fichiers chiffrés` });
  if (!morceaux.length) return { vide: true, morceaux: [{ texte: 'Aucun indice majeur dans les traces collectées.' }] };
  return { vide: false, morceaux };
});

const NOMS_SOURCES = [[/pare-feu/i, 'le pare-feu'], [/DNS/i, 'le journal des sites contactés (DNS)'], [/SMB|partag[ée]s \(/i, 'les dossiers partagés'], [/BITS/i, 'les transferts en arrière-plan (BITS)'], [/PowerShell/i, 'PowerShell'],
  [/USN/i, 'le journal des fichiers'], [/SRUM/i, 'le relevé des envois (SRUM)'], [/navigation|historique web/i, "l'historique web"], [/programmes lancés|exécutions/i, 'les traces de programmes lancés'],
  [/bureau à distance|RDP/i, 'les journaux du bureau à distance'], [/^Sécurité/i, 'le journal Sécurité'], [/^Système/i, 'le journal Système']];
/** ce que le poste ne pouvait pas montrer : sources désactivées (rien noté) et sources absentes ou illisibles */
T.limites = () => T.memo('limites', () => {
  const src = T.visibilite().sources.filter(s => ['absent', 'desactive'].includes(s.etat) && !/sysmon/i.test(s.source));
  const rang = n => { const i = NOMS_SOURCES.findIndex(x => x[1] === n); return i < 0 ? 99 : i; };
  const nom = s => (NOMS_SOURCES.find(([r]) => r.test(s.source)) || [0, s.source.charAt(0).toLowerCase() + s.source.slice(1)])[1];
  const groupe = etat => [...new Set(src.filter(s => s.etat === etat).map(nom))].sort((a, b) => rang(a) - rang(b));
  const desact = groupe('desactive'), abs = groupe('absent').filter(n => !desact.includes(n)), noms = [...desact, ...abs];
  if (!noms.length) return null;
  const et = l => l.length === 1 ? l[0] : l.slice(0, -1).join(', ') + ' et ' + l[l.length - 1];
  const pl = l => l.length > 1 || /^les /.test(l[0]);
  const morceaux = [];
  if (desact.length) morceaux.push(`${et(desact)} n'enregistrai${pl(desact) ? 'ent' : 't'} rien`);
  if (abs.length) morceaux.push(`${et(abs)} ${pl(abs) ? 'manquaient ou étaient illisibles' : 'manquait ou était illisible'}`);
  const p = morceaux.join(' ; ');
  return { noms, desact, abs, phrase: `${p.charAt(0).toUpperCase()}${p.slice(1)}. Si des données sont parties par là, ce poste ne permet pas de le voir.` };
});

const OUTILS_MDP = /mimi|mimikatz|netpass|lazagne|webbrowserpass|mailpass|chromepass|procdump/i;
const nomOutilMdp = p => /mimi/i.test(p) ? 'mimikatz' : String(p || '').replace(/\.exe$/i, '').toLowerCase();
T.actions = () => T.memo('actions', () => {
  const v = T.vue(), k = v.kpi, R = T.reglages(), out = [];
  const fenIds = new Set(T.fenetres().map(f => f.id));
  const dansFen = r => String(r.Fenetre || T.fenDe(r.Date) || '').split(',').some(x => fenIds.has(x));
  // 1. isoler
  if (v.actives.length) out.push({ id: 'isoler', titre: 'Isoler le poste du réseau', sous: `Une connexion vers ${v.actives.map(a => a.ip).join(', ')} était encore ouverte au moment de la collecte.`, bouton: 'isoler' });
  // poste sain (aucun incident constaté) : ni CNIL, ni assureur, ni chasse sur le parc
  const incident = T.bilan().incident;
  if (!incident) out.push({ id: 'rien', titre: "Rien d'urgent sur ce poste", sous: "Aucune trace d'intrusion, de vol de données ni de chiffrement. Remettre le poste en service et garder le rapport client avec le PV de collecte.", lien: 'preuves/rapports', lienTexte: 'Rapports à imprimer' });
  // 2. CNIL (incident constaté)
  if (!incident) { /* rien à notifier sur la base de cet examen */ }
  else if (v.cnil) {
    const e = v.cnil.echeance;
    const quand = `${JOURS[e.getDay()]} ${T.jm(e)} à ${T.hm(e)}`;
    out.push({ id: 'cnil', titre: 'Notifier la CNIL', sous: v.cnil.restantH >= 0 ? `Avant le ${quand}. Décision du client et de son DPO.` : `Le délai de 72 h a expiré le ${quand}. Notifier sans attendre, en expliquant le retard. Décision du cabinet et de son DPO.`, compte: true });
  } else out.push({ id: 'cnil', titre: 'Notifier la CNIL', sous: 'Dans les 72 h après la découverte. Décision du client et de son DPO.', saisir: true });
  // 3. mots de passe
  const outilsMdp = T.table('executions_fenetres').filter(r => OUTILS_MDP.test(r.Programme || '') && dansFen(r)).sort((a, b) => T.pdate(a.Date) - T.pdate(b.Date));
  if (outilsMdp.length) out.push({ id: 'mdp', titre: 'Changer tous les mots de passe du poste', sous: `Un outil de vol de mots de passe (${nomOutilMdp(outilsMdp[0].Programme)}) a été lancé à ${T.hm(T.pdate(outilsMdp[0].Date))}.` });
  else if (k.comptesNav && incident) out.push({ id: 'mdp', titre: 'Changer tous les mots de passe du poste', sous: `${T.nb(k.comptesNav)} identifiant(s) enregistré(s) dans les navigateurs de ce poste.` });
  // 4. serveurs touches avec d'autres identifiants (4648)
  const vus = new Set();
  for (const r of T.table('identifiants_explicites_4648').filter(dansFen)) {
    const srv = r.Serveur || ''; if (!srv || vus.has(srv.toLowerCase()) || /localhost|^-$/i.test(srv)) continue; vus.add(srv.toLowerCase());
    out.push({ id: 'srv-' + srv, titre: `Vérifier ${T.nomServeur(srv, r.CompteUtilise)}`, sous: `Le compte ${String(r.CompteUtilise || '').split('\\').pop()} a été utilisé vers ${srv} à ${T.hm(T.pdate(r.Date))}.` });
  }
  // 5. comptes crees pendant une fenetre
  const ajouts = T.table('evenements_comptes');
  for (const r of ajouts.filter(x => x.EventID === '4720' && dansFen(x))) {
    const nom = (/SamAccountName=(\S+)/.exec(r.Details || '') || [])[1] || String(r.CibleOuGroupe || '').split('\\').pop();
    const admin = ajouts.some(x => x.EventID === '4732' && /administrat/i.test(x.CibleOuGroupe || '') && String(x.Membre || '').toLowerCase().endsWith('\\' + nom.toLowerCase()));
    out.push({ id: 'compte-' + nom, titre: `Supprimer le compte « ${nom} »`, sous: `Créé à ${T.hm(T.pdate(r.Date))}${admin ? ' et mis administrateur' : ''}.` });
  }
  // 6. services installes pendant une fenetre (7045)
  for (const r of T.table('resume_evenements_cles').filter(x => x.EventID === '7045' && dansFen(x))) {
    const msg = r.Message || '';
    const m = /Service Name:\s*(.+?)\s+Service File Name:\s*(.+?)(?:\s+Service Type:|$)/i.exec(msg) || /Nom du service\s*:\s*(.+?)\s+Nom du fichier du service\s*:\s*(.+?)(?:\s+Type de service|$)/i.exec(msg) || /:\s*([^,]+),\s*(.+)$/.exec(msg) || [];
    const svc = (m[1] || '').trim(), bin = (m[2] || '').trim().replace(/^"([^"]*)".*$/, '$1');
    if ((!svc && !bin) || T.serviceOrdinaire(svc, bin)) continue;
    const dossier = bin.includes('\\') ? bin.slice(0, bin.lastIndexOf('\\')) : '';
    out.push({ id: 'svc-' + svc, titre: `Supprimer le service ${svc}${bin ? ' et ' + bin.split('\\').pop() : ''}`, sous: `Installé à ${T.hm(T.pdate(r.Date))}${dossier ? ' depuis ' + dossier : ''}.` });
  }
  // 7. exclusion Defender
  for (const r of T.table('resume_evenements_cles').filter(x => x.EventID === '5007' && /Exclusions/i.test(x.Message || ''))) {
    const ch = (/Exclusions\\(?:Paths|Extensions|Processes)\\(.+)$/i.exec(r.Message || '') || [])[1] || '';
    out.push({ id: 'excl-' + ch, titre: "Retirer l'exclusion Defender", sous: ch ? `Le dossier ${ch} est exclu depuis ${T.hm(T.pdate(r.Date))}.` : `Exclusion ajoutée à ${T.hm(T.pdate(r.Date))}.` });
  }
  // 8. bureau a distance expose
  const rdpPub = T.table('ouvertures_session_4624').filter(r => r.Type === '10' && T.typeIp(r.IP) === 'PUBLIQUE' && !T.estBlanche(T.nettoyerIp(r.IP))).sort((a, b) => T.pdate(b.Date) - T.pdate(a.Date));
  if (rdpPub.length) out.push({ id: 'rdp', titre: 'Fermer le Bureau à distance exposé sur Internet', sous: `La connexion de ${T.hm(T.pdate(rdpPub[0].Date))} venait d'une IP publique.` });
  // 9. chasse sur le parc
  const io = T.iocs();
  if (incident && (io.ip.length || io.hachages.length)) out.push({ id: 'parc', titre: 'Chercher les mêmes traces sur tout le parc', sous: 'Les indicateurs sont prêts pour Datto RMM.', lien: 'details/ioc' });
  // 10. assureur (incident constaté)
  if (incident) out.push({ id: 'assureur', titre: "Prévenir l'assureur cyber", sous: 'Et proposer au client le dépôt de plainte.' });
  return out;
});
T.nomServeur = (srv, compte) => {
  const c = String(compte || ''), s = String(srv || '');
  if (/nas/i.test(s) || /nas/i.test(c)) return /sauvegarde|backup|save/i.test(c + ' ' + s) ? 'le NAS de sauvegarde' : 'le NAS ' + s;
  return 'le serveur ' + s;
};

/* ======================================================================== chronologie racontee
   T.recit(fenetreId) : chapitres et etapes construits par des regles fixes.
   Chaque etape : chapitre, titre (present, sujet « il » sous-entendu), explication de faits,
   deduction eventuelle, preuves principales et traces liees (ids fichier#n). */
T.CHAPITRES = [{ n: '01', nom: 'Il entre' }, { n: '02', nom: "Il s'installe" }, { n: '03', nom: 'Il emporte les données' }, { n: '04', nom: 'Il détruit' }, { n: '05', nom: 'Autres événements' }];
T.CHAPITRES_NEUTRES = ['Connexion', 'Sur le poste', 'Données', 'Suppressions', 'Autres événements'];
const RX = {
  scan: /netscan|advanced_ip_scanner|advanced_port_scanner|angryip|ipscan|nmap|softperfect/i,
  mdp: OUTILS_MDP,
  archive: /(^|\\)(7z|7za|7zg|winrar|rar|zip)(\.exe)?$/i,
  envoi: /rclone|winscp|filezilla|pscp|megasync|megacmd|curl\.exe|ftp\.exe|restic/i,
  distance: /anydesk|rustdesk|teamviewer|screenconnect|ngrok|cloudflared|chisel|atera|splashtop|supremo/i,
  vss: /vssadmin|wbadmin|bcdedit|wmic.*shadow/i,
  journal: /wevtutil/i,
  latéral: /psexec|paexec|wmic/i
};
const DESTINATIONS = [[/mega/i, 'MEGA'], [/gdrive|drive\.google|google/i, 'Google Drive'], [/dropbox/i, 'Dropbox'], [/onedrive|sharepoint/i, 'OneDrive'], [/wetransfer/i, 'WeTransfer'], [/sftp|ftp/i, 'un serveur FTP'], [/s3|amazonaws/i, 'un stockage Amazon S3']];
const destination = txt => { for (const [r, n] of DESTINATIONS) if (r.test(txt || '')) return n; return ''; };
const base = p => String(p || '').split('\\').pop().toLowerCase().replace(/\.exe$/, '');
const tableDe = id => String(id).split('#')[0];
const enMin = (a, b) => Math.abs(a - b) / 60e3;

T.recit = fenId => T.memo('recit:' + fenId, () => {
  const fen = T.fenetres().find(f => f.id === fenId);
  if (!fen) return null;
  const dans = e => (e.fen || '').split(',').includes(fenId);
  const evts = T.chronologie().evenements.filter(dans);
  const execF = T.table('executions_fenetres').filter(r => String(r.Fenetre || '').split(',').includes(fenId)).map(r => ({ t: T.pdate(r.Date), r, id: r._id, prog: base(r.Programme || r.Chemin) })).filter(x => x.t).sort((a, b) => a.t - b.t);
  const avecExecF = execF.length > 0;
  const pris = new Set();                   // ids d'evenements de la chronologie expliques par une regle
  const etapes = [];
  const etape = (chap, t, titre, sens, preuves, liees = [], ded = '', autre = {}) => {
    preuves = [...new Set(preuves.filter(Boolean))]; liees = [...new Set(liees.filter(x => x && !preuves.includes(x)))];
    [...preuves, ...liees].forEach(x => pris.add(x));
    etapes.push(Object.assign({ chap, t, titre, sens, ded, preuves, liees, cle: chap + '-' + (+t) + '-' + titre }, autre));
  };
  const ev = (voie, rx) => evts.filter(e => e.voie === voie && (!rx || rx.test(e.titre + ' ' + e.detail)));
  // executions : table de la fenetre si l'analyse existe, sinon la chronologie
  const execs = avecExecF ? execF : evts.filter(e => e.voie === 'Executions').map(e => ({ t: e.t, r: { Programme: e.titre, Chemin: e.detail, Detail: e.detail, Compte: e.compte || '' }, id: e.id, prog: base(e.titre) }));
  if (avecExecF) evts.filter(e => e.voie === 'Executions').forEach(e => pris.add(e.id)); // memes executions, autre table
  const execDe = rx => execs.filter(x => rx.test(x.prog) || rx.test(x.r.Chemin || '') || rx.test(x.r.Detail || ''));
  const grouper = (liste, ecartMin) => { const g = []; for (const x of liste) { const d = g[g.length - 1]; if (d && enMin(x.t, d[d.length - 1].t) <= ecartMin) d.push(x); else g.push([x]); } return g; };
  const ipInfo = T.analyseIp().ips;

  /* ---------- 01 il entre : connexion reussie depuis une IP publique ---------- */
  const entrees = evts.filter(e => ['Connexions', 'Sessions'].includes(e.voie) && e.ip && ['PUBLIQUE', 'VPN/CGNAT'].includes(T.typeIp(T.nettoyerIp(String(e.ip).split('/')[0]))));
  const parIp = {};
  for (const e of entrees) { const a = T.nettoyerIp(String(e.ip).split('/')[0]); (parIp[a] = parIp[a] || []).push(e); }
  const ipsEntree = Object.keys(parIp);
  for (const [a, l] of Object.entries(parIp)) {
    l.sort((x, y) => x.t - y.t);
    const ses = l.find(e => e.voie === 'Sessions'), i = ipInfo.find(x => x.ip === a) || {};
    const pays = T.nomPays(i.pays);
    const brute = T.table('echecs_par_ip').find(r => T.nettoyerIp(r.IP) === a);
    const rdp = l.some(e => /type 10|1149|RDP|bureau à distance/i.test(e.titre));
    let sens = `${rdp ? 'Session Bureau à distance' : 'Connexion'} avec le compte ${String((ses && ses.compte) || (l.find(e => e.compte) || {}).compte || ((/^Connexion réussie de (\S+)/.exec(l[0].titre) || [])[1] || '?')).split('\\').pop()}, depuis ${a}`;
    if (ses && ses.fin) sens += `, jusqu'à ${T.hm(ses.fin)}`;
    sens += '.';
    if (brute) {
      const d0 = T.pdate(brute.Premier), d1 = T.pdate(brute.Dernier);
      const quand = !d0 ? '' : !d1 || T.jm(d0) === T.jm(d1) ? `le ${T.jm(d0)}` : (d0.getMonth() === d1.getMonth() && d1.getDate() - d0.getDate() === 1 ? `les ${p2(d0.getDate())} et ${T.jm(d1)}` : `du ${T.jm(d0)} au ${T.jm(d1)}`);
      sens += ` Cette IP avait raté ${T.nb(T.num(brute.NbEchecs))} connexions ${quand}.`;
    }
    const brutesFen = ev('Force brute').filter(e => T.nettoyerIp(String(e.ip || '')) === a);
    const ordre = ['ouvertures_session_4624', 'rdp_authentifications_1149', 'sessions_reconstituees'];
    const preuves = [...l].sort((x, y) => ordre.indexOf(tableDe(x.id)) - ordre.indexOf(tableDe(y.id))).map(e => e.id);
    const blanche = T.estBlanche(a);
    if (blanche) sens += ' Cette IP est dans la liste blanche.';
    etape(0, l[0].t, `Se connecte à distance ${pays && !blanche ? T.depuisPays(pays) : 'depuis ' + a}`, sens, [...preuves, brute && brute._id], brutesFen.map(e => e.id), '', { ses });
  }
  const fb = {};
  for (const e of ev('Force brute')) if (!pris.has(e.id)) (fb[e.ip || '?'] = fb[e.ip || '?'] || []).push(e);
  for (const [a, l] of Object.entries(fb)) {
    const n = l.reduce((s, e) => s + (T.num(e.n) || 1), 0), z = l[l.length - 1].t;
    const cpt = [...new Set(l.flatMap(e => String(e.detail).replace(/^comptes essayes : /, '').split(/,\s*/)).map(c => c.replace(/^\\/, '').trim()).filter(Boolean))];
    etape(0, l[0].t, /^(-|\?|)$/.test(a) ? 'Tente des mots de passe (adresse non enregistrée)' : `Tente des mots de passe depuis ${a}`, `${T.nb(n)} échec${n > 1 ? 's' : ''}${l.length > 1 ? ` entre ${T.hm(l[0].t)} et ${T.hm(z)}` : ''}. Comptes essayés : ${cpt.slice(0, 8).join(', ')}${cpt.length > 8 ? '…' : ''}.`, l.map(e => e.id));
  }

  /* ---------- 02 il s'installe ---------- */
  for (const g of grouper(execDe(RX.scan), 30)) {
    const x = g[0], dossier = (x.r.Chemin || '').replace(/\\[^\\]+$/, '');
    etape(1, x.t, 'Scanne le réseau du cabinet', `${x.prog}.exe, lancé${dossier ? ' depuis ' + dossier.replace(/^c:/, 'C:').replace(/\\users\\public\\music/i, '\\Users\\Public\\Music') : ''}, cherche les autres machines du réseau.`, [...g].sort((a, b) => b.t - a.t).map(y => y.id));
  }
  const def = ev('Antivirus'), j5001 = ev('Journaux', evt(5001)), j5007 = ev('Journaux', evt(5007));
  if (def.length || j5001.length || j5007.length) {
    const tous = [...def, ...j5001, ...j5007].sort((a, b) => a.t - b.t);
    const bouts = [];
    if (def.length) { const cible = (/file:_?(\S+)/i.exec(def[0].detail) || [])[1] || ([...String(def[0].detail).matchAll(/([^\s\\/]+\.(exe|dll|ps1|bat|js|vbs))/gi)].pop() || [])[0] || ''; const f = cible.split('\\').pop(); bouts.push(`Defender détecte ${f || 'un programme malveillant'} à ${T.hm(def[0].t)}.`); }
    const coupe = j5001.length ? `La protection temps réel est coupée à ${T.hm(j5001[0].t)}` : '';
    const excl = j5007.find(e => /Exclusions/i.test(e.detail)), chExcl = excl ? ((/Exclusions\\(?:Paths|Extensions|Processes)\\(.+)$/i.exec(excl.detail) || [])[1] || '') : '';
    const ex2 = excl ? `le dossier ${chExcl} est exclu à ${T.hm(excl.t)}` : '';
    if (coupe || ex2) bouts.push([coupe, ex2].filter(Boolean).join(', ').replace(/^l/, c => coupe ? c : 'L') + '.');
    etape(1, tous[0].t, j5001.length || excl ? "Neutralise l'antivirus" : 'Déclenche une détection de l\'antivirus', bouts.join(' '), tous.map(e => e.id));
  }
  const mdp = execDe(RX.mdp);
  if (mdp.length) {
    const progs = []; for (const x of mdp) if (!progs.find(p => p.prog === x.prog)) progs.push(x);
    const sens = progs.map((x, i) => `${i ? 'puis ' : ''}${/mimi/i.test(x.prog) ? 'mimikatz (' + x.prog + '.exe)' : x.prog} à ${T.hm(x.t)}`).join(', ');
    const tri = [...mdp].sort((a, b) => a.t - b.t || (/Prefetch/i.test(a.r.Source) ? -1 : 1));
    etape(1, mdp[0].t, 'Lance des outils de vol de mots de passe', sens[0].toUpperCase() + sens.slice(1) + '.', tri.filter(x => /Prefetch/i.test(x.r.Source || '')).concat(tri.filter(x => !/Prefetch/i.test(x.r.Source || ''))).map(x => x.id));
  }
  for (const e of ev('Comptes', evt(4648))) {
    const r = T.preuve(e.id) || {};
    etape(1, e.t, `Utilise le compte ${T.nomServeur(r.Serveur, r.CompteUtilise).replace(/^le /, 'du ')}`.replace('du serveur', 'du serveur'),
      `Le compte ${String(r.CompteUtilise || '').split('\\').pop()} est utilisé vers ${r.Serveur || '?'} depuis la session de ${String(r.Auteur || '').split('\\').pop()}.`, [e.id]);
  }
  const comptes = ev('Comptes').filter(e => evt(4720, 4722, 4724, 4728, 4732, 4756).test(e.titre));
  const crees = comptes.filter(e => evt(4720).test(e.titre));
  for (const c of crees) {
    const r = T.preuve(c.id) || {}, nom = (/SamAccountName=(\S+)/.exec(r.Details || '') || [])[1] || String(r.CibleOuGroupe || '').split('\\').pop();
    const lies = comptes.filter(e => e !== c && String((T.preuve(e.id) || {}).Membre || '').toLowerCase().endsWith('\\' + nom.toLowerCase()) && enMin(e.t, c.t) <= 60);
    const admin = lies.some(e => /administrat/i.test((T.preuve(e.id) || {}).CibleOuGroupe || ''));
    const groupes = lies.map(e => { const gr = String((T.preuve(e.id) || {}).CibleOuGroupe || '').split('\\').pop(); return /administrat/i.test(gr) ? 'aux Administrateurs' : /bureau a distance|remote desktop/i.test(gr) ? 'au Bureau à distance' : 'au groupe ' + gr; });
    const fin = lies.length ? lies[lies.length - 1].t : c.t;
    let sens = groupes.length ? `Ajouté ${groupes.join(' puis ')} en ${Math.round((fin - c.t) / 1000)} secondes.` : `Créé par ${String(r.Auteur || '').split('\\').pop()}.`;
    const ensuite = execs.filter(x => String(x.r.Compte || '').toLowerCase() === nom.toLowerCase() && x.t > fin).map(x => x.prog + '.exe');
    if (ensuite.length) sens += ` Ce compte lance ensuite ${[...new Set(ensuite)].join(' et ')}.`;
    etape(1, c.t, `Crée un compte ${admin ? 'administrateur ' : ''}« ${nom} »`, sens, [c.id, ...lies.map(e => e.id)]);
  }
  for (const e of comptes) if (!pris.has(e.id)) etape(1, e.t, 'Modifie un compte', e.titre, [e.id]);
  for (const e of ev('Journaux', evt(7045, 4697))) {
    // message en anglais (« Service Name: X Service File Name: Y ») ou en français (« Nom du service : X Nom du fichier du service : Y »)
    const en = /Service Name:\s*(.+?)\s+Service File Name:\s*(.+?)(?:\s+Service Type:|$)/i.exec(e.detail) || /Nom du service\s*:\s*(.+?)\s+Nom du fichier du service\s*:\s*(.+?)(?:\s+Type de service|$)/i.exec(e.detail);
    const m = en || /:\s*([^,]+),\s*(.+)$/.exec(e.detail) || [], svc = (m[1] || '').trim(), bin = (m[2] || '').trim().replace(/^"([^"]*)".*$/, '$1'), b = base(bin);
    if (T.serviceOrdinaire(svc, bin)) { pris.add(e.id); continue; }
    const faux = /^(svhost|scvhost|svch0st|svchosts|scvhost|lsas|lsasss|csrsss|expl0rer|svchost32)$/i.test(b);
    const runs = execs.filter(x => x.prog === b);
    const lance = runs.find(x => /Prefetch/i.test(x.r.Source || '')) || runs[0];
    etape(1, e.t, faux ? `Installe un faux service « ${b} »` : (svc || b) ? `Installe le service « ${svc || b} »` : 'Installe un service',
      `${b}.exe${faux ? ', au nom proche de svchost.exe,' : ''} est installé comme service ${svc}${lance ? `, puis lancé à ${T.hm(lance.t)}` : ''}.`, [e.id, ...[...runs].sort((x, y) => (/Prefetch/i.test(x.r.Source || '') ? -1 : 1)).map(x => x.id)]);
  }
  for (const e of ev('Journaux', evt(4698))) etape(1, e.t, 'Crée une tâche planifiée', e.detail, [e.id]);
  for (const e of ev('Journaux', evt(4719))) etape(1, e.t, 'Change ce que Windows note dans ses journaux', e.detail, [e.id]);
  for (const g of grouper(execDe(RX.distance), 60)) etape(1, g[0].t, `Installe un outil d'accès à distance (${g[0].prog})`, `${g[0].prog}.exe lancé à ${T.hm(g[0].t)}.`, g.map(x => x.id));
  for (const g of grouper(execDe(RX.latéral), 30)) if (!g.every(x => pris.has(x.id))) etape(1, g[0].t, `Lance ${g[0].prog} vers d'autres postes`, `${g[0].prog}.exe à ${T.hm(g[0].t)}.`, g.map(x => x.id));

  /* ---------- 03 il emporte les donnees ---------- */
  const nav = ev('Navigation');
  const metier = nav.filter(e => /SANTE|METIER/i.test(e.titre));
  for (const g of grouper(metier, 30)) {
    const rows = g.map(e => T.preuve(e.id) || {});
    const site = ((rows[0].Titre || '').split(' - ').slice(1).join(' - ') || g[0].titre.split(' ')[0]).replace(/\s*\(.*?\)\s*/g, '').trim();
    const pages = [...new Set(rows.map(r => (r.Titre || '').split(' - ')[0].trim()).filter(Boolean))];
    const art = p => { const m = p.toLowerCase(); return /s$/.test(m) ? 'les ' + m : /^[aeiouyéèh]/.test(m) ? "l'" + m : 'le ' + m; };
    const titre = pages.length ? `Ouvre ${pages.map(art).join(' et ').replace(/ et (?=.* et )/g, ', ')} dans ${site}` : `Consulte ${site}`;
    etape(2, g[0].t, titre, `Pages ${pages.join(' et ') || site} consultées dans ${rows[0].Navigateur ? rows[0].Navigateur[0].toUpperCase() + rows[0].Navigateur.slice(1) : 'le navigateur'} avec le compte ${rows[0].Utilisateur || '?'}.`, g.map(e => e.id));
  }
  const accesMetier = ev('Fichiers', /^Données du cabinet ouvertes|tsclient/i);
  for (const g of grouper(execDe(RX.archive), 15)) {
    const cmd = g.map(x => x.r.Detail || '').find(d => /\s(a|u)\s/.test(d + ' ')) || '';
    const tokens = cmd.split(/\s+/);
    const ia = tokens.findIndex(tk => /\.(7z|zip|rar)$/i.test(tk));
    const archive = ia >= 0 ? tokens[ia] : '', source = ia >= 0 ? tokens.slice(ia + 1).join(' ') : '';
    const usn = ev('Fichiers', /^Archive créée :/).filter(e => !archive || e.titre.toLowerCase().includes(archive.split('\\').pop().toLowerCase()));
    const finEcr = usn.filter(e => /CLOSE|EXTEND/i.test(e.detail)).sort((a, b) => b.t - a.t)[0];
    const metierSrc = /logos|medist|axisante|weda|hellodoc|crossway|julie|dentalvision|visiodent|logosw|doctolib|\\data\b/i.test(source + ' ' + cmd);
    const principal = g.find(x => /4688/.test(x.r.Source || '')) || g[0];
    const sens = archive ? `${principal.prog === '7z' ? '7-Zip' : principal.prog} met ${source || 'des fichiers'} dans l'archive ${archive.split('\\').pop()}${/\s-p/.test(cmd) ? ', protégée par mot de passe' : ''}.${finEcr ? ` Écriture terminée à ${T.hm(finEcr.t)}.` : ''}` : `${principal.prog}.exe lancé à ${T.hm(principal.t)}.`;
    const lies = accesMetier.filter(e => enMin(e.t, principal.t) <= 30 && e.t <= principal.t);
    etape(2, principal.t, metierSrc ? 'Compresse les données du logiciel métier' : 'Compresse des fichiers', sens, [principal.id, ...usn.sort((a, b) => a.t - b.t).map(e => e.id)], [...lies.map(e => e.id), ...g.filter(x => x !== principal).map(x => x.id)]);
  }
  for (const e of accesMetier) if (!pris.has(e.id)) etape(2, e.t, /tsclient/i.test(e.titre) ? 'Copie des fichiers par le Bureau à distance' : 'Ouvre les données du logiciel métier', e.titre.replace(/^Données du cabinet ouvertes : /, '') + '.', [e.id]);
  const srumFen = T.table('srum_total_par_releve').filter(r => String(r.Fenetre || '').split(',').includes(fenId));
  for (const g of grouper(execDe(RX.envoi), 120)) {
    const prog = g[0].prog, cmd = g.map(x => x.r.Detail || '').find(d => /copy|sync|move|put|upload|-T/i.test(d)) || '';
    const releves = srumFen.filter(r => base(r.PremiereAppliEnvoi) === prog && T.num(r.PremiereAppliEnvoyeMo) > 0).sort((a, b) => T.pdate(a.Releve) - T.pdate(b.Releve));
    const mo = releves.reduce((s, r) => s + T.num(r.PremiereAppliEnvoyeMo), 0);
    const sites = nav.filter(e => /PARTAGE|TRANSFERT|OUTILS|ACCES DISTANT/i.test(e.titre) && (e.t >= +g[0].t - 15 * 60e3));
    const dest = destination(cmd) || destination(sites.map(e => e.titre).join(' '));
    const dernier = releves.length ? T.pdate(releves[releves.length - 1].Releve) : null;
    const fichier = (cmd.split(/\s+/).find(tk => /\.(7z|zip|rar|csv|sql|bak|tar|gz)$/i.test(tk)) || '').split('\\').pop();
    const remote = (/\s([A-Za-z0-9_-]{2,}:[^\s\\]*)/.exec(cmd) || [])[1] || '';
    const exPl = T.exfil().fenetres.find(f => f.id === fenId);
    let sens = `${prog} ${fichier ? 'copie ' + fichier : 'envoie des fichiers'}${remote ? ' vers ' + remote : dest ? ' vers ' + dest : ''}${dernier ? ` jusqu'à ${T.hm(dernier)}` : ''}.`;
    if (exPl && exPl.niveau === 'PLAUSIBLE') sens += ' Volume compatible avec une copie de la base patients.';
    const telech = ev('Navigation', /^Téléchargement/).filter(e => new RegExp(prog, 'i').test(e.titre + e.detail));
    const creation = evts.filter(e => e.voie === 'Fichiers' && new RegExp(prog + '\\.exe', 'i').test(e.detail));
    const navLies = sites.filter(e => new RegExp(prog + '|' + (dest.split(' ')[0] || '§'), 'i').test(e.titre + ' ' + e.detail) || /PARTAGE|TRANSFERT/i.test(e.titre));
    const tri = [...g].sort((a, b) => (/4688/.test(b.r.Source || '') ? 1 : 0) - (/4688/.test(a.r.Source || '') ? 1 : 0) || (/Prefetch/i.test(b.r.Source || '') ? 1 : 0) - (/Prefetch/i.test(a.r.Source || '') ? 1 : 0));
    etape(2, g[0].t, mo ? `Envoie ${T.volume(mo, 2)}${dest ? ' vers ' + dest : ' sur Internet'}` : `Lance ${prog}${dest ? ' vers ' + dest : ''}`, sens,
      [...tri.map(x => x.id), ...releves.map(r => r._id), ...navLies.map(e => e.id)], [...telech, ...creation].map(e => e.id),
      dernier ? `Fin de l'envoi placée à ${T.hm(dernier)} d'après le dernier relevé SRUM élevé, pas d'après un événement de fin.` : '');
  }
  for (const e of [...nav.filter(e => /PARTAGE|TRANSFERT/i.test(e.titre)), ...ev('USB')]) if (!pris.has(e.id) && e.g >= 2) etape(2, e.t, e.voie === 'USB' ? 'Branche un périphérique USB' : `Ouvre ${e.titre.split(' ')[0]}`, e.detail || e.titre, [e.id]);

  /* ---------- 04 il detruit ---------- */
  // seulement une vraie suppression : « vssadmin list shadows » ou Add-MpPreference ne suppriment rien
  const RX_SUPPR = /vssadmin.*\b(delete|resize)\b|shadowcopy.*delete|wbadmin.*delete|bcdedit.*(recoveryenabled|bootstatuspolicy)|win32_shadowcopy.*delete/i;
  const destr = ev('Rancongiciel', /^Commande destructrice/).filter(e => RX_SUPPR.test(e.detail)),
    vssExec = execDe(RX.vss).filter(x => RX_SUPPR.test(`${x.r.Detail || ''} ${x.r.Chemin || ''} ${x.r.LigneDeCommande || ''}`));
  if (destr.length || vssExec.length) {
    const tous = [...destr, ...vssExec].sort((a, b) => a.t - b.t), r = destr.length ? T.preuve(destr[0].id) || {} : {};
    const compte = r.Compte || r.Utilisateur || (vssExec[0] && vssExec[0].r.Compte) || '';
    etape(3, tous[0].t, 'Supprime les sauvegardes Windows', `Les clichés VSS sont effacés${compte ? ` avec le compte « ${String(compte).split('\\').pop()} »` : ''}. Windows ne peut plus restaurer les fichiers.`, [...destr.map(e => e.id), ...vssExec.map(x => x.id)]);
  }
  for (const e of ev('Rancongiciel', /^Chiffrement/)) {
    const r = T.preuve(e.id) || {}, ext = r.Extension || '';
    const notes = ev('Rancongiciel', /^Note de rançon/), n0 = notes[0] ? T.preuve(notes[0].id) || {} : null;
    const paquets = evts.filter(x => x.voie === 'Fichiers' && /modifications? de fichiers/.test(x.titre) && ext && x.detail.includes(ext));
    etape(3, e.t, `Chiffre ${T.nb(T.num(r.NbFichiers))} fichiers`, `Extension ${ext}, ${T.nb(Math.floor(T.num(r.TailleMo)))} Mo en ${String(r.DureeMinutes || '?').replace('.', ',')} minutes.${n0 ? ` Note de rançon déposée dans ${T.nb(T.num(n0.NbDossiers))} dossiers.` : ''}`,
      [e.id, ...notes.map(x => x.id)], paquets.map(x => x.id));
  }
  for (const e of ev('Rancongiciel', /^Note de rançon/)) if (!pris.has(e.id)) etape(3, e.t, 'Dépose une note de rançon', e.titre, [e.id]);
  const effac = ev('Journaux', evt(104, 1102)), wev = execDe(RX.journal);
  for (const e of effac) {
    const quel = evt(1102).test(e.titre) ? 'Sécurité' : ((/journal (\w+)/i.exec(e.detail) || [])[1] || 'System').replace(/^System$/i, 'Système');
    const w = wev.filter(x => enMin(x.t, e.t) <= 5);
    const compte = w.map(x => x.r.Compte).find(Boolean);
    etape(3, (w[0] && w[0].t < e.t) ? w[0].t : e.t, `Efface le journal ${quel}`, w.length ? `Avec wevtutil${compte ? ` et le compte « ${compte} »` : ''}.` : 'Événement d\'effacement enregistré par Windows.', [e.id, ...w.map(x => x.id)]);
  }
  for (const x of wev) if (!pris.has(x.id)) etape(3, x.t, 'Efface des journaux Windows', x.r.Detail || 'wevtutil', [x.id]);
  for (const e of ev('Journaux', evt(4616))) etape(3, e.t, "Modifie l'heure du poste", e.detail, [e.id]);

  /* ---------- tout le reste d'important : rien ne disparait en silence ---------- */
  const evExec = evts.filter(e => e.voie === 'Executions');
  const gExec = x => { const m = evExec.find(e => base(e.titre) === x.prog && enMin(e.t, x.t) <= 2); return m ? m.g : (x.r.OutilSensible === 'OUI' ? 3 : 1); };
  const execsRest = execs.filter(x => !pris.has(x.id) && (avecExecF ? gExec(x) : (evts.find(e => e.id === x.id) || {}).g) >= 2);
  const parProg = {}; for (const x of execsRest) (parProg[x.prog] = parProg[x.prog] || []).push(x);
  for (const l of Object.values(parProg)) for (const g of grouper(l, 2)) etape(4, g[0].t, `Lance ${g[0].prog}.exe`, `${(g[0].r.Chemin || '').trim() || g[0].prog + '.exe'}${g[0].r.Compte ? `, compte ${g[0].r.Compte}` : ''}.`, g.map(x => x.id));
  for (const e of evts.filter(e => e.g >= 2 && !pris.has(e.id) && e.voie !== 'Executions')) etape(4, e.t, e.titre, e.detail, [e.id]);

  // chapitres non vides, etapes dans l'ordre chronologique
  // fenetre legitime (liste blanche) : chapitres aux noms neutres, personne n'est presente comme attaquant
  const neutre = (T.exfil().fenetres.find(x => x.id === fenId) || {}).legitime;
  // etapes identiques qui se suivent (ex. 18 x « Efface des journaux Windows » en 2 min) : une seule etape « x 18 »
  const regrouper = l => {
    const r = [];
    for (const s of l) {
      const p = r[r.length - 1];
      if (p && p.titreBase === s.titre && enMin(s.t, p.tFin) <= 30) { p.n++; p.tFin = s.t; p.preuves = [...new Set([...p.preuves, ...s.preuves])]; p.liees = [...new Set([...p.liees, ...s.liees])]; p.titre = `${p.titreBase} (× ${p.n})`; continue; }
      r.push(Object.assign({}, s, { titreBase: s.titre, n: 1, tFin: s.t }));
    }
    return r;
  };
  // « Autres événements » : les 40 premiers ; le reste reste dans Détails › Tous les événements
  const MAX_AUTRES = 40;
  const chapitres = T.CHAPITRES.map((c, i) => {
    let l = regrouper(etapes.filter(s => s.chap === i).sort((a, b) => a.t - b.t));
    const caches = i === 4 && l.length > MAX_AUTRES ? l.length - MAX_AUTRES : 0;
    if (caches) l = l.slice(0, MAX_AUTRES);
    return { n: c.n, nom: neutre ? T.CHAPITRES_NEUTRES[i] : c.nom, etapes: l, caches };
  }).filter(c => c.etapes.length);
  chapitres.forEach(c => { const a = c.etapes[0].t, z = c.etapes[c.etapes.length - 1].t; c.plage = T.hm(a) === T.hm(z) ? T.hm(a) : `${T.hm(a)} → ${T.hm(z)}`; });
  const toutes = chapitres.flatMap(c => c.etapes);
  if (!toutes.length) return { fen, chapitres: [], etapes: [], ipsEntree, debut: fen.debut, fin: fen.fin, periode: T.periode(fen.debut, fen.fin) };
  const debut = toutes.reduce((m, s) => s.t < m ? s.t : m, toutes[0].t);
  let fin = toutes.reduce((m, s) => s.t > m ? s.t : m, toutes[0].t);
  for (const s of toutes) if (s.ses && s.ses.fin && s.ses.fin > fin && s.ses.fin <= fen.fin) fin = s.ses.fin;
  return { fen, chapitres, etapes: toutes, ipsEntree, debut, fin, periode: T.periode(debut, fin) };
});
