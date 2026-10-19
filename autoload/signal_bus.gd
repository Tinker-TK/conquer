# 这玩意儿是干嘛的（核心逻辑）：转发游戏阶段变化，让单位和界面同步响应。
# 数据是咋流动的（数据流向）：场景节点和信号提供输入，本脚本更新所属模块的状态与显示。
# 为啥这么写（选型决策）：保持原有接口，把同类职责归到一起，便于查找和配置。
# 性能咋样（复杂度）：按已有节点回调执行；此次整理只迁移路径，不增加新的循环。
extends Node

# Emitted by Global and connected by battle nodes outside this signal bus.
@warning_ignore("unused_signal")
signal phase_change(phase: Global.GamePhase)

@warning_ignore("unused_signal")
signal relic_triggered(id: StringName, display_name: String)
