/* Current resource report uses exactly the same engine as the offline calculator. */
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const M=require('./unit_power_calculator_model.js');
const out=path.resolve(__dirname,'..');
const root=path.resolve(__dirname,'../../..');
const seed=JSON.parse(fs.readFileSync(path.join(__dirname,'unit_power_calculator_seed.json'),'utf8'));
const current=M.evaluateAll(seed.defaults,seed.reference);
const resultFile=path.join(out,'单位战力_计算结果.json');
const old=fs.existsSync(resultFile)?JSON.parse(fs.readFileSync(resultFile,'utf8')):null;
const unchanged=old?.version===seed.version&&old.units.every(u=>{
 const now=seed.defaults.units.find(v=>v.id===u.id),r=current.result.get(u.id);
 return now&&u.max_hp===now.hp&&u.attack===now.attack&&u.defence===now.defence&&Math.abs(u.result.total_power-r.current.power)<1e-8&&Math.abs(u.upgraded_result.power-r.upgraded.power)<1e-8;
});
const previous=unchanged ? old.previous : old ? {
  version:old.version,date:old.date,units:old.units.map(u=>({id:u.id,name:u.unit_name||u.name,hp:u.max_hp??u.hp,attack:u.attack,defence:u.defence,power:u.result.total_power??u.result.power}))
}:null;
const f=(n,d=1)=>n===null?'—':n.toFixed(d);
const table=(headers,rows)=>['| '+headers.join(' | ')+' |','| '+headers.map(()=>'---').join(' | ')+' |',...rows.map(r=>'| '+r.join(' | ')+' |')].join('\n');
const rows=[];
for(const u of seed.defaults.units){
 const r=current.result.get(u.id);
 rows.push({...u,unit_name:u.name,unit_team:u.team,max_hp:u.hp,card_cost:u.cost,dodge_rate:u.dodge,
  result:{...r.current,effective_hp:r.current.ehp,equivalent_output:r.current.output,body_power:r.current.bodyPower,summon_power:r.current.summonPower,total_power:r.current.power,power_per_initial_energy:r.current.perCost},
  upgraded_result:r.upgraded,gain:r.gain,curve:r.curve});
}
for(const s of seed.sources){
 const actual=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,s.path))).digest('hex');
 if(actual!==s.sha256)throw Error('项目资源在计算期间变化：'+s.path);
}
const data={version:seed.version,date:seed.date,sourceRevision:seed.sourceRevision,model:seed.defaults.model,baseline:current.baseline,
 scope:'当前全局资源；未训练与真实训练1次全攻；无地形/外部强化。技能按强化等级数组精确匹配。隐身、抽牌、其他友军光环和瞬移接敌收益未折分。',
 units:rows,sources:seed.sources,previous,validation:{units:rows.length,live_sources:seed.sourceCount,actual_combat_measured:false,soldier_power:current.result.get('soldier').current.power,sources_unchanged_during_calculation:true}};
fs.writeFileSync(resultFile,JSON.stringify(data,null,2));
const ordered=[...rows].sort((a,b)=>a.team.localeCompare(b.team)||seed.reference.unitIds.indexOf(a.id)-seed.reference.unitIds.indexOf(b.id));
const allies=ordered.filter(u=>u.team==='team_a'),enemies=ordered.filter(u=>u.team==='team_b');
const allyRows=allies.map(u=>[u.name,`${u.hp}/${u.attack}/${u.defence}`,u.cost,f(u.result.power),f(u.upgraded_result.power),f(u.gain*100)+'%',f(u.result.perCost),f(u.upgraded_result.perCost)]);
const enemyRows=enemies.map(u=>[u.name,`${u.hp}/${u.attack}/${u.defence}`,u.cost,f(u.result.power),f(u.result.perCost),u.result.summonPower?'含召唤贡献 '+f(u.result.summonPower):'当前未训练资源']);
const changes=allies.map(u=>{
 const before=previous?.units.find(v=>v.id===u.id);
 if(!before)return null;
 return [u.name,`${before.hp}/${before.attack}/${before.defence}`,`${u.hp}/${u.attack}/${u.defence}`,f(before.power),f(u.result.power),f(u.result.power-before.power)];
}).filter(Boolean);
const skillRows=ordered.map(u=>[u.name,
 u.skills.filter(s=>!s.kind.endsWith('_passive')&&s.unlock.includes(0)).map(s=>s.name).join('、')||'无主动技能',
 u.team==='team_a'?(u.skills.filter(s=>!s.kind.endsWith('_passive')&&s.unlock.includes(1)).map(s=>s.name).join('、')||'无主动技能'):'不适用',
 u.skills.filter(s=>s.kind.endsWith('_passive')).map(s=>`${s.name}[${s.unlock.join(',')}]`).join('、')||'—']);
const effectRows=allies.filter(u=>u.result.unpricedEffects.length||u.upgraded_result.unpricedEffects.length||u.result.comboBonus).map(u=>[u.name,[...new Set([...u.result.unpricedEffects,...u.upgraded_result.unpricedEffects])].join('；')||`连击每成功命中攻击+${u.result.comboBonus}；按目标生命${seed.defaults.model.comboTargetHp}、击杀后清零计入输出`]);
const doc=`# 单位战力与计算标准

日期：${seed.date}；版本：${seed.version}；资源版本：${seed.sourceRevision}。

本次直接读取当前 **${rows.length} 个单位与 ${seed.sourceCount} 项资源/脚本**，按最新属性、技能动画、冷却、生效等级和被动重算。未训练士兵固定为 **100 分**。本表是可量化交锋战力估价，不是实战胜率。

## 当前己方单位与训练后战力

未训练为强化等级0；训练后为等级1，按每个单位当前训练能力点全部加攻击，未添加卡牌、遗物、战术或波次增益。当前全部己方每次训练2点、训练上限1次。战费比为战力/初始征召能量。

${table(['单位','当前生命/攻/防','初费','当前战力','训练1次战力','提升','当前战费比','训练战费比'],allyRows)}

## 当前敌方单位

敌方没有玩家篝火训练入口，本版按实际等级0资源计算；不把自定义+3攻击示例当作敌方真实强化。敌方费用为配置参考，不代表刷怪耗能。

${table(['单位','当前生命/攻/防','配置费','当前战力','战力/配置费','说明'],enemyRows)}

## 与上一版结果比较

${previous?`比较对象：${previous.version}，${previous.date}。属性与技能均以本次资源为准；战力变化也包含技能生效等级、主动技能替换及被动规则修正。`:'无上一版结果。'}

${changes.length?table(['单位','旧生命/攻/防','当前生命/攻/防','旧战力','当前战力','差值'],changes):'—'}

## 技能生效等级核对

数组按当前强化等级**精确匹配**：[0]只在未训练生效，[1]只在训练一次生效，[0,1]两种状态生效，[]停用。不能把训练后失效的技能继续计入输出。被动不占施法时间。当前默认生效等级为[0,1]，超出已有等级配置时可能没有主动技能。

${table(['单位','等级0主动技能','等级1主动技能','被动及生效等级'],skillRows)}

## 特殊收益及计分边界

${table(['单位','计算处理'],effectRows)}

- 剑士连击已计入：每击按当时基础攻击加连击层数计算，命中后叠层；参考目标生命100，目标死亡后清零并切换下一目标。伤害仍按既有理论伤害口径计分，不另外扣除过量伤害。参考目标生命可在计算器中修改。
- 圣殿骑士训练后自身获得攻击+2，已计入自身输出。对其他友军的加成取决于阵容与覆盖情况，未叠到单个单位战力中。
- 狼人隐身不是伤害免疫；5秒隐身的索敌、生存收益及瞬移接敌收益暂未折分。骑士上场抽牌的牌组收益也未折分。因此其战费比不能单独作为改费依据。
- 骑兵当前原冲刺在等级0/1都生效，等级1额外冲刺也生效：计算器按两个独立技能冷却处理。两份资源的实际冲刺距离都为默认600、速度300；加强版的射程450与冷却5秒改变可施放范围与频率，没有把文案“距离加长”当作额外冲刺距离。
- 反击净DPS仍为0，闪避按反击技能当前等级是否生效计算。反击打断普通施法的净收益需要实测校准。

## 公式与统一标准

\`\`\`text
每击伤害 = max(floor(当前攻击 × 技能倍率) − 对手防御, 1)
有效生命 = 生命 × 15 / max(15 − 防御, 1) / (1 − 生效闪避率 × 0.7)
等效输出 = DPS + 0.5 × 有效HPS
本体战力 = 100 × sqrt(有效生命/基准有效生命 × 等效输出/基准等效输出)
总战力 = 本体战力 + 召唤贡献
征召战费比 = 总战力 / (征召费用 + 退场加费)
\`\`\`

基准士兵有效生命${f(current.baseline.ehp)}，等效输出${f(current.baseline.output,6)}。窗口12秒，对手防御5、闪避0，近战在线率80%、远程100%，范围/冲刺平均目标1.5；直线穿透平均1.5且不超过配置上限。治疗与吸血兑现50%，有效治疗以0.5折算；召唤兑现75%。士兵剑矢按近战/远程各50%的窗口加权。全部开场技能就绪，施法互斥、按优先级排程、冷却从开始施法计算。

移动速度、控制、地形、毒、死亡爆炸和幸存结算扣血尚未折分。地图波次、牌组永久强化与正在进行的游戏存档状态未混入全局单位初值。

## 更新的文件与使用方式

- \`单位战力计算器.html\`：已装入本次项目初值、正确的等级数组及新被动。项目资源版本变化会使用独立的浏览器保存位置，打开时不会自动载入上一版旧初值；原来的调参方案仍可导入。
- \`单位战力_计算结果.json\`：每单位的完整当前/训练结果、曲线、施法排程、旧结果对照和资源指纹。
- 本文：当前21单位战力及计算口径。

重新生成计算器及报告：

\`\`\`powershell
python docs/数值设计/support/calculate_unit_power.py
\`\`\`

仅更新文档与计算器；本次计算过程已校验读取的项目资源没有变化。
`;
fs.writeFileSync(path.join(out,'单位战力与计算标准.md'),doc);
console.log(JSON.stringify({version:seed.version,units:rows.length,sourceRevision:seed.sourceRevision,rows:ordered.map(u=>({name:u.name,hp:u.hp,attack:u.attack,defence:u.defence,cost:u.cost,current:+f(u.result.power),trained:u.team==='team_a'?+f(u.upgraded_result.power):null,perCost:+f(u.result.perCost),trainedPerCost:u.team==='team_a'?+f(u.upgraded_result.perCost):null}))}));
