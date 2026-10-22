import Foundation
import SwiftUI

/// 统一管理当前连接的后端：优先 Agent，失败后按设置回退 SSH。
@MainActor
final class SessionController: ObservableObject {

    @Published private(set) var hostInfo: HostInfo?
    @Published private(set) var activeTransport: Transport?
    @Published private(set) var fallbackNotice: String?
    @Published private(set) var isConnecting = false

    private(set) var connection: Connection
    private let store: ConnectionStore

    private var agent: AgentClient?
    private var ssh: SshClient?

    init(connection: Connection, store: ConnectionStore) {
        self.connection = connection
        self.store = store
    }

    var isConnected: Bool { hostInfo != nil }

    var transportLabel: String {
        switch activeTransport {
        case .agent: return "Agent · WebSocket"
        case .ssh: return "SSH · SFTP"
        case nil: return "未连接"
        }
    }

    var latencyLabel: String {
        guard let agent else { return "—" }
        return "\(agent.lastLatencyMs) ms"
    }

    var initialPath: String {
        ssh?.initialPath ?? ""
    }

    // MARK: 连接

    func connect() async throws -> HostInfo {
        isConnecting = true
        fallbackNotice = nil
        defer { isConnecting = false }
        closeBackends()

        if connection.transport == .agent {
            do {
                return try await connectAgent()
            } catch {
                guard connection.allowSshFallback, connection.hasSshCredentials else {
                    throw error
                }
                do {
                    let info = try await connectSSH()
                    fallbackNotice = "Agent 连接失败，已自动切换到 SSH。\n\(error.localizedDescription)"
                    return info
                } catch let sshError {
                    throw PcMateError.message(
                        "Agent 连接失败：\(error.localizedDescription)\nSSH 回退也失败：\(sshError.localizedDescription)"
                    )
                }
            }
        }
        return try await connectSSH()
    }

    private func connectAgent() async throws -> HostInfo {
        let client = AgentClient(
            host: connection.host,
            port: connection.agentPort,
            token: connection.agentToken,
            tls: connection.agentTls,
            intervalMs: connection.agentIntervalMs,
            fingerprint: connection.agentFingerprint.isEmpty ? nil : connection.agentFingerprint
        )
        let info: HostInfo
        do {
            info = try await client.connect()
        } catch {
            client.close()
            throw error
        }
        agent = client
        ssh = nil
        activeTransport = .agent
        hostInfo = info
        if connection.agentFingerprint.isEmpty, let fingerprint = client.capturedFingerprint, !fingerprint.isEmpty {
            connection.agentFingerprint = fingerprint
            store.updateFingerprint(connectionID: connection.id, fingerprint: fingerprint, transport: .agent)
        }
        store.touch(connection)
        return info
    }

    private func connectSSH() async throws -> HostInfo {
        guard connection.hasSshCredentials else {
            throw PcMateError.message("SSH 连接需要用户名和密码/私钥")
        }
        let client = SshClient(connection: connection)
        let info: HostInfo
        do {
            info = try await client.connect()
        } catch {
            await client.close()
            throw error
        }
        ssh = client
        agent = nil
        activeTransport = .ssh
        hostInfo = info
        let fingerprint = client.capturedFingerprint
        if connection.sshFingerprint.isEmpty, !fingerprint.isEmpty {
            connection.sshFingerprint = fingerprint
            store.updateFingerprint(connectionID: connection.id, fingerprint: fingerprint, transport: .ssh)
        }
        store.touch(connection)
        return info
    }

    func close() {
        closeBackends()
        hostInfo = nil
        activeTransport = nil
        fallbackNotice = nil
    }

    private func closeBackends() {
        agent?.close()
        agent = nil
        if let ssh {
            Task { await ssh.close() }
        }
        ssh = nil
    }

    // MARK: 实时数据

    func snapshot() async throws -> Snapshot {
        if let agent { return try await agent.snapshot() }
        if let ssh { return try await ssh.snapshot() }
        throw PcMateError.connectionClosed
    }

    func processes() async throws -> ProcessSnapshot {
        if let agent { return try await agent.processes() }
        if let ssh { return try await ssh.processes() }
        throw PcMateError.connectionClosed
    }

    func kill(pid: Int) async throws -> String {
        if let agent { return try await agent.kill(pid: pid) }
        if let ssh { return try await ssh.kill(pid: pid) }
        throw PcMateError.connectionClosed
    }

    func cleanup(mode: CleanupMode) async throws -> CleanupResult {
        if let agent { return try await agent.cleanup(mode: mode) }
        if let ssh { return try await ssh.cleanup(mode: mode) }
        throw PcMateError.connectionClosed
    }

    // MARK: 详情（Agent 1.2.0+）

    var supportsDetails: Bool {
        if activeTransport == .agent { return true }
        return false
    }

    func power(_ action: PowerAction) async throws -> String {
        guard let agent else {
            throw PcMateError.message("电源操作需要 Agent 连接，SSH 模式暂不支持")
        }
        return try await agent.power(action)
    }

    func netInfo() async throws -> NetInfoDetail {
        guard let agent else {
            throw PcMateError.message("网络详情需要 Agent 连接，SSH 模式暂不支持")
        }
        return try await agent.netInfo()
    }

    func gpuInfo() async throws -> [GpuDetail] {
        guard let agent else {
            throw PcMateError.message("显卡详情需要 Agent 连接，SSH 模式暂不支持")
        }
        return try await agent.gpuInfo()
    }

    func sysInfo() async throws -> RemoteSysInfo {
        guard let agent else {
            throw PcMateError.message("系统详情需要 Agent 连接，SSH 模式暂不支持")
        }
        return try await agent.sysInfo()
    }

    func hardware() async throws -> HardwareSummary {
        guard let agent else {
            throw PcMateError.message("硬件信息需要 Agent 连接，SSH 模式暂不支持")
        }
        return try await agent.hardware()
    }

    // MARK: 文件

    func list(path: String) async throws -> RemoteListing {
        if let agent { return try await agent.list(path: path) }
        if let ssh { return try await ssh.list(path: path) }
        throw PcMateError.connectionClosed
    }

    func download(path: String, to destination: URL) async throws -> URL {
        if let agent { return try await agent.download(path: path, to: destination) }
        if let ssh { return try await ssh.download(path: path, to: destination) }
        throw PcMateError.connectionClosed
    }

    func upload(name: String, data: Data, directory: String) async throws -> RemoteFileEntry {
        if let agent { return try await agent.upload(name: name, data: data, directory: directory) }
        if let ssh { return try await ssh.upload(name: name, data: data, directory: directory) }
        throw PcMateError.connectionClosed
    }

    func makeDirectory(path: String) async throws -> String {
        if let agent { return try await agent.makeDirectory(path: path) }
        if let ssh { return try await ssh.makeDirectory(path: path) }
        throw PcMateError.connectionClosed
    }

    func delete(path: String) async throws -> String {
        if let agent { return try await agent.delete(path: path) }
        if let ssh { return try await ssh.delete(path: path) }
        throw PcMateError.connectionClosed
    }
}
