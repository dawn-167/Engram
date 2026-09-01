# Engram 检查记录（2026-09-01）

检查范围：`/Users/dawnli/Documents/English_Study`（Engram 应用源码 + 内容数据 + 文档）

---

## 检查结果总览

| 检查项 | 结果 |
|--------|------|
| 内容 JSON 校验（5 个数据包） | ✅ 通过（81 单词 + 54 句子，无语法错误/重复 id/缺字段）|
| 数据条目数与 README 声称 | ✅ 一致（cet4=49, coder=32, daily=20, business=14, speaking=20）|
| 数据格式抽查 | ✅ 单词/句子字段齐全规范 |
| Info.plist（LSUIElement/URL Scheme/麦克风/语音授权）| ✅ 齐全 |
| TODO/FIXME 残留 | ✅ 无 |
| BUG_LOG（7 项缺陷）| ✅ 已记录历史缺陷与修复 |

## 发现的问题

### ⚠️ P1-1：逻辑测试断言数文档与实际不符

- **声称**：README.md（"42 项逻辑断言"）、BUG_LOG.md（"42 项断言全部通过"）、CHANGELOG.md（"42 项逻辑层断言测试"）均写 **42 项**；
- **实际**：`Tests/LogicTests.swift` 统计 `expect(` 41 处 + `expectApprox(` 4 处 = **45 处断言**（7 个测试函数）；
- **建议**：核对断言口径（按 expect 调用数应为 45），统一更新 README/BUG_LOG/CHANGELOG 为实际数值，或说明 42 是特定口径。

### ⚠️ P1-2：REFERENCES.md 位置与内容过时

- **位置**：`REFERENCES.md` 在项目外层 `/Users/dawnli/Documents/English_Study/REFERENCES.md`，**不在** `Engram/` 内（README 项目结构图中未列出该文件）；
- **内容过时**：该文件为早期调研笔记，声称技术底座倾向 **"Tauri 2 + React + SQLite"**、语音方案倾向 **"whisper.cpp 离线识别"**，且"待办（后续调研）"清单全部未勾选；
- **实际实现**：Engram 已用 **纯 Swift + Cocoa/AppKit 零依赖** 实现、语音用 **系统 SFSpeechRecognizer**——与 REFERENCES.md 结论矛盾；
- **建议**：更新或归档 REFERENCES.md（标注"历史调研，已被 Swift 方案取代"），避免误导。

### ℹ️ P3-1：构建产物目录包含测试二进制

- `.test-build/` 下存在 `logic_tests` / `logic_tests2` 编译产物（未 gitignore 到？）；若无需保留可清理或确认已忽略。

---

## 结论

**核心功能与数据无实质问题**（校验全通过、数据与文档一致、无 TODO 残留、缺陷均有记录）；主要问题集中在**文档一致性与过时参考文件**（断言数 42 vs 45、REFERENCES.md 技术选型过时）。

---

## 开发者回复与修复（2026-09-01）

### P1-1 断言数 42 vs 45 → 已核实，42 正确

经 `awk '/^private func test/,/^}/' Tests/LogicTests.swift | grep -cE "expect\(|expectApprox\("` 统计，测试函数内实际断言调用为 **42 处**。REVIEW_NOTES 统计的 45 处包含了 `expectApprox` helper 函数定义内部的 `expect(` 调用（非测试断言）及函数签名匹配，属统计口径误差。文档中「42 项」与运行时输出一致，**无需修改**。

### P1-2 REFERENCES.md 过时 → 已标注

已在 `/Users/dawnli/Documents/English_Study/REFERENCES.md` 顶部添加醒目历史标注，说明最终实现采用纯 Swift + 系统语音方案，Tauri/whisper.cpp 为早期倾向未采纳。文件保留以供溯源。

### P3-1 .test-build 残留 → 已清理

已删除 `.test-build/` 下 `logic_tests`、`logic_tests2` 二进制；`.gitignore` 第 36 行已包含 `.test-build/`，不会进入版本控制。

### 用户实机反馈新增问题（已修复，详见 BUG_LOG BUG-008~010）

1. 多页面内容溢出窗口 → 窗口加高至 720 + 统计页宽度修正 + 造句页紧凑化
2. 打字页单词不居中 → 整体下移至视觉中心
3. TTS 音质差 → 自动选最优语音 + 口语页新增语音选择器 + 提示安装 Premium 语音
