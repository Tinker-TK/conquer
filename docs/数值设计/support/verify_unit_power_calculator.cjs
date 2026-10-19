/* Meaningful model and browser checks for the editable offline calculator. */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { pathToFileURL } = require('node:url');
const { createRequire } = require('node:module');
const assert = require('node:assert/strict');
const M = require('./unit_power_calculator_model.js');
const root = path.resolve(__dirname, '../../..');
const out = path.resolve(__dirname, '..');
const seed = JSON.parse(fs.readFileSync(path.join(__dirname, 'unit_power_calculator_seed.json'), 'utf8'));
const historical = JSON.parse(fs.readFileSync(path.join(out, '单位战力_计算结果.json'), 'utf8'));
const checks = [];
function check(name, fn) { fn(); checks.push(name); }
const near = (a, b) => assert(Math.abs(a - b) < 1e-7, `${a} != ${b}`);
const evaluate = state => M.evaluateAll(state, seed.reference);
const state = () => ({...M.copy(seed.defaults),curveMax:5}); // Explore exact-level gaps beyond the one real training step.
const find = (s, id) => s.units.find(u => u.id === id);
let defaults = evaluate(state());
check('report and calculator contain the same current 21-unit resource snapshot', () => {
  assert.equal(defaults.result.size, 21);
  assert.equal(historical.units.length, 21);
  assert.equal(historical.sourceRevision,seed.sourceRevision);
  for (const u of historical.units) {
    near(defaults.result.get(u.id).current.power,u.result.total_power);
    near(defaults.result.get(u.id).upgraded.power,u.upgraded_result.power);
  }
});
check('soldier 100 and independently checked 12-second damage', () => {
  const r = defaults.result.get('soldier').current;
  near(r.power, 100); near(r.dps, 103 / 12 * .8); near(r.ehp, 150);
});
check('untrained archer only fires its enabled normal shot: 12 hits of 7 damage',()=>{
  const r=defaults.result.get('archer').current;
  near(r.dps,12*7/12);
  assert(r.trace.every(t=>t.id.endsWith('/archer_arrow_attack.tres')));
  near(r.power,100*Math.sqrt((80*15/13)/150*7/(103/12*.8)));
});
check('passives do not take casting time; self aura and exact level swaps affect output',()=>{
  const s=state(),u=find(s,'knight_templar');
  const withAura=evaluate(s).result.get(u.id).upgraded;
  assert.equal(withAura.auraAttack,2);
  const aura=u.skills.find(k=>k.kind==='aura_passive');aura.aura_include_caster=false;
  const without=evaluate(s).result.get(u.id).upgraded;
  assert(withAura.dps>without.dps);assert(withAura.trace.every(t=>t.id!==aura.id));
  const ax=defaults.result.get('armored_axeman');
  assert(ax.current.trace.some(t=>t.id.endsWith('/armored_examan_chop_attack.tres')));
  assert(ax.upgraded.trace.every(t=>!t.id.endsWith('/armored_examan_chop_attack.tres')));
});
check('consecutive attack applies from the next hit and clears on target death',()=>{
  const s=state(),u=find(s,'swords_man');u.skills=[u.skills.find(k=>k.kind==='combo_passive'),{...M.copy(find(s,'soldier').skills[0]),rate:1,offsets:[0],duration:.1,cooldown:1,unlock:[0,1]}];
  u.hp=80;u.attack=10;s.model.comboTargetHp=20;
  const r=evaluate(s).result.get(u.id).current, hits=r.trace.flatMap(t=>t.hits);
  assert.deepEqual(hits.slice(0,5).map(h=>h.attackUsed),[10,11,12,13,10]);
  assert(r.chainResets>0);assert(r.trace.every(t=>!t.id.endsWith('/swords_man_consecutive_attack.tres')));
});
check('stealth and deployment draw are disclosed instead of invented numerical bonuses',()=>{
  const s=state(),u=find(s,'were_wolf'),before=evaluate(s).result.get(u.id).current;
  u.skills.find(k=>k.kind==='stealth_passive').stealth_duration=10;
  const after=evaluate(s).result.get(u.id).current;
  near(before.power,after.power);assert(after.unpricedEffects.some(v=>v.includes('10秒')));
  assert(defaults.result.get('knight').current.unpricedEffects.some(v=>v.includes('抽1张')));
  assert(defaults.result.get('knight').upgraded.unpricedEffects.some(v=>v.includes('抽2张')));
});
check('doubling HP gives sqrt(2), with fixed reference and other units unchanged', () => {
  const s = state(); find(s, 'soldier').hp *= 2; const r = evaluate(s);
  near(r.result.get('soldier').current.power, 100 * Math.sqrt(2));
  near(r.result.get('archer').current.power, defaults.result.get('archer').current.power);
});
check('training applies allocated points; sword-arrow proximity windows are explicit', () => {
  const s = state(), u = find(s, 'soldier'); u.plan.attackAllocation = 0; u.plan.defenceAllocation = 2;
  const r = evaluate(s).result.get('soldier').upgraded;
  assert.equal(r.attributes.attack, 10); assert.equal(r.attributes.defence, 7);
  assert(r.swordMix); assert(r.swordMix.far.trace.every(t => t.name === '普通攻击'));
  near(r.output, r.swordMix.near.output * .5 + r.swordMix.far.output * .5);
});
check('0-stage ignores growth and buffs; 1-stage buffs apply once', () => {
  const s = state(), u = find(s, 'archer'); u.plan.hpBuff = 50; u.plan.attackBuff = 3;
  const r = evaluate(s).result.get('archer'); assert.equal(r.current.attributes.hp, 80);
  assert.equal(r.upgraded.attributes.hp, 130); assert.equal(r.curve[2].attributes.hp, 130);
  assert.equal(r.upgraded.attributes.attack, 17);
});
check('custom growth uses compounded percent plus linear growth', () => {
  const s = state(), u = find(s, 'archer'); u.plan.mode = 'custom'; u.plan.hpGrowth = .1; u.plan.hpStep = 5;
  const r = evaluate(s).result.get('archer'); assert.equal(r.curve[2].attributes.hp, 106);
});
check('cost changes efficiency only; zero fee and extra card energy are handled', () => {
  const s = state(), u = find(s, 'archer'); u.departures = 2; u.plan.buffEnergy = 3;
  const r = evaluate(s).result.get('archer'); near(r.current.power, defaults.result.get('archer').current.power);
  near(r.upgraded.perCost, r.upgraded.power / 3); near(r.upgraded.perTotalEnergy, r.upgraded.power / 6);
  u.cost = 0; u.departures = 0; const free = evaluate(s).result.get('archer'); assert.equal(free.current.perCost, null);
});
check('summon dependency follows child current stats, not its planned upgrades', () => {
  const s = state(), old = defaults.result.get('necromancer').current;
  find(s, 'bat').plan.hpBuff = 1000;
  near(evaluate(s).result.get('necromancer').current.power, old.power);
  find(s, 'bat').hp *= 2;
  const changed = evaluate(s).result.get('necromancer').current;
  near(changed.bodyPower, old.bodyPower); near(changed.summonPower, old.summonPower * Math.sqrt(2));
});
check('skill unlocks and counter unlocks honor base and planned training count', () => {
  const s = state(), u = find(s, 'archer'); u.skills.forEach(k => k.unlock = [1]);
  const r = evaluate(s).result.get('archer'); near(r.current.power, 0); assert(r.upgraded.power > 0); assert.equal(r.gain, null);
  near(r.curve[2].power, 0);
  const k = find(s, 'knight'); k.hp = 800; k.defence = 5; k.dodge = .2;
  k.counterUnlock = [1]; const r2 = evaluate(s).result.get('knight');
  near(r2.current.ehp, 1200); assert(r2.upgraded.ehp > 1200);
  assert(r2.curve[2].ehp < r2.upgraded.ehp);
});
check('skills use exact level arrays including replacement, gaps and empty arrays', () => {
  const s = state(), u = find(s, 'archer');
  u.skills[0].unlock = [0, 2]; u.skills[1].unlock = [1];
  const r = evaluate(s).result.get('archer');
  assert(r.current.trace.every(t => t.id === u.skills[0].id));
  assert(r.upgraded.trace.every(t => t.id === u.skills[1].id));
  assert(r.curve[2].trace.every(t => t.id === u.skills[0].id));
  near(r.curve[3].power, 0);
  u.skills.forEach(k => k.unlock = []); near(evaluate(s).result.get('archer').current.power, 0);
  for (const invalid of [[-1], [100], [1.5], [true], ['1'], null]) {
    u.skills[0].unlock = invalid; assert.throws(() => evaluate(s), /生效等级/);
  }
});
check('all 21 curves share one stage range and forecast classification', () => {
  const s = state(); find(s, 'archer').plan.levels = 8; const r = evaluate(s);
  for (const v of r.result.values()) assert.equal(v.curve.length, 9);
  assert.equal(r.result.get('soldier').curve[1].forecast, false); assert.equal(r.result.get('soldier').curve[2].forecast, true);
  assert.equal(r.result.get('skeleton').curve[1].forecast, true);
});
check('schedules respect nonoverlap and cooldowns', () => {
  for (const v of defaults.result.values()) for (const r of [v.current, v.upgraded, ...v.curve]) {
    const schedules = r.swordMix ? [r.swordMix.near.trace, r.swordMix.far.trace] : [r.trace];
    for (const trace of schedules) {
      let lastEnd = 0; const ready = new Map();
      for (const t of trace) { assert(t.start >= lastEnd - 1e-8); assert(t.start >= (ready.get(t.id) || 0) - 1e-8); ready.set(t.id, t.start + t.cooldown); lastEnd = t.end; }
    }
  }
});
check('invalid and degenerate inputs fail with a useful message', () => {
  const s = state(); find(s, 'soldier').hp = 0; assert.throws(() => evaluate(s), /hp/);
  const s2 = state(); find(s2, 'knight').dodge = 1; s2.model.eligible = 1; assert.throws(() => evaluate(s2), /无上限/);
  const s3 = state(); s3.model.meleeUptime = 0; assert.throws(() => evaluate(s3), /基准士兵输出为零/);
  const s4 = state(); find(s4, 'archer').skills[0].offsets = [99]; assert.throws(() => evaluate(s4), /命中时间/);
});
check('all recorded gameplay sources remain byte-identical', () => {
  for (const source of seed.sources) assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root, source.path))).digest('hex'), source.sha256);
});

(async () => {
  const modules = process.env.CODEX_WORKSPACE_NODE_MODULES || path.join(require('node:os').homedir(), '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules');
  const bundled = createRequire(path.join(modules, '.power-calculator-tests.cjs'));
  const { chromium } = bundled('playwright');
  const browser = await chromium.launch({ executablePath: 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe', headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1080 }, acceptDownloads: true });
  const page = await context.newPage(); const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto(pathToFileURL(path.join(out, '单位战力计算器.html')).href);
  await page.waitForFunction(() => window.UnitPowerCalculator?.getResults()?.result.size === 21);
  assert.equal(await page.locator('#unit-rows tr').count(), 21);
  assert.equal(await page.locator('#current-power').innerText(), '100.0');
  assert.equal(await page.locator('#curve-legend input').count(), 21);
  assert(await page.locator('#power-chart path').count() >= 21);
  checks.push('desktop renders all 21 rows, both charts and fixed baseline');
  const hp = page.locator('#unit-rows tr[data-unit="soldier"] input[data-field="hp"]');
  await hp.fill('200'); await page.waitForFunction(() => window.UnitPowerCalculator.getState().units.find(u => u.id === 'soldier').hp === 200);
  assert.match(await page.locator('#current-power').innerText(), /141\.4/);
  await hp.fill(''); assert.equal(await page.locator('#error').isVisible(), true);
  const attack = page.locator('#unit-rows tr[data-unit="soldier"] input[data-field="attack"]'); await attack.fill('12');
  assert.equal(await page.locator('#error').isVisible(), true);
  await hp.fill('100'); assert.equal(await page.locator('#error').isVisible(), false);
  assert.equal(await page.evaluate(() => window.UnitPowerCalculator.getState().units.find(u => u.id === 'soldier').attack), 12);
  checks.push('live edits, multiple pending invalid fields and recovery work');
  await page.locator('#tab-editor').click();
  const index = await page.evaluate(() => window.UnitPowerCalculator.getState().units.findIndex(u => u.id === 'soldier'));
  await page.locator(`[data-path="units.${index}.plan.attackAllocation"]`).fill('1');
  assert.equal(await page.locator(`[data-path="units.${index}.plan.defenceAllocation"]`).inputValue(), '1');
  await page.locator(`[data-path="units.${index}.plan.attackBuff"]`).fill('5');
  assert.equal(await page.locator('#error').isVisible(), false);
  checks.push('training allocation auto-balances and extra strengthening updates results');
  const skillLevels = page.locator(`[data-path="units.${index}.skills.0.unlock"]`);
  await skillLevels.fill('[0]');
  assert.equal(await page.locator('#error').isVisible(), false);
  assert((await page.evaluate(() => window.UnitPowerCalculator.getResults().result.get('soldier').upgraded.trace)).every(t => t.name !== '普通攻击'));
  await skillLevels.fill('[1.5]'); assert.equal(await page.locator('#error').isVisible(), true);
  await skillLevels.fill('['); assert.equal(await page.locator('#error').isVisible(), true);
  await skillLevels.fill('[0,1]'); assert.equal(await page.locator('#error').isVisible(), false);
  assert((await page.evaluate(() => window.UnitPowerCalculator.getResults().result.get('soldier').upgraded.trace)).some(t => t.name === '普通攻击'));
  checks.push('live array editing excludes expired skills and invalid arrays recover without page errors');
  await page.waitForTimeout(500); await page.reload(); await page.waitForFunction(() => window.UnitPowerCalculator?.getResults());
  assert.equal(await page.evaluate(() => window.UnitPowerCalculator.getState().units.find(u => u.id === 'soldier').plan.attackBuff), 5);
  checks.push('local saved state survives reload');
  const before = await page.evaluate(() => window.UnitPowerCalculator.getResults().result.get('soldier').upgraded.power);
  const downloadEvent = page.waitForEvent('download'); await page.locator('#download-html').click(); const download = await downloadEvent;
  const backup = path.join(__dirname, 'calculator_test_backup.html'); await download.saveAs(backup);
  const copyPage = await context.newPage(); await copyPage.goto(pathToFileURL(backup).href); await copyPage.waitForFunction(() => window.UnitPowerCalculator?.getResults());
  near(await copyPage.evaluate(() => window.UnitPowerCalculator.getResults().result.get('soldier').upgraded.power), before);
  checks.push('downloaded standalone copy preserves all inputs and recalculates offline');
  await copyPage.close(); fs.unlinkSync(backup);
  const imported = state(); find(imported, 'soldier').attack = 20;
  await page.locator('#import-file').setInputFiles({ name: 'test-plan.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(imported)) });
  await page.waitForFunction(() => window.UnitPowerCalculator.getState().units.find(u => u.id === 'soldier').attack === 20);
  checks.push('JSON plan import validates and refreshes all units');
  const exportEvent = page.waitForEvent('download'); await page.locator('#export-json').click(); const exported = await exportEvent;
  const exportedPath = path.join(__dirname, 'calculator_test_export.json'); await exported.saveAs(exportedPath);
  const exportState = JSON.parse(fs.readFileSync(exportedPath, 'utf8')); M.validate(exportState, seed.reference.unitIds);
  assert.equal(find(exportState, 'soldier').attack, 20); fs.unlinkSync(exportedPath);
  await page.locator('#import-file').setInputFiles({ name: 'bad-plan.json', mimeType: 'application/json', buffer: Buffer.from('{"schema":"unit-power-calculator/v1","units":[]}') });
  await page.waitForFunction(() => document.getElementById('toast').textContent.includes('导入失败'));
  assert.equal(await page.evaluate(() => window.UnitPowerCalculator.getState().units.find(u => u.id === 'soldier').attack), 20);
  checks.push('JSON export is valid and malformed import preserves existing inputs');
  await page.locator('#tab-overview').click();
  await page.locator('#show-selected').click(); assert.equal(await page.locator('#curve-legend input:checked').count(), 1);
  await page.locator('#show-all').click(); assert.equal(await page.locator('#curve-legend input:checked').count(), 21);
  await page.locator('#bulk-levels').fill('3'); await page.locator('#apply-levels').click();
  assert.equal(await page.evaluate(() => window.UnitPowerCalculator.getState().units.every(u => u.plan.levels === 3)), true);
  checks.push('all-series visibility and bulk comparison-stage controls work');
  await page.locator('#reset').click(); await page.locator('#tab-editor').click();
  for (const id of seed.reference.unitIds) {
    await page.locator('#selected-unit').selectOption(id);
    assert.equal(await page.locator('#error').isVisible(), false);
    assert.equal(await page.locator('#skill-fields .skill').count(), find(seed.defaults, id).skills.length + (id === 'soldier' ? 1 : 0));
    assert.equal(await page.locator('#view-editor input:invalid').count(), 0);
  }
  checks.push('all 21 unit editors including summon and sword-arrow fields render valid values');
  await page.locator('#selected-unit').selectOption('soldier'); await page.locator('#tab-standard').click();
  const oldArcher = await page.evaluate(() => window.UnitPowerCalculator.getResults().result.get('archer').current.power);
  await page.locator('[data-path="model.targetDefence"]').fill('6');
  near(await page.evaluate(() => window.UnitPowerCalculator.getResults().result.get('soldier').current.power), 100);
  assert.notEqual(await page.evaluate(() => window.UnitPowerCalculator.getResults().result.get('archer').current.power), oldArcher);
  await page.locator('[data-path="model.targetDefence"]').fill('5');
  checks.push('comparison environment changes recalculate all units on a fixed soldier scale');
  await page.locator('#tab-overview').click(); await page.waitForTimeout(4500);
  await page.screenshot({ path: path.join(__dirname, 'unit_power_calculator_desktop.png'), fullPage: true });
  await page.locator('#tab-editor').click(); await page.screenshot({ path: path.join(__dirname, 'unit_power_calculator_editor.png'), fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 }); await page.locator('#tab-overview').click(); await page.waitForTimeout(150);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), true);
  await page.screenshot({ path: path.join(__dirname, 'unit_power_calculator_mobile.png'), fullPage: true });
  checks.push('390-pixel mobile layout contains overflow in the data table');
  assert.deepEqual(errors, []);
  await browser.close();
  const report = { version: seed.version, date: seed.date, checks, count: checks.length, browser: 'Microsoft Edge headless / Playwright', actualCombatMeasured: false,
    units: [...defaults.result].map(([id, r]) => ({ id, current: r.current.power, upgraded: r.upgraded.power, perCost: r.upgraded.perCost, forecast: r.upgraded.forecast })) };
  fs.writeFileSync(path.join(__dirname, 'unit_power_calculator_validation.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ checks: checks.length, units: 21, browserErrors: errors.length, screenshots: 3 }));
})().catch(e => { console.error(e); process.exitCode = 1; });
