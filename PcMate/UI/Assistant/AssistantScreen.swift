import SwiftUI

// MARK: - AI 助手

/// 聊天页：问题 → 电脑上的 Agent 调模型 + 跑工具 → 回答。
///
/// 手机上不做任何「智能」：这里只负责输入、气泡、工具执行记录和设置入口。
struct AssistantScreen: View {

    @EnvironmentObject private var session: ComputerSession
    @ObservedObject private var store = AssistantStore.shared

    @State private var showSettings = false
    @State private var connecting = false
    @FocusState private var inputFocused: Bool

    private let bottomID = "assistant-bottom"

    private let suggestions = [
        "现在电脑卡不卡？",
        "内存被谁占了",
        "把外网关掉",
        "桌面上有什么文件"
    ]

    var body: some View {
        ZStack {
            AuroraBackdrop()

            AuroraScreen {
                topBar
            } content: {
                if session.isConnected {
                    conversation
                } else {
                    disconnected
                }
            } bar: {
                if session.isConnected {
                    inputBar
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            AssistantSettingsSheet(controller: session.controller)
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        AppTopBar(title: "AI 助手", subtitle: statusText) {
            HStack(spacing: 0) {
                AuroraIconButton(systemIcon: "trash", size: 34) {
                    store.clear()
                }
                AuroraIconButton(systemIcon: "slider.horizontal.3", size: 34) {
                    showSettings = true
                }
            }
        }
    }

    private var statusText: String {
        if session.isConnected { return "\(session.displayName) · 可调用工具操作电脑" }
        if session.connecting { return "正在连接…" }
        if let selected = session.selected { return "未连接 · \(selected.name)" }
        return "还没有选择电脑"
    }

    // MARK: 对话

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
                    if store.messages.isEmpty {
                        intro
                    }
                    ForEach(store.messages) { message in
                        bubble(message)
                    }
                    if store.sending {
                        thinking
                    }
                    Color.clear.frame(height: 1).id(bottomID)
                }
                .padding(.horizontal, AuroraMetrics.pagePadding)
                .padding(.top, 4)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.count) { _ in scrollToBottom(proxy) }
            .onChange(of: store.sending) { _ in scrollToBottom(proxy) }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Aurora.brand.tint(0.12))
                        .frame(width: 46, height: 46)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Aurora.brand)
                        )
                    Text("问问这台电脑")
                        .font(AuroraFont.titleLarge)
                        .foregroundStyle(Aurora.ink)
                    Text("查进程、清内存、开关外网、整理文件、关机重启——\n说一句话就行，AI 会自己调用工具去做。")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("试试这些")
                .font(AuroraFont.labelSmall)
                .foregroundStyle(Aurora.muted)
                .padding(.leading, 4)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(suggestions, id: \.self) { text in
                    suggestionChip(text)
                }
            }
        }
        .padding(.top, 4)
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            ask(text)
        } label: {
            Text(text)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    AuroraShape.control
                        .fill(Aurora.surface)
                        .shadow(color: Aurora.cardShadow, radius: 3, x: 0, y: 1)
                )
                .overlay(
                    AuroraShape.control.stroke(Aurora.line.opacity(0.55), lineWidth: 1)
                )
                .contentShape(AuroraShape.control)
        }
        .buttonStyle(PressScaleStyle())
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack(spacing: 0) {
                Spacer(minLength: 44)
                Text(message.text)
                    .font(AuroraFont.bodyMedium)
                    .foregroundStyle(Aurora.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Aurora.brand.tint(0.14))
                    )
            }

        case .assistant:
            VStack(alignment: .leading, spacing: 9) {
                if !message.steps.isEmpty {
                    stepList(message.steps)
                }
                markdown(message.text)
                if !message.model.isEmpty {
                    Text(footer(message))
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AuroraShape.card
                    .fill(Aurora.surface)
                    .shadow(color: Aurora.cardShadow, radius: 4, x: 0, y: 1)
            )
            .overlay(
                AuroraShape.card.stroke(Aurora.line.opacity(0.55), lineWidth: 1)
            )

        case .error:
            AuroraBanner(
                systemIcon: "exclamationmark.triangle.fill",
                text: message.text,
                tone: Aurora.rose
            )
        }
    }

    private func stepList(_ steps: [AssistantStep]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(steps) { step in
                HStack(spacing: 6) {
                    Image(systemName: step.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(step.ok ? Aurora.teal : Aurora.rose)
                    Text(step.title)
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(step.ok ? Aurora.teal : Aurora.rose)
                        .lineLimit(1)
                    if !step.summary.isEmpty {
                        Text(step.summary)
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Capsule().fill((step.ok ? Aurora.teal : Aurora.rose).tint(0.10))
                )
            }
        }
    }

    private func markdown(_ text: String) -> some View {
        // 只解析行内 Markdown（粗体、代码），保留换行；
        // 大段 Markdown 在气泡里反而更难读。
        let attributed = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        return Text(attributed)
            .font(AuroraFont.bodyMedium)
            .foregroundStyle(Aurora.ink)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func footer(_ message: ChatMessage) -> String {
        let seconds = Double(message.elapsedMs) / 1000
        if seconds > 0.05 {
            return "\(message.model) · \(String(format: "%.1f", seconds)) 秒"
        }
        return message.model
    }

    private var thinking: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(Aurora.brand)
            Text("正在思考…")
                .font(AuroraFont.bodyMedium)
                .foregroundStyle(Aurora.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AuroraShape.card
                .fill(Aurora.surface)
                .shadow(color: Aurora.cardShadow, radius: 4, x: 0, y: 1)
        )
        .overlay(
            AuroraShape.card.stroke(Aurora.line.opacity(0.55), lineWidth: 1)
        )
    }

    // MARK: 输入

    private var inputBar: some View {
        GlassBar(contentPadding: EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 8)) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("问点什么…", text: $store.draft, axis: .vertical)
                    .font(AuroraFont.bodyMedium)
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { askDraft() }
                    .padding(.vertical, 9)

                sendButton
            }
        }
    }

    private var sendButton: some View {
        Button {
            askDraft()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(canSend ? Aurora.brandDeep : Aurora.muted)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(canSend ? Aurora.brand.tint(0.16) : Aurora.surfaceVariant)
                )
                .overlay(
                    Circle().stroke(
                        canSend ? Aurora.brand.opacity(0.28) : Aurora.line.opacity(0.6),
                        lineWidth: 1
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!canSend)
    }

    private var canSend: Bool {
        !store.sending && !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func askDraft() {
        guard canSend else { return }
        inputFocused = false
        Task { await store.send(session.controller) }
    }

    @MainActor
    private func ask(_ text: String) {
        guard session.isConnected, !store.sending else { return }
        inputFocused = false
        store.draft = text
        Task { await store.send(session.controller) }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }

    // MARK: 未连接

    private var disconnected: some View {
        AuroraScrollView(bottomInset: 40) {
            if let error = session.errorText {
                AuroraBanner(
                    systemIcon: "exclamationmark.triangle.fill",
                    text: error,
                    tone: Aurora.rose
                )
            }
            SectionCard {
                EmptyStateView(
                    systemIcon: "sparkles",
                    title: session.selected == nil ? "还没有选择电脑" : "还没有连接电脑",
                    message: "AI 助手在电脑上执行：电脑负责调模型、跑工具，\n手机只负责提问。"
                ) {
                    if session.selected == nil {
                        Text("先去「首页」添加一台电脑")
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.inkSoft)
                    } else {
                        PrimaryButton(
                            text: connecting ? "连接中…" : "连接电脑",
                            systemIcon: "bolt.horizontal.fill",
                            enabled: !connecting
                        ) {
                            connect()
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.vertical, 18)
            }
        }
    }

    @MainActor
    private func connect() {
        guard !connecting else { return }
        connecting = true
        Task {
            await session.connect()
            connecting = false
        }
    }
}
