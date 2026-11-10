import G7SensorKit
import SwiftDate
import SwiftUI

/// The Elara home screen. It uses the state and actions of the iAPS home screen and only
/// replaces the layout: a bold glucose value, a spectrum chart and compact strips for the
/// remaining data. The summaries of the iAPS home screen follow below the first page.
extension Home.RootView {
    var elaraContent: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ElaraBackground()

                ScrollView {
                    VStack(spacing: 8) {
                        VStack(spacing: 8) {
                            // The same notice of a newer iAPS release as on the iAPS home screen
                            versionBanner
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            elaraHero
                                .padding(.bottom, 14)
                            elaraBolusStrip
                            elaraStatsRow
                            ElaraSpectrumChart(
                                data: state.data,
                                hours: $state.hours,
                                onOpenDataTable: { state.showModal(for: .dataTable) },
                                onSnoozeAlarms: { state.showModal(for: .snooze) },
                                alarmActive: state.alarm != nil
                            )
                            .frame(maxHeight: .infinity)
                            elaraInsulinStrip
                            elaraDeviceStrip
                            elaraLoopStrip
                        }
                        .frame(height: max(560, geo.size.height - Self.elaraNavBarHeight - 8))

                        // The bar covers the bottom of the first page: the summaries start below it,
                        // on the next page
                        Color.clear.frame(height: Self.elaraNavBarHeight + 16)

                        elaraSummaries
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, Self.elaraNavBarHeight + 16)
                }
                .scrollIndicators(.hidden)

                elaraNavBar
            }
        }
        .sheet(isPresented: $showElaraStatus) {
            ElaraStatusSheet(state: state)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .environment(\.colorScheme, colorScheme)
        }
    }

    static var elaraNavBarHeight: CGFloat { 84 }

    // MARK: - Glucose value

    private var elaraGlucose: Double? {
        (state.recentGlucose?.glucose ?? state.recentGlucose?.sgv).map(Double.init)
    }

    private var elaraLow: Double { NSDecimalNumber(decimal: state.data.lowGlucose).doubleValue }
    private var elaraHigh: Double { NSDecimalNumber(decimal: state.data.highGlucose).doubleValue }

    private var elaraStatusColor: Color {
        guard let glucose = elaraGlucose else { return ElaraPalette.device }
        return ElaraPalette.status(mgdl: glucose, low: elaraLow, high: elaraHigh)
    }

    private var elaraStatusText: String {
        guard let glucose = elaraGlucose else { return "" }
        if glucose < elaraLow { return NSLocalizedString("Low", comment: "Elara glucose status") }
        if glucose > elaraHigh { return NSLocalizedString("High", comment: "Elara glucose status") }
        return NSLocalizedString("In range", comment: "Elara glucose status")
    }

    /// Whole part and decimal of the current value; mg/dL has no decimal.
    private var elaraValueParts: (whole: String, decimal: String?) {
        // No reading yet: a dash
        guard let glucose = elaraGlucose else { return ("—", nil) }
        guard state.data.units == .mmolL else { return ("\(Int(glucose.rounded()))", nil) }
        let text = String(format: "%.1f", glucose * 0.0555)
        let parts = text.split(separator: ".")
        return (String(parts.first ?? "0"), parts.count > 1 ? String(parts[1]) : nil)
    }

    private var elaraDeltaText: String {
        guard let delta = state.glucoseDelta else { return "" }
        if state.data.units == .mmolL {
            return String(format: "%+.1f", Double(delta) * 0.0555)
                .replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
        }
        return String(format: "%+d", delta)
    }

    private var elaraReadingAge: String {
        guard let date = state.recentGlucose?.dateString else { return "" }
        let minutes = max(0, Int(state.data.timerDate.timeIntervalSince(date) / 60))
        return "\(minutes) min"
    }

    private var elaraTrendAngle: Angle? {
        switch state.recentGlucose?.direction {
        case .doubleUp,
             .singleUp,
             .tripleUp: return .degrees(-90)
        case .fortyFiveUp: return .degrees(-45)
        case .flat: return .degrees(0)
        case .fortyFiveDown: return .degrees(45)
        case .doubleDown,
             .singleDown,
             .tripleDown: return .degrees(90)
        default: return nil
        }
    }

    private var elaraValue: some View {
        let parts = elaraValueParts
        // The comma sits on the baseline; the decimal is raised so its top lines up with the
        // whole part, like a superscript.
        let whole: CGFloat = 86
        let decimalSize: CGFloat = 44
        let digits = HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(parts.whole)
                .font(.system(size: whole, weight: .black))
            if let decimal = parts.decimal {
                Text(Locale.current.decimalSeparator ?? ",")
                    .font(.system(size: 32, weight: .black))
                    .padding(.horizontal, 1)
                Text(decimal)
                    .font(.system(size: decimalSize, weight: .black))
                    .baselineOffset((whole - decimalSize) * 0.7)
            }
        }
        .tracking(-2)
        .padding(.horizontal, 4)
        .fixedSize()
        let base = elaraStatusColor
        let gradient = LinearGradient(
            colors: colorScheme == .dark
                ? [ElaraPalette.lightened(base, by: 0.7), ElaraPalette.lightened(base, by: 0.25), base]
                : [ElaraPalette.lightened(base, by: 0.25), base, ElaraPalette.deepened(base)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        return digits
            .opacity(0)
            .overlay(gradient.mask(digits))
            .shadow(color: base.opacity(colorScheme == .dark ? 0.4 : 0.25), radius: 12, y: colorScheme == .dark ? 0 : 6)
            .accessibilityElement()
            .accessibilityLabel(Text(parts.decimal.map { "\(parts.whole),\($0)" } ?? parts.whole))
    }

    private var elaraHero: some View {
        HStack(alignment: .center) {
            elaraValue
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    if let angle = elaraTrendAngle {
                        Circle()
                            .fill(elaraStatusColor)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(Color.black)
                                    .rotationEffect(angle)
                            )
                    }
                    Text(elaraDeltaText)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ElaraPalette.text(colorScheme))
                }
                Text(
                    elaraReadingAge.isEmpty ? state.data.units.rawValue :
                        "\(state.data.units.rawValue) · \(elaraReadingAge)"
                )
                .font(.system(size: 12))
                .foregroundStyle(ElaraPalette.muted(colorScheme))
                Text(elaraStatusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ElaraPalette.readable(elaraStatusColor, colorScheme))
            }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 118)
        .contentShape(Rectangle())
        // The same actions as the glucose value of the iAPS home screen
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if state.alarm == nil {
                state.openCGM()
            } else {
                state.showModal(for: .snooze)
            }
        }
        .onLongPressGesture {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            if state.alarm == nil {
                state.showModal(for: .snooze)
            } else {
                state.openCGM()
            }
        }
    }

    // MARK: - Bolus

    /// A running bolus as a capsule under the glucose value: a blue line runs clockwise around it
    /// from the left as the bolus is delivered. The stop button stands apart on the right. The
    /// slot keeps its height when no bolus runs, so nothing jumps.
    @ViewBuilder private var elaraBolusStrip: some View {
        if let progress = state.bolusProgress, let amount = state.bolusAmount {
            let total = NSDecimalNumber(decimal: amount).doubleValue
            let fraction = min(1, max(0, NSDecimalNumber(decimal: progress).doubleValue))
            let delivered = total * fraction
            let unit = NSLocalizedString("U", comment: "Insulin unit")
            HStack(spacing: 10) {
                ZStack {
                    ElaraBolusCapsule()
                        .fill(ElaraPalette.insulin.opacity(colorScheme == .dark ? 0.14 : 0.10))
                    ElaraBolusCapsule()
                        .stroke(ElaraPalette.insulin.opacity(colorScheme == .dark ? 0.25 : 0.18), lineWidth: 3)
                    ElaraBolusCapsule()
                        .trim(from: 0, to: CGFloat(fraction))
                        .stroke(ElaraPalette.insulin, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .animation(.linear(duration: 0.5), value: fraction)

                    HStack(spacing: 9) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(ElaraPalette.insulin))
                            .background(Circle().fill(ElaraPalette.insulin.opacity(0.18)).padding(-5))
                        (
                            Text(NSLocalizedString("Bolusing", comment: "") + " · ")
                                + Text(Self.elaraBolusAmount(delivered)).bold()
                                + Text(" / " + Self.elaraBolusAmount(total) + " " + unit)
                        )
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ElaraPalette.text(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                }
                .padding(1.5)
                .accessibilityElement(children: .combine)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    state.cancelBolus()
                } label: {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(ElaraPalette.red)
                            .frame(width: 11, height: 11)
                        Text("Stop")
                            .font(.system(size: 15, weight: .bold))
                            // White on the dark background reads better at night.
                            .foregroundStyle(colorScheme == .dark ? Color.white : ElaraPalette.red)
                    }
                    .padding(.horizontal, 15)
                    .frame(maxHeight: .infinity)
                    .background(Capsule().fill(ElaraPalette.red.opacity(colorScheme == .dark ? 0.18 : 0.12)))
                    .overlay(
                        Capsule().stroke(
                            colorScheme == .dark ? ElaraPalette.red : ElaraPalette.red.opacity(0.25),
                            lineWidth: colorScheme == .dark ? 1.5 : 1
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Cancel bolus"))
            }
            .frame(height: 46)
            .transition(.opacity)
        } else {
            Color.clear.frame(height: 46)
        }
    }

    /// Insulin with two decimals and the locale's decimal separator, e.g. "0,25".
    private static func elaraBolusAmount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    // MARK: - Stats

    private var elaraTempBasalText: String {
        state.pumpSuspended ? NSLocalizedString("Pump suspended", comment: "") : tempBasalString
    }

    private var elaraEventualText: String {
        guard let eventualBG = state.eventualBG else { return "—" }
        return state.data.units == .mmolL
            ? Decimal(eventualBG).asMmolL.formatted(.number.precision(.fractionLength(1)))
            : "\(eventualBG)"
    }

    /// ISF and carb ratio of the last loop, as the algorithm reported them.
    private var elaraISFText: String {
        guard let reason = latestReason.first else { return "—" }
        var parts: [String] = []
        if let isf = reason.isf?.decimalValue, isf > 0 {
            parts.append(isf.formatted(.number.precision(.fractionLength(state.data.units == .mmolL ? 1 : 0))))
        }
        if let cr = reason.cr?.decimalValue, cr > 0 {
            parts.append("1:" + cr.formatted(.number.precision(.fractionLength(0 ... 1))))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private var elaraStatsRow: some View {
        HStack(spacing: 0) {
            elaraStat(label: NSLocalizedString("Temp basal", comment: "Elara"), value: elaraTempBasalText, first: true)
            elaraStat(label: NSLocalizedString("Eventual", comment: "Elara forecast"), value: elaraEventualText, first: false)
            elaraStat(label: NSLocalizedString("ISF · CR", comment: "Elara"), value: elaraISFText, first: false)
        }
        .padding(.horizontal, 4)
    }

    private func elaraStat(label: String, value: String, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(ElaraPalette.muted(colorScheme))
            Text(value)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ElaraPalette.text(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, first ? 2 : 10)
        .overlay(alignment: .leading) {
            if !first {
                Rectangle().fill(ElaraPalette.hairline(colorScheme)).frame(width: 1)
            }
        }
    }

    // MARK: - Strips

    private var elaraIOBText: String {
        guard let iob = state.data.iob else { return "?" }
        return iob.formatted(.number.precision(.fractionLength(0 ... 2)))
    }

    private var elaraCOBText: String {
        guard let cob = state.data.suggestion?.cob else { return "?" }
        return cob.formatted(.number.precision(.fractionLength(0)))
    }

    private var elaraInsulinStrip: some View {
        HStack(spacing: 0) {
            elaraCompactCell(
                prefix: NSLocalizedString("IOB", comment: ""),
                name: nil,
                value: elaraIOBText + " " + NSLocalizedString("U", comment: "Insulin unit"),
                dot: (state.data.iob ?? 0) < 0 ? ElaraPalette.red : ElaraPalette.insulin,
                divider: false
            )
            elaraCompactCell(
                prefix: NSLocalizedString("COB", comment: ""),
                name: nil,
                value: elaraCOBText + " g",
                dot: ElaraPalette.carbs,
                divider: true
            )
        }
        .frame(height: 38)
        .elaraCard(colorScheme)
        .contentShape(Rectangle())
        .onTapGesture { elaraOpenBolus() }
    }

    private static func elaraString(_ key: String, _ fallback: String) -> String {
        Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    }

    /// Short "1d 9h" / "9h 40m" forms; a zero day part is dropped.
    private static func elaraShortTime(_ interval: TimeInterval) -> String {
        let days = Int(interval / 86400)
        let hours = Int((interval - Double(days) * 86400) / 3600)
        if days > 0 { return String(format: elaraString("elara.dev.dh", "%dd %dh"), days, hours) }
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        return String(format: elaraString("elara.dev.hm", "%dh %dm"), hours, minutes)
    }

    /// Pod or patch time left in the short form ("1d 9h"); the 8 hour grace period after expiry
    /// ("Grace 5h"), minutes in the last hour and "Replace" once it has run out.
    private var elaraPumpSub: String? {
        if let pumpManager = state.deviceDataManager.pumpManager, !pumpManager.isOnboarded {
            return NSLocalizedString("Re-connect pump!", comment: "")
        }
        guard let date = state.pumpExpiresAtDate else { return nil }
        let interval = date.timeIntervalSince(state.data.timerDate)
        if interval <= 0 {
            let graceLeft = 8 * 3600 + interval
            guard graceLeft > 0 else { return Self.elaraString("elara.dev.replace", "Replace") }
            let short = graceLeft >= 3600
                ? String(Self.elaraShortTime(graceLeft).split(separator: " ").first ?? "")
                : "\(Int(graceLeft / 60)) min"
            return String(format: Self.elaraString("elara.dev.grace", "Grace %@"), short)
        }
        guard interval >= 3600 else { return "\(Int(interval / 60)) min" }
        let text = Self.elaraShortTime(interval)
        return interval >= 86400 ? text : String(text.split(separator: " ").first ?? Substring(text))
    }

    private var elaraReservoirText: String? {
        guard let reservoir = state.reservoir, reservoir != 0xDEAD_BEEF else { return nil }
        return reservoir.formatted(.number.precision(.fractionLength(0))) + " " +
            NSLocalizedString("U", comment: "Insulin unit")
    }

    private var elaraPumpWarning: Bool {
        if let date = state.pumpExpiresAtDate, date.timeIntervalSince(state.data.timerDate) < 8 * 3600 { return true }
        if let reservoir = state.reservoir, reservoir != 0xDEAD_BEEF, reservoir < 20 { return true }
        return false
    }

    /// The CGM's name as the device itself reports it (e.g. "Dexcom G7"); nil without a CGM.
    private var elaraCGMName: String? {
        guard let title = state.deviceDataManager.cgmManager?.localizedTitle, !title.isEmpty else { return nil }
        return title
    }

    /// Sensor time in the short form, with its state: the last day (orange), the G7 grace period
    /// after the nominal expiry ("Grace 9h 40m", red) and "Replace" once that has run out.
    private var elaraSensor: (text: String, color: Color?)? {
        guard let start = state.recentGlucose?.sessionStartDate else { return nil }
        let age = state.data.timerDate.timeIntervalSince(start)
        let left = state.sensorDays - age
        if left <= 0 { return (Self.elaraString("elara.dev.replace", "Replace"), ElaraPalette.red) }
        if let nominal = (state.deviceDataManager.cgmManager as? G7CGMManager)?.sensorExpiresAt, nominal <= Date() {
            return (String(format: Self.elaraString("elara.dev.grace", "Grace %@"), Self.elaraShortTime(left)), ElaraPalette.red)
        }
        if left < 86400 { return (Self.elaraShortTime(left), .orange) }
        return (Self.elaraShortTime(state.displayExpiration ? left : age), nil)
    }

    /// Pump and sensor with their real names: "PUMP: Omnipod DASH" over "1d 9h · 50 U", and
    /// "SENSOR: Dexcom G7" over "4d 7h". A tubed pump without an expiry shows its reservoir.
    private var elaraDeviceStrip: some View {
        HStack(spacing: 0) {
            Button {
                if state.pumpDisplayState != nil { state.setupPump = true }
            } label: {
                let hasPump = !state.pumpName.isEmpty
                let sub = elaraPumpSub
                elaraCompactCell(
                    prefix: Self.elaraString("elara.dev.pump", "Pump:"),
                    name: hasPump ? state.pumpName : Self.elaraString("elara.dev.nopump", "No pump"),
                    value: hasPump ? (sub ?? elaraReservoirText ?? "—") : "—",
                    detail: hasPump && sub != nil ? elaraReservoirText.map { "· \($0)" } : nil,
                    dot: elaraPumpWarning ? Color.orange : ElaraPalette.pump,
                    divider: false
                )
            }
            .buttonStyle(.plain)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                state.openCGM()
            } label: {
                let sensor = elaraSensor
                elaraCompactCell(
                    prefix: Self.elaraString("elara.dev.sensor", "Sensor:"),
                    name: elaraCGMName ?? Self.elaraString("elara.dev.nosensor", "No sensor"),
                    value: sensor?.text ?? "—",
                    valueColor: sensor?.color,
                    dot: sensor?.color ?? ElaraPalette.insulin,
                    divider: true
                )
            }
            .buttonStyle(.plain)
        }
        .frame(height: 38)
        .elaraCard(colorScheme, radius: 14)
    }

    /// A compact two-line cell for the 38 pt strips: a small dot, prefix and name above a bold value.
    private func elaraCompactCell(
        prefix: String,
        name: String?,
        value: String,
        detail: String? = nil,
        valueColor: Color? = nil,
        dot: Color,
        divider: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(prefix.uppercased())
                    .font(.system(size: 8.5, weight: .heavy))
                    .kerning(0.4)
                    .foregroundStyle(ElaraPalette.muted(colorScheme))
                if let name {
                    Text(name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ElaraPalette.muted(colorScheme))
                        .truncationMode(.tail)
                }
            }
            .lineLimit(1)
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(valueColor ?? ElaraPalette.text(colorScheme))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(ElaraPalette.muted(colorScheme))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, divider ? 12 : 14)
        .overlay(alignment: .leading) {
            if divider {
                Rectangle().fill(ElaraPalette.hairline(colorScheme)).frame(width: 1).padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Loop

    private var elaraLoopColor: Color {
        let suggestion = state.closedLoop && state.enactedSuggestion?.recieved == true
            ? (state.enactedSuggestion ?? state.data.suggestion) : state.data.suggestion
        guard suggestion?.timestamp != nil else { return ElaraPalette.device }
        guard !state.manualTempBasal else { return Color.loopManualTemp }
        let delta = state.data.timerDate.timeIntervalSince(state.lastLoopDate) - 30
        if delta <= 8 * 60 {
            return suggestion?.deliverAt != nil ? ElaraPalette.green : ElaraPalette.carbs
        }
        return delta <= 12 * 60 ? ElaraPalette.carbs : ElaraPalette.red
    }

    private var elaraLoopCaption: String {
        if state.isLooping { return NSLocalizedString("Looping", comment: "Elara loop status") }
        guard state.closedLoop else { return NSLocalizedString("Open", comment: "") }
        guard state.lastLoopDate != .distantPast else { return "Loop —" }
        let minutes = Int((state.data.timerDate.timeIntervalSince(state.lastLoopDate) - 30) / 60) + 1
        return minutes > 999 ? "Loop —" : "Loop · \(minutes) min"
    }

    var elaraOverrideActive: Bool { fetchedPercent.first?.enabled ?? false }

    /// The name of the active override: the preset, the percentage, or "Override".
    private var elaraOverrideText: String {
        guard let override = fetchedPercent.first, override.enabled else { return "" }
        if override.isPreset {
            if let name = fetchedProfiles.first(where: { $0.id == override.id })?.name,
               name != "EMPTY", !name.isEmpty, name != "\u{0022}\u{0022}"
            {
                return String(name.prefix(15))
            }
            return "📉"
        }
        if override.percentage != 100 {
            return override.percentage.formatted(.number.precision(.fractionLength(0))) + " %"
        }
        if override.smbIsOff { return NSLocalizedString("No ", comment: "No as in no SMBs") + "SMB" }
        return NSLocalizedString("Override", comment: "")
    }

    private var elaraLoopStrip: some View {
        HStack(spacing: 0) {
            elaraInlineItem(dot: elaraLoopColor, label: nil, value: elaraLoopCaption, detail: nil)
                .contentShape(Rectangle())
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showElaraStatus = true
                }
                .onLongPressGesture {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    state.runLoop()
                }
            if elaraOverrideActive || tempTargetString != nil {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if elaraOverrideActive { showCancelAlert = true } else { showCancelTTAlert = true }
                } label: {
                    // Override in LoopYellow, temporary target in green, on a see-through tint,
                    // with the time it still runs, refreshed every minute
                    let tint = elaraOverrideActive ? ElaraPalette.carbs : ElaraPalette.green
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        let remaining = elaraAdjustmentRemaining(now: timeline.date)
                        HStack(spacing: 7) {
                            // A ring that empties as the adjustment runs out; full when it runs until turned off
                            ZStack {
                                Circle().stroke(tint.opacity(0.3), lineWidth: 2)
                                Circle()
                                    .trim(from: 0, to: remaining?.fraction ?? 1)
                                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 11, height: 11)
                            Text(elaraOverrideActive ? elaraOverrideText : (tempTargetString ?? ""))
                                .fontWeight(.medium)
                                .foregroundStyle(ElaraPalette.text(colorScheme))
                            Spacer(minLength: 4)
                            if let remaining {
                                Text(remaining.text)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                    .foregroundStyle(ElaraPalette.readable(tint, colorScheme))
                            }
                        }
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .padding(.leading, -4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(tint.opacity(colorScheme == .dark ? 0.4 : 0.35), lineWidth: 1)
                            )
                    )
                    .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 36)
        .elaraCard(colorScheme, radius: 14)
    }

    /// Time the active override (or else temporary target) still runs, e.g. "1 u 20 min" or "35 min",
    /// with the part of its duration that is left; "∞" and a full ring when it runs until turned off,
    /// nil once it has ended.
    private func elaraAdjustmentRemaining(now: Date) -> (text: String, fraction: CGFloat)? {
        let start: Date?
        let minutes: Double
        if let override = fetchedPercent.first, override.enabled {
            if override.indefinite { return ("∞", 1) }
            start = override.date
            minutes = override.duration?.doubleValue ?? 0
        } else if let target = state.tempTarget {
            start = target.createdAt
            minutes = NSDecimalNumber(decimal: target.duration).doubleValue
        } else {
            return nil
        }
        guard minutes > 0 else { return ("∞", 1) }
        guard let start else { return nil }
        let remaining = start.addingTimeInterval(minutes * 60).timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = remaining >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .brief
        formatter.zeroFormattingBehavior = .dropAll
        // Round up, so the last minute reads "1 min" rather than nothing
        let text = formatter.string(from: (remaining / 60).rounded(.up) * 60) ?? ""
        return (text, CGFloat(min(1, max(0, remaining / (minutes * 60)))))
    }

    private func elaraInlineItem(dot: Color, label: String?, value: String, detail: String?) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 6, height: 6)
            if let label {
                Text(label).foregroundStyle(ElaraPalette.muted(colorScheme))
            }
            Text(value)
                .fontWeight(label == nil ? .medium : .semibold)
                .foregroundStyle(ElaraPalette.text(colorScheme))
            if let detail {
                Text(detail).foregroundStyle(ElaraPalette.muted(colorScheme))
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, 14)
    }

    // MARK: - Summaries

    /// The summaries of the iAPS home screen, on Elara cards below the first page.
    private var elaraSummaries: some View {
        VStack(spacing: 15) {
            if !state.data.glucose.isEmpty {
                preview
            }
            loopPreview
            if state.carbData > 0 {
                activeCOBView
            }
            if !state.iobData.isEmpty {
                activeIOBView
            }
            insulinView
            mealsView
        }
        .padding(.horizontal, -10)
        .padding(.top, 8)
    }

    // MARK: - Navigation bar

    private func elaraOpenBolus() {
        if state.bolusProgress != nil {
            showBolusActiveAlert = true
        } else {
            state.showModal(for: .bolus(waitForSuggestion: state.useCalc, fetch: false))
        }
    }

    /// The buttons of the iAPS button panel, in Elara's bar.
    private var elaraNavBar: some View {
        let isTarget = state.tempTarget != nil
        return HStack(spacing: 0) {
            elaraNavButton(
                "clock.arrow.trianglehead.counterclockwise.rotate.90",
                a11y: NSLocalizedString("History", comment: "")
            ) {
                state.showModal(for: .dataTable)
            }
            elaraNavButton("chart.pie.fill", a11y: NSLocalizedString("Statistics", comment: "")) {
                state.showModal(for: .statistics)
            }
            if state.carbButton {
                elaraNavButton("leaf.fill", a11y: NSLocalizedString("Add Meal", comment: ""), badge: state.carbsRequired) {
                    state.showModal(for: .addCarbs(editMode: false, override: false, mode: .meal))
                }
                .contextMenu {
                    Button {
                        state.showModal(for: .addCarbs(editMode: false, override: false, mode: .presets)) }
                    label: { Label("Meal Presets", systemImage: "menucard") }
                    Button {
                        state.showModal(for: .addCarbs(editMode: false, override: false, mode: .barcode)) }
                    label: { Label("Barcode", systemImage: "barcode.viewfinder") }
                    if state.ai {
                        Button {
                            state.showModal(for: .addCarbs(editMode: false, override: false, mode: .image)) }
                        label: { Label("AI Image Analysis", systemImage: "photo.badge.magnifyingglass") }
                        Button {
                            state.showModal(for: .addCarbs(editMode: false, override: false, mode: .voice)) }
                        label: { Label("Voice Input", systemImage: "mic.fill") }
                    }
                    Button {
                        state.showModal(for: .addCarbs(editMode: false, override: false, mode: .meal)) }
                    label: { Label("Add Meal", systemImage: "birthday.cake") }
                }
            }
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                elaraOpenBolus()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .frame(width: 50, height: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ElaraPalette.green))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text("Bolus"))
            if state.allowManualTemp {
                elaraNavButton("gauge.with.needle", a11y: NSLocalizedString("Manual Temp Basal", comment: "")) {
                    state.showModal(for: .manualTempBasal)
                }
            }
            if state.profileButton {
                elaraNavIcon(
                    "slider.horizontal.3",
                    active: elaraOverrideActive ? ElaraPalette.pump : nil
                )
                .onTapGesture {
                    if elaraOverrideActive { showCancelAlert.toggle() } else { state.showModal(for: .overrideProfilesConfig) }
                }
                .onLongPressGesture { state.showModal(for: .overrideProfilesConfig) }
                .accessibilityLabel(Text(NSLocalizedString("Profile Override", comment: "")))
                .accessibilityAddTraits(.isButton)
            }
            if state.useTargetButton {
                elaraNavIcon("target", active: isTarget ? ElaraPalette.green : nil)
                    .onTapGesture {
                        if isTarget { showCancelTTAlert.toggle() } else { state.showModal(for: .addTempTarget) }
                    }
                    .onLongPressGesture { state.showModal(for: .addTempTarget) }
                    .accessibilityLabel(Text(NSLocalizedString("Temporary Target", comment: "")))
                    .accessibilityAddTraits(.isButton)
            }
            elaraNavButton("gearshape", a11y: NSLocalizedString("Settings", comment: "")) {
                state.showModal(for: .settings)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 64)
        // The summaries scroll underneath, so the bar is frosted
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .elaraCard(colorScheme)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .confirmationDialog("Cancel Profile Override", isPresented: $showCancelAlert) {
            Button("Cancel Profile Override", role: .destructive) {
                state.cancelProfile()
                triggerUpdate.toggle()
            }
        }
        .confirmationDialog("Cancel Temporary Target", isPresented: $showCancelTTAlert) {
            Button("Cancel Temporary Target", role: .destructive) {
                state.cancelTempTarget()
            }
        }
        .confirmationDialog("Bolus already in Progress", isPresented: $showBolusActiveAlert) {
            Button("Bolus already in Progress!", role: .destructive) {
                showBolusActiveAlert = false
            }
        }
    }

    private func elaraNavButton(
        _ symbol: String,
        a11y: String,
        active: Color? = nil,
        badge: Decimal? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            elaraNavIcon(symbol, active: active, badge: badge)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(a11y))
    }

    /// An icon of the bar; a tinted square behind it while its override or target is active.
    /// The carbs the loop asks for show as a red badge, as on the iAPS meal button.
    private func elaraNavIcon(_ symbol: String, active: Color? = nil, badge: Decimal? = nil) -> some View {
        // Trio's history symbol needs iOS 18; iOS 17 shows the older clock symbol
        Image(systemName: UIImage(systemName: symbol) == nil ? "clock.arrow.circlepath" : symbol)
            .font(.system(size: 19, weight: .regular))
            .foregroundStyle(active ?? ElaraPalette.text(colorScheme).opacity(0.85))
            .frame(width: 40, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(active.map { $0.opacity(0.16) } ?? .clear)
            )
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge.formatted(.number.precision(.fractionLength(0))))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(ElaraPalette.red))
                        .offset(x: 4, y: -2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// A capsule whose outline starts at the middle of the left end and runs clockwise, so a trimmed
/// stroke grows over the top, around the right end and back along the bottom.
private struct ElaraBolusCapsule: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.height / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.midY),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.midY),
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.midY),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        return path
    }
}
