/* ============================================================================
   04_graphiques.js : graphiques ECharts (frise, carte, SRUM, visibilite, plausibilite)
   ============================================================================ */
'use strict';

T.COUL = { g0: '#98a2b3', g1: '#2e90fa', g2: '#f79009', g3: '#d92d20', fen: 'rgba(217,45,32,0.07)', fenBord: 'rgba(217,45,32,0.35)', vert: '#12b76a', texte: '#344054', grille: '#eaecf0' };
T._graphs = {};
T.graph = (el, option) => {
  const id = el.id || (el.id = 'g' + Math.random().toString(36).slice(2));
  if (T._graphs[id]) { try { T._graphs[id].dispose(); } catch (e) { /* deja detruit */ } }
  const g = echarts.init(el, null, { renderer: 'canvas' });
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
    tooltip: { trigger: 'item', confine: true, formatter: p => { const e = evts[p.data.value[p.seriesIndex === 1 ? 4 : 3]]; return e ? `<b>${T.esc(e.titre)}</b><br>${T.fcourt(e.t)}${e.fin ? ' → ' + T.fcourt(e.fin) : ''}${e.fen ? ' · ' + e.fen : ''}<br><span style="color:#667085">${T.esc(e.detail).slice(0, 220)}</span>` : ''; } },
    xAxis: { type: 'time', axisLabel: { hideOverlap: true, formatter: { day: '{dd}/{MM}', hour: '{HH}:{mm}', minute: '{HH}:{mm}' } }, splitLine: { show: true, lineStyle: { color: T.COUL.grille } } },
    yAxis: { type: 'category', data: voies, inverse: true, axisTick: { show: false }, axisLine: { show: false }, splitLine: { show: true, lineStyle: { color: T.COUL.grille } }, axisLabel: { color: T.COUL.texte, fontWeight: 600 } },
    dataZoom: [{ type: 'slider', xAxisIndex: 0, height: 22, bottom: 14, labelFormatter: v => T.fcourt(new Date(v)) }, { type: 'inside', xAxisIndex: 0 }],
    series: [
      { type: 'scatter', data: points, encode: { x: 0, y: 1 }, large: false, markArea: { silent: true, label: { color: '#b42318', fontWeight: 700, position: 'insideTop' }, data: zonesFenetres(fen) } },
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
  const couleur = p => p.succes ? '#f04438' : p.echecs >= 1000 ? '#f79009' : p.echecs >= 100 ? '#fdb022' : '#fedf89';
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
      return `${T.drapeau(e.pays)} <b>${e.ip}</b> ${e.ville ? '· ' + T.esc(e.ville) : ''}<br>${T.esc(e.operateur || '')}<br>${e.succes ? '✅ connexion réussie · ' : ''}${e.echecs ? T.nb(e.echecs) + ' échecs' : ''}`;
    } },
    geo: { map: 'monde', nameProperty: 'iso2', roam: true, zoom: 1.2, center: [12, 28], tooltip: { show: true },
      itemStyle: { areaColor: '#f2f4f7', borderColor: '#d0d5dd', borderWidth: 0.6 }, emphasis: { itemStyle: { areaColor: '#e4e7ec' }, label: { show: false } }, select: { disabled: true },
      regions: analyse.pays.map(p => ({ name: p.pays, itemStyle: { areaColor: couleur(p) }, emphasis: { itemStyle: { areaColor: couleur(p), opacity: 0.85 } } })) },
    series: [
      { type: 'lines', coordinateSystem: 'geo', data: lignes, zlevel: 2, effect: { show: true, period: 4, trailLength: 0.35, symbolSize: 4, color: '#b42318' }, lineStyle: { color: '#d92d20', width: 1.4, opacity: 0.55, curveness: 0.25 } },
      { type: 'effectScatter', coordinateSystem: 'geo', zlevel: 3, data: pts.filter(p => p.e.succes && !p.e.blanche), symbolSize: 11, rippleEffect: { scale: 3.5, brushType: 'stroke' }, itemStyle: { color: '#b42318' } },
      { type: 'scatter', coordinateSystem: 'geo', zlevel: 3, data: pts.filter(p => !p.e.succes || p.e.blanche), symbolSize: 6, itemStyle: { color: '#dc6803', opacity: 0.85 } },
      { type: 'scatter', coordinateSystem: 'geo', zlevel: 4, data: [{ name: 'Cabinet', value: cible }], symbol: 'pin', symbolSize: 26, itemStyle: { color: '#155eef' }, tooltip: { formatter: 'Cabinet (poste analysé)' } }
    ]
  });
};

/* ---------------------------------------------------------------- SRUM : volumes envoyes par releve */
T.graphSrum = (el, ex) => {
  const fen = T.fenetres();
  const data = ex.serie.map(p => ({ value: [+p.t, Math.round(p.envoye * 10) / 10], p, itemStyle: { color: p.fen ? (p.envoye > (ex.ref ? ex.ref.max : Infinity) ? T.COUL.g3 : T.COUL.g2) : '#84adff' } }));
  const ml = ex.ref ? [{ yAxis: ex.ref.p95, name: '95e centile', lineStyle: { color: '#f79009', type: 'dashed' }, label: { formatter: 'P95 {c} Mo', color: '#b54708' } },
    { yAxis: ex.ref.max, name: 'max', lineStyle: { color: '#d92d20', type: 'dashed' }, label: { formatter: 'max habituel {c} Mo', color: '#b42318' } }] : [];
  const g = T.graph(el, {
    grid: { left: 60, right: 30, top: 24, bottom: 70 },
    tooltip: { trigger: 'item', formatter: x => { const p = x.data.p; return `<b>${T.fcourt(p.t)}</b> ${p.fen ? '· ' + p.fen : ''}<br>Envoyé : <b>${T.nb(p.envoye, 1)} Mo</b> · reçu ${T.nb(p.recu)} Mo<br>1re appli : ${T.esc(p.app)} (${T.nb(p.appMo, 1)} Mo)`; } },
    xAxis: { type: 'time', axisLabel: { hideOverlap: true, formatter: { day: '{dd}/{MM}', hour: '{HH}:{mm}' } } },
    yAxis: { type: 'value', name: 'Mo envoyés / relevé', nameTextStyle: { align: 'left' }, splitLine: { lineStyle: { color: T.COUL.grille } } },
    dataZoom: [{ type: 'slider', height: 22, bottom: 14, labelFormatter: v => T.fcourt(new Date(v)) }, { type: 'inside' }],
    series: [{ type: 'bar', data, barMaxWidth: 10, markLine: { symbol: 'none', silent: true, data: ml }, markArea: { silent: true, label: { color: '#b42318', fontWeight: 700 }, data: zonesFenetres(fen) } }]
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
    series: [{ type: 'bar', barWidth: 14, data: val.map((v, i) => ({ value: Math.round(v), itemStyle: { color: ['#155eef', f.niveau === 'PLAUSIBLE' ? T.COUL.g3 : T.COUL.g2, '#98a2b3'][i], borderRadius: 4 } })),
      label: { show: true, position: 'right', formatter: p => (i => (i === 1 && !f.couvre) ? 'non mesuré' : (i === 2 && !f.capacite) ? 'débit inconnu' : T.nb(p.value) + ' Mo')(p.dataIndex) } }]
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
      pieces: [{ value: 1, label: 'couvert', color: '#12b76a' }, { value: 0.5, label: 'partiel', color: '#a6f4c5' }, { value: 0, label: 'non couvert', color: '#fecdca' }, { value: -1, label: 'désactivé', color: '#f04438' }, { value: -2, label: 'absent', color: '#d0d5dd' }] },
    dataZoom: [Object.assign({ type: 'slider', xAxisIndex: 0, height: 18, bottom: 36 }, cadrage()), Object.assign({ type: 'inside', xAxisIndex: 0 }, cadrage())],
    series: [{ type: 'heatmap', data, itemStyle: { borderColor: '#fff', borderWidth: 0.5 }, progressive: 0 },
      // serie vide au-dessus de la heatmap : porte les cadres des fenetres de l'attaquant
      { type: 'line', data: [], z: 10, silent: true, markArea: { silent: true, label: { color: '#b42318', fontWeight: 700, position: 'top' }, itemStyle: { color: 'rgba(217,45,32,0.10)', borderColor: '#b42318', borderWidth: 2, borderType: 'dashed' },
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
    series: [{ type: 'bar', name: 'échecs', data: jours.map(j => parJour[j]), itemStyle: { color: '#f79009', borderRadius: [3, 3, 0, 0] } }]
  });
  return true;
};
