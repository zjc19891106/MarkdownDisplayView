#!/bin/bash

# LaTeX 集成验证脚本
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}LaTeX 公式集成验证${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查字体文件
echo -e "${YELLOW}[1/6] 检查字体文件...${NC}"
FONT_DIR="/Users/zhujichao_1/Desktop/zjc19891106/MarkdownDisplayView/MarkdownDisplayView/Sources/MarkdownDisplayView/Resources"
FONT_COUNT=$(ls -1 "$FONT_DIR"/KaTeX_*.ttf 2>/dev/null | wc -l)

if [ "$FONT_COUNT" -eq 20 ]; then
    echo -e "${GREEN}✅ 找到 20 个字体文件${NC}"
else
    echo -e "${RED}❌ 字体文件不完整，期望 20 个，实际 $FONT_COUNT 个${NC}"
    exit 1
fi

# 检查 LaTeXAttachment.swift
echo -e "${YELLOW}[2/6] 检查 LaTeXAttachment.swift...${NC}"
if [ -f "/Users/zhujichao_1/Desktop/zjc19891106/MarkdownDisplayView/MarkdownDisplayView/Sources/MarkdownDisplayView/LaTeXAttachment.swift" ]; then
    echo -e "${GREEN}✅ LaTeXAttachment.swift 存在${NC}"
else
    echo -e "${RED}❌ LaTeXAttachment.swift 不存在${NC}"
    exit 1
fi

# 检查 FontLoader.swift
echo -e "${YELLOW}[3/6] 检查 FontLoader.swift...${NC}"
if [ -f "/Users/zhujichao_1/Desktop/zjc19891106/MarkdownDisplayView/MarkdownDisplayView/Sources/MarkdownDisplayView/FontLoader.swift" ]; then
    echo -e "${GREEN}✅ FontLoader.swift 存在${NC}"
else
    echo -e "${RED}❌ FontLoader.swift 不存在${NC}"
    exit 1
fi

# 检查 CocoaPods 配置
echo -e "${YELLOW}[4/6] 检查 CocoaPods 配置...${NC}"
if grep -q "resource_bundles" "/Users/zhujichao_1/Desktop/zjc19891106/MarkdownDisplayView/MarkdownDisplayKit.podspec"; then
    echo -e "${GREEN}✅ CocoaPods resource_bundles 已配置${NC}"
else
    echo -e "${RED}❌ CocoaPods resource_bundles 未配置${NC}"
    exit 1
fi

# 检查 SPM 配置
echo -e "${YELLOW}[5/6] 检查 SPM 配置...${NC}"
if grep -q "resources:" "/Users/zhujichao_1/Desktop/zjc19891106/MarkdownDisplayView/Package.swift"; then
    echo -e "${GREEN}✅ SPM resources 已配置${NC}"
else
    echo -e "${RED}❌ SPM resources 未配置${NC}"
    exit 1
fi

# 检查示例文件
echo -e "${YELLOW}[6/6] 检查示例文件...${NC}"
if grep -q "公式测试" "/Users/zhujichao_1/Desktop/zjc19891106/MarkdownDisplayView/CocoapodsMDExample/CocoapodsMDExample/MarkdownExampleViewController.swift"; then
    echo -e "${GREEN}✅ 示例文件已更新（CocoapodsMDExample）${NC}"
else
    echo -e "${RED}❌ 示例文件未更新${NC}"
    exit 1
fi

if grep -q "公式测试" "/Users/zhujichao_1/Desktop/zjc19891106/MarkdownDisplayView/Example/ExampleForMarkdown/ExampleForMarkdown/MarkdownExampleViewController.swift"; then
    echo -e "${GREEN}✅ 示例文件已更新（ExampleForMarkdown）${NC}"
else
    echo -e "${RED}❌ 示例文件未更新${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ 所有检查通过！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}文件清单：${NC}"
echo "  - 20 个 KaTeX 字体文件"
echo "  - LaTeXAttachment.swift"
echo "  - FontLoader.swift"
echo "  - MarkdownParser.swift (已修改)"
echo "  - MarkdownDisplayView.swift (已修改)"
echo "  - MarkdownRenderElement.swift (已修改)"
echo "  - MarkdownDisplayKit.podspec (已配置)"
echo "  - Package.swift (已配置)"
echo "  - 2 个示例项目 (已更新)"
echo ""
echo -e "${YELLOW}下一步：${NC}"
echo "  1. 运行示例应用测试公式渲染"
echo "  2. 查看 LATEX_INTEGRATION.md 了解详情"
echo "  3. 提交更改到 git"
