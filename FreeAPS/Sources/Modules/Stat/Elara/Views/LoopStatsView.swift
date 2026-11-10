import SwiftDate
import SwiftUI

/// Interval, duration and missed counts for the loops and for the sensor readings, under the rings.
struct LoopStatsView: View {
    let statsData: [LoopStatsProcessedData]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let loops = statsData.first(where: { $0.category == .successfulLoop }) {
                row(
                    color: .blue,
                    title: String(localized: "Loops"),
                    second: (String(localized: "Duration"), seconds(loops.medianDuration)),
                    data: loops
                )
            }
            if let glucose = statsData.first(where: { $0.category == .glucoseCount }) {
                Divider()
                row(
                    color: .green,
                    title: String(localized: "Sensor Readings"),
                    // A reading has no duration: the longest stretch without one tells more
                    second: (String(localized: "Longest Gap"), minutes(glucose.longestGap)),
                    data: glucose
                )
            }
            if let days = statsData.first?.totalDays {
                Divider()
                HStack {
                    Text("Days").foregroundStyle(.secondary)
                    Spacer()
                    Text(days.description)
                }
                .font(.subheadline)
            }
        }
        .padding()
    }

    private func row(color: Color, title: String, second: (String, String), data: LoopStatsProcessedData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.subheadline.weight(.semibold))
            }
            HStack {
                StatChartUtils.statView(title: String(localized: "Interval"), value: minutes(data.medianInterval))
                Spacer()
                StatChartUtils.statView(title: second.0, value: second.1)
                Spacer()
                StatChartUtils.statView(title: String(localized: "Missed"), value: data.missedPerDay.formatted())
            }
        }
    }

    private func minutes(_ seconds: Double) -> String {
        (seconds / 60).formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "m"
    }

    private func seconds(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "s"
    }
}
