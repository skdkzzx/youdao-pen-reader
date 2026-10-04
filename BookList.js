// BookList.js - 书架排序与筛选
//
// 从 buildBookList 拆出的展示层逻辑：排序、筛选、分组统计。
// 纯函数，便于单元测试；不依赖 QML 运行时。
.pragma library

// ====== 排序 ======
//
// 可用的排序方式。value 用于持久化，label 用于界面，
// compare 接收 (a, b) 返回负数/0/正数（与 Array.sort 约定一致）。

var SORT_RECENT = "recent";       // 最近阅读
var SORT_NAME = "name";           // 书名
var SORT_PROGRESS = "progress";   // 阅读进度
var SORT_SIZE = "size";           // 文件大小
var SORT_UNREAD = "unread";       // 未读优先

var SORT_MODES = [
    { value: SORT_RECENT,   label: "最近阅读" },
    { value: SORT_NAME,     label: "书名" },
    { value: SORT_PROGRESS, label: "进度" },
    { value: SORT_SIZE,     label: "大小" },
    { value: SORT_UNREAD,   label: "未读优先" }
];

function sortLabel(mode) {
    for (var i = 0; i < SORT_MODES.length; i++) {
        if (SORT_MODES[i].value === mode) return SORT_MODES[i].label;
    }
    return "最近阅读";
}

function isValidSortMode(mode) {
    for (var i = 0; i < SORT_MODES.length; i++) {
        if (SORT_MODES[i].value === mode) return true;
    }
    return false;
}

// 按指定模式排序（返回新数组，不修改入参）
function sortBooks(items, mode) {
    if (!items || items.length === 0) return [];
    var arr = items.slice(0);
    if (!isValidSortMode(mode)) mode = SORT_RECENT;

    arr.sort(function (a, b) {
        // 排序键相等时统一用书名做稳定的次级排序，避免顺序抖动
        switch (mode) {
        case SORT_NAME:
            return compareName(a, b);
        case SORT_PROGRESS:
            var dp = num(b.progress) - num(a.progress);
            return dp !== 0 ? dp : compareName(a, b);
        case SORT_SIZE:
            var ds = num(b.size) - num(a.size);
            return ds !== 0 ? ds : compareName(a, b);
        case SORT_UNREAD:
            // 未读（进度 0）排前面，其余按最近阅读
            var au = num(a.progress) > 0 ? 1 : 0;
            var bu = num(b.progress) > 0 ? 1 : 0;
            if (au !== bu) return au - bu;
            var du = num(b.timestamp) - num(a.timestamp);
            return du !== 0 ? du : compareName(a, b);
        case SORT_RECENT:
        default:
            var dr = num(b.timestamp) - num(a.timestamp);
            return dr !== 0 ? dr : compareName(a, b);
        }
    });
    return arr;
}

function compareName(a, b) {
    var na = String(a.name || "");
    var nb = String(b.name || "");
    // 用 localeCompare 时指定中文排序，并保证结果稳定
    var r = na.localeCompare(nb);
    if (r !== 0) return r;
    // 同名时按路径兜底，保证顺序确定
    return String(a.file || "").localeCompare(String(b.file || ""));
}

function num(v) {
    var n = parseInt(v);
    return isNaN(n) ? 0 : n;
}

// ====== 筛选 ======

var FILTER_ALL = "all";
var FILTER_UNREAD = "unread";     // 未读（进度 0）
var FILTER_READING = "reading";   // 在读（1-99%）
var FILTER_DONE = "done";         // 已读完（100%）

var FILTER_MODES = [
    { value: FILTER_ALL,     label: "全部" },
    { value: FILTER_UNREAD,  label: "未读" },
    { value: FILTER_READING, label: "在读" },
    { value: FILTER_DONE,    label: "读完" }
];

function isValidFilterMode(mode) {
    for (var i = 0; i < FILTER_MODES.length; i++) {
        if (FILTER_MODES[i].value === mode) return true;
    }
    return false;
}

// 按进度区间筛选
function filterByStatus(items, mode) {
    if (!items) return [];
    if (!isValidFilterMode(mode) || mode === FILTER_ALL) return items.slice(0);

    var out = [];
    for (var i = 0; i < items.length; i++) {
        var p = num(items[i].progress);
        if (mode === FILTER_UNREAD && p === 0) out.push(items[i]);
        else if (mode === FILTER_READING && p > 0 && p < 100) out.push(items[i]);
        else if (mode === FILTER_DONE && p >= 100) out.push(items[i]);
    }
    return out;
}

// 按书名关键字筛选（大小写不敏感；空关键字返回全部）
function filterByQuery(items, query) {
    if (!items) return [];
    var q = String(query || "").trim();
    if (q === "") return items.slice(0);
    var needle = q.toLowerCase();
    var out = [];
    for (var i = 0; i < items.length; i++) {
        var name = String(items[i].name || "").toLowerCase();
        if (name.indexOf(needle) >= 0) out.push(items[i]);
    }
    return out;
}

// 组合筛选（关键字 + 状态），再做排序
function applyView(items, query, statusMode, sortMode) {
    var r = filterByQuery(items, query);
    r = filterByStatus(r, statusMode);
    return sortBooks(r, sortMode);
}

// ====== 统计 ======

// 汇总书架状态分布，供筛选标签显示数量
function statusCounts(items) {
    var c = { all: 0, unread: 0, reading: 0, done: 0 };
    if (!items) return c;
    for (var i = 0; i < items.length; i++) {
        c.all++;
        var p = num(items[i].progress);
        if (p === 0) c.unread++;
        else if (p >= 100) c.done++;
        else c.reading++;
    }
    return c;
}

// 格式化文件大小（KB/MB）
function formatSize(bytes) {
    var b = num(bytes);
    if (b <= 0) return "";
    if (b < 1024) return b + " B";
    if (b < 1024 * 1024) return (b / 1024).toFixed(1) + " KB";
    return (b / (1024 * 1024)).toFixed(1) + " MB";
}
