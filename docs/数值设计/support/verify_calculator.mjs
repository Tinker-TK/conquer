// CDP smoke test for the single-file calculator.
// Usage: start Edge with --remote-debugging-port=9222, then run this file.
const PORT = process.env.CDP_PORT || 9222;
const list = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
const page = list.find(x => x.type === 'page' && (x.title || '').includes('ballsprite')) || list.find(x => x.type === 'page' && x.url.startsWith('file:'));
if (!page) throw new Error('no page target');
const ws = new WebSocket(page.webSocketDebuggerUrl);
let nextId = 0;
const pending = new Map();
const exceptions = [];
const consoleErrors = [];
ws.onmessage = (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    if (msg.error) reject(new Error(JSON.stringify(msg.error)));
    else resolve(msg.result);
  }
  if (msg.method === 'Runtime.exceptionThrown') {
    exceptions.push(msg.params.exceptionDetails?.text || JSON.stringify(msg.params));
  }
  if (msg.method === 'Runtime.consoleAPICalled' && msg.params.type === 'error') {
    consoleErrors.push(msg.params.args.map(a => a.value || a.description || '').join(' '));
  }
};
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
function send(method, params = {}) {
  const id = ++nextId;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });
}
async function evalJs(expression) {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || ''));
  return r.result?.value;
}
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
await send('Runtime.enable');
await sleep(500);
const out = {};
out.title = await evalJs('document.title');
out.initialSummary = await evalJs('document.querySelector("#summary").innerText.replace(/\\n+/g," | ")');
out.tabCounts = {};
for (const tab of ['overview', 'units', 'cards', 'relics', 'potions', 'build', 'calibration']) {
  await evalJs(`state.tab=${JSON.stringify(tab)}; render();`);
  await sleep(120);
  out.tabCounts[tab] = await evalJs('({panels:document.querySelectorAll("#view .panel").length, rows:document.querySelectorAll("#view tbody tr").length, text:document.querySelector("#view").innerText.slice(0,80)})');
}
await evalJs('state.tab="units"; render();');
await sleep(100);
out.unitRows = await evalJs('document.querySelectorAll("#view tbody tr").length');
out.swordsmanBefore = await evalJs('simulateUnit(unitView(UNIT_BY_ID.swords_man),0).power');
await evalJs('document.querySelector("#applyTargetUnits").click()');
await sleep(150);
out.swordsmanAfter = await evalJs('simulateUnit(unitView(UNIT_BY_ID.swords_man),0).power');
out.targetEdit = await evalJs('state.edits.units.swords_man');
await evalJs('document.querySelector("#resetUnitEdits").click()');
await sleep(100);
out.swordsmanReset = await evalJs('simulateUnit(unitView(UNIT_BY_ID.swords_man),0).power');
await evalJs('state.tab="cards"; render();');
await sleep(100);
await evalJs('document.querySelector("#applyTargetCosts").click()');
await sleep(100);
out.sacrificeCost = await evalJs('cardView(CARD_BY_ID.sacrifice).cost');
await evalJs('document.querySelector("#resetCardEdits").click()');
await sleep(100);
out.sacrificeReset = await evalJs('cardView(CARD_BY_ID.sacrifice).cost');
out.deckBefore = await evalJs('state.deck.length');
await evalJs('addCard("power_enhance")');
await sleep(100);
out.deckAfter = await evalJs('state.deck.length');
await evalJs('openUnit("soldier")');
await sleep(150);
out.drawerOpen = await evalJs('document.querySelector("#drawer").classList.contains("open")');
out.drawerTitle = await evalJs('document.querySelector("#drawerTitle").innerText');
await evalJs('closeDrawer()');
out.consoleErrors = consoleErrors;
out.exceptions = exceptions;
console.log(JSON.stringify(out, null, 2));
ws.close();
