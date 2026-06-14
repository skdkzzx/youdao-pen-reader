// ReaderUtils.js - 阅读器工具函数
.pragma library

var defaultBookFolder = "/userdisk/Music/";
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

function processContent(content, charsPerLine) {
    var rawLines = content.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
    var wrapped = [];
    var chapters = [];
    var chapterRegex = /^(第[一二三四五六七八九十百千零\d]+[章节回集卷部篇]|Chapter\s+\d+|CHAPTER\s+\d+)/;

    for (var i = 0; i < rawLines.length; i++) {
        var raw = rawLines[i];
        var title = raw.trim();
        if (title.length > 0 && title.length < 50 && chapterRegex.test(title)) {
            chapters.push({ title: title, lineIndex: wrapped.length });
        }

        if (raw.length === 0) {
            wrapped.push("");
        } else {
            var rest = raw;
            while (rest.length > charsPerLine) {
                wrapped.push(rest.substring(0, charsPerLine));
                rest = rest.substring(charsPerLine);
            }
            wrapped.push(rest);
        }
    }

    return { lines: wrapped, chapters: chapters };
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
            items.push({
                file: url,
                name: bookTitle(url),
                line: line,
                totalLines: totalLines,
                timestamp: parseInt(progressItem.timestamp) || 0,
                progress: progressFromLine(line, totalLines)
            });
        }
    }

    for (var file in progressStore) {
        if (seen[file]) continue;
        var item = progressStore[file];
        var itemFile = item.file || file;
        if (folderScanAvailable && isDefaultBookFile(itemFile)) continue;
        items.push({
            file: itemFile,
            name: bookTitle(item.name || itemFile),
            line: parseInt(item.line) || 0,
            totalLines: parseInt(item.totalLines) || 0,
            timestamp: parseInt(item.timestamp) || 0,
            progress: progressFromLine(parseInt(item.line) || 0, parseInt(item.totalLines) || 0)
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

function getUploaderUrl(output) {
    var match = output.match(/http:\/\/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8088/);
    return match ? match[0] : "";
}
