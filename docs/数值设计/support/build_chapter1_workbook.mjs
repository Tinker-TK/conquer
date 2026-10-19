import fs from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { Workbook, SpreadsheetFile } from './artifact_runtime.mjs';

const d=JSON.parse(await fs.readFile(new URL('../第一章·翠绿原野_数值草案.json',import.meta.url),'utf8'));
const wb=Workbook.create();
const order=['关卡总览','路线生命','波次与结算','敌兵与开局'];
const sh=Object.fromEntries(order.map(n=>[n,wb.worksheets.add(n)]));
const ov=sh['关卡总览'], rt=sh['路线生命'], ws=sh['波次与结算'], us=sh['敌兵与开局'];
const navy='#244E43', ink='#253C35', amber='#FFF0C5', grey='#ECF0EF';
const col=n=>{let s='';while(n){n--;s=String.fromCharCode(65+n%26)+s;n=Math.floor(n/26);}return s;};
const val=(s,a,v)=>s.getRange(a).values=[[v]];
const fx=(s,a,v)=>s.getRange(a).formulas=[[v]];
const get=(s,a)=>s.getRange(a).values[0][0];
function mergeText(s,a,text){s.getRange(a).merge();s.getRange(a).values=[[text]];s.getRange(a).format.wrapText=true;}
function base(s,title,note,cols,rows){
 s.showGridLines=false;
 s.getRange('A1:'+col(cols)+rows).format={font:{name:'Microsoft YaHei',size:10,color:ink},rowHeight:26,columnWidth:12,verticalAlignment:'center',numberFormat:'0'};
 mergeText(s,'A2:'+col(cols)+'2',title);s.getRange('A2:'+col(cols)+'2').format={font:{name:'Microsoft YaHei',size:16,bold:true,color:navy},rowHeight:36};
 mergeText(s,'A4:'+col(cols)+'4',note);s.getRange('A4:'+col(cols)+'4').format.rowHeight=36;
 s.freezePanes.freezeRows(8);s.tabColor=navy;
}
function header(s,row,labels){s.getRange('A'+row).write([labels]);s.getRange('A'+row+':'+col(labels.length)+row).format={fill:navy,font:{color:'#FFFFFF',bold:true},rowHeight:40,wrapText:true,horizontalAlignment:'center'};}
function inp(s,a){s.getRange(a).format={fill:amber,font:{color:'#805816'}};}
function raw(s,a){s.getRange(a).format.fill=grey;}
function whole(s,a,min,max){s.getRange(a).dataValidation={rule:{type:'whole',operator:'between',formula1:min,formula2:max}};}

base(ov,'翠绿原野 · 第一章关卡参考','CH1-v0.1 / 2026-10-09。黄色可调、白色公式、灰色当前资源。参考脚本不是实测，修改表格不会修改游戏。',13,52);
mergeText(ov,'A6:M6','统一采用当前起始牌组；不计地形、天气、站位收益，不依赖药水或新增强力卡。');
header(ov,8,['编号','关卡','适用层','据点生命','首轮能量','成长/轮','能量上限','抽牌/轮','参考轮数','参考战损','脚本状态','轮数目标','战损目标']);
ov.getRange('A9').write(d.encounters.map(e=>[e.id,e.name,e.floors,e.enemy_max_hp,e.energy_per_round,e.energy_growth,e.base_energy_cap,e.cards_per_round,null,null,null,e.round_target,e.loss_target]));
ov.getRange('A8:A14').format.columnWidth=7;ov.getRange('B8:B14').format.columnWidth=20;ov.getRange('C8:C14').format.columnWidth=18;
ov.getRange('E8:H14').format.columnWidth=10;ov.getRange('I8:M14').format.columnWidth=13;inp(ov,'D9:H14');whole(ov,'D9:D14',1,9999);whole(ov,'E9:G14',0,100);whole(ov,'H9:H14',0,10);
mergeText(ov,'A16:M16','据点生命控制需要赢几轮；敌兵属性与编成控制某一轮是否能赢。两者分开调整。');
mergeText(ov,'A18:E18','路线预算（取回血选项；不使用药水）');
val(ov,'A20','Boss最低入场生命');fx(ov,'C20',"=IF(COUNT('路线生命'!F9:F22)=14,MIN('路线生命'!F9:F22),\"待补脚本\")");
val(ov,'A21','Boss最高入场生命');fx(ov,'C21',"=IF(COUNT('路线生命'!F9:F22)=14,MAX('路线生命'!F9:F22),\"待补脚本\")");
val(ov,'A22','章末最低生命');fx(ov,'C22',"=IF(COUNT('路线生命'!G9:G22)=14,MIN('路线生命'!G9:G22),\"待补脚本\")");
val(ov,'A23','章末最高生命');fx(ov,'C23',"=IF(COUNT('路线生命'!G9:G22)=14,MAX('路线生命'!G9:G22),\"待补脚本\")");
for(let r=20;r<=23;r++)ov.getRange('A'+r+':B'+r).merge();
mergeText(ov,'A26:E27','先测A、E、F，再跑整章。每档至少10次，记录轮数、基地战损、剩余能量、征召当前费用；药水另列。');
mergeText(ov,'A29:E31','若交锋本身合适但拖长，普通据点生命减4，Boss减6。若某一轮普遍全灭，先改编成或攻击，不先加回血。');
header(ov,35,['编号','据点生命','参考战损']);
for(let i=0;i<6;i++){const r=36+i,t=9+i;val(ov,'A'+r,d.encounters[i].id);fx(ov,'B'+r,'=D'+t);fx(ov,'C'+r,'=J'+t);}
const chart=ov.charts.add('line',ov.getRange('A35:C41'));chart.title='据点生命与参考战损';chart.setPosition('F18','N32');chart.titleTextStyle.fontSize=13;chart.titleTextStyle.typeface='Microsoft YaHei';chart.hasLegend=true;
chart.xAxis={axisType:'textAxis',textStyle:{typeface:'Microsoft YaHei',fontSize:10}};chart.yAxis={numberFormatCode:'0',numberFormatSourceLinked:false,textStyle:{typeface:'Microsoft YaHei',fontSize:10}};
chart.series.items[0].line={fill:'#397761',style:'solid',width:2};chart.series.items[1].line={fill:'#D19C43',style:'solid',width:2};
header(ov,44,['层','实际战斗节点','配置']);
ov.getRange('A45').write([[2,'02_01 / 02_02 / 02_03','A'],[4,'04_03','B'],[5,'05_02','C'],[7,'07_02 / 07_03','D'],[8,'08_01 / 08_03','E'],[10,'10_01','F']]);
ov.getRange('B44:B50').format.columnWidth=26;mergeText(ov,'E44:M46','节点简写省略floor_。第3层全是事件；04_01、06_01是事件；09_02是休息。按实际type绑定。');
mergeText(ov,'E48:M50','源：当前章节JSON、BattleLevelConfig及战斗/卡牌脚本。完整字段、源文件和填表步骤见同目录初版文档。');

base(us,'敌兵副本与当前开局','敌兵属性仅用于本章副本。技能保留；T首版闪避设0。属性检查只计算普通攻击，不自动预测交锋胜负。',19,35);
us.getRange('A2:S2').unmerge();mergeText(us,'A2:M2','敌兵副本与当前开局');
us.getRange('A4:S4').unmerge();mergeText(us,'A4:M4','敌兵属性仅用于本章副本。技能保留；T首版闪避设0。属性检查只计算普通攻击，不自动预测交锋胜负。');
header(us,8,['代号','敌兵','草案生命','草案攻击','草案防御','幸存扣血','闪避','士兵每击','强化每击','普通击杀次数','强化击杀次数','敌打士兵','加固后受击','源资源ID','当前生命','当前攻击','当前防御','当前扣血','当前闪避']);
us.getRange('A9').write(d.enemies.map(u=>[u.code,u.name,u.max_hp,u.attack,u.defence,u.hp_damage_value,u.dodge_rate,null,null,null,null,null,null,u.source,u.current.max_hp,u.current.attack,u.current.defence,u.current.hp_damage_value,u.current.dodge_rate]));
inp(us,'C9:G13');raw(us,'N9:S13');us.getRange('G9:G13').format.numberFormat='0%';us.getRange('S9:S13').format.numberFormat='0%';
whole(us,'C9:C13',1,9999);whole(us,'D9:F13',0,9999);us.getRange('A8:A13').format.columnWidth=7;us.getRange('B8:B13').format.columnWidth=18;us.getRange('N8:N13').format.columnWidth=23;us.getRange('H8:M13').format.columnWidth=13;
header(us,17,['角色','单位','生命','攻击','防御','幸存扣血','初费']);
us.getRange('A18').write(['soldier','archer'].map((n,i)=>{const u=d.player_units[n];return['玩家',i?'弓箭手':'士兵',u.max_hp,u.attack,u.defence,u.hp_damage_value,u.card_cost];}));
inp(us,'C18:G19');mergeText(us,'A22:C22','强化参数');mergeText(us,'A23:C23','力量强化+攻击');val(us,'D23',5);mergeText(us,'A24:C24','护甲加固+防御');val(us,'D24',3);inp(us,'D23:D24');
for(let i=0;i<5;i++){const r=9+i;
 fx(us,'H'+r,'=MAX($D$18-E'+r+',1)');fx(us,'I'+r,'=MAX($D$18+$D$23-E'+r+',1)');
 fx(us,'J'+r,'=ROUNDUP(C'+r+'/H'+r+',0)');fx(us,'K'+r,'=ROUNDUP(C'+r+'/I'+r+',0)');
 fx(us,'L'+r,'=MAX(D'+r+'-$E$18,1)');fx(us,'M'+r,'=MAX(D'+r+'-$E$18-$D$24,1)');
}
mergeText(us,'A27:S28','源：data/units/unit_data.gd及各单位.tres。当前列包含源码默认值；开局为3士兵+2弓手+2护甲+3攻击强化。玩家数值供属性比较，不自动改变路线开局生命。');
mergeText(us,'A30:S31','B沿用精英哥布林技能：旋转0.8倍率/4次命中/8秒冷却；强击2倍率/10秒。每段单独减防御，不能只按攻击13估价。');
mergeText(us,'A33:S34','攻击、防御、生命改变后，请重新试玩并更新波次表的胜负与幸存扣血值；本表不会用一个战力分数替你预测胜负。');

const groups=new Map();let row=9;
base(ws,'波次编成与参考结算','胜负为设计假设：1=我方胜、0=我方败、2=全灭平局；空白=未设参考。兵种属性改变不会自动预测胜负。',19,85);
mergeText(ws,'A6:S6','空波仍占一个回合。非循环耗尽后复用末个非空波；F循环6–10波，无成长。重复编成用公式链接原始波次。');
header(ws,8,['配置','回合','S','R','O','T','B','敌单位生命和','敌人数','幸存扣血池','胜负假设','我幸存扣血','敌幸存扣血','打敌据点','玩家战损','敌余生命','累计战损','基础能量','状态 / 说明']);
ws.getRange('A8:G85').format.columnWidth=8;ws.getRange('H8:J85').format.columnWidth=13;ws.getRange('K8:R85').format.columnWidth=12;ws.getRange('S8:S85').format.columnWidth=24;
for(let ei=0;ei<6;ei++){
 const e=d.encounters[ei], start=row, total=e.id==='F'?15:Math.max(e.waves.length,e.reference_rows.length), summary=9+ei;
 const waveRows=[];
 for(let i=0;i<total;i++,row++){
  const r=i+1, idx=i<e.waves.length?i:(e.id==='F'?5+(i-10)%5:e.waves.length-1);
  const w=e.waves[idx], ref=e.reference_rows[i];
  ws.getRange('A'+row).write([[e.id,r,...['S','R','O','T','B'].map(k=>w[k]),null,null,null,ref?ref.result:null,ref?ref.ally_survivor_damage:0,ref?ref.enemy_survivor_damage:0,null,null,null,null,null,null]]);
  if(i<e.waves.length){waveRows.push(row);inp(ws,'C'+row+':G'+row);}else{
   for(let k=3;k<=7;k++)fx(ws,col(k)+row,'='+col(k)+waveRows[idx]);
  }
  fx(ws,'H'+row,'=C'+row+"*'敌兵与开局'!$C$9+D"+row+"*'敌兵与开局'!$C$10+E"+row+"*'敌兵与开局'!$C$11+F"+row+"*'敌兵与开局'!$C$12+G"+row+"*'敌兵与开局'!$C$13");
  fx(ws,'I'+row,'=SUM(C'+row+':G'+row+')');
  fx(ws,'J'+row,'=C'+row+"*'敌兵与开局'!$F$9+D"+row+"*'敌兵与开局'!$F$10+E"+row+"*'敌兵与开局'!$F$11+F"+row+"*'敌兵与开局'!$F$12+G"+row+"*'敌兵与开局'!$F$13");
  const prev=i===0?"'关卡总览'!$D$"+summary:'P'+(row-1);
  fx(ws,'N'+row,'=IF(OR('+prev+'<=0,NOT(ISNUMBER(K'+row+'))),0,IF(K'+row+'=1,B'+row+'+L'+row+',0))');
  fx(ws,'O'+row,'=IF(OR('+prev+'<=0,NOT(ISNUMBER(K'+row+'))),0,IF(K'+row+'=0,B'+row+'+M'+row+',0))');
  fx(ws,'P'+row,'=MAX(0,'+prev+'-N'+row+')');fx(ws,'Q'+row,(i===0?'=0':'=Q'+(row-1))+'+O'+row);
  fx(ws,'R'+row,"=MIN('关卡总览'!$E$"+summary+"+(B"+row+"-1)*'关卡总览'!$F$"+summary+",'关卡总览'!$G$"+summary+')');
  fx(ws,'S'+row,'=IF('+prev+'<=0,"已结束",IF(NOT(ISNUMBER(K'+row+')),"待填写胜负",IF(M'+row+'>J'+row+',"敌幸存值超上限",IF(AND(I'+row+'=0,K'+row+'=0),"空波不可判败","'+(i>=e.waves.length?'复用波'+(idx+1):sum(w)===0?'空波':'原始波'+(idx+1))+'"))))');
  inp(ws,'K'+row+':M'+row);whole(ws,'C'+row+':G'+row,0,20);whole(ws,'K'+row,0,2);whole(ws,'L'+row+':M'+row,0,100);
 }
 groups.set(e.id,{start,end:row-1,summary,waveRows});
 const g=groups.get(e.id);
 fx(ov,'I'+summary,"=IF('波次与结算'!P"+g.end+'>0,"待继续",COUNTIF(\'波次与结算\'!P'+g.start+':P'+g.end+',">0")+1)');
 fx(ov,'J'+summary,"='波次与结算'!Q"+g.end);
 fx(ov,'K'+summary,"=IF('波次与结算'!P"+g.end+'>0,"未扣完","已扣完")');
 if(ei<5){mergeText(ws,'A'+row+':S'+row,e.id==='E'?'以下为Boss：第11轮后循环6–10，无成长。':'下一套配置');ws.getRange('A'+row+':S'+row).format.fill=grey;row++;}
}
function sum(w){return Object.values(w).reduce((a,b)=>a+b,0);}
ws.getRange('O9:O'+(row-1)).conditionalFormats.add('cellIs',{operator:'greaterThan',formula:0,format:{fill:'#F8DED2',font:{color:'#9E4828'}}});
ws.freezePanes.freezeColumns(2);

base(rt,'14条实际路线的生命预算','按真实节点类型，取回血选项，满血溢出不计回复。战损倍率只放大预算，不模拟另一组交锋；死亡后生命保持0。',31,32);
rt.getRange('A2:AE2').unmerge();mergeText(rt,'A2:H2','14条实际路线的生命预算');
rt.getRange('A4:AE4').unmerge();mergeText(rt,'A4:H4','按真实节点类型，取回血选项，满血溢出不计回复。战损倍率只放大预算，不模拟另一组交锋；死亡后生命保持0。');
val(rt,'A5','开局生命');val(rt,'B5',100);val(rt,'C5','生命上限');val(rt,'D5',100);val(rt,'E5','战损倍率');val(rt,'F5',1);inp(rt,'B5');inp(rt,'D5');inp(rt,'F5');rt.getRange('F5').format.numberFormat='0.0x';
mergeText(rt,'A6:H6','可将F5改为1.5观察压力预算。若某套据点未扣完，路线结果显示待补脚本。右侧保留逐层生命与实际回复。');
header(rt,8,['路径','节点序列（省略floor_）','普通场数','战损预算','实际回复','Boss入场','章末生命','脚本状态']);
rt.getRange('A8:A22').format.columnWidth=8;rt.getRange('B8:B22').format.columnWidth=65;rt.getRange('C8:G22').format.columnWidth=12;rt.getRange('H8:H22').format.columnWidth=16;rt.getRange('I1:I32').format.columnWidth=3;
rt.getRange('J8').write([['出发',...Array.from({length:10},(_,i)=>'层'+(i+1)+'后')]]);rt.getRange('J8:T8').format={fill:navy,font:{color:'#FFFFFF',bold:true},rowHeight:40};
rt.getRange('V8').write([Array.from({length:10},(_,i)=>'层'+(i+1)+'回复')]);rt.getRange('V8:AE8').format={fill:navy,font:{color:'#FFFFFF',bold:true},rowHeight:40};
const nmap=new Map(d.chapter_nodes.map(n=>[n.id,n]));
for(let i=0;i<d.routes.length;i++){
 const r=9+i, route=d.routes[i], missing=[];let lossTerms=[];
 val(rt,'A'+r,route.id);val(rt,'B'+r,route.nodes.slice(1,9).map(x=>x.replace('floor_','')).join(' → '));val(rt,'C'+r,route.normal_battles);
 raw(rt,'A'+r+':C'+r);rt.getRange('B'+r).format.wrapText=true;rt.getRange('A'+r+':AE'+r).format.rowHeight=40;
 fx(rt,'J'+r,'=$B$5');
 for(let j=0;j<10;j++){
  const n=nmap.get(route.nodes[j]), prev=col(10+j)+r, next=col(11+j)+r, healed=col(22+j)+r;
  const group=n.reference_encounter?groups.get(n.reference_encounter):null;
  const loss=group?"'关卡总览'!$J$"+group.summary+'*$F$5':'0';
  const heal=[1,2].includes(n.type)?Math.max(...n.event.choices.map(c=>c.heal)):0;
  if(group){lossTerms.push(loss);missing.push("'关卡总览'!$K$"+group.summary+'<>"已扣完"');}
  fx(rt,next,'=IF(OR('+prev+'<=0,'+prev+'-'+loss+'<=0),0,MIN($D$5,'+prev+'-'+loss+'+'+heal+'))');
  fx(rt,healed,'=IF('+prev+'>'+loss+',MIN(MAX(0,$D$5-('+prev+'-'+loss+')),'+heal+'),0)');
 }
 const unresolved='OR('+missing.join(',')+')';
 fx(rt,'D'+r,'=IF('+unresolved+',"待补脚本",'+lossTerms.join('+')+')');
 fx(rt,'E'+r,'=IF('+unresolved+',"待补脚本",SUM(V'+r+':AE'+r+'))');
 fx(rt,'F'+r,'=IF('+unresolved+',"待补脚本",S'+r+')');fx(rt,'G'+r,'=IF('+unresolved+',"待补脚本",T'+r+')');
 fx(rt,'H'+r,'=IF('+unresolved+',"待补脚本",IF(T'+r+'<=0,"预算耗尽","有余量"))');
}
rt.getRange('D9:G22').format.numberFormat='0.0';rt.getRange('J9:AE22').format.numberFormat='0.0';
mergeText(rt,'A25:H26','路线上共2–4场普通战斗、1场Boss、1–3次20点休息；全部共14条路径。入场生命模型没有加入药水收益、购物支出或尚未获得的新征召牌。');
mergeText(rt,'A28:H30','源：data/levels/第一章 ·  翠绿原野.json。当前有5个节点标题与type不一致；本表保留type，不将事件误算为战斗。数值预算依赖波次表的假设结算，不代表实测平均值。');
rt.getRange('G9:G22').conditionalFormats.add('cellIs',{operator:'lessThanOrEqual',formula:0,format:{fill:'#F8DED2',font:{color:'#9E4828'}}});

wb.recalculate();
function assert(c,m){if(!c)throw Error(m);}
for(const e of d.encounters){const g=groups.get(e.id);assert(get(ov,'I'+g.summary)===e.reference_rounds,'round mismatch '+e.id);assert(get(ov,'J'+g.summary)===e.reference_loss,'loss mismatch '+e.id+' '+JSON.stringify(ws.getRange('K'+g.start+':Q'+g.end).values));}
for(let i=0;i<14;i++){const r=9+i,b=d.routes[i].baseline;assert(get(rt,'F'+r)===b.boss_entry_hp,'boss budget '+r);assert(get(rt,'G'+r)===b.end_hp,'end budget '+r);assert(get(rt,'E'+r)===b.actual_heal,'heal cap '+r);}
// Sensitivity, pending references, blank outcomes, and absorbing death are verified
// then restored, so the delivered workbook contains only the baseline reference.
val(rt,'F5',1.5);wb.recalculate();for(let i=0;i<14;i++){const r=9+i,s=d.routes[i].stress;assert(get(rt,'F'+r)===s.boss_entry_hp&&get(rt,'G'+r)===s.end_hp,'stress budget '+r);}val(rt,'F5',1);
val(ov,'D9',27);wb.recalculate();assert(get(ov,'K9')==='未扣完','pending HP check');assert(get(rt,'G9')==='待补脚本','pending route check');val(ov,'D9',22);
const a=groups.get('A');assert(get(ws,'O'+a.end)===0,'blank backup outcome must cause no damage');
val(us,'C9',140);wb.recalculate();assert(get(us,'J9')===18,'unit HP sensitivity');assert(get(ws,'H'+a.start)===140,'wave HP linkage');val(us,'C9',70);
val(rt,'F5',10);wb.recalculate();assert(get(rt,'G9')===0,'death must absorb healing');val(rt,'F5',1);wb.recalculate();
const errors=await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:20},maxChars:1500});
console.log('FORMULA_SCAN',errors.ndjson);
console.log('BASELINE',JSON.stringify({bossMin:get(ov,'C20'),bossMax:get(ov,'C21'),endMin:get(ov,'C22'),endMax:get(ov,'C23'),groups:Object.fromEntries(groups)}));
await fs.mkdir(new URL('./chapter1_previews/',import.meta.url),{recursive:true});
const renders=[['关卡总览','A1:N32','总览'],['关卡总览','A35:M50','节点与图表数据'],['敌兵与开局','A1:M24','属性'],['敌兵与开局','N8:S13','当前来源'],['路线生命','A1:H30','路线'],['波次与结算','A1:S23','早期波次'],['波次与结算','A51:S70','Boss波次']];
for(const [sheetName,range,file] of renders){const b=await wb.render({sheetName,range,format:'png',scale:1});await fs.writeFile(new URL('./chapter1_previews/'+file+'.png',import.meta.url),new Uint8Array(await b.arrayBuffer()));}
const output=await SpreadsheetFile.exportXlsx(wb);await output.save(fileURLToPath(new URL('../第一章·翠绿原野_关卡参考.xlsx',import.meta.url)));
await fs.writeFile(new URL('./chapter1_workbook_validation.json',import.meta.url),JSON.stringify({date:'2026-10-09',sheets:order,formulaScan:errors.ndjson,routes:14,groups:Object.fromEntries(groups),sensitivities:['stress1.5','enemyHPpending','blankOutcome','unitHP','deathAbsorbs'],baseline:{bossMin:get(ov,'C20'),bossMax:get(ov,'C21'),endMin:get(ov,'C22'),endMax:get(ov,'C23')}},null,2));
console.log('EXPORT_OK');
