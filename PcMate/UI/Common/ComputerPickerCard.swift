import SwiftUI

// === 「当前电脑」选择卡（工具栏 / 首页共用）===
//
// 工具栏里的所有功能（进程、文件、打印、外网开关…）都作用在「当前电脑」上。
// 这个卡片负责选电脑、连接、断开，并把状态显示清楚。

struct ComputerPickerCard: View {

    @EnvironmentObject private var store: ConnectionStore
    @EnvironmentObject private var session: ComputerSession

    @State private var showAdd = false

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {

                HStack(alignment: .center, spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill((session.isConnected ? Aurora.teal : Aurora.brand).tint(0.13))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: session.isConnected ? "checkmark.circle" : "desktopcomputer")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(session.isConnected ? Aurora.teal : Aurora.brand)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前电脑")
                            .font(AuroraFont.titleMedium)
                            .foregroundStyle(Aurora.ink)
                        Text(statusLine)
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    StatusPill(
                        text: session.isConnected ? "已连接" : (session.connecting ? "连接中" : "未连接"),
                        color: session.isConnected ? Aurora.teal : (session.connecting ? Aurora.warning : Aurora.muted)
                    )
                }

                if store.connections.isEmpty {
                    Text("还没有配置电脑。先在电脑上装好 PcMate Agent，再用配对码添加。")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    picker
                }

                if let error = session.errorText {
                    AuroraBanner(systemIcon: "exclamationmark.triangle.fill", text: error, tone: Aurora.rose)
                }

                actions
            }
        }
        .sheet(isPresented: $showAdd) {
            ConnectionEditScreen(connection: nil)
        }
    }

    // MARK: 选择器

    private var picker: some View {
        Menu {
            ForEach(store.connections) { connection in
                Button {
                    session.select(connection)
                } label: {
                    if connection.id == session.selected?.id {
                        Label(connection.name, systemImage: "checkmark")
                    } else {
                        Text(connection.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Monogram(
                    name: session.selected?.name ?? "?",
                    tone: session.isConnected ? Aurora.teal : Aurora.brand,
                    size: 38
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.selected?.name ?? "选择一台电脑")
                        .font(AuroraFont.titleSmall)
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                    Text(session.selected?.address ?? "点这里切换")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Aurora.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Aurora.surfaceVariant)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: 按钮

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if session.isConnected {
                TonalButton(text: "重新连接", systemIcon: "arrow.clockwise", expands: true) {
                    Task { await session.reconnect() }
                }
                DangerTonalButton(text: "断开", systemIcon: "xmark.circle", expands: true) {
                    session.disconnect()
                }
            } else {
                PrimaryButton(
                    text: session.connecting ? "连接中…" : "连接电脑",
                    systemIcon: "bolt.horizontal.fill",
                    enabled: session.selected != nil && !session.connecting,
                    expands: true
                ) {
                    Task { await session.connect() }
                }
                TonalButton(text: "添加", systemIcon: "plus", expands: false) {
                    showAdd = true
                }
            }
        }
    }

    private var statusLine: String {
        if let selected = session.selected {
            if session.isConnected {
                let host = session.hostInfo?.hostname ?? selected.name
                return "已连接 \(host) · \(session.transportLabel)"
            }
            return "已选 \(selected.name) · 未连接"
        }
        return store.connections.isEmpty ? "需要先添加一台电脑" : "还没有选择电脑"
    }
}
