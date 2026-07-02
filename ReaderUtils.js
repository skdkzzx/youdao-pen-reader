// ReaderUtils.js - 阅读器工具函数
.pragma library

var defaultBookFolder = "/userdisk/Music/小说/";
var defaultBookSuffix = ".txt";

function setDefaults(folder, suffix) {
    defaultBookFolder = folder;
    defaultBookSuffix = suffix;
}

function basename(url) {
    if (typeof url !== "string") return "未命名";
    var parts = url.replace(/\\/g, "/").split("/");
    return parts[parts.length - 1] || "未命名";
}

function bookTitle(value) {
    var name = basename(value);
    try {
        name = decodeURIComponent(name);
    } catch (e) { }
    var lower = name.toLowerCase();
    if (lower.length > defaultBookSuffix.length
        && lower.substring(lower.length - defaultBookSuffix.length) === defaultBookSuffix) {
        name = name.substring(0, name.length - defaultBookSuffix.length);
    }
    return name;
}

function stripFilePrefix(url) {
    if (typeof url !== "string") return "";
    return url.indexOf("file://") === 0 ? url.substring(7) : url;
}

function isDefaultBookFile(url) {
    var path = stripFilePrefix(url).replace(/\\/g, "/");
    try {
        path = decodeURIComponent(path);
    } catch (e) { }
    return path.toLowerCase().indexOf(defaultBookFolder.toLowerCase()) === 0;
}

function addFilePrefix(path) {
    if (typeof path !== "string") return "";
    path = path.trim();
    if (path === "") return "";
    if (path.indexOf("file://") === 0) return path;
    return "file://" + path;
}

function normalizeBookInput(text, folder, suffix) {
    folder = folder || defaultBookFolder;
    suffix = suffix || defaultBookSuffix;
    if (typeof text !== "string") return "";
    var path = text.trim();
    if (path === "") return "";
    if (path.indexOf("file://") === 0) return path;

    var hasFolder = path.indexOf("/") >= 0 || path.indexOf("\\") >= 0;
    if (!hasFolder) {
        var lower = path.toLowerCase();
        if (lower.length < suffix.length
            || lower.substring(lower.length - suffix.length) !== suffix) {
            path += suffix;
        }
        path = folder + path;
    }
    return addFilePrefix(path);
}

function encodePath(url) {
    if (url.indexOf("file://") !== 0) return url;
    var p = url.substring(7);
    var encoded = "";
    for (var i = 0; i < p.length; i++) {
        var c = p.charAt(i);
        encoded += c.charCodeAt(0) > 127 ? encodeURIComponent(c) : c;
    }
    return "file://" + encoded;
}

// ====== 中英文视觉宽度处理 ======

// 判断字符是否为宽字符（中文/日文/韩文/全角符号 ≈ 2个英文字母宽）
function isWideChar(code) {
    return (code >= 0x2E80 && code <= 0x9FFF)    || // CJK统一表意文字、部首等
           (code >= 0xF900 && code <= 0xFAFF)    || // CJK兼容表意文字
           (code >= 0xFF00 && code <= 0xFFEF)    || // 全角形式（包含全角字母）
           (code >= 0x3000 && code <= 0x303F)    || // CJK符号和标点
           (code >= 0xAC00 && code <= 0xD7AF)    || // 韩文
           code === 0x200C || code === 0x200D;      // 零宽非连接符/零宽连接符
}

// 计算字符串的视觉宽度（中文=2，英文=1）
function visualWidth(str) {
    var w = 0;
    for (var i = 0; i < str.length; i++) {
        w += isWideChar(str.charCodeAt(i)) ? 2 : 1;
    }
    return w;
}

// 在字符串中按视觉宽度和单词边界找到合适的截断位置
// 优先在空格/CJK字符后/中英文交界处断开，避免切断英文单词
function findSplitPoint(str, maxWidth) {
    var w = 0;
    var lastBreak = -1;
    var prevIsWide = false;

    for (var i = 0; i < str.length; i++) {
        var code = str.charCodeAt(i);
        var curIsWide = isWideChar(code);
        var cw = curIsWide ? 2 : 1;

        // 如果加上这个字符会超出最大宽度
        if (w + cw > maxWidth) {
            // 有合适的断点则在那断开，否则硬切
            if (lastBreak > 0) return lastBreak;
            if (i > 0) return i;
            return 1;
        }

        w += cw;

        // 判断当前位置是否可断开（断点在该字符之后）
        var isBreak = false;
        if (code === 0x20 || code === 0x3000) {
            // 空格：可以在空格之后断开
            isBreak = true;
        } else if (curIsWide) {
            // CJK字符：每个CJK字符后都可以断开
            isBreak = true;
        } else if (i + 1 < str.length) {
            var next = str.charCodeAt(i + 1);
            var nextIsWide = isWideChar(next);
            if (nextIsWide || next === 0x20 || next === 0x3000) {
                // 英文单词结束（后面是空格或中文），可以断开
                isBreak = true;
            } else if (prevIsWide && !curIsWide) {
                // 中文后接英文开头：也可以断开
                isBreak = true;
            }
        } else {
            // 最后一个字符
            isBreak = true;
        }

        if (isBreak) lastBreak = i + 1;
        prevIsWide = curIsWide;
    }

    return str.length;
}

function updateCharsPerLine(baseFontSize) {
    if (baseFontSize <= 13) return 22;
    else if (baseFontSize <= 15) return 19;
    else return 16;
}

function progressFromLine(line, total) {
    if (line <= 0) return 0;
    if (total > 0) return Math.min(100, Math.max(1, Math.round((line / total) * 100)));
    return Math.min(99, Math.max(1, Math.round(line / 100)));
}

function normalizeAutoScrollSeconds(value) {
    var seconds = parseInt(value);
    if (isNaN(seconds)) seconds = 2;
    return Math.max(1, Math.min(999, seconds));
}

function getLinesPerPage(height, readerMargin, textLineHeight) {
    var readableHeight = Math.max(40, height - readerMargin * 2);
    return Math.max(1, Math.floor(readableHeight / textLineHeight));
}

function getTextLineHeight(fontMetricsHeight, baseFontSize, lineSpacing) {
    var extraSpacing = baseFontSize <= 13 ? Math.max(0, lineSpacing - 2) : lineSpacing;
    return Math.max(1, Math.ceil(fontMetricsHeight) + extraSpacing);
}

function maxStartLine(linesLength, linesPerPage) {
    return Math.max(0, linesLength - linesPerPage);
}

function clampCurrentLine(currentLine, maxLine) {
    return Math.max(0, Math.min(currentLine, maxLine));
}

function getProgressPercent(currentLine, linesLength) {
    if (linesLength === 0) return 0;
    return Math.round((currentLine / linesLength) * 100);
}

function getCurrentPage(currentLine, linesPerPage) {
    return Math.floor(currentLine / linesPerPage) + 1;
}

function getTotalPages(linesLength, linesPerPage) {
    return Math.max(1, Math.ceil(linesLength / linesPerPage));
}

function getPageText(lines, currentLine, linesPerPage) {
    if (lines.length === 0) return "";
    var end = Math.min(currentLine + linesPerPage, lines.length);
    var page = [];
    for (var i = currentLine; i < end; i++) page.push(lines[i]);
    return page.join("\n");
}

// ====== 章节标题识别 ======
// 共享正则，同时用于章节边界扫描和章节列表构建
var _chapterRegex = /^(第[一二三四五六七八九十百千零\d]+[章节回集卷部篇]|Chapter\s+\d+|CHAPTER\s+\d+|Part\s+\d+|PART\s+\d+|Volume\s+\d+|VOLUME\s+\d+|Vol\.?\s*\d+|Section\s+\d+|SECTION\s+\d+|Act\s+\d+|ACT\s+\d+|Book\s+\d+|BOOK\s+\d+)/;

function getChapterRegex() {
    return _chapterRegex;
}

// ====== 内容处理（视觉宽度感知 + 单词边界保护） ======
// charsPerLine 表示每行可容纳的中文字符数，视觉宽度预算 = charsPerLine * 2

// 将原始文本按换行符拆分为数组
function splitIntoLines(content) {
    return content.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
}

// 单遍 O(L) 换行处理：遍历每个字符，追踪视觉宽度和最佳断点，
// 不创建中间子串，不重复扫描。
function wrapLine(output, raw, maxWidth) {
    var segStart = 0;
    var lastBreak = 0;
    var width = 0;

    for (var j = 0; j < raw.length; j++) {
        var code = raw.charCodeAt(j);
        var cw = isWideChar(code) ? 2 : 1;

        // 超出视觉宽度 → 切分
        if (width + cw > maxWidth) {
            var cut = lastBreak > segStart ? lastBreak : j;
            if (cut === segStart) cut = Math.max(segStart + 1, j);
            output.push(raw.substring(segStart, cut));
            segStart = cut;
            j = segStart - 1;   // for 循环会 +1
            width = 0;
            lastBreak = segStart;
            continue;
        }

        width += cw;

        // 判断当前位置是否为合适的断点
        var isBreak = false;
        if (code === 0x20 || code === 0x3000) {
            isBreak = true;                 // ASCII/全角空格
        } else if (isWideChar(code)) {
            isBreak = true;                 // CJK 字符：每个都可断开
        } else if (j + 1 < raw.length) {
            var next = raw.charCodeAt(j + 1);
            if (isWideChar(next) || next === 0x20 || next === 0x3000) {
                isBreak = true;             // 英文字符后紧跟 CJK/空格
            }
        }

        if (isBreak) lastBreak = j + 1;
    }

    // 收尾部分
    if (segStart < raw.length) {
        output.push(raw.substring(segStart));
    }
}

// 处理原始行数组（可复用给分块加载）
function wrapLines(rawLines, maxVisualWidth) {
    var output = [];
    var chapters = [];
    var chapterRegex = getChapterRegex();

    for (var i = 0; i < rawLines.length; i++) {
        var raw = rawLines[i];
        var title = raw.trim();
        if (title.length > 0 && title.length < 60 && chapterRegex.test(title)) {
            chapters.push({ title: title, lineIndex: output.length });
        }

        if (raw.length === 0) {
            output.push("");
        } else {
            wrapLine(output, raw, maxVisualWidth);
        }
    }

    return { lines: output, chapters: chapters };
}

// 完整处理（兼容旧接口，内部使用新算法）
function processContent(content, charsPerLine) {
    var rawLines = splitIntoLines(content);
    return wrapLines(rawLines, charsPerLine * 2);
}

function buildBookList(folderScanAvailable, bookFolderModel, progressStore, defaultBookFolder) {
    var items = [];
    var seen = {};

    if (folderScanAvailable && bookFolderModel) {
        for (var i = 0; i < bookFolderModel.count; i++) {
            var url = folderModelFileUrl(bookFolderModel, i, defaultBookFolder);
            if (url === "") continue;
            seen[url] = true;

            var progressItem = progressStore[url] || {};
            var line = parseInt(progressItem.line) || 0;
            var totalLines = parseInt(progressItem.totalLines) || 0;
            var bp = parseInt(progressItem.bookPercent);
            items.push({
                file: url,
                name: bookTitle(url),
                line: line,
                totalLines: totalLines,
                timestamp: parseInt(progressItem.timestamp) || 0,
                progress: isNaN(bp) ? progressFromLine(line, totalLines) : bp
            });
        }
    }

    for (var file in progressStore) {
        if (seen[file]) continue;
        var item = progressStore[file];
        var itemFile = item.file || file;
        // 只要在 /userdisk/Music/ 下的书都只来自文件夹扫描，删了就消失
        if (isDefaultBookFile(itemFile)) continue;
        var p = stripFilePrefix(itemFile).replace(/\\/g, "/").toLowerCase();
        try { p = decodeURIComponent(p); } catch(e) {}
        if (p.indexOf("/userdisk/music/") === 0) continue;
        var bp2 = parseInt(item.bookPercent);
        items.push({
            file: itemFile,
            name: bookTitle(item.name || itemFile),
            line: parseInt(item.line) || 0,
            totalLines: parseInt(item.totalLines) || 0,
            timestamp: parseInt(item.timestamp) || 0,
            progress: isNaN(bp2) ? progressFromLine(parseInt(item.line) || 0, parseInt(item.totalLines) || 0) : bp2
        });
    }
    items.sort(function (a, b) {
        if (a.timestamp !== b.timestamp) return b.timestamp - a.timestamp;
        return a.name.localeCompare(b.name);
    });
    if (items.length > 50) items = items.slice(0, 50);
    return items;
}

function folderModelFileUrl(bookFolderModel, index, defaultBookFolder) {
    if (!bookFolderModel) return "";
    var fileName = bookFolderModel.get(index, "fileName");
    if (fileName) return addFilePrefix(defaultBookFolder + String(fileName));
    var fileUrl = bookFolderModel.get(index, "fileURL");
    if (fileUrl) return String(fileUrl);
    var filePath = bookFolderModel.get(index, "filePath");
    if (filePath) return addFilePrefix(String(filePath));
    return "";
}

function jumpToPage(currentLine, page, linesPerPage, linesLength) {
    return (Math.max(1, page) - 1) * linesPerPage;
}

function jumpToPercentLine(percent, linesLength) {
    return Math.floor((percent / 100) * linesLength);
}

function findChapterIndex(chapterList, currentLine) {
    var idx = 0;
    for (var i = 0; i < chapterList.length; i++) {
        if (chapterList[i].lineIndex <= currentLine) idx = i;
    }
    return idx;
}

function getThemeColors(name) {
    var themes = {
        "默认": { bg: "#FFFBF0", fg: "#333333" },
        "白色": { bg: "#FFFFFF", fg: "#333333" },
        "黄色": { bg: "#FFF8E1", fg: "#5D4037" },
        "绿色": { bg: "#E8F5E9", fg: "#2E7D32" },
        "黑色": { bg: "#263238", fg: "#ECEFF1" },
        "粉色": { bg: "#FCE4EC", fg: "#880E4F" },
        "蓝色": { bg: "#E3F2FD", fg: "#1565C0" }
    };
    return themes[name] || themes["默认"];
}

// 从上传服务日志中提取 URL
function getUploaderUrl(output) {
    var match = output.match(/http:\/\/[\d.]+:8088/);
    return match ? match[0] : "";
}

// 数字格式化（12345 -> "12,345"）
function formatNumber(n) {
    if (n === undefined || n === null) return "0";
    return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}
