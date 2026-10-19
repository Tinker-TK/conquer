/* ---------------- cards table ---------------- */
function ratioCell(ratio, targetRatio = null, showTarget = false) {
  if (ratio == null) return '<span class="tip">—</span>';
  const text = showTarget && targetRatio != null ? `${ratio.toFixed(2)} → ${targetRatio.toFixed(2)}` : ratio.toFixed(2);
  const barRatio = showTarget && targetRatio != null ? targetRatio : ratio;
  return `<div class="ratio"><div class="bar"><i style="width:${clamp(barRatio / 1.5 * 100, 0, 100)}%"></i></div><span>${text}</span></div>`;
}
function renderCards() {
  const search = state.search.toLowerCase(), cat = state.filter.cards, cost = state.filter.cost;
  const rarity = state.filter.rarity || 'all', sort = state.sort.cards;
  let list = DATA.cards.filter(c => {
    if (cat !== 'all' && c.category !== cat) return false;
    if (cost !== 'all' && String(cardView(c).cost) !== String(cost)) return false;
    if (rarity !== 'all' && c.rarity !== rarity) return false;
    if (search && !(c.name + ' ' + (c.desc || '') + ' ' + (c.tags || []).join(' ')).toLowerCase().includes(search)) return false;
    return true;
  }).map(c => ({ c, s: cardStats(c) }));
  list.sort((a, b) => {
    if (sort === 'name') return a.c.name.localeCompare(b.c.name);
    if (sort === 'cost') return a.s.cost - b.s.cost || b.s.power - a.s.power;
    if (sort === 'ratio') return (b.s.ratio || 0) - (a.s.ratio || 0);
    if (sort === 'upgrade') return b.s.upgradeDelta - a.s.upgradeDelta;
    return b.s.power - a.s.power;
  });
  const rows = list.map(({ c, s }) => {
    const effRatio = (s.targetCost != null && s.targetCost !== s.cost) ? s.targetRatio : s.ratio;
    const status = effRatio == null ? '' : effRatio > 1.3 ? '<span class="pill warn">超预算</span>'
      : effRatio < 0.45 ? '<span class="pill bad">偏低</span>' : '<span class="pill good">正常</span>';
    return `<tr data-card="${esc(c.id)}"><td class="name">${esc(c.name)}</td>
      <td class="num">${s.cost}${s.targetCost != null && s.targetCost !== s.cost ? ` <span class="sub">→${s.targetCost}</span>` : ''}</td>
      <td>${c.category === 'recruit' ? '<span class="pill good">征召</span>' : `<span class="pill">${esc(ROLE_CN[c.role] || '效果')}</span>`}</td>
      <td>${rarityPill(c.rarity)}</td><td class="num"><b>${fmt(s.power, 1)}</b></td>
      <td class="num">${fmt(s.upgradePower, 1)}</td><td>${ratioCell(s.ratio, s.targetRatio, s.targetCost != null && s.targetCost !== s.cost)}</td><td>${status}</td>
      <td>${(c.tags || []).map(t => `<span class="pill">${esc(t)}</span>`).join(' ')}</td>
      <td><button class="btn small" data-add-card="${esc(c.id)}">加入</button></td></tr>`;
  }).join('');
  $('#view').innerHTML = `<div class="panel"><h2>卡牌战力</h2>
    <p class="hint">效率 = 单卡 P / 费用预算。治疗/护盾/控制会被单体估价低估，低效率不一定弱。</p>
    <div class="toolbar"><input id="cSearch" placeholder="搜索卡牌 / 效果 / 标签" value="${esc(state.search)}">
      <select id="cCat"><option value="all" ${cat === 'all' ? 'selected' : ''}>全部类型</option>
        <option value="effect" ${cat === 'effect' ? 'selected' : ''}>效果/能力</option>
        <option value="recruit" ${cat === 'recruit' ? 'selected' : ''}>征召</option></select>
      <select id="cCost"><option value="all" ${cost === 'all' ? 'selected' : ''}>全部费用</option>
        ${[0,1,2,3,4,5].map(x => `<option value="${x}" ${String(cost) === String(x) ? 'selected' : ''}>${x} 费</option>`).join('')}</select>
      <select id="cRarity"><option value="all" ${rarity === 'all' ? 'selected' : ''}>全部稀有度</option>
        <option value="common" ${rarity === 'common' ? 'selected' : ''}>普通</option>
        <option value="rare" ${rarity === 'rare' ? 'selected' : ''}>稀有</option></select>
      <select id="cSort"><option value="power" ${sort === 'power' ? 'selected' : ''}>按战力</option>
        <option value="ratio" ${sort === 'ratio' ? 'selected' : ''}>按效率</option>
        <option value="upgrade" ${sort === 'upgrade' ? 'selected' : ''}>按强化提升</option>
        <option value="cost" ${sort === 'cost' ? 'selected' : ''}>按费用</option>
        <option value="name" ${sort === 'name' ? 'selected' : ''}>按名称</option></select>
      <button class="btn small" id="applyTargetCosts">套用建议费用</button>
      <button class="btn small" id="resetCardEdits">恢复当前</button>
      <span class="tip">共 ${list.length} 张</span></div>
    <div class="tablewrap"><table><thead><tr><th>卡牌</th><th class="num">费</th><th>类型</th><th>稀有</th>
      <th class="num">基础 P</th><th class="num">强化 P</th><th>效率</th><th>状态</th><th>标签</th><th></th></tr></thead>
      <tbody>${rows || '<tr><td colspan="10" class="empty">没有匹配的卡牌</td></tr>'}</tbody></table></div></div>`;
  $('#cSearch').oninput = (e) => { state.search = e.target.value; renderCards(); };
  $('#cCat').onchange = (e) => { state.filter.cards = e.target.value; renderCards(); };
  $('#cCost').onchange = (e) => { state.filter.cost = e.target.value; renderCards(); };
  $('#cRarity').onchange = (e) => { state.filter.rarity = e.target.value; renderCards(); };
  $('#cSort').onchange = (e) => { state.sort.cards = e.target.value; renderCards(); };
  $('#applyTargetCosts').onclick = applyTargetCosts;
  $('#resetCardEdits').onclick = resetCardEdits;
  $$('[data-card]').forEach(tr => tr.onclick = () => openCard(tr.dataset.card));
  $$('[data-add-card]').forEach(b => b.onclick = (e) => { e.stopPropagation(); addCard(b.dataset.addCard); });
}

/* ---------------- relics table ---------------- */
function renderRelics() {
  const search = state.search.toLowerCase(), rarity = state.filter.relics;
  const section = state.filter.section || 'all', sort = state.sort.relics;
  let list = DATA.relics.filter(r => {
    if (rarity !== 'all' && r.rarity !== rarity) return false;
    if (section !== 'all' && r.section !== section) return false;
    if (search && !(r.name + ' ' + r.effect + ' ' + r.section).toLowerCase().includes(search)) return false;
    return true;
  });
  list.sort((a, b) => sort === 'name' ? a.name.localeCompare(b.name) : sort === 'price' ? b.price - a.price : relicPower(b) - relicPower(a));
  const rows = list.map(r => `<tr data-relic="${esc(r.id)}"><td class="name">${esc(r.name)}</td>
    <td>${rarityPill(r.rarity)}</td><td><span class="pill">${esc(r.trigger)}</span></td>
    <td class="num"><b>${fmt(relicPower(r), 0)}</b></td><td class="num">${r.price || '不出售'}</td>
    <td>${esc(r.section)}</td><td class="sub">${esc((r.effect || '').slice(0, 90))}${(r.effect || '').length > 90 ? '…' : ''}</td>
    <td><button class="btn small" data-add-relic="${esc(r.id)}">加入</button></td></tr>`).join('');
  const sections = [...new Set(DATA.relics.map(r => r.section))].sort();
  $('#view').innerHTML = `<div class="panel"><h2>遗物战力</h2>
    <p class="hint">P 是每场战斗的等效价值。普通 60–90，稀有 140–200，首领 300–420。</p>
    <div class="toolbar"><input id="rSearch" placeholder="搜索遗物 / 效果 / 流派" value="${esc(state.search)}">
      <select id="rRarity"><option value="all" ${rarity === 'all' ? 'selected' : ''}>全部稀有度</option>
        <option value="common" ${rarity === 'common' ? 'selected' : ''}>普通</option>
        <option value="rare" ${rarity === 'rare' ? 'selected' : ''}>稀有</option>
        <option value="boss" ${rarity === 'boss' ? 'selected' : ''}>首领</option></select>
      <select id="rSection"><option value="all" ${section === 'all' ? 'selected' : ''}>全部流派</option>
        ${sections.map(s => `<option value="${esc(s)}" ${section === s ? 'selected' : ''}>${esc(s)}</option>`).join('')}</select>
      <select id="rSort"><option value="power" ${sort === 'power' ? 'selected' : ''}>按战力</option>
        <option value="price" ${sort === 'price' ? 'selected' : ''}>按价格</option>
        <option value="name" ${sort === 'name' ? 'selected' : ''}>按名称</option></select>
      <span class="tip">共 ${list.length} 件</span></div>
    <div class="tablewrap"><table><thead><tr><th>遗物</th><th>稀有</th><th>触发</th><th class="num">P/场</th>
      <th class="num">价格</th><th>流派</th><th>效果</th><th></th></tr></thead>
      <tbody>${rows || '<tr><td colspan="8" class="empty">没有匹配的遗物</td></tr>'}</tbody></table></div></div>`;
  $('#rSearch').oninput = (e) => { state.search = e.target.value; renderRelics(); };
  $('#rRarity').onchange = (e) => { state.filter.relics = e.target.value; renderRelics(); };
  $('#rSection').onchange = (e) => { state.filter.section = e.target.value; renderRelics(); };
  $('#rSort').onchange = (e) => { state.sort.relics = e.target.value; renderRelics(); };
  $$('[data-relic]').forEach(tr => tr.onclick = () => openRelic(tr.dataset.relic));
  $$('[data-add-relic]').forEach(b => b.onclick = (e) => { e.stopPropagation(); addRelic(b.dataset.addRelic); });
}

/* ---------------- potions table ---------------- */
function renderPotions() {
  const search = state.search.toLowerCase(), rarity = state.filter.potions;
  const act = state.filter.act || 'all', sort = state.sort.potions;
  let list = DATA.potions.filter(p => {
    if (rarity !== 'all' && p.rarity !== rarity) return false;
    if (act !== 'all' && String(p.min_act) !== String(act)) return false;
    if (search && !(p.name + ' ' + p.effect + ' ' + p.role).toLowerCase().includes(search)) return false;
    return true;
  });
  list.sort((a, b) => sort === 'name' ? a.name.localeCompare(b.name) : sort === 'price' ? b.price - a.price : potionPower(b) - potionPower(a));
  const rows = list.map(p => `<tr data-potion="${esc(p.id)}"><td class="name">${esc(p.name)}</td>
    <td>${rarityPill(p.rarity)}</td><td class="num">${p.price}</td><td class="num"><b>${fmt(potionPower(p), 0)}</b></td>
    <td class="num">${p.min_act}</td><td>${esc(p.target)}</td>
    <td class="sub">${esc((p.effect || '').slice(0, 100))}${(p.effect || '').length > 100 ? '…' : ''}</td>
    <td><button class="btn small" data-add-potion="${esc(p.id)}">加入</button></td></tr>`).join('');
  $('#view').innerHTML = `<div class="panel"><h2>药水战力</h2>
    <p class="hint">P 是一次使用的等效价值。普通 90–130，稀有 180–260，传说 350–500。</p>
    <div class="toolbar"><input id="pSearch" placeholder="搜索药水 / 效果 / 定位" value="${esc(state.search)}">
      <select id="pRarity"><option value="all" ${rarity === 'all' ? 'selected' : ''}>全部稀有度</option>
        <option value="common" ${rarity === 'common' ? 'selected' : ''}>普通</option>
        <option value="rare" ${rarity === 'rare' ? 'selected' : ''}>稀有</option>
        <option value="legendary" ${rarity === 'legendary' ? 'selected' : ''}>传说</option></select>
      <select id="pAct"><option value="all" ${act === 'all' ? 'selected' : ''}>全部幕</option>
        ${[1,2,3].map(x => `<option value="${x}" ${String(act) === String(x) ? 'selected' : ''}>第 ${x} 幕起</option>`).join('')}</select>
      <select id="pSort"><option value="power" ${sort === 'power' ? 'selected' : ''}>按战力</option>
        <option value="price" ${sort === 'price' ? 'selected' : ''}>按价格</option>
        <option value="name" ${sort === 'name' ? 'selected' : ''}>按名称</option></select>
      <span class="tip">共 ${list.length} 瓶</span></div>
    <div class="tablewrap"><table><thead><tr><th>药水</th><th>稀有</th><th class="num">价格</th><th class="num">P</th>
      <th class="num">幕</th><th>目标</th><th>效果</th><th></th></tr></thead>
      <tbody>${rows || '<tr><td colspan="8" class="empty">没有匹配的药水</td></tr>'}</tbody></table></div></div>`;
  $('#pSearch').oninput = (e) => { state.search = e.target.value; renderPotions(); };
  $('#pRarity').onchange = (e) => { state.filter.potions = e.target.value; renderPotions(); };
  $('#pAct').onchange = (e) => { state.filter.act = e.target.value; renderPotions(); };
  $('#pSort').onchange = (e) => { state.sort.potions = e.target.value; renderPotions(); };
  $$('[data-potion]').forEach(tr => tr.onclick = () => openPotion(tr.dataset.potion));
  $$('[data-add-potion]').forEach(b => b.onclick = (e) => { e.stopPropagation(); addPotion(b.dataset.addPotion); });
}
