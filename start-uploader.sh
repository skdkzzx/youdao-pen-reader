#!/bin/sh
# 小说上传服务启动脚本 v3.0
# 自动选择可用后端: node > python3 > busybox httpd
LOG_FILE="/tmp/novel-uploader.log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT=8088
UPLOAD_DIR="/userdisk/Music/小说"
HTTPD_ROOT="/tmp/novel-httpd"

# 清空日志（覆盖模式，确保不会读到旧内容）
: >"$LOG_FILE"
echo "=== start $(date) ===" >>"$LOG_FILE"
echo "SCRIPT_DIR=$SCRIPT_DIR" >>"$LOG_FILE"

# 杀旧进程
fuser -k ${PORT}/tcp 2>/dev/null >>"$LOG_FILE" 2>&1 || true
sleep 0.3

mkdir -p "$UPLOAD_DIR" "$HTTPD_ROOT" 2>/dev/null

# 获取本机 IP
# 修复：原实现把 'echo "$line" && break' 放在 while 管道的子 shell 中，
# break 只终止子 shell 的 read 循环，主 shell 无法获知首个可用地址；
# 同时 [ "$last" = "0" ] || [ "$last" = "255" ] && continue 的求值顺序
# 依赖 shell 实现，语义不清。此处改为显式 if 判断并只输出首个地址。
get_ip() {
    for cmd in "ip -4 addr show scope global" "ifconfig" "hostname -I"; do
        candidate=$(
            eval $cmd 2>/dev/null | grep -oE '([0-9]+\.){3}[0-9]+' | while read -r line; do
                case "$line" in
                    127.*|169.254.*) continue ;;
                esac
                last="${line##*.}"
                if [ "$last" = "0" ] || [ "$last" = "255" ]; then
                    continue
                fi
                printf '%s\n' "$line"
                break
            done | head -n 1
        )
        if [ -n "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    printf '0.0.0.0\n'
}
LAN_IP=$(get_ip)
echo "LAN_IP=$LAN_IP" >>"$LOG_FILE"

# 检测端口是否就绪
wait_for_port() {
    local max_wait=${1:-10}
    local i=0
    while [ $i -lt $max_wait ]; do
        if grep -qi ":$(printf '%04X' $PORT)" /proc/net/tcp 2>/dev/null; then
            return 0
        fi
        sleep 0.3
        i=$((i + 1))
    done
    return 1
}

# 进程存活核心：用 setsid 创建独立 session，sendCommand 结束后进程不灭
DETACH="setsid"
command -v setsid >/dev/null 2>&1 || DETACH="nohup"

# 生成 HTML 上传页面
cat > "$HTTPD_ROOT/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>小说上传</title>
<style>
*,*::before,*::after{box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
     background:#f0f2f5;margin:0;color:#1a1a2e;min-height:100vh;
     display:flex;align-items:center;justify-content:center;padding:16px}
main{width:100%;max-width:480px;background:#fff;border-radius:16px;
     padding:28px 24px;box-shadow:0 4px 24px rgba(0,0,0,.08)}
h1{font-size:24px;margin:0 0 6px;text-align:center}
.sub{text-align:center;font-size:13px;color:#888;margin:0 0 20px}
.upload-zone{position:relative;margin:0 0 16px}
.drop-area{border:2px dashed #c7ced8;border-radius:12px;padding:32px 16px;
            text-align:center;transition:all .2s;cursor:pointer;
            background:#fafbfc;min-height:120px;
            display:flex;flex-direction:column;align-items:center;justify-content:center}
.drop-area.active,.drop-area:hover{border-color:#2563eb;background:#eef4ff}
.drop-area.has-file{border-color:#4caf50;background:#f1f8e9}
.drop-icon{font-size:40px;margin:0 0 8px}
.drop-text{font-size:15px;color:#555;margin:0 0 4px}
.drop-hint{font-size:12px;color:#999;margin:0}
#fileInput{position:absolute;inset:0;opacity:0;cursor:pointer}
.file-info{display:none;align-items:center;gap:8px;padding:10px 14px;
            background:#f1f8e9;border-radius:8px;margin:0 0 12px}
.file-info.show{display:flex}
.file-info .name{flex:1;font-size:14px;color:#2e7d32;overflow:hidden;
                  text-overflow:ellipsis;white-space:nowrap}
.file-info .size{font-size:12px;color:#666;white-space:nowrap}
.file-info .clear{width:24px;height:24px;border-radius:50%;background:#ef9a9a;
                   color:#c62828;border:0;cursor:pointer;font-size:14px;
                   line-height:24px;text-align:center;padding:0;flex-shrink:0}
button{width:100%;padding:13px;font-size:16px;border:0;border-radius:10px;
        cursor:pointer;font-weight:600;transition:all .2s}
#uploadBtn{background:#2563eb;color:#fff}
#uploadBtn:hover{background:#1d4ed8}
#uploadBtn:disabled{background:#94a3b8;cursor:not-allowed}
.msg{padding:12px;border-radius:8px;margin:12px 0 0;font-size:14px;display:none}
.msg.success{display:block;background:#f1f8e9;color:#2e7d32}
.msg.error{display:block;background:#ffebee;color:#c62828}
.path-info{text-align:center;font-size:11px;color:#aaa;margin:10px 0 0;word-break:break-all}
</style>
</head>
<body>
<main>
<h1>小说上传</h1>
<p class="sub">选择 .txt 文件上传到词典笔</p>
<div class="upload-zone">
  <div class="drop-area" id="dropArea">
    <div class="drop-icon">📄</div>
    <p class="drop-text">点击选择文件或拖拽到此处</p>
    <p class="drop-hint">仅支持 .txt 文本文件</p>
  </div>
  <input type="file" id="fileInput" accept=".txt,text/plain">
</div>
<div class="file-info" id="fileInfo">
  <span class="name" id="fileName"></span>
  <span class="size" id="fileSize"></span>
  <button class="clear" id="clearBtn" title="清除选择">&times;</button>
</div>
<button id="uploadBtn" disabled>请先选择文件</button>
<div id="msg"></div>
<p class="path-info">保存位置：/userdisk/Music/小说/</p>
</main>
<script>
var $=function(id){return document.getElementById(id)};
var dropArea=$('dropArea'),fileInput=$('fileInput'),
    fileInfo=$('fileInfo'),fileName=$('fileName'),fileSize=$('fileSize'),
    clearBtn=$('clearBtn'),uploadBtn=$('uploadBtn'),msg=$('msg');
var selectedFile=null;
function fmtSize(b){
  if(b<1024)return b+' B';
  if(b<1048576)return (b/1024).toFixed(1)+' KB';
  return (b/1048576).toFixed(1)+' MB';
}
function selectFile(f){
  if(!f)return;
  if(!f.name.toLowerCase().endsWith('.txt')){showMsg('请选择 .txt 文件','error');return;}
  selectedFile=f;fileName.textContent=f.name;fileSize.textContent=fmtSize(f.size);
  fileInfo.classList.add('show');dropArea.classList.add('has-file');
  uploadBtn.disabled=false;uploadBtn.textContent='上传 '+f.name;
  msg.className='msg';msg.style.display='none';
}
function clearFile(){
  selectedFile=null;fileInput.value='';fileInfo.classList.remove('show');
  dropArea.classList.remove('has-file');uploadBtn.disabled=true;
  uploadBtn.textContent='请先选择文件';
}
function showMsg(text,type){
  msg.textContent=text;msg.className='msg '+type;msg.style.display='block';
  if(type==='success')setTimeout(function(){msg.style.display='none'},6000);
}
fileInput.addEventListener('change',function(){selectFile(this.files[0]);});
clearBtn.addEventListener('click',function(e){e.stopPropagation();clearFile();});
['dragenter','dragover'].forEach(function(e){
  dropArea.addEventListener(e,function(ev){ev.preventDefault();dropArea.classList.add('active');});
});
['dragleave'].forEach(function(e){
  dropArea.addEventListener(e,function(ev){ev.preventDefault();dropArea.classList.remove('active');});
});
dropArea.addEventListener('drop',function(e){
  e.preventDefault();dropArea.classList.remove('active');
  if(e.dataTransfer.files.length>0)selectFile(e.dataTransfer.files[0]);
});
function uploadError(text){
  showMsg(text,'error');
  // 保留已选文件与按钮文案，避免「请先选择文件」与 fileInfo 面板自相矛盾
  uploadBtn.disabled=false;
  if(selectedFile)uploadBtn.textContent='上传 '+selectedFile.name;
}
uploadBtn.addEventListener('click',function(){
  if(!selectedFile)return;
  uploadBtn.disabled=true;uploadBtn.textContent='上传中...';
  var x=new XMLHttpRequest();
  // 直接 POST 原始二进制，文件名走 query string：
  // 彻底避免 base64 膨胀(4/3) 与 URL 编码再膨胀(~5%)，也避免 shell 端解码二进制
  x.open('POST','/upload?name='+encodeURIComponent(selectedFile.name),true);
  x.setRequestHeader('Content-Type','application/octet-stream');
  x.timeout=120000;
  x.onload=function(){
    if(x.status===200){showMsg('✅ '+selectedFile.name+' 上传成功！','success');clearFile();}
    else{uploadError('上传失败：'+(x.responseText||('HTTP '+x.status)));}
  };
  x.onerror=function(){uploadError('网络错误，请检查连接');};
  x.ontimeout=function(){uploadError('上传超时，文件可能过大');};
  x.send(selectedFile);
});
</script>
</body>
</html>
HTMLEOF

# 生成 upload.cgi（shell CGI，兼容旧版客户端）
#
# 注意：本 CGI 仅作为 busybox httpd 后端的兜底，且**不再用于**新版前端。
# 新版前端直接 POST 原始二进制到 /upload（busybox httpd 无 CGI 时无法处理，
# 此时会 404，前端会提示改用 SSH 上传），因此这里的正确性只影响旧客户端。
#
# 相比旧实现修复了 4 个缺陷：
#   1. data 字段此前**从未**做 URL 解码 → base64 中的 '=' 以 %3D 形式传入，
#      BusyBox base64 视为非法字符而失败。现统一解码 name 与 data。
#   2. 旧代码 `if [ $? -eq 0 ]` 检查的是 mkdir 的退出码而非 base64 的，
#      导致文件已写入成功却返回 ERR。现显式捕获 base64 的退出码。
#   3. 旧代码对 base64 数据执行 sed 's/+/ /g'，把 base64 字母表中的 '+'
#      替换成空格从而损坏数据。现仅对 name 字段做 '+' → 空格还原。
#   4. 旧代码用 echo 管道给 base64，尾部换行污染输入。现统一用 printf。
cat > "$HTTPD_ROOT/upload.cgi" << 'CGIEOF'
#!/bin/sh
UPLOAD_DIR="/userdisk/Music/小说"

# ---- 工具函数 ----
# URL 解码（%XX → 字节）。busybox printf %b 支持 \xHH 转义。
url_decode() {
    printf '%b' "$(printf '%s' "$1" | sed 's/%/\\x/g')" 2>/dev/null || printf '%s' "$1"
}

# 过滤不安全的文件名字符，保证只落在 UPLOAD_DIR 内
sanitize_name() {
    base=$(basename "$1" 2>/dev/null) || base="$1"
    printf '%s' "$base" | sed 's/[\/:*?"<>|\\]/_/g'
}

emit_header() {
    printf 'Content-Type: text/plain\n\n'
}

# 只接受 POST 请求
if [ "$REQUEST_METHOD" != "POST" ]; then
    emit_header
    printf 'ERR Method not allowed\n'
    exit 0
fi

# 1MB 上限：防止超长畸形请求耗尽内存
MAXLEN=1048576
case "$CONTENT_LENGTH" in
    ''|*[!0-9]*) CONTENT_LENGTH=0 ;;
esac
if [ "$CONTENT_LENGTH" -gt "$MAXLEN" ]; then
    emit_header
    printf 'ERR payload too large\n'
    exit 0
fi

# 分块读取 POST 数据，避免大请求一次性读入内存
body=""
if [ "$CONTENT_LENGTH" -gt 0 ]; then
    remaining=$CONTENT_LENGTH
    while [ "$remaining" -gt 0 ]; do
        if [ "$remaining" -gt 8192 ]; then
            chunk=$(dd bs=8192 count=1 2>/dev/null)
        else
            chunk=$(dd bs="$remaining" count=1 2>/dev/null)
        fi
        [ -z "$chunk" ] && break
        body="$body$chunk"
        got=$(printf '%s' "$chunk" | wc -c)
        [ "$got" -le 0 ] && break
        remaining=$((remaining - got))
    done
fi

# ---- 解析字段 ----
# name：取 name= 到第一个 & 之间的内容
raw_name=$(printf '%s' "$body" | sed -n 's/.*name=\([^&]*\).*/\1/p')
# data：取 data= 之后的所有内容（base64 不含 & ，但用 $ 锚定更安全）
raw_data=$(printf '%s' "$body" | sed -n 's/.*data=\(.*\)$/\1/p')

# name 需要 URL 解码 + 表单 '+ → 空格' 还原
name=$(url_decode "$raw_name" | sed 's/+/ /g')
name=$(sanitize_name "$name")
[ -z "$name" ] && name="novel.txt"
case "$(printf '%s' "$name" | tr 'A-Z' 'a-z')" in
    *.txt) ;;
    *) name="${name}.txt" ;;
esac

# data 只需要 URL 解码，**绝不能**做 '+' → 空格（会破坏 base64）
b64=$(url_decode "$raw_data")

mkdir -p "$UPLOAD_DIR" 2>/dev/null

# 先写临时文件再原子替换，避免半截文件覆盖已有小说
tmp="$UPLOAD_DIR/.upload.$$.tmp"
printf '%s' "$b64" | base64 -d > "$tmp" 2>/dev/null
rc=$?

if [ "$rc" -eq 0 ] && [ -s "$tmp" ]; then
    mv "$tmp" "$UPLOAD_DIR/$name" 2>/dev/null || {
        rm -f "$tmp"
        emit_header
        printf 'ERR write failed\n'
        exit 0
    }
    emit_header
    printf 'OK %s\n' "$name"
else
    rm -f "$tmp"
    emit_header
    printf 'ERR decode failed\n'
fi
CGIEOF
chmod +x "$HTTPD_ROOT/upload.cgi"

# ============================================================
# 方案 1: Node.js
# ============================================================
if command -v node >/dev/null 2>&1; then
    echo "Found node" >>"$LOG_FILE"
    cat > "$HTTPD_ROOT/server.js" << 'NODEEOF'
var http = require('http');
var fs = require('fs');
var url = require('url');
var PORT = 8088;
var UPLOAD_DIR = '/userdisk/Music/小说';
// 上传上限 32MB，防止畸形请求耗尽内存
var MAX_BYTES = 32 * 1024 * 1024;
var HTML = '';
try { HTML = fs.readFileSync('/tmp/novel-httpd/index.html', 'utf8'); } catch(e) {}

function safeName(raw) {
    var name = String(raw || '').split(/[\/\\]/).pop();
    name = name.replace(/[:*?"<>|]/g, '_');
    if (!name) name = 'novel.txt';
    if (!/\.txt$/i.test(name)) name += '.txt';
    return name;
}

var server = http.createServer(function(req, res) {
    var parsed = url.parse(req.url, true);
    if (req.method === 'GET' && (parsed.pathname === '/' || parsed.pathname === '/index.html')) {
        res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8'});
        res.end(HTML);
        return;
    }
    if (req.method === 'POST' && (parsed.pathname === '/upload' || parsed.pathname === '/upload.cgi')) {
        var chunks = [];
        var total = 0;
        var aborted = false;
        req.on('data', function(c) {
            if (aborted) return;
            total += c.length;
            if (total > MAX_BYTES) {
                aborted = true;
                res.writeHead(413);
                res.end('ERR payload too large');
                req.destroy();
                return;
            }
            chunks.push(c);
        });
        req.on('end', function() {
            if (aborted) return;
            try {
                var name = safeName(parsed.query.name);
                var buf = Buffer.concat(chunks);
                if (!buf.length) { res.writeHead(400); res.end('ERR empty body'); return; }
                if (!fs.existsSync(UPLOAD_DIR)) fs.mkdirSync(UPLOAD_DIR, {recursive: true});
                // 先写临时文件再原子改名，避免半截文件覆盖已有小说
                var tmp = UPLOAD_DIR + '/.upload.' + process.pid + '.tmp';
                fs.writeFileSync(tmp, buf);
                fs.renameSync(tmp, UPLOAD_DIR + '/' + name);
                res.writeHead(200, {'Content-Type': 'text/plain; charset=utf-8'});
                res.end('OK ' + name);
            } catch(e) {
                res.writeHead(500);
                res.end('ERR ' + (e && e.message ? e.message : 'write failed'));
            }
        });
        req.on('error', function() {
            if (!aborted) { try { res.writeHead(500); res.end('ERR stream error'); } catch(e) {} }
        });
        return;
    }
    res.writeHead(404);
    res.end('Not Found');
});
server.listen(PORT, '0.0.0.0', function() {
    console.log('http://' + (process.argv[2] || '0.0.0.0') + ':' + PORT);
});
NODEEOF

    $DETACH sh -c "exec node '$HTTPD_ROOT/server.js' '$LAN_IP'" </dev/null >>"$LOG_FILE" 2>&1 &

    if wait_for_port 10; then
        echo "http://$LAN_IP:$PORT" >>"$LOG_FILE"
        echo "Backend: node http://$LAN_IP:$PORT" >>"$LOG_FILE"
        echo "Backend: node http://$LAN_IP:$PORT"
        exit 0
    else
        echo "ERROR: node started but port $PORT not listening" >>"$LOG_FILE"
        fuser -k ${PORT}/tcp 2>/dev/null || true
        pkill -f "node.*server.js" 2>/dev/null || true
    fi
fi

# ============================================================
# 方案 2: Python3
# ============================================================
if command -v python3 >/dev/null 2>&1; then
    echo "Found python3" >>"$LOG_FILE"
    cat > "$HTTPD_ROOT/server.py" << 'PYEOF'
import http.server
import socketserver
import os
import urllib.parse

PORT = 8088
UPLOAD_DIR = '/userdisk/Music/小说'
HTTPD_ROOT = '/tmp/novel-httpd'
# 上传上限 32MB，防止畸形请求耗尽内存
MAX_BYTES = 32 * 1024 * 1024

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

def safe_name(raw):
    name = os.path.basename(str(raw or '').replace('\\', '/'))
    name = ''.join(c if c not in '/:*?"<>|' else '_' for c in name)
    if not name:
        name = 'novel.txt'
    if not name.lower().endswith('.txt'):
        name += '.txt'
    return name

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def _plain(self, code, text):
        body = text.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path in ('/', '/index.html'):
            try:
                with open(os.path.join(HTTPD_ROOT, 'index.html'), 'r', encoding='utf-8') as f:
                    content = f.read()
                body = content.encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except Exception as e:
                self._plain(500, 'ERR ' + str(e))
        else:
            self._plain(404, 'Not Found')

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path not in ('/upload', '/upload.cgi'):
            self._plain(404, 'Not Found')
            return

        try:
            content_length = int(self.headers.get('Content-Length', 0) or 0)
        except ValueError:
            self._plain(400, 'ERR bad content-length')
            return

        if content_length <= 0:
            self._plain(400, 'ERR empty body')
            return
        if content_length > MAX_BYTES:
            self._plain(413, 'ERR payload too large')
            return

        # 分块读取，避免一次性把大请求读进内存
        remaining = content_length
        chunks = []
        while remaining > 0:
            chunk = self.rfile.read(min(65536, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        data = b''.join(chunks)

        if not data:
            self._plain(400, 'ERR empty body')
            return

        try:
            params = urllib.parse.parse_qs(parsed.query)
            name = safe_name(params.get('name', ['novel.txt'])[0])
            os.makedirs(UPLOAD_DIR, exist_ok=True)
            # 先写临时文件再原子改名，避免半截文件覆盖已有小说
            tmp = os.path.join(UPLOAD_DIR, '.upload.%d.tmp' % os.getpid())
            with open(tmp, 'wb') as f:
                f.write(data)
            os.replace(tmp, os.path.join(UPLOAD_DIR, name))
            self._plain(200, 'OK ' + name)
        except Exception as e:
            self._plain(500, 'ERR ' + str(e))

with ReusableTCPServer(('0.0.0.0', PORT), Handler) as httpd:
    print('http://0.0.0.0:' + str(PORT))
    httpd.serve_forever()
PYEOF

    $DETACH sh -c "exec python3 '$HTTPD_ROOT/server.py'" </dev/null >>"$LOG_FILE" 2>&1 &

    if wait_for_port 10; then
        echo "http://$LAN_IP:$PORT" >>"$LOG_FILE"
        echo "Backend: python3 http://$LAN_IP:$PORT" >>"$LOG_FILE"
        echo "Backend: python3 http://$LAN_IP:$PORT"
        exit 0
    else
        echo "ERROR: python3 started but port $PORT not listening" >>"$LOG_FILE"
        fuser -k ${PORT}/tcp 2>/dev/null || true
        pkill -f "python3.*server.py" 2>/dev/null || true
    fi
fi

# ============================================================
# 方案 3: busybox httpd
# 修复：原实现只检查 `command -v busybox`，但很多嵌入式 busybox 并未编译
# httpd applet（如 iSH 的精简版即为 `httpd: applet not found`）。
# 此时启动必然失败，而最终错误信息却仍提示「未找到 ... busybox httpd」，
# 具有误导性。这里改为实际探测 applet 是否可用。
# ============================================================
if command -v busybox >/dev/null 2>&1 && busybox httpd --help >/dev/null 2>&1; then
    echo "Found busybox httpd" >>"$LOG_FILE"

    # 配置 busybox httpd：让 .cgi 文件用 sh 执行
    cat > "$HTTPD_ROOT/httpd.conf" << 'CONFEOF'
I:/bin/sh
*.cgi:/bin/sh
CONFEOF

    $DETACH sh -c "exec busybox httpd -f -p $PORT -h '$HTTPD_ROOT' -c '$HTTPD_ROOT/httpd.conf'" \
        </dev/null >>"$LOG_FILE" 2>&1 &

    if wait_for_port 10; then
        echo "http://$LAN_IP:$PORT" >>"$LOG_FILE"
        echo "Backend: busybox httpd http://$LAN_IP:$PORT" >>"$LOG_FILE"
        echo "Backend: busybox httpd http://$LAN_IP:$PORT"
        exit 0
    else
        echo "ERROR: busybox httpd started but port $PORT not listening" >>"$LOG_FILE"
        fuser -k ${PORT}/tcp 2>/dev/null || true
    fi
fi

# ============================================================
# 全部失败
# ============================================================
# 给出可操作的兜底方案，而不是含糊的「未找到 ... busybox httpd」
if command -v busybox >/dev/null 2>&1 && ! busybox httpd --help >/dev/null 2>&1; then
    echo "ERROR: busybox 存在但未编译 httpd applet，且无 node/python3" >>"$LOG_FILE"
    echo "ERROR: busybox lacks httpd applet" >>"$LOG_FILE"
else
    echo "ERROR: 未找到可用的 node / python3 / busybox httpd" >>"$LOG_FILE"
fi
echo "HINT: 可改用 SSH/SFTP 上传，把 txt 放到 $UPLOAD_DIR" >>"$LOG_FILE"
echo "ERROR: no usable http backend found"
exit 1
