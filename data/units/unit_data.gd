# 这玩意儿是干嘛的（核心逻辑）：保存单位属性、卡面和技能配置，供场景和出牌系统读取。
# 数据是咋流动的（数据流向）：Inspector 中的配置进入资源，再由战斗或界面节点读取并执行。
# 为啥这么写（选型决策）：保持原有接口，把同类职责归到一起，便于查找和配置。
# 性能咋样（复杂度）：资源本身不运行每帧循环，仅在对应系统使用时处理。
class_name UnitData
extends Resource
enum MonsterRank { NORMAL, ELITE, BOSS, LEGENDARY }

## 单位的中文显示名称，用于单位详情、测试按钮和招募界面；不会改变单位所属阵营或战斗属性。
@export var unit_name: String = '名字'
## 单位场景的英文标识，征召时按 res://scenes/units/此标识.tscn 查找场景。必须与实际场景文件名一致。
@export var unit_english_name: String = 'soldier'
## 兵种分类，用于区分步兵、骑兵等单位类型；选择项目已有的兵种枚举，不会自动赋予技能。
@export var unit_type: Global.UnitType = Global.UnitType.SOILDIER
## 单位阵营标识。team_a 为己方，team_b 为敌方；决定队伍分组、索敌和效果的敌我判断。
@export var unit_team: String = 'team_a'
## 怪物等级：普通、精英、首领、传说。策反只允许普通敌军；等级独立于兵种、数值与波次成长。
@export var monster_rank: MonsterRank = MonsterRank.NORMAL
@export_group('战斗单位属性')
## 单位的基础最大生命值，也是出场时的初始生命。单位受到伤害后死亡；训练、强化和本局增益可能在此基础上增加生命。
@export var max_hp: int = 100
## 单位的基础防御，每次普通受击从攻击伤害中扣除；普通命中至少造成 1 点伤害。药水等直接效果伤害使用各自的结算规则。
@export var defence: int = 5
## 单位的基础攻击力，技能通常以攻击力乘以 Attack Rate 计算伤害或治疗量，再交给目标结算防御等规则。
@export var attack: int = 15
# 存活到获胜结算时对敌方玩家造成的伤害，与普通攻击力无关。
## 此单位存活到获胜回合结算时，对败方玩家造成的额外生命伤害。与单位攻击力无关；0 表示此单位不贡献额外扣血。
@export_range(0, 100, 1) var hp_damage_value: int = 1
## 单位移动的基础速度，单位为世界像素/秒；越大则移动越快，减速效果会在此基础上计算。飞行跨层的快速升降使用独立速度。
@export var speed: float = 150.0       # 移动速度
## 飞行单位直接飞向目标，忽略地形碰撞和导航路线；跨越楼层时每层快速升降 64 像素。
@export var is_flying: bool = false
## 普通攻击的闪避概率，按 0～1 配置；0.25 表示 25%，0 从不闪避，1 必定闪避。直接效果伤害不走此闪避判定。
@export var dodge_rate: float = 0.0

@export_group('单位牌属性')
## 这张单位征召牌的基础能量费用。退场加费等本局规则会修改具体卡牌的实际费用，不会改写此资源的基础值。
@export_range(0, 3, 1) var card_cost: int = 1
## 单位征召牌显示在卡面上的名称，可以与单位名称不同；不会改变实际召唤的单位。
@export var card_name: String
## 单位征召牌的主卡面图片，显示在 CardImage 区域；只控制卡牌外观。
@export var card_image: Texture2D
## 单位征召牌的第二层插图或图集区域，显示在 CardImage2 区域；用于单位立绘等卡面装饰。
@export var card_image_2: AtlasTexture
## 基础征召牌说明，供配置预览使用。正式卡面按当前训练等级展示征召、上场效果和生效技能；修改文案不会改变实际战斗属性或技能。
@export var card_discription: String

@export_group('训练升级')
# 每次训练授予的能力点；玩家自行分配到攻击或防御，1 点增加 1 点属性。
## 每次篝火训练授予此兵种卡的能力点数。玩家分配到攻击或防御，每 1 点增加对应属性 1 点；进度按本局每张具体卡牌独立保存。
@export_range(0, 999, 1) var upgrade_ability_points: int = 3
# 0 表示不可训练。次数按本局每张具体兵种卡独立记录。
## 本局中每张此兵种卡最多可训练的次数。0 表示不可训练；复制或新获得的具体卡牌分别记录训练次数。
@export_range(0, 99, 1) var max_upgrade_count: int = 1

@export_group('技能栏属性')
## 单位技能资源列表，包含主动技能和驻场被动。仅装配解锁强化等级数组包含当前强化次数的技能；主动技能按 Priority、冷却及合法目标选择，需要匹配施法动画。驻场被动独立生效，不占用攻击动作或冷却。
@export var skills: Array[SkillBase] = [
	preload('res://data/skills/normal_attack.tres')
	]
# 防守反击技能
## 单位防守反击时使用的技能资源；留空则没有此反击技能，解锁强化等级数组不包含当前强化次数时不触发反击或对应闪避。反击沿用技能的施法动画、命中帧、倍率和特效配置。
@export var dodge_skill: SkillBase = null

# 仅记录出场单位对应原牌的强化次数；保留复制属性所需的存储标记，不作为策划配置列。
@export_storage var card_upgrade_level: int = 0
@export_storage var soldier_specialization: String = ""
# 出场时原牌费用的快照，忽略临时免费效果；直接测试单位使用card_cost。
@export_storage var combat_card_cost: int = -1


# 基础士兵即有远近普攻；斩击分支舍弃远程。旧强化存档未选分支时按飞弹兼容。
func get_soldier_specialization(upgrade_level: int = -1) -> String:
	var level := card_upgrade_level if upgrade_level < 0 else upgrade_level
	if unit_english_name != "soldier" or level < 1:
		return ""
	return soldier_specialization if soldier_specialization in ["slash", "missile"] else "missile"


func has_sword_arrow(upgrade_level: int = -1) -> bool:
	return unit_team == "team_a" and unit_english_name == "soldier" and get_soldier_specialization(upgrade_level) != "slash"


# 骑士征召牌的上场效果只由成功出牌触发，单位复制、召唤或留在场上不重复抽牌。
func get_deployment_draw_count(upgrade_level: int = -1) -> int:
	if unit_team != "team_a" or unit_english_name != "knight":
		return 0
	var level := card_upgrade_level if upgrade_level < 0 else upgrade_level
	return 3 if level >= 1 else 1


func is_basic_attack(skill: SkillBase) -> bool:
	# 兼容旧存档中尚未保存普通攻击标记的技能快照。
	return skill != null and (skill.is_basic_attack or (
		skill.get_script().resource_path == "res://scripts/skills/normal_attack.gd" \
		and skill.cast_animation == "attack_01" and skill.priority == 0))


static func sword_arrow_description() -> String:
	return "剑矢：普攻可在300范围内发射箭矢，近身使用近战普攻；远近攻击共用冷却。选择斩击强化后不再射箭。"


# 按原牌当前强化次数精确匹配；离开配置等级后原技能失效。
func is_skill_unlocked(skill: SkillBase, upgrade_level: int = -1) -> bool:
	var level := card_upgrade_level if upgrade_level < 0 else upgrade_level
	return skill != null and skill.is_active_at_upgrade_level(level) and (
		skill.soldier_branch.is_empty() or skill.soldier_branch == get_soldier_specialization(level))


# 作用：按原牌强化次数筛选技能；没有参数，返回独立技能列表，不修改共享配置。
func get_unlocked_skills() -> Array[SkillBase]:
	var result: Array[SkillBase] = []
	for skill: SkillBase in skills:
		if is_skill_unlocked(skill):
			result.append(skill)
	return result


@export_group('其它参数')
## 留空按兵种匹配；可填写 human、monster、beast、undead、slime，覆盖受击与死亡音色。
@export var combat_sound_profile: StringName = &""
