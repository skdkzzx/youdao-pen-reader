// Storage.js - 纯 JSON 文件持久化存储

var BACKUP_PATH = "/userdisk/.novel-reader-state.json";
var BACKUP_PATH2 = "/userdisk/PenMods/plugins/novel-reader/.state-backup.json";
var dataCache = null;   // 内存缓存 {key: value}
var flushPending = false;

// ====== 初始化 ======

function initStorage() {
    loadFileCache();
}

// ====== 文件读写 ======

function loadFileCache() {
    dataCache = {};
    var loaded = false;

    // 尝试主位置
    try {
        var xhr1 = new XMLHttpRequest();
        xhr1.open("GET", "file://" + BACKUP_PATH, false);
        xhr1.send();
        if (xhr1.status === 200 || xhr1.status === 0) {
            var parsed1 = JSON.parse(xhr1.responseText);
            if (parsed1 && typeof parsed1 === "object") {
                dataCache = parsed1;
                loaded = true;
            }
        }
    } catch (e) {}

    // 主位置读取失败 → 尝试备份
    if (!loaded) {
        try {
            var xhr2 = new XMLHttpRequest();
            xhr2.open("GET", "file://" + BACKUP_PATH2, false);
            xhr2.send();
            if (xhr2.status === 200 || xhr2.status === 0) {
                var parsed2 = JSON.parse(xhr2.responseText);
                if (parsed2 && typeof parsed2 === "object") {
                    dataCache = parsed2;
                    loaded = true;
                }
            }
        } catch (e2) {}
    }
}

function flushToFile() {
    var ctrl = getShellCtrl();
    if (!ctrl) return;
    try {
        var json = JSON.stringify(dataCache);
        var b64 = Qt.btoa(json);
        // 分两步：写临时文件 + mv 重命名（原子替换防损坏）
        // printf 比 echo 更可靠，不受数据长度限制
        ctrl.sendCommand("printf '%s' '" + b64.replace(/'/g, "'\\''") + "' | base64 -d > " + BACKUP_PATH + ".tmp 2>/dev/null");
        ctrl.sendCommand("mv " + BACKUP_PATH + ".tmp " + BACKUP_PATH + " 2>/dev/null");
        ctrl.sendCommand("printf '%s' '" + b64.replace(/'/g, "'\\''") + "' | base64 -d > " + BACKUP_PATH2 + ".tmp 2>/dev/null");
        ctrl.sendCommand("mv " + BACKUP_PATH2 + ".tmp " + BACKUP_PATH2 + " 2>/dev/null");
    } catch (e) {}
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
    flushToFile();
    return true;
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
    writeState("progress", JSON.stringify(progressStore));
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
