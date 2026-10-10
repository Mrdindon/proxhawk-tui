# Proxhawk-tui — Proxmox VE 的文本控制台

[English](README.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | **简体中文** | [Русский](README.ru.md)

版本 2.2.0 · 许可证 AGPL-3.0-or-later

`proxhawk-tui` 是 Proxmox VE Web 界面（运行在 8006 端口的 GUI）的文本版本。它使用
Unicode 边框、盲文字符图表、Nerd Font 图标和 ANSI 颜色，重现了 Web 界面的布局、
导航和大部分面板，并且不需要任何 Proxmox VE 节点上尚未安装的软件。

![proxhawk-tui 演示：数据中心概要和 HA、节点概要、网络、系统日志、社区脚本和磁盘、虚拟机概要和选项](docs/demo.gif)

*演示数据。*

## 亮点

- **与 Web 界面相同的布局和菜单**（已对照 Proxmox VE 9 的菜单定义检查）：顶部栏、
  资源树（服务器 / 文件夹 / 池 / 存储视图）、各对象的导航菜单、工具栏、内容面板
  以及*任务 / 集群日志*面板。
- **读写**：每个配置表格都提供*添加 / 编辑 / 删除*（`a` / `e` / `d`）。对话框
  **根据所调用 API 的模式自动生成**，因此提供与 GUI 对话框相同的参数、选项和默认
  值，包括在子表单中编辑的属性字符串（`net0`、`scsi0`、`rootfs`……）。
- **完整覆盖 GUI**：数据中心（集群、选项、各类存储、备份任务、复制、权限、用户、
  API 令牌、双因素认证、组、池、角色、领域、HA 和亲和性规则、SDN 及其区域、VNet、
  子网、控制器、IPAM、DNS、VNet 防火墙、fabric、路由映射、前缀列表、ACME、防火墙、
  指标服务器、资源和目录映射、自定义 CPU 型号、通知），节点（可应用/还原的网络、
  证书和 ACME 申请、DNS、hosts、时间、服务、更新、软件源、磁盘的 GPT/擦除、LVM、
  LVM-Thin、目录、ZFS、带安装向导的 **Ceph**、监视器、OSD、CephFS、池），虚拟机
  和容器（硬件/资源、cloud-init、选项、快照、备份、恢复、防火墙、权限、HA、克隆、
  模板、迁移）。
- **控制台**：有串口的虚拟机使用 `qm terminal`，**没有串口的 Linux 虚拟机使用
  SSH**（IP 通过客户机代理、邻居表或网桥网络扫描获得），容器使用 `pct enter`，
  以及节点 Shell。
- **极小的占用**：纯 bash，加上 Proxmox VE 自带的 Perl 和 `pvesh`。对话框使用
  `whiptail`（同样自带）或 `dialog`。没有守护进程，没有依赖，除了
  `~/.config/proxhawk-tui` 和一个临时目录外不写入任何内容。
- **快速**：一个常驻的小型 Perl 助手只加载一次 API，以毫秒级响应请求，而不是每次
  读取都启动 `pvesh`（1–2 秒）。
- **经过测试**：`tools/integration-test.sh` 在真实节点上操作每个面板和每个动作，
  并通过 API 验证每一次写入（参见 [docs/TESTING.md](docs/TESTING.md)）。
- **模块化**：每个面板都是 `views/` 中的一个小函数；主题、图标集和语言都是普通
  文件。
- **键盘和鼠标**，256 色、真彩色或 8 色，Nerd Font、Unicode、纯 ASCII 或无图标。
  快捷键和颜色可配置；十种主题（Dracula、Nord、Gruvbox、Catppuccin、Tokyo
  Night……）。
- **34 种语言**：英语、法语、西班牙语、德语、简体中文和俄语完整翻译；其他 GUI
  语言通过节点上安装的 Proxmox VE 官方翻译目录提供（与 GUI 用词相同）。参见
  [docs/I18N.md](docs/I18N.md)。
- **批量操作和队列**：在搜索表格中用`空格键`标记虚拟机，一起启动、停止或备份；
  对忙碌虚拟机的操作会进入队列。
- **可脚本化**：`proxhawk-tui guests list -o table`、
  `proxhawk-tui guests start 101`、`proxhawk-tui api get /version`……
  （输出 JSON 或表格，参见 [docs/CLI.md](docs/CLI.md)）。
- **插件**：可选的菜单项（community-scripts 安装器、Ansible 清单）——参见
  [docs/EXTENDING.md](docs/EXTENDING.md#plugins)。

## 要求

| 组件 | 说明 |
|-----------|-------|
| Proxmox VE 7、8 或 9 节点 | 在节点上以 `root` 运行，直接运行或使用 `sudo`（参见[谁可以运行](#谁可以运行)） |
| bash ≥ 4.3 | 标准 |
| perl + PVE Perl 模块 | 随 Proxmox VE 提供 |
| `whiptail` 或 `dialog` | 默认已安装 `whiptail`；否则使用内置提示 |
| `less` | 可选，用于显示日志 |
| UTF-8 终端，≥ 80×18 | 建议 256 色；使用原始图标需要 Nerd Font |

## 安装

### 一行命令（最新版本的软件包）

在 Proxmox VE 节点上，以 root（或使用 `sudo`）运行一行命令即可安装最新版本
（`apt` 安装前会用 SHA-256 校验和检查 `.deb`）：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mrdindon/proxhawk-tui/main/install.sh)"
proxhawk-tui
```

使用 sudo：`sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mrdindon/proxhawk-tui/main/install.sh)"`，
然后运行 `sudo proxhawk-tui`。

卸载：`apt remove proxhawk-tui`。运行前可以先阅读 [install.sh](install.sh)；
软件包也可以在 [Releases 页面](https://github.com/Mrdindon/proxhawk-tui/releases)
下载。

### 使用 git clone

`main` 分支包含已发布的版本（标签 `vX.Y.Z`）；`develop` 是开发中的版本。

```bash
apt install git            # 如果尚未安装 git
git clone https://github.com/Mrdindon/proxhawk-tui.git /opt/proxhawk-tui
cd /opt/proxhawk-tui
./proxhawk-tui             # 直接运行，或：
./install.sh               # 命令 "proxhawk-tui"（/usr/local/bin 中的符号链接）
```

- **更新**：`proxhawk-tui upgrade`（参见[更新](#更新)）。
- **指定版本**：`git checkout vX.Y.Z`（回到最新版本：`git checkout main`）。
- **卸载**：`./install.sh --uninstall`，然后删除该目录。
- 可以使用任何目录；`./install.sh --prefix DIR` 将命令放在 `/usr/local/bin`
  以外的位置。
- 不要混用两种方式：使用克隆之前先卸载软件包（`apt remove proxhawk-tui`），
  反之亦然。

### 更新

```bash
proxhawk-tui upgrade --check    # 是否有新版本？（有则退出码为 10）
proxhawk-tui upgrade            # 更新（会请求确认；使用 --yes 跳过）
```

`upgrade` 会检测 proxhawk-tui 的安装方式：

| 安装方式 | `upgrade` 的操作 |
|---|---|
| 一行命令安装（`.deb` 软件包） | 下载最新版本的 `.deb`，校验其 SHA-256，并用 `apt` 安装（以 root 或使用 `sudo`） |
| `git clone` | `git fetch`，显示新版本及其提交，然后对当前分支执行 `git pull --ff-only`（有本地修改时拒绝） |
| 手动解压的归档 | 显示可用的版本及安装方法 |

`--version X.Y.Z` 安装指定版本（软件包）。再次运行一行安装命令同样会更新软件包。

### 谁可以运行

proxhawk-tui 像 `pvesh` 一样直接使用本地的 Proxmox VE API（不经过 HTTP，不使用
票据）：它必须在节点上以 **root** 运行，直接运行或使用 `sudo`。**Proxmox VE
权限**是另一个层级：启动时，proxhawk-tui 会询问以哪个 Proxmox VE 用户的身份操作
（`root@pam`、`alice@pve`……），并像 GUI 一样应用该用户的权限（参见
[Running as another user](docs/CONFIGURATION.md#running-as-another-user)）。
要从非 root 的 Linux 账户运行 proxhawk-tui，需要通过 HTTPS 和令牌访问 API：目前
尚不支持。

常用选项：

```bash
proxhawk-tui --glyphs nerd       # GUI 的 Font Awesome 图标（需要在您的终端中
                                 # 使用 Nerd Font，参见 docs/CONFIGURATION.md）
proxhawk-tui --theme dark        # "Proxmox Dark" 外观
proxhawk-tui --lang zh_CN        # 界面语言（默认：自动）
proxhawk-tui --select qemu/100   # 直接打开虚拟机 100
proxhawk-tui --backend pvesh     # 不使用常驻的 API 助手
```

## 常用按键

| 按键 | 操作 |
|-----|--------|
| `↑` `↓` / `j` `k`、`PgUp` `PgDn`、`Home` `End` | 在当前面板中移动 |
| `Tab` / `Shift+Tab` | 下一个 / 上一个面板（树 → 菜单 → 内容 → 任务） |
| `←` `→` | 在树中折叠 / 展开，在面板之间切换 |
| `回车` | 打开 / 操作所选行 |
| `/` | 搜索资源 |
| `v` | 切换树视图（服务器、文件夹、池、存储） |
| `a` `e` `d` | 在配置表格中添加、编辑、删除 |
| `s` `h` `c` `H` `m` | 启动、关机菜单、控制台、SSH、更多（虚拟机） |
| `b` `h` `S` `B` | 重启、关机、Shell、批量操作（节点） |
| `t` | 更改概要中图表的时间范围 |
| `l` | 切换*任务* / *集群日志* |
| `r` / `F5` | 刷新 |
| `F1` / `?` | 帮助窗口：当前面板的按键 |
| `F2` `F3` `F4` | 顶部栏按钮：创建虚拟机、创建 CT、用户菜单（设置、图标、语言……） |
| `空格` `m` `f` | 标记虚拟机、批量操作、过滤（搜索表格） |
| `w` | 虚拟机或节点的浏览器控制台 URL（noVNC / xterm.js） |
| `F6` | 暂停 / 恢复自动刷新 |
| `q` / `F10` | 退出 |

完整列表见 [docs/USAGE.md](docs/USAGE.md)。

## 文档

详细文档为英文。

| 文档 | 内容 |
|----------|---------|
| [docs/USAGE.md](docs/USAGE.md) | 用户指南：屏幕布局、导航、每个面板和动作 |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | 配置文件、快捷键、颜色、命令行、插件、主题、图标集 |
| [docs/CLI.md](docs/CLI.md) | 非交互式命令（JSON / 表格） |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 模块、数据流、API 助手协议、渲染 |
| [docs/EXTENDING.md](docs/EXTENDING.md) | 如何添加面板、动作、主题或图标集 |
| [docs/I18N.md](docs/I18N.md) | 语言、翻译、添加语言 |
| [docs/TESTING.md](docs/TESTING.md) | lint、自检、屏幕测试、读写集成测试 |
| [AGENTS.md](AGENTS.md) | 面向编程代理的简短指南 |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | 内部说明：设计决策、Proxmox VE 的行为、发布流程 |
| [CHANGELOG.md](CHANGELOG.md) | 版本记录 |
| [docs/COMPARISON-devnullvoid-pvetui.md](docs/COMPARISON-devnullvoid-pvetui.md) | 对 devnullvoid/pvetui 的分析及改进思路 |

## 项目结构

```
proxhawk-tui     入口（参数、主循环、键盘/鼠标）
install.sh       安装 / 卸载（来自 GitHub 的软件包，或符号链接）
lib/             模块（终端、API、组件、布局、动作……）
lib/broker.pl    常驻的 API 助手（Perl、PVE 模块）
views/           每种对象类型一个文件（datacenter、node、qemu、lxc……）
themes/          配色主题
plugins/         可选插件（在 F4 > 插件 中启用）
lang/            语言（en、fr、es、de、zh_CN、ru + TEMPLATE.sh）
fonts/           节点 Linux 控制台使用的字体
conf/            示例配置
tests/screens/   屏幕测试场景、录制的 API 响应、参考屏幕
tools/           lint.sh、selftest.sh、screen-test.sh、integration-test.sh、
                 i18n-extract.sh、i18n-check.sh、make-release.sh、make-deb.sh
docs/            文档
```

## 限制

- 图形控制台（noVNC、SPICE）无法在终端中显示：改用串行控制台、SSH 或
  `pct enter`（`w` 提供浏览器中 noVNC 控制台的 URL）。
- 只能在集群的节点上运行（尚不支持远程连接 API）。
- proxhawk-tui 在集群节点上以 `root` 运行（直接运行或使用 `sudo`）：它像 `pvesh`
  一样直接使用本地 API（不经过 HTTP，不使用票据）；应用的 Proxmox VE 权限是启动时
  所选用户的权限。
- 上传（ISO、模板、代码片段）使用节点本身上的文件。
- 在节点的 Linux 控制台（显示器/键盘、IPMI）上无法使用 Nerd Font：proxhawk-tui 会在
  那里加载自带的控制台字体（图标和图表，退出时恢复原字体）；中文、日文、韩文以及
  从右到左书写的语言在该控制台上会回退为英文。参见
  [docs/CONFIGURATION.md](docs/CONFIGURATION.md#linux-console)。

## 开发方式

proxhawk-tui 使用 Anthropic 的 AI 编程代理 [Claude Code](https://claude.com/claude-code)
编写，由作者指导和审查，并在真实的 Proxmox VE 节点上测试（参见
[docs/TESTING.md](docs/TESTING.md)）。设计说明和经验总结见
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)；[AGENTS.md](AGENTS.md) 是提供给参与
开发的编程代理的指南。

## 许可证和名称

proxhawk-tui 是自由软件，采用 **GNU Affero 通用公共许可证 v3.0 或更高版本**（参见
[LICENSE](LICENSE)），即 Proxmox VE 本身的许可证，API 助手会加载其 Perl 模块。

Proxmox® 是 Proxmox Server Solutions GmbH 的注册商标。proxhawk-tui 是一个独立
项目，与 Proxmox Server Solutions GmbH 无关联，也未获其认可。它曾名为 *pvetui*
（1.0 – 1.1），后改名为 *pvetty*（1.2 – 1.3）；这些版本的设置会自动迁移。
