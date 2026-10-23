import SwiftUI

@main
struct PcMateApp: App {

    @StateObject private var store: ConnectionStore
    @StateObject private var printers: PrinterStore
    @StateObject private var session: ComputerSession

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
                .preferredColorScheme(.light)
                .tint(Aurora.brand)
        }
    }
}
