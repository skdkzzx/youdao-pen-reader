import QtQuick 2.15
import QtQuick.LocalStorage 2.0
import "qrc:/qml/commons"
import "Storage.js" as Storage
import "ReaderUtils.js" as ReaderUtils

Rectangle {
    id: root
    width: 320
    height: 170
    color: bgColor

    signal backButtonClicked

    property string currentUrl: ""
    property string fileName: ""
    property bool isLoading: false
    property string statusMessage: ""
    property var xhr: null
    property int currentRequestId: 0

    property var lines: []
    property int currentLine: 0
    property int charsPerLine: 35
    property var chapterList: []

    property int baseFontSize: 14
    property int lineSpacing: 4
    property string bgColor: "#FFFBF0"
    property string textColor: "#333333"
    property string themeName: "默认"
    property bool autoScroll: false
    property int autoScrollSeconds: 2

    property string activePanel: ""
    property string homeMode: "home"
    property bool keyboardPending: false
    property real pendingProgressRatio: -1
    property var bookList: []
    property var bookmarkList: []
    property var progressStore: ({})
    property var bookmarksStore: ({})
    property string lastFilePath: ""
    property var bookFolderModel: null
    property bool folderScanAvailable: false
    property var uploaderController: (typeof shellPluginController !== "undefined") ? shellPluginController : null
    property bool uploaderStarted: false
    property string uploaderStatus: "上传服务未启动"
    property string uploaderAddress: ""
    property string uploaderOutput: ""
    property var db: null
    property bool showSponsor: false
    property int sponsorQrIndex: 0
    property bool showTutorial: false
    property int tutorialLine: 0
    property var tutorialLines: []
    readonly property string defaultBookFolder: "/userdisk/Music/"
    readonly property string defaultBookSuffix: ".txt"
    readonly property int readerMargin: 6

    FontMetrics {
        id: readerFontMetrics
        font.family: "Microsoft YaHei"
        font.pixelSize: baseFontSize
    }

    Timer {
        id: autoScrollTimer
        interval: Math.max(1, autoScrollSeconds) * 1000
        repeat: true
        running: autoScroll && currentUrl !== "" && activePanel === ""
        onTriggered: nextPage()
    }

    Timer {
        id: uploaderStartTimer
        interval: 700
        repeat: false
        onTriggered: startUploaderService()
    }

    Timer {
        id: uploaderOutputTimer
        interval: 500
        repeat: true
        running: true
        onTriggered: refreshUploaderOutput()
    }

    // 防抖写入定时器：翻页停止 1.5 秒后将进度写入数据库
    Timer {
        id: flushDebounceTimer
        interval: 1500
        repeat: false
        onTriggered: Storage.flushProgressToDB(db, progressStore)
    }

    // 定期持久化保存定时器（每2分钟），兜底确保数据写入
    Timer {
        id: persistTimer
        interval: 120000
        repeat: true
        running: true
        onTriggered: persistState()
    }

    Component.onCompleted: {
        initDatabase();
        uploaderStartTimer.start();
        var everOpened = readState("everOpened", "");
        if (everOpened === "") {
            writeState("everOpened", "1");
            sponsorQrIndex = 0;
            showSponsor = true;
        }
    }

    Component.onDestruction: {
        flushProgress();
        saveSettings();
    }

    function initDatabase() {
        db = Storage.openDatabase();
        loadSettings();
        loadProgressStore();
        loadBookmarksStore();
        startBookFolderScan();
        loadBookList();
    }

    // 定期将所有状态写入 SQLite 数据库
    function persistState() {
        if (currentUrl !== "") {
            Storage.flushProgressToDB(db, progressStore);
        }
        saveSettings();
    }

    function startUploaderService() {
        if (uploaderStarted)
            return;
        uploaderController = (typeof shellPluginController !== "undefined") ? shellPluginController : null;
        if (!uploaderController) {
            uploaderStatus = "上传服务未加载";
            return;
        }

        uploaderStarted = true;
        uploaderStatus = "上传服务启动中";
        uploaderAddress = "";
        uploaderController.startShell();
        uploaderController.sendCommand("sh /userdisk/PenMods/plugins/novel-reader/start-uploader.sh || sh /userdisk/youdaoExt/ext/novel-reader/start-uploader.sh || sh ./start-uploader.sh");
    }

    function stopUploaderService() {
        if (!uploaderStarted)
            return;
        if (uploaderController) {
            uploaderController.sendCommand("kill $(lsof -t -i:8088) 2>/dev/null; pkill -f uploader.py; pkill -f uploader.js; echo '上传服务已停止'");
        }
        uploaderStarted = false;
        uploaderStatus = "上传服务已停止";
        uploaderAddress = "";
    }

    function openShelf() {
        homeMode = "shelf";
        loadBookList();
    }

    function closeShelf() {
        homeMode = "home";
    }

    function openTutorial() {
        tutorialLines = ["【使用教程】", "", "一、小说存放位置", "小说文件请放到：", "/userdisk/Music/", "支持 .txt 格式，文件名随意。", "", "二、打开小说", "1. 自动扫描：把 txt 放到上面的目录后，", "   进入「我的书架」即可看到。", "2. 手动输入：首页点击「手动输入书名」，", "   输入小说名即可，不需要输完整路径。", "", "三、上传小说", "1. 局域网上传（推荐）：", "   点击「启动上传」，首页会显示一个网址，", "   手机/电脑浏览器打开该网址即可上传。", "   手机和词典笔需连接同一个 Wi-Fi。", "2. SSH 上传：", "   用 WinSCP（电脑）或 Termius（手机）", "   通过 SFTP 连接词典笔，", "   把 txt 文件传到 /userdisk/Music/。", "   连接信息：IP:词典笔IP 端口:22", "   用户名:root 密码:PenMods中设置的SSH密码", "", "四、阅读操作", "· 点击屏幕左侧 1/3：上一页", "· 点击屏幕右侧 1/3：下一页", "· 点击屏幕中间 1/3：打开菜单", "· 上下左右滑动：翻页", "", "五、菜单功能", "· 进度条：拖拽快速跳转", "· 字号：小/中/大 三档", "· 行距：紧凑/标准/宽松", "· 主题：7种配色可选", "· 书签：添加/查看/删除书签", "· 跳转：按百分比/页码/章节跳转", "· 自动翻页：可自定义间隔秒数", "· 上一章/下一章：快速切换章节", "", "六、常见问题", "Q: 书架没有显示小说？", "A: 确认文件在 /userdisk/Music/ 且后缀是 .txt", "", "Q: 上传网页打不开？", "A: 确认手机和词典笔在同一 Wi-Fi，", "   并检查词典笔系统是否有 python3 或 node。", "", "Q: 手动输入书名打不开？", "A: 只需输入小说名，如「三体」，", "   不需要输入完整路径。", "", "【以上为全部教程内容】"];
        tutorialLine = 0;
        showTutorial = true;
    }

    function refreshUploaderOutput() {
        if (!uploaderStarted)
            return;
        uploaderController = (typeof shellPluginController !== "undefined") ? shellPluginController : null;
        uploaderOutput = uploaderController ? uploaderController.outputText : "";
        var addr = ReaderUtils.getUploaderUrl(uploaderOutput);
        if (addr) {
            uploaderAddress = addr;
            uploaderStatus = "上传服务已启动";
        } else if (uploaderStarted && uploaderOutput.indexOf("未找到 python3 或 node") >= 0) {
            uploaderStatus = "缺少 python3/node";
        } else if (uploaderStarted && uploaderOutput.indexOf("Address already in use") >= 0) {
            uploaderStatus = "端口已占用";
        }
    }

    function readState(key, fallbackValue) {
        return Storage.readState(db, key, fallbackValue);
    }

    function writeState(key, value) {
        return Storage.writeState(db, key, value);
    }

    function loadProgressStore() {
        progressStore = Storage.loadProgressStore(db);
    }

    function loadBookmarksStore() {
        bookmarksStore = Storage.loadBookmarksStore(db);
    }

    // 翻页时只更新内存，不写数据库（由防抖定时器批量写入）
    function saveProgress() {
        Storage.updateProgressMemory(progressStore, currentUrl, fileName, currentLine, lines.length);
        flushDebounceTimer.restart();
    }

    // 立即将进度写入数据库（关键操作时调用）
    function flushProgress() {
        if (currentUrl === "") return;
        Storage.updateProgressMemory(progressStore, currentUrl, fileName, currentLine, lines.length);
        Storage.flushProgressToDB(db, progressStore);
        flushDebounceTimer.stop();
    }

    function loadProgress(url) {
        return Storage.loadProgressFromStore(progressStore, url);
    }

    function saveSettings() {
        var settings = {
            fontSize: baseFontSize,
            lineSpacing: lineSpacing,
            bgColor: bgColor,
            textColor: textColor,
            themeName: themeName,
            lastFile: lastFilePath,
            autoScrollSeconds: autoScrollSeconds
        };
        Storage.saveSettingsToStore(db, settings);
    }

    function loadSettings() {
        var settings = Storage.loadSettingsFromStore(db);
        baseFontSize = parseInt(settings.fontSize) || 14;
        lineSpacing = parseInt(settings.lineSpacing) || 4;
        bgColor = settings.bgColor || "#FFFBF0";
        textColor = settings.textColor || "#333333";
        themeName = settings.themeName || "默认";
        lastFilePath = settings.lastFile || "";
        if (settings.autoScrollSeconds !== undefined) {
            autoScrollSeconds = ReaderUtils.normalizeAutoScrollSeconds(settings.autoScrollSeconds);
        } else if (settings.autoScrollSpeed !== undefined) {
            var oldSpeed = parseInt(settings.autoScrollSpeed) || 3;
            autoScrollSeconds = ReaderUtils.normalizeAutoScrollSeconds(Math.round(2 / Math.max(1, oldSpeed)));
        } else {
            autoScrollSeconds = 2;
        }
        charsPerLine = ReaderUtils.updateCharsPerLine(baseFontSize);
    }

    function loadBookList() {
        bookList = ReaderUtils.buildBookList(folderScanAvailable, bookFolderModel, progressStore, defaultBookFolder);
    }

    function startBookFolderScan() {
        if (bookFolderModel)
            return;
        try {
            var qml = "import QtQuick 2.15\n" + "import Qt.labs.folderlistmodel 2.1\n" + "FolderListModel {\n" + "    folder: \"file://" + defaultBookFolder + "\"\n" + "    nameFilters: [\"*.txt\", \"*.TXT\"]\n" + "    showDirs: false\n" + "    showFiles: true\n" + "    showDotAndDotDot: false\n" + "    sortField: FolderListModel.Name\n" + "}\n";
            bookFolderModel = Qt.createQmlObject(qml, root, "BookFolderModel");
            bookFolderModel.countChanged.connect(loadBookList);
            folderScanAvailable = true;
            loadBookList();
        } catch (e) {
            bookFolderModel = null;
            folderScanAvailable = false;
        }
    }

    function folderModelFileUrl(index) {
        return ReaderUtils.folderModelFileUrl(bookFolderModel, index, defaultBookFolder);
    }

    function loadBookmarkList() {
        if (currentUrl === "") {
            bookmarkList = [];
            return;
        }
        var items = bookmarksStore[currentUrl] || [];
        items.sort(function (a, b) {
            return (parseInt(a.line) || 0) - (parseInt(b.line) || 0);
        });
        bookmarkList = items;
    }

    function addBookmark() {
        if (currentUrl === "")
            return;
        var preview = lines.length > currentLine ? String(lines[currentLine]).trim() : "";
        if (preview.length > 22)
            preview = preview.substring(0, 22) + "...";

        var items = bookmarksStore[currentUrl] || [];
        items.push({
            id: String(new Date().getTime()) + "_" + String(Math.floor(Math.random() * 10000)),
            file: currentUrl,
            name: fileName,
            line: currentLine,
            percent: getProgressPercent(),
            preview: preview
        });
        bookmarksStore[currentUrl] = items;
        if (writeState("bookmarks", JSON.stringify(bookmarksStore))) {
            loadBookmarkList();
            statusMessage = "已添加书签";
            messageTimer.restart();
        } else {
            statusMessage = "添加书签失败";
            messageTimer.restart();
        }
    }

    function deleteBookmark(id) {
        if (currentUrl === "")
            return;
        var source = bookmarksStore[currentUrl] || [];
        var kept = [];
        for (var i = 0; i < source.length; i++) {
            if (source[i].id !== id)
                kept.push(source[i]);
        }
        bookmarksStore[currentUrl] = kept;
        if (writeState("bookmarks", JSON.stringify(bookmarksStore))) {
            loadBookmarkList();
        } else {
            statusMessage = "删除书签失败";
            messageTimer.restart();
        }
    }

    function deleteCurrentRecord() {
        if (!db || currentUrl === "")
            return;
        if (Storage.deleteRecord(db, currentUrl, progressStore)) {
            statusMessage = "记录已删除";
            messageTimer.restart();
            loadBookList();
        } else {
            statusMessage = "删除记录失败";
            messageTimer.restart();
        }
    }

    function basename(url) {
        return ReaderUtils.basename(url);
    }

    function bookTitle(value) {
        return ReaderUtils.bookTitle(value);
    }

    function stripFilePrefix(url) {
        return ReaderUtils.stripFilePrefix(url);
    }

    function isDefaultBookFile(url) {
        return ReaderUtils.isDefaultBookFile(url);
    }

    function addFilePrefix(path) {
        return ReaderUtils.addFilePrefix(path);
    }

    function normalizeBookInput(text) {
        return ReaderUtils.normalizeBookInput(text, defaultBookFolder, defaultBookSuffix);
    }

    function encodePath(url) {
        return ReaderUtils.encodePath(url);
    }

    function updateCharsPerLine() {
        charsPerLine = ReaderUtils.updateCharsPerLine(baseFontSize);
    }

    function progressFromLine(line, total) {
        return ReaderUtils.progressFromLine(line, total);
    }

    function normalizeAutoScrollSeconds(value) {
        return ReaderUtils.normalizeAutoScrollSeconds(value);
    }

    function getLinesPerPage() {
        var th = getTextLineHeight();
        return ReaderUtils.getLinesPerPage(root.height, readerMargin, th);
    }

    function getTextLineHeight() {
        return ReaderUtils.getTextLineHeight(readerFontMetrics.height, baseFontSize, lineSpacing);
    }

    function maxStartLine() {
        return ReaderUtils.maxStartLine(lines.length, getLinesPerPage());
    }

    function clampCurrentLine() {
        currentLine = ReaderUtils.clampCurrentLine(currentLine, maxStartLine());
    }

    function getProgressPercent() {
        return ReaderUtils.getProgressPercent(currentLine, lines.length);
    }

    function getCurrentPage() {
        return ReaderUtils.getCurrentPage(currentLine, getLinesPerPage());
    }

    function getTotalPages() {
        return ReaderUtils.getTotalPages(lines.length, getLinesPerPage());
    }

    function getPageText() {
        return ReaderUtils.getPageText(lines, currentLine, getLinesPerPage());
    }

    function closePanels() {
        activePanel = "";
    }

    function openPanel(name) {
        activePanel = name;
        if (name === "bookmarks")
            loadBookmarkList();
    }

    function returnToShelf() {
        var oldUrl = currentUrl;
        var oldName = fileName;
        var oldLine = currentLine;
        var oldTotalLines = lines.length;

        // 先保存进度到内存和数据库，再清空状态
        if (oldUrl !== "") {
            progressStore[oldUrl] = {
                file: oldUrl,
                name: oldName || basename(oldUrl),
                line: oldLine,
                totalLines: oldTotalLines,
                timestamp: new Date().getTime()
            };
            writeState("progress", JSON.stringify(progressStore));
        }

        autoScroll = false;
        closePanels();
        homeMode = "shelf";
        currentUrl = "";
        fileName = "";
        lines = [];
        chapterList = [];
        bookmarkList = [];
        currentLine = 0;

        loadBookList();
    }

    function returnToHome() {
        var oldUrl = currentUrl;
        var oldName = fileName;
        var oldLine = currentLine;
        var oldTotalLines = lines.length;

        // 保存当前阅读进度
        if (oldUrl !== "") {
            progressStore[oldUrl] = {
                file: oldUrl,
                name: oldName || basename(oldUrl),
                line: oldLine,
                totalLines: oldTotalLines,
                timestamp: new Date().getTime()
            };
            writeState("progress", JSON.stringify(progressStore));
        }

        autoScroll = false;
        closePanels();
        homeMode = "home";
        currentUrl = "";
        fileName = "";
        lines = [];
        chapterList = [];
        bookmarkList = [];
        currentLine = 0;

        loadBookList();
    }

    function loadFile(url) {
        if (!url)
            return;

        // 先保存当前书籍的阅读进度，避免切换书籍时丢失
        if (currentUrl !== "" && currentUrl !== url) {
            flushProgress();
        }

        if (xhr && xhr.readyState === XMLHttpRequest.LOADING) {
            xhr.abort();
            xhr = null;
        }

        closePanels();
        isLoading = true;
        statusMessage = "";
        currentUrl = url;
        fileName = bookTitle(url);
        lastFilePath = url;

        var encodedUrl = encodePath(url);
        doLoadFile(url, encodedUrl);
    }

    function doLoadFile(originalUrl, requestUrl) {
        var reqId = ++currentRequestId;
        xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (reqId !== currentRequestId)
                return;
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            isLoading = false;
            if (xhr.status === 200 || xhr.status === 0) {
                var content = xhr.responseText || "";
                if (content.length > 0 && content.charCodeAt(0) === 0xFEFF)
                    content = content.substring(1);
                processContent(content);
                if (pendingProgressRatio >= 0) {
                    currentLine = Math.floor(pendingProgressRatio * lines.length);
                    pendingProgressRatio = -1;
                } else {
                    currentLine = loadProgress(originalUrl);
                }
                clampCurrentLine();
                loadBookmarkList();
                saveSettings();
                statusMessage = "";
            } else if (requestUrl !== originalUrl) {
                doLoadFile(originalUrl, originalUrl);
                return;
            } else {
                lines = [];
                chapterList = [];
                currentLine = 0;
                statusMessage = "无法打开文件";
            }
            xhr = null;
        };
        xhr.onerror = function () {
            if (requestUrl !== originalUrl) {
                doLoadFile(originalUrl, originalUrl);
                return;
            }
            isLoading = false;
            lines = [];
            chapterList = [];
            currentLine = 0;
            statusMessage = "无法打开文件";
            xhr = null;
        };
        xhr.open("GET", requestUrl);
        xhr.send();
    }

    function processContent(content) {
        var result = ReaderUtils.processContent(content, charsPerLine);
        lines = result.lines;
        chapterList = result.chapters;
    }

    function nextPage() {
        if (currentLine < maxStartLine()) {
            currentLine = Math.min(currentLine + getLinesPerPage(), maxStartLine());
            saveProgress();
        } else {
            autoScroll = false;
        }
    }

    function prevPage() {
        if (currentLine > 0) {
            currentLine = Math.max(0, currentLine - getLinesPerPage());
            saveProgress();
        }
    }

    function jumpToPercent(percent) {
        if (lines.length === 0)
            return;
        var lpp = getLinesPerPage();
        percent = Math.max(0, Math.min(100, percent));
        currentLine = Math.floor((percent / 100) * lines.length);
        clampCurrentLine();
        currentLine = Math.floor(currentLine / lpp) * lpp;
        saveProgress();
    }

    function jumpToPage(page) {
        var lpp = getLinesPerPage();
        currentLine = (Math.max(1, page) - 1) * lpp;
        clampCurrentLine();
        saveProgress();
    }

    function jumpToChapter(offset) {
        if (chapterList.length === 0)
            return;
        var currentIndex = 0;
        for (var i = 0; i < chapterList.length; i++) {
            if (chapterList[i].lineIndex <= currentLine)
                currentIndex = i;
        }
        var nextIndex = Math.max(0, Math.min(chapterList.length - 1, currentIndex + offset));
        currentLine = chapterList[nextIndex].lineIndex;
        saveProgress();
    }

    function setFontSize(size) {
        var ratio = lines.length > 0 ? currentLine / lines.length : 0;
        baseFontSize = size;
        updateCharsPerLine();
        if (currentUrl !== "") {
            pendingProgressRatio = ratio;
            loadFile(currentUrl);
        }
        saveSettings();
    }

    function setTheme(name) {
        themeName = name;
        var colors = {
            "默认": {
                bg: "#FFFBF0",
                fg: "#333333"
            },
            "白色": {
                bg: "#FFFFFF",
                fg: "#333333"
            },
            "黄色": {
                bg: "#FFF8E1",
                fg: "#5D4037"
            },
            "绿色": {
                bg: "#E8F5E9",
                fg: "#2E7D32"
            },
            "黑色": {
                bg: "#263238",
                fg: "#ECEFF1"
            },
            "粉色": {
                bg: "#FCE4EC",
                fg: "#880E4F"
            },
            "蓝色": {
                bg: "#E3F2FD",
                fg: "#1565C0"
            }
        }[name] || {
            bg: "#FFFBF0",
            fg: "#333333"
        };
        bgColor = colors.bg;
        textColor = colors.fg;
        saveSettings();
    }

    function showKeyboard(initialText, callback) {
        if (keyboardPending)
            return;
        if (typeof qmlGlobal !== "undefined" && qmlGlobal.inputPageShowing)
            return;
        keyboardPending = true;

        try {
            var comp = qmlCreateComponent("YInputPage");
            if (comp.status === Component.Ready) {
                var incubator = comp.incubateObject(pagePopHelper.containerItem);
                if (incubator.status !== Component.Ready) {
                    incubator.onStatusChanged = function (status) {
                        if (status === Component.Ready)
                            setupKeyboard(incubator.object, initialText, callback);
                    };
                } else {
                    setupKeyboard(incubator.object, initialText, callback);
                }
            } else {
                keyboardPending = false;
            }
        } catch (e) {
            keyboardPending = false;
        }
    }

    function setupKeyboard(keyboardPage, initialText, callback) {
        keyboardPage.backButtonClicked.connect(function () {
            if (typeof qmlGlobal !== "undefined")
                qmlGlobal.inputPageShowing = false;
            keyboardPage.todoDestroy();
            keyboardPending = false;
        });
        keyboardPage.inputFinished.connect(function (content) {
            if (typeof qmlGlobal !== "undefined")
                qmlGlobal.inputPageShowing = false;
            keyboardPage.todoDestroy();
            keyboardPending = false;
            if (content !== undefined && callback)
                callback(content);
        });
        keyboardPage.enterText(initialText);
        keyboardPage.show();
        if (typeof qmlGlobal !== "undefined")
            qmlGlobal.inputPageShowing = true;
    }

    Timer {
        id: messageTimer
        interval: 1200
        repeat: false
        onTriggered: statusMessage = ""
    }

    Item {
        id: homePage
        anchors.fill: parent
        visible: currentUrl === ""

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4
            visible: homeMode === "home"

            Text {
                width: parent.width
                text: "电子书阅读器"
                font.pixelSize: 16
                font.bold: true
                color: textColor
                horizontalAlignment: Text.AlignHCenter
                font.family: "Microsoft YaHei"
            }

            Text {
                width: parent.width
                text: uploaderAddress !== "" ? uploaderAddress : "小说请放到 " + defaultBookFolder
                font.pixelSize: 10
                color: uploaderAddress !== "" ? "#1565C0" : textColor
                opacity: uploaderAddress !== "" ? 1.0 : 0.65
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
                font.family: "Microsoft YaHei"
            }

            Text {
                width: parent.width
                text: uploaderAddress !== "" ? "手机/电脑浏览器输入以上网址上传 txt" : uploaderStatus
                font.pixelSize: 9
                color: "#666666"
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.family: "Microsoft YaHei"
            }

            Row {
                width: parent.width
                height: 24
                spacing: 6

                Rectangle {
                    width: (parent.width - 6) / 2
                    height: 24
                    radius: 3
                    color: uploaderStarted ? "#FFEBEE" : "#E3F2FD"
                    border.color: uploaderStarted ? "#EF9A9A" : "#BBDEFB"
                    Text {
                        anchors.centerIn: parent
                        text: uploaderStarted ? "取消上传" : "启动上传"
                        font.pixelSize: 11
                        color: uploaderStarted ? "#D32F2F" : "#1565C0"
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (uploaderStarted) {
                                stopUploaderService();
                            } else {
                                uploaderStarted = false;
                                startUploaderService();
                            }
                        }
                    }
                }

                Rectangle {
                    width: (parent.width - 6) / 2
                    height: 24
                    radius: 3
                    color: "#2f7dcc"
                    Text {
                        anchors.centerIn: parent
                        text: "手动输入书名"
                        font.pixelSize: 11
                        color: "#fff"
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: showKeyboard("", function (text) {
                            var url = normalizeBookInput(text);
                            if (url)
                                loadFile(url);
                        })
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 34
                radius: 4
                color: "#F8F4EC"
                border.color: "#E0D8C8"
                Text {
                    anchors.centerIn: parent
                    text: "我的书架 (" + bookList.length + ")"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#333333"
                    font.family: "Microsoft YaHei"
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: openShelf()
                }
            }

            Row {
                width: parent.width
                height: 28
                spacing: 6

                Rectangle {
                    width: (parent.width - 6) / 2
                    height: 28
                    radius: 4
                    color: "#FFF3E0"
                    border.color: "#FFCC80"
                    Text {
                        anchors.centerIn: parent
                        text: "☕ 赞赏作者"
                        font.pixelSize: 12
                        color: "#E65100"
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            sponsorQrIndex = 0;
                            showSponsor = true;
                        }
                    }
                }

                Rectangle {
                    width: (parent.width - 6) / 2
                    height: 28
                    radius: 4
                    color: "#E8F5E9"
                    border.color: "#A5D6A7"
                    Text {
                        anchors.centerIn: parent
                        text: "QQ群 1040494353"
                        font.pixelSize: 12
                        color: "#2E7D32"
                        font.family: "Microsoft YaHei"
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            visible: homeMode === "shelf"

            Column {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 4

                Row {
                    width: parent.width
                    height: 24
                    spacing: 6

                    Rectangle {
                        width: 58
                        height: 24
                        radius: 4
                        color: "#DDDDDD"
                        Text {
                            anchors.centerIn: parent
                            text: "返回"
                            font.pixelSize: 11
                            color: "#333333"
                            font.family: "Microsoft YaHei"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: closeShelf()
                        }
                    }

                    Text {
                        width: parent.width - 64 - 52
                        height: 24
                        text: "我的书架 (" + bookList.length + ")"
                        font.pixelSize: 14
                        font.bold: true
                        color: textColor
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        font.family: "Microsoft YaHei"
                    }

                    Rectangle {
                        width: 52
                        height: 24
                        radius: 4
                        color: "#E3F2FD"
                        border.color: "#BBDEFB"
                        Text {
                            anchors.centerIn: parent
                            text: "教程"
                            font.pixelSize: 11
                            color: "#1565C0"
                            font.family: "Microsoft YaHei"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: openTutorial()
                        }
                    }
                }

                ListView {
                    width: parent.width
                    height: parent.height - 28
                    clip: true
                    spacing: 3
                    model: bookList
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        width: parent.width
                        height: 24
                        radius: 3
                        color: bookMouse.pressed ? "#E0D8C8" : "#F8F4EC"
                        border.color: "#E0D8C8"

                        MouseArea {
                            id: bookMouse
                            anchors.fill: parent
                            z: 0
                            onClicked: {
                                isLoading = true;
                                statusMessage = "";
                                loadFile(modelData.file);
                            }
                        }

                        Row {
                            z: 1
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 4

                            Text {
                                width: parent.width - 60
                                text: modelData.name
                                font.pixelSize: 11
                                color: "#333"
                                elide: Text.ElideMiddle
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: "Microsoft YaHei"
                            }
                            Text {
                                text: modelData.progress + "%"
                                font.pixelSize: 9
                                color: "#888"
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: "Microsoft YaHei"
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: bookList.length === 0
                        text: "暂无小说\n请将 txt 放到 /userdisk/Music/"
                        font.pixelSize: 11
                        color: textColor
                        opacity: 0.5
                        horizontalAlignment: Text.AlignHCenter
                        font.family: "Microsoft YaHei"
                    }
                }
            }
        }
    }

    Item {
        id: readerPage
        anchors.fill: parent
        visible: currentUrl !== ""

        Text {
            id: contentText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: readerMargin
            anchors.rightMargin: readerMargin
            anchors.topMargin: readerMargin
            anchors.bottomMargin: readerMargin
            text: getPageText()
            font.family: "Microsoft YaHei"
            font.pixelSize: baseFontSize
            lineHeightMode: Text.FixedHeight
            lineHeight: getTextLineHeight()
            color: textColor
            wrapMode: Text.NoWrap
            clip: true
        }

        MouseArea {
            id: pageTouch
            anchors.fill: parent
            enabled: activePanel === "" && !isLoading
            property real startX: 0
            property real startY: 0
            property bool moved: false
            property bool longPressed: false
            pressAndHoldInterval: 800

            onPressed: {
                startX = mouseX;
                startY = mouseY;
                moved = false;
                longPressed = false;
            }

            onPressAndHold: {
                longPressed = true;
                returnToHome();
            }

            onPositionChanged: {
                if (Math.abs(mouseX - startX) > 15 || Math.abs(mouseY - startY) > 15)
                    moved = true;
            }

            onReleased: {
                if (longPressed)
                    return;
                var dx = mouseX - startX;
                var dy = mouseY - startY;
                var dist = Math.sqrt(dx * dx + dy * dy);

                if (moved && dist > 30) {
                    if (Math.abs(dy) > Math.abs(dx)) {
                        if (dy < 0)
                            nextPage();
                        else
                            prevPage();
                    } else {
                        if (dx < 0)
                            nextPage();
                        else
                            prevPage();
                    }
                    return;
                }

                if (mouseX > width / 3 && mouseX < width * 2 / 3)
                    openPanel("menu");
                else if (mouseX < width / 3)
                    prevPage();
                else
                    nextPage();
            }
        }
    }

    Rectangle {
        id: menuPanel
        visible: activePanel === "menu" && currentUrl !== ""
        anchors.fill: parent
        anchors.margins: 8
        radius: 6
        color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
        border.color: "#CCCCCC"
        z: 40

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 5

            Row {
                width: parent.width
                height: 32
                Text {
                    width: parent.width - 38
                    text: fileName
                    font.pixelSize: 12
                    font.bold: true
                    color: textColor
                    elide: Text.ElideMiddle
                    verticalAlignment: Text.AlignVCenter
                    font.family: "Microsoft YaHei"
                }
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: "#DDDDDD"
                    Text {
                        anchors.centerIn: parent
                        text: "x"
                        font.pixelSize: 15
                        color: "#333"
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: closePanels()
                    }
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 37
                contentWidth: width
                contentHeight: menuContent.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: menuContent
                    width: parent.width
                    spacing: 5

                    Text {
                        width: parent.width
                        text: "进度: " + getProgressPercent() + "% (" + getCurrentPage() + "/" + getTotalPages() + "页)"
                        font.pixelSize: 11
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }

                    Rectangle {
                        width: parent.width
                        height: 12
                        radius: 6
                        color: "#CCCCCC"
                        Rectangle {
                            width: parent.width * (getProgressPercent() / 100)
                            height: parent.height
                            radius: 6
                            color: "#2f7dcc"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: jumpToPercent((mouseX / width) * 100)
                        }
                    }

                    Row {
                        spacing: 4
                        Repeater {
                            model: [
                                {
                                    t: "小",
                                    v: 13
                                },
                                {
                                    t: "中",
                                    v: 15
                                },
                                {
                                    t: "大",
                                    v: 18
                                }
                            ]
                            delegate: Rectangle {
                                width: 42
                                height: 20
                                radius: 3
                                color: baseFontSize === modelData.v ? "#2f7dcc" : "#EEEEEE"
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.t
                                    font.pixelSize: 10
                                    color: baseFontSize === modelData.v ? "#fff" : "#333"
                                    font.family: "Microsoft YaHei"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: setFontSize(modelData.v)
                                }
                            }
                        }
                    }

                    Row {
                        spacing: 4
                        Repeater {
                            model: [
                                {
                                    t: "紧凑",
                                    v: 2
                                },
                                {
                                    t: "标准",
                                    v: 4
                                },
                                {
                                    t: "宽松",
                                    v: 6
                                }
                            ]
                            delegate: Rectangle {
                                width: 56
                                height: 20
                                radius: 3
                                color: lineSpacing === modelData.v ? "#2f7dcc" : "#EEEEEE"
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.t
                                    font.pixelSize: 10
                                    color: lineSpacing === modelData.v ? "#fff" : "#333"
                                    font.family: "Microsoft YaHei"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        lineSpacing = modelData.v;
                                        clampCurrentLine();
                                        saveSettings();
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        spacing: 3
                        Repeater {
                            model: [
                                {
                                    n: "默认",
                                    c: "#FFFBF0"
                                },
                                {
                                    n: "白色",
                                    c: "#FFFFFF"
                                },
                                {
                                    n: "黄色",
                                    c: "#FFF8E1"
                                },
                                {
                                    n: "绿色",
                                    c: "#E8F5E9"
                                },
                                {
                                    n: "黑色",
                                    c: "#263238"
                                },
                                {
                                    n: "粉色",
                                    c: "#FCE4EC"
                                },
                                {
                                    n: "蓝色",
                                    c: "#E3F2FD"
                                }
                            ]
                            delegate: Rectangle {
                                width: 28
                                height: 20
                                radius: 3
                                color: modelData.c
                                border.color: themeName === modelData.n ? "#2f7dcc" : "#BBBBBB"
                                border.width: themeName === modelData.n ? 2 : 1
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.n.charAt(0)
                                    font.pixelSize: 9
                                    color: modelData.n === "黑色" ? "#ECEFF1" : "#333"
                                    font.family: "Microsoft YaHei"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: setTheme(modelData.n)
                                }
                            }
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 3
                        rowSpacing: 4
                        columnSpacing: 4

                        MenuButton {
                            label: "返回书架"
                            w: (menuContent.width - 8) / 3
                            onClicked: returnToShelf()
                        }
                        MenuButton {
                            label: "跳转"
                            w: (menuContent.width - 8) / 3
                            onClicked: openPanel("jump")
                        }
                        MenuButton {
                            label: "书签"
                            w: (menuContent.width - 8) / 3
                            onClicked: openPanel("bookmarks")
                        }
                        MenuButton {
                            label: "添加书签"
                            w: (menuContent.width - 8) / 3
                            bg: "#E8F5E9"
                            fg: "#2E7D32"
                            onClicked: addBookmark()
                        }
                        MenuButton {
                            label: autoScroll ? "停止翻页" : "自动翻页"
                            w: (menuContent.width - 8) / 3
                            onClicked: {
                                if (autoScroll)
                                    autoScroll = false;
                                else
                                    openPanel("auto");
                            }
                        }
                        MenuButton {
                            label: "删除记录"
                            w: (menuContent.width - 8) / 3
                            bg: "#FFD0D0"
                            fg: "#D32F2F"
                            onClicked: deleteCurrentRecord()
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 4
                        MenuButton {
                            label: "上一章"
                            w: (menuContent.width - 4) / 2
                            bg: "#E3F2FD"
                            fg: "#1565C0"
                            onClicked: jumpToChapter(-1)
                        }
                        MenuButton {
                            label: "下一章"
                            w: (menuContent.width - 4) / 2
                            bg: "#E3F2FD"
                            fg: "#1565C0"
                            onClicked: jumpToChapter(1)
                        }
                    }

                    // 底部边距
                    Item { width: parent.width; height: 10 }
                }
            }
        }
    }

    Rectangle {
        visible: activePanel === "jump"
        anchors.fill: parent
        anchors.margins: 10
        radius: 6
        color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
        border.color: "#CCCCCC"
        z: 50

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            Row {
                width: parent.width
                height: 32
                Text {
                    width: parent.width - 38
                    text: "跳转到"
                    font.pixelSize: 13
                    font.bold: true
                    color: textColor
                    verticalAlignment: Text.AlignVCenter
                    font.family: "Microsoft YaHei"
                }
                MenuButton {
                    label: "x"
                    w: 32
                    h: 32
                    onClicked: closePanels()
                }
            }

            Text {
                width: parent.width
                text: "第" + getCurrentPage() + "页 / 共" + getTotalPages() + "页 (" + getProgressPercent() + "%)"
                font.pixelSize: 10
                color: textColor
                font.family: "Microsoft YaHei"
            }

            Row {
                spacing: 4
                Repeater {
                    model: [
                        {
                            t: "0%",
                            v: 0
                        },
                        {
                            t: "25%",
                            v: 25
                        },
                        {
                            t: "50%",
                            v: 50
                        },
                        {
                            t: "75%",
                            v: 75
                        },
                        {
                            t: "100%",
                            v: 100
                        }
                    ]
                    delegate: MenuButton {
                        label: modelData.t
                        w: 42
                        h: 21
                        bg: "#2f7dcc"
                        fg: "#fff"
                        onClicked: {
                            jumpToPercent(modelData.v);
                            closePanels();
                        }
                    }
                }
            }

            ListView {
                width: parent.width
                height: 44
                clip: true
                spacing: 2
                visible: chapterList.length > 0
                model: chapterList

                delegate: Rectangle {
                    width: parent.width
                    height: 20
                    radius: 2
                    color: chapterMouse.pressed ? "#E0D8C8" : "#F5F0E8"
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.title
                        font.pixelSize: 10
                        color: "#333"
                        elide: Text.ElideRight
                        width: parent.width - 8
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        id: chapterMouse
                        anchors.fill: parent
                        onClicked: {
                            currentLine = modelData.lineIndex;
                            saveProgress();
                            closePanels();
                        }
                    }
                }
            }

            Row {
                spacing: 6
                MenuButton {
                    label: "输入页数"
                    w: 70
                    h: 22
                    onClicked: {
                        activePanel = "";
                        showKeyboard(String(getCurrentPage()), function (text) {
                            var page = parseInt(text);
                            if (!isNaN(page))
                                jumpToPage(page);
                        });
                    }
                }
                MenuButton {
                    label: "输入百分比"
                    w: 78
                    h: 22
                    onClicked: {
                        activePanel = "";
                        showKeyboard(String(getProgressPercent()), function (text) {
                            var percent = parseInt(text);
                            if (!isNaN(percent))
                                jumpToPercent(percent);
                        });
                    }
                }
                MenuButton {
                    label: "关闭"
                    w: 50
                    h: 22
                    onClicked: closePanels()
                }
            }
        }
    }

    Rectangle {
        visible: activePanel === "bookmarks"
        anchors.fill: parent
        anchors.margins: 10
        radius: 6
        color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
        border.color: "#CCCCCC"
        z: 50

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 5

            Row {
                width: parent.width
                height: 32
                Text {
                    width: parent.width - 38
                    text: "书签 (" + bookmarkList.length + ")"
                    font.pixelSize: 13
                    font.bold: true
                    color: textColor
                    verticalAlignment: Text.AlignVCenter
                    font.family: "Microsoft YaHei"
                }
                MenuButton {
                    label: "x"
                    w: 32
                    h: 32
                    onClicked: closePanels()
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#EEEEEE"
            }

            ListView {
                width: parent.width
                height: parent.height - 43
                clip: true
                spacing: 4
                model: bookmarkList

                delegate: Rectangle {
                    width: parent.width
                    height: 36
                    radius: 4
                    color: bmMouse.pressed ? "#E0D8C8" : "#F5F0E8"
                    border.color: "#DDDDDD"

                    MouseArea {
                        id: bmMouse
                        anchors.fill: parent
                        z: 0
                        onClicked: {
                            currentLine = modelData.line;
                            clampCurrentLine();
                            saveProgress();
                            closePanels();
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: deleteButton.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "书签 " + (index + 1) + " - 第" + (Math.floor(modelData.line / getLinesPerPage()) + 1) + "页"
                            font.pixelSize: 11
                            color: "#333"
                            font.family: "Microsoft YaHei"
                        }
                        Text {
                            width: parent.width
                            text: modelData.preview || "..."
                            font.pixelSize: 9
                            color: "#888"
                            elide: Text.ElideRight
                            font.family: "Microsoft YaHei"
                        }
                    }

                    Rectangle {
                        id: deleteButton
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        radius: 12
                        color: "#D9534F"
                        z: 2
                        Text {
                            anchors.centerIn: parent
                            text: "x"
                            font.pixelSize: 13
                            color: "#fff"
                            font.family: "Microsoft YaHei"
                        }
                        MouseArea {
                            anchors.fill: parent
                            z: 3
                            onClicked: deleteBookmark(modelData.id)
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: bookmarkList.length === 0
                    text: "暂无书签\n阅读时点击「添加书签」"
                    font.pixelSize: 11
                    color: textColor
                    opacity: 0.5
                    horizontalAlignment: Text.AlignHCenter
                    font.family: "Microsoft YaHei"
                }
            }
        }
    }

    Rectangle {
        visible: activePanel === "auto"
        anchors.fill: parent
        anchors.margins: 25
        radius: 6
        color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
        border.color: "#CCCCCC"
        z: 50

        Column {
            anchors.centerIn: parent
            spacing: 9
            width: parent.width - 16

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "自动翻页"
                font.pixelSize: 14
                font.bold: true
                color: textColor
                font.family: "Microsoft YaHei"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "间隔: " + autoScrollSeconds + " 秒/页"
                font.pixelSize: 11
                color: textColor
                font.family: "Microsoft YaHei"
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                MenuButton {
                    label: "输入秒数"
                    w: 86
                    h: 24
                    bg: "#E3F2FD"
                    fg: "#1565C0"
                    onClicked: {
                        activePanel = "";
                        showKeyboard(String(autoScrollSeconds), function (text) {
                            autoScrollSeconds = normalizeAutoScrollSeconds(text);
                            saveSettings();
                            openPanel("auto");
                        });
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                MenuButton {
                    label: "开始"
                    w: 76
                    h: 26
                    bg: "#2f7dcc"
                    fg: "#fff"
                    onClicked: {
                        autoScroll = true;
                        closePanels();
                    }
                }
                MenuButton {
                    label: "取消"
                    w: 76
                    h: 26
                    onClicked: closePanels()
                }
            }
        }
    }

    TutorialPage {
        id: tutorialOverlay
        visible: showTutorial
        pageLines: tutorialLines
        pageLine: tutorialLine
        z: 80
        onCloseClicked: showTutorial = false
    }

    Rectangle {
        visible: isLoading
        anchors.centerIn: parent
        width: 84
        height: 24
        radius: 4
        color: "#FFFFFF"
        border.color: "#DDDDDD"
        z: 100
        Text {
            anchors.centerIn: parent
            text: "加载中..."
            font.pixelSize: 11
            color: "#333"
            font.family: "Microsoft YaHei"
        }
    }

    Text {
        anchors.centerIn: parent
        visible: statusMessage !== "" && !isLoading
        text: statusMessage
        font.pixelSize: 13
        color: "#D32F2F"
        z: 100
        font.family: "Microsoft YaHei"
    }

    SponsorDialog {
        id: sponsorOverlay
        visible: showSponsor
        sponsorQrIndex: sponsorQrIndex
        z: 110
        onCloseClicked: showSponsor = false
        onQrClicked: sponsorQrIndex = sponsorQrIndex === 0 ? 1 : 0
    }

    YPagePopHelper {
        id: pagePopHelper
        z: 99
        property var containerItem: this
        isShowing: typeof qmlGlobal !== "undefined" ? qmlGlobal.inputPageShowing : false
    }
}
