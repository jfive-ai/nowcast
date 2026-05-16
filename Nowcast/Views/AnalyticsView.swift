import SwiftUI
import Charts

/// Dashboard surfacing the user's own usage: cost trend, top topics, per-
/// source contribution share, and the returned → fresh → in-report funnel.
struct AnalyticsView: View {
    @EnvironmentObject private var state: AppState
    @State private var costPoints: [AnalyticsRepository.CostPoint] = []
    @State private var topics: [AnalyticsRepository.TopicPoint] = []
    @State private var contributions: [AnalyticsRepository.SourceContributionPoint] = []
    @State private var funnel: [AnalyticsRepository.FunnelStage] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Analytics")
                        .font(.title2).bold()
                    Spacer()
                    Text("Last 30 days").font(.caption).foregroundStyle(.secondary)
                    Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                }

                if isEmpty {
                    emptyState
                } else {
                    costCard
                    topicsCard
                    contributionsCard
                    funnelCard
                }
            }
            .padding()
        }
        .onAppear { refresh() }
    }

    private var isEmpty: Bool {
        costPoints.isEmpty && topics.isEmpty && contributions.isEmpty && funnel.allSatisfy { $0.value == 0 }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No data yet")
                .font(.headline)
            Text("Generate a few reports to see usage trends.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private var costCard: some View {
        Card(title: "Cost trend (USD)") {
            Chart(costPoints) { p in
                LineMark(
                    x: .value("Day", p.day, unit: .day),
                    y: .value("USD", p.usd)
                )
                .interpolationMethod(.monotone)
                AreaMark(
                    x: .value("Day", p.day, unit: .day),
                    y: .value("USD", p.usd)
                )
                .foregroundStyle(Color.accentColor.opacity(0.15))
                .interpolationMethod(.monotone)
            }
            .chartYAxis { AxisMarks(format: .currency(code: "USD").precision(.fractionLength(2))) }
            .frame(height: 160)
        }
    }

    private var topicsCard: some View {
        Card(title: "Top topics") {
            Chart(topics) { t in
                BarMark(
                    x: .value("Reports", t.count),
                    y: .value("Topic", t.topic)
                )
                .annotation(position: .trailing) {
                    Text("\(t.count)").font(.caption2)
                }
            }
            .frame(height: CGFloat(40 + (topics.count * 24)))
        }
    }

    private var contributionsCard: some View {
        Card(title: "Items per source") {
            Chart(contributions) { c in
                BarMark(
                    x: .value("Source", c.sourceKind.displayName),
                    y: .value("Returned", c.returned)
                )
                .foregroundStyle(.gray.opacity(0.35))
                BarMark(
                    x: .value("Source", c.sourceKind.displayName),
                    y: .value("Fresh", c.fresh)
                )
                .foregroundStyle(Color.accentColor)
            }
            .frame(height: 160)
        }
    }

    private var funnelCard: some View {
        Card(title: "Freshness funnel") {
            Chart(funnel) { stage in
                BarMark(
                    x: .value("Stage", stage.stage),
                    y: .value("Items", stage.value)
                )
                .annotation(position: .top) {
                    Text("\(stage.value)").font(.caption2)
                }
            }
            .frame(height: 160)
        }
    }

    private func refresh() {
        let repo = AnalyticsRepository(storage: state.storage)
        costPoints = (try? repo.costByDay()) ?? []
        topics = (try? repo.topicFrequency()) ?? []
        contributions = (try? repo.sourceContribution()) ?? []
        funnel = (try? repo.freshnessFunnel()) ?? []
    }
}

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}
