#!/usr/bin/env python
# -*- coding: utf-8 -*-
# FontForge: 文件 → 执行脚本 → 选择本文件

import fontforge
import os
import re

# ==================== 修改这里 ====================
SVG_DIR = "/home/output/"   # 改成你的 SVG 文件夹绝对路径
# =================================================

# 获取当前打开的字体；如果没打开任何文件，则新建一个
try:
    font = fontforge.activeFont()
except:
    font = fontforge.font()

count = 0

for filename in sorted(os.listdir(SVG_DIR)):
    if not filename.lower().endswith(".svg"):
        continue

    # 匹配 5E01.svg → 提取 5E01
    m = re.match(r'^([0-9A-Fa-f]+)\.svg$', filename)
    if not m:
        print("跳过（文件名不符合）: " + filename)
        continue

    codepoint = int(m.group(1), 16)
    filepath = os.path.join(SVG_DIR, filename)

    try:
        # 创建/定位到对应 Unicode 码点的字形
        glyph = font.createChar(codepoint)

        # 导入 SVG 轮廓
        glyph.importOutlines(filepath)

        # 修正轮廓方向（防止"口"字变实心）
        glyph.correctDirection()

        # 去除重叠路径
        glyph.removeOverlap()

        # 可选：统一字宽（等宽字体用）
        # glyph.width = 1000

        count += 1
        print("✅ U+%s  ← %s" % (m.group(1).upper(), filename))

    except Exception as e:
        print("❌ %s: %s" % (filename, str(e)))

print("\n完成，共导入 %d 个字形" % count)

# 如需直接生成字体文件，取消下面注释：
# font.generate(os.path.join(SVG_DIR, "output.ttf"))
