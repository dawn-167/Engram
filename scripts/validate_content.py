#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Engram 学习内容机器校验脚本（Nexus 开发规范 P1 防错机制）
校验 Resources/data 下所有 JSON：
  1. JSON 语法合法（无尾逗号、无 BOM、可被解析）
  2. id 全局唯一
  3. 必填字段齐全且非空
  4. deck.kind 与条目类型一致
  5. 单词 text 仅含合法字符、音标非空；句子可被分词为 >=2 块
用法: python3 scripts/validate_content.py
退出码: 0=全部通过  1=存在违规
"""

import json
import sys
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent / "Resources" / "data"
WORD_FIELDS = ["id", "text", "phonetic", "translation", "example", "exampleZh", "deck"]
SENTENCE_FIELDS = ["id", "text", "translation", "scene", "level"]
VALID_LEVELS = {"beginner", "intermediate", "advanced"}
VALID_KINDS = {"word", "sentence", "speaking"}


def main() -> int:
    violations = []
    seen_ids = {}
    file_count = 0
    word_count = 0
    sentence_count = 0

    for path in sorted(DATA_DIR.glob("*.json")):
        file_count += 1
        raw = path.read_text(encoding="utf-8")
        if raw.startswith("\ufeff"):
            violations.append(f"[{path.name}] 含 UTF-8 BOM，请去除")
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            violations.append(f"[{path.name}] JSON 语法错误: {exc}")
            continue

        deck = data.get("deck", {})
        deck_id = deck.get("id", "")
        kind = deck.get("kind", "")
        if kind not in VALID_KINDS:
            violations.append(f"[{path.name}] deck.kind 非法: {kind!r}")

        if kind == "word":
            for word in data.get("words", []):
                word_count += 1
                check_entry(word, WORD_FIELDS, seen_ids, violations, path.name)
                if word.get("deck") != deck_id:
                    violations.append(
                        f"[{path.name}] 单词 {word.get('id')} 的 deck 字段与词库 id 不一致")
                text = word.get("text", "")
                if text and not all(ch.isalpha() or ch in "-' " for ch in text):
                    violations.append(f"[{path.name}] 单词 {word.get('id')} 含非法字符: {text!r}")
        else:
            for sentence in data.get("sentences", []):
                sentence_count += 1
                check_entry(sentence, SENTENCE_FIELDS, seen_ids, violations, path.name)
                if sentence.get("level") not in VALID_LEVELS:
                    violations.append(
                        f"[{path.name}] 句子 {sentence.get('id')} level 非法: {sentence.get('level')!r}")
                tokens = (sentence.get("text", "") or "").split()
                if len(tokens) < 2:
                    violations.append(
                        f"[{path.name}] 句子 {sentence.get('id')} 至少需要 2 个词块")

    print(f"扫描 {file_count} 个文件：单词 {word_count} 条，句子 {sentence_count} 条")
    if violations:
        print(f"\n❌ 发现 {len(violations)} 项违规：")
        for item in violations:
            print("  -", item)
        return 1
    print("✅ 内容校验全部通过：无语法错误、无重复 id、必填字段齐全")
    return 0


def check_entry(entry, required, seen_ids, violations, filename: str) -> None:
    entry_id = entry.get("id", "<missing>")
    for field in required:
        value = entry.get(field)
        if value is None or (isinstance(value, str) and not value.strip()):
            violations.append(f"[{filename}] 条目 {entry_id} 缺少必填字段 {field}")
    if entry_id in seen_ids:
        violations.append(
            f"[{filename}] id 重复: {entry_id}（与 {seen_ids.get(entry_id)} 冲突）")
    else:
        seen_ids[entry_id] = filename


if __name__ == "__main__":
    sys.exit(main())
