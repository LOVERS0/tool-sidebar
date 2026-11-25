import AppKit
import Carbon
import Sparkle
import UniformTypeIdentifiers

// MARK: - 数据模型

struct Tool {
    let id: String
    var name: String
    var subtitle: String
    let icon: String
    var group: String
    var path: String? = nil
    var url: String? = nil
    var repo: String? = nil
    var source: String = "builtin"
    var manual: Bool = false
    var version: String? = nil
    var bundleID: String? = nil
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
    let bundleID: String?
}

struct CatalogFile: Codable {
    var tools: [CatalogTool]
}

struct FeaturedItem: Codable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let group: String?
    let repo: String?
    let url: String?
}

struct FeaturedFile: Codable {
    let tools: [FeaturedItem]
}

struct Overrides: Codable {
    var names: [String: String] = [:]
    var orders: [String: [String]] = [:]
    var categories: [String: String] = [:]
    var customCategories: [String] = []
    var favorites: [String] = []

    init() {}
    enum CodingKeys: String, CodingKey { case names, orders, categories, customCategories, favorites }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        names = try values.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
        orders = try values.decodeIfPresent([String: [String]].self, forKey: .orders) ?? [:]
        categories = try values.decodeIfPresent([String: String].self, forKey: .categories) ?? [:]
        customCategories = try values.decodeIfPresent([String].self, forKey: .customCategories) ?? []
        favorites = try values.decodeIfPresent([String].self, forKey: .favorites) ?? []
    }
}

struct MigrationTool: Codable {
    let repo: String
    let name: String
    let group: String?
}

struct MigrationFile: Codable {
    let version: Int
    let tools: [MigrationTool]
    let overrides: Overrides?
    let autostart: Bool?
}

/// Restore only the repository list. Never install or overwrite a local app during import.
func restoreToolList(_ imported: [MigrationTool], keeping existing: [CatalogTool]) throws -> [CatalogTool] {
    var result = existing
    var repos = Set(existing.compactMap { $0.repo?.lowercased() })
    for item in imported {
        guard let parsed = AgentCLI.parseRepo(item.repo),
              item.repo == "\(parsed.owner)/\(parsed.repo)" else {
            throw AgentError.message("配置中包含无效的 GitHub 仓库：\(item.repo)")
        }
        guard repos.insert(item.repo.lowercased()).inserted else { continue }
        result.append(CatalogTool(id: "repo:\(item.repo)", name: item.name, subtitle: "已收录",
            icon: "shippingbox", group: item.group ?? "已收录", path: nil, repo: item.repo,
            version: nil, sha256: nil, installedAt: nil, bundleID: nil))
    }
    return result
}

func expandedPath(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}

func isInstalled(_ tool: Tool) -> Bool {
    InstalledApplications.url(for: tool) != nil
}

/// One scan per model refresh, shared by row state and launching.
enum InstalledApplications {
    private static var byName: [String: URL] = [:]
    private static var byBundleID: [String: URL] = [:]

    static func refresh(directories: [URL] = [URL(fileURLWithPath: NSHomeDirectory() + "/Applications"),
                                             URL(fileURLWithPath: "/Applications")]) {
        byName = [:]
        byBundleID = [:]
        for directory in directories {
            let apps = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for app in apps where app.pathExtension == "app" {
                let bundle = Bundle(url: app)
                var names = [app.deletingPathExtension().lastPathComponent]
                for key in ["CFBundleName", "CFBundleDisplayName"] {
                    if let name = bundle?.object(forInfoDictionaryKey: key) as? String { names.append(name) }
                }
                for name in names where byName[name.lowercased()] == nil { byName[name.lowercased()] = app }
                if let id = bundle?.bundleIdentifier, byBundleID[id] == nil { byBundleID[id] = app }
            }
        }
    }

    static func url(for tool: Tool) -> URL? {
        if let path = tool.path, FileManager.default.fileExists(atPath: expandedPath(path)) {
            return URL(fileURLWithPath: expandedPath(path))
        }
        if let id = tool.bundleID, !id.isEmpty {
            if let app = byBundleID[id] { return app }
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return app }
        }
        var names = [tool.name]
        if let path = tool.path { names.append(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) }
        if let repo = tool.repo { names.append(String(repo.split(separator: "/").last ?? "")) }
        for name in names {
            if let app = byName[name.lowercased()], FileManager.default.fileExists(atPath: app.path) { return app }
        }
        return nil
    }
}

let catalogPath: String = (("~/Library/Application Support/小工具侧边栏/catalog.json") as NSString).expandingTildeInPath
let overridesPath: String = (("~/Library/Application Support/小工具侧边栏/overrides.json") as NSString).expandingTildeInPath
let featuredCachePath: String = (("~/Library/Application Support/小工具侧边栏/featured-cache.json") as NSString).expandingTildeInPath
let featuredURL = URL(string: "https://api.github.com/repos/LOVERS0/tool-sidebar/contents/featured.json")!
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
            source: "catalog",
            version: item.version,
            bundleID: item.bundleID
        )
    }
}

func loadOverrides() -> Overrides {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: overridesPath)),
          let value = try? JSONDecoder().decode(Overrides.self, from: data) else {
        return Overrides()
    }
    return value
}

func saveOverrides(_ value: Overrides) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    let url = URL(fileURLWithPath: overridesPath)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
}

func loadFeaturedCache(preferBundled: Bool = false) -> [Tool] {
    var payload: Data?
    if !preferBundled, let cached = try? Data(contentsOf: URL(fileURLWithPath: featuredCachePath)) {
        payload = cached
    } else if let bundled = Bundle.main.url(forResource: "featured", withExtension: "json") {
        payload = try? Data(contentsOf: bundled)
    }
    guard let data = payload,
          let file = try? JSONDecoder().decode(FeaturedFile.self, from: data) else {
        return []
    }
    return file.tools.map { item in
        Tool(id: item.id, name: item.name, subtitle: item.subtitle, icon: item.icon,
             group: item.group ?? "精选", path: nil, url: item.url, repo: item.repo, source: "featured")
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
        Tool(id: "novelwriter", name: "novelWriter", subtitle: "小说工程 / 章节 / 情节线 · 需手动下载", icon: "list.bullet.rectangle", group: "写作", url: "https://github.com/saga-soft/novelWriter/releases", repo: "saga-soft/novelWriter", manual: true),

        // AI / 开发
        Tool(id: "ccswitch", name: "CC Switch", subtitle: "一键切换 AI 供应商", icon: "arrow.triangle.2.circlepath", group: "AI / 开发", path: "~/Applications/CC Switch.app", repo: "farion1231/cc-switch"),
        Tool(id: "dsh", name: "DeepSeek Harness", subtitle: "当前使用的 AI 工作台", icon: "terminal", group: "AI / 开发", path: "/Applications/DeepSeek Harness.app"),
        Tool(id: "dshdesktop", name: "DSH Desktop", subtitle: "桌面版", icon: "macwindow", group: "AI / 开发", path: "/Applications/DSH Desktop.app"),
        Tool(id: "githubdesktop", name: "GitHub Desktop", subtitle: "Git 图形客户端", icon: "arrow.triangle.branch", group: "AI / 开发", path: "/Applications/GitHub Desktop.app"),
        Tool(id: "openclaw", name: "OpenClaw", subtitle: "个人 AI 助理", icon: "sparkles", group: "AI / 开发", repo: "openclaw/openclaw"),

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
        Tool(id: "itsycal", name: "Itsycal", subtitle: "菜单栏日历", icon: "calendar", group: "系统小工具", url: "https://www.mowglii.com/itsycal/", manual: true),
        Tool(id: "alttab", name: "AltTab", subtitle: "窗口切换", icon: "rectangle.on.rectangle", group: "系统小工具", repo: "lwouis/alt-tab-macos"),
        Tool(id: "latest", name: "Latest", subtitle: "检查 App 更新", icon: "arrow.down.circle", group: "系统小工具", repo: "mangerlahn/Latest"),
    ]
}

// MARK: - 启动 / 本地 agent

func launchTool(_ tool: Tool) {
    if let app = InstalledApplications.url(for: tool) {
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error = error else { return }
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.showLaunchError(appName: tool.name, detail: error.localizedDescription)
            }
        }
        return
    }
    if let s = tool.url, let url = URL(string: s) {
        NSWorkspace.shared.open(url)
    }
}

enum AgentRunner {
    @discardableResult
    static func run(_ arguments: [String], completion: ((String) -> Void)? = nil) -> Process? {
        guard let executable = Bundle.main.executablePath else {
            completion?("")
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--agent"] + arguments
        let output = Pipe()
        process.standardOutput = output
        // Merge stderr so it is drained together with stdout.
        process.standardError = output
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
        if completion == nil {
            DispatchQueue.global().async { _ = output.fileHandleForReading.readDataToEndOfFile() }
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
    let installedSnapshot: Bool
    var onClick: (() -> Void)?
    var onInstall: (() -> Void)?
    var onUpdate: (() -> Void)?
    var onUninstall: (() -> Void)?
    var onReveal: (() -> Void)?
    var onRename: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onAssignCategory: ((String?) -> Void)?
    var onNewCategory: (() -> Void)?
    var onToggleFavorite: (() -> Void)?
    var isFavorite = false
    var categories: [String] = []
    var updateVersion: String?
    private let background = NSView()
    private var tracking: NSTrackingArea?
    private var isSelectedRow = false

    func setSelected(_ selected: Bool) {
        isSelectedRow = selected
        background.layer?.backgroundColor = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
            : NSColor.clear.cgColor
    }

    init(tool: Tool, updateVersion: String? = nil, isFavorite: Bool = false) {
        self.tool = tool
        self.installedSnapshot = isInstalled(tool)
        self.updateVersion = updateVersion
        self.isFavorite = isFavorite
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        let installed = installedSnapshot

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
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)

        let actionTitle: String
        if installed && updateVersion != nil { actionTitle = L10n.t("更新", "Update") }
        else if installed { actionTitle = L10n.t("打开", "Open") }
        else if tool.manual { actionTitle = L10n.t("下载", "Get") }
        else if tool.repo != nil { actionTitle = L10n.t("安装", "Install") }
        else if tool.url != nil { actionTitle = L10n.t("访问", "Visit") }
        else { actionTitle = L10n.t("未安装", "Missing") }
        let action = NSButton(title: actionTitle, target: self, action: #selector(primaryAction))
        action.isEnabled = installed || tool.repo != nil || tool.url != nil
        action.isBordered = false
        action.font = .systemFont(ofSize: 11, weight: .medium)
        action.contentTintColor = .controlAccentColor
        action.translatesAutoresizingMaskIntoConstraints = false
        action.setAccessibilityLabel("\(actionTitle) \(tool.name)")
        addSubview(action)
        toolTip = tool.name + "\n" + tool.subtitle
        setAccessibilityRole(.group)
        setAccessibilityLabel(tool.name)

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
            text.trailingAnchor.constraint(equalTo: action.leadingAnchor, constant: -8),

            action.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            action.centerYAnchor.constraint(equalTo: centerYAnchor),
            action.widthAnchor.constraint(equalToConstant: 46),
            action.heightAnchor.constraint(equalToConstant: 28),

            heightAnchor.constraint(equalToConstant: 46)
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
        guard !isSelectedRow else { return }
        background.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        guard !isSelectedRow else { return }
        background.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        add(isFavorite ? L10n.t("取消收藏", "Remove favorite") : L10n.t("收藏", "Add favorite"), #selector(toggleFavoriteAction))
        menu.addItem(.separator())
        if isInstalled(tool) {
            add(L10n.t("打开", "Open"), #selector(openAction))
            if tool.path != nil { add(L10n.t("在 Finder 中显示", "Show in Finder"), #selector(revealAction)) }
            if let version = updateVersion { add(L10n.t("更新到 v\(version)", "Update to v\(version)"), #selector(updateAction)) }
            if tool.repo != nil || tool.source == "catalog" { add(L10n.t("卸载（移到废纸篓）", "Uninstall (move to Trash)"), #selector(uninstallAction)) }
            add(L10n.t("重命名…", "Rename…"), #selector(renameAction))
            add("上移", #selector(moveUpAction))
            add("下移", #selector(moveDownAction))

            let categoryMenu = NSMenu()
            for name in categories {
                let item = NSMenuItem(title: name, action: #selector(assignCategoryAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = name
                categoryMenu.addItem(item)
            }
            categoryMenu.addItem(NSMenuItem.separator())
            let newItem = NSMenuItem(title: "新建分类…", action: #selector(newCategoryAction), keyEquivalent: "")
            newItem.target = self
            categoryMenu.addItem(newItem)
            let resetItem = NSMenuItem(title: "移回默认分类", action: #selector(resetCategoryAction), keyEquivalent: "")
            resetItem.target = self
            categoryMenu.addItem(resetItem)
            let categoryItem = NSMenuItem(title: "分类", action: nil, keyEquivalent: "")
            categoryItem.submenu = categoryMenu
            menu.addItem(categoryItem)
        } else if tool.manual {
            add(L10n.t("前往官方下载", "Open official download"), #selector(webAction))
        } else if tool.repo != nil {
            add(L10n.t("安装", "Install"), #selector(installAction))
        } else if tool.url != nil {
            add("在浏览器中打开", #selector(webAction))
        }
        return menu.items.isEmpty ? nil : menu
    }

    @objc private func openAction() { onClick?() }
    @objc private func toggleFavoriteAction() { onToggleFavorite?() }
    @objc private func primaryAction() {
        if updateVersion != nil && isInstalled(tool) { onUpdate?() }
        else { onClick?() }
    }
    @objc private func installAction() { onInstall?() }
    @objc private func updateAction() { onUpdate?() }
    @objc private func uninstallAction() { onUninstall?() }
    @objc private func revealAction() { onReveal?() }
    @objc private func renameAction() { onRename?() }
    @objc private func moveUpAction() { onMoveUp?() }
    @objc private func moveDownAction() { onMoveDown?() }
    @objc private func assignCategoryAction(_ sender: NSMenuItem) { onAssignCategory?(sender.representedObject as? String) }
    @objc private func newCategoryAction() { onNewCategory?() }
    @objc private func resetCategoryAction() { onAssignCategory?(nil) }
    @objc private func webAction() {
        if let link = tool.url, let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - 侧边栏控制器

final class SidebarViewController: NSViewController, NSSearchFieldDelegate {
    private let previewMode: Bool

    init(preview: Bool = false) {
        previewMode = preview
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        previewMode = false
        super.init(coder: coder)
    }

    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let stack = NSStackView()
    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let filterControl = NSSegmentedControl(labels: [L10n.t("全部", "All"), L10n.t("已安装", "Installed"), L10n.t("收藏", "Favorites")], trackingMode: .selectOne, target: nil, action: nil)
    private var rowGroups: [(header: NSView, spacer: NSView?, rows: [ToolRowView])] = []
    private var emptyStateView: NSView?
    private var query = ""
    private var catalogTools: [Tool] = []
    private var progressPanel: NSPanel?
    private var currentProcess: Process?
    private var currentInstallTarget: String?
    private var installCancelled = false
    private var installGeneration = UUID()
    private var updateVersions: [String: String] = [:]
    private var didCheckUpdates = false
    private var overrides = Overrides()
    private var featuredTools: [Tool] = []
    private var visibleRows: [ToolRowView] = []
    private var selectedIndex: Int?
    private var keyMonitor: Any?

    private var allTools: [Tool] = []

    private func mergedTools() -> [Tool] {
        var byRepo: [String: Tool] = [:]
        var byPath: [String: Tool] = [:]
        for item in catalogTools {
            if let repo = item.repo { byRepo[repo] = item }
            if let path = item.path { byPath[path] = item }
        }
        var merged: [Tool] = []
        var used = Set<String>()
        for base in Toolbox.builtin {
            if let repo = base.repo, let catalog = byRepo[repo] {
                var tool = base
                tool.path = catalog.path ?? base.path
                tool.bundleID = catalog.bundleID
                if let version = catalog.version, !version.isEmpty {
                    tool.subtitle = base.subtitle + " · v\(version)"
                }
                tool.source = "catalog"
                merged.append(tool)
                used.insert(catalog.id)
            } else if let path = base.path, let catalog = byPath[path] {
                var tool = base
                if let version = catalog.version, !version.isEmpty {
                    tool.subtitle = base.subtitle + " · v\(version)"
                }
                tool.source = "catalog"
                merged.append(tool)
                used.insert(catalog.id)
            } else {
                merged.append(base)
            }
        }
        for item in featuredTools {
            if let repo = item.repo, let catalog = byRepo[repo] {
                var tool = item
                tool.path = catalog.path ?? item.path
                tool.bundleID = catalog.bundleID
                if let version = catalog.version, !version.isEmpty {
                    tool.subtitle = item.subtitle + " · v\(version)"
                }
                tool.source = "catalog"
                merged.append(tool)
                used.insert(catalog.id)
            } else {
                merged.append(item)
            }
        }
        for item in catalogTools where !used.contains(item.id) {
            var tool = item
            if let version = item.version, !version.isEmpty {
                tool.subtitle = "已收录 · v\(version)"
            } else {
                tool.subtitle = "已收录"
            }
            merged.append(tool)
        }
        return merged.map { item in
            var tool = item
            // Resolve before applying a custom/localized display name.
            if let installed = InstalledApplications.url(for: tool) { tool.path = installed.path }
            if let custom = overrides.names[item.id], !custom.isEmpty {
                tool.name = custom
            } else if L10n.isEnglish {
                tool.name = L10n.name(tool.name)
            }
            if let category = overrides.categories[item.id], !category.isEmpty {
                tool.group = category
            }
            tool.subtitle = L10n.subtitle(tool.subtitle)
            return tool
        }
    }

    private var groups: [String] {
        var result = Toolbox.builtinGroups
        for category in overrides.customCategories where !result.contains(category) {
            result.append(category)
        }
        if !featuredTools.isEmpty {
            result.append("精选")
        }
        if allTools.contains(where: { $0.group == "已收录" }) {
            result.append("已收录")
        }
        return result
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
        catalogTools = previewMode ? [] : loadCatalogTools()
        overrides = previewMode ? Overrides() : loadOverrides()
        featuredTools = loadFeaturedCache(preferBundled: previewMode)
        buildHeader()
        buildSearch()
        buildScroll()
        buildFooter()
        installKeyMonitor()
        rebuild()
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func buildHeader() {
        let title = NSTextField(labelWithString: L10n.t("小工具", "Tools"))
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        let plusButton = NSButton(title: "+", target: self, action: #selector(addRepo))
        plusButton.isBordered = false
        plusButton.font = .systemFont(ofSize: 17, weight: .regular)
        plusButton.contentTintColor = .secondaryLabelColor
        plusButton.translatesAutoresizingMaskIntoConstraints = false
        plusButton.toolTip = L10n.t("添加 GitHub 工具", "Add a GitHub tool")
        plusButton.setAccessibilityLabel(plusButton.toolTip)
        view.addSubview(plusButton)

        let menuButton = NSButton(title: "⋯", target: self, action: #selector(showMoreMenu(_:)))
        menuButton.isBordered = false
        menuButton.font = .systemFont(ofSize: 15, weight: .medium)
        menuButton.contentTintColor = .secondaryLabelColor
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.toolTip = L10n.t("设置与更多操作", "Settings and more")
        menuButton.setAccessibilityLabel(menuButton.toolTip)
        view.addSubview(menuButton)

        let closeButton = NSButton(title: "×", target: self, action: #selector(hideWindow))
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 16, weight: .medium)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.toolTip = L10n.t("收起侧边栏", "Hide sidebar")
        closeButton.setAccessibilityLabel(closeButton.toolTip)
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

            menuButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            menuButton.trailingAnchor.constraint(equalTo: plusButton.leadingAnchor, constant: -2),
            menuButton.widthAnchor.constraint(equalToConstant: 22),
            menuButton.heightAnchor.constraint(equalToConstant: 22),

            countLabel.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            countLabel.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -6)
        ])
    }

    private func buildSearch() {
        searchField.placeholderString = L10n.t("搜索工具…", "Search tools…")
        searchField.font = .systemFont(ofSize: 12)
        searchField.controlSize = .regular
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 44),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])
        filterControl.selectedSegment = 0
        filterControl.target = self
        filterControl.action = #selector(filterChanged)
        filterControl.controlSize = .small
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        filterControl.setAccessibilityLabel(L10n.t("筛选工具", "Filter tools"))
        view.addSubview(filterControl)
        NSLayoutConstraint.activate([
            filterControl.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            filterControl.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            filterControl.trailingAnchor.constraint(equalTo: searchField.trailingAnchor)
        ])
    }

    @objc private func filterChanged() {
        applyFilter()
        scrollToTop()
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
            scrollView.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 6),
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
        let hint = NSTextField(labelWithString: L10n.t("↑↓ 选择 · ⏎ 打开 · esc 收起", "↑↓ select · ⏎ open · esc hide"))
        hint.font = .systemFont(ofSize: 10.5)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -34),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14),
            hint.centerYAnchor.constraint(equalTo: divider.bottomAnchor, constant: 17)
        ])
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func hideWindow() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.hideSidebar()
        } else {
            view.window?.orderOut(nil)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        hideWindow()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        rebuild()
        scrollToTop()
        guard !previewMode else { return }
        checkForUpdates()
        refreshFeatured()
    }

    func scrollToTop() {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func fuzzyContains(_ text: String, _ query: String) -> Bool {
        let haystack = text.lowercased()
        let needle = query.lowercased()
        if haystack.contains(needle) { return true }
        var index = haystack.startIndex
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return false }
            index = haystack.index(after: found)
        }
        return true
    }

    private func lastJSON(_ text: String) -> [String: Any]? {
        for line in text.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"),
                  let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dict = object as? [String: Any] else { continue }
            return dict
        }
        return nil
    }

    private func checkForUpdates() {
        guard !didCheckUpdates, !catalogTools.isEmpty else { return }
        didCheckUpdates = true
        AgentRunner.run(["check-updates"]) { [weak self] output in
            guard let self = self, let data = self.lastJSON(output),
                  let list = data["updates"] as? [[String: Any]] else { return }
            for item in list {
                if let repo = item["repo"] as? String, let latest = item["latest"] as? String {
                    self.updateVersions[repo] = latest
                }
            }
            if !self.updateVersions.isEmpty { self.rebuild() }
        }
    }

    private func refreshFeatured() {
        var request = URLRequest(url: featuredURL)
        request.setValue("application/vnd.github.raw", forHTTPHeaderField: "Accept")
        request.setValue("ToolSidebar/1.2", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let file = try? JSONDecoder().decode(FeaturedFile.self, from: data) else { return }
            try? data.write(to: URL(fileURLWithPath: featuredCachePath))
            let tools = file.tools.map { item in
                Tool(id: item.id, name: item.name, subtitle: item.subtitle, icon: item.icon,
                     group: item.group ?? "精选", path: nil, url: item.url, repo: item.repo, source: "featured")
            }
            let work = DispatchWorkItem {
                self.featuredTools = tools
                self.rebuild()
            }
            DispatchQueue.main.async(execute: work)
        }.resume()
    }

    private func orderedIds(for group: String) -> [String] {
        let current = allTools.filter { $0.group == group }.map { $0.id }
        guard let stored = overrides.orders[group] else { return current }
        var result = stored.filter { current.contains($0) }
        result.append(contentsOf: current.filter { !result.contains($0) })
        return result
    }

    private func sorted(_ items: [Tool], group: String) -> [Tool] {
        let order = orderedIds(for: group)
        return items.sorted {
            (order.firstIndex(of: $0.id) ?? 9999) < (order.firstIndex(of: $1.id) ?? 9999)
        }
    }

    private func rename(_ tool: Tool) {
        let alert = NSAlert()
        alert.messageText = "重命名"
        alert.informativeText = "给「\(tool.name)」起一个你习惯的名字（留空恢复默认）。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: L10n.t("取消", "Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = tool.name
        alert.accessoryView = field
        alert.window.level = .floating
        if alert.runModal() == .alertFirstButtonReturn {
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                overrides.names.removeValue(forKey: tool.id)
            } else {
                overrides.names[tool.id] = value
            }
            saveOverrides(overrides)
            rebuild()
        }
    }

    private func move(_ tool: Tool, up: Bool) {
        let group = tool.group
        var ids = orderedIds(for: group)
        guard let index = ids.firstIndex(of: tool.id) else { return }
        let target = up ? index - 1 : index + 1
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        overrides.orders[group] = ids
        saveOverrides(overrides)
        rebuild()
    }

    private func uninstall(_ tool: Tool) {
        let alert = NSAlert()
        alert.messageText = "卸载 \(tool.name)？"
        alert.informativeText = "App 会移到废纸篓，并从已收录目录移除。"
        alert.addButton(withTitle: "卸载")
        alert.addButton(withTitle: "取消")
        if alert.runModal() != .alertFirstButtonReturn { return }
        let target = tool.repo ?? tool.path ?? tool.name
        AgentRunner.run(["remove", target]) { [weak self] _ in
            guard let self = self else { return }
            self.catalogTools = loadCatalogTools()
            self.updateVersions.removeAll()
            self.rebuild()
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if let editor = searchField.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        query = searchField.stringValue
        applyFilter()
        scrollToTop()
    }

    // MARK: 键盘操作

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  let window = self.view.window,
                  window.isKeyWindow else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // 输入法正在拼写时，把按键让给输入法（否则拼音选词的回车会被当成「打开」）
        if let editor = view.window?.firstResponder as? NSTextView, editor.hasMarkedText() {
            return event
        }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // ⌘F 聚焦搜索
        if mods == .command, (event.charactersIgnoringModifiers ?? "").lowercased() == "f" {
            view.window?.makeFirstResponder(searchField)
            searchField.selectText(nil)
            return nil
        }
        guard mods.isEmpty else { return event }
        switch event.keyCode {
        case 125: // ↓
            moveSelection(1)
            return nil
        case 126: // ↑
            moveSelection(-1)
            return nil
        case 36, 76: // Return / 小键盘 Enter
            activateSelection()
            return nil
        case 53: // Esc：先清搜索，再收起
            dismiss()
            return nil
        default:
            return event
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !visibleRows.isEmpty else { return }
        let start = selectedIndex ?? (delta > 0 ? -1 : visibleRows.count)
        let index = max(0, min(visibleRows.count - 1, start + delta))
        selectRow(at: index)
    }

    private func selectRow(at index: Int) {
        guard visibleRows.indices.contains(index) else { return }
        for (i, row) in visibleRows.enumerated() {
            row.setSelected(i == index)
        }
        selectedIndex = index
        let row = visibleRows[index]
        row.scrollToVisible(row.bounds.insetBy(dx: 0, dy: -8))
    }

    private func activateSelection() {
        guard !visibleRows.isEmpty else { return }
        let index = selectedIndex ?? 0
        guard visibleRows.indices.contains(index) else { return }
        selectRow(at: index)
        handle(visibleRows[index].tool)
    }

    private func dismiss() {
        if !searchField.stringValue.isEmpty {
            searchField.stringValue = ""
            query = ""
            applyFilter()
            return
        }
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.hideSidebar()
        } else {
            view.window?.orderOut(nil)
        }
    }

    // MARK: 行点击 / 本地 agent

    private func handle(_ tool: Tool) {
        if let index = visibleRows.firstIndex(where: { $0.tool.id == tool.id }) {
            selectRow(at: index)
        }
        if isInstalled(tool) {
            launchTool(tool)
            return
        }
        if tool.manual, let link = tool.url, let url = URL(string: link) {
            NSWorkspace.shared.open(url)
            return
        }
        if let repo = tool.repo {
            startInstall(target: repo)
            return
        }
        if let link = tool.url {
            if let url = URL(string: link) { NSWorkspace.shared.open(url) }
            return
        }
        showError(L10n.t("尚未安装该应用", "App not installed"),
                  detail: L10n.t("请先从该应用的官方渠道安装。", "Install this app from its official source first."))
    }

    @objc private func addRepo() {
        let alert = NSAlert()
        alert.messageText = "从 GitHub 收录工具"
        alert.informativeText = "输入 owner/repo、完整链接，或一个搜索词；安装助手会搜索、下载、自检、安装并收录。"
        alert.addButton(withTitle: L10n.t("开始", "Start"))
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

    @objc private func showMoreMenu(_ sender: NSButton) {
        makeMoreMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    func makeMoreMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        add(L10n.t("检查更新…", "Check for updates…"), #selector(checkSparkleUpdates))
        let login = NSMenuItem(title: L10n.t("开机自启", "Launch at login"), action: #selector(toggleAutostartMenu), keyEquivalent: "")
        login.target = self
        login.state = autostartEnabled() ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        add(L10n.t("导出配置…", "Export settings…"), #selector(exportConfig))
        add(L10n.t("导入配置…", "Import settings…"), #selector(importConfig))
        add(L10n.t("GitHub 仓库 / 反馈…", "GitHub repo / feedback…"), #selector(openGitHubRepo))
        menu.addItem(.separator())
        add(L10n.t("退出", "Quit"), #selector(quitApp))
        return menu
    }

    @objc private func openGitHubRepo() {
        if let url = URL(string: "https://github.com/LOVERS0/tool-sidebar") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func checkSparkleUpdates() {
        (NSApp.delegate as? AppDelegate)?.checkForUpdatesSparkle()
    }

    @objc private func exportConfig() {
        let panel = NSSavePanel()
        panel.title = "导出配置"
        panel.nameFieldStringValue = "tool-sidebar-migration.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var seen = Set<String>()
        var tools: [MigrationTool] = []
        for tool in allTools where isInstalled(tool) || tool.source == "catalog" || overrides.favorites.contains(tool.id) {
            guard let repo = tool.repo, !seen.contains(repo) else { continue }
            seen.insert(repo)
            tools.append(MigrationTool(repo: repo, name: tool.name, group: tool.group))
        }
        let file = MigrationFile(version: 1, tools: tools, overrides: overrides, autostart: autostartEnabled())
        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: url, options: .atomic)
            showError("已导出", detail: "\(tools.count) 个工具 + 重命名/分类/自启设置\n\(url.path)")
        } catch {
            showError("导出失败", detail: error.localizedDescription)
        }
    }

    @objc private func importConfig() {
        let panel = NSOpenPanel()
        panel.title = "导入配置"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(MigrationFile.self, from: data) else {
            showError("导入失败", detail: "文件格式不对")
            return
        }
        let alert = NSAlert()
        alert.messageText = "导入 \(file.tools.count) 个工具？"
        alert.informativeText = "恢复收藏、名称、分类、排序、工具清单及开机自启设置。缺少的应用需要手动选择安装，不会批量下载安装。"
        alert.addButton(withTitle: "导入")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let catalogURL = URL(fileURLWithPath: catalogPath)
            let existing: [CatalogTool]
            if FileManager.default.fileExists(atPath: catalogPath) {
                existing = try JSONDecoder().decode(CatalogFile.self, from: Data(contentsOf: catalogURL)).tools
            } else { existing = [] }
            let restored = try restoreToolList(file.tools, keeping: existing)
            let encoded = try JSONEncoder().encode(CatalogFile(tools: restored))
            try FileManager.default.createDirectory(at: catalogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: catalogURL, options: .atomic)
            if let imported = file.overrides {
                overrides = imported
                saveOverrides(overrides)
            }
            if let autostart = file.autostart {
                AgentRunner.run(["autostart", autostart ? "on" : "off", Bundle.main.bundlePath]) { _ in }
            }
            catalogTools = loadCatalogTools()
            rebuild()
        } catch {
            showError(L10n.t("导入失败", "Import failed"), detail: error.localizedDescription)
        }
    }

    private func currentCategoryNames() -> [String] {
        var list = Toolbox.builtinGroups
        for category in overrides.customCategories where !list.contains(category) {
            list.append(category)
        }
        return list
    }

    private func assignCategory(_ tool: Tool, to category: String?) {
        if let category = category, !category.isEmpty {
            if !currentCategoryNames().contains(category) {
                overrides.customCategories.append(category)
            }
            overrides.categories[tool.id] = category
        } else {
            overrides.categories.removeValue(forKey: tool.id)
        }
        saveOverrides(overrides)
        rebuild()
    }

    private func newCategory(for tool: Tool) {
        let alert = NSAlert()
        alert.messageText = "新建分类"
        alert.informativeText = "给「\(tool.name)」新建一个分类。"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "分类名称"
        alert.accessoryView = field
        alert.window.level = .floating
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !currentCategoryNames().contains(name) {
            overrides.customCategories.append(name)
        }
        assignCategory(tool, to: name)
    }

    @objc private func toggleAutostartMenu() {
        AgentRunner.run(["autostart", autostartEnabled() ? "off" : "on", Bundle.main.bundlePath]) { [weak self] output in
            if let data = self?.lastJSON(output), (data["ok"] as? Bool) != true {
                self?.showError(L10n.t("设置失败", "Could not update setting"), detail: output)
            }
        }
    }

    private func startInstall(target: String, force: Bool = false) {
        guard progressPanel == nil else { return }
        let generation = UUID()
        installGeneration = generation
        currentInstallTarget = target
        installCancelled = false
        showProgress(L10n.t("正在搜索、下载并自检…", "Searching, downloading and verifying…"))
        var arguments = ["install", target]
        if force { arguments.append("--force") }
        currentProcess = AgentRunner.run(arguments) { [weak self] output in
            guard let self = self, self.installGeneration == generation else { return }
            self.currentProcess = nil
            self.progressPanel?.close()
            self.progressPanel = nil
            self.catalogTools = loadCatalogTools()
            self.rebuild()
            if self.installCancelled {
                self.installCancelled = false
                return
            }
            if let result = AgentResult.parse(output) {
                self.showResult(result)
            } else {
                self.showError(L10n.t("安装器没有返回结果", "The installer returned no result"), detail: output)
            }
        }
    }

    @objc private func cancelInstall() {
        installGeneration = UUID()
        installCancelled = true
        currentProcess?.terminate()
        currentProcess = nil
        progressPanel?.close()
        progressPanel = nil
    }

    private func showProgress(_ text: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 112),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.t("正在安装", "Installing")
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        let content = NSView()
        let spinner = NSProgressIndicator(frame: NSRect(x: 18, y: 56, width: 20, height: 20))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        content.addSubview(spinner)

        let label = NSTextField(wrappingLabelWithString: text)
        label.frame = NSRect(x: 50, y: 54, width: 290, height: 44)
        label.font = .systemFont(ofSize: 12)
        content.addSubview(label)

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelInstall))
        cancel.frame = NSRect(x: 280, y: 8, width: 64, height: 24)
        cancel.bezelStyle = .rounded
        cancel.font = .systemFont(ofSize: 11)
        content.addSubview(cancel)

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
            alert.informativeText = result.releaseURL.map { L10n.t("安装器没找到可直接安装的 macOS 包。\n可以打开发布页手动下载：\n\($0)", "The installer couldn't find a directly installable macOS package.\nYou can open the release page to download manually:\n\($0)") } ?? ""
            alert.addButton(withTitle: "好")
            if currentInstallTarget != nil { alert.addButton(withTitle: "重试") }
            if result.releaseURL != nil { alert.addButton(withTitle: "打开发布页") }
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
        guard let window = view.window else {
            alert.runModal()
            return
        }
        let retryTarget = currentInstallTarget
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            if response == .alertSecondButtonReturn, let target = retryTarget {
                self.startInstall(target: target)
            } else if response == .alertThirdButtonReturn, let link = result?.releaseURL, let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func rebuild() {
        let previousID = selectedIndex.flatMap { visibleRows.indices.contains($0) ? visibleRows[$0].tool.id : nil }
        InstalledApplications.refresh()
        allTools = mergedTools()
        for subview in stack.arrangedSubviews {
            stack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        rowGroups = []
        emptyStateView = nil
        visibleRows = []
        selectedIndex = nil
        let categories = currentCategoryNames()
        let favorites = Set(overrides.favorites)
        var first = true
        for group in groups {
            let items = sorted(allTools.filter { $0.group == group }, group: group).sorted {
                favorites.contains($0.id) && !favorites.contains($1.id)
            }
            guard !items.isEmpty else { continue }
            var spacer: NSView?
            if !first {
                let gap = NSView()
                gap.translatesAutoresizingMaskIntoConstraints = false
                gap.heightAnchor.constraint(equalToConstant: 10).isActive = true
                stack.addArrangedSubview(gap)
                spacer = gap
            }
            let header = NSTextField(labelWithString: L10n.group(group).uppercased())
            header.font = .systemFont(ofSize: 10, weight: .semibold)
            header.textColor = .secondaryLabelColor
            stack.addArrangedSubview(header)
            stack.setCustomSpacing(4, after: header)
            var rows: [ToolRowView] = []
            for tool in items {
                let latest = tool.repo.flatMap { updateVersions[$0] }
                let row = ToolRowView(tool: tool, updateVersion: latest, isFavorite: favorites.contains(tool.id))
                row.onClick = { [weak self] in self?.handle(tool) }
                row.onInstall = { [weak self] in self?.startInstall(target: tool.repo ?? tool.name) }
                if let repo = tool.repo { row.onUpdate = { [weak self] in self?.startInstall(target: repo, force: true) } }
                row.onUninstall = { [weak self] in self?.uninstall(tool) }
                row.onRename = { [weak self] in self?.rename(tool) }
                row.onMoveUp = { [weak self] in self?.move(tool, up: true) }
                row.onMoveDown = { [weak self] in self?.move(tool, up: false) }
                row.categories = categories
                row.onAssignCategory = { [weak self] category in self?.assignCategory(tool, to: category) }
                row.onNewCategory = { [weak self] in self?.newCategory(for: tool) }
                row.onToggleFavorite = { [weak self] in self?.toggleFavorite(tool) }
                row.onReveal = {
                    if let path = tool.path { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expandedPath(path))]) }
                }
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                rows.append(row)
            }
            rowGroups.append((header, spacer, rows))
            first = false
        }
        let installed = allTools.filter { isInstalled($0) }.count
        countLabel.stringValue = L10n.t("\(installed) / \(allTools.count) 已装", "\(installed) / \(allTools.count) installed")
        applyFilter(preferredSelection: previousID)
    }

    private func toggleFavorite(_ tool: Tool) {
        if overrides.favorites.contains(tool.id) { overrides.favorites.removeAll { $0 == tool.id } }
        else { overrides.favorites.append(tool.id) }
        saveOverrides(overrides)
        rebuild()
    }

    /// Search reuses existing rows; no application scans or view allocation per keystroke.
    private func applyFilter(preferredSelection: String? = nil) {
        let previousID = preferredSelection ?? selectedIndex.flatMap { visibleRows.indices.contains($0) ? visibleRows[$0].tool.id : nil }
        if let empty = emptyStateView {
            stack.removeArrangedSubview(empty)
            empty.removeFromSuperview()
            emptyStateView = nil
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let favorites = Set(overrides.favorites)
        visibleRows = []
        var hasGroup = false
        for group in rowGroups {
            var matches: [ToolRowView] = []
            for row in group.rows {
                let tool = row.tool
                let textMatches = q.isEmpty || fuzzyContains(tool.name, q) || fuzzyContains(tool.subtitle, q)
                let scopeMatches = filterControl.selectedSegment == 1 ? row.installedSnapshot
                    : filterControl.selectedSegment == 2 ? favorites.contains(tool.id) : true
                row.isHidden = !(textMatches && scopeMatches)
                if !row.isHidden { matches.append(row) }
            }
            group.header.isHidden = matches.isEmpty
            group.spacer?.isHidden = matches.isEmpty || !hasGroup
            if !matches.isEmpty { hasGroup = true }
            visibleRows.append(contentsOf: matches)
        }
        if visibleRows.isEmpty { addEmptyState(query: q) }
        for group in rowGroups { for row in group.rows { row.setSelected(false) } }
        selectedIndex = nil
        if let previousID = previousID, let index = visibleRows.firstIndex(where: { $0.tool.id == previousID }) {
            selectRowSilently(at: index)
        }
    }

    private func addEmptyState(query: String) {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: query.isEmpty ? L10n.t("此筛选下还没有工具", "No tools in this filter") : L10n.t("没有匹配「\(query)」的工具", "No tools match “\(query)”"))
        title.font = .systemFont(ofSize: 12)
        title.textColor = .secondaryLabelColor
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: L10n.t("试试更短的关键词，或用 + 从 GitHub 收录", "Try a shorter keyword, or use + to add from GitHub"))
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false

        wrapper.addSubview(title)
        wrapper.addSubview(hint)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: 96),
            title.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 28),
            title.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -12),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 12),
            hint.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -12)
        ])
        emptyStateView = wrapper
        stack.addArrangedSubview(wrapper)
        wrapper.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func selectRowSilently(at index: Int) {
        guard visibleRows.indices.contains(index) else { return }
        for (i, row) in visibleRows.enumerated() { row.setSelected(i == index) }
        selectedIndex = index
    }
}

// MARK: - 悬浮球

final class FloatingBallView: NSView {
    var onClick: (() -> Void)?
    var onMoved: ((NSPoint) -> Void)?
    private var moved = false
    private var hover = false
    private var tracking: NSTrackingArea?

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        NSColor(calibratedWhite: hover ? 0.18 : 0.10, alpha: 0.94).setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        circle.lineWidth = 1
        circle.stroke()
        if let image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "小工具")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white])) {
            let size = image.size
            image.draw(in: NSRect(x: (bounds.width - size.width) / 2,
                                  y: (bounds.height - size.height) / 2,
                                  width: size.width, height: size.height))
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = tracking { removeTrackingArea(old) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) { moved = false }

    override func mouseDragged(with event: NSEvent) {
        moved = true
        guard let window = window else { return }
        window.setFrameOrigin(NSPoint(x: window.frame.origin.x + event.deltaX,
                                      y: window.frame.origin.y + event.deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        if moved {
            if let window = window { onMoved?(window.frame.origin) }
        } else {
            onClick?()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - App 入口

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem?
    var ballWindow: NSPanel?
    var updaterController: SPUStandardUpdaterController!
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private let silentMode = CommandLine.arguments.contains("--silent")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(silentMode ? .accessory : .regular)
        if CommandLine.arguments.contains("--sparkle-check") {
            let work = DispatchWorkItem { [weak self] in self?.checkForUpdatesSparkle() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        }
        buildMainMenu()
        if !silentMode {
            buildWindow()
        }
        buildStatusItem()
        registerHotKey()
        startSparkleIfNeeded()
        if silentMode {
            showBall()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func showLaunchError(appName: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = L10n.t("无法打开 \(appName)", "Could not open \(appName)")
        alert.informativeText = detail
        alert.addButton(withTitle: L10n.t("好", "OK"))
        alert.runModal()
    }

    func registerHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x54534252), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(cmdKey | optionKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData = userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            let work = DispatchWorkItem { delegate.toggleWindow() }
            DispatchQueue.main.async(execute: work)
            return noErr
        }, 1, &eventType, pointer, &hotKeyHandler)
    }

    func buildWindow() {
        let width: CGFloat = 360
        let height: CGFloat = 660

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("小工具侧边栏", "ToolSidebar")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 340, height: 440)
        window.isRestorable = false
        window.delegate = self
        window.contentViewController = SidebarViewController()
        window.setContentSize(NSSize(width: width, height: height))
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.initialFirstResponder = nil

        self.window = window
        positionWindow()
        window.makeKeyAndOrderFront(nil)
        let sizeWork = DispatchWorkItem {
            window.setContentSize(NSSize(width: width, height: height))
            self.positionWindow()
        }
        DispatchQueue.main.async(execute: sizeWork)
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

    private var sparkleStarted = false

    func startSparkleIfNeeded() {
        guard !sparkleStarted else { return }
        sparkleStarted = true
        if updaterController == nil {
            updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        }
        updaterController.startUpdater()
    }

    @objc func checkForUpdatesSparkle() {
        startSparkleIfNeeded()
        updaterController.checkForUpdates(nil)
    }

    @objc func toggleWindow() {
        if let window = window, window.isVisible {
            hideSidebar()
        } else {
            showSidebar()
        }
    }

    func showSidebar() {
        hideBall()
        if window == nil {
            buildWindow()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideSidebar() {
        window?.orderOut(nil)
        showBall()
        let work = DispatchWorkItem { [weak self] in self?.startSparkleIfNeeded() }
        DispatchQueue.main.async(execute: work)
    }

    func showBall() {
        guard ballWindow == nil else {
            ballWindow?.orderFront(nil)
            return
        }
        let size: CGFloat = 58
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        let ball = FloatingBallView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        ball.onClick = { [weak self] in self?.showSidebar() }
        ball.onMoved = { origin in
            UserDefaults.standard.set(NSStringFromPoint(origin), forKey: "ballOrigin")
        }
        panel.contentView = ball
        if let saved = UserDefaults.standard.string(forKey: "ballOrigin") {
            panel.setFrameOrigin(NSPointFromString(saved))
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - size - 18, y: frame.midY - size / 2))
        } else {
            panel.center()
        }
        panel.orderFront(nil)
        ballWindow = panel
    }

    func hideBall() {
        ballWindow?.orderOut(nil)
        ballWindow = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSidebar()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideSidebar()
        return false
    }

    func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let updateItem = NSMenuItem(title: L10n.t("检查更新…", "Check for updates…"), action: #selector(checkForUpdatesSparkle), keyEquivalent: "")
        updateItem.target = self
        appMenu.addItem(updateItem)
        appMenu.addItem(withTitle: L10n.t("隐藏窗口", "Hide Window"), action: #selector(toggleWindow), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L10n.t("退出", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }
}
