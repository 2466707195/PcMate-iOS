import Foundation

// MARK: - Agent 客户端

/// PcMate Agent 的 iOS 客户端：WebSocket 接收实时快照，HTTPS 端点传输文件。
/// 自签名证书通过 `PinnedTLSDelegate` 按配对时记录的指纹校验。
@MainActor
final class AgentClient: NSObject {

    let host: String
    let port: Int
    let token: String
    let tls: Bool
    let intervalMs: Int

    private let tlsDelegate: PinnedTLSDelegate
    private var session: URLSession!
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?

    private var pending: [Int64: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextID: Int64 = 0
    private var welcomeContinuation: CheckedContinuation<HostInfo, Error>?
    private var latestSnapshot: Snapshot?
    private var snapshotWaiters: [UInt64: CheckedContinuation<Snapshot, Error>] = [:]
    private var nextWaiterID: UInt64 = 0
    private var closed = false

    private(set) var hostInfo: HostInfo?
    private(set) var lastLatencyMs: Int64 = 0

    var capturedFingerprint: String? { tlsDelegate.capturedFingerprint }

    init(host: String, port: Int, token: String, tls: Bool, intervalMs: Int, fingerprint: String?) {
        self.host = host
        self.port = port
        self.token = token
        self.tls = tls
        self.intervalMs = max(intervalMs, 250)
        self.tlsDelegate = PinnedTLSDelegate(expectedFingerprint: fingerprint)
        super.init()
    }

    // MARK: 连接

    func connect() async throws -> HostInfo {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PcMateError.message("Agent 凭证为空，请先配对或填写访问令牌")
        }
        closed = false

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        // WebSocket 是长连接，不能沿用短请求的 resource timeout。
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: tlsDelegate, delegateQueue: nil)

        var components = URLComponents()
        components.scheme = tls ? "wss" : "ws"
        components.host = host
        components.port = port
        components.path = "/ws"
        guard let url = components.url else {
            throw PcMateError.message("电脑地址无效")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        socket = task
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        let info = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HostInfo, Error>) in
            welcomeContinuation = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, let waiting = self.welcomeContinuation else { return }
                self.welcomeContinuation = nil
                waiting.resume(throwing: PcMateError.timeout)
            }
        }
        hostInfo = info

        try? await send(["type": "subscribe", "intervalMs": intervalMs])
        _ = try? await ping()

        // 保活：每 30 秒发一个 WebSocket ping。
        // 电脑端的读超时是 75 秒，只靠它单方面发 ping 不够稳——
        // 手机静置一会儿再点按钮，会报「软件导致连接中止」。
        keepaliveTask?.cancel()
        keepaliveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, !self.closed else { return }
                await self.sendKeepalivePing()
            }
        }
        return info
    }

    func close() {
        guard !closed else { return }
        closed = true
        keepaliveTask?.cancel()
        keepaliveTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        failAll(PcMateError.connectionClosed)
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: WebSocket 收发

    /// 保活 ping。iOS 的 API 是 `sendPing(pongReceiveHandler:)`，没有 pongTimeout。
    private func sendKeepalivePing() async {
        guard let socket else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            socket.sendPing { _ in continuation.resume() }
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let socket else { return }
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    handle(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handle(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    failAll(PcMateError.message("Agent 连接已断开：\(error.localizedDescription)"))
                }
                return
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let message = object as? [String: Any],
              let type = message["type"] as? String else { return }

        switch type {
        case "welcome":
            let hostObject = message["host"] as? [String: Any] ?? [:]
            let info = AgentParser.host(hostObject)
            hostInfo = info
            if let continuation = welcomeContinuation {
                welcomeContinuation = nil
                continuation.resume(returning: info)
            }

        case "snapshot":
            guard let payload = message["data"] as? [String: Any] else { return }
            let snapshot = AgentParser.snapshot(payload)
            latestSnapshot = snapshot
            let waiters = snapshotWaiters
            snapshotWaiters.removeAll()
            for (_, waiter) in waiters { waiter.resume(returning: snapshot) }

        case "response", "error":
            guard let id = AgentParser.int64(message["id"]) else { return }
            guard let continuation = pending.removeValue(forKey: id) else { return }
            if (message["ok"] as? Bool) == true {
                continuation.resume(returning: message["data"] as? [String: Any] ?? [:])
            } else {
                let error = message["error"] as? String ?? "Agent 请求失败"
                continuation.resume(throwing: PcMateError.message(error))
            }

        default:
            break
        }
    }

    private func send(_ payload: [String: Any]) async throws {
        guard let socket else { throw PcMateError.connectionClosed }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw PcMateError.message("无法编码请求")
        }
        try await socket.send(.string(text))
    }

    // MARK: 请求

    func request(
        action: String,
        pid: Int? = nil,
        mode: String? = nil,
        extra: [String: Any] = [:],
        timeout: TimeInterval = 20
    ) async throws -> [String: Any] {
        guard !closed else { throw PcMateError.connectionClosed }
        nextID += 1
        let id = nextID
        var payload: [String: Any] = [
            "type": "request",
            "id": id,
            "action": action
        ]
        if let pid { payload["pid"] = pid }
        if let mode { payload["mode"] = mode }
        for (key, value) in extra { payload[key] = value }

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.send(payload)
                } catch {
                    if let pending = self.pending.removeValue(forKey: id) {
                        pending.resume(throwing: error)
                    }
                    return
                }
                let nanos = UInt64(max(timeout, 1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                if let pending = self.pending.removeValue(forKey: id) {
                    pending.resume(throwing: PcMateError.timeout)
                }
            }
        }
    }

    func ping() async throws -> Int64 {
        let started = Date().timeIntervalSince1970
        _ = try await request(action: "ping", timeout: 5)
        let rtt = Int64(max((Date().timeIntervalSince1970 - started) * 1000, 0))
        lastLatencyMs = rtt
        return rtt
    }

    func snapshot() async throws -> Snapshot {
        if let latestSnapshot { return latestSnapshot }
        nextWaiterID += 1
        let waiterID = nextWaiterID
        return try await withCheckedThrowingContinuation { continuation in
            snapshotWaiters[waiterID] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard let self else { return }
                if let pending = self.snapshotWaiters.removeValue(forKey: waiterID) {
                    pending.resume(throwing: PcMateError.timeout)
                }
            }
        }
    }

    func processes() async throws -> ProcessSnapshot {
        let data = try await request(action: "processes", timeout: 25)
        let (items, total) = AgentParser.processes(data)
        return ProcessSnapshot(items: items, totalCount: total)
    }

    func kill(pid: Int) async throws -> String {
        let data = try await request(action: "kill", pid: pid, timeout: 10)
        return data["message"] as? String ?? "进程已结束"
    }

    func cleanup(mode: CleanupMode) async throws -> CleanupResult {
        let data = try await request(action: "cleanup", mode: mode.rawValue, timeout: 30)
        return AgentParser.cleanup(data)
    }

    func power(_ action: PowerAction) async throws -> String {
        let data = try await request(action: "power", mode: action.rawValue, timeout: 15)
        return data["message"] as? String ?? "\(action.title)指令已发送"
    }

    func netInfo() async throws -> NetInfoDetail {
        let data = try await request(action: "netinfo", timeout: 30)
        return AgentParser.netInfo(data)
    }

    func gpuInfo() async throws -> [GpuDetail] {
        let data = try await request(action: "gpuinfo", timeout: 30)
        return AgentParser.gpuList(data)
    }

    func sysInfo() async throws -> RemoteSysInfo {
        let data = try await request(action: "sysinfo", timeout: 20)
        return AgentParser.sysInfo(data)
    }

    func hardware() async throws -> HardwareSummary {
        let data = try await request(action: "hardware", timeout: 40)
        return AgentParser.hardware(data)
    }

    // MARK: 外网开关（Agent 1.5.0+）

    func netMode() async throws -> NetModeInfo {
        let data = try await request(action: "netmode", timeout: 25)
        return AgentParser.netMode(data)
    }

    /// enabled=true 走 DHCP（开外网）；false 改成手动 IP 且清空网关（关外网）。
    func setExternal(_ enabled: Bool, adapter: String) async throws -> NetModeInfo {
        let data = try await request(
            action: "netmode-set",
            extra: ["enabled": enabled, "adapter": adapter],
            timeout: 60
        )
        return AgentParser.netMode(data)
    }

    // MARK: AI 助手（Agent 1.6.0+）
    //
    // 模型调用和工具执行都在电脑上，手机只发问题、收结果。
    // 超时给到 150 秒：一次提问里模型可能要连着调好几轮工具。

    func assistant(text: String, history: [(role: String, content: String)]) async throws -> AssistantReply {
        let turns = history.map { ["role": $0.role, "content": $0.content] }
        let data = try await request(
            action: "assistant",
            extra: ["text": text, "history": turns],
            timeout: 150
        )
        return AgentParser.assistantReply(data)
    }

    // MARK: 服务商与模型管理

    func aiConfig() async throws -> AIConfigInfo {
        let data = try await request(action: "ai-config", timeout: 10)
        return AgentParser.aiConfig(data)
    }

    /// 保存 / 更新一个服务商。apiKey 留空表示不修改，"-" 表示清空。
    @discardableResult
    func saveAIProvider(
        name: String,
        baseUrl: String,
        apiKey: String,
        model: String = "",
        setActive: Bool = false
    ) async throws -> AIProviderInfo {
        var extra: [String: Any] = ["name": name]
        if !baseUrl.isEmpty { extra["baseUrl"] = baseUrl }
        if !apiKey.isEmpty { extra["apiKey"] = apiKey }
        if !model.isEmpty { extra["model"] = model }
        if setActive { extra["setActive"] = true }
        let data = try await request(action: "ai-provider-save", extra: extra, timeout: 15)
        return AgentParser.aiProvider(data)
    }

    func deleteAIProvider(name: String) async throws {
        _ = try await request(action: "ai-provider-delete", extra: ["name": name], timeout: 15)
    }

    @discardableResult
    func selectAIProvider(name: String) async throws -> AIConfigInfo {
        let data = try await request(action: "ai-provider-select", extra: ["name": name], timeout: 15)
        return AgentParser.aiConfig(data)
    }

    /// 设置某个服务商当前选用的模型（点常用模型行时用）。
    @discardableResult
    func setProviderModel(name: String, model: String) async throws -> AIConfigInfo {
        let data = try await request(
            action: "ai-provider-model",
            extra: ["name": name, "model": model],
            timeout: 15
        )
        return AgentParser.aiConfig(data)
    }

    /// 拉取模型列表。name 留空 = 当前服务商；也可以带 baseUrl + apiKey 试一家还没保存的。
    func fetchAIModels(name: String = "", baseUrl: String = "", apiKey: String = "") async throws -> [AIModelInfo] {
        var extra: [String: Any] = [:]
        if !name.isEmpty { extra["name"] = name }
        if !baseUrl.isEmpty { extra["baseUrl"] = baseUrl }
        if !apiKey.isEmpty { extra["apiKey"] = apiKey }
        let data = try await request(action: "ai-models", extra: extra, timeout: 40)
        let rows = data["models"] as? [[String: Any]] ?? []
        return rows.map { row in
            AIModelInfo(
                model: AgentParser.string(row["id"]),
                ownedBy: AgentParser.string(row["owned"]),
                favorite: row["favorite"] as? Bool ?? false
            )
        }
    }

    /// 测某个服务商 + 模型是否真的能用。
    func testAIModel(name: String = "", model: String, baseUrl: String = "", apiKey: String = "") async throws -> AIModelTestResult {
        var extra: [String: Any] = ["model": model]
        if !name.isEmpty { extra["name"] = name }
        if !baseUrl.isEmpty { extra["baseUrl"] = baseUrl }
        if !apiKey.isEmpty { extra["apiKey"] = apiKey }
        let data = try await request(action: "ai-model-test", extra: extra, timeout: 70)
        return AIModelTestResult(
            reply: data["reply"] as? String ?? "",
            model: data["model"] as? String ?? model,
            provider: data["provider"] as? String ?? name,
            elapsedMs: AgentParser.int64(data["elapsedMs"]) ?? 0
        )
    }

    @discardableResult
    func addAIFavorite(name: String, model: String) async throws -> AIConfigInfo {
        let data = try await request(
            action: "ai-favorite-add",
            extra: ["name": name, "model": model],
            timeout: 15
        )
        return AgentParser.aiConfig(data)
    }

    @discardableResult
    func removeAIFavorite(name: String, model: String) async throws -> AIConfigInfo {
        let data = try await request(
            action: "ai-favorite-remove",
            extra: ["name": name, "model": model],
            timeout: 15
        )
        return AgentParser.aiConfig(data)
    }

    private func failAll(_ error: Error) {
        if let continuation = welcomeContinuation {
            welcomeContinuation = nil
            continuation.resume(throwing: error)
        }
        let allPending = pending
        pending.removeAll()
        for (_, continuation) in allPending {
            continuation.resume(throwing: error)
        }
        let waiters = snapshotWaiters
        snapshotWaiters.removeAll()
        for (_, waiter) in waiters { waiter.resume(throwing: error) }
    }

    // MARK: 文件 HTTP 端点

    private func fileRequest(endpoint: String, path: String, method: String) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = tls ? "https" : "http"
        components.host = host
        components.port = port
        components.path = "/files/\(endpoint)"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components.url else {
            throw PcMateError.message("文件路径无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    func list(path: String) async throws -> RemoteListing {
        let request = try fileRequest(endpoint: "list", path: path, method: "GET")
        let (data, response) = try await session.data(for: request)
        try check(response: response, data: data)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PcMateError.message("Agent 返回的文件列表格式不正确")
        }
        return AgentParser.listing(object)
    }

    func download(path: String, to destination: URL) async throws -> URL {
        let request = try fileRequest(endpoint: "download", path: path, method: "GET")
        let (temporary, response) = try await session.download(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = (try? Data(contentsOf: temporary)) ?? Data()
            throw fileError(status: http.statusCode, data: body)
        }
        let manager = FileManager.default
        let folder = destination.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: temporary, to: destination)
        return destination
    }

    func upload(name: String, data: Data, directory: String) async throws -> RemoteFileEntry {
        let remotePath = RemotePath.join(directory, name)
        var request = try fileRequest(endpoint: "upload", path: remotePath, method: "POST")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await session.upload(for: request, from: data)
        try check(response: response, data: responseData)
        guard let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw PcMateError.message("Agent 返回的上传结果格式不正确")
        }
        return AgentParser.file(object)
    }

    func makeDirectory(path: String) async throws -> String {
        var request = try fileRequest(endpoint: "mkdir", path: path, method: "POST")
        request.httpBody = Data()
        let (data, response) = try await session.data(for: request)
        try check(response: response, data: data)
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        return "文件夹已创建"
    }

    func delete(path: String) async throws -> String {
        var request = try fileRequest(endpoint: "delete", path: path, method: "POST")
        request.httpBody = Data()
        let (data, response) = try await session.data(for: request)
        try check(response: response, data: data)
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        return "已删除"
    }

    private func check(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw fileError(status: http.statusCode, data: data)
        }
    }

    private func fileError(status: Int, data: Data) -> Error {
        if status == 401 { return PcMateError.unauthorized }
        if status == 404 {
            return PcMateError.message("这台电脑上的 Agent 版本过低，没有文件传输接口（404）。请在电脑上把它升级到 PcMate Agent 1.2.0 后再试。")
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty { return PcMateError.message(text) }
        return PcMateError.message("文件操作失败（HTTP \(status)）")
    }
}

// MARK: - JSON 解析

enum AgentParser {

    static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        int64(value).map(Int.init)
    }

    static func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) ?? 0 }
        return 0
    }

    static func string(_ value: Any?) -> String {
        value as? String ?? ""
    }

    static func host(_ data: [String: Any]) -> HostInfo {
        HostInfo(
            hostname: string(data["hostname"]),
            os: RemoteOS(rawValue: string(data["os"])) ?? .unknown,
            osLabel: string(data["osLabel"]),
            kernel: string(data["kernel"]),
            cpuModel: string(data["cpuModel"]),
            cores: int(data["cores"]) ?? 0,
            totalMemBytes: int64(data["totalMemBytes"]) ?? 0,
            gpuName: string(data["gpuName"]).isEmpty ? nil : string(data["gpuName"]),
            gpuMemBytes: int64(data["gpuMemBytes"]) ?? 0,
            isRoot: data["isRoot"] as? Bool ?? false,
            agentVersion: string(data["agentVersion"])
        )
    }

    static func snapshot(_ data: [String: Any]) -> Snapshot {
        var snapshot = Snapshot()
        snapshot.timeMs = int64(data["timeMs"]) ?? snapshot.timeMs
        snapshot.latencyMs = int64(data["latencyMs"]) ?? 0
        snapshot.cpuPercent = double(data["cpuPercent"])
        snapshot.perCore = (data["perCore"] as? [Any])?.map { double($0) } ?? []
        snapshot.cpuSpeedMhz = int(data["cpuSpeedMhz"]).flatMap { $0 > 0 ? $0 : nil }
        snapshot.memTotal = int64(data["memTotal"]) ?? 0
        snapshot.memUsed = int64(data["memUsed"]) ?? 0
        snapshot.memAvailable = int64(data["memAvailable"]) ?? 0
        snapshot.memFree = int64(data["memFree"]) ?? 0
        snapshot.memCached = int64(data["memCached"]) ?? 0
        snapshot.memBuffers = int64(data["memBuffers"]) ?? 0
        snapshot.memCommitted = int64(data["memCommitted"]) ?? 0
        snapshot.commitLimit = int64(data["commitLimit"]) ?? 0
        snapshot.swapTotal = int64(data["swapTotal"]) ?? 0
        snapshot.swapUsed = int64(data["swapUsed"]) ?? 0
        snapshot.poolPaged = int64(data["poolPaged"]) ?? 0
        snapshot.poolNonPaged = int64(data["poolNonPaged"]) ?? 0
        snapshot.netRxBps = int64(data["netRxBps"]) ?? 0
        snapshot.netTxBps = int64(data["netTxBps"]) ?? 0
        snapshot.netRxTotal = int64(data["netRxTotal"]) ?? 0
        snapshot.netTxTotal = int64(data["netTxTotal"]) ?? 0
        snapshot.gpuPercent = (data["gpuPercent"] as? NSNumber)?.doubleValue
        snapshot.gpuName = string(data["gpuName"]).isEmpty ? nil : string(data["gpuName"])
        snapshot.gpuMemBytes = int64(data["gpuMemBytes"]) ?? 0
        snapshot.uptimeSeconds = int64(data["uptimeSeconds"]) ?? 0
        snapshot.processCount = int(data["processCount"]) ?? 0
        snapshot.loadAverage = string(data["loadAverage"]).isEmpty ? nil : string(data["loadAverage"])
        snapshot.disks = (data["disks"] as? [[String: Any]] ?? []).map { disk in
            DiskInfo(
                name: string(disk["name"]),
                detail: string(disk["detail"]),
                totalBytes: int64(disk["totalBytes"]) ?? 0,
                usedBytes: int64(disk["usedBytes"]) ?? 0,
                percent: double(disk["percent"])
            )
        }
        return snapshot
    }

    static func processes(_ data: [String: Any]) -> ([ProcessInfo], Int) {
        let items = (data["items"] as? [[String: Any]] ?? []).compactMap { item -> ProcessInfo? in
            guard let pid = int(item["pid"]), pid > 0 else { return nil }
            return ProcessInfo(
                pid: pid,
                name: string(item["name"]),
                user: string(item["user"]),
                cpuPercent: double(item["cpuPercent"]),
                memBytes: int64(item["memBytes"]) ?? 0,
                command: string(item["command"])
            )
        }
        return (items, int(data["totalCount"]) ?? items.count)
    }

    static func cleanup(_ data: [String: Any]) -> CleanupResult {
        CleanupResult(
            success: data["success"] as? Bool ?? false,
            beforeBytes: int64(data["beforeBytes"]) ?? 0,
            afterBytes: int64(data["afterBytes"]) ?? 0,
            metricLabel: string(data["metricLabel"]).isEmpty ? "可用内存" : string(data["metricLabel"]),
            message: string(data["message"]),
            log: string(data["log"]),
            timeMs: int64(data["timeMs"]) ?? Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    static func netInfo(_ data: [String: Any]) -> NetInfoDetail {
        let wifiData = data["wifi"] as? [String: Any] ?? [:]
        var wifi = WifiDetail()
        wifi.available = wifiData["available"] as? Bool ?? false
        wifi.ssid = string(wifiData["ssid"])
        wifi.bssid = string(wifiData["bssid"])
        wifi.signalPercent = int(wifiData["signalPercent"]) ?? 0
        wifi.radio = string(wifiData["radio"])
        wifi.band = string(wifiData["band"])
        wifi.channel = string(wifiData["channel"])
        wifi.rxRate = string(wifiData["rxRate"])
        wifi.txRate = string(wifiData["txRate"])

        return NetInfoDetail(
            adapters: (data["adapters"] as? [[String: Any]] ?? []).map { item in
                NetAdapterInfo(
                    name: string(item["name"]),
                    mac: string(item["mac"]),
                    ipv4: item["ipv4"] as? [String] ?? [],
                    ipv6: item["ipv6"] as? [String] ?? [],
                    up: item["up"] as? Bool ?? false,
                    mtu: int(item["mtu"]) ?? 0
                )
            },
            wifi: wifi,
            bluetooth: (data["bluetooth"] as? [[String: Any]] ?? []).map { item in
                BluetoothDeviceInfo(
                    name: string(item["name"]),
                    address: string(item["address"]),
                    connected: item["connected"] as? Bool ?? false,
                    kind: string(item["kind"])
                )
            },
            note: string(data["note"])
        )
    }

    static func gpuList(_ data: [String: Any]) -> [GpuDetail] {
        (data["items"] as? [[String: Any]] ?? []).map { item in
            GpuDetail(
                name: string(item["name"]),
                vendor: string(item["vendor"]),
                driver: string(item["driver"]),
                memBytes: int64(item["memBytes"]) ?? 0,
                status: string(item["status"])
            )
        }
    }

    static func sysInfo(_ data: [String: Any]) -> RemoteSysInfo {
        RemoteSysInfo(
            agentVersion: string(data["agentVersion"]),
            protocolVersion: int(data["protocol"]) ?? 0,
            platform: string(data["platform"]),
            arch: string(data["arch"]),
            uptimeSec: int64(data["uptimeSec"]) ?? 0,
            bootTimeSec: int64(data["bootTimeSec"]) ?? 0,
            hostname: string(data["hostname"]),
            osLabel: string(data["osLabel"]),
            kernel: string(data["kernel"]),
            cpuModel: string(data["cpuModel"]),
            cores: int(data["cores"]) ?? 0,
            totalMemBytes: int64(data["totalMemBytes"]) ?? 0
        )
    }

    static func hardware(_ data: [String: Any]) -> HardwareSummary {
        let system = data["system"] as? [String: Any] ?? [:]
        let board = data["board"] as? [String: Any] ?? [:]
        let bios = data["bios"] as? [String: Any] ?? [:]

        var battery: HardwareBattery?
        if let item = data["battery"] as? [String: Any] {
            battery = HardwareBattery(
                name: string(item["name"]),
                percent: int(item["percent"]) ?? 0,
                status: string(item["status"])
            )
        }

        return HardwareSummary(
            systemManufacturer: string(system["manufacturer"]),
            systemModel: string(system["model"]),
            systemSerial: string(system["serial"]),
            boardManufacturer: string(board["manufacturer"]),
            boardProduct: string(board["product"]),
            boardVersion: string(board["version"]),
            boardSerial: string(board["serial"]),
            biosVendor: string(bios["vendor"]),
            biosVersion: string(bios["version"]),
            biosDate: string(bios["date"]),
            memory: (data["memory"] as? [[String: Any]] ?? []).map { item in
                HardwareMemoryModule(
                    slot: string(item["slot"]),
                    sizeBytes: int64(item["sizeBytes"]) ?? 0,
                    speedMhz: int(item["speedMhz"]) ?? 0,
                    manufacturer: string(item["manufacturer"]),
                    partNumber: string(item["partNumber"])
                )
            },
            memoryTotalBytes: int64(data["memoryTotalBytes"]) ?? 0,
            disks: (data["disks"] as? [[String: Any]] ?? []).map { item in
                HardwareDisk(
                    name: string(item["name"]),
                    sizeBytes: int64(item["sizeBytes"]) ?? 0,
                    media: string(item["media"]),
                    interfaceName: string(item["interface"]),
                    serial: string(item["serial"]),
                    health: string(item["health"])
                )
            },
            gpus: (data["gpus"] as? [[String: Any]] ?? []).map { item in
                GpuDetail(
                    name: string(item["name"]),
                    vendor: string(item["vendor"]),
                    driver: string(item["driver"]),
                    memBytes: int64(item["memBytes"]) ?? 0,
                    status: string(item["status"])
                )
            },
            battery: battery
        )
    }

    static func assistantReply(_ data: [String: Any]) -> AssistantReply {
        AssistantReply(
            reply: string(data["reply"]),
            steps: (data["steps"] as? [[String: Any]] ?? []).map { item in
                AssistantStep(
                    tool: string(item["tool"]),
                    args: string(item["args"]),
                    ok: item["ok"] as? Bool ?? false,
                    summary: string(item["summary"])
                )
            },
            model: string(data["model"]),
            elapsedMs: int64(data["elapsedMs"]) ?? 0
        )
    }

    static func aiConfig(_ data: [String: Any]) -> AIConfigInfo {
        let providers = (data["providers"] as? [[String: Any]] ?? []).map { aiProvider($0) }
        let favorites = (data["favorites"] as? [[String: Any]] ?? []).map { row in
            AIFavoriteInfo(
                provider: string(row["provider"]),
                model: string(row["model"]),
                exists: row["exists"] as? Bool ?? true
            )
        }
        return AIConfigInfo(
            active: string(data["active"]),
            providers: providers,
            favorites: favorites,
            maxSteps: int(data["maxSteps"]) ?? 6
        )
    }

    static func aiProvider(_ data: [String: Any]) -> AIProviderInfo {
        AIProviderInfo(
            name: string(data["name"]),
            baseUrl: string(data["baseUrl"]),
            model: string(data["model"]),
            hasKey: data["hasKey"] as? Bool ?? false,
            keyHint: string(data["keyHint"]),
            endpoint: string(data["endpoint"]),
            active: data["active"] as? Bool ?? false
        )
    }

    static func netMode(_ data: [String: Any]) -> NetModeInfo {
        var info = NetModeInfo()
        info.externalEnabled = data["externalEnabled"] as? Bool ?? false
        info.activeName = string(data["activeName"])
        info.admin = data["admin"] as? Bool ?? false
        info.supported = data["supported"] as? Bool ?? true
        info.note = string(data["note"])
        info.adapters = (data["adapters"] as? [[String: Any]] ?? []).map { item in
            var adapter = NetModeAdapter()
            adapter.name = string(item["name"])
            adapter.dhcp = item["dhcp"] as? Bool ?? false
            adapter.ipv4 = item["ipv4"] as? [String] ?? []
            adapter.prefix = int(item["prefix"]) ?? 0
            adapter.mask = string(item["mask"])
            adapter.gateway = item["gateway"] as? [String] ?? []
            adapter.hasGateway = item["hasGateway"] as? Bool ?? false
            adapter.connected = item["connected"] as? Bool ?? false
            return adapter
        }
        return info
    }

    static func listing(_ data: [String: Any]) -> RemoteListing {
        RemoteListing(
            path: string(data["path"]),
            parent: string(data["parent"]),
            entries: (data["entries"] as? [[String: Any]] ?? []).map(file)
        )
    }

    static func file(_ data: [String: Any]) -> RemoteFileEntry {
        RemoteFileEntry(
            name: string(data["name"]),
            path: string(data["path"]),
            isDir: data["dir"] as? Bool ?? false,
            sizeBytes: int64(data["size"]) ?? 0,
            modifiedMs: int64(data["modifiedMs"]) ?? 0
        )
    }
}
