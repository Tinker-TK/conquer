/* ---------------- deck / build actions ---------------- */
function addCard(id, count = 1) {
  if (!CARD_BY_ID[id]) return;
  const found = state.deck.find(d => d.id === id);
  if (found) found.count += count;
  else state.deck.push({ id, count });
  save(); render(); toast(`已加入 ${CARD_BY_ID[id].name}`);
}
function addUnit(id) { if (UNIT_BY_ID[id]) addCard('unit_' + id); }
function removeCard(id) { state.deck = state.deck.filter(d => d.id !== id); save(); render(); }
function setCount(id, count) {
  const n = Math.max(0, Math.min(99, Math.floor(Number(count) || 0)));
  const found = state.deck.find(d => d.id === id);
  if (!found) return;
  if (n <= 0) removeCard(id);
  else { found.count = n; save(); render(); }
}
function addRelic(id) {
  if (!RELIC_BY_ID[id]) return;
  if (state.relics.includes(id)) { toast('同一件遗物不能重复携带'); return; }
  state.relics.push(id); save(); render(); toast(`已加入 ${RELIC_BY_ID[id].name}`);
}
function removeRelic(id) { state.relics = state.relics.filter(x => x !== id); save(); render(); }
function addPotion(id) {
  if (!POTION_BY_ID[id]) return;
  if (state.potions.length >= 3) { toast('药水带 3 格已满；先移除一瓶。'); return; }
  state.potions.push(id); save(); render(); toast(`已加入 ${POTION_BY_ID[id].name}`);
}
function removePotion(index) { state.potions.splice(index, 1); save(); render(); }

function applyTargetUnits() {
  for (const u of DATA.units) {
    if (u.team === 'ally' && u.target) {
      state.edits.units[u.id] = {
        hp: u.target.hp, attack: u.target.attack, defence: u.target.defence, cost: u.target.cost,
      };
    }
  }
  save(); render(); toast('已套用 11 个己方单位的目标三围');
}
function resetUnitEdits() {
  state.edits.units = {};
  save(); render(); toast('已恢复当前单位三围');
}
function applyTargetCosts() {
  for (const c of DATA.cards) {
    if (c.target_cost != null && c.target_cost !== c.cost) {
      state.edits.cards[c.id] = { ...(state.edits.cards[c.id] || {}), cost: c.target_cost };
    }
  }
  save(); render(); toast('已套用建议费用（16 张）');
}
function resetCardEdits() {
  state.edits.cards = {};
  save(); render(); toast('已恢复当前卡牌费用/效果');
}

function renderBuild() {
  const s = buildSummary(), entries = deckEntries();
  const recruitRows = entries.filter(e => e.card.category === 'recruit');
  const effectRows = entries.filter(e => e.card.category === 'effect');
  const deckRow = (e) => {
    const c = cardView(e.card), st = cardStats(c);
    return `<div class="deckrow"><div class="grow"><div class="nm">${esc(c.name)}</div>
      <div class="meta">${c.category === 'recruit' ? '征召' : (ROLE_CN[c.role] || '效果')} · ${c.cost} 费 · ${fmt(st.power, 0)} P</div></div>
      <div class="count"><button data-dec="${esc(c.id)}">−</button>
        <input value="${e.count}" data-count="${esc(c.id)}"><button data-inc="${esc(c.id)}">+</button></div>
      <button class="btn small danger" data-remove="${esc(c.id)}">移除</button></div>`;
  };
  const relics = state.relics.map(id => RELIC_BY_ID[id]).filter(Boolean);
  const potionRows = state.potions.map((id, i) => {
    const p = POTION_BY_ID[id];
    return p ? `<div class="deckrow"><div class="grow"><div class="nm">${esc(p.name)}</div>
      <div class="meta">${RARITY_CN[p.rarity]} · ${fmt(potionPower(p), 0)} P</div></div>
      <button class="btn small danger" data-remove-potion="${i}">移除</button></div>` : '';
  }).join('');
  const w = warnings(s);
  $('#view').innerHTML = `<div class="grid2">
    <div class="panel"><h2>卡组构筑</h2>
      <p class="hint">当前 ${s.cards.length} 张，平均 ${fmt(s.avgCost, 2)} 费，每费 ${fmt(s.efficiency, 1)} P。</p>
      <div class="toolbar"><select id="quickCard" style="min-width:220px"><option value="">选择卡牌加入…</option>
        ${DATA.cards.map(c => `<option value="${esc(c.id)}">${esc(c.name)} · ${c.cost}费 · ${fmt(cardPower(c), 0)}P</option>`).join('')}</select>
        <button class="btn small" id="quickCardAdd">加入</button>
        <button class="btn small" id="starterBtn">起始牌组</button>
        <button class="btn small danger" id="clearDeck">清空卡组</button></div>
      <h3>征召牌（${recruitRows.length} 种 / ${sum(recruitRows.map(x => x.count))} 张）</h3>
      ${recruitRows.length ? recruitRows.map(deckRow).join('') : '<div class="empty">没有征召牌</div>'}
      <h3>效果/能力牌（${effectRows.length} 种 / ${sum(effectRows.map(x => x.count))} 张）</h3>
      ${effectRows.length ? effectRows.map(deckRow).join('') : '<div class="empty">没有效果牌</div>'}
    </div>
    <div class="panel"><h2>遗物与药水</h2>
      <p class="hint">遗物不重复；药水 3 格。</p>
      <h3>遗物（${relics.length} 件 · ${fmt(s.relicPowerSum, 0)} P）</h3>
      <div class="toolbar"><select id="quickRelic" style="min-width:220px"><option value="">选择遗物加入…</option>
        ${DATA.relics.map(r => `<option value="${esc(r.id)}">${esc(r.name)} · ${RARITY_CN[r.rarity]} · ${fmt(relicPower(r), 0)}P</option>`).join('')}</select>
        <button class="btn small" id="quickRelicAdd">加入</button></div>
      ${relics.length ? relics.map(r => `<div class="deckrow"><div class="grow"><div class="nm">${esc(r.name)}</div>
        <div class="meta">${RARITY_CN[r.rarity]} · ${esc(r.section)} · ${fmt(relicPower(r), 0)} P</div></div>
        <button class="btn small danger" data-remove-relic="${esc(r.id)}">移除</button></div>`).join('') : '<div class="empty">还没有遗物</div>'}
      <h3>药水带（${state.potions.length}/3 · ${fmt(s.potionPowerSum, 0)} P）</h3>
      <div class="belt">${[0,1,2].map(i => {
        const id = state.potions[i], p = id ? POTION_BY_ID[id] : null;
        return p ? `<div class="slot filled"><div><b>${esc(p.name)}</b><br><span class="sub">${fmt(potionPower(p), 0)} P</span></div></div>`
          : `<div class="slot">空<br><span class="sub">第 ${i + 1} 格</span></div>`;
      }).join('')}</div>
      <div class="toolbar" style="margin-top:10px"><select id="quickPotion" style="min-width:220px"><option value="">选择药水加入…</option>
        ${DATA.potions.map(p => `<option value="${esc(p.id)}">${esc(p.name)} · ${RARITY_CN[p.rarity]} · ${fmt(potionPower(p), 0)}P</option>`).join('')}</select>
        <button class="btn small" id="quickPotionAdd">加入</button></div>
      ${potionRows || '<div class="empty">还没有药水</div>'}
      <div class="hr"></div><h3>诊断</h3>
      <div class="warnlist">${w.map(([cls, title, body]) => `<div class="warn ${cls}"><b>${esc(title)}</b><span>${esc(body)}</span></div>`).join('')}</div>
    </div>
  </div>
  <div class="panel"><h2>构筑总览</h2>
    <div class="grid3">
      <div><div class="kv"><span>卡组战力</span><span>${fmt(s.deckPower, 0)} P</span></div>
        <div class="kv"><span>单位战力</span><span>${fmt(s.unitPowerSum, 0)} P</span></div>
        <div class="kv"><span>效果牌战力</span><span>${fmt(s.effectPower, 0)} P</span></div></div>
      <div><div class="kv"><span>遗物战力</span><span>${fmt(s.relicPowerSum, 0)} P</span></div>
        <div class="kv"><span>药水战力</span><span>${fmt(s.potionPowerSum, 0)} P</span></div>
        <div class="kv"><span>总战力</span><span>${fmt(s.total, 0)} P</span></div></div>
      <div><div class="kv"><span>平均费用</span><span>${fmt(s.avgCost, 2)}</span></div>
        <div class="kv"><span>每费战力</span><span>${fmt(s.efficiency, 1)}</span></div>
        <div class="kv"><span>征召比例</span><span>${(s.recruitRatio * 100).toFixed(0)}%</span></div></div>
    </div>
    <div class="toolbar" style="margin-top:12px"><button class="btn" onclick="setCompare('A')">存为 A</button>
      <button class="btn" onclick="setCompare('B')">存为 B</button>
      <button class="btn small" onclick="clearCompare()">清空对比</button>
      <span class="tip">A/B 快照只存在浏览器本地，不会改游戏。</span></div>
    ${renderCompareTable()}</div>`;
  $('#quickCardAdd').onclick = () => { const v = $('#quickCard').value; if (v) addCard(v); };
  $('#quickRelicAdd').onclick = () => { const v = $('#quickRelic').value; if (v) addRelic(v); };
  $('#quickPotionAdd').onclick = () => { const v = $('#quickPotion').value; if (v) addPotion(v); };
  $('#starterBtn').onclick = () => { state.deck = starterDeck(); save(); render(); toast('已恢复起始牌组'); };
  $('#clearDeck').onclick = () => { state.deck = []; save(); render(); };
  $$('[data-dec]').forEach(b => b.onclick = () => { const id = b.dataset.dec; const e = state.deck.find(d => d.id === id); if (e) setCount(id, e.count - 1); });
  $$('[data-inc]').forEach(b => b.onclick = () => { const id = b.dataset.inc; const e = state.deck.find(d => d.id === id); if (e) setCount(id, e.count + 1); });
  $$('[data-count]').forEach(inp => inp.onchange = () => setCount(inp.dataset.count, inp.value));
  $$('[data-remove]').forEach(b => b.onclick = () => removeCard(b.dataset.remove));
  $$('[data-remove-relic]').forEach(b => b.onclick = () => removeRelic(b.dataset.removeRelic));
  $$('[data-remove-potion]').forEach(b => b.onclick = () => removePotion(Number(b.dataset.removePotion)));
}

/* ---------------- calibration ---------------- */
const MODEL_FIELDS = [
  ['window', '观察窗口（秒）', 0.5, 1, 120, '单位战力按这个窗口估 DPS'],
  ['cast', '单次施法占用（秒）', 0.05, 0.1, 5, '技能动画/施法时间'],
  ['target_def', '参考目标防御', 1, 0, 999, '所有伤害按这个防御算'],
  ['area_targets', '范围平均目标数', 0.1, 1, 10, '区域/冲刺平均命中'],
  ['melee_uptime', '近战输出在线率', 0.01, 0, 1, '走路/被拉扯的折损'],
  ['ranged_uptime', '远程输出在线率', 0.01, 0, 1, '远程通常接近 1'],
  ['heal_weight', '治疗权重', 0.05, 0, 5, 'HPS 折算成输出的比例'],
  ['reference_hp', '基准有效生命', 1, 1, 9999, '士兵默认 150'],
  ['reference_output', '基准等效输出', 0.1, 0.1, 999, '士兵默认 4.0'],
  ['reference_power', '基准战力', 1, 1, 9999, '士兵 = 100'],
  ['energy_value', '1 能量 = ? P', 5, 10, 500, '费用/资源比较'],
  ['draw_value', '1 抽牌 = ? P', 1, 5, 200, '抽牌/检索比较'],
  ['hp_value', '1 玩家生命 = ? P', 0.5, 0.5, 50, '血契/事件付血'],
];
const COEF_FIELDS = [
  ['ATTACK_UP', '+1 攻击'], ['DEFENCE_UP', '+1 防御'], ['HEAL_PERCENT', '回复 1% 生命'],
  ['POISON_ON_HIT', '1 层中毒'], ['SHIELD', '1 点护盾'], ['DRAW', '抽 1 张'],
  ['GAIN_ENERGY', '+1 能量'], ['PARALYSIS', '1 秒眩晕'], ['WEAKNESS', '1 点虚弱'],
  ['VULNERABILITY', '+1% 易伤'], ['DAMAGE_ZONE', '区域 1 点/跳'], ['BLEED', '流血 1 点/秒'],
  ['SACRIFICE', '献祭基础'], ['KEEP_DISTANCE', '保持距离基础'], ['FRENZY', '狂化基础'],
];
function renderCalibration() {
  const m = state.model, base = soldierBaseline();
  const field = ([key, label, step, min, max, help]) => `<div class="field">
    <label title="${esc(help)}">${esc(label)}</label>
    <input type="number" step="${step}" min="${min}" max="${max}" value="${m[key]}" data-model="${key}"></div>`;
  const coef = ([key, label]) => `<div class="field"><label>${esc(label)}</label>
    <input type="number" step="0.5" value="${m.cardCoef[key]}" data-coef="${key}"></div>`;
  $('#view').innerHTML = `<div class="grid2">
    <div class="panel"><h2>模型校准</h2>
      <p class="hint">改这里会立刻重算全部单位/卡牌。建议先保持默认，等试玩有数据再校准。</p>
      <div class="grid3" style="gap:0 14px">${MODEL_FIELDS.map(field).join('')}</div>
      <div class="hr"></div><div class="kv"><span>当前士兵基准</span>
        <span>${fmt(base.power, 1)} P · EHP ${fmt(base.ehp, 1)} · 输出 ${fmt(base.output, 2)}</span></div>
      <div class="toolbar" style="margin-top:12px"><button class="btn small" id="resetModel">恢复默认</button>
        <button class="btn small" id="exportBtn">导出方案</button>
        <button class="btn small" id="importBtn">导入方案</button></div>
      <div class="formula">单位 P = reference_power × √(有效生命 / reference_hp × 等效输出 / reference_output)
有效生命 = 生命 × 15 / max(15 − 防御, 1) / (1 − 闪避 × 0.7)
等效输出 = DPS × 在线率 + heal_weight × HPS + 召唤贡献</div>
    </div>
    <div class="panel"><h2>卡牌效果系数</h2>
      <p class="hint">这些系数决定单卡 P。改完看卡牌页的效率排序有没有变化。</p>
      <div class="grid2" style="gap:0 12px">${COEF_FIELDS.map(coef).join('')}</div>
      <div class="hr"></div><h3>公式</h3>
      <div class="formula">卡牌 P = Σ 效果数值 × 系数 × 条件折损
费用预算 = 100 × 费用^0.8（0 费固定 100）
效率 = 卡牌 P / 费用预算</div>
      <p class="tip">治疗/护盾/控制的单体估价天然偏低；看效率时先看它是否属于“组合件”。</p>
    </div>
  </div>
  <div class="panel"><h2>数据与版本</h2>
    <div class="grid3">
      <div><div class="kv"><span>数据版本</span><span>${esc(DATA.meta.version)}</span></div>
        <div class="kv"><span>日期</span><span>${esc(DATA.meta.date)}</span></div></div>
      <div><div class="kv"><span>单位</span><span>${DATA.units.length}</span></div>
        <div class="kv"><span>卡牌</span><span>${DATA.cards.length}</span></div></div>
      <div><div class="kv"><span>遗物</span><span>${DATA.relics.length}</span></div>
        <div class="kv"><span>药水</span><span>${DATA.potions.length}</span></div></div>
    </div>
    <p class="tip" style="margin-top:10px">导出会把当前卡组、遗物、药水、手动改过的数值和模型参数一起保存为 JSON；导入会覆盖当前状态。</p>
  </div>`;
  $$('[data-model]').forEach(inp => inp.onchange = () => {
    const k = inp.dataset.model, v = Number(inp.value);
    if (Number.isFinite(v)) { state.model[k] = v; save(); render(); }
  });
  $$('[data-coef]').forEach(inp => inp.onchange = () => {
    const k = inp.dataset.coef, v = Number(inp.value);
    if (Number.isFinite(v)) { state.model.cardCoef[k] = v; save(); render(); }
  });
  $('#resetModel').onclick = () => { state.model = JSON.parse(JSON.stringify(DATA.model)); save(); render(); toast('模型已恢复默认'); };
  $('#exportBtn').onclick = exportState;
  $('#importBtn').onclick = () => $('#fileImport').click();
}
