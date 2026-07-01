# 电子书阅读器 v6.5.0

[许可证: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)(https://www.gnu.org/licenses/gpl-3.0)

一款专为词典笔设计的小说阅读器插件，支持本地 `.txt` 小说阅读，并提供局域网网页上传功能，让你轻松在词典笔上看小说。

插件基于 [PenMods](https://github.com/PenUniverse/PenMods) 插件环境开发，适用于已经刷入或修改为 PenMods 相关系统的设备。

## 功能特性

### 核心阅读

- 自动扫描 `/userdisk/Music/小说/` 目录下的 `.txt` 小说文件
- "我的书架"独立页面，显示所有已扫描和已阅读的小说
- 支持手动输入书名打开小说（无需输入完整路径）
- 自动记录每本小说的阅读进度，下次打开自动恢复
- **逐章加载**：每次只加载当前章节，进入阅读器极速打开
- **章节导航**：滚动模式下章节顶部"上一章"、底部"下一章"按钮，分页模式章尾"下一章"按钮
- 支持书签功能，可添加、查看、删除书签
- 支持章节识别与跳转（自动识别"第X章"等中文章节格式）
- **书架进度**：显示整本书总阅读进度
- **菜单进度**：显示当前章节阅读进度

### 阅读设置

- 三种字号可选：小（13px）、中（15px）、大（18px），**默认中号**
- 三种行距模式：紧凑、标准、宽松
- 七种阅读主题：默认、白色、黄色、绿色、黑色、粉色、蓝色
- 支持自动翻页，可自定义间隔秒数（1~999 秒）

### 两种阅读模式

#### 分页模式（默认）
- 适合专注阅读，一页一页翻
- 点击/滑动翻页
- 章末自动显示"下一章 →"按钮
- 再次点击右区域或按钮加载下一章

#### 滚动模式
- 适合快速浏览，上下滑动滚动查看全文
- 章节顶部显示"← 上一章"按钮
- 章节底部显示"下一章 →"按钮
- 右下角 ☰ 按钮打开菜单
- 可随时在菜单中切换滚动/分页模式（切换后自动保存位置）

### 交互操作

- 点击屏幕左 1/3 区域：上一页（分页模式）/ 上翻一屏（滚动模式）
- 点击屏幕右 1/3 区域：下一页（分页模式）/ 下翻一屏（滚动模式）
- 点击屏幕中间 1/3 区域：打开菜单
- 滑动操作：上/下/左/右滑动均可翻页
- 长按屏幕：返回首页（分页、滚动模式均支持）
- 菜单面板：进度条拖拽跳转、百分比快速跳转、页码跳转、章节列表跳转
- **☰ 浮动菜单按钮**：滚动模式右下角显示，点击打开菜单

### 内置教程

- 书架页面右上角有"教程"按钮，点击即可查看使用教程
- 教程内容涵盖小说存放、上传方式、阅读操作、菜单功能、常见问题等
- 阅读教程的操作与阅读小说一致（点击/滑动翻页）

### Toast 提示

- 底部弹出式黑色圆角提示，2 秒自动消失
- 书签添加成功、模式切换等操作均有 Toast 反馈

### 局域网上传

- - 内置 HTTP 上传服务器（端口 8088）
- - 支持 Python3 和 Node.js 两种运行时（自动检测）
- - 手机/电脑浏览器打开即用，无需安装额外 App
- - 上传的文件自动保存到 `/userdisk/Music/小说/` 目录
- - 文件名自动清理特殊字符，确保兼容性

## 文件结构

```
novel-reader/
├── main.qml              # 主界面 QML 文件（阅读器核心逻辑与 UI）
├── ReaderUtils.js        # 阅读器工具函数（换行、章节扫描、书架列表等）
├── Storage.js            # JSON 文件持久化存储
├── MenuButton.qml        # 菜单按钮组件
├── SponsorDialog.qml     # 赞赏弹窗组件
├── TutorialPage.qml      # 使用教程页面
├── metadata.json         # 插件元数据（ID、版本、作者等）
├── libshell_plugin.so    # Shell 插件原生库（用于启动上传服务）
├── start-uploader.sh     # 上传服务启动脚本（自动检测 python3/node）
├── uploader.py           # Python 版上传 HTTP 服务器
├── uploader.js           # Node.js 版上传 HTTP 服务器
├── Thanks.PNG            # 爱发电赞赏二维码
├── weixin.png            # 微信赞赏二维码
├── icon.png              # 应用图标
├── LICENSE               # GPL v3 开源协议
└── README.md             # 说明文档
```

## 适用环境

- 已安装或使用 PenMods 修改过的词典笔系统
- 插件系统支持 QML 插件加载
- 如需使用局域网上传功能，词典笔系统内需要有 `python3` 或 `node`
- 词典笔和手机/电脑需连接至同一局域网 Wi-Fi

## 安装方式
### 安装`python3` 和 `node`

## 1. 前置准备

### 1.1 PC 端

- ADB 已安装并能连接设备
- 网络可访问以下站点：
  - `https://nodejs.org`（Node.js 官方下载）
  - `https://github.com`（Python 预编译包）

### 1.2 设备端
#### 确认设备连接
adb devices
#### 输出示例:
#### List of devices attached
#### 2CA0000000000    device

## 2. 下载预编译包

### 2.1 Python 3 (python-build-standalone)

> **来源**: [astral-sh/python-build-standalone](https://github.com/astral-sh/python-build-standalone)
>

前往 [Releases 页面](https://github.com/astral-sh/python-build-standalone/releases)，找到最新版本（如 `20260610`）。

下载对应的 **aarch64 install_only** 包：

| Python 版本 | 下载文件名 |
|-------------|-----------|
| **3.11** | `cpython-3.11.XX+YYYYMMDD-aarch64-unknown-linux-gnu-install_only.tar.gz` |


> ⚠️ 务必选择 `install_only` 版本，体积更小；`aarch64-unknown-linux-gnu` 对应 glibc 版本。

### 2.2 Node.js

> **来源**: [nodejs.org](https://nodejs.org)
>
> **⚠️ 重要**：Node.js v18 起要求 **glibc ≥ 2.28**，而本设备只有 **glibc 2.27**。因此必须使用 **Node.js v16 LTS**！

直接下载 Node.js v16.20.2 ARM64 版：

```bash
# 命令行下载 (Windows/Linux/macOS)
curl -L -o node-v16.20.2-linux-arm64.tar.xz \
  "https://nodejs.org/dist/v16.20.2/node-v16.20.2-linux-arm64.tar.xz"
```

或浏览器访问：https://nodejs.org/dist/v16.20.2/node-v16.20.2-linux-arm64.tar.xz

### 2.3 确认文件

下载完成后，两个文件名如下：

```
cpython-3.11.15+20260610-aarch64-unknown-linux-gnu-install_only.tar.gz  (~49 MB)
node-v16.20.2-linux-arm64.tar.xz                                         (~22 MB)
```

---

## 3. 推送到设备

```bash
# 推送 Python
adb push cpython-3.11.15+20260610-aarch64-unknown-linux-gnu-install_only.tar.gz \
  /userdisk/PenMods/plugins/novel-reader/

# 推送 Node.js
adb push node-v16.20.2-linux-arm64.tar.xz \
  /userdisk/PenMods/plugins/novel-reader/

# 确认文件已推送
adb shell ls -la /userdisk/PenMods/plugins/novel-reader/*.tar.*
```

---

## 4. 解压安装

### 4.1 Python（tar.gz 格式）

```bash
adb shell

# 进入目标目录
cd /userdisk/PenMods/plugins/novel-reader

# 解压 (BusyBox tar 支持 -z 即 gzip)
tar -xzf cpython-*.tar.gz

# 验证
./python/bin/python3 --version
# 输出: Python 3.11.15
```

### 4.2 Node.js（tar.xz 格式）

BusyBox 的 tar 不支持 `-J`（xz），需要两步：

```bash
# 第一步: 先解 xz 压缩
unxz node-v16.20.2-linux-arm64.tar.xz
# 得到 node-v16.20.2-linux-arm64.tar

# 第二步: 解 tar 包
tar -xf node-v16.20.2-linux-arm64.tar

# 验证
./node-v16.20.2-linux-arm64/bin/node --version
# 输出: v16.20.2
```

### 4.3 清理安装包

```bash
# 删除压缩包，释放空间
rm -f cpython-*.tar.gz node-*.tar.xz node-*.tar
```

---

## 5. 全局配置

将 Python 和 Node.js 链接到系统 PATH 中：

```bash
# 创建软链接
ln -sf /userdisk/PenMods/plugins/novel-reader/python/bin/python3 /usr/bin/python3
ln -sf /userdisk/PenMods/plugins/novel-reader/python/bin/python3 /usr/bin/python
ln -sf /userdisk/PenMods/plugins/novel-reader/node-v16.20.2-linux-arm64/bin/node   /usr/bin/node
ln -sf /userdisk/PenMods/plugins/novel-reader/node-v16.20.2-linux-arm64/bin/npm    /usr/bin/npm

# 退出 adb shell
exit
```



---

## 6. 验证安装

```bash
# 全局验证（从任意目录）
adb shell python3 --version
adb shell node --version
adb shell npm --version

# 预期输出:
# Python 3.11.15
# v16.20.2
# 8.19.4
```

```bash
# 验证 command -v 能找到
adb shell "command -v python3 && command -v node && command -v npm"

# 预期输出:
# /usr/bin/python3
# /usr/bin/node
# /usr/bin/npm
```
### 安装插件
通过 PenMods 插件目录安装

将整个 `novel-reader` 文件夹复制到 PenMods 的插件目录下：

```
/userdisk/PenMods/plugins/novel-reader/
```

安装完成后，在插件管理中即可打开


## 小说默认目录

小说默认读取目录为：

```
/userdisk/Music/小说/
```

请把 `.txt` 小说文件放到这个目录下。阅读器打开后会自动扫描该目录中的 `.txt` 文件，并在"我的书架"中显示。

示例：

```
/userdisk/Music/小说/三体.txt
/userdisk/Music/小说/斗破苍穹.txt
/userdisk/Music/小说/凡人修仙传.txt
```

### 手动输入书名

手动输入书名时，不需要输入完整路径。比如小说文件是 `/userdisk/Music/小说/三体.txt`，在阅读器里输入 `三体` 或 `三体.txt` 即可打开。

## 上传小说的方式

### 方式一：局域网网页上传（推荐）

这是最简单的上传方式，无需任何工具，手机/电脑浏览器即可完成。

#### 1. 启动上传服务

打开阅读器后，插件会尝试自动启动上传服务。

启动成功后，首页会显示类似下面的网址：

```
http://192.168.1.23:8088
```

如果服务未自动启动，可以点击首页的"启动上传"按钮手动启动。

#### 2. 上传小说

在同一 Wi-Fi 下，用手机或电脑浏览器打开这个地址，即可看到上传页面。

选择手机/电脑上的 `.txt` 文件，点击"上传 txt"按钮即可。

上传后的小说会自动保存到 `/userdisk/Music/小说/` 目录。

#### 3. 查看小说

上传完成后，回到阅读器的"我的书架"，即可看到上传的小说。

#### 常见问题

如果首页一直显示"上传服务启动中"，可能是：

- 系统内没有 `python3` 或 `node`（可通过 SSH 执行 `which python3` 或 `which node` 检查）
- 插件的 shell 启动能力没有正常加载
- 端口 8088 已被其他程序占用

### 方式二：通过 SSH 上传（WinSCP / Termius）

如果网页上传不可用，也可以使用 SSH 直接把小说文件传到词典笔里。

#### 前置条件

- 词典笔已经连接 Wi-Fi
- 电脑或手机和词典笔在同一个 Wi-Fi 下
- PenMods 开发者设置里已经开启 SSH
- 已经在 PenMods 开发者设置里设置好 SSH 密码
- 已经知道词典笔的 IP 地址

#### 查看词典笔 IP

通常可以在词典笔的 Wi-Fi 设置中查看当前连接网络的 IP 地址。常见的格式类似于：

```
192.168.1.23
```

#### SSH 连接信息

```
地址：词典笔 IP（例如 192.168.1.23）
端口：22
用户名：root
密码：PenMods 开发者设置中设置的 SSH 密码
```

如果你的系统用户名不是 `root`，请以实际系统为准。

#### 使用电脑上传：WinSCP

1. 下载并安装 [WinSCP](https://winscp.net/)
2. 打开 WinSCP，新建连接
3. 填写连接信息：
   - 文件协议：SFTP
   - 主机名：词典笔的 IP
   - 端口号：22
   - 用户名：root
   - 密码：你在 PenMods 开发者设置中设置的 SSH 密码
4. 点击登录/连接
5. 如果第一次连接弹出主机密钥提示，选择接受
6. 连接成功后，进入 `/userdisk/Music/小说/` 目录
7. 在左侧找到电脑上的 `.txt` 小说文件，拖到右侧即可
8. 上传完成后，打开阅读器，进入"我的书架"查看

#### 使用手机上传：Termius

1. 在手机上安装 Termius（iOS/Android 均可）
2. 新建连接，填写：
   - Host：词典笔的 IP
   - Port：22
   - Username：root
   - Password：你在 PenMods 开发者设置中设置的 SSH 密码
3. 保存并连接
4. 第一次连接时如果出现确认主机指纹的提示，选择确认
5. 连接成功后，进入 SFTP 文件管理界面
6. 进入 `/userdisk/Music/小说/` 目录
7. 选择手机里的 `.txt` 小说文件，上传即可
8. 上传完成后，回到阅读器"我的书架"查看

## 阅读界面操作说明

### 翻页操作

| 操作 | 说明 |
|------|------|
| 点击屏幕左侧 1/3 | 上一页 |
| 点击屏幕右侧 1/3 | 下一页 |
| 点击屏幕中间 1/3 | 打开菜单 |
| 上/下滑动 | 翻页 |
| 左/右滑动 | 翻页 |

### 菜单功能

| 功能 | 说明 |
|------|------|
| 进度条 | 拖拽可快速跳转到指定位置 |
| 字号 | 小 / 中 / 大 三档切换 |
| 行距 | 紧凑 / 标准 / 宽松 三档切换 |
| 主题 | 默认 / 白色 / 黄色 / 绿色 / 黑色 / 粉色 / 蓝色 |
| 返回书架 | 保存进度并返回书架页面 |
| 跳转 | 按百分比 / 页码 / 章节跳转 |
| 书签 | 查看已添加的书签列表 |
| 添加书签 | 在当前位置添加书签 |
| 自动翻页 | 设置间隔秒数后自动翻页 |
| 删除记录 | 删除当前小说的阅读进度记录 |
| 上一章 / 下一章 | 跳转到相邻章节 |

### 自动翻页

1. 在菜单中点击"自动翻页"
2. 设置间隔秒数（默认2秒，可自定义1~999秒）
3. 点击"开始"即可自动翻页
4. 点击菜单中的"停止翻页"或再次打开菜单可停止

### 书签功能

- 在阅读时点击"添加书签"，会在当前位置保存一个书签
- 书签记录当前页码和预览文本
- 点击"书签"可查看所有已添加的书签
- 点击书签条目可跳转到对应位置
- 点击书签右侧的红色"×"可删除书签

### 跳转功能

- 按百分比跳转：0%、25%、50%、75%、100% 快速跳转
- 输入页码：精确跳转到指定页
- 输入百分比：精确跳转到指定百分比位置
- 章节列表：自动识别小说中的章节标题，点击即可跳转

##技术说明

### 技术栈

- **UI 框架**：Qt Quick / QML（基于 Qt 5.15）
- **数据存储**：Qt LocalStorage（SQLite）
- **上传服务**：Python3（http.server）/ Node.js（http 模块）
- **原生插件**：libshell_plugin.so（Shell 命令执行能力）

### 上传服务原理

上传服务通过 `start-uploader.sh` 脚本启动，脚本会依次检测系统中是否有 `python3` 和 `node`：

1. 如果有 `python3`，使用 `uploader.py` 启动 HTTP 服务
2. 如果没有 `python3` 但有 `node`，使用 `uploader.js` 启动 HTTP 服务
3. 如果都没有，输出错误提示

两种实现功能完全一致：

- 监听 0.0.0.0:8088 端口
- 提供 HTML 上传页面（GET /）
- 处理文件上传（POST /upload）
- 自动检测局域网 IP 并显示
- 文件保存到 `/userdisk/Music/小说/` 目录
- 文件名自动清理特殊字符，确保兼容性

### 数据存储

阅读器使用 JSON 文件持久化存储以下数据（双备份防损坏）：

- **阅读进度**：每本小说的当前章节、章节内行号、整本书进度百分比、最后阅读时间
- **阅读设置**：字号、行距、主题颜色、自动翻页间隔、滚动/分页模式
- **书签数据**：每本小说的书签列表（含所属章节索引）

存储位置：`/userdisk/.novel-reader-state.json`（主）及 `/userdisk/PenMods/plugins/novel-reader/.state-backup.json`（备份）

### 章节识别与逐章加载

阅读器自动识别以下格式的章节标题：

- 中文章节：第X章、第X节、第X回、第X集、第X卷、第X部、第X篇（支持中文数字和阿拉伯数字）
- 英文章节：Chapter X、CHAPTER X

章节标题长度限制：1~50 字符。

**逐章加载机制**：打开文件时只扫描章节边界（纯文本扫描，极快），仅加载当前章节内容进行换行处理。阅读到章节末尾时自动加载下一章。切换章节时保存当前章节进度，下次打开自动定位。

### 阅读模式

**分页模式**（默认）：传统翻页阅读，点击/滑动翻页，章末显示「下一章 →」按钮。

**滚动模式**：上下滑动滚动查看全文，章节顶部「← 上一章」按钮，底部「下一章 →」按钮。可在菜单中随时切换。切换后自动保存阅读位置。

### 屏幕适配

阅读器界面尺寸为 320×170 像素，适配词典笔屏幕。字号与每行字符数的对应关系：

| 字号 | 每行字符数 |
|------|-----------|
| ≤13px（小） | 22 字符 |
| 14~15px（中） | 19 字符 |
| ≥16px（大） | 16 字符 |

## 文件名建议

建议小说文件使用 `.txt` 后缀，文件名简洁明了。

推荐：

```
三体.txt
凡人修仙传.txt
小说名.txt
```

不推荐：

```
三体.doc
三体.pdf
三体.epub
```

当前阅读器仅支持纯文本 `.txt` 格式。

## 常见问题

### 书架没有显示小说

- 检查小说是否放在 `/userdisk/Music/小说/` 目录下
- 确认文件后缀是 `.txt`（大小写均可）
- 尝试返回首页再重新进入书架

### 上传网页打不开

- 确认词典笔和手机/电脑在同一个 Wi-Fi 下
- 确认首页显示的地址是否为 `http://词典笔IP:8088`
- 确认浏览器输入的 IP 是否和词典笔 Wi-Fi 设置中显示的一致
- 确认词典笔系统内是否有 `python3` 或 `node`（可通过 SSH 执行 `which python3` 或 `which node` 检查）
- 尝试点击首页的"启动上传"按钮重新启动服务

### SSH 连接失败

- 确认 PenMods 开发者设置中已经开启 SSH
- 确认 SSH 密码已经设置
- 确认 IP 地址填写正确
- 确认手机/电脑和词典笔在同一个局域网
- 确认端口为 `22`

### 手动输入书名打不开

手动输入只需要输入小说名，不需要输入完整路径。

例如文件路径是 `/userdisk/Music/小说/三体.txt`，输入 `三体` 或 `三体.txt` 都可以。

### 阅读进度丢失

- 阅读进度保存在本地 JSON 文件中（`/userdisk/.novel-reader-state.json`，双备份）
- 如果卸载插件或清除应用数据，进度会丢失
- 删除小说文件不会自动清除对应的进度记录

### 自动翻页太快/太慢

在自动翻页设置中，可以自定义间隔秒数（1~999秒），点击"输入秒数"即可设置。

## 注意事项

- 本插件不会自带小说资源，请自行上传你拥有合法来源的 `.txt` 文件
- 局域网上传只在同一 Wi-Fi 内使用，不需要公网地址
- 默认小说目录固定为 `/userdisk/Music/小说/`
- 如果修改系统目录或删除小说文件，书架会根据扫描结果更新
- 书架最多显示 50 本小说（按最近阅读时间排序）

## 版本信息

- **插件 ID**：`com.reader.novel`
- **当前版本**：6.5.0
- **作者**：skdkzzx
- **基于**：PenMods 插件环境

## 更新日志 (v6.5.0)

### 新增功能
- **逐章加载**：每次只加载当前章节，大幅提升打开速度，告别大文件卡顿
- **滚动模式**：新增上下滚动阅读模式，可在菜单中随时切换滚动/分页
- **章节导航按钮**：滚动模式下章节顶部「← 上一章」、底部「下一章 →」按钮；分页模式章尾「下一章 →」按钮
- **Toast 提示系统**：底部弹出式圆角提示，书签添加、模式切换等操作有反馈
- **右下角菜单按钮**：滚动模式下显示 ☰ 浮动按钮，快速打开菜单
- **整本书进度**：书架显示总阅读进度，菜单内显示当前章节进度

### 体验优化
- 默认字号改为 15px（中号）
- 所有按钮适配 7 种阅读主题色
- 首次进入自动定位到上次阅读章节
- 分页模式双击右区域快速加载下一章（先显示按钮，再点加载）
- 书签已添加改为 Toast 提示

### 技术改进
- 移除旧版分块加载代码，改用按章加载架构
- 存储改用 JSON 文件持久化（双备份防丢失）
- 工具函数与存储逻辑模块化到独立 JS 文件

## 许可证

本项目基于 [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html) 开源。

你可以自由地使用、修改和分发本软件，但需要遵守 GPL v3 协议的条款，包括：

- 保留原始版权声明
- 衍生作品必须同样以 GPL v3 协议开源
- 必须提供源代码

详见 [LICENSE](LICENSE) 文件。
