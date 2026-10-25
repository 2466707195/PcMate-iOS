import SwiftUI

// MARK: - 模型列表
//
// 填好接口地址和 Key 之后，把这家服务商的模型全拉出来。
// 每一行都有两个按钮：「测试」当场试通不通，「添加为常用模型」收进常用列表；
// 点整行就是直接把这个模型设成当前要用的。

struct AIModelListSheet: View {

    let session: ComputerSession
    let providerName: String
    let baseUrl: String
    let apiKey: String
    /// 添加 / 移除常用模型后回调，让外层刷新
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var models: [AIModelInfo] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var notice: String?
    @State private var noticeIsError = false
    @State private var endpoint = ""
    @State private var testingModel: String?
    @State private var testResult: String?
    @State private var workingModel: String?

    private var controller: SessionController? { session.controller }

    var body: some View {
        ZStack {
            AuroraBackdrop()

            AuroraScreen {
                AppTopBar(
                    title: "模型列表",
                    subtitle: subtitle,
                    onBack: { dismiss() }
                ) {
                    AuroraIconButton(systemIcon: "arrow.clockwise", size: 34, enabled: !loading) {
                        Task { await load() }
                    }
                }
            } content: {
                AuroraScrollView(bottomInset: 50) {
                    if loading {
                        SectionCard {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small).tint(Aurora.brand)
                                Text("正在从服务商拉取模型列表…")
                                    .font(AuroraFont.bodySmall)
                                    .foregroundStyle(Aurora.inkSoft)
                                Spacer(minLength: 0)
                            }
                        }
                    } else if let errorText {
                        VStack(alignment: .leading, spacing: 10) {
                            AuroraBanner(
                                systemIcon: "exclamationmark.triangle.fill",
                                text: errorText,
                                tone: Aurora.rose
                            )
                            PrimaryButton(text: "重试", systemIcon: "arrow.clockwise") {
                                Task { await load() }
                            }
                            if !session.isConnected {
                                TonalButton(
                                    text: "重新连接电脑",
                                    systemIcon: "bolt.horizontal.fill"
                                ) {
                                    Task {
                                        await session.ensureConnected()
                                        await load()
                                    }
                                }
                            }
                        }
                    } else if models.isEmpty {
                        SectionCard {
                            EmptyStateView(
                                systemIcon: "square.stack.3d.up.slash",
                                title: "没有拉到任何模型",
                                message: "有的服务商不支持 /models 接口。\n可以返回编辑页手填模型名，再用「测试」确认能不能用。"
                            ) {
                                EmptyView()
                            }
                            .padding(.vertical, 12)
                        }
                    } else {
                        if let notice {
                            AuroraBanner(
                                systemIcon: noticeIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                                text: notice,
                                tone: noticeIsError ? Aurora.rose : Aurora.teal
                            )
                        }
                        SectionCard {
                            VStack(alignment: .leading, spacing: 12) {
                                AuroraSectionHeader(
                                    title: "共 \(models.count) 个模型",
                                    subtitle: endpoint,
                                    systemIcon: "cpu",
                                    tone: Aurora.brand
                                )
                                VStack(spacing: 0) {
                                    ForEach(models.indices, id: \.self) { index in
                                        if index > 0 {
                                            Divider().overlay(Aurora.hairline)
                                        }
                                        row(models[index])
                                    }
                                }
                            }
                        }
                    }
                }
            } bar: {
                EmptyView()
            }
        }
        .task { await load() }
    }

    private var subtitle: String {
        if providerName.isEmpty { return baseUrl }
        return "\(providerName) · \(baseUrl)"
    }

    // MARK: 单行

    private func row(_ item: AIModelInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.favorite ? "star.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.favorite ? Aurora.brand : Aurora.muted)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.model)
                        .font(AuroraFont.titleSmall)
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                    if !item.ownedBy.isEmpty {
                        Text(item.ownedBy)
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if item.favorite {
                    Text("常用")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.brand)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Aurora.brand.tint(0.12)))
                }
            }

            HStack(spacing: 8) {
                SmallTonalButton(
                    text: testingModel == item.model ? "测试中…" : "测试",
                    systemIcon: "bolt.horizontal",
                    enabled: testingModel == nil && workingModel == nil
                ) {
                    Task { await test(item) }
                }

                if item.favorite {
                    SmallTonalButton(
                        text: workingModel == item.model ? "处理中…" : "取消常用",
                        systemIcon: "star.slash",
                        enabled: workingModel == nil && testingModel == nil
                    ) {
                        Task { await toggleFavorite(item) }
                    }
                } else {
                    SmallTonalButton(
                        text: workingModel == item.model ? "处理中…" : "添加为常用模型",
                        systemIcon: "star",
                        enabled: workingModel == nil && testingModel == nil
                    ) {
                        Task { await toggleFavorite(item) }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await use(item) }
        }
    }

    // MARK: 动作

    @MainActor
    private func load() async {
        loading = true
        errorText = nil
        notice = nil
        noticeIsError = false
        // 后台回来连接可能被挂掉：先探活重连，再拉列表
        await session.ensureConnected()
        do {
            let rows = try await controller?.fetchAIModels(
                name: providerName, baseUrl: baseUrl, apiKey: apiKey
            )
            models = rows ?? []
            endpoint = endpointOf(baseUrl)
        } catch {
            errorText = friendly(error)
        }
        loading = false
    }

    /// 点整行：把这个模型设成当前要用的模型。
    @MainActor
    private func use(_ item: AIModelInfo) async {
        guard workingModel == nil, testingModel == nil, !providerName.isEmpty else { return }
        workingModel = item.model
        notice = nil
        noticeIsError = false
        defer { workingModel = nil }
        do {
            _ = try await controller?.setProviderModel(name: providerName, model: item.model)
            notice = "已选用「\(item.model)」"
            noticeIsError = false
            onChanged()
        } catch {
            // 服务商还没保存成功（比如从编辑页刚跳过来）：说清楚下一步
            notice = "「\(item.model)」选好了，但没能设成当前模型：\(friendly(error))\n回编辑页点一下「保存」再来选。"
            noticeIsError = true
        }
    }

    @MainActor
    private func test(_ item: AIModelInfo) async {
        guard testingModel == nil, workingModel == nil else { return }
        testingModel = item.model
        notice = nil
        noticeIsError = false
        defer { testingModel = nil }
        do {
            let result = try await controller?.testAIModel(
                name: providerName, model: item.model, baseUrl: baseUrl, apiKey: apiKey
            )
            let seconds = String(format: "%.1f", Double(result?.elapsedMs ?? 0) / 1000)
            var text = "「\(item.model)」连接正常 · \(seconds) 秒"
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
    private func toggleFavorite(_ item: AIModelInfo) async {
        guard workingModel == nil, testingModel == nil, !providerName.isEmpty else { return }
        workingModel = item.model
        notice = nil
        noticeIsError = false
        defer { workingModel = nil }
        do {
            if item.favorite {
                _ = try await controller?.removeAIFavorite(name: providerName, model: item.model)
                notice = "已从常用模型移除「\(item.model)」"
            } else {
                _ = try await controller?.addAIFavorite(name: providerName, model: item.model)
                notice = "已添加为常用模型「\(item.model)」"
            }
            noticeIsError = false
            // 重新拉一次，让收藏状态和电脑上保持一致
            let rows = try? await controller?.fetchAIModels(
                name: providerName, baseUrl: baseUrl, apiKey: apiKey
            )
            if let rows { models = rows }
            onChanged()
        } catch {
            notice = friendly(error)
            noticeIsError = true
        }
    }

    private func endpointOf(_ base: String) -> String {
        let trimmed = base.trimmed
        guard !trimmed.isEmpty else { return "" }
        var value = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        if value.hasSuffix("/models") { return value }
        if value.hasSuffix("/chat/completions") {
            return String(value.dropLast("/chat/completions".count)) + "/models"
        }
        if value.hasSuffix("/v1") { return value + "/models" }
        return value + "/v1/models"
    }

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
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
