import AppKit

// CLI 模式：可被 App 自身调用，也可在终端里跑
let cliArguments = CommandLine.arguments
if let index = cliArguments.firstIndex(of: "--agent"), index + 1 < cliArguments.count {
    exit(AgentCLI.run(Array(cliArguments[(index + 1)...])))
}

if cliArguments.contains("--translate") || cliArguments.contains("--translator") {
    fputs("内置翻译已移除。请使用独立翻译应用。\n", stderr)
    exit(64)
}

// 单实例：正常 GUI 启动时加 flock；--agent 不参与
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
