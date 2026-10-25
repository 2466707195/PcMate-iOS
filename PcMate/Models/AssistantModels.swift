import Foundation

// MARK: - AI 助手的数据结构
//
// 模型调用和工具执行都在电脑端 Agent 上完成，这里只负责收发和展示。

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

    var icon: String {
        switch tool {
        case "list_processes", "kill_process": return "list.bullet.rectangle"
        case "cleanup_memory": return "sparkles"
        case "power_action": return "power"
        case "set_external_network", "network_status", "network_adapters": return "wifi"
        case "list_files", "read_file", "write_file", "make_directory", "delete_file": return "folder"
        case "run_command": return "terminal"
        case "hardware_info", "system_info": return "desktopcomputer"
        default: return "wrench.and.screwdriver"
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

/// 大模型配置（手机端只能看到是否已配置，拿不到完整 Key）。
struct AIConfigInfo {
    var baseUrl: String
    var model: String
    var hasKey: Bool
    var keyHint: String
    var endpoint: String
}

/// 设置页「测试连接」的结果。
struct AssistantTestResult {
    var reply: String
    var model: String
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
