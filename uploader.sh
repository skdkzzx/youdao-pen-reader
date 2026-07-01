#!/bin/sh

# 纯 Shell HTTP 上传服务器 — 无需 python3/node
# 使用 busybox httpd + CGI（优先）或 nc 兜底
# 输出格式与 QML 的 refreshUploaderOutput() 兼容

PORT=8088
UPLOAD_DIR="/userdisk/Music/小说"
HTTPD_ROOT="/tmp/novel-httpd"
LOGFILE="/tmp/novel-uploader.log"

# 将 stdout/stderr 都写入日志，方便 QML 读取
exec > "$LOGFILE" 2>&1

mkdir -p "$UPLOAD_DIR" "$HTTPD_ROOT"

# ---------- 获取局域网 IP ----------
get_ips() {
    # 方法 1: ip addr
    ips=$(ip addr 2>/dev/null | sed -n 's/.*inet \([0-9.]\+\)\/.*/\1/p' | grep -v '^127\.\|^169\.254\.\|^0\.')
    [ -n "$ips" ] && { echo "$ips"; return; }

    # 方法 2: ifconfig
    ips=$(ifconfig 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]\+\) .*/\1/p' | grep -v '^127\.\|^169\.254\.\|^0\.')
    [ -n "$ips" ] && { echo "$ips"; return; }

    # 方法 3: hostname -I
    ips=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^127\.\|^169\.254\.\|^0\.')
    [ -n "$ips" ] && echo "$ips" || echo "127.0.0.1"
}

# ---------- 输出 IP（QML 通过此信息检测地址） ----------
MY_IPS=$(get_ips)
echo "=== Novel Uploader (shell) ==="

for ip in $MY_IPS; do
    echo "http://$ip:$PORT"
done

# ---------- 清理函数 ----------
cleanup() {
    # 尝试 kill httpd（如果有 pid 文件）
    [ -f "$HTTPD_ROOT/httpd.pid" ] && kill "$(cat "$HTTPD_ROOT/httpd.pid")" 2>/dev/null
    # 清理 nc 进程
    pkill -f "novel-uploader.sh.*nc" 2>/dev/null || true
    rm -rf "$HTTPD_ROOT"
}

trap cleanup EXIT INT TERM

# ============================================================
# 方案 A: busybox httpd + CGI（优先）
# ============================================================
start_httpd() {
    # ---------- 生成 index.html ----------
    cat > "$HTTPD_ROOT/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>小说上传服务</title>
<style>
  body{font-family:sans-serif;background:#f6f7f9;margin:0;color:#222}
  main{max-width:560px;margin:32px auto;padding:20px;background:#fff;border:1px solid #dde1e7;border-radius:8px}
  h1{font-size:22px;margin:0 0 12px}
  .path{padding:10px;background:#eef6ff;border-radius:6px;font-family:monospace;font-size:14px;word-break:break-all}
  .msg{padding:10px;margin:12px 0;background:#f1f8e9;border-radius:6px;color:#2e7d32}
  input,button{width:100%;box-sizing:border-box;font-size:16px}
  input{padding:10px;border:1px solid #c7ced8;border-radius:6px;background:#fff}
  button{margin-top:12px;padding:11px;border:0;border-radius:6px;background:#2563eb;color:#fff;cursor:pointer}
  button:disabled{background:#94a3b8;cursor:not-allowed}
  .status{margin-top:12px;font-size:14px;color:#666}
</style>
</head>
<body>
<main>
  <h1>📚 小说上传服务</h1>
  <p>选择 <b>.txt</b> 文件上传，文件会保存到：</p>
  <div class="path">/userdisk/Music/小说/</div>
  <div id="message" class="msg" style="display:none"></div>
  <input type="file" id="file" accept=".txt,text/plain">
  <button id="btn" onclick="upload()">上传 TXT</button>
  <div id="status" class="status"></div>
</main>
<script>
function $(id){return document.getElementById(id)}
function upload(){
  var f=$('file').files[0];
  if(!f){$('status').textContent='请先选择文件';return}
  var btn=$('btn');btn.disabled=true;btn.textContent='上传中...';
  var r=new FileReader();
  r.onload=function(){
    var b64=btoa(String.fromCharCode.apply(null,new Uint8Array(r.result)));
    var x=new XMLHttpRequest();
    x.open('POST','/upload.cgi',true);
    x.setRequestHeader('Content-Type','application/x-www-form-urlencoded');
    x.onload=function(){
      $('message').style.display='block';
      $('message').textContent='✅ 上传成功: '+f.name;
      $('file').value='';btn.disabled=false;btn.textContent='上传 TXT';
      setTimeout(function(){$('message').style.display='none'},5000);
    };
    x.onerror=function(){
      $('status').textContent='上传失败: 连接错误';
      btn.disabled=false;btn.textContent='上传 TXT';
    };
    x.send('name='+encodeURIComponent(f.name)+'&data='+encodeURIComponent(b64));
  };
  r.readAsArrayBuffer(f);
}
</script>
</body>
</html>
EOF

    # ---------- 生成 upload.cgi ----------
    cat > "$HTTPD_ROOT/upload.cgi" << 'EOF'
#!/bin/sh

# 接收 POST 数据，解析 URL-encoded base64 文件
CONTENT_LENGTH=${CONTENT_LENGTH:-0}

# 精确读取 CONTENT_LENGTH 字节
body=$(dd bs=1 count=$CONTENT_LENGTH 2>/dev/null)

# 提取 name 和 data 字段
name=$(echo "$body" | sed 's/.*[?&]\?name=\([^&]*\).*/\1/' | sed 's/+/ /g')
data=$(echo "$body" | sed 's/.*[?&]\?data=\([^&]*\).*/\1/' | sed 's/+/ /g')

# URL 解码（处理 %XX）
name=$(echo "$name" | sed 's/%/\\x/g')
name=$(printf '%b' "$name" 2>/dev/null || echo "$name")

# 过滤文件名
name=$(basename "$name" | sed 's/[\/:*?"<>|]/_/g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
[ -z "$name" ] && name="novel.txt"
echo "$name" | grep -qi '\.txt$' || name="${name}.txt"

# base64 解码并保存
echo "$data" | base64 -d > "/userdisk/Music/小说/$name" 2>/dev/null && {
    echo "Content-Type: text/plain; charset=utf-8"
    echo ""
    echo "OK: $name"
} || {
    echo "Content-Type: text/plain; charset=utf-8"
    echo ""
    echo "ERR: save failed"
}
EOF
    chmod +x "$HTTPD_ROOT/upload.cgi"

    # ---------- 启动 httpd ----------
    # 检查 busybox 是否存在以及是否支持 httpd
    if busybox httpd --help 2>/dev/null | grep -q '\-p'; then
        busybox httpd -p "$PORT" -h "$HTTPD_ROOT" &
        echo "$!" > "$HTTPD_ROOT/httpd.pid"
        wait "$!"
        return $?
    fi

    return 1
}

# ============================================================
# 方案 B: nc 兜底（仅当 busybox httpd 不可用时）
# ============================================================
start_nc_server() {
    # 需要 nc 支持 -l -p
    NC=""
    for c in nc busybox nc.traditional; do
        if command -v "$c" >/dev/null 2>&1; then
            if echo "" | "$c" -h 2>&1 | grep -q 'l.*p'; then
                NC="$c"
                break
            fi
        fi
    done

    [ -z "$NC" ] && return 1

    # 用 nc 实现极简 HTTP 服务器（每次请求 fork）
    serve_request() {
        local method path version header body clen
        read method path version

        # 读头部
        while read header; do
            header=$(echo "$header" | tr -d '\r')
            [ -z "$header" ] && break
            case "$header" in
                [Cc]ontent-[Ll]ength:*) clen="${header#*: }" ;;
            esac
        done

        case "$method" in
            GET)
                cat "$HTTPD_ROOT/index.html"
                ;;
            POST)
                body=$(dd bs=1 count="$clen" 2>/dev/null)
                name=$(echo "$body" | sed 's/.*name=\([^&]*\).*/\1/' | sed 's/+/ /g')
                data=$(echo "$body" | sed 's/.*data=\([^&]*\).*/\1/' | sed 's/+/ /g')
                name=$(echo "$name" | sed 's/%/\\x/g')
                name=$(printf '%b' "$name" 2>/dev/null || echo "$name")
                name=$(basename "$name" | sed 's/[\/:*?"<>|]/_/g')
                [ -z "$name" ] && name="novel.txt"
                echo "$name" | grep -qi '\.txt$' || name="${name}.txt"
                echo "$data" | base64 -d > "$UPLOAD_DIR/$name" 2>/dev/null
                # HTTP redirect (303)
                echo "HTTP/1.0 303 See Other"
                echo "Location: /"
                echo ""
                ;;
            *)
                echo "HTTP/1.0 404 Not Found"
                echo ""
                echo "Not Found"
                ;;
        esac
    }

    while true; do
        if [ "$NC" = "nc" ]; then
            # 某些 nc 支持 -e 参数
            nc -l -p "$PORT" -e /bin/sh -c "serve_request" 2>/dev/null
        else
            # 从 stdin 读取请求，处理后发送响应
            serve_request | "$NC" -l -p "$PORT" -q 1 2>/dev/null
        fi
    done
}

# ============================================================
# 主流程
# ============================================================

# 优先方案 A: busybox httpd
start_httpd
RC=$?

# 如果 httpd 失败，尝试方案 B
if [ $RC -ne 0 ]; then
    start_nc_server
    RC=$?
fi

# 都失败
echo "错误: 无法启动 HTTP 服务器（需要 busybox httpd 或 nc）"
exit 1
