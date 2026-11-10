import Charts
import SwiftUI

/// A view that displays a bar chart for bolus insulin statistics.
///
/// This view presents different types of bolus insulin (manual, SMB, and external) over time,
/// allowing users to adjust the time interval and scroll through historical data.
struct BolusStatsView: View {
    /// The selected time interval for displaying statistics.
    @Binding var selectedInterval: ElaraStat.StateModel.StatsTimeInterval
    /// The list of bolus statistics data.
    let bolusStats: [BolusStats]
    /// The state model containing cached statistics data.
    let state: ElaraStat.StateModel

    /// The current scroll position in the chart.
    @State private var scrollPosition = Date()
    /// The currently selected date in the chart.
    @State private var selectedDate: Date?
    /// The calculated bolus insulin averages for the visible range.
    @State private var currentAverages: (manual: Double, smb: Double, external: Double) = (0, 0, 0)
    /// The calculated total bolus insulin for the visible range.
    @State private var currentTotal: Double = 0
    /// Timer to throttle updates when scrolling.
    @State private var updateTimer = ElaraStat.UpdateTimer()
    /// The actual chart plot's width in pixel
    @State private var chartWidth: CGFloat = 0

    /// Computes the visible date range based on the current scroll position.
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    /// Retrieves the bolus statistic for a given date.
    /// - Parameter date: The date for which to retrieve bolus data.
    /// - Returns: The `BolusStats` object if available, otherwise `nil`.
    private func getBolusForDate(_ date: Date) -> BolusStats? {
        bolusStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    /// Updates the bolus insulin averages based on the visible date range.
    private func updateCalculatedValues() {
        currentAverages = state.getCachedBolusAverages(for: visibleDateRange)
        currentTotal = state.getCachedBolusTotals(for: visibleDateRange)
    }

    /// The bolus values shown in the summary: the selected bar's, or the period's averages and total.
    private var shownBolus: (manual: Double, smb: Double, external: Double, total: Double) {
        guard let selectedDate else {
            return (currentAverages.manual, currentAverages.smb, currentAverages.external, currentTotal)
        }
        guard let bolus = getBolusForDate(selectedDate) else { return (0, 0, 0, 0) }
        return (bolus.manualBolus, bolus.smb, bolus.external, bolus.manualBolus + bolus.smb + bolus.external)
    }

    /// Averages over a period get the ø prefix; a single day or bar does not.
    private func label(_ title: LocalizedStringKey) -> Text {
        selectedInterval != .day && selectedDate == nil
            ? Text("ø") + Text("\u{00A0}") + Text(title)
            : Text(title)
    }

    /// A view displaying the statistics summary: the period's bolus averages, or the selected bar's values.
    private var statsView: some View {
        let shown = shownBolus
        return HStack(alignment: .top) {
            Grid(alignment: .leading) {
                GridRow {
                    label("Manual:")
                    Text(shown.manual.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("U")
                }
                GridRow {
                    label("SMB:")
                    Text(shown.smb.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("U")
                }
                GridRow {
                    label("External:")
                    Text(shown.external.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("U")
                }
                Divider()
                GridRow {
                    Text("Total:")
                    Text(shown.total.formatted(.number.precision(.fractionLength(1))))
                        .foregroundStyle(selectedDate != nil ? Color.insulin : Color.primary)
                        + Text("\u{00A0}") + Text("U")
                }
            }
            .font(.headline)
            .accessibilityElement(children: .combine)

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView.padding(.bottom)

            VStack(alignment: .trailing) {
                Text("Bolus Insulin (U)")
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
                updateCalculatedValues()
            }
        }
        .onChange(of: scrollPosition) {
            updateTimer.scheduleUpdate {
                updateCalculatedValues()
            }
        }
        .onChange(of: selectedInterval) {
            Task {
                scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
                // Use async dispatch to ensure scroll position is updated before calculating values
                await MainActor.run {
                    updateCalculatedValues()
                }
            }
        }
    }

    /// A view displaying the bar chart for bolus insulin statistics.
    private var chartsView: some View {
        Chart {
            ForEach(bolusStats) { stat in
                // Total Bolus Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.manualBolus)
                )
                .foregroundStyle(by: .value("Type", "Manual"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )

                // Carb Bolus Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.smb)
                )
                .foregroundStyle(by: .value("Type", "SMB"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )
                // Correction Bolus Bar
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.external)
                )
                .foregroundStyle(by: .value("Type", "External"))
                .position(by: .value("Type", "Boluses"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )
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

            // The selected bar's values are shown in the summary above the chart
            if let selectedDate, getBolusForDate(selectedDate) != nil {
                RuleMark(x: .value("Selected Date", selectedDate))
                    .foregroundStyle(Color.insulin.opacity(0.35))
            }
        }
        .chartForegroundStyleScale([
            "SMB": Color.blue,
            "Manual": Color.teal,
            "External": Color.purple
        ])
        .chartLegend(position: .bottom, alignment: .leading, spacing: 12) {
            let legendItems: [(String, Color)] = [
                (String(localized: "SMB"), Color.blue),
                (String(localized: "Manual"), Color.teal),
                (elaraStatString("External"), Color.purple)
            ]

            let columns = [GridItem(.adaptive(minimum: 65), spacing: 4)]

            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(legendItems, id: \.0) { item in
                    StatChartUtils.legendItem(label: item.0, color: item.1)
                }
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
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: $scrollPosition)
        .chartScrollTargetBehavior(
            .valueAligned(
                matching:
                selectedInterval == .day ?
                    DateComponents(minute: 0) : // Align to next hour for Day view
                    DateComponents(hour: 0), // Align to start of day for other views
                majorAlignment: .matching(
                    StatChartUtils.alignmentComponents(for: selectedInterval)
                )
            )
        )
        .chartXVisibleDomain(length: StatChartUtils.visibleDomainLength(for: selectedInterval))
        .frame(height: 280)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Bolus insulin bar chart"))
    }
}
