import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var draftKey: String = ""
    @State private var draftRetention: String = ""
    @State private var savedFlash: Bool = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            SubscriptionsView()
                .tabItem { Label("Sources", systemImage: "list.bullet.rectangle") }
        }
        .padding()
        .onAppear {
            draftKey = state.openAIAPIKey
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
                        savedFlash = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            savedFlash = false
                        }
                    }
                    .disabled(draftKey == state.openAIAPIKey)
                    if savedFlash {
                        Text("Saved").foregroundStyle(.green).font(.caption)
                    }
                }
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
}
