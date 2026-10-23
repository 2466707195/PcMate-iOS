import SwiftUI

// MARK: - 网络与外网

/// 手动开关电脑的外网访问。
///
/// 关闭外网 = 把网卡从 DHCP 改成「手动 IP + 网关留空」，
/// 局域网（打印机、文件共享、Agent）照旧可用，但公网通道会被切断。
struct NetworkControlScreen: View {

    let session: SessionController

    @Environment(\.dismiss) private var dismiss

    @State private var info: NetModeInfo?
    @State private var selectedName: String = ""
    @State private var loading = false
    @State private var applying = false
    @State private var errorText: String?
    @State private var notice: String?

    var body: some View {
        ZStack {
            AuroraBackdrop()

            AuroraScreen {
                AppTopBar(title: "网络与外网", subtitle: subtitle, onBack: { dismiss() }) {
                    AuroraIconButton(
                        systemIcon: "arrow.clockwise",
                        enabled: !loading && !applying
                    ) {
                        Task { await load() }
                    }
                }
            } content: {
                AuroraScrollView(bottomInset: 40) {
                    if let errorText {
                        AuroraBanner(systemIcon: "exclamationmark.triangle.fill", text: errorText, tone: Aurora.rose)
                    }
                    if let notice {
                        AuroraBanner(systemIcon: "checkmark.circle.fill", text: notice, tone: Aurora.teal)
                    }

                    if info == nil {
                        loadingCard
                    } else {
                        switchCard
                        adapterCard
                    }
                }
            } bar: {
                EmptyView()
            }
        }
        .task { await load() }
    }

    // MARK: 外网开关

    @ViewBuilder
    private var switchCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {

                HStack(alignment: .center, spacing: 12) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill((externalEnabled ? Aurora.teal : Aurora.rose).tint(0.13))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: externalEnabled ? "globe.asia.australia.fill" : "globe.badge.chevron.backward")
                                .font(.system(size: 23, weight: .semibold))
                                .foregroundStyle(externalEnabled ? Aurora.teal : Aurora.rose)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(externalEnabled ? "外网访问已开启" : "外网访问已关闭")
                            .font(AuroraFont.titleLarge)
                            .foregroundStyle(Aurora.ink)
                        Text(externalEnabled
                             ? "网卡走自动获取（DHCP），电脑可以正常上网。"
                             : "网卡为手动 IP 且没有默认网关：局域网可用，公网不通。")
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    PrimaryButton(
                        text: "开启外网",
                        systemIcon: "checkmark.circle",
                        enabled: canApply && !externalEnabled,
                        expands: true
                    ) {
                        Task { await apply(true) }
                    }

                    DangerTonalButton(
                        text: "关闭外网",
                        systemIcon: "wifi.slash",
                        enabled: canApply && externalEnabled,
                        expands: true
                    ) {
                        Task { await apply(false) }
                    }
                }

                if applying {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在应用，网卡会重新获取地址，大约需要几秒…")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.inkSoft)
                    }
                }

                AuroraBanner(
                    systemIcon: "info.circle.fill",
                    text: "关闭外网只断开公网：Wi-Fi / 网线里的打印机、文件共享和 PcMate Agent 都不受影响。想恢复上网点「开启外网」即可。",
                    tone: Aurora.info
                )
            }
        }
    }

    // MARK: 网卡详情

    private var adapterCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {

                HStack(alignment: .center, spacing: 10) {
                    AuroraSectionHeader(
                        title: "网卡",
                        subtitle: "哪一张网卡要开/关外网",
                        systemIcon: "network",
                        trailingText: "\(adapters.count) 张"
                    )
                    Spacer(minLength: 0)
                    if adapters.count > 1 {
                        adapterMenu
                    }
                }

                if let adapter = activeAdapter {
                    VStack(spacing: 0) {
                        NetDetailRow(label: "名称", value: adapter.name)
                        Divider().overlay(Aurora.hairline)
                        NetDetailRow(label: "获取方式", value: adapter.modeLabel)
                        Divider().overlay(Aurora.hairline)
                        NetDetailRow(label: "IPv4", value: adapter.ipLabel)
                        Divider().overlay(Aurora.hairline)
                        NetDetailRow(label: "子网", value: adapter.prefixLabel)
                        Divider().overlay(Aurora.hairline)
                        NetDetailRow(label: "默认网关", value: adapter.gatewayLabel)
                    }
                } else {
                    Text("没有读到可用的网卡。")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                }

                if !admin {
                    AuroraBanner(
                        systemIcon: "lock.shield.fill",
                        text: "检测到 Agent 没有管理员权限，改网卡会失败。请把 PcMate Agent 安装成系统服务（以管理员身份运行 pcmate-agent --install），或右键「以管理员身份运行」。",
                        tone: Aurora.warning
                    )
                }

                if let note = info?.note, !note.isEmpty, errorText == nil {
                    Text(note)
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var adapterMenu: some View {
        Menu {
            ForEach(adapters) { adapter in
                Button {
                    selectedName = adapter.name
                } label: {
                    if adapter.name == activeAdapter?.name {
                        Label(adapter.name, systemImage: "checkmark")
                    } else {
                        Text(adapter.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(activeAdapter?.name ?? "选择")
                    .font(AuroraFont.labelMedium)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Aurora.brand)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Aurora.brand.tint(0.13)))
            .contentShape(Capsule())
        }
    }

    private var loadingCard: some View {
        SectionCard {
            if loading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在读取网卡状态…")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            } else if errorText != nil {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Aurora.rose)
                        Text("读不到电脑的网卡状态")
                            .font(AuroraFont.titleSmall)
                            .foregroundStyle(Aurora.ink)
                    }
                    Text("确认电脑上的 PcMate Agent 正在运行、并且是 1.5.0 或更高版本，然后重新读取一次。")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    TonalButton(text: "重新读取", systemIcon: "arrow.clockwise") {
                        Task { await load() }
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Aurora.muted)
                    Text("暂无数据，点右上角刷新")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: 数据

    private var adapters: [NetModeAdapter] { info?.adapters ?? [] }

    private var activeAdapter: NetModeAdapter? {
        adapters.first { $0.name == selectedName } ?? adapters.first
    }

    private var externalEnabled: Bool { info?.externalEnabled ?? false }

    private var admin: Bool { info?.admin ?? true }

    private var canApply: Bool {
        guard !applying, let adapter = activeAdapter else { return false }
        if externalEnabled { return true }
        // 关闭外网需要先把当前 IP 读出来（改成手动 IP 时要用）。
        return !adapter.ipv4.isEmpty
    }

    private var subtitle: String {
        guard let info else { return errorText == nil ? "读取中…" : "读取失败" }
        if !info.supported { return "当前电脑不支持" }
        return info.externalEnabled ? "外网已开启" : "外网已关闭"
    }

    /// 老版本 Agent 不认识 netmode 指令，翻译成「该升级了」，别把原始报错丢给用户。
    private func describe(_ error: Error) -> String {
        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("netmode") && (raw.contains("未知操作") || lower.contains("unknown")) {
            return "电脑上的 PcMate Agent 版本太旧，还不认识「外网开关」这条指令。把它升级到 1.5.0（桌面 PcMate-Agent-1.5.0 包，管理员运行 install），再点右上角刷新。"
        }
        return raw
    }

    private func load() async {
        loading = true
        errorText = nil
        do {
            let value = try await session.netMode()
            info = value
            if selectedName.isEmpty || !value.adapters.contains(where: { $0.name == selectedName }) {
                selectedName = value.activeName
            }
        } catch {
            errorText = describe(error)
        }
        loading = false
    }

    private func apply(_ enabled: Bool) async {
        guard let adapter = activeAdapter else { return }
        applying = true
        errorText = nil
        notice = nil
        do {
            let updated = try await session.setExternal(enabled, adapter: adapter.name)
            info = updated
            selectedName = adapter.name
            notice = updated.note.isEmpty
                ? (enabled ? "已开启外网访问。" : "已关闭外网访问。")
                : updated.note
        } catch {
            errorText = describe(error)
            applying = false
            await load()
            return
        }
        // 改网卡会重建 IP 配置，承载 Agent 的这条 WebSocket 很可能被一起拆掉：
        // 先把连接找回来，再把网卡的真实状态读回界面。
        await syncAfterApply(enabled: enabled, adapter: adapter.name)
        applying = false
    }

    /// 应用之后的自愈同步：轮询读回真实状态，连接断了就自动重连。
    private func syncAfterApply(enabled: Bool, adapter: String) async {
        var matched = false
        var latest: NetModeInfo?

        for attempt in 0..<8 {
            let delay: UInt64 = attempt == 0 ? 1_500_000_000 : 2_000_000_000
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { return }

            guard let value = await netModeAfterReconnect() else { continue }
            info = value
            latest = value
            if let target = value.adapters.first(where: { $0.name == adapter }),
               target.hasGateway == enabled {
                matched = true
                break
            }
        }

        if matched {
            notice = enabled
                ? "已开启外网：「\(adapter)」恢复自动获取 IP（DHCP）。"
                : "已关闭外网：「\(adapter)」改成手动 IP、默认网关已清空，局域网照旧。"
            return
        }

        // 8 次都没对上：要么电脑还没配置完，要么没改成功，明说。
        if let latest,
           let target = latest.adapters.first(where: { $0.name == adapter }),
           target.hasGateway != enabled {
            errorText = enabled
                ? "电脑那边「\(adapter)」还是没有网关，外网可能没开成功。稍后点右上角刷新确认。"
                : "电脑那边「\(adapter)」还带着默认网关，外网可能没关成功。稍后点右上角刷新确认。"
            return
        }
        notice = "指令已经发到电脑，网卡还在重新配置。稍等几秒点右上角刷新看看。"
    }

    /// 读网卡状态；连接被网卡重配置打断时自动重连一次。
    private func netModeAfterReconnect() async -> NetModeInfo? {
        do {
            return try await session.netMode()
        } catch {
            do {
                _ = try await session.connect()
                return try await session.netMode()
            } catch {
                return nil
            }
        }
    }
}

// MARK: - 详情行

private struct NetDetailRow: View {

    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(AuroraFont.bodyMedium)
                .foregroundStyle(Aurora.inkSoft)
            Spacer(minLength: 8)
            Text(value)
                .font(AuroraFont.bodyMedium)
                .foregroundStyle(Aurora.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
    }
}
