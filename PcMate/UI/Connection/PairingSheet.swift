import SwiftUI
import UIKit

struct PairingSheet: View {

    let host: String
    let port: Int
    let tls: Bool
    let onPaired: (PairResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var result: PairResult?

    var body: some View {
        ZStack {
            AuroraBackdrop()
            AuroraScreen {
                AppTopBar(
                    title: result == nil ? "配对电脑" : "配对成功",
                    subtitle: result == nil ? "\(host):\(port)" : "凭证已安全保存",
                    onBack: { dismiss() }
                ) {
                    EmptyView()
                }
            } content: {
                AuroraScrollView(bottomInset: 128) {
                    if let result {
                        successCard(result)
                    } else {
                        codeCard
                    }
                }
            } bar: {
                GlassBar {
                    if let result {
                        PrimaryButton(text: "完成", systemIcon: "checkmark") {
                            onPaired(result)
                            dismiss()
                        }
                    } else {
                        GradientButton(
                            text: busy ? "正在配对…" : "开始配对",
                            systemIcon: "link",
                            enabled: code.count == 6 && !busy
                        ) {
                            pair()
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(busy)
    }

    private var codeCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Aurora.brandContainer)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "number.square.fill")
                                .font(.system(size: 23))
                                .foregroundStyle(Aurora.brand)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("输入 6 位配对码")
                            .font(AuroraFont.titleMedium)
                            .foregroundStyle(Aurora.ink)
                        Text("在电脑端 PcMate Agent 的托盘菜单里点击「配对新设备」")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                TextField("000000", text: $code)
                    .keyboardType(.numberPad)
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .foregroundStyle(Aurora.ink)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Aurora.surfaceVariant)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(code.count == 6 ? Aurora.brand.opacity(0.45) : Aurora.line, lineWidth: 1)
                    )
                    .onChange(of: code) { newValue in
                        let filtered = String(newValue.filter { $0.isNumber }.prefix(6))
                        if filtered != newValue { code = filtered }
                    }

                if let errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Aurora.rose)
                            .padding(.top, 1)
                        Text(errorMessage)
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.rose)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Aurora.roseContainer))
                }

                Text("配对码由电脑端生成，5 分钟内有效。配对成功后，iOS 会保存访问令牌和服务器证书指纹。")
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if busy {
                    HStack(spacing: 9) {
                        ProgressView()
                            .tint(Aurora.brand)
                        Text("正在验证证书并交换令牌…")
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.inkSoft)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func successCard(_ result: PairResult) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Aurora.successContainer)
                        .frame(width: 58, height: 58)
                        .overlay(
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Aurora.success)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.hostInfo?.hostname.isEmpty == false ? (result.hostInfo?.hostname ?? "电脑") : "电脑")
                            .font(AuroraFont.titleLarge)
                            .foregroundStyle(Aurora.ink)
                        Text("已建立信任，可以开始远程管理")
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.inkSoft)
                    }
                }

                if let info = result.hostInfo {
                    infoRow("系统", info.osLabel.isEmpty ? info.osShort : info.osLabel)
                    infoRow("CPU", info.cpuModel.isEmpty ? "—" : info.cpuModel)
                    infoRow("内存", Fmt.bytes(info.totalMemBytes))
                }
                infoRow("Agent 端口", String(result.port))

                VStack(alignment: .leading, spacing: 4) {
                    Text("证书指纹（SHA-256）")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                    Text(result.fingerprint.isEmpty ? "—" : result.fingerprint)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Aurora.inkSoft)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Aurora.surfaceVariant))
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.muted)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func pair() {
        guard code.count == 6, !busy else { return }
        busy = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let paired = try await AgentPairing.pair(host: host, port: port, code: code, tls: tls)
                result = paired
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = false
        }
    }
}
