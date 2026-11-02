import AppKit

// CLI 模式：可被 App 自身调用，也可在终端里跑
let cliArguments = CommandLine.arguments
if let index = cliArguments.firstIndex(of: "--agent"), index + 1 < cliArguments.count {
    exit(AgentCLI.run(Array(cliArguments[(index + 1)...])))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
