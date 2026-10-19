# 一键打包

Godot 顶部工具栏点击 **一键打包**（也可从“项目 → 工具 → 一键打包…”打开），选择 **Windows**、**Mac** 或 **两个都打包**，点击 **开始打包**。

完成后点击 **打开输出目录**，把其中的 ZIP 发给朋友。默认保存在 `builds/日期/时间-编号/`，每次创建新目录，不覆盖以前的包。可选择项目外的其他输出位置。

- Windows：x64 Release，ZIP 包含 exe、pck、启动说明和显卡兼容模式入口。
- Mac：Universal Release，兼容 Intel 和 Apple Silicon，使用 Godot 的临时签名。ZIP 保留 Mac 可执行权限和原始签名，并附上首次启动说明。
- 每个包附带引擎及素材许可说明，输出目录保存 SHA256 校验值与打包日志。

点击打包前会保存已打开的场景和工坊资源；未命名的当前场景需要先保存。打包期间界面可以继续操作，也可以关闭打包窗口；后台任务会继续。关闭编辑器时会等待任务结束。请等待当前打包完成后再进行下一次打包。

首次使用若按钮未出现，重新打开项目，或在“项目设置 → 插件”启用“一键打包”。

开发环境需要 Python 3.10+。Windows 优先自动使用现有 Codex Python，其次使用 `python`；Mac 使用 `python3`。导出使用当前编辑器的 Godot 程序，需在“编辑器 → 管理导出模板”安装与引擎版本匹配的模板。Mac 首次启动若被拦截，按包内说明在“隐私与安全性”允许该应用；临时签名不包含 Apple 公证。

命令行也可以使用相同打包流程：

```text
python tools/packaging/package_game.py --platform both --godot <Godot程序路径> --result .maintenance/packaging/result.json
```

`--platform windows` 只打 Windows 包，`--platform macos` 只打 Mac 包；`--output` 可指定其他输出目录。该工具只允许项目内的 `builds` 或项目外目录，避免将打包结果写入源素材目录。
