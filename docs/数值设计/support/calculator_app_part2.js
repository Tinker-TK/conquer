/* ---------------- SVG helpers ---------------- */
function svgDonut(segments, size = 190) {
  const total = sum(segments.map(s => s.value));
  if (!total) return '<div class="empty">还没有加入内容</div>';
  const r = 68, c = 2 * Math.PI * r, cx = size / 2, cy = size / 2;
  let offset = 0;
  const arcs = segments.filter(s => s.value > 0).map(s => {
    const len = c * s.value / total;
    const el = `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${s.color}" stroke-width="18"
      stroke-dasharray="${len} ${c - len}" stroke-dashoffset="${-offset}" transform="rotate(-90 ${cx} ${cy})"
      stroke-linecap="butt"></circle>`;
    offset += len;
    return el;
  }).join('');
  return `<svg class="svg" viewBox="0 0 ${size} ${size}" role="img">
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="#0b1117" stroke-width="18"></circle>
    ${arcs}
    <text x="${cx}" y="${cy - 4}" text-anchor="middle" fill="#e8eef5" font-size="22" font-weight="800">${fmt(total, 0)}</text>
    <text x="${cx}" y="${cy + 15}" text-anchor="middle" fill="#93a4b5" font-size="10">总战力 P</text>
  </svg>`;
}
function svgBars(items, opts = {}) {
  const width = 440, rowH = 26, padL = 96, padR = 56;
  const max = Math.max(1, ...items.map(i => i.value));
  const height = Math.max(40, items.length * rowH + 16);
  const rows = items.map((it, i) => {
    const y = 10 + i * rowH;
    const w = Math.max(2, (width - padL - padR) * it.value / max);
    return `<text x="0" y="${y + 11}" fill="#b9c9d8" font-size="10.5">${esc(it.label)}</text>
      <rect x="${padL}" y="${y}" width="${width - padL - padR}" height="14" rx="5" fill="#0b1117"></rect>
      <rect x="${padL}" y="${y}" width="${w}" height="14" rx="5" fill="${it.color || '#54d6c8'}"></rect>
      <text x="${width - 2}" y="${y + 11}" text-anchor="end" fill="#93a4b5" font-size="10">${fmt(it.value, 0)}</text>`;
  }).join('');
  return `<svg class="svg" viewBox="0 0 ${width} ${height}" role="img">${rows}</svg>`;
}
function svgRadar(axes, values, size = 230) {
  const cx = size / 2, cy = size / 2 + 4, r = 78, n = axes.length;
  const pt = (i, v) => {
    const a = -Math.PI / 2 + i * 2 * Math.PI / n;
    return [cx + Math.cos(a) * r * v / 100, cy + Math.sin(a) * r * v / 100];
  };
  const grid = [25, 50, 75, 100].map(level => {
    const pts = axes.map((_, i) => pt(i, level).map(x => x.toFixed(1)).join(',')).join(' ');
    return `<polygon points="${pts}" fill="none" stroke="#2a3a4a" stroke-width="1"></polygon>`;
  }).join('');
  const spokes = axes.map((_, i) => {
    const [x, y] = pt(i, 100);
    return `<line x1="${cx}" y1="${cy}" x2="${x}" y2="${y}" stroke="#2a3a4a" stroke-width="1"></line>`;
  }).join('');
  const poly = axes.map((_, i) => pt(i, values[i]).map(x => x.toFixed(1)).join(',')).join(' ');
  const labels = axes.map((a, i) => {
    const [x, y] = pt(i, 118);
    return `<text x="${x}" y="${y + 3}" text-anchor="middle" fill="#93a4b5" font-size="10">${esc(a)}</text>`;
  }).join('');
  return `<svg class="svg" viewBox="0 0 ${size} ${size}" role="img">${grid}${spokes}
    <polygon points="${poly}" fill="rgba(84,214,200,.18)" stroke="#54d6c8" stroke-width="2"></polygon>${labels}</svg>`;
}

/* ---------------- summary ---------------- */
function renderSummary() {
  const s = buildSummary();
  const cmp = state.compare.A ? snapshotSummaryDelta(s, state.compare.A.summary) : null;
  const delta = cmp;
  const item = (label, value, sub, cls = '', d = null) => `<div class="stat ${cls}">
    <div class="label">${label}</div>
    <div class="value">${value}${d != null ? `<span class="delta ${d >= 0 ? 'up' : 'down'}">${signed(d, 0)}</span>` : ''}</div>
    <div class="sub">${sub}</div></div>`;
  $('#summary').innerHTML = [
    item('总战力', fmt(s.total, 0), `${s.cards.length} 张牌 + ${state.relics.length} 遗物 + ${state.potions.length} 药水`, 'gold', delta ? delta.total : null),
    item('卡组战力', fmt(s.deckPower, 0), `单位 ${fmt(s.unitPowerSum, 0)} / 效果 ${fmt(s.effectPower, 0)}`, 'blue', delta ? delta.deckPower : null),
    item('单位战力', fmt(s.unitPowerSum, 0), `${s.recruits.length} 张征召牌`, '', delta ? delta.unitPowerSum : null),
    item('遗物战力', fmt(s.relicPowerSum, 0), `${state.relics.length} 件`, 'purple', delta ? delta.relicPowerSum : null),
    item('药水战力', fmt(s.potionPowerSum, 0), `${state.potions.length} 瓶`, '', delta ? delta.potionPowerSum : null),
    item('每费战力', fmt(s.efficiency, 1), `平均费用 ${fmt(s.avgCost, 2)}`, 'gold', delta ? delta.efficiency : null),
  ].join('');
}
function snapshotSummaryDelta(now, old) {
  if (!old) return null;
  return {
    total: now.total - old.total, deckPower: now.deckPower - old.deckPower,
    unitPowerSum: now.unitPowerSum - old.unitPowerSum,
    relicPowerSum: now.relicPowerSum - old.relicPowerSum,
    potionPowerSum: now.potionPowerSum - old.potionPowerSum,
    efficiency: now.efficiency - old.efficiency,
  };
}
function renderFooter() {
  $('#footer').innerHTML = `模型 ${esc(DATA.meta.version)} · 士兵 = 100 P · 数据版本 ${esc(DATA.meta.date)} · 设计估价，不是实战胜率`;
}

/* ---------------- overview ---------------- */
function renderOverview() {
  const s = buildSummary(), w = warnings(s);
  const comp = [
    { label: '卡组', value: s.deckPower, color: '#54d6c8' },
    { label: '遗物', value: s.relicPowerSum, color: '#b48cff' },
    { label: '药水', value: s.potionPowerSum, color: '#e8b45a' },
  ];
  const costMap = {};
  for (const c of s.cards) {
    const cost = Math.max(0, cardView(c).cost);
    costMap[cost] = costMap[cost] || { count: 0, power: 0 };
    costMap[cost].count++;
    costMap[cost].power += cardPower(c);
  }
  const costBars = Object.keys(costMap).sort((a, b) => a - b).map(k => ({
    label: `${k} 费`, value: costMap[k].power, color: Number(k) >= 3 ? '#e8b45a' : '#54d6c8',
  }));
  const top = [...s.effects].sort((a, b) => cardPower(b) - cardPower(a)).slice(0, 8)
    .map(c => ({ label: c.name, value: cardPower(c), color: c.role === 'core' ? '#e8b45a' : '#6aa9ff' }));
  $('#view').innerHTML = `<div class="grid2">
      <div class="panel"><h2>战力构成</h2>
        <p class="hint">卡组、遗物、药水三类来源。总战力是设计估价，不是胜率。</p>
        ${'<div class="donut-wrap">'}${svgDonut(comp)}${'</div>'}
        <div class="legend">${comp.map(x => `<span><i style="background:${x.color}"></i>${x.label} ${fmt(x.value, 0)}</span>`).join('')}</div>
      </div>
      <div class="panel"><h2>六维评估</h2>
        <p class="hint">按卡牌标签与征召比例估算，用来发现“全是输出/没有资源”这类结构问题。</p>
        ${svgRadar(['输出', '生存', '资源', '控制', '成长', '稳定'], radarValues(s))}
      </div>
    </div>
    <div class="grid2">
      <div class="panel"><h2>费用曲线</h2>
        <p class="hint">每费卡组的战力分布。高费牌应明显高于低费牌，否则就是“贵而弱”。</p>
        ${costBars.length ? svgBars(costBars) : '<div class="empty">还没有卡牌</div>'}
      </div>
      <div class="panel"><h2>诊断</h2>
        <p class="hint">先看红色/橙色，再决定改什么。</p>
        <div class="warnlist">${w.map(([cls, title, body]) => `<div class="warn ${cls}"><b>${esc(title)}</b><span>${esc(body)}</span></div>`).join('')}</div>
      </div>
    </div>
    <div class="panel"><h2>卡组 Top 8</h2>
      <p class="hint">按单卡 P 排序。数值高不一定该削，先看它是否兑现条件太容易。</p>
      ${top.length ? svgBars(top) : '<div class="empty">还没有效果牌</div>'}
    </div>
    <div class="panel"><h2>A/B 对比</h2>
      <p class="hint">调参前存 A，改完存 B，再看差值是来自单位、卡牌、遗物还是药水。</p>
      ${renderCompareTable()}
    </div>`;
}
function radarValues(s) {
  const total = Math.max(1, s.deckPower);
  const share = (tag) => {
    const p = sum(s.cards.filter(c => (c.tags || []).includes(tag)).map(cardPower));
    return clamp(p / total * 100 * 2.2, 0, 100);
  };
  return [
    share('输出'), share('增益'), share('资源'), share('控制'),
    clamp(state.relics.length * 9 + s.cards.filter(c => c.max_upgrade > 0).length * 1.5, 0, 100),
    clamp(s.recruitRatio * 150, 0, 100),
  ];
}
function renderCompareTable() {
  const A = state.compare.A, B = state.compare.B;
  if (!A && !B) return '<div class="empty">还没有快照。点顶部“存为 A”，改构筑后再“存为 B”。</div>';
  const rows = [
    ['总战力', A ? A.summary.total : null, B ? B.summary.total : null, 'total'],
    ['卡组', A ? A.summary.deckPower : null, B ? B.summary.deckPower : null, 'deckPower'],
    ['单位', A ? A.summary.unitPowerSum : null, B ? B.summary.unitPowerSum : null, 'unitPowerSum'],
    ['效果牌', A ? A.summary.effectPower : null, B ? B.summary.effectPower : null, 'effectPower'],
    ['遗物', A ? A.summary.relicPowerSum : null, B ? B.summary.relicPowerSum : null, 'relicPowerSum'],
    ['药水', A ? A.summary.potionPowerSum : null, B ? B.summary.potionPowerSum : null, 'potionPowerSum'],
    ['每费战力', A ? A.summary.efficiency : null, B ? B.summary.efficiency : null, 'efficiency'],
    ['卡牌数', A ? A.summary.cards.length : null, B ? B.summary.cards.length : null, 'count'],
    ['平均费用', A ? A.summary.avgCost : null, B ? B.summary.avgCost : null, 'avgCost'],
  ];
  return `<div class="tablewrap" style="max-height:none"><table style="min-width:520px">
    <thead><tr><th>指标</th><th class="num">A</th><th class="num">B</th><th class="num">B − A</th></tr></thead>
    <tbody>${rows.map(([label, a, b, key]) => {
      const d = a != null && b != null ? b - a : null;
      const digits = key === 'efficiency' || key === 'avgCost' ? 2 : 0;
      return `<tr><td class="name">${label}</td><td class="num">${a == null ? '—' : fmt(a, digits)}</td>
        <td class="num">${b == null ? '—' : fmt(b, digits)}</td>
        <td class="num" style="color:${d == null ? '#93a4b5' : d >= 0 ? '#6ed49a' : '#f16a6a'}">${d == null ? '—' : signed(d, digits)}</td></tr>`;
    }).join('')}</tbody></table></div>
    <div class="toolbar" style="margin-top:10px"><button class="btn small" onclick="clearCompare()">清空对比</button>
      <span class="tip">A / B 只保存快照，不覆盖当前构筑。</span></div>`;
}

/* ---------------- units table ---------------- */
function renderUnits() {
  const search = state.search.toLowerCase(), faction = state.filter.units, sort = state.sort.units;
  let list = DATA.units.filter(u => {
    if (faction !== 'all' && u.team !== faction) return false;
    if (search && !(u.name + ' ' + (u.role || '') + ' ' + (u.tier || '')).toLowerCase().includes(search)) return false;
    return true;
  }).map(u => {
    const v = unitView(u);
    return { u, v, sim: simulateUnit(v, 0), target: unitTargetPower(u) };
  });
  list.sort((a, b) => {
    if (sort === 'name') return a.u.name.localeCompare(b.u.name);
    if (sort === 'cost') return a.v.cost - b.v.cost || b.sim.power - a.sim.power;
    if (sort === 'perCost') return (b.sim.power / Math.max(1, b.v.cost)) - (a.sim.power / Math.max(1, a.v.cost));
    return b.sim.power - a.sim.power;
  });
  const rows = list.map(({ u, v, sim, target }) => {
    const status = target == null ? '' : (() => {
      const p = target ? (sim.power - target) / target : 0;
      if (Math.abs(p) <= 0.1) return `<span class="pill good">达标</span>`;
      if (p > 0.15) return `<span class="pill warn">+${(p * 100).toFixed(0)}%</span>`;
      if (p < -0.15) return `<span class="pill bad">${(p * 100).toFixed(0)}%</span>`;
      return `<span class="pill">接近</span>`;
    })();
    return `<tr data-unit="${esc(u.id)}">
      <td class="name">${esc(u.name)}</td>
      <td>${u.team === 'ally' ? '<span class="pill good">己方</span>' : `<span class="pill">${esc(u.tier || '敌方')}</span>`}</td>
      <td class="num">${v.hp}</td><td class="num">${v.attack}</td><td class="num">${v.defence}</td>
      <td class="num">${v.cost}</td><td class="num"><b>${fmt(sim.power, 1)}</b></td>
      <td class="num">${fmt(sim.power / Math.max(1, v.cost), 1)}</td>
      <td class="num">${target == null ? '—' : fmt(target, 1)}</td><td>${status}</td>
      <td>${u.team === 'ally' ? `<button class="btn small" data-add-unit="${esc(u.id)}">加入</button>` : ''}</td></tr>`;
  }).join('');
  $('#view').innerHTML = `<div class="panel"><h2>单位战力</h2>
    <p class="hint">点击行查看技能与公式；己方单位可加入卡组。P = 100 × √(有效生命/150 × 等效输出/4.0)。</p>
    <div class="toolbar"><input id="uSearch" placeholder="搜索单位 / 定位 / 威胁级" value="${esc(state.search)}">
      <select id="uFaction"><option value="all" ${faction === 'all' ? 'selected' : ''}>全部阵营</option>
        <option value="ally" ${faction === 'ally' ? 'selected' : ''}>己方</option>
        <option value="enemy" ${faction === 'enemy' ? 'selected' : ''}>敌方</option></select>
      <select id="uSort"><option value="power" ${sort === 'power' ? 'selected' : ''}>按战力</option>
        <option value="perCost" ${sort === 'perCost' ? 'selected' : ''}>按每费战力</option>
        <option value="cost" ${sort === 'cost' ? 'selected' : ''}>按费用</option>
        <option value="name" ${sort === 'name' ? 'selected' : ''}>按名称</option></select>
      <button class="btn small" id="applyTargetUnits">套用目标三围</button>
      <button class="btn small" id="resetUnitEdits">恢复当前</button>
      <span class="tip">共 ${list.length} 个单位</span></div>
    <div class="tablewrap"><table><thead><tr><th>单位</th><th>阵营</th><th class="num">生命</th><th class="num">攻击</th>
      <th class="num">防御</th><th class="num">费</th><th class="num">P</th><th class="num">P/费</th>
      <th class="num">目标 P</th><th>状态</th><th></th></tr></thead>
      <tbody>${rows || '<tr><td colspan="11" class="empty">没有匹配的单位</td></tr>'}</tbody></table></div></div>`;
  $('#uSearch').oninput = (e) => { state.search = e.target.value; renderUnits(); };
  $('#uFaction').onchange = (e) => { state.filter.units = e.target.value; renderUnits(); };
  $('#uSort').onchange = (e) => { state.sort.units = e.target.value; renderUnits(); };
  $('#applyTargetUnits').onclick = applyTargetUnits;
  $('#resetUnitEdits').onclick = resetUnitEdits;
  $$('[data-unit]').forEach(tr => tr.onclick = () => openUnit(tr.dataset.unit));
  $$('[data-add-unit]').forEach(b => b.onclick = (e) => { e.stopPropagation(); addUnit(b.dataset.addUnit); });
}
