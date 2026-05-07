import SwiftUI

/// Modal form for creating or editing a `TopicPreset`. Pass `preset = nil`
/// to create a new one; pass an existing preset to edit it in place.
struct TopicPresetEditor: View {
    @Environment(\.dismiss) private var dismiss

    let original: TopicPreset?
    let onSave: (TopicPreset) -> Void

    @State private var name: String
    @State private var query: String
    @State private var window: TimeWindow
    @State private var sources: Set<SourceKind>
    @State private var cadenceKind: CadenceKind
    @State private var everyNHours: Int
    @State private var dailyTime: Date
    @State private var weeklyDay: Int
    @State private var weeklyTime: Date
    @State private var deliveryNotification: Bool
    @State private var deliveryMenuBar: Bool

    init(preset: TopicPreset?, onSave: @escaping (TopicPreset) -> Void) {
        self.original = preset
        self.onSave = onSave

        _name = State(initialValue: preset?.name ?? "")
        _query = State(initialValue: preset?.query ?? "")
        _window = State(initialValue: preset?.window ?? .today)
        _sources = State(initialValue: Set(preset?.sources ?? [.hackerNews]))

        switch preset?.cadence ?? .manual {
        case .manual:
            _cadenceKind = State(initialValue: .manual)
            _everyNHours = State(initialValue: 1)
            _dailyTime = State(initialValue: Self.todayAt(hour: 8, minute: 0))
            _weeklyDay = State(initialValue: 2)
            _weeklyTime = State(initialValue: Self.todayAt(hour: 9, minute: 0))
        case .everyNHours(let h):
            _cadenceKind = State(initialValue: .everyNHours)
            _everyNHours = State(initialValue: h)
            _dailyTime = State(initialValue: Self.todayAt(hour: 8, minute: 0))
            _weeklyDay = State(initialValue: 2)
            _weeklyTime = State(initialValue: Self.todayAt(hour: 9, minute: 0))
        case .dailyAt(let h, let m):
            _cadenceKind = State(initialValue: .daily)
            _everyNHours = State(initialValue: 1)
            _dailyTime = State(initialValue: Self.todayAt(hour: h, minute: m))
            _weeklyDay = State(initialValue: 2)
            _weeklyTime = State(initialValue: Self.todayAt(hour: 9, minute: 0))
        case .weeklyAt(let w, let h, let m):
            _cadenceKind = State(initialValue: .weekly)
            _everyNHours = State(initialValue: 1)
            _dailyTime = State(initialValue: Self.todayAt(hour: 8, minute: 0))
            _weeklyDay = State(initialValue: w)
            _weeklyTime = State(initialValue: Self.todayAt(hour: h, minute: m))
        }

        let channels = preset?.deliveryChannels ?? [.inApp]
        _deliveryNotification = State(initialValue: channels.contains(.notification))
        _deliveryMenuBar = State(initialValue: channels.contains(.menuBar))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(original == nil ? "New preset" : "Edit preset")
                .font(.title2).bold()
                .padding([.horizontal, .top])

            Form {
                Section("Basics") {
                    TextField("Name", text: $name)
                    TextField("Topic / query", text: $query)
                    Picker("Window", selection: $window) {
                        ForEach(TimeWindow.allCases) { w in
                            Text(w.displayName).tag(w)
                        }
                    }
                }

                Section("Sources") {
                    ForEach(SourceKind.allCases) { kind in
                        Toggle(isOn: binding(for: kind)) {
                            HStack {
                                Text(kind.displayName)
                                if !kind.isAvailableInMVP {
                                    Text("Phase 2+")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!kind.isAvailableInMVP)
                    }
                }

                Section("Schedule") {
                    Picker("Cadence", selection: $cadenceKind) {
                        ForEach(CadenceKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }

                    switch cadenceKind {
                    case .manual:
                        Text("Run only when triggered manually.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .everyNHours:
                        Stepper("Every \(everyNHours) hour\(everyNHours == 1 ? "" : "s")",
                                value: $everyNHours, in: 1...24)
                    case .daily:
                        DatePicker("At", selection: $dailyTime, displayedComponents: .hourAndMinute)
                    case .weekly:
                        Picker("Day", selection: $weeklyDay) {
                            Text("Sunday").tag(1)
                            Text("Monday").tag(2)
                            Text("Tuesday").tag(3)
                            Text("Wednesday").tag(4)
                            Text("Thursday").tag(5)
                            Text("Friday").tag(6)
                            Text("Saturday").tag(7)
                        }
                        DatePicker("At", selection: $weeklyTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section("Delivery") {
                    Toggle("macOS notification", isOn: $deliveryNotification)
                    Toggle("Menu bar badge", isOn: $deliveryMenuBar)
                    Text("Reports always appear in History.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 8) {
                if !isValid {
                    Text(validationHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(buildPreset())
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(minWidth: 460, idealWidth: 460, minHeight: 560, idealHeight: 620)
    }

    private var validationHint: String {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Add a name to enable Save."
        }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Add a topic / query to enable Save."
        }
        if sources.isEmpty {
            return "Pick at least one source."
        }
        return ""
    }

    private func binding(for kind: SourceKind) -> Binding<Bool> {
        Binding(
            get: { sources.contains(kind) },
            set: { isOn in
                if isOn { sources.insert(kind) } else { sources.remove(kind) }
            }
        )
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !query.trimmingCharacters(in: .whitespaces).isEmpty &&
        !sources.isEmpty
    }

    private func buildPreset() -> TopicPreset {
        let cadence: Cadence
        switch cadenceKind {
        case .manual:
            cadence = .manual
        case .everyNHours:
            cadence = .everyNHours(hours: everyNHours)
        case .daily:
            let comps = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
            cadence = .dailyAt(hour: comps.hour ?? 8, minute: comps.minute ?? 0)
        case .weekly:
            let comps = Calendar.current.dateComponents([.hour, .minute], from: weeklyTime)
            cadence = .weeklyAt(weekday: weeklyDay, hour: comps.hour ?? 9, minute: comps.minute ?? 0)
        }

        var channels: [DeliveryChannel] = [.inApp]
        if deliveryNotification { channels.append(.notification) }
        if deliveryMenuBar { channels.append(.menuBar) }

        let orderedSources = SourceKind.allCases.filter { sources.contains($0) }

        return TopicPreset(
            id: original?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            query: query.trimmingCharacters(in: .whitespaces),
            window: window,
            sources: orderedSources,
            cadence: cadence,
            deliveryChannels: channels,
            createdAt: original?.createdAt ?? Date(),
            lastRunAt: original?.lastRunAt
        )
    }

    private static func todayAt(hour: Int, minute: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }
}

enum CadenceKind: String, CaseIterable, Identifiable {
    case manual
    case everyNHours
    case daily
    case weekly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:       return "Manual only"
        case .everyNHours:  return "Every N hours"
        case .daily:        return "Daily at time"
        case .weekly:       return "Weekly"
        }
    }
}
