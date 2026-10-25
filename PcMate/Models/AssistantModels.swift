import Foundation

// MARK: - AI 助手的数据结构
//
// 模型调用和工具执行都在电脑端 Agent 上完成，这里只负责收发和展示。
// Key 永远不下发到手机：只传「有没有配」和末 4 位。

/// Agent 执行过的一次工具调用。
struct AssistantStep: Identifiable, Hashable {

    let id = UUID()
    var tool: String
    var args: String
    var ok: Bool
    var summary: String

    /// 工具名 → 中文标签（手机上看不懂函数名）。
    var title: String {
        switch tool {
        case "list_processes": return "查看进程"
        case "kill_process": return "结束进程"
        case "cleanup_memory": return "清理内存"
        case "power_action": return "电源操作"
        case "system_info": return "电脑信息"
        case "network_status": return "网络状态"
        case "set_external_network": return "开关外网"
        case "network_adapters": return "网卡详情"
        case "list_files": return "浏览文件"
        case "read_file": return "读取文件"
        case "write_file": return "写入文件"
        case "make_directory": return "新建文件夹"
        case "delete_file": return "删除文件"
        case "run_command": return "执行命令"
        case "hardware_info": return "硬件信息"
        default: return tool
        }
    }
}

/// Agent 返回的一次完整回答。
struct AssistantReply {
    var reply: String
    var steps: [AssistantStep]
    var model: String
    var elapsedMs: Int64
}

/// 一个模型服务商（OpenAI 兼容接口）。
struct AIProviderInfo: Identifiable, Hashable {
    var id: String { name }

    var name: String
    var baseUrl: String
    /// 这个服务商当前选用的模型
    var model: String
    var hasKey: Bool
    var keyHint: String
    var endpoint: String
    var active: Bool

    /// 列表副标题：地址 + 当前模型。
    var subtitle: String {
        var text = baseUrl.isEmpty ? "还没填接口地址" : baseUrl
        if !model.isEmpty {
            text += " · \(model)"
        }
        return text
    }

    var keyLabel: String {
        hasKey ? "Key 已配置 \(keyHint)" : "还没填 Key"
    }
}

/// 一条常用模型记录。
struct AIFavoriteInfo: Identifiable, Hashable {
    var id: String { provider + "||" + model }

    var provider: String
    var model: String
    /// 对应的服务商是否还存在（被删掉的行要能标出来）
    var exists: Bool
}

/// 从服务商拉回来的一个模型。
struct AIModelInfo: Identifiable, Hashable {
    var id: String { model }

    var model: String
    var ownedBy: String
    var favorite: Bool
}

/// 电脑上的完整 AI 配置。
struct AIConfigInfo {
    var active: String
    var providers: [AIProviderInfo]
    var favorites: [AIFavoriteInfo]
    var maxSteps: Int

    var activeProvider: AIProviderInfo? {
        providers.first { $0.active } ?? providers.first { $0.name == active }
    }
}

/// 模型测试结果。
struct AIModelTestResult {
    var reply: String
    var model: String
    var provider: String
    var elapsedMs: Int64
}

/// 对话里的一条消息。
struct ChatMessage: Identifiable {

    enum Role {
        case user
        case assistant
        case error
    }

    let id = UUID()
    var role: Role
    var text: String
    var steps: [AssistantStep] = []
    var model: String = ""
    var elapsedMs: Int64 = 0
    var at = Date()

    /// 回传给模型的纯文本历史（不含工具细节和错误）。
    var historyTurn: (role: String, content: String)? {
        switch role {
        case .user: return ("user", text)
        case .assistant: return ("assistant", text)
        case .error: return nil
        }
    }
}
