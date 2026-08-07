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

        // 写主位置
        ctrl.sendCommand("printf '%s' '" + safeB64 + "' | base64 -d > " + BACKUP_PATH + ".tmp 2>/dev/null");
        ctrl.sendCommand("[ -s " + BACKUP_PATH + ".tmp ] && mv " + BACKUP_PATH + ".tmp " + BACKUP_PATH + " 2>/dev/null || rm -f " + BACKUP_PATH + ".tmp");

        // 写备份位置
        ctrl.sendCommand("printf '%s' '" + safeB64 + "' | base64 -d > " + BACKUP_PATH2 + ".tmp 2>/dev/null");
        ctrl.sendCommand("[ -s " + BACKUP_PATH2 + ".tmp ] && mv " + BACKUP_PATH2 + ".tmp " + BACKUP_PATH2 + " 2>/dev/null || rm -f " + BACKUP_PATH2 + ".tmp");

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

function updateProgressMemory(progressStore, currentUrl, fileName, currentLine, totalLines, chapterIdx, bookPercent) {
    if (currentUrl === "") return;
    progressStore[currentUrl] = {
        file: currentUrl,
        name: fileName,
        line: currentLine,
        totalLines: totalLines,
        chapterIdx: chapterIdx !== undefined ? chapterIdx : 0,
        bookPercent: bookPercent !== undefined ? bookPercent : 0,
        timestamp: new Date().getTime()
    };
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
    if (item && parseInt(item.chapterIdx) === chapterIdx) {
        return parseInt(item.line) || 0;
    }
    return 0;
}

function deleteRecord(currentUrl, progressStore) {
    if (currentUrl === "") return false;
    delete progressStore[currentUrl];
    return writeState("progress", JSON.stringify(progressStore));
}
