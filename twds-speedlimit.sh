#!/bin/bash
URL="https://mirror.twds.com.tw/centos-stream/10-stream/BaseOS/x86_64/iso/CentOS-Stream-10-20251027.0-x86_64-dvd1.iso"

if ! command -v trickle &> /dev/null; then
    echo "未找到 trickle，嘗試自動安裝..."
    
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y trickle >/dev/null 2>&1
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y trickle >/dev/null 2>&1
    elif command -v yum &> /dev/null; then
        sudo yum install -y trickle >/dev/null 2>&1
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm trickle >/dev/null 2>&1
    else
        echo "無法自動安裝 trickle，無法識別的系統類型或無法找到合適的包管理器。"
        echo "請手動安裝 trickle 後再執行此腳本。"
        exit 1
    fi
    
    if ! command -v trickle &> /dev/null; then
        echo "trickle 安裝失敗，請手動安裝後再執行此腳本。"
        exit 1
    else
        echo "已安裝 trickle。"
    fi
else
    echo "已安裝 trickle。"
fi

if ! pgrep trickled > /dev/null; then
    echo "啟動 trickled 守護進程..."
    if command -v systemctl &> /dev/null && systemctl list-unit-files | grep -q trickled; then
        sudo systemctl start trickled >/dev/null 2>&1
    else
        sudo trickled -d >/dev/null 2>&1 &
    fi
    sleep 1
fi

read -p "請輸入想要使用的網路速度 (單位: Mbps): " NETWORK_SPEED

if ! [[ "$NETWORK_SPEED" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "錯誤: 請輸入有效的數字"
    exit 1
fi

DOWNLOAD_SPEED=$(awk "BEGIN {printf \"%.0f\", $NETWORK_SPEED * 125}")

clear

echo "----------------------------------------"
echo "專門刷TWDS Mirror的東西 (限速版)"
echo "----------------------------------------"
echo "開始刷流量 - 如需取消請按 Ctrl+C 停止"
echo "目標URL: $URL"
echo "檔案存放位置: /dev/null"
echo "網路限速: $NETWORK_SPEED Mbps (約 $DOWNLOAD_SPEED KB/s)"
echo "----------------------------------------"

trap 'echo ""; echo "下載已停止"; exit 0' INT TERM
PARALLEL_DOWNLOADS=10

for i in $(seq 1 $PARALLEL_DOWNLOADS); do
    (
        while true; do
            trickle -s -d $((DOWNLOAD_SPEED / PARALLEL_DOWNLOADS)) wget -q -O /dev/null "$URL" 2>/dev/null
            sleep 0.5
        done
    ) &
    
    wget_pids[$i]=$!
done

download_loop_pid="${wget_pids[*]}"
trap 'kill $download_loop_pid 2>/dev/null; echo ""; echo "下載已停止"; exit 0' EXIT

IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
if [ -z "$IFACE" ]; then
    IFACE=$(ip link | grep "UP" | grep -v "lo:" | head -1 | cut -d: -f2 | tr -d ' ')
fi

START_TIME=$(date +%s)
LAST_UPDATE_TIME=$START_TIME
RX_START=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
TX_START=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
RX_LAST=$RX_START
TX_LAST=$TX_START
TOTAL_RX_DIFF=0
TOTAL_TX_DIFF=0

format_size() {
    local size=$1
    if [ $size -ge 1073741824 ]; then 
        local gb=$(awk "BEGIN {printf \"%.2f\", $size/1073741824}")
        echo "$gb GB"
    elif [ $size -ge 1048576 ]; then
        local mb=$(awk "BEGIN {printf \"%.2f\", $size/1048576}")
        echo "$mb MB"
    elif [ $size -ge 1024 ]; then
        local kb=$(awk "BEGIN {printf \"%.2f\", $size/1024}")
        echo "$kb KB"
    else
        echo "$size B"
    fi
}

simple_format_size() {
    local size=$1
    if [ $size -ge 1073741824 ]; then 
        local gb=$(awk "BEGIN {printf \"%.2f\", $size/1073741824}")
        echo "$gb GB"
    elif [ $size -ge 1048576 ]; then
        local mb=$(awk "BEGIN {printf \"%.2f\", $size/1048576}")
        echo "$mb MB"
    elif [ $size -ge 1024 ]; then
        local kb=$(awk "BEGIN {printf \"%.2f\", $size/1024}")
        echo "$kb KB"
    else
        echo "$size B"
    fi
}

while true; do
    RX_NOW=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
    TX_NOW=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    
    CURRENT_TIME=$(date +%s)
    
    TOTAL_RX_DIFF=$((RX_NOW - RX_START))
    TOTAL_TX_DIFF=$((TX_NOW - TX_START))
    
    RX_INTERVAL_DIFF=$((RX_NOW - RX_LAST))
    TX_INTERVAL_DIFF=$((TX_NOW - TX_LAST))
    
    TIME_DIFF=$((CURRENT_TIME - LAST_UPDATE_TIME))
    
    if [ $TIME_DIFF -gt 0 ]; then
        RX_SPEED=$((RX_INTERVAL_DIFF / TIME_DIFF))
        TX_SPEED=$((TX_INTERVAL_DIFF / TIME_DIFF))
    else
        RX_SPEED=0
        TX_SPEED=0
    fi
    
    RX_LAST=$RX_NOW
    TX_LAST=$TX_NOW
    LAST_UPDATE_TIME=$CURRENT_TIME
    
    ELAPSED=$((CURRENT_TIME - START_TIME))
    DAYS=$((ELAPSED / 86400))
    HOURS=$(( (ELAPSED % 86400) / 3600 ))
    MINUTES=$(( (ELAPSED % 3600) / 60 ))
    SECONDS=$((ELAPSED % 60))
    
    if [ $DAYS -gt 0 ]; then
        TIME_STR="${DAYS}天 ${HOURS}時 ${MINUTES}分 ${SECONDS}秒"
    elif [ $HOURS -gt 0 ]; then
        TIME_STR="${HOURS}時 ${MINUTES}分 ${SECONDS}秒"
    elif [ $MINUTES -gt 0 ]; then
        TIME_STR="${MINUTES}分 ${SECONDS}秒"
    else
        TIME_STR="${SECONDS}秒"
    fi
    
    echo -ne "\r\033[K"
    
    echo -n "下載: $(simple_format_size $TOTAL_RX_DIFF) ($(simple_format_size $RX_SPEED)/s) | 上傳: $(simple_format_size $TOTAL_TX_DIFF) ($(simple_format_size $TX_SPEED)/s) | 運行時間: ${TIME_STR} | 限速: $NETWORK_SPEED Mbps"
    
    sleep 1
done
