import Foundation
import Combine
import Security

// MARK: - Keychain

/// 只把凭据放进 Keychain；UserDefaults 里仅保存连接元数据。
final class KeychainStore {

    static let shared = KeychainStore()

    private let service = "com.aurora.pcmate"

    private init() {}

    func set(_ value: String, for key: String) {
        guard !value.isEmpty else {
            delete(key)
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    func get(_ key: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - 连接持久化

@MainActor
final class ConnectionStore: ObservableObject {

    @Published private(set) var connections: [Connection] = []

    private let defaultsKey = "pcmate.connections.v1"
    private let keychain = KeychainStore.shared

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Connection].self, from: data) else {
            connections = []
            return
        }
        connections = decoded.map { hydrate($0) }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    func save(_ connection: Connection) {
        var hydrated = connection
        if hydrated.lastUsedAt == 0 {
            hydrated.lastUsedAt = Int64(Date().timeIntervalSince1970 * 1000)
        }

        let secretKeys = [
            "password": hydrated.password,
            "privateKey": hydrated.privateKey,
            "passphrase": hydrated.passphrase,
            "sudoPassword": hydrated.sudoPassword,
            "agentToken": hydrated.agentToken,
            "agentFingerprint": hydrated.agentFingerprint,
            "sshFingerprint": hydrated.sshFingerprint
        ]
        for (name, value) in secretKeys {
            keychain.set(value, for: secretKey(connectionID: hydrated.id, name: name))
        }

        // 内存里保留完整凭据，列表点进去才能直接连接；
        // 落盘时再统一 sanitized()，秘密只留在 Keychain。
        if let index = connections.firstIndex(where: { $0.id == hydrated.id }) {
            connections[index] = hydrated
        } else {
            connections.insert(hydrated, at: 0)
        }
        persist()
    }

    func delete(_ connection: Connection) {
        connections.removeAll { $0.id == connection.id }
        for name in ["password", "privateKey", "passphrase", "sudoPassword", "agentToken", "agentFingerprint", "sshFingerprint"] {
            keychain.delete(secretKey(connectionID: connection.id, name: name))
        }
        persist()
    }

    func touch(_ connection: Connection) {
        var copy = connection
        copy.lastUsedAt = Int64(Date().timeIntervalSince1970 * 1000)
        save(copy)
    }

    func updateFingerprint(connectionID: String, fingerprint: String, transport: Transport) {
        let name = transport == .agent ? "agentFingerprint" : "sshFingerprint"
        keychain.set(fingerprint, for: secretKey(connectionID: connectionID, name: name))
        if let index = connections.firstIndex(where: { $0.id == connectionID }) {
            if transport == .agent {
                connections[index].agentFingerprint = fingerprint
            } else {
                connections[index].sshFingerprint = fingerprint
            }
            persist()
        }
    }

    func hydrate(_ connection: Connection) -> Connection {
        var copy = connection
        copy.password = keychain.get(secretKey(connectionID: connection.id, name: "password"))
        copy.privateKey = keychain.get(secretKey(connectionID: connection.id, name: "privateKey"))
        copy.passphrase = keychain.get(secretKey(connectionID: connection.id, name: "passphrase"))
        copy.sudoPassword = keychain.get(secretKey(connectionID: connection.id, name: "sudoPassword"))
        copy.agentToken = keychain.get(secretKey(connectionID: connection.id, name: "agentToken"))
        copy.agentFingerprint = keychain.get(secretKey(connectionID: connection.id, name: "agentFingerprint"))
        copy.sshFingerprint = keychain.get(secretKey(connectionID: connection.id, name: "sshFingerprint"))
        return copy
    }

    private func persist() {
        let stored = connections.map { $0.sanitized() }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func secretKey(connectionID: String, name: String) -> String {
        "conn.\(connectionID).\(name)"
    }
}
