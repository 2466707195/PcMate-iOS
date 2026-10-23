import Foundation

// MARK: - 外网开关（Agent 1.5.0 起）
//
// 「外网开关」控制电脑能不能上公网：
//   开启 = 网卡走 DHCP（自动获取 IP + 网关），正常上网
//   关闭 = 保留当前 IP 与子网掩码，但把默认网关清空，局域网照旧、公网断开
//
// 这个能力依赖 Agent 在 Windows 上用 netsh 改网卡，因此需要管理员权限。

/// 一张网卡的外网相关状态。
struct NetModeAdapter: Identifiable, Equatable {

    var id: String { name }

    var name: String = ""
    var dhcp: Bool = false
    var ipv4: [String] = []
    var prefix: Int = 0
    var mask: String = ""
    var gateway: [String] = []
    var hasGateway: Bool = false
    var connected: Bool = false

    var ipLabel: String { ipv4.first ?? "—" }
    var gatewayLabel: String { gateway.first ?? "未设置" }
    var modeLabel: String { dhcp ? "自动获取（DHCP）" : "手动 IP" }
    var prefixLabel: String { prefix > 0 ? "/\(prefix) · \(mask)" : "—" }

    /// 有默认网关才可能访问外网。
    var internetEnabled: Bool { hasGateway }
}

/// 电脑当前的外网状态。
struct NetModeInfo: Equatable {

    var adapters: [NetModeAdapter] = []
    var externalEnabled: Bool = false
    var activeName: String = ""
    var admin: Bool = false
    var supported: Bool = true
    var note: String = ""

    /// 当前选中的网卡；没选中时退回第一张可用网卡。
    var active: NetModeAdapter? {
        adapters.first { $0.name == activeName } ?? adapters.first
    }

    /// 能上外网的网卡名（用于展示"外网已开启"）。
    var onlineNames: [String] {
        adapters.filter { $0.internetEnabled }.map(\.name)
    }
}
