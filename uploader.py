#!/usr/bin/env python3
import cgi
import html
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8088
MUSIC_DIR = "/userdisk/Music/小说"


def lan_ips():
    ips = []
    try:
        name = socket.gethostname()
        for info in socket.getaddrinfo(name, None, socket.AF_INET):
            ip = info[4][0]
            if ip != "127.0.0.1" and ip not in ips:
                ips.append(ip)
    except Exception:
        pass

    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("8.8.8.8", 80))
        ip = probe.getsockname()[0]
        probe.close()
        if ip != "127.0.0.1" and ip not in ips:
            ips.append(ip)
    except Exception:
        pass

    return ips


def safe_name(name):
    name = os.path.basename(name or "novel.txt")
    for ch in '\\/:*?"<>|':
        name = name.replace(ch, "_")
    name = name.strip() or "novel.txt"
    if not name.lower().endswith(".txt"):
        name += ".txt"
    return name


class Handler(BaseHTTPRequestHandler):
    last_message = ""

    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        self.send_page(Handler.last_message)

    def do_POST(self):
        if self.path != "/upload":
            self.send_error(404)
            return

        form = cgi.FieldStorage(
            fp=self.rfile,
            headers=self.headers,
            environ={
                "REQUEST_METHOD": "POST",
                "CONTENT_TYPE": self.headers.get("Content-Type", ""),
            },
        )
        item = form["file"] if "file" in form else None
        if not item or not getattr(item, "filename", ""):
            Handler.last_message = "上传失败：没有选择文件"
            self.redirect()
            return

        os.makedirs(MUSIC_DIR, exist_ok=True)
        file_name = safe_name(item.filename)
        target = os.path.join(MUSIC_DIR, file_name)
        with open(target, "wb") as f:
            f.write(item.file.read())

        Handler.last_message = "已上传：" + file_name
        self.redirect()

    def redirect(self):
        self.send_response(303)
        self.send_header("Location", "/")
        self.end_headers()

    def send_page(self, message=""):
        msg = html.escape(message or "")
        body = f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>小说上传服务</title>
  <style>
    body {{ font-family: sans-serif; background: #f6f7f9; margin: 0; color: #222; }}
    main {{ max-width: 560px; margin: 32px auto; padding: 20px; background: #fff; border: 1px solid #dde1e7; border-radius: 8px; }}
    h1 {{ font-size: 22px; margin: 0 0 12px; }}
    .path {{ padding: 10px; background: #eef6ff; border-radius: 6px; font-family: monospace; }}
    .msg {{ padding: 10px; margin: 12px 0; background: #f1f8e9; border-radius: 6px; color: #2e7d32; }}
    input, button {{ width: 100%; box-sizing: border-box; font-size: 16px; }}
    input {{ padding: 10px; border: 1px solid #c7ced8; border-radius: 6px; }}
    button {{ margin-top: 12px; padding: 11px; border: 0; border-radius: 6px; background: #2563eb; color: white; }}
  </style>
</head>
<body>
  <main>
    <h1>小说上传服务</h1>
    <p>选择 txt 文件上传，文件会保存到：</p>
    <div class="path">{html.escape(MUSIC_DIR)}/</div>
    {f'<div class="msg">{msg}</div>' if msg else ''}
    <form method="post" action="/upload" enctype="multipart/form-data">
      <input type="file" name="file" accept=".txt,text/plain" required>
      <button type="submit">上传 txt</button>
    </form>
  </main>
</body>
</html>"""
        data = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    os.makedirs(MUSIC_DIR, exist_ok=True)
    print("小说上传服务已启动")
    print("保存目录:", MUSIC_DIR + "/")
    ips = lan_ips()
    if ips:
        print("请在同一局域网浏览器打开：")
        for ip in ips:
            print(f"http://{ip}:{PORT}")
    else:
        print("未获取到局域网 IP，请确认已连接 Wi-Fi。端口:", PORT)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
