import ActivityKit
import SwiftUI
import WidgetKit

/// Lock screen Live Activity in the Elara style: the bold glucose value with trend and delta,
/// the last two hours as bars, and a strip with IOB, carbs and the loop.
struct ElaraLiveActivityView: View {
    @Environment(\.colorScheme) private var scheme

    var context: ActivityViewContext<LiveActivityAttributes>
    /// In the expanded Dynamic Island the island itself is the background.
    var inIsland: Bool = false
    /// The small activity family on the Apple Watch Smart Stack: value, trend and bars only.
    var compact: Bool = false
    /// The chart is off in the Live Activity settings: value, trend, delta and time, no bars or strip.
    var simple: Bool = false
    /// CarPlay's card is less tall than the lock screen: tighter spacing and narrower bars, so the
    /// strip stays above the bottom edge and the delta keeps its room.
    var carPlay: Bool = false

    private var state: LiveActivityAttributes.ContentState { context.state }

    static let green = Color(.displayP3, red: 0.401, green: 0.757, blue: 0.242)
    static let red = Color(.displayP3, red: 0.894, green: 0.208, blue: 0.310)
    static let high = Color(.displayP3, red: 151 / 255, green: 90 / 255, blue: 232 / 255)
    static let yellow = Color(red: 1, green: 0.757, blue: 0.271)
    private static let insulin = Color(red: 45 / 255, green: 138 / 255, blue: 247 / 255)
    private static let carbs = Color(red: 255 / 255, green: 193 / 255, blue: 69 / 255)
    static let muted = Color(red: 143 / 255, green: 148 / 255, blue: 156 / 255)

    private var textColor: Color { scheme == .dark || inIsland ? .white : Color(red: 22 / 255, green: 24 / 255, blue: 29 / 255) }
    private var hairline: Color { textColor.opacity(0.12) }

    static func status(_ mgdl: Int, low: Int16, high: Int16) -> Color {
        if mgdl < Int(low) { return red }
        if mgdl > Int(high) { return Self.high }
        return green
    }

    /// Status color of the current reading, gray once the activity is stale.
    static func statusColor(_ context: ActivityViewContext<LiveActivityAttributes>) -> Color {
        let state = context.state
        guard !context.isStale, let mgdl = currentMgdl(state) else { return muted }
        return status(mgdl, low: state.chartLowThreshold, high: state.chartHighThreshold)
    }

    /// The current reading in mg/dL: the newest of the readings, or the formatted value.
    private static func currentMgdl(_ state: LiveActivityAttributes.ContentState) -> Int? {
        if let readings = state.readings,
           let index = readings.dates.indices.max(by: { readings.dates[$0] < readings.dates[$1] })
        {
            return Int(readings.values[index])
        }
        let text = state.bg.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text) else { return nil }
        return state.mmol ? Int((value / 0.0555).rounded()) : Int(value)
    }

    /// The trend arrow as an angle; iAPS sends it as an arrow symbol.
    static func rotation(_ direction: String?) -> Double? {
        switch direction?.unicodeScalars.first {
        case "↑": return -90
        case "↗": return -45
        case "→": return 0
        case "↘": return 45
        case "↓": return 90
        default: return nil
        }
    }

    /// The loop's color, as the iAPS loop circle: green, yellow after 8 minutes, red after 12.
    static func loopColor(_ context: ActivityViewContext<LiveActivityAttributes>) -> Color {
        let minutes = abs(context.state.loopDate.timeIntervalSinceNow) / 60
        return minutes > 12 ? red : minutes > 8 ? yellow : green
    }

    private var statusColor: Color { Self.statusColor(context) }

    private var unit: String { state.mmol ? "mmol/L" : "mg/dL" }

    /// Whole part and decimal of the formatted value; mg/dL has no decimal.
    private var valueParts: (whole: String, decimal: String?) {
        let parts = state.bg.split(whereSeparator: { $0 == "," || $0 == "." })
        return (String(parts.first ?? "--"), parts.count > 1 ? String(parts[1]) : nil)
    }

    var body: some View {
        if compact {
            if simple { compactSimpleBody } else { compactBody }
        } else if simple, !inIsland {
            simpleBody
        } else {
            fullBody
        }
    }

    private var loopStatus: some View {
        HStack(spacing: 5) {
            Circle().fill(Self.loopColor(context)).frame(width: 6, height: 6)
            Text("Loop")
            Text(state.loopDate, style: .relative)
        }
        .foregroundStyle(Self.muted)
    }

    private var activityBackground: Color {
        scheme == .dark
            ? Color(red: 20 / 255, green: 25 / 255, blue: 35 / 255).opacity(0.78)
            : Color.white.opacity(0.78)
    }

    private var simpleBody: some View {
        HStack(alignment: .center, spacing: 12) {
            value(scale: 1)
            delta
            Spacer(minLength: 4)
            loopStatus
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(textColor)
        .privacySensitive()
        .activityBackgroundTint(activityBackground)
    }

    private var compactSimpleBody: some View {
        HStack(alignment: .center, spacing: 10) {
            value(scale: 0.85)
            delta
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .privacySensitive()
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                value(scale: 0.7)
                delta
                Spacer(minLength: 0)
            }
            bars.frame(maxWidth: .infinity).frame(height: 30)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .privacySensitive()
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: carPlay ? 6 : 10) {
            HStack(alignment: .center, spacing: carPlay ? 10 : 12) {
                value(scale: carPlay ? 0.9 : 1)
                delta
                    .layoutPriority(1)
                Spacer(minLength: 4)
                bars.frame(width: carPlay ? 96 : 140, height: carPlay ? 36 : 44)
            }
            Rectangle().fill(hairline).frame(height: 1)
            strip
        }
        .padding(.horizontal, inIsland ? 6 : 16)
        .padding(.top, inIsland ? 0 : carPlay ? 8 : 14)
        .padding(.bottom, inIsland ? 4 : carPlay ? 10 : 12)
        .foregroundStyle(textColor)
        .privacySensitive()
        .activityBackgroundTint(inIsland ? nil : activityBackground)
    }

    private func value(scale: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(valueParts.whole)
                .font(.system(size: 52 * scale, weight: .black))
            if let decimal = valueParts.decimal {
                Text(Locale.current.decimalSeparator ?? ",")
                    .font(.system(size: 20 * scale, weight: .black))
                    .padding(.horizontal, 1)
                Text(decimal)
                    .font(.system(size: 26 * scale, weight: .black))
                    .baselineOffset(18 * scale)
            }
        }
        .tracking(-1.5)
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(
            LinearGradient(
                colors: [statusColor.opacity(0.6), statusColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var delta: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if !context.isStale, let rotation = Self.rotation(state.direction) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.black)
                        .rotationEffect(.degrees(rotation))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(statusColor))
                }
                Text(context.isStale ? "--" : state.change.trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 15, weight: .bold))
                    // Only the delta is fixed: a relative date text reports a huge ideal width
                    .fixedSize()
            }
            HStack(spacing: 0) {
                Text(unit)
                Text(" · ")
                Text(state.date, style: .relative)
            }
            .font(.system(size: 11))
            .foregroundStyle(Self.muted)
            .lineLimit(1)
        }
    }

    private var bars: some View {
        let start = Date().addingTimeInterval(-2 * 3600)
        let readings = state.readings.map { series in
            zip(series.dates, series.values)
                .filter { $0.0 >= start }
                .sorted { $0.0 < $1.0 }
        } ?? []
        return Canvas { context, size in
            let slots = 24
            let gap: CGFloat = 2
            let width = max(2, (size.width - gap * CGFloat(slots - 1)) / CGFloat(slots))
            let values = readings.map { Double($0.1) }
            let top = max(220, values.max() ?? 220)
            let end = Date()
            for (reading, value) in zip(readings, values) {
                let slot = slots - 1 - Int(end.timeIntervalSince(reading.0) / 300)
                guard slot >= 0 else { continue }
                let fraction = max(0.08, min(1, (value - 40) / (top - 40)))
                let height = size.height * CGFloat(fraction)
                let rect = CGRect(x: CGFloat(slot) * (width + gap), y: size.height - height, width: width, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: width / 2),
                    with: .color(
                        self.context.isStale ? Self.muted.opacity(0.5) :
                            Self.status(Int(reading.1), low: state.chartLowThreshold, high: state.chartHighThreshold)
                    )
                )
            }
        }
    }

    private var strip: some View {
        HStack(spacing: 0) {
            stripItem(Self.insulin, Text(state.iob + " " + NSLocalizedString("U", comment: "Insulin unit")))
            divider
            stripItem(Self.carbs, Text(state.cob + " g"))
            Spacer(minLength: 8)
            loopStatus
        }
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
    }

    private var divider: some View {
        Rectangle().fill(hairline).frame(width: 1, height: 14).padding(.horizontal, 12)
    }

    private func stripItem(_ color: Color, _ text: Text) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            text
        }
    }
}

/// The lock screen, the Apple Watch Smart Stack and CarPlay. CarPlay (iOS 26 and later) and the
/// Smart Stack both use the small activity family and can't be told apart; CarPlay's card is much
/// wider than any watch, so above this width the lock screen layout is used.
@available(iOS 18.0, *) struct ElaraActivityBanner: View {
    @Environment(\.activityFamily) private var activityFamily
    let context: ActivityViewContext<LiveActivityAttributes>

    private static let carPlayMinimumWidth: CGFloat = 240
    /// The lock screen layout is too large for CarPlay's card, so there it's laid out in a larger
    /// frame and scaled down.
    private static let carPlayScale: CGFloat = 0.8

    var body: some View {
        if activityFamily == .small {
            let simple = !(context.state.showChart && context.state.watchChart)
            GeometryReader { geometry in
                Group {
                    if geometry.size.width >= Self.carPlayMinimumWidth {
                        ElaraLiveActivityView(context: context, simple: simple, carPlay: true)
                            .frame(
                                width: geometry.size.width / Self.carPlayScale,
                                height: geometry.size.height / Self.carPlayScale
                            )
                            .scaleEffect(Self.carPlayScale)
                    } else {
                        ElaraLiveActivityView(context: context, compact: true, simple: simple)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        } else {
            ElaraLiveActivityView(context: context, simple: !context.state.showChart)
        }
    }
}

// MARK: - Dynamic Island

/// Compact leading: the value in its status color.
struct ElaraIslandCompactLeading: View {
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        Text(context.state.bg)
            .font(.system(size: 15, weight: .black))
            .foregroundStyle(ElaraLiveActivityView.statusColor(context))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.leading, 4)
    }
}

/// Compact trailing: the trend arrow in a status-colored circle and the delta.
struct ElaraIslandCompactTrailing: View {
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        HStack(spacing: 4) {
            if !context.isStale, let rotation = ElaraLiveActivityView.rotation(context.state.direction) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.black)
                    .rotationEffect(.degrees(rotation))
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(ElaraLiveActivityView.statusColor(context)))
            }
            Text(context.isStale ? "--" : context.state.change.trimmingCharacters(in: .whitespaces))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.trailing, 4)
    }
}

/// Minimal: just the value, as large as the round island allows.
struct ElaraIslandMinimal: View {
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        Text(context.state.bg)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(ElaraLiveActivityView.statusColor(context))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, 3)
    }
}
