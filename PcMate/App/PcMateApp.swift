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

    var body: some Scene {
        WindowGroup {
            RootTabScreen()
                .environmentObject(store)
                .environmentObject(printers)
                .environmentObject(session)
                .environmentObject(theme)
                .preferredColorScheme(theme.isDark ? .dark : .light)
                .tint(Aurora.brand)
        }
    }
}
