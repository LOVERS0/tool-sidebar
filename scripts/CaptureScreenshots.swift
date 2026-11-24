import AppKit

@main
struct CaptureScreenshots {
    @MainActor static func main() async throws {
        UserDefaults.standard.setVolatileDomain(["appLanguage": "zh", "translationOnlineEnabled": false], forName: UserDefaults.argumentDomain)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let sidebar = SidebarViewController(preview: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 660), styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1)
        window.contentViewController = sidebar
        window.setContentSize(NSSize(width: 360, height: 660))
        try capture(sidebar.view, to: "screenshot.png")
        let translator = TranslatorWindowController()
        let content = translator.window!.contentView!
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let button = descendants(content).compactMap { $0 as? NSButton }.first { $0.action?.description == "translateAction" }!
        NSApp.sendAction(button.action!, to: button.target, from: button)
        try await Task.sleep(nanoseconds: 200_000_000)
        try capture(content, to: "translator.png")
        print("Captured native sidebar and translator views")
    }

    @MainActor static func capture(_ view: NSView, to path: String) throws {
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Cannot capture view") }
        bitmap.size = view.bounds.size
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode screenshot") }
        try png.write(to: URL(fileURLWithPath: path))
    }
}
