import Foundation

enum L10n {
    static var isEnglish: Bool {
        if let value = UserDefaults.standard.string(forKey: "appLanguage"), !value.isEmpty {
            return value == "en"
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return !preferred.hasPrefix("zh")
    }

    static func t(_ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }

    private static let groupMap: [String: String] = [
        "写作": "Writing",
        "AI / 开发": "AI & Dev",
        "系统小工具": "System",
        "精选": "Featured",
        "已收录": "Installed",
    ]

    private static let nameMap: [String: String] = [
        "作家助手": "Writer Assistant",
        "思源笔记": "SiYuan",
        "公众号排版 doocs/md": "doocs/md",
        "去 AI 味 avoid-ai-writing": "Avoid AI Writing",
        "妙言 MiaoYan": "MiaoYan",
    ]

    private static let subtitleMap: [String: String] = [
        "番茄官方 · 正文 / 发布 / 备份": "Fanqie · draft / publish / backup",
        "本地 Markdown · 沉浸写作": "Local Markdown · focused writing",
        "沉浸写作 / 大纲": "Focused writing / outlines",
        "设定集 / 人物卡 / 世界观": "Worldbuilding / characters / lore",
        "小说工程 / 章节 / 情节线 · 需手动下载": "Novel projects / chapters / plotlines · manual download",
        "排版出 PDF / 样书 · 需手动下载": "Typeset PDF / proofs · manual download",
        "Markdown → 微信样式": "Markdown → WeChat styling",
        "Agent Skill · 需配合 agent": "Agent Skill · requires an agent",
        "一键切换 AI 供应商": "Switch AI providers",
        "当前使用的 agent harness": "Current agent harness",
        "桌面版": "Desktop app",
        "Git 图形客户端": "Git GUI",
        "个人 AI 助理": "Personal AI assistant",
        "文档转 Markdown · 点击复制命令": "Docs → Markdown · copy command",
        "剪贴板历史": "Clipboard history",
        "窗口吸附": "Window snapping",
        "文本扩展 / 缩写": "Text expander / snippets",
        "菜单栏系统监控": "Menu bar system monitor",
        "跨设备传文件": "Cross-device file transfer",
        "菜单栏管理": "Menu bar manager",
        "压缩 / 解压": "Archive / extract",
        "查重 / 清垃圾": "Duplicates / cleanup",
        "外接屏亮度": "External display brightness",
        "菜单栏日历": "Menu bar calendar",
        "窗口切换": "Window switcher",
        "检查 App 更新": "App update checker",
        "已收录": "Installed",
        "迁移导入": "Imported",
        "菜单栏开关合集": "Menu bar switches",
        "菜单栏图标隐藏": "Hide menu bar icons",
        "学术 Markdown 写作": "Academic Markdown writing",
        "简洁 Markdown 编辑器": "Minimal Markdown editor",
        "隐私笔记 / 同步": "Private notes / sync",
        "大纲笔记 / 知识库": "Outliner / knowledge base",
        "高性能代码编辑器": "High-performance editor",
        "离线 API 客户端": "Offline API client",
        "词典 / 翻译 / OCR": "Dictionary / translation / OCR",
        "划词翻译 / OCR": "Select-to-translate / OCR",
    ]

    static func group(_ value: String) -> String {
        isEnglish ? (groupMap[value] ?? value) : value
    }

    static func name(_ value: String) -> String {
        isEnglish ? (nameMap[value] ?? value) : value
    }

    static func subtitle(_ value: String) -> String {
        guard isEnglish else { return value }
        var base = value
        var suffix = ""
        if let range = value.range(of: " · v") {
            base = String(value[..<range.lowerBound])
            suffix = String(value[range.lowerBound...])
        }
        return (subtitleMap[base] ?? base) + suffix
    }
}
