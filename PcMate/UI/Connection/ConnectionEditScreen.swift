import SwiftUI
import UIKit

struct ConnectionEditScreen: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ConnectionStore

    private let original: Connection?
    @State private var draft: Connection
    @State private var showPairing = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false

    init(connection: Connection?) {
        self.original = connection
        _draft = State(initialValue: connection ?? Connection(name: "我的电脑", host: ""))
    }

    private var isEditing: Bool { original != nil }

    var body: some View {
        ZStack {
            AuroraBackdrop()
            AuroraScreen {
                AppTopBar(
                    title: isEditing ? "编辑电脑" : "添加电脑",
                    subtitle: "Agent 优先 · SSH 回退",
                    onBack: { dismiss() }
                ) {
                    TextLinkButton(text: "保存") { save() }
                }
            } content: {
                AuroraScrollView(bottomInset: 128) {
                    basicSection
                    transportSection

                    if draft.transport == .agent {
                        agentSection
                    }

                    sshSection
                    settingsSection
                    securitySection
                }
            } bar: {
                GlassBar {
                    HStack(spacing: 10) {
                        if isEditing {
                            DangerTonalButton(text: "删除", systemIcon: "trash") {
                                showDeleteConfirm = true
                            }
                        }
                        PrimaryButton(text: "保存", systemIcon: "checkmark") {
                            save()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPairing) {
            PairingSheet(
                host: normalizedHost,
                port: draft.agentPort,
                tls: draft.agentTls
            ) { result in
                draft.agentToken = result.token
                draft.agentFingerprint = result.fingerprint
                draft.agentPort = result.port
                draft.agentTls = result.tls
                if draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.name == "我的电脑" {
                    draft.name = result.name.isEmpty ? (result.hostInfo?.hostname ?? "我的电脑") : result.name
                }
                if let host = result.hostInfo?.hostname, !host.isEmpty, draft.host.isEmpty {
                    draft.host = host
                }
                showPairing = false
            }
        }
        .alert("无法保存", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("删除这台电脑？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let original { store.delete(original) }
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("连接信息和 Keychain 中的密码、令牌都会删除。")
        }
    }

    // MARK: 基本信息

    private var basicSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 13) {
                fieldLabel("名称")
                AuroraTextField(
                    placeholder: "例如：书房电脑",
                    text: $draft.name,
                    systemIcon: "desktopcomputer"
                )

                fieldLabel("电脑地址")
                AuroraTextField(
                    placeholder: "IP 或主机名，例如 192.168.2.195",
                    text: $draft.host,
                    systemIcon: "network"
                )
                Text("iOS 与电脑需要在同一个局域网。也可以填电脑的 mDNS 名称。")
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
            }
        }
    }

    // MARK: 传输方式

    private var transportSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("连接方式")
                    .font(AuroraFont.titleMedium)
                    .foregroundStyle(Aurora.ink)

                HStack(spacing: 8) {
                    ForEach(Transport.allCases) { transport in
                        Button {
                            draft.transport = transport
                        } label: {
                            VStack(spacing: 3) {
                                HStack(spacing: 5) {
                                    Image(systemName: transport == .agent ? "bolt.horizontal.fill" : "terminal.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(transport.label)
                                        .font(AuroraFont.labelLarge)
                                }
                                Text(transport == .agent ? "实时推送，推荐" : "通用回退")
                                    .font(AuroraFont.labelSmall)
                                    .opacity(0.75)
                            }
                            .foregroundStyle(draft.transport == transport ? Aurora.onBrandContainer : Aurora.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(draft.transport == transport ? Aurora.brandContainer : Aurora.surfaceVariant)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(draft.transport == transport ? Aurora.brand.opacity(0.35) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Agent

    private var agentSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Agent")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                    Spacer()
                    Text("WebSocket + HTTPS")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.brand)
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel("端口")
                        AuroraTextField(
                            placeholder: "8765",
                            text: Binding(
                                get: { String(draft.agentPort) },
                                set: { draft.agentPort = Int($0) ?? 8765 }
                            ),
                            systemIcon: "number",
                            keyboardType: .numberPad
                        )
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel("采集间隔")
                        AuroraTextField(
                            placeholder: "500",
                            text: Binding(
                                get: { String(draft.agentIntervalMs) },
                                set: { draft.agentIntervalMs = Int($0) ?? 500 }
                            ),
                            systemIcon: "timer",
                            keyboardType: .numberPad
                        )
                    }
                }

                Toggle(isOn: $draft.agentTls) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("使用 TLS")
                            .font(AuroraFont.bodyMedium)
                            .foregroundStyle(Aurora.ink)
                        Text("Agent 默认自签名证书，首次连接会固定指纹")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                    }
                }
                .tint(Aurora.brand)

                fieldLabel("访问令牌")
                AuroraTextField(
                    placeholder: "配对后自动填入",
                    text: $draft.agentToken,
                    systemIcon: "key.fill",
                    isSecure: true
                )

                if draft.agentToken.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Aurora.warning)
                        Text("还没有令牌，请用 6 位配对码连接一次。")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.warning)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Aurora.warningContainer))
                }

                TonalButton(text: "用 6 位配对码连接", systemIcon: "number.square.fill") {
                    guard validateHost() else { return }
                    showPairing = true
                }
            }
        }
    }

    // MARK: SSH

    private var sshSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text(draft.transport == .agent ? "SSH 回退（可选）" : "SSH")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                    Spacer()
                    Text("SFTP")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.teal)
                }

                if draft.transport == .agent {
                    Toggle(isOn: $draft.allowSshFallback) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Agent 失败时自动回退 SSH")
                                .font(AuroraFont.bodyMedium)
                                .foregroundStyle(Aurora.ink)
                            Text("需要电脑已开启 OpenSSH 服务")
                                .font(AuroraFont.labelSmall)
                                .foregroundStyle(Aurora.muted)
                        }
                    }
                    .tint(Aurora.teal)
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel("SSH 端口")
                        AuroraTextField(
                            placeholder: "22",
                            text: Binding(
                                get: { String(draft.port) },
                                set: { draft.port = Int($0) ?? 22 }
                            ),
                            systemIcon: "number",
                            keyboardType: .numberPad
                        )
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel("用户名")
                        AuroraTextField(
                            placeholder: "Windows: 用户名",
                            text: $draft.username,
                            systemIcon: "person.fill"
                        )
                    }
                }

                HStack(spacing: 8) {
                    ForEach(AuthType.allCases) { type in
                        Button {
                            draft.authType = type
                        } label: {
                            Text(type.label)
                                .font(AuroraFont.labelLarge)
                                .foregroundStyle(draft.authType == type ? Aurora.onTealContainer : Aurora.inkSoft)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(draft.authType == type ? Aurora.tealContainer : Aurora.surfaceVariant)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if draft.authType == .password {
                    fieldLabel("密码")
                    AuroraTextField(
                        placeholder: "SSH 登录密码",
                        text: $draft.password,
                        systemIcon: "lock.fill",
                        isSecure: true
                    )
                } else {
                    fieldLabel("OpenSSH 私钥")
                    TextEditor(text: $draft.privateKey)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Aurora.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 112)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Aurora.surfaceVariant))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Aurora.line, lineWidth: 1)
                        )
                        .overlay(alignment: .topLeading) {
                            if draft.privateKey.isEmpty {
                                Text("-----BEGIN OPENSSH PRIVATE KEY-----")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(Aurora.muted)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }

                    fieldLabel("私钥密码（可选）")
                    AuroraTextField(
                        placeholder: "没有就留空",
                        text: $draft.passphrase,
                        systemIcon: "key.horizontal.fill",
                        isSecure: true
                    )
                }

                fieldLabel("sudo 密码（可选）")
                AuroraTextField(
                    placeholder: "Linux 清理缓存时使用",
                    text: $draft.sudoPassword,
                    systemIcon: "lock.rotation",
                    isSecure: true
                )
            }
        }
    }

    // MARK: 刷新与安全

    private var settingsSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("刷新")
                    .font(AuroraFont.titleMedium)
                    .foregroundStyle(Aurora.ink)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel("仪表盘刷新间隔（秒）")
                        AuroraTextField(
                            placeholder: "2",
                            text: Binding(
                                get: { String(draft.refreshSeconds) },
                                set: { draft.refreshSeconds = max(1, min(30, Int($0) ?? 2)) }
                            ),
                            systemIcon: "arrow.clockwise",
                            keyboardType: .numberPad
                        )
                    }
                }
                Text("Agent 会主动推送快照；SSH 模式按这个间隔执行采样命令。")
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
            }
        }
    }

    private var securitySection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(Aurora.success)
                    Text("安全")
                        .font(AuroraFont.titleMedium)
                        .foregroundStyle(Aurora.ink)
                }
                Text("密码、私钥和 Agent 令牌只保存在 iOS Keychain；UserDefaults 只存连接元数据。TLS 证书和 SSH 主机密钥都按首次信任的 SHA-256 指纹固定。")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                if !draft.agentFingerprint.isEmpty {
                    fingerprintRow(label: "TLS 指纹", value: draft.agentFingerprint)
                }
                if !draft.sshFingerprint.isEmpty {
                    fingerprintRow(label: "SSH 指纹", value: draft.sshFingerprint)
                }
            }
        }
    }

    private func fingerprintRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(AuroraFont.labelSmall)
                .foregroundStyle(Aurora.muted)
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Aurora.inkSoft)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(.top, 3)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AuroraFont.labelMedium)
            .foregroundStyle(Aurora.inkSoft)
    }

    // MARK: 保存

    private var normalizedHost: String {
        draft.host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// 允许用户直接粘贴 `192.168.2.195:8765` 或带协议的地址：
    /// 去掉协议、路径和端口，端口写回 Agent 端口。
    private func validateHost() -> Bool {
        var raw = normalizedHost
        if let slash = raw.firstIndex(of: "/") {
            raw = String(raw[..<slash])
        }
        let colonCount = raw.filter { $0 == ":" }.count
        if colonCount == 1, let colon = raw.lastIndex(of: ":") {
            let portText = String(raw[raw.index(after: colon)...])
            if let port = Int(portText), (1...65535).contains(port) {
                if draft.transport == .ssh {
                    draft.port = port
                } else {
                    draft.agentPort = port
                }
                raw = String(raw[..<colon])
            }
        }
        draft.host = raw
        if raw.isEmpty {
            errorMessage = "请先填写电脑的 IP 或主机名。"
            return false
        }
        return true
    }

    private func save() {
        guard validateHost() else { return }
        guard (1...65535).contains(draft.agentPort) else {
            errorMessage = "Agent 端口需要在 1-65535 之间。"
            return
        }
        guard (1...65535).contains(draft.port) else {
            errorMessage = "SSH 端口需要在 1-65535 之间。"
            return
        }
        if draft.transport == .ssh {
            guard !draft.username.trimmingCharacters(in: .whitespaces).isEmpty else {
                errorMessage = "SSH 连接需要用户名。"
                return
            }
            guard !draft.password.isEmpty || !draft.privateKey.isEmpty else {
                errorMessage = "SSH 连接需要密码或 OpenSSH 私钥。"
                return
            }
        }
        draft.host = normalizedHost
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.name = draft.host
        }
        store.save(draft)
        dismiss()
    }
}
