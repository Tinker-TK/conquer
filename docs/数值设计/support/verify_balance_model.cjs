// Verify the exported calculator against the Python snapshot without a browser.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const data = JSON.parse(fs.readFileSync(path.join(__dirname, 'design_data.json'), 'utf8'));
const context = vm.createContext({ DATA: data, document: {}, localStorage: { getItem: () => null, setItem() {} } });
const source = fs.readFileSync(path.join(__dirname, 'calculator_app_part1.js'), 'utf8');
vm.runInContext(source + '\nglobalThis.results = DATA.units.filter(u => u.team === "ally").map(u => ({id:u.id, js:unitPower(u), exported:u.current.power}));', context);
for (const row of context.results) {
  if (Math.abs(row.js - row.exported) > 0.15) throw new Error(JSON.stringify(row));
}
if (context.results.length !== 11) throw new Error('Expected all 11 recruitable units.');
console.log(JSON.stringify({passed:true, units:context.results.length, version:data.model.version}));
