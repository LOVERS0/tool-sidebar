import AppKit

// MARK: - 数据模型

struct Tool {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let group: String
    var path: String? = nil
    var url: String? = nil
    var command: String? = nil
    var repo: String? = nil
    var source: String = "builtin"
}

struct CatalogTool: Codable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let group: String
    let path: String?
    let repo: String?
    let version: String?
    let sha256: String?
    let installedAt: String?
}

struct CatalogFile: Codable {
    var tools: [CatalogTool]
}

func expandedPath(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}

func isInstalled(_ tool: Tool) -> Bool {
    guard let p = tool.path else { return false }
    return FileManager.default.fileExists(atPath: expandedPath(p))
}

let catalogPath: String = (("~/Library/Application Support/小工具侧边栏/catalog.json") as NSString).expandingTildeInPath
let launchAgentPath: String = (("~/Library/LaunchAgents/com.a1.toolsidebar.plist") as NSString).expandingTildeInPath

func loadCatalogTools() -> [Tool] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: catalogPath)),
          let file = try? JSONDecoder().decode(CatalogFile.self, from: data) else {
        return []
    }
    return file.tools.map { item in
        Tool(
            id: item.id,
            name: item.name,
            subtitle: item.subtitle,
            icon: item.icon,
            group: "已收录",
            path: item.path,
            repo: item.repo,
            source: "catalog"
        )
    }
}

func autostartEnabled() -> Bool {
    FileManager.default.fileExists(atPath: launchAgentPath)
}

enum Toolbox {
    static let builtinGroups = ["写作", "AI / 开发", "系统小工具"]

    static let builtin: [Tool] = [
        // 写作
        Tool(id: "zuojia", name: "作家助手", subtitle: "番茄官方 · 正文 / 发布 / 备份", icon: "square.and.pencil", group: "写作", path: "/Applications/作家助手.app"),
        Tool(id: "miaoyan", name: "妙言 MiaoYan", subtitle: "本地 Markdown · 沉浸写作", icon: "text.quote", group: "写作", path: "~/Applications/MiaoYan.app", repo: "tw93/MiaoYan"),
        Tool(id: "effie", name: "Effie", subtitle: "沉浸写作 / 大纲", icon: "pencil.line", group: "写作", path: "/Applications/Effie.app"),
        Tool(id: "siyuan", name: "思源笔记", subtitle: "设定集 / 人物卡 / 世界观", icon: "books.vertical", group: "写作", repo: "siyuan-note/siyuan"),
        Tool(id: "novelwriter", name: "novelWriter", subtitle: "小说工程 / 章节 / 情节线", icon: "list.bullet.rectangle", group: "写作", repo: "saga-soft/novelWriter"),
        Tool(id: "typst", name: "Typst", subtitle: "排版出 PDF / 样书", icon: "doc.richtext", group: "写作", repo: "typst/typst"),
        Tool(id: "doocsmd", name: "公众号排版 doocs/md", subtitle: "Markdown → 微信样式", icon: "doc.plaintext", group: "写作", url: "https://md.doocs.org/"),
        Tool(id: "avoidai", name: "去 AI 味 avoid-ai-writing", subtitle: "Agent Skill · 需配合 agent", icon: "eraser", group: "写作", url: "https://github.com/conorbronsdon/avoid-ai-writing"),

        // AI / 开发
        Tool(id: "ccswitch", name: "CC Switch", subtitle: "一键切换 AI 供应商", icon: "arrow.triangle.2.circlepath", group: "AI / 开发", path: "~/Applications/CC Switch.app", repo: "farion1231/cc-switch"),
        Tool(id: "dsh", name: "DeepSeek Harness", subtitle: "当前使用的 agent harness", icon: "terminal", group: "AI / 开发", path: "/Applications/DeepSeek Harness.app"),
        Tool(id: "dshdesktop", name: "DSH Desktop", subtitle: "桌面版", icon: "macwindow", group: "AI / 开发", path: "/Applications/DSH Desktop.app"),
        Tool(id: "githubdesktop", name: "GitHub Desktop", subtitle: "Git 图形客户端", icon: "arrow.triangle.branch", group: "AI / 开发", path: "/Applications/GitHub Desktop.app"),
        Tool(id: "openclaw", name: "OpenClaw", subtitle: "个人 AI 助理", icon: "sparkles", group: "AI / 开发", repo: "openclaw/openclaw"),
        Tool(id: "markitdown", name: "MarkItDown", subtitle: "文档转 Markdown · 点击复制命令", icon: "doc.text.magnifyingglass", group: "AI / 开发", command: "markitdown "),

        // 系统小工具
        Tool(id: "maccy", name: "Maccy", subtitle: "剪贴板历史", icon: "doc.on.clipboard", group: "系统小工具", path: "~/Applications/Maccy.app", repo: "p0deje/Maccy"),
        Tool(id: "rectangle", name: "Rectangle", subtitle: "窗口吸附", icon: "rectangle.3.group", group: "系统小工具", path: "~/Applications/Rectangle.app", repo: "rxhanson/Rectangle"),
        Tool(id: "espanso", name: "Espanso", subtitle: "文本扩展 / 缩写", icon: "text.badge.plus", group: "系统小工具", repo: "espanso/espanso"),
        Tool(id: "stats", name: "Stats", subtitle: "菜单栏系统监控", icon: "gauge.with.dots.needle.67percent", group: "系统小工具", repo: "exelban/stats"),
        Tool(id: "localsend", name: "LocalSend", subtitle: "跨设备传文件", icon: "arrow.left.arrow.right", group: "系统小工具", repo: "localsend/localsend"),
        Tool(id: "ice", name: "Ice", subtitle: "菜单栏管理", icon: "menubar.rectangle", group: "系统小工具", repo: "jordanbaird/Ice"),
        Tool(id: "keka", name: "Keka", subtitle: "压缩 / 解压", icon: "archivebox", group: "系统小工具", repo: "aonez/Keka"),
        Tool(id: "czkawka", name: "Czkawka", subtitle: "查重 / 清垃圾", icon: "trash.slash", group: "系统小工具", repo: "qarmin/czkawka"),
        Tool(id: "monitorcontrol", name: "MonitorControl", subtitle: "外接屏亮度", icon: "display", group: "系统小工具", repo: "MonitorControl/MonitorControl"),
        Tool(id: "itsycal", name: "Itsycal", subtitle: "菜单栏日历", icon: "calendar", group: "系统小工具", url: "https://www.mowglii.com/itsycal/"),
        Tool(id: "alttab", name: "AltTab", subtitle: "窗口切换", icon: "rectangle.on.rectangle", group: "系统小工具", repo: "lwouis/alt-tab-macos"),
        Tool(id: "latest", name: "Latest", subtitle: "检查 App 更新", icon: "arrow.down.circle", group: "系统小工具", repo: "mangerlahn/Latest"),
    ]
}

// MARK: - 启动 / 本地 agent

func launchTool(_ tool: Tool) {
    if let cmd = tool.command {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        NSSound(named: "Pop")?.play()
        return
    }
    if let p = tool.path {
        let path = expandedPath(p)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
            return
        }
    }
    if let s = tool.url, let url = URL(string: s) {
        NSWorkspace.shared.open(url)
    }
}

enum AgentRunner {
    static var scriptPath: String {
        Bundle.main.path(forResource: "toolagent", ofType: "py", inDirectory: "agent") ?? ""
    }

    @discardableResult
    static func run(_ arguments: [String], completion: ((String) -> Void)? = nil) -> Process? {
        let script = scriptPath
        guard !script.isEmpty else {
            completion?("")
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            completion?("")
            return nil
        }
        if let completion = completion {
            let work = DispatchWorkItem {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                let done = DispatchWorkItem { completion(text) }
                DispatchQueue.main.async(execute: done)
            }
            DispatchQueue.global().async(execute: work)
        }
        return process
    }
}

struct AgentResult {
    var ok = false
    var name: String?
    var version: String?
    var path: String?
    var message: String?
    var error: String?
    var releaseURL: String?
    var sha256: String?
    var codesignOK: Bool?
    var notarized: Bool?
    var checksumVerified: Bool?

    static func parse(_ text: String) -> AgentResult? {
        for line in text.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"),
                  let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dict = object as? [String: Any] else { continue }
            var result = AgentResult()
            result.ok = dict["ok"] as? Bool ?? false
            result.name = dict["name"] as? String
            result.version = dict["version"] as? String
            result.path = dict["path"] as? String
            result.message = dict["message"] as? String
            result.error = dict["error"] as? String
            result.releaseURL = dict["release_url"] as? String
            result.sha256 = dict["sha256"] as? String
            result.codesignOK = dict["codesign_ok"] as? Bool
            result.notarized = dict["notarized"] as? Bool
            result.checksumVerified = dict["checksum_verified"] as? Bool
            return result
        }
        return nil
    }
}

// MARK: - 基础视图

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class ToolRowView: NSView {
    let tool: Tool
    var onClick: (() -> Void)?
    private let background = NSView()
    private var tracking: NSTrackingArea?

    init(tool: Tool) {
        self.tool = tool
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        let installed = isInstalled(tool)

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        if let image = NSImage(systemSymbolName: tool.icon, accessibilityDescription: tool.name) {
            icon.image = image
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        }
        icon.contentTintColor = installed ? .controlAccentColor : .secondaryLabelColor
        addSubview(icon)

        let title = NSTextField(labelWithString: tool.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let subtitle = NSTextField(labelWithString: tool.subtitle)
        subtitle.font = .systemFont(ofSize: 10.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = (installed ? NSColor.systemGreen : NSColor.secondaryLabelColor.withAlphaComponent(0.3)).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),

            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: dot.leadingAnchor, constant: -8),

            dot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),

            heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = tracking { removeTrackingArea(old) }
        let new = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(new)
        tracking = new
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        background.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        background.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

// MARK: - 侧边栏控制器

final class SidebarViewController: NSViewController, NSSearchFieldDelegate {
    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let stack = NSStackView()
    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private var query = ""
    private var catalogTools: [Tool] = []
    private var progressPanel: NSPanel?

    private var allTools: [Tool] {
        Toolbox.builtin + catalogTools
    }

    private var groups: [String] {
        Toolbox.builtinGroups + (catalogTools.isEmpty ? [] : ["已收录"])
    }

    override func loadView() {
        let root = NSVisualEffectView()
        root.material = .sidebar
        root.blendingMode = .behindWindow
        root.state = .active
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        catalogTools = loadCatalogTools()
        buildHeader()
        buildSearch()
        buildScroll()
        buildFooter()
        rebuild()
    }

    private func buildHeader() {
        let title = NSTextField(labelWithString: "小工具")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        let plusButton = NSButton(title: "+", target: self, action: #selector(addRepo))
        plusButton.isBordered = false
        plusButton.font = .systemFont(ofSize: 17, weight: .regular)
        plusButton.contentTintColor = .secondaryLabelColor
        plusButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(plusButton)

        let closeButton = NSButton(title: "×", target: self, action: #selector(hideWindow))
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 16, weight: .medium)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        countLabel.font = .systemFont(ofSize: 10)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(countLabel)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),

            closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),

            plusButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            plusButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),
            plusButton.widthAnchor.constraint(equalToConstant: 22),
            plusButton.heightAnchor.constraint(equalToConstant: 22),

            countLabel.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            countLabel.trailingAnchor.constraint(equalTo: plusButton.leadingAnchor, constant: -6)
        ])
    }

    private func buildSearch() {
        searchField.placeholderString = "搜索工具…"
        searchField.font = .systemFont(ofSize: 12)
        searchField.controlSize = .small
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 44),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])
    }

    private func buildScroll() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false

        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -40),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),

            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -8)
        ])
    }

    private func buildFooter() {
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dot)

        let hint = NSTextField(labelWithString: "绿点=已装，点击启动")
        hint.font = .systemFont(ofSize: 9.5)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)

        let auto = NSButton(checkboxWithTitle: "开机自启", target: self, action: #selector(toggleAutostart(_:)))
        auto.state = autostartEnabled() ? .on : .off
        auto.font = .systemFont(ofSize: 9.5)
        auto.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(auto)

        let quit = NSButton(title: "退出", target: self, action: #selector(quitApp))
        quit.isBordered = false
        quit.font = .systemFont(ofSize: 10)
        quit.contentTintColor = .secondaryLabelColor
        quit.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(quit)

        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -34),

            dot.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            dot.centerYAnchor.constraint(equalTo: divider.bottomAnchor, constant: 17),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),

            hint.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            hint.centerYAnchor.constraint(equalTo: dot.centerYAnchor),

            auto.trailingAnchor.constraint(equalTo: quit.leadingAnchor, constant: -8),
            auto.centerYAnchor.constraint(equalTo: dot.centerYAnchor),

            hint.trailingAnchor.constraint(lessThanOrEqualTo: auto.leadingAnchor, constant: -6),

            quit.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            quit.centerYAnchor.constraint(equalTo: dot.centerYAnchor)
        ])
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func hideWindow() {
        view.window?.orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        hideWindow()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        scrollToTop()
    }

    func scrollToTop() {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func controlTextDidChange(_ obj: Notification) {
        query = searchField.stringValue
        rebuild()
    }

    // MARK: 行点击 / 本地 agent

    private func handle(_ tool: Tool) {
        if isInstalled(tool) || tool.command != nil {
            launchTool(tool)
            return
        }
        if let repo = tool.repo {
            startInstall(target: repo)
            return
        }
        if let link = tool.url {
            if link.contains("github.com") {
                startInstall(target: link)
            } else if let url = URL(string: link) {
                // 纯网页工具（不是下载），仍然用浏览器打开
                NSWorkspace.shared.open(url)
            }
            return
        }
        // 没有仓库信息：让本地 agent 按名字搜索后直接装
        startInstall(target: tool.name)
    }

    @objc private func addRepo() {
        let alert = NSAlert()
        alert.messageText = "从 GitHub 收录工具"
        alert.informativeText = "输入 owner/repo、完整链接，或一个搜索词；本地 agent 会搜索、下载、自检、安装并收录。"
        alert.addButton(withTitle: "开始")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "例如：rxhanson/Rectangle 或 窗口管理"
        alert.accessoryView = field
        alert.window.level = .floating
        if alert.runModal() == .alertFirstButtonReturn {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { startInstall(target: text) }
        }
    }

    @objc private func toggleAutostart(_ sender: NSButton) {
        let enabled = sender.state == .on
        AgentRunner.run(["autostart", enabled ? "on" : "off", Bundle.main.bundlePath]) { _ in }
    }

    private func startInstall(target: String) {
        guard progressPanel == nil else { return }
        showProgress("本地 agent 正在搜索 / 下载 / 自检…")
        AgentRunner.run(["install", target]) { [weak self] output in
            guard let self = self else { return }
            self.progressPanel?.close()
            self.progressPanel = nil
            self.catalogTools = loadCatalogTools()
            self.rebuild()
            if let result = AgentResult.parse(output) {
                self.showResult(result)
            } else {
                self.showError("agent 没有返回结果", detail: output)
            }
        }
    }

    private func showProgress(_ text: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 104),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "本地安装 agent"
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        let content = NSView()
        let spinner = NSProgressIndicator(frame: NSRect(x: 18, y: 56, width: 20, height: 20))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        content.addSubview(spinner)

        let label = NSTextField(wrappingLabelWithString: text)
        label.frame = NSRect(x: 50, y: 46, width: 290, height: 44)
        label.font = .systemFont(ofSize: 12)
        content.addSubview(label)

        panel.contentView = content
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        progressPanel = panel
    }

    private func showResult(_ result: AgentResult) {
        let alert = NSAlert()
        if result.ok {
            alert.messageText = "✅ 已自检并收录：\(result.name ?? "")"
            var lines: [String] = []
            if let version = result.version, !version.isEmpty { lines.append("版本：\(version)") }
            if let codesign = result.codesignOK { lines.append("代码签名：\(codesign ? "通过" : "未通过")") }
            if let notarized = result.notarized { lines.append("公证：\(notarized ? "已公证" : "未公证")") }
            if let checksum = result.checksumVerified {
                lines.append("官方校验文件：\(checksum ? "匹配" : "不匹配")")
            } else {
                lines.append("官方校验文件：无（已记录 SHA-256）")
            }
            if let sha = result.sha256 { lines.append("SHA-256：\(sha.prefix(16))…") }
            if let path = result.path { lines.append("路径：\(path)") }
            alert.informativeText = lines.joined(separator: "\n")
            alert.addButton(withTitle: "好")
        } else {
            alert.messageText = "❌ \(result.error ?? result.message ?? "安装失败")"
            alert.informativeText = result.releaseURL.map { "agent 没找到可直接安装的 macOS 包。\n发布页（可点「复制链接」）：\n\($0)" } ?? ""
            alert.addButton(withTitle: "好")
            if result.releaseURL != nil { alert.addButton(withTitle: "复制链接") }
        }
        present(alert, result: result)
    }

    private func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = String(detail.suffix(600))
        alert.addButton(withTitle: "好")
        present(alert, result: nil)
    }

    private func present(_ alert: NSAlert, result: AgentResult?) {
        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertSecondButtonReturn, let link = result?.releaseURL {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                }
            }
        } else {
            alert.runModal()
        }
    }

    private func rebuild() {
        for subview in stack.arrangedSubviews {
            stack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var isFirstGroup = true

        for group in groups {
            let items = allTools.filter { tool in
                guard tool.group == group else { return false }
                if q.isEmpty { return true }
                return tool.name.localizedCaseInsensitiveContains(q)
                    || tool.subtitle.localizedCaseInsensitiveContains(q)
            }
            if items.isEmpty { continue }

            if !isFirstGroup {
                let spacer = NSView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                spacer.heightAnchor.constraint(equalToConstant: 10).isActive = true
                stack.addArrangedSubview(spacer)
            }

            let header = NSTextField(labelWithString: group.uppercased())
            header.font = .systemFont(ofSize: 9.5, weight: .semibold)
            header.textColor = .secondaryLabelColor
            stack.addArrangedSubview(header)
            stack.setCustomSpacing(4, after: header)

            for tool in items {
                let row = ToolRowView(tool: tool)
                row.onClick = { [weak self] in self?.handle(tool) }
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }

            isFirstGroup = false
        }

        let installed = allTools.filter { isInstalled($0) }.count
        countLabel.stringValue = "\(installed) / \(allTools.count) 已装"
    }
}

// MARK: - App 入口

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMainMenu()
        buildWindow()
        buildStatusItem()
        NSApp.activate(ignoringOtherApps: true)
    }

    func buildWindow() {
        let width: CGFloat = 320
        let height: CGFloat = 660

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "小工具侧边栏"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 300, height: 440)
        window.delegate = self
        window.contentViewController = SidebarViewController()
        window.setContentSize(NSSize(width: width, height: height))
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.initialFirstResponder = nil

        window.makeKeyAndOrderFront(nil)
        self.window = window
        positionWindow()
        let work = DispatchWorkItem { self.positionWindow() }
        DispatchQueue.main.async(execute: work)
        let scrollWork = DispatchWorkItem {
            if let controller = window.contentViewController as? SidebarViewController {
                controller.scrollToTop()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: scrollWork)
    }

    func positionWindow() {
        guard let window = window else { return }
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            window.center()
            return
        }
        let frame = screen.visibleFrame
        let size = window.frame.size
        var x = frame.maxX - size.width - 18
        var y = frame.midY - size.height / 2
        x = max(frame.minX + 8, min(x, frame.maxX - size.width - 8))
        y = max(frame.minY + 8, min(y, frame.maxY - size.height - 8))
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "小工具侧边栏")
            button.target = self
            button.action = #selector(toggleWindow)
        }
        statusItem = item
    }

    @objc func toggleWindow() {
        guard let window = window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "隐藏窗口", action: #selector(toggleWindow), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }
}

// MARK: - CLI 模式（供自动化 / 本地 agent 调用）

let cliArguments = CommandLine.arguments
if let index = cliArguments.firstIndex(of: "--agent"), index + 1 < cliArguments.count {
    let args = Array(cliArguments[(index + 1)...])
    guard let script = Bundle.main.path(forResource: "toolagent", ofType: "py", inDirectory: "agent") else {
        FileHandle.standardError.write("agent script not found\n".data(using: .utf8)!)
        exit(2)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [script] + args
    try? process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
