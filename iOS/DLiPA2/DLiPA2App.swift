import SwiftUI
import UIKit

@main
struct IPADownloaderApp: App {
    @StateObject private var service = IPAToolService()

    init() {
        Self.configureBarAppearances()
        DebugLogger.start()
        JITHelper.prepareStartupJIT26PoolIfNeeded()
    }

    private static func configureBarAppearances() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(service)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var service: IPAToolService

    var body: some View {
        TabView {
            SearchView()
                .tabItem {
                    Label("Tìm kiếm", systemImage: "magnifyingglass")
                }

            DownloadsView()
                .tabItem {
                    Label("Tải xuống", systemImage: "arrow.down.circle")
                }
                .badge(service.activeDownloads.filter { !$0.isCompleted && $0.errorMessage == nil }.count)

            AccountsView()
                .tabItem {
                    Label("Tài khoản", systemImage: "person.crop.circle")
                }
        }
    }
}
