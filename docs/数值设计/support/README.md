# 数值文档生成工具

生成脚本、输入快照、校验记录和表格预览均保留，数值表与草稿未修改。

`build_workbook.mjs`、`build_chapter1_workbook.mjs` 通过 `artifact_runtime.mjs` 加载表格库：优先使用本地安装，否则读取 Codex 的共享工作区运行时。本机共享库与此前目录链接使用的库完全相同；项目不再保留会被文件扫描器遍历的 `node_modules` 链接。

```text
node docs/数值设计/support/build_workbook.mjs
node docs/数值设计/support/build_chapter1_workbook.mjs
```

这些命令会重新生成对应表格和预览。更换电脑后可设置环境变量 `CODEX_WORKSPACE_NODE_MODULES` 为包含 `@oai/artifact-tool` 的依赖目录，也可恢复本地依赖。共享依赖未被删除。

## 统一战力计算器（单位/卡牌/遗物/药水）

2026-10-19已同步NUM-DESIGN-v1.0实装：解析真实多命中帧，每段扣`ceil(防御/段数)`；奖励基线与资源数值读取新配置。`node docs/数值设计/support/verify_balance_model.cjs`交叉核对Python快照与JavaScript模型的11个可征召单位结果。历史工作簿及原设计表保留作对照。

`design_data.py` 读取当前 `data/units`、`data/skills`、`data/cards`、`data/relics`、`data/potions`、`data/levels`、`data/shops`，并合并 `遗物流派设计.md`、`药水能力设计与投放方案.md`、`路线事件设计.md` 中的扩展内容，输出 `design_data.json`。`build_calculator.py` 把 JSON 与 `calculator_app.js` 注入 `calculator_template.html`，生成同目录上层的 `战力计算器.html`。

```text
python docs/数值设计/support/design_data.py
python docs/数值设计/support/build_calculator.py
node docs/数值设计/support/verify_calculator.mjs   # 先启动带 --remote-debugging-port=9222 的 Edge
```

计算器逻辑源码按职责拆成 `calculator_app_part1.js`（模型/状态）、`part2.js`（总览/单位）、`part3.js`（卡牌/遗物/药水）、`part4.js`（构筑/校准）、`part5.js`（抽屉/事件/初始化）。修改后按 1→5 顺序合并为 `calculator_app.js`，再运行 `build_calculator.py`。旧的 `单位战力计算器.html` 只覆盖单位，保留作历史对照。

## 离线战力计算器（旧版，仅单位）

`build_unit_power_calculator.py` 读取当前单位与技能、场景动画，生成同目录上层的 `单位战力计算器.html`。计算模型和界面分别维护在 `unit_power_calculator_model.js`、`unit_power_calculator_app.js` 与 `unit_power_calculator_template.html`；最终页面包含全部代码和初值，可独立离线使用。

```text
python docs/数值设计/support/build_unit_power_calculator.py
node docs/数值设计/support/verify_unit_power_calculator.cjs
```

验证脚本使用共享 Node 依赖里的 Playwright 和本机 Edge。结果写入 `unit_power_calculator_validation.json`；浏览器截图保存在本目录。历史工作簿不随计算器重新生成而改写。`calculate_unit_power.py` 会重新生成计算器，并通过 `export_current_unit_power.cjs` 使用相同引擎更新最新战力文档和 JSON 结果。
