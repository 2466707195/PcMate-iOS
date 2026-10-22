import SwiftUI
import Foundation

struct DashboardScreen: View {

    let connection: Connection
    @StateObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss

    @State private var showProcesses = false
    @State private var showFiles = false
    @State private var showCleanup = false
    @State private var detail: DashboardDetail?

    init(connection: Connection, store: ConnectionStore) {
        self.connection = connection
        _model = StateObject(wrappedValue: DashboardModel(connection: connection, store: store))
    }

    var body: some View {
        ZStack {
            AuroraBackdrop()
            AuroraScreen {
                AppTopBar(
                    title: title,
                    subtitle: model.statusLine,
                    onBack: {
                        model.disconnect()
                        dismiss()
                    }
                ) {
                    HStack(spacing: 2) {
                        Button {
                            model.refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Aurora.brand)
                                .frame(width: 38, height: 38)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.isConnected)

                        Menu {
                            Button {
                                model.retry()
                            } label: {
                                Label("重新连接", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button {
                                showCleanup = true
                            } label: {
                                Label("清理内存", systemImage: "sparkles")
                            }
                            .disabled(!model.isConnected)
                            Button(role: .destructive) {
                                model.disconnect()
                                dismiss()
                            } label: {
                                Label("断开连接", systemImage: "xmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Aurora.inkSoft)
                                .frame(width: 38, height: 38)
                                .contentShape(Rectangle())
                        }
                    }
                }
            } content: {
                AuroraScrollView(bottomInset: 150) {
                    if model.connecting {
                        connectingCard
                    }

                    if let fallback = model.fallbackNotice {
                        banner(
                            icon: "arrow.triangle.swap",
                            text: fallback,
                            color: Aurora.warning,
                            background: Aurora.warningContainer
                        )
                    }

                    if let error = model.errorMessage {
                        if model.isConnected {
                            banner(
                                icon: "exclamationmark.triangle.fill",
                                text: error,
                                color: Aurora.rose,
                                background: Aurora.roseContainer
                            )
                        } else {
                            errorCard(error)
                        }
                    }

                    if let snapshot = model.snapshot {
                        statusHero(snapshot)
                        bigMetricGrid(snapshot)
                        smallMetricRow(snapshot)
                        diskCard(snapshot)
                        systemCard(snapshot)
                    } else if !model.connecting && model.errorMessage == nil {
                        loadingCard
                    }
                }
            } bar: {
                GlassBar {
                    HStack(spacing: 8) {
                        SmallTonalButton(text: "进程", systemIcon: "list.bullet.rectangle", expands: true) {
                            showProcesses = true
                        }
                        .disabled(!model.isConnected)

                        SmallTonalButton(text: "文件", systemIcon: "folder.fill", expands: true) {
                            showFiles = true
                        }
                        .disabled(!model.isConnected)

                        SmallTonalButton(text: "清理", systemIcon: "sparkles", expands: true) {
                            showCleanup = true
                        }
                        .disabled(!model.isConnected)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showProcesses) {
            ProcessesScreen(session: model.session)
        }
        .navigationDestination(isPresented: $showFiles) {
            FilesScreen(session: model.session)
        }
        .sheet(isPresented: $showCleanup) {
            CleanupScreen(session: model.session, hostInfo: model.hostInfo)
        }
        .sheet(item: $detail) { kind in
            DashboardDetailSheet(kind: kind, model: model) {
                detail = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showProcesses = true
                }
            }
        }
        .onAppear {
            Task { await model.start() }
        }
    }

    private var title: String {
        let hostname = model.hostInfo?.hostname.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return hostname.isEmpty ? connection.name : hostname
    }

    // MARK: 状态卡

    private func statusHero(_ snapshot: Snapshot) -> some View {
        SectionCard {
            HStack(alignment: .center, spacing: 12) {
                MetricRing(
                    title: "CPU",
                    value: snapshot.cpuPercent,
                    color: Aurora.brand,
                    centerText: Fmt.percent(snapshot.cpuPercent)
                )
                MetricRing(
                    title: "内存",
                    value: snapshot.memPercent,
                    color: Aurora.teal,
                    centerText: Fmt.percent(snapshot.memPercent)
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(model.hostInfo?.osLabel.isEmpty == false ? (model.hostInfo?.osLabel ?? "") : (model.hostInfo?.osShort ?? "电脑"))
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(2)
                    Text("\(model.hostInfo?.cores ?? 0) 核 · \(model.hostInfo?.cpuModel ?? "CPU")")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .lineLimit(2)

                    HStack(spacing: 5) {
                        StatusPill(text: "运行 \(Fmt.uptime(snapshot.uptimeSeconds))", color: Aurora.teal)
                        StatusPill(text: "\(snapshot.processCount) 进程", color: Aurora.brand)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // 上面四个大卡：处理器 / 内存 / 网络 / 显卡（2×2，等宽等高）
    private func bigMetricGrid(_ snapshot: Snapshot) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            MetricTile(
                title: "处理器",
                value: Fmt.percent(snapshot.cpuPercent),
                subtitle: snapshot.cpuSpeedMhz.map { "\($0) MHz" } ?? "实时占用",
                systemIcon: "cpu",
                color: Aurora.brand,
                sparkline: model.cpuHistory,
                onTap: { detail = .cpu }
            )
            MetricTile(
                title: "内存",
                value: Fmt.percent(snapshot.memPercent),
                subtitle: "\(Fmt.bytes(snapshot.memUsed)) / \(Fmt.bytes(snapshot.memTotal))",
                systemIcon: "memorychip",
                color: Aurora.teal,
                sparkline: model.memHistory,
                onTap: { detail = .memory }
            )
            MetricTile(
                title: "网络",
                value: Fmt.rate(snapshot.netRxBps),
                subtitle: "上传 \(Fmt.rate(snapshot.netTxBps))",
                systemIcon: "arrow.down.circle",
                color: Aurora.info,
                sparkline: model.rxHistory,
                onTap: { detail = .network }
            )
            MetricTile(
                title: "显卡",
                value: snapshot.gpuPercent.map { Fmt.percent($0) } ?? "—",
                subtitle: snapshot.gpuName ?? "未检测到独显",
                systemIcon: "display",
                color: Aurora.rose,
                sparkline: [],
                onTap: { detail = .gpu }
            )
        }
    }

    // 下面一行：运行时间 / 进程（等宽等高）
    private func smallMetricRow(_ snapshot: Snapshot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            MetricTile(
                title: "运行时间",
                value: Fmt.uptime(snapshot.uptimeSeconds),
                subtitle: snapshot.loadAverage.map { "负载 \($0)" } ?? "系统已运行",
                systemIcon: "clock",
                color: Aurora.success,
                sparkline: [],
                onTap: { detail = .uptime }
            )
            MetricTile(
                title: "进程",
                value: "\(snapshot.processCount)",
                subtitle: "当前运行进程",
                systemIcon: "list.bullet.rectangle",
                color: Aurora.warning,
                sparkline: [],
                onTap: { showProcesses = true }
            )
        }
    }

    private func diskCard(_ snapshot: Snapshot) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("磁盘")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                    Spacer()
                    Text("\(snapshot.disks.count) 个卷")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                }

                if snapshot.disks.isEmpty {
                    Text("没有读取到磁盘信息")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.muted)
                        .padding(.vertical, 6)
                } else {
                    ForEach(snapshot.disks) { disk in
                        DiskRow(disk: disk)
                    }
                }
            }
        }
    }

    private func systemCard(_ snapshot: Snapshot) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("系统信息")
                    .font(AuroraFont.titleMedium)
                    .foregroundStyle(Aurora.ink)
                    .padding(.bottom, 8)

                InfoRow(label: "主机名", value: model.hostInfo?.hostname ?? "—")
                InfoRow(label: "系统", value: model.hostInfo?.osLabel ?? model.hostInfo?.osShort ?? "—")
                InfoRow(label: "内核", value: model.hostInfo?.kernel ?? "—")
                InfoRow(label: "CPU", value: model.hostInfo?.cpuModel ?? "—")
                InfoRow(label: "内存", value: Fmt.bytes(snapshot.memTotal))
                if let gpu = snapshot.gpuName ?? model.hostInfo?.gpuName, !gpu.isEmpty {
                    InfoRow(label: "显卡", value: gpu)
                }
                InfoRow(label: "连接", value: model.session.transportLabel)
                if model.session.activeTransport == .agent {
                    InfoRow(label: "延迟", value: model.session.latencyLabel)
                }
                InfoRow(label: "刷新", value: model.lastUpdated.map { Fmt.date(Int64($0.timeIntervalSince1970 * 1000)) } ?? "—")
            }
        }
    }

    // MARK: 状态块

    private var connectingCard: some View {
        SectionCard {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(Aurora.brand)
                    .scaleEffect(1.15)
                VStack(alignment: .leading, spacing: 3) {
                    Text("正在连接 \(connection.name)")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                    Text(connection.transport == .agent ? "正在建立 WebSocket 并校验证书指纹…" : "正在建立 SSH 会话…")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
        }
    }

    private var loadingCard: some View {
        SectionCard {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Aurora.brand)
                Text("等待第一帧状态…")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.inkSoft)
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private func errorCard(_ error: String) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Aurora.roseContainer)
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(Aurora.rose)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("连接失败")
                            .font(AuroraFont.titleMedium)
                            .foregroundStyle(Aurora.ink)
                        Text("请确认电脑端 Agent 正在运行，且在同一局域网。")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.inkSoft)
                    }
                }
                Text(error)
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.rose)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Aurora.roseContainer.opacity(0.65)))

                HStack(spacing: 9) {
                    TonalButton(text: "重试", systemIcon: "arrow.clockwise") {
                        model.retry()
                    }
                    TextLinkButton(text: "返回") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func banner(icon: String, text: String, color: Color, background: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(background))
    }
}

// MARK: - 环形指标

private struct MetricRing: View {

    let title: String
    let value: Double
    let color: Color
    let centerText: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Aurora.line, lineWidth: 7)
            Circle()
                .trim(from: 0, to: min(max(value / 100, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(title)
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                Text(centerText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Aurora.ink)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }
            .padding(6)
        }
        .frame(width: 82, height: 82)
    }
}

// MARK: - 指标小卡

private struct MetricTile: View {

    /// 六个卡片统一高度：行与行、列与列都对齐。
    static let height: CGFloat = 128

    let title: String
    let value: String
    let subtitle: String
    let systemIcon: String
    let color: Color
    let sparkline: [Double]
    var onTap: (() -> Void)? = nil

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                        Text(value)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Aurora.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: systemIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 9).fill(color.tint(0.12)))
                }

                Spacer(minLength: 4)

                HStack(alignment: .center, spacing: 4) {
                    Text(subtitle)
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if onTap != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Aurora.muted.opacity(0.8))
                    }
                }

                if sparkline.count > 1 {
                    Sparkline(values: sparkline, color: color)
                        .frame(height: 20)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: MetricTile.height)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { onTap?() }
    }
}

// MARK: - 迷你折线

private struct Sparkline: View {

    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(values.max() ?? 1, 1)
            let minValue = min(values.min() ?? 0, maxValue)
            let span = max(maxValue - minValue, 0.001)
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let normalized = (value - minValue) / span
                    let y = proxy.size.height - CGFloat(normalized) * (proxy.size.height - 2) - 1
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - 磁盘行

private struct DiskRow: View {

    let disk: DiskInfo

    private var tone: Color {
        if disk.percent >= 85 { return Aurora.rose }
        if disk.percent >= 65 { return Aurora.warning }
        return Aurora.teal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(tone)
                Text(disk.name)
                    .font(AuroraFont.labelMedium)
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Fmt.bytes(disk.usedBytes)) / \(Fmt.bytes(disk.totalBytes))")
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.inkSoft)
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Aurora.surfaceVariant)
                    Capsule()
                        .fill(tone)
                        .frame(width: max(proxy.size.width * CGFloat(min(max(disk.percent, 0), 100) / 100), 3))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - 系统信息行

private struct InfoRow: View {

    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.muted)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Aurora.hairline)
                .frame(height: 1)
        }
    }
}
