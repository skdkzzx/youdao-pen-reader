import QtQuick 2.15
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

    property var lines: []           // 当前章节的换行后文本
    property var rawLines: []         // 原始文本行（全部）
    property var chapterBoundaries: [] // [{title, startRaw, endRaw}]
    property int currentChapterIdx: -1
    property int currentLine: 0
    property int charsPerLine: 35
    property var chapterList: []

    property int baseFontSize: 15
    property int lineSpacing: 4
    property string bgColor: "#FFFBF0"
    property string textColor: "#333333"
    property string themeName: "默认"
    property bool autoScroll: false
    property int autoScrollSeconds: 2
    property bool animating: false
    property int turnDirection: 0
    property int pendingLine: -1

    // ====== 页面管理器 ======
    property var pageStack: ["home"]       // 导航历史栈
    property string pageMode: "home"       // 当前页面: home | shelf | reader
    property bool isTransitioning: false   // 过渡动画进行中
    property string prevPageMode: "home"   // 上一页面（用于反向动画）

    // 统一页面导航（自动判断是否需要动画）
    function navigateTo(page, direction) {
        if (isTransitioning || page === pageMode)
            return;
        if (page === "reader" && currentUrl === "")
            return;
        var from = pageItem(pageMode);
        var to = pageItem(page);
        prevPageMode = pageMode;
        pageStack.push(page);
        pageMode = page;
        isTransitioning = true;
        startPageTransition(prevPageMode, page, direction || 1);
    }

    // 返回上一页
    function navigateBack() {
        if (isTransitioning || pageStack.length <= 1)
            return;
        pageStack.pop();
        var from = pageItem(pageMode);
        prevPageMode = pageMode;
        var prev = pageStack[pageStack.length - 1];
        var to = pageItem(prev);
        pageMode = prev;
        if (from === to)
            return;
        isTransitioning = true;
        startPageTransition(prevPageMode, prev, -1);
    }

    // 回到栈底（首页），跳过相同物理页
    function navigateRoot() {
        if (isTransitioning)
            return;
        var rootPage = pageStack[0];
        var from = pageItem(pageMode);
        var to = pageItem(rootPage);
        while (pageStack.length > 1)
            pageStack.pop();
        prevPageMode = pageMode;
        pageMode = rootPage;
        if (from === to)
            return;
        isTransitioning = true;
        startPageTransition(prevPageMode, rootPage, -1);
    }

    // 获取页面 Item 引用
    function pageItem(mode) {
        if (mode === "home")
            return homePage;
        if (mode === "shelf")
            return shelfPage;
        if (mode === "reader")
            return readerPage;
        return null;
    }

    property string activePanel: ""
    property bool keyboardPending: false
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
    property bool showSponsor: false
    property int sponsorQrIndex: 0
    property bool showTutorial: false
    property int tutorialLine: 0
    property var tutorialLines: []
    property bool _ipQueried: false
    property int _uploadRetry: 0
    // 章节加载相关（不再需要分块处理）

    // ====== 滚动模式 ======
    property bool scrollMode: false
    property real scrollOffset: 0
    property real scrollMax: 0

    // ====== Toast ======
    property string toastMessage: ""
    property bool showNextChapter: false   // 是否显示"下一章"按钮

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
        running: autoScroll && pageMode === "reader" && activePanel === "" && !scrollMode
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

    // 防抖写入定时器：翻页停止 1.5 秒后将进度写入文件
    Timer {
        id: flushDebounceTimer
        interval: 1500
        repeat: false
        onTriggered: Storage.flushProgressStore(progressStore)
    }

    // ====== 页面过渡动画 ======
    // 用于主页/书架/阅读器之间的滑动切换
    ParallelAnimation {
        id: pageTransitionAnim
        property Item fromItem: null
        property Item toItem: null
        property int direction: 1  // 1=前进(左滑), -1=后退(右滑)

        NumberAnimation {
            target: pageTransitionAnim.fromItem
            property: "x"
            from: 0
            to: 0
            duration: 260
            easing.type: Easing.InOutCubic
        }
        NumberAnimation {
            target: pageTransitionAnim.fromItem
            property: "opacity"
            from: 1
            to: 0
            duration: 220
        }
        NumberAnimation {
            target: pageTransitionAnim.toItem
            property: "x"
            from: 0
            to: 0
            duration: 260
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: pageTransitionAnim.toItem
            property: "opacity"
            from: 0
            to: 1
            duration: 220
        }

        onStarted: {
            if (!fromItem || !toItem) {
                isTransitioning = false;
                stop();
                return;
            }
            // 设置起始位置
            fromItem.x = 0;
            fromItem.opacity = 1;
            fromItem.visible = true;
            toItem.visible = true;

            var d = pageTransitionAnim.direction;
            pageTransitionAnim.toItem.x = d * fromItem.width;

            // 目标位置
            pageTransitionAnim.fromItem.x = -d * fromItem.width * 0.3;
            pageTransitionAnim.toItem.x = 0;
        }

        onFinished: {
            if (fromItem) {
                fromItem.visible = false;
                fromItem.x = 0;
            }
            if (toItem) {
                toItem.opacity = 1;
                toItem.x = 0;
            }
            isTransitioning = false;
        }
    }

    function startPageTransition(fromMode, toMode, dir) {
        var from = pageItem(fromMode);
        var to = pageItem(toMode);
        if (!from || !to) {
            if (from)
                from.visible = false;
            if (to)
                to.visible = true;
            isTransitioning = false;
            return;
        }
        pageTransitionAnim.fromItem = from;
        pageTransitionAnim.toItem = to;
        pageTransitionAnim.direction = dir;
        pageTransitionAnim.restart();
    }

    Component.onCompleted: {
        Storage.initStorage();
        uploaderStartTimer.start();
        loadSettings();
        loadProgressStore();
        loadBookmarksStore();
        startBookFolderScan();
        loadBookList();
        var everOpened = readState("everOpened", "");
        if (everOpened === "") {
            writeState("everOpened", "1");
            sponsorQrIndex = 0;
            showSponsor = true;
        }
    }

    Component.onDestruction: {
        // 不依赖 currentUrl——returnToShelf 已清空，但 progressStore 内存中仍有正确数据
        if (currentUrl !== "" && lines.length > 0) {
            Storage.updateProgressMemory(progressStore, currentUrl, fileName, currentLine, lines.length);
        }
        // 始终刷一遍 progressStore——里面保存的是最后一次完整保存的进度
        Storage.flushProgressStore(progressStore);
        saveSettings();
    }

    function _readLog(path) {
        try {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "file://" + path, false);
            xhr.send();
            if (xhr.status === 200 || xhr.status === 0)
                return xhr.responseText || "";
        } catch (e) {}
        return "";
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
        _ipQueried = false;
        _uploadRetry = 0;
        uploaderController.sendCommand("rm -f /tmp/novel-uploader.log 2>/dev/null; echo ''");
        uploaderController.sendCommand("sh /userdisk/PenMods/plugins/novel-reader/start-uploader.sh >/tmp/novel-uploader.log 2>&1 &");
    }

    function stopUploaderService() {
        if (!uploaderStarted)
            return;
        if (uploaderController) {
            uploaderController.sendCommand("fuser -k 8088/tcp 2>/dev/null || kill $(fuser 8088/tcp 2>/dev/null) 2>/dev/null || pkill -f 'uploader\.py\|uploader\.js' 2>/dev/null; echo ''");
        }
        uploaderStarted = false;
        uploaderStatus = "上传服务已停止";
        uploaderAddress = "";
    }

    function openShelf() {
        navigateTo("shelf");
        loadBookList();
    }

    function closeShelf() {
        navigateBack();
    }

    function openTutorial() {
        tutorialLines = ["【使用教程】", "", "一、小说存放位置", "小说文件请放到：", "/userdisk/Music/", "支持 .txt 格式，文件名随意。", "", "二、打开小说", "1. 自动扫描：把 txt 放到上面的目录后，", "   进入「我的书架」即可看到。", "2. 手动输入：首页点击「手动输入书名」，", "   输入小说名即可，不需要输完整路径。", "", "三、上传小说", "1. 局域网上传（推荐）：", "   点击「启动上传」，首页会显示一个网址，", "   手机/电脑浏览器打开该网址即可上传。", "   手机和词典笔需连接同一个 Wi-Fi。", "2. SSH 上传：", "   用 WinSCP（电脑）或 Termius（手机）", "   通过 SFTP 连接词典笔，", "   把 txt 文件传到 /userdisk/Music/。", "   连接信息：IP:词典笔IP 端口:22", "   用户名:root 密码:PenMods中设置的SSH密码", "", "四、阅读操作", "· 点击屏幕左侧 1/3：上一页", "· 点击屏幕右侧 1/3：下一页", "· 点击屏幕中间 1/3：打开菜单", "· 上下左右滑动：翻页", "", "五、菜单功能", "· 进度条：拖拽快速跳转", "· 字号：小/中/大 三档", "· 行距：紧凑/标准/宽松", "· 主题：7种配色可选", "· 书签：添加/查看/删除书签", "· 跳转：按百分比/页码/章节跳转", "· 自动翻页：可自定义间隔秒数", "· 上一章/下一章：快速切换章节", "", "六、常见问题", "Q: 书架没有显示小说？", "A: 确认文件在 /userdisk/Music/ 且后缀是 .txt", "", "Q: 上传网页打不开？", "A: 确认手机和词典笔在同一 Wi-Fi，", "   并检查词典笔系统是否有 python3 或 node。", "", "Q: 手动输入书名打不开？", "A: 只需输入小说名，如「三体」，", "   不需要输入完整路径。", "", "【以上为全部教程内容】"];
        tutorialLine = 0;
        showTutorial = true;
    }

    function refreshUploaderOutput() {
        if (!uploaderStarted || uploaderAddress !== "")
            return;

        uploaderController = (typeof shellPluginController !== "undefined") ? shellPluginController : null;
        if (!uploaderController)
            return;

        var log = _readLog("/tmp/novel-uploader.log");
        if (log !== "") {
            var url = ReaderUtils.getUploaderUrl(log);
            if (url) {
                uploaderAddress = url;
                uploaderStatus = "上传服务已启动";
                _uploadRetry = 0;
                return;
            }
            var ips = log.match(/(\d+\.\d+\.\d+\.\d+)/g);
            if (ips) {
                for (var i = ips.length - 1; i >= 0; i--) {
                    if (ips[i] !== "127.0.0.1" && ips[i].indexOf("169.254.") !== 0 && ips[i] !== "0.0.0.0") {
                        uploaderAddress = "http://" + ips[i] + ":8088";
                        uploaderStatus = "上传服务已启动";
                        _uploadRetry = 0;
                        return;
                    }
                }
            }
            if (log.indexOf("未找到 python3 或 node") >= 0) {
                uploaderStatus = "缺少 python3/node";
                return;
            }
            if (log.indexOf("Address already in use") >= 0 || log.indexOf("EADDRINUSE") >= 0) {
                uploaderStatus = "端口 8088 被占用";
                return;
            }
        }

        _uploadRetry++;
        if (_uploadRetry > 40) {
            uploaderStatus = log === "" ? "上传服务未启动或日志为空" : "获取 IP 超时，请检查网络连接";
        }
    }
    function readState(key, fallbackValue) {
        return Storage.readState(key, fallbackValue);
    }

    function writeState(key, value) {
        return Storage.writeState(key, value);
    }

    function loadProgressStore() {
        progressStore = Storage.loadProgressStore();
    }

    function loadBookmarksStore() {
        bookmarksStore = Storage.loadBookmarksStore();
    }

    // 计算整本书进度（用于书架显示）
    function calcBookPercent() {
        if (!rawLines || rawLines.length === 0 || chapterBoundaries.length === 0) return 0;
        var doneRaw = 0;
        for (var i = 0; i < currentChapterIdx && i < chapterBoundaries.length; i++) {
            doneRaw += chapterBoundaries[i].endRaw - chapterBoundaries[i].startRaw;
        }
        var chapTotal = 0, chapDone = 0;
        if (currentChapterIdx >= 0 && currentChapterIdx < chapterBoundaries.length) {
            var b = chapterBoundaries[currentChapterIdx];
            chapTotal = b.endRaw - b.startRaw;
            chapDone = chapTotal > 0 && lines.length > 0
                ? Math.floor((currentLine / lines.length) * chapTotal) : 0;
        }
        return Math.min(100, Math.round((doneRaw + Math.min(chapDone, chapTotal)) / rawLines.length * 100));
    }

    // 翻页时只更新内存，由防抖定时器批量写入文件
    function saveProgress() {
        Storage.updateProgressMemory(progressStore, currentUrl, fileName, currentLine, lines.length, currentChapterIdx, calcBookPercent());
        flushDebounceTimer.restart();
    }

    // 立即将进度写入文件（关键操作时调用）
    function flushProgress() {
        if (currentUrl === "")
            return;
        Storage.updateProgressMemory(progressStore, currentUrl, fileName, currentLine, lines.length, currentChapterIdx, calcBookPercent());
        Storage.flushProgressStore(progressStore);
        flushDebounceTimer.stop();
    }

    function loadProgress(url) {
        var item = Storage.loadProgressFromStore(progressStore, url);
        if (item && typeof item === "object") return item;
        return null;
    }

    function saveSettings() {
        var settings = {
            fontSize: baseFontSize,
            lineSpacing: lineSpacing,
            bgColor: bgColor,
            textColor: textColor,
            themeName: themeName,
            lastFile: lastFilePath,
            autoScrollSeconds: autoScrollSeconds,
            scrollMode: scrollMode
        };
        Storage.saveSettingsToStore(settings);
    }

    function loadSettings() {
        var settings = Storage.loadSettingsFromStore();
        baseFontSize = parseInt(settings.fontSize) || 15;
        lineSpacing = parseInt(settings.lineSpacing) || 4;
        bgColor = settings.bgColor || "#FFFBF0";
        textColor = settings.textColor || "#333333";
        themeName = settings.themeName || "默认";
        lastFilePath = settings.lastFile || "";
        scrollMode = settings.scrollMode === true;
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
            chapterIdx: currentChapterIdx,
            percent: getProgressPercent(),
            preview: preview
        });
        bookmarksStore[currentUrl] = items;
        if (writeState("bookmarks", JSON.stringify(bookmarksStore))) {
            loadBookmarkList();
            showToast("✓ 已添加书签");
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
        if (currentUrl === "")
            return;
        if (Storage.deleteRecord(currentUrl, progressStore)) {
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
        // 菜单内显示章节进度
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

    function showToast(msg) {
        toastMessage = msg;
        toastTimer.restart();
    }

    function toggleScrollMode() {
        if (!currentUrl || lines.length === 0)
            return;
        if (scrollMode) {
            // 滚动 → 分页
            var newLine = Math.floor(scrollFlickable.contentY / getTextLineHeight());
            currentLine = Math.max(0, Math.min(newLine, maxStartLine()));
            clampCurrentLine();
            scrollMode = false;
            flushProgress();
        } else {
            // 分页 → 滚动
            scrollOffset = currentLine * getTextLineHeight();
            scrollMode = true;
            updateScrollMax();
            scrollFlickable.contentY = Math.max(0, Math.min(scrollOffset, scrollMax));
        }
        saveSettings();
        showToast(scrollMode ? "已切换为滚动模式" : "已切换为分页模式");
    }

    function updateScrollMax() {
        if (lines.length > 0) {
            var contentH = lines.length * getTextLineHeight();
            var viewH = readerPage.height - readerMargin * 2;
            scrollMax = Math.max(0, contentH - viewH);
            if (scrollOffset > scrollMax)
                scrollOffset = scrollMax;
        } else {
            scrollMax = 0;
            scrollOffset = 0;
        }
    }

    function closePanels() {
        activePanel = "";
    }

    function openPanel(name) {
        if (name === "bookmarks")
            loadBookmarkList();
        activePanel = name;
    }

    function returnToShelf() {
        // 取消正在进行的翻页动画
        if (animating) {
            pageSlideAnim.stop();
            pageTurnOverlay.visible = false;
            pageTurnOverlay.x = 0;
            animating = false;
            turnDirection = 0;
            pendingLine = -1;
        }

        // 先保存当前进度到内存（progressStore → dataCache），再清空状态
        if (currentUrl !== "")
            flushProgress();

        autoScroll = false;
        closePanels();
        currentUrl = "";
        fileName = "";
        lines = [];
        rawLines = [];
        chapterBoundaries = [];
        chapterList = [];
        bookmarkList = [];
        currentLine = 0;
        currentChapterIdx = -1;
        showNextChapter = false;

        // 导航到书架
        navigateRoot();
        navigateTo("shelf");
        loadBookList();
    }

    function returnToHome() {
        // 取消正在进行的翻页动画
        if (animating) {
            pageSlideAnim.stop();
            pageTurnOverlay.visible = false;
            pageTurnOverlay.x = 0;
            animating = false;
            turnDirection = 0;
            pendingLine = -1;
        }

        // 先保存当前进度到内存，再清空状态
        if (currentUrl !== "")
            flushProgress();

        autoScroll = false;
        closePanels();
        currentUrl = "";
        fileName = "";
        lines = [];
        rawLines = [];
        chapterBoundaries = [];
        chapterList = [];
        bookmarkList = [];
        currentLine = 0;
        currentChapterIdx = -1;
        showNextChapter = false;

        navigateRoot();
        loadBookList();
    }

    function loadFile(url) {
        if (!url)
            return;

        // 取消正在进行的翻页动画
        if (animating) {
            pageSlideAnim.stop();
            pageTurnOverlay.visible = false;
            pageTurnOverlay.x = 0;
            animating = false;
            turnDirection = 0;
            pendingLine = -1;
        }

        // 先保存当前书籍的阅读进度，避免切换书籍时丢失
        if (currentUrl !== "" && currentUrl !== url) {
            flushProgress();
        }

        if (xhr && xhr.readyState === XMLHttpRequest.LOADING) {
            xhr.abort();
            xhr = null;
        }

        closePanels();

        // 先设置 currentUrl，再导航到阅读器（navigateTo 依赖它）
        currentUrl = url;
        fileName = bookTitle(url);
        lastFilePath = url;

        // 导航到阅读器页面
        if (pageMode !== "reader") {
            navigateTo("reader");
        }

        isLoading = true;
        statusMessage = "";

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
            if (xhr.status === 200 || xhr.status === 0) {
                var content = xhr.responseText || "";
                if (content.length > 0 && content.charCodeAt(0) === 0xFEFF)
                    content = content.substring(1);
                // processContent 会将后续初始化移至 afterContentLoaded（同步小文件/异步大文件）
                processContent(content);
            } else if (requestUrl !== originalUrl) {
                doLoadFile(originalUrl, originalUrl);
                return;
            } else {
                isLoading = false;
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

    // ====== 章节边界扫描（纯文本扫描，不做换行处理，速度极快） ======
    function scanChapterBoundaries(raw) {
        var bounds = [];
        var regex = /^(第[一二三四五六七八九十百千零\d]+[章节回集卷部篇]|Chapter\s+\d+|CHAPTER\s+\d+|Part\s+\d+|PART\s+\d+)/;
        for (var i = 0; i < raw.length; i++) {
            var t = raw[i].trim();
            if (t.length > 0 && t.length < 60 && regex.test(t)) {
                if (bounds.length > 0)
                    bounds[bounds.length - 1].endRaw = i;
                bounds.push({ title: t, startRaw: i, endRaw: raw.length });
            }
        }
        // 无章节 → 整本书算一章
        if (bounds.length === 0) {
            bounds.push({ title: bookTitle(fileName), startRaw: 0, endRaw: raw.length });
            return bounds;
        }
        // 第 0 章从文件开头开始（包含序言/前言等）
        bounds[0].startRaw = 0;
        for (var j = 0; j < bounds.length - 1; j++)
            bounds[j].endRaw = bounds[j + 1].startRaw;
        return bounds;
    }

    // 加载指定章节（仅换行该章节的原始行）
    function loadChapter(idx) {
        if (idx < 0 || idx >= chapterBoundaries.length) return;
        if (currentChapterIdx === idx && lines.length > 0) return; // 已加载
        isLoading = true;

        var b = chapterBoundaries[idx];
        var chapterRaw = rawLines.slice(b.startRaw, b.endRaw);
        var result = ReaderUtils.wrapLines(chapterRaw, charsPerLine * 2);
        lines = result.lines;
        currentChapterIdx = idx;
        currentLine = 0;

        // 恢复该章节的阅读进度
        var saved = Storage.loadChapterProgress(progressStore, currentUrl, idx);
        if (saved > 0) {
            currentLine = Math.min(saved, maxStartLine());
        }
        clampCurrentLine();

        // 滚动模式同步滚动位置
        if (scrollMode) {
            scrollFlickable.contentY = currentLine * getTextLineHeight();
        }

        updateChapterList();
        updateScrollMax();
        loadBookmarkList();
        saveSettings();
        isLoading = false;
        statusMessage = "";
    }

    function updateChapterList() {
        chapterList = [];
        for (var i = 0; i < chapterBoundaries.length; i++) {
            chapterList.push({ title: chapterBoundaries[i].title, lineIndex: i });
        }
    }

    function processContent(content) {
        try {
            rawLines = ReaderUtils.splitIntoLines(content);
            chapterBoundaries = scanChapterBoundaries(rawLines);

            // 读取保存的进度 → 定位到对应章节
            var saved = loadProgress(currentUrl);
            var savedChapter = (saved && saved.chapterIdx !== undefined) ? saved.chapterIdx : 0;
            if (savedChapter >= chapterBoundaries.length) savedChapter = 0;

            loadChapter(savedChapter);
        } catch (e) {
            isLoading = false;
            statusMessage = "";
        }
    }

    function afterContentLoaded() {
        // 兼容旧接口：setFontSize 等可能调用后调用此函数
        // 现在由 loadChapter 处理加载完成后的初始化
    }

    function nextPage() {
        if (animating)
            return;
        var maxLine = maxStartLine();
        if (currentLine >= maxLine) {
            if (currentChapterIdx < chapterBoundaries.length - 1) {
                if (showNextChapter) {
                    // 已显示"下一章"按钮，再次点击 → 加载下一章
                    showNextChapter = false;
                    saveProgress();
                    loadChapter(currentChapterIdx + 1);
                    return;
                }
                showNextChapter = true;
            }
            autoScroll = false;
            return;
        }
        showNextChapter = false;

        var newLine = Math.min(currentLine + getLinesPerPage(), maxLine);
        if (currentLine === newLine)
            return;

        // 临时切换到新行计算新页文本，再恢复以保持 contentText 不变
        var oldLine = currentLine;
        currentLine = newLine;
        pageTurnText.text = getPageText();
        currentLine = oldLine;

        // 设置覆盖层从右侧滑入
        turnDirection = 1;
        turnShadow.anchors.left = turnShadow.parent.left;
        turnShadow.anchors.right = undefined;
        turnShadow.color = Qt.rgba(0, 0, 0, 0);
        pageTurnOverlay.x = readerPage.width;
        pageTurnOverlay.visible = true;
        animating = true;
        pendingLine = newLine;

        pageSlideAnim.from = readerPage.width;
        pageSlideAnim.to = 0;
        pageSlideAnim.start();

        // 内存中更新进度（数据库由防抖定时器写入）
        Storage.updateProgressMemory(progressStore, currentUrl, fileName, newLine, lines.length, currentChapterIdx, calcBookPercent());
        flushDebounceTimer.restart();
    }

    function prevPage() {
        if (animating)
            return;
        if (currentLine <= 0)
            return;

        var newLine = Math.max(0, currentLine - getLinesPerPage());
        if (currentLine === newLine)
            return;

        // 临时切换到新行计算新页文本
        var oldLine = currentLine;
        currentLine = newLine;
        pageTurnText.text = getPageText();
        currentLine = oldLine;

        // 设置覆盖层从左侧滑入
        turnDirection = -1;
        turnShadow.anchors.left = undefined;
        turnShadow.anchors.right = turnShadow.parent.right;
        turnShadow.color = Qt.rgba(0, 0, 0, 0);
        pageTurnOverlay.x = -readerPage.width;
        pageTurnOverlay.visible = true;
        animating = true;
        pendingLine = newLine;

        pageSlideAnim.from = -readerPage.width;
        pageSlideAnim.to = 0;
        pageSlideAnim.start();

        Storage.updateProgressMemory(progressStore, currentUrl, fileName, newLine, lines.length, currentChapterIdx, calcBookPercent());
        flushDebounceTimer.restart();
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
        if (chapterBoundaries.length === 0) return;
        var newIdx = currentChapterIdx + offset;
        if (newIdx < 0 || newIdx >= chapterBoundaries.length) return;
        if (newIdx === currentChapterIdx) return;
        // 保存当前章节进度
        saveProgress();
        // 加载新章节
        loadChapter(newIdx);
    }

    function setFontSize(size) {
        var ratio = lines.length > 0 ? currentLine / lines.length : 0;
        baseFontSize = size;
        updateCharsPerLine();
        if (currentUrl !== "" && currentChapterIdx >= 0 && chapterBoundaries.length > 0) {
            // 重新加载当前章节（使用新字号换行），保持阅读比例
            var b = chapterBoundaries[currentChapterIdx];
            var chapterRaw = rawLines.slice(b.startRaw, b.endRaw);
            var result = ReaderUtils.wrapLines(chapterRaw, charsPerLine * 2);
            lines = result.lines;
            currentLine = Math.min(Math.floor(ratio * lines.length), maxStartLine());
            clampCurrentLine();
            updateScrollMax();
            if (scrollMode) {
                scrollOffset = currentLine * getTextLineHeight();
                scrollFlickable.contentY = Math.max(0, scrollOffset);
            }
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
        visible: pageMode === "home"

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4
            visible: pageMode === "home"

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
                elide: Text.ElideLeft
                horizontalAlignment: Text.AlignHCenter
                font.family: "Microsoft YaHei"
            }

            Text {
                width: parent.width
                text: uploaderAddress !== "" ? ("上传服务已启动  |  请在浏览器输入此网址上传小说") : uploaderStatus
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
                        text: "作者：skdkzzx"
                        font.pixelSize: 12
                        color: "#2E7D32"
                        font.family: "Microsoft YaHei"
                    }
                }
            }
        }
    }

    Item {
        id: shelfPage
        anchors.fill: parent
        visible: pageMode === "shelf"

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
                    width: parent.width - 122
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

    Item {
        id: readerPage
        anchors.fill: parent
        visible: pageMode === "reader"
        clip: true

        // 当前页文本（分页模式）
        Text {
            id: contentText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: readerMargin
            anchors.rightMargin: readerMargin
            anchors.topMargin: readerMargin
            anchors.bottomMargin: readerMargin + (!scrollMode && showNextChapter ? 26 : 0)
            text: getPageText()
            font.family: "Microsoft YaHei"
            font.pixelSize: baseFontSize
            lineHeightMode: Text.FixedHeight
            lineHeight: getTextLineHeight()
            color: textColor
            wrapMode: Text.NoWrap
            clip: true
            visible: !scrollMode
        }

        // 滚动模式容器（Flickable 上下滚动查看全文）
        Flickable {
            id: scrollFlickable
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: readerMargin
            anchors.rightMargin: readerMargin
            anchors.topMargin: readerMargin
            anchors.bottomMargin: readerMargin
            visible: scrollMode
            clip: true
            contentWidth: width
            contentHeight: scrollContentCol.height
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: scrollMode
            pixelAligned: true

            // 滚动停止时保存阅读进度
            onMovementEnded: {
                if (scrollMode) {
                    var line = Math.floor(contentY / getTextLineHeight());
                    currentLine = Math.max(0, Math.min(line, Math.max(0, lines.length - getLinesPerPage())));
                    Storage.updateProgressMemory(progressStore, currentUrl, fileName, currentLine, lines.length, currentChapterIdx, calcBookPercent());
                    flushDebounceTimer.restart();
                }
            }

            Column {
                id: scrollContentCol
                width: parent.width
                spacing: 0

                // 章首"上一章"按钮（主题色填充）
                Item {
                    width: parent.width
                    height: (scrollMode && currentChapterIdx > 0) ? 30 : 0
                    Rectangle {
                        anchors.centerIn: parent
                        width: 80
                        height: 22
                        radius: 2
                        color: textColor
                        visible: scrollMode && currentChapterIdx > 0
                        Text {
                            anchors.centerIn: parent
                            text: "← 上一章"
                            font.pixelSize: 11
                            color: bgColor
                            font.family: "Microsoft YaHei"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                saveProgress();
                                loadChapter(currentChapterIdx - 1);
                            }
                        }
                    }
                }

                Text {
                    id: scrollFullText
                    width: parent.width
                    text: lines.join("\n")
                    font.family: "Microsoft YaHei"
                    font.pixelSize: baseFontSize
                    lineHeightMode: Text.FixedHeight
                    lineHeight: getTextLineHeight()
                    color: textColor
                    wrapMode: Text.NoWrap
                }

                // 章尾"下一章"按钮（主题色填充）
                Item {
                    width: parent.width
                    height: (scrollMode && currentChapterIdx < chapterBoundaries.length - 1) ? 30 : 0
                    Rectangle {
                        anchors.centerIn: parent
                        width: 80
                        height: 22
                        radius: 2
                        color: textColor
                        visible: scrollMode && currentChapterIdx < chapterBoundaries.length - 1
                        Text {
                            anchors.centerIn: parent
                            text: "下一章 →"
                            font.pixelSize: 11
                            color: bgColor
                            font.family: "Microsoft YaHei"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                saveProgress();
                                loadChapter(currentChapterIdx + 1);
                            }
                        }
                    }
                }
            }
        }

        // 滚动模式点击/长按处理（放在 Flickable 外面，避免事件被吞）
        MouseArea {
            id: scrollOverlay
            anchors.fill: scrollFlickable
            visible: scrollMode
            z: 10
            preventStealing: false

            property point pressPos
            property bool dragged: false

            onPressed: function(mouse) {
                pressPos = Qt.point(mouse.x, mouse.y);
                dragged = false;
                mouse.accepted = false;
            }

            onPositionChanged: function(mouse) {
                var dx = Math.abs(mouse.x - pressPos.x);
                var dy = Math.abs(mouse.y - pressPos.y);
                if (dx > 15 || dy > 15)
                    dragged = true;
                mouse.accepted = false;
            }

            onReleased: function(mouse) {
                if (!dragged) {
                    var clickX = pressPos.x;
                    if (clickX < scrollFlickable.width / 3) {
                        scrollFlickable.contentY = Math.max(0, scrollFlickable.contentY - scrollFlickable.height);
                    } else if (clickX > scrollFlickable.width * 2 / 3) {
                        scrollFlickable.contentY = Math.min(scrollFlickable.contentHeight - scrollFlickable.height, scrollFlickable.contentY + scrollFlickable.height);
                    }
                    // 中间区域不做任何操作
                }
                mouse.accepted = false;
            }

            onClicked: mouse.accepted = false
        }

        // 滚动模式浮动菜单按钮（右下角）
        Rectangle {
            id: scrollMenuBtn
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 4
            anchors.bottomMargin: 4
            width: 28
            height: 28
            radius: 14
            color: "#AA000000"
            visible: scrollMode && activePanel === ""
            z: 20

            Text {
                anchors.centerIn: parent
                text: "☰"
                font.pixelSize: 16
                color: "#FFFFFF"
                font.family: "Microsoft YaHei"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    openPanel("menu");
                }
            }
        }

        // 分页模式章尾"下一章 →"按钮
        Rectangle {
            id: pageNextBtn
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            width: 100
            height: 24
            radius: 2
            color: textColor
            visible: !scrollMode && showNextChapter && currentChapterIdx < chapterBoundaries.length - 1
            z: 30
            Text {
                anchors.centerIn: parent
                text: "下一章 →"
                font.pixelSize: 11
                font.bold: true
                color: bgColor
                font.family: "Microsoft YaHei"
            }
            MouseArea {
                anchors.fill: parent
                onPressed: {
                    showNextChapter = false;
                    saveProgress();
                    loadChapter(currentChapterIdx + 1);
                }
            }
        }

        // 翻页覆盖层（新页从右侧/左侧滑入覆盖旧页）
        Rectangle {
            id: pageTurnOverlay
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width
            color: bgColor
            visible: false
            z: 5

            // 翻页阴影（滑入边缘的渐变阴影）
            Rectangle {
                id: turnShadow
                width: 8
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                visible: turnDirection !== 0
                z: 6
                // 阴影渐变，在 onStarted 中动态赋值
            }
            // 预定义两种方向的阴影渐变
            Gradient {
                id: shadowGradRight
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(0, 0, 0, 0.15)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(0, 0, 0, 0)
                }
            }
            Gradient {
                id: shadowGradLeft
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(0, 0, 0, 0)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(0, 0, 0, 0.15)
                }
            }

            Text {
                id: pageTurnText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: readerMargin
                anchors.rightMargin: readerMargin
                anchors.topMargin: readerMargin
                anchors.bottomMargin: readerMargin
                font.family: "Microsoft YaHei"
                font.pixelSize: baseFontSize
                lineHeightMode: Text.FixedHeight
                lineHeight: getTextLineHeight()
                color: textColor
                wrapMode: Text.NoWrap
                clip: true
            }
        }

        // 翻页滑动动画
        PropertyAnimation {
            id: pageSlideAnim
            target: pageTurnOverlay
            property: "x"
            duration: 200
            easing.type: Easing.OutQuad
            onStarted: {
                // 动画开始时添加滑动边缘阴影
                turnShadow.gradient = turnDirection > 0 ? shadowGradRight : shadowGradLeft;
            }
            onFinished: {
                // 更新当前行，contentText 通过绑定自动刷新
                currentLine = pendingLine;
                pendingLine = -1;
                // 重置覆盖层状态
                pageTurnOverlay.visible = false;
                pageTurnOverlay.x = 0;
                turnShadow.gradient = null;
                turnDirection = 0;
                animating = false;
            }
        }

        MouseArea {
            id: pageTouch
            anchors.fill: parent
            z: 1
            enabled: activePanel === "" && !isLoading && !animating && !scrollMode
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

                // 点击：左/中/右区域（用 onPressed 记录的位置，更可靠）
                var clickX = startX;
                var clickY = startY;
                if (clickX > width / 3 && clickX < width * 2 / 3) {
                    openPanel("menu");
                } else if (clickX < width / 3) {
                    prevPage();
                } else {
                    nextPage();
                }
            }
        }
    }

    Rectangle {
        id: menuPanel
        visible: activePanel === "menu" || menuPanel.opacity > 0.01
        opacity: activePanel === "menu" ? 1 : 0
        scale: 1
        anchors.fill: parent
        anchors.margins: 8
        radius: 6
        color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
        border.color: "#CCCCCC"
        z: 40
        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutBack
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 5

            Row {
                width: parent.width
                height: 24
                Text {
                    width: parent.width - 30
                    text: fileName
                    font.pixelSize: 12
                    font.bold: true
                    color: textColor
                    elide: Text.ElideMiddle
                    verticalAlignment: Text.AlignVCenter
                    font.family: "Microsoft YaHei"
                }
                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: "#DDDDDD"
                    Text {
                        anchors.centerIn: parent
                        text: "x"
                        font.pixelSize: 12
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
                            label: scrollMode ? "📖分页" : "📜滚动"
                            w: (menuContent.width - 8) / 3
                            bg: scrollMode ? "#E8F5E9" : "#FFF3E0"
                            fg: scrollMode ? "#2E7D32" : "#E65100"
                            onClicked: {
                                toggleScrollMode();
                                closePanels();
                            }
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
                    Item {
                        width: parent.width
                        height: 10
                    }
                }
            }
        }
    }

    Rectangle {
        id: jumpPanel
        visible: activePanel === "jump" || jumpPanel.opacity > 0.01
        opacity: activePanel === "jump" ? 1 : 0
        scale: 1
        anchors.fill: parent
        anchors.margins: 10
        radius: 6
        color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
        border.color: "#CCCCCC"
        z: 50
        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutBack
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            Row {
                width: parent.width
                height: 24
                Text {
                    width: parent.width - 30
                    text: "跳转到"
                    font.pixelSize: 12
                    font.bold: true
                    color: textColor
                    verticalAlignment: Text.AlignVCenter
                    font.family: "Microsoft YaHei"
                }
                MenuButton {
                    label: "x"
                    w: 24
                    h: 24
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
                            if (modelData.lineIndex !== currentChapterIdx) {
                                saveProgress();
                                loadChapter(modelData.lineIndex);
                            }
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
        id: bookmarkPanel
        visible: activePanel === "bookmarks" || bookmarkPanel.opacity > 0.01
        opacity: activePanel === "bookmarks" ? 1 : 0
        scale: 1
        anchors.fill: parent
        anchors.margins: 10
        radius: 6
        color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
        border.color: "#CCCCCC"
        z: 50
        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutBack
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 5

            Row {
                width: parent.width
                height: 24
                Text {
                    width: parent.width - 30
                    text: "书签 (" + bookmarkList.length + ")"
                    font.pixelSize: 12
                    font.bold: true
                    color: textColor
                    verticalAlignment: Text.AlignVCenter
                    font.family: "Microsoft YaHei"
                }
                MenuButton {
                    label: "x"
                    w: 24
                    h: 24
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
                            var bmChapter = parseInt(modelData.chapterIdx);
                            if (!isNaN(bmChapter) && bmChapter !== currentChapterIdx) {
                                loadChapter(bmChapter);
                            }
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
        id: autoPanel
        visible: activePanel === "auto" || autoPanel.opacity > 0.01
        opacity: activePanel === "auto" ? 1 : 0
        scale: 1
        anchors.fill: parent
        anchors.margins: 25
        radius: 6
        color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
        border.color: "#CCCCCC"
        z: 50
        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutBack
            }
        }

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
        width: 110
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

    // ====== Toast 提示 ======
    Rectangle {
        id: toast
        visible: toastMessage !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        width: toastTxt.width + 24
        height: 22
        radius: 11
        color: "#CC000000"
        z: 200

        Text {
            id: toastTxt
            anchors.centerIn: parent
            text: toastMessage
            font.pixelSize: 11
            color: "#FFFFFF"
            font.family: "Microsoft YaHei"
        }
    }

    Timer {
        id: toastTimer
        interval: 2200
        repeat: false
        onTriggered: toastMessage = ""
    }

    YPagePopHelper {
        id: pagePopHelper
        z: 99
        property var containerItem: this
        isShowing: typeof qmlGlobal !== "undefined" ? qmlGlobal.inputPageShowing : false
    }
}
