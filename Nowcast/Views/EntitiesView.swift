import SwiftUI

/// Sidebar tab that surfaces the cross-brief entity index built by
/// `EntityExtractor` (P5-2). Left: ranked list of entities with mention
/// counts. Right (the larger detail pane): timeline of mentions for the
/// selected entity, each row jumps into the originating report.
struct EntitiesView: View {
    @EnvironmentObject private var state: AppState
    @Binding var selectedReport: Report?

    @State private var query: String = ""
    @State private var kindFilter: Entity.Kind? = nil
    @State private var entities: [Entity] = []
    @State private var selectedEntityID: UUID?
    @State private var timeline: [EntityTimelineRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            Divider()
            if entities.isEmpty {
                emptyState
            } else {
                entityList
            }
            if !timeline.isEmpty {
                Divider()
                Text("Mentions")
                    .font(.caption).bold()
                    .padding(.horizontal, 12).padding(.top, 6)
                timelineList
            }
        }
        .task { reload() }
    }

    // MARK: - Sections

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter entities…", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            Picker("", selection: kindBinding) {
                Text("All").tag(Entity.Kind?.none)
                ForEach(Entity.Kind.allCases) { k in
                    Text(k.displayName).tag(Entity.Kind?.some(k))
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var entityList: some View {
        List(filteredEntities, selection: $selectedEntityID) { entity in
            HStack {
                Image(systemName: entity.kind.symbol)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entity.canonicalName).font(.callout)
                    Text(entity.kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entity.mentionCount)")
                    .font(.caption).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            .tag(entity.id)
        }
        .listStyle(.inset)
        .frame(maxHeight: timeline.isEmpty ? .infinity : 280)
        .onChange(of: selectedEntityID) { id in
            timeline = id.map(state.mentions(forEntity:)) ?? []
        }
    }

    private var timelineList: some View {
        List(timeline) { row in
            Button {
                state.selectedReportID = row.report.id
                selectedReport = row.report
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(row.report.topic).font(.callout).bold()
                        Spacer()
                        Text(row.report.generatedAt, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let h = row.clusterHeadline {
                        Text(h).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.grid.cross")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No entities yet")
                .font(.headline)
            Text("Enable Entity extraction in Settings → Pipeline to start building a cross-brief entity index.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var filteredEntities: [Entity] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entities }
        return entities.filter { $0.canonicalName.lowercased().contains(q) }
    }

    private var kindBinding: Binding<Entity.Kind?> {
        Binding(
            get: { kindFilter },
            set: { newValue in
                kindFilter = newValue
                reload()
            }
        )
    }

    private func reload() {
        entities = state.topEntities(limit: 200, kind: kindFilter)
        if let id = selectedEntityID, entities.contains(where: { $0.id == id }) == false {
            selectedEntityID = nil
            timeline = []
        }
    }
}
