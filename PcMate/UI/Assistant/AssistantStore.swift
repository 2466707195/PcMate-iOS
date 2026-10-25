import Foundation
import SwiftUI

/// AI 助手的对话状态。
///
/// 做成单例：切到别的标签页再切回来，聊天记录还在。
/// 记录只在内存里，App 重启就清空（不落盘，避免历史里夹着敏感信息）。
final class AssistantStore: ObservableObject {

    static let shared = AssistantStore()

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var sending = false
    @Published var draft = ""

    private init() {}

    /// 回传给模型的纯文本历史（最多 16 轮）。
    var history: [(role: String, content: String)] {
        messages.suffix(16).compactMap { $0.historyTurn }
    }

    func clear() {
        messages.removeAll()
    }

    /// 发一条问题。整个过程只在这台手机上排队：发送中再点一次会被忽略。
    @MainActor
    func send(_ controller: SessionController?) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        guard let controller else {
            messages.append(ChatMessage(role: .error, text: "还没有连接电脑，先在「首页」选一台电脑并连接。"))
            return
        }
        let history = self.history
        draft = ""
        messages.append(ChatMessage(role: .user, text: text))
        sending = true
        defer { sending = false }
        do {
            let reply = try await controller.assistant(text: text, history: history)
            messages.append(
                ChatMessage(
                    role: .assistant,
                    text: reply.reply,
                    steps: reply.steps,
                    model: reply.model,
                    elapsedMs: reply.elapsedMs
                )
            )
        } catch {
            messages.append(ChatMessage(role: .error, text: error.localizedDescription))
        }
    }
}
