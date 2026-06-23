import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if !store.isLoggedIn {
                LoginView()
            } else {
                MainTabView()
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(store.isDark ? .dark : .light)
    }
}

struct MainTabView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView(selection: $store.tab) {
            ChatView()
                .tabItem { Label("Trò chuyện", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(0)
            CodeToolsView()
                .tabItem { Label("Lập trình", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(1)
            LibraryView()
                .tabItem { Label("Thư viện", systemImage: "clock.arrow.circlepath") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
                .tag(3)
            if store.isAdmin {
                AdminView()
                    .tabItem { Label("Quản trị", systemImage: "person.2.badge.gearshape.fill") }
                    .tag(4)
            }
        }
        .task {
            await store.loadProviders()
            await store.loadKeys()
            await store.refreshConversations()
            await store.refreshCredits()
        }
    }
}
