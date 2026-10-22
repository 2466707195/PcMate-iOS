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
                        Button {
                            showAdd = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Aurora.brand)
                                .frame(width: AuroraMetrics.iconButtonSize, height: AuroraMetrics.iconButtonSize)
                                .background(Circle().fill(Aurora.brandContainer))
                        }
                        .buttonStyle(.plain)
                    }
                } content: {
                    AuroraScrollView(bottomInset: 150) {
                        hero
                        if store.connections.isEmpty {
                            emptyState
                        } else {
                            HStack {
                                Text("我的电脑")
                                    .font(AuroraFont.titleMedium)
                                    .foregroundStyle(Aurora.ink)
                                Spacer()
                                Text("\(store.connections.count) 台")
                                    .font(AuroraFont.labelMedium)
                                    .foregroundStyle(Aurora.inkSoft)
                            }
                            .padding(.top, 6)

                            ForEach(store.connections) { connection in
                                connectionCard(connection)
                            }
                        }
                    }
                } bar: {
                    GlassBar {
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

    // MARK: 顶部渐变卡

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Aurora.brandGradient)
                .shadow(color: Aurora.brand.opacity(0.22), radius: 14, x: 0, y: 7)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: 6, height: 6)
                        Text("局域网直连")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.16)))

                    Text("远程看电脑")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(Color.white)
                        .tracking(-0.6)

                    Text("实时状态 · 进程管理 · 文件传输")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Color.white.opacity(0.82))

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("证书指纹固定 · TOFU")
                            .font(AuroraFont.labelSmall)
                    }
                    .foregroundStyle(Color.white.opacity(0.82))
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)

                Image(systemName: "desktopcomputer")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.top, 4)
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
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
            HStack(spacing: 12) {
                Monogram(name: connection.name, tone: connection.transport == .agent ? Aurora.brand : Aurora.teal, size: 46)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(connection.name)
                            .font(AuroraFont.titleMedium)
                            .foregroundStyle(Aurora.ink)
                            .lineLimit(1)
                        if connection.transport == .agent && connection.agentToken.isEmpty {
                            Text("未配对")
                                .font(AuroraFont.labelSmall)
                                .foregroundStyle(Aurora.warning)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Aurora.warningContainer))
                        }
                    }
                    Text(connection.address)
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Text(connection.transportLabel)
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(connection.transport == .agent ? Aurora.brand : Aurora.teal)
                        Text("·")
                            .foregroundStyle(Aurora.muted)
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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
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
