import Foundation
import SwiftUI

@MainActor
final class DashboardModel: ObservableObject {

    let session: SessionController
    let connection: Connection

    @Published private(set) var hostInfo: HostInfo?
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memHistory: [Double] = []
    @Published private(set) var rxHistory: [Double] = []
    @Published private(set) var txHistory: [Double] = []
    @Published var errorMessage: String?
    @Published var fallbackNotice: String?
    @Published private(set) var connecting = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var hardware: HardwareSummary?
    @Published private(set) var hardwareLoading = false
    @Published private(set) var hardwareError: String?

    private var pollTask: Task<Void, Never>?
    private var lastSnapshotMs: Int64 = 0
    private var hasStarted = false

    init(connection: Connection, store: ConnectionStore) {
        self.connection = connection
        self.session = SessionController(connection: connection, store: store)
    }

    var isConnected: Bool { hostInfo != nil }

    var statusLine: String {
        guard let hostInfo else {
            return connecting ? "正在连接…" : "未连接"
        }
        var parts = [session.transportLabel, hostInfo.osShort]
        if session.activeTransport == .agent {
            parts.append(session.latencyLabel)
        }
        return parts.joined(separator: " · ")
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await connect()
    }

    func retry() {
        hasStarted = true
        Task { await connect() }
    }

    func refresh() {
        Task { await refreshOnce() }
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        session.close()
        hostInfo = nil
        snapshot = nil
        lastUpdated = nil
        hardware = nil
        hardwareError = nil
        hardwareLoading = false
    }

    /// 读取硬件信息（主板 / 内存条 / 硬盘 / 电池）。Agent 端会缓存 3 分钟。
    func loadHardware(force: Bool = false) async {
        guard session.activeTransport == .agent else {
            hardwareError = "硬件信息需要 Agent 连接，SSH 模式暂不支持"
            return
        }
        guard !hardwareLoading else { return }
        if !force, hardware != nil { return }
        hardwareLoading = true
        hardwareError = nil
        do {
            hardware = try await session.hardware()
        } catch {
            hardwareError = error.localizedDescription
        }
        hardwareLoading = false
    }

    private func connect() async {
        pollTask?.cancel()
        pollTask = nil
        connecting = true
        errorMessage = nil
        fallbackNotice = nil
        do {
            let info = try await session.connect()
            hostInfo = info
            fallbackNotice = session.fallbackNotice
            connecting = false
            await refreshOnce()
            startPolling()
            await loadHardware()
        } catch {
            connecting = false
            hostInfo = nil
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        let seconds = max(1, min(10, connection.refreshSeconds))
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshOnce()
            }
        }
    }

    private func refreshOnce() async {
        do {
            let value = try await session.snapshot()
            guard value.timeMs != lastSnapshotMs else { return }
            lastSnapshotMs = value.timeMs
            snapshot = value
            lastUpdated = Date()
            if errorMessage != nil, hostInfo != nil {
                errorMessage = nil
            }
            cpuHistory = trimmed(cpuHistory + [value.cpuPercent])
            memHistory = trimmed(memHistory + [value.memPercent])
            rxHistory = trimmed(rxHistory + [Double(value.netRxBps)])
            txHistory = trimmed(txHistory + [Double(value.netTxBps)])
        } catch {
            if hostInfo != nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func trimmed(_ array: [Double]) -> [Double] {
        Array(array.suffix(40))
    }
}
