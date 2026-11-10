import Charts
import SwiftUI

/// A view that displays a bar chart for meal statistics.
///
/// This view presents macronutrient intake (carbohydrates, fats, and proteins) over time,
/// allowing users to adjust the time interval and scroll through historical data.
struct MealStatsView: View {
    /// The selected time interval for displaying statistics.
    @Binding var selectedInterval: ElaraStat.StateModel.StatsTimeInterval
    /// The list of meal statistics data.
    let mealStats: [MealStats]
    /// The state model containing cached statistics data.
    let state: ElaraStat.StateModel

    /// The current scroll position in the chart.
    @State private var scrollPosition = Date()
    /// The currently selected date in the chart.
    @State private var selectedDate: Date?
    /// The calculated macronutrient averages for the visible range.
    @State private var currentAverages: (carbs: Double, fat: Double, protein: Double) = (0, 0, 0)
    /// Timer to throttle updates when scrolling.
    @State private var updateTimer = ElaraStat.UpdateTimer()
    /// The actual chart plot's width in pixel
    @State private var chartWidth: CGFloat = 0

    /// Computes the visible date range based on the current scroll position.
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.visibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    /// Retrieves the meal statistic for a given date.
    /// - Parameter date: The date for which to retrieve meal data.
    /// - Returns: The `MealStats` object if available, otherwise `nil`.
    private func getMealForDate(_ date: Date) -> MealStats? {
        mealStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    /// Updates the macronutrient averages based on the visible date range.
    private func updateAverages() {
        currentAverages = state.getCachedMealAverages(for: visibleDateRange)
    }

    /// The macros shown in the summary: the selected bar's, or the period's averages.
    private var shownMacros: (carbs: Double, fat: Double, protein: Double) {
        guard let selectedDate else { return currentAverages }
        guard let meal = getMealForDate(selectedDate) else { return (0, 0, 0) }
        return (meal.carbs, meal.fat, meal.protein)
    }

    /// A view displaying the statistics summary: the period's averages, or the selected bar's values.
    private var statsView: some View {
        let macros = shownMacros
        return HStack(alignment: .top) {
            Grid(alignment: .leading, verticalSpacing: 2) {
                GridRow {
                    Text("Carbs:")
                    (
                        Text(macros.carbs.formatted(.number.precision(.fractionLength(1))))
                            + Text("\u{00A0}") + Text("g")
                    )
                    .foregroundStyle(selectedDate != nil ? Color.orange : Color.primary)
                }
                if state.useFPUconversion {
                    GridRow {
                        Text("Fat:")
                        Text(macros.fat.formatted(.number.precision(.fractionLength(1))))
                            + Text("\u{00A0}") + Text("g")
                    }
                    GridRow {
                        Text("Protein:")
                        Text(macros.protein.formatted(.number.precision(.fractionLength(1))))
                            + Text("\u{00A0}") + Text("g")
                    }
                }
            }
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)

            Spacer()

            if let selectedDate {
                StatSelectionPill(
                    text: StatChartUtils.selectionLabel(for: selectedDate, interval: selectedInterval),
                    color: .orange
                ) {
                    withAnimation(.easeInOut) { self.selectedDate = nil }
                }
            } else {
                Text(
                    StatChartUtils
                        .formatVisibleDateRange(from: visibleDateRange.start, to: visibleDateRange.end, for: selectedInterval)
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView.padding(.bottom)

            VStack(alignment: .trailing) {
                Text("Macro Nutrients (g)")
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
            }
        }
        .onChange(of: scrollPosition) {
            updateTimer.scheduleUpdate {
                updateAverages()
            }
        }
        .onChange(of: selectedInterval) {
            Task {
                scrollPosition = StatChartUtils.getInitialScrollPosition(for: selectedInterval)
                // Use async dispatch to ensure scroll position is updated before calculating averages
                await MainActor.run {
                    updateAverages()
                }
            }
        }
    }

    /// A view displaying the bar chart for meal statistics.
    private var chartsView: some View {
        Chart {
            ForEach(mealStats) { stat in
                // Carbs Bar (bottom)
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.carbs)
                )
                .foregroundStyle(by: .value("Type", "Carbs"))
                .position(by: .value("Type", "Macros"))
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )
                if state.useFPUconversion {
                    // Fat Bar (middle)
                    BarMark(
                        x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                        y: .value("Amount", stat.fat)
                    )
                    .foregroundStyle(by: .value("Type", "Fat"))
                    .position(by: .value("Type", "Macros"))
                    .opacity(
                        selectedDate.map { date in
                            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                        } ?? 1
                    )
                    // Protein Bar (top)
                    BarMark(
                        x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                        y: .value("Amount", stat.protein)
                    )
                    .foregroundStyle(by: .value("Type", "Protein"))
                    .position(by: .value("Type", "Macros"))
                    .opacity(
                        selectedDate.map { date in
                            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                        } ?? 1
                    )
                }
            }

            // The selected bar's values are shown in the summary above the chart
            if let selectedDate, getMealForDate(selectedDate) != nil {
                RuleMark(x: .value("Selected Date", selectedDate))
                    .foregroundStyle(Color.orange.opacity(0.35))
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
        .chartForegroundStyleScale([
            "Carbs": Color.orange,
            "Fat": Color.purple,
            "Protein": Color.blue
        ])
        .chartLegend(position: .bottom, alignment: .leading, spacing: 12) {
            let legendItems: [(String, Color)] = state.useFPUconversion ? [
                (String(localized: "Carbs"), Color.orange),
                (String(localized: "Fat"), Color.purple),
                (elaraStatString("Protein"), Color.blue)
            ] : [(String(localized: "Carbs"), Color.orange)]

            let columns = [GridItem(.adaptive(minimum: 95), spacing: 4)]

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
        .accessibilityLabel(Text("Meal macronutrients bar chart"))
    }
}
