#!/bin/bash

# 字体复制脚本
# 用途：将 KaTeX 字体文件从 LateXDemo 复制到 MarkdownDisplayView

set -e  # 遇到错误立即退出

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}开始复制 KaTeX 字体文件${NC}"
echo -e "${GREEN}========================================${NC}"

# 源目录和目标目录
SOURCE_DIR="/Users/zhujichao_1/Desktop/zjc19891106/LateXDemo/LateXDemo"
TARGET_DIR="/Users/zhujichao_1/Desktop/zjc19891106/MarkdownDisplayView/MarkdownDisplayView/Sources/MarkdownDisplayView/Resources"

# 创建目标目录
echo -e "${YELLOW}创建目标目录...${NC}"
mkdir -p "$TARGET_DIR"

# 复制所有 KaTeX 字体文件
echo -e "${YELLOW}复制字体文件...${NC}"
cp "$SOURCE_DIR"/KaTeX_*.ttf "$TARGET_DIR/"

# 统计复制的文件数量
FONT_COUNT=$(ls -1 "$TARGET_DIR"/KaTeX_*.ttf 2>/dev/null | wc -l)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ 成功复制 $FONT_COUNT 个字体文件${NC}"
echo -e "${GREEN}========================================${NC}"

# 列出复制的文件
echo -e "${YELLOW}已复制的字体文件：${NC}"
ls -1 "$TARGET_DIR"/KaTeX_*.ttf | xargs -n 1 basename

echo ""
echo -e "${GREEN}字体文件复制完成！${NC}"
echo -e "${YELLOW}接下来需要：${NC}"
echo -e "  1. 配置 CocoaPods 的 resource_bundles"
echo -e "  2. 配置 SPM 的 Package.swift resources"
echo -e "  3. 更新 Info.plist 注册字体"
