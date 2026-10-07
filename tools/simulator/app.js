// app.js —— 词典笔界面模拟器
//
// 目的：把 QML 布局在 320x170 的真实视口下还原出来，便于检查
// 「在这个屏幕上到底放不放得下、看得清不清」。
//
// 数据来源：main.qml 中的显式数值（页面结构、尺寸、文案）。
// 本文件不追求模拟 QML 运行时语义，只模拟「渲染结果」。
// 因此交互是简化的：翻页、跳转可用；文本换行按字数估算。

const SW = 320, SH = 170;

// ===== 与 main.qml 保持一致的常量 =====
const CFG = {
  readerMargin: 7,
  baseFontSize: 15,
  lineSpacing: 4,
  charsPerLine: 19,        // updateCharsPerLine(15) = 19
  shelfSort: 'recent',
  shelfFilter: 'all',
  theme: '默认',
};

// ===== 模拟数据 =====
const BOOKS = [
  { name: '三体',            progress: 62, size: 1.8e6, ts: 5, ch: '第三章 红岸之五', ln: 42 },
  { name: '活着',            progress: 100, size: 4.1e5, ts: 9, ch: '尾声',          ln: 12 },
  { name: '百年孤独',        progress: 8,  size: 2.4e6, ts: 3, ch: '第一章 冰块',     ln: 5  },
  { name: '银河系漫游指南',   progress: 0,  size: 8.9e5, ts: 0, ch: '第一章',         ln: 0  },
  { name: '球状闪电',        progress: 0,  size: 6.2e5, ts: 0, ch: '第一章',         ln: 0  },
  { name: '围城',            progress: 35, size: 1.1e6, ts: 7, ch: '第二章',         ln: 88 },
  { name: '动物农场',        progress: 100, size: 2.2e5, ts: 1, ch: '第十章',        ln: 20 },
];

const TEXT_LINES = `第一章 疯狂年代
中国，1967年。
物理学家叶文洁的父亲叶哲泰，
在批斗会上被自己的学生打死。
这一刻，一个关于宇宙的答案，
开始在沉默中生长。
"不要回答，不要回答，不要回答。"
红岸基地的巨型天线，
指向了四光年外的半人马座。
她按下了发射键。
八年后，她收到了一条警告。
但为时已晚。
人类的命运，
从那一刻起就已经改写。`.split('\n');

// ===== 状态 =====
const state = {
  page: 'reader',
  panel: '',           // menu / search / bookmarks / stats ...
  line: 0,
  shelfQuery: '',
  sort: 'recent',
  filter: 'all',
  readingSpeed: 0,
  statsKey: 0,
  bookmarks: [
    { ch: '第一章', pct: 12, preview: '叶文洁走进房间...', note: '这里很震撼' },
    { ch: '第三章', pct: 45, preview: '他说：这是个陷阱', note: '' },
  ],
};

// ===== 工具函数（与 ReadingStats.js 对齐）=====
function fmtDuration(sec) {
  if (!sec || sec < 0) return '0秒';
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  if (h > 0) return m > 0 ? `${h}小时${m}分` : `${h}小时`;
  if (m > 0) return s > 0 ? `${m}分${s}秒` : `${m}分`;
  return s + '秒';
}
function fmtSize(b) {
  if (!b) return '';
  if (b < 1024) return b + ' B';
  if (b < 1048576) return (b / 1024).toFixed(1) + ' KB';
  return (b / 1048576).toFixed(1) + ' MB';
}

// ===== 书架视图（与 BookList.js 逻辑一致）=====
function shelfView() {
  let arr = BOOKS.slice();
  if (state.shelfQuery.trim()) {
    const q = state.shelfQuery.trim().toLowerCase();
    arr = arr.filter(b => b.name.toLowerCase().includes(q));
  }
  if (state.filter === 'unread')  arr = arr.filter(b => b.progress === 0);
  if (state.filter === 'reading') arr = arr.filter(b => b.progress > 0 && b.progress < 100);
  if (state.filter === 'done')    arr = arr.filter(b => b.progress >= 100);

  const byName = (a, b) => a.name.localeCompare(b.name, 'zh');
  switch (state.sort) {
    case 'name':     arr.sort(byName); break;
    case 'progress': arr.sort((a, b) => (b.progress - a.progress) || byName(a, b)); break;
    case 'size':     arr.sort((a, b) => (b.size - a.size) || byName(a, b)); break;
    case 'unread':   arr.sort((a, b) => ((a.progress > 0) - (b.progress > 0)) || (b.ts - a.ts) || byName(a, b)); break;
    default:         arr.sort((a, b) => (b.ts - a.ts) || byName(a, b));
  }
  return arr;
}
function statusCounts() {
  const c = { all: 0, unread: 0, reading: 0, done: 0 };
  BOOKS.forEach(b => {
    c.all++;
    if (b.progress === 0) c.unread++;
    else if (b.progress >= 100) c.done++;
    else c.reading++;
  });
  return c;
}

// ===== 页面渲染 =====
function render() {
  const el = document.getElementById('screen');
  let html = '';

  if (state.panel === 'menu')          html = viewMenu();
  else if (state.panel === 'search')   html = viewSearch();
  else if (state.panel === 'bookmarks')html = viewBookmarks();
  else if (state.panel === 'stats')    html = viewStats();
  else if (state.page === 'reader')    html = viewReader();
  else if (state.page === 'shelf')     html = viewShelf();
  else if (state.page === 'home')      html = viewHome();
  else if (state.page === 'settings')  html = viewSettings();

  el.innerHTML = html + `<div class="toast" id="toast"></div>`;
  updateMetrics();
}

// —— 阅读器 ——
function viewReader() {
  const m = CFG.readerMargin, fs = CFG.baseFontSize, ls = CFG.lineSpacing;
  // 关键修复：文本区高度必须扣除底部状态栏，否则最后一行被压住
  const STATUS_H = 14;   // 与 QML readerStatusBarHeight 一致
  const availH = SH - m * 2 - STATUS_H;
  const lineH = Math.ceil(fs * 1.35) + ls;
  const linesPerPage = Math.max(1, Math.floor(availH / lineH));
  const start = state.line;
  const page = TEXT_LINES.slice(start, start + linesPerPage);
  const totalPages = Math.ceil(TEXT_LINES.length / linesPerPage);
  const curPage = Math.floor(start / linesPerPage) + 1;
  const bookPct = Math.round((start / TEXT_LINES.length) * 100);

  return `
  <div class="page active" style="padding:${m}px;padding-bottom:0">
    <div style="flex:1;font-size:${fs}px;line-height:${lineH}px;overflow:hidden;color:var(--fg)">
      ${page.map(l => `<div>${l || '&nbsp;'}</div>`).join('')}
    </div>
    <div style="height:${STATUS_H}px;flex-shrink:0;display:flex;align-items:center;
                justify-content:space-between;font-size:8.5px;color:#999;
                border-top:1px solid rgba(0,0,0,.05);margin:0 -${m}px">
      <span style="padding-left:${m}px">全书 ${bookPct}%　剩余 ${state.readingSpeed > 0 ? '约2小时' : '约2小时'}</span>
      <span style="padding-right:${m}px">${curPage}/${totalPages} 页</span>
    </div>
  </div>`;
}

// —— 主菜单（阅读中点击中间弹出）——
function viewMenu() {
  return `
  <div class="page active" style="background:var(--bg)">
    <div class="title">菜单</div>
    <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:4px;flex-shrink:0">
      ${btn('返回书架')}${btn('搜索')}${btn('章节')}
      ${btn('跳转')}${btn('添加书签')}${btn('书签')}
      ${btn('上一章')}${btn('滚动')}${btn('下一章')}
    </div>
    <div style="margin-top:4px;font-size:9px;color:#888">
      进度: ${Math.round(state.line / TEXT_LINES.length * 100)}%　阅读: 1小时30分
    </div>
    <div style="height:10px;border-radius:5px;background:#ddd;margin-top:4px;flex-shrink:0">
      <div style="width:${Math.round(state.line / TEXT_LINES.length * 100)}%;height:100%;
                  border-radius:5px;background:#2f7dcc"></div>
    </div>
  </div>`;
}

// —— 书架 ——
function viewShelf() {
  const list = shelfView();
  const c = statusCounts();
  const filters = [['all','全部'],['unread','未读'],['reading','在读'],['done','读完']];
  const sorts = [['recent','最近'],['name','书名'],['progress','进度'],['size','大小'],['unread','未读']];

  // 紧凑布局：搜索框与筛选合并为一行，排序折叠进按钮弹出
  const TOP = 24, CHIPS = 22, HINT = 12, BOTTOM = 28;
  const chromeH = TOP + CHIPS + HINT + BOTTOM + 3 * 4;
  const listH = SH - 12 - chromeH;

  return `
  <div class="page active" style="padding:5px;gap:3px">
    <div class="topbar" style="height:${TOP}px">
      <div class="btn" style="height:${TOP}px;min-width:42px;font-size:10px"
           onclick="go('home')">返回</div>
      <div class="title" style="font-size:12px">
        ${list.length}${list.length !== BOOKS.length ? '/' + BOOKS.length : ''} 本
      </div>
      <div class="btn small ${state.shelfQuery ? 'on' : ''}"
           style="height:${TOP}px;min-width:42px;font-size:10px"
           onclick="promptSearch()">搜索</div>
    </div>

    <div class="chips" style="height:${SEARCH}px;align-items:center;gap:3px">
      <div class="chip" style="width:34px;height:${SEARCH}px;background:${state.filter==='all'?'var(--accent)':'#eee'};
           color:${state.filter==='all'?'#fff':'#666'}" onclick="setFilter('all')">
        ${state.shelfQuery ? '✕' : c.all}
      </div>
      ${filters.slice(1).map(([k,label]) =>
        `<div class="chip ${state.filter===k?'on':''}" style="flex:1;height:${SEARCH}px"
              onclick="setFilter('${k}')">${label}${c[k]}</div>`).join('')}
      <div class="chip" style="width:34px;height:${SEARCH}px;background:#8D6E63;color:#fff"
           onclick="cycleSort()">⇅</div>
    </div>

    <div class="list" style="height:${listH}px">
      ${list.length === 0
        ? `<div style="text-align:center;color:#999;font-size:10px;padding-top:6px">
             ${BOOKS.length ? '没有符合条件的书籍' : '暂无小说'}</div>`
        : list.map(b => `
          <div class="row" style="height:${LIST_ROW}px;background:#F8F4EC;border:1px solid var(--border)"
               onclick="openBook('${b.name}')">
            <span style="flex:1;font-size:10.5px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${b.name}</span>
            <span style="font-size:8.5px;color:#888;flex-shrink:0">${b.progress}%</span>
          </div>`).join('')}
    </div>

    <div style="height:${BOTTOM}px;flex-shrink:0;display:flex;align-items:center;
                justify-content:space-between;font-size:9px;color:#999">
      <span>排序：${(sorts.find(x => x[0] === state.sort) || [,'最近'])[1]}</span>
      <span>${state.shelfQuery ? '筛选：“' + state.shelfQuery + '”' : ''}</span>
    </div>
  </div>`;
}

function cycleSort() {
  const order = ['recent','name','progress','size','unread'];
  const i = order.indexOf(state.sort);
  state.sort = order[(i + 1) % order.length];
  render();
  toast('排序：' + ({recent:'最近',name:'书名',progress:'进度',size:'大小',unread:'未读'})[state.sort]);
}

// —— 搜索面板 ——
function viewSearch() {
  const q = state.shelfQuery || '测试';
  const hits = [
    { ch: 1, line: 12, before: '这是一个', match: '测试', after: '文本' },
    { ch: 1, line: 48, before: '关于', match: '测试', after: '的说明' },
    { ch: 3, line: 130, before: '他说', match: '测试', after: '结束' },
  ];
  return `
  <div class="page active">
    <div class="topbar">
      <div class="btn" onclick="closePanel()">返回</div>
      <div class="title">全文搜索</div>
      <div class="btn small" onclick="setQuery('')">清空</div>
    </div>
    <div class="input" onclick="promptSearch()">
      <span class="${q ? 'val' : 'ph'}">${q || '点击输入要搜索的内容…'}</span>
    </div>
    <div class="chips">
      <div class="chip" style="flex:1">整词匹配</div>
      <div class="chip" style="flex:1">区分大小写</div>
    </div>
    <div style="font-size:10px;color:#888;flex-shrink:0">共 ${hits.length} 处匹配</div>
    <div class="list">
      ${hits.map(h => `
        <div class="row" style="height:34px;background:#F5F5F5;border:1px solid #e0e0e0;
             flex-direction:column;align-items:flex-start;justify-content:center;gap:1px;padding:4px 6px">
          <div style="font-size:9px;color:#999">第 ${h.ch} 章 · 第 ${h.line + 1} 行</div>
          <div style="font-size:11px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;width:100%">
            ${h.before}<span style="color:#D32F2F;font-weight:700">${h.match}</span>${h.after}
          </div>
        </div>`).join('')}
    </div>
  </div>`;
}

// —— 书签面板 ——
function viewBookmarks() {
  return `
  <div class="page active">
    <div class="topbar">
      <div class="btn" onclick="closePanel()">返回</div>
      <div class="title">书签 (${state.bookmarks.length})</div>
      <div class="btn small primary">导出</div>
    </div>
    <div style="height:1px;background:#eee;flex-shrink:0"></div>
    <div class="list">
      ${state.bookmarks.map((b, i) => `
        <div class="row" style="height:${b.note ? 50 : 36}px;background:#F5F0E8;border:1px solid #ddd;
             flex-direction:column;align-items:flex-start;justify-content:center;gap:2px;padding:4px 6px;position:relative">
          <div style="font-size:11px;color:#333">书签 ${i + 1} - 第${Math.floor(b.pct / 10) + 1}页</div>
          <div style="font-size:9px;color:#888;width:210px;overflow:hidden;
                      text-overflow:ellipsis;white-space:nowrap">${b.preview}</div>
          ${b.note ? `<div style="font-size:9px;color:#2E7D32;width:210px;overflow:hidden;
                       text-overflow:ellipsis;white-space:nowrap">备注：${b.note}</div>` : ''}
          <div style="position:absolute;right:34px;top:50%;transform:translateY(-50%);
                      width:30px;height:20px;border-radius:3px;background:#FFF3E0;border:1px solid #FFCC80;
                      display:flex;align-items:center;justify-content:center;font-size:9px;color:#E65100">备注</div>
          <div style="position:absolute;right:4px;top:50%;transform:translateY(-50%);
                      width:24px;height:20px;border-radius:3px;background:#eee;
                      display:flex;align-items:center;justify-content:center;font-size:11px;color:#888">×</div>
        </div>`).join('')}
    </div>
  </div>`;
}

// —— 阅读统计 ——
function viewStats() {
  const c = statusCounts();
  const rows = [
    ['累计阅读', '1小时30分'], ['阅读天数', '2 天'], ['日均阅读', '45分'],
    ['在读书籍', '3 本'], ['已读完', '2 本'],
    ['书架藏书', c.all + ' 本'], ['未读', c.unread + ' 本'], ['在读', c.reading + ' 本'],
  ];
  return `
  <div class="page active">
    <div class="topbar">
      <div class="btn" onclick="showPage('settings')">返回</div>
      <div class="title">阅读统计</div>
      <div class="btn small" onclick="refreshStats()">刷新</div>
    </div>
    <div class="list">
      <div style="font-size:11px;font-weight:700;flex-shrink:0">阅读概况</div>
      ${rows.map(([k, v]) => `
        <div class="row" style="height:26px;background:#F8F4EC;border:1px solid var(--border)">
          <span style="flex:1;font-size:11px;color:#666">${k}</span>
          <span style="font-size:11px;font-weight:700;color:#2f7dcc">${v}</span>
        </div>`).join('')}
      <div style="height:1px;background:#eee;margin:2px 0"></div>
      <div style="font-size:11px;font-weight:700">阅读速度</div>
      <div style="font-size:10px;color:#888">
        ${state.readingSpeed > 0 ? state.readingSpeed + ' 字/分（本机实测）'
                                 : '300 字/分（默认值，读满 1 分钟后自动校准）'}
      </div>
    </div>
  </div>`;
}

// —— 首页 ——
function viewHome() {
  return `
  <div class="page active">
    <div class="title" style="font-size:16px">电子书阅读器</div>
    <div style="text-align:center;font-size:10px;color:#888">
      小说请放到 /userdisk/Music/小说/
    </div>
    <div style="height:24px;border-radius:3px;background:#E3F2FD;border:1px solid #BBDEFB;
                display:flex;align-items:center;justify-content:center;font-size:11px;color:#1565C0">
      上传服务未启动
    </div>
    <div style="display:flex;gap:6px;height:24px">
      <div class="btn" style="flex:1">启动上传</div>
      <div class="btn" style="flex:1" onclick="showPage('settings')">设置</div>
    </div>
    <div class="row" style="height:34px;background:#F8F4EC;border:1px solid var(--border);
                justify-content:center;font-size:13px;font-weight:700"
         onclick="showPage('shelf')">我的书架 (${BOOKS.length})</div>
  </div>`;
}

// —— 设置 ——
function viewSettings() {
  return `
  <div class="page active">
    <div class="topbar">
      <div class="btn" onclick="showPage('home')">返回</div>
      <div class="title">设置</div>
      <div class="btn small primary">关于</div>
    </div>
    <div class="list">
      <div style="font-size:9px;color:#888">小说目录：/userdisk/Music/小说/</div>
      <div class="row" style="height:28px;background:#E3F2FD;border:1px solid #BBDEFB;
                  justify-content:center;font-size:11px;color:#1565C0"
           onclick="openPanel('stats')">阅读统计 ›</div>
      <div style="height:1px;background:#eee"></div>
      <div style="font-size:11px;font-weight:700">排版</div>
      <div style="display:flex;gap:4px;font-size:10px">
        <span style="color:#666;width:46px">字号 ${CFG.baseFontSize}</span>
        <div class="chip" style="width:30px">－</div>
        <div class="chip" style="width:30px">＋</div>
        <div class="chip" style="width:46px">重置</div>
      </div>
      <div style="display:flex;gap:4px;font-size:10px">
        <span style="color:#666;width:46px">行距 ${CFG.lineSpacing}</span>
        <div class="chip" style="width:30px">－</div>
        <div class="chip" style="width:30px">＋</div>
        <span style="color:#666;width:46px">边距 ${CFG.readerMargin}</span>
        <div class="chip" style="width:30px">－</div>
        <div class="chip" style="width:30px">＋</div>
      </div>
    </div>
  </div>`;
}

function btn(label, cls = '') {
  return `<div class="btn ${cls}" style="flex:1">${label}</div>`;
}

// ===== 交互 =====
function showPage(p) { state.page = p; state.panel = ''; render(); }
function go(p) { showPage(p); }
function openPanel(p) { state.panel = p; render(); }
function closePanel() { state.panel = ''; render(); }
function openBook(name) {
  state.page = 'reader'; state.panel = ''; state.line = 0;
  toast('打开《' + name + '》'); render();
}
function setSort(k) { state.sort = k; render(); }
function setFilter(k) { state.filter = k; render(); }
function setQuery(q) { state.shelfQuery = q; render(); }
function refreshStats() { state.statsKey++; render(); toast('统计已刷新'); }
function promptSearch() {
  const v = window.prompt('输入要搜索的内容', state.shelfQuery);
  if (v !== null) { state.shelfQuery = v; render(); }
}
function toast(msg) {
  const el = document.getElementById('toast');
  if (!el) return;
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(window._tt);
  window._tt = setTimeout(() => el.classList.remove('show'), 1800);
}

// 模拟翻页
function nextPage(delta) {
  if (state.page !== 'reader') return;
  state.line = Math.max(0, Math.min(TEXT_LINES.length - 1, state.line + delta));
  render();
}

// ===== 屏幕尺寸与统计 =====
function updateMetrics() {
  const c = document.getElementById('metrics');
  if (!c) return;
  const list = shelfView();
  const chromeH = 24 + 22 + 12 + 28 + 3 * 4;
  const listH = SH - 12 - chromeH;

  const m = CFG.readerMargin;
  const availH = SH - m * 2 - 14;      // 扣除状态栏 13px
  const lineH = Math.ceil(CFG.baseFontSize * 1.35) + CFG.lineSpacing;
  const lpp = Math.max(1, Math.floor(availH / lineH));
  const textBottom = m + lpp * lineH;
  const statusTop = SH - 14;

  c.innerHTML = `
    <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:8px">
      ${metric('阅读器每页行数', lpp + ' 行', lpp >= 6 ? 'good' : 'bad')}
      ${metric('正文底部 / 状态栏顶', textBottom + ' / ' + statusTop + 'px',
               textBottom <= statusTop ? 'good' : 'bad')}
      ${metric('书架列表可用高度', listH + 'px', listH >= 66 ? 'good' : 'bad')}
      ${metric('书架可见条目', Math.max(0, Math.floor(listH / 24)) + ' 本',
               listH >= 48 ? 'good' : 'bad')}
    </div>`;
}
function metric(k, v, cls = '') {
  return `<div style="background:#1e2329;border-radius:8px;padding:8px 10px">
    <div style="font-size:10.5px;color:#7d8794;margin-bottom:3px">${k}</div>
    <div style="font-size:15px;font-weight:700" class="${cls}">${v}</div>
  </div>`;
}

// ===== 启动 =====
window.addEventListener('DOMContentLoaded', () => {
  document.getElementById('screen').style.width = SW + 'px';
  document.getElementById('screen').style.height = SH + 'px';
  render();
  document.addEventListener('keydown', e => {
    if (e.key === 'ArrowRight') nextPage(6);
    if (e.key === 'ArrowLeft')  nextPage(-6);
    if (e.key === 'Escape')     closePanel();
  });
});
