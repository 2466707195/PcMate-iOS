import SwiftUI
import Foundation

// MARK: - 仪表盘详情面板

enum DashboardDetail: String, Identifiable {
    case cpu
    case memory
    case network
    case gpu
    case uptime
    case hardware

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "处理器"
        case .memory: return "内存"
        case .network: return "网络"
        case .gpu: return "显卡"
        case .uptime: return "运行时间"
        case .hardware: return "硬件信息"
        }
    }

    var subtitle: String {
        switch self {
        case .cpu: return "实时占用与每个核心"
        case .memory: return "占用明细与一键整理"
        case .network: return "流量、无线与蓝牙"
        case .gpu: return "显卡列表与驱动"
        case .uptime: return "开机时间与连接信息"
        case .hardware: return "主板、内存条、硬盘与电池"
        }
    }
}

struct DashboardDetailSheet: View {

    let kind: DashboardDetail
    @ObservedObject var model: DashboardModel
    var onOpenProcesses: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AuroraBackdrop()
            AuroraScreen {
                AppTopBar(title: kind.title, subtitle: kind.subtitle, onBack: { dismiss() }) {
                    EmptyView()
                }
            } content: {
                AuroraScrollView(bottomInset: 40) {
                    switch kind {
                    case .cpu:
                        CpuDetailView(model: model, onOpenProcesses: onOpenProcesses)
                    case .memory:
                        MemoryDetailView(model: model)
                    case .network:
                        NetworkDetailView(model: model)
                    case .gpu:
                        GpuDetailView(model: model)
                    case .uptime:
                        UptimeDetailView(model: model)
                    case .hardware:
                        HardwareDetailView(model: model)
                    }
                }
            } bar: {
                EmptyView()
            }
        }
    }
}

// MARK: - 处理器

private struct CpuDetailView: View {

    @ObservedObject var model: DashboardModel
    var onOpenProcesses: () -> Void

    var body: some View {
        VStack(spacing: AuroraMetrics.cardSpacing) {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(model.snapshot.map { Fmt.percent($0.cpuPercent) } ?? "—")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Aurora.ink)
                        Spacer(minLength: 0)
                        if let speed = model.snapshot?.cpuSpeedMhz {
                            StatusPill(text: "\(speed) MHz", color: Aurora.brand)
                        }
                    }
                    Text(model.hostInfo?.cpuModel ?? "未知处理器")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        StatusPill(text: "\(model.hostInfo?.cores ?? 0) 个逻辑核心", color: Aurora.teal)
                        if let load = model.snapshot?.loadAverage {
                            StatusPill(text: "负载 \(load)", color: Aurora.warning)
                        }
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("每个核心")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)

                    let cores = model.snapshot?.perCore ?? []
                    if cores.isEmpty {
                        Text("这台电脑没有上报每个核心的占用率。升级 Agent 到 1.2.0 后可见。")
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(Array(cores.enumerated()), id: \.offset) { index, value in
                            CoreUsageRow(index: index, percent: value)
                        }
                    }
                }
            }

            TonalButton(text: "查看占用最高的进程", systemIcon: "list.bullet.rectangle") {
                onOpenProcesses()
            }
        }
    }
}

private struct CoreUsageRow: View {

    let index: Int
    let percent: Double

    private var tone: Color {
        if percent >= 85 { return Aurora.rose }
        if percent >= 60 { return Aurora.warning }
        return Aurora.brand
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("核心 \(index + 1)")
                .font(AuroraFont.labelMedium)
                .foregroundStyle(Aurora.inkSoft)
                .frame(width: 62, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Aurora.surfaceVariant)
                    Capsule()
                        .fill(tone)
                        .frame(width: max(proxy.size.width * CGFloat(min(max(percent, 0), 100) / 100), 3))
                }
            }
            .frame(height: 8)

            Text(Fmt.percent(percent))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Aurora.inkSoft)
                .frame(width: 46, alignment: .trailing)
        }
    }
}

// MARK: - 内存

private struct MemoryDetailView: View {

    @ObservedObject var model: DashboardModel

    @State private var busy = false
    @State private var message: String?
    @State private var errorMessage: String?

    private var snapshot: Snapshot? { model.snapshot }

    private var cleanupMode: CleanupMode {
        if model.hostInfo?.os == .windows { return .windowsTrim }
        return .linuxAll
    }

    var body: some View {
        VStack(spacing: AuroraMetrics.cardSpacing) {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(snapshot.map { Fmt.percent($0.memPercent) } ?? "—")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Aurora.ink)
                        Spacer(minLength: 0)
                        if let snapshot {
                            StatusPill(text: "\(Fmt.bytes(snapshot.memUsed)) / \(Fmt.bytes(snapshot.memTotal))", color: Aurora.teal)
                        }
                    }
                    if let snapshot {
                        ProgressBar(value: snapshot.memPercent, color: Aurora.teal)
                        HStack(spacing: 6) {
                            StatusPill(text: "可用 \(Fmt.bytes(snapshot.memAvailable))", color: Aurora.brand)
                            if snapshot.swapTotal > 0 {
                                StatusPill(text: "交换 \(Fmt.bytes(snapshot.swapUsed))", color: Aurora.warning)
                            }
                        }
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 0) {
                    Text("占用明细")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                        .padding(.bottom, 6)

                    DetailRow(label: "已用", value: snapshot.map { Fmt.bytes($0.memUsed) } ?? "—")
                    DetailRow(label: "可用", value: snapshot.map { Fmt.bytes($0.memAvailable) } ?? "—")
                    DetailRow(label: "空闲", value: snapshot.map { Fmt.bytes($0.memFree) } ?? "—")
                    DetailRow(label: "缓存", value: snapshot.map { Fmt.bytes($0.memCached) } ?? "—")
                    if let buffers = snapshot?.memBuffers, buffers > 0 {
                        DetailRow(label: "缓冲区", value: Fmt.bytes(buffers))
                    }
                    DetailRow(label: "已提交", value: snapshot.map { Fmt.bytes($0.memCommitted) } ?? "—")
                    DetailRow(label: "提交上限", value: snapshot.map { Fmt.bytes($0.commitLimit) } ?? "—")
                    if let snapshot, snapshot.swapTotal > 0 {
                        DetailRow(label: "交换区", value: "\(Fmt.bytes(snapshot.swapUsed)) / \(Fmt.bytes(snapshot.swapTotal))")
                    }
                    if let paged = snapshot?.poolPaged, paged > 0 {
                        DetailRow(label: "分页池", value: Fmt.bytes(paged))
                    }
                    if let nonPaged = snapshot?.poolNonPaged, nonPaged > 0 {
                        DetailRow(label: "非分页池", value: Fmt.bytes(nonPaged))
                    }
                    DetailRow(label: "总量", value: snapshot.map { Fmt.bytes($0.memTotal) } ?? "—", showsDivider: false)
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("整理内存")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                    Text(cleanupHint)
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    if let message {
                        DetailBanner(text: message, color: Aurora.success, background: Aurora.successContainer)
                    }
                    if let errorMessage {
                        DetailBanner(text: errorMessage, color: Aurora.rose, background: Aurora.roseContainer)
                    }

                    PrimaryButton(
                        text: busy ? "正在整理…" : "立即整理内存",
                        systemIcon: "sparkles",
                        enabled: !busy
                    ) {
                        runCleanup()
                    }
                }
            }
        }
    }

    private var cleanupHint: String {
        if cleanupMode == .windowsTrim {
            return "Windows 上会把各进程的工作集还给系统，能立刻降低「已用内存」。部分受保护进程会被跳过，属正常现象。"
        }
        return "Linux 上会释放页缓存与目录缓存，不影响正在运行的程序。"
    }

    private func runCleanup() {
        guard !busy else { return }
        busy = true
        message = nil
        errorMessage = nil
        Task { @MainActor in
            do {
                let result = try await model.session.cleanup(mode: cleanupMode)
                message = result.message.isEmpty ? "内存已整理" : result.message
                model.refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: - 网络

private struct NetworkDetailView: View {

    @ObservedObject var model: DashboardModel

    @State private var info: NetInfoDetail?
    @State private var loading = false
    @State private var errorMessage: String?

    private var snapshot: Snapshot? { model.snapshot }

    var body: some View {
        VStack(spacing: AuroraMetrics.cardSpacing) {
            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("实时流量")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                    HStack(spacing: 10) {
                        RateBlock(title: "下载", value: snapshot.map { Fmt.rate($0.netRxBps) } ?? "—", color: Aurora.brand)
                        RateBlock(title: "上传", value: snapshot.map { Fmt.rate($0.netTxBps) } ?? "—", color: Aurora.info)
                    }
                    DetailRow(label: "累计下载", value: snapshot.map { Fmt.bytes($0.netRxTotal) } ?? "—")
                    DetailRow(label: "累计上传", value: snapshot.map { Fmt.bytes($0.netTxTotal) } ?? "—")
                    DetailRow(label: "连接延迟", value: model.session.latencyLabel, showsDivider: false)
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("网络接口")
                            .font(AuroraFont.titleMedium)
                            .foregroundStyle(Aurora.ink)
                        Spacer()
                        if loading {
                            ProgressView().tint(Aurora.brand)
                        }
                    }

                    if let errorMessage {
                        DetailBanner(
                            text: errorMessage + "\n网络详情需要 PcMate Agent 1.2.0 及以上版本。",
                            color: Aurora.rose,
                            background: Aurora.roseContainer
                        )
                    }

                    let adapters = info?.adapters ?? []
                    if adapters.isEmpty && errorMessage == nil {
                        Text(loading ? "正在读取网卡…" : "没有读取到网卡信息")
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.muted)
                    } else {
                        ForEach(adapters) { adapter in
                            AdapterRow(adapter: adapter)
                        }
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Wi-Fi")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)

                    if let wifi = info?.wifi, wifi.isConnected {
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(wifi.ssid)
                                    .font(AuroraFont.titleMedium)
                                    .foregroundStyle(Aurora.ink)
                                    .lineLimit(1)
                                Text(wifi.band.isEmpty ? "已连接" : "已连接 · \(wifi.band)")
                                    .font(AuroraFont.labelSmall)
                                    .foregroundStyle(Aurora.inkSoft)
                            }
                            Spacer(minLength: 0)
                            StatusPill(text: "信号 \(wifi.signalPercent)%", color: wifi.signalPercent >= 55 ? Aurora.success : Aurora.warning)
                        }
                        DetailRow(label: "BSSID", value: wifi.bssid.isEmpty ? "—" : wifi.bssid)
                        DetailRow(label: "信道", value: wifi.channel.isEmpty ? "—" : wifi.channel)
                        DetailRow(label: "协议", value: wifi.radio.isEmpty ? "—" : wifi.radio)
                        DetailRow(label: "接收速率", value: wifi.rxRate.isEmpty ? "—" : wifi.rxRate)
                        DetailRow(label: "发送速率", value: wifi.txRate.isEmpty ? "—" : wifi.txRate, showsDivider: false)
                    } else {
                        Text(info == nil && loading ? "正在读取无线状态…" : "未连接 Wi-Fi，或这台电脑没有无线网卡")
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("蓝牙")
                            .font(AuroraFont.titleMedium)
                            .foregroundStyle(Aurora.ink)
                        Spacer()
                        Text("\(info?.bluetooth.filter { $0.connected }.count ?? 0) 个已连接")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                    }

                    let devices = info?.bluetooth ?? []
                    if devices.isEmpty {
                        Text(info == nil && loading ? "正在读取蓝牙设备…" : "没有发现已配对的蓝牙设备")
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.muted)
                    } else {
                        ForEach(devices) { device in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(device.connected ? Aurora.success : Aurora.muted)
                                    .frame(width: 7, height: 7)
                                Text(device.name)
                                    .font(AuroraFont.bodySmall)
                                    .foregroundStyle(Aurora.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(device.connected ? "已连接" : "未连接")
                                    .font(AuroraFont.labelSmall)
                                    .foregroundStyle(device.connected ? Aurora.success : Aurora.muted)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    if let note = info?.note, !note.isEmpty {
                        Text(note)
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                    }
                }
            }

            TonalButton(text: "刷新网络详情", systemIcon: "arrow.clockwise", enabled: !loading) {
                Task { await load() }
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard !loading else { return }
        loading = true
        errorMessage = nil
        do {
            info = try await model.session.netInfo()
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}

private struct RateBlock: View {

    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AuroraFont.labelSmall)
                .foregroundStyle(Aurora.muted)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(color.tint(0.1)))
    }
}

private struct AdapterRow: View {

    let adapter: NetAdapterInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: adapter.up ? "wifi" : "wifi.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(adapter.up ? Aurora.teal : Aurora.muted)
                Text(adapter.name)
                    .font(AuroraFont.labelMedium)
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(adapter.up ? "已连接" : "未启用")
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(adapter.up ? Aurora.teal : Aurora.muted)
            }
            if !adapter.ipv4.isEmpty {
                Text(adapter.ipv4.joined(separator: "  ·  "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Aurora.inkSoft)
            }
            if !adapter.mac.isEmpty {
                Text(adapter.mac)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Aurora.muted)
            }
        }
        .padding(.vertical, 5)
    }
}

// MARK: - 显卡

private struct GpuDetailView: View {

    @ObservedObject var model: DashboardModel

    @State private var list: [GpuDetail] = []
    @State private var loading = false
    @State private var errorMessage: String?

    private var snapshot: Snapshot? { model.snapshot }

    private var gpuPercentText: String {
        guard let value = snapshot?.gpuPercent else { return "—" }
        return Fmt.percent(value)
    }

    var body: some View {
        VStack(spacing: AuroraMetrics.cardSpacing) {
            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("当前占用")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(gpuPercentText)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Aurora.ink)
                        Spacer(minLength: 0)
                        if let mem = snapshot?.gpuMemBytes, mem > 0 {
                            StatusPill(text: Fmt.bytes(mem), color: Aurora.rose)
                        }
                    }
                    Text(snapshot?.gpuName ?? model.hostInfo?.gpuName ?? "未检测到显卡")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if snapshot?.gpuPercent == nil {
                        Text("这张显卡不提供实时占用率（占用率目前只支持 NVIDIA 显卡）。")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("显卡列表")
                            .font(AuroraFont.titleMedium)
                            .foregroundStyle(Aurora.ink)
                        Spacer()
                        if loading {
                            ProgressView().tint(Aurora.brand)
                        }
                    }

                    if let errorMessage {
                        DetailBanner(
                            text: errorMessage + "\n显卡列表需要 PcMate Agent 1.2.0 及以上版本。",
                            color: Aurora.rose,
                            background: Aurora.roseContainer
                        )
                    }

                    if list.isEmpty && errorMessage == nil {
                        Text(loading ? "正在读取显卡…" : "没有读取到显卡信息")
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.muted)
                    } else {
                        ForEach(list) { gpu in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(gpu.name)
                                    .font(AuroraFont.labelMedium)
                                    .foregroundStyle(Aurora.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(detailLine(gpu))
                                    .font(AuroraFont.labelSmall)
                                    .foregroundStyle(Aurora.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
            }

            TonalButton(text: "刷新显卡信息", systemIcon: "arrow.clockwise", enabled: !loading) {
                Task { await load() }
            }
        }
        .task { await load() }
    }

    private func detailLine(_ gpu: GpuDetail) -> String {
        var parts: [String] = []
        if !gpu.vendor.isEmpty { parts.append(gpu.vendor) }
        if gpu.memBytes > 0 { parts.append("显存 \(Fmt.bytes(gpu.memBytes))") }
        if !gpu.driver.isEmpty { parts.append("驱动 \(gpu.driver)") }
        if !gpu.status.isEmpty { parts.append(gpu.status) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    @MainActor
    private func load() async {
        guard !loading else { return }
        loading = true
        errorMessage = nil
        do {
            list = try await model.session.gpuInfo()
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - 运行时间

private struct UptimeDetailView: View {

    @ObservedObject var model: DashboardModel

    @State private var sysInfo: RemoteSysInfo?
    @State private var loading = false

    private var snapshot: Snapshot? { model.snapshot }

    private var bootTimeText: String {
        if let sysInfo, sysInfo.bootTimeSec > 0 {
            return Fmt.date(sysInfo.bootTimeSec * 1000)
        }
        guard let snapshot, snapshot.uptimeSeconds > 0 else { return "—" }
        let boot = Int64(Date().timeIntervalSince1970) - snapshot.uptimeSeconds
        return Fmt.date(boot * 1000)
    }

    var body: some View {
        VStack(spacing: AuroraMetrics.cardSpacing) {
            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(snapshot.map { Fmt.uptime($0.uptimeSeconds) } ?? "—")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Aurora.ink)
                    Text("系统已连续运行")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                    HStack(spacing: 6) {
                        if loading {
                            StatusPill(text: "正在读取…", color: Aurora.muted)
                        } else {
                            StatusPill(text: "开机于 \(bootTimeText)", color: Aurora.teal)
                        }
                        if let load = snapshot?.loadAverage {
                            StatusPill(text: "负载 \(load)", color: Aurora.warning)
                        }
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 0) {
                    Text("系统与连接")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                        .padding(.bottom, 6)

                    DetailRow(label: "主机名", value: model.hostInfo?.hostname ?? "—")
                    DetailRow(label: "系统", value: model.hostInfo?.osLabel ?? model.hostInfo?.osShort ?? "—")
                    DetailRow(label: "内核", value: model.hostInfo?.kernel ?? "—")
                    DetailRow(label: "处理器", value: model.hostInfo?.cpuModel ?? "—")
                    DetailRow(label: "内存", value: snapshot.map { Fmt.bytes($0.memTotal) } ?? "—")
                    DetailRow(label: "Agent", value: agentVersionText)
                    DetailRow(label: "连接", value: model.session.transportLabel)
                    if model.session.activeTransport == .agent {
                        DetailRow(label: "延迟", value: model.session.latencyLabel)
                    }
                    DetailRow(label: "最后刷新", value: model.lastUpdated.map { Fmt.date(Int64($0.timeIntervalSince1970 * 1000)) } ?? "—", showsDivider: false)
                }
            }

            TonalButton(text: "重新连接", systemIcon: "arrow.triangle.2.circlepath") {
                model.retry()
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        loading = true
        sysInfo = try? await model.session.sysInfo()
        loading = false
    }

    private var agentVersionText: String {
        if let version = sysInfo?.agentVersion, !version.isEmpty { return version }
        if let version = model.hostInfo?.agentVersion, !version.isEmpty { return version }
        return "—"
    }
}

// MARK: - 硬件信息

private struct HardwareDetailView: View {

    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(spacing: AuroraMetrics.cardSpacing) {
            if let hardware = model.hardware, hardware.hasAnyData {
                overviewCard(hardware)
                memoryCard(hardware)
                diskCard(hardware)
                if !hardware.gpus.isEmpty {
                    gpuCard(hardware)
                }
            } else {
                SectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            if model.hardwareLoading {
                                ProgressView().tint(Aurora.brand)
                            }
                            Text(model.hardwareLoading ? "正在读取硬件信息…" : "还没有读到硬件信息")
                                .font(AuroraFont.bodySmall)
                                .foregroundStyle(Aurora.inkSoft)
                        }
                        if let error = model.hardwareError {
                            DetailBanner(
                                text: error + "\n硬件信息需要 PcMate Agent 1.4.0 及以上版本。",
                                color: Aurora.rose,
                                background: Aurora.roseContainer
                            )
                        }
                    }
                }
            }

            TonalButton(
                text: "刷新硬件信息",
                systemIcon: "arrow.clockwise",
                enabled: !model.hardwareLoading
            ) {
                Task { await model.loadHardware(force: true) }
            }
        }
        .task { await model.loadHardware() }
    }

    private func overviewCard(_ hardware: HardwareSummary) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(hardware.machineName)
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let battery = hardware.battery {
                        StatusPill(
                            text: "电池 \(battery.percent)%",
                            color: battery.percent >= 30 ? Aurora.success : Aurora.warning
                        )
                    }
                }
                .padding(.bottom, 6)

                if let battery = hardware.battery {
                    let text = battery.status.isEmpty ? battery.name : "\(battery.name) · \(battery.status)"
                    if !text.isEmpty {
                        Text(text)
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.inkSoft)
                            .padding(.bottom, 4)
                    }
                }

                DetailRow(label: "制造商", value: hardware.systemManufacturer.isEmpty ? "—" : hardware.systemManufacturer)
                DetailRow(label: "型号", value: hardware.systemModel.isEmpty ? "—" : hardware.systemModel)
                if !hardware.systemSerial.isEmpty {
                    DetailRow(label: "序列号", value: hardware.systemSerial)
                }
                DetailRow(label: "主板", value: hardware.boardName.isEmpty ? "—" : hardware.boardName)
                if !hardware.boardVersion.isEmpty {
                    DetailRow(label: "主板版本", value: hardware.boardVersion)
                }
                if !hardware.boardSerial.isEmpty {
                    DetailRow(label: "主板序列", value: hardware.boardSerial)
                }
                DetailRow(label: "BIOS", value: biosText(hardware))
                DetailRow(label: "BIOS 日期", value: hardware.biosDate.isEmpty ? "—" : hardware.biosDate)
                DetailRow(label: "处理器", value: model.hostInfo?.cpuModel ?? "—")
                DetailRow(
                    label: "内存",
                    value: hardware.memoryTotalBytes > 0 ? Fmt.bytes(hardware.memoryTotalBytes) : "—",
                    showsDivider: false
                )
            }
        }
    }

    private func memoryCard(_ hardware: HardwareSummary) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("内存条")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                    Spacer(minLength: 0)
                    Text(hardware.memoryTotalBytes > 0 ? "\(hardware.memory.count) 条 · \(Fmt.bytes(hardware.memoryTotalBytes))" : "\(hardware.memory.count) 条")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                }

                if hardware.memory.isEmpty {
                    Text("没有读取到内存条信息（Linux 需要安装 dmidecode，部分虚拟机也不提供）。")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(hardware.memory) { module in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "memorychip")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Aurora.teal)
                                Text(module.slot.isEmpty ? "内存插槽" : module.slot)
                                    .font(AuroraFont.labelMedium)
                                    .foregroundStyle(Aurora.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(Fmt.bytes(module.sizeBytes))
                                    .font(AuroraFont.labelMedium)
                                    .foregroundStyle(Aurora.ink)
                            }
                            Text(memoryDetail(module))
                                .font(AuroraFont.labelSmall)
                                .foregroundStyle(Aurora.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    private func diskCard(_ hardware: HardwareSummary) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("硬盘")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                    Spacer(minLength: 0)
                    Text("\(hardware.disks.count) 块")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                }

                if hardware.disks.isEmpty {
                    Text("没有读取到物理硬盘信息。")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.muted)
                } else {
                    ForEach(hardware.disks) { disk in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "internaldrive.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Aurora.brand)
                                Text(disk.name.isEmpty ? "未知硬盘" : disk.name)
                                    .font(AuroraFont.labelMedium)
                                    .foregroundStyle(Aurora.ink)
                                    .lineLimit(2)
                                Spacer(minLength: 4)
                                Text(Fmt.bytes(disk.sizeBytes))
                                    .font(AuroraFont.labelMedium)
                                    .foregroundStyle(Aurora.ink)
                            }
                            HStack(spacing: 6) {
                                if !disk.media.isEmpty {
                                    StatusPill(text: disk.media, color: Aurora.brand)
                                }
                                if !disk.interfaceName.isEmpty {
                                    StatusPill(text: disk.interfaceName, color: Aurora.teal)
                                }
                                if !disk.health.isEmpty {
                                    StatusPill(text: disk.health, color: healthColor(disk.health))
                                }
                            }
                            if !disk.serial.isEmpty {
                                Text("序列号 \(disk.serial)")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Aurora.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    private func gpuCard(_ hardware: HardwareSummary) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("显卡")
                    .font(AuroraFont.titleMedium)
                    .foregroundStyle(Aurora.ink)

                ForEach(hardware.gpus) { gpu in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gpu.name)
                            .font(AuroraFont.labelMedium)
                            .foregroundStyle(Aurora.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(gpuDetail(gpu))
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private func biosText(_ hardware: HardwareSummary) -> String {
        let parts = [hardware.biosVendor, hardware.biosVersion].filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    private func memoryDetail(_ module: HardwareMemoryModule) -> String {
        var parts: [String] = []
        if module.speedMhz > 0 { parts.append("\(module.speedMhz) MHz") }
        if !module.manufacturer.isEmpty { parts.append(module.manufacturer) }
        if !module.partNumber.isEmpty { parts.append(module.partNumber) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func gpuDetail(_ gpu: GpuDetail) -> String {
        var parts: [String] = []
        if !gpu.vendor.isEmpty { parts.append(gpu.vendor) }
        if gpu.memBytes > 0 { parts.append("显存 \(Fmt.bytes(gpu.memBytes))") }
        if !gpu.driver.isEmpty { parts.append("驱动 \(gpu.driver)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func healthColor(_ health: String) -> Color {
        let lower = health.lowercased()
        if lower.contains("unhealthy") || lower.contains("warning") { return Aurora.rose }
        if lower.contains("healthy") || lower.contains("ok") { return Aurora.success }
        return Aurora.muted
    }
}

// MARK: - 复用小组件

private struct DetailRow: View {

    let label: String
    let value: String
    var showsDivider: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.muted)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Aurora.hairline)
                    .frame(height: 1)
            }
        }
    }
}

private struct DetailBanner: View {

    let text: String
    let color: Color
    let background: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(background))
    }
}

private struct ProgressBar: View {

    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Aurora.surfaceVariant)
                Capsule()
                    .fill(color)
                    .frame(width: max(proxy.size.width * CGFloat(min(max(value, 0), 100) / 100), 3))
            }
        }
        .frame(height: 8)
    }
}
