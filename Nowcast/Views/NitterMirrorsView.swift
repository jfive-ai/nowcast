import SwiftUI

/// Settings tab for managing the ordered list of Nitter mirrors and
/// running ad-hoc health checks. Public mirrors come and go fast — this
/// view is intentionally just an editable list, not auto-discovery.
struct NitterMirrorsView: View {
    @ObservedObject private var store = NitterMirrorStore.shared
    @State private var draft: String = ""
    @State private var health: [String: MirrorHealth] = [:]
    @State private var isChecking: Bool = false

    var body: some View {
        Form {
            Section("Add mirror") {
                TextField("https://nitter.example.com", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                HStack {
                    Spacer()
                    Button("Add") { add() }
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Tried in order; on failure a mirror is demoted to the back of the rotation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Mirrors") {
                if store.mirrors.isEmpty {
                    Text("No mirrors configured. X content won't be pulled until you add one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.mirrors, id: \.self) { mirror in
                        HStack(spacing: 8) {
                            statusDot(for: mirror)
                            Text(mirror)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                store.remove(mirror)
                                health[mirror] = nil
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        runHealthCheck()
                    } label: {
                        if isChecking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Check health")
                        }
                    }
                    .disabled(store.mirrors.isEmpty || isChecking)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func statusDot(for mirror: String) -> some View {
        let color: Color = {
            switch health[mirror] {
            case .ok: return .green
            case .down: return .red
            default: return .secondary
            }
        }()
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private func add() {
        let cleaned = draft.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }
        store.add(cleaned)
        draft = ""
    }

    private func runHealthCheck() {
        guard !isChecking else { return }
        isChecking = true
        let mirrors = store.mirrors
        Task {
            await withTaskGroup(of: (String, MirrorHealth).self) { group in
                for mirror in mirrors {
                    group.addTask { (mirror, await Self.probe(mirror)) }
                }
                for await (mirror, status) in group {
                    health[mirror] = status
                }
            }
            isChecking = false
        }
    }

    private static func probe(_ baseURL: String) async -> MirrorHealth {
        // The "/jack" handle exists historically and gives a small RSS
        // payload — good enough as a liveness probe without hammering
        // a specific user's feed.
        guard let url = URL(string: "\(baseURL)/jack/rss") else { return .down }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Nowcast/0.1", forHTTPHeaderField: "User-Agent")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                return .ok
            }
            return .down
        } catch {
            return .down
        }
    }
}

private enum MirrorHealth {
    case ok
    case down
}
