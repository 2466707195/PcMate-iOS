import SwiftUI

// MARK: - 工具栏

/// 工具栏里的每一项功能。
enum ToolRoute: String, Identifiable, CaseIterable {
    case info
    case processes
    case files
    case cleanup
    case network
    case power
    case print

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: return "电脑信息"
        case .processes: return "进程管理"
        case .files: return "文件传输"
        case .cleanup: return "内存清理"
        case .network: return "网络与外网"
        case .power: return "电源管理"
        case .print: return "打印"
        }
    }

    var subtitle: String {
        switch self {
        case .info: return "配置 · 硬件 · 实时状态"
        case .processes: return "看占用、结束进程"
        case .files: return "浏览、上传、下载"
        case .cleanup: return "释放缓存与工作集"
        case .network: return "开关电脑的外网访问"
        case .power: return "锁定 · 睡眠 · 关机"
        case .print: return "局域网打印机 + 电脑桥接"
        }
    }

    var icon: String {
        switch self {
        case .info: return "desktopcomputer"
        case .processes: return "list.bullet.rectangle"
        case .files: return "folder.fill"
        case .cleanup: return "sparkles"
        case .network: return "wifi"
        case .power: return "power"
        case .print: return "printer.fill"
        }
    }

    var tone: Color {
        switch self {
        case .info: return Aurora.brand
        case .processes: return Aurora.brand
        case .files: return Aurora.info
        case .cleanup: return Aurora.teal
        case .network: return Aurora.info
        case .power: return Aurora.rose
        case .print: return Aurora.teal
        }
    }

    /// 打印只走局域网/桥接端口，不需要 Agent 连接；其余功能都需要。
    var needsConnection: Bool { self != .print }
}

struct ToolsScreen: View {

    @EnvironmentObject private var store: ConnectionStore
    @EnvironmentObject private var session: ComputerSession

    @State private var route: ToolRoute?
    @State private var showComputers = false

    var body: some View {
        ZStack {
            AuroraBackdrop()

            AuroraScreen {
                // 顶部不画底色，只留右上角的透明电脑按钮
                TabHeaderBar(caption: statusCaption) { showComputers = true }
            } content: {
                AuroraScrollView(bottomInset: 118) {
                    toolGrid
                    footnote
                }
            } bar: {
                EmptyView()
            }
        }
        .sheet(isPresented: $showComputers) {
            ComputerListSheet()
        }
        .fullScreenCover(item: $route) { target in
            destination(for: target)
        }
    }

    // MARK: 功能宫格

    private var toolGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: AuroraMetrics.cardSpacing),
                GridItem(.flexible(), spacing: AuroraMetrics.cardSpacing)
            ],
            spacing: AuroraMetrics.cardSpacing
        ) {
            ForEach(ToolRoute.allCases) { tool in
                toolCard(tool)
            }
        }
        .padding(.top, 2)
    }

    private func toolCard(_ tool: ToolRoute) -> some View {
        let ready = isReady(tool)
        return Button {
            route = tool
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tool.tone.tint(0.13))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: tool.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(tool.tone)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.title)
                        .font(AuroraFont.titleSmall)
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                    Text(tool.subtitle)
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if tool.needsConnection && !ready {
                    Text("需要先连接")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.warning)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(AuroraMetrics.cardPadding)
            .background(
                AuroraShape.card
                    .fill(Aurora.surface)
                    .shadow(color: Aurora.cardShadow, radius: 4, x: 0, y: 1)
            )
            .overlay(
                AuroraShape.card.stroke(Aurora.line.opacity(0.55), lineWidth: 1)
            )
            .contentShape(AuroraShape.card)
        }
        .buttonStyle(PressScaleStyle())
    }

    private var footnote: some View {
        Text("提示：进程、文件、外网开关等需要电脑上运行 PcMate Agent 1.5.0 或更高版本；打印走局域网，无需连接也能用。")
            .font(AuroraFont.labelSmall)
            .foregroundStyle(Aurora.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }

    private func isReady(_ tool: ToolRoute) -> Bool {
        if tool == .print { return true }
        return session.isConnected
    }

    private var statusCaption: String {
        if session.isConnected { return session.displayName }
        if session.connecting { return "连接中…" }
        if let selected = session.selected { return "未连接 · \(selected.name)" }
        return "未选电脑"
    }

    // MARK: 目标页面

    @ViewBuilder
    private func destination(for tool: ToolRoute) -> some View {
        switch tool {
        case .print:
            PrintHomeScreen(onClose: { route = nil })

        case .info:
            if let connection = session.selected {
                DashboardScreen(connection: connection, store: store)
            } else {
                NeedsConnectionScreen(tool: tool)
            }

        case .processes:
            if let controller = session.controller {
                ProcessesScreen(session: controller)
            } else {
                NeedsConnectionScreen(tool: tool)
            }

        case .files:
            if let controller = session.controller {
                FilesScreen(session: controller)
            } else {
                NeedsConnectionScreen(tool: tool)
            }

        case .cleanup:
            if let controller = session.controller {
                CleanupScreen(session: controller, hostInfo: session.hostInfo)
            } else {
                NeedsConnectionScreen(tool: tool)
            }

        case .network:
            if let controller = session.controller {
                NetworkControlScreen(session: controller)
            } else {
                NeedsConnectionScreen(tool: tool)
            }

        case .power:
            if let controller = session.controller {
                PowerControlScreen(session: controller)
            } else {
                NeedsConnectionScreen(tool: tool)
            }
        }
    }
}

// MARK: - 未连接时的占位页

struct NeedsConnectionScreen: View {

    let tool: ToolRoute

    @EnvironmentObject private var session: ComputerSession
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false
    @State private var errorText: String?

    private var hasTarget: Bool { session.selected != nil }

    var body: some View {
        ZStack {
            AuroraBackdrop()
            AuroraScreen {
                AppTopBar(
                    title: tool.title,
                    subtitle: hasTarget ? session.displayName : "需要先选择电脑",
                    onBack: { dismiss() }
                )
            } content: {
                AuroraScrollView(bottomInset: 40) {
                    if let errorText {
                        AuroraBanner(
                            systemIcon: "exclamationmark.triangle.fill",
                            text: errorText,
                            tone: Aurora.rose
                        )
                    }
                    SectionCard {
                        EmptyStateView(
                            systemIcon: "bolt.horizontal.circle",
                            title: hasTarget ? "还没有连接电脑" : "还没有选择电脑",
                            message: hasTarget
                                ? "连上电脑后就能使用「\(tool.title)」，\n打印桥接会跟着一起就绪。"
                                : "先去「首页」添加或选择一台电脑，\n再回到这里连接。"
                        ) {
                            if hasTarget {
                                PrimaryButton(
                                    text: busy ? "连接中…" : "连接电脑",
                                    systemIcon: "bolt.horizontal.fill",
                                    enabled: !busy
                                ) {
                                    connect()
                                }
                                .fixedSize(horizontal: true, vertical: false)
                            } else {
                                PrimaryButton(text: "知道了", systemIcon: "checkmark") {
                                    dismiss()
                                }
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .padding(.vertical, 18)
                    }
                }
            } bar: {
                EmptyView()
            }
        }
    }

    private func connect() {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task { @MainActor in
            await session.connect()
            busy = false
            if session.isConnected {
                dismiss()
            } else {
                errorText = session.errorText ?? "连接失败，请回首页检查电脑配置。"
            }
        }
    }
}
