# 开始界面插画向左扩图

成品：`fantasy-battle-extended.png`，1568 × 1254。使用内置 `image_gen.imagegen` 续绘，未使用 CLI/API 回退。

原画：`fantasy-battle.png`，1254 × 1254，文件保持不变。先将原画放在新增画布的 x=314、y=0，再让 imagegen 填充左侧白色条带。生成结果仅用于新增区域，接边色差也仅在新增区域内校准；最终将原画原始像素完整拷回右侧，并验证该区域的 RGBA 数据与原画完全相同。

界面固定显示高度 1080、按图片比例计算宽度，并对齐设计画布右边缘。原画在新纹理中的起点仍映射到界面 x=840；新画幅延伸至约 x=569.57，覆盖底部 x=700 的斜分界，因此原有角色、怪物和武器的大小与位置保持不变。

左侧羊皮纸分区使用不透明底色，避免新增画幅从纸面透出矩形边界。

最终实际编辑提示词：

```text
Use case: compositing, PRECISE LEFT OUTPAINTING of an already expanded canvas.
Input image 1 is the edit target. Its canvas is already 1568 wide × 1254 high. The LEFTMOST 314 pixel strip is plain WHITE and is the only region to inpaint. Everything to the RIGHT of x=314 is the original existing painting and is LOCKED. Do not change the canvas dimensions, composition, size or position of ANY existing element. Especially keep the existing red crown flag and its pole, the mage's gold cloak, the knight's red cape and spear, the turquoise spell shield, dwarf and crystal-horned monster exactly in place. Do not zoom out, shrink, stretch, recenter, redraw or reinterpret the original right-hand painted area.
Fill ONLY the white strip on the left with natural continuations of the painted objects touching its RIGHT border: cream cloud and blue sky near the top; the edge of the EXISTING red flag and distant blue-green hills around the upper-middle; continuing the gold mage cloak and red cape around middle/lower heights; olive grass, a soft pale path and muted rock at the bottom. Preserve the exact edge heights, contours, brushstroke style and colors across x=314. No hard vertical seam, no visible white remaining, no decorative border and no mirrored or repeated edge strip. Original subjects must retain their exact pixel size and relative placement. Add no characters or new props. This is targeted inpainting of the blank strip, not a new painting. Match the existing soft gouache style and lighting. No text or UI.
```
