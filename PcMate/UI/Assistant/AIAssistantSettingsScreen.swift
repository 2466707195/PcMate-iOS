import SwiftUI

// MARK: - AI 助手设置（模型服务商管理）
//
// 从「设置 → AI 助手」进来。配置全部存在电脑上的 agent.json 里，
// 手机端只能读到「有没有 Key」和末 4 位，拿不到明文。
//
// 能做的事：
//   · 配很多家服务商（名称 + 接口地址 + Key），一键切换当前生效的那家
//   · 填好地址和 Key 后「获取模型列表」，列出服务商的所有模型
//   · 每个模型上都有「测试」和「添加为常用模型」
//   · 常用模型跨服务商保存，点一下就直接当成当前模型用

struct AIAssistantSettingsScreen: View {

    let controller: SessionController?

    @Environment(\.dismiss) private var dismiss

    @State private var config: AIConfigInfo?
    @State private var loading = true
    @State private var notice: String?
    @State private var noticeIsError = false
    @State private var showEditor = false
    @State private var editing: AIProviderInfo?
    @State private var modelSheet: AIModelSheetContext?
    @State private var testingFavorite: String?
    @State private var deleting: String?

    var body: some View {
        ZStack {
            AuroraBackdrop()

            AuroraScreen {
                AppTopBar(title: "AI 助手", subtitle: "模型与密钥只保存在电脑上", onBack: { dismiss() }) {
                    AuroraIconButton(systemIcon: "arrow.clockwise", size: 34, enabled: !loading) {
                        Task { await reload() }
                    }
                }
            } content: {
                AuroraScrollView(bottomInset: 60) {
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
                        if let notice {
                            VStack(alignment: .leading, spacing: 8) {
                                AuroraBanner(
                                    systemIcon: noticeIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                                    text: notice,
                                    tone: noticeIsError ? Aurora.rose : Aurora.teal
                                )
                                if noticeIsError {
                                    TonalButton(
                                        text: "重试",
                                        systemIcon: "arrow.clockwise",
                                        enabled: !loading
                                    ) {
                                        Task { await reload() }
                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        }
                        activeCard
                        favoritesCard
                        providersCard
                        tipsCard
                    }
                }
            } bar: {
                EmptyView()
            }
        }
        .task { await reload() }
        .sheet(isPresented: $showEditor) {
            AIProviderEditorSheet(
                controller: controller,
                provider: editing,
                onSaved: { Task { await reload() } },
                onFetchModels: { providerName, url, key in
                    // 先把这家服务商存下来：模型列表里点某个模型时，
                    // 要能直接把它设成当前模型，没保存过的服务商是设不动的。
                    Task {
                        _ = try? await controller?.saveAIProvider(
                            name: providerName, baseUrl: url, apiKey: key, model: "", setActive: true
                        )
                        await reload()
                        modelSheet = AIModelSheetContext(
                            providerName: providerName,
                            baseUrl: url,
                            apiKey: key
                        )
                    }
                }
            )
        }
        .sheet(item: $modelSheet) { context in
            AIModelListSheet(
                controller: controller,
                providerName: context.providerName,
                baseUrl: context.baseUrl,
                apiKey: context.apiKey,
                onChanged: { Task { await reload() } }
            )
        }
    }

    // MARK: 当前生效

    @ViewBuilder
    private var activeCard: some View {
        if let config, let active = config.activeProvider {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    AuroraSectionHeader(
                        title: "当前生效",
                        subtitle: "助手页现在用这一家 + 这一个模型",
                        systemIcon: "bolt.horizontal.fill",
                        tone: Aurora.teal
                    )

                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Aurora.teal.tint(0.13))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Aurora.teal)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(active.name)
                                .font(AuroraFont.titleSmall)
                                .foregroundStyle(Aurora.ink)
                            Text(active.model.isEmpty ? "还没选模型" : active.model)
                                .font(AuroraFont.labelMedium)
                                .foregroundStyle(Aurora.teal)
                                .lineLimit(1)
                            Text(active.keyLabel)
                                .font(AuroraFont.labelSmall)
                                .foregroundStyle(Aurora.muted)
                        }

                        Spacer(minLength: 4)

                        TonalButton(
                            text: "获取模型",
                            systemIcon: "square.and.arrow.down",
                            enabled: active.hasKey
                        ) {
                            modelSheet = AIModelSheetContext(
                                providerName: active.name,
                                baseUrl: active.baseUrl,
                                apiKey: ""
                            )
                        }
                    }

                    Text(active.endpoint)
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        } else {
            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    AuroraSectionHeader(
                        title: "还没有可用的服务商",
                        subtitle: "填好接口地址和 Key 就能开始",
                        systemIcon: "exclamationmark.triangle.fill",
                        tone: Aurora.warning
                    )
                    Text("AI 助手需要一家 OpenAI 兼容的模型服务。点下面的「添加服务商」，或者直接点快速预设。")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(text: "添加服务商", systemIcon: "plus") {
                        editing = nil
                        showEditor = true
                    }
                }
            }
        }
    }

    // MARK: 常用模型

    @ViewBuilder
    private var favoritesCard: some View {
        if let config, !config.favorites.isEmpty {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    AuroraSectionHeader(
                        title: "常用模型",
                        subtitle: "点一下就用这个模型提问",
                        systemIcon: "star.fill",
                        tone: Aurora.brand
                    )

                    VStack(spacing: 0) {
                        ForEach(config.favorites.indices, id: \.self) { index in
                            if index > 0 {
                                Divider().overlay(Aurora.hairline)
                            }
                            let favorite = config.favorites[index]
                            favoriteRow(favorite, active: config.activeProvider?.name == favorite.provider
                                && config.activeProvider?.model == favorite.model)
                        }
                    }
                }
            }
        }
    }

    private func favoriteRow(_ favorite: AIFavoriteInfo, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: active ? "checkmark.circle.fill" : "star.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? Aurora.teal : Aurora.brand)

                VStack(alignment: .leading, spacing: 2) {
                    Text(favorite.model)
                        .font(AuroraFont.titleSmall)
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                    Text(favorite.exists ? favorite.provider : "\(favorite.provider)（服务商已删除）")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(favorite.exists ? Aurora.muted : Aurora.rose)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if active {
                    Text("使用中")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.teal)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Aurora.teal.tint(0.12)))
                }
            }

            HStack(spacing: 8) {
                SmallTonalButton(
                    text: testingFavorite == favorite.id ? "测试中…" : "测试",
                    systemIcon: "bolt.horizontal",
                    enabled: testingFavorite == nil && favorite.exists
                ) {
                    Task { await testFavorite(favorite) }
                }

                SmallTonalButton(
                    text: "移除",
                    systemIcon: "star.slash",
                    enabled: testingFavorite == nil
                ) {
                    Task { await removeFavorite(favorite) }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            guard favorite.exists else { return }
            Task { await useFavorite(favorite) }
        }
    }

    // MARK: 服务商列表

    private var providersCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "模型服务商",
                    subtitle: "可以配很多家，随时切换",
                    systemIcon: "building.2",
                    tone: Aurora.brand
                )

                if let config, !config.providers.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(config.providers.indices, id: \.self) { index in
                            if index > 0 {
                                Divider().overlay(Aurora.hairline)
                            }
                            providerRow(config.providers[index])
                        }
                    }
                } else {
                    Text("一家都还没配。")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.muted)
                }

                PrimaryButton(text: "添加服务商", systemIcon: "plus") {
                    editing = nil
                    showEditor = true
                }
            }
        }
    }

    private func providerRow(_ provider: AIProviderInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((provider.active ? Aurora.teal : Aurora.brand).tint(0.13))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: provider.active ? "checkmark.circle.fill" : "server.rack")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(provider.active ? Aurora.teal : Aurora.brand)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(AuroraFont.titleSmall)
                            .foregroundStyle(Aurora.ink)
                        if provider.active {
                            Text("当前")
                                .font(AuroraFont.labelSmall)
                                .foregroundStyle(Aurora.teal)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Aurora.teal.tint(0.12)))
                        }
                    }
                    Text(provider.subtitle)
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(1)
                    Text(provider.keyLabel)
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(provider.hasKey ? Aurora.muted : Aurora.rose)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: 8) {
                if !provider.active {
                    SmallTonalButton(
                        text: "设为当前",
                        systemIcon: "checkmark.circle",
                        enabled: !busy
                    ) {
                        Task { await makeActive(provider) }
                    }
                }

                SmallTonalButton(
                    text: "编辑",
                    systemIcon: "pencil",
                    enabled: !busy
                ) {
                    editing = provider
                    showEditor = true
                }

                SmallTonalButton(
                    text: deleting == provider.name ? "删除中…" : "删除",
                    systemIcon: "trash",
                    enabled: deleting == nil && !busy
                ) {
                    Task { await removeProvider(provider) }
                }

                Spacer(minLength: 0)

                SmallTonalButton(
                    text: "获取模型",
                    systemIcon: "square.and.arrow.down",
                    enabled: provider.hasKey && !busy
                ) {
                    modelSheet = AIModelSheetContext(
                        providerName: provider.name,
                        baseUrl: provider.baseUrl,
                        apiKey: ""
                    )
                }
            }
        }
        .padding(.vertical, 9)
    }

    // MARK: 说明

    private var tipsCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                AuroraSectionHeader(
                    title: "使用须知",
                    systemIcon: "info.circle",
                    tone: Aurora.info
                )
                tip("接口地址填域名（https://api.deepseek.com）或 /v1 结尾都行，Agent 会自动补 /chat/completions。")
                tip("Key 只写进这台电脑的 Agent 配置，手机端拿不到明文；编辑时留空表示不修改，填 - 表示清空。")
                tip("有的服务商不支持 /models，拉不到列表时可以手填模型名，再用「测试」确认能用。")
                tip("工具权限已全部放开：模型可以结束进程、删文件、关机。只把自己的电脑配给助手用。")
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

    // MARK: 动作

    private var busy: Bool { loading || testingFavorite != nil || deleting != nil }

    @MainActor
    private func reload() async {
        loading = true
        notice = nil
        noticeIsError = false
        do {
            config = try await controller?.aiConfig()
        } catch {
            notice = friendly(error)
            noticeIsError = true
        }
        loading = false
    }

    @MainActor
    private func makeActive(_ provider: AIProviderInfo) async {
        guard !busy else { return }
        notice = nil
        noticeIsError = false
        do {
            config = try await controller?.selectAIProvider(name: provider.name)
            notice = "已切换到「\(provider.name)」"
            noticeIsError = false
        } catch {
            notice = friendly(error)
            noticeIsError = true
        }
    }

    @MainActor
    private func removeProvider(_ provider: AIProviderInfo) async {
        guard deleting == nil else { return }
        deleting = provider.name
        notice = nil
        noticeIsError = false
        defer { deleting = nil }
        do {
            try await controller?.deleteAIProvider(name: provider.name)
            config = try await controller?.aiConfig()
            notice = "已删除「\(provider.name)」"
            noticeIsError = false
        } catch {
            notice = friendly(error)
            noticeIsError = true
        }
    }

    @MainActor
    private func useFavorite(_ favorite: AIFavoriteInfo) async {
        guard !busy else { return }
        notice = nil
        noticeIsError = false
        do {
            config = try await controller?.setProviderModel(name: favorite.provider, model: favorite.model)
            notice = "已选用「\(favorite.model)」"
            noticeIsError = false
        } catch {
            notice = friendly(error)
            noticeIsError = true
        }
    }

    @MainActor
    private func testFavorite(_ favorite: AIFavoriteInfo) async {
        guard testingFavorite == nil else { return }
        testingFavorite = favorite.id
        notice = nil
        noticeIsError = false
        defer { testingFavorite = nil }
        do {
            let result = try await controller?.testAIModel(
                name: favorite.provider, model: favorite.model, baseUrl: "", apiKey: ""
            )
            notice = testNotice(result, fallbackModel: favorite.model)
            noticeIsError = false
        } catch {
            notice = friendly(error)
            noticeIsError = true
        }
    }

    @MainActor
    private func removeFavorite(_ favorite: AIFavoriteInfo) async {
        guard testingFavorite == nil else { return }
        notice = nil
        noticeIsError = false
        do {
            config = try await controller?.removeAIFavorite(name: favorite.provider, model: favorite.model)
            notice = "已从常用模型移除「\(favorite.model)」"
            noticeIsError = false
        } catch {
            notice = friendly(error)
            noticeIsError = true
        }
    }

    /// 把错误翻译成用户能照着做的话；连接类错误给重试提示。
    private func friendly(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("软件导致连接中止")
            || text.contains("网络连接已丢失")
            || text.contains("连接已断开")
            || text.contains("Agent 连接已断开") {
            return "和电脑的连接中断了（\(text)）。\n检查手机和电脑是否还在同一个 Wi-Fi，然后点「重试」。"
        }
        if text.contains("未知操作") {
            return "\(text)\n电脑上的 Agent 太旧了，请升级到 1.6.0 或更高版本。"
        }
        return text
    }

    private func testNotice(_ result: AIModelTestResult?, fallbackModel: String) -> String {
        guard let result else { return "没有连接" }
        let seconds = String(format: "%.1f", Double(result.elapsedMs) / 1000)
        var text = "「\(result.model.isEmpty ? fallbackModel : result.model)」连接正常 · \(seconds) 秒"
        if !result.reply.isEmpty {
            text += "\n模型回复：\(result.reply)"
        }
        return text
    }
}

/// 打开模型列表时带的上下文：要拉哪一家的模型。
struct AIModelSheetContext: Identifiable {
    let id = UUID()
    var providerName: String
    var baseUrl: String
    var apiKey: String
}

/// 编辑页里的快速预设。
private struct PresetItem: Identifiable {
    let id = UUID()
    var name: String
    var url: String
    var model: String
}

// MARK: - 服务商编辑

struct AIProviderEditorSheet: View {

    let controller: SessionController?
    /// nil 表示新建
    let provider: AIProviderInfo?
    let onSaved: () -> Void
    /// 让外层打开模型列表（服务商名、地址、Key）
    let onFetchModels: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var baseUrl = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var hasKey = false
    @State private var keyHint = ""
    @State private var notice: String?
    @State private var noticeIsError = false
    @State private var saving = false
    @State private var testing = false
    @FocusState private var focus: Field?

    private enum Field { case name, url, key, model }

    private let presets: [PresetItem] = [
        PresetItem(name: "DeepSeek", url: "https://api.deepseek.com", model: "deepseek-chat"),
        PresetItem(name: "通义千问", url: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus"),
        PresetItem(name: "硅基流动", url: "https://api.siliconflow.cn/v1", model: "deepseek-ai/DeepSeek-V3"),
        PresetItem(name: "本机 Ollama", url: "http://127.0.0.1:11434/v1", model: "qwen2.5:7b")
    ]

    var body: some View {
        ZStack {
            AuroraBackdrop()

            AuroraScreen {
                AppTopBar(
                    title: provider == nil ? "添加服务商" : "编辑服务商",
                    subtitle: provider == nil ? "填地址和 Key，然后拉模型列表" : "留空的项表示不修改",
                    onBack: { dismiss() }
                )
            } content: {
                AuroraScrollView(bottomInset: 100) {
                    if let notice {
                        AuroraBanner(
                            systemIcon: noticeIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                            text: notice,
                            tone: noticeIsError ? Aurora.rose : Aurora.teal
                        )
                    }

                    presetCard
                    formCard

                    PrimaryButton(
                        text: saving ? "保存中…" : "保存",
                        systemIcon: "checkmark",
                        enabled: !saving && !testing
                    ) {
                        Task { await submit() }
                    }

                    TonalButton(
                        text: testing ? "测试中…" : "测试这个模型",
                        systemIcon: "bolt.horizontal",
                        enabled: !saving && !testing && !model.trimmed.isEmpty
                    ) {
                        Task { await test() }
                    }

                    Button {
                        Task { await fetchModels() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                            Text("获取模型列表")
                                .font(AuroraFont.labelLarge)
                        }
                        .foregroundStyle(Aurora.brandDeep)
                        .frame(maxWidth: .infinity)
                        .frame(height: AuroraMetrics.primaryButtonHeight)
                        .background(
                            AuroraShape.button
                                .fill(Aurora.brand.tint(0.10))
                        )
                        .overlay(
                            AuroraShape.button.stroke(Aurora.brand.opacity(0.25), lineWidth: 1)
                        )
                        .contentShape(AuroraShape.button)
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(saving || testing)

                    Text("填好地址和 Key 之后，「获取模型列表」会把这家服务商的所有模型列出来，每个模型都能单独测试、添加为常用。")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } bar: {
                EmptyView()
            }
        }
        .onAppear { fill() }
    }

    // MARK: 预设

    private var presetCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "快速填写",
                    subtitle: "点一下填好地址和模型，再补 Key",
                    systemIcon: "wand.and.stars",
                    tone: Aurora.brand
                )
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(presets) { preset in
                        Button {
                            if name.trimmed.isEmpty { name = preset.name }
                            baseUrl = preset.url
                            if model.trimmed.isEmpty { model = preset.model }
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

                fieldLabel("名称（随便起，比如「公司的 Key」）")
                AuroraTextField(placeholder: "DeepSeek", text: $name, systemIcon: "tag")
                    .focused($focus, equals: .name)

                fieldLabel("接口地址")
                AuroraTextField(
                    placeholder: "https://api.deepseek.com",
                    text: $baseUrl,
                    systemIcon: "link",
                    keyboardType: .URL
                )
                .focused($focus, equals: .url)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                Text(endpointPreview)
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .fixedSize(horizontal: false, vertical: true)

                fieldLabel("API Key")
                AuroraTextField(
                    placeholder: hasKey ? "已配置 \(keyHint)（留空不修改）" : "sk-…",
                    text: $apiKey,
                    systemIcon: "key.fill",
                    isSecure: true
                )
                .focused($focus, equals: .key)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                Text("填 - 表示清空已保存的 Key。")
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)

                fieldLabel("当前模型（可以先不填，用「获取模型列表」选）")
                AuroraTextField(
                    placeholder: "deepseek-chat",
                    text: $model,
                    systemIcon: "cpu"
                )
                .focused($focus, equals: .model)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AuroraFont.labelSmall)
            .foregroundStyle(Aurora.muted)
            .fixedSize(horizontal: false, vertical: true)
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

    private func fill() {
        guard let provider else { return }
        name = provider.name
        baseUrl = provider.baseUrl
        model = provider.model
        hasKey = provider.hasKey
        keyHint = provider.keyHint
    }

    // MARK: 动作

    @MainActor
    private func submit() async {
        guard !saving, !testing else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            notice = "先给这个服务商起个名字"
            noticeIsError = true
            return
        }
        saving = true
        notice = nil
        noticeIsError = false
        let url = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)

        defer { saving = false }
        do {
            let saved = try await controller?.saveAIProvider(
                name: trimmedName, baseUrl: url, apiKey: key, model: modelName, setActive: true
            )
            notice = "已保存「\(saved?.name ?? trimmedName)」"
            noticeIsError = false
            onSaved()
            dismiss()
        } catch {
            notice = friendly(error)
            noticeIsError = true
        }
    }

    @MainActor
    private func test() async {
        guard !saving, !testing else { return }
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            notice = "先填模型名，或者用「获取模型列表」选一个"
            noticeIsError = true
            return
        }
        testing = true
        notice = nil
        noticeIsError = false
        let url = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        defer { testing = false }
        do {
            let result = try await controller?.testAIModel(
                name: providerName, model: modelName, baseUrl: url, apiKey: key
            )
            let seconds = String(format: "%.1f", Double(result?.elapsedMs ?? 0) / 1000)
            var text = "「\(modelName)」连接正常 · \(seconds) 秒"
            if let reply = result?.reply, !reply.isEmpty {
                text += "\n模型回复：\(reply)"
            }
            notice = text
            noticeIsError = false
        } catch {
            notice = friendly(error)
            noticeIsError = true
        }
    }

    @MainActor
    private func fetchModels() async {
        guard !saving, !testing else { return }
        let url = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            notice = "先填接口地址"
            noticeIsError = true
            return
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty && !hasKey {
            notice = "先填 API Key"
            noticeIsError = true
            return
        }
        // 交给外层打开模型列表页，由它自己去拉
        onFetchModels(
            name.trimmingCharacters(in: .whitespacesAndNewlines),
            url,
            key
        )
    }

    private func friendly(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("软件导致连接中止")
            || text.contains("网络连接已丢失")
            || text.contains("连接已断开")
            || text.contains("Agent 连接已断开") {
            return "和电脑的连接中断了（\(text)）。\n检查手机和电脑是否还在同一个 Wi-Fi，然后重试。"
        }
        if text.contains("未知操作") {
            return "\(text)\n电脑上的 Agent 太旧了，请升级到 1.6.0 或更高版本。"
        }
        return text
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
