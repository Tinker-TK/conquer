@tool
extends Resource
class_name RiverSettings

# 外观资源只保存配置；运行中的水位由 DynamicRiver 独立持有。
@export_category("水位")
## 0 为干涸，1 为最高水位；灰度高度低于水位的区域被水覆盖。
@export_range(0.0, 1.0, 0.01) var water_level: float = 0.66
## 是否让水位按正弦周期涨落。开启后围绕基础 Water Level 在 Tide Amplitude 范围内变化，并限制在 0～1；战斗暂停时潮汐也暂停。
@export var tide_enabled: bool = false
## 潮汐相对基础水位的最大涨落幅度，0 表示不涨落；仅在 Tide Enabled 开启时使用。越大则干湿河床范围变化越明显。
@export_range(0.0, 0.4, 0.01) var tide_amplitude: float = 0.12
## 一次完整涨落周期的时长，单位为秒；越大则潮汐越慢，仅在潮汐开启时使用。
@export_range(2.0, 120.0, 0.5) var tide_period: float = 12.0

@export_category("河床与高度图")
## Polygon2D 河流的可选高度图。RiverTileMap 使用 TileSet 的配套高度图集。
@export var height_texture: Texture2D
## 可选无缝河床贴图；为空时使用程序化碎石河床。
@export var bed_texture: Texture2D
## 河床贴图的重复尺寸，单位为河流节点本地像素；越大则贴图图案越大。只有配置 Bed Texture 时使用。
@export_range(16.0, 512.0, 1.0) var bed_texture_scale: float = 128.0
## 程序化低处河床的基础颜色，用于碎石底色；配置河床贴图后仍与贴图颜色混合。当前着色使用此颜色的 RGB。
@export var bed_color: Color = Color(0.36, 0.40, 0.34, 1.0)
## 高处河岸的基础颜色，根据高度图与河床颜色过渡；用于岸边露出的泥土或碎石。当前着色使用此颜色的 RGB。
@export var bank_color: Color = Color(0.32, 0.29, 0.21, 1.0)
## 自动高度图中从河岸到低河床的水平距离，单位为节点本地像素。
@export_range(8.0, 160.0, 1.0) var bank_slope: float = 40.0
## 自动河床高度细节、碎石与水面噪声的随机种子。相同参数与种子产生相同分布，修改可更换细节而不改变河流多边形。
@export var random_seed: int = 1303
## 河流表面采样网格的大小，单位为节点本地像素；越大则河岸和水面细节的像素块越粗，越小则更细腻。
@export_range(1.0, 8.0, 1.0) var pixel_size: float = 2.0

@export_category("水色与流动")
## 浅水区域的水色，按水面与河床的高度差同深水色混合；透明表现由 Shallow Opacity 控制，当前只使用颜色 RGB。
@export var shallow_color: Color = Color(0.29, 0.47, 0.51, 1.0)
## 深水区域的水色，水越深则此颜色占比越高；与浅水色共同营造深浅层次，当前只使用颜色 RGB。
@export var deep_color: Color = Color(0.13, 0.29, 0.37, 1.0)
## 浅水水色覆盖河床的混合强度，0 保留河床颜色，1 主要显示浅水色；越大则浅水看起来越不透明。
@export_range(0.0, 1.0, 0.01) var shallow_opacity: float = 0.22
## 深水水色覆盖河床的混合强度，0 保留河床颜色，1 主要显示深水色；越大则深处越难看清河床。
@export_range(0.0, 1.0, 0.01) var deep_opacity: float = 0.72
## 河流自身水纹、焦散与泡沫噪声的移动速度，单位为节点本地像素/秒；正 X 向右、正 Y 向下，(0, 0) 停止这些流动动画。不会停止关联天气产生的雨滴与脚步波纹。
@export var flow_velocity: Vector2 = Vector2(18.0, 4.0)
## 流水噪声的空间尺度，单位为本地像素；越大则水纹和焦散图案越宽，越小则更细密。移动速度由 Flow Velocity 控制。
@export_range(16.0, 256.0, 1.0) var wave_scale: float = 64.0
## 水纹与天气波纹引起的河床、倒影折射强度；0 不扭曲，越大则水下细节变形越明显。水深也会影响折射幅度。
@export_range(0.0, 8.0, 0.1) var refraction: float = 1.6
## 水底焦散亮纹的强度，范围 0～1；0 关闭焦散，越大则浅水底部的流动亮纹越明显。
@export_range(0.0, 1.0, 0.01) var caustics_strength: float = 0.20

@export_category("岸边与倒影")
## 岸边泡沫亮边的颜色和不透明度；Alpha 为 0 时隐藏泡沫。只显示在被水覆盖的岸边带。
@export var foam_color: Color = Color(0.84, 0.93, 0.89, 0.85)
## 岸边泡沫带的基础宽度，单位为节点本地像素；0 关闭泡沫，越大则岸边亮带越宽，效果还受 Bank Slope 与 Pixel Size 影响。
@export_range(0.0, 12.0, 0.5) var foam_width: float = 2.0
## 岸边泡沫深度阈值的噪声扰动幅度。0 保持均匀边界，越大则泡沫的起伏变化越明显；不移动实际水位形成的干湿边界。
@export_range(0.0, 0.1, 0.001) var shore_motion: float = 0.012
## 河流水面中天气倒影的混合强度，范围 0～1；0 隐藏倒影。需通过 Weather Path 连接 RainWeather，且其倒影开关已启用。
@export_range(0.0, 1.0, 0.01) var reflection_opacity: float = 0.30

@export_category("开关与性能")
## 动态河流效果总开关，关闭时隐藏河床和水面的动态绘制；不修改地形碰撞、导航或单位战斗属性。
@export var enabled: bool = true
## 自动高度图的最长边上限；几何/坡度改变才重建，水位改变只更新 Shader。
@export_range(128, 1024, 128) var height_resolution: int = 512
