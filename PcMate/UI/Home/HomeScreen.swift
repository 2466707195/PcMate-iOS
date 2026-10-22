import SwiftUI

struct HomeScreen: View {

    @EnvironmentObject private var store: ConnectionStore
    @State private var showAdd = false
    @State private var editing: Connection?
    @State private var deleteTarget: Connection?

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackdrop()
                AuroraScreen {
                    AppTopBar(title: "PcMate", subtitle: "把电脑装进口袋") {
                        AuroraIconButton(systemIcon: "plus") {
                            showAdd = true
                        }
                    }
                } content: {
                    AuroraScrollView(bottomInset: 172) {
                        hero
                        if store.connections.isEmpty {
                            emptyState
                        } else {
                            AuroraSectionHeader(
                                title: "我的电脑",
                                subtitle: "点卡片进入仪表盘",
                                systemIcon: "desktopcomputer",
                                trailingText: "\(store.connections.count) 台"
                            )
                            .padding(.top, 6)

                            ForEach(store.connections) { connection in
                                connectionCard(connection)
                            }
                        }
                    }
                } bar: {
                    GlassBar {
                        HStack(spacing: 8) {
                            Text(store.connections.isEmpty ? "还没有电脑" : "\(store.connections.count) 台电脑")
                                .font(AuroraFont.bodySmall)
                                .foregroundStyle(Aurora.inkSoft)
                            Spacer(minLength: 0)
                            StatusPill(text: "仅局域网", color: Aurora.teal)
                        }
                        Spacer().frame(height: 10)
                        PrimaryButton(
                            text: store.connections.isEmpty ? "添加第一台电脑" : "添加另一台电脑",
                            systemIcon: "plus"
                        ) {
                            showAdd = true
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Connection.self) { connection in
                DashboardScreen(connection: connection, store: store)
            }
        }
        .sheet(isPresented: $showAdd) {
            ConnectionEditScreen(connection: nil)
                .environmentObject(store)
        }
        .sheet(item: $editing) { connection in
            ConnectionEditScreen(connection: connection)
                .environmentObject(store)
        }
        .confirmationDialog(
            "删除这台电脑？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { target in
            Button("删除", role: .destructive) {
                store.delete(target)
                deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: { target in
            Text("将删除「\(target.name)」的连接信息和 Keychain 中的凭据。")
        }
    }

    // MARK: 顶部介绍卡

    private var hero: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Aurora.brandContainer)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundStyle(Aurora.brand)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("远程看电脑")
                            .font(AuroraFont.headlineSmall)
                            .foregroundStyle(Aurora.ink)
                            .tracking(-0.4)
                        Text("实时状态 · 进程管理 · 文件传输")
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                }

                HStack(spacing: 8) {
                    StatusPill(text: "局域网直连", color: Aurora.teal)
                    StatusPill(text: "证书固定", color: Aurora.brand)
                }

                HStack(spacing: 7) {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Aurora.brand)
                    Text("Agent 实时推送 · SSH 自动回退")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.inkSoft)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: 空状态

    private var emptyState: some View {
        SectionCard {
            EmptyStateView(
                systemIcon: "desktopcomputer",
                title: "还没有电脑",
                message: "在电脑上安装并启动 PcMate Agent，\n然后用 6 位配对码连接。"
            ) {
                TonalButton(text: "开始配对", systemIcon: "link") {
                    showAdd = true
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.vertical, 18)
        }
        .padding(.top, 6)
    }

    // MARK: 连接卡片

    private func connectionCard(_ connection: Connection) -> some View {
        NavigationLink(value: connection) {
            SectionCard {
                HStack(spacing: 12) {
                    Monogram(name: connection.name, tone: connection.transport == .agent ? Aurora.brand : Aurora.teal, size: 46)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(connection.name)
                                .font(AuroraFont.titleMedium)
                                .foregroundStyle(Aurora.ink)
                                .lineLimit(1)
                            if connection.transport == .agent && connection.agentToken.isEmpty {
                                StatusPill(text: "未配对", color: Aurora.warning)
                                    .allowsHitTesting(false)
                            }
                        }
                        Text(connection.address)
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.inkSoft)
                            .lineLimit(1)
                        HStack(spacing: 7) {
                            StatusPill(
                                text: connection.transportLabel,
                                color: connection.transport == .agent ? Aurora.brand : Aurora.teal
                            )
                            .allowsHitTesting(false)
                            Text(Fmt.relative(connection.lastUsedAt))
                                .font(AuroraFont.labelSmall)
                                .foregroundStyle(Aurora.muted)
                        }
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Aurora.muted)
                }
            }
        }
        .buttonStyle(PressScaleStyle())
        .contextMenu {
            Button {
                editing = connection
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteTarget = connection
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
