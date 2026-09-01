# 技术文档 — Engram

## 1. 架构

遵循 Nexus 五层架构，单向依赖：

```
App（AppDelegate / AppState / RootViewController）
  ↓
Views（页面视图 + 通用组件）
  ↓
Services（业务逻辑，纯逻辑可测试）
  ↓
Models（纯数据结构）
  ↑
Common（Nexus CommonKit，只读）
```

- **Services 层**不 import 任何 UI 类型（NSView / NSWindow 等），全部可在命令行直接断言测试。
- **Views 层**不直接读写文件或 UserDefaults，数据通过 Service 获取。
- **Common 层**从 Nexus TEMPLATE 复制，只读不改。
- 所有 Service 先定义 `XxxProtocol`，便于替换与测试。

## 2. 核心模块

### 2.1 SpacedRepetitionService（SM-2 间隔重复）

自研实现，基于公开的 SuperMemo SM-2 算法描述，未复制 Anki 源码（规避 AGPL）。

- EF 初始 2.5，下限 1.3。
- 间隔：第 1 次 1 天，第 2 次 6 天，之后 `上次间隔 × EF`（四舍五入）。
- 未通过（q < 3）：重置连续成功次数，10 分钟后重现（学习阶段）。
- EF 调整：`EF' = EF + (0.1 - (5-q)×(0.08 + (5-q)×0.02))`。
- 四档评分映射：忘记=1、困难=3、良好=4、简单=5。

### 2.2 TypingService（打字状态机）

- 逐字符输入，大小写不敏感。
- 输错任一字符 → 整词重置（typedLength=0），避免错误肌肉记忆。
- 统计：完成词数、正确按键、总按键、错词数、耗时。
- WPM = 正确按键数 / 5 / 分钟数（通用口径）。
- 正确率 = 正确按键 / 总按键。

### 2.3 SentenceBuildService（连词造句）

- 按空白分词，撇号缩写（don't / I'm）保持完整。
- 打乱保证结果不等于原序（最多 20 次尝试）。
- 前缀校验：已选词块与目标句逐位置比对，错选即拒。
- 完成判定：已选 == 目标。

### 2.4 PronunciationScorer（发音评分）

- 归一化：小写、去标点、按词切分。
- 词级对齐：最长公共子序列（LCS），得到命中词 / 漏词 / 多词。
- 准确度 = 命中率 − 多词轻微惩罚（上限 15%），0~100。
- WPM = 识别词数 / 分钟数。
- 评级：优秀 ≥90、良好 75~89、及格 55~74、需练习 <55。
- 空识别结果安全返回 0 分（LCS 用半开区间，不会触发范围崩溃）。

### 2.5 SpeechService（TTS）

- AVSpeechSynthesizer，优先 `com.apple.voice.enhanced.en-US.Samantha`，回退 en-US。
- 语速以系统默认语速为基准，0.3~0.6 适合学习。
- @MainActor 隔离，AVSpeechSynthesizer 用 `nonisolated(unsafe)` 标注（约定仅主线程访问）。

### 2.6 SpeechRecognitionService（ASR）

- SFSpeechRecognizer（en-US），`requiresOnDeviceRecognition = supportsOnDeviceRecognition`（优先离线）。
- AVAudioEngine inputNode tap 采集，音频线程回调统一切主线程。
- 主动停止时以当前已识别文本收尾，避免用户卡死。
- 出错且非主动取消时同样收尾。

### 2.7 ReviewService（复习队列）

- 从全部 MemoryItem 中筛到期项，新条目（从未复习）优先，其次按到期时间升序。
- 评分后落库并累加今日复习数。

### 2.8 ProgressStore（持久化）

- 唯一允许读写磁盘的 Service，路径 `~/Library/Application Support/Engram/progress.json`。
- ISO8601 日期编码，pretty-printed JSON。
- `mutate` 临界区自动落盘 + 维护连续天数。
- `ensureItem`：新条目首次出现计入「今日新学」。
- `recordToday`：累加今日某项练习量。

### 2.9 StatsService（统计聚合）

- 仪表盘汇总：到期数、已学、已掌握（连续成功 ≥3 次）、连续天数、今日行动、今日新学、七日活跃、打字正确率、口语均分、各模块累计量。
- 缺失日期补零。

## 3. 跨模块记忆接线

| 模块 | 完成动作 | 记忆登记 | 每日统计 |
|---|---|---|---|
| 单词打字 | 正确打完一词 | `.word` + `.good` | wordsTyped +1 |
| 连词造句 | 正确组完一句 | `.sentence` + `.good` | sentencesBuilt +1 |
| 口语私教 | 评分完成 | `.speaking` + 按准确度映射（≥90 easy / 60~89 good / 30~59 hard / <30 again） | spoken +1，发音分累加 |
| 复习 | 四档评分 | 对应评分 | reviewed +1 |

打字会话结束时还会累加 keyPressCorrect / keyPressTotal 用于正确率统计。

## 4. 内容格式

### 4.1 词库 JSON（words_*.json）

```json
{
  "deck": { "id": "cet4-core", "name": "四级核心词", "description": "...", "kind": "word" },
  "words": [
    { "id": "cet4-abandon", "text": "abandon", "phonetic": "/əˈbændən/",
      "translation": "v. 放弃；抛弃", "example": "...", "exampleZh": "...", "deck": "cet4-core" }
  ]
}
```

### 4.2 句库 JSON（sentences_*.json / speaking_*.json）

```json
{
  "deck": { "id": "daily-sentences", "name": "日常口语", "description": "...", "kind": "sentence" },
  "sentences": [
    { "id": "daily-001", "text": "How do I get to the station?",
      "translation": "去车站怎么走？", "scene": "travel", "level": "beginner" }
  ]
}
```

`kind` 取值：`word` / `sentence` / `speaking`。`level`：`beginner` / `intermediate` / `advanced`。

## 5. 构建

```bash
./build.sh              # 编译 + 同步资源 + ad-hoc 签名
./build.sh --no-sign    # 不签名
./build.sh --clean      # 清理后重建
```

- `swiftc` 收集 `Sources/` 下所有 `.swift`，链接 Cocoa / Carbon / AVFoundation / Speech。
- `-O -whole-module-optimization`。
- 输出 `Engram.app/Contents/MacOS/Engram`，同步 `Resources/`，`codesign --force --deep --sign -`。

## 6. 测试与校验

```bash
python3 scripts/validate_content.py   # 内容 JSON 校验
bash scripts/run_logic_tests.sh       # 42 项逻辑断言
```

逻辑测试覆盖：SM-2 调度、打字状态机（正确/错误/跳过/完成）、造句分词与校验、发音评分 LCS（含空输入）、内容加载、持久化读写。

## 7. 应用身份

| 字段 | 值 |
|---|---|
| 显示名 | Engram |
| id | engram |
| 类别 | life |
| Bundle ID | com.nexus.life.engram |
| URL Scheme | nexus-engram |
| 全局热键 | Ctrl+Option+E（kVK_ANSI_E） |
| Carbon 签名 | 0x454E（"EN"） |
| 最低系统 | macOS 14.0 |
| 主题色 | #6C5CE7 |

## 8. 隐私

- 语音识别优先 on-device 离线运行，不上传音频。
- 进度数据仅存本地 `~/Library/Application Support/Engram/`。
- 无网络请求、无遥测、无第三方 SDK。
