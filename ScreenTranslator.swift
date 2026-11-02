import AppKit
import Vision
import NaturalLanguage

// MARK: - 屏幕翻译（截图 → OCR → 中文覆盖层）

struct ScreenTranslationItem {
    let source: String
    let translation: String
    let box: CGRect
}

final class TranslationOverlayView: NSView {
    private let screenshot: NSImage
    private let items: [ScreenTranslationItem]
    var onClose: (() -> Void)?

    init(screenshot: NSImage, items: [ScreenTranslationItem]) {
        self.screenshot = screenshot
        self.items = items
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        screenshot.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 0.55, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        for item in items {
            let box = item.box
            let width = bounds.width
            let height = bounds.height
            var rect = CGRect(
                x: box.minX * width,
                y: (1 - box.maxY) * height,
                width: max(box.width * width, 60),
                height: max(box.height * height, 18)
            )
            let fontSize = max(11, min(20, rect.height * 0.55))
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ]
            let text = item.translation as NSString
            let textHeight = text.boundingRect(
                with: CGSize(width: rect.width - 10, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            ).height
            rect.size.height = max(rect.height, textHeight + 8)
            rect.size.width = min(width - rect.minX - 4, rect.width + 12)
            rect.origin.y = min(rect.origin.y, height - rect.height - 2)

            let background = NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -2), xRadius: 5, yRadius: 5)
            NSColor(calibratedWhite: 0.05, alpha: 0.82).setFill()
            background.fill()
            NSColor.white.withAlphaComponent(0.16).setStroke()
            background.lineWidth = 1
            background.stroke()
            text.draw(in: rect, withAttributes: attributes)
        }

        let hint = "屏幕翻译 · 点击任意处或按 Esc 关闭"
        let hintAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let hintSize = (hint as NSString).size(withAttributes: hintAttributes)
        let hintRect = CGRect(x: (bounds.width - hintSize.width) / 2 - 12,
                              y: 14,
                              width: hintSize.width + 24,
                              height: 30)
        NSColor(calibratedWhite: 0.05, alpha: 0.8).setFill()
        NSBezierPath(roundedRect: hintRect, xRadius: 8, yRadius: 8).fill()
        (hint as NSString).draw(at: CGPoint(x: hintRect.minX + 12, y: hintRect.minY + 7), withAttributes: hintAttributes)
    }

    override func mouseDown(with event: NSEvent) {
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onClose?()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class TranslationOverlayController: NSWindowController {
    static var current: TranslationOverlayController?

    init(screenshot: NSImage, items: [ScreenTranslationItem]) {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        let view = TranslationOverlayView(screenshot: screenshot, items: items)
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        panel.contentView = view
        super.init(window: panel)
        view.onClose = { [weak self] in self?.dismiss() }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(view)
        TranslationOverlayController.current = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func dismiss() {
        window?.orderOut(nil)
        TranslationOverlayController.current = nil
    }
}

enum ScreenTranslator {
    static func show() {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            showPermissionAlert()
            return
        }
        let shot = captureScreen()
        guard let screenshot = shot else {
            showError("截屏失败", "请确认已在 系统设置 → 隐私与安全性 → 屏幕录制 中授权。")
            return
        }
        guard let cgImage = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            showError("截屏失败", "无法读取屏幕图像。")
            return
        }
        var lines: [(String, CGRect)] = []
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count >= 2 else { continue }
                guard text.range(of: "[A-Za-z]", options: .regularExpression) != nil else { continue }
                guard text.range(of: "\\p{Han}", options: .regularExpression) == nil else { continue }
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(text)
                guard recognizer.dominantLanguage == .english else { continue }
                lines.append((text, observation.boundingBox))
            }
        } catch {
            showError("OCR 失败", error.localizedDescription)
            return
        }
        guard !lines.isEmpty else {
            showError("没识别到英文", "试试让英文窗口保持在最前面，再按一次 ⌥⌘Y。")
            return
        }
        translate(lines: lines, screenshot: screenshot)
    }

    private static func captureScreen() -> NSImage? {
        let path = NSTemporaryDirectory() + "toolsidebar-screen.png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "png", path]
        try? process.run()
        process.waitUntilExit()
        return NSImage(contentsOfFile: path)
    }

    private static func translate(lines: [(String, CGRect)], screenshot: NSImage) {
        var results: [ScreenTranslationItem] = []
        func next(_ index: Int) {
            guard index < lines.count else {
                let controller = ScreenTranslationPanelController(items: results)
                _ = controller
                return
            }
            let line = lines[index]
            Translator.translate(line.0, toChinese: true) { text, _ in
                results.append(ScreenTranslationItem(source: line.0, translation: text, box: line.1))
                next(index + 1)
            }
        }
        next(0)
    }

    private static func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要「屏幕录制」权限"
        alert.informativeText = "屏幕翻译要截取当前窗口做 OCR。请到 系统设置 → 隐私与安全性 → 屏幕录制 勾选「小工具侧边栏」，然后重新按 ⌥⌘Y。"
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "好")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private static func showError(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

// MARK: - 屏幕翻译结果面板（对照阅读）

final class ScreenTranslationPanelController: NSWindowController {
    static var current: ScreenTranslationPanelController?

    init(items: [ScreenTranslationItem]) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "屏幕翻译"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 620))
        let scroll = NSScrollView(frame: NSRect(x: 12, y: 48, width: 396, height: 560))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView()
        textView.isEditable = false
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 12.5)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        var body = ""
        for item in items {
            body += item.source + "\n→ " + item.translation + "\n\n"
        }
        textView.string = body
        scroll.documentView = textView

        let copyButton = NSButton(title: "复制全部", target: nil, action: nil)
        copyButton.bezelStyle = .rounded
        copyButton.frame = NSRect(x: 12, y: 12, width: 90, height: 28)
        let closeButton = NSButton(title: "关闭", target: nil, action: nil)
        closeButton.bezelStyle = .rounded
        closeButton.frame = NSRect(x: 110, y: 12, width: 70, height: 28)

        content.addSubview(scroll)
        content.addSubview(copyButton)
        content.addSubview(closeButton)
        panel.contentView = content
        super.init(window: panel)

        copyButton.target = self
        copyButton.action = #selector(copyAll(_:))
        closeButton.target = self
        closeButton.action = #selector(closePanel)
        panel.makeKeyAndOrderFront(nil)
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 440, y: frame.midY - 310))
        }
        NSApp.activate(ignoringOtherApps: true)
        ScreenTranslationPanelController.current = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func copyAll(_ sender: Any?) {
        if let textView = (window?.contentView?.subviews.compactMap { $0 as? NSScrollView }.first?.documentView as? NSTextView) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(textView.string, forType: .string)
        }
    }

    @objc private func closePanel() {
        window?.orderOut(nil)
        ScreenTranslationPanelController.current = nil
    }
}
