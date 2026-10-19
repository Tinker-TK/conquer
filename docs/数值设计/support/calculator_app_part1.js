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
