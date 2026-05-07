import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var draftKey: String = ""
    @State private var draftYouTubeKey: String = ""
    @State private var draftBraveKey: String = ""
    @State private var draftRetention: String = ""
    @State private var savedFlash: Bool = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            SubscriptionsView()
                .tabItem { Label("Sources", systemImage: "list.bullet.rectangle") }
            NitterMirrorsView()
                .tabItem { Label("Nitter", systemImage: "network") }
            EmailSettingsView()
                .tabItem { Label("Email", systemImage: "envelope") }
        }
        .padding()
        .onAppear {
            draftKey = state.openAIAPIKey
            draftYouTubeKey = state.youtubeAPIKey
            draftBraveKey = state.braveAPIKey
            draftRetention = String(state.retentionDays)
        }
    }

    private var generalTab: some View {
        Form {
            Section("OpenAI") {
                SecureField("API key", text: $draftKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") {
                        state.saveAPIKey(draftKey)
                        flashSaved()
                    }
                    .disabled(draftKey == state.openAIAPIKey)
                    if savedFlash {
                        Text("Saved").foregroundStyle(.green).font(.caption)
                    }
                }
            }

            Section("YouTube Data API") {
                SecureField("API key", text: $draftYouTubeKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    state.saveYouTubeAPIKey(draftYouTubeKey)
                    flashSaved()
                }
                .disabled(draftYouTubeKey == state.youtubeAPIKey)
                Text("Required for YouTube search and channel adapters. Free tier: 10k quota / day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Brave Search API") {
                SecureField("API key", text: $draftBraveKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    state.saveBraveAPIKey(draftBraveKey)
                    flashSaved()
                }
                .disabled(draftBraveKey == state.braveAPIKey)
                Text("Required for the Web search adapter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Retention") {
                HStack {
                    TextField("Days", text: $draftRetention)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitRetention() }
                    Button("Apply") { commitRetention() }
                    Spacer()
                }
                Text("0 keeps reports forever.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                HStack {
                    Text("Total report size")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: state.totalReportBytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Reports stored")
                    Spacer()
                    Text("\(state.reports.count)")
                        .foregroundStyle(.secondary)
                }
                Button("Delete oldest 10") {
                    state.deleteOldest(10)
                }
                .disabled(state.reports.isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    private func commitRetention() {
        if let v = Int(draftRetention.trimmingCharacters(in: .whitespaces)), v >= 0 {
            state.retentionDays = v
            state.applyRetention()
        }
    }

    private func flashSaved() {
        savedFlash = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            savedFlash = false
        }
    }
}
