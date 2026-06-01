# AltTab 切换器 UI 美化方向（titles / "应用名 – 窗口标题" 外观）

> 范围：仅针对当前用户使用的 **list / titles 外观模式**（暗色半透明圆角面板，每行 = 应用图标 + 「应用名 – 窗口标题」单色白字 + 右侧圆圈窗口数 + 选中行高亮）。
> 样式真源：`src/switcher/Appearance.swift`（颜色 / 字体 / 尺寸 / 高亮）。
> 高亮实际绘制：`src/switcher/main-window/TileUnderLayer.swift`（titles / thumbnails 模式的 focused / hovered 选中环都在这里画，值全部读自 `Appearance.swift`）。
> 排版（应用名 – 标题 字符串拼装）：`src/switcher/main-window/TileView.swift` 的 `getAppOrAndWindowTitle()` + `TileTitleView.swift`。

## 现状基线（改前）

| 项 | 值 | 位置 |
|----|----|----|
| 选中行填充 | `systemAccent @ 0.20` | `Appearance.swift:33` `highlightFocusedBackgroundColor` |
| 悬停行填充 | `systemAccent @ 0.10` | `Appearance.swift:34` `highlightHoveredBackgroundColor` |
| 选中行描边 | `systemAccent @ 1.0`（实心亮蓝） | `Appearance.swift:35` `highlightFocusedBorderColor` |
| 悬停行描边 | `systemAccent @ 0.70` | `Appearance.swift:36` `highlightHoveredBorderColor` |
| 描边宽度 | titles=2px / 其它=3px | `Appearance.swift:79` `highlightBorderWidth` |
| 圆角 | titles `cellCornerRadius=10` | `Appearance.swift:164` |
| 文字色 | 暗色主题 `white @ 0.85`，整串单色 | `Appearance.swift:197` `darkTheme()` |
| 字体 | `systemFont(16/14/13)`，macOS 26 起 `.medium` | `Appearance.swift:176/182` |
| 行内边距 | titles `edgeInsetsSize=7` | `Appearance.swift:165` |

视觉问题：选中态是一圈 **2px 实心亮蓝描边环**（偏 AppKit 默认、偏厚重），填充很淡（0.20）所以"色块感"弱、"描边环感"强；「应用名 – 窗口标题」整串等重单色白字，缺层次。

---

## 方向 A：Raycast / Spotlight 式柔和现代（推荐落地）

**参照**：Raycast 主列表、macOS Spotlight、Arc 命令面板 —— 选中态是**柔和的整块填充**，弱描边或无描边，圆角偏大，靠"实心色块"而非"硬环"区分焦点。

**精确代码改动点（全部在 `Appearance.swift`）**：

| 改动 | 改前 → 改后 | 行 |
|----|----|----|
| 提高选中填充 alpha | `0.20 → 0.30` | `highlightFocusedBackgroundColor` :33 |
| 提高悬停填充 alpha | `0.10 → 0.18` | `highlightHoveredBackgroundColor` :34 |
| 选中描边降为细淡轮廓 | `accent@1.0 → accent@0.50` | `highlightFocusedBorderColor` :35 |
| 悬停描边降淡 | `accent@0.70 → accent@0.28` | `highlightHoveredBorderColor` :36 |
| titles 描边减细 | `2 → 1` px | `highlightBorderWidth` :79 |
| （可选）行内留白加大 | titles `edgeInsetsSize 7 → 8` | :165 |
| （可选）圆角更软 | titles `cellCornerRadius 10 → 12` | :164 |

- **改动量**：核心 5 行（填充×2 + 描边×2 + 描边宽度×1），全是常量/getter 调值，零结构改动。可选两项再 +2 行。
- **回归风险**：**极低**。`TileUnderLayer.updateLayer` 原样读取这些值，渲染路径不变；只是色值变了。描边宽度按 style 区分（line 79），只动 titles 分支，不影响 appIcons 的焦点环。
- **是否偏离上游**：偏离 —— 上游默认是亮蓝实心环。但这是**纯外观参数**，无逻辑分叉，未来同步上游冲突面极小（只在这几行）。

**优点**：现代、柔和、与 Raycast/Spotlight 观感一致；改动最集中、最可逆、最不主观。
**缺点**：填充 0.30 在浅色 system accent（如黄色）下对比稍弱，但暗色玻璃面板上完全够辨识；描边变细在高分屏上更精致、在低分屏上略弱。
**推荐**：✅ **作为本次唯一落地项**（见交付物 2，已实现）。可选的 edgeInsets / cornerRadius 微调留作人工开关。

---

## 方向 B：极简近单色克制

**参照**：原生 macOS 列表选中、Linear 列表、GitHub 命令面板 —— **去掉彩色**，选中态用中性白/灰半透明填充 + 无描边，强调"安静、克制、不抢色"。

**精确代码改动点**：

| 改动 | 改前 → 改后 | 行 |
|----|----|----|
| 选中填充改中性白 | `accent@0.20 → white@0.14` | `highlightFocusedBackgroundColor` :33 |
| 悬停填充改中性白 | `accent@0.10 → white@0.07` | `highlightHoveredBackgroundColor` :34 |
| 去描边（焦点） | `accent@1.0 → white@0.0`（透明） | `highlightFocusedBorderColor` :35 |
| 去描边（悬停） | `accent@0.70 → white@0.0` | `highlightHoveredBorderColor` :36 |
| 描边宽度归零 | titles `2 → 0` | `highlightBorderWidth` :79 |
| 文字弱化次级信息 | 见下"排版层次" | — |

- **排版层次（高风险、需人工确认）**：把「应用名 – 窗口标题」拆成两段——应用名 `white@0.95 / .medium`，分隔符与窗口标题 `white@0.55 / .regular`。需改 `TileView.getAppOrAndWindowTitle()` 返回结构化片段，并在 `TileTitleView` 用 `attributedStringValue` 分段着色（注意与既有 search-highlight 的 `attributedStringValue` 逻辑叠加，`TileView.applySearchHighlight()` 会整体重写富文本，需协调）。
- **改动量**：高亮部分 5 行；若做排版层次则额外改 2 个文件（`TileView` + `TileTitleView`），约 30–50 行，且与搜索高亮耦合。
- **回归风险**：高亮部分低；**排版层次部分中高**（与 `applySearchHighlight` 的富文本重写、截断映射 `truncatedDisplay` 共用一条 attributedString 管线，易顾此失彼）。
- **是否偏离上游**：高亮偏离中等（去色）；排版层次**显著偏离上游**，未来同步成本高。

**优点**：最克制、最不容易"廉价彩色感"，在多彩壁纸上更稳。
**缺点**：去掉 accent 后选中态辨识度依赖填充对比，弱用户可能觉得"不够明显"；排版层次改动触碰高耦合的富文本管线，无人值守不宜动。
**推荐**：作为"想要更安静观感"的人工可选项；**排版层次拆分务必人工评审后再做**。

---

## 方向 C：鲜明玻璃质感有层次

**参照**：visionOS / macOS 26 Liquid Glass、Sonoma 控制中心 —— 选中态较强的 accent 填充 + 细高光描边 + 更大圆角 + 应用名/标题分层，"有质感、有层次、略张扬"。

**精确代码改动点**：

| 改动 | 改前 → 改后 | 行 |
|----|----|----|
| 选中填充加重 | `accent@0.20 → accent@0.38` | :33 |
| 悬停填充 | `accent@0.10 → accent@0.20` | :34 |
| 选中描边保留但偏高光 | `accent@1.0 → accent@0.65` | :35 |
| 悬停描边 | `accent@0.70 → accent@0.40` | :36 |
| 描边宽度 | titles `2`（保留，作高光边） | :79 |
| 圆角更大 | titles `cellCornerRadius 10 → 14` | :164 |
| 行高留白 | titles `edgeInsetsSize 7 → 9` | :165 |
| 字重提一档 | titles 普通 → `.medium`（全系统版本，改 `updateFont`） | :182 |
| 排版层次 | 应用名纯白 `.semibold` / 标题 `white@0.6`（同方向 B 的高风险改动） | `TileView`+`TileTitleView` |

- **改动量**：高亮 + 尺寸 + 字重约 8 行 `Appearance.swift`；排版层次另算（同 B，30–50 行跨文件）。
- **回归风险**：`Appearance.swift` 部分中低（尺寸/字重变化会影响行高与面板宽度计算，需目测面板不溢出）；排版层次部分中高。
- **是否偏离上游**：偏离较大（多处尺寸 + 字重 + 排版结构）。

**优点**：最出彩、最有"设计感"和层次；适合喜欢鲜明玻璃质感的用户。
**缺点**：accent@0.38 较抢眼，浅色 accent 下可能偏艳；尺寸/字重改动牵连布局计算，回归面更大；同样涉及高耦合排版改动。
**推荐**：作为"想要更强视觉"的人工可选项，建议**分两步**：先只调高亮+圆角（低风险），排版层次单独评审。

---

## 三方向对比与建议

| 维度 | A 柔和现代 | B 极简单色 | C 玻璃层次 |
|----|----|----|----|
| 改动集中度 | ★★★★★ | ★★★☆（含排版则★★） | ★★（多处） |
| 回归风险 | 极低 | 低（排版部分中高） | 中（排版部分中高） |
| 偏离上游 | 小 | 中（排版大） | 大 |
| 视觉现代感 | 高 | 中（克制） | 最高 |
| 无人值守可安全落地 | ✅ 全部 | 仅高亮部分 | 仅高亮+圆角 |

**总建议**：本次无人值守**只落地方向 A 的高亮柔和填充**（最稳、最不主观、改动最集中，见交付物 2）。方向 B / C 的取舍、以及三者共有的「应用名 / 窗口标题排版层次拆分」都需要**肉眼挑选 + 人工评审**（尤其排版层次会触碰 `applySearchHighlight` 的富文本管线），留给用户决策。

## 待人工决策清单

1. **排版层次拆分**（应用名重、窗口标题轻）：方向 B/C 共有，风险点在与 `TileView.applySearchHighlight()` 的 `attributedStringValue` 富文本/截断管线耦合，需人工设计与回归。
2. **方向 B vs C 的整体取向**：要"更安静（B）"还是"更鲜明（C）"，属主观审美，需用户拍板。
3. **方向 A 的可选微调**：`edgeInsetsSize 7→8`、`cellCornerRadius 10→12` 是否一并采用（本次未改，保持最小落地）。
4. **填充 alpha 的口味**：0.30 是保守中值，若觉得偏淡/偏重可在 `0.28–0.35` 区间微调。
