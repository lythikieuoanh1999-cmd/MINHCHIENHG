import SwiftUI

@main
struct KENIOSApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Color(red: 0.36, green: 0.42, blue: 0.93)) // xanh tím kiểu Gemini
        }
    }
}
