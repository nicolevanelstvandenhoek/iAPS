import SwiftUI

/// Elara's main chart: every glucose reading as a slim bar colored by range (red below the
/// low limit, green in range, violet above), the forecast as faded bars, a soft reflection,
/// carb and bolus dots at their time, and the basal rate as a strip at the bottom.
struct ElaraSpectrumChart: View {
    @ObservedObject var data: ChartModel
    /// Hours on screen; the same setting as the hours menu of the iAPS home screen.
    @Binding var hours: Int
    /// A double tap opens the data table, as a tap on the iAPS chart does.
    var onOpenDataTable: () -> Void
    /// Opens the snooze screen for glucose alarms.
    var onSnoozeAlarms: () -> Void
    /// True while a glucose alarm is active.
    var alarmActive: Bool

    @Environment(\.colorScheme) private var scheme

    /// What a tap on a bar or a dot selected; shown as a small card over the chart.
    private struct Selection: Equatable {
        let id: String
        let point: CGPoint
        let color: Color
        let time: Date
        let title: String
        let value: String
        let detail: String?
    }

    @State private var selection: Selection?

    private func snoozeButton() -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSnoozeAlarms()
        } label: {
            Image(systemName: alarmActive ? "bell.and.waves.left.and.right.fill" : "bell.slash.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(alarmActive ? ElaraPalette.red : ElaraPalette.text(scheme))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(ElaraPalette.control(scheme)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Snooze Alerts"))
    }

    private static let hourOptions = [1, 3, 6, 9, 12, 24]

    // MARK: - Units

    private var isMmolL: Bool { data.units == .mmolL }

    private func label(_ mgdl: Double) -> String {
        if isMmolL {
            return String(format: "%.1f", mgdl * 0.0555).replacingOccurrences(of: ".", with: ",")
        }
        return "\(Int(mgdl.rounded()))"
    }

    private var lowMgdl: Double { NSDecimalNumber(decimal: data.lowGlucose).doubleValue }
    private var highMgdl: Double { NSDecimalNumber(decimal: data.highGlucose).doubleValue }

    // MARK: - Window

    private var now: Date { Date() }
    private var windowStart: Date { now.addingTimeInterval(-Double(hours) * 3600) }
    /// Forecast after now: 60 min, but only 20 min on the 1 h view so the past keeps most of the width.
    private var forecastMinutes: Double { hours < 3 ? 20 : 60 }
    private var windowEnd: Date { now.addingTimeInterval(forecastMinutes * 60) }

    private struct Reading {
        let date: Date
        let mgdl: Double
        let forecast: Bool
    }

    private var readings: [Reading] {
        data.glucose.compactMap { g in
            guard let value = g.glucose ?? g.sgv, g.dateString >= windowStart, g.dateString <= now else { return nil }
            return Reading(date: g.dateString, mgdl: Double(value), forecast: false)
        }
        .sorted { $0.date < $1.date }
    }

    /// The forecast line shown first: carbs, then unannounced meals, then IOB, then zero-temp.
    private var forecast: [Reading] {
        guard !data.hidePredictions,
              let suggestion = data.suggestion,
              let start = suggestion.deliverAt ?? suggestion.timestamp,
              let values = suggestion.predictions?.cob ?? suggestion.predictions?.uam
              ?? suggestion.predictions?.iob ?? suggestion.predictions?.zt
        else { return [] }
        let lastReading = readings.last?.date ?? now
        return values.enumerated().compactMap { index, value in
            let date = start.addingTimeInterval(Double(index) * 300)
            guard date > lastReading, date <= windowEnd else { return nil }
            return Reading(date: date, mgdl: Double(value), forecast: true)
        }
    }

    private struct Dot {
        let date: Date
        let color: Color
        let isCarb: Bool
        let title: String
        let value: String
        let detail: String?
    }

    private var carbDots: [Dot] {
        data.carbs
            .filter { !($0.isFPU ?? false) && $0.carbs > 0 }
            .compactMap { entry in
                let date = entry.actualDate ?? entry.createdAt
                guard date >= windowStart, date <= now else { return nil }
                var details: [String] = []
                if let fat = entry.fat, fat > 0 {
                    details.append(NSLocalizedString("Fat", comment: "") + " \(NSDecimalNumber(decimal: fat).intValue) g")
                }
                if let protein = entry.protein, protein > 0 {
                    details.append(NSLocalizedString("Protein", comment: "") + " \(NSDecimalNumber(decimal: protein).intValue) g")
                }
                if let note = entry.note, !note.isEmpty { details.append(note) }
                return Dot(
                    date: date,
                    color: ElaraPalette.carbs,
                    isCarb: true,
                    title: NSLocalizedString("Carbs", comment: ""),
                    value: "\(NSDecimalNumber(decimal: entry.carbs).intValue) g",
                    detail: details.isEmpty ? nil : details.joined(separator: " · ")
                )
            }
    }

    private var bolusDots: [Dot] {
        data.boluses.compactMap { event in
            guard let amount = event.amount, amount >= data.minimumSMB,
                  event.timestamp >= windowStart, event.timestamp <= now else { return nil }
            let isSMB = event.isSMB ?? false
            return Dot(
                date: event.timestamp,
                color: ElaraPalette.insulin,
                isCarb: false,
                title: isSMB ? "SMB" : "Bolus",
                value: unitsText(amount, digits: 2) + " " + NSLocalizedString("U", comment: "Insulin unit"),
                detail: (event.isExternal ?? false) ? NSLocalizedString("External", comment: "External Insulin") : nil
            )
        }
    }

    /// Latest carb entry and bolus in the window, for the legend under the title.
    private var latestCarbs: Decimal? {
        data.carbs
            .filter { !($0.isFPU ?? false) && $0.carbs > 0 && ($0.actualDate ?? $0.createdAt) >= windowStart }
            .max { ($0.actualDate ?? $0.createdAt) < ($1.actualDate ?? $1.createdAt) }?
            .carbs
    }

    private var latestBolus: Decimal? {
        data.boluses
            .filter { ($0.amount ?? 0) >= data.minimumSMB && $0.timestamp >= windowStart }
            .max { $0.timestamp < $1.timestamp }?
            .amount
    }

    // MARK: - Basal

    private struct BasalSegment {
        let start: Date
        let end: Date
        let rate: Double
    }

    /// A temp basal is stored as a rate event followed by a duration event.
    private var basalSegments: [BasalSegment] {
        var temps: [BasalSegment] = []
        let events = data.tempBasals
        for (index, event) in events.enumerated() where event.type == .tempBasal {
            guard index + 1 < events.count, events[index + 1].type == .tempBasalDuration else { continue }
            let duration = Double(events[index + 1].durationMin ?? 0) * 60
            guard duration > 0 else { continue }
            temps.append(BasalSegment(
                start: event.timestamp,
                end: event.timestamp.addingTimeInterval(duration),
                rate: NSDecimalNumber(decimal: event.rate ?? 0).doubleValue
            ))
        }
        temps.sort { $0.start < $1.start }
        var segments: [BasalSegment] = []
        var cursor = windowStart
        for (i, t) in temps.enumerated() {
            // A later temp basal cancels the one before it
            let end = min(t.end, i + 1 < temps.count ? temps[i + 1].start : .distantFuture, now)
            guard end > windowStart, t.start < now, end > t.start else { continue }
            let start = max(t.start, windowStart)
            if cursor < start { appendProfile(from: cursor, to: start, into: &segments) }
            segments.append(BasalSegment(start: start, end: end, rate: t.rate))
            cursor = max(cursor, end)
        }
        if cursor < now { appendProfile(from: cursor, to: now, into: &segments) }
        return segments
    }

    private func appendProfile(from start: Date, to end: Date, into segments: inout [BasalSegment]) {
        guard start < end, !data.basalProfile.isEmpty else { return }
        let sorted = data.basalProfile.sorted { $0.minutes < $1.minutes }
        let calendar = Calendar.current
        var cursor = start
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            let time = calendar.dateComponents([.hour, .minute], from: cursor)
            let minutes = (time.hour ?? 0) * 60 + (time.minute ?? 0)
            let index = sorted.lastIndex { $0.minutes <= minutes } ?? (sorted.count - 1)
            let nextMinutes = index + 1 < sorted.count ? sorted[index + 1].minutes : 24 * 60 + sorted[0].minutes
            let next = Self.profileSwitchDate(minutes: nextMinutes, from: dayStart, after: cursor, calendar: calendar)
            let segmentEnd = min(end, next)
            // The cursor must always move forward, or the chart hangs the app
            guard segmentEnd > cursor else { break }
            segments.append(BasalSegment(
                start: cursor,
                end: segmentEnd,
                rate: NSDecimalNumber(decimal: sorted[index].rate).doubleValue
            ))
            cursor = segmentEnd
        }
    }

    /// The date a basal profile entry starting `minutes` after midnight of `dayStart` takes
    /// effect (values of 24 h and more fall on later days), resolved on the clock so a 23 or 25 h
    /// day keeps the switch at the right time.
    private static func profileSwitchDate(minutes: Int, from dayStart: Date, after cursor: Date, calendar: Calendar) -> Date {
        let day = calendar.date(byAdding: .day, value: minutes / (24 * 60), to: dayStart) ?? dayStart
        let clock = minutes % (24 * 60)
        let date = calendar.date(bySettingHour: clock / 60, minute: clock % 60, second: 0, of: day)
            ?? day.addingTimeInterval(TimeInterval(clock * 60))
        return date > cursor ? date : date.addingTimeInterval(3600)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            legend
            GeometryReader { geo in
                chart(size: geo.size)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onOpenDataTable() }
                    .onTapGesture { location in
                        withAnimation(.easeOut(duration: 0.15)) { select(at: location, size: geo.size) }
                    }
            }
            .frame(minHeight: 180)
            .task(id: selection?.id) {
                // Close the card again after a few seconds
                guard selection != nil else { return }
                try? await Task.sleep(for: .seconds(6))
                withAnimation(.easeOut(duration: 0.2)) { selection = nil }
            }
            timeLabels
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .elaraCard(scheme, radius: 28)
    }

    private var header: some View {
        HStack {
            Text(String(localized: "elara.chart.title", defaultValue: "Glucose"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ElaraPalette.text(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(-1)
            Spacer()
            snoozeButton()
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                ForEach(Self.hourOptions, id: \.self) { option in
                    let selected = hours == option
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        hours = option
                    } label: {
                        Text("\(option)" + NSLocalizedString("h", comment: "Short for hours"))
                            .font(.system(size: 12, weight: selected ? .semibold : .medium))
                            .foregroundStyle(
                                selected ? (scheme == .dark ? Color.black : Color.white) : ElaraPalette.muted(scheme)
                            )
                            .frame(minWidth: 31, minHeight: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selected ? ElaraPalette.text(scheme) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ElaraPalette.control(scheme)))
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder private var legend: some View {
        if latestCarbs != nil || latestBolus != nil {
            HStack(spacing: 12) {
                if let carbs = latestCarbs {
                    legendItem(color: ElaraPalette.carbs, text: "\(NSDecimalNumber(decimal: carbs).intValue) g")
                }
                if let bolus = latestBolus {
                    legendItem(
                        color: ElaraPalette.insulin,
                        text: unitsText(bolus) + " " + NSLocalizedString("U", comment: "Insulin unit")
                    )
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ElaraPalette.readable(color, scheme))
        }
    }

    private func unitsText(_ units: Decimal, digits: Int = 1) -> String {
        NSDecimalNumber(decimal: units).doubleValue.formatted(.number.precision(.fractionLength(digits)))
    }

    private var timeLabels: some View {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        // A third of the window per label: 20 min at 1 h, 3 h at 9 h
        let step = Double(hours) * 3600 / 3
        let marks = (1 ... 3).map { now.addingTimeInterval(-Double($0) * step) }.reversed()
        return HStack {
            ForEach(Array(marks), id: \.self) { date in
                Text(formatter.string(from: date))
                Spacer()
            }
            Text("now")
                .fontWeight(.semibold)
                .foregroundStyle(ElaraPalette.text(scheme))
        }
        // "Now" sits under the end of the plot, not under the range rail
        .padding(.trailing, Self.railWidth)
        .font(.system(size: 11))
        .foregroundStyle(ElaraPalette.muted(scheme))
        .padding(.horizontal, 2)
    }

    // MARK: - Layout

    /// Positions shared by drawing and tapping, so a tap finds exactly what is drawn there.
    private struct Layout {
        let size: CGSize
        let start: Date
        let span: TimeInterval
        let barWidth: CGFloat
        let baseline: CGFloat
        let barArea: CGFloat
        let reflectionHeight: CGFloat
        let basalHeight: CGFloat
        let yMin: Double
        let maxValue: Double
        let toDisplay: (Double) -> Double

        func x(_ date: Date) -> CGFloat {
            CGFloat(date.timeIntervalSince(start) / span) * (size.width - barWidth)
        }

        func height(_ mgdl: Double) -> CGFloat {
            CGFloat(max(0, (toDisplay(mgdl) - yMin) / (maxValue - yMin))) * barArea
        }
    }

    /// Room on the right for the range rail with the limit values.
    private static let railWidth: CGFloat = 44

    private func layout(for size: CGSize) -> Layout {
        // Bars, dots and basal use the plot; the rail sits to its right
        let plot = CGSize(width: max(1, size.width - Self.railWidth), height: size.height)
        let all = readings + forecast
        let isMmolL = self.isMmolL
        let toDisplay: (Double) -> Double = { isMmolL ? $0 * 0.0555 : $0 }
        let maxValue = max(
            toDisplay(highMgdl) + (isMmolL ? 2 : 36),
            (all.map { toDisplay($0.mgdl) }.max() ?? 0) + (isMmolL ? 1 : 18)
        )
        let basalHeight: CGFloat = 16
        let reflectionHeight = size.height * 0.16
        let baseline = size.height - basalHeight - reflectionHeight - 6
        let span = windowEnd.timeIntervalSince(windowStart)
        let slot = plot.width / CGFloat(span / 300)
        return Layout(
            size: plot,
            start: windowStart,
            span: span,
            barWidth: max(1.2, min(4, slot * 0.64)),
            baseline: baseline,
            barArea: baseline - 18,
            reflectionHeight: reflectionHeight,
            basalHeight: basalHeight,
            yMin: isMmolL ? 2.0 : 36.0,
            maxValue: maxValue,
            toDisplay: toDisplay
        )
    }

    /// Top of the bar nearest to a moment, so dots sit right above it.
    private func barTop(at date: Date, _ l: Layout) -> CGFloat {
        let nearest = readings.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        return l.baseline - l.height(nearest?.mgdl ?? lowMgdl)
    }

    private func dotCenter(_ dot: Dot, _ l: Layout) -> CGPoint {
        CGPoint(x: l.x(dot.date) + l.barWidth / 2, y: barTop(at: dot.date, l) - (dot.isCarb ? 18 : 9))
    }

    // MARK: - Tapping

    /// A tap on a dot shows the meal or bolus; a tap near a bar shows that reading; elsewhere it closes.
    private func select(at location: CGPoint, size: CGSize) {
        let l = layout(for: size)
        let dots = carbDots + bolusDots
        if let dot = dots.min(by: { distance(dotCenter($0, l), location) < distance(dotCenter($1, l), location) }),
           distance(dotCenter(dot, l), location) < 18
        {
            let id = "dot-\(dot.isCarb)-\(dot.date.timeIntervalSince1970)"
            selection = selection?.id == id ? nil : Selection(
                id: id,
                point: dotCenter(dot, l),
                color: dot.color,
                time: dot.date,
                title: dot.title,
                value: dot.value,
                detail: dot.detail
            )
        } else if let reading = (readings + forecast)
            .min(by: { abs(l.x($0.date) - location.x) < abs(l.x($1.date) - location.x) }),
            abs(l.x(reading.date) + l.barWidth / 2 - location.x) < max(12, l.barWidth * 3)
        {
            let id = "bar-\(reading.forecast)-\(reading.date.timeIntervalSince1970)"
            let status = reading.mgdl < lowMgdl ? NSLocalizedString("Low", comment: "Elara glucose status") :
                reading.mgdl > highMgdl ? NSLocalizedString("High", comment: "Elara glucose status") :
                NSLocalizedString("In range", comment: "Elara glucose status")
            selection = selection?.id == id ? nil : Selection(
                id: id,
                point: CGPoint(x: l.x(reading.date) + l.barWidth / 2, y: l.baseline - l.height(reading.mgdl)),
                color: ElaraPalette.status(mgdl: reading.mgdl, low: lowMgdl, high: highMgdl),
                time: reading.date,
                title: reading.forecast ? NSLocalizedString("Eventual", comment: "Elara forecast") :
                    NSLocalizedString("Glucose", comment: ""),
                value: label(reading.mgdl) + " " + data.units.rawValue,
                detail: reading.forecast ? nil : status
            )
        } else {
            selection = nil
        }
        if selection != nil {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Small card with the selected item, kept inside the chart.
    @ViewBuilder private func selectionCard(_ size: CGSize) -> some View {
        if let selection {
            let formatter: DateFormatter = {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                return formatter
            }()
            let cardWidth: CGFloat = 150
            let x = min(max(selection.point.x, cardWidth / 2), size.width - cardWidth / 2)
            let y = max(30, selection.point.y - 40)

            Circle()
                .stroke(selection.color, lineWidth: 2)
                .frame(width: 14, height: 14)
                .position(selection.point)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(selection.color).frame(width: 7, height: 7)
                    Text(selection.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ElaraPalette.muted(scheme))
                    Spacer(minLength: 4)
                    Text(formatter.string(from: selection.time))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(ElaraPalette.muted(scheme))
                }
                Text(selection.value)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(ElaraPalette.text(scheme))
                if let detail = selection.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(ElaraPalette.muted(scheme))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: cardWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(scheme == .dark ? Color(red: 30 / 255, green: 36 / 255, blue: 48 / 255) : Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            )
            .position(x: x, y: y)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Drawing

    private func chart(size: CGSize) -> some View {
        let all = readings + forecast
        let l = layout(for: size)
        let reflectionHeight = l.reflectionHeight
        let basalHeight = l.basalHeight
        let baseline = l.baseline
        let barWidth = l.barWidth

        func x(_ date: Date) -> CGFloat { l.x(date) }
        func height(_ mgdl: Double) -> CGFloat { l.height(mgdl) }
        func color(_ mgdl: Double) -> Color {
            ElaraPalette.status(mgdl: mgdl, low: lowMgdl, high: highMgdl)
        }

        let current = readings.last
        let segments = basalSegments
        let maxRate = max(0.5, segments.map(\.rate).max() ?? 0, NSDecimalNumber(decimal: data.maxBasal).doubleValue * 0.5)
        let dots = carbDots + bolusDots

        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                // Range limits across the plot
                let plotWidth = l.size.width
                let highY = baseline - height(highMgdl)
                let lowY = baseline - height(lowMgdl)
                for (y, tint) in [(highY, ElaraPalette.high), (lowY, ElaraPalette.red)] {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: plotWidth, y: y))
                    context.stroke(line, with: .color(tint.opacity(0.55)), style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
                }

                // Range rail to the right of the plot: green between the limits, purple above and
                // red below, with a dot and the value at each limit
                let railX = plotWidth + 10
                let railTop = baseline - l.barArea
                for (from, to, tint, opacity) in [
                    (railTop, highY, ElaraPalette.high, 0.35),
                    (highY, lowY, ElaraPalette.green, 1.0),
                    (lowY, baseline, ElaraPalette.red, 0.35)
                ] where to > from {
                    var rail = Path()
                    rail.move(to: CGPoint(x: railX, y: from))
                    rail.addLine(to: CGPoint(x: railX, y: to))
                    context.stroke(rail, with: .color(tint.opacity(opacity)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                for (mgdl, y, tint) in [(highMgdl, highY, ElaraPalette.high), (lowMgdl, lowY, ElaraPalette.red)] {
                    context.fill(
                        Path(ellipseIn: CGRect(x: railX - 4, y: y - 4, width: 8, height: 8)),
                        with: .color(tint)
                    )
                    context.draw(
                        Text(label(mgdl))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(ElaraPalette.readable(tint, scheme)),
                        at: CGPoint(x: railX + 8, y: y),
                        anchor: .leading
                    )
                }

                // Bars and their reflection
                for reading in all {
                    let h = height(reading.mgdl)
                    let tint = color(reading.mgdl)
                    let opacity = reading.forecast ? 0.3 : 1
                    let bar = CGRect(x: x(reading.date), y: baseline - h, width: barWidth, height: h)
                    context.fill(Path(roundedRect: bar, cornerRadius: barWidth / 2), with: .color(tint.opacity(opacity)))
                    if !reading.forecast {
                        let mirror = CGRect(x: bar.minX, y: baseline + 4, width: barWidth, height: min(h * 0.3, reflectionHeight))
                        context.fill(Path(roundedRect: mirror, cornerRadius: barWidth / 2), with: .color(tint.opacity(0.13)))
                    }
                }

                // Carb and bolus dots above the bar at their time
                for dot in dots {
                    let center = dotCenter(dot, l)
                    let rect = CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: rect), with: .color(dot.color))
                }

                // Basal strip
                if !segments.isEmpty {
                    var path = Path()
                    let bottom = size.height
                    path.move(to: CGPoint(x: x(segments[0].start), y: bottom))
                    for segment in segments {
                        let y = bottom - CGFloat(segment.rate / maxRate) * basalHeight
                        path.addLine(to: CGPoint(x: x(segment.start), y: y))
                        path.addLine(to: CGPoint(x: x(segment.end), y: y))
                    }
                    path.addLine(to: CGPoint(x: x(segments[segments.count - 1].end), y: bottom))
                    path.closeSubpath()
                    context.fill(path, with: .color(ElaraPalette.insulin.opacity(scheme == .dark ? 0.45 : 0.35)))
                }
            }

            // Now: arrow.down.circle just above the newest bar
            if let current {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ElaraPalette.text(scheme))
                    .position(x: x(current.date) + barWidth / 2, y: baseline - height(current.mgdl) - 10)
            }

            selectionCard(size)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("Glucose as bars over the last %d hours", comment: "Elara chart"),
            hours
        )))
    }
}
