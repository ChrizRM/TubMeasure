import SwiftUI

@main
struct TubMeasureApp: App {
    @StateObject private var store = ScanStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
        }
    }
}
