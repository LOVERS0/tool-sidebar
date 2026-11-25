import AppKit

@main
struct RegressionTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        guard (try? condition()) == true else { fatalError(message) }
        checks += 1
    }

    @MainActor static func main() throws {
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
        let missingTool = Tool(id: "missing", name: "Missing app", subtitle: "", icon: "app", group: "Test", path: root.appendingPathComponent("NotInstalled.app").path)
        let missingRow = ToolRowView(tool: missingTool)
        let missingAction = missingRow.subviews.compactMap { $0 as? NSButton }.first!
        expect(!missingAction.isEnabled && missingAction.title == L10n.t("未安装", "Missing"), "A missing app without an explicit source must not offer guessed installation")
        let actions = Set(controller.makeMoreMenu().items.compactMap { $0.action?.description })
        expect(actions == Set(["checkSparkleUpdates", "toggleAutostartMenu", "exportConfig", "importConfig", "openGitHubRepo", "quitApp"]), "More menu must contain only update, startup, backup, feedback and quit actions")
        let retired = Set(["typst", "doocsmd", "avoidai", "markitdown"])
        expect(Toolbox.builtin.allSatisfy { !retired.contains($0.id) }, "Retire non-application and command-copy defaults")
        expect(Toolbox.builtin.contains { $0.id == "maccy" } && Toolbox.builtin.contains { $0.id == "rectangle" }, "Keep normal application launchers")
        let installedEntry = CatalogTool(id: "repo:owner/existing", name: "Existing name", subtitle: "", icon: "app", group: "已收录", path: "/Applications/Existing.app", repo: "owner/existing", version: "3.0", sha256: "unchanged", installedAt: "existing-date", bundleID: "fixture.existing")
        let restored = try restoreToolList([
            MigrationTool(repo: "OWNER/existing", name: "Do not overwrite", group: nil),
            MigrationTool(repo: "owner/new", name: "New tool", group: "系统小工具"),
            MigrationTool(repo: "owner/new", name: "Duplicate", group: nil)
        ], keeping: [installedEntry])
        expect(restored.count == 2, "Restore repository entries without duplicates")
        expect(restored[0].name == "Existing name" && restored[0].path == installedEntry.path && restored[0].sha256 == "unchanged" && restored[0].bundleID == "fixture.existing", "Import must preserve existing installed app metadata")
        expect(restored[1].path == nil && restored[1].version == nil && restored[1].installedAt == nil, "Restore a missing tool as an uninstalled entry instead of installing it")
        do {
            _ = try restoreToolList([MigrationTool(repo: "not-a-repository", name: "Invalid", group: nil)], keeping: [installedEntry])
            fatalError("Invalid backup repository must fail")
        } catch { checks += 1 }
        let oldBackup = try JSONDecoder().decode(MigrationFile.self, from: Data("{\"version\":1,\"tools\":[{\"repo\":\"owner/new\",\"name\":\"New tool\"}],\"overrides\":{\"names\":{\"maccy\":\"剪贴板\"},\"orders\":{},\"categories\":{},\"customCategories\":[]},\"autostart\":false}".utf8))
        expect(oldBackup.overrides?.names["maccy"] == "剪贴板" && oldBackup.tools.count == 1, "Continue reading existing configuration backups after removing automatic installation")
        print("PASS: \(checks) regression checks")
    }
}
