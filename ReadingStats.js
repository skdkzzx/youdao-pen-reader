// ReadingStats.js - 阅读统计与进度估算
//
// 职责：把「已读位置 / 总长度 / 已用时长」换算成用户可读的信息。
// 全部为纯函数，便于单元测试，不依赖 QML 运行时。
.pragma library

// 估算经验的默认阅读速度（中文，字符/分钟）。
// 词典笔屏幕小、翻页频繁，取 300 字/分偏保守。
var DEFAULT_CHARS_PER_MINUTE = 300;

// 阅读速度的有效区间，超出则视为异常值不作参考
var MIN_SPEED = 50;
var MAX_SPEED = 3000;

// ====== 进度计算 ======

// 全书进度百分比（0-100）。基于「字符偏移」而非行号，
// 因为行号会随字号变化，字符偏移是稳定的。
function bookPercent(charsBefore, totalChars) {
    if (!totalChars || totalChars <= 0) return 0;
    var v = Math.round((charsBefore / totalChars) * 100);
    return Math.max(0, Math.min(100, v));
}

// 本章进度百分比（0-100）
function chapterPercent(charsInChapter, chapterChars) {
    if (!chapterChars || chapterChars <= 0) return 0;
    var v = Math.round((charsInChapter / chapterChars) * 100);
    return Math.max(0, Math.min(100, v));
}

// 把「行号」换算成「该章内的字符偏移」。
// 用于在未记录字符偏移时粗略估算（每行按平均字符数计）。
function lineToChars(line, linesPerChapter, chapterChars) {
    if (!linesPerChapter || linesPerChapter <= 0) return 0;
    var ratio = line / linesPerChapter;
    return Math.round(ratio * (chapterChars || 0));
}

// ====== 剩余时间估算 ======

// 根据已读字符数与已用秒数计算阅读速度（字符/分钟）。
// 样本不足或数值异常时返回 0，表示「无法估算」。
function estimateSpeed(charsRead, secondsElapsed) {
    if (!charsRead || charsRead <= 0) return 0;
    if (!secondsElapsed || secondsElapsed < 30) return 0;   // 样本太短不可靠
    var perMinute = charsRead / (secondsElapsed / 60);
    if (perMinute < MIN_SPEED || perMinute > MAX_SPEED) return 0;
    return Math.round(perMinute);
}

// 剩余阅读时间（秒）。speed<=0 时用默认速度估算。
function estimatedRemainingSeconds(charsRemaining, speed) {
    if (!charsRemaining || charsRemaining <= 0) return 0;
    var s = (speed && speed > 0) ? speed : DEFAULT_CHARS_PER_MINUTE;
    return Math.round((charsRemaining / s) * 60);
}

// ====== 时长格式化 ======

// 把秒数格式化为紧凑的中文时长，如「1小时23分」「23分」「45秒」
function formatDuration(seconds) {
    if (!seconds || seconds < 0) return "0秒";
    var total = Math.floor(seconds);
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    if (h > 0) {
        return m > 0 ? (h + "小时" + m + "分") : (h + "小时");
    }
    if (m > 0) {
        return s > 0 ? (m + "分" + s + "秒") : (m + "分");
    }
    return s + "秒";
}

// 用于「剩余约 X」的简短形式，不足 1 分钟显示「不到 1 分钟」
function formatRemaining(seconds) {
    if (!seconds || seconds <= 0) return "已读完";
    if (seconds < 60) return "不到 1 分钟";
    return formatDuration(seconds);
}

// ====== 阅读统计 ======

// 由「每本书的阅读记录」汇总统计信息。
// records: [{readingTime: 秒, bookPercent: 0-100, timestamp: 毫秒}, ...]
function summarize(records) {
    var totalSeconds = 0;
    var finished = 0;
    var started = 0;
    var activeDays = {};
    var sessions = 0;

    if (!records) return emptySummary();

    for (var i = 0; i < records.length; i++) {
        var r = records[i];
        if (!r) continue;
        var t = parseInt(r.readingTime) || 0;
        if (t > 0) {
            totalSeconds += t;
            started++;
            sessions++;
            var d = dayKey(r.timestamp);
            if (d !== "") activeDays[d] = true;
        }
        var p = parseInt(r.bookPercent) || 0;
        if (p >= 100) finished++;
    }

    var days = 0;
    for (var k in activeDays) days++;

    return {
        totalSeconds: totalSeconds,
        bookCount: started,
        finishedCount: finished,
        activeDays: days,
        avgSecondsPerDay: days > 0 ? Math.round(totalSeconds / days) : 0,
        avgSecondsPerBook: started > 0 ? Math.round(totalSeconds / started) : 0
    };
}

function emptySummary() {
    return {
        totalSeconds: 0,
        bookCount: 0,
        finishedCount: 0,
        activeDays: 0,
        avgSecondsPerDay: 0,
        avgSecondsPerBook: 0
    };
}

// 把毫秒时间戳转为 YYYY-MM-DD（本地日期），用于统计活跃天数
function dayKey(ms) {
    var t = parseInt(ms);
    if (!t || t <= 0) return "";
    var d = new Date(t);
    var y = d.getFullYear();
    var m = d.getMonth() + 1;
    var day = d.getDate();
    return y + "-" + (m < 10 ? "0" : "") + m + "-" + (day < 10 ? "0" : "") + day;
}
