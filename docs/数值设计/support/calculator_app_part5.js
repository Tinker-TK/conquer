/* ---------------- drawer ---------------- */
function openDrawer(title, sub, html, after) {
  $('#drawerTitle').textContent = title;
  $('#drawerSub').textContent = sub;
  $('#drawerBody').innerHTML = html;
  $('#drawer').classList.add('open');
  if (after) after();
}
function closeDrawer() { $('#drawer').classList.remove('open'); }

function openUnit(id) {
  const u = UNIT_BY_ID[id];
  if (!u) return;
  const v = unitView(u);
  const sim = simulateUnit(v, 0);
  const trainedP = trainedPower(u);
  const target = unitTargetPower(u);
  const skillRows = (u.skills || []).map(s => `<div class="skillrow">
    <div><b>${esc(s.name)}</b><div class="sub">${esc(s.kind)} · ${esc((s.unlock || []).join(','))}</div></div>
    <div class="num">${fmt(s.rate, 2)}×</div>
    <div class="num">${fmt(s.cooldown, 1)}s</div>
    <div class="num">${fmt(s.range, 0)}</div>
  </div>`).join('');
  const html = `<div class="field"><label>生命</label><input type="number" data-unit-field="hp" value="${v.hp}" min="1"></div>
    <div class="field"><label>攻击</label><input type="number" data-unit-field="attack" value="${v.attack}" min="0"></div>
    <div class="field"><label>防御</label><input type="number" data-unit-field="defence" value="${v.defence}" min="0"></div>
    <div class="field"><label>费用</label><input type="number" data-unit-field="cost" value="${v.cost}" min="0" max="10"></div>
    <div class="field"><label>闪避</label><input type="number" data-unit-field="dodge" value="${v.dodge}" step="0.05" min="0" max="1"></div>
    <div class="hr"></div>
    <div class="kv"><span>当前战力</span><span>${fmt(sim.power, 1)} P</span></div>
    <div class="kv"><span>每费战力</span><span>${fmt(sim.power / Math.max(1, v.cost), 1)}</span></div>
    ${target != null ? `<div class="kv"><span>目标战力</span><span>${fmt(target, 1)} P（${signed(sim.power - target, 1)}）</span></div>` : ''}
    <div class="kv"><span>有效生命</span><span>${fmt(sim.ehp, 1)}</span></div>
    <div class="kv"><span>DPS / HPS</span><span>${fmt(sim.dps, 2)} / ${fmt(sim.hps, 2)}</span></div>
    <div class="kv"><span>等效输出</span><span>${fmt(sim.output, 2)}</span></div>
    <div class="kv"><span>训练后战力</span><span>${fmt(trainedP, 1)} P（${signed(trainedP - sim.power, 1)}）</span></div>
    <div class="hr"></div>
    <h3>技能</h3>
    <div class="skillrow" style="color:#93a4b5"><div>技能</div><div class="num">倍率</div><div class="num">冷却</div><div class="num">射程</div></div>
    ${skillRows || '<div class="empty">没有配置技能</div>'}
    <div class="hr"></div>
    <h3>计算分解</h3>
    <div class="formula">有效生命 = ${v.hp} × 15 / max(15 − ${v.defence}, 1) / (1 − ${fmt(v.dodge, 2)} × 0.7) = ${fmt(sim.ehp, 1)}
DPS = 伤害 / ${fmt(state.model.window, 0)}s × 在线率 = ${fmt(sim.dps, 2)}
等效输出 = ${fmt(sim.dps, 2)} + ${fmt(state.model.heal_weight, 2)} × ${fmt(sim.hps, 2)} = ${fmt(sim.output, 2)}
本体战力 = 100 × √(${fmt(sim.ehp, 1)}/150 × ${fmt(sim.output, 2)}/4.0) = ${fmt(sim.bodyPower, 1)} P
总战力 = 本体 ${fmt(sim.bodyPower, 1)} + 召唤 ${fmt(sim.summonBonus, 1)} = ${fmt(sim.power, 1)} P</div>
    <div class="toolbar" style="margin-top:12px">
      ${u.team === 'ally' ? `<button class="btn gold" id="drawerAddUnit">加入卡组</button>` : ''}
      <button class="btn small" id="drawerResetUnit">重置本单位</button>
    </div>`;
  openDrawer(u.name, `${u.team === 'ally' ? '己方' : '敌方'} · ${u.role || ''} ${u.tier || ''}`, html, () => {
    $$('[data-unit-field]').forEach(inp => inp.onchange = () => {
      const f = inp.dataset.unitField;
      state.edits.units[id] = state.edits.units[id] || {};
      state.edits.units[id][f] = Number(inp.value);
      save(); render(); openUnit(id);
    });
    if ($('#drawerAddUnit')) $('#drawerAddUnit').onclick = () => addUnit(id);
    $('#drawerResetUnit').onclick = () => {
      delete state.edits.units[id]; save(); render(); openUnit(id);
    };
  });
}

function openCard(id) {
  const c = CARD_BY_ID[id];
  if (!c) return;
  const v = cardView(c);
  const st = cardStats(v);
  const effects = (v.effects || []).map((e, i) => `<div class="skillrow" style="grid-template-columns:1.4fr .6fr .6fr .6fr">
    <div><b>${esc(kindCn(e.kind || 0))}</b><div class="sub">${esc(kindName(e.kind || 0))}</div></div>
    <div><input type="number" step="0.1" style="width:100%" data-eff="${i}" data-eff-field="amount" value="${e.amount == null ? 0 : e.amount}"></div>
    <div class="num">+${fmt(e.upgrade_amount || 0, 1)}</div>
    <div class="num">${e.status_seconds ? fmt(e.status_seconds, 1) + 's' : e.lasting_rounds ? fmt(e.lasting_rounds, 0) + '轮' : ''}</div>
  </div>`).join('');
  const html = `<div class="field"><label>费用</label><input type="number" data-card-cost="1" value="${v.cost}" min="0" max="10"></div>
    <div class="field"><label>稀有度</label><div>${rarityPill(c.rarity)} <span class="sub">${c.rarity === 'rare' ? '商店 90–120' : '商店 55–80'}</span></div></div>
    <div class="field"><label>类型</label><div>${c.category === 'recruit' ? '征召牌' : '效果/能力牌'} · ${esc(ROLE_CN[c.role] || '')}</div></div>
    <div class="hr"></div>
    <h3>基础说明</h3><p style="font-size:12.5px">${esc(c.desc || '（待补文案）')}</p>
    <h3>强化后</h3><p style="font-size:12.5px">${esc(c.upgrade_desc || '（待补文案）')}</p>
    <div class="kv"><span>强化方式</span><span>${esc(c.upgrade_note || '—')}</span></div>
    <div class="hr"></div>
    <div class="kv"><span>基础 P</span><span>${fmt(st.power, 1)}</span></div>
    <div class="kv"><span>强化 P</span><span>${fmt(st.upgradePower, 1)}（${signed(st.upgradeDelta, 1)}）</span></div>
    <div class="kv"><span>费用预算</span><span>${fmt(st.budget, 1)} P</span></div>
    <div class="kv"><span>效率</span><span>${st.ratio == null ? '—' : st.ratio.toFixed(2)}${st.targetCost != null && st.targetCost !== st.cost && st.targetRatio != null ? ` → 建议 ${st.targetRatio.toFixed(2)}` : ''}</span></div>
    <div class="kv"><span>每费战力</span><span>${st.perCost == null ? '—' : fmt(st.perCost, 1)}</span></div>
    ${st.upgradedCost !== st.cost ? `<div class="kv"><span>强化后费用</span><span>${st.upgradedCost}（效率 ${st.upgradedRatio == null ? '—' : st.upgradedRatio.toFixed(2)}）</span></div>` : ''}
    <div class="hr"></div>
    <h3>效果明细</h3>
    ${effects || '<div class="empty">征召牌不在这里改效果；到单位页调整。</div>'}
    <div class="formula">卡牌 P = Σ 效果价值
效果价值 = 数值 × 系数（可在“校准”页改）</div>
    <div class="toolbar" style="margin-top:12px">
      <button class="btn gold" id="drawerAddCard">加入卡组</button>
      <button class="btn small" id="drawerResetCard">重置本牌</button>
    </div>`;
  openDrawer(c.name, `${cardType(c)} · ${c.cost} 费 · ${fmt(st.power, 0)} P`, html, () => {
    $('[data-card-cost]').onchange = (e) => {
      state.edits.cards[id] = state.edits.cards[id] || {};
      state.edits.cards[id].cost = Number(e.target.value);
      save(); render(); openCard(id);
    };
    $$('[data-eff]').forEach(inp => inp.onchange = () => {
      const idx = Number(inp.dataset.eff);
      const field = inp.dataset.effField;
      const effects = JSON.parse(JSON.stringify(c.effects || []));
      effects[idx][field] = Number(inp.value);
      state.edits.cards[id] = state.edits.cards[id] || {};
      state.edits.cards[id].effects = effects;
      save(); render(); openCard(id);
    });
    $('#drawerAddCard').onclick = () => addCard(id);
    $('#drawerResetCard').onclick = () => { delete state.edits.cards[id]; save(); render(); openCard(id); };
  });
}

function openRelic(id) {
  const r = RELIC_BY_ID[id];
  if (!r) return;
  const html = `<div class="kv"><span>稀有度</span><span>${RARITY_CN[r.rarity]}</span></div>
    <div class="kv"><span>触发</span><span>${esc(r.trigger)}</span></div>
    <div class="kv"><span>流派</span><span>${esc(r.section)}</span></div>
    <div class="kv"><span>价格</span><span>${r.price || '不出售'}</span></div>
    <div class="hr"></div>
    <h3>效果</h3><p style="font-size:12.5px">${esc(r.effect)}</p>
    <div class="field"><label>P 覆盖</label><input type="number" data-relic-power value="${fmt(relicPower(r), 0)}" min="0"></div>
    <div class="formula">遗物 P = 每场触发次数 × 单次价值 × 兑现率
当前是设计估价；覆盖值会写进本地方案，不改游戏。</div>
    <div class="toolbar" style="margin-top:12px">
      <button class="btn gold" id="drawerAddRelic">加入构筑</button>
      <button class="btn small" id="drawerResetRelic">重置</button>
    </div>`;
  openDrawer(r.name, `${RARITY_CN[r.rarity]} · ${r.section} · ${fmt(relicPower(r), 0)} P`, html, () => {
    $('[data-relic-power]').onchange = (e) => {
      state.edits.relics[id] = state.edits.relics[id] || {};
      state.edits.relics[id].power = Number(e.target.value);
      save(); render(); openRelic(id);
    };
    $('#drawerAddRelic').onclick = () => addRelic(id);
    $('#drawerResetRelic').onclick = () => { delete state.edits.relics[id]; save(); render(); openRelic(id); };
  });
}

function openPotion(id) {
  const p = POTION_BY_ID[id];
  if (!p) return;
  const html = `<div class="kv"><span>稀有度</span><span>${RARITY_CN[p.rarity]}</span></div>
    <div class="kv"><span>价格</span><span>${p.price}</span></div>
    <div class="kv"><span>起始幕</span><span>第 ${p.min_act} 幕</span></div>
    <div class="kv"><span>目标</span><span>${esc(p.target)}</span></div>
    <div class="hr"></div>
    <h3>效果</h3><p style="font-size:12.5px">${esc(p.effect)}</p>
    <div class="field"><label>P 覆盖</label><input type="number" data-potion-power value="${fmt(potionPower(p), 0)}" min="0"></div>
    <div class="formula">药水 P = 命中次数 × 每次伤害 × 目标数 × 1.2 + 功能价值
当前是设计估价；覆盖值会写进本地方案，不改游戏。</div>
    <div class="toolbar" style="margin-top:12px">
      <button class="btn gold" id="drawerAddPotion">加入药水带</button>
      <button class="btn small" id="drawerResetPotion">重置</button>
    </div>`;
  openDrawer(p.name, `${RARITY_CN[p.rarity]} · ${p.target} · ${fmt(potionPower(p), 0)} P`, html, () => {
    $('[data-potion-power]').onchange = (e) => {
      state.edits.potions[id] = state.edits.potions[id] || {};
      state.edits.potions[id].power = Number(e.target.value);
      save(); render(); openPotion(id);
    };
    $('#drawerAddPotion').onclick = () => addPotion(id);
    $('#drawerResetPotion').onclick = () => { delete state.edits.potions[id]; save(); render(); openPotion(id); };
  });
}

/* ---------------- export / import / compare ---------------- */
function exportState() {
  const payload = {
    app: 'ballsprite-power-calculator', version: DATA.meta.version,
    exportedAt: new Date().toISOString(),
    deck: state.deck, relics: state.relics, potions: state.potions,
    edits: state.edits, model: state.model, compare: state.compare,
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'ballsprite-战力方案.json';
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  toast('已导出方案 JSON');
}

function importState(file) {
  const reader = new FileReader();
  reader.onload = () => {
    try {
      const s = JSON.parse(reader.result);
      if (!s || s.app !== 'ballsprite-power-calculator') throw new Error('不是本计算器的方案文件');
      state.deck = Array.isArray(s.deck) ? s.deck : state.deck;
      state.relics = Array.isArray(s.relics) ? s.relics : state.relics;
      state.potions = Array.isArray(s.potions) ? s.potions : state.potions;
      state.edits = s.edits || state.edits;
      if (s.model) {
        for (const k of MODEL_KEYS) if (Number.isFinite(s.model[k])) state.model[k] = s.model[k];
        if (s.model.cardCoef) Object.assign(state.model.cardCoef, s.model.cardCoef);
      }
      if (s.compare) state.compare = s.compare;
      save(); render(); toast('方案已导入');
    } catch (e) { toast('导入失败：' + e.message); }
  };
  reader.readAsText(file);
}

function setCompare(which) {
  state.compare[which] = snapshot();
  save(); render();
  toast(`已存为 ${which}`);
}
function clearCompare() {
  state.compare = { A: null, B: null };
  save(); render();
  toast('已清空对比');
}
window.setCompare = setCompare;
window.clearCompare = clearCompare;

/* ---------------- toast / tabs / init ---------------- */
let toastTimer = null;
function toast(msg) {
  const el = $('#toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), 2200);
}

function render() {
  renderSummary();
  renderFooter();
  $$('#tabs .tab').forEach(b => b.classList.toggle('active', b.dataset.tab === state.tab));
  if (state.tab === 'overview') renderOverview();
  else if (state.tab === 'units') renderUnits();
  else if (state.tab === 'cards') renderCards();
  else if (state.tab === 'relics') renderRelics();
  else if (state.tab === 'potions') renderPotions();
  else if (state.tab === 'build') renderBuild();
  else if (state.tab === 'calibration') renderCalibration();
}

function init() {
  load();
  const hashRaw = (location.hash || '').replace('#', '');
  const hashParts = hashRaw.split('/');
  const hashTab = hashParts[0];
  if (['overview', 'units', 'cards', 'relics', 'potions', 'build', 'calibration'].includes(hashTab)) state.tab = hashTab;
  $('#btnPreset').onclick = () => {
    state.deck = starterDeck(); state.relics = []; state.potions = [];
    save(); render(); toast('已恢复起始牌组（不含遗物/药水）');
  };
  $('#btnCompareA').onclick = () => setCompare('A');
  $('#btnCompareB').onclick = () => setCompare('B');
  $('#btnExport').onclick = exportState;
  $('#btnImport').onclick = () => $('#fileImport').click();
  $('#btnReset').onclick = () => {
    if (!confirm('清空当前构筑、手动修改和 A/B 快照？')) return;
    state = {
      tab: 'overview', deck: starterDeck(), relics: [], potions: [],
      edits: { units: {}, cards: {}, relics: {}, potions: {} },
      model: JSON.parse(JSON.stringify(DATA.model)),
      compare: { A: null, B: null }, search: '',
      filter: { units: 'all', cards: 'all', relics: 'all', potions: 'all', cost: 'all', act: 'all' },
      sort: { units: 'power', cards: 'power', relics: 'power', potions: 'power' },
      showTarget: true,
    };
    try { localStorage.removeItem(STORAGE_KEY); } catch (e) { /* ignore */ }
    render(); toast('已重置');
  };
  $('#fileImport').onchange = (e) => { const f = e.target.files[0]; if (f) importState(f); e.target.value = ''; };
  $$('#tabs .tab').forEach(b => b.onclick = () => { state.tab = b.dataset.tab; state.search = ''; location.hash = state.tab; render(); });
  $('#drawerClose').onclick = closeDrawer;
  window.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeDrawer(); });
  window.onerror = (msg) => {
    document.title = 'ERROR · ' + msg;
    toast('计算器出错：' + msg);
  };
  render();
  if (hashParts.length > 1 && hashParts[1]) {
    const kind = hashParts[0], id = hashParts[1];
    setTimeout(() => {
      if (kind === 'unit') openUnit(id);
      else if (kind === 'card') openCard(id);
      else if (kind === 'relic') openRelic(id);
      else if (kind === 'potion') openPotion(id);
    }, 0);
  }
}

init();
