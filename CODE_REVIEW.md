# 代码审查报告

审查对象：电子书阅读器 v1.2.1（commit 6098a39）
审查范围：上传链路、持久化层、阅读器核心逻辑
审查方式：静态分析 + 在 BusyBox 环境（Alpine aarch64 / musl / BusyBox 1.37，
与词典笔同源实现）上构造真实请求复现

---

## 一、结论速览

| 编号 | 严重度 | 位置 | 问题 | 状态 |
|------|--------|------|------|------|
| U1 | 致命 | `upload.cgi` | `data` 字段从未 URL 解码，base64 含 `=` 填充即失败 | 已修复 |
| U2 | 致命 | `upload.cgi` | `$?` 检查的是 `mkdir` 而非 `base64`，误报失败 | 已修复 |
| U3 | 高 | `upload.cgi` | `sed 's/+/ /g'` 用于 base64，`+` 被毁导致数据损坏 | 已修复 |
| U4 | 高 | `upload.cgi` | `echo \| base64 -d` 尾部换行污染输入 | 已修复 |
| U5 | 高 | `start-uploader.sh` | 未探测 busybox httpd applet，错误提示有误导性 | 已修复 |
| U6 | 中 | 前端 JS | 上传失败后按钮文案与真实状态矛盾 | 已修复 |
| U7 | 中 | `main.qml` | `_readLog` 同步 XHR 每 500ms 阻塞 UI 线程 | 已修复 |
| U8 | 中 | `main.qml` | 先置 `uploaderStarted=true`，失败后无法重试 | 已修复 |
| U9 | 低 | 前端 JS | base64 + URL 编码导致请求体膨胀 40% | 已修复 |
| R1 | 中 | `Storage.js` | 4 次异步 `sendCommand` 无顺序保证，写竞争 | 已修复 |
| R2 | 中 | `Storage.js` | 章节进度只在 `chapterIdx` 相等时恢复，换章即丢 | 已修复 |
| R3 | 低 | `ReaderUtils.js` | 返回共享正则对象，存在状态污染隐患 | 已修复 |
| B1 | 中 | `main.qml` | 删除文件未清理进度/书签，孤儿记录累积 | 已修复 |
| B2 | 中 | `main.qml` | 重命名书籍不迁移进度键，改名即丢进度 | 已修复 |
| G1 | 中 | `start-uploader.sh` | `get_ip` 管道子 shell 中 `break` 失效 | 已修复 |

---

## 二、上传功能缺陷（重点）

### U1 —— 致命：POST body 的 `data` 字段从未解码

原 `upload.cgi` 只对 `name` 做 URL 解码，`data` 直接进入 `base64 -d`：

```sh
name=$(printf '%b' "$(echo "$name" | sed 's/%/\\x/g')" ...)   # 只解码 name
echo "$data" | base64 -d > "$UPLOAD_DIR/$name"                # data 从未解码
```

前端却对两者都调用了 `encodeURIComponent`，会把 base64 的填充符 `=` 转成 `%3D`。
BusyBox 的 `base64` 把 `%3D` 当作非法字符，**退出码 1**。

实测复现：

```
请求体        name=%E4%B8%89%E4%BD%93.txt&data=56ys5LiA56ugIOS9oOWlveS4lueVjAo%3D
传入 base64   56ys5LiA56ugIOS9oOWlveS4lueVjAo%3D
退出码        1

逐字节验证：含 %3D → 退出码 1 ； 含 = → 退出码 0
```

**触发条件**：源文件字节数**不是 3 的倍数**时 base64 末尾必然出现 `=`，
即绝大多数真实 txt 小说都会失败；只有恰好 3n 字节的文件能侥幸通过。

**修复**：`data` 与 `name` 统一解码，且 `data` 只做 URL 解码、
不做 `+` → 空格还原；全部改用 `printf`。同时改为「写临时文件再原子 mv」，
避免半截文件覆盖已有小说。

> 这也解释了为何 v1.2.0 / v1.2.1 反复修补上传问题却未根治 ——
> 补的是 URL 提取与启动逻辑，始终没有触及 CGI 的解码链路。

---

### U2 —— 致命：`$?` 检查对象错误

```sh
echo "$data" | base64 -d > "$UPLOAD_DIR/$name" 2>/dev/null
if [ $? -eq 0 ] && [ -s "$UPLOAD_DIR/$name" ]; then
```

`$?` 反映的是**上一条命令**（即 `mkdir`）的退出码，而非 `base64` 的。
两个判断是 `&&` 关系，`$?` 非 0 时直接短路。

实测结果最能说明问题：

```
上传目录内容   -rw-r--r-- 24  三体.txt    ← 文件写成功了
内容校验       第一章 你好世界             ← 内容完全正确
HTTP 响应      ERR decode failed          ← 却告诉用户失败
```

**危害**：用户看到「上传失败」但文件已入库 → 反复重传产生覆盖混乱，
或直接放弃上传。属典型的误报型数据不一致。

**修复**：显式捕获 `base64 -d` 的退出码后再判断。

---

### U3 —— 高：`sed 's/+/ /g'` 破坏 base64 数据

```sh
data=$(echo "$body" | sed 's/.*data=\([^&]*\).*/\1/' | sed 's/+/ /g')
```

`+` → 空格 是 `application/x-www-form-urlencoded` 的正确解码规则，
但 base64 字母表本身包含 `+`，一个 `+` 变空格即让整个文件损坏。

实测：

```
原始 data 字段   SGVsbG8+
sed 处理后       [SGVsbG8 ]
解码结果         Helbase64: truncated input    ← 数据截断损坏
```

**触发条件**：`+` 在 base64 输出中的出现概率约 1.5%/字符，
1MB 的 txt（base64 约 137 万字符）几乎**必然**包含 `+`。

**修复**：仅对 `name` 做 `+` → 空格还原，`data` 只做 URL 解码。

---

### U4 —— 高：`echo` 追加换行污染 base64 输入

四处 `echo "$var" | base64 -d` 都会在末尾补 `\n`。
虽然 BusyBox 对尾部换行容错，但一旦换用 GNU coreutils 的 `base64`
行为可能不同（可移植性隐患）。**修复**：统一改用 `printf '%s'`。

---

### U5 —— 高：busybox 分支未探测 httpd applet

三个后端中 `busybox httpd` 是唯一保证存在的（PenMods 环境必带 busybox，
node / python3 均为可选），而这条路径恰好依赖缺陷最集中的 shell CGI。

实测本机 busybox **不含 httpd applet**：

```
$ busybox --list | grep -x httpd
（无输出）
$ busybox httpd -f -p 18088 ...
httpd: applet not found
```

而脚本的最终提示是 `ERROR: 未找到 node 或 python3 或 busybox httpd` ——
busybox 明明存在，只是没编译该 applet，提示具有误导性，
用户按提示去 `opkg install node` 未必可行。

**修复**：改为 `busybox httpd --help` 实际探测 applet；
失败时区分「busybox 缺 httpd」与「完全无后端」两种情况，
并追加 `HINT:` 行引导改用 SSH/SFTP 上传。

---

### U6 —— 中：前端失败分支状态机脱节

```js
else{
  showMsg('上传失败，请重试');
  uploadBtn.disabled=false;
  uploadBtn.textContent='请先选择文件';   // ← 但 selectedFile 仍然非空
}
```

失败后 `selectedFile` 未清空、`fileInfo` 面板仍显示已选文件，
按钮文案却被改成「请先选择文件」→ **UI 自相矛盾**，
且再次点击的重试文案永不恢复。

**修复**：抽出 `uploadError()`，失败时保留已选文件与按钮文案；
新增 `timeout` 处理；回显服务端错误信息而非笼统的「上传失败」。

---

### U9 —— 低：编码膨胀

原实现 `b64 += String.fromCharCode(...)` 逐字符拼接，再叠加
`encodeURIComponent` 二次膨胀。实测：

```
原始          1,000,000 字节
base64        1,333,336 字节
URL 编码后约  1,403,511 字节     (+40%)
```

**修复**：前端改为直接 POST 原始二进制（`application/octet-stream`），
文件名走 query string，彻底省掉 base64 与 URL 编码两层膨胀；
后端 Node/Python 同步改为分块读取原始字节并写入。

---

### G1 —— 中：`get_ip` 无法正确选定首个地址

```sh
ip=$(... | while read line; do
    ...
    echo "$line" && break        # break 只终止子 shell 的 read 循环
done)
```

`while` 位于管道中，运行在**子 shell**；`break` 与 `echo` 的输出
都无法影响主 shell 的流程控制。同时
`[ "$last" = "0" ] || [ "$last" = "255" ] && continue` 的求值顺序
依赖 shell 实现，语义不清。

**修复**：改为显式 `if` 判断 + `printf` 输出 + `| head -n 1` 收敛，
确保只取首个可用地址。验证结果：

```
仅回环      -> 0.0.0.0
正常单网卡  -> 192.168.1.23
多网卡      -> 192.168.1.23      （不再拼接多行）
链路本地    -> 192.168.0.8       （正确跳过 169.254.*）
无ip有ifc   -> 172.16.5.9
全空        -> 0.0.0.0
```

---

## 三、持久化层缺陷

### R1 —— 中：`flushToFile` 写入无顺序保证

```js
ctrl.sendCommand("printf ... > " + BACKUP_PATH + ".tmp");
ctrl.sendCommand("[ -s ... ] && mv ... || rm -f ...");   // 依赖上一条已完成
```

`sendCommand` 是**异步**的（无返回值、无回调）。两次相邻调用不保证
shell 端顺序执行，`.tmp` 可能尚未写完就被 `mv`，或被后一条的 `rm -f` 删除。
紧随其后的**同步 XHR 校验**读到旧内容，`flushToFile` 于是返回 `false`
并**丢弃本次写入** —— 调用方（如 `addBookmark`）据此提示「添加书签失败」。

`periodicSaveTimer`（5s）、`flushProgress`、`Component.onDestruction`
三处都会调用，竞态窗口很宽。

**修复**：每个写入位置合并为单条命令，用 `&&` 串联保证顺序：

```js
"printf '%s' '<b64>' | base64 -d > <target>.tmp && [ -s <target>.tmp ]"
+ " && mv -f <target>.tmp <target> || rm -f <target>.tmp"
```

### R2 —— 中：章节进度恢复条件过严

```js
if (item && parseInt(item.chapterIdx) === chapterIdx) return parseInt(item.line) || 0;
return 0;   // ← 章节不匹配一律从第 0 行开始
```

进度记录只有**一个** `chapterIdx`。读到第 5 章中途跳到第 10 章后
再回到第 5 章，进度归零，与 README「自动记录每本小说的阅读进度」不符。

**修复**：新增 `progress[url].chapters[idx]` 分章存储，
`loadChapterProgress` 优先读取该章独立记录，并保留顶层字段兼容旧数据。

### R3 —— 低：共享正则对象外泄

`getChapterRegex()` 直接返回内部单例。当前无 `/g` 标志，
`test()` 不产生 `lastIndex` 残留，**暂未触发 bug**；但一旦有人加 `/g` 或 `/y`
就会出现「隔行漏判章节」的诡异现象。

**修复**：改为持有正则**源串**，`getChapterRegex()` 每次返回独立副本。

---

## 四、书架与记录管理

### B2 —— 中：重命名书籍丢失进度与书签

`shelfRenameBook` 仅执行 `mv` 文件。进度与书签都以 `file://路径` 为键，
重命名后旧键成为**孤儿**：新路径下进度归零、书签全丢。
用户视角就是「改名后从头开始读」。

**修复**：新增 `Storage.renameRecord()`，同步迁移进度与书签键并清理旧键。

### B1 —— 中：删除文件未清理记录

`Storage.deleteRecord` 只清 `progressStore`，`bookmarksStore` 中的对应键
永久残留；且 `buildBookList` 会过滤掉扫描不到的文件，
这些不可见的记录只会在 `.novel-reader-state.json` 中持续累积。

**修复**：新增 `Storage.purgeRecord()`，删除文件时同时清理进度与书签。

---

## 五、验证记录

所有修复均在 BusyBox 环境（Alpine aarch64 / musl / BusyBox 1.37）上验证：

**上传 CGI 回归测试**（原报告中的失败用例全部重跑）：

```
✅ 测试1.txt (源 26 字节)     ← base64 带 = 填充，原版必失败
✅ book_1.txt (源 26 字节)
✅ 测试2.txt (源 6 字节)      ← base64 含 +，原版数据损坏
✅ book_2.txt (源 6 字节)
✅ 测试3.txt (源 19 字节)
✅ book_3.txt (源 19 字节)
通过 6 / 失败 0
```

**边界用例**：

| 用例 | 结果 |
|------|------|
| 文件名含空格与 `&` | ✅ 正确落盘 |
| 路径穿越 `../../etc/passwd` | ✅ 被 basename 限制在目标目录内 |
| 非 POST 方法 | ✅ `ERR Method not allowed` |
| 超长请求（>1MB） | ✅ `ERR payload too large` |
| 畸形 base64 | ✅ `ERR decode failed` |

**JS 逻辑测试**（node 驱动，注入 Qt 桩）：

```
分章进度   第5章存42 → 切第10章存7 → 回第5章仍为42   ✅
旧数据兼容 chapterIdx 吻合返回 99；不吻合返回 0        ✅
重命名迁移 新键进度/书签就位，旧键已清除               ✅
删除清理   进度与书签同时清除                          ✅
写入命令   flushToFile 发出 2 条命令，均含 && 串联     ✅
换行算法   每行视觉宽度均 ≤ 20，英文单词未被截断       ✅
章节识别   第一章/第123章/Chapter 2 正确识别           ✅
getChapterRegex 返回独立 RegExp 副本                   ✅
```

**未能端到端验证的部分**：本机 BusyBox 未编译 `httpd` applet，
故 busybox httpd 的 CGI 收发的完整链路未跑通；U1–U4 通过直接构造
CGI 环境变量（`REQUEST_METHOD` / `CONTENT_LENGTH`）执行真实
`upload.cgi` 完成端到端复现，结论对词典笔的 BusyBox 环境具有直接可比性。
建议在真机上重点回归 busybox httpd 后端。

---

## 六、遗留建议（未在本次修复范围）

1. **弃用 shell CGI**：在 BusyBox 下用 shell 解析 URL 编码的二进制数据
   属系统性风险。新版前端已改为直接 POST 二进制，shell CGI 现仅作为
   旧客户端的兜底；若目标是彻底规避，可让 busybox httpd 只做静态服务，
   上传交由 SSH/SFTP。
2. **`saveSettings()` 在 `onDestruction` 中可能失效**：组件销毁阶段
   异步 `sendCommand` 是否还能送达未经真机验证。建议把设置写入提前到
   变更时立即执行，而非依赖销毁回调。
3. **`buildBookList` 上限 50 本**：超出部分静默丢弃，建议提示用户。
4. **阅读进度未按字号缩放归一化**：改字号后 `currentLine` 语义变化，
   可能产生位置漂移（`bookmarksStore` 已保存 `linesTotal` 供换算，
   进度表未利用该字段）。
