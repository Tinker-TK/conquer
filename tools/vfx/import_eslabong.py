"""Port recovered Eslabong visual resources into an isolated Godot namespace.

Input recovery lives under .maintenance/eslabong; shipped files never depend on it.
The original installation is read only. Run after GDRETools resource recovery.
"""
from pathlib import Path
import collections
import hashlib
import json
import re
from fix_eslabong_spawns import rewrite_spawns

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.maintenance/eslabong'
SOURCE = WORK / 'recovered'
DEST = ROOT / 'assets/effect/eslabong_vfx'
PREFIX = 'res://assets/effect/eslabong_vfx/'
REFS = re.compile(r'res://[^"\n\\]+\.(?:tscn|tres|gdshaderinc|gdshader|gd|png|svg|webp|jpg|wav|ogg|mp3)(?![a-zA-Z])')
PRESERVED_EXTRA = {'OrbitingBladeVFX.gd', 'RicochetBladeVFX.gd', 'SpinningBladeVFX.gd', 'EffectBurnGround.gd', 'ReaverDynamiteAxeExplosionVFX.gd', 'terrify_impact.gd', 'TextureScroller.gd', 'DesperatePrayer.gd', 'righteous_ward.gd', 'fire_barrier.gd', 'LassoProjectile.gd', 'BurningFire.gd'}
PRESERVED_EXTRA.add('Projectile.gd')

def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8', newline='\n')

def category(path):
    name = path.stem.lower()
    if 'StatusEffects' in path.parts: return '持续状态'
    if 'projectile' in name: return '投射物'
    if 'beam' in name or 'bolt' in name and 'lightning' in name: return '光束雷电'
    if any(x in name for x in ('ground','decal','storm','barrier','prison','burnground','gravitywell')): return '范围地面'
    if any(x in name for x in ('orbit','shield','ward','buff','immolation','heat-trail','trail','charge')): return '持续光环'
    if any(x in name for x in ('cast','launch','windup','resurrect','portal','blink','departure','arrival')): return '施法传送'
    if any(x in name for x in ('heal','mend','rejuvenation')): return '治疗恢复'
    if any(x in name for x in ('arc','blade','slash','thrust','strike','hammer','melee')): return '近战攻击'
    if 'sparks' in name: return '粒子火花'
    return '命中爆发'

def label(name):
    translations = {'VFX':'', 'Impact':'命中', 'Cast':'施法', 'Burst':'爆发', 'Ground':'地面', 'Decal':'印记', 'Sparks':'火花', 'Fireball':'火球', 'Fire':'火焰', 'Ice':'冰霜', 'Poison':'毒', 'Lightning':'雷电', 'Electric':'电能', 'Holy':'神圣', 'Nature':'自然', 'Arcane':'奥术', 'Shadow':'暗影', 'Blood':'鲜血', 'Shield':'护盾', 'Heal':'治疗', 'Burn':'灼烧', 'Freeze':'冻结', 'Stun':'眩晕', 'Sleep':'睡眠', 'Charm':'魅惑', 'Rage':'狂怒', 'Regen':'再生', 'Weaken':'虚弱', 'Slow':'减速', 'Silence':'沉默', 'Fear':'恐惧', 'Bleed':'流血', 'Blessed':'祝福', 'Curse':'诅咒', 'Armor':'护甲', 'Greed':'贪欲', 'Projectile':'飞行弹', 'Portal':'传送门', 'Smoke':'烟雾', 'Beam':'光束', 'Storm':'风暴', 'Thrust':'突刺', 'Slash':'斩击', 'Orbit':'环绕', 'Shards':'碎片', 'Explosion':'爆炸', 'Physical':'物理', 'Earth':'大地', 'Water':'水', 'Wind':'风', 'Wood':'木屑', 'Net':'网', 'Confusion':'混乱', 'Entangled':'缠绕'}
    words = re.sub(r'([a-z])([A-Z])', r'\1 \2', name).replace('_',' ').split()
    translations.update({'Bubble':'罩','Ambient':'环境','Poof':'烟团','Premium':'强化','Shard':'碎片','Shatter':'碎裂','Glacial':'冰川','Prison':'牢笼','Righteous':'正义','Ward':'结界','Barrier':'屏障','Prayer':'祈祷','Chain':'连锁','Wave':'波浪','Ember':'余烬','Everwinter':'永冬','Frost':'寒霜','Emberfall':'陨火','Petrification':'石化','Stab':'刺击','Hammer':'重锤','Arc':'弧光','Blade':'刀刃','Trail':'尾迹','Dash':'冲刺','Cast':'施法','Light':'光芒','Wrath':'怒火','Burning':'燃烧','Entangling':'缠绕','Roots':'根须','Ground':'地面','Bolt':'飞弹','Whirlwind':'旋风','Slam':'重击','Vine':'藤蔓','Rejuvenation':'回春','Resurrection':'复活'})
    return ' · '.join(translations.get(w,w) for w in words if translations.get(w,w))

def main():
    seeds = set((SOURCE/'Scenes/VFX').rglob('*.tscn'))
    for p in (SOURCE/'Scenes').rglob('*.tscn'):
        n=p.stem.lower()
        if any(w in n for w in ['projectile','explosionvfx','deadeyewindupvfx']) or p.stem in {'PortalEffect','GravityWellEffect','PoofVFX','GenericBeam','HollowExplosion','FireBarrier','RighteousWard'}:
            if 'Turrets' not in p.parts: seeds.add(p)
    seeds.add(SOURCE/'Art/VFX/TerrifyImpact.tscn')
    for p in (SOURCE/'Scenes').glob('*.tscn'):
        if not any(w in p.stem.lower() for w in ['arena','mercenary','test','damage_number']):seeds.add(p)
    seeds.update((SOURCE/'Scenes/Abilities').glob('*.tscn'))
    seeds.update((SOURCE/'Scripts/VFX').rglob('*.tscn'))
    queue=[p.relative_to(SOURCE).as_posix() for p in seeds]
    queue += [p.relative_to(SOURCE).as_posix() for p in (SOURCE/'Scripts/VFX').rglob('*.gd') if p.stem not in {'VFXPool','LoopingAudio'}]
    queue += [p.relative_to(SOURCE).as_posix() for p in SOURCE.rglob('*.gdshader')]
    seen=set();textures=set();adapted=[];preserved=[]
    class_names={}
    for p in (SOURCE/'Scripts/VFX').rglob('*.gd'):
        m=re.search(r'class_name\s+(\w+)',p.read_text(encoding='utf-8'))
        if m:class_names[m[1]]=p.relative_to(SOURCE).as_posix()
    class_names['SelfDestructParticles']='Scripts/VFX/SelfDestructParticles.gd'
    while queue:
        rel=queue.pop()
        if rel in seen:continue
        seen.add(rel)
        src=SOURCE/rel
        if src.suffix in {'.png','.webp','.jpg','.svg'}:
            textures.add(rel);continue
        if src.suffix in {'.wav','.mp3','.ogg'}:continue
        if not src.exists():
            if src.suffix=='.gdshaderinc' and (WORK/'text'/rel).exists():src=WORK/'text'/rel
            else:raise FileNotFoundError(src)
        text=src.read_text(encoding='utf-8')
        recovered_projectile=rel=='Scripts/Projectile.gd'
        if recovered_projectile:
            text=re.sub(r'\bProjectile\b', 'EslabongRecoveredProjectile', text)
            physics='''func _physics_process(delta: float) -> void:
\t_update_ability_flight_vfx(delta)
\t_refresh_upright_animated_visuals()
\tif spin_speed != 0.0 and _visual_node != null:
\t\t_visual_node.rotation += deg_to_rad(spin_speed) * delta
\tif animation_fps > 0.0 and _visual_node is Sprite2D:
\t\tvar total_frames: int = _visual_node.hframes * _visual_node.vframes
\t\t_anim_timer += delta
\t\tif total_frames > 1:
\t\t\t_visual_node.frame = int(_anim_timer * animation_fps) % total_frames
\tif get_meta("sequence_driven", false):
\t\treturn
\tvar step := minf(speed, 420.0) * delta
\tposition += _direction * step
\t_traveled_dist += step
\tif _traveled_dist >= 280.0:
\t\tif impact_vfx != null:
\t\t\tpreload("res://assets/effect/eslabong_vfx/runtime/pool.gd").spawn_for(self, impact_vfx, global_position)
\t\tqueue_free()

'''
            text=re.sub(r'^func _physics_process\([^)]*\)[^\n]*\n.*?(?=^func |^static func |\Z)', physics, text, flags=re.M|re.S)
            text=re.sub(r'^func _on_body_entered\([^)]*\)[^\n]*\n.*?(?=^func |^static func |\Z)', 'func _on_body_entered(_body: Node) -> void:\n\tpass\n\n', text, flags=re.M|re.S)
            text=text.replace('\t_setup_time_scaled_tictac_sfx()','\t# Audio is supplied by the host game.')
        visual_script=src.suffix=='.gd' and ('/VFX/' in '/'+rel or src.name in PRESERVED_EXTRA)
        if src.suffix=='.gd' and not visual_script:
            # Projectile movement is supplied by the library's visual adapter.
            resource_script=bool(re.search(r'extends (?:StatusEffect|AbilityEffect|Resource|RefCounted)\b',text))
            text='extends Resource\n' if resource_script else 'extends "'+PREFIX+'runtime/projectile_visual.gd"\n'
            if rel in {'Scenes/fire_wave_spike.gd', 'Scenes/ice_wave_spike.gd'}:
                text='extends "'+PREFIX+'runtime/wave_spike_visual.gd"\n'
            adapted.append(rel)
        else:
            queue.extend(p.removeprefix('res://') for p in REFS.findall(text) if not p.endswith(('.ogg','.mp3','.wav')) and not p.startswith(PREFIX))
            if visual_script:
                aliases=[]
                inherited=''
                ancestor=re.search(r'extends "res://([^"]+)"',text)
                while ancestor:
                    ancestor_text=(SOURCE/ancestor[1]).read_text(encoding='utf-8')
                    inherited+='\n'+ancestor_text
                    ancestor=re.search(r'extends "res://([^"]+)"',ancestor_text)
                if 'current_scene' in text and 'VFXPool' not in text:text+='\n# VFXPool scopes runtime child visuals.\n'
                uses_clock='.create_timer(' in text or 'Time.get_ticks_msec()' in text or src.name=='HolyLightVFX.gd'
                if uses_clock:text+='\n# Clock owns playback time and visual timers.\n'
                if '.create_timer(' in inherited or 'Time.get_ticks_msec()' in inherited:inherited+='\nClock\n'
                for symbol, target in {**class_names, 'VFXPool':'../runtime/pool.gd', 'GameFeel':'../runtime/game_feel.gd', 'Faction':'../runtime/faction.gd', 'CastContext':'../runtime/context.gd', 'EffectBeam':'../runtime/beam_data.gd', 'Mercenary':'../runtime/mercenary_type.gd', 'Projectile':'../runtime/projectile_type.gd', 'StatusEffect':'../runtime/status_type.gd', 'StatusEffectModifier':'../runtime/status_type.gd', 'AIControllerComponent':'../runtime/ai_compat.gd', 'Clock':'../runtime/clock.gd'}.items():
                    if re.search(r'\b'+symbol+r'\b',text) and not re.search(r'class_name\s+'+symbol+r'\b',text) and not re.search(r'\b'+symbol+r'\b',inherited):
                        path=PREFIX+('runtime/'+target.split('/')[-1] if target.startswith('../') else 'source/'+target)
                        aliases.append(f'const {symbol} = preload("{path}")')
                        if not target.startswith('../'):queue.append(target)
                # Keep global class names private to this imported library.
                text=re.sub(r'^class_name\s+\w+\s*\n','',text,flags=re.M)
                lines=text.splitlines();n=next(i for i,l in enumerate(lines) if l.startswith('extends '))
                lines[n+1:n+1]=['']+aliases+['']
                text='\n'.join(lines)+'\n'
                if recovered_projectile:text='class_name EslabongRecoveredProjectile\n'+text
                text=text.replace('VFXPool.spawn_configured(', 'VFXPool.spawn_configured_for(self, ').replace('VFXPool.spawn(', 'VFXPool.spawn_for(self, ')
                text=text.replace('return tree.root.get_node_or_null(VFX_POOL_AUTOLOAD_PATH)', 'return VFXPool.pool_for(self)')
                text=re.sub(r'\b(\w+)\.get_tree\(\)\.current_scene', lambda m:f'VFXPool.pool_for({m[1]}).get_parent()', text)
                text=re.sub(r'(?<![.\w])get_tree\(\)\.current_scene', 'VFXPool.pool_for(self).get_parent()', text)
                text=re.sub(r'func _release_ghost\(ghost: Sprite2D\) -> void\s*:[\s\S]*?(?=\nfunc |\nstatic func |\Z)', 'func _release_ghost(ghost: Sprite2D) -> void:\n\tif is_instance_valid(ghost):\n\t\tghost.visible = false\n\t\tghost.queue_free()\n\n', text)
                text=text.replace('for area in get_overlapping_areas():', 'for area in ([] if not monitoring else get_overlapping_areas()):')
                text=re.sub(r'\b(\w+)\.(get_overlapping_bodies|get_overlapping_areas)\(\)', lambda m:f'([] if not {m[1]}.monitoring else {m[0]})',text)
                text=re.sub(r'\b(\w+)\.get_tree\(\)\.create_timer\(', lambda m:f'Clock.timer_for({m[1]}, ', text)
                text=re.sub(r'(?<![.\w])(?:get_tree\(\)|tree)\.create_timer\(', 'Clock.timer_for(self, ', text)
                text=text.replace('SceneTreeTimer', 'Timer').replace('Time.get_ticks_msec()', 'Clock.ticks_for(self)')
                text=re.sub(r'^static func [\s\S]*?(?=^func |^static func |\Z)', lambda m:m[0].replace('Clock.ticks_for(self)', 'Time.get_ticks_msec()').replace('Clock.timer_for(self, ', '(Engine.get_main_loop() as SceneTree).create_timer('), text, flags=re.M)
                text=re.sub(r'\b(is|as|const) Projectile\b', r'\1 EslabongProjectileType', text)
                text=re.sub(r': Projectile\b', ': EslabongProjectileType', text)
                text=re.sub(r'\bProjectile\.', 'EslabongProjectileType.', text)
                text=text.replace('var lifetime: = maxf(_get_particle_lifetime(), longest_sprite_duration)', 'var lifetime: = maxf(_get_particle_lifetime(), maxf(longest_sprite_duration, float(anim_player.current_animation_length) if anim_player != null else 0.0))')
                # A suspended coroutine must not retain a GPU material after its
                # owner is cleared before its timer elapses.
                text=text.replace('\tparticles.process_material = mat\n', '\tparticles.process_material = mat\n\tmat = null\n')
                text=text.replace('\tparticles.color_ramp = grad\n', '\tparticles.color_ramp = grad\n\tgrad = null\n')
                text=re.sub(r'(func _start_vfx_deferred\(\)[^\n]*\n)', r'\1\tif not is_inside_tree():\n\t\treturn\n', text)
                if src.name=='HolySparks.gd':text=text.replace('\tmat = null\n', '\tmat = null\n\tgrad = null\n\ttex = null\n')
                if src.name=='GlacialPrisonVFX.gd':
                    text=text.replace('_target.global_position + Vector2(0, -18)', '_target.global_position + (Vector2.ZERO if _target.get_meta("eslabong_visual_anchor", false) else Vector2(0, -18))')
                if src.name=='BurningFire.gd':
                    text=text.replace('_mercenary.global_position + CROSS_HEAD_OFFSET + Vector2(0, _cross_y_offset)', '_mercenary.to_global(CROSS_HEAD_OFFSET + Vector2(0, _cross_y_offset))')
                if src.name=='DeadeyeWindupVFX.gd':
                    text=text.replace('_line.global_position = Vector2.ZERO', '_line.position = Vector2.ZERO')
                    text=text.replace('_line.add_point(global_position)', '_line.add_point(_line.to_local(global_position))')
                    text=text.replace('_line.add_point(_laser_target_pos)', '_line.add_point(_line.to_local(_laser_target_pos))')
                    text=text.replace('glow.add_point(global_position)', 'glow.add_point(glow.to_local(global_position))')
                    text=text.replace('glow.add_point(_laser_target_pos)', 'glow.add_point(glow.to_local(_laser_target_pos))')
                if src.name=='HolyLightVFX.gd':
                    text=text.replace('\tawait tween.finished', '\ttween = null\n\tawait Clock.timer_for(self, expand_duration).timeout')
                    text=text.replace('\t\tawait pulse_tween.finished', '\t\tpulse_tween = null\n\t\tawait Clock.timer_for(self, 0.1).timeout')
                    text=text.replace('\tawait tween2.finished', '\ttween2 = null\n\tawait Clock.timer_for(self, retract_duration).timeout')
                text=rewrite_spawns(text, src.name)
                preserved.append(rel)
            text=REFS.sub(lambda m:PREFIX+'runtime/silent.tres' if m[0].endswith(('.wav','.ogg','.mp3')) else PREFIX+'source/'+m[0].removeprefix('res://'),text)
            # REFS already includes newly added aliases; repair only that prefix.
            text=text.replace(PREFIX+'source/assets/effect/eslabong_vfx/',PREFIX)
            text=re.sub(r' uid="uid://[^"]+"','',text)
            if rel == 'Scenes/VFX/HeatTrailVFX.tscn':
                # Rect copies produced uninitialised screen pixels inside scaled
                # SubViewports on D3D12. Copy the viewport before each refraction.
                text=text.replace('"values": [1, 0]', '"values": [2, 0]')
                text=re.sub(r'(\[node name="BackBufferCopy"[^\n]+\]\n)', r'\1copy_mode = 2\n', text)
            text=re.sub(r'global uniform float combat_vfx_time;', '#define combat_vfx_time TIME',text)
            text=re.sub(r'res://Art/UI/Fonts/[^"\n]+\.(?:ttf|otf)', 'res://assets/fonts/numbers/lilita_one/LilitaOne-Regular.ttf', text)
            text=re.sub(r'\tvar tree := get_tree\(\)\n\tif tree != null:\n\t\tawait tree.create_timer\(([0-9.]+)\).timeout\n\t\tif is_instance_valid\(self\):\n\t\t\tqueue_free\(\)',lambda m:'\tvar expiry := Timer.new()\n\texpiry.one_shot = true\n\texpiry.wait_time = '+m[1]+'\n\tadd_child(expiry)\n\texpiry.timeout.connect(queue_free)\n\texpiry.start()',text)
        write(DEST/'source'/rel,text)
    # Collect texture imports from the original pack. Native Godot restores pixels.
    jobs=[]
    for rel in sorted(textures):
        meta=(WORK/'text'/(rel+'.import')).read_text(encoding='utf-8')
        match=re.search(r'path="(res://[^\"]+\.ctex)"',meta)
        if match is None:raise ValueError(rel)
        jobs.append({'input':match[1],'output':str(DEST/'source'/rel).replace('\\','/')})
    write(WORK/'texture_jobs.json',json.dumps(jobs,ensure_ascii=False,indent=2))
    items=[]
    for src in sorted(seeds):
        rel=src.relative_to(SOURCE).as_posix();cat=category(src)
        original=src.read_text(encoding='utf-8')
        mode='projectile' if cat=='投射物' else 'beam' if cat=='光束雷电' else 'continuous' if cat in {'持续状态','持续光环'} else 'oneshot'
        if src.stem=='CleanArcadePostProcess':mode='postprocess';cat='屏幕着色器'
        fidelity='visual_adapter' if any('res://'+x in original for x in adapted) else 'recovered_projectile' if 'res://Scripts/Projectile.gd' in original else 'recovered_visual'
        items.append({'id':rel.removesuffix('.tscn').replace('/','_').lower(),'name':label(src.stem),'original_name':src.stem,'category':cat,'mode':mode,'path':PREFIX+'source/'+rel,'source_path':'res://'+rel,'fidelity':fidelity,'replay_seconds':5.2 if cat in {'范围地面','持续状态','持续光环'} else 0.85 if 'LightningBolt' in src.stem else 2.8})
    # Pure procedural effects have no .tscn in the exported game.
    for file,cat in [('ShadowPriest/ShadowPriestVFX','暗影祭司'),('MeleeTechniqueVFX','近战招式'),('MeleeDebuffVFX','持续状态')]:
        original=(SOURCE/'Scripts/VFX'/(file+'.gd')).read_text()
        enum=re.search(r'enum Style\s*\{([^}]+)\}',original)[1]
        for i,style in enumerate(re.findall(r'\b[A-Z][A-Z_]+\b',enum)):
            rel='procedural/'+file.replace('/','_')+'_'+style.lower()+'.tscn'
            content=f'[gd_scene format=3]\n\n[ext_resource type="Script" path="{PREFIX}source/Scripts/VFX/{file}.gd" id="1"]\n\n[node name="{style}" type="Node2D"]\nscript = ExtResource("1")\n'
            if 'ShadowPriest' not in file:content+=f'style = {i}\n'
            write(DEST/rel,content)
            items.append({'id':style.lower()+'_'+file.split('/')[-1].lower(),'name':label(style.title()),'original_name':style,'category':cat,'mode':'continuous' if cat=='持续状态' or 'AURA' in style else 'oneshot','path':PREFIX+rel,'source_path':'res://Scripts/VFX/'+file+'.gd','recipe':{'style':i,'shadow_priest':'ShadowPriest' in file},'fidelity':'recovered_procedural','replay_seconds':3.0})
    # Every authored presence/orbit profile in the procedural orbit script.
    orbit=(SOURCE/'Scripts/VFX/ArchmageElementOrbitVFX.gd').read_text()
    profiles=sorted(set(re.findall(r'"((?:boss_presence_|relic_orbit_|archmage_element_|boss_element_|celestial_element_)[a-z_]+)"',orbit)))
    for profile in profiles:
        items.append({'id':profile,'name':label(profile.title()),'original_name':profile,'category':'持续光环','mode':'continuous','path':PREFIX+'source/Scenes/VFX/ArchmageElementOrbitVFX.tscn','source_path':'res://Scripts/VFX/ArchmageElementOrbitVFX.gd','recipe':{'elements':[profile]},'fidelity':'recovered_procedural','replay_seconds':5.0})
    # Original impact scripts select distinct geometry for ability signatures.
    for stem in ['ElementalImpactVFX','FireballImpactVFX']:
        s=(SOURCE/'Scripts/VFX'/(stem+'.gd')).read_text()
        ids=sorted(set(re.findall(r'&"([a-z][a-z0-9_]+)"',s)))
        base=next((x for x in items if x['original_name']==('ArcaneImpactVFX' if stem=='ElementalImpactVFX' else stem)),None)
        for ability in ids:
            if ability in {'suppress_screenshake','pooled','manual_start','default'}:continue
            entry=dict(base);entry.update(id=stem.lower()+'_'+ability,name=label(ability.title()),original_name=ability,category='技能变体',recipe={'ability_vfx_id':ability},fidelity='recovered_procedural')
            if stem=='ElementalImpactVFX':
                family={'arcane_torpedo':'ArcaneTorpedoImpactVFX','guiding_light':'GuidingLightImpactVFX','javalin':'SpearThrustImpactVFX','rock_throw':'RockThrowImpactVFX','shaman_bolt':'ShamanPoisonImpactVFX'}.get(ability,'ChronoNeedleImpactVFX' if ability.startswith(('chrono','deadline')) else 'ArcaneImpactVFX')
                authored=next((x for x in items if x['original_name']==family),base)
                entry['path']=authored['path']
            items.append(entry)
    catalog={'source_game':'Eslabong Demo','source_engine':'Godot 4.6.0','recovered_pack_sha256':hashlib.sha256((WORK/'decrypted.pck').read_bytes()).hexdigest(),'items':items,'coverage':{'core_vfx_scenes':len(list((SOURCE/'Scenes/VFX').rglob('*.tscn'))),'recovered_scenes':len(seeds),'preserved_visual_scripts':len(preserved),'adapted_scripts':adapted,'textures':len(textures),'categories':dict(collections.Counter(i['category'] for i in items))}}
    write(DEST/'catalog.json',json.dumps(catalog,ensure_ascii=False,indent=2))
    write(DEST/'catalog_data.gd', 'extends RefCounted\n## Generated by tools/vfx/import_eslabong.py; export-safe catalog.\nconst DATA: Dictionary = '+json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
    write(DEST/'source_manifest.json',json.dumps({'files':sorted(seen),'textures':sorted(textures),'preserved_visual_scripts':sorted(preserved),'adapted_scripts':adapted},ensure_ascii=False,indent=2))
    print(json.dumps(catalog['coverage'],ensure_ascii=False));print('CATALOG',len(items),'TEXTURES',len(jobs))

if __name__=='__main__':main()
