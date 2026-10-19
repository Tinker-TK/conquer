import fs from 'node:fs/promises';
import path from 'node:path';
const root='E:/MyGame/Game11/conquer/trunk/ballsprite';
async function walk(p) {const out=[];for(const e of await fs.readdir(p,{withFileTypes:true})) {if(['.godot','.maintenance','.git','assets'].includes(e.name))continue;const q=path.join(p,e.name);if(e.isDirectory())out.push(...await walk(q));else out.push(q);}return out;}
const files=await walk(root);
const out={date:'2026-10-08',resources:{},scenes:{}};
for(const f of files.filter(f=>f.endsWith('.tres')&&f.includes(path.sep+'data'+path.sep))) {
 const t=await fs.readFile(f,'utf8');const refs={};
 for(const m of t.matchAll(/\[ext_resource[^\n]*path="([^"]+)"[^\n]*id="([^"]+)"\]/g))refs[m[2]]=m[1];
 const parts=t.split(/^\[resource\]\s*$/m), props={};
 for(const m of (parts[1]||'').matchAll(/^(\w+) = (.*)$/gm))props[m[1]]=m[2];
 out.resources[path.relative(root,f).replaceAll('\\','/')]={refs,props,text:t};
}
for(const f of files.filter(f=>f.endsWith('.tscn')&&(f.includes(path.sep+'levels'+path.sep)||f.includes(path.sep+'units'+path.sep)))) {
 const t=await fs.readFile(f,'utf8');out.scenes[path.relative(root,f).replaceAll('\\','/')]=t;
}
await fs.writeFile(path.join(root,'docs/数值设计/support/project_snapshot.json'),JSON.stringify(out,null,2));
console.log(JSON.stringify({resources:Object.keys(out.resources).length,scenes:Object.keys(out.scenes).length}));
for(const [k,v] of Object.entries(out.resources))console.log(k,JSON.stringify(v.props),JSON.stringify(v.refs));
for(const [k,v] of Object.entries(out.scenes).filter(([k])=>k.includes('levels/')))console.log('WAVE',k,v);
for(const f of files.filter(f=>f.endsWith('.json')&&f.includes(path.sep+'data'+path.sep+'levels'))) console.log('MAP',path.relative(root,f),(await fs.readFile(f,'utf8')).slice(0,15000));
