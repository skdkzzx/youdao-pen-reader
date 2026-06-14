// Storage.js - 数据库与持久化存储逻辑
.pragma library

function openDatabase() {
    try {
        var db = Qt.openDatabaseSync("NovelReaderStateV2", "1.0", "Novel Reader State", 1000000);
        db.transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, value TEXT)");
        });
        return db;
    } catch (e) {
        return null;
    }
}

function readState(db, key, fallbackValue) {
    if (!db) return fallbackValue;
    var result = fallbackValue;
    try {
        db.transaction(function (tx) {
            var rs = tx.executeSql("SELECT value FROM state WHERE key = ?", [key]);
            if (rs.rows.length > 0) result = rs.rows.item(0).value;
        });
    } catch (e) {
        result = fallbackValue;
    }
    return result;
}

function writeState(db, key, value) {
    if (!db) return false;
    try {
        db.transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, value TEXT)");
            tx.executeSql("INSERT OR REPLACE INTO state(key, value) VALUES(?, ?)", [key, value]);
        });
        return true;
    } catch (e) {
        return false;
    }
}

function loadProgressStore(db) {
    try {
        return JSON.parse(readState(db, "progress", "{}")) || {};
    } catch (e) {
        return {};
    }
}

function loadBookmarksStore(db) {
    try {
        return JSON.parse(readState(db, "bookmarks", "{}")) || {};
    } catch (e) {
        return {};
    }
}

function saveProgressToStore(db, currentUrl, fileName, currentLine, lines, progressStore) {
    if (!db || currentUrl === "") return;
    progressStore[currentUrl] = {
        file: currentUrl,
        name: fileName,
        line: currentLine,
        totalLines: lines.length,
        timestamp: new Date().getTime()
    };
    writeState(db, "progress", JSON.stringify(progressStore));
}

function loadProgressFromStore(progressStore, url) {
    var item = progressStore[url];
    return item ? (parseInt(item.line) || 0) : 0;
}

function saveSettingsToStore(db, settings) {
    writeState(db, "settings", JSON.stringify(settings));
}

function loadSettingsFromStore(db) {
    var settings = {};
    try {
        settings = JSON.parse(readState(db, "settings", "{}")) || {};
    } catch (e) {
        settings = {};
    }
    return settings;
}

function deleteRecord(db, currentUrl, progressStore) {
    if (!db || currentUrl === "") return false;
    delete progressStore[currentUrl];
    return writeState(db, "progress", JSON.stringify(progressStore));
}
