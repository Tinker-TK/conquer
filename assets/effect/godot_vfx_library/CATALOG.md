# 特效资源中文索引

实际收录：30 个粒子场景、24 个着色器、4 张粒子贴图。上游演示的 34 个选项包含同一战斗粒子的 5 种元素颜色。

可搜索和复制路径的图文版：[catalog.html](catalog.html)。使用方式见 [README.md](README.md)。

## 粒子场景

| 中文名称 | 分类 | 文件 | 说明 |
| --- | --- | --- | --- |
| 血液飞溅 | 战斗 | [blood_splash](effects/combat/blood_splash.tscn) | CPUParticles2D / 单次 |
| 通用元素战斗粒子 | 战斗 | [combat_particle](effects/combat/combat_particle.tscn) | CPUParticles2D / 单次 |
| 连击光环 | 战斗 | [combo_ring](effects/combat/combo_ring.tscn) | CPUParticles2D / 单次 |
| 能量爆发 | 战斗 | [energy_burst](effects/combat/energy_burst.tscn) | CPUParticles2D / 单次 |
| 治疗粒子 | 战斗 | [heal_particles](effects/combat/heal_particles.tscn) | CPUParticles2D / 持续 |
| 护盾破碎 | 战斗 | [shield_break](effects/combat/shield_break.tscn) | CPUParticles2D / 单次 |
| 冲刺拖尾 | 移动 | [dash_trail](effects/movement/dash_trail.tscn) | CPUParticles2D / 持续 |
| 跳跃扬尘 | 移动 | [jump_dust](effects/movement/jump_dust.tscn) | CPUParticles2D / 单次 |
| 滑墙火花 | 移动 | [wall_slide_spark](effects/movement/wall_slide_spark.tscn) | CPUParticles2D / 持续 |
| 火球拖尾 | 魔法与技能 | [fireball_trail](effects/magic/fireball_trail.tscn) | CPUParticles2D / 持续 |
| 冰霜爆发 | 魔法与技能 | [ice_frost](effects/magic/ice_frost.tscn) | CPUParticles2D / 单次 |
| 闪电链 | 魔法与技能 | [lightning_chain](effects/magic/lightning_chain.tscn) | Node2D / 单次 |
| 魔法光环 | 魔法与技能 | [magic_aura](effects/magic/magic_aura.tscn) | GPUParticles2D / 持续 |
| 毒雾 | 魔法与技能 | [poison_cloud](effects/magic/poison_cloud.tscn) | CPUParticles2D / 持续 |
| 传送门漩涡 | 魔法与技能 | [portal_vortex](effects/magic/portal_vortex.tscn) | CPUParticles2D / 持续 |
| 召唤法阵 | 魔法与技能 | [summon_circle](effects/magic/summon_circle.tscn) | CPUParticles2D / 持续 |
| 灰烬飘落 | 环境 | [ash_particles](effects/environment/ash_particles.tscn) | CPUParticles2D / 持续 |
| 篝火烟雾 | 环境 | [campfire_smoke](effects/environment/campfire_smoke.tscn) | CPUParticles2D / 持续 |
| 蜡烛火焰 | 环境 | [candle_flame](effects/environment/candle_flame.tscn) | CPUParticles2D / 持续 |
| 尘土爆发 | 环境 | [dust_cloud](effects/environment/dust_cloud.tscn) | CPUParticles2D / 单次 |
| 落叶 | 环境 | [falling_leaves](effects/environment/falling_leaves.tscn) | CPUParticles2D / 持续 |
| 萤火虫 | 环境 | [fireflies](effects/environment/fireflies.tscn) | CPUParticles2D / 持续 |
| 火花 | 环境 | [sparks](effects/environment/sparks.tscn) | CPUParticles2D / 单次 |
| 蒸汽 | 环境 | [steam](effects/environment/steam.tscn) | CPUParticles2D / 单次 |
| 火把火焰 | 环境 | [torch_fire](effects/environment/torch_fire.tscn) | CPUParticles2D / 持续 |
| 水花飞溅 | 环境 | [water_splash](effects/environment/water_splash.tscn) | CPUParticles2D / 单次 |
| 木屑飞溅 | 环境 | [wood_debris](effects/environment/wood_debris.tscn) | CPUParticles2D / 单次 |
| 雨滴 | 天气 | [rain_drops](effects/weather/rain_drops.tscn) | CPUParticles2D / 持续 |
| 雪花 | 天气 | [snow_flakes](effects/weather/snow_flakes.tscn) | CPUParticles2D / 持续 |
| 瀑布水雾 | 天气 | [waterfall_mist](effects/weather/waterfall_mist.tscn) | CPUParticles2D / 持续 |

## 着色器

| 中文名称 | 分类 | 文件 | 说明 |
| --- | --- | --- | --- |
| 闪烁 | 角色状态 | [blink](shaders/status/blink.gdshader) | 在 ShaderMaterial 中调整参数 |
| 燃烧 | 角色状态 | [burning](shaders/status/burning.gdshader) | 纹理参数：distortion_texture |
| 颜色替换 | 角色状态 | [color_change](shaders/status/color_change.gdshader) | 在 ShaderMaterial 中调整参数 |
| 溶解消失 | 角色状态 | [dissolve](shaders/status/dissolve.gdshader) | 纹理参数：dissolve_texture |
| 敌人受击组合效果 | 角色状态 | [enemy](shaders/status/enemy.gdshader) | 在 ShaderMaterial 中调整参数 |
| 受击闪白 | 角色状态 | [flash_white](shaders/status/flash_white.gdshader) | 在 ShaderMaterial 中调整参数 |
| 冻结 | 角色状态 | [frozen](shaders/status/frozen.gdshader) | 纹理参数：ice_texture |
| 隐身 | 角色状态 | [invisibility](shaders/status/invisibility.gdshader) | 纹理参数：distortion_texture |
| 轮廓发光 | 角色状态 | [outline_glow](shaders/status/outline_glow.gdshader) | 在 ShaderMaterial 中调整参数 |
| 石化 | 角色状态 | [petrify](shaders/status/petrify.gdshader) | 纹理参数：crack_texture |
| 中毒 | 角色状态 | [poison](shaders/status/poison.gdshader) | 在 ShaderMaterial 中调整参数 |
| 模糊 | 屏幕效果 | [blur_amount](shaders/screen/blur_amount.gdshader) | 在 ShaderMaterial 中调整参数 |
| 色差 | 屏幕效果 | [chromatic_aberration](shaders/screen/chromatic_aberration.gdshader) | 在 ShaderMaterial 中调整参数 |
| 雾气 | 屏幕效果 | [fog](shaders/screen/fog.gdshader) | 纹理参数：noise_texture |
| 灰度 | 屏幕效果 | [grayscale](shaders/screen/grayscale.gdshader) | 在 ShaderMaterial 中调整参数 |
| 径向模糊 | 屏幕效果 | [radial_blur](shaders/screen/radial_blur.gdshader) | 在 ShaderMaterial 中调整参数 |
| 抖动 | 屏幕效果 | [shake_intensity](shaders/screen/shake_intensity.gdshader) | 在 ShaderMaterial 中调整参数 |
| 暗角 | 屏幕效果 | [vignette](shaders/screen/vignette.gdshader) | 在 ShaderMaterial 中调整参数 |
| 热浪扭曲 | 环境 | [heat_distortion](shaders/environment/heat_distortion.gdshader) | 纹理参数：noise_texture |
| 星空 | 环境 | [starSky](shaders/environment/starSky.gdshader) | 纹理参数：small_stars_texture, large_stars_texture；保留 Brian Smith 的 MIT 署名；适用于 ColorRect |
| 像素水面与倒影 | 环境 | [water](shaders/environment/water.gdshader) | 纹理参数：noise_texture, noise_texture2, SCREEN_TEXTURE |
| 波动水面 | 环境 | [water_surface](shaders/environment/water_surface.gdshader) | 在 ShaderMaterial 中调整参数 |
| 能量屏障 | 魔法与技能 | [energy_barrier](shaders/magic/energy_barrier.gdshader) | 在 ShaderMaterial 中调整参数 |
| 传送门扭曲 | 魔法与技能 | [portal_vortex](shaders/magic/portal_vortex.gdshader) | 在 ShaderMaterial 中调整参数 |

## 贴图

| 中文名称 | 分类 | 文件 | 说明 |
| --- | --- | --- | --- |
| 火焰粒子贴图 | 粒子贴图 | [fire_particle](textures/fire_particle.png) |  /  |
| 萤火虫贴图 | 粒子贴图 | [firefly](textures/firefly.png) |  /  |
| 树叶贴图 | 粒子贴图 | [leaf](textures/leaf.png) |  /  |
| 火花粒子贴图 | 粒子贴图 | [spark_particle2](textures/spark_particle2.png) |  /  |
