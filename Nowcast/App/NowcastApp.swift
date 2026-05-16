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
}
