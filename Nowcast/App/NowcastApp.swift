import SwiftUI

@main
struct NowcastApp: App {
    @StateObject private var state = AppState()
    @StateObject private var audioPlayer = AudioBriefPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .environmentObject(audioPlayer)
                .frame(minWidth: 900, minHeight: 600)
#if DEBUG
                .task { await runSelfCheckIfRequested() }
#endif
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .frame(width: 480, height: 360)
        }

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(state)
                .environmentObject(audioPlayer)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "newspaper")
                if state.unreadCount > 0 {
                    Text("\(state.unreadCount)")
                        .font(.caption)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

#if DEBUG
    /// Headless regression gate: `NOWCAST_SELF_CHECK=1 Nowcast.app/Contents/MacOS/Nowcast`
    /// runs the same SelfCheck the Settings button does (insert-only,
    /// namespaced rows against the real DB), prints the check summary to
    /// stdout, and exits non-zero on failure.
    @MainActor
    private func runSelfCheckIfRequested() async {
        guard ProcessInfo.processInfo.environment["NOWCAST_SELF_CHECK"] == "1" else { return }
        let result = await SelfCheck.run(storage: state.storage)
        print(result.summary)
        exit(result.passed ? 0 : 1)
    }
#endif
}
