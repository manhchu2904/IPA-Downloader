import SwiftUI
import UIKit

enum AppTab: Hashable {
    case search
    case downloads
    case accounts
}

@main
struct IPADownloaderApp: App {
    @StateObject private var service = IPAToolService()

    init() {
        Self.configureBarAppearances()
        DebugLogger.start()
        JITHelper.prepareStartupJIT26PoolIfNeeded()
    }

    private static func configureBarAppearances() {
        if #available(iOS 26.0, *) {
            return
        }
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
    @State private var selectedTab: AppTab = .search

    private var activeDownloadCount: Int {
        service.activeDownloads.filter { !$0.isCompleted && $0.errorMessage == nil }.count
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SearchView(
                onOpenAccounts: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = .accounts
                    }
                },
                onOpenDownloads: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = .downloads
                    }
                }
            )
            .tabItem {
                Label("Tìm kiếm", systemImage: "magnifyingglass")
            }
            .tag(AppTab.search)

            DownloadsView(
                onOpenSearch: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = .search
                    }
                }
            )
            .tabItem {
                Label("Tải xuống", systemImage: "arrow.down.circle.fill")
            }
            .badge(activeDownloadCount)
            .tag(AppTab.downloads)

            AccountsView()
                .tabItem {
                    Label("Tài khoản", systemImage: "person.crop.circle.fill")
                }
                .tag(AppTab.accounts)
        }
    }
}
