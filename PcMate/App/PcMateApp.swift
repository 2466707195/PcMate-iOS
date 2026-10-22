import SwiftUI

@main
struct PcMateApp: App {

    @StateObject private var store = ConnectionStore()

    var body: some Scene {
        WindowGroup {
            HomeScreen()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .tint(Aurora.brand)
        }
    }
}
