/* ballsprite power calculator — vanilla JS, no build step, no network. */
'use strict';

const $ = (s, root = document) => root.querySelector(s);
const $$ = (s, root = document) => Array.from(root.querySelectorAll(s));
const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
const fmt = (n, d = 1) => {
  if (n == null || Number.isNaN(Number(n))) return '—';
  const v = Number(n);
  if (Math.abs(v - Math.round(v)) < 1e-9) return String(Math.round(v));
  return v.toFixed(d);
};
const signed = (n, d = 1) => (n > 0 ? '+' : '') + fmt(n, d);
const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
const sum = (arr) => arr.reduce((a, b) => a + b, 0);

const STORAGE_KEY = 'ballsprite_power_calc_balance_v1';
const MODEL_KEYS = ['window', 'cast', 'target_def', 'area_targets', 'melee_uptime',
  'ranged_uptime', 'heal_weight', 'reference_hp', 'reference_output', 'reference_power',
  'energy_value', 'draw_value', 'hp_value'];

const UNIT_BY_ID = Object.fromEntries(DATA.units.map(u => [u.id, u]));
const CARD_BY_ID = Object.fromEntries(DATA.cards.map(c => [c.id, c]));
const RELIC_BY_ID = Object.fromEntries(DATA.relics.map(r => [r.id, r]));
const POTION_BY_ID = Object.fromEntries(DATA.potions.map(p => [p.id, p]));
const KIND_NAMES = DATA.model.kindNames || [];
const KIND_CN = DATA.model.kindCn || {};
const RARITY_CN = { common: '普通', rare: '稀有', boss: '首领', legendary: '传说' };
const ROLE_CN = { core: '核心', support: '辅助', resource: '资源', finisher: '终结', recruit: '征召' };

function kindName(k) { return KIND_NAMES[k] || ('KIND_' + k); }
function kindCn(k) { return KIND_CN[kindName(k)] || kindName(k); }
function rarityPill(r) { return `<span class="pill ${r}">${RARITY_CN[r] || r}</span>`; }
function cardType(c) { return c.category === 'recruit' ? '征召' : (ROLE_CN[c.role] || '效果'); }

function starterDeck() {
  return (DATA.baseline.start_deck_ids || []).map(([id, count]) => ({ id, count }));
}

let state = {
  tab: 'overview', deck: starterDeck(), relics: [], potions: [],
  edits: { units: {}, cards: {}, relics: {}, potions: {} },
  model: JSON.parse(JSON.stringify(DATA.model)),
  compare: { A: null, B: null }, search: '',
  filter: { units: 'all', cards: 'all', relics: 'all', potions: 'all', cost: 'all', act: 'all' },
  sort: { units: 'power', cards: 'power', relics: 'power', potions: 'power' },
  showTarget: true,
};

function save() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({
      version: DATA.meta.version, deck: state.deck, relics: state.relics,
      potions: state.potions, edits: state.edits, model: state.model,
      compare: state.compare, showTarget: state.showTarget,
    }));
  } catch (e) { /* ignore quota */ }
}
function load() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return;
    const s = JSON.parse(raw);
    if (!s || s.version !== DATA.meta.version) return;
    if (Array.isArray(s.deck)) state.deck = s.deck;
    if (Array.isArray(s.relics)) state.relics = s.relics;
    if (Array.isArray(s.potions)) state.potions = s.potions;
    if (s.edits) state.edits = s.edits;
    if (s.model) {
      for (const k of MODEL_KEYS) if (Number.isFinite(s.model[k])) state.model[k] = s.model[k];
      if (s.model.cardCoef) Object.assign(state.model.cardCoef, s.model.cardCoef);
    }
    if (s.compare) state.compare = s.compare;
    if (typeof s.showTarget === 'boolean') state.showTarget = s.showTarget;
  } catch (e) { /* ignore broken save */ }
}

/* ---------------- unit model ---------------- */
function unitView(u) {
  const e = state.edits.units[u.id] || {};
  return {
    ...u,
    hp: e.hp != null ? Number(e.hp) : u.hp,
    attack: e.attack != null ? Number(e.attack) : u.attack,
    defence: e.defence != null ? Number(e.defence) : u.defence,
    cost: e.cost != null ? Number(e.cost) : u.cost,
    dodge: e.dodge != null ? Number(e.dodge) : u.dodge,
  };
}

function simulateUnit(u, level = 0, model = state.model) {
  const attack = u.attack + (level > 0 ? (u.upgrade_points || 0) : 0);
  const branch = u.id === 'soldier' && level > 0 ? 'missile' : null;
  const skills = (u.skills || []).filter(s => !branch || !s.branch || s.branch === branch)
    .filter(s => Array.isArray(s.unlock) ? s.unlock.includes(level) : level >= (s.unlock || 0));
  const active = skills.filter(s => !['passive', 'aura_passive', 'combo_passive', 'stealth_passive'].includes(s.kind)
    && (s.rate > 0 || s.kind === 'heal' || s.kind === 'summon'));
  const ranged = active.some(s => s.kind !== 'heal' && s.range >= 250);
  const uptime = ranged ? model.ranged_uptime : model.melee_uptime;
  let t = 0, dmg = 0, heal = 0, summonBonus = 0, casts = 0;
  const ready = {};
  for (const s of active) ready[s.id || s.name] = 0;
  while (t < model.window - 1e-9 && casts < 200) {
    const avail = active.filter(s => (ready[s.id || s.name] || 0) <= t + 1e-9);
    if (!avail.length) {
      const next = Math.min(...active.map(s => ready[s.id || s.name] || 0));
      t = Number.isFinite(next) ? next : model.window;
      continue;
    }
    avail.sort((a, b) => (b.priority - a.priority) || String(a.id || a.name).localeCompare(String(b.id || b.name)));
    const s = avail[0];
    const start = t;
    const end = start + model.cast;
    ready[s.id || s.name] = start + Math.max(s.cooldown || 1, model.cast);
    casts++;
    if (end <= model.window) {
      if (s.kind === 'heal') heal += attack * (s.rate || 1);
      else if (s.kind === 'summon') { if (!summonBonus) summonBonus = 50; }
      else {
        const perHit = Math.max(Math.floor(attack * (s.rate || 1)) - Math.ceil(model.target_def / Math.max(1, s.hits || 1)), 1);
        const targets = (s.kind === 'area' || s.kind === 'dash') ? model.area_targets : 1;
        dmg += perHit * (s.hits || 1) * targets;
      }
    }
    t = end;
  }
  const dps = dmg / model.window * uptime;
  const hps = heal / model.window * uptime;
  const output = dps + model.heal_weight * hps;
  const ehp = u.hp * 15 / Math.max(15 - u.defence, 1) / (1 - u.dodge * 0.7);
  const bodyPower = model.reference_power * Math.sqrt((ehp / model.reference_hp) * (output / model.reference_output));
  const power = bodyPower + summonBonus;
  return { ehp, dps, hps, output, power, bodyPower, uptime, casts, summonBonus };
}

function soldierBaseline() { return simulateUnit(unitView(UNIT_BY_ID.soldier), 0); }
function unitPower(u, level = 0) { return simulateUnit(unitView(u), level).power; }
function trainedPower(u) {
  const v = unitView(u);
  const l1 = simulateUnit(v, 1).power;
  const l0 = simulateUnit(v, 0).power;
  if (l1 >= l0) return l1;
  // Conservative floor: some upgraded skills carry special effects this model
  // does not price (chain lightning, frost slow, ...). Price the points only.
  return simulateUnit({ ...v, attack: v.attack + (u.upgrade_points || 0) }, 0).power;
}
function unitTargetPower(u) {
  if (!u.target) return null;
  const v = { ...unitView(u), hp: u.target.hp, attack: u.target.attack, defence: u.target.defence, cost: u.target.cost };
  return simulateUnit(v, 0).power;
}

/* ---------------- card model ---------------- */
function cardBudget(cost) { return cost <= 0 ? 100 : 100 * Math.pow(cost, 0.8); }

function effectValue(e, upgraded = false, model = state.model) {
  const k = kindName(e.kind == null ? 0 : e.kind);
  const coef = model.cardCoef || {};
  let a = Number(e.amount || 0) + (upgraded ? Number(e.upgrade_amount || 0) : 0);
  let sec = Number(e.status_seconds || 0) + (upgraded ? Number(e.upgrade_status_seconds || 0) : 0);
  let rounds = Number(e.lasting_rounds == null ? 2 : e.lasting_rounds) + (upgraded ? Number(e.upgrade_lasting_rounds || 0) : 0);
  const radius = Number(e.radius || 0);
  switch (k) {
    case 'ATTACK_UP': return a * coef.ATTACK_UP;
    case 'DEFENCE_UP': return a * coef.DEFENCE_UP;
    case 'HEAL_PERCENT': return a * coef.HEAL_PERCENT;
    case 'POISON_ON_HIT': return a * coef.POISON_ON_HIT;
    case 'DEATH_EXPLOSION': return a * coef.DEATH_EXPLOSION * (1 + Math.max(0, radius - 120) / 400);
    case 'COPY_ALLY': return coef.COPY_ALLY;
    case 'DAMAGE_ZONE': return a * coef.DAMAGE_ZONE;
    case 'MUD_ZONE': return coef.MUD_ZONE + 15 * Math.max(0, rounds - 2);
    case 'DRAW': return a * coef.DRAW;
    case 'LOCK_DRAW': return coef.LOCK_DRAW;
    case 'PAY_HP': return a * coef.PAY_HP;
    case 'ENERGY_EACH_ROUND': return a * coef.ENERGY_EACH_ROUND;
    case 'DEATH_ATTACK_AURA': return a * coef.DEATH_ATTACK_AURA;
    case 'RANDOM_PLAY': return a * coef.RANDOM_PLAY;
    case 'RECALL_ALLY': return coef.RECALL_ALLY;
    case 'GAIN_ENERGY': return a * coef.GAIN_ENERGY;
    case 'MAX_HP_UP': return a * coef.MAX_HP_UP;
    case 'RETAIN_ALLIES': return coef.RETAIN_ALLIES - 15 * a;
    case 'WEAKNESS': return a * coef.WEAKNESS;
    case 'VULNERABILITY': return a * coef.VULNERABILITY;
    case 'DEFENCE_DOWN': return a * coef.DEFENCE_DOWN;
    case 'PARALYSIS': return a * coef.PARALYSIS;
    case 'CONVERT_ENEMY': return coef.CONVERT_ENEMY;
    case 'FRENZY': return coef.FRENZY;
    case 'RETREAT_DRAW': return coef.RETREAT_DRAW + 15 * a;
    case 'DIVERSE_ARMY': return coef.DIVERSE_ARMY + 20 * a;
    case 'KEEP_DISTANCE': return coef.KEEP_DISTANCE + 1.5 * (a - 100);
    case 'JUDGER': return coef.JUDGER + 10 * a;
    case 'COMRADE': return coef.COMRADE;
    case 'TEMPORARY_UPGRADE': return coef.TEMPORARY_UPGRADE;
    case 'BLEED': return a * Math.max(1, sec) * coef.BLEED;
    case 'HEALING_BAN': return coef.HEALING_BAN + 2.5 * Math.max(1, sec);
    case 'ARMOR_SHRED': return coef.ARMOR_SHRED + 15 * Math.max(0, a - 1);
    case 'SLEEP': return coef.SLEEP + 4 * Math.max(1, sec);
    case 'SHIELD': return a * coef.SHIELD;
    case 'OVERFLOW_SHIELD': return coef.OVERFLOW_SHIELD;
    case 'MISSING_HEALTH_SHIELD': return a * coef.MISSING_HEALTH_SHIELD;
    case 'KNOCKBACK_IMMUNITY': return coef.KNOCKBACK_IMMUNITY;
    case 'TUTOR_UNIT': return coef.TUTOR_UNIT;
    case 'DISCARD_DRAW': return a * coef.DISCARD_DRAW;
    case 'SACRIFICE': return coef.SACRIFICE + 45 * (4 / Math.max(1, a));
    case 'RESURRECT': return coef.RESURRECT;
    case 'DEATH_DRAW': return coef.DEATH_DRAW;
    case 'ARMY_ATTACK': return a * coef.ARMY_ATTACK;
    case 'ARMY_DEFENCE': return a * coef.ARMY_DEFENCE;
    case 'ARMY_SPEED': return a * coef.ARMY_SPEED;
    case 'BATTLE_STANDARD': return 40 * a;
    case 'SPIKE_TRAP': return 30 + a * coef.SPIKE_TRAP;
    case 'TRANSCRIBE': return coef.TRANSCRIBE + (upgraded && e.upgrade_upgrades_drawn_cards ? 20 : 0);
    case 'REFORMATION': return coef.REFORMATION;
    case 'HAND_DISCOUNT': return a * coef.HAND_DISCOUNT;
    case 'OVERDRAFT': return a * coef.OVERDRAFT - 15 * Number(e.next_round_penalty || 3);
    case 'THRIFT': return coef.THRIFT;
    default: return 0;
  }
}

function cardView(c) {
  const e = state.edits.cards[c.id] || {};
  return { ...c, cost: e.cost != null ? Number(e.cost) : c.cost, effects: e.effects || c.effects };
}
function cardPower(c) {
  if (c.category === 'recruit') {
    const u = UNIT_BY_ID[c.unit_id];
    return u ? unitPower(u) : 0;
  }
  return sum((c.effects || []).map(e => effectValue(e, false)));
}
function cardUpgradePower(c) {
  if (c.category === 'recruit') {
    const u = UNIT_BY_ID[c.unit_id];
    return u ? trainedPower(u) : 0;
  }
  return sum((c.effects || []).map(e => effectValue(e, true)));
}
function cardStats(c) {
  const v = cardView(c);
  const p = cardPower(v), up = cardUpgradePower(v);
  const cost = Math.max(0, v.cost), budget = cardBudget(cost);
  const upgradedCost = Math.max(0, cost + (v.upgrade_cost || 0));
  const upgradedBudget = cardBudget(upgradedCost);
  const targetCost = v.target_cost == null ? cost : Math.max(0, v.target_cost);
  const targetBudget = cardBudget(targetCost);
  return {
    power: p, upgradePower: up, upgradeDelta: up - p, cost, targetCost: v.target_cost, budget,
    ratio: budget ? p / budget : null, targetRatio: targetBudget ? p / targetBudget : null,
    upgradedCost, upgradedBudget,
    upgradedRatio: upgradedBudget ? up / upgradedBudget : null,
    perCost: cost ? p / cost : null,
  };
}

function relicPower(r) {
  const e = state.edits.relics[r.id];
  return e && e.power != null ? Number(e.power) : Number(r.power || 0);
}
function potionPower(p) {
  const e = state.edits.potions[p.id];
  return e && e.power != null ? Number(e.power) : Number(p.power || 0);
}

/* ---------------- build summary ---------------- */
function deckEntries() {
  const map = new Map();
  for (const d of state.deck) {
    if (!CARD_BY_ID[d.id] || d.count <= 0) continue;
    map.set(d.id, (map.get(d.id) || 0) + Number(d.count));
  }
  return Array.from(map.entries()).map(([id, count]) => ({ id, count, card: CARD_BY_ID[id] }));
}
function deckCards() {
  const out = [];
  for (const e of deckEntries()) for (let i = 0; i < e.count; i++) out.push(cardView(e.card));
  return out;
}
function buildSummary() {
  const cards = deckCards();
  const recruits = cards.filter(c => c.category === 'recruit');
  const effects = cards.filter(c => c.category === 'effect');
  const deckPower = sum(cards.map(cardPower));
  const unitPowerSum = sum(recruits.map(cardPower));
  const effectPower = sum(effects.map(cardPower));
  const relicPowerSum = sum(state.relics.map(id => RELIC_BY_ID[id]).filter(Boolean).map(relicPower));
  const potionPowerSum = sum(state.potions.map(id => POTION_BY_ID[id]).filter(Boolean).map(potionPower));
  const total = deckPower + relicPowerSum + potionPowerSum;
  const totalCost = sum(cards.map(c => cardView(c).cost));
  const tags = {};
  for (const c of cards) for (const t of (c.tags || [])) tags[t] = (tags[t] || 0) + 1;
  return {
    cards, recruits, effects, deckPower, unitPowerSum, effectPower,
    relicPowerSum, potionPowerSum, total, totalCost,
    avgCost: cards.length ? totalCost / cards.length : 0,
    efficiency: totalCost ? deckPower / totalCost : 0,
    tags, recruitRatio: cards.length ? recruits.length / cards.length : 0,
    over: effects.filter(c => { const s = cardStats(c); return s.ratio != null && s.ratio > 1.3; }),
    under: effects.filter(c => { const s = cardStats(c); return s.ratio != null && s.ratio < 0.45 && c.role !== 'support'; }),
  };
}
function warnings(s) {
  const out = [];
  if (!s.recruits.length) out.push(['bad', '没有征召牌', '卡组无法召唤单位。至少放 3 张征召牌。']);
  else if (s.recruitRatio < 0.3) out.push(['warn', '征召牌比例偏低', `当前 ${(s.recruitRatio * 100).toFixed(0)}%，建议 35–50%。`]);
  if (s.avgCost > 2.2) out.push(['warn', '平均费用偏高', `当前 ${s.avgCost.toFixed(2)}，建议 1.6–2.0；高费牌容易卡手。`]);
  if (s.cards.length > 30) out.push(['warn', '卡组过厚', `${s.cards.length} 张，关键牌上手率会下降。`]);
  if (s.cards.length < 10) out.push(['warn', '卡组过薄', `${s.cards.length} 张，抽牌/消耗后容易断档。`]);
  if (s.over.length) out.push(['warn', `有 ${s.over.length} 张牌超出预算`, s.over.map(c => c.name).join('、') + '。优先实测，不要直接砍。']);
  if (s.under.length) out.push(['warn', `有 ${s.under.length} 张牌低于预算`, s.under.map(c => c.name).join('、') + '。检查是否费用过高。']);
  if (state.relics.length > 10) out.push(['warn', '遗物过多', '一局目标 8–10 件；超过 10 件会让触发提示刷屏。']);
  if (state.potions.length > 3) out.push(['warn', '药水超过 3 格', '需要替换或扩展腰带。']);
  if (!out.length) out.push(['ok', '构筑看起来健康', '没有触发明显的预算/比例警告。']);
  return out;
}
function snapshot() {
  return {
    at: new Date().toISOString(), summary: buildSummary(),
    deck: JSON.parse(JSON.stringify(state.deck)), relics: [...state.relics], potions: [...state.potions],
    edits: JSON.parse(JSON.stringify(state.edits)), model: JSON.parse(JSON.stringify(state.model)),
  };
}

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
