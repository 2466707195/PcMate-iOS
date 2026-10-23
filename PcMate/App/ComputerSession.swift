import Foundation
import SwiftUI

// MARK: - 当前电脑会话
//
// 「工具栏」和「设置」里的功能都需要一台"正在控制的电脑"。
// 这个对象负责：选电脑 → 建立连接（复用 SessionController）→ 给各功能页共用同一个连接。
//
// 首页点卡片进仪表盘仍然是 DashboardScreen 自己的连接，互不干扰。

@MainActor
final class ComputerSession: ObservableObject {

    @Published private(set) var selected: Connection?
    @Published private(set) var controller: SessionController?
    @Published private(set) var connecting = false
    @Published private(set) var errorText: String?
    @Published private(set) var lastConnectedAt: Date?

    private let store: ConnectionStore
    private let printers: PrinterStore

    init(store: ConnectionStore, printers: PrinterStore) {
        self.store = store
        self.printers = printers
    }

    var isConnected: Bool { controller?.isConnected == true }
    var hostInfo: HostInfo? { controller?.hostInfo }
    var transportLabel: String { controller?.transportLabel ?? "未连接" }

    /// 已连接电脑的名字（优先用主机名，退回配置名）。
    var displayName: String {
        let hostname = hostInfo?.hostname.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !hostname.isEmpty { return hostname }
        return selected?.name ?? "未选择电脑"
    }

    /// 首屏自动选中最近用过的一台电脑，省去用户多点一次。
    func autoselectIfNeeded() {
        guard selected == nil, let first = store.connections.first else { return }
        selected = first
    }

    func select(_ connection: Connection) {
        guard selected?.id != connection.id else { return }
        disconnect()
        selected = connection
        errorText = nil
    }

    func select(id: String) {
        guard let connection = store.connections.first(where: { $0.id == id }) else { return }
        select(connection)
    }

    func connect() async {
        guard let connection = selected else {
            errorText = "请先选择一台电脑"
            return
        }
        guard !connecting else { return }
        if controller?.isConnected == true { return }

        connecting = true
        errorText = nil
        let session = SessionController(connection: connection, store: store)
        do {
            _ = try await session.connect()
            controller = session
            lastConnectedAt = Date()
            syncBridgePrinter(connection)
        } catch {
            session.close()
            errorText = error.localizedDescription
        }
        connecting = false
    }

    // MARK: - 打印桥接

    /// 打印桥接**跟着电脑连接走**：连上电脑就自动把它的 9100 桥接端口
    /// 加进「局域网打印」，不用再去扫描列表里单独添加一条「电脑桥接」。
    ///
    /// 同一个 IP 已经存在桥接打印机时只更新名字（电脑改名了也能同步过来），
    /// 不会重复添加。
    private func syncBridgePrinter(_ connection: Connection) {
        let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }

        let hostname = hostInfo?.hostname.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = hostname.isEmpty ? connection.name : hostname
        let name = base.isEmpty ? "电脑桥接打印" : "\(base)（电脑桥接）"

        if let existing = printers.printers.first(where: { $0.format == .bridge && $0.host == host }) {
            guard existing.name != name else { return }
            var updated = existing
            updated.name = name
            printers.update(updated)
            return
        }

        var printer = PrinterConfig()
        printer.name = name
        printer.host = host
        printer.port = 9100
        printer.proto = .raw
        printer.format = .bridge
        printer.paper = .a4
        printer.normalizeFormat()
        printers.add(printer)
    }

    /// 一键重连：先断开再连。
    func reconnect() async {
        disconnect()
        await connect()
    }

    func disconnect() {
        controller?.close()
        controller = nil
        lastConnectedAt = nil
    }

    /// 配置被编辑或删除后，同步一下选中项（删掉的就清空）。
    func refreshSelection() {
        guard let current = selected else { return }
        guard store.connections.contains(where: { $0.id == current.id }) else {
            disconnect()
            selected = nil
            return
        }
        selected = store.connections.first { $0.id == current.id }
    }
}
