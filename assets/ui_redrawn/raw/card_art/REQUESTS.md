# 前八项卡画的生成要求摘要

这八项由并行工作进程调用内置 imagegen 生成。工作进程在保存逐字提示词前中断，因此以下是下达的生成要求摘要，不冒充逐字 API 日志。原始 PNG 已完整保存在本目录。

共通要求：以 `ui_extracted/card_art/` 相应原图为参考，高清重绘且保持像素美术风格；不含文字、数字、卡框、费用徽章；主体保持完整轮廓并去除场景底色；背景移除主体后独立补画为完整方形图像。

- `summon_guard_subject.png`：完整蓝银骑士与剑盾，透明或单色底。
- `summon_guard_background.png`：骑士背后的完整蓝天、草地与远景，不含骑士。
- `hold_position_subject.png`：完整金边蓝银盾牌，透明或单色底。
- `hold_position_background.png`：盾牌背后的蓝色放射光，不含盾牌。
- `fireball_subject.png`：完整火球、尾焰及星火，透明或单色底。
- `fireball_background.png`：完整暗红魔法背景，不含火球。
- `battlefield_heal_subject.png`：完整治疗叶片及光效，透明或单色底。
- `battlefield_heal_background.png`：完整绿色魔法光背景，不含叶片。

战意旗帜的两项及根代理后续生成保存了逐字提示词，见 `prompts_root.json`。
