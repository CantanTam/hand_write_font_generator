#!/bin/bash

set -euo pipefail

INPUT_SVG="input.svg"
FONT_FILE="font.txt"
QR_SIZE=120

# ========== 定位参数（单位：px）==========
LEFTSET=120   # 距离页面右边缘向左偏移多少 px
TOPSET=60    # 距离页面下边缘向上偏移多少 px

# ========== 是否删除中间 SVG 文件 ==========
# Y = 生成 PDF 后删除 unicode.svg，只保留 PDF
# N = 保留 unicode.svg（默认）
DELETESVG="Y"

# ========== 0. 自动修复 font.txt 编码 ==========
python3 -c "
with open('$FONT_FILE', 'rb') as f:
    raw = f.read()
if raw.startswith(b'\xff\xfe'):
    text = raw[2:].decode('utf-16-le')
elif raw.startswith(b'\xfe\xff'):
    text = raw[2:].decode('utf-16-be')
elif raw.startswith(b'\xef\xbb\xbf'):
    text = raw[3:].decode('utf-8')
else:
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError:
        text = raw.decode('gbk')
text = text.replace('\x00', '').replace('\r\n', '\n').replace('\r', '\n')
text = text.strip('\n') + '\n' if text.strip() else ''
with open('$FONT_FILE', 'w', encoding='utf-8') as f:
    f.write(text)
"

# ========== 环境检查 ==========
for cmd in qrencode inkscape python3; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ 错误: 未安装 $cmd"
        exit 1
    fi
done

if [ ! -f "$INPUT_SVG" ] || [ ! -f "$FONT_FILE" ]; then
    echo "❌ 错误: 找不到 $INPUT_SVG 或 $FONT_FILE"
    exit 1
fi

LINE_NUM=0

# ========== 主循环 ==========
while true; do
    RESULT=$(python3 -c "
import sys
try:
    with open('$FONT_FILE', 'r', encoding='utf-8') as f:
        lines = f.readlines()
    if not lines:
        print('ERROR:EMPTY')
        sys.exit(0)
    first = lines[0].strip()
    if '>' not in first:
        print('ERROR:FORMAT')
        sys.exit(0)
    char, unicode_val = first.split('>', 1)
    print(f'{char.strip()}|{unicode_val.strip()}')
except Exception as e:
    print(f'ERROR:{e}')
" 2>/dev/null)

    if [[ "$RESULT" == ERROR:EMPTY* ]]; then
        break
    fi
    if [[ "$RESULT" == ERROR:* ]]; then
        echo "❌ 错误: $RESULT"
        exit 1
    fi

    CHAR=$(echo "$RESULT" | cut -d'|' -f1)
    UNICODE=$(echo "$RESULT" | cut -d'|' -f2)

    LINE_NUM=$((LINE_NUM + 1))
    echo "[$LINE_NUM] 正在处理: 汉字='$CHAR'  →  Unicode='$UNICODE'"

    # ---------- 替换 ★ 为汉字 ----------
    python3 -c "
with open('$INPUT_SVG', 'r', encoding='utf-8') as f:
    content = f.read()
content = content.replace('★', '$CHAR')
with open('temp_${UNICODE}.svg', 'w', encoding='utf-8') as f:
    f.write(content)
"

    # ---------- 生成矢量二维码 ----------
    qrencode -t SVG -s 1 -o "qr_${UNICODE}.svg" "$UNICODE"

    # ---------- 合并（两步法） ----------
    python3 << PYEOF
import xml.etree.ElementTree as ET
import re

def to_px(val):
    if not val:
        return 0.0
    m = re.match(r'([\d.]+)\s*([a-z%]*)', str(val).strip())
    if not m:
        return 0.0
    num, unit = float(m.group(1)), m.group(2)
    conv = {'mm': 3.779, 'cm': 37.79, 'in': 96, 'pt': 1.333, 'pc': 16}
    return num * conv.get(unit, 1)

def remove_white_bg(elem):
    for child in list(elem):
        tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
        if tag == 'rect' and child.get('fill', '').lower() in ('white', '#ffffff', '#fff'):
            elem.remove(child)
            continue
        remove_white_bg(child)

ET.register_namespace('', 'http://www.w3.org/2000/svg')
ns = '{http://www.w3.org/2000/svg}'

base = ET.parse("temp_${UNICODE}.svg").getroot()
qr = ET.parse("qr_${UNICODE}.svg").getroot()

# 步骤 1：生成 120×120 px 无白底二维码图块
remove_white_bg(qr)

vb = qr.get('viewBox', '0 0 29 29').replace(',', ' ').split()
orig_w = float(vb[2])

qr120 = ET.Element(f'{ns}svg')
qr120.set('width', '120px')
qr120.set('height', '120px')
qr120.set('viewBox', '0 0 120 120')
qr120.set('xmlns', 'http://www.w3.org/2000/svg')

g_scale = ET.SubElement(qr120, f'{ns}g')
g_scale.set('transform', f'scale({120.0 / orig_w:.6f})')

for child in list(qr):
    g_scale.append(child)

# 步骤 2：计算 input.svg 坐标系并粘贴
base_w = base.get('width', '0')
base_h = base.get('height', '0')
base_vb = base.get('viewBox', '')

base_w_px = to_px(base_w)
base_h_px = to_px(base_h)

if base_vb:
    parts = base_vb.replace(',', ' ').split()
    if len(parts) == 4:
        vb_x, vb_y, vb_w, vb_h = map(float, parts)
        upp_x = vb_w / base_w_px if base_w_px > 0 else 1.0
        upp_y = vb_h / base_h_px if base_h_px > 0 else 1.0
        upp = (upp_x + upp_y) / 2
        right = vb_x + vb_w
        bottom = vb_y + vb_h
    else:
        upp = 1.0
        right = base_w_px
        bottom = base_h_px
else:
    upp = 1.0
    right = base_w_px
    bottom = base_h_px

qr_size_u = ${QR_SIZE}.0 * upp
leftset_u = ${LEFTSET}.0 * upp
topset_u  = ${TOPSET}.0 * upp

x = right - leftset_u - qr_size_u
y = bottom - topset_u - qr_size_u

print(f"  [调试] 1px = {upp:.6f} 用户单位, 定位: ({x:.4f}, {y:.4f})")

g = ET.SubElement(base, f'{ns}g')
g.set('id', 'qrcode')
g.set('transform', f'translate({x:.4f}, {y:.4f}) scale({upp:.6f})')

for child in list(qr120):
    g.append(child)

ET.ElementTree(base).write("${UNICODE}.svg", encoding='utf-8', xml_declaration=True)
PYEOF

    # ---------- 导出 PDF ----------
    inkscape "${UNICODE}.svg" --export-filename="${UNICODE}.pdf" 2>/dev/null

    # ---------- 根据 DELETESVG 决定是否保留 unicode.svg ----------
    if [ "$DELETESVG" = "Y" ]; then
        rm -f "${UNICODE}.svg"
        echo "       ✅ 已生成: ${UNICODE}.pdf（已删除 ${UNICODE}.svg）"
    else
        echo "       ✅ 已生成: ${UNICODE}.svg  +  ${UNICODE}.pdf"
    fi

    # ---------- 删除第一行 ----------
    python3 -c "
with open('$FONT_FILE', 'r', encoding='utf-8') as f:
    lines = f.readlines()
with open('$FONT_FILE', 'w', encoding='utf-8') as f:
    f.writelines(lines[1:])
"

    # ---------- 清理临时文件 ----------
    rm -f "temp_${UNICODE}.svg" "qr_${UNICODE}.svg"
    echo ""
done

echo "========================================"
echo "🎉 全部完成！共处理 $LINE_NUM 个字符。"
