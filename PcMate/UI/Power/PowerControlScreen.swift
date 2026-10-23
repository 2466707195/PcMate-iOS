import SwiftUI

// MARK: - 电源管理

/// 远程控制电脑的电源：锁定 / 睡眠 / 关机 / 重启（Agent 1.3.0+）。
struct PowerControlScreen: View {

    let session: SessionController

    @Environment(\.dismiss) private var dismiss

    @State private var confirm: PowerAction?
    @State private var busy = false
    @State private var notice: String?
    @State private var errorText: String?

    private let columns = [
        GridItem(.flexible(), spacing: AuroraMetrics.cardSpacing),
        GridItem(.flexible(), spacing: AuroraMetrics.cardSpacing)
    ]

    var body: some View {
        ZStack {
            AuroraBackdrop()

            AuroraScreen {
                AppTopBar(title: "电源管理", subtitle: hostLabel, onBack: { dismiss() })
            } content: {
                AuroraScrollView(bottomInset: 40) {
                    if let errorText {
                        AuroraBanner(systemIcon: "exclamationmark.triangle.fill", text: errorText, tone: Aurora.rose)
                    }
                    if let notice {
                        AuroraBanner(systemIcon: "checkmark.circle.fill", text: notice, tone: Aurora.teal)
                    }

                    LazyVGrid(columns: columns, spacing: AuroraMetrics.cardSpacing) {
                        ForEach(PowerAction.allCases) { action in
                            actionCard(action)
                        }
                    }

                    AuroraBanner(
                        systemIcon: "exclamationmark.triangle.fill",
                        text: "关机和重启会让 Agent 停止响应：关机后需要有人到电脑前重新开机；重启一般一两分钟后能自动恢复连接。",
                        tone: Aurora.warning
                    )
                }
            } bar: {
                EmptyView()
            }
        }
        .confirmationDialog(
            confirm?.confirmTitle ?? "",
            isPresented: Binding(
                get: { confirm != nil },
                set: { if !$0 { confirm = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirm
        ) { action in
            Button(action.confirmButton, role: action.isDestructive ? .destructive : nil) {
                run(action)
            }
            Button("取消", role: .cancel) { confirm = nil }
        } message: { action in
            Text(action.detail)
        }
    }

    private func actionCard(_ action: PowerAction) -> some View {
        Button {
            confirm = action
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tone(action).tint(0.13))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: action.systemIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(tone(action))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(AuroraFont.titleSmall)
                        .foregroundStyle(Aurora.ink)
                    Text(action.detail)
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
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
        .disabled(busy)
        .opacity(busy ? 0.55 : 1)
    }

    private func tone(_ action: PowerAction) -> Color {
        action.isDestructive ? Aurora.rose : Aurora.brand
    }

    private var hostLabel: String {
        let hostname = session.hostInfo?.hostname.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !hostname.isEmpty { return hostname }
        return session.connection.name
    }

    private func run(_ action: PowerAction) {
        guard !busy else { return }
        confirm = nil
        busy = true
        errorText = nil
        notice = nil
        Task { @MainActor in
            do {
                notice = try await session.power(action)
            } catch {
                errorText = "操作失败：\(error.localizedDescription)"
            }
            busy = false
        }
    }
}
