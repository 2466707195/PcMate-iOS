import SwiftUI

// MARK: - 底部三栏

enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case home
    case tools
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .tools: return "工具栏"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .tools: return "square.grid.2x2"
        case .settings: return "gearshape"
        }
    }
}

/// App 根视图：液态玻璃底栏 + 三个页面。
///
/// 底栏实现来自 Aurora UI（iOS 18+ 用系统 TabView 自动获得 Liquid Glass；
/// iOS 16/17 用自绘的白胶囊底栏，视觉一致）。
struct RootTabScreen: View {

    @State private var tab: AppTab = .home
    @EnvironmentObject private var session: ComputerSession
    @EnvironmentObject private var store: ConnectionStore

    private var items: [AuroraTabSpec<AppTab>] {
        [
            AuroraTabSpec(id: .home, title: AppTab.home.title, icon: AppTab.home.icon),
            AuroraTabSpec(id: .tools, title: AppTab.tools.title, icon: AppTab.tools.icon),
            AuroraTabSpec(id: .settings, title: AppTab.settings.title, icon: AppTab.settings.icon)
        ]
    }

    var body: some View {
        AuroraTabHost(selection: $tab, items: items) { value in
            switch value {
            case .home:
                HomeScreen()
            case .tools:
                ToolsScreen()
            case .settings:
                SettingsScreen()
            }
        }
        .onAppear {
            session.autoselectIfNeeded()
        }
    }
}
