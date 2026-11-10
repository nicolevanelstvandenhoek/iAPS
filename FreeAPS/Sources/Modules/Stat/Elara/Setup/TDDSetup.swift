import CoreData
import Foundation

/// Represents statistical data about Total Daily Dose for a specific time period
struct TDDStats: Identifiable {
    let id = UUID()
    /// The date representing this time period
    let date: Date
    /// Total insulin in units
    let amount: Double
}

extension ElaraStat.StateModel {
    /// Sets up TDD statistics by fetching and processing insulin data
    func setupTDDStats() {
        Task {
            do {
                let (hourly, daily) = try await fetchTDDStats()

                await MainActor.run {
                    self.hourlyTDDStats = hourly
                    self.dailyTDDStats = daily
                }

                // Initially calculate and cache daily averages
                await calculateAndCacheTDDAverages()
            } catch {
                warning(.default, "Fetching total daily dose statistics failed", error: error)
            }
        }
    }

    /// Daily totals come from the TDD iAPS saves with every loop; the hourly view (D) is built from
    /// the boluses and temp basals of the iAPS pump history, which holds the last 24 hours.
    private func fetchTDDStats() async throws -> (hourly: [TDDStats], daily: [TDDStats]) {
        let tddTaskContext = CoreDataStack.shared.newTaskContext()
        tddTaskContext.name = "ElaraStat.fetchTDDStats"

        let threeMonthsAgo = Date().addingTimeInterval(-90 * 24 * 3600)
        let tddResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TDD.self,
            onContext: tddTaskContext,
            predicate: NSPredicate(format: "timestamp >= %@ AND tdd > 0", threeMonthsAgo as NSDate),
            key: "timestamp",
            ascending: true,
            batchSize: 100
        )

        let calendar = Calendar.current
        let daily = await tddTaskContext.perform {
            self.processDailyTDDs(tddResults as? [TDD] ?? [], calendar: calendar)
        }
        let hourly = processHourlyInsulinData(events: pumpHistory, calendar: calendar)
        return (hourly, daily)
    }

    /// Spreads the boluses and temp basals of the pump history over the hours they were given in,
    /// leaving out the time the pump was suspended.
    private func processHourlyInsulinData(events: [PumpHistoryEvent], calendar: Calendar) -> [TDDStats] {
        var insulinByHour: [Date: Double] = [:]
        let sorted = events.sorted { $0.timestamp < $1.timestamp }

        func hour(_ date: Date) -> Date {
            calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
        }

        for bolus in sorted where bolus.type == .bolus || bolus.type == .isExternal {
            insulinByHour[hour(bolus.timestamp), default: 0] += NSDecimalNumber(decimal: bolus.amount ?? 0).doubleValue
        }

        // Suspend and resume pairs
        var suspensions: [(start: Date, end: Date)] = []
        for suspend in sorted where suspend.type == .pumpSuspend {
            if let resume = sorted.first(where: { $0.type == .pumpResume && $0.timestamp > suspend.timestamp }) {
                suspensions.append((suspend.timestamp, resume.timestamp))
            } else {
                suspensions.append((suspend.timestamp, Date()))
            }
        }

        func effectiveHours(from start: Date, to end: Date) -> Double {
            let total = end.timeIntervalSince(start) / 3600
            let suspended = suspensions.reduce(0.0) { sum, pair in
                guard pair.start < end, pair.end > start else { return sum }
                return sum + min(end, pair.end).timeIntervalSince(max(start, pair.start)) / 3600
            }
            return max(0, total - suspended)
        }

        // Temp basals run until the next temp basal, at most their planned duration
        let temps = sorted.filter { $0.type == .tempBasal }
        let durations = sorted.filter { $0.type == .tempBasalDuration }
        for (index, temp) in temps.enumerated() {
            let rate = NSDecimalNumber(decimal: temp.rate ?? 0).doubleValue
            guard rate > 0 else { continue }
            let planned = durations.first(where: { abs($0.timestamp.timeIntervalSince(temp.timestamp)) < 1 })?.durationMin
                ?? temp.duration ?? 30
            var end = temp.timestamp.addingTimeInterval(Double(planned) * 60)
            if index < temps.count - 1 { end = min(end, temps[index + 1].timestamp) }
            end = min(end, Date())
            guard end > temp.timestamp else { continue }

            var segmentStart = temp.timestamp
            while segmentStart < end {
                let nextHour = calendar.date(byAdding: .hour, value: 1, to: hour(segmentStart)) ?? end
                let segmentEnd = min(nextHour, end)
                insulinByHour[hour(segmentStart), default: 0] += rate * effectiveHours(from: segmentStart, to: segmentEnd)
                segmentStart = segmentEnd
            }
        }

        return insulinByHour.keys.sorted().map { TDDStats(date: $0, amount: insulinByHour[$0, default: 0]) }
    }

    /// Processes TDDStored records to create daily Total Daily Dose statistics
    /// - Parameters:
    ///   - tdds: Array of TDDStored objects containing daily insulin data
    ///   - calendar: Calendar instance used for date calculations and grouping
    /// - Returns: Array of TDDStats objects representing daily insulin amounts
    /// - Note: This method groups TDD records by day and uses only the last (most recent) entry
    ///         for each day, as this represents the complete TDD value for that day. This approach
    ///         is appropriate for week, month, and total views where we want the final daily totals.
    private func processDailyTDDs(_ tdds: [TDD], calendar: Calendar) -> [TDDStats] {
        // MARK: - Group TDDs by Calendar Day

        // Create a dictionary where keys are start-of-day dates and values are arrays of TDD entries for that day
        let dailyGrouped = Dictionary(grouping: tdds) { tdd in
            guard let timestamp = tdd.timestamp else { return Date() }
            // Use start of day (midnight) as the key for grouping
            return calendar.startOfDay(for: timestamp)
        }

        // MARK: - Process Each Day's Entries

        // Create a TDDStats object for each day using the most recent TDD entry
        return dailyGrouped.keys.sorted().map { dayDate in
            // Get all TDD entries for this day
            let entries = dailyGrouped[dayDate, default: []]

            // MARK: - Sort and Select Most Recent Entry

            // Sort entries chronologically to find the most recent one for the day
            let sortedEntries = entries.sorted {
                ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast)
            }

            // MARK: - Create TDDStats from Most Recent Entry

            // The last entry in the sorted array contains the complete TDD for the day
            if let lastEntry = sortedEntries.last, let total = lastEntry.tdd?.doubleValue {
                // Create TDDStats with the day's date and the total insulin amount
                return TDDStats(
                    date: dayDate,
                    amount: total
                )
            } else {
                // Fallback if no valid entry exists for this day
                return TDDStats(
                    date: dayDate,
                    amount: 0.0
                )
            }
        }
    }

    /// Calculates and caches the daily averages of Total Daily Dose (TDD) insulin values
    /// - Note: This function runs asynchronously and updates the tddAveragesCache on the main actor
    private func calculateAndCacheTDDAverages() async {
        let tddTaskContext = CoreDataStack.shared.newTaskContext()
        tddTaskContext.name = "StatStateModel.calculateAndCacheTDDAverages"

        // Get calendar for date calculations
        let calendar = Calendar.current

        // Calculate daily averages on background context
        let dailyAverages = await tddTaskContext.perform { [dailyTDDStats] in
            // Group TDD stats by calendar day
            let groupedByDay = Dictionary(grouping: dailyTDDStats) { stat in
                calendar.startOfDay(for: stat.date)
            }

            // Calculate average TDD for each day
            var averages: [Date: Double] = [:]
            for (day, stats) in groupedByDay {
                // Sum up all TDD values for the day
                let total = stats.reduce(0.0) { $0 + $1.amount }
                let count = Double(stats.count)
                // Store average in dictionary
                averages[day] = total / count
            }
            return averages
        }

        // Update cache on main actor
        await MainActor.run {
            self.tddAveragesCache = dailyAverages
        }
    }

    /// Gets the cached average Total Daily Dose (TDD) of insulin for a specified date range
    /// - Parameter range: A tuple containing the start and end dates to get averages for
    /// - Returns: The average TDD in units for the specified date range
    func getCachedTDDAverages(for range: (start: Date, end: Date)) -> Double {
        // Calculate and return the TDD averages for the given date range using cached values
        calculateTDDAveragesForDateRange(from: range.start, to: range.end)
    }

    /// Calculates the average Total Daily Dose (TDD) of insulin for a specified date range
    /// - Parameters:
    ///   - startDate: The start date of the range to calculate averages for
    ///   - endDate: The end date of the range to calculate averages for
    /// - Returns: The average TDD in units for the specified date range. Returns 0.0 if no data exists.
    private func calculateTDDAveragesForDateRange(from startDate: Date, to endDate: Date) -> Double {
        // Filter cached TDD values to only include those within the date range
        let relevantStats = tddAveragesCache.filter { date, _ in
            date >= startDate && date <= endDate
        }

        // Return 0 if no data exists for the specified range
        guard !relevantStats.isEmpty else { return 0.0 }

        // Calculate total TDD by summing all values
        let total = relevantStats.values.reduce(0.0, +)
        // Convert count to Double for floating point division
        let count = Double(relevantStats.count)

        // Return average TDD
        return total / count
    }
}
