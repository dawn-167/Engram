# Engram — 英语记忆引擎

> 融合四款开源英语学习工具优点的 macOS 原生离线应用。
> 纯 Swift + Cocoa/AppKit，零第三方依赖，零云 API Key，菜单栏常驻。

## 它融合了什么

| 来源项目 | 借鉴的优点 | 在 Engram 中的实现 |
|---|---|---|
| [Qwerty Learner](https://github.com/Kaiyiwing/qwerty-learner) | 打字背单词、输错整词重来、音标发音、WPM/正确率 | 「单词打字」模块，逐字母着色、错词重置、系统 TTS 朗读 |
| [Earthworm](https://github.com/cuixueshe/earthworm) | 句子拆词块打乱、按语序还原、即时纠错 | 「连词造句」模块，流式词块点选、前缀校验、错选即拒 |
| [ChatterPal](https://github.com/likebeans/ChatterPal) | 跟读评测、多维发音评分、场景分级 | 「口语私教」模块，改用 macOS 系统离线识别 + 自研 LCS 词级对齐评分 |
| [Anki](https://github.com/ankitects/anki) | SM-2 间隔重复、到期复习队列 | 「复习」模块，四档评分翻转卡，自研 SM-2（未复制 AGPL 代码） |

**核心融合点**：四个模块共享同一套记忆调度状态。任何模块练过的条目都会进入统一的到期复习队列，实现跨模块的记忆曲线。

## 系统要求

- macOS 14.0 及以上（Apple Silicon / Intel 均可）
- 首次使用口语模块需授权麦克风与语音识别（识别优先在本机离线运行）

## 快速开始

```bash
# 构建（编译 + 同步资源 + ad-hoc 签名）
./build.sh

# 运行
open Engram.app

# 清理后重建
./build.sh --clean

# 不签名构建（调试用）
./build.sh --no-sign
```

构建产物：`Engram.app`（位于项目根目录）。

## 使用方式

- 应用启动后驻留菜单栏（无 Dock 图标），窗口默认出现在外接副屏。
- **全局热键** `⌃⌥E`（Ctrl+Option+E）随时唤出/隐藏窗口。
- 左侧栏切换模块：学习中心 / 单词打字 / 连词造句 / 口语私教 / 复习 / 学习统计。
- 打字页直接敲击键盘输入；错一个字母整词重来。
- 复习页点击卡片或按空格翻面，选择「忘记/困难/良好/简单」四档评分。
- 进度自动保存到 `~/Library/Application Support/Engram/progress.json`。

## 深链（URL Scheme）

```
nexus-engram://                     唤出窗口
nexus-engram://page?name=typing     直达单词打字
nexus-engram://page?name=sentence   直达连词造句
nexus-engram://page?name=speaking   直达口语私教
nexus-engram://page?name=review     直达复习
nexus-engram://page?name=stats      直达学习统计
nexus-engram://page?name=home       回到学习中心
```

## 学习内容

内置 5 个内容包（`Resources/data/`）：

- `words_cet4.json` — 四级核心词（49 条）
- `words_coder.json` — 程序员英语（32 条）
- `sentences_daily.json` — 日常口语句（20 条）
- `sentences_business.json` — 商务与旅行句（14 条）
- `speaking_scenes.json` — 口语场景句（20 条）

新增内容只需放入同格式 JSON，无需改代码。格式见 `docs/TECHNICAL_DOCUMENTATION.md`。

## 项目结构

```
Engram/
├── Sources/
│   ├── main.swift              # 入口
│   ├── App/                    # AppDelegate / AppState / RootViewController
│   ├── Models/                 # 纯数据结构
│   ├── Services/               # 业务逻辑（纯逻辑，可命令行测试）
│   ├── Views/                  # 界面层
│   └── Common/                 # Nexus CommonKit（只读）
├── Resources/
│   ├── AppIcon.icns
│   └── data/                   # 学习内容 JSON
├── Tests/LogicTests.swift      # 42 项逻辑断言
├── scripts/                    # 内容校验 / 逻辑测试 / 图标生成
├── build.sh                    # Nexus 标准构建脚本
├── Info.plist
├── nexus.json                  # Nexus 应用元信息
└── docs/                       # 设计与技术文档
```

## 质量验证

- `python3 scripts/validate_content.py` — 内容 JSON 机器校验
- `bash scripts/run_logic_tests.sh` — 42 项逻辑层断言
- `swiftc` 全量编译 — 零警告

## 许可

本项目代码为原创实现。SM-2 算法基于公开的 SuperMemo 算法描述自行编写，未复制 Anki 源码，不受 AGPL 约束。学习内容为示例数据。
