/* UNIT-POWER-CALC v1: deterministic comparison model, no gameplay mutations. */
(function (host) {
  'use strict';
  const EPS = 1e-9;
  const copy = x => JSON.parse(JSON.stringify(x));
  const number = (x, name, min, max, integer = false) => {
    if (!Number.isFinite(x) || x < min || x > max || (integer && !Number.isInteger(x)))
      throw new Error(`${name}应为${integer ? '整数' : '数值'}，范围 ${min}～${max}`);
  };
  const levels = (value, name) => {
    if (Array.isArray(value)) {
      if (value.length > 100) throw new Error(`${name}最多配置100个等级`);
      value.forEach(level => number(level, name, 0, 99, true));
    } else {
      // 旧计算方案的整数保留原先的最低等级规则，新项目初值使用数组。
      number(value, name, 0, 99, true);
    }
  };
  const activeAt = (value, level) => Array.isArray(value) ? value.includes(level) : value <= level;
  const passive = s => s.kind.endsWith('_passive');

  function validate(state, ids) {
    if (!state || state.schema !== 'unit-power-calculator/v1') throw new Error('方案格式或版本不匹配');
    if (!Array.isArray(state.units) || state.units.length !== ids.length) throw new Error('方案必须包含全部现有单位');
    const actual = state.units.map(u => u.id);
    if (new Set(actual).size !== ids.length || ids.some(id => !actual.includes(id))) throw new Error('单位 ID 缺失、重复或不匹配');
    const m = state.model;
    if (!m) throw new Error('缺少计算标准');
    for (const [k, lo, hi] of [
      ['window', 1, 120], ['incoming', 1, 99999], ['targetDefence', 0, 99999],
      ['eligible', 0, 1], ['targetDodge', 0, 1], ['meleeUptime', 0, 1], ['rangedUptime', 0, 1],
      ['areaTargets', 1, 50], ['pierceTargets', 1, 50], ['healRealization', 0, 1],
      ['lifestealRealization', 0, 1], ['healWeight', 0, 5], ['summonRealization', 0, 1],
      ['swordFarShare', 0, 1], ['costBonus', 0, 1]
    ]) number(m[k], k, lo, hi);
    number(m.comboTargetHp ?? 100, '连击参考目标生命', 1, 10000000);
    number(state.curveMax, '曲线阶段上限', 1, 20, true);
    for (const u of state.units) {
      if (typeof u.name !== 'string' || !u.name.trim() || u.name.length > 60) throw new Error('单位名称应为 1～60 字');
      if (!['team_a', 'team_b'].includes(u.team)) throw new Error('单位阵营无效');
      for (const [k, lo, hi] of [
        ['hp', 1, 10000000], ['attack', 0, 100000], ['defence', 0, 100000], ['cost', 0, 999],
        ['dodge', 0, 1], ['counterNetDps', -100000, 100000], ['baseLevel', 0, 99],
        ['gameMax', 0, 99], ['upgradePoints', 0, 999], ['departures', 0, 999]
      ]) number(u[k], `${u.name} ${k}`, lo, hi, !['dodge', 'counterNetDps'].includes(k));
      if (u.uptime !== null) number(u.uptime, `${u.name}输出在线率`, 0, 1);
      if (typeof u.hasCounter !== 'boolean') throw new Error('反击开关无效');
      levels(u.counterUnlock, '反击生效等级');
      const p = u.plan;
      if (!p || !['training', 'custom'].includes(p.mode)) throw new Error('成长模式无效');
      if (p.mode === 'training' && u.team !== 'team_a') throw new Error('敌方单位请使用自定义成长');
      for (const k of ['levels', 'attackAllocation', 'defenceAllocation']) number(p[k], k, 0, k === 'levels' ? 20 : 999, true);
      if (p.mode === 'training' && p.attackAllocation + p.defenceAllocation !== u.upgradePoints)
        throw new Error(`${u.name}每次训练分配的攻击＋防御必须等于 ${u.upgradePoints} 能力点`);
      for (const k of ['hpStep', 'attackStep', 'defenceStep', 'hpBuff', 'attackBuff', 'defenceBuff']) number(p[k], k, -100000, 100000, true);
      for (const k of ['hpGrowth', 'attackGrowth', 'defenceGrowth']) number(p[k], k, -0.9, 2);
      for (const k of ['dodgeStep', 'dodgeBuff']) number(p[k], k, -1, 1);
      for (const k of ['costStep', 'costBuff']) number(p[k], k, -999, 999, true);
      number(p.buffEnergy, '额外强化总能量', 0, 999);
      number(p.cooldownFactor, '强化冷却系数', 0.1, 10);
      number(p.animationFactor, '强化动作系数', 0.1, 10);
      number(p.outputFactor, '强化输出系数', 0, 10);
      if (!Array.isArray(u.skills) || u.skills.length > 20) throw new Error('每个单位最多 20 个技能');
      for (const s of u.skills) {
        if (!['normal', 'projectile', 'area', 'dash', 'lifesteal', 'heal', 'summon','teleport','combo_passive','aura_passive','stealth_passive'].includes(s.kind)) throw new Error('技能类型无效');
        if (passive(s)) {
          levels(s.unlock, '被动生效等级');
          if (s.kind === 'combo_passive') number(s.attack_bonus_per_hit, '连击每命中攻击增量', 0, 999, true);
          if (s.kind === 'aura_passive') {
            number(s.aura_attack_bonus, '光环攻击增量', 0, 999, true); number(s.aura_radius, '光环半径', 1, 2000);
            if (typeof s.aura_include_caster !== 'boolean') throw new Error('光环包括自身开关无效');
          }
          if (s.kind === 'stealth_passive') {
            number(s.stealth_health_percent, '隐身触发生命百分比', 1, 100); number(s.stealth_duration, '隐身时长', .1, 60);
          }
          continue;
        }
        number(s.rate, '技能倍率', 0, 100); number(s.cooldown, '技能冷却', 0.05, 120);
        number(s.duration, '技能占用时间', 0.05, 120); number(s.priority, '技能优先级', -999, 999, true);
        number(s.range, '技能射程', 0, 99999); levels(s.unlock, '技能生效等级');
        if (typeof s.basic !== 'boolean' || typeof s.straight !== 'boolean') throw new Error('技能攻击标记无效');
        number(s.pierce, '穿透上限', 1, 99, true);
        if (s.targets !== null) number(s.targets, '平均命中目标', 1, 50);
        if (!Array.isArray(s.offsets) || !s.offsets.length || s.offsets.length > 100) throw new Error('命中时间应至少有一项');
        s.offsets.forEach(t => number(t, '命中时间', 0, Math.max(0, s.duration - 0.000001)));
        if (s.kind === 'summon') {
          if (!ids.includes(s.child)) throw new Error('召唤目标不在单位表内');
          number(s.summonDelay, '召唤延迟', 0, 120);
        }
      }
      if (u.id === 'soldier') {
        if (!u.sword) throw new Error('缺少士兵剑矢配置');
        number(u.sword.range, '剑矢射程', 1, 99999);
        number(u.sword.duration, '剑矢动画占时', 0.05, 120);
        number(u.sword.offset, '剑矢发箭时间', 0, u.sword.duration - 0.000001);
      }
    }
    return true;
  }

  function atStage(unit, stage) {
    const u = copy(unit), p = unit.plan;
    if (stage === 0) return u;
    const training = p.mode === 'training';
    const value = (base, growth, step, buff, min) => Math.max(min, Math.floor(base * Math.pow(1 + growth, stage) + stage * step + buff + EPS));
    u.hp = value(unit.hp, training ? 0 : p.hpGrowth, training ? 0 : p.hpStep, p.hpBuff, 1);
    u.attack = value(unit.attack, training ? 0 : p.attackGrowth, training ? p.attackAllocation : p.attackStep, p.attackBuff, 0);
    u.defence = value(unit.defence, training ? 0 : p.defenceGrowth, training ? p.defenceAllocation : p.defenceStep, p.defenceBuff, 0);
    u.dodge = Math.max(0, Math.min(1, unit.dodge + (training ? 0 : stage * p.dodgeStep) + p.dodgeBuff));
    u.cost = Math.max(0, unit.cost + (training ? 0 : stage * p.costStep) + p.costBuff);
    u.baseLevel = unit.baseLevel + stage;
    return u;
  }

  function targets(skill, model) {
    if (skill.targets !== null) return skill.targets;
    if (['area', 'dash'].includes(skill.kind)) return model.areaTargets;
    if (skill.kind === 'projectile' && skill.straight && skill.pierce > 1) return Math.min(skill.pierce, model.pierceTargets);
    return 1;
  }

  function schedule(unit, model, stage, far = false) {
    const p = unit.plan, upgraded = stage > 0;
    const active = unit.skills.filter(s => activeAt(s.unlock, unit.baseLevel));
    const passives = active.filter(passive);
    const auraAttack = unit.team === 'team_a' ? Math.max(0, ...passives.filter(s => s.kind === 'aura_passive' && s.aura_include_caster).map(s => s.aura_attack_bonus)) : 0;
    const comboBonus = Math.max(0, ...passives.filter(s => s.kind === 'combo_passive').map(s => s.attack_bonus_per_hit));
    let chain = 0, remainingHp = model.comboTargetHp ?? 100, chainResets = 0;
    let skills = active.filter(s => !passive(s)).map(copy);
    const sword = unit.id === 'soldier' && unit.team === 'team_a' && unit.baseLevel >= 1;
    if (far && sword) {
      skills = skills.filter(s => s.basic || s.range >= unit.sword.range || ['heal', 'summon'].includes(s.kind));
      for (const s of skills.filter(s => s.basic)) {
        s.kind = 'projectile'; s.range = unit.sword.range; s.duration = unit.sword.duration;
        s.offsets = [unit.sword.offset]; s.targets = 1;
      }
    }
    const cdFactor = upgraded ? p.cooldownFactor : 1;
    const animationFactor = upgraded ? p.animationFactor : 1;
    for (const s of skills) {
      s.cooldown *= cdFactor;
      // Manual dash duration includes travel, not an ordinary cast animation.
      if (s.kind !== 'dash') { s.duration *= animationFactor; s.offsets = s.offsets.map(t => t * animationFactor); }
    }
    const ranged = skills.some(s => !['heal', 'summon', 'dash'].includes(s.kind) && s.range >= 250);
    const uptime = unit.uptime === null ? (ranged ? model.rangedUptime : model.meleeUptime) : unit.uptime;
    const order = skills.map((_, i) => i).sort((a, b) => skills[b].priority - skills[a].priority || a - b);
    const ready = skills.map(() => 0), trace = [], births = [];
    const stats = skills.map(s => ({ name: s.name, casts: 0, hits: 0, damage: 0, healing: 0 }));
    let t = 0, damage = 0, healing = 0;
    while (skills.length && t < model.window - EPS) {
      const i = order.find(i => ready[i] <= t + EPS);
      if (i === undefined) { t = Math.min(...ready); continue; }
      const s = skills[i], start = t, end = t + s.duration;
      ready[i] = start + s.cooldown; stats[i].casts++;
      const hits = [];
      for (const offset of s.offsets) {
        const time = start + offset;
        if (time >= model.window - EPS) continue;
        if (s.kind === 'summon') {
          const born = time + s.summonDelay;
          if (born < model.window) births.push({ child: s.child, time: born });
          hits.push({ time, born }); continue;
        }
        let dmg = 0, heal = 0;
        const attackUsed = unit.attack + auraAttack + chain * comboBonus;
        if (s.kind === 'heal') heal = Math.floor(attackUsed * s.rate + EPS) * model.healRealization;
        else {
          dmg = Math.max(Math.floor(attackUsed * s.rate + EPS) - model.targetDefence, 1);
          if (s.kind !== 'projectile') dmg *= 1 - model.targetDodge;
          dmg *= targets(s, model);
          if (s.kind === 'lifesteal') heal = dmg * model.lifestealRealization;
          if (comboBonus) {
            remainingHp -= dmg / targets(s, model);
            if (remainingHp <= EPS) { remainingHp = model.comboTargetHp ?? 100; chain = 0; chainResets++; }
            else chain += s.kind === 'projectile' ? 1 : 1 - model.targetDodge;
          }
        }
        damage += dmg; healing += heal; stats[i].hits++; stats[i].damage += dmg; stats[i].healing += heal;
        hits.push({ time, damage: dmg, healing: heal, attackUsed });
      }
      trace.push({ id: s.id, name: s.name, start, end, cooldown: s.cooldown, hits }); t = end;
      if (trace.length > 10000) throw new Error('技能排程过长，请检查冷却与动作时间');
    }
    const outputFactor = upgraded ? p.outputFactor : 1;
    const activeCounter = unit.hasCounter && activeAt(unit.counterUnlock, unit.baseLevel);
    const counter = activeCounter ? unit.counterNetDps : 0;
    const dps = damage / model.window * uptime * outputFactor + counter;
    if (dps < 0) throw new Error(`${unit.name}反击净收益使总 DPS 小于零，请修正`);
    const hps = healing / model.window * uptime * outputFactor;
    const unpricedEffects = [];
    for (const s of passives) {
      if (s.kind === 'stealth_passive') unpricedEffects.push(`隐身：生命低于${s.stealth_health_percent}%持续${s.stealth_duration}秒，生存/索敌收益未折分`);
      if (s.kind === 'aura_passive') unpricedEffects.push(`光环：范围${s.aura_radius}、攻击+${s.aura_attack_bonus}；${s.aura_include_caster ? '自身收益已计入，' : ''}其他友军收益未折分`);
    }
    if (skills.some(s => s.kind === 'teleport')) unpricedEffects.push('瞬移接敌和后排索敌收益未折分');
    if (unit.id === 'knight' && unit.team === 'team_a') unpricedEffects.push(`征召抽${unit.baseLevel >= 1 ? 2 : 1}张牌，牌组收益未折分`);
    return { dps, hps, output: dps + model.healWeight * hps, uptime, trace, stats, births, passives, auraAttack, comboBonus, chainResets, unpricedEffects };
  }

  function output(unit, model, stage) {
    const near = schedule(unit, model, stage, false);
    if (unit.id !== 'soldier' || unit.team !== 'team_a' || unit.baseLevel < 1 || !model.swordFarShare) return near;
    const far = schedule(unit, model, stage, true), q = model.swordFarShare;
    return { ...near, dps: near.dps * (1 - q) + far.dps * q, hps: near.hps * (1 - q) + far.hps * q,
      output: near.output * (1 - q) + far.output * q, swordMix: { near, far, share: q } };
  }

  function ehp(unit, model) {
    const dodge = unit.hasCounter && activeAt(unit.counterUnlock, unit.baseLevel) ? unit.dodge : 0;
    const denominator = 1 - dodge * model.eligible;
    if (denominator <= EPS) throw new Error(`${unit.name}闪避有效占比达到100%，有效生命无上限；请降低参考占比或闪避率`);
    return unit.hp * model.incoming / Math.max(model.incoming - unit.defence, 1) / denominator;
  }

  function evaluateAll(state, reference) {
    validate(state, reference.unitIds);
    const m = state.model, baseline = output(reference.soldier, m, 0), baseEhp = ehp(reference.soldier, m);
    if (baseline.output <= 0) throw new Error('当前比较标准下基准士兵输出为零，请调整对手闪避或治疗权重');
    const norm = r => 100 * Math.sqrt(r.ehp / baseEhp * r.output / baseline.output);
    const base = new Map(), result = new Map();
    const phase = (u, n) => {
      const current = atStage(u, n), out = output(current, m, n);
      const r = { ...out, ehp: ehp(current, m), attributes: current, stage: n };
      r.bodyPower = norm(r); return r;
    };
    for (const u of state.units) base.set(u.id, phase(u, 0));
    function complete(u, n) {
      const r = n === 0 ? { ...base.get(u.id) } : phase(u, n);
      r.summonPower = 0; r.summons = [];
      for (const birth of r.births) {
        const child = base.get(birth.child);
        if (!child) throw new Error('召唤目标不存在');
        if (child.attributes.team !== u.team) throw new Error(`${u.name}与召唤单位阵营不一致`);
        if (child.births.length) throw new Error('暂不支持嵌套召唤，请更换召唤目标');
        const weight = (m.window - birth.time) / m.window * m.summonRealization;
        const contribution = weight * child.bodyPower;
        r.summonPower += contribution; r.summons.push({ ...birth, weight, contribution });
      }
      r.power = r.bodyPower + r.summonPower;
      r.recruitCost = r.attributes.cost + u.departures;
      r.totalEnergy = r.recruitCost + (n > 0 ? u.plan.buffEnergy : 0);
      r.perCost = r.recruitCost > 0 ? r.power / r.recruitCost : null;
      r.perTotalEnergy = r.totalEnergy > 0 ? r.power / r.totalEnergy : null;
      r.budget = r.recruitCost > 0 ? 100 * r.recruitCost * (1 + m.costBonus * (r.recruitCost - 1)) : null;
      r.budgetRatio = r.budget ? r.power / r.budget : null;
      r.forecast = n > 0 && (u.plan.mode !== 'training' || u.baseLevel + n > u.gameMax);
      return r;
    }
    const curveMax = Math.max(state.curveMax, ...state.units.map(u => u.plan.levels));
    for (const u of state.units) {
      const current = complete(u, 0), upgraded = complete(u, u.plan.levels);
      const curve = Array.from({ length: curveMax + 1 }, (_, n) => complete(u, n));
      result.set(u.id, { current, upgraded, curve, gain: current.power ? upgraded.power / current.power - 1 : null });
    }
    return { result, baseline: { ehp: baseEhp, output: baseline.output, dps: baseline.dps }, version: 'UNIT-POWER-CALC-v2' };
  }

  host.UnitPowerModel = { copy, validate, atStage, schedule, evaluateAll };
  if (typeof module !== 'undefined' && module.exports) module.exports = host.UnitPowerModel;
})(typeof window !== 'undefined' ? window : globalThis);
