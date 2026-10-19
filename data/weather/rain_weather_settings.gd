# 雨天外观配置；不保存单位或战斗状态，可由多个关卡复用。
@tool
extends Resource
class_name RainWeatherSettings

@export_category("天气开关")
## 雨天效果总开关，控制落雨、积水、倒影、水花与雨天场景色调。雪天启用时会自动关闭雨天；河流的水位和水面开关由河流配置控制。
@export var enabled: bool = true
## 降雨强度，范围 0～1；越大则飘落雨滴和落雨水花越多、雨天场景色调越明显。0 停止降雨，积水仍由 Puddles Enabled 与 Wetness 决定是否显示。
@export_range(0.0, 1.0, 0.01) var intensity: float = 0.65
## 雨天的整体场景色调，与原始颜色按降雨强度混合；白色保持原始色调，较暗的蓝灰色可营造阴雨氛围。
@export var atmosphere_tint: Color = Color(0.76, 0.83, 0.94, 1.0)
## 积水轮廓、水边噪声、独立云层排布与随机水花的种子。相同种子与配置可复现相同分布；云层使用独立随机序列。
@export var random_seed: int = 731

@export_category("雨滴")
## 满降雨强度时的雨滴粒子数量，约 70% 远景、30% 近景；实际数量还受 Intensity 影响。越大则雨更密集，渲染开销也更高。
@export_range(32, 1600, 1) var rain_amount: int = 560
# 与雨丝尺寸一致，速度以实际渲染像素/秒配置，窗口缩小不会减慢落雨。
## 雨滴向下的基础速度，按实际渲染像素/秒配置；越大则落雨越快。运行时会按镜头与窗口变换换算，保持画面中的雨速。
@export_range(100.0, 6000.0, 10.0) var fall_speed: float = 1800.0
## 雨滴的水平速度，按实际渲染像素/秒配置；负值向左，正值向右，0 表示无整体横向风。绝对值越大则雨丝倾斜越明显。
@export_range(-3000.0, 3000.0, 5.0) var wind: float = -250.0
## 雨滴不透明度，越大则雨丝越清晰。会与 Rain Color 的 Alpha 相乘，也影响落雨水花所用的雨滴颜色；不控制积水透明度。
@export_range(0.02, 1.0, 0.01) var rain_opacity: float = 0.6
## 空中雨丝与落雨水花的基础颜色，Alpha 与 Rain Opacity 相乘；积水的水色由 Water Tint 控制。
@export var rain_color: Color = Color(0.84, 0.92, 1.0, 1.0)
# 雨丝尺寸按实际渲染像素保持，不随镜头缩放或窗口拉伸变成亚像素。
## 雨丝宽度，单位为实际渲染像素；越大则雨丝越粗，远景雨丝略细。尺寸不随镜头缩放变成亚像素。
@export_range(1.0, 12.0, 1.0) var streak_width: float = 3.0
## 雨丝长度，单位为实际渲染像素；越大则雨滴拖尾越长，远景雨丝略短。
@export_range(4.0, 96.0, 1.0) var streak_length: float = 22.0

@export_category("积水")
## 是否显示地面的雨水积洼。关闭后仍可落雨，河流也仍由自己的开关控制；积水覆盖范围还受地表遮罩限制。
@export var puddles_enabled: bool = true
## 积水覆盖程度，范围 0～1；越大则同一噪声中的水洼越多、越连片，0 表示无积水。不是严格的地面面积百分比。
@export_range(0.0, 1.0, 0.01) var puddle_coverage: float = 0.52
## 积水主噪声的斑块尺度；越大则水洼越大、越连片，越小则更细碎。主体轮廓固定在世界坐标，不随天空或水边动画移动。
@export_range(32.0, 512.0, 1.0) var puddle_scale: float = 150.0
## 水洼主体轮廓的过渡柔和程度；越大则积水与原地面的交界越宽、越柔和，越小则边界越清晰。
@export_range(0.005, 0.1, 0.005) var edge_softness: float = 0.025
## 地面积水的整体不透明度及湿润表现强度，范围 0～1；0 隐藏积水，越大则水色、倒影与水面波纹更明显。
@export_range(0.0, 1.0, 0.01) var wetness: float = 0.7
# 静态噪声同时控制深浅透明度；0 恢复均匀透明度，1 让浅边更通透。
## 按积水噪声深浅改变透明度的程度。0 使用均匀透明度，越接近 1 则浅边更通透、深处更明显；与 Wetness 共同决定最终透明度。
@export_range(0.0, 1.0, 0.01) var depth_opacity: float = 0.65
## 积水的基础水色，主要用于天空颜色层；与 Sky Strength、原地面颜色及倒影共同合成。当前积水着色只读取此颜色的 RGB。
@export var water_tint: Color = Color(0.30, 0.43, 0.55, 1.0)
## 积水中水色和天空明暗层的混合强度，范围 0～1；0 保留原地面色，越大则天空色层越明显。
@export_range(0.0, 1.0, 0.01) var sky_strength: float = 0.36
## 水面独立云层的不透明度，默认 0.65；0 隐藏云层，越大越实。使用场景 Clouds 时不再额外乘 Sky Strength；角色和树木倒影仍覆盖在云层上。
@export_range(0.0, 1.0, 0.01) var sky_cloud_strength: float = 0.65
## 从 RainWeather 的 Cloud Source Path 下读取 Clouds 精灵图片；在独立副本中遮掉深色底影、上下翻转，再随机组成水面云层。不移动或修改原精灵/原纹理。找不到图片时回退到 Sky Texture。
@export var sky_use_scene_clouds: bool = true
## 每个循环云层图块中随机排布的云朵数量；形状从来源精灵图片中选取。Random Seed 相同时排布可复现，运行中不会逐帧重新选形。
@export_range(1, 24, 1) var sky_cloud_count: int = 6
## 云朵原始图片在循环图中的基础尺寸倍率，并叠加少量随机大小变化；最终世界尺寸还受 Sky Scale 影响。
@export_range(0.2, 1.5, 0.05) var sky_cloud_size: float = 0.65
## 积水天空明暗层使用的图片纹理；主要读取图片亮度形成云形。留空使用程序化噪声，不影响水洼主体轮廓。
@export var sky_texture: Texture2D = preload("res://assets/tilemap/sky.png")
## 天空纹理在世界中的重复尺寸，单位为世界像素；越大则云形越大。只有配置 Sky Texture 时使用。
@export_range(128.0, 2048.0, 16.0) var sky_scale: float = 800.0
## 水面云纹沿画面水平方向随风移动：Wind 正数向右、负数向左，速度取其绝对值乘 Sky Wind Speed Scale，与雨滴下落速度无关。只移动水面云纹，不改变场景云朵或积水轮廓。
@export var sky_follow_wind: bool = true
## 水面云纹相对于风速的慢速倍率；默认 0.02，Wind 为 300 时云纹以 6 世界像素/秒流动。0 冻结；无风时也停止流动。仅在 Sky Follow Wind 开启时生效。
@export_range(0.0, 0.2, 0.001) var sky_wind_speed_scale: float = 0.02
# 自定义云纹速度保留给不跟随风的场景；不参与积水遮罩。
## 关闭 Sky Follow Wind 后使用的自定义云纹方向与速度，单位为世界像素/秒；正 X 向右、正 Y 向下，(0, 0) 停止移动。不会推动积水轮廓。
@export var sky_scroll_speed: Vector2 = Vector2(4.0, 0.0)
## 雨滴与脚步波纹引起的水面折射强度；0 不扭曲，越大则波纹附近的地面和倒影变形越明显。不会让整片水洼一起漂移。
@export_range(0.0, 4.0, 0.05) var distortion: float = 1.2

@export_category("移动水边")
# 细噪声只改变内侧亮边的宽度/碎片，不参与水洼主体阈值。
## 水洼内侧亮边的细噪声尺度；越大则亮边的宽窄变化与碎片越大，越小则更细密。此噪声不改变水洼主体范围。
@export_range(8.0, 128.0, 1.0) var edge_noise_scale: float = 24.0
## 水边细噪声对亮边宽度与断续碎片的影响强度；0 为连续均匀亮边，越大则边缘变化越明显。
@export_range(0.0, 0.3, 0.005) var edge_noise_strength: float = 0.10
## 水边细噪声的采样滚动速度，单位为世界像素/秒；(0, 0) 保持亮边纹理静止。只改变边缘细节，不移动水洼主体。
@export var edge_noise_speed: Vector2 = Vector2(12.0, -8.0)
## 水洼内侧亮边的基础宽度，单位为世界像素；0 关闭亮边，越大则边线越宽。实际宽度还受水边噪声影响。
@export_range(0.0, 12.0, 0.5) var edge_width: float = 3.0
## 水洼内侧亮边的颜色与不透明度；Alpha 为 0 时隐藏亮边，与 Edge Width 共同控制边缘高光。
@export var edge_color: Color = Color(0.72, 0.84, 0.86, 0.75)

@export_category("倒影")
## 是否生成单位与场景精灵的水面倒影。关闭可减少离屏渲染开销；连接此天气节点的河流也会停止使用这些倒影。
@export var reflections_enabled: bool = true
## 地面积水中单位和物体倒影的混合强度，范围 0～1；0 隐藏倒影，越大则更清晰。河流使用自身的 Reflection Opacity。
@export_range(0.0, 1.0, 0.01) var reflection_opacity: float = 0.48
## 倒影从脚底向远端衰减透明度的强度，范围 0～1；0 不额外渐隐，越大则远离脚底的倒影越淡。
@export_range(0.0, 1.0, 0.05) var reflection_fade: float = 0.3
## 倒影离屏纹理相对于水面画布的分辨率倍率。1 最清晰，0.5 宽高各减半，0.25 更省渲染开销但细节更少。
@export_range(0.25, 1.0, 0.25) var reflection_resolution: float = 0.5
## 倒影的纵向压缩比例，1 为原精灵高度，越小则倒影越短；围绕脚底位置向下镜像。
@export_range(0.2, 1.0, 0.05) var reflection_height: float = 0.72
## 默认脚底位置相对单位或物体锚点的本地 Y 偏移，正值向下。用于倒影镜像和脚步水花落点；节点 rain_foot_offset 元数据可覆盖此值。
@export_range(-80.0, 100.0, 1.0) var foot_offset: float = 12.0
## 倒影起点与脚底之间的裁切间隔，单位为世界像素；越大则脚底下方保留的无倒影空隙越宽。
@export_range(0.0, 10.0, 1.0) var reflection_gap: float = 2.0
## 同时复制用于倒影的精灵数量上限，包含单位与符合条件的场景物体。越大则可显示更多倒影，也会增加更新与渲染开销。
@export_range(8, 256, 1) var max_reflections: int = 128

@export_category("落雨水花与脚步")
## 满降雨强度时每秒尝试产生的随机落雨水花数量，实际速率乘以 Intensity，并受可用地表与 Max Ripples 限制。0 停止随机落雨水花。
@export_range(0.0, 240.0, 1.0) var splash_rate: float = 72.0
# 地面水花按屏幕像素保持可读；水面环半径仍使用世界坐标。
## 地面落雨水花的尺寸倍率，越大则溅起的水花越大；按屏幕像素保持可读。水面扩散环的半径仍由 Ripple Radius 控制。
@export_range(0.5, 3.0, 0.1) var splash_size: float = 1.0
## 地面落雨水花的不透明度，越大则溅起的水花越明显；还会叠加水花自身随时间的淡出。
@export_range(0.05, 1.0, 0.05) var splash_opacity: float = 0.9
## 地面落雨水花一次播放的持续秒数，越大则水花保留越久；水面扩散环由 Ripple Lifetime 控制。
@export_range(0.12, 0.5, 0.01) var splash_lifetime: float = 0.22
## 雨滴或脚步水面波纹的持续秒数，越大则扩散环保留越久，也更容易达到同时事件数上限。
@export_range(0.15, 1.5, 0.05) var ripple_lifetime: float = 0.7
## 水面扩散环的基础最大半径，单位为世界像素；越大则雨滴与脚步引起的波纹扩散范围越广。
@export_range(3.0, 40.0, 1.0) var ripple_radius: float = 14.0
## 同时保留的落雨水花与水面波纹事件总数上限。达到上限时跳过新事件；越大则能显示更多水花，但绘制开销增加。
@export_range(16, 256, 1) var max_ripples: int = 96
## 是否根据移动单位的行走距离生成积水脚步水花。只在可见单位脚底位于可用积水且在镜头内时触发。
@export var footsteps_enabled: bool = true
## 单位每移动多少世界像素触发一次积水脚步水花；越小则步频越密集。瞬间传送或死亡会重置距离，避免连续补出水花。
@export_range(8.0, 100.0, 1.0) var step_distance: float = 22.0
