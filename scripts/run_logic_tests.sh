#!/bin/bash
# ============================================================
# Engram Services 纯逻辑层命令行测试（不依赖 UI、不启动应用）
# 编译 Models + Services + Tests 为临时可执行文件并运行
# ============================================================
set -e
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.test-build"
mkdir -p "$BUILD_DIR"

SWIFT_FILES=$(find "$PROJECT_DIR/Sources/Models" "$PROJECT_DIR/Sources/Services" -name "*.swift" | sort)
TEST_FILE="$PROJECT_DIR/Tests/LogicTests.swift"

echo "🔨 编译逻辑层测试..."
swiftc $SWIFT_FILES "$TEST_FILE" \
    -o "$BUILD_DIR/logic_tests" \
    -framework AVFoundation \
    -framework Speech \
    -framework Foundation

echo "🧪 运行测试..."
"$BUILD_DIR/logic_tests"
