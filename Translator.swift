import Foundation
#if canImport(Translation) && compiler(>=6.2)
import Translation
#endif

// MARK: - 内置中英翻译（系统翻译可用时优先，否则用内置词库）

enum Translator {
    static let phrases: [(String, String)] = [
        ("clipboard history", "剪贴板历史"),
        ("clipboard manager", "剪贴板管理器"),
        ("clipboard", "剪贴板"),
        ("window manager", "窗口管理器"),
        ("window management", "窗口管理"),
        ("window", "窗口"),
        ("menu bar", "菜单栏"),
        ("system monitor", "系统监控"),
        ("file transfer", "文件传输"),
        ("duplicate finder", "重复文件查找"),
        ("screenshot", "截图"),
        ("calendar", "日历"),
        ("archiver", "压缩工具"),
        ("text editor", "文本编辑器"),
        ("markdown editor", "Markdown 编辑器"),
        ("markdown", "Markdown"),
        ("writing", "写作"),
        ("notes", "笔记"),
        ("note taking", "笔记"),
        ("knowledge base", "知识库"),
        ("local-first", "本地优先"),
        ("open source", "开源"),
        ("free", "免费"),
        ("privacy", "隐私"),
        ("search", "搜索"),
        ("quick", "快速"),
        ("lightweight", "轻量"),
        ("powerful", "强大"),
        ("simple", "简洁"),
        ("tool", "工具"),
        ("utility", "小工具"),
        ("application", "应用"),
        ("app", "应用"),
        ("support", "支持"),
        ("settings", "设置"),
        ("preferences", "偏好设置"),
        ("install", "安装"),
        ("update", "更新"),
        ("download", "下载"),
        ("version", "版本"),
        ("manager", "管理器"),
        ("monitor", "监控"),
        ("history", "历史"),
        ("finder", "访达"),
        ("archive", "压缩包"),
        ("compression", "压缩"),
        ("video editor", "视频编辑器"),
        ("image", "图片"),
        ("audio", "音频"),
        ("voice", "语音"),
        ("design", "设计"),
        ("code editor", "代码编辑器"),
        ("developer", "开发者"),
        ("terminal", "终端"),
        ("agent", "智能体"),
        ("assistant", "助手"),
        ("workflow", "工作流"),
        ("automation", "自动化"),
        ("browser", "浏览器"),
        ("client", "客户端"),
        ("server", "服务器"),
        ("api client", "API 客户端"),
        ("database", "数据库"),
        ("music", "音乐"),
        ("player", "播放器"),
        ("reader", "阅读器"),
        ("book", "书籍"),
        ("rss", "RSS"),
        ("email", "邮件"),
        ("password", "密码"),
        ("security", "安全"),
        ("network", "网络"),
        ("proxy", "代理"),
        ("backup", "备份"),
        ("sync", "同步"),
        ("cleaner", "清理工具"),
        ("cleanup", "清理"),
        ("uninstaller", "卸载工具"),
        ("menu", "菜单"),
        ("bar", "栏"),
        ("status", "状态"),
        ("quick look", "快速查看"),
        ("preview", "预览"),
        ("snippet", "片段"),
        ("text expander", "文本扩展"),
        ("typing", "输入"),
        ("keyboard", "键盘"),
        ("mouse", "鼠标"),
        ("trackpad", "触控板"),
        ("display", "显示器"),
        ("brightness", "亮度"),
        ("volume", "音量"),
        ("battery", "电池"),
        ("cpu", "CPU"),
        ("memory", "内存"),
        ("disk", "磁盘"),
        ("usage", "占用"),
        ("clean", "清理"),
        ("duplicate", "重复"),
        ("similar images", "相似图片"),
        ("large files", "大文件"),
        ("file manager", "文件管理器"),
        ("launcher", "启动器"),
        ("hotkey", "快捷键"),
        ("shortcut", "快捷键"),
        ("plugin", "插件"),
        ("extension", "扩展"),
        ("theme", "主题"),
        ("language", "语言"),
        ("translation", "翻译"),
        ("translate", "翻译"),
        ("dark mode", "深色模式"),
        ("notification", "通知"),
        ("calendar", "日历"),
        ("weather", "天气"),
        ("clock", "时钟"),
        ("timer", "计时器"),
        ("pomodoro", "番茄钟"),
        ("habit", "习惯"),
        ("todo", "待办"),
        ("task", "任务"),
        ("project", "项目"),
        ("kanban", "看板"),
        ("wiki", "维基"),
        ("journal", "日记"),
        ("diary", "日记"),
    ]

    private static let englishPhrases = phrases.sorted { $0.0.count > $1.0.count }
    private static let chinesePhrases = phrases.sorted { $0.1.count > $1.1.count }

    static func dictionaryTranslate(_ text: String, toChinese: Bool) -> String {
        var result = text
        if toChinese {
            for (en, zh) in englishPhrases {
                result = result.replacingOccurrences(of: en, with: zh, options: [.caseInsensitive])
            }
        } else {
            for (en, zh) in chinesePhrases {
                result = result.replacingOccurrences(of: zh, with: en, options: [])
            }
        }
        return result
    }

    enum Provider: String {
        case online = "在线翻译（MyMemory）"
        case dictionary = "内置词库"
        case fallback = "在线不可用，使用词库"
    }

    static var onlineEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "translationOnlineEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "translationOnlineEnabled") }
    }

    private static let cache: NSCache<NSString, NSString> = {
        let value = NSCache<NSString, NSString>()
        value.countLimit = 200
        value.totalCostLimit = 1_000_000
        return value
    }()

    /// Preserve all Unicode scalars; prefer sentence/word boundaries when possible.
    static func chunks(_ text: String, maxBytes: Int = 450) -> [String] {
        precondition(maxBytes >= 4)
        var result: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            let next = String(scalar)
            if current.utf8.count + next.utf8.count > maxBytes {
                if let boundary = current.lastIndex(where: { $0.isWhitespace || "。！？.!?".contains($0) }),
                   current[...boundary].utf8.count >= maxBytes / 2 {
                    let end = current.index(after: boundary)
                    result.append(String(current[..<end]))
                    current = String(current[end...])
                } else {
                    result.append(current)
                    current = ""
                }
            }
            current += next
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func onlineTranslate(_ text: String, toChinese: Bool, useCache: Bool = true,
        load: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !Task.isCancelled else { return nil }
        let key = (toChinese ? "en|zh-CN|" : "zh-CN|en|") + trimmed
        if useCache, let cached = cache.object(forKey: key as NSString) { return cached as String }
        var translatedParts: [String] = []
        do {
            for part in chunks(trimmed) {
                try Task.checkCancellation()
                // Whitespace-only chunks do not need a network round trip.
                if part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    translatedParts.append(part)
                    continue
                }
                var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
                components.queryItems = [URLQueryItem(name: "q", value: part),
                    URLQueryItem(name: "langpair", value: toChinese ? "en|zh-CN" : "zh-CN|en")]
                guard let url = components.url else { return nil }
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await load(request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let responseStatus = object["responseStatus"], String(describing: responseStatus) == "200",
                      let responseData = object["responseData"] as? [String: Any],
                      let translated = responseData["translatedText"] as? String,
                      !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                // The service trims surrounding whitespace; restore paragraph/word separators.
                let leading = String(part.prefix(while: { $0.isWhitespace }))
                let trailing = String(part.reversed().prefix(while: { $0.isWhitespace }).reversed())
                translatedParts.append(leading + translated.trimmingCharacters(in: .whitespacesAndNewlines) + trailing)
            }
        } catch { return nil }
        let translated = translatedParts.joined()
        if useCache { cache.setObject(translated as NSString, forKey: key as NSString, cost: translated.utf8.count) }
        return translated
    }

    @discardableResult
    static func translate(_ text: String, toChinese: Bool, completion: @escaping (String, Provider) -> Void) -> Task<Void, Never> {
        Task {
            let result = await translateAsync(text, toChinese: toChinese)
            guard !Task.isCancelled else { return }
            DispatchQueue.main.async { completion(result.0, result.1) }
        }
    }

    static func translateAsync(_ text: String, toChinese: Bool) async -> (String, Provider) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", .dictionary) }
        let online = onlineEnabled
        if online, let translated = await onlineTranslate(trimmed, toChinese: toChinese) { return (translated, .online) }
        return (dictionaryTranslate(trimmed, toChinese: toChinese), online ? .fallback : .dictionary)
    }

    private final class ResultBox {
        private let lock = NSLock()
        private var value: (String, Provider)?
        func set(_ result: (String, Provider)) { lock.lock(); defer { lock.unlock() }; value = result }
        func get() -> (String, Provider)? { lock.lock(); defer { lock.unlock() }; return value }
    }

    static func translateSync(_ text: String, toChinese: Bool) -> (String, Provider) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        let task = Task.detached {
            box.set(await translateAsync(text, toChinese: toChinese))
            semaphore.signal()
        }
        let timeout = min(120, Double(chunks(text).count) * 20 + 5)
        if semaphore.wait(timeout: .now() + timeout) == .timedOut { task.cancel() }
        return box.get() ?? (dictionaryTranslate(text, toChinese: toChinese), onlineEnabled ? .fallback : .dictionary)
    }

}

// MARK: - 翻译窗口

import AppKit

final class TranslatorWindowController: NSWindowController, NSTextViewDelegate, NSWindowDelegate {
    private let inputView = NSTextView()
    private let outputView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let direction = NSSegmentedControl(labels: [L10n.t("英 → 中", "EN → ZH"), L10n.t("中 → 英", "ZH → EN")], trackingMode: .selectOne, target: nil, action: nil)
    private var toChinese = true
    private var translationTask: Task<Void, Never>?
    private var requestID = UUID()

    deinit { translationTask?.cancel() }

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.t("中英翻译", "CN ↔ EN Translator")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        super.init(window: panel)
        panel.delegate = self
        panel.minSize = NSSize(width: 520, height: 400)
        buildUI()
        panel.setContentSize(NSSize(width: 520, height: 400))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeScroll(_ textView: NSTextView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        return scroll
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let inputScroll = makeScroll(inputView)
        inputView.delegate = self
        inputView.setAccessibilityLabel(L10n.t("待翻译文本", "Text to translate"))
        let outputScroll = makeScroll(outputView)
        outputView.isEditable = false
        outputView.setAccessibilityLabel(L10n.t("翻译结果", "Translation result"))
        direction.selectedSegment = 0
        direction.target = self
        direction.action = #selector(directionChanged)
        let button = NSButton(title: L10n.t("翻译", "Translate"), target: self, action: #selector(translateAction))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.keyEquivalentModifierMask = [.command]
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.stringValue = L10n.t("词库替换 · 在线翻译需开启", "Dictionary · online opt-in")
        for view in [inputScroll, outputScroll, direction, button, statusLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            inputScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            inputScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            inputScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            inputScroll.heightAnchor.constraint(equalToConstant: 120),
            direction.leadingAnchor.constraint(equalTo: inputScroll.leadingAnchor),
            direction.topAnchor.constraint(equalTo: inputScroll.bottomAnchor, constant: 10),
            direction.widthAnchor.constraint(equalToConstant: 160),
            button.leadingAnchor.constraint(equalTo: direction.trailingAnchor, constant: 10),
            button.centerYAnchor.constraint(equalTo: direction.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 80),
            statusLabel.leadingAnchor.constraint(equalTo: button.trailingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: inputScroll.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            outputScroll.leadingAnchor.constraint(equalTo: inputScroll.leadingAnchor),
            outputScroll.trailingAnchor.constraint(equalTo: inputScroll.trailingAnchor),
            outputScroll.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 12),
            outputScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            outputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        inputView.string = "Clipboard history manager for macOS"
    }

    private func cancelPendingTranslation() {
        requestID = UUID()
        translationTask?.cancel()
        translationTask = nil
    }

    func windowWillClose(_ notification: Notification) { cancelPendingTranslation() }

    func textDidChange(_ notification: Notification) {
        cancelPendingTranslation()
        outputView.string = ""
        statusLabel.stringValue = L10n.t("\(inputView.string.count) 字 · ⌘↩ 翻译", "\(inputView.string.count) characters · ⌘↩ translate")
    }

    @objc private func directionChanged() {
        cancelPendingTranslation()
        toChinese = direction.selectedSegment == 0
        outputView.string = ""
        statusLabel.stringValue = L10n.t("方向已切换，点击翻译", "Direction changed; translate again")
    }

    @objc private func translateAction() {
        cancelPendingTranslation()
        let text = inputView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            outputView.string = ""
            statusLabel.stringValue = L10n.t("请输入待翻译文本", "Enter text to translate")
            return
        }
        guard text.utf8.count <= 6_000 else {
            outputView.string = ""
            statusLabel.stringValue = L10n.t("文本过长，请分成较短的段落", "Text is too long; split into shorter paragraphs")
            statusLabel.toolTip = statusLabel.stringValue
            return
        }
        let id = requestID
        outputView.string = ""
        statusLabel.stringValue = L10n.t("翻译中…", "Translating…")
        translationTask = Translator.translate(text, toChinese: toChinese) { [weak self] result, provider in
            guard let self = self, self.requestID == id else { return }
            self.translationTask = nil
            self.outputView.string = result
            switch provider {
            case .online: self.statusLabel.stringValue = L10n.t("在线翻译（MyMemory）", "Online (MyMemory)")
            case .dictionary: self.statusLabel.stringValue = L10n.t("词库替换（非全文翻译）", "Dictionary substitution")
            case .fallback: self.statusLabel.stringValue = L10n.t("在线不可用，已用词库替换", "Online unavailable; dictionary used")
            }
            self.statusLabel.toolTip = self.statusLabel.stringValue
        }
    }
}
