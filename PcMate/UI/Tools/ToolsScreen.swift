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

    var body: some View {
        ZStack {
            AuroraBackdrop()

            AuroraScreen {
                AppTopBar(title: "工具栏", subtitle: session.isConnected ? session.displayName : "先选一台电脑") {
                    if session.isConnected {
                        StatusPill(text: "在线", color: Aurora.teal)
                    } else {
                        StatusPill(text: "离线", color: Aurora.muted)
                    }
                }
            } content: {
                AuroraScrollView(bottomInset: 118) {
                    ComputerPickerCard()
                    toolGrid
                    footnote
                }
            } bar: {
                EmptyView()
            }
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
                    .fill(Color.white)
                    .shadow(color: Aurora.cardShadow, radius: 4, x: 0, y: 1)
            )
            .overlay(
                AuroraShape.card.stroke(Aurora.line.opacity(0.55), lineWidth: 1)
            )
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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AuroraBackdrop()
            AuroraScreen {
                AppTopBar(title: tool.title, subtitle: "需要先连接电脑", onBack: { dismiss() })
            } content: {
                AuroraScrollView(bottomInset: 40) {
                    SectionCard {
                        EmptyStateView(
                            systemIcon: "bolt.horizontal.circle",
                            title: "还没有连接电脑",
                            message: "回到工具栏，选一台电脑并点「连接电脑」，\n然后就能使用「\(tool.title)」了。"
                        ) {
                            PrimaryButton(text: "知道了", systemIcon: "checkmark") {
                                dismiss()
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.vertical, 18)
                    }
                }
            } bar: {
                EmptyView()
            }
        }
    }
}
