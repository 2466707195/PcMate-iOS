import Foundation
import SwiftUI

// MARK: - 进程分组与图标

enum ProcessGroup: String, CaseIterable, Identifiable {
    case app = "应用"
    case background = "后台进程"

    var id: String { rawValue }
    var label: String { rawValue }
}

enum ProcessIconKey: String {
    case browser, chat, folder, task, file, code, health, terminal, developer
    case hub, widgets, memory, search, settings, security, desktop, keyboard
    case volume, print, cloud, games, music, video, image, email, phone, lock, generic

    var systemIcon: String {
        switch self {
        case .browser: return "globe"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .folder: return "folder.fill"
        case .task: return "checklist"
        case .file: return "doc.text.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .health: return "heart.text.square.fill"
        case .terminal: return "terminal.fill"
        case .developer: return "hammer.fill"
        case .hub: return "point.3.connected.trianglepath.dotted"
        case .widgets: return "square.grid.2x2.fill"
        case .memory: return "memorychip.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        case .security: return "lock.shield.fill"
        case .desktop: return "desktopcomputer"
        case .keyboard: return "keyboard.fill"
        case .volume: return "speaker.wave.2.fill"
        case .print: return "printer.fill"
        case .cloud: return "cloud.fill"
        case .games: return "gamecontroller.fill"
        case .music: return "music.note"
        case .video: return "play.rectangle.fill"
        case .image: return "photo.fill"
        case .email: return "envelope.fill"
        case .phone: return "phone.fill"
        case .lock: return "lock.fill"
        case .generic: return "app.dashed"
        }
    }

    var tone: Color {
        switch self {
        case .browser: return Aurora.info
        case .chat: return Aurora.teal
        case .folder: return Aurora.warning
        case .task: return Aurora.brand
        case .file: return Aurora.info
        case .code: return Aurora.brand
        case .health: return Aurora.rose
        case .terminal: return Aurora.inkSoft
        case .developer: return Aurora.warning
        case .hub: return Aurora.teal
        case .widgets: return Aurora.brand
        case .memory: return Aurora.inkSoft
        case .search: return Aurora.info
        case .settings: return Aurora.inkSoft
        case .security: return Aurora.success
        case .desktop: return Aurora.info
        case .keyboard: return Aurora.inkSoft
        case .volume: return Aurora.teal
        case .print: return Aurora.inkSoft
        case .cloud: return Aurora.info
        case .games: return Aurora.brand
        case .music: return Aurora.rose
        case .video: return Aurora.rose
        case .image: return Aurora.warning
        case .email: return Aurora.info
        case .phone: return Aurora.success
        case .lock: return Aurora.warning
        case .generic: return Aurora.muted
        }
    }
}

struct ProcessMeta {
    let display: String
    let group: ProcessGroup
    let icon: ProcessIconKey
}

// MARK: - 常见进程中文名

enum ProcessCatalog {

    private static let entries: [String: ProcessMeta] = [
        // 浏览器
        "chrome": .init(display: "Google Chrome 浏览器", group: .app, icon: .browser),
        "msedge": .init(display: "Edge 浏览器", group: .app, icon: .browser),
        "firefox": .init(display: "Firefox 浏览器", group: .app, icon: .browser),
        "iexplore": .init(display: "Internet Explorer", group: .app, icon: .browser),
        "360se": .init(display: "360 安全浏览器", group: .app, icon: .browser),
        "360chrome": .init(display: "360 极速浏览器", group: .app, icon: .browser),
        "qqbrowser": .init(display: "QQ 浏览器", group: .app, icon: .browser),

        // 社交通讯
        "wechat": .init(display: "微信", group: .app, icon: .chat),
        "wechatappex": .init(display: "微信", group: .app, icon: .chat),
        "wechatinput": .init(display: "微信输入法", group: .background, icon: .keyboard),
        "qq": .init(display: "QQ", group: .app, icon: .chat),
        "tim": .init(display: "TIM", group: .app, icon: .chat),
        "dingtalk": .init(display: "钉钉", group: .app, icon: .chat),
        "feishu": .init(display: "飞书", group: .app, icon: .chat),
        "lark": .init(display: "Lark", group: .app, icon: .chat),

        // 系统与桌面
        "explorer": .init(display: "Windows 资源管理器", group: .app, icon: .folder),
        "taskmgr": .init(display: "任务管理器", group: .app, icon: .task),
        "notepad": .init(display: "记事本", group: .app, icon: .file),
        "calc": .init(display: "计算器", group: .app, icon: .file),
        "mspaint": .init(display: "画图", group: .app, icon: .image),
        "snippingtool": .init(display: "截图工具", group: .app, icon: .image),
        "systemsettings": .init(display: "系统设置", group: .app, icon: .settings),
        "startmenuexperiencehost": .init(display: "开始菜单", group: .background, icon: .desktop),
        "shellexperiencehost": .init(display: "Windows Shell", group: .background, icon: .desktop),
        "sihost": .init(display: "Windows 外壳主机", group: .background, icon: .desktop),
        "dwm": .init(display: "桌面窗口管理器", group: .background, icon: .desktop),
        "logonui": .init(display: "登录界面", group: .background, icon: .lock),

        // 办公与文档
        "winword": .init(display: "Microsoft Word", group: .app, icon: .file),
        "excel": .init(display: "Microsoft Excel", group: .app, icon: .file),
        "powerpnt": .init(display: "Microsoft PowerPoint", group: .app, icon: .file),
        "outlook": .init(display: "Microsoft Outlook", group: .app, icon: .email),
        "wps": .init(display: "WPS Office", group: .app, icon: .file),
        "et": .init(display: "WPS 表格", group: .app, icon: .file),
        "wpp": .init(display: "WPS 演示", group: .app, icon: .file),
        "acrord32": .init(display: "Adobe Acrobat", group: .app, icon: .file),
        "photoshop": .init(display: "Photoshop", group: .app, icon: .image),
        "potplayer": .init(display: "PotPlayer", group: .app, icon: .video),
        "vlc": .init(display: "VLC 播放器", group: .app, icon: .video),

        // 开发工具
        "code": .init(display: "Visual Studio Code", group: .app, icon: .code),
        "opencode": .init(display: "OpenCode", group: .app, icon: .code),
        "devenv": .init(display: "Visual Studio", group: .app, icon: .code),
        "idea64": .init(display: "IntelliJ IDEA", group: .app, icon: .code),
        "idea": .init(display: "IntelliJ IDEA", group: .app, icon: .code),
        "pycharm64": .init(display: "PyCharm", group: .app, icon: .code),
        "studio64": .init(display: "Android Studio", group: .app, icon: .code),
        "postman": .init(display: "Postman", group: .app, icon: .developer),
        "docker": .init(display: "Docker Desktop", group: .app, icon: .developer),
        "healthone": .init(display: "HealthOne", group: .app, icon: .health),

        // 终端与脚本
        "powershell": .init(display: "Windows PowerShell", group: .background, icon: .terminal),
        "pwsh": .init(display: "PowerShell", group: .background, icon: .terminal),
        "cmd": .init(display: "命令提示符", group: .background, icon: .terminal),
        "wsl": .init(display: "WSL", group: .background, icon: .terminal),
        "bun": .init(display: "Bun", group: .background, icon: .terminal),
        "node": .init(display: "Node.js", group: .background, icon: .terminal),
        "python": .init(display: "Python", group: .background, icon: .terminal),
        "adb": .init(display: "Android Debug Bridge", group: .background, icon: .developer),
        "pcmate-agent": .init(display: "PcMate Agent 服务", group: .background, icon: .settings),

        // 后台与系统进程
        "svchost": .init(display: "Windows 服务主机", group: .background, icon: .settings),
        "services": .init(display: "Windows 服务控制管理器", group: .background, icon: .settings),
        "lsass": .init(display: "本地安全机构进程", group: .background, icon: .security),
        "smss": .init(display: "Windows 会话管理器", group: .background, icon: .settings),
        "csrss": .init(display: "客户端服务器运行时", group: .background, icon: .settings),
        "wininit": .init(display: "Windows 启动应用程序", group: .background, icon: .settings),
        "winlogon": .init(display: "Windows 登录应用程序", group: .background, icon: .settings),
        "runtimebroker": .init(display: "运行时代理", group: .background, icon: .memory),
        "dllhost": .init(display: "COM 代理", group: .background, icon: .memory),
        "comsurrogate": .init(display: "COM 代理", group: .background, icon: .memory),
        "aggregatorhost": .init(display: "聚合主机", group: .background, icon: .hub),
        "applicationframehost": .init(display: "应用程序框架主机", group: .background, icon: .widgets),
        "searchindexer": .init(display: "Windows Search 索引器", group: .background, icon: .search),
        "searchhost": .init(display: "Windows Search", group: .background, icon: .search),
        "ctfmon": .init(display: "CTF 加载程序", group: .background, icon: .keyboard),
        "textinputhost": .init(display: "文本输入主机", group: .background, icon: .keyboard),
        "msmpeng": .init(display: "Microsoft Defender 防病毒", group: .background, icon: .security),
        "securityhealthservice": .init(display: "Windows 安全中心服务", group: .background, icon: .security),
        "securityhealthhost": .init(display: "Windows 安全中心", group: .background, icon: .security),
        "system": .init(display: "系统", group: .background, icon: .memory),
        "registry": .init(display: "注册表", group: .background, icon: .memory),
        "idle": .init(display: "系统空闲进程", group: .background, icon: .memory),
        "memorycompression": .init(display: "内存压缩", group: .background, icon: .memory),
        "audiodg": .init(display: "Windows 音频设备图形", group: .background, icon: .volume),
        "spoolsv": .init(display: "打印后台处理程序", group: .background, icon: .print),
        "nvcontainer": .init(display: "NVIDIA 容器", group: .background, icon: .settings),
        "igfx": .init(display: "Intel 图形", group: .background, icon: .memory),
        "sgtool": .init(display: "搜狗输入法工具", group: .background, icon: .keyboard),
        "sogousmartassistant": .init(display: "搜狗智能助手", group: .background, icon: .chat),
        "nisrv": .init(display: "Microsoft Defender 网络检查服务", group: .background, icon: .security),

        // 云与娱乐
        "onedrive": .init(display: "OneDrive", group: .app, icon: .cloud),
        "dropbox": .init(display: "Dropbox", group: .app, icon: .cloud),
        "baidunetdisk": .init(display: "百度网盘", group: .app, icon: .cloud),
        "steam": .init(display: "Steam", group: .app, icon: .games),
        "epicgameslauncher": .init(display: "Epic Games", group: .app, icon: .games),
        "battle.net": .init(display: "Battle.net", group: .app, icon: .games),
        "xbox": .init(display: "Xbox", group: .background, icon: .games),
        "gamebar": .init(display: "Xbox Game Bar", group: .background, icon: .games),
        "cloudmusic": .init(display: "网易云音乐", group: .app, icon: .music),
        "qqmusic": .init(display: "QQ 音乐", group: .app, icon: .music)
    ]

    private static let backgroundHints = [
        "svc", "service", "host", "broker", "runtime", "system", "csrss", "lsass",
        "services", "smss", "wininit", "winlogon", "dwm", "ctfmon", "search",
        "spoolsv", "audiodg", "msmpeng", "security", "surrogate", "aggregator",
        "background", "daemon", "kernel", "kworker", "systemd", "dbus", "udev"
    ]

    static func meta(name: String) -> ProcessMeta {
        let raw = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.range(of: #"^pid\s+\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return ProcessMeta(display: "系统进程", group: .background, icon: .memory)
        }
        var key = raw.lowercased()
        if key.hasSuffix(".exe") { key.removeLast(4) }
        if let hit = entries[key] { return hit }

        let lower = key
        if lower.contains("chrome") || lower.contains("edge") || lower.contains("firefox") {
            return ProcessMeta(display: raw.isEmpty ? "浏览器" : raw, group: .app, icon: .browser)
        }
        if lower.contains("code") || lower.contains("studio") || lower.contains("idea") {
            return ProcessMeta(display: raw.isEmpty ? "开发工具" : raw, group: .app, icon: .code)
        }
        if backgroundHints.contains(where: { lower.contains($0) }) {
            return ProcessMeta(display: raw.isEmpty ? "系统进程" : raw, group: .background, icon: .settings)
        }
        return ProcessMeta(display: raw.isEmpty ? "未知进程" : raw, group: .background, icon: .generic)
    }
}
