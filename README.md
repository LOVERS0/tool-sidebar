# 小工具侧边栏（ToolSidebar）

> GitHub 仓库：https://github.com/LOVERS0/tool-sidebar  
> 下载：https://github.com/LOVERS0/tool-sidebar/releases

一个 macOS 悬浮侧边栏 + 本地安装 agent：把写作 / AI / 系统小工具收进一列，点一下启动；从 GitHub 下载开源工具时自动做自检（SHA-256、签名、公证），通过后安装并收录；支持开机自启。

![侧边栏截图](screenshot.png)

## 功能

- **一列管所有工具**：内置 26 个（写作 / AI 开发 / 系统小工具），分组、搜索、绿点=已装，点一下启动。
- **点未安装的工具 = 让本地 agent 去装**：自动查该仓库最新 Release → 选 macOS 包 → 下载 → 自检 → 安装到 `~/Applications` → 写入目录并显示在「已收录」分组。**全程在 App 内完成，不弹浏览器窗口**；失败时只弹结果说明，可点「复制链接」拿发布页。
- **顶栏 `+` 任意收录**：输入 `owner/repo`、完整 GitHub 链接，或一个搜索词（agent 会搜索并逐个探测可用 macOS 包）→ 同样走下载 + 自检 + 收录。中文关键词内置映射（窗口管理 / 剪贴板 / 菜单栏 / 压缩 / 查重 / 系统监控 / 传输 / 日历 等）。
- **自检内容**：
  - SHA-256 计算并记录；如果仓库提供官方 checksum 文件则自动比对；
  - `codesign --verify --deep --strict` 代码签名校验，不通过则不安装；
  - `spctl --assess` 公证 / Gatekeeper 评估；
  - 记录 Team ID、版本、安装时间到目录 JSON。
- **开机自启**：底部勾选即可（写 `~/Library/LaunchAgents`，取消则移除）。
- 菜单栏田字格图标唤出、置顶悬浮、`Esc` 隐藏、`⌘Q` 退出。

## 构建

需要 macOS + Command Line Tools（无需完整 Xcode）：

```bash
cd tool-sidebar
./build.sh
# 产物：~/Applications/小工具侧边栏.app
open "$HOME/Applications/小工具侧边栏.app"
```

## 使用

- 点绿色圆点的行：启动对应 App（MarkItDown 行点击复制命令）。
- 点灰色圆点的行：本地 agent 自动搜索 / 下载 / 自检 / 安装。
- 顶栏 `+`：收录不在列表里的 GitHub 工具。
- 底部「开机自启」：勾选后下次登录自动打开侧边栏。

### 命令行 / 自动化

App 自带 `--agent` 模式，等价于直接调用本地 agent：

```bash
APP="$HOME/Applications/小工具侧边栏.app/Contents/MacOS/ToolSidebar"

"$APP" --agent search maccy                # 搜仓库
"$APP" --agent install rxhanson/Rectangle  # 下载 + 自检 + 安装 + 收录
"$APP" --agent install owner/repo --check-only   # 只下载自检，不安装
"$APP" --agent list                        # 查看已收录目录
"$APP" --agent autostart status|on|off     # 开机自启
```

## 目录与数据

- 已收录工具目录：`~/Library/Application Support/小工具侧边栏/catalog.json`
- 下载缓存：`~/Library/Caches/ToolSidebar/`
- 开机自启：`~/Library/LaunchAgents/com.a1.toolsidebar.plist`
- 安装位置：`~/Applications`

## 安全说明

- 只安装 `codesign` 校验通过的 `.app`；校验失败立即停止。
- 下载文件的 SHA-256 会写入目录 JSON，便于事后核对。
- 不自带提权，不静默改系统设置；开机自启使用用户级 LaunchAgent。
- 直连 GitHub 失败时自动改用 `ghproxy.net` 镜像下载（仅下载，不涉及账号 Token）。
- 目前只自动安装 `.dmg` / `.zip` 里的 `.app`；`.pkg`、源码包和纯 CLI 工具不支持，会给出发布页链接（可复制，不会自动开浏览器）。

## 已知限制

- GitHub API 未带 Token 时 60 次/小时，搜索和查 Release 会受限；可在 `~/.config/tool-sidebar/github_token` 放一个 Token（只用于读 API / 发布，不会外传）。
- 只挑 Apple Silicon / Universal 优先的 macOS 资源；Intel 机器可能拿到不合适的包。
- 部分仓库 Release 里没有现成 macOS App（如 Typst、novelWriter），会提示失败并给出发布页。

## 目录结构

```
ToolSidebar.swift        # App 源码（纯 AppKit）
agent/toolagent.py       # 本地安装 agent（Python 3 标准库）
build.sh                 # 编译 + 打包到 ~/Applications
screenshot.png           # 运行截图
```

## License

MIT
