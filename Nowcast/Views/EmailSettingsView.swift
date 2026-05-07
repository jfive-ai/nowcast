import SwiftUI

/// Settings tab for the email-digest delivery channel. SMTP only,
/// implicit-TLS (port 465). Password lives in Keychain; everything else in
/// UserDefaults via `SMTPSettingsStore`.
struct EmailSettingsView: View {
    @EnvironmentObject private var state: AppState

    @State private var host: String = ""
    @State private var port: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var fromAddress: String = ""
    @State private var fromName: String = ""
    @State private var recipients: String = ""
    @State private var passwordChanged: Bool = false
    @State private var savedFlash: Bool = false
    @State private var testStatus: String?

    var body: some View {
        Form {
            Section("SMTP server (port 465 implicit TLS)") {
                TextField("Host (e.g. smtp.gmail.com)", text: $host)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password (or app password)", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: password) { _ in passwordChanged = true }
                Text("Use an app-specific password where supported (Gmail, Fastmail, iCloud).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("From / To") {
                TextField("From address", text: $fromAddress)
                    .textFieldStyle(.roundedBorder)
                TextField("From name (optional)", text: $fromName)
                    .textFieldStyle(.roundedBorder)
                TextField("Recipients (comma-separated)", text: $recipients)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                HStack {
                    Button("Save") { save() }
                    Button("Send test email") { Task { await sendTest() } }
                        .disabled(!canSendTest)
                    Spacer()
                    if savedFlash {
                        Text("Saved").foregroundStyle(.green).font(.caption)
                    }
                }
                if let testStatus {
                    Text(testStatus)
                        .font(.caption)
                        .foregroundStyle(testStatus.hasPrefix("OK") ? .green : .red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadFromState() }
    }

    private var canSendTest: Bool {
        !host.isEmpty && !username.isEmpty && !fromAddress.isEmpty
            && !recipients.isEmpty && (state.hasSMTPPassword || !password.isEmpty)
    }

    private func loadFromState() {
        let s = state.smtpSettings
        host = s.host
        port = String(s.port)
        username = s.username
        fromAddress = s.fromAddress
        fromName = s.fromName
        recipients = s.recipients.joined(separator: ", ")
        password = "" // never repopulate from keychain into a visible field
        passwordChanged = false
    }

    private func save() {
        let parsedPort = UInt16(port.trimmingCharacters(in: .whitespaces)) ?? 465
        let parsedRecipients = recipients
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        state.smtpSettings = SMTPSettings(
            host: host.trimmingCharacters(in: .whitespaces),
            port: parsedPort,
            username: username.trimmingCharacters(in: .whitespaces),
            fromAddress: fromAddress.trimmingCharacters(in: .whitespaces),
            fromName: fromName.trimmingCharacters(in: .whitespaces),
            recipients: parsedRecipients
        )

        // Only overwrite the keychain password when the field was actually
        // edited this session, so re-saving doesn't blank the stored secret.
        if passwordChanged {
            state.saveSMTPPassword(password)
            passwordChanged = false
        }

        savedFlash = true
        testStatus = nil
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            savedFlash = false
        }
    }

    private func sendTest() async {
        save()
        guard let pw = KeychainStore.shared.getSecret(account: KeychainAccount.smtpPassword),
              !pw.isEmpty else {
            testStatus = "No password saved."
            return
        }
        testStatus = "Sending…"
        let sender = EmailDigestSender(settings: state.smtpSettings, password: pw)
        let testMarkdown = """
        # Nowcast test

        This is a delivery test from Nowcast. If you can read this, your SMTP \
        configuration is working.
        """
        let testReport = Report(
            id: UUID(),
            presetID: nil,
            topic: "SMTP test",
            window: .today,
            generatedAt: Date(),
            markdownPath: "",
            byteSize: Int64(testMarkdown.utf8.count),
            sourceCount: 0,
            readAt: nil,
            promptTokens: nil,
            completionTokens: nil,
            usdCost: nil,
            modelUsed: nil,
            providerUsed: nil
        )
        do {
            try await sender.send(report: testReport, markdown: testMarkdown)
            testStatus = "OK — test email sent."
        } catch {
            testStatus = "Failed: \(error.localizedDescription)"
        }
    }
}
