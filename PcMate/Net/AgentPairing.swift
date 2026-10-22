import Foundation

enum AgentPairing {

    static func pair(host: String, port: Int, code: String, tls: Bool) async throws -> PairResult {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw PcMateError.message("请填写电脑的 IP 或主机名")
        }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count == 6, trimmedCode.allSatisfy({ $0.isNumber }) else {
            throw PcMateError.message("请输入电脑上显示的 6 位配对码")
        }
        guard (1...65535).contains(port) else {
            throw PcMateError.message("Agent 端口需要在 1-65535 之间")
        }

        var components = URLComponents()
        components.scheme = tls ? "https" : "http"
        components.host = trimmedHost
        components.port = port
        components.path = "/pair"
        guard let url = components.url else {
            throw PcMateError.message("电脑地址无效")
        }

        let delegate = PinnedTLSDelegate(expectedFingerprint: nil)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": trimmedCode])

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if http.statusCode == 401 {
                throw PcMateError.message("配对码不正确，请在电脑上重新查看")
            }
            if http.statusCode == 429 {
                throw PcMateError.message(text.isEmpty ? "尝试次数过多，请 5 分钟后再试" : text)
            }
            throw PcMateError.message(text.isEmpty ? "配对失败（HTTP \(http.statusCode)）" : text)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PcMateError.message("电脑返回的配对结果格式不正确")
        }
        let token = AgentParser.string(object["token"])
        guard !token.isEmpty else {
            throw PcMateError.message("配对成功但电脑没有返回凭证")
        }
        let serverFingerprint = AgentParser.string(object["fingerprint"])
        if let captured = delegate.capturedFingerprint,
           !serverFingerprint.isEmpty,
           PinnedTLSDelegate.normalize(captured) != PinnedTLSDelegate.normalize(serverFingerprint) {
            throw PcMateError.tlsFingerprintMismatch(expected: serverFingerprint, actual: captured)
        }

        let hostObject = object["host"] as? [String: Any] ?? [:]
        return PairResult(
            token: token,
            fingerprint: serverFingerprint.isEmpty ? (delegate.capturedFingerprint ?? "") : serverFingerprint,
            name: AgentParser.string(object["name"]),
            hostInfo: hostObject.isEmpty ? nil : AgentParser.host(hostObject),
            port: AgentParser.int(object["port"]) ?? port,
            tls: object["tls"] as? Bool ?? tls
        )
    }
}
