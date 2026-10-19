import fs from 'node:fs/promises';
const s=JSON.parse(await fs.readFile(new URL('./runtime_snapshot.json',import.meta.url),'utf8'));
const skills=Object.fromEntries(s.skills.map(x=>[x.path,x]));
for(const u of s.units){const sc=s.unit_scenes.find(x=>x.unit.path===u.path);console.log(JSON.stringify({id:u.unit_english_name,hp:u.max_hp,atk:u.attack,def:u.defence,cost:u.card_cost,skills:u.skills.map(p=>{const k=skills[p];return {id:p.split('/').pop(),rate:k.attack_rate,cd:k.cooldown,hits:k.hit_frame.length,anim:sc?.animations[k.cast_animation]?.duration,priority:k.priority};})}));}
for(const l of s.levels)console.log('LEVEL',JSON.stringify({path:l.path,repeat:l.repeat_waves,start:l.repeat_start,end:l.repeat_end,waves:l.waves.map(w=>w.units.map(u=>({name:u.unit.unit_english_name,hp:u.unit.max_hp,atk:u.unit.attack,def:u.unit.defence,growth:u.growth})))}));
