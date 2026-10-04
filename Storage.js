// Storage.js - 纯 JSON 文件持久化存储（v2 - 修复 Unicode 与数据丢失问题）

var BACKUP_PATH = "/userdisk/.novel-reader-state.json";
var BACKUP_PATH2 = "/userdisk/PenMods/plugins/novel-reader/.state-backup.json";
var dataCache = null;       // 内存缓存 {key: value}
var lastKnownGoodCache = {}; // 上次成功写入的缓存副本（损坏时恢复用）
var flushPending = false;

// ====== 初始化 ======

function initStorage() {
    loadFileCache();
}

// ====== 安全的 Base64 编解码（支持中文/Emoji） ======

function utf8ToBase64(str) {
    try {
        // UTF-16 → UTF-8 字节序列 → Latin1 字符串 → base64
        return Qt.btoa(unescape(encodeURIComponent(str)));
    } catch (e) {
        return "";
    }
}

function base64ToUtf8(str) {
    try {
        return decodeURIComponent(escape(Qt.atob(str)));
    } catch (e) {
        return null;
    }
}

// ====== 文件读写（带完整性校验） ======

function loadFileCache() {
    var loaded = false;
    var candidates = [BACKUP_PATH, BACKUP_PATH2];

    for (var c = 0; c < candidates.length; c++) {
        try {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "file://" + candidates[c], false);
            xhr.send();
            if (xhr.status === 200 || xhr.status === 0) {
                var text = xhr.responseText || "";
                if (text.length < 2) continue; // 空文件跳过

                var parsed = JSON.parse(text);
                if (parsed && typeof parsed === "object") {
                    // 完整性校验：至少要有 progress 或 settings 字段之一
                    if (parsed.hasOwnProperty("progress") || parsed.hasOwnProperty("settings") || parsed.hasOwnProperty("bookmarks")) {
                        dataCache = parsed;
                        lastKnownGoodCache = JSON.parse(JSON.stringify(parsed)); // 深拷贝备份
                        loaded = true;
                        break;
                    }
                }
            }
        } catch (e) {}
    }

    if (!loaded) {
        // 两个文件都损坏 → 用上次已知的完好数据，而不是空对象
        if (lastKnownGoodCache && Object.keys(lastKnownGoodCache).length > 0) {
            dataCache = JSON.parse(JSON.stringify(lastKnownGoodCache));
        } else {
            dataCache = {};
        }
    }
}

function flushToFile() {
    var ctrl = getShellCtrl();
    if (!ctrl) return false;

    try {
        var json = JSON.stringify(dataCache);
        if (json === "{}") {
            // 空数据不写入，防止覆盖有效数据
            return false;
        }

        var b64 = utf8ToBase64(json);
        if (!b64 || b64.length === 0) {
            return false;
        }

        // 安全转义单引号
        var safeB64 = b64.replace(/'/g, "'\\''");

        // 修复：原实现把「写 tmp」与「mv tmp」拆成两条 sendCommand 调用。
        // sendCommand 是异步且无返回确认的，两条命令之间的执行顺序没有保证，
        // 可能出现 tmp 尚未写完就被 mv / 被后一条的 rm 删除的情况；
        // 紧随其后的同步 XHR 校验因此读到旧内容，flushToFile 误判失败并
        // 丢弃本次写入（表现为「添加书签失败」、进度不落盘）。
        // 现将每个写入位置合并为单条命令，用 && 串联保证顺序。
        var writeOne = function (target) {
            ctrl.sendCommand(
                "printf '%s' '" + safeB64 + "' | base64 -d > " + target + ".tmp 2>/dev/null"
                + " && [ -s " + target + ".tmp ]"
                + " && mv -f " + target + ".tmp " + target + " 2>/dev/null"
                + " || rm -f " + target + ".tmp 2>/dev/null");
        };

        writeOne(BACKUP_PATH);
        writeOne(BACKUP_PATH2);

        // 验证主文件是否写入成功
        var verifyXhr = new XMLHttpRequest();
        verifyXhr.open("GET", "file://" + BACKUP_PATH, false);
        verifyXhr.send();
        if (verifyXhr.status === 200 || verifyXhr.status === 0) {
            var verifyText = verifyXhr.responseText || "";
            if (verifyText.length > 2) {
                lastKnownGoodCache = JSON.parse(JSON.stringify(dataCache));
                return true;
            }
        }
        return false;
    } catch (e) {
        return false;
    }
}

function getShellCtrl() {
    return (typeof shellPluginController !== "undefined") ? shellPluginController : null;
}

// ====== 键值读写（内存缓存 + 文件持久化） ======

function readState(key, fallbackValue) {
    if (dataCache === null) loadFileCache();
    return dataCache.hasOwnProperty(key) ? dataCache[key] : fallbackValue;
}

function writeState(key, value) {
    if (dataCache === null) loadFileCache();
    dataCache[key] = value;
    return flushToFile();
}

// ====== 进度/书签/设置 读写 ======

function loadProgressStore() {
    try {
        return JSON.parse(readState("progress", "{}")) || {};
    } catch (e) {
        return {};
    }
}

function loadBookmarksStore() {
    try {
        return JSON.parse(readState("bookmarks", "{}")) || {};
    } catch (e) {
        return {};
    }
}

function loadSettingsFromStore() {
    var settings = {};
    try {
        settings = JSON.parse(readState("settings", "{}")) || {};
    } catch (e) {
        settings = {};
    }
    return settings;
}

function saveSettingsToStore(settings) {
    writeState("settings", JSON.stringify(settings));
}

// 记录某本书「每章」的阅读位置。
// 修复：原实现整本书只保存一个 chapterIdx + line，换章后回到旧章节时
// 因 chapterIdx 不匹配而一律从第 0 行开始，等于丢失该章进度。
// 现按 url + chapterIdx 分别保存，同时保留顶层字段兼容旧数据。
function updateProgressMemory(progressStore, currentUrl, fileName, currentLine, totalLines, chapterIdx, bookPercent, readingTime) {
    if (currentUrl === "") return;
    var idx = chapterIdx !== undefined ? chapterIdx : 0;
    var prev = progressStore[currentUrl] || {};
    var chapters = prev.chapters || {};
    chapters[String(idx)] = currentLine;
    var rec = {
        file: currentUrl,
        name: fileName,
        line: currentLine,
        totalLines: totalLines,
        chapterIdx: idx,
        chapters: chapters,
        bookPercent: bookPercent !== undefined ? bookPercent : 0,
        timestamp: new Date().getTime()
    };
    // 修复：本函数会整体重建记录对象，此前未保留 readingTime，
    // 导致 periodicSaveTimer（阅读时每 5 秒）一触发就把阅读时长抹掉，
    // 时长显示在 flushProgress 与定时保存之间反复跳变。
    // 现沿用既有 readingTime，仅在调用方显式传入时覆盖。
    if (readingTime !== undefined && readingTime !== null) {
        rec.readingTime = readingTime;
    } else if (prev.readingTime !== undefined) {
        rec.readingTime = prev.readingTime;
    }
    progressStore[currentUrl] = rec;
}

function flushProgressStore(progressStore) {
    return writeState("progress", JSON.stringify(progressStore));
}

function loadProgressFromStore(progressStore, url) {
    var item = progressStore[url];
    return item ? item : null;
}

function loadChapterProgress(progressStore, url, chapterIdx) {
    var item = progressStore[url];
    if (!item) return 0;
    // 优先读取该章的独立记录
    if (item.chapters && item.chapters[String(chapterIdx)] !== undefined) {
        return parseInt(item.chapters[String(chapterIdx)]) || 0;
    }
    // 兼容旧数据：仅当章节号吻合时才复用顶层 line
    if (parseInt(item.chapterIdx) === chapterIdx) {
        return parseInt(item.line) || 0;
    }
    return 0;
}

function deleteRecord(currentUrl, progressStore) {
    if (currentUrl === "") return false;
    delete progressStore[currentUrl];
    return writeState("progress", JSON.stringify(progressStore));
}

// 重命名书籍时把进度与书签迁移到新路径键上，并清理旧键。
// 不迁移会导致「改名后进度归零、书签丢失」。
function renameRecord(oldUrl, newUrl, progressStore, bookmarksStore) {
    if (oldUrl === "" || newUrl === "" || oldUrl === newUrl) return false;
    var moved = false;
    if (progressStore[oldUrl] !== undefined) {
        var rec = progressStore[oldUrl];
        rec.file = newUrl;
        progressStore[newUrl] = rec;
        delete progressStore[oldUrl];
        moved = true;
    }
    if (bookmarksStore && bookmarksStore[oldUrl] !== undefined) {
        var items = bookmarksStore[oldUrl] || [];
        for (var i = 0; i < items.length; i++) items[i].file = newUrl;
        bookmarksStore[newUrl] = items;
        delete bookmarksStore[oldUrl];
        moved = true;
    }
    return moved;
}

// 删除文件时同时清理其进度与书签，避免状态文件持续膨胀
function purgeRecord(url, progressStore, bookmarksStore) {
    if (url === "") return false;
    var removed = false;
    if (progressStore[url] !== undefined) { delete progressStore[url]; removed = true; }
    if (bookmarksStore && bookmarksStore[url] !== undefined) { delete bookmarksStore[url]; removed = true; }
    return removed;
}
