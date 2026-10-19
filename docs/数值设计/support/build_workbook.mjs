
import fs from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { Workbook, SpreadsheetFile } from './artifact_runtime.mjs';
const dir=new URL('../',import.meta.url);
const snap=JSON.parse(await fs.readFile(new URL('./runtime_snapshot.json',import.meta.url),'utf8'));
const wb=Workbook.create(), names=['调参总览','单位战力','技能输出','波次压力','效果与资源','路线收支','试玩记录'];
const sheets=Object.fromEntries(names.map(n=>[n,wb.worksheets.add(n)]));
const col=n=>{let s='';while(n){n--;s=String.fromCharCode(65+n%26)+s;n=Math.floor(n/26);}return s;};
function table(sh,row,headers,rows){sh.getRange('A'+row+':'+col(headers.length)+row).values=[headers];if(rows.length)sh.getRange('A'+(row+1)).write(rows);sh.getRange('A'+row+':'+col(headers.length)+row).format={fill:'#283D58',font:{color:'#FFFFFF',bold:true},rowHeight:34,wrapText:true,horizontalAlignment:'center'};}
function value(sh,cell,v){sh.getRange(cell).values=[[v]];}
function formula(sh,cell,v){sh.getRange(cell).formulas=[[v]];}
function input(sh,r){sh.getRange(r).format.fill='#FFF3CE';sh.getRange(r).format.font.color='#865C00';}
function title(sh,t,note,cols,last){sh.showGridLines=false;sh.getRange('A1:'+col(cols)+last).format={font:{name:'Arial',size:10,color:'#243247'},rowHeight:24,columnWidth:14,verticalAlignment:'center'};value(sh,'A2',t);sh.getRange('A2').format.font={name:'Arial',size:14,bold:true};value(sh,'A4',note);sh.getRange('A4:'+col(cols)+'4').format.rowHeight=30;sh.getRange('A2:'+col(cols)+'2').format.borders={bottom:{style:'thin',color:'#93A4B8'}};sh.getRange('A6:'+col(cols)+last).format.numberFormat='0.00';sh.getRange('A1:A'+last).format.columnWidth=23;sh.freezePanes.freezeRows(6);}
const ov=sheets['调参总览'],us=sheets['单位战力'],ks=sheets['技能输出'],ws=sheets['波次压力'],cs=sheets['效果与资源'],rs=sheets['路线收支'],ts=sheets['试玩记录'];
title(ov,'ballsprite 数值调参框架','2026-10-08。黄色为可调输入；灰色为原始快照；白色为公式。战力和波次压力均为估算。',14,65);
ov.tabColor='#283D58';
const params=[
['参考来袭每击原伤',15,'点','假设；代表敌人普通攻击，改变它可检查防御阈值'],
['参考目标防御',5,'点','快照中骷髅兵防御'],
['参考目标闪避',0,'概率','假设；只有近战普通伤害能触发当前闪避规则'],
['来袭近战伤害占比',0.7,'比例','假设；投射物与环境伤害不参与当前闪避'],
['参考交锋观察时间',12,'秒','估价窗口；不会限制游戏真实交锋'],
['首轮基础能量',3,'点','BattleLevelConfig 默认；5份关卡当前相同'],
['每轮能量成长',1,'点','BattleLevelConfig 默认'],
['基础能量上限',10,'点','额外能量不受此上限截断'],
['每轮常规抽牌',5,'张','当前关卡快照；用实际抽牌数校准'],
['本局附加能量上限',0,'点','当前开局0，可试储能水晶+1'],
['抽牌遗物阈值',10,'张','十抽引擎；模型从计数0开始'],
['抽牌遗物能量',1,'点','十抽引擎 amount'],
['牌组总张数',10,'张','开局3士兵+2弓手+2防御+3强化'],
['征召牌张数',5,'张','开局3士兵+2弓手'],
['前排征召牌张数',3,'张','开局3士兵'],
['能量用于有效征召的比例',0.7,'比例','假设；剩余能量分配给效果牌或未使用'],
['每张征召牌每轮平均退场次数',0.35,'次/轮','估算输入，实际依赖洗牌和使用率'],
['高费单位额外预算',0.08,'比例/费','设计假设，用来补偿占一张手牌与高费难出'],
['单位每费效率低阈值',0.75,'倍率','设计诊断阈值，不能代替实战胜率'],
['单位每费效率高阈值',1.35,'倍率','设计诊断阈值'],
['治疗折算输出权重',0.5,'系数','假设；过量治疗和抢占攻击动画另在技能表控制'],
['开局实际生命',100,'点','引擎导出80基础+坚城之心20；城防铁壁被拒绝'],
['开局金币',99,'金币','RunStartData默认，尚无完整商店消耗闭环'],
['每点玩家生命的能量估值',0.25,'能量/点','仅估价假设，依据少掉的生命和额外能量校准'],
['模型参考征召初费',1,'点','士兵当前基础费用'],
['95%区间 z 值',1.96,'系数','Wilson 区间'],
];
table(ov,9,['参数','当前值','单位','依据或调整用途'],params);input(ov,'B10:B35');ov.getRange('A9:A35').format.columnWidth=37;ov.getRange('D9:D35').format.columnWidth=80;ov.getRange('B10:B35').format.numberFormat='0.00';ov.getRange('B12:B13').format.numberFormat='0%';ov.getRange('B25:B25').format.numberFormat='0%';
value(ov,'F6','结果');value(ov,'G6','公式值');value(ov,'F7','首手缺征召概率');formula(ov,'G7','=IF(OR(B22<1,B23<0,B23>B22,B18<0,B18>B22),"参数无效",IF(B18>B22-B23,0,COMBIN(B22-B23,B18)/COMBIN(B22,B18)))');
value(ov,'F8','首手缺前排概率');formula(ov,'G8','=IF(OR(B22<1,B24<0,B24>B22,B18<0,B18>B22),"参数无效",IF(B18>B22-B24,0,COMBIN(B22-B24,B18)/COMBIN(B22,B18)))');ov.getRange('G7:G8').format.numberFormat='0.0%';
value(ov,'F9','单位每费效率超上限数');formula(ov,'G9',"=COUNTIF('单位战力'!Q7:Q27,\">\"&B29)");
value(ov,'F10','单位每费效率低于下限数');formula(ov,'G10',"=COUNTIF('单位战力'!Q7:Q27,\"<\"&B28)");
value(ov,'F12','建议顺序');value(ov,'F13','1. 先调单位与技能');value(ov,'F14','2. 再调敌阵与空波');value(ov,'F15','3. 用路线检查生命收支');value(ov,'F16','4. 试玩记录相同版本与策略');
value(ov,'F18','仅改表格不会修改游戏资源');
value(ov,'F20','目前停用或价值受限的效果');value(ov,'F21','时长牌：运行时拒绝使用');value(ov,'F22','治疗牌：准备阶段通常满血');value(ov,'F23','毒伤：只在回合末扣幸存者');value(ov,'F24','开局护甲：只影响首次开打队伍');
ov.getRange('F6:F24').format.columnWidth=38;ov.getRange('G6:G24').format.columnWidth=18;
value(ov,'A38','概率依据：https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.hypergeom.html');
value(ov,'A40','调参时保持参考来袭与防御一致，避免把模型条件改变误认为单位本身被加强。');
const unitRows=new Map(snap.units.map((u,i)=>[u.path,i+7]));
const soldier=snap.units.find(u=>u.unit_english_name==='soldier'), sr=unitRows.get(soldier.path);
const skillMap=new Map(snap.skills.map(s=>[s.path,s]));
const skillRows=[];
for(const u of snap.units){
 const sc=snap.unit_scenes.find(x=>x.unit.path===u.path);
 const ordered=u.skills.map((p,i)=>({...skillMap.get(p),order:i})).sort((a,b)=>b.priority-a.priority||a.order-b.order);
 for(const k of ordered){
  const file=k.script_path.split('/').pop();
  const kind=file==='ally_heal.gd'?'治疗':file==='summon_unit.gd'?'召唤':file==='bloodthirst_attack.gd'?'吸血':file==='arrow_attack.gd'?'远程':file==='area_attack.gd'||file==='dash_attack.gd'?'范围':'近战';
  let duration=sc?.animations[k.cast_animation]?.duration??1;
  if(file==='dash_attack.gd')duration+=k.dash_distance/Math.max(k.dash_speed,1);
  const targets=kind==='范围'?1.5:(k.pierce_count>1?1.5:1);
  const availability=kind==='治疗'?0.5:1;
  skillRows.push({u,k,kind,duration,targets,availability});
 }
}
title(ks,'技能输出与动画占用','按优先级分配动画时间的长期近似。特殊攻击与普通攻击不会直接相加；开场爆发、走位与反击需试玩校准。',18,skillRows.length+8);
table(ks,6,['单位','技能','类型','优先级','单位攻击','攻击倍率','冷却秒','施法占用秒','命中帧数','平均目标数','可用目标比例','此前动画占用','施放次数/秒','每击有效伤害','DPS','有效HPS','技能来源','说明'],skillRows.map((o,i)=>[o.u.unit_name,o.k.skill_name,o.kind,o.k.priority,null,o.k.attack_rate,o.k.cooldown,o.duration,o.k.hit_frame.length,o.targets,o.availability,null,null,null,null,null,o.k.path,o.k.manual_finish?'手动结束；占用含冲刺估计':'技能初始可用；短战斗另看首发']));
input(ks,'F7:K'+(skillRows.length+6));ks.getRange('A6:B'+(skillRows.length+6)).format.columnWidth=21;ks.getRange('Q6:Q'+(skillRows.length+6)).format.columnWidth=65;ks.getRange('R6:R'+(skillRows.length+6)).format.columnWidth=43;ks.getRange('K7:L'+(skillRows.length+6)).format.numberFormat='0.0%';
for(let i=0;i<skillRows.length;i++){
 const row=i+7,o=skillRows[i],ur=unitRows.get(o.u.path);
 formula(ks,'E'+row,"='单位战力'!E"+ur);
 formula(ks,'L'+row,i&&skillRows[i-1].u.path===o.u.path?'=L'+(row-1)+'+M'+(row-1)+'*H'+(row-1):'=0');
 formula(ks,'M'+row,'=IF(OR(G'+row+'<=0,H'+row+'<=0,K'+row+'<0,K'+row+'>1),"输入无效",MIN(K'+row+'/G'+row+',MAX(0,1-L'+row+')/H'+row+'))');
 const dodge=(o.kind==='远程')?'1':"(1-'调参总览'!$B$12)";
 formula(ks,'N'+row,'=MAX(INT(E'+row+'*F'+row+")-'调参总览'!$B$11,1)*"+dodge);
 formula(ks,'O'+row,['治疗','召唤'].includes(o.kind)?'=0':'=M'+row+'*N'+row+'*I'+row+'*J'+row);
 formula(ks,'P'+row,o.kind==='治疗'?'=M'+row+'*INT(E'+row+'*F'+row+')*I'+row:o.kind==='吸血'?'=O'+row+'*K'+row:'=0');
}
title(us,'单位战力与费用','士兵为1战力。这里只反推生命；治疗、反击和召唤另行折算。原始配置保留在W:AB。',28,30);
table(us,6,['ID','单位','费用','生命','攻击','防御','闪避','扣血值','输出在线率','阵型系数','召唤附加战力','反击DPS','有效DPS','有效HPS','有效生命','相对战力','每费战力','目标战力','反推生命','诊断','来源','','原始费用','原始生命','原始攻击','原始防御','原始闪避','原始扣血'],snap.units.map(u=>[u.unit_english_name,u.unit_name,u.card_cost,u.max_hp,u.attack,u.defence,u.dodge_rate,u.hp_damage_value,u.skills.some(p=>skillMap.get(p).cast_range>=250)?1:0.8,1,0,0,null,null,null,null,null,null,null,null,u.path,null,u.card_cost,u.max_hp,u.attack,u.defence,u.dodge_rate,u.hp_damage_value]));
input(us,'C7:L27');us.getRange('W7:AB27').format.fill='#EBEFF4';us.getRange('B6:B27').format.columnWidth=20;us.getRange('G7:G27').format.numberFormat='0%';us.getRange('I7:I27').format.numberFormat='0%';us.getRange('U6:U27').format.columnWidth=55;us.getRange('T6:T27').format.columnWidth=18;us.freezePanes.freezeColumns(2);
for(const u of snap.units){
 const r=unitRows.get(u.path),matches=skillRows.map((o,i)=>o.u.path===u.path?i+7:null).filter(Boolean);
 formula(us,'M'+r,'=('+matches.map(j=>"'技能输出'!O"+j).join('+')+')*I'+r+'+L'+r);
 formula(us,'N'+r,'=('+matches.map(j=>"'技能输出'!P"+j).join('+')+')*I'+r);
 formula(us,'O'+r,"=IF(OR(D"+r+"<=0,G"+r+"<0,G"+r+">=1,'调参总览'!$B$10<=0),\"输入无效\",D"+r+"*'调参总览'!$B$10/MAX('调参总览'!$B$10-F"+r+",1)/(1-G"+r+"*'调参总览'!$B$13))");
 formula(us,'P'+r,"=SQRT(O"+r+"/$O$"+sr+"*(M"+r+"+N"+r+"*'调参总览'!$B$30)/($M$"+sr+"+$N$"+sr+"*'调参总览'!$B$30))*J"+r+"+K"+r);
 formula(us,'Q'+r,'=IF(C'+r+'<=0,"单独估价",P'+r+'/C'+r+')');
 formula(us,'R'+r,"=C"+r+"*(1+'调参总览'!$B$27*(C"+r+"-1))");
 formula(us,'S'+r,'=IF(P'+r+'<=K'+r+',"待实测",MAX(5,ROUND(D'+r+'*((MAX(0,R'+r+'-K'+r+'))/(P'+r+'-K'+r+'))^2/5,0)*5))');
 formula(us,'T'+r,'=IF(Q'+r+">'调参总览'!$B$29,\"效率偏高\",IF(Q"+r+"<'调参总览'!$B$28,\"效率偏低\",\"参考区间内\"))");
}
us.getRange('Q7:Q27').conditionalFormats.addCustom("=Q7>'调参总览'!$B$29",{fill:'#FDE1DC',font:{color:'#AA3027'}});
us.getRange('Q7:Q27').conditionalFormats.addCustom("=Q7<'调参总览'!$B$28",{fill:'#E2ECFA',font:{color:'#24569B'}});
title(ws,'波次压力与重复成长','展开当前5份关卡的前12轮。压力=敌阵战力/可部署战力；使用抽牌和费用近似，不能转换为实战胜率。',16,67);
const waveRows=[];
for(const level of snap.levels)for(let r=1;r<=12;r++){
 const end=level.repeat_end||level.waves.length,start=level.repeat_start;
 let index=r-1,cycle=0;
 if(level.repeat_waves&&r>end){index=start-1+(r-end-1)%(end-start+1);cycle=1+Math.floor((r-end-1)/(end-start+1));}
 if(!level.repeat_waves&&r>level.waves.length){index=level.waves.map(w=>w.units.length>0).lastIndexOf(true);}
 const wave=level.waves[index]??{units:[]};
 waveRows.push({level,r,index,cycle,wave});
}
table(ws,6,['关卡','轮数','原波次','循环次数','敌方人数','基础能量','抽牌附加能量','征召平均费用','预计征召数','玩家预算战力','敌阵战力','压力比','全败最大扣血','敌方节点生命','来源','波次说明'],waveRows.map(o=>[o.level.path.split('/').pop().replace('.tres',''),o.r,o.index+1,o.cycle,o.wave.units.length,null,null,null,null,null,null,null,null,o.level.enemy_max_hp,o.level.path,o.wave.units.length?'战力含本轮重复成长':o.r>o.level.waves.length?'耗尽后重用末有效阵型':'原配置为空波']));
ws.getRange('O6:O66').format.columnWidth=57;ws.getRange('P6:P66').format.columnWidth=39;ws.freezePanes.freezeColumns(1);
for(let i=0;i<waveRows.length;i++){
 const row=i+7,o=waveRows[i];
 formula(ws,'F'+row,"=MIN('调参总览'!$B$15+(B"+row+"-1)*'调参总览'!$B$16,'调参总览'!$B$17)");
 formula(ws,'G'+row,"=(INT(B"+row+"*'调参总览'!$B$18/'调参总览'!$B$20)-INT((B"+row+"-1)*'调参总览'!$B$18/'调参总览'!$B$20))*'调参总览'!$B$21+'调参总览'!$B$19");
 formula(ws,'H'+row,"='调参总览'!$B$34+(B"+row+"-1)*'调参总览'!$B$26");
 formula(ws,'I'+row,"=MIN((F"+row+"+G"+row+")*'调参总览'!$B$25/H"+row+",'调参总览'!$B$18*'调参总览'!$B$23/'调参总览'!$B$22)");
 formula(ws,'J'+row,"=I"+row+"*'单位战力'!$P$"+sr);
 const terms=o.wave.units.map(x=>{
  const base=snap.units.find(u=>u.unit_english_name===x.unit.unit_english_name),u=unitRows.get(base.path),g=x.growth||{};
  return "'单位战力'!P"+u+"*SQRT(('单位战力'!D"+u+"+D"+row+"*"+(g.max_hp||0)+")/'单位战力'!D"+u+"*MAX('调参总览'!$B$10-'单位战力'!F"+u+",1)/MAX('调参总览'!$B$10-'单位战力'!F"+u+"-D"+row+"*"+(g.defence||0)+",1)*MAX('单位战力'!E"+u+"+D"+row+"*"+(g.attack||0)+"-'调参总览'!$B$11,1)/MAX('单位战力'!E"+u+"-'调参总览'!$B$11,1))";
 });
 formula(ws,'K'+row,'='+(terms.length?terms.join('+'):'0'));
 formula(ws,'L'+row,'=IF(J'+row+'<=0,"无部署预算",K'+row+'/J'+row+')');
 formula(ws,'M'+row,'=IF(E'+row+'=0,0,B'+row+'+'+(o.wave.units.length?o.wave.units.map(x=>"'单位战力'!H"+unitRows.get(snap.units.find(u=>u.unit_english_name===x.unit.unit_english_name).path)).join('+'):'0')+')');
}
ws.getRange('L7:L66').conditionalFormats.add('cellIs',{operator:'greaterThan',formula:1.3,format:{fill:'#FDE1DC',font:{color:'#AA3027'}}});
title(cs,'效果牌、遗物与药水估价','效果按参考士兵估价。黄色兑现率与额外战力由试玩校准。玩家生命成本和部队生命必须分开。',16,53);
const kindLabels=['攻击强化','单位治疗','防御强化','附毒','死亡爆炸','时长','复制','伤害区域','泥潭','抽牌','禁抽','付玩家生命','逐轮能量','伤亡光环','随机出牌','回撤','自定义','即时能量','最大生命'];
const warnings={0:'只延续到本单位退场；Rounds不会自动转移到下一轮',1:'准备阶段通常满血，初始兑现率为0',2:'平减防御，接近每击伤害时收益陡升',3:'回合末扣幸存者，不当作战斗DPS',4:'当前爆炸伤害遍历附近双方单位',5:'运行逻辑停用，不进入有效奖励池',6:'当前实际继承强化，复制品不生成原牌',7:'区域持续到本场结束，受停留时间影响',8:'双方80%减速，不能直接视为伤害',9:'抽到的牌还要有能量和合法目标',11:'0费可重复循环；是否值3HP需实战',13:'累计己方死亡，后续新生成单位也获得加成',14:'免费出牌，可触发后续连锁；随机位置需折损',15:'当前回到手牌，不加费，可重新满血部署'};
table(cs,6,['效果牌','费用','主效果数值','类型','消耗牌','额外有效生命','额外单位伤害','附加战力','净获得能量','玩家生命成本','兑现率','毛能量价值','净能量价值','风险或规则','来源','副效果'],snap.cards.map(c=>{
 const e=c.effects[0],kind=e.kind;
 const hp=kind===2?null:kind===1?null:0;
 const damage=kind===0?null:kind===4?e.amount:kind===7?null:0;
 const extra=kind===6?1:kind===9?0.6:kind===14?2:0;
 const gain=kind===11?c.effects.find(x=>x.kind===17)?.amount??0:0;
 const pay=kind===11?e.amount:0;
 const prob=kind===1||kind===3||kind===5?0:kind===14?0.6:kind===4?0.7:1;
 return[c.card_name,c.card_cost,e.amount,kindLabels[kind],c.after_use===1?'是':'否',hp,damage,extra,gain,pay,prob,null,null,warnings[kind]||'根据实际触发次数校准',c.path,c.effects.slice(1).map(e=>'kind='+e.kind+' amount='+e.amount).join('；')];
}));
input(cs,'B7:C21');input(cs,'F7:K21');cs.getRange('N6:N53').format.columnWidth=64;cs.getRange('O6:O53').format.columnWidth=62;cs.getRange('A6:A53').format.columnWidth=23;cs.getRange('K7:K21').format.numberFormat='0%';
for(let i=0;i<snap.cards.length;i++){
 const row=i+7,e=snap.cards[i].effects[0];
 if(e.kind===4)formula(cs,'G'+row,'=C'+row);
 if(e.kind===6)formula(cs,'H'+row,"='单位战力'!P"+sr);
 if(e.kind===14)formula(cs,'H'+row,"=C"+row+"*'单位战力'!P"+sr);
 if(e.kind===11)formula(cs,'J'+row,'=C'+row);
 if(e.kind===2)formula(cs,'F'+row,"='单位战力'!O"+sr+"*(MAX('调参总览'!$B$10-'单位战力'!F"+sr+",1)/MAX('调参总览'!$B$10-'单位战力'!F"+sr+"-C"+row+",1)-1)");
 if(e.kind===1)formula(cs,'F'+row,"='单位战力'!O"+sr+"*C"+row+"/100");
 if(e.kind===0)formula(cs,'G'+row,"='单位战力'!M"+sr+"*C"+row+"/MAX('单位战力'!E"+sr+"-'调参总览'!$B$11,1)*'调参总览'!$B$14");
 if(e.kind===7)formula(cs,'G'+row,"=C"+row+"*'调参总览'!$B$14/"+e.interval);
 formula(cs,'L'+row,"=((SQRT((1+F"+row+"/'单位战力'!O"+sr+")*(1+G"+row+"/('单位战力'!M"+sr+"*'调参总览'!$B$14)))-1)*'单位战力'!P"+sr+"+H"+row+")*K"+row+"+I"+row+"-J"+row+"*'调参总览'!$B$33");
 formula(cs,'M'+row,'=L'+row+'-B'+row);
}
table(cs,25,['遗物','类型','数值','抽牌阈值','生效范围'],snap.relics.map(r=>[r.display_name,['抽牌能量','玩家生命','旧城防','首次护甲','能量上限'][r.kind],r.amount,r.draw_threshold,r.kind===2?'已停用':r.kind===3?'仅首轮单位':'本局']));
cs.getRange('N25:O25').values=[['遗物说明','来源']];cs.getRange('N26').write(snap.relics.map(r=>[r.description,r.path]));
table(cs,36,['药水','每跳伤害','间隔秒','观察秒数','命中跳数','平均目标','覆盖率','估计总伤害','折算能量'],snap.potions.map(p=>[p.display_name,p.damage,p.interval,p.kind===0?p.duration:12,null,1.5,0.5,null,null]));
cs.getRange('N36:O36').values=[['药水说明','来源']];cs.getRange('N37').write(snap.potions.map(p=>[p.description,p.path]));input(cs,'B37:D39');input(cs,'F37:G39');
for(let i=0;i<snap.potions.length;i++){const row=i+37,p=snap.potions[i];
 formula(cs,'E'+row,p.kind===1?'='+p.casts:'=1+MAX(0,INT((D'+row+'-0.000001)/C'+row+'))');
 formula(cs,'H'+row,'=B'+row+'*E'+row+'*F'+row+'*G'+row);
 formula(cs,'I'+row,"=H"+row+"/('单位战力'!M"+sr+"*'调参总览'!$B$14)");
}
value(cs,'A42','药水先命中一次。火焰持续到本轮结束；龙卷持续6秒；闪电4次须实际点完。');
value(cs,'A44','遗物和药水的真实价值，应看省下的玩家生命与改变的交锋胜负。');
title(rs,'一条路线的生命与金币收支','10节点为设计示例，并非当前导入路线；采用较高战损检验生命预算。金币支出只是未来商店预算。',16,20);
const plan=[['普通战斗',8,0.70,2,0,0,0],['招募事件',0,1,0,0,0,0],['普通战斗',8,0.70,2,0,0,0],['休息',0,1,0,20,0,0],['普通战斗',8,0.70,2,0,0,0],['遗物事件',0,1,0,0,0,0],['普通战斗',8,0.70,2,0,0,0],['普通战斗',8,0.70,2,0,0,0],['休息',0,1,0,20,0,0],['Boss',10,0.65,3,0,0,0]];
table(rs,6,['节点','类型','预计交锋数','交锋胜率','败轮幸存扣血和','期望损失生命','回复生命','获得金币','花费金币','进入生命','离开生命','进入金币','离开金币','生命状态','说明','设计依据'],plan.map((p,i)=>[i+1,p[0],p[1],p[2],p[3],null,p[4],p[5],p[6],null,null,null,null,null,'按同胜率简化估计；非通关率','建议首版路线']));
input(rs,'B7:E16');input(rs,'G7:I16');rs.getRange('D7:D16').format.numberFormat='0%';rs.getRange('O6:O16').format.columnWidth=55;
for(let r=7;r<=16;r++){
 formula(rs,'F'+r,'=(1-D'+r+')*(C'+r+'*(C'+r+'+1)/2+C'+r+'*E'+r+')');
 formula(rs,'J'+r,r===7?"='调参总览'!$B$31":'=K'+(r-1));
 formula(rs,'K'+r,"=IF(J"+r+"<=0,0,IF(J"+r+"-F"+r+"<=0,0,MIN('调参总览'!$B$31,J"+r+"-F"+r+"+G"+r+")))");
 formula(rs,'L'+r,r===7?"='调参总览'!$B$32":'=M'+(r-1));
 formula(rs,'M'+r,'=MAX(0,L'+r+'+H'+r+'-I'+r+')');
 formula(rs,'N'+r,'=IF(K'+r+'<=0,"死亡",IF(K'+r+"<'调参总览'!$B$31*0.25,\"生命偏低\",\"尚有余量\"))");
}
rs.getRange('K7:K16').conditionalFormats.add('cellIs',{operator:'lessThanOrEqual',formula:0,format:{fill:'#FDE1DC',font:{color:'#AA3027'}}});
title(ts,'试玩记录与胜率区间','每行一场同版本、同关卡、同策略的遭遇；当前没有填入虚构试玩数据。最多200行。',16,222);
value(ts,'A6','有效场次');formula(ts,'B6','=COUNT(O23:O222)');value(ts,'A7','遭遇胜率');formula(ts,'B7','=IF(B6=0,"",AVERAGE(O23:O222))');
value(ts,'A8','95%区间下限');formula(ts,'B8',"=IF(B6=0,\"\",(B7+'调参总览'!$B$35^2/(2*B6)-'调参总览'!$B$35*SQRT(B7*(1-B7)/B6+'调参总览'!$B$35^2/(4*B6^2)))/(1+'调参总览'!$B$35^2/B6))");
value(ts,'A9','95%区间上限');formula(ts,'B9',"=IF(B6=0,\"\",(B7+'调参总览'!$B$35^2/(2*B6)+'调参总览'!$B$35*SQRT(B7*(1-B7)/B6+'调参总览'!$B$35^2/(4*B6^2)))/(1+'调参总览'!$B$35^2/B6))");ts.getRange('B7:B9').format.numberFormat='0.0%';
value(ts,'A11','来源：https://www.itl.nist.gov/div898/handbook/prc/section2/prc241.htm');
value(ts,'A13','上方统计全部有效行，不随Excel筛选变化；比较分组时复制所需行到空白副本。');
value(ts,'A15','重复测试同一玩家或同一随机种子的样本不独立，区间只作为方向参考。');
table(ts,22,['版本','随机种子','局ID','关卡','策略/牌组','药水次数','可用能量','消耗能量','准备秒','交锋总秒','交锋轮数','进入生命','离开生命','败轮扣血和','胜利1失败0','问题备注'],Array.from({length:200},()=>Array(16).fill(null)));input(ts,'A23:P222');ts.freezePanes.freezeRows(22);ts.getRange('E22:E222').format.columnWidth=25;ts.getRange('P22:P222').format.columnWidth=65;ts.getRange('O23:O222').dataValidation={rule:{type:'whole',operator:'between',formula1:0,formula2:1}};
for(const sh of [us,ks,ws,cs,rs])sh.getRange('A6:'+col(sh===us?28:sh===ks?18:16)+'6').format.rowHeight=40;
const data=waveRows.slice(0,12).map((o,i)=>[String(o.r),null,null,null]);
table(ov,45,['回合','基础能量','抽牌附加','压力比'],data);
for(let i=0;i<12;i++){const r=46+i,w=i+7;formula(ov,'B'+r,"='波次压力'!F"+w);formula(ov,'C'+r,"='波次压力'!G"+w);formula(ov,'D'+r,"='波次压力'!L"+w);}
const chart=ov.charts.add('line',[ov.getRange('A45:A57'),ov.getRange('D45:D57')]);chart.title='level_001 波次压力（估算）';chart.setPosition('F28','N43');chart.hasLegend=false;chart.titleTextStyle.fontSize=13;chart.titleTextStyle.typeface='Arial';chart.xAxis={axisType:'textAxis',textStyle:{typeface:'Arial',fontSize:10}};chart.yAxis={numberFormatCode:'0.0',numberFormatSourceLinked:false,textStyle:{typeface:'Arial',fontSize:10}};chart.series.items[0].line={fill:'#476FA5',style:'solid',width:2};
us.getRange('C7:F27').format.numberFormat='0';us.getRange('H7:H27').format.numberFormat='0';us.getRange('S7:S27').format.numberFormat='0';us.getRange('W7:Z27').format.numberFormat='0';us.getRange('AA7:AA27').format.numberFormat='0%';us.getRange('AB7:AB27').format.numberFormat='0';
ks.getRange('D7:E54').format.numberFormat='0';ks.getRange('I7:I54').format.numberFormat='0';ks.getRange('J7:J54').format.numberFormat='0.0';
ws.getRange('B7:G66').format.numberFormat='0';ws.getRange('M7:N66').format.numberFormat='0';cs.getRange('B7:C21').format.numberFormat='0';cs.getRange('D6:D21').format.columnWidth=18;
rs.getRange('A7:A16').format.numberFormat='0';rs.getRange('C7:C16').format.numberFormat='0';rs.getRange('E7:E16').format.numberFormat='0';rs.getRange('F7:M16').format.numberFormat='0.0';
ts.getRange('B6').format.numberFormat='0';ov.getRange('G9:G10').format.numberFormat='0';ov.getRange('B14:B24').format.numberFormat='0';ov.getRange('B31:B32').format.numberFormat='0';ov.getRange('B34').format.numberFormat='0';
for(let i=0;i<snap.cards.length;i++){const r=i+7,e=snap.cards[i].effects[0];if([1,2].includes(e.kind))cs.getRange('F'+r).format.fill='#FFFFFF';if([0,4,7].includes(e.kind))cs.getRange('G'+r).format.fill='#FFFFFF';if([6,14].includes(e.kind))cs.getRange('H'+r).format.fill='#FFFFFF';if(e.kind===11)cs.getRange('J'+r).format.fill='#FFFFFF';}
cs.getRange('N7:O21').format.wrapText=true;cs.getRange('A7:P21').format.rowHeight=36;cs.getRange('N26:O32').format.wrapText=true;cs.getRange('A26:O32').format.rowHeight=43;cs.getRange('N37:O39').format.wrapText=true;cs.getRange('A37:O39').format.rowHeight=48;
wb.recalculate();
const v=(sh,cell)=>sh.getRange(cell).values[0][0];
const before=v(us,'P'+sr),knightRow=unitRows.get(snap.units.find(x=>x.unit_english_name==='knight').path),kp=v(us,'P'+knightRow),kh=v(us,'D'+knightRow);
value(us,'D'+knightRow,kh*2);wb.recalculate();const after=v(us,'P'+knightRow);if(Math.abs(after/kp-Math.sqrt(2))>1e-8)throw Error('HP sensitivity failed');value(us,'D'+knightRow,kh);
value(ov,'B19',1);wb.recalculate();if(v(ws,'G7')!==1)throw Error('Energy modifier sensitivity failed');value(ov,'B19',0);
value(ts,'O23',1);value(ts,'O24',0);wb.recalculate();if(v(ts,'B6')!==2||v(ts,'B7')!==0.5)throw Error('Trial aggregation failed');ts.getRange('O23:O24').clear({applyTo:'contents'});
const origin=ov.getRange('B22').values[0][0];value(ov,'B22',0);wb.recalculate();if(v(ov,'G7')!=='参数无效')throw Error('Deck boundary failed');value(ov,'B22',origin);wb.recalculate();
console.log('KEY_RESULTS',JSON.stringify({soldier:before,knight:kp,firstHandNoUnit:v(ov,'G7'),firstHandNoFront:v(ov,'G8'),routeEndHp:v(rs,'K16'),trialN:v(ts,'B6'),skillRows:skillRows.length}));
const errors=await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:3000});console.log('ERROR_SCAN',errors.ndjson);
console.log((await wb.inspect({kind:'table',range:'单位战力!A7:T10',include:'values,formulas',tableMaxRows:4,tableMaxCols:20,maxChars:4000})).ndjson);
await fs.mkdir(new URL('./previews/',import.meta.url),{recursive:true});
for(const name of names){const end=name==='调参总览'?'N43':name==='单位战力'?'T15':name==='技能输出'?'P17':name==='波次压力'?'N19':name==='效果与资源'?'M16':name==='路线收支'?'N17':'P28';const blob=await wb.render({sheetName:name,range:'A1:'+end,scale:1,format:'png'});await fs.writeFile(new URL('./previews/'+name+'.png',import.meta.url),new Uint8Array(await blob.arrayBuffer()));}
for(const [name,range,file] of [['效果与资源','A25:O44','资源说明'],['单位战力','T6:AB27','原始单位'],['调参总览','A45:D57','压力明细']]){const blob=await wb.render({sheetName:name,range,scale:1,format:'png'});await fs.writeFile(new URL('./previews/'+file+'.png',import.meta.url),new Uint8Array(await blob.arrayBuffer()));}
const output=await SpreadsheetFile.exportXlsx(wb);await output.save(fileURLToPath(new URL('../数值调参工作簿.xlsx',import.meta.url)));
await fs.writeFile(new URL('./model_validation.json',import.meta.url),JSON.stringify({date:'2026-10-08',units:snap.units.length,skills:skillRows.length,levels:snap.levels.length,formulaErrorScan:errors.ndjson,hpSensitivity:{before:kp,doubled:after},deckChance:{noUnits:v(ov,'G7'),noFront:v(ov,'G8')},routeHp:v(rs,'K16'),trialRowsEmpty:v(ts,'B6')},null,2));
console.log('EXPORT_OK');
