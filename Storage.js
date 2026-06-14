// Storage.js - 纯 JSON 文件持久化存储

var BACKUP_PATH = "/userdisk/.novel-reader-state.json";
var dataCache = null;   // 内存缓存 {key: value}
var flushPending = false;

// ====== 初始化 ======

function initStorage() {
    loadFileCache();
}

// ====== 文件读写 ======

function loadFileCache() {
    dataCache = {};
    try {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + BACKUP_PATH, false);
        xhr.send();
        if (xhr.status === 200 || xhr.status === 0) {
            var parsed = JSON.parse(xhr.responseText);
            if (parsed && typeof parsed === "object")
                dataCache = parsed;
        }
    } catch (e) {}
}

function flushToFile() {
    var ctrl = getShellCtrl();
    if (!ctrl) return;
    try {
        var json = JSON.stringify(dataCache);
        var b64 = Qt.btoa(json);
        ctrl.sendCommand("echo " + b64 + " | base64 -d > " + BACKUP_PATH + " 2>/dev/null");
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

function updateProgressMemory(progressStore, currentUrl, fileName, currentLine, totalLines) {
    if (currentUrl === "") return;
    progressStore[currentUrl] = {
        file: currentUrl,
        name: fileName,
        line: currentLine,
        totalLines: totalLines,
        timestamp: new Date().getTime()
    };
}

function flushProgressStore(progressStore) {
    writeState("progress", JSON.stringify(progressStore));
}

function loadProgressFromStore(progressStore, url) {
    var item = progressStore[url];
    return item ? (parseInt(item.line) || 0) : 0;
}

function deleteRecord(currentUrl, progressStore) {
    if (currentUrl === "") return false;
    delete progressStore[currentUrl];
    return writeState("progress", JSON.stringify(progressStore));
}
