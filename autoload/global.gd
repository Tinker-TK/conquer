# 这玩意儿是干嘛的（核心逻辑）：保存准备、自动战斗等游戏阶段和兵种枚举，为各系统提供共同约定。
# 数据是咋流动的（数据流向）：场景节点和信号提供输入，本脚本更新所属模块的状态与显示。
# 为啥这么写（选型决策）：保持原有接口，把同类职责归到一起，便于查找和配置。
# 性能咋样（复杂度）：按已有节点回调执行；此次整理只迁移路径，不增加新的循环。
extends Node

# 游戏阶段
enum GamePhase{
	CARD_PLAY,
	AUTO_BATTLE,
	ROUND_RESOLVE,
	VICTORY,
	DEFEAT
}
# 当前阶段
var game_phase: GamePhase:
	set(value):
		game_phase = value
		SignalBus.phase_change.emit(value)


# 作用：准备和交锋期间都允许出牌，结算与胜负阶段停止；没有参数，返回阶段是否允许。
func is_card_play_phase() -> bool:
	return game_phase in [GamePhase.CARD_PLAY, GamePhase.AUTO_BATTLE]

enum UnitType{
	SOILDIER,
	ARCHER,
	ORC,
	ARMOREDAXEMAN,
	KNIGHT,
	KNIGHTTEMPLAR,
	LANCER,
	PRIEST,
	SWORDSMAN,
	WIZARD,
	WEREBEAR,
	WEREWOLF,
	NECROMANCER,
	ARMOREDORC,
	BAT,
	ELITEORC,
	GREATSWORDSKELETON,
	ORCRIDER,
	SKELETON,
	SKELETONARCHER,
	SLIME,
	# Tiny Swords Enemy Pack；追加枚举，保留已有兵种编号与存档兼容。
	BEAR,
	BOMBFISH,
	BUMBLEBEE,
	GIANTBAT,
	GNOLL,
	GNOME,
	HARPOONSHARK,
	HEXSHAMAN,
	IMP,
	LIZARD,
	MINOTAUR,
	PADDLESHARK,
	PANDA,
	SKULL,
	SLINGSHOTGNOME,
	SNAKE,
	SPEARGOBLIN,
	SPIDER,
	THIEF,
	TORCHGOBLIN,
	TROLL,
	TURTLE,
	PIGRIDER
}
var unit_data: Dictionary = {
	UnitType.SOILDIER :{
		'name' : 'soldier'
	}
}
