#!/bin/bash

set -euo pipefail

FONT_FILE="font_utf8.txt"
OUTPUT="merged.pdf"

if [ ! -f "$FONT_FILE" ]; then
    echo "❌ 错误: 找不到 $FONT_FILE"
    exit 1
fi

files=()
count=0

# 按 font_utf8.txt 的行顺序读取
while IFS='>' read -r char unicode; do
    # 清理 Unicode 值中的空白（防止有回车、空格等）
    unicode=$(echo "$unicode" | tr -d ' \t\r\n')

    # 跳过空行
    [ -z "$unicode" ] && continue

    pdf="${unicode}.pdf"

    if [ -f "$pdf" ]; then
        files+=("$pdf")
        count=$((count + 1))
    else
        echo "⚠️  跳过: 未找到 ${pdf}（对应 ${char}）"
    fi
done < "$FONT_FILE"

if [ "$count" -eq 0 ]; then
    echo "❌ 错误: 没有找到任何可合并的 PDF 文件"
    exit 1
fi

echo "📑 正在按 ${FONT_FILE} 的顺序合并 ${count} 个 PDF 文件..."

gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile="$OUTPUT" "${files[@]}"

echo "✅ 合并完成: ${OUTPUT}"
