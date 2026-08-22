#!/bin/bash

set -euo pipefail

# ============================================================================
# 1. 检测/创建 finish 文件夹
# ============================================================================
mkdir -p finish

# ============================================================================
# 2. 按修改时间排序（从早到晚）收集当前目录的 .svg 文件
# ============================================================================
mapfile -t svg_files < <(find . -maxdepth 1 -name "*.svg" -type f -printf '%T@ %p\n' | sort -n | cut -d' ' -f2-)

total=${#svg_files[@]}
if [ "$total" -eq 0 ]; then
    echo "当前目录没有 .svg 文件"
    exit 0
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  批量处理 SVG"
echo "  总计: $total 张"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================================
# 3~6. 逐个复制并处理
# ============================================================================
for svg_path in "${svg_files[@]}"; do
    filename=$(basename "$svg_path")
    echo "处理: $filename"

    # 复制到 finish
    cp "$svg_path" "finish/$filename"

    # 在 finish 内部处理
    python3 - "finish/$filename" << 'PYEOF'
import sys, xml.etree.ElementTree as ET

svg_file = sys.argv[1]
svg = ET.parse(svg_file)
root = svg.getroot()
ns = 'http://www.w3.org/2000/svg'

# 保留原始命名空间，防止前缀被改写
ET.register_namespace('', ns)
ET.register_namespace('inkscape', 'http://www.inkscape.org/namespaces/inkscape')
ET.register_namespace('sodipodi', 'http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd')

ref_elem = None
font_elem = None

# 查找 id="reference" 和 id="font" 的元素
for elem in root.iter():
    eid = elem.get('id')
    if eid == 'reference':
        ref_elem = elem
    elif eid == 'font':
        font_elem = elem

target_style = 'display:inline;opacity:1;fill:#000000'

def clean_conflicting_attrs(elem):
    """移除可能与 style 冲突的独立属性"""
    elem.attrib.pop('fill', None)
    elem.attrib.pop('fill-opacity', None)
    elem.attrib.pop('opacity', None)

if ref_elem is not None and font_elem is None:
    # 只有 reference：修改样式并重命名为 font
    clean_conflicting_attrs(ref_elem)
    ref_elem.set('style', target_style)
    ref_elem.set('id', 'font')
    print("  → 仅含 reference，已重命名为 font 并修改样式")

elif ref_elem is not None and font_elem is not None:
    # 同时含有 font 和 reference：删除 reference，修改 font
    removed = False
    for parent in root.iter():
        for child in list(parent):
            if child.get('id') == 'reference':
                parent.remove(child)
                removed = True
                break
        if removed:
            break

    clean_conflicting_attrs(font_elem)
    font_elem.set('style', target_style)
    print("  → 含 reference + font，已删除 reference 并修改 font 样式")

else:
    print("  → 未找到 reference，跳过")

svg.write(svg_file, encoding='UTF-8', xml_declaration=True)
PYEOF
done

echo ""
echo "完成。输出: finish/"
