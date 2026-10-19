"""Generate an offline designer's handbook from real project paths and exported fields."""
from pathlib import Path
from datetime import datetime
import json
import re

ROOT = Path(__file__).resolve().parents[2]

def entry(key, title, summary, paths, schemas, steps, notes, mode='检查器配置'):
    return dict(id=key, title=title, summary=summary, paths=paths, schemas=schemas,
                steps=steps, notes=notes, mode=mode)

entries = [
entry('run','开局数值与初始牌组','调整初始生命、金币、卡组，以及开局携带的遗物和药水。',
 ['data/run/run_start_data.tres'],['data/run/run_start_data.gd'],
 ['打开配置资源，在 Inspector 修改初始数值。','在 cards 数组放入 UnitData 征召牌或 CardDefinition 卡牌；重复引用代表多张牌。','保存后从主菜单重新开局，当前已经创建的牌不会被追溯修改。'],
 ['玩家 HP 由 RunManager 保存，进入新战斗继承当前生命；正式战场使用 HUD 显示 HP。','测试用的遗物开局配置放在 examples/data/run_items_example.tres。']),
entry('units','单位属性与兵种','调整生命、攻击、防御、移速、卡面、费用，以及主动和反击技能。',
 ['data/units/','scenes/units/'],['data/units/unit_data.gd'],
 ['复制一份单位 .tres，再修改属性与 skills 列表。','将单位场景根节点的 unit_data 指向对应资源。','用于征召的 unit_english_name 必须对应 scenes/units/ 中同名 .tscn。','己方使用 team_a 与对应单位脚本，敌方使用 team_b；分组与碰撞层也要一致。'],
 ['多种敌人仍共享 orc.tres。修改它会影响这些敌人；下方单位映射表可查实际引用。','necromancer 已有独立数据；skeleton 目前仍使用 orc.tres 的属性。','unit_type 枚举保留历史值；实际征召场景由 unit_english_name 拼接，勿随意重排枚举。']),
entry('skills','技能、命中帧与冷却','配置攻击、治疗、范围、投射物、冲刺和召唤。',
 ['data/skills/','scripts/skills/'],['data/skills/skill_base.gd','scripts/skills/arrow_attack.gd','scripts/skills/area_attack.gd','scripts/skills/dash_attack.gd'],
 ['复制同类型技能 .tres，沿用对应技能实现脚本。','设置 cooldown、priority、cast_range 和 target_type。','cast_animation 填单位精灵里的动作名，hit_frame 填生效帧索引。','把技能资源放到单位 skills 数组；反击技能放 dodge_skill，并设置 dodge_rate。'],
 ['帧索引从 0 开始；多个 hit_frame 会触发多次效果。','priority 越大越先选择；技能冷却在开始动作时计算。','正常施法动画应关闭循环。manual_finish 只供自行收尾的技能使用。','新增一种技能行为需要编写 execute，现成类型只需配置。']),
entry('summon','死灵法师召唤','summon 第 6 帧出现魔法阵，魔法阵播完后在原位置生成骷髅。',
 ['data/skills/necromancer_summon.tres','data/units/necromancer.tres','scenes/units/necromancer.tscn','scenes/effects/creat_effect.tscn','scenes/units/skeleton.tscn'],
 ['scripts/skills/summon_unit.gd'],
 ['在 necromancer 场景中拖动 SummonPoint 标记，指定相对角色的召唤位置。','在技能资源调整 cooldown、hit_frame，或替换 summon_scene。','特效实际动画名为 green_magic_circle，必须关闭循环。'],
 ['默认冷却 8 秒、priority 10、SELF 目标、hit_frame [5]。','SummonPoint 优先于 summon_offset；位置在放出特效时固定，不追随角色移动。','角色翻转精灵不会自动翻转标记位置。召唤场景必须与施法者同阵营。','召唤师死亡、离树或离开自动战斗阶段时取消尚未完成的召唤。']),
entry('cards','卡牌与组合效果','配置征召、强化、能力卡，以及目标、消耗和效果期限。',
 ['data/cards/','data/card_effects/card_effect.gd','scenes/cards/unit_card.tscn','examples/data/card_examples.tres'],
 ['data/cards/card_definition.gd','data/card_effects/card_effect.gd'],
 ['复制已有 .tres，设置 category、target、card_cost 和 after_use。','在 effects 数组组合 CardEffect；回复与减速 amount 使用百分数，例如 25。','单位强化用 lifetime 选择本场、指定回合或本局永久；lasting_rounds 指定回合数。','把卡加入 data/run/run_start_data.tres 的 cards 数组，重新开局抽取。'],
 ['地面区域支持本场和指定回合，不支持永久；interval 仅表示伤害结算间隔。','征召使用 summon_unit，普通卡牌效果由 effects 处理。','运行时统一使用 scenes/cards/unit_card.tscn；其它兵种卡场景保留作编辑预览。','随机出牌或收回放在效果列表最后；新机制使用 CUSTOM 并实现脚本验证和执行。']),
entry('levels','关卡规则与波次','配置每轮能量、抽牌、战斗时长和敌人阵型。',
 ['data/levels/','scenes/levels/waves/wave_01.tscn','scenes/levels/templates/wave_template.tscn','scenes/levels/battles/'],
 ['data/levels/battle_level_config.gd'],
 ['复制 level_template.tres，填写关卡名字、场景与数值。','复制 wave_template.tscn，在根节点下直接放敌方单位场景并摆阵。','将波次按回合顺序放进 waves；空项表示该回合不刷新。','在 scenes/app/game_session.tscn 根节点的 node_levels 字典中绑定该资源。'],
 ['波次坐标相对于 Entities/TeamB；保持波次根节点原点与缩放 1。','repeat_waves 关闭时，最后有效波次出完且清场才获胜；开启时循环波次，清光当前敌人即可获胜。','经地图进入时，关卡配置覆盖场景内时长、能量、抽牌和波次。','F6 直接运行战场不会自动加载某个关卡 .tres；用绑定后的 GameSession 验证。','当前 wave_01 实际有 5 个兽人，资源中“双兽人”是历史显示名，不作为刷怪依据。']),
entry('terrain','战场、地形与镜头','可视化摆放建筑、树木、地砖和导航，调整镜头范围。',
 ['scenes/battle/battle_scene.tscn','scenes/levels/templates/battle_template.tscn','scenes/levels/battles/battle_001.tscn','scenes/world/tree01.tscn','scenes/units/player_base.tscn'],
 ['scripts/battle/battle_scene.gd','scripts/battle/battle_camera.gd'],
 ['复制继承战场模板，为关卡建立自己的战场场景。','在 Level 下编辑地形、碰撞和树木；改变障碍后重新烘焙 NavigationRegion2D。','正式战场不再实例化 PlayerBase；旧场景保留为兼容资源，玩家生命在开局配置设置。','修改 Camera2D 对应脚本的 view_bounds 和 move_speed。'],
 ['征召落点受实际导航区域的己方半场限制；deployment_rect 只是兼容字段。','不要重命名 Entities/TeamA、Entities/TeamB、HandManager、BattleRoundManager、CardUI 等脚本依赖的节点。','碰撞约定：team_a 第 1 层、team_b 第 2 层、entity 第 3 层、land 第 4 层。']),
entry('relics','遗物','配置抽牌回能、基地生命、防御与开场护甲。',
 ['data/relics/','examples/scenes/items_demo.tscn'],['data/relics/relic_definition.gd'],
 ['复制对应 kind 的资源，设置唯一 id、显示文本和图标。','按类型配置 amount、draw_threshold 或 rounds。','放进开局配置 starting_relics，或由奖励逻辑调用 RunManager.add_relic。'],
 ['遗物按 id 去重；相同 id 不会重复获得。','DRAW_ENERGY 按真实抽到的牌累计；每跨过 draw_threshold 发放 amount 点能量。','配置遗物资源不等于已经做了掉落奖励入口；当前可通过开局配置或示例验证。']),
entry('potions','药水','配置龙卷风、落雷、火焰的伤害、范围、次数与持续时间。',
 ['data/potions/','scenes/effects/potion_effect.tscn','examples/data/run_items_example.tres'],['data/potions/potion_definition.gd'],
 ['复制 tornado、lightning 或 fire 配置，设置 kind 和 targets。','按类型调整 damage、radius、interval、duration、speed 或 casts、cast_delay。','加入开局配置 starting_potions，在自动战斗时从 HUD 使用。'],
 ['同类药水可持有多瓶；首次合法施放才消耗指定药水实例。','药水的 duration 是秒数，与卡牌效果的回合期限不同。']),
entry('map','地图路线与事件','用地图工坊和事件工坊配置路线、节点关卡、事件选项与奖励。',
 ['scenes/app/game_session.tscn','scenes/map/map.tscn','scenes/map/nodes/','scripts/map/map.gd','scripts/map/event_panel.gd'],
 ['scripts/app/game_session.gd','scripts/map/map.gd'],
 ['GameSession 的 node_levels 按地图节点 ID 绑定关卡，event_levels 提供事件 ID 回退。','地图图标在 Map 根节点检查器配置。','固定路线通过地图工坊编辑并导入；事件通过事件工坊编辑 data/events/ 中的资源。'],
 ['优先级：node_levels → event_levels → 旧 battle_scenes → 默认战场。','起点节点为 battle_a / battle_b，中间如 floor_03_0，终点为 boss。','默认路线为十层；导入固定路线的通关条件按实际地图终点判定。','现有事件奖励通过工坊配置；新增一种奖励机制才需要实现对应运行逻辑。'], '检查器 + 脚本'),
entry('visual','界面、美术与动画','替换卡面、UI 主题、角色帧动画和特效贴图。',
 ['scenes/ui/','scenes/cards/unit_card.tscn','assets/characters/','assets/ui_redrawn/','assets/ui_extracted/','assets/animations/generated/','themes/','shaders/'],[],
 ['单位与卡牌的卡面图在对应数据资源修改；全局卡面布局在 unit_card.tscn 编辑。','人物 AnimatedSprite2D 的 SpriteFrames 保存动作，修改名字时同步技能 cast_animation。','UI 皮肤在 themes，受击与选中效果在 shaders。','原画 raw、drafts 已忽略导入；运行贴图与这些源文件分开维护。'],
 ['assets 中未接入的素材和授权来源仍保留，不按静态引用数量删除。','MechaGirl 是独立素材示例，尚不代表已加入单位数据或初始牌组。','批量特效插件默认把 SpriteFrames 输出到 assets/animations/generated。']),
entry('tools','配置插件与开发入口','保留数据表编辑器、特效导入器和开发连接服务。',
 ['addons/data_table_editor/','addons/batch_effect_importer/','autoload/mcp_interaction_server.gd','project.godot'],[],
 ['数据表插件扫描 data 的一级分类目录，并识别其中的 Resource 结构脚本。','单位、技能、卡牌、遗物、药水、关卡和开局数据均按此规则存放。','目前 project.godot 启用批量特效插件；数据表插件可在项目设置的插件页启用。'],
 ['autoload 是系统入口，普通数值配置不必修改它。','tests 与 tools 不会被正式流程主动调用；维护结果写到 .maintenance。'], '开发工具'),
]

labels = {
'max_hp':'最大生命','starting_hp':'开局生命','starting_gold':'开局金币','cards':'初始牌组',
'starting_relics':'开局遗物','starting_potions':'开局药水','unit_name':'显示名称',
'unit_english_name':'场景文件名','unit_type':'历史兵种枚举','unit_team':'阵营',
'defence':'防御','attack':'攻击','speed':'移动速度','dodge_rate':'闪避概率（0～1）',
'card_cost':'能量费用','card_name':'卡牌名称','card_image':'卡面图片','card_image_2':'叠加卡面图片',
'card_discription':'卡牌说明','skills':'主动技能列表','dodge_skill':'闪避反击技能',
'skill_name':'技能名称','description':'说明','attack_rate':'攻击倍率','cooldown':'冷却（秒）',
'priority':'选择优先级','cast_range':'施法距离','manual_finish':'技能自行结束',
'cast_animation':'施法动画名','hit_frame':'生效帧索引（从 0 开始）','target_type':'索敌规则',
'on_hit_effect':'命中特效场景','summon_scene':'召唤单位场景','summon_marker_path':'落点标记节点路径',
'summon_offset':'无标记时的落点偏移','effect_animation':'召唤特效动画名',
'projectile_scene':'投射物场景','projectile_trajectory':'弹道类型','pierce_count':'可穿透目标数',
'projectile_pos':'发射位置偏移','category':'卡牌类别','target':'目标类型','after_use':'使用后去向',
'summon_unit':'征召单位配置','effects':'按顺序执行的效果','kind':'效果类型','amount':'效果数值',
'lifetime':'生效期限','lasting_rounds':'持续回合数','radius':'作用半径','interval':'结算间隔（秒）',
'affected_team':'影响阵营','level_name':'关卡显示名','notes':'设计备注','battle_scene':'战场场景',
'waves':'逐回合波次列表','repeat_waves':'循环波次','battle_duration':'每轮战斗秒数',
'energy_per_round':'每轮基础能量','cards_per_round':'每轮抽牌数','id':'唯一标识',
'display_name':'显示名称','icon':'图标','draw_threshold':'触发所需抽牌张数','rounds':'持续回合数',
'targets':'受影响阵营','damage':'伤害','duration':'持续秒数','casts':'施放次数','cast_delay':'连续施放间隔',
'move_speed':'镜头移动速度','view_bounds':'镜头范围','battlefield_rect':'战场落点矩形',
'deployment_rect':'旧兼容部署范围','card_ui':'战斗界面节点引用','battle_scenes':'旧场景回退字典',
'node_levels':'地图节点 → 关卡','event_levels':'事件 ID → 关卡','map_node_scene':'地图节点模板',
'battle_icon':'战斗图标','event_icon':'事件图标','rest_icon':'休息图标','boss_icon':'首领图标',
}

for item in entries:
    item['fields'] = []
    for path in item['schemas']:
        assert (ROOT/path).is_file(), path
        for line in (ROOT/path).read_text(encoding='utf-8').splitlines():
            m = re.search(r'@export\w*(?:\([^\n]*?\))?\s+var\s+(\w+)(.*)', line)
            if m:
                name, declaration = m.groups()
                item['fields'].append(dict(name=name, label=labels.get(name,name),
                                           declaration=declaration.strip(), source=path))
    for path in item['paths']:
        assert (ROOT/path).exists(), path

files=[]
for p in ROOT.rglob('*'):
    rel=p.relative_to(ROOT)
    if p.is_file() and not any(x.startswith('.') or x in {'node_modules', '__pycache__'} for x in rel.parts) and p.suffix not in {'.uid','.import'}:
        files.append(dict(path=rel.as_posix(), size=p.stat().st_size))
units=[]
for p in sorted((ROOT/'scenes/units').glob('*.tscn')):
    text=p.read_text(encoding='utf-8')
    match=re.search(r'path="res://(data/units/[^\"]+)"',text)
    units.append(dict(scene=p.relative_to(ROOT).as_posix(),data=match.group(1) if match else '由脚本初始化'))
manifest=json.loads((ROOT/'docs/reorganization_manifest.json').read_text(encoding='utf-8'))
# Preserve the historical manifest on disk, but link only current destinations in the guide.
current_moves={'tests/config_catalog_export.gd':'addons/game_config_editor/config_catalog_export.gd',
               'tests/config_catalog_export.gd.uid':'addons/game_config_editor/config_catalog_export.gd.uid',
               'tests/navigation_bake_check.gd':'tools/maintenance/navigation_bake.gd',
               'tests/navigation_bake_check.gd.uid':'tools/maintenance/navigation_bake.gd.uid'}
manifest['moved']={old:current_moves.get(new,new) for old,new in manifest['moved'].items()
                   if (ROOT/current_moves.get(new,new)).exists()}
manifest['moved'].update(current_moves)
checks_path=ROOT/'.maintenance/checks/current/results.json'
checks=json.loads(checks_path.read_text(encoding='utf-8')) if checks_path.exists() else []
audit_path=ROOT/'.maintenance/path_audit.json'
audit=json.loads(audit_path.read_text(encoding='utf-8')) if audit_path.exists() else {}
load_log=ROOT/'.maintenance/checks/current/resources.log'
load_match=re.search(r'RESOURCE_LOAD_CHECK: (\d+) resources; failures=\[\]',load_log.read_text(encoding='utf-8',errors='replace')) if load_log.exists() else None
data=dict(entries=entries,files=sorted(files,key=lambda f:f['path']),units=units,
          migration=manifest,checks=checks,audit=audit,generated=datetime.now().strftime('%Y-%m-%d %H:%M'),
          root=str(ROOT),resource_checks=int(load_match.group(1)) if load_match else '未验证')
template=(ROOT/'tools/maintenance/guide_template.html').read_text(encoding='utf-8')
html=template.replace('__PROJECT_DATA__',json.dumps(data,ensure_ascii=False).replace('</',r'<\/'))
(ROOT/'docs/project_architecture.html').write_text(html,encoding='utf-8')
print('Built docs/project_architecture.html:',len(entries),'configuration topics,',len(files),'files.')
