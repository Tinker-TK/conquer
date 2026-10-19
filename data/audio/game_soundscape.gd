extends Resource
class_name GameSoundscape

## 主菜单和征途的背景音乐；WAV 由播放管理器循环，可替换为正式配乐。
@export var music: AudioStream
## 地图、晴天和雪天的背景风声。
@export var wind: AudioStream
## 雨天战场的背景雨声。
@export var rain: AudioStream
## 音量设置中用于试听音效通道的短音。
@export var feedback: AudioStream
## 背景音乐基准音量（分贝），与玩家的音乐音量相乘。
@export_range(-60, 0) var music_db := -22.0
## 环境音基准音量（分贝），与玩家的环境音音量相乘。
@export_range(-60, 0) var ambience_db := -25.0
