import SwiftUI

/// Watch version of the iPhone Elara skin: black with a night-blue top, a bold glucose value,
/// glucose as 5-minute bars and one strip for IOB and carbs.
enum ElaraWatchPalette {
    static let green = Color(.displayP3, red: 0.401, green: 0.757, blue: 0.242)
    static let red = Color(.displayP3, red: 0.894, green: 0.208, blue: 0.310)
    static let high = Color(.displayP3, red: 151 / 255, green: 90 / 255, blue: 232 / 255)
    static let insulin = Color(.displayP3, red: 0.175, green: 0.542, blue: 0.970)
    static let carbs = Color(red: 1, green: 0.757, blue: 0.271)
    static let override = Color(red: 0.443, green: 0.380, blue: 0.937)

    static let muted = Color(red: 143 / 255, green: 148 / 255, blue: 156 / 255)
    static let card = Color.white.opacity(0.08)
    static let hairline = Color.white.opacity(0.12)

    static let background = LinearGradient(
        stops: [
            .init(color: Color(red: 16 / 255, green: 32 / 255, blue: 68 / 255), location: 0),
            .init(color: Color(red: 18 / 255, green: 36 / 255, blue: 74 / 255).opacity(0.6), location: 0.3),
            .init(color: .black, location: 0.6)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The watch has no glucose range of its own: 70 and 180 mg/dL.
    static func status(forMgdl mgdl: Double) -> Color {
        if mgdl < 70 { return red }
        if mgdl > 180 { return high }
        return green
    }
}

/// Elara main screen: loop status, the glucose value with trend and delta, the last two hours as
/// bars, and IOB, carbs and the chosen extra value of the watch settings.
struct ElaraWatchHeroView: View {
    @EnvironmentObject var state: WatchStateModel
    /// The value chosen in the watch settings (heart rate, eventual glucose, steps, ISF or
    /// override), as the iAPS watch face shows it.
    let extra: String?
    let loopColor: Color
    let loopText: String

    /// No reading for 15 minutes.
    private var isStale: Bool {
        guard let date = state.glucoseDate else { return true }
        return state.timerDate.timeIntervalSince(date) > 15 * 60
    }

    /// The current value in mg/dL: the newest reading, or the shown value.
    private var currentMgdl: Double? {
        if let newest = state.elaraReadings.max(by: { $0.date < $1.date }) { return Double(newest.glucose) }
        let text = state.glucose.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text) else { return nil }
        return text.contains(".") || value < 30 ? value / 0.0555 : value
    }

    private var statusColor: Color {
        guard !isStale, let mgdl = currentMgdl else { return Color.gray.opacity(0.55) }
        return ElaraWatchPalette.status(forMgdl: mgdl)
    }

    /// Whole part and decimal of the current value; mg/dL has no decimal.
    private var valueParts: (whole: String, decimal: String?) {
        let parts = state.glucose.split(whereSeparator: { $0 == "," || $0 == "." })
        return (String(parts.first ?? "--"), parts.count > 1 ? String(parts[1]) : nil)
    }

    /// iAPS sends the trend as arrow symbols.
    private var trendAngle: Double? {
        switch state.trend.unicodeScalars.first {
        case "↑": return -90
        case "↗": return -45
        case "→": return 0
        case "↘": return 45
        case "↓": return 90
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            loopRow
            valueRow
            bars
            strip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var loopRow: some View {
        HStack(spacing: 5) {
            Circle().fill(loopColor).frame(width: 6, height: 6)
            Text(loopText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var valueRow: some View {
        HStack(alignment: .center) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(valueParts.whole)
                    .font(.system(size: 54, weight: .black))
                if let decimal = valueParts.decimal {
                    Text(Locale.current.decimalSeparator ?? ",")
                        .font(.system(size: 22, weight: .black))
                    Text(decimal)
                        .font(.system(size: 28, weight: .black))
                        .baselineOffset(16)
                }
            }
            .tracking(-2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(
                LinearGradient(
                    colors: [statusColor.opacity(0.55), statusColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: statusColor.opacity(0.4), radius: 8)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                if !isStale, let angle = trendAngle {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.black)
                        .rotationEffect(.degrees(angle))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(statusColor))
                }
                Text(isStale ? "--" : state.delta)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var bars: some View {
        Canvas { context, size in
            let start = Date().addingTimeInterval(-2 * 3600)
            let readings = state.elaraReadings.filter { $0.date >= start }
            guard !readings.isEmpty else { return }
            let slots = 24
            let gap: CGFloat = 3
            let width = max(2, (size.width - gap * CGFloat(slots - 1)) / CGFloat(slots))
            let top = max(220, readings.map { Double($0.glucose) }.max() ?? 220)
            let floor = 40.0
            let end = Date()
            for reading in readings {
                let slot = slots - 1 - Int(end.timeIntervalSince(reading.date) / 300)
                guard slot >= 0 else { continue }
                let mgdl = Double(reading.glucose)
                let fraction = max(0.08, min(1, (mgdl - floor) / (top - floor)))
                let height = size.height * CGFloat(fraction)
                let rect = CGRect(x: CGFloat(slot) * (width + gap), y: size.height - height, width: width, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: width / 2),
                    with: .color(isStale ? Color.gray.opacity(0.4) : ElaraWatchPalette.status(forMgdl: mgdl))
                )
            }
        }
        .frame(minHeight: 16, maxHeight: 40)
        .accessibilityHidden(true)
    }

    private var strip: some View {
        HStack(spacing: 0) {
            stripItem(color: ElaraWatchPalette.insulin, text: Self.number(state.iob) + " " + NSLocalizedString("U", comment: ""))
            Rectangle().fill(ElaraWatchPalette.hairline).frame(width: 1, height: 16)
            stripItem(color: ElaraWatchPalette.carbs, text: Self.number(state.cob) + " g")
            if let extra {
                Rectangle().fill(ElaraWatchPalette.hairline).frame(width: 1, height: 16)
                stripItem(color: ElaraWatchPalette.muted, text: extra)
            }
        }
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ElaraWatchPalette.card))
    }

    private static func number(_ value: Decimal?) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.precision(.fractionLength(0 ... 2)))
    }

    private func stripItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(isStale ? "--" : text)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Round action button of the Elara watch skin: a small circle just around the symbol, with a
/// larger tap area around it.
struct ElaraWatchButtonLabel<Label: View>: View {
    let fill: Color
    @ViewBuilder let label: Label

    var body: some View {
        label
            .frame(width: 30, height: 30)
            .background(Circle().fill(fill))
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Elara background behind a whole screen while the Elara skin is chosen.
    func elaraWatchScreen(_ active: Bool) -> some View {
        background { if active { ElaraWatchPalette.background.ignoresSafeArea() } }
            .tint(active ? ElaraWatchPalette.green : nil)
    }
}
