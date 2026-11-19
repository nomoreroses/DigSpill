/* ============================================================================
   03_ia.js : analyse par Claude sur une synthese FILTREE + verification de chaque citation
   - comptes pseudonymises (U1, U2...), noms de fichiers / dossiers non techniques masques,
     URL reduites au domaine, adresses e-mail masquees ;
   - l'apercu exact de ce qui part est affiche avant tout envoi ;
   - chaque phrase de la reponse est controlee : citation existante ? valeurs presentes dans la preuve ?
   ============================================================================ */
'use strict';

const GENERIQUES = new Set(['c:', 'd:', 'e:', 'windows', 'system32', 'syswow64', 'program files', 'program files (x86)', 'programdata', 'users', 'public', 'appdata', 'local', 'roaming',
  'locallow', 'temp', 'tmp', 'desktop', 'bureau', 'documents', 'downloads', 'telechargements', 'téléchargements', 'music', 'musique', 'pictures', 'images', 'videos', 'vidéos', 'microsoft',
  'google', 'chrome', 'application', 'edge', 'mozilla', 'firefox', 'user data', 'default', 'prefetch', 'perflogs', '$recycle.bin', 'logos_w', 'axisante', 'axi', 'medistory', 'julie',
  'hellodoc', 'crossway', 'data', 'database', 'export', 'sauvegarde', 'backup', 'outils', 'tools', 'netbird', 'splashtop', 'anydesk', 'teamviewer', 'rustdesk', '7-zip', 'winrar', 'rclone',
  'sysinternals', 'nirsoft', 'tsclient', 'onedrive', 'dropbox', 'mega', 'megasync', 'drivers', 'tasks', 'office16', 'root', 'microsoft office', 'courriers']);
const RX_EXEC = /\.(exe|dll|ps1|psm1|bat|cmd|vbs|js|hta|scr|msi|sys|lnk|7z|zip|rar|tar|gz|fdb|gdb|mdf|ldf|4dd)$/i;
const RX_CIT = /\[([A-Za-z0-9_.]+#\d+)\]/g;

T.Masque = class {
  constructor() { this.comptes = new Map(); }
  compte(nom) {
    if (!nom) return '';
    const i = nom.lastIndexOf('\\'), dom = i >= 0 ? nom.slice(0, i) : '', base = i >= 0 ? nom.slice(i + 1) : nom;
    if (!base || /^(system|systeme|-|anonymous logon|administrateur|administrator|invite|guest|defaultaccount|support)$/i.test(base)) return nom;
    const k = base.toLowerCase(); if (!this.comptes.has(k)) this.comptes.set(k, 'U' + (this.comptes.size + 1));
    return (dom && dom !== '-' ? dom.replace(/^(?!BUILTIN|NT AUTHORITY|AUTORITE NT).*$/i, 'DOMAINE') + '\\' : '') + this.comptes.get(k);
  }
  chemin(p) {
    if (!p) return '';
    const parts = String(p).split(/[\\/]/);
    return parts.map((x, i) => {
      const xl = x.toLowerCase();
      if (i > 0 && parts[i - 1].toLowerCase() === 'users' && !['public', 'default', 'all users'].includes(xl)) return this.compte(x);
      if (i === parts.length - 1 && RX_EXEC.test(x)) return x;
      if (GENERIQUES.has(xl) || /^[a-z]:$/i.test(x) || x === '') return x;
      if (i === parts.length - 1) { const e = x.includes('.') ? x.split('.').pop() : ''; return e && e.length <= 5 ? `[fichier .${e}]` : '[fichier]'; }
      return '[dossier]';
    }).join('\\');
  }
  url(u) { const m = /^[a-z]+:\/\/([^/:?#]+)/i.exec(u || ''); return m ? m[1] : ''; }
  texte(t) {
    t = String(t || '').replace(/[a-z]:\\[^\s"'|,;]+/gi, m => this.chemin(m)).replace(/https?:\/\/[^\s"'|,;]+/gi, m => this.url(m)).replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '[email]');
    for (const [nom, code] of [...this.comptes].sort((a, b) => b[0].length - a[0].length)) t = t.replace(new RegExp(`\\b${nom.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'gi'), code);
    return t;
  }
};

T.syntheseIA = () => {
  const mq = new T.Masque(), ip = T.analyseIp().ips, ex = T.exfil();
  const conv = { Compte: v => mq.compte(v), Utilisateur: v => mq.compte(v), Auteur: v => mq.compte(v), CibleOuGroupe: v => mq.compte(v), Membre: v => mq.compte(v),
    Chemin: v => mq.chemin(v), Fichier: v => mq.chemin(v), Detail: v => mq.texte(v), Url: v => mq.url(v), Constat: v => mq.texte(v), Motif: v => mq.texte(v), ProcessName: v => mq.chemin(v) };
  const lignes = (nom, cols, limite, filtre) => {
    const out = [];
    for (const r of T.table(nom)) {
      if (filtre && !filtre(r)) continue;
      const o = { id: r._id }; for (const k of cols) { let v = r[k]; if (v === undefined || v === '') continue; if (conv[k]) v = conv[k](v); o[k] = v; }
      out.push(o); if (out.length >= limite) break;
    }
    return out;
  };
  const s = {
    poste: 'POSTE-ANALYSE', date_collecte: T.identite().date, consigne_heures: 'Heures locales du poste collecte.',
    fenetres: T.fenetres().map(w => ({ id: w.id, debut: T.fdate(w.debut), fin: T.fdate(w.fin), motif: mq.texte(w.motif), preuve: w.preuve })),
    grille_verification: lignes('grille_verification', ['Canal', 'Statut', 'Constat'], 60),
    sessions: lignes('sessions_reconstituees', ['Debut', 'Fin', 'DureeMin', 'FinPar', 'Compte', 'Type', 'IP', 'TypeIP'], 80, r => r.TypeIP !== '-' || /type 10|RDP/i.test(r.Type || '')),
    ip: ip.filter(e => e.type !== 'Privee').slice(0, 60).map(e => ({ ip: e.ip, type: e.type, pays: e.pays, operateur: e.operateur, categorie: e.categorie, succes: e.succes, echecs: e.echecs,
      premier: e.premier, dernier: e.dernier, listes: e.listes.map(l => l.nom), liste_blanche: !!e.blanche, active_a_la_collecte: e.active, preuves: e.preuves.slice(0, 4) })),
    executions_pendant_fenetres: lignes('executions_fenetres', ['Date', 'Source', 'Programme', 'Chemin', 'Compte', 'Detail', 'OutilSensible', 'Fenetre'], 150),
    volumes_envoyes: ex.fenetres.map(f => ({ id: f.id, debut: T.fdate(f.debut), fin: T.fdate(f.fin), duree_min: f.duree, envoye_mo: Math.round(f.envoye * 10) / 10,
      capacite_ligne_mo: f.capacite ? Math.round(f.capacite) : null, niveau: f.niveau, constats: f.constats, apps: f.apps.slice(0, 5).map(a => ({ app: a.app, mo: Math.round(a.mo * 10) / 10, ecart: a.ecart, preuves: a.ids.slice(0, 2) })),
      preuves: f.preuves.slice(0, 6) })),
    hypotheses_volumes: { taille_base_mo: ex.hyp.taille, compression: ex.hyp.compression, debit_montant_mbps: ex.hyp.debit || null, note: 'hypotheses saisies par le technicien' },
    reference_srum: ex.ref,
    navigation_pendant_fenetres: lignes('navigation_fenetres', ['Date', 'Utilisateur', 'Categorie', 'Url', 'Fenetre'], 80),
    telechargements_pendant_fenetres: lignes('telechargements', ['Date', 'Fichier', 'Url', 'Fenetre'], 20, r => !!r.Fenetre),
    acces_fichiers: lignes('acces_fichiers_lnk_jumplists_shellbags', ['Date1', 'Source', 'Chemin', 'Utilisateur', 'Fenetre', 'TSCLIENT', 'DONNEES_METIER'], 40, r => r.Fenetre || r.TSCLIENT || r.DONNEES_METIER),
    comptes: lignes('evenements_comptes', ['Date', 'EventID', 'Action', 'Auteur', 'CibleOuGroupe', 'Membre'], 40),
    rancon: [...lignes('fichiers_chiffres_par_extension', ['Extension', 'NbFichiers', 'TailleMo', 'Premier', 'Dernier', 'DureeMinutes'], 10), ...lignes('notes_rancon_candidates', ['Nom', 'NbDossiers', 'Derniere'], 5)],
    antivirus: lignes('defender_detections', ['InitialDetectionTime', 'ProcessName', 'Resources', 'ActionSuccess'], 30),
    anti_forensique: T.visibilite().anti.slice(0, 20).map(a => ({ date: a.date, trace: a.trace, preuve: a.id })),
    usb_pendant_fenetres: lignes('usb_chronologie', ['Date', 'Source', 'Peripherique', 'Fenetre'], 20, r => !!r.Fenetre),
    archives_creees: lignes('usn_fenetres', ['Date', 'Fichier', 'Raison', 'Fenetre'], 30, r => r.Archive === 'OUI'),
    couverture_journaux: lignes('journaux_couverture', ['Journal', 'Present', 'PremierEvt', 'DernierEvt'], 20)
  };
  // les champs Resources de Defender contiennent des chemins
  s.antivirus.forEach(a => { if (a.Resources) a.Resources = mq.texte(a.Resources); });
  return { synthese: s, masque: mq };
};

T.PROMPT_SYSTEME = `Tu es un analyste en reponse a incident (DFIR) qui assiste un technicien d'infogerance francais.
Le client est un cabinet de sante : les donnees patients sont des donnees de sante (art. 9 RGPD).
Tu recois une SYNTHESE FILTREE d'une collecte de triage Windows (JSON). Les comptes sont pseudonymises (U1, U2...),
les noms de fichiers non techniques sont masques. Chaque element porte un identifiant de preuve ("id", "preuve" ou "preuves").

REGLES STRICTES :
- Chaque phrase factuelle se termine par au moins une citation au format [identifiant], par ex. [sessions_reconstituees#3].
  N'utilise QUE des identifiants presents dans la synthese. N'invente aucun fait, aucune IP, aucune heure.
- Toute supposition ou interpretation qu'aucune preuve n'etablit directement commence par "(deduction)".
- Reprends les valeurs exactement comme dans la synthese (IP, heures au format HH:MM, volumes en Mo, noms de programmes).
- Ne conclus pas a la place de l'analyste : propose une position graduee et ce qui la ferait evoluer.
- La decision d'informer les patients (art. 34 RGPD) appartient au responsable de traitement (le cabinet) et a son DPO.
- Francais simple, phrases courtes, une idee par phrase.

FORMAT (Markdown) :
## Resume pour le praticien
(5 lignes maximum, sans jargon)
## Deroule de l'attaque
(liste chronologique, une ligne par etape)
## Exfiltration : position graduee
## Points a verifier en priorite
## Actions immediates recommandees`;

T.apercuIA = () => {
  const { synthese, masque } = T.syntheseIA();
  const texte = JSON.stringify(synthese, null, 1);
  return { texte, ko: Math.round(new Blob([texte]).size / 1024), tokens: Math.round(texte.length / 3.2), comptes: masque.comptes.size, masque };
};

T.lancerIA = async (cle, modele) => {
  const { synthese, masque } = T.syntheseIA();
  const corps = { model: modele, max_tokens: 6000, system: T.PROMPT_SYSTEME,
    messages: [{ role: 'user', content: 'Synthese de la collecte :\n```json\n' + JSON.stringify(synthese) + '\n```\nRedige l\'analyse.' }] };
  const r = await fetch('https://api.anthropic.com/v1/messages', { method: 'POST', headers: {
    'content-type': 'application/json', 'x-api-key': cle, 'anthropic-version': '2023-06-01', 'anthropic-dangerous-direct-browser-access': 'true' }, body: JSON.stringify(corps) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error((j.error && j.error.message) || ('HTTP ' + r.status));
  const texte = (j.content || []).filter(x => x.type === 'text').map(x => x.text).join('');
  return Object.assign(T.verifierIA(texte, masque), { modele: j.model, usage: j.usage });
};

const faits = phrase => {
  const s = phrase.replace(RX_CIT, ' '), f = new Set();
  (s.match(/\b\d{1,3}(?:\.\d{1,3}){3}\b/g) || []).forEach(x => f.add(x));
  (s.match(/\b[0-2]?\d[:h][0-5]\d\b/g) || []).forEach(x => f.add(x.replace('h', ':').padStart(5, '0')));
  (s.match(/\b20\d\d-\d\d-\d\d\b/g) || []).forEach(x => f.add(x));
  (s.match(/\b[\w.-]+\.(?:exe|ps1|bat|dll|7z|zip|rar)\b/gi) || []).forEach(x => f.add(x.toLowerCase()));
  return [...f];
};
/** decoupe la reponse en phrases et controle chaque citation contre les lignes de preuve */
T.verifierIA = (texte, masque) => {
  masque = masque || T.syntheseIA().masque;
  const phrases = [];
  for (const ligne of String(texte).split('\n')) {
    if (!ligne.trim()) { phrases.push({ texte: '', statut: 'vide' }); continue; }
    if (/^\s*#/.test(ligne)) { phrases.push({ texte: ligne.replace(/^\s*#+\s*/, ''), statut: 'titre' }); continue; }
    const puce = /^\s*([-*]|\d+[.)])\s+/.test(ligne);
    const morceaux = ligne.replace(/^\s*([-*]|\d+[.)])\s+/, '').split(/(?<=[.!?\]])\s+(?=[A-ZÀÉÈ(0-9])/);
    morceaux.forEach((p, i) => {
      if (!p.trim()) return;
      const ids = [...p.matchAll(RX_CIT)].map(m => m[1]);
      const deduction = /\(d[ée]duction\)/i.test(p);
      const o = { texte: p, puce: puce && i === 0, citations: [], inconnues: [], absentes: [], deduction };
      if (!ids.length) { o.statut = deduction ? 'deduction' : 'non_sourcee'; phrases.push(o); return; }
      let contenu = '';
      for (const id of ids) {
        const r = T.preuve(id);
        if (!r) { o.inconnues.push(id); continue; }
        o.citations.push(id);
        const brut = Object.entries(r).filter(([k]) => k !== '_id').map(([, v]) => v).join(' ');
        contenu += ' ' + brut + ' ' + masque.texte(brut);
      }
      const c = contenu.toLowerCase();
      o.absentes = o.citations.length ? faits(p).filter(f => !c.includes(f.toLowerCase())) : [];
      o.statut = o.inconnues.length && !o.citations.length ? 'citation_invalide' : (o.inconnues.length || o.absentes.length) ? 'a_controler' : 'verifiee';
      phrases.push(o);
    });
  }
  const bilan = {}; phrases.forEach(p => { if (!['vide', 'titre'].includes(p.statut)) bilan[p.statut] = (bilan[p.statut] || 0) + 1; });
  const corresp = {}; for (const [k, v] of masque.comptes) corresp[v] = k;
  return { texte, phrases, bilan, correspondance: corresp };
};
