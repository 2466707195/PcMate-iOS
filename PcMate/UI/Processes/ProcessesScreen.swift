import Foundation
import SwiftUI

enum ProcessFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case app = "应用"
    case background = "后台"

    var id: String { rawValue }
}

struct ProcessSection: Identifiable {
    let group: ProcessGroup
    let items: [ProcessInfo]
    var id: String { group.rawValue }
}

@MainActor
final class ProcessesModel: ObservableObject {

    let session: SessionController

    @Published private(set) var items: [ProcessInfo] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var loading = false
    @Published private(set) var killingPID: Int?
    @Published var search = ""
    @Published var filter: ProcessFilter = .all
    @Published var errorMessage: String?
    @Published var lastActionMessage: String?

    init(session: SessionController) {
        self.session = session
    }

    var grouped: [ProcessSection] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var app: [ProcessInfo] = []
        var background: [ProcessInfo] = []

        for item in items {
            let meta = ProcessCatalog.meta(name: item.name)
            if filter == .app, meta.group != .app { continue }
            if filter == .background, meta.group != .background { continue }
            if !query.isEmpty {
                let haystack = [
                    meta.display,
                    item.name,
                    item.command,
                    item.user,
                    String(item.pid)
                ].joined(separator: " ").lowercased()
                if !haystack.contains(query) { continue }
            }
            if meta.group == .app {
                app.append(item)
            } else {
                background.append(item)
            }
        }

        app.sort { $0.cpuPercent > $1.cpuPercent }
        background.sort { $0.cpuPercent > $1.cpuPercent }
        return [
            ProcessSection(group: .app, items: app),
            ProcessSection(group: .background, items: background)
        ].filter { !$0.items.isEmpty }
    }

    func load() async {
        guard !loading else { return }
        loading = true
        errorMessage = nil
        do {
            let snapshot = try await session.processes()
            items = snapshot.items
            totalCount = snapshot.totalCount
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func kill(pid: Int) async {
        guard killingPID == nil else { return }
        killingPID = pid
        errorMessage = nil
        do {
            lastActionMessage = try await session.kill(pid: pid)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
        killingPID = nil
    }
}

struct ProcessesScreen: View {

    @StateObject private var model: ProcessesModel
    @Environment(\.dismiss) private var dismiss

    @State private var selected: ProcessInfo?
    @State private var killTarget: ProcessInfo?
    @State private var showActionAlert = false

    init(session: SessionController) {
        _model = StateObject(wrappedValue: ProcessesModel(session: session))
    }

    var body: some View {
        ZStack {
            AuroraBackdrop()
            AuroraScreen {
                AppTopBar(
                    title: "进程",
                    subtitle: "\(model.totalCount) 个进程 · \(model.session.transportLabel)",
                    onBack: { dismiss() }
                ) {
                    Button {
                        Task { await model.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Aurora.brand)
                            .frame(width: 38, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.loading)
                }
            } content: {
                AuroraScrollView(bottomInset: 120) {
                    searchAndFilter

                    if let error = model.errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Aurora.rose)
                            Text(error)
                                .font(AuroraFont.bodySmall)
                                .foregroundStyle(Aurora.rose)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Aurora.roseContainer))
                    }

                    if model.loading && model.items.isEmpty {
                        SectionCard {
                            HStack(spacing: 10) {
                                ProgressView().tint(Aurora.brand)
                                Text("正在读取进程列表…")
                                    .font(AuroraFont.bodySmall)
                                    .foregroundStyle(Aurora.inkSoft)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    ForEach(model.grouped) { section in
                        processSection(section)
                    }

                    if !model.loading && model.grouped.isEmpty && model.errorMessage == nil {
                        SectionCard {
                            EmptyStateView(
                                systemIcon: "magnifyingglass",
                                title: "没有匹配的进程",
                                message: "换个关键词，或切换到「全部」。"
                            )
                            .padding(.vertical, 16)
                        }
                    }
                }
            } bar: {
                GlassBar {
                    HStack(spacing: 8) {
                        SmallTonalButton(text: "刷新", systemIcon: "arrow.clockwise", expands: true) {
                            Task { await model.load() }
                        }
                        SmallTonalButton(text: "全部", systemIcon: "square.grid.2x2", expands: true) {
                            model.filter = .all
                            model.search = ""
                        }
                        SmallTonalButton(text: "后台", systemIcon: "gearshape.2", expands: true) {
                            model.filter = .background
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            Task { await model.load() }
        }
        .sheet(item: $selected) { item in
            ProcessDetailSheet(
                item: item,
                killing: model.killingPID == item.pid
            ) {
                Task { @MainActor in
                    await model.kill(pid: item.pid)
                    selected = nil
                    showActionAlert = true
                }
            }
        }
        .confirmationDialog(
            "结束这个进程？",
            isPresented: Binding(
                get: { killTarget != nil },
                set: { if !$0 { killTarget = nil } }
            ),
            presenting: killTarget
        ) { target in
            Button("结束进程", role: .destructive) {
                Task { @MainActor in
                    await model.kill(pid: target.pid)
                    killTarget = nil
                    showActionAlert = true
                }
            }
            Button("取消", role: .cancel) { killTarget = nil }
        } message: { target in
            Text("将向 PID \(target.pid) 发送强制结束信号。系统关键进程可能无法结束。")
        }
        .alert("操作结果", isPresented: $showActionAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(model.lastActionMessage ?? model.errorMessage ?? "操作已完成")
        }
    }

    private var searchAndFilter: some View {
        VStack(spacing: 10) {
            AuroraTextField(
                placeholder: "搜索进程名、PID、用户",
                text: $model.search,
                systemIcon: "magnifyingglass"
            )

            HStack(spacing: 8) {
                ForEach(ProcessFilter.allCases) { filter in
                    Button {
                        model.filter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(AuroraFont.labelLarge)
                            .foregroundStyle(model.filter == filter ? Aurora.onBrandContainer : Aurora.inkSoft)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(model.filter == filter ? Aurora.brandContainer : Aurora.surfaceVariant)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func processSection(_ section: ProcessSection) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(section.group.label)
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                    Text("\(section.items.count)")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                    Spacer()
                    Text("按 CPU 排序")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                }
                .padding(.bottom, 4)

                ForEach(section.items) { item in
                    Button {
                        selected = item
                    } label: {
                        ProcessRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            selected = item
                        } label: {
                            Label("查看详情", systemImage: "info.circle")
                        }
                        Button(role: .destructive) {
                            killTarget = item
                        } label: {
                            Label("结束进程", systemImage: "xmark.octagon")
                        }
                    }

                    if item.id != section.items.last?.id {
                        Rectangle()
                            .fill(Aurora.hairline)
                            .frame(height: 1)
                    }
                }
            }
        }
    }
}

private struct ProcessRow: View {

    let item: ProcessInfo

    private var meta: ProcessMeta { ProcessCatalog.meta(name: item.name) }

    private var cpuTone: Color {
        if item.cpuPercent >= 50 { return Aurora.rose }
        if item.cpuPercent >= 20 { return Aurora.warning }
        return Aurora.teal
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(meta.icon.tone.tint(0.12))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: meta.icon.systemIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(meta.icon.tone)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(meta.display)
                    .font(AuroraFont.labelLarge)
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                Text("\(item.name) · PID \(item.pid)")
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.percent(item.cpuPercent))
                    .font(AuroraFont.labelMedium)
                    .foregroundStyle(cpuTone)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(cpuTone.tint(0.12)))
                Text(Fmt.bytes(item.memBytes))
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.inkSoft)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

private struct ProcessDetailSheet: View {

    let item: ProcessInfo
    let killing: Bool
    let onKill: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmKill = false

    private var meta: ProcessMeta { ProcessCatalog.meta(name: item.name) }

    var body: some View {
        ZStack {
            AuroraBackdrop()
            AuroraScreen {
                AppTopBar(
                    title: "进程详情",
                    subtitle: meta.display,
                    onBack: { dismiss() }
                ) {
                    EmptyView()
                }
            } content: {
                AuroraScrollView(bottomInset: 128) {
                    SectionCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(meta.icon.tone.tint(0.12))
                                    .frame(width: 54, height: 54)
                                    .overlay(
                                        Image(systemName: meta.icon.systemIcon)
                                            .font(.system(size: 23, weight: .semibold))
                                            .foregroundStyle(meta.icon.tone)
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(meta.display)
                                        .font(AuroraFont.titleLarge)
                                        .foregroundStyle(Aurora.ink)
                                    Text(meta.group.label)
                                        .font(AuroraFont.labelSmall)
                                        .foregroundStyle(Aurora.muted)
                                }
                            }

                            detailRow("原始名称", item.name)
                            detailRow("PID", String(item.pid))
                            detailRow("用户", item.user.isEmpty ? "—" : item.user)
                            detailRow("CPU", Fmt.percent(item.cpuPercent))
                            detailRow("内存", Fmt.bytes(item.memBytes))
                        }
                    }

                    if !item.command.isEmpty {
                        SectionCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("命令行")
                                    .font(AuroraFont.titleMedium)
                                    .foregroundStyle(Aurora.ink)
                                Text(item.command)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(Aurora.inkSoft)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            } bar: {
                GlassBar {
                    DangerTonalButton(text: killing ? "正在结束…" : "结束进程", systemIcon: "xmark.octagon", enabled: !killing) {
                        confirmKill = true
                    }
                }
            }
        }
        .confirmationDialog("结束这个进程？", isPresented: $confirmKill, titleVisibility: .visible) {
            Button("结束进程", role: .destructive) { onKill() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("PID \(item.pid) · \(meta.display)\n系统关键进程可能拒绝结束。")
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.muted)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
