# 这玩意儿是干嘛的（核心逻辑）：把游戏资源的英文属性翻译成策划能理解的表格标题。
# 数据是咋流动的（数据流向）：资源属性名和枚举 → 中文显示；保存时仍使用原英文属性名。
# 为啥这么写（选型决策）：显示翻译与实际配置分开，改中文标题不会改变游戏资源格式。
# 性能咋样（复杂度）：字典只在刷新表格时查找，没有每帧计算。
@tool
extends RefCounted

const TITLES := {"cards": "卡牌效果", "card_effects": "卡牌效果明细", "allies": "己方单位特性", "enemies": "敌方单位特性", "skills": "技能配置", "relics": "遗物效果", "potions": "药水效果"}
const KEYS := {
	"cards": ["card_name", "card_cost", "rarity", "category", "target", "after_use", "retain_in_hand", "starts_in_hand", "max_upgrade_count", "upgrade_cost_change", "card_discription", "effects"],
	"card_effects": ["kind", "amount", "upgrade_amount", "upgrade_lasting_rounds", "status_seconds", "upgrade_status_seconds", "upgrades_drawn_cards", "upgrade_upgrades_drawn_cards", "next_round_penalty", "can_convert_elite", "upgrade_can_convert_elite", "lifetime", "lasting_rounds", "radius", "interval", "affected_team"],
	"allies": ["unit_name", "card_cost", "max_hp", "attack", "defence", "hp_damage_value", "upgrade_ability_points", "max_upgrade_count", "speed", "is_flying", "dodge_rate", "skills", "dodge_skill"],
	"enemies": ["unit_name", "monster_rank", "max_hp", "attack", "defence", "hp_damage_value", "speed", "is_flying", "dodge_rate", "skills", "dodge_skill"],
	"skills": ["unit_name", "skill_name", "unlock_upgrade_levels", "soldier_branch", "stealth_health_percent", "stealth_duration", "teleport_distance", "teleport_effect", "teleport_effect_scale", "teleport_effect_duration", "attack_bonus_per_hit", "aura_radius", "aura_attack_bonus", "aura_include_caster", "aura_effect", "is_basic_attack", "attack_rate", "cooldown", "chant_duration", "overflow_to_shield", "knockback_distance", "knockback_duration", "wall_stun_duration", "self_effect", "consume_shield", "bleed_stacks_per_hit", "blood_return_interval", "upgraded_stun_duration", "counter_armor_break", "taunt_radius", "taunt_duration", "defence_per_attacker", "taunt_effect", "dash_distance", "dash_speed", "dash_count", "dash_pause", "damage_trigger_count", "true_damage_base_percent", "retreat_distance", "retreat_seconds", "advance_seconds", "triple_wind", "wind_attack_rate", "wind_speed", "wind_distance", "wind_radius", "priority", "cast_range", "cast_animation", "hit_frame", "target_type", "on_hit_effect"],
	"relics": ["display_name", "kind", "amount", "draw_threshold", "rounds", "description"],
	"potions": ["display_name", "kind", "targets", "damage", "radius", "interval", "rounds", "speed", "duration", "casts", "cast_delay", "effect_scene", "effect_scale", "effect_offset", "description"]}
const FIELDS := {
	"status_seconds": "状态持续秒数", "upgrade_status_seconds": "强化状态秒数增量", "upgrades_drawn_cards": "誊抄临时强化抽牌", "upgrade_upgrades_drawn_cards": "强化后临时强化抽牌", "next_round_penalty": "下回合上限惩罚",
	"retain_in_hand": "固有（回合末保留）", "starts_in_hand": "开局优先入手",
	"stealth_health_percent": "隐身生命阈值（%）", "stealth_duration": "隐身持续秒数", "teleport_distance": "传送落点距离", "teleport_effect": "传送门特效", "teleport_effect_scale": "传送门缩放", "teleport_effect_duration": "传送门播放秒数",
	"attack_bonus_per_hit": "每次命中攻击加成",
	"aura_radius": "光环半径", "aura_attack_bonus": "庇护攻击加成", "aura_include_caster": "光环包含自身", "aura_effect": "驻场光环特效",
	"is_basic_attack": "普通攻击标记", "soldier_branch": "士兵强化分支",
	"chant_duration": "咏唱秒数", "overflow_to_shield": "溢出治疗转护盾",
	"knockback_distance": "击退距离", "knockback_duration": "击退秒数", "wall_stun_duration": "撞墙眩晕秒数", "self_effect": "自身实验室特效", "consume_shield": "双刀消耗护盾加伤",
	"bleed_stacks_per_hit": "血影每次流血层数", "blood_return_interval": "鲜血回归间隔", "upgraded_stun_duration": "强化反击眩晕秒数",
	"counter_armor_break": "每次反击破甲", "taunt_radius": "嘲讽半径", "taunt_duration": "嘲讽持续秒数", "defence_per_attacker": "每名瞄准敌人防御加成", "taunt_effect": "嘲讽释放特效",
	"dash_distance": "每段冲锋距离", "dash_speed": "冲锋速度", "dash_count": "连续冲锋次数", "dash_pause": "两段冲锋间隔",
	"damage_trigger_count": "七伤触发次数", "true_damage_base_percent": "七伤真伤基数（%）", "retreat_distance": "后撤与前突距离", "retreat_seconds": "后撤秒数", "advance_seconds": "前突秒数", "triple_wind": "强化三道风", "wind_attack_rate": "吹风伤害倍率", "wind_speed": "吹风速度", "wind_distance": "吹风最大距离", "wind_radius": "吹风碰撞半径",
	"pierce_all": "穿透沿途全部敌人",
	"is_flying": "飞行单位",
	"unlock_upgrade_levels": "解锁强化等级",
	"monster_rank": "怪物等级", "crowded_unit_count": "狂化拥挤阈值", "crowded_stat_percent": "拥挤攻防百分比", "solo_attack_bonus_percent": "独存攻击增幅", "solo_defence_bonus_percent": "独存防御增幅", "cooldown_reduction_percent": "独存冷却减少", "required_unit_types": "所需兵种种类", "minimum_attack_percent": "近身攻击百分比", "distance_for_max_bonus": "满增益距离",
	"rarity": "卡牌品质",
	"effect_scene": "使用特效场景", "effect_scale": "特效缩放倍率", "effect_offset": "特效位置偏移",
	"upgrade_ability_points": "升级能力点数", "max_upgrade_count": "可强化次数", "upgrade_amount": "每次强化效果增量", "upgrade_cost_change": "每次强化费用增量", "upgrade_lasting_rounds": "每次强化回合增量", "can_convert_elite": "允许策反精英", "upgrade_can_convert_elite": "强化后可策反精英",
	"unit_name": "单位名称", "unit_english_name": "英文标识", "unit_type": "兵种类型", "unit_team": "阵营", "max_hp": "最大生命", "defence": "防御", "attack": "攻击", "hp_damage_value": "基地扣血值", "speed": "速度", "dodge_rate": "闪避率", "card_cost": "卡牌费用", "card_name": "卡牌名称", "card_discription": "卡牌说明", "card_image": "卡牌图片", "card_image_2": "单位插图",
	"skill_name": "技能名称", "description": "说明文案", "attack_rate": "伤害倍率", "cooldown": "冷却秒数", "priority": "优先级", "cast_range": "施法距离", "manual_finish": "手动结束", "cast_animation": "施法动画", "hit_frame": "命中帧", "target_type": "索敌方式", "on_hit_effect": "命中特效", "projectile_trajectory": "弹道", "pierce_count": "穿透数", "projectile_scene": "投射物", "projectile_pos": "发射偏移", "summon_scene": "召唤单位", "summon_offset": "召唤偏移", "effect_animation": "特效动画", "summon_unit": "征召单位",
	"category": "卡牌类型", "target": "目标类型", "after_use": "使用后", "effects": "效果列表", "lifetime": "期限", "lasting_rounds": "回合数", "kind": "效果类型", "amount": "效果数值", "radius": "半径", "interval": "间隔", "affected_team": "作用阵营", "id": "标识", "display_name": "名称", "draw_threshold": "抽牌门槛", "rounds": "持续回合", "targets": "作用阵营", "damage": "伤害", "duration": "持续秒数", "casts": "次数", "cast_delay": "释放间隔", "skills": "技能列表", "dodge_skill": "防守反击"}
const ENUMS := {"HAND_CARD": "其它手牌", "NORMAL": "普通", "ELITE": "精英", "BOSS": "首领", "LEGENDARY": "传说", "RECRUIT": "征召", "ENHANCEMENT": "强化", "ABILITY": "能力", "NONE": "无目标", "ALLY": "友军", "ENEMY": "敌军", "ANY_UNIT": "任意单位", "POSITION": "战场位置", "DISCARD": "弃牌堆", "EXHAUST": "消耗区", "PERSIST": "常驻至战斗结束", "COMMON": "普通（蓝框）", "RARE": "稀有（金框）", "BATTLE": "本场", "ROUNDS": "指定回合", "RUN": "本局", "ENEMIES": "敌军", "ALLIES": "友军", "BOTH": "双方", "DRAW_ENERGY": "抽牌获能量", "BASE_HEALTH": "基地生命", "BASE_DEFENCE": "基地防御", "OPENING_DEFENCE": "开战防御", "TORNADO": "龙卷风", "LIGHTNING": "闪电", "FIRE": "火焰", "THUNDER_CLOUD": "雷云", "ENEMY_NEAREST": "最近敌人", "ALLY_LOWEST_HP": "低血友军", "SELF": "自身", "ENEMY_LOWEST_HP": "最低生命敌人", "ENEMY_LOWEST_HP_PERCENT": "最低生命比例敌人", "ENEMY_FARTHEST": "最远敌人"}
const EFFECTS := {32: "流血", 33: "禁疗", 34: "受击破甲", 35: "限时睡眠", 36: "获得护盾", 37: "溢出治疗转盾", 38: "损失生命转盾", 39: "免疫击退", 40: "检索单位牌", 41: "弃牌抽牌", 42: "击杀回能", 43: "复活", 44: "阵亡抽牌", 45: "全体攻击", 46: "全体防御", 47: "全体移速", 48: "战旗", 49: "地刺", 50: "誊抄", 51: "随机变阵", 52: "本回合手牌减费", 53: "透支能量", 54: "节流", 30: "战友（下一单位减费）", 31: "进化（临时升级手牌）", 20: "虚弱", 21: "易伤", 22: "防御降低", 23: "麻痹", 24: "策反", 25: "狂化", 26: "下回合按幸存者抽牌", 27: "合理搭配", 28: "保持距离", 29: "审判者", 0: "攻击提升", 1: "百分比治疗", 2: "防御提升", 3: "攻击附毒", 4: "死亡爆炸", 6: "复制友军", 7: "伤害区域", 8: "减速区域", 9: "抽牌", 10: "停止抽牌", 11: "支付生命", 12: "每轮获得能量", 13: "阵亡攻击光环", 14: "随机出牌", 15: "撤回友军", 16: "自定义", 17: "立即获得能量", 18: "最大生命提升", 19: "留存友军（数值为阵亡加费）"}
