import SwiftUI

// MARK: - 设置
//
// 设置页只管「跟当前电脑无关」的事：管理电脑配置、打印机、缓存、关于。
// 具体的远程操作（进程、文件、外网、电源）都放在「工具栏」里。

struct SettingsScreen: View {

    @EnvironmentObject private var store: ConnectionStore
    @EnvironmentObject private var session: ComputerSession

    @ObservedObject private var theme = ThemeStore.shared

    @State private var showTheme = false
    @State private var showAdd = false
    @State private var editing: Connection?
    @State private var deleteTarget: Connection?

    @State private var showPrinters = false
    @State private var showPower = false
    @State private var showComputers = false
    @State private var showAI = false

    @State private var cache: AppCache.Report?
    @State private var cacheBusy = false
    @State private var cacheNotice: String?

    var body: some View {
        ZStack {
            AuroraBackdrop()

            AuroraScreen {
                // 和其他两页一致：顶部透明，只有右上角的电脑按钮
                TabHeaderBar { showComputers = true }
            } content: {
                AuroraScrollView(bottomInset: 118) {
                    if let cacheNotice {
                        AuroraBanner(systemIcon: "checkmark.circle.fill", text: cacheNotice, tone: Aurora.teal)
                    }
                    computersCard
                    aiCard
                    appearanceCard
                    printCard
                    systemCard
                    aboutCard
                }
            } bar: {
                EmptyView()
            }
        }
        .sheet(isPresented: $showAI) {
            AIAssistantSettingsScreen(controller: session.controller)
        }
        .sheet(isPresented: $showAdd) {
            ConnectionEditScreen(connection: nil)
        }
        .sheet(isPresented: $showComputers) {
            ComputerListSheet()
        }
        .sheet(item: $editing) { connection in
            ConnectionEditScreen(connection: connection)
        }
        .fullScreenCover(isPresented: $showTheme) {
            ThemeScreen()
        }
        .fullScreenCover(isPresented: $showPrinters) {
            PrintHomeScreen(onClose: { showPrinters = false })
        }
        .fullScreenCover(isPresented: $showPower) {
            if let controller = session.controller {
                PowerControlScreen(session: controller)
            } else {
                NeedsConnectionScreen(tool: .power)
            }
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
                session.refreshSelection()
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: { target in
            Text("将删除「\(target.name)」的连接信息和 Keychain 中的凭据。")
        }
        .task { refreshCache() }
    }

    // MARK: 电脑

    private var computersCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "电脑",
                    subtitle: "添加、编辑、删除已配置的电脑",
                    systemIcon: "desktopcomputer",
                    trailingText: "\(store.connections.count) 台"
                )

                VStack(spacing: 0) {
                    SettingsRow(
                        systemIcon: "plus",
                        title: "添加电脑",
                        subtitle: "用 6 位配对码连接新电脑",
                        tone: Aurora.brand
                    ) {
                        showAdd = true
                    }

                    ForEach(store.connections) { connection in
                        Divider().overlay(Aurora.hairline)
                        connectionRow(connection)
                    }
                }
            }
        }
    }

    private func connectionRow(_ connection: Connection) -> some View {
        HStack(spacing: 12) {
            Monogram(
                name: connection.name,
                tone: connection.transport == .agent ? Aurora.brand : Aurora.teal,
                size: 36
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(connection.name)
                    .font(AuroraFont.titleSmall)
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                Text(connection.address)
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if session.selected?.id == connection.id {
                StatusPill(text: "当前", color: Aurora.teal)
                    .allowsHitTesting(false)
            }

            AuroraIconButton(systemIcon: "pencil", tone: Aurora.brand, size: 34) {
                editing = connection
            }
            AuroraIconButton(systemIcon: "trash", tone: Aurora.rose, size: 34) {
                deleteTarget = connection
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: AI 助手

    private var aiCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "AI 助手",
                    subtitle: "模型服务商、密钥、常用模型",
                    systemIcon: "sparkles",
                    tone: Aurora.brand
                )

                VStack(spacing: 0) {
                    SettingsRow(
                        systemIcon: "cpu",
                        title: "模型与密钥",
                        subtitle: session.isConnected ? "填接口地址和 Key，拉模型列表" : "需要先连接电脑",
                        tone: Aurora.brand
                    ) {
                        showAI = true
                    }
                }

                Text("在「助手」页用聊天的方式提问，由这台电脑调模型、跑工具（进程、清理、电源、外网、文件、命令）。密钥只保存在电脑上。")
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 外观

    private var appearanceCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "外观",
                    subtitle: "背景、图标与强调色",
                    systemIcon: "paintpalette",
                    tone: Aurora.brand,
                    trailingText: theme.themeName
                )

                VStack(spacing: 0) {
                    SettingsRow(
                        systemIcon: "circle.lefthalf.filled",
                        title: "界面主题",
                        subtitle: theme.isDark ? "\(theme.themeName) · 深色底" : "\(theme.themeName) · 浅色底",
                        tone: Aurora.brand
                    ) {
                        showTheme = true
                    }

                    Divider().overlay(Aurora.hairline)

                    SettingsRow(
                        systemIcon: "swatchpalette",
                        title: "当前配色",
                        subtitle: "主色、底色与光晕都在主题里调",
                        tone: Aurora.teal,
                        showsChevron: false
                    )
                }
            }
        }
    }

    // MARK: 打印

    private var printCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "局域网打印",
                    subtitle: "打印机列表、桥接打印、测试页",
                    systemIcon: "printer",
                    tone: Aurora.teal
                )

                VStack(spacing: 0) {
                    SettingsRow(
                        systemIcon: "printer.fill",
                        title: "打印机管理",
                        subtitle: "扫描、添加、编辑打印机",
                        tone: Aurora.teal
                    ) {
                        showPrinters = true
                    }
                }
            }
        }
    }

    // MARK: 系统

    private var systemCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "系统",
                    subtitle: "缓存与电源",
                    systemIcon: "gearshape.2",
                    tone: Aurora.brand
                )

                VStack(spacing: 0) {
                    cacheRow
                    Divider().overlay(Aurora.hairline)
                    SettingsRow(
                        systemIcon: "power",
                        title: "电源管理",
                        subtitle: session.isConnected ? "锁定 · 睡眠 · 关机 · 重启" : "需要先连接电脑",
                        tone: Aurora.rose
                    ) {
                        showPower = true
                    }
                }
            }
        }
    }

    private var cacheRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Aurora.brand.tint(0.13))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "trash.slash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Aurora.brand)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("软件缓存清理")
                    .font(AuroraFont.titleSmall)
                    .foregroundStyle(Aurora.ink)
                Text(cache.map { "共 \(Fmt.bytes($0.totalBytes)) · \($0.detail)" } ?? "正在统计…")
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            SmallTonalButton(
                text: cacheBusy ? "清理中" : "清理",
                systemIcon: "trash",
                enabled: !cacheBusy
            ) {
                cleanCache()
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: 关于

    private var aboutCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "关于",
                    subtitle: "版本与说明",
                    systemIcon: "info.circle",
                    tone: Aurora.brand
                )

                VStack(spacing: 0) {
                    SettingsRow(
                        systemIcon: "app.badge",
                        title: "PcMate",
                        subtitle: "版本 1.6.0",
                        tone: Aurora.brand,
                        showsChevron: false
                    )
                    Divider().overlay(Aurora.hairline)
                    SettingsRow(
                        systemIcon: "sparkles",
                        title: "AI 助手",
                        subtitle: "「助手」页需要 Agent 1.6.0 及以上",
                        tone: Aurora.brand,
                        showsChevron: false
                    )
                    Divider().overlay(Aurora.hairline)
                    SettingsRow(
                        systemIcon: "server.rack",
                        title: "电脑端 Agent",
                        subtitle: "桥接打印、外网开关需要 1.5.0 及以上",
                        tone: Aurora.brand,
                        showsChevron: false
                    )
                    Divider().overlay(Aurora.hairline)
                    SettingsRow(
                        systemIcon: "paintpalette",
                        title: "界面风格",
                        subtitle: "Aurora UI · 极光卡片式",
                        tone: Aurora.brand,
                        showsChevron: false
                    )
                }
            }
        }
    }

    // MARK: 动作

    private func refreshCache() {
        let report = AppCache.measure()
        cache = report
    }

    private func cleanCache() {
        guard !cacheBusy else { return }
        cacheBusy = true
        cacheNotice = nil
        let freed = AppCache.clear()
        refreshCache()
        cacheBusy = false
        cacheNotice = freed > 0 ? "已清理 \(Fmt.bytes(freed)) 缓存。" : "缓存已经很干净，没有可清理的内容。"
    }
}

// MARK: - 设置项

private struct SettingsRow: View {

    let systemIcon: String
    let title: String
    var subtitle: String? = nil
    var tone: Color = Aurora.brand
    var showsChevron: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tone.tint(0.13))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: systemIcon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tone)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AuroraFont.titleSmall)
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 4)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Aurora.muted)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }
}
