import SwiftUI

@main
struct AutoLedgerApp: App {
    @StateObject private var store = LedgerStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.accent)
                .onOpenURL { url in
                    _ = URLRouter.handle(url)
                }
        }
    }
}
