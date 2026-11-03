import AppKit

// CLI 模式：可被 App 自身调用，也可在终端里跑
let cliArguments = CommandLine.arguments
if let index = cliArguments.firstIndex(of: "--agent"), index + 1 < cliArguments.count {
    exit(AgentCLI.run(Array(cliArguments[(index + 1)...])))
}

if let index = cliArguments.firstIndex(of: "--translate"), index + 1 < cliArguments.count {
    let text = cliArguments[(index + 1)...].joined(separator: " ")
    let (result, provider) = Translator.translateSync(text, toChinese: true)
    print("[\(provider.rawValue)]")
    print(result)
    exit(0)
}

// 单实例：正常 GUI 启动时加 flock；--agent / --translate 不参与
import Darwin
let lockPath = NSTemporaryDirectory() + "com.a1.toolsidebar.lock"
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o600)
if lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
