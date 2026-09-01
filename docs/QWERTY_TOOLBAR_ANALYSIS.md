# qwerty-learner 任务栏分析（供 Engram 移植参考）

> 来源：本地克隆 `english-learning-app/qwerty-learner`（https://github.com/Kaiyiwing/qwerty-learner，浅克隆 `122acd9`）
> 分析日期：2026-09-01 ｜ 用途：确认任务栏 UI 元素是否在代码中、可否提取，并列出完整功能清单

---

## 一、任务栏功能清单（13 个元素 + 附加）

qwerty 顶部控制栏（`src/components/Header/`），从左到右：

| # | 元素 | 状态 | 功能 |
|---|------|------|------|
| 1 | **CET-4** | 文字 | 当前词库名。点击跳转词库选择页（`/gallery`），可切换词库（CET-4/CET-6/考研/雅思/托福…） |
| 2 | **第 4 章** | 文字 | 当前章节。点击弹出章节下拉（`Listbox`），切换学习章节（每章一组词） |
| 3 | **美音** | 文字 | **发音/音标切换入口**。弹出面板：音标显示开关、单词发音开关、释义发音开关、循环发音开关、口音选择（美音/英音/日/德…） |
| 4 | 🔊 喇叭 | 蓝紫 | **音效设置**：开关按键音、开关效果音 |
| 5 | ↻ 循环 | 灰=关 | **单词循环次数**：1 / 3 / 5 / 8 / 无限次重复当前单词（默认 1，灰显） |
| 6 | 🙈 眼睛+斜杠 | 灰=关 | **默写模式**（`Ctrl+V`）：隐藏全部 / 隐藏元音 / 隐藏辅音 / 随机隐藏，边听边默写 |
| 7 | 🈯 A+− 形图标 | 蓝紫 | **释义显示开关**（`Ctrl+Shift+V`）：显示/隐藏中文释义 |
| 8 | 📕 书本 | 蓝紫 | **错题本**：跳转错题页（`/error-book`），查看/复习打错的单词 |
| 9 | 🥧 饼图 | 蓝紫 | **数据统计**：跳转统计页（`/analysis`，热力图、键盘按键热图、WPM 趋势） |
| 10 | ☀️ 太阳 | 蓝紫 | **深色模式开关**（日/月图标切换） |
| 11 | ⌨️ 键盘 | 蓝紫 | **指法图示**：弹出推荐打字指法图 |
| 12 | ⚙️ 齿轮 | 蓝紫 | **设置对话框**（视图 / 数据 / 音效 / 高级 四页 Tab） |
| 13 | **Start** | 蓝紫主按钮 | **开始/暂停**本节练习（`Enter`）；悬停展开 **Restart** 重新开始 |

**附加**（开始输入后出现在 Start 旁）：**Skip** 按钮 —— 跳过当前单词。

**布局规律**：左侧文字 = "你在哪"（词库/章节/发音）→ 中间图标 = "怎么学/怎么看"（音效、循环、默写、释义、错题本、统计、主题、指法、设置）→ 右侧 Start = "开始"。

**相关快捷键**：`Enter` 开始/暂停 ｜ `Ctrl+V` 默写模式 ｜ `Ctrl+Shift+V` 释义开关 ｜ `Ctrl+J` 朗读发音 ｜ `Tab` 临时显示释义。

---

## 二、UI 元素是否在代码中？能否提取？

**结论：组件全部在代码中（✅ 可提取），图标只存名字（⚠️ SVG 数据不在仓库内）。**

| 类别 | 是否在代码中 | 说明 |
|------|-------------|------|
| 工具栏**布局与组件**（Header、各开关、Start、Skip） | ✅ 全在 | 位于 `src/components/Header/` 与 `src/pages/Typing/components/`，已原样提取到 `qwerty-toolbar-src/`（14 个文件） |
| **图标**（喇叭/循环/眼睛/A+−/书本/饼图/太阳/键盘/齿轮） | ⚠️ 只有名字 | 代码用 iconify 按名引用：`~icons/heroicons/xxx`、`~icons/tabler/xxx`。构建时由 `unplugin-icons` 从 `@iconify/json`（devDependency）解析出 SVG 路径；仓库无 `node_modules`，**SVG 数据不在 git 里** |
| 自定义 SVG | ✅ 仅 2 个 | `src/assets/logo.svg`、`src/assets/xiaohongshu.svg`（通过 vite `customCollections` 引用），与工具栏无关 |

**获取图标 SVG 的途径**（如需还原像素级图标）：
1. **已提取**：全仓库 **64 个 iconify 图标 + 3 个本地 SVG** 已下载到 `docs/qwerty-icons-all/`（文件名 `集合_图标名.svg`，0 空文件）；其中任务栏 13 个另存于 `docs/qwerty-icons/` 便于查看
2. 其他图标可再从 iconify CDN 取：`https://api.iconify.design/<集合>/<图标名>.svg`（例如 `https://api.iconify.design/tabler/repeat.svg`）
3. **移植到 Engram（AppKit）推荐**：直接用 macOS 内置 **SF Symbols** 替代（见第五节映射表），无需引入图标资源

---

## 三、图标清单（组件 → 图标导入 → 含义）

| 工具栏元素 | 源码文件 | 图标 import（iconify） | 含义 |
|-----------|---------|------------------------|------|
| 词库/章节 | `DictChapterButton/index.tsx` | 无（纯文字） | 词库名 + 章节下拉 |
| 发音切换 | `PronunciationSwitcher/index.tsx` | 无（纯文字，弹出面板内 Switch） | 美音/英音 + 音标/发音开关 |
| 音效 | `SoundSwitcher/index.tsx` | `heroicons/speaker-wave-solid` | 按键音/效果音开关 |
| 循环 | `LoopWordSwitcher/index.tsx` | `tabler/repeat`、`tabler/repeat-off` | 单词循环次数 1/3/5/8/∞ |
| 默写 | `WordDictationSwitcher/index.tsx` | `heroicons/eye-slash-solid`、`heroicons/eye-solid` | 默写模式开关（Ctrl+V） |
| 释义开关 | `Switcher/index.tsx`（内联） | `tabler/language`、`tabler/language-off` | 释义显示开关（Ctrl+Shift+V） |
| 错题本 | `ErrorBookButton.tsx` | `bxs/book` | 跳转错题页 |
| 统计 | `AnalysisButton/index.tsx` | `heroicons/chart-pie-solid` | 跳转统计页 |
| 深色模式 | `Switcher/index.tsx`（内联） | `heroicons/sun-solid`、`heroicons/moon-solid` | 明暗主题切换 |
| 指法 | `HandPositionIllustration/index.tsx` | `ic/round-keyboard` | 弹出指法图 |
| 设置 | `Setting/index.tsx` | `heroicons/cog-6-tooth-solid` | 设置对话框 |
| Start | `StartButton/index.tsx` | 无（纯文字 + indigo 底色） | 开始/暂停 + Restart |

---

## 四、提取的源码文件（`docs/qwerty-toolbar-src/`，14 个）

```
qwerty-toolbar-src/
├── Header.tsx                      # 顶部栏容器（logo+标题 / 白卡按钮组）
├── Tooltip.tsx                     # 悬浮提示组件（各图标 tooltip 依赖）
├── TypingPage.tsx                  # 打字页整体（含 Skip 按钮、计时器、状态机接线）
├── DictChapterButton/index.tsx     # 词库名 + 章节下拉
├── PronunciationSwitcher/index.tsx # 发音/音标/口音切换面板
├── Switcher/index.tsx              # 图标组容器（释义开关、深色模式内联于此）
├── SoundSwitcher/index.tsx         # 音效设置（按键音/效果音）
├── LoopWordSwitcher/index.tsx      # 单词循环次数
├── WordDictationSwitcher/index.tsx # 默写模式（隐藏全部/元音/辅音/随机）
├── ErrorBookButton.tsx             # 错题本入口
├── AnalysisButton/index.tsx        # 数据统计入口
├── HandPositionIllustration/index.tsx # 指法图示弹窗
├── Setting/index.tsx               # 设置对话框（视图/数据/音效/高级）
└── StartButton/index.tsx           # Start/Pause + Restart
```

> 说明：以上为 qwerty 原样源码（React/TSX），仅供 Engram（Swift/AppKit）移植时对照行为与样式，不能直接编译进项目。

---

## 五、移植到 Engram 的 SF Symbols 映射建议

| qwerty 图标 | 功能 | macOS SF Symbols |
|------------|------|-----------------|
| speaker-wave | 音效 | `speaker.wave.2.fill` |
| repeat / repeat-off | 循环 | `repeat` / `repeat.1` |
| eye / eye-slash | 默写 | `eye.fill` / `eye.slash.fill` |
| language（A+−） | 释义开关 | `textformat.size` |
| book | 错题本 | `book.fill` |
| chart-pie | 统计 | `chart.pie.fill` |
| sun / moon | 深色模式 | `sun.max.fill` / `moon.fill` |
| keyboard | 指法 | `keyboard.fill` |
| cog | 设置 | `gearshape.fill` |
| Start（按钮） | 开始/暂停 | `play.fill` / `pause.fill`（可配文字） |

---

## 六、全部 UI 图标提取（`docs/qwerty-icons-all/`，64 + 3 个）

> 全仓库扫描 `~icons/` 导入共 **64 个唯一图标**（90 处引用，21 个 iconify 集合），已全部下载；另复制 3 个本地 SVG。文件名 = `集合_图标名.svg`。

| 集合 | 数量 | 图标 |
|------|------|------|
| bxs | 1 | book（错题本） |
| fa | 2 | sort-down, sort-up |
| heroicons | 17 | chart-pie-20-solid, chart-pie-solid（统计）, check-circle-20-solid, check-circle-solid, clock-20-solid, cog-6-tooth-solid（设置）, exclamation-triangle-solid, eye-slash-solid（默写关）, eye-solid（默写开）, hand-thumb-up-solid, heart-solid, moon-solid（深色）, speaker-wave-solid（音效）, star-solid, sun-solid（深色）, x-circle-20-solid, x-mark-solid |
| ic | 4 | outline-collections-bookmark, outline-error, outline-info, round-keyboard（指法） |
| icon-park-outline | 1 | excel（导出） |
| logos | 1 | partytown-icon |
| majesticons | 1 | paper-fold-text-line |
| material-symbols | 3 | mail, star, star-outline |
| mdi | 2 | coffee, robot-angry |
| ooui | 2 | next-ltr, next-rtl |
| pajamas | 1 | review-list |
| ph | 2 | arrows-down-up-fill, warning |
| ri | 2 | links-line, twitter-fill |
| simple-icons | 3 | github, visualstudiocode, wechat |
| solar | 1 | sticker-smile-square-outline |
| tabler | 19 | adjustments-horizontal, arrow-narrow-left, arrow-narrow-right, book-2, brand-wechat, check, chevron-down, circle-x, coffee, database-cog, ear, language（释义开）, language-off（释义关）, list, repeat（循环开）, repeat-off（循环关）, share-2, terminal-2, x |
| twemoji | 1 | flag-china |
| weui | 1 | delete-filled |

**本地 SVG（3 个，已复制进同目录）**：`my-icons_logo.svg`（品牌 logo）、`my-icons_xiaohongshu.svg`（自定义集合图标）、`_local_keyBackground.svg`（分享海报背景）。

> 另外 `SoundIcon.tsx` / `VolumeIcon.tsx`（单词发音图标组件）是手写内联 SVG，已在源码中，无需提取。

---

*文档结束 · 与 qwerty 仓库 `122acd9` 对齐*
