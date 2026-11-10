import SwiftUI

/// Looping performance as two rings, like Apple's activity rings: the outer ring shows the share of
/// expected loops that ran, the inner ring the share of expected sensor readings that arrived.
struct LoopBarChartView: View {
    let loopStatRecords: [LoopStatRecord]
    let selectedInterval: ElaraStat.StateModel.StatsTimeIntervalWithToday
    let statsData: [LoopStatsProcessedData]

    private var loops: LoopStatsProcessedData? { statsData.first { $0.category == .successfulLoop } }
    private var glucose: LoopStatsProcessedData? { statsData.first { $0.category == .glucoseCount } }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                ring(fraction: (loops?.percentage ?? 0) / 100, color: .blue, diameter: 150)
                ring(fraction: (glucose?.percentage ?? 0) / 100, color: .green, diameter: 106)
                VStack(spacing: 0) {
                    Text(Self.percent(loops?.percentage ?? 0, digits: 0))
                        .font(.system(size: 22, weight: .heavy))
                    Text("succeeded")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 166, height: 166)

            VStack(alignment: .leading, spacing: 16) {
                legend(color: .blue, title: String(localized: "Loops"), data: loops)
                legend(color: .green, title: String(localized: "Sensor Readings"), data: glucose)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Looping performance bar chart"))
        .accessibilityValue(Text(
            "\(String(localized: "Loops")) \(Self.percent(loops?.percentage ?? 0, digits: 1)), "
                + "\(String(localized: "Sensor Readings")) \(Self.percent(glucose?.percentage ?? 0, digits: 1))"
        ))
    }

    private func ring(fraction: Double, color: Color, diameter: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: 16)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private func legend(color: Color, title: String, data: LoopStatsProcessedData?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(title).font(.subheadline.weight(.semibold))
            }
            if let data {
                Text(String(
                    localized: "\(data.count) of \(data.expectedPerDay)",
                    comment: "Loops or readings counted of those expected, e.g. 277 of 288"
                ) + " · " + Self.percent(data.percentage, digits: 1))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if selectedInterval != .today, selectedInterval != .day {
                    Text("per day")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    static func percent(_ value: Double, digits: Int) -> String {
        (value / 100).formatted(.percent.grouping(.never).rounded().precision(.fractionLength(digits)))
    }
}
