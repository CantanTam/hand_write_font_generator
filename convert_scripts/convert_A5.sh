#!/bin/bash

set -euo pipefail

# ============================================================================
# 常量
# ============================================================================
A6_W_MM=148
A6_H_MM=210
TARGET_DPI=300

A6_W_PX=$(awk "BEGIN {printf \"%d\", $A6_W_MM / 25.4 * $TARGET_DPI}")
A6_H_PX=$(awk "BEGIN {printf \"%d\", $A6_H_MM / 25.4 * $TARGET_DPI}")

TEMP_IMG="temp.png"
TEMP_TOP="temp_top.png"
TEMP_BOT="temp_bot.png"

# ============================================================================
# 依赖检查
# ============================================================================
for cmd in magick zbarimg potrace awk dialog; do
    if ! command -v "$cmd" &>/dev/null; then
        clear
        echo "❌ 缺少依赖: $cmd"
        echo "   安装: sudo pacman -S imagemagick zbar potrace awk dialog"
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

        # 解析（form 输出每行一个值）
        mapfile -t v <<< "$vals"
        cut_off="${v[0]}"
        thresh="${v[1]}"
        smooth="${v[2]}"
        despeck="${v[3]}"

        # 验证裁切偏移
        if ! [[ "$cut_off" =~ ^[0-9]+$ ]]; then
            dialog --title " 错误 " --msgbox "裁切偏移必须是非负整数" 7 30
            continue
        fi
        side_len=$((A6_W_PX - cut_off * 2))
        if [ "$side_len" -le 0 ]; then
            dialog --title " 错误 " --msgbox "裁切偏移过大" 7 30
            continue
        fi

        # 验证灰度阈值 (0-100 整数)
        if ! [[ "$thresh" =~ ^-?[0-9]+$ ]]; then
            dialog --title " 错误 " --msgbox "灰度阈值必须是整数" 7 30
            continue
        fi
        if [ "$thresh" -lt 0 ]; then
            thresh=0
        elif [ "$thresh" -gt 100 ]; then
            thresh=100
        fi

        # 验证平滑度 (0-150 整数)
        if ! [[ "$smooth" =~ ^-?[0-9]+$ ]]; then
            dialog --title " 错误 " --msgbox "平滑度必须是整数" 7 30
            continue
        fi
        if [ "$smooth" -lt 0 ]; then
            smooth=0
        elif [ "$smooth" -gt 150 ]; then
            smooth=150
        fi

        # 验证去噪强度 (0-20 整数)
        if ! [[ "$despeck" =~ ^-?[0-9]+$ ]]; then
            dialog --title " 错误 " --msgbox "去噪强度必须是整数" 7 30
            continue
        fi
        if [ "$despeck" -lt 0 ]; then
            despeck=0
        elif [ "$despeck" -gt 20 ]; then
            despeck=20
        fi

        # 导出
        CUT_OFFSET=$cut_off
        THRESHOLD=$(awk "BEGIN {printf \"%.2f\", $thresh / 100}")
        SMOOTH=$(awk "BEGIN {printf \"%.2f\", $smooth / 100}")
        DESPECKLE=$despeck
        echo "✅ 裁切偏移: ${CUT_OFFSET} px | 灰度阈值: ${THRESHOLD} | 平滑度: ${SMOOTH} | 去噪: ${DESPECKLE}"
        return 0
    done
}

# ============================================================================
# 每次执行前：输入参数
# ============================================================================
if ! config_dialog; then
    exit 1
fi

# ============================================================================
# 创建文件夹
# ============================================================================
mkdir -p source output

# ============================================================================
# 收集图片
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
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================================
# 主处理
# ============================================================================
process_all() {
    local img h half qr_value bot_qr side_len svg_mm

    for img in "${images[@]}"; do
        printf "处理: %-30s  " "$img"

        # 检测二维码
        qr_value=$(zbarimg -q --raw "$img" 2>/dev/null | head -1 || true)

        if [ -z "$qr_value" ]; then
            mv "$img" "source/$img"
            echo "→ 无二维码"
            continue
        fi

        # 复制、移原图
        cp "$img" "$TEMP_IMG"
        mv "$img" "source/$img"

        # 切半检测方向
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

        # 标准化到 A6 @ 300 DPI
        magick "$TEMP_IMG" \
            -resize "${A6_W_PX}x${A6_H_PX}" \
            -extent "${A6_W_PX}x${A6_H_PX}" \
            -gravity NorthWest \
            -set units PixelsPerInch \
            -density "$TARGET_DPI" \
            "$TEMP_IMG" 2>/dev/null

        # 带偏移的正方形裁切
        side_len=$((A6_W_PX - CUT_OFFSET * 2))

        magick "$TEMP_IMG" \
            -crop "${side_len}x${side_len}+${CUT_OFFSET}+${CUT_OFFSET}" \
            +repage \
            "${TEMP_IMG%.png}_square.png" 2>/dev/null

        # --- potrace 矢量化（-k 处理灰度阈值）---
        # -k : 灰度阈值（用户可调，0~1，越小越少的深色被保留）
        # -a : 角点阈值（用户可调）
        #      越小 → 越锐利，节点越多
        #      越大 → 越平滑，节点越少
        # -t : 去噪阈值（用户可调）
        #      面积小于此像素数的闭合形状会被抹掉
        svg_mm=$(awk "BEGIN {printf \"%.2f\", $side_len / $A6_W_PX * $A6_W_MM}")

        magick "${TEMP_IMG%.png}_square.png" pgm:- 2>/dev/null | \
            potrace -k "$THRESHOLD" -a "$SMOOTH" -t "$DESPECKLE" -s \
            -W "${svg_mm}mm" -H "${svg_mm}mm" \
            -o "${qr_value}.svg" 2>/dev/null

        # 清理、移动
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
