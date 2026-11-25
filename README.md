# 小工具侧边栏 · ToolSidebar

[![Release](https://img.shields.io/github/v/release/LOVERS0/tool-sidebar?color=6ea8fe&label=release)](https://github.com/LOVERS0/tool-sidebar/releases)
[![Platform](https://img.shields.io/badge/macOS-13%2B-black)](https://github.com/LOVERS0/tool-sidebar)
[![License](https://img.shields.io/github/license/LOVERS0/tool-sidebar?color=green)](LICENSE)

[English](README.en.md) · [下载最新版](https://github.com/LOVERS0/tool-sidebar/releases/latest) · [官网](https://lovers0.github.io/tool-sidebar/) · [反馈问题](https://github.com/LOVERS0/tool-sidebar/issues)

把常用的写作、AI 和系统工具放进一个 macOS 悬浮侧边栏。按 `⌥⌘T` 呼出，搜索后回车打开；还没装的工具，可以从 GitHub 下载并安装。

![ToolSidebar 1.11.0 侧边栏：全部、已安装、收藏筛选和明确的行操作](screenshot.png)

## 1.11.0：精简为应用启动与管理

- 移除内置在线翻译和离线词库窗口，应用不再请求翻译服务。
- 缺少明确来源的应用只显示「未安装」，不再按名字猜仓库并自动安装。
- 移除全量批量安装，以及「去 AI 味」、网页排版、复制命令、CLI 工具等非应用入口。
- 导入配置只恢复工具清单与设置。缺少的应用保留为待安装项，由你逐个选择安装。
- 菜单保留检查更新、开机自启、配置备份、反馈和退出。启动失败时显示实际错误，不再引导你给本应用开辅助功能权限。

搜索、收藏、分类、快捷键、悬浮球，以及单个应用的安装、更新和卸载继续保留。已有工具记录、收藏和旧版备份仍可使用。

## 安装

从 [Releases](https://github.com/LOVERS0/tool-sidebar/releases/latest) 下载 `ToolSidebar.zip`，解压后将 `小工具侧边栏.app` 放入 `/Applications` 或 `~/Applications`。

需要 **macOS 13.0 或更新版本**，支持 Apple Silicon 和 Intel。当前安装包采用 ad-hoc 签名，尚未经过 Apple 公证；如系统拦截首次打开，请先确认下载来源，再按「系统设置 → 隐私与安全」中的提示处理。

也可以通过 Homebrew 安装：

```bash
brew tap lovers0/tool-sidebar
brew install --cask tool-sidebar
```

## 日常使用

| 操作 | 方法 |
| --- | --- |
| 呼出或收起 | `⌥⌘T`；收起后也可点悬浮球展开 |
| 搜索 | `⌘F` 聚焦搜索框，输入名称或说明关键词 |
| 键盘打开 | `↑↓` 选择，`⏎` 打开或执行对应操作 |
| 清空 / 收起 | `Esc` 先清空搜索，再收起侧边栏 |
| 收藏、分类和排序 | 右键工具行 |
| 添加工具 | 顶栏 `+`，输入 `owner/repo`、GitHub 链接或搜索词 |
| 更新、卸载、定位应用 | 右键已收录的工具 |
| 自启、配置备份和恢复 | 顶栏 `⋯` 菜单 |

内置 22 个应用入口，按写作、AI / 开发、系统小工具分组；远程精选列表从仓库的 `featured.json` 更新。需要手动下载的应用会打开官方页面。

你可以重命名工具、调整顺序和分类。换机时，在 `⋯` 中导出配置，再在新机器导入；配置包含已装及已收录的工具清单、名称、分类、排序、收藏和自启设置；导入时不会自动下载或安装应用。

收起后显示可拖动的悬浮球：

![悬浮球](ball.png)

## 安装与更新的检查

安装助手支持 `.dmg` / `.zip` 中的 `.app`，安装位置为 `~/Applications`；不支持 `.pkg` 安装器和纯命令行工具。

- GitHub 提供官方 SHA-256 digest 时，必须比对一致。
- 自动安装要求代码签名和 macOS Gatekeeper 评估均通过。未通过会停止，并提供官方发布页入口。
- 保留应用隔离标记；不会静默清除系统安全检查。
- 直连下载失败时会尝试 `ghproxy.net` 镜像，仍执行上述检查。计算出的 SHA-256 会写入本地目录记录。
- 应用自身通过 Sparkle 和已签名的 appcast 更新。`⋯` →「检查更新…」可以手动检查。

安装助手会优先读取 `~/.config/tool-sidebar/github_token`，其次读取 `GITHUB_TOKEN`，再尝试已登录的 `gh`，用于提高 GitHub API 配额。Token 仅用于 GitHub API 请求。

## 构建与测试

需要 macOS 和 Xcode Command Line Tools：

```bash
git clone https://github.com/LOVERS0/tool-sidebar.git
cd tool-sidebar
./build.sh
./scripts/test.sh
```

产物位于 `build/小工具侧边栏.app`，默认不会覆盖已安装的版本。可用 `APP_PATH` 指定其他绝对 `.app` 路径；`VERSION`、`SIGN_IDENTITY` 和 `NOTARY_PROFILE` 分别控制版本、Developer ID 签名与公证。

回归检查覆盖芯片架构选择、失败时保留旧版、子进程输出、旧配置兼容、安装识别、搜索行复用、列表筛选、精简菜单及配置恢复。CI 会构建 Universal 包并运行检查。

截图来自实际 AppKit 视图，可用 `./scripts/screenshots.sh` 重新生成。发布流程见 [RELEASE.md](RELEASE.md)，Apple 公证配置见 [NOTARIZATION.md](NOTARIZATION.md)。

## 命令行与数据

```bash
APP="/Applications/小工具侧边栏.app/Contents/MacOS/ToolSidebar"
"$APP" --agent search maccy
"$APP" --agent install rxhanson/Rectangle
"$APP" --agent install owner/repo --check-only
"$APP" --agent install owner/repo --force
"$APP" --agent list
"$APP" --agent check-updates
"$APP" --agent remove owner/repo
"$APP" --agent autostart status
"$APP" --agent app-update-check
```

`--check-only` 下载并检查，不安装；`--force` 更新已存在的应用。旧的 `--agent app-update` 直接替换流程已停用，请在应用菜单使用 Sparkle 更新。

| 数据 | 路径 |
| --- | --- |
| 已收录工具 | `~/Library/Application Support/小工具侧边栏/catalog.json` |
| 名称、分类、排序和收藏 | 同目录下的 `overrides.json` |
| 下载缓存 | `~/Library/Caches/ToolSidebar/` |
| 开机自启 | `~/Library/LaunchAgents/com.a1.toolsidebar.plist` |

项目使用 Swift / AppKit，安装助手也是 Swift 实现。界面会按系统语言切换中英文。

## License

[MIT](LICENSE)
