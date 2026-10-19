// Exercise the standalone spreadsheet UI without browser automation or game writes.
const fs=require('fs'),vm=require('vm'),assert=require('assert'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'../../docs/game_config_catalog.html'),'utf8');
class Element{
 constructor(tag='div'){this.tagName=tag;this.children=[];this.style={};this.dataset={};this.value='';this.attributes={};this.classList={add(){},toggle(){}};this.valid=true}
 append(...items){this.children.push(...items)}
 replaceChildren(...items){this.children=items}
 setAttribute(k,v){this.attributes[k]=v}
 removeAttribute(k){delete this.attributes[k]}
 add(option){this.children.push(option)}
 setCustomValidity(message){this.valid=!message}
 checkValidity(){return this.valid}
 reportValidity(){return this.valid}
 showModal(){this.open=true}
 close(){this.open=false}
 click(){if(this.onclick)this.onclick()}
}
const ids=['catalog-data','tabs','sheet-head','sheet-body','sheet-title','sheet-subtitle','sheet-foot','search','stamp','change-count','apply','toast','save','export','import','file-input','close-modal','modal','modal-body','diff','help','mode','add-row','add-column'];
const elements=new Map(ids.map(id=>[id,new Element()]));
elements.get('catalog-data').textContent=html.match(/<script id="catalog-data" type="application\/json">([\s\S]*?)<\/script>/)[1];
const store=new Map(),listeners={};
const sandbox={console,Option:class{constructor(text,value){this.text=text;this.value=value}},document:{getElementById:id=>elements.get(id),createElement:t=>new Element(t),querySelector:()=>null,addEventListener:(name,cb)=>{listeners[name]=cb}},localStorage:{getItem:k=>store.get(k),setItem:(k,v)=>store.set(k,v),removeItem:k=>store.delete(k)},location:{protocol:'file:',hostname:''},setTimeout:()=>0,clearTimeout(){},Blob:class{},URL:{createObjectURL(){return'blob:test'},revokeObjectURL(){}}};
vm.createContext(sandbox);
const script=html.match(/<script>\s*([\s\S]*?)<\/script>\s*<\/body>/)[1];
new vm.Script(script).runInContext(sandbox);
const run=s=>vm.runInContext(s,sandbox);
assert.equal(run('allChanges().length'),0);
assert.equal(elements.get('sheet-body').children.length,run('visibleRows().length'));
assert.ok(elements.get('sheet-body').children.length>0);
assert.equal(run('index.has("res://data/cards/round_add.tres") || index.has("res://data/cards/round_reduce.tres")'),false);
assert.equal(run('Object.hasOwn(kindNames,5)'),false);
assert.equal(run('title(index.get("res://data/cards/copy_ally.tres::Resource_27uql")).endsWith("复制友军")'),true);
assert.equal(run('enumOptions(find(index.get("res://data/cards/copy_ally.tres::Resource_27uql"),"kind")).some(([number])=>number===5)'),false);
assert.equal(run('enumOptions(find(index.get("res://data/cards/copy_ally.tres::Resource_27uql"),"kind")).some(([number])=>number===6)'),true);
assert.equal(run('kindNames[17]'),'立即获得能量');
assert.equal(run('kindNames[18]'),'最大生命提升');
for(const category of ['cards','card_effects','allies','enemies','skills','relics','potions'])run("category='"+category+"';renderTabs();renderSheet()");
assert.equal(elements.get('sheet-body').children.length,run('visibleRows().length'));
run("category='skills';renderSheet()");
assert.deepEqual(Array.from(run('columns.slice(0,3)')),['unit_name','skill_name','unlock_upgrade_levels']);
const skillId='res://data/skills/soldier_power_attack.tres';
assert.ok(run('value(index.get("'+skillId+'"),"unit_name").includes("士兵")'));
assert.equal(run('title(index.get("'+skillId+'"))===value(index.get("'+skillId+'"),"skill_name")'),true);
const ownerCell=run('makeCell(index.get("'+skillId+'"),"unit_name",0,0)');
assert.equal(ownerCell.children[0].tagName,'div');
assert.ok(ownerCell.children[0].textContent.includes('士兵'));
assert.equal(run('find(index.get("'+skillId+'"),"unit_name").editable'),false);
run('var sharedUnit=copy(index.get("res://data/units/soldier.tres"));sharedUnit.id="res://data/units/shared_test.tres";find(sharedUnit,"unit_name").value="共享测试单位";data.records.push(sharedUnit)');
assert.ok(run('value(index.get("'+skillId+'"),"unit_name").includes("共享测试单位")'));
run('data.records.pop()');
assert.ok(run('value(index.get("res://data/skills/knight_dodge_attack.tres"),"unit_name").includes("骑士")'));
elements.get('search').value='士兵';
assert.ok(run('visibleRows().some(r=>r.id==="'+skillId+'")'));
elements.get('search').value='';
const unlockCell=run('makeCell(index.get("'+skillId+'"),"unlock_upgrade_levels",0,0)');
assert.equal(unlockCell.children[0].type,'text');
assert.equal(unlockCell.children[0].value,'[0,1]');
assert.ok(unlockCell.children[0].title.includes('[0] 强化后失效'));
unlockCell.children[0].value='[0]';unlockCell.children[0].onchange();
assert.deepEqual(Array.from(run('value(index.get("'+skillId+'"),"unlock_upgrade_levels")')),[0]);
for(const text of ['0','[','[-1]','[100]','[1.5]','[true]','["1"]']){
 unlockCell.children[0].value=text;unlockCell.children[0].onchange();
 assert.equal(unlockCell.children[0].valid,false);
 assert.deepEqual(Array.from(run('value(index.get("'+skillId+'"),"unlock_upgrade_levels")')),[0]);
}
unlockCell.children[0].value='[]';unlockCell.children[0].onchange();
assert.equal(run('value(index.get("'+skillId+'"),"unlock_upgrade_levels").length'),0);
unlockCell.children[0].value='[0,1]';unlockCell.children[0].onchange();
assert.equal(run('allChanges().length'),0);
assert.equal(run('enumOptions(find(index.get("res://data/cards/copy_ally.tres"),"category"))[1][1]'),'强化');
run("category='allies';renderSheet()");
const cell=run('makeCell(index.get("res://data/units/soldier.tres"),"attack",0,0)');
cell.children[0].value='27';cell.children[0].onchange();
assert.equal(run('value(index.get("res://data/units/soldier.tres"),"attack")'),27);
assert.equal(run('allChanges().length'),1);
assert.equal(elements.get('change-count').textContent,1);
elements.get('diff').onclick();
assert.ok(elements.get('modal-body').innerHTML.includes('攻击'));
assert.ok(store.size===1);
for(const id of ['new-name','new-label','new-type','new-default','new-description','confirm-column'])elements.set(id,new Element());
elements.get('add-column').onclick();
elements.get('new-name').value='custom_power';
elements.get('new-label').value='自定义力量';
elements.get('new-type').value='int';
elements.get('new-default').value='3';
elements.get('new-description').value='策划新增参数';
elements.get('confirm-column').onclick();
assert.equal(run('data.pending_columns.length'),1);
assert.equal(run('data.records.filter(r=>r.group==="units").every(r=>find(r,"custom_power")?.value===3)'),true);
assert.ok(run('sheetColumns().includes("custom_power")'));
run('removeColumn("custom_power")');
assert.equal(run('data.pending_columns.length'),0);
assert.equal(run('data.records.filter(r=>r.group==="units").some(r=>find(r,"custom_power"))'),false);
const row=run('visible.findIndex(r=>r.id==="res://data/units/soldier.tres")'),col=run('columns.indexOf("max_hp")');
listeners.paste({target:{dataset:{resource:'res://data/units/soldier.tres',row:String(row),column:String(col)}},clipboardData:{getData:()=> '200\t29'},preventDefault(){}});
assert.equal(run('value(index.get("res://data/units/soldier.tres"),"max_hp")'),200);
assert.equal(run('value(index.get("res://data/units/soldier.tres"),"attack")'),29);
for(const id of ['row-template','row-slug','row-label','confirm-row'])elements.set(id,new Element());
run("category='allies';renderSheet()");
elements.get('add-row').onclick();
elements.get('row-template').value='res://data/units/soldier.tres';
elements.get('row-slug').value='test_soldier';
elements.get('row-label').value='测试士兵';
elements.get('confirm-row').onclick();
assert.equal(run('data.pending_rows.length'),1);
assert.equal(run('value(index.get("res://data/units/test_soldier.tres"),"unit_english_name")'),'test_soldier');
assert.equal(run('value(index.get("res://data/units/test_soldier.tres"),"unit_name")'),'测试士兵');
assert.equal(run('visibleRows().some(r=>r.id==="res://data/units/test_soldier.tres")'),true);
run('removeRow("res://data/units/test_soldier.tres")');
assert.equal(run('data.pending_rows.length'),0);
run("category='card_effects';renderSheet()");
elements.get('add-row').onclick();
const effectSource=run('visible[0].id');
elements.get('row-template').value=effectSource;
elements.get('row-slug').value='extra_effect';
elements.get('confirm-row').onclick();
assert.equal(run('data.pending_rows.length'),1);
assert.equal(run('data.pending_rows[0].id'),effectSource.split('::')[0]+'::Resource_extra_effect');
run('removeRow(data.pending_rows[0].id)');
assert.equal(run('data.pending_rows.length'),0);
run("category='allies';renderSheet()");
const hpHeader=elements.get('sheet-head').children[0].children[run('columns.indexOf("max_hp")')+1];
assert(hpHeader.title.includes('最大生命'));
const hpCell=run('makeCell(index.get("res://data/units/soldier.tres"),"max_hp",0,0)');
assert(hpCell.children[0].title.includes('最大生命'));
const skillsCell=run('makeCell(index.get("res://data/units/soldier.tres"),"skills",0,0)');
assert(skillsCell.children[0].title.includes('优先选择'));
console.log('CONFIG_CATALOG_SHEET_UI_PASS: seven sheets, skill unit associations and unlock levels, parameter tooltips, cells, new/remove rows and columns, drafts, Excel paste');
