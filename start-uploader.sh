#!/bin/sh
# 小说上传服务启动脚本 v2.1
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
get_ip() {
    for cmd in "ip -4 addr show scope global" "ifconfig" "hostname -I"; do
        ip=$(eval $cmd 2>/dev/null | grep -oE '([0-9]+\.){3}[0-9]+' | while read line; do
            case "$line" in 127.*|169.254.*) continue ;; esac
            last="${line##*.}"
            [ "$last" = "0" ] || [ "$last" = "255" ] && continue
            echo "$line" && break
        done)
        [ -n "$ip" ] && echo "$ip" && return 0
    done
    echo "0.0.0.0"
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
uploadBtn.addEventListener('click',function(){
  if(!selectedFile)return;
  uploadBtn.disabled=true;uploadBtn.textContent='上传中...';
  var r=new FileReader();
  r.onload=function(){
    var bytes=new Uint8Array(r.result),b64='';
    for(var i=0;i<bytes.length;i++)b64+=String.fromCharCode(bytes[i]);
    b64=btoa(b64);
    var x=new XMLHttpRequest();
    x.open('POST','/upload.cgi',true);
    x.setRequestHeader('Content-Type','application/x-www-form-urlencoded');
    x.onload=function(){
      if(x.status===200){showMsg('✅ '+selectedFile.name+' 上传成功！','success');clearFile();}
      else{showMsg('上传失败，请重试','error');uploadBtn.disabled=false;uploadBtn.textContent='请先选择文件';}
    };
    x.onerror=function(){showMsg('网络错误，请检查连接','error');uploadBtn.disabled=false;uploadBtn.textContent='请先选择文件';};
    x.send('name='+encodeURIComponent(selectedFile.name)+'&data='+encodeURIComponent(b64));
  };
  r.readAsArrayBuffer(selectedFile);
});
</script>
</body>
</html>
HTMLEOF

# 生成 upload.cgi（shell CGI）
cat > "$HTTPD_ROOT/upload.cgi" << 'CGIEOF'
#!/bin/sh
UPLOAD_DIR="/userdisk/Music/小说"

# 只接受 POST 请求
if [ "$REQUEST_METHOD" != "POST" ]; then
    echo "Content-Type: text/plain"
    echo ""
    echo "ERR Method not allowed"
    exit 0
fi

# 读取 POST 数据（优化：按块读取而非逐字节）
body=""
if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
    body=$(dd bs=$CONTENT_LENGTH count=1 2>/dev/null || cat)
fi

name=$(echo "$body" | sed 's/.*name=\([^&]*\).*/\1/' | sed 's/+/ /g')
data=$(echo "$body" | sed 's/.*data=\([^&]*\).*/\1/' | sed 's/+/ /g')

# URL 解码（busybox printf %b 支持反斜杠转义）
name=$(printf '%b' "$(echo "$name" | sed 's/%/\\x/g')" 2>/dev/null || echo "$name")
name=$(basename "$name" 2>/dev/null || echo "$name")
name=$(echo "$name" | sed 's/[\/:*?"<>|\\]/_/g')
[ -z "$name" ] && name="novel.txt"
echo "$name" | grep -qi '\.txt$' || name="${name}.txt"
mkdir -p "$UPLOAD_DIR" 2>/dev/null
echo "$data" | base64 -d > "$UPLOAD_DIR/$name" 2>/dev/null
if [ $? -eq 0 ] && [ -s "$UPLOAD_DIR/$name" ]; then
    echo "Content-Type: text/plain"
    echo ""
    echo "OK $name"
else
    echo "Content-Type: text/plain"
    echo ""
    echo "ERR decode failed"
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
var qs = require('querystring');
var path = require('path');
var PORT = 8088;
var UPLOAD_DIR = '/userdisk/Music/小说';
var HTML = '';
try { HTML = fs.readFileSync('/tmp/novel-httpd/index.html', 'utf8'); } catch(e) {}
var server = http.createServer(function(req, res) {
    if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html')) {
        res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8'});
        res.end(HTML);
    } else if (req.method === 'POST' && (req.url === '/upload' || req.url === '/upload.cgi')) {
        var chunks = [];
        req.on('data', function(c) { chunks.push(c); });
        req.on('end', function() {
            try {
                var body = Buffer.concat(chunks).toString();
                var params = qs.parse(body);
                var name = String(params.name || 'novel.txt');
                name = path.basename(name).replace(/[/:*?"<>|]/g, '_');
                if (!name.toLowerCase().endsWith('.txt')) name += '.txt';
                var data = Buffer.from(String(params.data || ''), 'base64');
                if (!fs.existsSync(UPLOAD_DIR)) fs.mkdirSync(UPLOAD_DIR);
                fs.writeFileSync(UPLOAD_DIR + '/' + name, data);
                res.writeHead(200);
                res.end('OK ' + name);
            } catch(e) { res.writeHead(500); res.end('ERR'); }
        });
    } else { res.writeHead(404); res.end('Not Found'); }
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
import base64
import urllib.parse

PORT = 8088
UPLOAD_DIR = '/userdisk/Music/小说'
HTTPD_ROOT = '/tmp/novel-httpd'

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path in ('/', '/index.html'):
            try:
                with open(os.path.join(HTTPD_ROOT, 'index.html'), 'r', encoding='utf-8') as f:
                    content = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.end_headers()
                self.wfile.write(content.encode('utf-8'))
            except Exception as e:
                self.send_error(500, str(e))
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path in ('/upload', '/upload.cgi'):
            try:
                content_length = int(self.headers.get('Content-Length', 0))
                body = self.rfile.read(content_length).decode('utf-8')
                params = urllib.parse.parse_qs(body)
                name = params.get('name', ['novel.txt'])[0]
                data_b64 = params.get('data', [''])[0]

                name = os.path.basename(name)
                name = ''.join(c if c not in '/:*?"<>|' else '_' for c in name)
                if not name.lower().endswith('.txt'):
                    name += '.txt'

                data = base64.b64decode(data_b64)
                os.makedirs(UPLOAD_DIR, exist_ok=True)
                with open(os.path.join(UPLOAD_DIR, name), 'wb') as f:
                    f.write(data)

                self.send_response(200)
                self.end_headers()
                self.wfile.write(('OK ' + name).encode('utf-8'))
            except Exception as e:
                self.send_error(500, str(e))
        else:
            self.send_error(404)

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
# ============================================================
if command -v busybox >/dev/null 2>&1; then
    echo "Found busybox" >>"$LOG_FILE"

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
echo "ERROR: 未找到 node 或 python3 或 busybox httpd" >>"$LOG_FILE"
echo "ERROR: no node or python3 or busybox httpd found"
exit 1
