import CoreData
import Foundation
import Observation
import SwiftUI

extension ElaraStat {
    /// Data of the Elara statistics screen, the Trio statistics on iAPS data.
    @Observable final class StateModel {
        var highLimit: Decimal = 180
        var lowLimit: Decimal = 70
        var eA1cDisplayUnit: EstimatedA1cDisplayUnit = .percent
        var units: GlucoseUnits = .mgdL
        var timeInRangeType: TimeInRangeType = .timeInTightRange
        /// Shows fat and protein next to the carbs, following the iAPS fat and protein setting.
        var useFPUconversion: Bool = false
        /// The iAPS pump history (last 24 hours), for the hourly insulin and the bolus split.
        @ObservationIgnored var pumpHistory: [PumpHistoryEvent] = []
        var glucoseFromPersistence: [Readings] = []
        var loopStatRecords: [LoopStatRecord] = []
        var loopStats: [LoopStatsProcessedData] = []
        var groupedLoopStats: [LoopStatsByPeriod] = []
        var bolusStats: [BolusStats] = []
        var hourlyStats: [HourlyStats] = []
        var glucoseRangeStats: [GlucoseRangeStats] = []

        var hourlyMealStats: [MealStats] = []
        var dailyMealStats: [MealStats] = []
        var dailyMealTotalsCache: [Date: (carbs: Double, fat: Double, protein: Double)] = [:]

        var hourlyTDDStats: [TDDStats] = []
        var dailyTDDStats: [TDDStats] = []
        var tddAveragesCache: [Date: Double] = [:]

        var hourlyBolusStats: [BolusStats] = []
        var dailyBolusStats: [BolusStats] = []
        var bolusAveragesCache: [Date: (manual: Double, smb: Double, external: Double)] = [:]
        var bolusTotalsCache: [(Date, total: Double)] = []

        var dailyGlucosePercentileStats: [GlucoseDailyPercentileStats] = []
        var glucosePercentileCache: [Date: GlucoseDailyPercentileStats] = [:]
        var dailyGlucoseDistributionStats: [GlucoseDailyDistributionStats] = []
        var glucoseDistributionCache: [Date: GlucoseDailyDistributionStats] = [:]
        var glucoseReadings: [Readings] = []

        @ObservationIgnored private var started = false

        var selectedIntervalForGlucoseStats: StatsTimeIntervalWithToday = .today {
            didSet { if started { setupGlucoseArray(for: selectedIntervalForGlucoseStats) } }
        }

        var selectedIntervalForInsulinStats: StatsTimeInterval = .day
        var selectedIntervalForMealStats: StatsTimeInterval = .day

        var selectedIntervalForLoopStats: StatsTimeIntervalWithToday = .today {
            didSet { if started { setupLoopStatRecords() } }
        }

        var selectedGlucoseChartType: GlucoseChartType = .percentileByTime
        var selectedInsulinChartType: InsulinChartType = .totalDailyDose
        var selectedLoopingChartType: LoopingChartType = .loopingPerformance
        var selectedMealChartType: MealChartType = .totalMeals

        @ObservationIgnored let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        /// Starts all fetches once, with the iAPS settings.
        func start(
            highLimit: Decimal,
            units: GlucoseUnits,
            eA1cDisplayUnit: EstimatedA1cDisplayUnit,
            useFPUconversion: Bool,
            pumpHistory: [PumpHistoryEvent]
        ) {
            guard !started else { return }
            started = true
            self.highLimit = highLimit
            self.units = units
            self.eA1cDisplayUnit = eA1cDisplayUnit
            self.useFPUconversion = useFPUconversion
            self.pumpHistory = pumpHistory
            lowLimit = Decimal(timeInRangeType.bottomThreshold)

            setupGlucoseArray(for: selectedIntervalForGlucoseStats)
            setupLoopStatRecords()
            setupTDDStats()
            setupBolusStats()
            setupMealStats()
            setupGlucoseDailyStats()
        }

        func setupGlucoseArray(for interval: StatsTimeIntervalWithToday) {
            Task {
                // Load data for current interval (existing code)
                let ids = await fetchGlucose(for: interval)
                await updateGlucoseArray(with: ids)

                // Also ensure we have the full dataset loaded
                if glucoseReadings.isEmpty {
                    let allIds = await fetchGlucose(for: .total)
                    await updateAllGlucoseArray(with: allIds)
                }

                // Calculate hourly stats and glucose range stats asynchronously with fetched glucose IDs
                async let hourlyStats: () = calculateHourlyStatsForGlucoseAreaChart(from: ids)
                async let glucoseRangeStats: () = calculateGlucoseRangeStatsForStackedChart(from: ids)
                _ = await (hourlyStats, glucoseRangeStats)
            }
        }

        func setupGlucoseDailyStats() {
            Task {
                // Get glucose IDs once (using the private fetchGlucose method)
                let allIds = await fetchGlucose(for: .total)

                // Pass the IDs to the implementation in GlucoseStatsSetup.swift
                await setupGlucoseStats(with: allIds)
            }
        }

        private func fetchGlucose(for interval: StatsTimeIntervalWithToday) async -> [NSManagedObjectID] {
            do {
                let context = CoreDataStack.shared.newTaskContext()
                context.name = "StatStateModel.fetchGlucose"

                let predicate: NSPredicate

                switch interval {
                case .day:
                    predicate = NSPredicate.glucoseForStatsDay
                case .week:
                    predicate = NSPredicate.glucoseForStatsWeek
                case .today:
                    predicate = NSPredicate.glucoseForStatsToday
                case .month:
                    predicate = NSPredicate.glucoseForStatsMonth
                case .total:
                    predicate = NSPredicate.glucoseForStatsTotal
                }

                let results = try await CoreDataStack.shared.fetchEntitiesAsync(
                    ofType: Readings.self,
                    onContext: context,
                    predicate: predicate,
                    key: "date",
                    ascending: false,
                    batchSize: 100,
                    propertiesToFetch: ["glucose", "objectID"]
                )

                return try await context.perform {
                    guard let fetchedResults = results as? [[String: Any]] else {
                        throw CoreDataError.fetchError(function: #function, file: #file)
                    }
                    return fetchedResults.compactMap { $0["objectID"] as? NSManagedObjectID }
                }
            } catch {
                warning(.default, "Fetching glucose for statistics failed", error: error)
                return []
            }
        }

        @MainActor private func updateGlucoseArray(with IDs: [NSManagedObjectID]) {
            do {
                let glucoseObjects = try IDs.compactMap { id in
                    try viewContext.existingObject(with: id) as? Readings
                }
                glucoseFromPersistence = glucoseObjects
            } catch {
                warning(.default, "Loading glucose for statistics failed", error: error)
            }
        }

        @MainActor private func updateAllGlucoseArray(with IDs: [NSManagedObjectID]) {
            do {
                let glucoseObjects = try IDs.compactMap { id in
                    try viewContext.existingObject(with: id) as? Readings
                }
                glucoseReadings = glucoseObjects
            } catch {
                warning(.default, "Loading all glucose readings for statistics failed", error: error)
            }
        }
    }

    @Observable final class UpdateTimer {
        private var workItem: DispatchWorkItem?

        /// Schedules a delayed update action
        /// - Parameter action: The closure to execute after the delay
        /// Cancels any previously scheduled update before scheduling a new one
        func scheduleUpdate(action: @escaping () -> Void) {
            workItem?.cancel()

            let newWorkItem = DispatchWorkItem {
                action()
            }
            workItem = newWorkItem

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: newWorkItem)
        }
    }
}

// MARK: Stats Types + Enums

extension ElaraStat.StateModel {
    /// Defines the available types of glucose charts
    enum GlucoseChartType: String, CaseIterable {
        /// Ambulatory Glucose Profile showing percentile ranges
        case percentileByTime = "Percentile"
        /// Time-based distribution of glucose ranges
        case distributionByTime = "Distribution"
        /// Glycemia Risk Index for the selected period
        case glycemiaRiskIndex = "Glycemia Risk Index"
        /// Day-based box plot of glucose percentile ranges
        case percentileByDay = "Percentile (by day)"
        /// Day-based distribution of glucose ranges
        case distributionByDay = "Distribution (by day)"

        var displayName: String {
            switch self {
            case .percentileByTime:
                return String(localized: "Percentile")
            case .distributionByTime:
                return String(localized: "Distribution")
            case .glycemiaRiskIndex:
                return String(localized: "Glycemia Risk Index")
            case .percentileByDay:
                return String(localized: "Percentile (by day)")
            case .distributionByDay:
                return String(localized: "Distribution (by day)")
            }
        }
    }

    /// Defines the available types of insulin charts
    enum InsulinChartType: String, CaseIterable {
        /// Shows total daily insulin doses
        case totalDailyDose = "Total Daily Dose"
        /// Shows distribution of bolus types
        case bolusDistribution = "Bolus Distribution"

        var displayName: String {
            switch self {
            case .totalDailyDose:
                return String(localized: "Total Daily Dose")
            case .bolusDistribution:
                return String(localized: "Bolus Distribution")
            }
        }
    }

    /// Defines the available types of looping charts
    enum LoopingChartType: String, CaseIterable {
        /// Shows loop completion and success rates
        case loopingPerformance = "Looping Performance"

        var displayName: String {
            switch self {
            case .loopingPerformance:
                return String(localized: "Looping Performance")
            }
        }
    }

    /// Defines the available types of meal charts
    enum MealChartType: String, CaseIterable {
        /// Shows total meal statistics
        case totalMeals = "Total Meals"

        var displayName: String {
            switch self {
            case .totalMeals:
                return String(localized: "Total Meals")
            }
        }
    }

    /// Defines the available time periods for duration-based statistics including 'Today' (time since midnight until now)
    enum StatsTimeIntervalWithToday: String, CaseIterable, Identifiable {
        /// Current day
        case today
        /// Single day view
        case day = "D"
        /// Week view
        case week = "W"
        /// Month view
        case month = "M"
        /// Three month view
        case total = "3 M"

        var id: Self { self }

        var displayName: String {
            switch self {
            case .today:
                return String(localized: "Today")
            case .day:
                return String(localized: "D", comment: "Abbreviation for day")
            case .week:
                return String(localized: "W", comment: "Abbreviation for week")
            case .month:
                return String(localized: "M", comment: "Abbreviation for month")
            case .total:
                return String(localized: "3 M", comment: "Abbreviation for three months")
            }
        }
    }

    /// Defines the available time periods for duration-based statistics
    enum StatsTimeInterval: String, CaseIterable, Identifiable {
        /// Single day interval
        case day = "D"
        /// Week interval
        case week = "W"
        /// Month interval
        case month = "M"
        /// Three month interval
        case total = "3 M"

        var id: Self { self }

        var displayName: String {
            switch self {
            case .day:
                return String(localized: "D", comment: "Abbreviation for day")
            case .week:
                return String(localized: "W", comment: "Abbreviation for week")
            case .month:
                return String(localized: "M", comment: "Abbreviation for month")
            case .total:
                return String(localized: "3 M", comment: "Abbreviation for three months")
            }
        }
    }

    /// Defines the main categories of statistics available in the app
    enum StatisticViewType: String, CaseIterable, Identifiable {
        /// Glucose-related statistics including AGP and distributions
        case glucose
        /// Insulin delivery statistics including TDD and bolus distributions
        case insulin
        /// Loop performance and system status statistics
        case looping
        /// Meal-related statistics and correlations
        case meals

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .glucose:
                return elaraStatString("Glucose")
            case .insulin:
                return String(localized: "Insulin", comment: "Title for insulin-related statistics")
            case .looping:
                return elaraStatString("Looping")
            case .meals:
                return elaraStatString("Meals")
            }
        }
    }
}
