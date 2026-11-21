import SwiftUI

@main
struct DLiPA2App: App {
    @StateObject private var service = IPAToolService()

    init() {
        DebugLogger.start()
        JITHelper.prepareStartupJIT26PoolIfNeeded()
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
