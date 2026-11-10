import Charts
import SwiftDate
import SwiftUI

extension ElaraStat {
    /// The Trio statistics screen in the Elara skin, shown by the iAPS statistics screen while Elara is chosen.
    struct RootView: View {
        enum Constants {
            static let spacing: CGFloat = 16
            static let cornerRadius: CGFloat = 10
            static let backgroundOpacity = 0.1
        }

        @Environment(\.colorScheme) var colorScheme

        let highLimit: Decimal
        let units: GlucoseUnits
        let eA1cDisplayUnit: EstimatedA1cDisplayUnit
        let useFPUconversion: Bool
        let pumpHistory: () -> [PumpHistoryEvent]

        @State var state = StateModel()
        @State private var selectedView: StateModel.StatisticViewType = .glucose
        @State private var isGlucoseDaySelected: Bool = false
        @State private var showGlucoseStatsHelp = false
        @State private var glucoseStatsHintDetent = PresentationDetent.large

        private var intervalOptions: [ElaraStat.StateModel.StatsTimeIntervalWithToday] {
            state.selectedGlucoseChartType == .percentileByDay || state.selectedGlucoseChartType == .distributionByDay
                ? [.week, .month, .total] : ElaraStat.StateModel.StatsTimeIntervalWithToday.allCases
        }

        private var isElara: Bool { ElaraTheme.shared.isActive }

        /// Elara: the screen title large, with the number of readings in the period below.
        private var elaraHeader: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Statistics")
                    .font(.system(size: 34, weight: .heavy))
                    .tracking(-0.7)
                Text(verbatim: "\(state.glucoseFromPersistence.count) × " + elaraStatString("Glucose"))
                    .font(.system(size: 12))
                    .foregroundStyle(ElaraPalette.muted(colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        }

        private func elaraGlucoseText(_ mgdl: Decimal) -> String {
            state.units == .mmolL ? mgdl.formatted(for: .mmolL) : "\(mgdl)"
        }

        /// Elara: time in range as a large percentage over a low / in range / high bar.
        private var elaraTimeInRangeCard: some View {
            let values = state.glucoseFromPersistence.map { Decimal(Int($0.glucose)) }
            let total = max(1, values.count)
            let low = Double(values.filter { $0 < state.lowLimit }.count) / Double(total)
            let high = Double(values.filter { $0 > state.highLimit }.count) / Double(total)
            let inRange = values.isEmpty ? 0 : max(0, 1 - low - high)
            func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

            return VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Time in Range")
                            .font(.system(size: 15, weight: .semibold))
                        Text(
                            verbatim: "\(elaraGlucoseText(state.lowLimit)) – \(elaraGlucoseText(state.highLimit)) \(state.units.rawValue)"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(ElaraPalette.muted(colorScheme))
                    }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int((inRange * 100).rounded()))")
                            .font(.system(size: 44, weight: .black))
                            .foregroundStyle(ElaraPalette.green)
                        Text("%")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(ElaraPalette.green)
                    }
                }

                let parts: [(fraction: Double, color: Color)] = [
                    (low, ElaraPalette.red), (inRange, ElaraPalette.green), (high, ElaraPalette.high)
                ]
                GeometryReader { geometry in
                    HStack(spacing: 3) {
                        ForEach(0 ..< parts.count, id: \.self) { index in
                            let fraction = parts[index].fraction
                            let color = parts[index].color
                            if fraction > 0 {
                                Capsule()
                                    .fill(color)
                                    .frame(width: max(6, (geometry.size.width - 6) * fraction))
                            }
                        }
                    }
                }
                .frame(height: 10)

                HStack(spacing: 14) {
                    elaraLegend(String(localized: "Low"), percent(low), ElaraPalette.red)
                    elaraLegend(String(localized: "In Range"), percent(inRange), ElaraPalette.green)
                    elaraLegend(String(localized: "High"), percent(high), ElaraPalette.high)
                }
            }
            .padding(16)
            .elaraCard(colorScheme)
        }

        private func elaraLegend(_ title: String, _ value: String, _ color: Color) -> some View {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).foregroundStyle(ElaraPalette.muted(colorScheme))
                Text(value).fontWeight(.bold)
            }
            .font(.system(size: 12))
        }

        var body: some View {
            VStack {
                if isElara {
                    elaraHeader
                }

                Picker("View", selection: $selectedView) {
                    ForEach(StateModel.StatisticViewType.allCases) { viewType in
                        Text(viewType.displayName).tag(viewType)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ScrollView {
                    VStack(spacing: Constants.spacing) {
                        switch selectedView {
                        case .glucose:
                            glucoseView
                        case .insulin:
                            insulinView
                        case .looping:
                            loopingView
                        case .meals:
                            mealsView
                        }
                    }
                    .padding()
                }
            }
            // Dense charts and stat grids shatter at accessibility sizes; cap tighter than the global bound.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear {
                state.start(
                    highLimit: highLimit,
                    units: units,
                    eA1cDisplayUnit: eA1cDisplayUnit,
                    useFPUconversion: useFPUconversion,
                    pumpHistory: pumpHistory()
                )
            }
        }

        // MARK: - Stats View

        @ViewBuilder var glucoseView: some View {
            if isElara {
                elaraTimeInRangeCard
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Chart Type")
                    .font(.headline)

                Picker("Glucose Chart Type", selection: $state.selectedGlucoseChartType) {
                    ForEach(StateModel.GlucoseChartType.allCases, id: \.self) { type in
                        Text(type.displayName)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: state.selectedGlucoseChartType) { _, newValue in
                    // If switching to daily chart and day/today is selected, switch to week
                    if newValue == .percentileByDay || newValue == .distributionByDay,
                       state.selectedIntervalForGlucoseStats == .day || state.selectedIntervalForGlucoseStats == .today
                    {
                        state.selectedIntervalForGlucoseStats = .week
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            Picker("Duration", selection: $state.selectedIntervalForGlucoseStats) {
                ForEach(intervalOptions, id: \.self) { timeInterval in
                    Text(timeInterval.displayName)
                }
            }
            .pickerStyle(.segmented)

            if state.glucoseFromPersistence.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Glucose Data"),
                    systemImage: "chart.bar.fill",
                    description: Text("Glucose statistics will appear here once data is available.")
                )
            } else {
                timeInRangeCard

                if state.selectedGlucoseChartType == .glycemiaRiskIndex {
                    StatCard {
                        GRIExplanationView(result: GRICalculator.calculate(
                            glucoseValues: state.glucoseFromPersistence.map { Int($0.glucose) }
                        ), units: state.units)
                    }
                } else {
                    if !isGlucoseDaySelected && state.selectedGlucoseChartType != .percentileByDay && state
                        .selectedGlucoseChartType != .distributionByDay
                    {
                        glucoseStatsCard
                    }

                    var hintText: String? {
                        switch state.selectedGlucoseChartType {
                        case .glycemiaRiskIndex:
                            nil
                        case .percentileByTime:
                            String(localized: "Tap and hold the AGP graph or Time-in-Range ring to reveal more details.")
                        case .distributionByTime:
                            String(localized: "Tap and hold the Time-in-Range ring to reveal more details.")
                        case .percentileByDay:
                            String(
                                localized: "Tap a percentile or tap and hold a bar to reveal more details. Swipe to scroll through time."
                            )
                        case .distributionByDay:
                            String(
                                localized: "Tap and hold a bar in the chart to reveal more details. Swipe to scroll through time."
                            )
                        }
                    }
                    if let hintText {
                        HStack {
                            Image(systemName: "hand.draw.fill")
                                .foregroundStyle(Color.primary)
                                .padding(.leading)
                            Text(hintText)
                                .foregroundStyle(Color.secondary)
                                .padding(.trailing)
                        }.font(.footnote)
                    }
                }
            }
        }

        private var timeInRangeCard: some View {
            StatCard {
                VStack(spacing: Constants.spacing) {
                    switch state.selectedGlucoseChartType {
                    case .distributionByDay,
                         .percentileByDay:
                        let interval: ElaraStat.StateModel.StatsTimeInterval = {
                            switch state.selectedIntervalForGlucoseStats {
                            case .month,
                                 .total:
                                return ElaraStat.StateModel.StatsTimeInterval(
                                    rawValue: state.selectedIntervalForGlucoseStats.rawValue
                                )!
                            default:
                                return .week
                            }
                        }()

                        if state.selectedGlucoseChartType == .percentileByDay {
                            GlucoseDailyPercentileChart(
                                glucose: state.glucoseFromPersistence,
                                highLimit: state.highLimit,
                                units: state.units,
                                timeInRangeType: state.timeInRangeType,
                                selectedInterval: interval,
                                isDaySelected: $isGlucoseDaySelected,
                                state: state
                            )
                        } else { // if state.selectedGlucoseChartType == .distributionByDay
                            GlucoseDailyDistributionChart(
                                glucose: state.glucoseReadings,
                                highLimit: state.highLimit,
                                units: state.units,
                                timeInRangeType: state.timeInRangeType,
                                selectedInterval: interval,
                                eA1cDisplayUnit: state.eA1cDisplayUnit,
                                isDaySelected: $isGlucoseDaySelected,
                                state: state
                            )
                        }

                    case .glycemiaRiskIndex:
                        GRIChartView(result: GRICalculator.calculate(
                            glucoseValues: state.glucoseFromPersistence.map { Int($0.glucose) }
                        ), units: state.units)

                    case .percentileByTime:
                        GlucosePercentileChart(
                            glucose: state.glucoseFromPersistence,
                            highLimit: state.highLimit,
                            timeInRangeType: state.timeInRangeType,
                            units: state.units,
                            hourlyStats: state.hourlyStats,
                            isToday: state.selectedIntervalForGlucoseStats == .today
                        )

                    case .distributionByTime:
                        GlucoseDistributionChart(
                            glucose: state.glucoseReadings,
                            highLimit: state.highLimit,
                            lowLimit: state.lowLimit,
                            units: state.units,
                            glucoseRangeStats: state.glucoseRangeStats,
                            timeInRangeType: state.timeInRangeType
                        )
                    }
                }
            }
        }

        private var glucoseStatsCard: some View {
            StatCard {
                VStack(spacing: Constants.spacing) {
                    GlucoseSectorChart(
                        highLimit: state.highLimit,
                        units: state.units,
                        glucose: state.glucoseFromPersistence,
                        timeInRangeType: state.timeInRangeType,
                        showChart: true
                    )

                    Divider()

                    GlucoseMetricsView(
                        units: state.units,
                        eA1cDisplayUnit: state.eA1cDisplayUnit,
                        glucose: state.glucoseFromPersistence
                    )
                }
                .overlay(alignment: .topTrailing) {
                    Button(action: { showGlucoseStatsHelp = true }) {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(Color.blue)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("More information"))
                }
            }
            .sheet(isPresented: $showGlucoseStatsHelp) {
                GlucoseMetricsHelpView(hintDetent: $glucoseStatsHintDetent, showHelp: $showGlucoseStatsHelp)
            }
        }

        @ViewBuilder var insulinView: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Chart Type")
                    .font(.headline)

                Picker("Insulin Chart Type", selection: $state.selectedInsulinChartType) {
                    ForEach(StateModel.InsulinChartType.allCases, id: \.self) { type in
                        Text(type.displayName)
                    }
                }.pickerStyle(.menu)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            Picker("Duration", selection: $state.selectedIntervalForInsulinStats) {
                ForEach(StateModel.StatsTimeInterval.allCases) { timeInterval in
                    Text(timeInterval.displayName).tag(timeInterval)
                }
            }
            .pickerStyle(.segmented)

            StatCard {
                switch state.selectedInsulinChartType {
                case .totalDailyDose:
                    if state.dailyTDDStats.isEmpty {
                        ContentUnavailableView(
                            String(localized: "No TDD Data"),
                            systemImage: "chart.bar.xaxis",
                            description: Text("Total Daily Doses will appear here once data is available.")
                        )
                    } else {
                        TotalDailyDoseChart(
                            selectedInterval: $state.selectedIntervalForInsulinStats,
                            tddStats: state.selectedIntervalForInsulinStats == .day ?
                                state.hourlyTDDStats : state.dailyTDDStats,
                            state: state
                        )
                    }

                case .bolusDistribution:
                    var hasBolusData: Bool {
                        state.dailyBolusStats.contains { $0.manualBolus > 0 || $0.smb > 0 || $0.external > 0 }
                    }

                    if state.dailyBolusStats.isEmpty || !hasBolusData {
                        ContentUnavailableView(
                            String(localized: "No Bolus Data"),
                            systemImage: "cross.vial",
                            description: Text("Bolus statistics will appear here once data is available.")
                        )
                    } else {
                        BolusStatsView(
                            selectedInterval: $state.selectedIntervalForInsulinStats,
                            bolusStats: state.selectedIntervalForInsulinStats == .day ?
                                state.hourlyBolusStats : state.dailyBolusStats,
                            state: state
                        )
                    }
                }
            }

            HStack {
                Image(systemName: "hand.draw.fill").foregroundStyle(Color.primary)
                VStack(alignment: .leading) {
                    Text("Swipe the chart to scroll through time.")
                    Text("Tap and hold a bar to reveal more details.")
                }.foregroundStyle(Color.secondary)
            }.font(.footnote)
        }

        @ViewBuilder var loopingView: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Chart Type")
                    .font(.headline)

                Picker("Looping Chart Type", selection: $state.selectedLoopingChartType) {
                    ForEach(StateModel.LoopingChartType.allCases, id: \.self) { type in
                        Text(type.displayName)
                    }
                }.pickerStyle(.menu)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            Picker("Duration", selection: $state.selectedIntervalForLoopStats) {
                ForEach(StateModel.StatsTimeIntervalWithToday.allCases, id: \.self) { interval in
                    Text(interval.displayName)
                }
            }
            .pickerStyle(.segmented)

            StatCard {
                switch state.selectedLoopingChartType {
                case .loopingPerformance:
                    if state.loopStatRecords.isEmpty {
                        ContentUnavailableView(
                            String(localized: "No Loop Data"),
                            systemImage: "clock.arrow.2.circlepath",
                            description: Text("Loop statistics will appear here once data is available.")
                        )
                    } else {
                        loopingChartView
                        loopStats
                    }
                }
            }
        }

        private var loopingChartView: some View {
            VStack(spacing: Constants.spacing) {
                LoopBarChartView(
                    loopStatRecords: state.loopStatRecords,
                    selectedInterval: state.selectedIntervalForLoopStats,
                    statsData: state.loopStats
                )
            }
        }

        private var loopStats: some View {
            VStack(spacing: Constants.spacing) {
                LoopStatsView(
                    statsData: state.loopStats
                )
            }
        }

        @ViewBuilder var mealsView: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Chart Type")
                    .font(.headline)

                Picker("Meal Chart Type", selection: $state.selectedMealChartType) {
                    ForEach(StateModel.MealChartType.allCases, id: \.self) { type in
                        Text(type.displayName)
                    }
                }.pickerStyle(.menu)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            Picker("Duration", selection: $state.selectedIntervalForMealStats) {
                ForEach(StateModel.StatsTimeInterval.allCases, id: \.self) { timeInterval in
                    Text(timeInterval.displayName)
                }
            }
            .pickerStyle(.segmented)

            StatCard {
                switch state.selectedMealChartType {
                case .totalMeals:
                    var hasMealData: Bool {
                        state.dailyMealStats.contains { $0.carbs > 0 || $0.fat > 0 || $0.protein > 0 }
                    }

                    if state.dailyMealStats.isEmpty || !hasMealData {
                        ContentUnavailableView(
                            String(localized: "No Meal Data"),
                            systemImage: "leaf.fill",
                            description: Text("Meal statistics will appear here once data is available.")
                        )
                    } else {
                        MealStatsView(
                            selectedInterval: $state.selectedIntervalForMealStats,
                            mealStats: state.selectedIntervalForMealStats == .day ?
                                state.hourlyMealStats : state.dailyMealStats,
                            state: state
                        )
                    }
                }
            }

            HStack {
                Image(systemName: "hand.draw.fill").foregroundStyle(Color.primary)
                VStack(alignment: .leading) {
                    Text("Swipe the chart to scroll through time.")
                    Text("Tap and hold a bar to reveal more details.")
                }.foregroundStyle(Color.secondary)
            }.font(.footnote)
        }
    }
}

// MARK: - Supporting Views

struct StatCard<Content: View>: View {
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if ElaraTheme.shared.isActive {
            content
                .padding()
                .elaraCard(colorScheme)
        } else {
            content
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: ElaraStat.RootView.Constants.cornerRadius)
                        .fill(Color.secondary.opacity(ElaraStat.RootView.Constants.backgroundOpacity))
                )
        }
    }
}
