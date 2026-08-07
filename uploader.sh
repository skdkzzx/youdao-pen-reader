#!/bin/sh
# 小说上传服务 - 命令行管理工具
# 用法: sh uploader.sh {start|stop|status|restart}
PORT=8088
LOG_FILE="/tmp/novel-uploader.log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

check_port() {
    grep -qi ":$(printf '%04X' $PORT)" /proc/net/tcp 2>/dev/null && return 0
    return 1
}

do_start() {
    echo "启动上传服务..."
    sh "$SCRIPT_DIR/start-uploader.sh"
    # 等待最多 5 秒检测端口
    local i=0
    while [ $i -lt 25 ]; do
        sleep 0.2
        if check_port; then
            do_status
            return 0
        fi
        i=$((i + 1))
    done
    echo "启动超时"
    do_status
}

do_stop() {
    echo "停止上传服务..."
    fuser -k ${PORT}/tcp 2>/dev/null || true
    pkill -f 'novel-httpd' 2>/dev/null || true
    pkill -f 'upload_server' 2>/dev/null || true
    pkill -f 'node.*server.js' 2>/dev/null || true
    pkill -f 'python3.*server.py' 2>/dev/null || true
    sleep 0.5
    echo "已停止"
}

do_status() {
    if check_port; then
        echo "上传服务运行中 (端口 $PORT)"
        grep -o 'http://[0-9.]*:'"$PORT" "$LOG_FILE" 2>/dev/null | tail -1
    else
        echo "上传服务未运行"
        tail -5 "$LOG_FILE" 2>/dev/null
    fi
}

case "${1:-start}" in
    start)   do_start ;;
    stop)    do_stop ;;
    restart) do_stop; sleep 1; do_start ;;
    status)  do_status ;;
    *)       echo "用法: $0 {start|stop|restart|status}" ;;
esac
