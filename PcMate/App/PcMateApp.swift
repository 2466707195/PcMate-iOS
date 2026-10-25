import SwiftUI

@main
struct PcMateApp: App {

    @StateObject private var store: ConnectionStore
    @StateObject private var printers: PrinterStore
    @StateObject private var session: ComputerSession
    /// 主题变化时整个 `body` 会重跑，下面所有页面重新取色
    @StateObject private var theme = ThemeStore.shared

    init() {
        let connectionStore = ConnectionStore()
        let printerStore = PrinterStore()
        _store = StateObject(wrappedValue: connectionStore)
        _printers = StateObject(wrappedValue: printerStore)
        _session = StateObject(wrappedValue: ComputerSession(store: connectionStore, printers: printerStore))
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabScreen()
                .environmentObject(store)
                .environmentObject(printers)
                .environmentObject(session)
                .environmentObject(theme)
                .preferredColorScheme(theme.isDark ? .dark : .light)
                .tint(Aurora.brand)
                // 切到别的 App（复制地址 / Key）再回来时，iOS 已经把
                // WebSocket 挂掉了。回到前台自动探活，断了就重连——
                // 否则用户看到的是「断开连接」，按钮也点不动。
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    Task { await session.ensureConnected() }
                }
        }
    }
}
