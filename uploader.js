const http = require("http");
const os = require("os");
const fs = require("fs");
const path = require("path");

const PORT = 8088;
const MUSIC_DIR = "/userdisk/Music/小说";
let lastMessage = "";

function lanIps() {
  const result = [];
  for (const entries of Object.values(os.networkInterfaces())) {
    for (const item of entries || []) {
      if (item.family === "IPv4" && !item.internal) result.push(item.address);
    }
  }
  return result;
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function safeName(name) {
  let fileName = path.basename(String(name || "novel.txt")).replace(/[\\/:*?"<>|]/g, "_").trim();
  if (!fileName) fileName = "novel.txt";
  if (!/\.txt$/i.test(fileName)) fileName += ".txt";
  return fileName;
}

function page(message) {
  const msg = escapeHtml(message || "");
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>小说上传服务</title>
  <style>
    body { font-family: sans-serif; background: #f6f7f9; margin: 0; color: #222; }
    main { max-width: 560px; margin: 32px auto; padding: 20px; background: #fff; border: 1px solid #dde1e7; border-radius: 8px; }
    h1 { font-size: 22px; margin: 0 0 12px; }
    .path { padding: 10px; background: #eef6ff; border-radius: 6px; font-family: monospace; }
    .msg { padding: 10px; margin: 12px 0; background: #f1f8e9; border-radius: 6px; color: #2e7d32; }
    input, button { width: 100%; box-sizing: border-box; font-size: 16px; }
    input { padding: 10px; border: 1px solid #c7ced8; border-radius: 6px; }
    button { margin-top: 12px; padding: 11px; border: 0; border-radius: 6px; background: #2563eb; color: white; }
  </style>
</head>
<body>
  <main>
    <h1>小说上传服务</h1>
    <p>选择 txt 文件上传，文件会保存到：</p>
    <div class="path">${escapeHtml(MUSIC_DIR)}/</div>
    ${msg ? `<div class="msg">${msg}</div>` : ""}
    <form method="post" action="/upload" enctype="multipart/form-data">
      <input type="file" name="file" accept=".txt,text/plain" required>
      <button type="submit">上传 txt</button>
    </form>
  </main>
</body>
</html>`;
}

function parseMultipart(buffer, contentType) {
  const match = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(contentType || "");
  if (!match) throw new Error("缺少上传边界");
  const boundary = Buffer.from("--" + (match[1] || match[2]));
  let pos = buffer.indexOf(boundary);
  while (pos !== -1) {
    const headerStart = pos + boundary.length + 2;
    const headerEnd = buffer.indexOf(Buffer.from("\r\n\r\n"), headerStart);
    if (headerEnd < 0) break;
    const header = buffer.slice(headerStart, headerEnd).toString("utf8");
    const next = buffer.indexOf(boundary, headerEnd + 4);
    if (next < 0) break;
    const filename = /filename="([^"]*)"/i.exec(header);
    if (/name="file"/i.test(header) && filename) {
      let end = next;
      if (buffer[end - 2] === 13 && buffer[end - 1] === 10) end -= 2;
      return {
        name: safeName(filename[1]),
        data: buffer.slice(headerEnd + 4, end),
      };
    }
    pos = next;
  }
  throw new Error("没有找到上传文件");
}

function redirect(res) {
  res.writeHead(303, { Location: "/" });
  res.end();
}

fs.mkdirSync(MUSIC_DIR, { recursive: true });

http
  .createServer((req, res) => {
    if (req.method === "GET") {
      const body = Buffer.from(page(lastMessage), "utf8");
      res.writeHead(200, {
        "Content-Type": "text/html; charset=utf-8",
        "Content-Length": body.length,
      });
      res.end(body);
      return;
    }

    if (req.method !== "POST" || req.url !== "/upload") {
      res.writeHead(404);
      res.end("Not Found");
      return;
    }

    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      try {
        const upload = parseMultipart(Buffer.concat(chunks), req.headers["content-type"]);
        fs.writeFileSync(path.join(MUSIC_DIR, upload.name), upload.data);
        lastMessage = "已上传：" + upload.name;
      } catch (err) {
        lastMessage = "上传失败：" + err.message;
      }
      redirect(res);
    });
  })
  .listen(PORT, "0.0.0.0", () => {
    console.log("小说上传服务已启动");
    console.log("保存目录:", MUSIC_DIR + "/");
    const ips = lanIps();
    if (ips.length) {
      console.log("请在同一局域网浏览器打开：");
      for (const ip of ips) console.log(`http://${ip}:${PORT}`);
    } else {
      console.log("未获取到局域网 IP，请确认已连接 Wi-Fi。端口:", PORT);
    }
  });
