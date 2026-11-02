import Foundation
import CryptoKit

// MARK: - 本地安装 agent（纯 Swift，无 Python 依赖）

enum AgentError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

enum AgentCLI {
    static let home = NSHomeDirectory()
    static let appsDir = home + "/Applications"
    static let cacheDir = home + "/Library/Caches/ToolSidebar"
    static let catalogDir = home + "/Library/Application Support/小工具侧边栏"
    static let catalogPath = catalogDir + "/catalog.json"
    static let launchAgentPath = home + "/Library/LaunchAgents/com.a1.toolsidebar.plist"
    static let mirror = "https://ghproxy.net/"

    // MARK: 输出

    static func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        print(text)
        fflush(stdout)
    }

    static func fail(_ message: String, extra: [String: Any] = [:]) -> Int32 {
        var object = extra
        object["ok"] = false
        object["error"] = message
        emit(object)
        return 1
    }

    // MARK: 入口

    static func run(_ args: [String]) -> Int32 {
        guard let command = args.first else {
            return fail("缺少命令")
        }
        switch command {
        case "install":
            guard args.count >= 2 else { return fail("缺少安装目标") }
            let checkOnly = args.contains("--check-only")
            let force = args.contains("--force")
            var group = "已收录"
            if let index = args.firstIndex(of: "--group"), index + 1 < args.count {
                group = args[index + 1]
            }
            return install(target: args[1], checkOnly: checkOnly, force: force, group: group)
        case "search":
            guard args.count >= 2 else { return fail("缺少搜索词") }
            return search(query: args[1])
        case "list":
            emit(["tools": loadCatalog()])
            return 0
        case "remove":
            guard args.count >= 2 else { return fail("缺少仓库或路径") }
            return remove(target: args[1])
        case "check-updates":
            return checkUpdates()
        case "app-update-check":
            return appUpdateCheck()
        case "app-update":
            return appUpdate()
        case "autostart":
            guard args.count >= 2 else { return fail("缺少动作") }
            let appPath = args.count >= 3 ? args[2] : ""
            return autostart(action: args[1], appPath: appPath)
        default:
            return fail("未知命令：\(command)")
        }
    }

    // MARK: 网络

    static func token() -> String? {
        let tokenFile = home + "/.config/tool-sidebar/github_token"
        if let text = try? String(contentsOfFile: tokenFile, encoding: .utf8) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        let env = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ""
        return env.isEmpty ? nil : env
    }

    static func http(_ url: URL, method: String = "GET", body: Data? = nil) -> (Data?, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("ToolSidebar-Agent/2.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var data: Data?
        var status = 0
        let task = URLSession.shared.dataTask(with: request) { responseData, response, _ in
            data = responseData
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 120)
        return (data, status)
    }

    static func api(_ path: String) -> [String: Any]? {
        guard let url = URL(string: "https://api.github.com" + path) else { return nil }
        let (data, status) = http(url)
        guard status >= 200, status < 300, let data = data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    static func download(url: URL, to destination: URL) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        let task = URLSession.shared.downloadTask(with: url) { temporary, response, _ in
            if let temporary = temporary,
               (response as? HTTPURLResponse)?.statusCode == 200 {
                try? FileManager.default.removeItem(at: destination)
                if (try? FileManager.default.moveItem(at: temporary, to: destination)) != nil {
                    success = true
                }
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 600)
        return success
    }

    static func downloadWithMirror(_ urlString: String, to destination: URL) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        if download(url: url, to: destination) { return "direct" }
        if let mirrorURL = URL(string: mirror + urlString), download(url: mirrorURL, to: destination) {
            return "mirror"
        }
        return nil
    }

    // MARK: 工具函数

    static func sha256(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = (try? handle.read(upToCount: 1 << 20)) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    static func process(_ executable: String, _ arguments: [String]) -> (code: Int32, out: String, err: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do {
            try task.run()
        } catch {
            return (-1, "", error.localizedDescription)
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "")
    }

    static func normalizeVersion(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        return text
    }

    static func parseRepo(_ input: String) -> (owner: String, repo: String)? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "github.com/") {
            let rest = text[range.upperBound...]
            let parts = rest.split(separator: "/")
            if parts.count >= 2 {
                var repo = String(parts[1])
                if repo.hasSuffix(".git") { repo.removeLast(4) }
                return (String(parts[0]), repo)
            }
        }
        let parts = text.split(separator: "/")
        if parts.count == 2,
           !text.contains(" "),
           !text.lowercased().hasPrefix("http") {
            return (String(parts[0]), String(parts[1]))
        }
        return nil
    }

    // MARK: 搜索

    static let cjkMap: [(String, String)] = [
        ("窗口管理", "window manager"), ("窗口", "window"),
        ("剪贴板", "clipboard"), ("菜单栏", "menu bar"),
        ("压缩", "archiver"), ("解压", "archiver"),
        ("查重", "duplicate finder"), ("系统监控", "system monitor"),
        ("传输", "file transfer"), ("笔记", "notes"),
        ("写作", "writing"), ("排版", "typesetting"),
        ("日历", "calendar"), ("下载", "downloader"),
        ("截图", "screenshot"),
    ]

    static let directMap: [String: String] = [
        "窗口管理": "rxhanson/Rectangle",
        "窗口吸附": "rxhanson/Rectangle",
        "剪贴板": "p0deje/Maccy",
        "菜单栏": "jordanbaird/Ice",
        "菜单栏管理": "jordanbaird/Ice",
        "压缩": "aonez/Keka",
        "解压": "aonez/Keka",
        "查重": "qarmin/czkawka",
        "系统监控": "exelban/stats",
        "传输": "localsend/localsend",
        "跨设备传文件": "localsend/localsend",
        "日历": "sfsam/Itsycal",
        "窗口切换": "lwouis/alt-tab-macos",
    ]

    static func normalizedQuery(_ query: String) -> String {
        var text = query
        for (cn, en) in cjkMap {
            text = text.replacingOccurrences(of: cn, with: " " + en + " ")
        }
        return text.split(separator: " ").joined(separator: " ")
    }

    static func searchRepos(_ query: String, limit: Int = 10) -> [[String: Any]] {
        let normalized = normalizedQuery(query)
        var items = rawSearch(normalized + " macos")
        if items.isEmpty {
            items = rawSearch(normalized)
        }
        let needle = query.lowercased()
        let scored = items.map { item -> (Double, [String: Any]) in
            let name = (item["name"] as? String ?? "").lowercased()
            let description = (item["description"] as? String ?? "").lowercased()
            let text = name + " " + description
            var score = 0.0
            if name == needle { score += 100 }
            else if name.contains(needle) { score += 50 }
            if text.contains("macos") || text.contains("mac os") || text.contains("os x") { score += 30 }
            if text.contains("mac") && !text.contains("macos") { score += 8 }
            if text.contains("linux") && !text.contains("macos") { score -= 10 }
            let stars = Double(item["stargazers_count"] as? Int ?? 0)
            score += min(stars / 10000.0, 10)
            return (score, item)
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(limit).map { $0.1 }
    }

    static func rawSearch(_ query: String) -> [[String: Any]] {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        guard let object = api("/search/repositories?q=\(encoded)&sort=stars&order=desc&per_page=20"),
              let items = object["items"] as? [[String: Any]] else {
            return []
        }
        return items.filter { ($0["archived"] as? Bool) != true }
    }

    // MARK: 资产选择

    static func isInstallable(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.hasSuffix(".dmg") || lower.hasSuffix(".zip") else { return false }
        let bad = ["windows", "win64", "win32", "linux", ".deb", ".rpm", "appimage", ".sig", ".sha256"]
        if bad.contains(where: { lower.contains($0) }) { return false }
        return true
    }

    static func pickAsset(_ assets: [[String: Any]]) -> [String: Any]? {
        var scored: [(Int, [String: Any])] = []
        for asset in assets {
            guard let name = asset["name"] as? String, isInstallable(name) else { continue }
            let lower = name.lowercased()
            var score = 0
            if lower.hasSuffix(".dmg") { score += 8 }
            if lower.hasSuffix(".zip") { score += 4 }
            if lower.contains("arm64") || lower.contains("aarch64") || lower.contains("universal") || lower.contains("silicon") {
                score += 3
            }
            if lower.contains("mac") || lower.contains("darwin") || lower.contains("osx") { score += 2 }
            if lower.contains("x86_64") || lower.contains("intel") || lower.contains("amd64") { score -= 1 }
            scored.append((score, asset))
        }
        return scored.max(by: { $0.0 < $1.0 })?.1
    }

    // MARK: 解包 / 校验

    static func findApp(in directory: String) -> String? {
        let fm = FileManager.default
        if let names = try? fm.contentsOfDirectory(atPath: directory) {
            for name in names where name.hasSuffix(".app") {
                return directory + "/" + name
            }
            for name in names {
                let path = directory + "/" + name
                if let sub = try? fm.contentsOfDirectory(atPath: path) {
                    for inner in sub where inner.hasSuffix(".app") {
                        return path + "/" + inner
                    }
                }
            }
        }
        return nil
    }

    static func prepareApp(assetPath: String, workDir: String, mountPoint: inout String?) throws -> String {
        if assetPath.lowercased().hasSuffix(".dmg") {
            let (code, out, _) = process("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", assetPath])
            guard code == 0 else { throw AgentError.message("挂载 DMG 失败") }
            var mount: String?
            for line in out.split(separator: "\n") {
                if line.contains("/Volumes/") {
                    mount = line.split(separator: "\t").last.map(String.init)?.trimmingCharacters(in: .whitespaces)
                }
            }
            guard let mountPath = mount, let app = findApp(in: mountPath) else {
                throw AgentError.message("DMG 里没有 .app")
            }
            mountPoint = mountPath
            return app
        }
        let (code, _, _) = process("/usr/bin/ditto", ["-x", "-k", assetPath, workDir])
        guard code == 0 else { throw AgentError.message("解压失败") }
        guard let app = findApp(in: workDir) else { throw AgentError.message("压缩包里没有 .app") }
        return app
    }

    static func bundleInfo(_ appPath: String) -> (name: String, version: String) {
        let plistPath = appPath + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return ((appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: ""), "")
        }
        let name = plist["CFBundleDisplayName"] as? String
            ?? plist["CFBundleName"] as? String
            ?? (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let version = plist["CFBundleShortVersionString"] as? String
            ?? plist["CFBundleVersion"] as? String
            ?? ""
        return (name, version)
    }

    static func verify(appPath: String) -> (codesign: Bool, notarized: Bool, team: String?) {
        let codesign = process("/usr/bin/codesign", ["--verify", "--deep", "--strict", appPath]).code == 0
        let notarized = process("/usr/sbin/spctl", ["--assess", "--type", "execute", "-vv", appPath]).code == 0
        let detail = process("/usr/bin/codesign", ["-dv", "--verbose=4", appPath])
        var team: String?
        for line in detail.err.split(separator: "\n") {
            if line.hasPrefix("TeamIdentifier=") {
                team = String(line.dropFirst("TeamIdentifier=".count))
            }
        }
        return (codesign, notarized, team)
    }

    // MARK: 目录

    static func loadCatalog() -> [[String: Any]] {
        guard let data = FileManager.default.contents(atPath: catalogPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tools = object["tools"] as? [[String: Any]] else {
            return []
        }
        return tools
    }

    static func saveCatalog(_ tools: [[String: Any]]) {
        try? FileManager.default.createDirectory(atPath: catalogDir, withIntermediateDirectories: true)
        let object: [String: Any] = ["tools": tools]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: catalogPath))
        }
    }

    static func upsertCatalog(_ entry: [String: Any]) {
        var tools = loadCatalog()
        if let repo = entry["repo"] as? String {
            tools.removeAll { ($0["repo"] as? String) == repo }
        }
        tools.append(entry)
        saveCatalog(tools)
    }

    // MARK: 安装

    static func install(target: String, checkOnly: Bool, force: Bool, group: String) -> Int32 {
        do {
            let result = try performInstall(target: target, checkOnly: checkOnly, force: force, group: group)
            emit(result)
            return 0
        } catch {
            var extra: [String: Any] = ["target": target]
            if let agentError = error as? AgentError, case .message(let message) = agentError {
                extra["error"] = message
            } else {
                extra["error"] = "安装失败：\(error.localizedDescription)"
            }
            let direct = directMap[target.trimmingCharacters(in: .whitespaces)] ?? target
            if let parsed = parseRepo(direct) {
                extra["release_url"] = "https://github.com/\(parsed.owner)/\(parsed.repo)/releases"
            }
            emit(extra.merging(["ok": false]) { _, new in new })
            return 1
        }
    }

    static func performInstall(target: String, checkOnly: Bool, force: Bool, group: String) throws -> [String: Any] {
        let direct = directMap[target.trimmingCharacters(in: .whitespaces)]
        let parsed = parseRepo(direct ?? target)
        var release: [String: Any]?
        var full: String

        if let parsed = parsed {
            full = "\(parsed.owner)/\(parsed.repo)"
        } else {
            let candidates = searchRepos(target)
            guard !candidates.isEmpty else {
                throw AgentError.message("没有搜到「\(target)」对应的 GitHub 仓库")
            }
            var picked: String?
            for candidate in candidates.prefix(6) {
                guard let name = candidate["full_name"] as? String,
                      let candidateRelease = api("/repos/\(name)/releases/latest"),
                      let assets = candidateRelease["assets"] as? [[String: Any]],
                      pickAsset(assets) != nil else { continue }
                picked = name
                release = candidateRelease
                break
            }
            guard let pickedName = picked else {
                throw AgentError.message("搜到了仓库，但没有可自动安装的 macOS 包（只支持 dmg / zip）")
            }
            full = pickedName
        }

        if release == nil {
            release = api("/repos/\(full)/releases/latest")
        }
        guard let releaseObject = release else {
            throw AgentError.message("仓库没有 Release")
        }
        let releaseURL = releaseObject["html_url"] as? String ?? "https://github.com/\(full)/releases"
        guard let assets = releaseObject["assets"] as? [[String: Any]], let asset = pickAsset(assets) else {
            throw AgentError.message("这个仓库没有可直接安装的 macOS 包")
        }
        guard let assetName = asset["name"] as? String,
              let downloadURL = asset["browser_download_url"] as? String else {
            throw AgentError.message("Release 资源信息不完整")
        }

        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let destination = URL(fileURLWithPath: cacheDir + "/" + assetName)
        guard let via = downloadWithMirror(downloadURL, to: destination) else {
            throw AgentError.message("下载失败")
        }
        guard let digest = sha256(destination.path) else {
            throw AgentError.message("计算 SHA-256 失败")
        }
        var checksumVerified: Bool?
        if let official = asset["digest"] as? String, official.hasPrefix("sha256:") {
            let expected = String(official.dropFirst("sha256:".count))
            checksumVerified = (expected.lowercased() == digest.lowercased())
            if checksumVerified == false {
                throw AgentError.message("SHA-256 与 GitHub 官方 digest 不一致，已停止安装")
            }
        }

        let workDir = NSTemporaryDirectory() + "toolsidebar-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        var mountPoint: String?
        defer {
            if let mount = mountPoint {
                process("/usr/bin/hdiutil", ["detach", mount, "-quiet"])
            }
            try? FileManager.default.removeItem(atPath: workDir)
        }

        let appSource = try prepareApp(assetPath: destination.path, workDir: workDir, mountPoint: &mountPoint)
        let info = bundleInfo(appSource)
        let verification = verify(appPath: appSource)

        var result: [String: Any] = [
            "ok": true,
            "repo": full,
            "name": info.name,
            "version": info.version,
            "release_url": releaseURL,
            "asset": assetName,
            "sha256": digest,
            "codesign_ok": verification.codesign,
            "notarized": verification.notarized,
            "download_via": via,
            "group": group,
        ]
        if let team = verification.team { result["team_id"] = team }
        if let checksum = checksumVerified { result["checksum_verified"] = checksum }

        if !verification.codesign {
            result["ok"] = false
            result["error"] = "代码签名校验失败，已停止安装"
            return result
        }
        if checkOnly {
            result["message"] = "自检完成（未安装）"
            return result
        }

        try? FileManager.default.createDirectory(atPath: appsDir, withIntermediateDirectories: true)
        let appName = (appSource as NSString).lastPathComponent
        let finalPath = appsDir + "/" + appName
        let fm = FileManager.default
        if fm.fileExists(atPath: finalPath) {
            if force {
                try? fm.trashItem(at: URL(fileURLWithPath: finalPath), resultingItemURL: nil)
            } else {
                result["path"] = finalPath
                result["already_installed"] = true
                result["message"] = "已经安装过"
                return result
            }
        }
        let (copyCode, _, copyErr) = process("/usr/bin/ditto", [appSource, finalPath])
        guard copyCode == 0 else {
            throw AgentError.message("复制 App 失败：\(copyErr)")
        }
        process("/usr/bin/xattr", ["-dr", "com.apple.quarantine", finalPath])

        result["path"] = finalPath
        result["already_installed"] = false
        result["message"] = "安装完成，已通过自检并收录"

        let formatter = ISO8601DateFormatter()
        upsertCatalog([
            "id": "repo:\(full)",
            "name": info.name,
            "subtitle": "\(full) · \(info.version)",
            "icon": "shippingbox",
            "group": group,
            "path": finalPath,
            "repo": full,
            "version": info.version,
            "sha256": digest,
            "installedAt": formatter.string(from: Date()),
        ])
        return result
    }

    // MARK: 搜索 / 卸载 / 更新 / 自启

    static func search(query: String) -> Int32 {
        guard let item = searchRepos(query).first else {
            return fail("没有搜到合适的仓库")
        }
        emit([
            "ok": true,
            "repo": item["full_name"] as? String ?? "",
            "stars": item["stargazers_count"] as? Int ?? 0,
            "description": item["description"] as? String ?? "",
            "url": item["html_url"] as? String ?? "",
        ])
        return 0
    }

    static func remove(target: String) -> Int32 {
        var tools = loadCatalog()
        guard let index = tools.firstIndex(where: {
            ($0["repo"] as? String) == target || ($0["path"] as? String) == target
        }) else {
            return fail("目录里没有这个工具")
        }
        let tool = tools[index]
        var trashed = false
        if let path = tool["path"] as? String, FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                trashed = true
            } catch {
                return fail("移到废纸篓失败：\(error.localizedDescription)")
            }
        }
        tools.remove(at: index)
        saveCatalog(tools)
        emit(["ok": true, "name": tool["name"] as? String ?? "", "trashed": trashed])
        return 0
    }

    static func checkUpdates() -> Int32 {
        var updates: [[String: Any]] = []
        for tool in loadCatalog() {
            guard let repo = tool["repo"] as? String,
                  let release = api("/repos/\(repo)/releases/latest"),
                  let tag = release["tag_name"] as? String,
                  let assets = release["assets"] as? [[String: Any]],
                  pickAsset(assets) != nil else { continue }
            let current = normalizeVersion(tool["version"] as? String ?? "")
            let latest = normalizeVersion(tag)
            if !latest.isEmpty && latest != current {
                updates.append([
                    "repo": repo,
                    "name": tool["name"] as? String ?? "",
                    "current": current,
                    "latest": latest,
                    "path": tool["path"] as? String ?? "",
                ])
            }
        }
        emit(["ok": true, "updates": updates])
        return 0
    }

    // MARK: App 自更新

    static let appRepo = "LOVERS0/tool-sidebar"

    static func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    static func appUpdateCheck() -> Int32 {
        guard let release = api("/repos/\(appRepo)/releases/latest"),
              let tag = release["tag_name"] as? String,
              let assets = release["assets"] as? [[String: Any]] else {
            return fail("检查更新失败")
        }
        let latest = normalizeVersion(tag)
        let current = currentAppVersion()
        let zipAsset = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".zip") == true }
        var result: [String: Any] = [
            "ok": true,
            "current": current,
            "latest": latest,
            "update": latest != current,
            "release_url": release["html_url"] as? String ?? "",
        ]
        if let asset = zipAsset {
            result["asset"] = asset["name"] as? String ?? ""
            result["url"] = asset["browser_download_url"] as? String ?? ""
            if let digest = asset["digest"] as? String { result["digest"] = digest }
        }
        emit(result)
        return 0
    }

    static func appUpdate() -> Int32 {
        guard let release = api("/repos/\(appRepo)/releases/latest"),
              let assets = release["assets"] as? [[String: Any]],
              let asset = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".zip") == true }),
              let name = asset["name"] as? String,
              let urlString = asset["browser_download_url"] as? String,
              let url = URL(string: urlString) else {
            return fail("没有找到可用的更新包")
        }
        let updateDir = home + "/Library/Caches/ToolSidebar/update"
        try? FileManager.default.removeItem(atPath: updateDir)
        try? FileManager.default.createDirectory(atPath: updateDir, withIntermediateDirectories: true)
        let zipPath = updateDir + "/" + name
        guard downloadWithMirror(urlString, to: URL(fileURLWithPath: zipPath)) != nil else {
            return fail("更新包下载失败")
        }
        if let digest = asset["digest"] as? String, digest.hasPrefix("sha256:"),
           let actual = sha256(zipPath) {
            let expected = String(digest.dropFirst("sha256:".count))
            if expected.lowercased() != actual.lowercased() {
                return fail("更新包 SHA-256 校验失败")
            }
        }
        let appDir = updateDir + "/app"
        try? FileManager.default.createDirectory(atPath: appDir, withIntermediateDirectories: true)
        let (code, _, _) = process("/usr/bin/ditto", ["-x", "-k", zipPath, appDir])
        guard code == 0, let app = findApp(in: appDir) else {
            return fail("更新包解压失败")
        }
        emit(["ok": true, "path": app, "latest": normalizeVersion(release["tag_name"] as? String ?? "")])
        return 0
    }

    static func autostart(action: String, appPath: String) -> Int32 {
        let fm = FileManager.default
        if action == "status" {
            emit(["ok": true, "enabled": fm.fileExists(atPath: launchAgentPath)])
            return 0
        }
        if action == "off" {
            process("/bin/launchctl", ["bootout", "gui/\(getuid())", launchAgentPath])
            try? fm.removeItem(atPath: launchAgentPath)
            emit(["ok": true, "enabled": false])
            return 0
        }
        if action == "on" {
            guard !appPath.isEmpty else { return fail("缺少 App 路径") }
            try? fm.createDirectory(atPath: launchAgentPath.replacingOccurrences(of: "/com.a1.toolsidebar.plist", with: ""),
                                    withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Label": "com.a1.toolsidebar",
                "ProgramArguments": [appPath, "--silent"],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
            ]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
                return fail("生成 LaunchAgent 失败")
            }
            try? data.write(to: URL(fileURLWithPath: launchAgentPath))
            process("/bin/launchctl", ["bootout", "gui/\(getuid())", launchAgentPath])
            let (code, _, _) = process("/bin/launchctl", ["bootstrap", "gui/\(getuid())", launchAgentPath])
            emit(["ok": true, "enabled": true, "launchctl": Int(code)])
            return 0
        }
        return fail("未知动作：\(action)")
    }
}
