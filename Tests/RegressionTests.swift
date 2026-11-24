import AppKit

@main
struct RegressionTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        guard (try? condition()) == true else { fatalError(message) }
        checks += 1
    }

    @MainActor static func main() async throws {
        let assets: [[String: Any]] = [
            ["name": "Utility-macos-arm64.dmg"],
            ["name": "Utility-macos-x86_64.zip"],
            ["name": "Utility-windows-x64.zip"]
        ]
        expect(AgentCLI.pickAsset(assets, architecture: .intel)?["name"] as? String == "Utility-macos-x86_64.zip", "Intel must reject an ARM-only DMG")
        expect(AgentCLI.pickAsset(assets, architecture: .arm64)?["name"] as? String == "Utility-macos-arm64.dmg", "Apple Silicon must select ARM")
        expect(AgentCLI.pickAsset([["name": "Utility-arm64.zip"]], architecture: .intel) == nil, "Never fall back to an incompatible architecture")
        expect(AgentCLI.pickAsset(assets + [["name": "Utility-universal.zip"]], architecture: .intel)?["name"] as? String == "Utility-universal.zip", "Prefer universal over archive format")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("toolsidebar-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("New.app")
        let destination = root.appendingPathComponent("Installed.app")
        for app in [source, destination] { try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true) }
        try Data("new".utf8).write(to: source.appendingPathComponent("version"))
        try Data("old".utf8).write(to: destination.appendingPathComponent("version"))
        do {
            try AgentCLI.replaceApp(source: source.path, destination: destination.path) { _ in
                throw AgentError.message("Simulated validation failure")
            }
            fatalError("Validation failure must propagate")
        } catch {}
        expect(try String(contentsOf: destination.appendingPathComponent("version"), encoding: .utf8) == "old", "Failed validation must preserve the old app")
        try AgentCLI.replaceApp(source: source.path, destination: destination.path)
        expect(try String(contentsOf: destination.appendingPathComponent("version"), encoding: .utf8) == "new", "Commit the staged app only after validation")
        expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".toolsidebar-") }.isEmpty, "Successful replacement must clean staging/backup files")
        do {
            try AgentCLI.replaceApp(source: root.appendingPathComponent("Missing.app").path, destination: destination.path)
            fatalError("Missing source must fail")
        } catch {}
        expect(try String(contentsOf: destination.appendingPathComponent("version"), encoding: .utf8) == "new", "Copy failure must preserve the installed app")

        let output = AgentCLI.process("/bin/sh", ["-c", "head -c 131072 /dev/zero >&2; head -c 131072 /dev/zero"])
        expect(output.code == 0 && output.out.utf8.count == 131072 && output.err.utf8.count == 131072, "Drain both large streams without deadlock or data loss")

        let legacy = try JSONDecoder().decode(Overrides.self, from: Data("{\"names\":{\"maccy\":\"剪贴板\"},\"orders\":{},\"categories\":{},\"customCategories\":[]}".utf8))
        expect(legacy.names["maccy"] == "剪贴板" && legacy.favorites.isEmpty, "Existing settings must survive the new favorites field")
        var settings = legacy
        settings.favorites = ["maccy"]
        let roundTrip = try JSONDecoder().decode(Overrides.self, from: JSONEncoder().encode(settings))
        expect(roundTrip.favorites == ["maccy"] && roundTrip.names == legacy.names, "Favorites must round-trip without losing custom names")

        let app = root.appendingPathComponent("Renamed.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "test.toolsidebar.fixture", "CFBundleName": "Utility", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        InstalledApplications.refresh(directories: [root])
        let identified = Tool(id: "fixture", name: "Custom display name", subtitle: "", icon: "app", group: "Test", path: root.appendingPathComponent("Old.app").path, bundleID: "test.toolsidebar.fixture")
        expect(InstalledApplications.url(for: identified)?.standardizedFileURL.path == app.standardizedFileURL.path, "Resolve a moved/renamed app by Bundle ID")
        let byName = Tool(id: "name", name: "Utility", subtitle: "", icon: "app", group: "Test")
        expect(isInstalled(byName), "Recognize apps outside a hardcoded catalog path")

        _ = NSApplication.shared
        let controller = SidebarViewController(preview: true)
        let view = controller.view
        func descendants(_ parent: NSView) -> [NSView] { parent.subviews.flatMap { [$0] + descendants($0) } }
        let nodes = descendants(view)
        let search = nodes.compactMap { $0 as? NSSearchField }.first!
        let filter = nodes.compactMap { $0 as? NSSegmentedControl }.first!
        let stack = nodes.compactMap { $0 as? NSStackView }.first { $0.arrangedSubviews.contains { $0 is ToolRowView } }!
        let rows = stack.arrangedSubviews.compactMap { $0 as? ToolRowView }
        let identifiers = rows.map(ObjectIdentifier.init)
        search.stringValue = "Maccy"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        let after = stack.arrangedSubviews.compactMap { $0 as? ToolRowView }
        expect(after.map(ObjectIdentifier.init) == identifiers, "Typing must reuse rows instead of rebuilding them")
        expect(!after.filter { !$0.isHidden }.isEmpty && after.filter { !$0.isHidden }.contains { $0.tool.id == "maccy" }, "Search must keep matching rows visible")
        search.stringValue = ""
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        filter.selectedSegment = 1
        NSApp.sendAction(filter.action!, to: filter.target, from: filter)
        expect(rows.filter { !$0.isHidden }.allSatisfy { $0.installedSnapshot }, "Installed filter must use actual status, not the existence of a configured path")
        filter.selectedSegment = 2
        NSApp.sendAction(filter.action!, to: filter.target, from: filter)
        expect(rows.filter { !$0.isHidden }.count == rows.filter { $0.isFavorite }.count, "Favorites filter must match persisted favorites")
        let longText = String(repeating: "Long paragraph with words. 中文段落。 👩🏽‍💻\n", count: 30)
        let parts = Translator.chunks(longText)
        expect(parts.joined() == longText && parts.allSatisfy { $0.utf8.count <= 450 }, "Chunk long multilingual text without losing content or exceeding the byte budget")
        let combining = "a" + String(repeating: "\u{0301}", count: 600)
        expect(Translator.chunks(combining).joined() == combining && Translator.chunks(combining).allSatisfy { $0.utf8.count <= 450 }, "Even a very long composed grapheme must survive chunking")
        var requests: [String] = []
        let translated = await Translator.onlineTranslate(longText, toChinese: true, useCache: false) { request in
            let part = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "q" }!.value!
            requests.append(part)
            let data = try JSONSerialization.data(withJSONObject: ["responseStatus": 200, "responseData": ["translatedText": part]])
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        expect(translated == longText.trimmingCharacters(in: .whitespacesAndNewlines) && requests.count > 1, "Translate every segment and preserve paragraph separators; do not truncate to the first segment")
        let rejected = await Translator.onlineTranslate("HTTP failure fixture", toChinese: true, useCache: false) { request in
            let data = Data("{\"responseStatus\":200,\"responseData\":{\"translatedText\":\"error body\"}}".utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        }
        expect(rejected == nil, "Do not show an HTTP error response as a successful translation")
        let quota = await Translator.onlineTranslate("Quota fixture", toChinese: true, useCache: false) { request in
            let data = Data("{\"responseStatus\":403,\"responseData\":{\"translatedText\":\"quota exceeded\"}}".utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        expect(quota == nil, "Reject service-level failures even when HTTP succeeds")
        let cancelled = Task { await Translator.onlineTranslate("Cancelled fixture", toChinese: true, useCache: false) { request in
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        } }
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        expect(cancelledResult == nil, "Cancelled requests must not produce a translation")

        UserDefaults.standard.setVolatileDomain(["translationOnlineEnabled": false], forName: UserDefaults.argumentDomain)
        let translator = TranslatorWindowController()
        let translatorNodes = descendants(translator.window!.contentView!)
        let input = translatorNodes.compactMap { $0 as? NSTextView }.first { $0.isEditable }!
        let outputView = translatorNodes.compactMap { $0 as? NSTextView }.first { !$0.isEditable }!
        let translateButton = translatorNodes.compactMap { $0 as? NSButton }.first { $0.action?.description == "translateAction" }!
        input.string = "clipboard"
        NSApp.sendAction(translateButton.action!, to: translateButton.target, from: translateButton)
        input.string = "timer"
        NSApp.sendAction(translateButton.action!, to: translateButton.target, from: translateButton)
        try await Task.sleep(nanoseconds: 150_000_000)
        expect(outputView.string == "计时器", "A superseded request must not overwrite the latest submitted text")
        input.string = "changed text"
        translator.textDidChange(Notification(name: NSText.didChangeNotification, object: input))
        expect(outputView.string.isEmpty, "Editing input must invalidate old output and pending requests")
        input.string = String(repeating: "中", count: 2100)
        NSApp.sendAction(translateButton.action!, to: translateButton.target, from: translateButton)
        expect(outputView.string.isEmpty, "Overlong input must be rejected instead of partially translated")
        translator.window?.close()
        print("PASS: \(checks) regression checks")
    }
}
