import Foundation

// MARK: - 基础枚举

enum RemoteOS: String, Codable, CaseIterable {
    case linux = "LINUX"
    case windows = "WINDOWS"
    case unknown = "UNKNOWN"

    var shortLabel: String {
        switch self {
        case .linux: return "Linux"
        case .windows: return "Windows"
        case .unknown: return "未知系统"
        }
    }

    var systemIcon: String {
        switch self {
        case .linux: return "terminal"
        case .windows: return "pc"
        case .unknown: return "desktopcomputer"
        }
    }
}

enum Transport: String, Codable, CaseIterable, Identifiable {
    case agent = "AGENT"
    case ssh = "SSH"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .agent: return "Agent"
        case .ssh: return "SSH"
        }
    }
}

enum AuthType: String, Codable, CaseIterable, Identifiable {
    case password = "PASSWORD"
    case key = "KEY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .password: return "密码"
        case .key: return "私钥"
        }
    }
}

// MARK: - 连接

struct Connection: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var host: String
    var port: Int = 22
    var username: String = ""
    var authType: AuthType = .password
    var password: String = ""
    var privateKey: String = ""
    var passphrase: String = ""
    var sudoPassword: String = ""
    var refreshSeconds: Int = 2
    var transport: Transport = .agent
    var agentPort: Int = 8765
    var agentToken: String = ""
    var agentTls: Bool = true
    var agentIntervalMs: Int = 500
    var allowSshFallback: Bool = true
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var lastUsedAt: Int64 = 0
    var agentFingerprint: String = ""
    var sshFingerprint: String = ""

    var address: String {
        transport == .agent ? "\(host):\(agentPort)" : "\(username)@\(host):\(port)"
    }

    var isKeyAuth: Bool { authType == .key }

    var hasSshCredentials: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        (!password.isEmpty || !privateKey.isEmpty)
    }

    var transportLabel: String { transport.label }

    /// 写入 UserDefaults 前去掉所有敏感字段，秘密只进 Keychain。
    func sanitized() -> Connection {
        var copy = self
        copy.password = ""
        copy.privateKey = ""
        copy.passphrase = ""
        copy.sudoPassword = ""
        copy.agentToken = ""
        copy.agentFingerprint = ""
        copy.sshFingerprint = ""
        return copy
    }
}

// MARK: - 主机与采样

struct HostInfo: Equatable {
    var hostname: String = ""
    var os: RemoteOS = .unknown
    var osLabel: String = ""
    var kernel: String = ""
    var cpuModel: String = ""
    var cores: Int = 0
    var totalMemBytes: Int64 = 0
    var gpuName: String?
    var gpuMemBytes: Int64 = 0
    var isRoot: Bool = false
    var agentVersion: String = ""

    var osShort: String { os.shortLabel }
}

struct DiskInfo: Identifiable, Equatable {
    var id: String { name + detail }
    var name: String
    var detail: String
    var totalBytes: Int64
    var usedBytes: Int64
    var percent: Double

    var freeBytes: Int64 { max(totalBytes - usedBytes, 0) }
}

struct Snapshot: Equatable {
    var timeMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var latencyMs: Int64 = 0
    var cpuPercent: Double = 0
    var perCore: [Double] = []
    var cpuSpeedMhz: Int?
    var memTotal: Int64 = 0
    var memUsed: Int64 = 0
    var memAvailable: Int64 = 0
    var memFree: Int64 = 0
    var memCached: Int64 = 0
    var memBuffers: Int64 = 0
    var memCommitted: Int64 = 0
    var commitLimit: Int64 = 0
    var swapTotal: Int64 = 0
    var swapUsed: Int64 = 0
    var poolPaged: Int64 = 0
    var poolNonPaged: Int64 = 0
    var disks: [DiskInfo] = []
    var netRxBps: Int64 = 0
    var netTxBps: Int64 = 0
    var netRxTotal: Int64 = 0
    var netTxTotal: Int64 = 0
    var gpuPercent: Double?
    var gpuName: String?
    var gpuMemBytes: Int64 = 0
    var uptimeSeconds: Int64 = 0
    var processCount: Int = 0
    var loadAverage: String?

    var memPercent: Double {
        guard memTotal > 0 else { return 0 }
        return min(max(Double(memUsed) / Double(memTotal) * 100, 0), 100)
    }

    var swapPercent: Double {
        guard swapTotal > 0 else { return 0 }
        return min(max(Double(swapUsed) / Double(swapTotal) * 100, 0), 100)
    }
}

struct ProcessInfo: Identifiable, Equatable, Hashable {
    var id: Int { pid }
    var pid: Int
    var name: String
    var user: String
    var cpuPercent: Double
    var memBytes: Int64
    var command: String = ""
}

struct ProcessSnapshot: Equatable {
    var items: [ProcessInfo] = []
    var totalCount: Int = 0
    var timeMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var note: String?
}

// MARK: - 清理

enum CleanupMode: String, CaseIterable, Identifiable {
    case linuxPage = "LINUX_PAGE"
    case linuxDentry = "LINUX_DENTRY"
    case linuxAll = "LINUX_ALL"
    case linuxDeep = "LINUX_DEEP"
    case windowsTrim = "WINDOWS_TRIM"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linuxPage: return "只释放页缓存"
        case .linuxDentry: return "只释放目录缓存"
        case .linuxAll: return "释放页缓存与目录缓存"
        case .linuxDeep: return "深度整理内存"
        case .windowsTrim: return "整理工作集"
        }
    }

    var subtitle: String {
        switch self {
        case .linuxPage: return "适合刚拷贝完大文件、内存暂时偏高的情况"
        case .linuxDentry: return "适合目录很多、文件索引占用较高的情况"
        case .linuxAll: return "最常用的组合，兼顾页缓存和目录缓存"
        case .linuxDeep: return "在组合清理之后再做一次内存紧凑"
        case .windowsTrim: return "让系统回收各进程暂时不用的工作集"
        }
    }

    static func modes(for os: RemoteOS) -> [CleanupMode] {
        os == .windows ? [.windowsTrim] : [.linuxAll, .linuxPage, .linuxDentry, .linuxDeep]
    }
}

struct CleanupResult: Equatable {
    var success: Bool = false
    var beforeBytes: Int64 = 0
    var afterBytes: Int64 = 0
    var metricLabel: String = "可用内存"
    var message: String = ""
    var log: String = ""
    var timeMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    var freedBytes: Int64 { max(afterBytes - beforeBytes, 0) }
}

// MARK: - 文件

struct RemoteFileEntry: Identifiable, Equatable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var isDir: Bool
    var sizeBytes: Int64 = 0
    var modifiedMs: Int64 = 0

    var systemIcon: String {
        if isDir { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "heic": return "photo"
        case "mp4", "mkv", "mov", "avi", "webm": return "play.rectangle"
        case "mp3", "wav", "flac", "m4a": return "music.note"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox"
        case "txt", "md", "log", "json", "xml", "yml", "yaml": return "doc.text"
        case "pdf": return "doc.richtext"
        case "exe", "msi", "bat", "cmd", "sh": return "gearshape"
        case "swift", "kt", "java", "py", "js", "ts", "go", "c", "cpp", "h": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}

struct RemoteListing: Equatable {
    var path: String
    var parent: String
    var entries: [RemoteFileEntry] = []
}

// MARK: - 配对

struct PairResult {
    var token: String
    var fingerprint: String
    var name: String
    var hostInfo: HostInfo?
    var port: Int
    var tls: Bool
}

// MARK: - 错误

enum PcMateError: LocalizedError {
    case message(String)
    case unauthorized
    case tlsFingerprintMismatch(expected: String, actual: String)
    case connectionClosed
    case timeout

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .unauthorized: return "配对凭证不正确，请在电脑上重新查看配对码"
        case .tlsFingerprintMismatch(let expected, let actual):
            return "证书指纹不一致，连接可能被劫持\n期望：\(expected)\n实际：\(actual)"
        case .connectionClosed: return "连接已断开，请重新连接"
        case .timeout: return "操作超时，请检查网络或电脑端 Agent"
        }
    }
}

// MARK: - 格式化

enum Fmt {
    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = Double(value)
        var i = 0
        while v >= 1024 && i < units.count - 1 {
            v /= 1024
            i += 1
        }
        let decimals = i == 0 ? 0 : (v >= 100 ? 0 : (v >= 10 ? 1 : 2))
        return String(format: "%.\(decimals)f %@", v, units[i] as NSString)
    }

    static func rate(_ value: Int64) -> String {
        bytes(value) + "/s"
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", min(max(value, 0), 100))
    }

    static func uptime(_ seconds: Int64) -> String {
        guard seconds > 0 else { return "—" }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分钟"
    }

    static func date(_ ms: Int64) -> String {
        guard ms > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    static func relative(_ ms: Int64) -> String {
        guard ms > 0 else { return "从未使用" }
        let seconds = Int64(Date().timeIntervalSince1970 - Double(ms) / 1000)
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(seconds / 60) 分钟前" }
        if seconds < 86400 { return "\(seconds / 3600) 小时前" }
        return "\(seconds / 86400) 天前"
    }
}

// MARK: - 路径工具

enum RemotePath {
    static func join(_ directory: String, _ name: String) -> String {
        guard !directory.isEmpty else { return name }
        if directory.hasSuffix("/") || directory.hasSuffix("\\") {
            return directory + name
        }
        // 只根据目录本身的分隔符判断：SFTP 的 C:/ 路径仍要用 /，不能因为盘符里的冒号就改成反斜杠。
        let separator = directory.contains("\\") ? "\\" : "/"
        return directory + separator + name
    }

    static func parent(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        if normalized == "/" { return "" }
        if normalized.count == 2, normalized.hasSuffix(":") { return "" }
        var comps = normalized.split(separator: "/").map(String.init)
        guard !comps.isEmpty else { return "" }
        comps.removeLast()
        if comps.isEmpty {
            return normalized.hasPrefix("/") ? "/" : ""
        }
        let joined = comps.joined(separator: "/")
        // Windows 盘符根目录保留末尾斜杠，避免 SFTP/Agent 把 "C:" 当成相对路径。
        if joined.count == 2, joined.hasSuffix(":") {
            return joined + (path.contains("\\") ? "\\" : "/")
        }
        if path.contains("\\") { return joined.replacingOccurrences(of: "/", with: "\\") }
        return normalized.hasPrefix("/") ? "/" + joined : joined
    }
}
