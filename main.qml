import QtQuick 2.15
import "qrc:/qml/commons"
import "Storage.js" as Storage
import "ReaderUtils.js" as ReaderUtils
import "Encoding.js" as Encoding
import "ReadingStats.js" as Stats
import "Search.js" as Search
import "BookList.js" as BookList

Rectangle {
    id: root
    width: 320
    height: 170
    color: bgColor
    focus: true

    signal backButtonClicked

    // 实体返回键（或有道词典笔实体按键）→ 立即保存进度
    Keys.onPressed: {
        if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
            if (currentUrl !== "" && pageMode === "reader") {
                flushProgress();
            }
        }
    }

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
    // 主题派生色（随 themeName 自动更新，避免各处硬编码颜色）
    property string cardColor: "#F8F4EC"
    property string borderColor: "#E0D8C8"
    property string subTextColor: "#888888"
    property string accentColor: "#2f7dcc"
    readonly property bool darkTheme: ReaderUtils.isDarkTheme(themeName)

    // ====== 夜间模式自动切换 ======
    property bool nightAuto: false            // 是否启用按时间自动切换
    property string dayTheme: "默认"          // 白天使用的主题
    property string nightTheme: "深灰"        // 夜间使用的主题
    property int nightStartHour: 20           // 夜间起始（含）
    property int nightEndHour: 7              // 夜间结束（不含）
    property string detectedEncoding: ""      // 当前书籍检测到的编码
    property bool encodingConverting: false   // 正在转码（显示提示用）
    property string encodingNotice: ""        // 转码完成后的提示文案
    // ====== 进度与阅读速度（用于剩余时间估算）======
    // 字符偏移是稳定的进度度量：行号会随字号/行距变化，字符偏移不会。
    property int chapterCharCount: 0          // 当前章节总字符数
    property var chapterCharOffsets: []       // 每章起始字符偏移 [{start, chars}]
    property int chapterCharsBefore: 0        // 当前章节之前的累计字符数
    property int bookCharTotal: 0             // 全书总字符数
    property int readingSpeed: 0              // 实测阅读速度（字符/分），0=未测得
    property double sessionCharsAtStart: 0    // 本次会话开始时的字符偏移
    property double sessionStartMs: 0         // 本次会话开始的时间戳

    // ====== 全文搜索 ======
    property string searchQuery: ""           // 用户输入的关键词
    property var searchResults: []            // 命中结果
    property int searchTotal: 0               // 命中总数（可能超过显示上限）
    property bool searchTruncated: false
    property bool searchWholeWord: false
    property bool searchCaseSensitive: false
    property string searchDate: ""            // 记忆上次搜索的时间（可选）
    property double pendingSearchRatio: -1    // 跨章跳转时待定位的比例

    property string encodingProbeUrl: ""      // 正在探测编码的书籍
    property int encodingProbeRetry: 0
    property string encodingConvertUrl: ""
    property string encodingConvertTarget: ""
    property int encodingConvertRetry: 0
    property bool autoScroll: false
    property int autoScrollSeconds: 2
    property bool animating: false
    property int turnDirection: 0
    property int pendingLine: -1
    property bool turnIsVertical: false

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
        if (mode === "settings")
            return settingsPage;
        if (mode === "chapterList")
            return chapterListPage;
        if (mode === "stats")
            return statsPage;
        return null;
    }

    property string activePanel: ""
    property bool keyboardPending: false
    property var bookList: []
    property int bookListTotal: 0   // 书架截断前的实际总数
    // ====== 书架视图（排序 / 筛选）======
    property string shelfQuery: ""
    property string shelfSort: BookList.SORT_RECENT
    property string shelfFilter: BookList.FILTER_ALL
    property var shelfSource: []     // 未过滤的完整列表
    property int statsRefreshKey: 0  // 改变时触发统计页重算
    property var bookmarkList: []
    property var progressStore: ({})
    property var bookmarksStore: ({})
    property var readingTimeData: ({})    // url -> 累计阅读秒数
    property string lastFilePath: ""   // 仅内存记录当前书籍；不再持久化（原先只写不读）
    property var bookFolderModel: null
    property bool folderScanAvailable: false
    property var uploaderController: (typeof shellPluginController !== "undefined") ? shellPluginController : null
    property bool uploaderStarted: false
    property bool uploaderStarting: false
    property bool _readLogPending: false
    property string uploaderStatus: "上传服务未启动"
    property string uploaderAddress: ""
    property string uploaderOutput: ""
    property bool showSponsor: false
    property var shelfContextItem: null     // 书架长按菜单的目标书籍
    property bool showShelfMenu: false      // 书架上下文菜单
    property bool showBookInfo: false       // 书籍信息面板
    property var bookInfoItem: null         // 当前查看的书籍信息
    // 书籍信息缓存（key -> {chars, chapters, readingTime}）
    property var bookInfoCache: ({})
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

    // ====== 章节列表设置 ======
    property string chapterNameMode: "scroll"  // "scroll" 滚动显示 或 "short" 仅显示第X章
    property string chapterSearchQuery: ""      // 章节搜索关键字
    property var filteredChapterList: []        // 过滤后的章节列表

    // ====== 手势设置 ======
    property bool tripleTapHome: false    // 三击返回首页
    property var tapTimestamps: []        // 点击时间戳队列

    // ====== Toast ======
    property string toastMessage: ""
    property bool showNextChapter: false   // 是否显示"下一章"按钮

    readonly property string defaultBookFolder: "/userdisk/Music/小说/"
    readonly property string defaultBookSuffix: ".txt"
    // 排版可调范围（集中定义，避免散落在界面代码里）
    property int readerMargin: 7                 // 页边距（可调）
    readonly property int FONT_MIN: 12
    readonly property int FONT_MAX: 28
    readonly property int FONT_DEFAULT: 15
    readonly property int LINE_SPACING_MIN: 0
    readonly property int LINE_SPACING_MAX: 12
    readonly property int MARGIN_MIN: 2
    readonly property int MARGIN_MAX: 20

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

    // 书架页自动重扫：用户停留在书架时（例如正在用手机上传小说），
    // 定期重扫目录，新上传的文件无需手动退出再进即可出现。
    // 仅在书架页可见时运行，且间隔较长，避免频繁 IO。
    Timer {
        id: shelfAutoRefreshTimer
        interval: 8000
        repeat: true
        running: pageMode === "shelf" && activePanel === ""
        onTriggered: refreshShelf()
    }

    // 进度延迟落盘：翻页等操作后延迟写一次，合并短时间内的多次变更。
    // 注：与下方 periodicSaveTimer 的分工是——
    //   本定时器：操作「后」的延迟落盘（防抖），不更新数据本身
    //   periodicSaveTimer：固定间隔的兜底保存（含数据更新），防实体按键退出丢进度
    // 两者此前间隔分别为 3s / 5s 且都执行全量双写，导致阅读时平均每 2~3 秒
    // 就要重写一次状态文件（每次 2 条 shell 命令 + 1 次同步 XHR）。
    // 现将延迟落盘统一为 5s，与兜底保存错开，显著降低写入频率。
    Timer {
        id: progressFlushTimer
        interval: 5000
        repeat: false
        onTriggered: Storage.flushProgressStore(progressStore)
    }

    Timer {
        id: uploaderStartTimer
        interval: 700
        repeat: false
        onTriggered: startUploaderService()
    }

    // 夜间模式自动切换检查（每 5 分钟一次，开销可忽略）
    Timer {
        id: nightModeTimer
        interval: 5 * 60 * 1000
        repeat: true
        running: nightAuto
        onTriggered: applyAutoTheme()
    }

    // 编码探测轮询（300ms，最多 20 次 = 6 秒）
    Timer {
        id: encodingProbeTimer
        interval: 300
        repeat: true
        running: false
        onTriggered: pollEncodingResult()
    }

    // 转码结果轮询（250ms，最多 40 次 = 10 秒）
    Timer {
        id: encodingConvertTimer
        interval: 250
        repeat: true
        running: false
        onTriggered: pollEncodingConvert()
    }

    Timer {
        id: uploaderOutputTimer
        interval: 500
        repeat: true
        running: false
        onTriggered: refreshUploaderOutput()
    }

    // 定时自动保存（每5秒）：防止实体按键退出导致进度丢失
    Timer {
        id: periodicSaveTimer
        interval: 5000
        repeat: true
        running: pageMode === "reader" && currentUrl !== "" && !isLoading
        onTriggered: {
            if (currentUrl === "" || pageMode !== "reader") return;
            // 滚动模式下先同步最新滚动位置
            if (scrollMode) {
                var line = Math.floor(scrollFlickable.contentY / getTextLineHeight());
                currentLine = Math.max(0, Math.min(line, Math.max(0, lines.length - getLinesPerPage())));
            }
            Storage.updateProgressMemory(progressStore, currentUrl, fileName, currentLine, lines.length, currentChapterIdx, calcBookPercent(), readingTimeData[currentUrl]);
            Storage.flushProgressStore(progressStore);
        }
    }

    // 阅读计时器（每秒累计当前书籍阅读时长）
    Timer {
        id: readingTimer
        interval: 1000
        repeat: true
        running: pageMode === "reader" && currentUrl !== "" && !isLoading
        onTriggered: {
            if (currentUrl === "") return;
            readingTimeData[currentUrl] = (readingTimeData[currentUrl] || 0) + 1;
            updateReadingSpeed();
        }
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
        // 启动时自动创建小说目录
        try {
            if (typeof shellPluginController !== "undefined" && shellPluginController)
                shellPluginController.sendCommand("mkdir -p " + defaultBookFolder);
        } catch(e) {}
        uploaderStartTimer.start();
        loadSettings();
        applyAutoTheme();
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
            Storage.updateProgressMemory(progressStore, currentUrl, fileName, currentLine, lines.length, currentChapterIdx, calcBookPercent(), readingTimeData[currentUrl]);
        }
        // 始终刷一遍 progressStore——里面保存的是最后一次完整保存的进度
        Storage.flushProgressStore(progressStore);
        saveSettings();
    }

    // 修复：原实现用同步 XHR（xhr.open(..., false)）读取日志，且由 500ms
    // 定时器驱动，每次都会阻塞 QML 渲染线程，且 HEAD + GET 两次请求。
    // 现改为单次异步 GET，并用 _readLogPending 防止请求重入。
    function _readLog(path, callback) {
        if (_readLogPending) return;
        _readLogPending = true;
        try {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "file://" + path, true);
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                _readLogPending = false;
                var text = "";
                if (xhr.status === 200 || xhr.status === 0)
                    text = xhr.responseText || "";
                callback(text);
            };
            xhr.onerror = function () {
                _readLogPending = false;
                callback("");
            };
            xhr.send();
        } catch (e) {
            _readLogPending = false;
            callback("");
        }
    }

    function startUploaderService() {
        if (uploaderStarted)
            return;
        uploaderController = (typeof shellPluginController !== "undefined") ? shellPluginController : null;
        if (!uploaderController) {
            uploaderStatus = "上传服务未加载";
            uploaderStarted = false;
            return;
        }

        // 修复：原先在发出启动命令「之前」就置 uploaderStarted = true，
        // 一旦后端启动失败（无可用环境/端口被占），按钮会停留在
        // 「取消上传」状态，用户必须先点一次取消才能重试。
        // 现改为「启动中」独立状态，仅在确认端口就绪后才置为已启动。
        uploaderStarting = true;
        uploaderStarted = false;
        uploaderStatus = "上传服务启动中";
        uploaderAddress = "";
        _ipQueried = false;
        _uploadRetry = 0;
        var pluginDir = Qt.resolvedUrl(".").replace("file://", "");
        try {
            uploaderController.sendCommand("rm -f /tmp/novel-uploader.log; sh " + shellEscape(pluginDir + "/start-uploader.sh"));
        } catch (e) {
            uploaderStarting = false;
            uploaderStatus = "启动命令执行失败";
            return;
        }
        uploaderOutputTimer.start();
    }

    function stopUploaderService() {
        if (!uploaderStarted && !uploaderStarting)
            return;
        if (uploaderController) {
            try {
                uploaderController.sendCommand("fuser -k 8088/tcp 2>/dev/null || pkill -f 'novel-httpd' 2>/dev/null; pkill -f 'node.*server.js' 2>/dev/null; pkill -f 'python3.*server.py' 2>/dev/null; pkill -f 'upload_server' 2>/dev/null; echo ''");
            } catch (e) {}
        }
        uploaderStarted = false;
        uploaderStarting = false;
        uploaderStatus = "上传服务已停止";
        uploaderAddress = "";
        _readLogPending = false;
        uploaderOutputTimer.stop();
    }

    // 强制重扫小说目录并刷新书架列表。
    // 上传服务、外部 SFTP 等都会在插件运行期间改变目录内容，
    // 因此进入书架前必须重扫，否则显示的是陈旧数据。
    function refreshShelf() {
        if (bookFolderModel) {
            try { bookFolderModel.destroy(); } catch(e) {}
            bookFolderModel = null;
            folderScanAvailable = false;
        }
        startBookFolderScan();
    }

    function openShelf() {
        refreshShelf();
        navigateTo("shelf");
    }

    function closeShelf() {
        navigateBack();
    }

    function openTutorial() {
        tutorialLines = ["【使用教程】", "", "一、小说存放位置", "小说文件请放到：", defaultBookFolder, "支持 .txt 格式，文件名随意。", "", "二、打开小说", "1. 自动扫描：把 txt 放到上面的目录后，", "   进入「我的书架」即可看到。", "2. 手动输入：首页点击「手动输入书名」，", "   输入小说名即可，不需要输完整路径。", "", "三、上传小说", "1. 局域网上传（推荐）：", "   点击「启动上传」，首页会显示一个网址，", "   手机/电脑浏览器打开该网址即可上传。", "   手机和词典笔需连接同一个 Wi-Fi。", "2. SSH 上传：", "   用 WinSCP（电脑）或 Termius（手机）", "   通过 SFTP 连接词典笔，", "   把 txt 文件传到 " + defaultBookFolder + "。", "   连接信息：IP:词典笔IP 端口:22", "   用户名:root 密码:PenMods中设置的SSH密码", "", "四、阅读操作", "· 点击屏幕左侧 1/3：上一页", "· 点击屏幕右侧 1/3：下一页", "· 点击屏幕中间 1/3：打开菜单", "· 上下左右滑动：翻页", "", "五、菜单功能", "· 进度条：拖拽快速跳转", "· 字号：小/中/大 三档", "· 行距：紧凑/标准/宽松", "· 主题：7种配色可选", "· 书签：添加/查看/删除书签", "· 跳转：按百分比/页码/章节跳转", "· 自动翻页：可自定义间隔秒数", "· 上一章/下一章：快速切换章节", "", "六、常见问题", "Q: 书架没有显示小说？", "A: 确认文件在 " + defaultBookFolder + " 且后缀是 .txt", "", "Q: 上传网页打不开？", "A: 确认手机和词典笔在同一 Wi-Fi，", "   并检查词典笔是否有 node 或 python3，", "   或 busybox 是否带 httpd 组件。", "   若提示缺少运行环境，请直接用下面的", "   SSH/SFTP 方式上传。", "", "Q: 手动输入书名打不开？", "A: 只需输入小说名，如「三体」，", "   不需要输入完整路径。", "", "Q: 上传后书架没有？", "A: 返回首页再重新进入「我的书架」，", "   书架会在进入时重新扫描目录。", "", "【以上为全部教程内容】"];
        tutorialLine = 0;
        showTutorial = true;
    }

    function refreshUploaderOutput() {
        if ((!uploaderStarted && !uploaderStarting) || uploaderAddress !== "")
            return;

        uploaderController = (typeof shellPluginController !== "undefined") ? shellPluginController : null;
        if (!uploaderController)
            return;

        _readLog("/tmp/novel-uploader.log", function (log) {
            applyUploaderLog(log);
        });
    }

    // 解析启动日志并更新上传服务状态
    function applyUploaderLog(log) {
        if (log === "") {
            _uploadRetry++;
            if (_uploadRetry > 40) {
                uploaderStarting = false;
                uploaderStatus = "上传服务未启动或日志为空";
                uploaderOutputTimer.stop();
            }
            return;
        }

        var url = ReaderUtils.getUploaderUrl(log);
        if (url) {
            uploaderAddress = url;
            uploaderStatus = "上传服务已启动";
            uploaderStarted = true;
            uploaderStarting = false;
            _uploadRetry = 0;
            return;
        }

        var ips = log.match(/(\d+\.\d+\.\d+\.\d+)/g);
        if (ips) {
            for (var i = ips.length - 1; i >= 0; i--) {
                if (ips[i] !== "127.0.0.1" && ips[i].indexOf("169.254.") !== 0 && ips[i] !== "0.0.0.0") {
                    uploaderAddress = "http://" + ips[i] + ":8088";
                    uploaderStatus = "上传服务已启动";
                    uploaderStarted = true;
                    uploaderStarting = false;
                    _uploadRetry = 0;
                    return;
                }
            }
        }

        if (log.indexOf("ERROR:") >= 0) {
            // 启动失败：立即复位，让用户可以再次点击启动重试
            uploaderStarting = false;
            uploaderStarted = false;
            uploaderOutputTimer.stop();
            if (log.indexOf("busybox 存在但未编译 httpd applet") >= 0) {
                uploaderStatus = "busybox 缺少 httpd 组件，请用 SSH/SFTP 上传";
            } else if (log.indexOf("未找到可用") >= 0 || log.indexOf("未找到") >= 0) {
                uploaderStatus = "缺少运行环境，请 SSH 安装 node: opkg install node";
            } else if (log.indexOf("端口") >= 0 || log.indexOf("port") >= 0) {
                uploaderStatus = "端口 8088 被占用";
            } else {
                uploaderStatus = "上传服务启动失败";
            }
            var hint = log.match(/HINT:.*/);
            if (hint) uploaderStatus = uploaderStatus + "（" + hint[0].replace("HINT: ", "") + "）";
            return;
        }

        if (log.indexOf("Address already in use") >= 0 || log.indexOf("EADDRINUSE") >= 0) {
            uploaderStarting = false;
            uploaderStarted = false;
            uploaderOutputTimer.stop();
            uploaderStatus = "端口 8088 被占用";
            return;
        }

        _uploadRetry++;
        if (_uploadRetry > 40) {
            uploaderStarting = false;
            uploaderStarted = false;
            uploaderStatus = "上传服务启动超时，请检查网络";
            uploaderOutputTimer.stop();
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
            // 优先使用记录的 wrappedLength（换行后行数），回退到当前 lines.length
            var wrappedTotal = b.wrappedLength || lines.length || 1;
            chapDone = chapTotal > 0 && wrappedTotal > 0
                ? Math.floor((currentLine / wrappedTotal) * chapTotal) : 0;
        }
        return Math.min(100, Math.round((doneRaw + Math.min(chapDone, chapTotal)) / rawLines.length * 100));
    }

    // 保存进度到内存并立即写入文件
    function saveProgress() {
        Storage.updateProgressMemory(progressStore, currentUrl, fileName, currentLine, lines.length, currentChapterIdx, calcBookPercent(), readingTimeData[currentUrl]);
        Storage.flushProgressStore(progressStore);
    }

    // 立即将进度写入文件（关键操作时调用）
    function flushProgress() {
        if (currentUrl === "")
            return;
        Storage.updateProgressMemory(progressStore, currentUrl, fileName, currentLine, lines.length, currentChapterIdx, calcBookPercent(), readingTimeData[currentUrl]);
        Storage.flushProgressStore(progressStore);
    }

    // 格式化阅读时长（秒 -> "X时X分" / "X分X秒" / "X秒"）
    function formatReadingTime(seconds) {
        if (!seconds || seconds < 0) return "0秒";
        var h = Math.floor(seconds / 3600);
        var m = Math.floor((seconds % 3600) / 60);
        var s = seconds % 60;
        if (h > 0) return h + "时" + m + "分";
        if (m > 0) return m + "分" + s + "秒";
        return s + "秒";
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
            nightAuto: nightAuto,
            dayTheme: dayTheme,
            nightTheme: nightTheme,
            autoScrollSeconds: autoScrollSeconds,
            readerMargin: readerMargin,
            nightStartHour: nightStartHour,
            nightEndHour: nightEndHour,
            shelfSort: shelfSort,
            shelfFilter: shelfFilter,
            scrollMode: scrollMode,
            tripleTapHome: tripleTapHome,
            chapterNameMode: chapterNameMode
        };
        Storage.saveSettingsToStore(settings);
    }

    function loadSettings() {
        var settings = Storage.loadSettingsFromStore();
        var fs = parseInt(settings.fontSize);
        if (isNaN(fs)) fs = FONT_DEFAULT;
        baseFontSize = Math.max(FONT_MIN, Math.min(FONT_MAX, fs));
        lineSpacing = parseInt(settings.lineSpacing) || 4;
        themeName = settings.themeName || "默认";
        applyThemeColors();
        // 夜间模式（旧状态文件无这些字段时用默认值）
        nightAuto = settings.nightAuto === true;
        dayTheme = settings.dayTheme || "默认";
        nightTheme = settings.nightTheme || "深灰";
        nightStartHour = clampHour(settings.nightStartHour, 20);
        nightEndHour = clampHour(settings.nightEndHour, 7);
        // 兼容旧状态文件中的 lastFile 字段（新版本不再写入，也不用于自动恢复）
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
        tripleTapHome = settings.tripleTapHome === true;
        chapterNameMode = settings.chapterNameMode || "scroll";
        // 书架视图偏好（旧状态文件无此字段时用默认值）
        shelfSort = BookList.isValidSortMode(settings.shelfSort)
                    ? settings.shelfSort : BookList.SORT_RECENT;
        shelfFilter = BookList.isValidFilterMode(settings.shelfFilter)
                      ? settings.shelfFilter : BookList.FILTER_ALL;
        // 页边距（新增项，旧状态文件无此字段时用默认值）
        var m = parseInt(settings.readerMargin);
        readerMargin = (isNaN(m) ? 7 : Math.max(MARGIN_MIN, Math.min(MARGIN_MAX, m)));
        charsPerLine = ReaderUtils.updateCharsPerLine(baseFontSize);
    }

    function loadBookList() {
        shelfSource = ReaderUtils.buildBookList(folderScanAvailable, bookFolderModel, progressStore, defaultBookFolder);
        bookListTotal = ReaderUtils.getBookListTotal();
        applyShelfView();
    }

    // ====== 阅读统计 ======

    // 汇总所有书籍的阅读记录
    function readingSummary() {
        var records = [];
        for (var url in progressStore) {
            var r = progressStore[url];
            if (!r) continue;
            records.push({
                readingTime: parseInt(r.readingTime) || 0,
                bookPercent: parseInt(r.bookPercent) || 0,
                timestamp: parseInt(r.timestamp) || 0
            });
        }
        return Stats.summarize(records);
    }

    // 统计页展示用的条目（已格式化）
    function statsRows() {
        var s = readingSummary();
        var counts = shelfFilterCounts();
        return [
            { k: "累计阅读", v: Stats.formatDuration(s.totalSeconds) },
            { k: "阅读天数", v: s.activeDays + " 天" },
            { k: "日均阅读", v: s.activeDays > 0 ? Stats.formatDuration(s.avgSecondsPerDay) : "—" },
            { k: "在读书籍", v: s.bookCount + " 本" },
            { k: "已读完", v: s.finishedCount + " 本" },
            { k: "书架藏书", v: counts.all + " 本" },
            { k: "未读", v: counts.unread + " 本" },
            { k: "在读", v: counts.reading + " 本" }
        ];
    }

    // 本机实测阅读速度（用于校准剩余时间预估）
    function statsSpeedText() {
        if (readingSpeed > 0) return readingSpeed + " 字/分（本机实测）";
        return Stats.DEFAULT_CHARS_PER_MINUTE + " 字/分（默认值，读满 1 分钟后自动校准）";
    }

    function openStats() {
        statsRefreshKey++;
        navigateTo("stats");
    }

    // 应用排序与筛选，生成最终展示列表
    function applyShelfView() {
        bookList = BookList.applyView(shelfSource, shelfQuery, shelfFilter, shelfSort);
    }

    function setShelfSort(mode) {
        shelfSort = mode;
        applyShelfView();
    }

    function setShelfFilter(mode) {
        shelfFilter = mode;
        applyShelfView();
    }

    // 循环切换排序方式（320x170 上比横排五个按钮省空间）
    function cycleShelfSort() {
        var order = [BookList.SORT_RECENT, BookList.SORT_NAME, BookList.SORT_PROGRESS,
                     BookList.SORT_SIZE, BookList.SORT_UNREAD];
        var i = order.indexOf(shelfSort);
        setShelfSort(order[(i + 1) % order.length]);
        showToast("排序：" + BookList.sortLabel(shelfSort));
    }

    function setShelfQuery(q) {
        shelfQuery = q || "";
        applyShelfView();
    }

    // 各筛选条件下的书籍数量（供标签显示）
    function shelfFilterCounts() {
        return BookList.statusCounts(shelfSource);
    }

    function shelfFilterLabel(mode) {
        var c = shelfFilterCounts();
        if (mode === BookList.FILTER_ALL) return "全部 " + c.all;
        if (mode === BookList.FILTER_UNREAD) return "未读 " + c.unread;
        if (mode === BookList.FILTER_READING) return "在读 " + c.reading;
        if (mode === BookList.FILTER_DONE) return "读完 " + c.done;
        return mode;
    }

    // 书架长按菜单：重命名
    function shelfRenameBook(item) {
        if (!item) return;
        showShelfMenu = false;
        showKeyboard(item.name, function(text) {
            if (text === undefined || text.trim() === "") return;
            var newName = text.trim();
            if (!/\.txt$/i.test(newName)) newName += ".txt";
            var oldPath = stripFilePrefix(item.file);
            var lastSlash = oldPath.lastIndexOf("/");
            var dir = lastSlash >= 0 ? oldPath.substring(0, lastSlash + 1) : defaultBookFolder;
            var newPath = dir + newName;
            try {
                if (typeof shellPluginController !== "undefined" && shellPluginController)
                    shellPluginController.sendCommand("mv " + shellEscape(oldPath) + " " + shellEscape(newPath));
            } catch(e) {}
            // 修复：进度与书签都以 file://路径 为键，重命名后若不迁移，
            // 旧键会变成孤儿 —— 用户视角是「改名后从头开始读、书签全丢」。
            Storage.renameRecord(addFilePrefix(oldPath), addFilePrefix(newPath), progressStore, bookmarksStore);
            writeState("progress", JSON.stringify(progressStore));
            writeState("bookmarks", JSON.stringify(bookmarksStore));
            // 刷新书架
            Qt.callLater(function() {
                if (bookFolderModel) {
                    try { bookFolderModel.destroy(); } catch(e) {}
                    bookFolderModel = null;
                }
                folderScanAvailable = false;
                startBookFolderScan();
                loadBookList();
            });
        });
    }

    // 书架长按菜单：删除文件
    function shelfDeleteBook(item) {
        if (!item) return;
        showShelfMenu = false;
        var oldPath = stripFilePrefix(item.file);
        try {
            if (typeof shellPluginController !== "undefined" && shellPluginController)
                shellPluginController.sendCommand("rm " + shellEscape(oldPath));
        } catch(e) {}
        if (item.file) {
            // 修复：删除文件时一并清理书签，避免状态文件留下孤儿键
            Storage.purgeRecord(item.file, progressStore, bookmarksStore);
            writeState("progress", JSON.stringify(progressStore));
            writeState("bookmarks", JSON.stringify(bookmarksStore));
        }
        Qt.callLater(function() {
            if (bookFolderModel) {
                try { bookFolderModel.destroy(); } catch(e) {}
                bookFolderModel = null;
            }
            folderScanAvailable = false;
            startBookFolderScan();
            loadBookList();
        });
        showToast("已删除");
    }

    // 书架长按菜单：仅删除记录
    function shelfDeleteRecord(item) {
        if (!item) return;
        showShelfMenu = false;
        if (item.file) Storage.deleteRecord(item.file, progressStore);
        loadBookList();
        showToast("记录已删除");
    }

    function startBookFolderScan() {
        if (bookFolderModel)
            return;
        try {
            var folderUrl = "file://" + defaultBookFolder;
            var qml = "import QtQuick 2.15\nimport Qt.labs.folderlistmodel 2.1\nFolderListModel {\n" +
                "    folder: \"" + folderUrl + "\"\n" +
                "    nameFilters: [\"*.txt\", \"*.TXT\"]\n" +
                "    showDirs: false\n showFiles: true\n showDotAndDotDot: false\n sortField: FolderListModel.Name\n}";
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
        addBookmarkWithNote("");
    }

    // 新增书签，可附带备注。note 为空时行为与原来一致。
    function addBookmarkWithNote(note) {
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
            linesTotal: lines.length,   // 创建时的总行数（用于字号缩放后比例调整）
            chapterIdx: currentChapterIdx,
            percent: getBookPercent(),
            preview: preview,
            note: String(note || ""),   // 用户备注
            created: new Date().getTime()
        });
        bookmarksStore[currentUrl] = items;
        if (writeState("bookmarks", JSON.stringify(bookmarksStore))) {
            loadBookmarkList();
            showToast("已添加书签");
        } else {
            statusMessage = "添加书签失败";
            messageTimer.restart();
        }
    }

    // 编辑某条书签的备注
    function editBookmarkNote(id) {
        if (currentUrl === "")
            return;
        var items = bookmarksStore[currentUrl] || [];
        var target = null;
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === id) { target = items[i]; break; }
        }
        if (!target) return;
        showKeyboard(target.note || "", function (text) {
            target.note = String(text || "");
            if (writeState("bookmarks", JSON.stringify(bookmarksStore))) {
                loadBookmarkList();
                showToast("备注已保存");
            } else {
                statusMessage = "备注保存失败";
                messageTimer.restart();
            }
        });
    }

    // 导出当前书籍的书签为文本文件
    function exportBookmarks() {
        if (currentUrl === "" || bookmarkList.length === 0) {
            showToast("没有可导出的书签");
            return;
        }
        var ctrl = (typeof shellPluginController !== "undefined") ? shellPluginController : null;
        if (!ctrl) {
            showToast("当前环境不支持导出");
            return;
        }
        var text = buildBookmarkExport();
        // 用 base64 传输，避免内容中的引号/换行破坏 shell 命令
        var b64 = Qt.btoa(unescape(encodeURIComponent(text)));
        var safe = b64.replace(/'/g, "'\\''");
        var out = "/userdisk/" + sanitizeFileName(fileName) + "-书签.txt";
        ctrl.sendCommand("mkdir -p /userdisk 2>/dev/null; "
            + "printf '%s' '" + safe + "' | base64 -d > " + shellEscape(out) + " 2>/dev/null; "
            + "[ -s " + shellEscape(out) + " ] && echo OK || echo FAIL");
        showToast("已导出到 " + out);
    }

    // 生成书签导出文本
    function buildBookmarkExport() {
        var t = "《" + fileName + "》书签\n";
        t += "导出时间：" + new Date().toLocaleString() + "\n";
        t += "共 " + bookmarkList.length + " 条\n";
        t += "----------------------------------------\n";
        for (var i = 0; i < bookmarkList.length; i++) {
            var b = bookmarkList[i];
            var ch = parseInt(b.chapterIdx);
            t += (i + 1) + ". ";
            if (!isNaN(ch) && ch >= 0 && ch < chapterBoundaries.length)
                t += "【" + chapterBoundaries[ch].title + "】";
            t += " 进度 " + (parseInt(b.percent) || 0) + "%\n";
            if (b.preview) t += "   原文：" + b.preview + "\n";
            if (b.note) t += "   备注：" + b.note + "\n";
            t += "\n";
        }
        return t;
    }

    // 文件名安全化（去掉路径分隔符等）
    function sanitizeFileName(name) {
        return String(name || "book").replace(/[\/:*?"<>|]/g, "_");
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

    // HTML 转义（用于 StyledText 中安全嵌入用户文本）
    function escapeHtml(str) {
        if (typeof str !== "string") return "";
        return str.replace(/&/g, "&amp;")
                  .replace(/</g, "&lt;")
                  .replace(/>/g, "&gt;");
    }

    function shellEscape(str) {
        return "'" + str.replace(/'/g, "'\''") + "'";
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

    // 阅读器底部状态栏高度（必须从文本可容纳行数中扣除，否则最后一行被压住）
    readonly property int readerStatusBarHeight: 14

    function getLinesPerPage() {
        var th = getTextLineHeight();
        return ReaderUtils.getLinesPerPage(root.height, readerMargin, th, readerStatusBarHeight);
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

    // 清空阅读器状态（公共逻辑）
    function clearReaderState() {
        if (animating) {
            pageSlideAnim.stop();
            pageTurnOverlay.visible = false;
            pageTurnOverlay.x = 0;
            pageTurnOverlay.y = 0;
            turnIsVertical = false;
            animating = false;
            turnDirection = 0;
            pendingLine = -1;
        }
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
    }

    function returnToShelf() {
        clearReaderState();
        navigateRoot();
        // 修复：此处原先只调 loadBookList()，不重扫目录，
        // 导致从阅读器返回书架时看不到期间新增/删除的文件。
        refreshShelf();
        navigateTo("shelf");
    }

    function returnToHome() {
        clearReaderState();
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

        // 记录本次阅读会话的起点，用于实测阅读速度
        sessionStartMs = new Date().getTime();
        sessionCharsAtStart = 0;

        // 清空上一本书的搜索结果（行号已无意义）
        searchQuery = "";
        searchResults = [];
        searchTotal = 0;
        searchTruncated = false;
        pendingSearchRatio = -1;

        // 取消上一本书残留的编码探测/转码任务，避免回调污染新书籍
        encodingProbeTimer.stop();
        encodingConvertTimer.stop();
        encodingProbeUrl = "";
        encodingConvertUrl = "";
        encodingConverting = false;
        encodingProbeRetry = 0;
        encodingConvertRetry = 0;

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
        detectedEncoding = "";
        encodingNotice = "";

        // 先检测编码：GBK/BIG5/UTF-16 的 txt 若直接按 UTF-8 读取会变乱码，
        // 需要先转码为 UTF-8 的临时文件再加载。
        detectEncodingThenLoad(url);
    }

    // ====== 编码检测与转码 ======

    // ====== 编码检测与转码 ======
    //
    // 流程：探测编码 → 若非 UTF-8 则转码到临时文件 → 加载（临时文件或原文件）
    // shellPluginController 无输出回传，因此通过「命令写结果文件 + 轮询读取」获取结论。
    // 轮询用异步 XHR，避免阻塞渲染线程。

    function detectEncodingThenLoad(url) {
        var ctrl = (typeof shellPluginController !== "undefined") ? shellPluginController : null;
        if (!ctrl) {
            // 无 shell 能力（如预览环境）时退回原逻辑，仅支持 UTF-8
            doLoadFile(url, encodePath(url));
            return;
        }
        encodingProbeUrl = url;
        encodingProbeRetry = 0;
        encodingProbeTimer.start();
        try {
            ctrl.sendCommand(Encoding.buildDetectToFileCommand(url));
        } catch (e) {
            // 探测命令失败不阻塞阅读，直接按 UTF-8 打开
            encodingProbeTimer.stop();
            doLoadFile(url, encodePath(url));
        }
    }

    // 轮询探测结果文件
    function pollEncodingResult() {
        if (encodingProbeUrl === "")
            return;
        var ctrl = (typeof shellPluginController !== "undefined") ? shellPluginController : null;
        if (!ctrl) {
            encodingProbeTimer.stop();
            doLoadFile(encodingProbeUrl, encodePath(encodingProbeUrl));
            return;
        }
        // 用 cat 把结果文件内容送到 QML 可见的位置（读文件走 XHR）
        var rp = Encoding.resultPathFor(encodingProbeUrl);
        _readTextFile(rp, function (text) {
            if (encodingProbeUrl === "") return;   // 期间已切换书籍
            var enc = Encoding.parseResultFile(text);
            if (enc === "" && encodingProbeRetry < 20) {
                encodingProbeRetry++;   // 命令尚未执行完，继续等
                return;
            }
            encodingProbeTimer.stop();
            applyEncoding(encodingProbeUrl, enc);
        });
    }

    // 依据探测结果决定「直接加载」还是「先转码再加载」
    function applyEncoding(url, enc) {
        detectedEncoding = enc;
        if (!Encoding.needConvert(enc)) {
            doLoadFile(url, encodePath(url));
            return;
        }
        var ctrl = (typeof shellPluginController !== "undefined") ? shellPluginController : null;
        if (!ctrl) {
            doLoadFile(url, encodePath(url));
            return;
        }
        encodingConverting = true;
        statusMessage = "正在转换编码（" + Encoding.encodingLabel(enc) + "）…";
        var converted = Encoding.tempPathFor(url);
        try {
            ctrl.sendCommand(Encoding.buildConvertCommand(url, enc));
        } catch (e) {
            encodingConverting = false;
            doLoadFile(url, encodePath(url));
            return;
        }
        encodingConvertUrl = url;
        encodingConvertTarget = converted;
        encodingConvertRetry = 0;
        encodingConvertTimer.start();
    }

    // 轮询转码结果（转换完成后直接读临时文件）
    function pollEncodingConvert() {
        if (encodingConvertUrl === "")
            return;
        if (encodingConvertRetry++ > 40) {
            // 超时：退回原文件，至少能打开（可能乱码）
            encodingConvertTimer.stop();
            encodingConverting = false;
            statusMessage = "编码转换超时，已按原样打开";
            doLoadFile(encodingConvertUrl, encodePath(encodingConvertUrl));
            encodingConvertUrl = "";
            return;
        }
        var target = encodingConvertTarget;
        _readTextFile(target, function (text) {
            if (encodingConvertUrl === "") return;
            if (text === "") return;   // 尚未生成，继续等
            encodingConvertTimer.stop();
            encodingConverting = false;
            encodingNotice = "已自动转换为 " + Encoding.encodingLabel(detectedEncoding);
            var u = encodingConvertUrl;
            encodingConvertUrl = "";
            // 加载转码后的临时文件（此时必为 UTF-8）
            doLoadFile(u, encodePath("file://" + target));
        });
    }

    // 异步读取文本文件（不阻塞 UI）；失败或不存在时回调空串
    function _readTextFile(path, callback) {
        try {
            var xhr2 = new XMLHttpRequest();
            xhr2.open("GET", "file://" + path, true);
            xhr2.onreadystatechange = function () {
                if (xhr2.readyState !== XMLHttpRequest.DONE) return;
                var t = "";
                if (xhr2.status === 200 || xhr2.status === 0)
                    t = xhr2.responseText || "";
                callback(t);
            };
            xhr2.onerror = function () { callback(""); };
            xhr2.send();
        } catch (e) {
            callback("");
        }
    }

    // originalUrl 始终是「原书路径」——进度、书签都以它为键，
    // 不能因转码临时文件而改变键值。
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
            } else if (requestUrl !== originalUrl && encodingConvertTarget === "") {
                // 路径编码回退：仅当不是「转码临时文件」时才重试原路径，
                // 否则会拿乱码文件再试一次，无意义且可能死循环
                doLoadFile(originalUrl, originalUrl);
                return;
            } else {
                isLoading = false;
                lines = [];
                chapterList = [];
                currentLine = 0;
                statusMessage = encodingConverting ? "编码转换失败" : "无法打开文件";
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
        var regex = ReaderUtils.getChapterRegex();
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
        var result = ReaderUtils.wrapLines(chapterRaw, charsPerLine * 2 - 1);
        lines = result.lines;
        chapterBoundaries[idx].wrappedLength = lines.length;
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

        // 跨章搜索跳转：章节切换后按记录的比例定位
        if (pendingSearchRatio >= 0) {
            currentLine = Math.min(Math.floor(pendingSearchRatio * lines.length), maxStartLine());
            clampCurrentLine();
            if (scrollMode) {
                scrollFlickable.contentY = currentLine * getTextLineHeight();
            }
            pendingSearchRatio = -1;
        }

        updateChapterCharStats();
        // 首次进入本书时，把会话字符起点对齐到当前位置，
        // 避免把「打开前的历史进度」误算进本次速度样本
        if (sessionStartMs === 0) {
            sessionStartMs = new Date().getTime();
            sessionCharsAtStart = currentCharOffset();
        }
        updateChapterList();
        updateScrollMax();
        loadBookmarkList();
        saveSettings();
        isLoading = false;
        statusMessage = "";
    }

    // 计算全书与各章的字符统计（在解析完成后调用一次）
    function computeCharStats() {
        chapterCharOffsets = [];
        var acc = 0;
        var total = 0;
        for (var i = 0; i < chapterBoundaries.length; i++) {
            var b = chapterBoundaries[i];
            var chars = 0;
            for (var j = b.startRaw; j < b.endRaw; j++) {
                chars += (rawLines[j] ? rawLines[j].length : 0) + 1;  // +1 计换行
            }
            chapterCharOffsets.push({ start: acc, chars: chars });
            acc += chars;
        }
        total = acc;
        bookCharTotal = total;
        updateChapterCharStats();
    }

    // 更新「当前章节」相关的字符统计量
    function updateChapterCharStats() {
        if (currentChapterIdx >= 0 && currentChapterIdx < chapterCharOffsets.length) {
            var c = chapterCharOffsets[currentChapterIdx];
            chapterCharsBefore = c.start;
            chapterCharCount = c.chars;
        } else {
            chapterCharsBefore = 0;
            chapterCharCount = 0;
        }
    }

    // 当前阅读位置对应的全书字符偏移
    function currentCharOffset() {
        if (chapterCharCount <= 0) return 0;
        var inChapter = 0;
        if (lines.length > 0 && chapterCharOffsets.length > currentChapterIdx
            && currentChapterIdx >= 0) {
            var perLine = chapterCharCount / Math.max(1, lines.length);
            inChapter = Math.round(currentLine * perLine);
        }
        return chapterCharsBefore + Math.min(inChapter, chapterCharCount);
    }

    // 全书进度百分比（基于字符偏移）
    function getBookPercent() {
        if (bookCharTotal <= 0) return getProgressPercent();
        return Stats.bookPercent(currentCharOffset(), bookCharTotal);
    }

    // 本章进度百分比
    function getChapterPercent() {
        if (chapterCharCount <= 0) return getProgressPercent();
        var inChapter = currentCharOffset() - chapterCharsBefore;
        return Stats.chapterPercent(inChapter, chapterCharCount);
    }

    // 预计剩余阅读时长（秒）；速度未测得时用默认值估算
    function getRemainingSeconds() {
        if (bookCharTotal <= 0) return 0;
        var remain = bookCharTotal - currentCharOffset();
        return Stats.estimatedRemainingSeconds(remain, readingSpeed);
    }

    // 剩余时长的可读文案
    function getRemainingText() {
        var sec = getRemainingSeconds();
        if (sec <= 0) return "已读完";
        return "剩余约 " + Stats.formatRemaining(sec);
    }

    // 依据本次会话「读了多久 / 读了多少字」估算阅读速度。
    // 样本不足或数值异常时保持 0（表示未测得），由估算函数退回默认速度。
    function updateReadingSpeed() {
        if (sessionStartMs <= 0 || currentUrl === "") return;
        var elapsed = (new Date().getTime() - sessionStartMs) / 1000;
        if (elapsed < 60) return;                     // 至少读满 1 分钟才有参考价值
        var charsRead = currentCharOffset() - sessionCharsAtStart;
        var spd = Stats.estimateSpeed(charsRead, elapsed);
        if (spd > 0) readingSpeed = spd;
    }

    // ====== 全文搜索 ======

    function openSearch() {
        searchQuery = "";
        searchResults = [];
        searchTotal = 0;
        searchTruncated = false;
        activePanel = "search";
    }

    // 执行搜索（基于 rawLines，不受换行与字号影响）
    function runSearch(query) {
        searchQuery = query || "";
        if (searchQuery === "") {
            searchResults = [];
            searchTotal = 0;
            searchTruncated = false;
            return;
        }
        if (!rawLines || rawLines.length === 0) {
            searchResults = [];
            searchTotal = 0;
            return;
        }
        var r = Search.search(rawLines, searchQuery, {
            caseSensitive: searchCaseSensitive,
            wholeWord: searchWholeWord
        });
        searchResults = r.hits;
        searchTotal = r.total;
        searchTruncated = r.truncated;
    }

    // 按章节归组，供结果列表展示
    function searchGroups() {
        if (!searchResults || searchResults.length === 0) return [];
        return Search.groupByChapter(searchResults, chapterBoundaries);
    }

    // 跳转到某条搜索结果
    function jumpToSearchHit(hit) {
        if (!hit) return;
        var targetChapter = Search.chapterIndexForLine(hit.line, chapterBoundaries);
        if (targetChapter < 0) targetChapter = 0;

        // 计算该原始行在目标章节内的行号
        var b = chapterBoundaries[targetChapter];
        var rawLineInChapter = hit.line - b.startRaw;

        if (targetChapter === currentChapterIdx) {
            // 已在该章：直接按比例定位到对应换行后的行
            var b2 = chapterBoundaries[currentChapterIdx];
            var rawCount = Math.max(1, b2.endRaw - b2.startRaw);
            var ratio = rawLineInChapter / rawCount;
            currentLine = Math.min(Math.floor(ratio * lines.length), maxStartLine());
            clampCurrentLine();
            if (scrollMode) {
                scrollFlickable.contentY = currentLine * getTextLineHeight();
            }
            closePanels();
            return;
        }

        // 跨章：切章后再定位。loadChapter 会从保存的进度恢复，
        // 因此这里用待定位变量在 loadChapter 完成后校正。
        pendingSearchRatio = rawLineInChapter / Math.max(1, b.endRaw - b.startRaw);
        loadChapter(targetChapter);
        closePanels();
    }

    function updateChapterList() {
        chapterList = [];
        for (var i = 0; i < chapterBoundaries.length; i++) {
            chapterList.push({ title: chapterBoundaries[i].title, lineIndex: i });
        }
    }

    function buildChapterList() {
        chapterSearchQuery = "";
        filterChapterList();
    }

    function filterChapterList() {
        var q = chapterSearchQuery.trim().toLowerCase();
        if (q === "") {
            filteredChapterList = chapterList;
            return;
        }
        var result = [];
        for (var i = 0; i < chapterList.length; i++) {
            if (chapterList[i].title.toLowerCase().indexOf(q) >= 0)
                result.push(chapterList[i]);
        }
        filteredChapterList = result;
    }

    function formatChapterTitle(title) {
        if (chapterNameMode === "short") {
            // 提取"第X章"部分
            var m = title.match(/(第[^章节回集卷部篇]+[章节回集卷部篇])/);
            return m ? m[1] : title;
        }
        return title; // scroll 模式由 Text 的 elide 处理
    }

    function processContent(content) {
        try {
            rawLines = ReaderUtils.splitIntoLines(content);
            chapterBoundaries = scanChapterBoundaries(rawLines);
            computeCharStats();

            // 读取保存的进度 → 定位到对应章节
            var saved = loadProgress(currentUrl);
            var savedChapter = (saved && saved.chapterIdx !== undefined) ? saved.chapterIdx : 0;
            if (savedChapter >= chapterBoundaries.length) savedChapter = 0;

            // 恢复阅读时长
            readingTimeData[currentUrl] = (saved && saved.readingTime !== undefined) ? saved.readingTime : 0;

            loadChapter(savedChapter);
        } catch (e) {
            rawLines = [];
            chapterBoundaries = [];
            lines = [];
            chapterList = [];
            currentLine = 0;
            currentChapterIdx = -1;
            isLoading = false;
            statusMessage = "文件处理失败";
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

        // 设置覆盖层滑入方向
        turnDirection = 1;
        turnShadow.anchors.left = turnShadow.parent.left;
        turnShadow.anchors.right = undefined;
        turnShadow.color = Qt.rgba(0, 0, 0, 0);
        pageTurnOverlay.x = 0;
        pageTurnOverlay.y = 0;
        pageTurnOverlay.visible = true;
        animating = true;
        pendingLine = newLine;

        if (turnIsVertical) {
            pageSlideAnim.property = "y";
            pageSlideAnim.from = readerPage.height;
        } else {
            pageSlideAnim.property = "x";
            pageSlideAnim.from = readerPage.width;
        }
        pageSlideAnim.to = 0;
        pageSlideAnim.start();

        // 保存进度到内存并立即写入文件
        Storage.updateProgressMemory(progressStore, currentUrl, fileName, newLine, lines.length, currentChapterIdx, calcBookPercent(), readingTimeData[currentUrl]);
        progressFlushTimer.restart();
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

        // 设置覆盖层滑入方向
        turnDirection = -1;
        turnShadow.anchors.left = undefined;
        turnShadow.anchors.right = turnShadow.parent.right;
        turnShadow.color = Qt.rgba(0, 0, 0, 0);
        pageTurnOverlay.x = 0;
        pageTurnOverlay.y = 0;
        pageTurnOverlay.visible = true;
        animating = true;
        pendingLine = newLine;

        if (turnIsVertical) {
            pageSlideAnim.property = "y";
            pageSlideAnim.from = -readerPage.height;
        } else {
            pageSlideAnim.property = "x";
            pageSlideAnim.from = -readerPage.width;
        }
        pageSlideAnim.to = 0;
        pageSlideAnim.start();

        Storage.updateProgressMemory(progressStore, currentUrl, fileName, newLine, lines.length, currentChapterIdx, calcBookPercent(), readingTimeData[currentUrl]);
        progressFlushTimer.restart();
    }

    function jumpToPercent(percent) {
        if (lines.length === 0)
            return;
        var lpp = getLinesPerPage();
        percent = Math.max(0, Math.min(100, percent));
        currentLine = Math.floor((percent / 100) * lines.length);
        clampCurrentLine();
        currentLine = Math.min(Math.floor(currentLine / lpp) * lpp, maxStartLine());
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

    // ====== 排版调节 ======

    function stepFontSize(delta) {
        var v = baseFontSize + delta;
        if (v < FONT_MIN) v = FONT_MIN;
        if (v > FONT_MAX) v = FONT_MAX;
        if (v !== baseFontSize) setFontSize(v);
    }

    function stepLineSpacing(delta) {
        var v = lineSpacing + delta;
        if (v < LINE_SPACING_MIN) v = LINE_SPACING_MIN;
        if (v > LINE_SPACING_MAX) v = LINE_SPACING_MAX;
        if (v !== lineSpacing) {
            lineSpacing = v;
            rewrapCurrentChapter();
            saveSettings();
        }
    }

    function stepMargin(delta) {
        var v = readerMargin + delta;
        if (v < MARGIN_MIN) v = MARGIN_MIN;
        if (v > MARGIN_MAX) v = MARGIN_MAX;
        if (v !== readerMargin) {
            readerMargin = v;
            rewrapCurrentChapter();
            saveSettings();
        }
    }

    // 行距/边距变化后需要重新换行（每页容纳的行数变了），
    // 但字符内容不变，因此按比例保持阅读位置。
    function rewrapCurrentChapter() {
        if (currentUrl === "" || currentChapterIdx < 0 || chapterBoundaries.length === 0)
            return;
        var ratio = lines.length > 0 ? (currentLine / lines.length) : 0;
        var b = chapterBoundaries[currentChapterIdx];
        var chapterRaw = rawLines.slice(b.startRaw, b.endRaw);
        var result = ReaderUtils.wrapLines(chapterRaw, charsPerLine * 2 - 1);
        lines = result.lines;
        currentLine = Math.min(Math.floor(ratio * lines.length), maxStartLine());
        clampCurrentLine();
        updateScrollMax();
        if (scrollMode) {
            scrollFlickable.contentY = currentLine * getTextLineHeight();
        }
    }

    function setFontSize(size) {
        var ratio = lines.length > 0 ? currentLine / lines.length : 0;
        baseFontSize = size;
        updateCharsPerLine();
        if (currentUrl !== "" && currentChapterIdx >= 0 && chapterBoundaries.length > 0) {
            // 重新加载当前章节（使用新字号换行），保持阅读比例
            var b = chapterBoundaries[currentChapterIdx];
            var chapterRaw = rawLines.slice(b.startRaw, b.endRaw);
            var result = ReaderUtils.wrapLines(chapterRaw, charsPerLine * 2 - 1);
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
        applyThemeColors();
        saveSettings();
    }

    // 当前小时是否落在夜间区间（支持跨零点，如 20 → 7）
    // 小时值收敛到 0-23
    function clampHour(v, def) {
        var n = parseInt(v);
        if (isNaN(n)) return def;
        return Math.max(0, Math.min(23, n));
    }

    function isNightHour(hour) {
        var h = (hour === undefined) ? new Date().getHours() : hour;
        if (nightStartHour === nightEndHour) return false;   // 区间为空视为不切换
        if (nightStartHour < nightEndHour)
            return h >= nightStartHour && h < nightEndHour;
        // 跨零点：h >= start 或 h < end
        return h >= nightStartHour || h < nightEndHour;
    }

    // 依据时间自动套用日/夜主题（仅在用户启用时生效）
    function applyAutoTheme() {
        if (!nightAuto) return;
        var target = isNightHour() ? nightTheme : dayTheme;
        if (themeName !== target) setTheme(target);
    }

    // 把当前主题的各个颜色槽位同步到属性上
    function applyThemeColors() {
        bgColor = ReaderUtils.themeColor(themeName, "bg");
        textColor = ReaderUtils.themeColor(themeName, "fg");
        cardColor = ReaderUtils.themeColor(themeName, "card");
        borderColor = ReaderUtils.themeColor(themeName, "border");
        subTextColor = ReaderUtils.themeColor(themeName, "sub");
        accentColor = ReaderUtils.themeColor(themeName, "accent");
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
                color: subTextColor
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
                    // 启动中显示中性色，已启动显示「取消」，失败后自动回到「启动」可重试
                    color: (uploaderStarted || uploaderStarting) ? "#FFEBEE" : "#E3F2FD"
                    border.color: (uploaderStarted || uploaderStarting) ? "#EF9A9A" : "#BBDEFB"
                    Text {
                        anchors.centerIn: parent
                        text: uploaderStarting ? "启动中…"
                                               : (uploaderStarted ? "取消上传" : "启动上传")
                        font.pixelSize: 11
                        color: uploaderStarting ? "#8D6E63"
                                                : (uploaderStarted ? "#D32F2F" : "#1565C0")
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (uploaderStarting) {
                                stopUploaderService();
                            } else if (uploaderStarted) {
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
                    color: cardColor
                    border.color: borderColor
                    Text {
                        anchors.centerIn: parent
                        text: "设置"
                        font.pixelSize: 11
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: navigateTo("settings")
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 34
                radius: 4
                color: cardColor
                border.color: borderColor
                Text {
                    anchors.centerIn: parent
                    text: "我的书架 (" + bookList.length + ")"
                    font.pixelSize: 13
                    font.bold: true
                    color: textColor
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
                        text: "赞赏作者"
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

            // 状态筛选标签
            Row {
                width: parent.width
                height: 22
                spacing: 4

                Repeater {
                    model: BookList.FILTER_MODES
                    delegate: Rectangle {
                        width: (parent.width - 38) / 4
                        height: 22
                        radius: 3
                        color: shelfFilter === modelData.value ? "#2f7dcc" : "#EEEEEE"
                        Text {
                            anchors.centerIn: parent
                            text: shelfFilterLabel(modelData.value)
                            font.pixelSize: 9
                            color: shelfFilter === modelData.value ? "#FFFFFF" : "#666666"
                            elide: Text.ElideRight
                            width: parent.width - 2
                            horizontalAlignment: Text.AlignHCenter
                            font.family: "Microsoft YaHei"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: setShelfFilter(modelData.value)
                        }
                    }
                }

                // 排序切换（点击循环切换，避免单独占一行 —— 320x170 上空间紧张）
                Rectangle {
                    width: 34
                    height: 22
                    radius: 3
                    color: "#8D6E63"
                    Text {
                        anchors.centerIn: parent
                        text: "⇅"
                        font.pixelSize: 12
                        color: "#FFFFFF"
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: cycleShelfSort()
                    }
                }
            }

            // 当前排序与搜索状态提示
            Text {
                width: parent.width
                height: 12
                text: "排序：" + BookList.sortLabel(shelfSort)
                      + (shelfQuery !== "" ? ("　筛选：“" + shelfQuery + "”") : "")
                font.pixelSize: 9
                color: subTextColor
                elide: Text.ElideRight
                font.family: "Microsoft YaHei"
            }

            ListView {
                width: parent.width
                // 顶栏24 + 筛选22 + 排序提示12 + 间距 ~12 + 底部 28
                height: parent.height - 104
                clip: true
                spacing: 3
                model: bookList
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    width: parent.width
                    height: 24
                    radius: 3
                    color: bookMouse.pressed ? "#E0D8C8" : "#F8F4EC"
                    border.color: borderColor

                    MouseArea {
                        id: bookMouse
                        anchors.fill: parent
                        z: 0
                        pressAndHoldInterval: 600
                        onClicked: {
                            isLoading = true;
                            statusMessage = "";
                            loadFile(modelData.file);
                        }
                        onPressAndHold: {
                            shelfContextItem = modelData;
                            showShelfMenu = true;
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
                            color: textColor
                            elide: Text.ElideMiddle
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: "Microsoft YaHei"
                        }
                        Text {
                            text: (modelData.progress || 0) + "%"
                            font.pixelSize: 9
                            color: subTextColor
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: "Microsoft YaHei"
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: bookList.length === 0
                    text: shelfSource.length > 0
                          ? "没有符合条件的书籍"
                          : ("暂无小说\n请将 txt 放到 " + defaultBookFolder)
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
        // 阅读器底部状态栏（定高 14px，与 readerStatusBarHeight 一致）。
        // 文本区域的行数计算已扣除该高度，避免最后一行被压住。
        Rectangle {
            id: readerStatusBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.readerStatusBarHeight
            color: "transparent"

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: "#00000010"
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: root.readerMargin
                anchors.verticalCenter: parent.verticalCenter
                text: "全书 " + getBookPercent() + "%　" + getRemainingText()
                font.pixelSize: 8
                color: subTextColor
                font.family: "Microsoft YaHei"
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: root.readerMargin
                anchors.verticalCenter: parent.verticalCenter
                text: getCurrentPage() + "/" + getTotalPages() + " 页"
                font.pixelSize: 8
                color: subTextColor
                font.family: "Microsoft YaHei"
            }
        }

        Text {
            id: contentText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: readerMargin
            anchors.rightMargin: readerMargin
            anchors.topMargin: readerMargin
            // 底部扣除：边距 + 状态栏高度（+ 章末「下一章」按钮预留）
            anchors.bottomMargin: readerMargin + root.readerStatusBarHeight
                                 + (!scrollMode && showNextChapter ? 26 : 0)
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
            // 同样扣除状态栏高度，避免内容被压住
            anchors.bottomMargin: readerMargin + root.readerStatusBarHeight
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
                    Storage.updateProgressMemory(progressStore, currentUrl, fileName, currentLine, lines.length, currentChapterIdx, calcBookPercent(), readingTimeData[currentUrl]);
                    Storage.flushProgressStore(progressStore);
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
                    }
                    MouseArea {
                        anchors.fill: parent
                        visible: scrollMode && currentChapterIdx > 0
                        onClicked: {
                            saveProgress();
                            loadChapter(currentChapterIdx - 1);
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
                    }
                    MouseArea {
                        anchors.fill: parent
                        visible: scrollMode && currentChapterIdx < chapterBoundaries.length - 1
                        onClicked: {
                            saveProgress();
                            loadChapter(currentChapterIdx + 1);
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
            x: 0
            y: 0
            width: parent.width
            height: parent.height
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
                pageTurnOverlay.y = 0;
                turnIsVertical = false;
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
                    turnIsVertical = Math.abs(dy) > Math.abs(dx);
                    if (turnIsVertical) {
                        if (dy < 0) nextPage();
                        else prevPage();
                    } else {
                        if (dx < 0) nextPage();
                        else prevPage();
                    }
                    return;
                }

                // 三击检测
                if (tripleTapHome) {
                    var now = new Date().getTime();
                    tapTimestamps.push(now);
                    // 只保留最近 700ms 内的点击
                    while (tapTimestamps.length > 0 && tapTimestamps[0] < now - 700)
                        tapTimestamps.shift();
                    if (tapTimestamps.length >= 3) {
                        tapTimestamps = [];
                        returnToHome();
                        return;
                    }
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

    // ====== 阅读统计页面 ======
    Item {
        id: statsPage
        anchors.fill: parent
        visible: pageMode === "stats"

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 5

            Row {
                width: parent.width
                height: 24
                spacing: 6

                Rectangle {
                    width: 50
                    height: 24
                    radius: 4
                    color: borderColor
                    Text {
                        anchors.centerIn: parent
                        text: "返回"
                        font.pixelSize: 11
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: navigateBack()
                    }
                }

                Text {
                    width: parent.width - 102
                    height: 24
                    text: "阅读统计"
                    font.pixelSize: 13
                    font.bold: true
                    color: textColor
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    font.family: "Microsoft YaHei"
                }

                Rectangle {
                    width: 40
                    height: 24
                    radius: 4
                    color: cardColor
                    Text {
                        anchors.centerIn: parent
                        text: "刷新"
                        font.pixelSize: 10
                        color: subTextColor
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { statsRefreshKey++; }
                    }
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 30
                contentWidth: width
                contentHeight: statsCol.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: statsCol
                    width: parent.width
                    spacing: 4

                    Text {
                        width: parent.width
                        text: "阅读概况"
                        font.pixelSize: 11
                        font.bold: true
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }

                    Repeater {
                        // 依赖 statsRefreshKey，点「刷新」或重新进入时重算
                        model: statsRefreshKey >= 0 ? statsRows() : []
                        delegate: Rectangle {
                            width: statsCol.width
                            height: 26
                            radius: 3
                            color: cardColor
                            border.color: borderColor

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8

                                Text {
                                    width: parent.width * 0.55
                                    text: modelData.k
                                    font.pixelSize: 11
                                    color: subTextColor
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: "Microsoft YaHei"
                                }
                                Text {
                                    width: parent.width * 0.45
                                    text: modelData.v
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: "#2f7dcc"
                                    horizontalAlignment: Text.AlignRight
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: "Microsoft YaHei"
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: cardColor }

                    Text {
                        width: parent.width
                        text: "阅读速度"
                        font.pixelSize: 11
                        font.bold: true
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }

                    Text {
                        width: parent.width
                        text: statsSpeedText()
                        font.pixelSize: 10
                        color: subTextColor
                        wrapMode: Text.WordWrap
                        font.family: "Microsoft YaHei"
                    }

                    Rectangle { width: parent.width; height: 1; color: cardColor }

                    Text {
                        width: parent.width
                        text: "说明"
                        font.pixelSize: 11
                        font.bold: true
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }

                    Text {
                        width: parent.width
                        text: "· 阅读时长在阅读时自动累计，每 5 秒保存一次\n"
                              + "· 阅读天数为有阅读记录的自然日天数\n"
                              + "· 速度用于估算剩余阅读时间，样本不足时用默认值"
                        font.pixelSize: 9
                        color: subTextColor
                        lineHeight: 1.4
                        wrapMode: Text.WordWrap
                        font.family: "Microsoft YaHei"
                    }
                }
            }
        }
    }

    Item {
        id: settingsPage
        anchors.fill: parent
        visible: pageMode === "settings"
        clip: true

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4

            Row {
                width: parent.width
                height: 24
                spacing: 6

                Rectangle {
                    width: 50
                    height: 24
                    radius: 4
                    color: borderColor
                    Text {
                        anchors.centerIn: parent
                        text: "返回"
                        font.pixelSize: 11
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: navigateBack()
                    }
                }

                Text {
                    width: parent.width - 102
                    height: 24
                    text: "设置"
                    font.pixelSize: 13
                    font.bold: true
                    color: textColor
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    font.family: "Microsoft YaHei"
                }

                Rectangle {
                    width: 40
                    height: 24
                    radius: 4
                    color: "#E3F2FD"
                    border.color: "#BBDEFB"
                    Text {
                        anchors.centerIn: parent
                        text: "关于"
                        font.pixelSize: 10
                        color: "#1565C0"
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: showToast("电子书阅读器 v6.5.0")
                    }
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 28
                contentWidth: width
                contentHeight: settingsCol.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: settingsCol
                    width: parent.width
                    spacing: 6

                    Text {
                        width: parent.width
                        text: "小说目录：" + defaultBookFolder
                        font.pixelSize: 9
                        color: subTextColor
                        wrapMode: Text.WordWrap
                        font.family: "Microsoft YaHei"
                    }

                    // 阅读统计入口
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 3
                        color: "#E3F2FD"
                        border.color: "#BBDEFB"

                        Text {
                            anchors.centerIn: parent
                            text: "阅读统计 ›"
                            font.pixelSize: 11
                            color: "#1565C0"
                            font.family: "Microsoft YaHei"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: openStats()
                        }
                    }

                    // 手势设置
                    Rectangle { width: parent.width; height: 1; color: cardColor }

                    Text {
                        text: "手势"
                        font.pixelSize: 11
                        font.bold: true
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }

                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 3
                        color: cardColor
                        border.color: borderColor

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 4

                            Text {
                                text: "三击返回首页"
                                font.pixelSize: 11
                                color: textColor
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: "Microsoft YaHei"
                            }
                            Item { width: parent.width - 110; height: 1 }

                            Rectangle {
                                width: 40
                                height: 20
                                radius: 10
                                color: tripleTapHome ? "#4CAF50" : "#CCCCCC"
                                anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    x: tripleTapHome ? 22 : 2
                                    y: 2
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: "#FFFFFF"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        tripleTapHome = !tripleTapHome;
                                        saveSettings();
                                    }
                                }
                            }
                        }
                    }

                    // 章节名显示模式
                    Rectangle { width: parent.width; height: 1; color: cardColor }

                    Text {
                        text: "章节名显示"
                        font.pixelSize: 11
                        font.bold: true
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }

                    Row {
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            width: (parent.width - 6) / 2
                            height: 24
                            radius: 3
                            color: chapterNameMode === "scroll" ? "#2f7dcc" : "#EEEEEE"
                            Text {
                                anchors.centerIn: parent
                                text: "滚动显示"
                                font.pixelSize: 10
                                color: chapterNameMode === "scroll" ? "#fff" : "#333"
                                font.family: "Microsoft YaHei"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    chapterNameMode = "scroll";
                                    saveSettings();
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - 6) / 2
                            height: 24
                            radius: 3
                            color: chapterNameMode === "short" ? "#2f7dcc" : "#EEEEEE"
                            Text {
                                anchors.centerIn: parent
                                text: "仅显示第X章"
                                font.pixelSize: 10
                                color: chapterNameMode === "short" ? "#fff" : "#333"
                                font.family: "Microsoft YaHei"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    chapterNameMode = "short";
                                    saveSettings();
                                }
                            }
                        }
                    }

                    Item { width: parent.width; height: 8 }
                }
            }
        }
    }

    // ====== 章节列表全屏页面 ======
    Rectangle {
        id: chapterListPage
        anchors.fill: parent
        visible: pageMode === "chapterList"
        color: bgColor

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4

            Row {
                width: parent.width
                height: 24
                spacing: 6

                Rectangle {
                    width: 50
                    height: 24
                    radius: 4
                    color: borderColor
                    Text {
                        anchors.centerIn: parent
                        text: "返回"
                        font.pixelSize: 11
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: navigateBack()
                    }
                }

                Text {
                    width: parent.width - 102
                    height: 24
                    text: "章节 (" + filteredChapterList.length + ")"
                    font.pixelSize: 13
                    font.bold: true
                    color: textColor
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.family: "Microsoft YaHei"
                }

                Rectangle {
                    width: 40
                    height: 24
                    radius: 4
                    color: chapterSearchQuery !== "" ? "#FFEBEE" : "#E3F2FD"
                    border.color: chapterSearchQuery !== "" ? "#EF9A9A" : "#BBDEFB"
                    Text {
                        anchors.centerIn: parent
                        text: chapterSearchQuery !== "" ? "x" : "搜索"
                        font.pixelSize: 11
                        color: chapterSearchQuery !== "" ? "#D32F2F" : "#1565C0"
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (chapterSearchQuery !== "") {
                                chapterSearchQuery = "";
                                filterChapterList();
                            } else {
                                showKeyboard("", function(text) {
                                    if (text !== undefined) {
                                        chapterSearchQuery = text || "";
                                        filterChapterList();
                                    }
                                });
                            }
                        }
                    }
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 28
                contentWidth: width
                contentHeight: chapterGrid.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: chapterGrid
                    width: parent.width
                    spacing: 3

                    // 2列布局：每行放2个章节
                    Repeater {
                        model: Math.ceil(filteredChapterList.length / 2)

                        delegate: Row {
                            width: parent.width
                            spacing: 4

                            // 左列
                            Rectangle {
                                width: (parent.width - 4) / 2
                                height: 26
                                radius: 3
                                color: (filteredChapterList[index * 2] && filteredChapterList[index * 2].lineIndex === currentChapterIdx) ? "#E3F2FD" : "#F5F0E8"
                                visible: filteredChapterList.length > index * 2
                                clip: true

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: filteredChapterList.length > index * 2 ? formatChapterTitle(filteredChapterList[index * 2].title) : ""
                                    font.pixelSize: 10
                                    color: filteredChapterList.length > index * 2 && filteredChapterList[index * 2].lineIndex === currentChapterIdx ? "#1565C0" : "#333"
                                    width: parent.width - 8
                                    elide: chapterNameMode === "scroll" ? Text.ElideRight : Text.ElideRight
                                    font.family: "Microsoft YaHei"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (filteredChapterList.length > index * 2) {
                                            var idx = filteredChapterList[index * 2].lineIndex;
                                            if (idx !== currentChapterIdx) {
                                                saveProgress();
                                                loadChapter(idx);
                                            }
                                            navigateBack();
                                        }
                                    }
                                }
                            }

                            // 右列
                            Rectangle {
                                width: (parent.width - 4) / 2
                                height: 26
                                radius: 3
                                color: (filteredChapterList.length > index * 2 + 1 && filteredChapterList[index * 2 + 1].lineIndex === currentChapterIdx) ? "#E3F2FD" : "#F5F0E8"
                                visible: filteredChapterList.length > index * 2 + 1
                                clip: true

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: filteredChapterList.length > index * 2 + 1 ? formatChapterTitle(filteredChapterList[index * 2 + 1].title) : ""
                                    font.pixelSize: 10
                                    color: filteredChapterList.length > index * 2 + 1 && filteredChapterList[index * 2 + 1].lineIndex === currentChapterIdx ? "#1565C0" : "#333"
                                    width: parent.width - 8
                                    elide: Text.ElideRight
                                    font.family: "Microsoft YaHei"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (filteredChapterList.length > index * 2 + 1) {
                                            var idx = filteredChapterList[index * 2 + 1].lineIndex;
                                            if (idx !== currentChapterIdx) {
                                                saveProgress();
                                                loadChapter(idx);
                                            }
                                            navigateBack();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: menuPanel
        visible: activePanel === "menu"
        anchors.fill: parent
        color: bgColor
        z: 40

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 5

            Row {
                width: parent.width
                height: 24
                Text {
                    width: parent.width - 52
                    text: fileName
                    font.pixelSize: 12
                    font.bold: true
                    color: textColor
                    elide: Text.ElideMiddle
                    verticalAlignment: Text.AlignVCenter
                    font.family: "Microsoft YaHei"
                }
                Rectangle {
                    width: 40
                    height: 24
                    radius: 4
                    color: borderColor
                    Text {
                        anchors.centerIn: parent
                        text: "关闭"
                        font.pixelSize: 10
                        color: textColor
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
                    spacing: 4

                    // 进度 + 阅读时长 + 剩余时间预估
                    Text {
                        width: parent.width
                        text: "本章 " + getChapterPercent() + "%　全书 " + getBookPercent()
                              + "%　(" + getCurrentPage() + "/" + getTotalPages() + "页)"
                        font.pixelSize: 9
                        color: subTextColor
                        font.family: "Microsoft YaHei"
                    }

                    Text {
                        width: parent.width
                        text: "已读 " + formatReadingTime(readingTimeData[currentUrl])
                              + "　" + getRemainingText()
                              + (readingSpeed > 0 ? ("　速度 " + readingSpeed + "字/分") : "")
                        font.pixelSize: 9
                        color: subTextColor
                        font.family: "Microsoft YaHei"
                    }

                    Rectangle {
                        width: parent.width
                        height: 10
                        radius: 5
                        color: borderColor
                        Rectangle {
                            width: parent.width * (getBookPercent() / 100)
                            height: parent.height
                            radius: 5
                            color: "#2f7dcc"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: jumpToPercent((mouseX / width) * 100)
                        }
                    }

                    // 字号：无级调节（12–28），左右加减
                    Row {
                        width: parent.width
                        height: 22
                        spacing: 3
                        Text {
                            width: 46; height: 22
                            text: "字号 " + baseFontSize
                            font.pixelSize: 10; color: subTextColor
                            verticalAlignment: Text.AlignVCenter
                            font.family: "Microsoft YaHei"
                        }
                        Rectangle {
                            width: 30; height: 22; radius: 3
                            color: baseFontSize <= FONT_MIN ? "#F0F0F0" : "#EEEEEE"
                            Text { anchors.centerIn: parent; text: "－"; font.pixelSize: 13; color: baseFontSize <= FONT_MIN ? "#BBB" : "#333"; font.family: "Microsoft YaHei" }
                            MouseArea { anchors.fill: parent; onClicked: stepFontSize(-1) }
                        }
                        Rectangle {
                            width: 30; height: 22; radius: 3; color: cardColor
                            Text { anchors.centerIn: parent; text: "＋"; font.pixelSize: 13; color: baseFontSize >= FONT_MAX ? "#BBB" : "#333"; font.family: "Microsoft YaHei" }
                            MouseArea { anchors.fill: parent; onClicked: stepFontSize(1) }
                        }
                        Rectangle {
                            width: 46; height: 22; radius: 3; color: cardColor
                            Text { anchors.centerIn: parent; text: "重置"; font.pixelSize: 9; color: subTextColor; font.family: "Microsoft YaHei" }
                            MouseArea { anchors.fill: parent; onClicked: setFontSize(FONT_DEFAULT) }
                        }
                    }

                    // 行距 / 页边距：独立调节
                    Row {
                        width: parent.width
                        height: 22
                        spacing: 3
                        Text {
                            width: 46; height: 22
                            text: "行距 " + lineSpacing
                            font.pixelSize: 10; color: subTextColor
                            verticalAlignment: Text.AlignVCenter
                            font.family: "Microsoft YaHei"
                        }
                        Rectangle {
                            width: 30; height: 22; radius: 3
                            color: lineSpacing <= LINE_SPACING_MIN ? "#F0F0F0" : "#EEEEEE"
                            Text { anchors.centerIn: parent; text: "－"; font.pixelSize: 13; color: lineSpacing <= LINE_SPACING_MIN ? "#BBB" : "#333"; font.family: "Microsoft YaHei" }
                            MouseArea { anchors.fill: parent; onClicked: stepLineSpacing(-1) }
                        }
                        Rectangle {
                            width: 30; height: 22; radius: 3; color: cardColor
                            Text { anchors.centerIn: parent; text: "＋"; font.pixelSize: 13; color: lineSpacing >= LINE_SPACING_MAX ? "#BBB" : "#333"; font.family: "Microsoft YaHei" }
                            MouseArea { anchors.fill: parent; onClicked: stepLineSpacing(1) }
                        }
                        Text {
                            width: 46; height: 22
                            text: "边距 " + readerMargin
                            font.pixelSize: 10; color: subTextColor
                            verticalAlignment: Text.AlignVCenter
                            font.family: "Microsoft YaHei"
                        }
                        Rectangle {
                            width: 30; height: 22; radius: 3
                            color: readerMargin <= MARGIN_MIN ? "#F0F0F0" : "#EEEEEE"
                            Text { anchors.centerIn: parent; text: "－"; font.pixelSize: 13; color: readerMargin <= MARGIN_MIN ? "#BBB" : "#333"; font.family: "Microsoft YaHei" }
                            MouseArea { anchors.fill: parent; onClicked: stepMargin(-1) }
                        }
                        Rectangle {
                            width: 30; height: 22; radius: 3; color: cardColor
                            Text { anchors.centerIn: parent; text: "＋"; font.pixelSize: 13; color: readerMargin >= MARGIN_MAX ? "#BBB" : "#333"; font.family: "Microsoft YaHei" }
                            MouseArea { anchors.fill: parent; onClicked: stepMargin(1) }
                        }
                    }

                    // 主题色 —— 10 个主题按「浅色 / 深色」分两行展示
                    Text {
                        text: "主题"
                        font.pixelSize: 10
                        color: subTextColor
                        font.family: "Microsoft YaHei"
                    }

                    // 浅色主题
                    Row {
                        spacing: 3
                        Repeater {
                            model: ["默认", "白色", "米黄", "黄色", "绿色", "蓝色", "粉色"]
                            delegate: Rectangle {
                                width: 38; height: 20; radius: 3
                                color: ReaderUtils.themeColor(modelData, "bg")
                                border.color: themeName === modelData ? accentColor : borderColor
                                border.width: themeName === modelData ? 2 : 1
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: 8
                                    color: ReaderUtils.themeColor(modelData, "fg")
                                    font.family: "Microsoft YaHei"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { nightAuto = false; setTheme(modelData); }
                                }
                            }
                        }
                    }

                    // 深色主题
                    Row {
                        spacing: 3
                        Repeater {
                            model: ["黑色", "深灰", "暗黑"]
                            delegate: Rectangle {
                                width: 54; height: 20; radius: 3
                                color: ReaderUtils.themeColor(modelData, "bg")
                                border.color: themeName === modelData ? accentColor : borderColor
                                border.width: themeName === modelData ? 2 : 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "🌙 " + modelData
                                    font.pixelSize: 8
                                    color: ReaderUtils.themeColor(modelData, "fg")
                                    font.family: "Microsoft YaHei"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { nightAuto = false; setTheme(modelData); }
                                }
                            }
                        }
                    }

                    // 夜间模式自动切换
                    Rectangle { width: parent.width; height: 1; color: borderColor }

                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 3
                        color: cardColor
                        border.color: borderColor

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 4

                            Text {
                                text: "夜间自动切换"
                                font.pixelSize: 11
                                color: textColor
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: "Microsoft YaHei"
                            }
                            Item { width: parent.width - 120; height: 1 }

                            Rectangle {
                                width: 40; height: 20; radius: 10
                                color: nightAuto ? "#4CAF50" : borderColor
                                anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    x: nightAuto ? 22 : 2
                                    y: 2
                                    width: 16; height: 16; radius: 8
                                    color: "#FFFFFF"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        nightAuto = !nightAuto;
                                        if (nightAuto) applyAutoTheme();
                                        saveSettings();
                                    }
                                }
                            }
                        }
                    }

                    // 时间区间与日/夜主题（仅在启用时显示）
                    Row {
                        visible: nightAuto
                        spacing: 4
                        height: 22

                        Text {
                            text: "夜间时段"
                            font.pixelSize: 10
                            color: subTextColor
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: "Microsoft YaHei"
                        }
                        Rectangle {
                            width: 42; height: 20; radius: 3
                            color: cardColor; border.color: borderColor
                            Text {
                                anchors.centerIn: parent
                                text: nightStartHour + ":00"
                                font.pixelSize: 10; color: textColor
                                font.family: "Microsoft YaHei"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: showKeyboard(String(nightStartHour), function (t) {
                                    nightStartHour = clampHour(t, 20);
                                    applyAutoTheme(); saveSettings();
                                })
                            }
                        }
                        Text {
                            text: "→"
                            font.pixelSize: 10
                            color: subTextColor
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            width: 42; height: 20; radius: 3
                            color: cardColor; border.color: borderColor
                            Text {
                                anchors.centerIn: parent
                                text: nightEndHour + ":00"
                                font.pixelSize: 10; color: textColor
                                font.family: "Microsoft YaHei"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: showKeyboard(String(nightEndHour), function (t) {
                                    nightEndHour = clampHour(t, 7);
                                    applyAutoTheme(); saveSettings();
                                })
                            }
                        }
                        Text {
                            text: "当前：" + (isNightHour() ? "夜间" : "白天")
                            font.pixelSize: 9
                            color: subTextColor
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: "Microsoft YaHei"
                        }
                    }

                    // 功能按钮网格
                    Grid {
                        width: parent.width
                        columns: 3
                        rowSpacing: 3
                        columnSpacing: 3

                        MenuButton { label: "返回书架"; w: (menuContent.width - 6) / 3; onClicked: returnToShelf() }
                        MenuButton { label: "搜索"; w: (menuContent.width - 6) / 3; onClicked: { closePanels(); openSearch(); } }
                        MenuButton { label: "章节"; w: (menuContent.width - 6) / 3; onClicked: { closePanels(); buildChapterList(); navigateTo("chapterList"); } }
                        MenuButton { label: "跳转"; w: (menuContent.width - 6) / 3; onClicked: openPanel("jump") }
                        MenuButton { label: "添加书签"; w: (menuContent.width - 6) / 3; onClicked: addBookmark() }
                        MenuButton { label: "书签"; w: (menuContent.width - 6) / 3; onClicked: openPanel("bookmarks") }
                        MenuButton { label: autoScroll ? "停止翻页" : "自动翻页"; w: (menuContent.width - 6) / 3; onClicked: { if (autoScroll) autoScroll = false; else openPanel("auto"); } }
                        MenuButton { label: "上一章"; w: (menuContent.width - 6) / 3; onClicked: jumpToChapter(-1) }
                        MenuButton { label: scrollMode ? "分页" : "滚动"; w: (menuContent.width - 6) / 3; onClicked: { toggleScrollMode(); closePanels(); } }
                        MenuButton { label: "下一章"; w: (menuContent.width - 6) / 3; onClicked: jumpToChapter(1) }
                    }

                    Item { width: parent.width; height: 6 }
                }
            }
        }
    }

    // ====== 全文搜索面板 ======
    Rectangle {
        id: searchPanel
        visible: activePanel === "search"
        anchors.fill: parent
        color: bgColor
        z: 40

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 5

            // 顶栏：返回 + 标题
            Row {
                width: parent.width
                height: 24
                spacing: 6

                Rectangle {
                    width: 50
                    height: 24
                    radius: 4
                    color: borderColor
                    Text {
                        anchors.centerIn: parent
                        text: "返回"
                        font.pixelSize: 11
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: closePanels()
                    }
                }

                Text {
                    width: parent.width - 102
                    height: 24
                    text: "全文搜索"
                    font.pixelSize: 13
                    font.bold: true
                    color: textColor
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    font.family: "Microsoft YaHei"
                }

                Rectangle {
                    width: 40
                    height: 24
                    radius: 4
                    color: cardColor
                    Text {
                        anchors.centerIn: parent
                        text: "清空"
                        font.pixelSize: 10
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { searchQuery = ""; runSearch(""); }
                    }
                }
            }

            // 输入框（点击唤起键盘）
            Rectangle {
                width: parent.width
                height: 28
                radius: 4
                color: "#FFFFFF"
                border.color: borderColor

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 16
                    text: searchQuery === "" ? "点击输入要搜索的内容…" : searchQuery
                    font.pixelSize: 12
                    color: searchQuery === "" ? "#AAAAAA" : "#333333"
                    elide: Text.ElideRight
                    font.family: "Microsoft YaHei"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        showKeyboard(searchQuery, function (text) {
                            runSearch(text);
                        });
                    }
                }
            }

            // 选项：整词 / 区分大小写
            Row {
                width: parent.width
                height: 22
                spacing: 6

                Rectangle {
                    width: (parent.width - 6) / 2
                    height: 22
                    radius: 3
                    color: searchWholeWord ? "#2f7dcc" : "#EEEEEE"
                    Text {
                        anchors.centerIn: parent
                        text: "整词匹配"
                        font.pixelSize: 10
                        color: searchWholeWord ? "#FFFFFF" : "#666666"
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            searchWholeWord = !searchWholeWord;
                            runSearch(searchQuery);
                        }
                    }
                }

                Rectangle {
                    width: (parent.width - 6) / 2
                    height: 22
                    radius: 3
                    color: searchCaseSensitive ? "#2f7dcc" : "#EEEEEE"
                    Text {
                        anchors.centerIn: parent
                        text: "区分大小写"
                        font.pixelSize: 10
                        color: searchCaseSensitive ? "#FFFFFF" : "#666666"
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            searchCaseSensitive = !searchCaseSensitive;
                            runSearch(searchQuery);
                        }
                    }
                }
            }

            // 结果统计
            Text {
                width: parent.width
                height: 16
                visible: searchQuery !== ""
                text: {
                    if (searchTotal === 0) return "未找到匹配内容";
                    var base = "共 " + searchTotal + " 处匹配";
                    if (searchTruncated) base += "（仅显示前 " + searchResults.length + " 处）";
                    return base;
                }
                font.pixelSize: 10
                color: searchTotal === 0 && searchQuery !== "" ? "#D32F2F" : "#888888"
                font.family: "Microsoft YaHei"
            }

            // 结果列表
            ListView {
                width: parent.width
                height: parent.height - 190
                clip: true
                model: searchResults
                spacing: 3
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    width: ListView.view.width
                    height: hitText.height + 12
                    radius: 4
                    color: cardColor
                    border.color: borderColor

                    Column {
                        id: hitText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 6
                        spacing: 2

                        Text {
                            width: parent.width
                            text: "第 " + (Search.chapterIndexForLine(modelData.line, chapterBoundaries) + 1)
                                  + " 章 · 第 " + (modelData.line + 1) + " 行"
                            font.pixelSize: 9
                            color: subTextColor
                            font.family: "Microsoft YaHei"
                        }

                        // 命中片段：关键词用高亮色
                        Text {
                            width: parent.width
                            textFormat: Text.StyledText
                            font.pixelSize: 11
                            color: textColor
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: "Microsoft YaHei"
                            text: Search.highlightSegments(modelData.before + modelData.match + modelData.after,
                                                           searchQuery, searchCaseSensitive)
                                  .map(function (s) {
                                      return s.isMatch
                                          ? ("<font color='#D32F2F'><b>" + escapeHtml(s.text) + "</b></font>")
                                          : escapeHtml(s.text);
                                  }).join("")
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: jumpToSearchHit(modelData)
                    }
                }
            }
        }
    }

    // ====== 跳转面板 ======
    Rectangle {
        id: jumpPanel
        visible: activePanel === "jump"
        anchors.fill: parent
        color: bgColor
        z: 40

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 5

            Row {
                width: parent.width
                height: 24
                spacing: 6

                Rectangle {
                    width: 50
                    height: 24
                    radius: 4
                    color: borderColor
                    Text {
                        anchors.centerIn: parent
                        text: "返回"
                        font.pixelSize: 11
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: closePanels()
                    }
                }

                Text {
                    width: parent.width - 102
                    height: 24
                    text: "跳转"
                    font.pixelSize: 13
                    font.bold: true
                    color: textColor
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    font.family: "Microsoft YaHei"
                }

                Rectangle {
                    width: 40
                    height: 24
                    radius: 4
                    color: borderColor
                    Text {
                        anchors.centerIn: parent
                        text: "x"
                        font.pixelSize: 11
                        color: textColor
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
                height: parent.height - 34
                contentWidth: width
                contentHeight: jumpContent.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: jumpContent
                    width: parent.width
                    spacing: 6

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
                            model: [ { t: "0%", v: 0 }, { t: "25%", v: 25 }, { t: "50%", v: 50 }, { t: "75%", v: 75 }, { t: "100%", v: 100 } ]
                            delegate: MenuButton {
                                label: modelData.t
                                w: 42
                                h: 21
                                bg: "#2f7dcc"
                                fg: "#fff"
                                onClicked: { jumpToPercent(modelData.v); closePanels(); }
                            }
                        }
                    }

                    MenuButton {
                        label: "章节跳转"
                        w: parent.width
                        h: 24
                        bg: "#E3F2FD"
                        fg: "#1565C0"
                        onClicked: {
                            closePanels();
                            buildChapterList();
                            navigateTo("chapterList");
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
                                    if (!isNaN(page)) jumpToPage(page);
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
                                    if (!isNaN(percent)) jumpToPercent(percent);
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
        }
    }

    Rectangle {
        id: bookmarkPanel
        visible: activePanel === "bookmarks"
        anchors.fill: parent
        color: bgColor
        z: 40

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 5

            Row {
                width: parent.width
                height: 24
                spacing: 6
                Rectangle {
                    width: 50; height: 24; radius: 4; color: borderColor
                    Text { anchors.centerIn: parent; text: "返回"; font.pixelSize: 11; color: textColor; font.family: "Microsoft YaHei" }
                    MouseArea { anchors.fill: parent; onClicked: closePanels() }
                }
                Text {
                    width: parent.width - 102
                    text: "书签 (" + bookmarkList.length + ")"
                    font.pixelSize: 13; font.bold: true; color: textColor
                    verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                    font.family: "Microsoft YaHei"
                }
                Rectangle {
                    width: 40; height: 24; radius: 4; color: "#E3F2FD"; border.color: "#BBDEFB"
                    Text { anchors.centerIn: parent; text: "导出"; font.pixelSize: 10; color: "#1565C0"; font.family: "Microsoft YaHei" }
                    MouseArea { anchors.fill: parent; onClicked: exportBookmarks() }
                }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: cardColor
            }

            ListView {
                width: parent.width
                height: parent.height - 43
                clip: true
                spacing: 4
                model: bookmarkList

                delegate: Rectangle {
                    width: parent.width
                    // 有备注时多留一行
                    height: (modelData.note && modelData.note !== "") ? 50 : 36
                    radius: 4
                    color: bmMouse.pressed ? "#E0D8C8" : "#F5F0E8"
                    border.color: borderColor

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
                            // 字号变化后按比例调整位置
                            if (modelData.linesTotal && modelData.linesTotal !== lines.length) {
                                currentLine = Math.floor(modelData.line / modelData.linesTotal * lines.length);
                            }
                            clampCurrentLine();
                            saveProgress();
                            closePanels();
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: noteButton.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "书签 " + (index + 1) + " - 第" + (Math.floor(modelData.line / getLinesPerPage()) + 1) + "页"
                            font.pixelSize: 11
                            color: textColor
                            font.family: "Microsoft YaHei"
                        }
                        Text {
                            width: parent.width
                            text: modelData.preview || "..."
                            font.pixelSize: 9
                            color: subTextColor
                            elide: Text.ElideRight
                            font.family: "Microsoft YaHei"
                        }
                        Text {
                            width: parent.width
                            visible: modelData.note && modelData.note !== ""
                            text: "备注：" + (modelData.note || "")
                            font.pixelSize: 9
                            color: "#2E7D32"
                            elide: Text.ElideRight
                            font.family: "Microsoft YaHei"
                        }
                    }

                    Rectangle {
                        id: noteButton
                        anchors.right: deleteButton.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 20
                        radius: 3
                        color: "#FFF3E0"
                        border.color: "#FFCC80"

                        Text {
                            anchors.centerIn: parent
                            text: "备注"
                            font.pixelSize: 9
                            color: "#E65100"
                            font.family: "Microsoft YaHei"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: editBookmarkNote(modelData.id)
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

    Rectangle {
        id: autoPanel
        visible: activePanel === "auto"
        anchors.fill: parent
        color: bgColor
        z: 40

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 5

            Row {
                width: parent.width
                height: 24
                spacing: 6
                Rectangle {
                    width: 50; height: 24; radius: 4; color: borderColor
                    Text { anchors.centerIn: parent; text: "返回"; font.pixelSize: 11; color: textColor; font.family: "Microsoft YaHei" }
                    MouseArea { anchors.fill: parent; onClicked: closePanels() }
                }
                Text {
                    width: parent.width - 102
                    text: "自动翻页"
                    font.pixelSize: 13; font.bold: true; color: textColor
                    verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                    font.family: "Microsoft YaHei"
                }
                Rectangle {
                    width: 40; height: 24; radius: 4; color: borderColor
                    Text { anchors.centerIn: parent; text: "x"; font.pixelSize: 11; color: textColor; font.family: "Microsoft YaHei" }
                    MouseArea { anchors.fill: parent; onClicked: closePanels() }
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 34
                contentWidth: width
                contentHeight: autoContent.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: autoContent
                    width: parent.width
                    spacing: 9

                    Text {
                        width: parent.width
                        text: "间隔: " + autoScrollSeconds + " 秒/页"
                        font.pixelSize: 11
                        color: textColor
                        font.family: "Microsoft YaHei"
                    }

                    Row {
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


    }
    }

    // ====== shelf menu ======
    Rectangle {
        id: shelfMenuPanel
        visible: showShelfMenu
        anchors.fill: parent
        color: "#40000000"
        z: 70

        MouseArea {
            anchors.fill: parent
            onClicked: showShelfMenu = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 60
            height: 148
            radius: 8
            color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
            border.color: borderColor

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Text {
                    width: parent.width
                    text: shelfContextItem ? shelfContextItem.name : ""
                    font.pixelSize: 11
                    font.bold: true
                    color: textColor
                    elide: Text.ElideRight
                    font.family: "Microsoft YaHei"
                }

                Rectangle { width: parent.width; height: 1; color: cardColor }

                MenuButton {
                    label: "书籍信息"
                    w: parent.width
                    h: 24
                    bg: "#E3F2FD"
                    fg: "#1565C0"
                    onClicked: {
                        showShelfMenu = false;
                        bookInfoItem = shelfContextItem;
                        // 收集书籍信息
                        var info = bookInfoCache[shelfContextItem.file] || { chars: 0, chapters: 0, loaded: false };
                        if (!info.loaded) {
                            try {
                                var xhr = new XMLHttpRequest();
                                xhr.open("GET", shelfContextItem.file, false);
                                xhr.send();
                                if (xhr.status === 200 || xhr.status === 0) {
                                    var content = xhr.responseText || "";
                                    info.chars = content.length;
                                    info.chapters = 0;
                                    var lines = content.split("\n");
                                    var re = ReaderUtils.getChapterRegex();
                                    for (var i = 0; i < lines.length; i++) {
                                        if (re.test(lines[i].trim())) info.chapters++;
                                    }
                                    if (info.chapters === 0) info.chapters = 1;
                                    info.loaded = true;
                                    bookInfoCache[shelfContextItem.file] = info;
                                }
                            } catch(e) {}
                        }
                        bookInfoItem = {
                            file: shelfContextItem.file,
                            name: shelfContextItem.name,
                            chars: info.chars,
                            chapters: info.chapters,
                            readingTime: readingTimeData[shelfContextItem.file] || 0
                        };
                        showBookInfo = true;
                    }
                }
                MenuButton {
                    label: "重命名"
                    w: parent.width
                    h: 24
                    onClicked: shelfRenameBook(shelfContextItem)
                }
                MenuButton {
                    label: "删除文件"
                    w: parent.width
                    h: 24
                    bg: "#FFEBEE"
                    fg: "#C62828"
                    onClicked: shelfDeleteBook(shelfContextItem)
                }
                MenuButton {
                    label: "删除记录（保留文件）"
                    w: parent.width
                    h: 24
                    onClicked: shelfDeleteRecord(shelfContextItem)
                }
            }
        }
    }

    // ====== 书籍信息面板 ======
    Rectangle {
        id: bookInfoPanel
        visible: showBookInfo
        anchors.fill: parent
        anchors.margins: 10
        radius: 6
        color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
        border.color: borderColor
        z: 60

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 5

            Row {
                width: parent.width
                height: 24
                Text {
                    width: parent.width - 30
                    text: bookInfoItem ? bookInfoItem.name : ""
                    font.pixelSize: 12
                    font.bold: true
                    color: textColor
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    font.family: "Microsoft YaHei"
                }
                MenuButton {
                    label: "x"
                    w: 24
                    h: 24
                    onClicked: showBookInfo = false
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 34
                contentWidth: width
                contentHeight: infoCol.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: infoCol
                    width: parent.width
                    spacing: 5

                    Row {
                        width: parent.width
                        spacing: 4
                        Text { text: "总字数"; font.pixelSize: 10; color: subTextColor; font.family: "Microsoft YaHei"; width: parent.width / 3 }
                        Text { text: "章节数"; font.pixelSize: 10; color: subTextColor; font.family: "Microsoft YaHei"; width: parent.width / 3 }
                        Text { text: "阅读时长"; font.pixelSize: 10; color: subTextColor; font.family: "Microsoft YaHei"; width: parent.width / 3 }
                    }
                    Row {
                        width: parent.width
                        spacing: 4
                        Text { text: bookInfoItem ? ReaderUtils.formatNumber(bookInfoItem.chars) : "0"; font.pixelSize: 14; font.bold: true; color: textColor; font.family: "Microsoft YaHei"; width: parent.width / 3 }
                        Text { text: bookInfoItem ? bookInfoItem.chapters : "0"; font.pixelSize: 14; font.bold: true; color: textColor; font.family: "Microsoft YaHei"; width: parent.width / 3 }
                        Text { text: bookInfoItem ? formatReadingTime(bookInfoItem.readingTime) : "0"; font.pixelSize: 14; font.bold: true; color: textColor; font.family: "Microsoft YaHei"; width: parent.width / 3 }
                    }

                    Rectangle { width: parent.width; height: 1; color: cardColor }

                    Row {
                        width: parent.width; spacing: 4
                        Text { text: "文件"; font.pixelSize: 10; color: subTextColor; font.family: "Microsoft YaHei"; width: 40 }
                        Text { text: bookInfoItem ? bookInfoItem.name : ""; font.pixelSize: 10; color: textColor; elide: Text.ElideRight; font.family: "Microsoft YaHei"; width: parent.width - 44 }
                    }
                    Row {
                        width: parent.width; spacing: 4
                        Text { text: "路径"; font.pixelSize: 10; color: subTextColor; font.family: "Microsoft YaHei"; width: 40 }
                        Text { text: bookInfoItem ? ReaderUtils.stripFilePrefix(bookInfoItem.file) : ""; font.pixelSize: 9; color: subTextColor; elide: Text.ElideLeft; font.family: "Microsoft YaHei"; width: parent.width - 44 }
                    }

                    MenuButton {
                        label: "关闭"
                        w: parent.width
                        h: 24
                        onClicked: showBookInfo = false
                    }
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
        border.color: borderColor
        z: 100
        Text {
            anchors.centerIn: parent
            text: "加载中..."
            font.pixelSize: 11
            color: textColor
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

    // 编码自动转换完成后的提示（信息性，用中性色，自动消失）
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 8
        width: Math.min(parent.width - 24, encodingNoticeText.implicitWidth + 20)
        height: 26
        radius: 13
        color: "#263238"
        opacity: 0.92
        visible: encodingNotice !== ""
        z: 101

        Text {
            id: encodingNoticeText
            anchors.centerIn: parent
            text: encodingNotice
            font.pixelSize: 11
            color: "#ECEFF1"
            font.family: "Microsoft YaHei"
        }

        Timer {
            running: encodingNotice !== ""
            interval: 2600
            onTriggered: encodingNotice = ""
        }
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
