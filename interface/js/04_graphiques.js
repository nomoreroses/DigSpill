/* ============================================================================
   04_graphiques.js : graphiques ECharts (frise, carte, SRUM, visibilite, plausibilite)
   ============================================================================ */
'use strict';

/* couleurs des graphiques : suivent le theme (sombre par defaut, clair dans Reglages) */
const PALETTES = {
  sombre: { fond: '#0b0b0c', panneau: '#111113', panneau2: '#18181b', ligne: '#222226', ligne2: '#2e2e33', fg: '#ededef', fg2: '#a9a9b1', fg3: '#8b8b94', rouge: '#ff6a5f', bleu: '#7cb0ff', orange: '#f5a524', vert: '#5bd68a', rgbRouge: '255,106,95', rgbVert: '91,214,138', rgbOrange: '245,165,36' },
  clair: { fond: '#fafaf9', panneau: '#ffffff', panneau2: '#f1f1ef', ligne: '#e5e5e2', ligne2: '#d4d4d0', fg: '#111113', fg2: '#4b4b53', fg3: '#62626b', rouge: '#c01519', bleu: '#1d56c9', orange: '#9a5700', vert: '#18733f', rgbRouge: '192,21,25', rgbVert: '24,115,63', rgbOrange: '154,87,0' }
};
T.majCouleurs = () => {
  const p = PALETTES[document.documentElement.classList.contains('clair') ? 'clair' : 'sombre'];
  T.COUL = { g0: p.fg3, g1: p.bleu, g2: p.orange, g3: p.rouge, fen: `rgba(${p.rgbRouge},0.08)`, fenBord: `rgba(${p.rgbRouge},0.45)`, vert: p.vert, texte: p.fg2, texte3: p.fg3, grille: p.ligne,
    fond: p.fond, panneau: p.panneau, panneau2: p.panneau2, ligne: p.ligne, ligne2: p.ligne2, fg: p.fg, rgbRouge: p.rgbRouge, rgbVert: p.rgbVert, rgbOrange: p.rgbOrange };
  return p;
};
const themeEcharts = () => {
  const p = T.majCouleurs(), axe = { axisLine: { lineStyle: { color: p.ligne2 } }, axisTick: { lineStyle: { color: p.ligne2 } }, axisLabel: { color: p.fg3 }, splitLine: { lineStyle: { color: p.ligne } }, nameTextStyle: { color: p.fg3 } };
  return { color: [p.bleu, p.orange, p.rouge, p.vert, p.fg3], backgroundColor: 'transparent', textStyle: { color: p.fg2, fontFamily: 'Geist, system-ui, sans-serif' },
    legend: { textStyle: { color: p.fg2 } }, tooltip: { backgroundColor: p.panneau2, borderColor: p.ligne2, textStyle: { color: p.fg } },
    categoryAxis: axe, valueAxis: axe, timeAxis: axe, logAxis: axe,
    dataZoom: { backgroundColor: 'transparent', borderColor: p.ligne2, fillerColor: `rgba(${p.rgbRouge},0.10)`, handleStyle: { color: p.panneau2, borderColor: p.fg3 }, moveHandleStyle: { color: p.ligne2 }, textStyle: { color: p.fg3 },
      dataBackground: { lineStyle: { color: p.ligne2 }, areaStyle: { color: p.ligne } }, selectedDataBackground: { lineStyle: { color: p.fg3 }, areaStyle: { color: p.ligne2 } } },
    visualMap: { textStyle: { color: p.fg2 } } };
};
T.majCouleurs();
T._graphs = {};
T.graph = (el, option) => {
  const id = el.id || (el.id = 'g' + Math.random().toString(36).slice(2));
  if (T._graphs[id]) { try { T._graphs[id].dispose(); } catch (e) { /* deja detruit */ } }
  const nomTheme = 'digspill-' + (document.documentElement.classList.contains('clair') ? 'clair' : 'sombre');
  echarts.registerTheme(nomTheme, themeEcharts());
  const g = echarts.init(el, nomTheme, { renderer: 'canvas' });
  g.setOption(Object.assign({ textStyle: { fontFamily: 'inherit' }, animationDuration: 400 }, option));
  T._graphs[id] = g;
  return g;
};
window.addEventListener('resize', () => Object.values(T._graphs).forEach(g => { try { g.resize(); } catch (e) { /* */ } }));

const zonesFenetres = (fen, axe = 'xAxis') => fen.map(w => [{ name: w.id, [axe]: +w.debut, itemStyle: { color: T.COUL.fen, borderColor: T.COUL.fenBord, borderWidth: 1, borderType: 'dashed' } }, { [axe]: +w.fin }]);

/* ---------------------------------------------------------------- frise chronologique */
T.graphFrise = (el, evts, voies, fen, onClic) => {
  const idx = Object.fromEntries(voies.map((v, i) => [v, i]));
  const points = [], plages = [];
  evts.forEach((e, i) => {
    if (!(e.voie in idx)) return;
    if (e.fin && (e.fin - e.t) > 5 * 60e3) plages.push({ value: [idx[e.voie], +e.t, +e.fin, e.g, i] });
    else points.push({ value: [+e.t, idx[e.voie], e.g, i], symbolSize: [5, 7, 10, 13][e.g], itemStyle: { color: T.COUL['g' + e.g], opacity: e.g ? 0.95 : 0.5 } });
  });
  const g = T.graph(el, {
    grid: { left: 120, right: 24, top: 18, bottom: 70 },
    tooltip: { trigger: 'item', confine: true, formatter: p => { const e = evts[p.data.value[p.seriesIndex === 1 ? 4 : 3]]; return e ? `<b>${T.esc(e.titre)}</b><br>${T.fcourt(e.t)}${e.fin ? ' → ' + T.fcourt(e.fin) : ''}${e.fen ? ' · ' + e.fen : ''}<br><span style="color:${T.COUL.texte3}">${T.esc(e.detail).slice(0, 220)}</span>` : ''; } },
    xAxis: { type: 'time', axisLabel: { hideOverlap: true, formatter: { year: '{yyyy}', month: '{dd}/{MM}', day: '{dd}/{MM}', hour: '{HH}:{mm}', minute: '{HH}:{mm}' } }, splitLine: { show: true, lineStyle: { color: T.COUL.grille } } },
    yAxis: { type: 'category', data: voies, inverse: true, axisTick: { show: false }, axisLine: { show: false }, splitLine: { show: true, lineStyle: { color: T.COUL.grille } }, axisLabel: { color: T.COUL.texte, fontWeight: 500 } },
    dataZoom: [{ type: 'slider', xAxisIndex: 0, height: 22, bottom: 14, labelFormatter: v => T.fcourt(new Date(v)) }, { type: 'inside', xAxisIndex: 0 }],
    series: [
      { type: 'scatter', data: points, encode: { x: 0, y: 1 }, large: false, markArea: { silent: true, label: { color: T.COUL.g3, fontWeight: 600, position: 'insideTop' }, data: zonesFenetres(fen) } },
      { type: 'custom', data: plages, encode: { x: [1, 2], y: 0 }, renderItem: (params, api) => {
          const y = api.value(0), a = api.coord([api.value(1), y]), b = api.coord([api.value(2), y]), h = api.size([0, 1])[1] * 0.42;
          const r = echarts.graphic.clipRectByRect({ x: a[0], y: a[1] - h / 2, width: Math.max(3, b[0] - a[0]), height: h }, { x: params.coordSys.x, y: params.coordSys.y, width: params.coordSys.width, height: params.coordSys.height });
          return r && { type: 'rect', shape: Object.assign(r, { r: 3 }), style: { fill: T.COUL['g' + api.value(3)], opacity: 0.55 } };
        } }
    ]
  });
  g.on('click', p => { const e = evts[p.data.value[p.seriesIndex === 1 ? 4 : 3]]; if (e && onClic) onClic(e); });
  return g;
};

/* ---------------------------------------------------------------- carte du monde */
T.graphCarte = (el, analyse) => {
  if (!echarts.getMap('monde')) echarts.registerMap('monde', T.MONDE.carte);
  const centres = T.MONDE.centres, noms = T.MONDE.noms, parPays = Object.fromEntries(analyse.pays.map(p => [p.pays, p]));
  const couleur = p => p.succes ? T.COUL.g3 : p.echecs >= 1000 ? T.COUL.g2 : p.echecs >= 100 ? `rgba(${T.COUL.rgbOrange},0.7)` : `rgba(${T.COUL.rgbOrange},0.45)`;
  const cible = [-1.68, 48.11];         // le cabinet (Bretagne) : point d'arrivee des connexions
  const pts = [], lignes = [];
  for (const e of analyse.ips) {
    if (e.type !== 'PUBLIQUE' || !e.pays) continue;
    const c = (e.lat !== null && e.lon !== null && e.lat !== undefined) ? [e.lon, e.lat] : centres[e.pays];
    if (!c) continue;
    pts.push({ name: e.ip, value: c, e });
    if (e.succes && !e.blanche) lignes.push({ coords: [c, cible], e });
  }
  return T.graph(el, {
    tooltip: { trigger: 'item', confine: true, formatter: p => {
      if (p.componentType === 'geo') { const d = parPays[p.name]; return `${T.drapeau(p.name)} <b>${T.esc(noms[p.name] || p.name)}</b>` + (d ? `<br>${d.ip} IP · ${d.succes} avec connexion réussie · ${T.nb(d.echecs)} échecs` : ''); }
      const e = p.data && p.data.e; if (!e) return p.name || '';
      return `${T.drapeau(e.pays)} <b>${e.ip}</b> ${e.ville ? '· ' + T.esc(e.ville) : ''}<br>${T.esc(e.operateur || '')}<br>${e.succes ? 'connexion réussie · ' : ''}${e.echecs ? T.nb(e.echecs) + ' échecs' : ''}`;
    } },
    geo: { map: 'monde', nameProperty: 'iso2', roam: true, zoom: 1.2, center: [12, 28], tooltip: { show: true },
      itemStyle: { areaColor: T.COUL.panneau2, borderColor: T.COUL.ligne2, borderWidth: 0.6 }, emphasis: { itemStyle: { areaColor: T.COUL.ligne2 }, label: { show: false } }, select: { disabled: true },
      regions: analyse.pays.map(p => ({ name: p.pays, itemStyle: { areaColor: couleur(p) }, emphasis: { itemStyle: { areaColor: couleur(p), opacity: 0.85 } } })) },
    series: [
      { type: 'lines', coordinateSystem: 'geo', data: lignes, zlevel: 2, effect: { show: true, period: 4, trailLength: 0.35, symbolSize: 4, color: T.COUL.g3 }, lineStyle: { color: T.COUL.g3, width: 1.4, opacity: 0.55, curveness: 0.25 } },
      { type: 'effectScatter', coordinateSystem: 'geo', zlevel: 3, data: pts.filter(p => p.e.succes && !p.e.blanche), symbolSize: 11, rippleEffect: { scale: 3.5, brushType: 'stroke' }, itemStyle: { color: T.COUL.g3 } },
      { type: 'scatter', coordinateSystem: 'geo', zlevel: 3, data: pts.filter(p => !p.e.succes || p.e.blanche), symbolSize: 6, itemStyle: { color: T.COUL.g2, opacity: 0.85 } },
      { type: 'scatter', coordinateSystem: 'geo', zlevel: 4, data: [{ name: 'Cabinet', value: cible }], symbol: 'pin', symbolSize: 26, itemStyle: { color: T.COUL.g1 }, tooltip: { formatter: 'Cabinet (poste analysé)' } }
    ]
  });
};

/* ---------------------------------------------------------------- SRUM : volumes envoyes par releve */
T.graphSrum = (el, ex) => {
  const fen = T.fenetres();
  const data = ex.serie.map(p => ({ value: [+p.t, Math.round(p.envoye * 10) / 10], p, itemStyle: { color: p.fen ? (p.envoye > (ex.ref ? ex.ref.max : Infinity) ? T.COUL.g3 : T.COUL.g2) : T.COUL.g1 } }));
  const ml = ex.ref ? [{ yAxis: ex.ref.p95, name: '95e centile', lineStyle: { color: T.COUL.g2, type: 'dashed' }, label: { formatter: 'P95 {c} Mo', color: T.COUL.g2 } },
    { yAxis: ex.ref.max, name: 'max', lineStyle: { color: T.COUL.g3, type: 'dashed' }, label: { formatter: 'max habituel {c} Mo', color: T.COUL.g3 } }] : [];
  const g = T.graph(el, {
    grid: { left: 60, right: 30, top: 24, bottom: 70 },
    tooltip: { trigger: 'item', formatter: x => { const p = x.data.p; return `<b>${T.fcourt(p.t)}</b> ${p.fen ? '· ' + p.fen : ''}<br>Envoyé : <b>${T.nb(p.envoye, 1)} Mo</b> · reçu ${T.nb(p.recu)} Mo<br>1re appli : ${T.esc(p.app)} (${T.nb(p.appMo, 1)} Mo)`; } },
    xAxis: { type: 'time', axisLabel: { hideOverlap: true, formatter: { day: '{dd}/{MM}', hour: '{HH}:{mm}' } } },
    yAxis: { type: 'value', name: 'Mo envoyés / relevé', nameTextStyle: { align: 'left' }, splitLine: { lineStyle: { color: T.COUL.grille } } },
    dataZoom: [{ type: 'slider', height: 22, bottom: 14, labelFormatter: v => T.fcourt(new Date(v)) }, { type: 'inside' }],
    series: [{ type: 'bar', data, barMaxWidth: 10, markLine: { symbol: 'none', silent: true, data: ml }, markArea: { silent: true, label: { color: T.COUL.g3, fontWeight: 600 }, data: zonesFenetres(fen) } }]
  });
  return g;
};

/* ---------------------------------------------------------------- plausibilite : barres comparees */
T.graphPlausibilite = (el, f, hyp) => {
  const cat = ['Base compressée', 'Envoyé (SRUM)', 'Capacité de la ligne'];
  const val = [hyp.comp || 0, f.couvre ? f.envoye : 0, f.capacite || 0];
  T.graph(el, {
    grid: { left: 130, right: 70, top: 6, bottom: 6 },
    xAxis: { type: 'value', show: false }, yAxis: { type: 'category', data: cat, inverse: true, axisTick: { show: false }, axisLine: { show: false } },
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' }, valueFormatter: v => T.nb(v) + ' Mo' },
    series: [{ type: 'bar', barWidth: 14, data: val.map((v, i) => ({ value: Math.round(v), itemStyle: { color: [T.COUL.g1, f.niveau === 'PLAUSIBLE' ? T.COUL.g3 : T.COUL.g2, T.COUL.g0][i], borderRadius: 4 } })),
      label: { show: true, position: 'right', color: T.COUL.texte, textBorderWidth: 0, fontSize: 11, formatter: p => (i => (i === 1 && !f.couvre) ? 'non mesuré' : (i === 2 && !f.capacite) ? 'débit inconnu' : T.nb(p.value) + ' Mo')(p.dataIndex) } }]
  });
};

/* ---------------------------------------------------------------- carte de visibilite */
T.graphVisibilite = (el, vis) => {
  const H = vis.grille.heures, L = vis.grille.lignes, data = [];
  L.forEach((l, y) => l.valeurs.forEach((v, x) => data.push([x, y, v])));
  const fen = T.fenetres(), idx = d => { const t = +d; let k = 0; for (let i = 0; i < H.length; i++) if (+H[i] <= t) k = i; return k; };
  // cadrage initial : la fenetre la plus preoccupante (hors liste blanche), +/- 1 jour
  const cadrage = () => {
    const ex = T.exfil().fenetres.filter(f => !f.legitime), ordre = ['PLAUSIBLE', 'PARTIELLE', 'INCONNU', 'HABITUEL', 'IMPOSSIBLE_LIGNE', 'EXCLUE_RESEAU'];
    const w = ex.sort((a, b) => ordre.indexOf(a.niveau) - ordre.indexOf(b.niveau) || b.envoye - a.envoye)[0];
    if (!w || H.length < 72) return {};
    return { startValue: Math.max(0, idx(w.debut) - 24), endValue: Math.min(H.length - 1, idx(w.fin) + 12) };
  };
  T.graph(el, {
    grid: { left: 230, right: 20, top: 26, bottom: 86 },
    tooltip: { formatter: p => `${T.esc(L[p.data[1]].source)}<br>${T.fcourt(H[p.data[0]])} : <b>${({ 1: 'couvert', 0.5: 'partiel', 0: 'non couvert', '-1': 'désactivé', '-2': 'absent' })[p.data[2]]}</b>` },
    xAxis: { type: 'category', data: H.map(d => T.fcourt(d)), axisLabel: { interval: Math.max(0, Math.floor(H.length / 14)), rotate: 0, fontSize: 10 }, splitArea: { show: false } },
    yAxis: { type: 'category', data: L.map(l => l.source), inverse: true, axisLabel: { fontSize: 11, color: T.COUL.texte } },
    visualMap: { type: 'piecewise', orient: 'horizontal', left: 'center', bottom: 4, itemGap: 14, textStyle: { fontSize: 11 },
      pieces: [{ value: 1, label: 'couvert', color: T.COUL.vert }, { value: 0.5, label: 'partiel', color: `rgba(${T.COUL.rgbVert},0.45)` }, { value: 0, label: 'non couvert', color: `rgba(${T.COUL.rgbRouge},0.35)` }, { value: -1, label: 'désactivé', color: T.COUL.g3 }, { value: -2, label: 'absent', color: T.COUL.ligne2 }] },
    dataZoom: [Object.assign({ type: 'slider', xAxisIndex: 0, height: 18, bottom: 36 }, cadrage()), Object.assign({ type: 'inside', xAxisIndex: 0 }, cadrage())],
    series: [{ type: 'heatmap', data, itemStyle: { borderColor: T.COUL.fond, borderWidth: 0.5 }, progressive: 0 },
      // serie vide au-dessus de la heatmap : porte les cadres des fenetres de l'attaquant
      { type: 'line', data: [], z: 10, silent: true, markArea: { silent: true, label: { color: T.COUL.g3, fontWeight: 600, position: 'top' }, itemStyle: { color: T.COUL.fen, borderColor: T.COUL.g3, borderWidth: 2, borderType: 'dashed' },
        data: fen.filter(w => +w.fin >= +H[0] && +w.debut <= +H[H.length - 1]).map(w => [{ name: w.id, xAxis: idx(w.debut) }, { xAxis: idx(w.fin) }]) } }]
  });
};

/* ---------------------------------------------------------------- force brute : echecs par jour */
T.graphBrute = el => {
  const parJour = {};
  for (const r of T.table('echecs_connexion_4625')) { const j = (r.Date || '').slice(0, 10); if (j) parJour[j] = (parJour[j] || 0) + 1; }
  const jours = Object.keys(parJour).sort();
  if (!jours.length) return false;
  T.graph(el, {
    grid: { left: 50, right: 16, top: 16, bottom: 28 }, tooltip: { trigger: 'axis' },
    xAxis: { type: 'category', data: jours.map(j => j.slice(8, 10) + '/' + j.slice(5, 7)), axisLabel: { fontSize: 10 } },
    yAxis: { type: 'value', splitLine: { lineStyle: { color: T.COUL.grille } } },
    series: [{ type: 'bar', name: 'échecs', data: jours.map(j => parJour[j]), itemStyle: { color: T.COUL.g2, borderRadius: [3, 3, 0, 0] } }]
  });
  return true;
};
