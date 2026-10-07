// Search.js - 全文搜索
//
// 在已加载的 rawLines（原始文本行）中查找关键词，返回可跳转的结果。
// 纯逻辑，便于单元测试。
.pragma library

// 单次搜索返回的最大结果数（避免结果过多卡顿）
var MAX_RESULTS = 200;

// 结果片段中关键词两侧各保留的字符数
var CONTEXT_PAD = 30;

// 搜索选项
var DEFAULT_OPTIONS = {
    caseSensitive: false,
    wholeWord: false
};

// 判断字符是否为 CJK（用于决定是否做「整词」匹配）
function isCJK(code) {
    return (code >= 0x2E80 && code <= 0x9FFF)
        || (code >= 0xF900 && code <= 0xFAFF)
        || (code >= 0x3000 && code <= 0x303F);
}

// 在主文本中查找所有命中位置。
// rawLines: 原始行数组（搜索基于原文，不受换行/字号影响）
// query: 关键词
// 返回 { hits: [{line, start, end, before, match, after}], truncated: bool, total: int }
function search(rawLines, query, options) {
    var result = { hits: [], truncated: false, total: 0 };
    if (!rawLines || !query || query === "") return result;

    var opt = options || DEFAULT_OPTIONS;
    var needle = opt.caseSensitive ? query : query.toLowerCase();
    if (needle === "") return result;

    for (var i = 0; i < rawLines.length; i++) {
        var line = rawLines[i];
        if (!line) continue;
        var hay = opt.caseSensitive ? line : line.toLowerCase();

        var from = 0;
        while (true) {
            var idx = hay.indexOf(needle, from);
            if (idx < 0) break;

            var endPos = idx + query.length;

            // 整词匹配：要求前后都不是「同类字符」，避免匹配到单词内部
            if (opt.wholeWord && !isValidWordBoundary(line, idx, endPos)) {
                from = idx + 1;
                continue;
            }

            result.total++;
            if (result.hits.length < MAX_RESULTS) {
                result.hits.push(buildHit(line, idx, endPos, i));
            } else {
                result.truncated = true;
            }
            from = idx + 1;
        }
    }
    return result;
}

// 整词边界校验：中文字符无需边界（本身即词），
// 英文/数字则要求前后不是字母数字
function isValidWordBoundary(line, start, end) {
    var before = start > 0 ? line.charCodeAt(start - 1) : 0;
    var after = end < line.length ? line.charCodeAt(end) : 0;
    if (isWordChar(before) && !isCJK(before)) return false;
    if (isWordChar(after) && !isCJK(after)) return false;
    return true;
}

function isWordChar(code) {
    if (code === 0) return false;
    // 字母、数字、下划线
    return (code >= 48 && code <= 57)
        || (code >= 65 && code <= 90)
        || (code >= 97 && code <= 122)
        || code === 95;
}

// 构造一条命中记录，含上下文片段（用于结果列表展示）
function buildHit(line, start, end, lineIndex) {
    var padStart = Math.max(0, start - CONTEXT_PAD);
    var padEnd = Math.min(line.length, end + CONTEXT_PAD);
    return {
        line: lineIndex,
        start: start,
        end: end,
        before: (padStart > 0 ? "…" : "") + line.substring(padStart, start),
        match: line.substring(start, end),
        after: line.substring(end, padEnd) + (padEnd < line.length ? "…" : ""),
        text: line.substring(padStart, padEnd).trim()
    };
}

// 高亮用的分段：把一行按关键词切成 [{text, isMatch}] 数组。
// 供界面用不同颜色渲染命中部分。
function highlightSegments(text, query, caseSensitive) {
    var segs = [];
    if (!text) return segs;
    if (!query || query === "") {
        segs.push({ text: text, isMatch: false });
        return segs;
    }
    var hay = caseSensitive ? text : text.toLowerCase();
    var needle = caseSensitive ? query : query.toLowerCase();
    var from = 0;
    while (true) {
        var idx = hay.indexOf(needle, from);
        if (idx < 0) break;
        if (idx > from) segs.push({ text: text.substring(from, idx), isMatch: false });
        segs.push({ text: text.substring(idx, idx + query.length), isMatch: true });
        from = idx + query.length;
    }
    if (from < text.length) segs.push({ text: text.substring(from), isMatch: false });
    return segs;
}

// 按「章节」归类命中结果，返回 [{chapterIdx, count, firstLine}]
// chapters: [{startRaw, endRaw, title}]
function groupByChapter(hits, chapters) {
    var groups = [];
    if (!hits || !chapters) return groups;
    var map = {};
    for (var i = 0; i < hits.length; i++) {
        var ci = chapterIndexForLine(hits[i].line, chapters);
        if (!map[ci]) {
            map[ci] = {
                chapterIdx: ci,
                title: (ci >= 0 && ci < chapters.length) ? chapters[ci].title : "（未知章节）",
                count: 0,
                firstLine: hits[i].line
            };
            groups.push(map[ci]);
        }
        map[ci].count++;
    }
    return groups;
}

// 定位某原始行所属的章节序号
function chapterIndexForLine(line, chapters) {
    for (var i = chapters.length - 1; i >= 0; i--) {
        if (chapters[i].startRaw <= line) return i;
    }
    return 0;
}