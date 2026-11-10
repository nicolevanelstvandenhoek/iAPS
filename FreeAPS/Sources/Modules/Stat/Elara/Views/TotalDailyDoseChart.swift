import Charts
import SwiftUI

/// A view that displays a bar chart for Total Daily Dose (TDD) statistics.
///
/// This view presents insulin usage over time, with the ability to adjust the time interval
/// and scroll through historical data.
struct TotalDailyDoseChart: View {
    /// The selected time interval for displaying statistics.
    @Binding var selectedInterval: ElaraStat.StateModel.StatsTimeInterval
    /// The list of TDD statistics data.
    let tddStats: [TDDStats]
    /// The state model containing cached statistics data.
    let state: ElaraStat.StateModel

    /// The current scroll position in the chart.
    @State private var scrollPosition = Date()
    /// The currently selected date in the chart.
    @State private var selectedDate: Date?
    /// The calculated average TDD for the visible range.
    @State private var currentAverage: Double = 0
    /// Timer to throttle updates when scrolling.
    @State private var updateTimer = ElaraStat.UpdateTimer()
    /// Sum of hourly doses for `Day` view
    @State private var sumOfHourlyDoses: Double = 0
    /// The actual chart plot's width in pixel
    @State private var chartWidth: CGFloat = 0

    /// Computes the visible date range based on the current scroll position.
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    /// Retrieves the TDD statistic for a given date.
    /// - Parameter date: The date for which to retrieve TDD data.
    /// - Returns: The `TDDStats` object if available, otherwise `nil`.
    private func getTDDForDate(_ date: Date) -> TDDStats? {
        tddStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    /// Updates the average TDD value based on the visible date range.
    private func updateAverages() {
        currentAverage = state.getCachedTDDAverages(for: visibleDateRange)
    }

    /// Updates the total of hourly doses for `Day` view
    private func updateTotalDoses() {
        sumOfHourlyDoses = tddStats.filter({ $0.date >= visibleDateRange.start && $0.date <= visibleDateRange.end })
            .reduce(0, { result, stat in
                result + stat.amount
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView.padding(.bottom)

            VStack(alignment: .trailing) {
                Text("Total Daily Dose (U)")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .padding(.bottom, 4)

                chartsView
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { chartWidth = geo.size.width }
                                .onChange(of: geo.size.width) { _, newValue in chartWidth = newValue }
                        }
                    )
            }
        }
        .onAppear {
            scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
            // Delay the initial update to ensure scroll position has been processed
            DispatchQueue.main.async {
                updateAverages()
                updateTotalDoses()
            }
        }
        .onChange(of: scrollPosition) {
            updateTimer.scheduleUpdate {
                updateAverages()
                if selectedInterval == .day {
                    updateTotalDoses()
                }
            }
        }
        .onChange(of: selectedInterval) {
            Task {
                scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
                // Use async dispatch to ensure scroll position is updated before calculating averages
                await MainActor.run {
                    updateAverages()
                    if selectedInterval == .day {
                        updateTotalDoses()
                    }
                }
            }
        }
    }

    /// A view displaying the statistics summary including average TDD.
    private var statsView: some View {
        HStack(alignment: .top) {
            if let selectedDate {
                Group {
                    Text("Total:")
                    Text((getTDDForDate(selectedDate)?.amount ?? 0).formatted(.number.precision(.fractionLength(1))))
                        .foregroundStyle(Color.insulin)
                        + Text("\u{00A0}") + Text("U")
                }
                .font(.headline)
            } else if selectedInterval == .day {
                Grid(alignment: .leading) {
                    GridRow {
                        Text("Average:")
                        Text(currentAverage.formatted(.number.precision(.fractionLength(1))))
                            + Text("\u{00A0}") + Text("U")
                    }
                    GridRow {
                        Text("Total:")
                        Text(sumOfHourlyDoses.formatted(.number.precision(.fractionLength(1))))
                            + Text("\u{00A0}") + Text("U")
                    }
                }
                .font(.headline)
            } else {
                Group {
                    Text("Average:")
                    Text(currentAverage.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("U")
                }
                .font(.headline)
            }
            Spacer()

            if let selectedDate {
                StatSelectionPill(
                    text: StatChartUtils.selectionLabel(for: selectedDate, interval: selectedInterval),
                    color: Color.insulin
                ) {
                    withAnimation(.easeInOut) { self.selectedDate = nil }
                }
            } else {
                Text(
                    StatChartUtils
                        .formatVisibleDateRange(from: visibleDateRange.start, to: visibleDateRange.end, for: selectedInterval)
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// A view displaying the bar chart for TDD statistics.
    private var chartsView: some View {
        Chart {
            ForEach(tddStats) { stat in
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.amount)
                )
                .foregroundStyle(Color.insulin)
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )
            }

            // The selected bar's value is shown in the summary above the chart
            if let selectedDate, getTDDForDate(selectedDate) != nil {
                RuleMark(x: .value("Selected Date", selectedDate))
                    .foregroundStyle(Color.insulin.opacity(0.35))
            }

            // Dummy PointMark to force SwiftCharts to render a visible domain of 00:00-23:59
            // i.e. single day from midnight to midnight
            if selectedInterval == .day {
                let calendar = Calendar.current
                let midnight = calendar.startOfDay(for: Date())
                let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight)!

                PointMark(
                    x: .value("Time", nextMidnight),
                    y: .value("Dummy", 0)
                )
                .opacity(0) // ensures dummy ChartContent is hidden
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                if let amount = value.as(Double.self) {
                    AxisValueLabel {
                        Text(amount.formatted(.number.precision(.fractionLength(0))))
                            .font(.footnote)
                    }
                    AxisGridLine()
                }
            }
        }
        .chartXAxis {
            StatChartUtils.dateAxisMarks(for: selectedInterval)
        }
        .chartScrollableAxes(.horizontal)
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
        .chartScrollPosition(x: $scrollPosition)
        .chartScrollTargetBehavior(
            .valueAligned(
                matching: selectedInterval == .day ?
                    DateComponents(minute: 0) :
                    DateComponents(hour: 0),
                majorAlignment: .matching(StatChartUtils.alignmentComponents(for: selectedInterval))
            )
        )
        .chartXVisibleDomain(length: StatChartUtils.visibleDomainLength(for: selectedInterval))
        .frame(height: 250)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Total daily dose bar chart"))
    }
}
