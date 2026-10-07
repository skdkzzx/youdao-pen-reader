// Encoding.js - 文本编码检测与转换
//
// 背景：小说 .txt 常见 GBK / UTF-8 / UTF-16 三种编码。QML 的
// XMLHttpRequest.responseText 恒定按 UTF-8 解码，读取 GBK 文件会得到
// 乱码，且 JS 侧拿不到原始字节，无法在 QML 内补救。
//
// 方案：由 shell 侧的 iconv / node 完成探测与转码，本模块只负责
//   - 构造探测命令
//   - 解析探测结果
//   - 给出可读的提示文案
// QML 层拿到转码后的临时文件路径后再用 XHR 读取（此时必为 UTF-8）。
//
// 设计原则：所有函数为纯函数（除显式标注者），便于单元测试。
.pragma library

// 支持探测的编码，按优先级排列
// UTF-8 放最后：它是 ASCII 兼容的，GBK 文件也常能通过宽松校验，
// 因此先让特征更明确的编码（含 BOM 的）优先匹配。
var CANDIDATE_ENCODINGS = ["UTF-8", "GBK", "BIG5", "UTF-16LE", "UTF-16BE"];

// iconv 可执行文件的候选名，按优先级探测。
// 注意：musl/Alpine 自带的 busybox iconv 只支持少量编码（无 GBK/BIG5），
// 若安装了 gnu-libiconv 则二进制名为 gnu-iconv。因此必须探测可用的那个，
// 否则会出现「探测为 GBK 但转码失败」的情况。
var ICONV_CANDIDATES = ["iconv", "gnu-iconv"];

// 探测结果枚举
var ENCODING_UNKNOWN = "";
var ENCODING_UTF8 = "UTF-8";

// 转码后临时文件目录与命名规则
var TMP_DIR = "/tmp/novel-reader";
var TMP_PREFIX = "/tmp/novel-reader/converted-";

// ====== 路径处理 ======

// 去掉 file:// 前缀，得到 shell 可用的路径
function toFsPath(url) {
    if (typeof url !== "string") return "";
    return url.indexOf("file://") === 0 ? url.substring(7) : url;
}

// 临时文件路径：用原文件名的哈希做后缀，避免不同书互相覆盖。
// 不使用时间戳，保证同一本书多次打开命中同一路径（便于覆盖复用）。
function tempPathFor(url) {
    var p = toFsPath(url);
    return TMP_PREFIX + hashString(p) + ".txt";
}

// 简易字符串哈希（FNV-1a 变体），仅用于生成稳定文件名
function hashString(str) {
    var h = 0x811c9dc5;
    for (var i = 0; i < str.length; i++) {
        h = h ^ str.charCodeAt(i);
        // 乘以 16777619，用移位避免 JS 大整数精度问题
        h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
    }
    return h.toString(16);
}

// ====== 探测命令构造 ======
//
// 输出格式约定（便于解析）：
//   ENC=<检测到的编码>
// 优先用 file -i（最准），回退到 iconv 试探。

function buildDetectCommand(url) {
    var p = toFsPath(url);
    var q = shellQuote(p);

    // UTF-16 必须靠 BOM 判断：它没有字节结构约束，任意偶数字节序列
    // 都能被 iconv "成功"解码成乱码，因此绝不能放进试探序列，
    // 否则 UTF-8 文件会被误判为 UTF-16LE。
    // 顺序：BOM 判定 → GBK/BIG5/UTF-8 试探（特征由强到弱）
    var bomCheck = "B=$(dd if=" + q + " bs=1 count=3 2>/dev/null | od -An -tx1 | tr -d ' \\n'); "
        + "case \"$B\" in "
        +   "fffe*) echo UTF-16LE; ;; "
        +   "feff*) echo UTF-16BE; ;; "
        +   "efbbbf*) echo UTF-8; ;; "
        + "esac";

    var ordered = ["GBK", "BIG5", "UTF-8"];
    var probe = "";
    for (var i = 0; i < ordered.length; i++) {
        if (i > 0) probe += " || ";
        probe += "(\"$ICONV_BIN\" -f " + iconvName(ordered[i]) + " -t UTF-8 "
               + q + " >/dev/null 2>&1 && echo " + ordered[i] + ")";
    }

    var viaFile = "(if command -v file >/dev/null 2>&1; then "
        + "M=$(file -bi " + q + " 2>/dev/null | sed 's/.*charset=//'); "
        + "[ -n \"$M\" ] && [ \"$M\" != \"binary\" ] && echo $M; fi)";

    // 先跑 BOM 检查，有结果就直接输出，否则进入试探
    return buildIconvPickInline()
        + "R=$(" + bomCheck + "); "
        + "if [ -n \"$R\" ]; then echo \"$R\"; "
        + "elif [ -n \"$ICONV_BIN\" ]; then ( " + probe + " ); "
        + "else " + viaFile + "; fi";
}

// 探测 iconv 是否安装了中文编码支持。
// 用于在转码失败时区分「编码确实不对」与「环境缺 iconv 编码表」。
// 同样用 iconv -l 判断，而非拿 /dev/null 试转。
function buildIconvCheckCommand() {
    var checks = [];
    for (var i = 0; i < ICONV_CANDIDATES.length; i++) {
        var c = ICONV_CANDIDATES[i];
        checks.push("(command -v " + c + " >/dev/null 2>&1 && " + c
            + " -l 2>/dev/null | tr ' ' '\\n' | grep -qx 'GBK'"
            + " && echo ICONV_OK=" + c + ")");
    }
    return checks.join(" || ") + " || echo ICONV_OK=";
}

function parseIconvCheck(out) {
    if (typeof out !== "string") return "";
    var m = out.match(/ICONV_OK=(\S+)/);
    return m ? m[1] : "";
}

// 把内部编码名转为 iconv 可识别的名称
function iconvName(enc) {
    if (enc === "UTF-8") return "UTF-8";
    if (enc === "GBK") return "GBK";
    if (enc === "BIG5") return "BIG5";
    if (enc === "UTF-16LE") return "UTF-16LE";
    if (enc === "UTF-16BE") return "UTF-16BE";
    return enc;
}

// 把探测出的编码名归一到内部名称；无法识别时返回 ENCODING_UNKNOWN
function normalizeEncoding(raw) {
    if (typeof raw !== "string") return ENCODING_UNKNOWN;
    var v = raw.trim().toLowerCase().replace(/^charset=/, "");
    // 去掉 file -i 可能附加的修饰，如 utf-8; charset=...
    var semi = v.indexOf(";");
    if (semi >= 0) v = v.substring(0, semi).trim();

    if (v === "" || v === "unknown-8bit" || v === "binary") return ENCODING_UNKNOWN;
    if (v.indexOf("utf-8") === 0 || v === "utf8") return "UTF-8";
    if (v.indexOf("utf-16le") === 0 || v === "utf-16") return "UTF-16LE";
    if (v.indexOf("utf-16be") === 0) return "UTF-16BE";
    if (v.indexOf("gbk") === 0 || v.indexOf("gb2312") === 0
        || v.indexOf("gb18030") === 0 || v.indexOf("cp936") === 0) return "GBK";
    if (v.indexOf("big5") === 0 || v.indexOf("big-5") === 0) return "BIG5";
    // 纯 ASCII 文件按 UTF-8 处理即可（两者字节级兼容）
    if (v.indexOf("iso-8859") === 0
        || v.indexOf("us-ascii") === 0
        || v === "ascii") return "UTF-8";
    return ENCODING_UNKNOWN;
}

// 探测结果文件路径（QML 侧读取此文件获取探测结论）
function resultPathFor(url) {
    return TMP_DIR + "/enc-" + hashString(toFsPath(url)) + ".txt";
}

// 构造「探测 + 结果落盘」命令。
// 由于 shellPluginController 无输出回传，必须把结论写入文件供 QML 读取。
// 命令执行完会留下 RESULT=<编码> 或 RESULT= 一行。
function buildDetectToFileCommand(url) {
    var rp = shellQuote(resultPathFor(url));
    var inner = buildDetectCommand(url);
    return "mkdir -p " + shellQuote(TMP_DIR) + " 2>/dev/null; "
        + "rm -f " + rp + " 2>/dev/null; "
        + "{ " + inner + " ; } | head -n 1 | sed 's/^/RESULT=/' > " + rp + " 2>/dev/null; "
        + "[ -s " + rp + " ] || echo 'RESULT=' > " + rp;
}

// 从结果文件内容解析编码
function parseResultFile(text) {
    if (typeof text !== "string") return ENCODING_UNKNOWN;
    var m = text.match(/RESULT=(\S*)/);
    if (!m) return ENCODING_UNKNOWN;
    return normalizeEncoding(m[1]);
}

// 从探测命令的输出中解析编码
function parseDetectOutput(out) {
    if (typeof out !== "string") return ENCODING_UNKNOWN;
    var m = out.match(/ENC=([A-Za-z0-9._-]+)/);
    if (m) return normalizeEncoding(m[1]);
    // 也支持裸输出（探测命令直接 echo 编码名）
    var line = out.split("\n")[0].trim();
    return normalizeEncoding(line);
}

// ====== 转码命令构造 ======

// 是否需要转码：UTF-8 与未知都按原文件直接读（保持现有行为）
function needConvert(encoding) {
    if (encoding === ENCODING_UTF8 || encoding === ENCODING_UNKNOWN) return false;
    return true;
}

// 构造转码命令：把原文件转成 UTF-8 写入临时文件，输出 CONV=OK / CONV=FAIL
// 同样先探测可用的 iconv 二进制，避免 busybox iconv 不支持 GBK 而静默失败。
function buildConvertCommand(url, encoding) {
    var src = shellQuote(toFsPath(url));
    var dst = shellQuote(tempPathFor(url));
    var enc = iconvName(encoding);
    return "mkdir -p " + shellQuote(TMP_DIR) + " 2>/dev/null; "
        + buildIconvPickInline()
        + "\"$ICONV_BIN\" -f " + enc + " -t UTF-8//TRANSLIT " + src + " > " + dst + " 2>/dev/null"
        + " && [ -s " + dst + " ] && echo CONV=OK || echo CONV=FAIL";
}

// 内联的 iconv 选择片段。
//
// 注意：不能用 `iconv -f GBK -t UTF-8 /dev/null` 做能力探测 —— 空输入
// 在任何 iconv 上都返回成功（无内容可转换），会把不支持 GBK 的
// busybox iconv 误判为可用，导致后续转码静默失败。
// 改用 `iconv -l`（列出支持的编码表），这是唯一可靠的判断方式。
function buildIconvPickInline() {
    return "ICONV_BIN=\"\"; "
        + "for c in " + ICONV_CANDIDATES.join(" ") + "; do "
        +   "if command -v $c >/dev/null 2>&1 "
        +     "&& $c -l 2>/dev/null | tr ' ' '\\n' | grep -qx 'GBK'; then "
        +     "ICONV_BIN=$c; break; "
        +   "fi; "
        + "done; ";
}

// 从转码命令输出解析结果
function parseConvertOutput(out) {
    if (typeof out !== "string") return false;
    return out.indexOf("CONV=OK") >= 0;
}

// ====== shell 引号处理 ======

// 单引号包裹并转义内部单引号，与 main.qml 中 shellEscape 行为一致
function shellQuote(str) {
    if (typeof str !== "string") return "''";
    return "'" + str.replace(/'/g, "'\\''") + "'";
}

// ====== 提示文案 ======

function encodingLabel(encoding) {
    if (encoding === "GBK") return "GBK（简体中文）";
    if (encoding === "BIG5") return "Big5（繁体中文）";
    if (encoding === "UTF-16LE" || encoding === "UTF-16BE") return "UTF-16";
    if (encoding === ENCODING_UTF8) return "UTF-8";
    return "未知";
}

// 是否需要提示用户「已自动转码」
function shouldNotifyConversion(encoding) {
    return needConvert(encoding);
}
