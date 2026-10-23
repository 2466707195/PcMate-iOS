import SwiftUI

/// 「我的电脑」列表：首页右上角的电脑图标点开就是它。
///
/// - 点一行：选中并连接（不用再去别的地方点第二次）
/// - 长按：打开仪表盘 / 连接 / 编辑 / 删除
struct ComputerListSheet: View {

    var onOpenDashboard: (Connection) -> Void = { _ in }

    @EnvironmentObject private var store: ConnectionStore
    @EnvironmentObject private var session: ComputerSession
    @Environment(\.dismiss) private var dismiss

    @State private var showAdd = false
    @State private var editing: Connection?
    @State private var deleteTarget: Connection?

    var body: some View {
        ZStack {
            AuroraBackdrop()

            VStack(spacing: 0) {
                header

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if store.connections.isEmpty {
                            emptyCard
                        } else {
                            ForEach(store.connections) { connection in
                                row(connection)
                            }

                            TonalButton(text: "添加一台新电脑", systemIcon: "plus") {
                                showAdd = true
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, AuroraMetrics.pagePadding)
                    .padding(.top, 2)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showAdd) {
            ConnectionEditScreen(connection: nil)
        }
        .sheet(item: $editing) { connection in
            ConnectionEditScreen(connection: connection)
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
                session.refreshSelection()
                deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: { target in
            Text("将删除「\(target.name)」的连接信息和 Keychain 中的凭据。")
        }
    }

    // MARK: 页头

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Aurora.brand.tint(0.10))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Aurora.brand)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("我的电脑")
                    .font(AuroraFont.titleLarge)
                    .foregroundStyle(Aurora.ink)
                Text(headerSubtitle)
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            AuroraIconButton(systemIcon: "xmark", tone: Aurora.inkSoft, size: 34) {
                dismiss()
            }
        }
        .padding(.horizontal, AuroraMetrics.pagePadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var headerSubtitle: String {
        if session.isConnected { return "已连接 \(session.displayName) · 点一行切换" }
        if store.connections.isEmpty { return "还没有添加过电脑" }
        return "\(store.connections.count) 台 · 点一下就连接"
    }

    // MARK: 空状态

    private var emptyCard: some View {
        SectionCard {
            EmptyStateView(
                systemIcon: "desktopcomputer",
                title: "还没有电脑",
                message: "在电脑上装好并启动 PcMate Agent，\n再用 6 位配对码添加。"
            ) {
                TonalButton(text: "添加电脑", systemIcon: "plus") {
                    showAdd = true
                }
            }
            .padding(.vertical, 14)
        }
    }

    // MARK: 行

    private func row(_ connection: Connection) -> some View {
        let isCurrent = connection.id == session.selected?.id
        let live = isCurrent && session.isConnected
        let connecting = isCurrent && session.connecting

        return Button {
            session.select(connection)
            dismiss()
            Task { await session.connect() }
        } label: {
            SectionCard {
                HStack(spacing: 12) {
                    Monogram(
                        name: connection.name,
                        tone: connection.transport == .agent ? Aurora.brand : Aurora.teal,
                        size: 44
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(connection.name)
                                .font(AuroraFont.titleMedium)
                                .foregroundStyle(Aurora.ink)
                                .lineLimit(1)

                            if live {
                                StatusPill(text: "已连接", color: Aurora.teal)
                            } else if connecting {
                                StatusPill(text: "连接中", color: Aurora.warning)
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
                            Text(Fmt.relative(connection.lastUsedAt))
                                .font(AuroraFont.labelSmall)
                                .foregroundStyle(Aurora.muted)
                        }
                    }

                    Spacer(minLength: 4)

                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isCurrent ? Aurora.brand : Aurora.muted)
                }
            }
            // 整张卡片都能点
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .contextMenu {
            Button {
                onOpenDashboard(connection)
            } label: {
                Label("打开仪表盘", systemImage: "gauge")
            }
            Button {
                session.select(connection)
                Task { await session.connect() }
            } label: {
                Label("连接", systemImage: "bolt.horizontal")
            }
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
