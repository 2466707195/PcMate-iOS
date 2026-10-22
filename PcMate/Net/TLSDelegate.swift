import Foundation
import CryptoKit
import Security

/// URLSession 的 TLS 校验：Agent 使用自签名证书，信任依据是配对时记录的
/// SHA-256 指纹（TOFU），而不是公共 CA。
final class PinnedTLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {

    private let lock = NSLock()
    private var _capturedFingerprint: String?
    private let expectedFingerprint: String?

    init(expectedFingerprint: String?) {
        self.expectedFingerprint = PinnedTLSDelegate.normalize(expectedFingerprint)
    }

    var capturedFingerprint: String? {
        lock.lock()
        defer { lock.unlock() }
        return _capturedFingerprint
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let fingerprint = PinnedTLSDelegate.fingerprint(of: trust)
        lock.lock()
        _capturedFingerprint = fingerprint
        lock.unlock()

        guard let expected = expectedFingerprint, !expected.isEmpty else {
            // 配对阶段：先接受，随后用服务端返回的 fingerprint 做二次校验。
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        guard let actual = fingerprint, PinnedTLSDelegate.normalize(actual) == expected else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    static func fingerprint(of trust: SecTrust) -> String? {
        guard let certificate = SecTrustGetCertificateAtIndex(trust, 0) else { return nil }
        let data = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: data)
        let base64 = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        return "SHA256:" + base64
    }

    static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("SHA256:") {
            text.removeFirst("SHA256:".count)
        }
        return text.replacingOccurrences(of: "=", with: "")
    }
}
