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

    static func dictionaryTranslate(_ text: String, toChinese: Bool) -> String {
        var result = text
        let ordered = phrases.sorted { $0.0.count > $1.0.count }
        if toChinese {
            for (en, zh) in ordered {
                result = result.replacingOccurrences(of: en, with: zh, options: [.caseInsensitive])
            }
        } else {
            for (en, zh) in ordered {
                result = result.replacingOccurrences(of: zh, with: en, options: [])
            }
        }
        return result
    }

    enum Provider: String {
        case system = "系统翻译"
        case online = "在线翻译（MyMemory）"
        case dictionary = "内置词库"
    }

    static var onlineEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "translationOnlineEnabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "translationOnlineEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "translationOnlineEnabled") }
    }

    private static let cache = NSCache<NSString, NSString>()

    private static func onlineTranslate(_ text: String, toChinese: Bool) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = (toChinese ? "en|zh-CN|" : "zh-CN|en|") + trimmed
        if let cached = cache.object(forKey: key as NSString) {
            return cached as String
        }
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: String(trimmed.prefix(450))),
            URLQueryItem(name: "langpair", value: toChinese ? "en|zh-CN" : "zh-CN|en"),
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseData = object["responseData"] as? [String: Any],
                  let translated = responseData["translatedText"] as? String,
                  !translated.isEmpty else {
                return nil
            }
            cache.setObject(translated as NSString, forKey: key as NSString)
            return translated
        } catch {
            return nil
        }
    }

    static func translate(_ text: String, toChinese: Bool, completion: @escaping (String, Provider) -> Void) {
        Task {
            let result = await translateAsync(text, toChinese: toChinese)
            let work = DispatchWorkItem { completion(result.0, result.1) }
            DispatchQueue.main.async(execute: work)
        }
    }

    static func translateAsync(_ text: String, toChinese: Bool) async -> (String, Provider) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", .dictionary) }
        if onlineEnabled, let online = await onlineTranslate(trimmed, toChinese: toChinese) {
            return (online, .online)
        }
        return (dictionaryTranslate(trimmed, toChinese: toChinese), .dictionary)
    }

    #if canImport(Translation) && compiler(>=6.2)
    @available(macOS 26.0, *)
    private static func systemTranslate(_ text: String, toChinese: Bool) async -> String? {
        let source = Locale.Language(identifier: toChinese ? "en" : "zh-Hans")
        let target = Locale.Language(identifier: toChinese ? "zh-Hans" : "en")
        let session = TranslationSession(installedSource: source, target: target)
        do {
            let response = try await session.translate(text)
            return response.targetText
        } catch {
            return nil
        }
    }
    #endif

    private final class ResultBox {
        var value: (String, Provider)?
    }

    static func translateSync(_ text: String, toChinese: Bool) -> (String, Provider) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        Task.detached {
            box.value = await translateAsync(text, toChinese: toChinese)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 25)
        if let value = box.value { return value }
        return (dictionaryTranslate(text, toChinese: toChinese), .dictionary)
    }

}

// MARK: - 翻译窗口

import AppKit

final class TranslatorWindowController: NSWindowController {
    private let inputView = NSTextView()
    private let outputView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let direction = NSSegmentedControl(labels: ["英 → 中", "中 → 英"], trackingMode: .selectOne, target: nil, action: nil)
    private var toChinese = true

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "中英翻译"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        super.init(window: panel)
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
        content.frame = NSRect(x: 0, y: 0, width: 520, height: 400)

        let inputScroll = makeScroll(inputView)
        inputScroll.frame = NSRect(x: 14, y: 266, width: 492, height: 120)
        inputScroll.autoresizingMask = [.width]

        let outputScroll = makeScroll(outputView)
        outputScroll.frame = NSRect(x: 14, y: 14, width: 492, height: 202)
        outputScroll.autoresizingMask = [.width, .height]
        outputView.isEditable = false

        direction.frame = NSRect(x: 14, y: 228, width: 160, height: 24)
        direction.selectedSegment = 0
        direction.target = self
        direction.action = #selector(directionChanged)
        direction.autoresizingMask = [.maxXMargin]

        let translateButton = NSButton(title: "翻译", target: self, action: #selector(translateAction))
        translateButton.bezelStyle = .rounded
        translateButton.frame = NSRect(x: 184, y: 226, width: 80, height: 28)

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.frame = NSRect(x: 274, y: 230, width: 232, height: 18)
        statusLabel.autoresizingMask = [.width]
        statusLabel.stringValue = "系统语言包未安装时使用内置词库"

        inputView.string = "Clipboard history manager for macOS"

        for view in [inputScroll, outputScroll, direction, translateButton, statusLabel] {
            content.addSubview(view)
        }
    }

    @objc private func directionChanged() {
        toChinese = direction.selectedSegment == 0
    }

    @objc private func translateAction() {
        statusLabel.stringValue = "翻译中…"
        Translator.translate(inputView.string, toChinese: toChinese) { [weak self] result, provider in
            self?.outputView.string = result
            self?.statusLabel.stringValue = provider.rawValue
        }
    }
}
