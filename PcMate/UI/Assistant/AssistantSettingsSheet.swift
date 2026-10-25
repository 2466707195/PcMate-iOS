import SwiftUI

// MARK: - AI 助手设置
//
// 配置存在电脑上的 agent.json（ai 字段），手机端只能读到「有没有 Key」和末 4 位。
// 留空表示不修改，API Key 填 - 表示清空。

struct AssistantPreset: Identifiable {
    let id = UUID()
    var name: String
    var baseUrl: String
    var model: String

    static let all: [AssistantPreset] = [
        AssistantPreset(name: "DeepSeek", baseUrl: "https://api.deepseek.com", model: "deepseek-chat"),
        AssistantPreset(name: "通义千问", baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus"),
        AssistantPreset(name: "硅基流动", baseUrl: "https://api.siliconflow.cn/v1", model: "deepseek-ai/DeepSeek-V3"),
        AssistantPreset(name: "本机 Ollama", baseUrl: "http://127.0.0.1:11434/v1", model: "qwen2.5:7b")
    ]
}

struct AssistantSettingsSheet: View {

    let controller: SessionController?

    @Environment(\.dismiss) private var dismiss

    @State private var baseUrl = ""
    @State private var modelName = ""
    @State private var apiKey = ""
    @State private var hasKey = false
    @State private var keyHint = ""
    @State private var loading = true
    @State private var busy = false
    @State private var notice: String?
    @State private var noticeIsError = false

    var body: some View {
        ZStack {
            AuroraBackdrop()

            AuroraScreen {
                AppTopBar(title: "AI 助手设置", subtitle: "配置只保存在电脑上", onBack: { dismiss() })
            } content: {
                AuroraScrollView(bottomInset: 110) {
                    if let notice {
                        AuroraBanner(
                            systemIcon: noticeIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                            text: notice,
                            tone: noticeIsError ? Aurora.rose : Aurora.teal
                        )
                    }
                    if loading {
                        SectionCard {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small).tint(Aurora.brand)
                                Text("正在读取电脑上的配置…")
                                    .font(AuroraFont.bodySmall)
                                    .foregroundStyle(Aurora.inkSoft)
                                Spacer(minLength: 0)
                            }
                        }
                    } else {
                        presetCard
                        formCard
                        tipsCard
                    }
                }
            } bar: {
                GlassBar {
                    HStack(spacing: 10) {
                        TonalButton(
                            text: busy ? "处理中…" : "测试连接",
                            systemIcon: "bolt.horizontal",
                            enabled: !busy && !loading
                        ) {
                            submit(testAfter: true)
                        }
                        PrimaryButton(
                            text: "保存",
                            systemIcon: "checkmark",
                            enabled: !busy && !loading
                        ) {
                            submit(testAfter: false)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: 快速填写

    private var presetCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "快速填写",
                    subtitle: "点一下自动填好地址和模型，再补 Key",
                    systemIcon: "wand.and.stars",
                    tone: Aurora.brand
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    ForEach(AssistantPreset.all) { preset in
                        Button {
                            baseUrl = preset.baseUrl
                            modelName = preset.model
                            notice = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(AuroraFont.labelMedium)
                                    .foregroundStyle(Aurora.brandDeep)
                                Text(preset.model)
                                    .font(AuroraFont.labelSmall)
                                    .foregroundStyle(Aurora.muted)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Aurora.brand.tint(0.07))
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
            }
        }
    }

    // MARK: 表单

    private var formCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "接口与密钥",
                    subtitle: "OpenAI 兼容接口，地址自填",
                    systemIcon: "key.horizontal",
                    tone: Aurora.teal
                )

                fieldLabel("接口地址")
                AuroraTextField(
                    placeholder: "https://api.deepseek.com",
                    text: $baseUrl,
                    systemIcon: "link"
                )
                Text(endpointPreview)
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .fixedSize(horizontal: false, vertical: true)

                fieldLabel("模型")
                AuroraTextField(
                    placeholder: "deepseek-chat",
                    text: $modelName,
                    systemIcon: "cpu"
                )

                fieldLabel("API Key")
                AuroraTextField(
                    placeholder: hasKey ? "已配置 \(keyHint)（留空不修改）" : "sk-…",
                    text: $apiKey,
                    systemIcon: "key.fill",
                    isSecure: true
                )
                Text("Key 只写进这台电脑的 Agent 配置，手机端拿不到完整内容。填 - 表示清空。")
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tipsCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                AuroraSectionHeader(
                    title: "使用须知",
                    systemIcon: "info.circle",
                    tone: Aurora.info
                )
                tip("接口地址填到域名（https://api.deepseek.com）或 /v1 结尾都行，Agent 会自动补 /chat/completions。")
                tip("工具权限已全部放开：模型可以结束进程、删文件、关机重启。只连自己的电脑。")
                tip("一次提问最多连续调用 6 轮工具；关机或关外网后会立刻结束本轮。")
                tip("需要电脑上运行 Agent 1.6.0 或更高版本。")
            }
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(Aurora.brand.tint(0.5))
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AuroraFont.labelSmall)
            .foregroundStyle(Aurora.muted)
    }

    /// 和 Agent 里 chatEndpoint 同样的补全规则，提前给用户看真实请求地址。
    private var endpointPreview: String {
        let trimmed = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "实际请求：等待填写接口地址" }
        var value = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        if value.hasSuffix("/chat/completions") {
            // 已经填全
        } else if value.hasSuffix("/v1") {
            value += "/chat/completions"
        } else {
            value += "/v1/chat/completions"
        }
        return "实际请求：\(value)"
    }

    // MARK: 读写

    @MainActor
    private func load() async {
        guard let controller else {
            loading = false
            notice = "还没有连接电脑，连接后才能读写模型配置。"
            noticeIsError = true
            return
        }
        do {
            let info = try await controller.assistantConfig()
            apply(info)
        } catch {
            notice = error.localizedDescription + "\n（如果没有这个功能，请把电脑上的 Agent 升级到 1.6.0）"
            noticeIsError = true
        }
        loading = false
    }

    private func apply(_ info: AIConfigInfo) {
        baseUrl = info.baseUrl
        modelName = info.model
        hasKey = info.hasKey
        keyHint = info.keyHint
    }

    @MainActor
    private func submit(testAfter: Bool) {
        guard let controller, !busy else { return }
        busy = true
        notice = nil
        let url = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let info = try await controller.saveAssistantConfig(baseUrl: url, model: model, apiKey: key)
                apply(info)
                apiKey = ""
                notice = "已保存"
                noticeIsError = false
                if testAfter {
                    let result = try await controller.testAssistant()
                    let seconds = String(format: "%.1f", Double(result.elapsedMs) / 1000)
                    var text = "连接正常 · \(result.model) · \(seconds) 秒"
                    if !result.reply.isEmpty {
                        text += "\n模型回复：\(result.reply)"
                    }
                    notice = text
                    noticeIsError = false
                }
            } catch {
                notice = error.localizedDescription
                noticeIsError = true
            }
            busy = false
        }
    }
}
