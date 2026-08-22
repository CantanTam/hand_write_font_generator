#!/bin/bash

set -euo pipefail

# ============================================================================
# 常量 —— 修改这里即可改变最终 SVG 的颜色和透明度
# ============================================================================
A6_W_MM=105
A6_H_MM=148
TARGET_DPI=300

A6_W_PX=$(awk "BEGIN {printf \"%d\", $A6_W_MM / 25.4 * $TARGET_DPI}")
A6_H_PX=$(awk "BEGIN {printf \"%d\", $A6_H_MM / 25.4 * $TARGET_DPI}")

REF_COLOR="#cccccc"      # ← 最终 path 的 fill 颜色
REF_OPACITY="1"        # ← 最终 path 的 opacity 透明度

TEMP_IMG="temp.png"
TEMP_TOP="temp_top.png"
TEMP_BOT="temp_bot.png"

# ============================================================================
# 依赖检查
# ============================================================================
for cmd in magick zbarimg potrace awk dialog inkscape python3; do
    if ! command -v "$cmd" &>/dev/null; then
        clear
        echo "❌ 缺少依赖: $cmd"
        echo "   安装: sudo pacman -S imagemagick zbar potrace awk dialog inkscape"
        exit 1
    fi
done

# ============================================================================
# 配置界面：一步输入 4 个参数
# ============================================================================
config_dialog() {
    local cut_off="0"
    local thresh="50"
    local smooth="100"
    local despeck="2"
    local vals side_len

    while true; do
        vals=$(dialog --clear --stdout \
            --title " 处理参数 " \
            --form "" 12 40 4 \
            "裁切偏移" 1 1 "$cut_off" 1 12 8 0 \
            "灰度阈值" 2 1 "$thresh" 2 12 8 0 \
            "平滑度"   3 1 "$smooth" 3 12 8 0 \
            "去噪强度" 4 1 "$despeck" 4 12 8 0) || {
            clear
            echo "❌ 已取消"
            return 1
        }

        clear

        mapfile -t v <<< "$vals"
        cut_off="${v[0]}"
        thresh="${v[1]}"
        smooth="${v[2]}"
        despeck="${v[3]}"

        if ! [[ "$cut_off" =~ ^[0-9]+$ ]]; then
            dialog --title " 错误 " --msgbox "裁切偏移必须是非负整数" 7 30
            continue
        fi
        side_len=$((A6_W_PX - cut_off * 2))
        if [ "$side_len" -le 0 ]; then
            dialog --title " 错误 " --msgbox "裁切偏移过大" 7 30
            continue
        fi

        if ! [[ "$thresh" =~ ^-?[0-9]+$ ]]; then
            dialog --title " 错误 " --msgbox "灰度阈值必须是整数" 7 30
            continue
        fi
        if [ "$thresh" -lt 0 ]; then
            thresh=0
        elif [ "$thresh" -gt 100 ]; then
            thresh=100
        fi

        if ! [[ "$smooth" =~ ^-?[0-9]+$ ]]; then
            dialog --title " 错误 " --msgbox "平滑度必须是整数" 7 30
            continue
        fi
        if [ "$smooth" -lt 0 ]; then
            smooth=0
        elif [ "$smooth" -gt 150 ]; then
            smooth=150
        fi

        if ! [[ "$despeck" =~ ^-?[0-9]+$ ]]; then
            dialog --title " 错误 " --msgbox "去噪强度必须是整数" 7 30
            continue
        fi
        if [ "$despeck" -lt 0 ]; then
            despeck=0
        elif [ "$despeck" -gt 20 ]; then
            despeck=20
        fi

        CUT_OFFSET=$cut_off
        THRESHOLD=$(awk "BEGIN {printf \"%.2f\", $thresh / 100}")
        SMOOTH=$(awk "BEGIN {printf \"%.2f\", $smooth / 100}")
        DESPECKLE=$despeck
        echo "✅ 裁切偏移: ${CUT_OFFSET} px | 灰度阈值: ${THRESHOLD} | 平滑度: ${SMOOTH} | 去噪: ${DESPECKLE}"
        return 0
    done
}

# ============================================================================
if ! config_dialog; then
    exit 1
fi

# ============================================================================
mkdir -p source output

# ============================================================================
shopt -s nullglob
images=()

for ext in png jpg jpeg bmp gif tiff webp PNG JPG JPEG BMP GIF TIFF WEBP; do
    for f in *."$ext"; do
        [ -f "$f" ] && [[ "$f" != "$TEMP_IMG" ]] && [[ "$f" != "$TEMP_TOP" ]] && [[ "$f" != "$TEMP_BOT" ]] && images+=("$f")
    done
done

shopt -u nullglob

total=${#images[@]}
[ "$total" -eq 0 ] && { clear; echo "未找到图片文件"; exit 0; }

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  扫描图批量处理"
echo "  总计: $total 张"
echo "  A6: ${A6_W_PX}x${A6_H_PX} px @ ${TARGET_DPI} DPI"
echo "  裁切偏移: ${CUT_OFFSET} px"
echo "  裁切边长: $((A6_W_PX - CUT_OFFSET * 2)) px"
echo "  灰度阈值: ${THRESHOLD} | 平滑度: ${SMOOTH} | 去噪: ${DESPECKLE}"
echo "  颜色: ${REF_COLOR} | 透明度: ${REF_OPACITY}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================================
process_all() {
    local img h half qr_value bot_qr side_len svg_mm

    for img in "${images[@]}"; do
        printf "处理: %-30s  " "$img"

        qr_value=$(zbarimg -q --raw "$img" 2>/dev/null | head -1 || true)

        if [ -z "$qr_value" ]; then
            mv "$img" "source/$img"
            echo "→ 无二维码"
            continue
        fi

        cp "$img" "$TEMP_IMG"
        mv "$img" "source/$img"

        h=$(identify -format "%h" "$TEMP_IMG")
        half=$((h / 2))

        magick "$TEMP_IMG" -crop "100%x${half}+0+0" +repage "$TEMP_TOP" 2>/dev/null
        magick "$TEMP_IMG" -crop "100%x${half}+0+${half}" +repage "$TEMP_BOT" 2>/dev/null

        bot_qr=$(zbarimg -q --raw "$TEMP_BOT" 2>/dev/null | head -1 || true)

        if [ -z "$bot_qr" ]; then
            magick "$TEMP_IMG" -flip -flop "$TEMP_IMG"
            echo -n "翻转 "
        else
            echo -n "正向 "
        fi

        magick "$TEMP_IMG" \
            -resize "${A6_W_PX}x${A6_H_PX}" \
            -extent "${A6_W_PX}x${A6_H_PX}" \
            -gravity NorthWest \
            -set units PixelsPerInch \
            -density "$TARGET_DPI" \
            "$TEMP_IMG" 2>/dev/null

        side_len=$((A6_W_PX - CUT_OFFSET * 2))

        magick "$TEMP_IMG" \
            -crop "${side_len}x${side_len}+${CUT_OFFSET}+${CUT_OFFSET}" \
            +repage \
            "${TEMP_IMG%.png}_square.png" 2>/dev/null

        svg_mm=$(awk "BEGIN {printf \"%.2f\", $side_len / $A6_W_PX * $A6_W_MM}")

        magick "${TEMP_IMG%.png}_square.png" pgm:- 2>/dev/null | \
            potrace -k "$THRESHOLD" -a "$SMOOTH" -t "$DESPECKLE" -s \
            -W "${svg_mm}mm" -H "${svg_mm}mm" \
            -o "${qr_value}.svg" 2>/dev/null

        if [ -f "${qr_value}.svg" ]; then
            inkscape "${qr_value}.svg" \
                --batch-process \
                --actions="select-all;selection-ungroup;select-all;path-union" \
                --export-filename="${qr_value}.svg" 2>/dev/null || true

            # 展平 <g>，删除旧 fill/fill-opacity，统一改用 style
            python3 - "$REF_COLOR" "$REF_OPACITY" "${qr_value}.svg" << 'PYEOF'
import sys, xml.etree.ElementTree as ET
color, opacity, svg_file = sys.argv[1], sys.argv[2], sys.argv[3]
svg = ET.parse(svg_file)
root = svg.getroot()
ns = 'http://www.w3.org/2000/svg'
ET.register_namespace('', ns)
ET.register_namespace('inkscape', 'http://www.inkscape.org/namespaces/inkscape')
ET.register_namespace('sodipodi', 'http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd')

# 1) 若 path 被 <g> 包裹，展平并保留 transform
for g in list(root):
    if g.tag != f'{{{ns}}}g':
        continue
    path = g.find(f'{{{ns}}}path')
    if path is None:
        continue
    if 'transform' in g.attrib and 'transform' not in path.attrib:
        path.set('transform', g.attrib['transform'])
    g.remove(path)
    idx = list(root).index(g)
    root.insert(idx + 1, path)
    root.remove(g)

# 2) 对所有 <path>：删除旧的 fill / fill-opacity，改用 style
for path in root.iter(f'{{{ns}}}path'):
    path.set('id', 'reference')
    path.attrib.pop('fill', None)
    path.attrib.pop('fill-opacity', None)
    path.set('style', f'fill:{color};opacity:{opacity}')

svg.write(svg_file, encoding='UTF-8', xml_declaration=True)
PYEOF
        fi

        rm -f "$TEMP_IMG" "$TEMP_TOP" "$TEMP_BOT" \
            "${TEMP_IMG%.png}_square.png"

        if [ -f "${qr_value}.svg" ]; then
            mv "${qr_value}.svg" "output/"
            echo "→ ${qr_value}.svg"
        else
            echo "→ 失败"
        fi
    done

    rm -f "$TEMP_IMG" "$TEMP_TOP" "$TEMP_BOT" \
        "${TEMP_IMG%.png}_square.png" 2>/dev/null
}

process_all

echo ""
echo "完成。输出: output/ | 原图: source/"
