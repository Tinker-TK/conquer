extends Resource
class_name PotionEffect
## 只保存配方；时钟、已命中目标与召唤物由本场 PotionRuntime 持有。
enum Kind {
	DAMAGE, STATUS, POISON, BUFF, SHIELD, HEAL_PLAYER, DRAW, ENERGY,
	SUMMON, CONVERT, COPY_ALLY, REVIVE, CLEANSE, UPGRADE_CARD, SKIP_ROUND,
	DELAYED_BLAST, ZONE, GRAVITY, CHAIN_LIGHTNING, KNOCKBACK,
	DISCARD_DRAW, TACTICS, MAX_HP, PAY_HP, FAIRY
}
@export var kind: Kind = Kind.DAMAGE
@export var amount := 0.0
@export var radius := 0.0
@export var interval := 0.5
@export var duration := 0.0
@export var rounds := 0
@export var delay := 0.0
@export var status_id: StringName
@export var buff_kind: CardEffect.Kind = CardEffect.Kind.ATTACK_UP
@export var unit_data: UnitData
@export var count := 1
## 单次状态来源可累计的上限；0 不限制。
@export var stack_cap := 0
