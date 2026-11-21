// Ouvre l'interface HTML produite par la vraie analyse, capture chaque ecran, releve les erreurs,
// et compare les donnees a la verite terrain du scenario.
// node interface.js <interface.html> <verite.json> <dossier_captures>
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');
const [html, veriteFichier, sortie] = process.argv.slice(2);
const chrome = ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(fs.existsSync);
const P = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  fs.mkdirSync(sortie, { recursive: true });
  const nav = await puppeteer.launch({ executablePath: chrome, headless: 'new', args: ['--lang=fr-FR', '--allow-file-access-from-files'] });
  const page = await nav.newPage();
  await page.setViewport({ width: 1440, height: 900 });
  const erreurs = [];
  page.on('pageerror', e => erreurs.push('erreur JS : ' + e.message));
  page.on('console', m => { if (m.type() === 'error') erreurs.push('console : ' + m.text()); });
  await page.goto('file:///' + html.replace(/\\/g, '/'), { waitUntil: 'load', timeout: 120000 });
  await P(2500);
  const ecrans = ['resume', 'chrono', 'details/grille', 'details/fenetres', 'details/chiffres', 'details/ip', 'details/exfil', 'details/memoire', 'details/visibilite',
    'details/sante', 'details/fuites', 'details/ioc', 'details/ia', 'details/evenements', 'details/synthese', 'preuves/integrite', 'preuves/rapports'];
  let n = 0;
  for (const e of ecrans) {
    await page.evaluate(x => T.aller(x), e); await P(1500);
    const info = await page.evaluate(() => ({
      titre: (document.querySelector('h1') || {}).textContent || '',
      erreurAffichage: [...document.querySelectorAll('.alerte')].map(x => x.textContent).filter(t => /Erreur d'affichage/.test(t)),
      hauteur: document.documentElement.scrollHeight
    }));
    for (const x of info.erreurAffichage) erreurs.push(`${e} : ${x}`);
    n++;
    const f = path.join(sortie, `${String(n).padStart(2, '0')}_${e.replace('/', '_')}.png`);
    await page.screenshot({ path: f, clip: { x: 0, y: 0, width: 1440, height: Math.min(info.hauteur, 2600) } });
    console.log(`ecran ${e} : « ${info.titre.trim().slice(0, 90)} », ${info.hauteur} px`);
  }
  // premiere etape de la chronologie ouverte
  await page.evaluate(() => T.aller('chrono')); await P(800);
  const ouverte = await page.evaluate(() => { const b = document.querySelector('.st'); if (b) { b.click(); return b.textContent.slice(0, 80); } return null; });
  if (ouverte) { await P(600); const h = await page.evaluate(() => document.documentElement.scrollHeight); await page.screenshot({ path: path.join(sortie, '18_chrono_etape.png'), clip: { x: 0, y: 0, width: 1440, height: Math.min(h, 2600) } }); console.log('etape ouverte : ' + ouverte); }
  // telephone
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 });
  await page.evaluate(() => T.aller('resume')); await P(800);
  await page.screenshot({ path: path.join(sortie, '19_telephone.png') });

  // verite terrain : chaque action du scenario se retrouve-t-elle dans les donnees de l'interface ?
  const brut = await page.evaluate(() => (document.getElementById('donnees') || {}).textContent || '');
  const texte = brut.replace(/\\\\/g, '\\').toLowerCase();
  const verite = JSON.parse(fs.readFileSync(veriteFichier, 'utf8').replace(/^\uFEFF/, ''));
  const resume = await page.evaluate(() => document.body.innerText);
  await page.evaluate(() => T.aller('chrono')); await P(800);
  const chrono = await page.evaluate(() => document.body.innerText);
  console.log('@@DEBUT verite');
  for (const a of [].concat(verite)) {
    const motifs = [].concat(a.Motifs || []).filter(Boolean);
    if (!motifs.length) continue;
    const r = motifs.map(m => {
      const mm = m.replace(/\\\\/g, '\\').toLowerCase();
      return `${m} : ${texte.includes(mm) ? 'donnees' : 'ABSENT des donnees'}${chrono.toLowerCase().includes(mm) ? ', chronologie' : ''}`;
    });
    console.log(`${a.Heure}  ${a.Id} | ${r.join(' | ')}`);
  }
  console.log('@@FIN verite');
  console.log('@@DEBUT resume_texte'); console.log(resume.slice(0, 6000)); console.log('@@FIN resume_texte');
  console.log('@@DEBUT chrono_texte'); console.log(chrono.slice(0, 8000)); console.log('@@FIN chrono_texte');
  console.log('@@DEBUT erreurs'); console.log(erreurs.length ? erreurs.join('\n') : 'aucune'); console.log('@@FIN erreurs');
  await nav.close();
})().catch(e => { console.error(e); process.exit(1); });
