(function () {
  'use strict';
  const M = window.UnitPowerModel;
  const seed = JSON.parse(document.getElementById('calculator-seed').textContent);
  const storageKey = seed.storageId;
  const $ = id => document.getElementById(id);
  const fmt = (n, digits = 1) => n === null || n === undefined ? '—' : n.toLocaleString('zh-CN', { minimumFractionDigits: digits, maximumFractionDigits: digits });
  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const compact = n => Number(n.toFixed(6));
  const kindName = { normal: '单体攻击', projectile: '投射物', area: '范围攻击', dash: '冲刺', lifesteal: '吸血攻击', heal: '治疗', summon: '召唤',teleport:'瞬移连击',combo_passive:'连击被动',aura_passive:'光环被动',stealth_passive:'隐身被动' };
  let state = M.copy(seed.initialState || seed.defaults), selected = 'soldier', tab = 'overview', sort = 'team';
  let hidden = new Set(), calculated, lastValidState, saveTimer, toastTimer, drawTimer, resetUndo, pending = new Map();
  const colors = { ally: '#1a7250', enemy: '#317e91', selected: '#c97021' };
  try {
    const saved = localStorage.getItem(storageKey);
    if (saved) { const parsed = JSON.parse(saved); M.evaluateAll(parsed, seed.reference); state = parsed; }
  } catch (_) { $('save-status').textContent = '使用项目初值'; }
  if (state.ui) {
    if (state.units.some(u => u.id === state.ui.selected)) selected = state.ui.selected;
    hidden = new Set((Array.isArray(state.ui.hidden) ? state.ui.hidden : []).filter(id => seed.reference.unitIds.includes(id)));
    if (['overview', 'editor', 'standard'].includes(state.ui.tab)) tab = state.ui.tab;
    if (['team', 'power', 'upgraded', 'efficiency', 'gain'].includes(state.ui.sort)) sort = state.ui.sort;
  }
  const unit = () => state.units.find(u => u.id === selected);
  const unitIndex = () => state.units.findIndex(u => u.id === selected);
  const snapshot = () => ({ ...M.copy(state), ui: { selected, hidden: [...hidden], tab, sort } });
  function toast(message) {
    clearTimeout(toastTimer); $('toast').textContent = message; $('toast').hidden = false;
    toastTimer = setTimeout(() => $('toast').hidden = true, 4200);
  }
  function error(message) { $('error').textContent = message; $('error').hidden = !message; }
  function save() {
    if (pending.size) return;
    clearTimeout(saveTimer); $('save-status').textContent = '保存中…';
    saveTimer = setTimeout(() => {
      try { localStorage.setItem(storageKey, JSON.stringify(snapshot())); $('save-status').textContent = '已自动保存'; }
      catch (_) { $('save-status').textContent = '请导出备份'; }
    }, 350);
  }
  function calculate() {
    if (pending.size) return false;
    try { calculated = M.evaluateAll(state, seed.reference); lastValidState = M.copy(state); error(''); return true; }
    catch (e) { error(e.message + '。结果暂保留最近有效值。'); return false; }
  }
  function field(path, label, value, spec = {}) {
    const { min = 0, max = 100000, step = 1, percent = false, nullable = false, options, checkbox = false, text = false, array = false, help = '' } = spec;
    const id = 'f-' + path.replace(/\./g, '-');
    const attr = `id="${esc(id)}" data-path="${esc(path)}"`;
    let input;
    if (checkbox) input = `<input type="checkbox" ${attr} ${value ? 'checked' : ''}>`;
    else if (options) input = `<select ${attr}>${options.map(([v, t]) => `<option value="${esc(v)}" ${v === value ? 'selected' : ''}>${esc(t)}</option>`).join('')}</select>`;
    else if (array) input = `<input type="text" ${attr} value="${esc(JSON.stringify(value))}" data-levels="true">`;
    else if (text) input = `<input type="text" ${attr} value="${esc(value)}" ${path.endsWith('.offsets') ? 'data-offsets="true"' : ''}>`;
    else input = `<input type="number" ${attr} min="${min}" max="${max}" step="${step === 1 && !percent ? 1 : 'any'}" value="${value === null ? '' : compact(percent ? value * 100 : value)}" ${percent ? 'data-percent="true"' : ''} ${nullable ? 'data-nullable="true" placeholder="自动"' : ''}>`;
    return `<label class="${checkbox ? 'checkline' : ''}" for="${id}">${checkbox ? input + esc(label) : esc(label) + input}${help ? '<span>' + esc(help) + '</span>' : ''}</label>`;
  }
  function renderEditor() {
    const u = unit(), i = unitIndex(), path = `units.${i}`, p = u.plan;
    $('base-fields').innerHTML = [
      field(path + '.hp', '当前生命', u.hp, { min: 1, max: 10000000 }),
      field(path + '.attack', '当前攻击', u.attack), field(path + '.defence', '当前防御', u.defence),
      field(path + '.cost', '基础征召费用', u.cost, { max: 999 }),
      field(path + '.dodge', '闪避率 %', u.dodge, { max: 100, step: 1, percent: true }),
      field(path + '.departures', '累计退场加费', u.departures, { max: 999 }),
      field(path + '.baseLevel', '当前已训练次数', u.baseLevel, { max: 99 }),
      field(path + '.gameMax', '游戏训练次数上限', u.gameMax, { max: 99 }),
      field(path + '.upgradePoints', '每次训练能力点', u.upgradePoints, { max: 999 }),
      field(path + '.uptime', '输出在线率 %（留空自动）', u.uptime, { max: 100, step: 1, percent: true, nullable: true }),
      field(path + '.counterNetDps', '反击净 DPS（待实测）', u.counterNetDps, { min: -100000, step: 0.1 }),
      field(path + '.counterUnlock', '反击生效强化等级', u.counterUnlock, { array: true, help: '[0,1] 仅在等级0和1生效；[] 不生效' }),
      field(path + '.hasCounter', '已配置闪避 / 反击技能', u.hasCounter, { checkbox: true })
    ].join('');
    const modes = u.team === 'team_a' ? [['training', '按游戏训练规则'], ['custom', '自定义成长']] : [['custom', '自定义成长（敌军预测）']];
    let growth = [field(path + '.plan.mode', '成长模式', p.mode, { options: modes }), field(path + '.plan.levels', '比较升级 / 强化阶段', p.levels, { max: 20 })];
    if (p.mode === 'training') {
      growth.push(field(path + '.plan.attackAllocation', '每次训练：攻击点', p.attackAllocation, { max: 999 }),
        field(path + '.plan.defenceAllocation', '每次训练：防御点', p.defenceAllocation, { max: 999 }));
      $('training-help').textContent = `每次分配共 ${u.upgradePoints} 点。修改攻击点时防御点自动补齐；修改防御点时攻击点自动补齐。当前剩余游戏训练次数 ${Math.max(0, u.gameMax - u.baseLevel)}。`;
    } else {
      for (const [k, label] of [['hpStep', '每阶生命 +'], ['attackStep', '每阶攻击 +'], ['defenceStep', '每阶防御 +'], ['costStep', '每阶征召费用 +']])
        growth.push(field(path + '.plan.' + k, label, p[k], { min: k === 'costStep' ? -999 : -100000, max: k === 'costStep' ? 999 : 100000 }));
      for (const [k, label] of [['hpGrowth', '每阶生命增长 %'], ['attackGrowth', '每阶攻击增长 %'], ['defenceGrowth', '每阶防御增长 %']])
        growth.push(field(path + '.plan.' + k, label, p[k], { min: -90, max: 200, step: 1, percent: true }));
      growth.push(field(path + '.plan.dodgeStep', '每阶闪避 + 百分点', p.dodgeStep, { min: -100, max: 100, percent: true }));
      $('training-help').textContent = '自定义成长全部按预测标记。百分比增长采用复利，固定增长线性叠加；这些设置不会自动成为游戏中的训练规则。';
    }
    $('plan-fields').innerHTML = growth.join('');
    $('buff-fields').innerHTML = [
      ...[['hpBuff', '额外生命 +'], ['attackBuff', '额外攻击 +'], ['defenceBuff', '额外防御 +']].map(([k, label]) => field(path + '.plan.' + k, label, p[k], { min: -100000 })),
      field(path + '.plan.dodgeBuff', '额外闪避 + 百分点', p.dodgeBuff, { min: -100, max: 100, percent: true }),
      field(path + '.plan.costBuff', '额外征召费用 +', p.costBuff, { min: -999, max: 999 }),
      field(path + '.plan.buffEnergy', '额外强化牌总耗能', p.buffEnergy, { max: 999, step: 0.1 }),
      field(path + '.plan.cooldownFactor', '冷却时长系数', p.cooldownFactor, { min: 0.1, max: 10, step: 0.05 }),
      field(path + '.plan.animationFactor', '动作时长系数', p.animationFactor, { min: 0.1, max: 10, step: 0.05 }),
      field(path + '.plan.outputFactor', '伤害与治疗输出系数', p.outputFactor, { max: 10, step: 0.05 })
    ].join('');
    $('skill-fields').innerHTML = u.skills.map((s, j) => {
      const sp = path + '.skills.' + j;
      if (s.kind.endsWith('_passive')) {
        let parameters = [field(sp+'.unlock','生效强化等级',s.unlock,{array:true})];
        if(s.kind==='combo_passive') parameters.push(field(sp+'.attack_bonus_per_hit','每命中攻击 +',s.attack_bonus_per_hit,{max:999}));
        if(s.kind==='aura_passive') parameters.push(field(sp+'.aura_attack_bonus','庇护攻击 +',s.aura_attack_bonus,{max:999}),field(sp+'.aura_radius','庇护半径',s.aura_radius,{min:1,max:2000}),field(sp+'.aura_include_caster','包含自身',s.aura_include_caster,{checkbox:true}));
        if(s.kind==='stealth_passive') parameters.push(field(sp+'.stealth_health_percent','触发生命百分比 %',s.stealth_health_percent,{min:1,max:100}),field(sp+'.stealth_duration','隐身秒数',s.stealth_duration,{min:.1,max:60,step:.1}));
        return `<section class="skill"><h3>${esc(s.name)}<span class="pill">${kindName[s.kind]}</span></h3><div class="fields">${parameters.join('')}</div><p class="help">被动不占用施法时间。连击按参考目标死亡后清零；光环只计自身攻击收益；隐身收益暂未折分。</p></section>`;
      }
      const extras = s.kind === 'summon' ? [
        field(sp + '.child', '召唤单位', s.child, { options: state.units.filter(v => v.team === u.team).map(v => [v.id, v.name]) }),
        field(sp + '.summonDelay', '命中后的生成延迟 / 秒', s.summonDelay, { max: 120, step: 0.05 })
      ] : [];
      return `<section class="skill"><h3>${esc(s.name)}<span class="pill">${kindName[s.kind]}</span></h3><div class="fields">` + [
        field(sp + '.rate', s.kind === 'heal' ? '治疗倍率' : '伤害倍率', s.rate, { max: 100, step: 0.05 }),
        field(sp + '.cooldown', '冷却 / 秒', s.cooldown, { min: 0.05, max: 120, step: 0.05 }),
        field(sp + '.duration', '动作占用 / 秒', s.duration, { min: 0.05, max: 120, step: 0.05 }),
        field(sp + '.priority', '优先级', s.priority, { min: -999, max: 999 }),
        field(sp + '.range', '施法射程', s.range, { max: 99999 }),
        field(sp + '.unlock', '解锁强化等级', s.unlock, { array: true, help: '[0] 强化后失效；[1] 仅强化一次时生效' }),
        field(sp + '.targets', '平均命中目标（留空自动）', s.targets, { min: 1, max: 50, step: 0.1, nullable: true }),
        field(sp + '.offsets', '命中时间 / 秒', s.offsets.map(compact).join(', '), { text: true }), ...extras
      ].join('') + '</div></section>';
    }).join('') + (u.id === 'soldier' ? `<section class="skill"><h3>训练后剑矢<span class="pill">远程窗口</span></h3><div class="fields">` + [
      field(path + '.sword.range', '剑矢射程', u.sword.range, { min: 1, max: 99999 }),
      field(path + '.sword.duration', '发箭动作占用 / 秒', u.sword.duration, { min: 0.05, max: 120, step: 0.05 }),
      field(path + '.sword.offset', '发箭时间 / 秒', u.sword.offset, { max: 120, step: 0.05 })
    ].join('') + '</div><p class="help">与近战普通攻击共用冷却和倍率。远程窗口占比在“计算标准”中调整。</p></section>' : '');
  }
  const standardSpecs = [
    ['window', '评估窗口 / 秒', 1, 120, 1], ['incoming', '参考来袭每击原伤', 1, 99999, 1], ['targetDefence', '参考对手防御', 0, 99999, 1],
    ['eligible', '可闪避来袭占比 %', 0, 100, 1, true], ['targetDodge', '参考对手闪避 %', 0, 100, 1, true],
    ['meleeUptime', '近战输出在线率 %', 0, 100, 1, true], ['rangedUptime', '远程输出在线率 %', 0, 100, 1, true],
    ['areaTargets', '范围 / 冲刺平均目标', 1, 50, 0.1], ['pierceTargets', '直线穿透平均目标', 1, 50, 0.1],
    ['healRealization', '治疗兑现率 %', 0, 100, 1, true], ['lifestealRealization', '吸血兑现率 %', 0, 100, 1, true],
    ['healWeight', '有效治疗折算权重', 0, 5, 0.05], ['summonRealization', '召唤兑现率 %', 0, 100, 1, true],
    ['swordFarShare', '士兵剑矢远程窗口占比 %', 0, 100, 1, true], ['costBonus', '每多一费的预算溢价 %', 0, 100, 1, true],['comboTargetHp','连击参考目标生命',1,10000000,1]
  ];
  function renderStandard() {
    $('standard-fields').innerHTML = standardSpecs.map(([k, label, min, max, step, percent]) => field('model.' + k, label, state.model[k] ?? 100, { min, max, step, percent })).join('');
  }
  function orderedUnits() {
    const values = [...state.units], r = id => calculated.result.get(id);
    if (sort === 'team') return values.sort((a, b) => a.team.localeCompare(b.team) || seed.reference.unitIds.indexOf(a.id) - seed.reference.unitIds.indexOf(b.id));
    const metric = u => sort === 'power' ? r(u.id).current.power : sort === 'upgraded' ? r(u.id).upgraded.power : sort === 'efficiency' ? r(u.id).upgraded.perCost ?? -1 : r(u.id).gain ?? -1;
    return values.sort((a, b) => metric(b) - metric(a));
  }
  function renderTable() {
    $('unit-rows').innerHTML = orderedUnits().map(u => {
      const i = state.units.indexOf(u), p = `units.${i}`;
      const cells = [['hp', 1, 10000000], ['attack', 0, 100000], ['defence', 0, 100000], ['cost', 0, 999], ['dodge', 0, 100]]
        .map(([k, min, max]) => `<td><input type="number" data-path="${p}.${k}" data-field="${k}" aria-label="${esc(u.name)}${k === 'hp' ? '生命' : k === 'attack' ? '攻击' : k === 'defence' ? '防御' : k === 'cost' ? '费用' : '闪避百分比'}" min="${min}" max="${max}" step="${k === 'dodge' ? 'any' : 1}" value="${k === 'dodge' ? compact(u[k] * 100) : u[k]}" ${k === 'dodge' ? 'data-percent="true"' : ''}></td>`).join('');
      return `<tr data-unit="${u.id}" class="${u.id === selected ? 'selected' : ''}"><td><button class="unit-name" data-edit-unit="${u.id}">${esc(u.name)}</button> <span class="dot ${u.team === 'team_b' ? 'enemy' : ''}"></span></td>${cells}<td class="power-cell" data-result="current"></td><td class="power-cell" data-result="upgraded"></td><td data-result="gain"></td><td data-result="fee"></td><td data-result="base-ratio"></td><td data-result="up-ratio"></td><td data-result="stage"></td></tr>`;
    }).join('');
    updateTableResults();
  }
  function updateTableResults() {
    const maxPower = Math.max(...[...calculated.result.values()].flatMap(r => [r.current.power, r.upgraded.power]), 1);
    for (const row of $('unit-rows').rows) {
      const r = calculated.result.get(row.dataset.unit), u = state.units.find(v => v.id === row.dataset.unit);
      const fill = (name, html) => row.querySelector(`[data-result="${name}"]`).innerHTML = html;
      for (const [key, cls] of [['current', ''], ['upgraded', 'up']]) fill(key, `<span class="mono ${cls ? 'up-value' : ''}">${fmt(r[key].power)}</span><div class="power-bar ${cls}" style="width:${r[key].power / maxPower * 100}%"></div>`);
      fill('gain', r.gain === null ? '—' : `${r.gain >= 0 ? '+' : ''}${fmt(r.gain * 100)}%`);
      fill('fee', fmt(r.upgraded.recruitCost, 0)); fill('base-ratio', r.current.perCost === null ? '免费' : fmt(r.current.perCost));
      fill('up-ratio', r.upgraded.perCost === null ? '免费' : fmt(r.upgraded.perCost));
      fill('stage', `${u.plan.levels} 阶 · ${r.upgraded.forecast ? '预测' : u.plan.levels === 0 ? '当前' : '训练'}`);
      row.classList.toggle('selected', row.dataset.unit === selected);
    }
  }
  function renderLegend() {
    $('curve-legend').innerHTML = state.units.map(u => `<label><input type="checkbox" data-series="${u.id}" ${hidden.has(u.id) ? '' : 'checked'}><span class="dot ${u.id === selected ? 'selected' : u.team === 'team_b' ? 'enemy' : ''}"></span><span data-selected="${u.id === selected}">${esc(u.name)}</span></label>`).join('');
  }
  function results() {
    const u = unit(), r = calculated.result.get(selected), b = r.current, a = r.upgraded;
    $('current-power').textContent = fmt(b.power);
    $('upgraded-power').textContent = fmt(a.power);
    $('current-detail').textContent = `${u.name} · 本体 ${fmt(b.bodyPower)}${b.summonPower ? ' + 召唤 ' + fmt(b.summonPower) : ''}`;
    $('gain-detail').textContent = `${u.plan.levels} 阶 · ${a.forecast ? '预测' : u.plan.levels ? '游戏训练' : '当前'} · ${r.gain === null ? '基准输出为零' : '提升 ' + (r.gain >= 0 ? '+' : '') + fmt(r.gain * 100) + '%'}`;
    $('cost-power').textContent = a.perCost === null ? '免费' : fmt(a.perCost);
    $('cost-detail').textContent = `征召 ${fmt(a.recruitCost, 0)} 能量 · 计入额外强化后 ${a.perTotalEnergy === null ? '免费' : fmt(a.perTotalEnergy) + ' 战力/能量'}`;
    $('team-tag').textContent = u.team === 'team_a' ? '己方' : '敌方'; $('team-tag').classList.toggle('enemy', u.team === 'team_b');
    const note = u.team === 'team_b' ? '敌军没有玩家篝火训练入口。强化数值用于自定义配兵预测，费用为配置参考值。' : a.forecast ? '当前方案属于自定义成长或超出游戏训练上限，图表按预测标记。' : '训练按当前游戏规则计算，额外强化按你填写的增量估价。';
    $('plan-note').textContent = note + (u.id === 'soldier' ? ' 士兵训练达到 1 次后启用剑矢，近战与远程输出按统一占比估价。' : '');
    const breakdown = [
      ['属性：生命 / 攻击 / 防御', `${b.attributes.hp} / ${b.attributes.attack} / ${b.attributes.defence}`, `${a.attributes.hp} / ${a.attributes.attack} / ${a.attributes.defence}`],
      ['有效生命', fmt(b.ehp), fmt(a.ehp)], ['输出 DPS', fmt(b.dps, 2), fmt(a.dps, 2)], ['有效治疗 HPS', fmt(b.hps, 2), fmt(a.hps, 2)],
      ['等效输出', fmt(b.output, 2), fmt(a.output, 2)], ['本体战力', fmt(b.bodyPower), fmt(a.bodyPower)], ['召唤贡献', fmt(b.summonPower), fmt(a.summonPower)],
      ['征召能量（含退场加费）', fmt(b.recruitCost, 0), fmt(a.recruitCost, 0)], ['含额外强化总能量', fmt(b.totalEnergy), fmt(a.totalEnergy)],
      ['总能量效率', b.perTotalEnergy === null ? '免费' : fmt(b.perTotalEnergy), a.perTotalEnergy === null ? '免费' : fmt(a.perTotalEnergy)],
      ['费用预算参考', b.budget === null ? '—' : fmt(b.budget), a.budget === null ? '—' : fmt(a.budget)],
      ['实际战力 / 费用预算', b.budgetRatio === null ? '—' : fmt(b.budgetRatio * 100) + '%', a.budgetRatio === null ? '—' : fmt(a.budgetRatio * 100) + '%']
    ];
    $('result-breakdown').innerHTML = `<table class="detail-table"><thead><tr><th>指标</th><th>当前</th><th>强化后</th></tr></thead><tbody>${breakdown.map(row => '<tr>' + row.map(v => '<td>' + esc(v) + '</td>').join('') + '</tr>').join('')}</tbody></table>` + [...new Set([...b.unpricedEffects,...a.unpricedEffects])].map(v=>'<p class="help">'+esc(v)+'</p>').join('');
    const scheduleTable = (data, title) => `<h3>${esc(title)}</h3><table class="detail-table"><thead><tr><th>技能</th><th>开始 / 秒</th><th>结束 / 秒</th><th>窗口内命中</th><th>伤害 / 治疗</th></tr></thead><tbody>${data.trace.map(t => `<tr><td>${esc(t.name)}</td><td>${fmt(t.start, 2)}</td><td>${fmt(t.end, 2)}</td><td>${t.hits.map(h => fmt(h.time, 2)).join(', ') || '—'}</td><td>${fmt(t.hits.reduce((sum, h) => sum + (h.damage || 0), 0), 1)} / ${fmt(t.hits.reduce((sum, h) => sum + (h.healing || 0), 0), 1)}</td></tr>`).join('')}</tbody></table>`;
    $('schedule-detail').innerHTML = a.swordMix ? scheduleTable(a.swordMix.near, '剑矢：近战窗口') + scheduleTable(a.swordMix.far, '剑矢：远程窗口，占比 ' + fmt(a.swordMix.share * 100, 0) + '%') : scheduleTable(a, '标准输出窗口');
    const base = calculated.baseline;
    $('baseline-detail').textContent = `当前比较环境中的固定基准：士兵生命 ${seed.reference.soldier.hp} / 攻击 ${seed.reference.soldier.attack} / 防御 ${seed.reference.soldier.defence}，有效生命 ${fmt(base.ehp)}，等效输出 ${fmt(base.output, 4)}。`;
    updateTableResults();
    drawCharts();
  }
  function svgEl(tag, attrs, text) {
    const el = document.createElementNS('http://www.w3.org/2000/svg', tag);
    for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
    if (text !== undefined) el.textContent = text;
    return el;
  }
  function drawChart(id, metric) {
    const svg = $(id), width = svg.getBoundingClientRect().width;
    if (width < 100) return;
    const height = svg.getBoundingClientRect().height, left = 64, right = 20, top = 15, bottom = 44;
    const maxStage = Math.max(state.curveMax, ...state.units.map(u => u.plan.levels));
    const visible = state.units.filter(u => !hidden.has(u.id));
    const points = visible.flatMap(u => calculated.result.get(u.id).curve.map(r => r[metric]).filter(v => v !== null));
    const rawMax = Math.max(...points, 1), magnitude = Math.pow(10, Math.floor(Math.log10(rawMax))), ceil = Math.ceil(rawMax / magnitude * 5) / 5 * magnitude;
    const maxY = ceil * 1.08;
    const x = n => left + n / maxStage * (width - left - right), y = n => height - bottom - n / maxY * (height - top - bottom);
    svg.replaceChildren(); svg.setAttribute('viewBox', `0 0 ${width} ${height}`);
    svg.append(svgEl('title', {}, metric === 'power' ? '单位战力成长曲线' : '单位征召战费比成长曲线'));
    for (let i = 0; i <= 4; i++) {
      const val = maxY * i / 4, yy = y(val);
      svg.append(svgEl('line', { x1: left, x2: width - right, y1: yy, y2: yy, class: 'grid' }));
      svg.append(svgEl('text', { x: left - 10, y: yy + 4, 'text-anchor': 'end' }, fmt(val, val > 100 ? 0 : 1)));
    }
    const tickStep = Math.max(1, Math.ceil(maxStage / (width < 420 ? 4 : 6)));
    const ticks = new Set([0, maxStage]); for (let n = 0; n <= maxStage; n += tickStep) ticks.add(n);
    [...ticks].sort((a, b) => a - b).forEach(n => svg.append(svgEl('text', { x: x(n), y: height - bottom + 20, 'text-anchor': 'middle' }, n)));
    svg.append(svgEl('text', { x: width - right, y: height - 3, 'text-anchor': 'end' }, '强化阶段（次）'));
    svg.append(svgEl('text', { x: left, y: 10 }, metric === 'power' ? '战力（分）' : '战力 / 能量'));
    // Draw the selected series last so it remains readable among all 21 units.
    for (const u of [...visible.filter(u => u.id !== selected), ...visible.filter(u => u.id === selected)]) {
      const data = calculated.result.get(u.id).curve, color = u.id === selected ? colors.selected : u.team === 'team_a' ? colors.ally : colors.enemy;
      for (let n = 1; n < data.length; n++) {
        if (data[n - 1][metric] === null || data[n][metric] === null) continue;
        svg.append(svgEl('path', { d: `M${x(n - 1)},${y(data[n - 1][metric])}L${x(n)},${y(data[n][metric])}`, stroke: color,
          class: 'series' + (u.id === selected ? ' selected' : ''), 'stroke-dasharray': data[n].forecast ? '5 4' : 'none', 'data-unit-series': u.id }));
      }
      if (u.id === selected) for (const r of data) if (r[metric] !== null) svg.append(svgEl('circle', { cx: x(r.stage), cy: y(r[metric]), r: r.stage === u.plan.levels ? 5 : 3, fill: color }));
    }
    const guide = svgEl('line', { x1: left, x2: left, y1: top, y2: height - bottom, class: 'guide', visibility: 'hidden' });
    svg.append(guide);
    const hit = svgEl('rect', { x: left, y: top, width: width - left - right, height: height - top - bottom, class: 'hit' });
    const show = e => {
      const bounds = svg.getBoundingClientRect(), pos = Math.max(left, Math.min(width - right, e.clientX - bounds.left));
      const n = (pos - left) / (width - left - right) * maxStage;
      guide.setAttribute('x1', pos); guide.setAttribute('x2', pos); guide.setAttribute('visibility', 'visible');
      const vals = visible.map(u => {
        const curve = calculated.result.get(u.id).curve, lo = Math.floor(n), hi = Math.min(lo + 1, curve.length - 1);
        const a = curve[lo]?.[metric], b = curve[hi]?.[metric];
        return { u, value: a === null || a === undefined || b === null || b === undefined ? null : a + (b - a) * (n - lo) };
      }).sort((a, b) => (b.value ?? -1) - (a.value ?? -1));
      $('chart-tooltip').innerHTML = `<div class="tip-title">阶段 ${fmt(n, 2)} · ${metric === 'power' ? '战力' : '战费比'} <span class="muted">（连线插值）</span></div>` + vals.map(v => `<div class="tiprow ${v.u.id === selected ? 'sel' : ''}"><span>${esc(v.u.name)}</span><span>${v.value === null ? '免费' : fmt(v.value)}</span></div>`).join('');
      const tip = $('chart-tooltip'); tip.hidden = false;
      const tw = tip.offsetWidth, th = tip.offsetHeight;
      tip.style.left = Math.max(8, Math.min(window.innerWidth - tw - 8, e.clientX + 14)) + 'px';
      tip.style.top = Math.max(8, Math.min(window.innerHeight - th - 8, e.clientY + 14)) + 'px';
    };
    hit.addEventListener('pointermove', show);
    hit.addEventListener('pointerleave', () => { guide.setAttribute('visibility', 'hidden'); $('chart-tooltip').hidden = true; });
    hit.addEventListener('click', e => { show(e); }); svg.append(hit);
  }
  function drawCharts() { if (tab === 'overview') { drawChart('power-chart', 'power'); drawChart('cost-chart', 'perCost'); } }
  function select(id, editor = false) {
    if (pending.size) { toast('请先修正当前无效输入，再切换单位。'); return; }
    selected = id; $('selected-unit').value = id;
    if (editor) setTab('editor', false);
    renderEditor(); renderLegend(); results(); save();
  }
  function setTab(next, persist = true) {
    tab = next;
    for (const name of ['overview', 'editor', 'standard']) { $('view-' + name).hidden = name !== tab; $('tab-' + name).setAttribute('aria-selected', String(name === tab)); }
    drawCharts(); if (persist) save();
  }
  function renderAll() {
    $('selected-unit').innerHTML = ['team_a', 'team_b'].map(team => `<optgroup label="${team === 'team_a' ? '己方单位' : '敌方单位'}">${state.units.filter(u => u.team === team).map(u => `<option value="${u.id}">${esc(u.name)}</option>`).join('')}</optgroup>`).join('');
    $('selected-unit').value = selected; $('curve-max').value = state.curveMax; $('sort-units').value = sort;
    $('bulk-levels').value = state.units.every(u => u.plan.levels === state.units[0].plan.levels) ? state.units[0].plan.levels : '';
    $('bulk-levels').placeholder = '混合';
    renderEditor(); renderStandard(); renderTable(); renderLegend(); setTab(tab, false); results();
  }
  function updateInput(e) {
    const input = e.target, path = input.dataset.path;
    if (!path) return;
    const keys = path.split('.'), key = keys.pop(); let object = state;
    for (const k of keys) object = object[k];
    let value;
    if (input.type === 'checkbox') value = input.checked;
    else if (input.dataset.levels) {
      try { value = JSON.parse(input.value); if (!Array.isArray(value)) value = null; }
      catch (_) { value = null; }
    }
    else if (input.dataset.offsets) value = input.value.split(',').map(v => v.trim()).map(v => v === '' ? NaN : Number(v));
    else if (input.tagName === 'SELECT') value = input.value;
    else if (input.type === 'text') value = input.value;
    else if (input.value.trim() === '') value = input.dataset.nullable ? null : NaN;
    else value = Number(input.value) / (input.dataset.percent ? 100 : 1);
    object[key] = value;
    const match = path.match(/^units\.(\d+)\.plan\.(attackAllocation|defenceAllocation)$/);
    if (match) {
      const u = state.units[Number(match[1])], other = key === 'attackAllocation' ? 'defenceAllocation' : 'attackAllocation';
      u.plan[other] = u.upgradePoints - value;
    }
    const pointMatch = path.match(/^units\.(\d+)\.upgradePoints$/);
    if (pointMatch) { const u = state.units[Number(pointMatch[1])]; u.plan.attackAllocation = value; u.plan.defenceAllocation = 0; }
    try {
      const next = M.evaluateAll(state, seed.reference);
      pending.clear(); calculated = next;
      lastValidState = M.copy(state);
      input.removeAttribute('aria-invalid');
      document.querySelectorAll('[aria-invalid="true"][data-path]').forEach(el => el.removeAttribute('aria-invalid'));
      error('');
      // Mirror duplicate base inputs while preserving the focused input/caret.
      document.querySelectorAll('[data-path]').forEach(el => {
        if (el === input || el.dataset.path !== path) return;
        if (el.type === 'checkbox') el.checked = value;
        else el.value = value === null ? '' : el.dataset.levels ? JSON.stringify(value) : el.dataset.percent ? value * 100 : value;
      });
      if (match) {
        const u = state.units[Number(match[1])];
        for (const k of ['attackAllocation', 'defenceAllocation']) {
          const el = document.querySelector(`[data-path="units.${match[1]}.plan.${k}"]`); if (el && el !== input) el.value = u.plan[k];
        }
      }
      if (key === 'mode' || pointMatch) renderEditor();
      results(); save();
    } catch (err) {
      pending.set(path, err.message); clearTimeout(saveTimer);
      $('save-status').textContent = '有无效输入'; input.setAttribute('aria-invalid', 'true');
      error(err.message + '。结果暂保留最近有效值，输入尚未保存。');
    }
  }
  function download(name, data, type) {
    const a = document.createElement('a'), url = URL.createObjectURL(new Blob([data], { type }));
    a.href = url; a.download = name; document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 2000);
  }
  function validExport() { if (pending.size) { toast('请先修正无效输入再导出。'); return false; } return true; }
  document.addEventListener('input', updateInput);
  document.addEventListener('change', e => { if (e.target.tagName === 'SELECT' || e.target.type === 'checkbox') updateInput(e); });
  document.addEventListener('click', e => { const button = e.target.closest('[data-edit-unit]'); if (button) select(button.dataset.editUnit, true); });
  $('selected-unit').addEventListener('change', e => { const id = e.target.value; select(id); if (pending.size) e.target.value = selected; });
  document.querySelectorAll('[data-tab]').forEach(el => el.addEventListener('click', () => setTab(el.dataset.tab)));
  $('curve-legend').addEventListener('change', e => { const id = e.target.dataset.series; if (!id) return; if (e.target.checked) hidden.delete(id); else hidden.add(id); drawCharts(); save(); });
  $('show-all').addEventListener('click', () => { hidden.clear(); renderLegend(); drawCharts(); save(); });
  $('show-selected').addEventListener('click', () => { hidden = new Set(state.units.filter(u => u.id !== selected).map(u => u.id)); renderLegend(); drawCharts(); save(); });
  $('sort-units').addEventListener('change', e => { sort = e.target.value; renderTable(); save(); });
  $('curve-max').addEventListener('input', e => {
    const value = Number(e.target.value);
    if (!e.target.value || !Number.isInteger(value) || value < 1 || value > 20) { e.target.setAttribute('aria-invalid', 'true'); return; }
    e.target.removeAttribute('aria-invalid'); state.curveMax = value; if (calculate()) { drawCharts(); save(); }
  });
  $('apply-levels').addEventListener('click', () => {
    if (!validExport()) return;
    const value = Number($('bulk-levels').value);
    if (!$('bulk-levels').value || !Number.isInteger(value) || value < 0 || value > 20) { toast('全员比较阶段应为 0～20 的整数。'); return; }
    state.units.forEach(u => u.plan.levels = value); if (calculate()) { renderAll(); save(); toast(`全员比较阶段已设为 ${value}。`); }
  });
  $('export-json').addEventListener('click', () => { if (validExport()) download('单位战力方案.json', JSON.stringify(snapshot(), null, 2), 'application/json;charset=utf-8'); });
  $('import-json').addEventListener('click', () => $('import-file').click());
  $('import-file').addEventListener('change', async e => {
    const file = e.target.files[0]; if (!file) return;
    try {
      if (file.size > 1000000) throw new Error('方案文件超过 1 MB');
      const imported = JSON.parse(await file.text()); const next = M.evaluateAll(imported, seed.reference);
      state = imported; lastValidState = M.copy(state); calculated = next; pending.clear(); selected = state.units.some(u => u.id === imported.ui?.selected) ? imported.ui.selected : 'soldier';
      hidden.clear(); renderAll(); save(); toast('方案已导入，全部单位与曲线已更新。');
    } catch (err) { toast('导入失败：' + err.message); }
    e.target.value = '';
  });
  $('download-html').addEventListener('click', () => {
    if (!validExport()) return;
    const clone = document.documentElement.cloneNode(true), savedSeed = M.copy(seed);
    savedSeed.initialState = snapshot(); savedSeed.storageId = 'unit-power-calc-v1-' + Date.now();
    clone.querySelector('#calculator-seed').textContent = JSON.stringify(savedSeed).replace(/</g, '\\u003c');
    clone.querySelector('#chart-tooltip').hidden = true; clone.querySelector('#toast').hidden = true;
    download('单位战力计算器_当前方案.html', '<!doctype html>\n' + clone.outerHTML, 'text/html;charset=utf-8');
    toast('副本包含全部单位、当前输入与固定基准，可离线打开。');
  });
  $('reset').addEventListener('click', () => {
    if ($('reset').dataset.undo === 'yes') { state = resetUndo; $('reset').dataset.undo = ''; $('reset').textContent = '恢复项目初值'; }
    else { resetUndo = M.copy(lastValidState); state = M.copy(seed.defaults); $('reset').dataset.undo = 'yes'; $('reset').textContent = '撤销恢复'; }
    pending.clear(); selected = 'soldier'; hidden.clear(); calculate(); renderAll(); save(); toast('已更新，可用“撤销恢复”取回上一方案。');
  });
  const resize = new ResizeObserver(() => { clearTimeout(drawTimer); drawTimer = setTimeout(drawCharts, 70); });
  resize.observe($('power-chart')); resize.observe($('cost-chart'));
  window.addEventListener('scroll', () => $('chart-tooltip').hidden = true, { passive: true });
  $('snapshot-label').textContent = '项目初值 · ' + seed.date;
  $('source-info').textContent = seed.version + ' · ' + seed.sourceCount + ' 项资源读取校验 · 固定基准士兵 100 分';
  if (calculate()) { renderAll(); $('save-status').textContent = '本地自动保存'; }
  window.UnitPowerCalculator = { getState: snapshot, getResults: () => calculated, getSeed: () => M.copy(seed) };
})();
