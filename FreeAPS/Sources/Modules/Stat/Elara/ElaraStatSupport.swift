import CoreData
import Foundation
import SwiftUI

/// The statistics of the Elara skin, taken over from Trio. They read the data iAPS already stores.
enum ElaraStat {}

// MARK: - Settings used by the Trio statistics

/// Lower threshold of the time in range and time in tight range statistics (Trio's standard: 70 mg/dL).
enum TimeInRangeType: String, CaseIterable, Identifiable, Hashable {
    var id: String { rawValue }
    case timeInTightRange

    var bottomThreshold: Int { 70 }
    var topThreshold: Int { 140 }
}

/// Unit of the estimated HbA1c, following the iAPS HbA1c unit setting.
enum EstimatedA1cDisplayUnit: String, CaseIterable, Identifiable, Hashable {
    var id: String { rawValue }
    case percent
    case mmolMol
}

// MARK: - Colours used by the Trio statistics

extension Color {
    static let dynamicRed = Color("LoopRed")
    static let dynamicOrange = Color("LoopYellow")
    static let dynamicGreen = Color("LoopGreen")
    static let dynamicTeal = Color("DarkGreen")
    static let dynamicBlue = Color(hue: 200.0 / 360.0, saturation: 0.6, brightness: 0.9)
    static let dynamicIndigo = Color(hue: 235.0 / 360.0, saturation: 0.6, brightness: 0.9)
    static let dynamicPurple = ElaraPalette.high

    static let staticLow = Color.dynamicRed
    static let staticInRange = Color.dynamicGreen
    static let staticHigh = Color.dynamicPurple

    static let bgDarkBlue = Color(red: 16 / 255, green: 32 / 255, blue: 68 / 255)
}

// MARK: - Glucose formatting

extension Decimal {
    /// The value (in mg/dL) as text in the given unit: mmol/L with one decimal.
    func formatted(for units: GlucoseUnits) -> String {
        if units == .mmolL {
            return asMmolL.formatted(.number.grouping(.never).precision(.fractionLength(1)))
        }
        return formatted(.number.grouping(.never).precision(.fractionLength(0)))
    }
}

extension Decimal {
    func formatted(withUnits units: GlucoseUnits) -> String {
        formatted(for: units) + " \(units.rawValue)"
    }

    func asUnit(_ units: GlucoseUnits) -> Decimal {
        units == .mgdL ? self : asMmolL.rounded(to: 1, roundingMode: .plain)
    }
}

extension Int {
    func formatted(withUnits units: GlucoseUnits) -> String {
        Decimal(self).formatted(withUnits: units)
    }

    func formatted(for units: GlucoseUnits) -> String {
        Decimal(self).formatted(for: units)
    }
}

extension Double {
    func asUnit(_ units: GlucoseUnits) -> Double {
        units == .mgdL ? self : Double(truncating: Decimal(self).asMmolL.rounded(to: 1, roundingMode: .plain) as NSNumber)
    }

    func formatted(withUnits units: GlucoseUnits) -> String {
        Decimal(self).formatted(withUnits: units)
    }

    func formatted(for units: GlucoseUnits) -> String {
        Decimal(self).formatted(for: units)
    }
}

// MARK: - Core Data helpers used by the Trio statistics

enum CoreDataError: Error {
    case fetchError(function: String, file: String)
    case unexpectedError(error: Error, function: String, file: String)
}

extension CoreDataStack {
    func newTaskContext() -> NSManagedObjectContext {
        let taskContext = persistentContainer.newBackgroundContext()
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        taskContext.undoManager = nil
        return taskContext
    }

    func fetchEntitiesAsync<T: NSManagedObject>(
        ofType type: T.Type,
        onContext context: NSManagedObjectContext,
        predicate: NSPredicate,
        key: String,
        ascending: Bool,
        fetchLimit: Int? = nil,
        batchSize: Int? = nil,
        propertiesToFetch: [String]? = nil,
        callingFunction: String = #function,
        callingClass: String = #fileID
    ) async throws -> Any {
        let request: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: String(describing: type))
        request.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        request.predicate = predicate
        if let fetchLimit { request.fetchLimit = fetchLimit }
        if let batchSize { request.fetchBatchSize = batchSize }
        if let propertiesToFetch {
            request.propertiesToFetch = propertiesToFetch
            request.resultType = .dictionaryResultType
        } else {
            request.resultType = .managedObjectResultType
        }

        return try await context.perform {
            do {
                if propertiesToFetch != nil {
                    return try context.fetch(request) as? [[String: Any]] ?? []
                }
                return try context.fetch(request) as? [T] ?? []
            } catch {
                throw CoreDataError.unexpectedError(error: error, function: callingFunction, file: callingClass)
            }
        }
    }

    func getNSManagedObject<T: NSManagedObject>(
        with ids: [NSManagedObjectID],
        context: NSManagedObjectContext,
        callingFunction: String = #function,
        callingClass: String = #fileID
    ) async throws -> [T] {
        try await context.perform {
            do {
                return try ids.compactMap { try context.existingObject(with: $0) as? T }
            } catch {
                throw CoreDataError.fetchError(function: callingFunction, file: callingClass)
            }
        }
    }
}

extension NSPredicate {
    private static func readings(since date: Date) -> NSPredicate {
        NSPredicate(format: "glucose > 0 AND date >= %@", date as NSDate)
    }

    static var glucoseForStatsToday: NSPredicate { readings(since: Calendar.current.startOfDay(for: Date())) }
    static var glucoseForStatsDay: NSPredicate { readings(since: Date().addingTimeInterval(-24 * 3600)) }
    static var glucoseForStatsWeek: NSPredicate { readings(since: Date().addingTimeInterval(-7 * 24 * 3600)) }
    static var glucoseForStatsMonth: NSPredicate { readings(since: Date().addingTimeInterval(-30 * 24 * 3600)) }
    static var glucoseForStatsTotal: NSPredicate { readings(since: Date().addingTimeInterval(-90 * 24 * 3600)) }

    static var mealsForStats: NSPredicate {
        NSPredicate(format: "actualDate >= %@", Date().addingTimeInterval(-90 * 24 * 3600) as NSDate)
    }
}

extension Calendar {
    /// Converts an hour (0-23) to a Date object representing that hour on the current day.
    /// This is used to properly position marks on the chart's time axis.
    ///
    /// - Parameter hour: Integer representing the hour of day (0-23)
    /// - Returns: Date object set to the specified hour on the current day
    ///
    /// Example:
    /// ```
    /// calendar.dateForChartHour(14) // Returns today's date at 2:00 PM
    /// calendar.dateForChartHour(0)  // Returns today's date at 12:00 AM
    /// ```
    func dateForChartHour(_ hour: Int) -> Date {
        let today = startOfDay(for: Date())
        return date(byAdding: .hour, value: hour, to: today) ?? today
    }
}

// MARK: - Translations

/// Words the statistics share with other iAPS screens but translate differently in Trio (such as
/// "Looping", which iAPS translates as the loop status). They use their own "elara.stats." key, and
/// otherwise the regular iAPS translation.
func elaraStatString(_ key: String) -> String {
    let regular = NSLocalizedString(key, comment: "")
    return Bundle.main.localizedString(forKey: "elara.stats." + key, value: regular, table: nil)
}
