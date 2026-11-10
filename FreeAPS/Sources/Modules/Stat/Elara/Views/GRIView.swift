import SwiftUI

struct GRIChartView: View {
    let result: GRICalculator.Result?
    var units: GlucoseUnits = .mgdL

    var body: some View {
        VStack(spacing: 16) {
            GRIView(result: result, units: units)
            if let result {
                GRIGaugeView(result: result)
            } else {
                ContentUnavailableView("No Glucose Data", systemImage: "chart.bar.fill")
            }
        }
    }
}

struct GRIView: View {
    let result: GRICalculator.Result?
    var units: GlucoseUnits = .mgdL
    @State private var showingDetails = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            showingDetails = true
        } label: {
            HStack {
                Text("GRI")
                    .font(.subheadline.weight(.semibold))
                if let result {
                    Text(result.score, format: .number.precision(.fractionLength(1)))
                        .font(.headline)
                    Text("/ 100")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Zone \(result.zone)")
                        .foregroundStyle(GRIPalette.color(for: result, scheme: colorScheme))
                } else {
                    Text("—")
                    Spacer()
                }
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows Glycemia Risk Index details")
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let result {
                            HStack {
                                Text(result.score, format: .number.precision(.fractionLength(1)))
                                    .font(.largeTitle.bold())
                                Text("/ 100")
                                Spacer()
                                Text("Zone \(result.zone)")
                                    .foregroundStyle(GRIPalette.color(for: result, scheme: colorScheme))
                            }
                            GRIGaugeView(result: result)
                        } else {
                            ContentUnavailableView("No Glucose Data", systemImage: "chart.bar.fill")
                        }
                        GRIExplanationView(result: result, units: units)
                    }
                    .padding()
                }
                .background(Color(uiColor: .systemBackground))
                .navigationTitle("Glycemia Risk Index")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(elaraStatString("Done")) { showingDetails = false }
                    }
                }
            }
            .preferredColorScheme(colorScheme)
            .presentationBackground(Color(uiColor: .systemBackground))
        }
    }
}

struct GRIExplanationView: View {
    let result: GRICalculator.Result?
    var units: GlucoseUnits = .mgdL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                "Glycemia Risk Index combines low and high glucose exposure into a score from 0 to 100. Lower scores indicate less glycemic risk."
            )
            Text(
                "Calculated from glucose readings in the selected period. Short periods and gaps in sensor data can make the score less representative."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let result {
                LabeledContent("Hypoglycemia component", value: component(result.hypoComponent))
                    .foregroundStyle(GRICalculationColors.hypo)
                LabeledContent("Hyperglycemia component", value: component(result.hyperComponent))
                    .foregroundStyle(GRICalculationColors.hyper)
            }
            Divider()
            if let result {
                DisclosureGroup("Score calculation") {
                    GRIScoreBreakdownView(result: result, units: units)
                        .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func component(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }
}

private enum GRICalculationColors {
    static let veryLow: Color = ElaraPalette.red
    static let low = veryLow.opacity(0.65)
    static let high = veryHigh.opacity(0.65)
    static let veryHigh: Color = ElaraPalette.high
    static let hypo = veryLow
    static let hyper = veryHigh
}

private struct GRIScoreBreakdownView: View {
    let result: GRICalculator.Result
    let units: GlucoseUnits

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GRI uses fixed glucose thresholds, regardless of your target range.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LabeledContent(String(localized: "Below \(threshold(54))", comment: "GRI band: very low glucose")) {
                Text(patientValue(percentage(result.veryLowPercentage), color: GRICalculationColors.veryLow))
            }
            LabeledContent(String(
                localized: "\(threshold(54)) to below \(threshold(70))",
                comment: "GRI band: low glucose"
            )) {
                Text(patientValue(percentage(result.lowPercentage), color: GRICalculationColors.low))
            }
            LabeledContent(String(
                localized: "Above \(threshold(180)) through \(threshold(250))",
                comment: "GRI band: high glucose"
            )) {
                Text(patientValue(percentage(result.highPercentage), color: GRICalculationColors.high))
            }
            LabeledContent(String(localized: "Above \(threshold(250))", comment: "GRI band: very high glucose")) {
                Text(patientValue(percentage(result.veryHighPercentage), color: GRICalculationColors.veryHigh))
            }

            Divider()
            calculation(
                "Hypoglycemia component",
                color: GRICalculationColors.hypo,
                formula: patientValue(number(result.veryLowPercentage), color: GRICalculationColors.veryLow) +
                    AttributedString(" + \(number(0.8)) × ") +
                    patientValue(number(result.lowPercentage), color: GRICalculationColors.low) + AttributedString(" = ") +
                    patientValue(number(result.hypoComponent), color: GRICalculationColors.hypo)
            )
            calculation(
                "Hyperglycemia component",
                color: GRICalculationColors.hyper,
                formula: patientValue(number(result.veryHighPercentage), color: GRICalculationColors.veryHigh) +
                    AttributedString(" + \(number(0.5)) × ") +
                    patientValue(number(result.highPercentage), color: GRICalculationColors.high) + AttributedString(" = ") +
                    patientValue(number(result.hyperComponent), color: GRICalculationColors.hyper)
            )
            calculation(
                "Weighted hypoglycemia",
                color: GRICalculationColors.hypo,
                formula: AttributedString("3 × ") + patientValue(number(result.hypoComponent), color: GRICalculationColors.hypo) +
                    AttributedString(" = ") +
                    patientValue(number(result.weightedHypoComponent), color: GRICalculationColors.hypo)
            )
            calculation(
                "Weighted hyperglycemia",
                color: GRICalculationColors.hyper,
                formula: AttributedString("\(number(1.6)) × ") +
                    patientValue(number(result.hyperComponent), color: GRICalculationColors.hyper) +
                    AttributedString(" = ") +
                    patientValue(number(result.weightedHyperComponent), color: GRICalculationColors.hyper)
            )
            calculation(
                "Combined score",
                formula: patientValue(number(result.weightedHypoComponent), color: GRICalculationColors.hypo) +
                    AttributedString(" + ") +
                    patientValue(number(result.weightedHyperComponent), color: GRICalculationColors.hyper) +
                    AttributedString(" = ") +
                    patientValue(number(result.uncappedScore), color: .primary)
            )
            Text("The final GRI score is capped at 100. Calculations use unrounded values.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            LabeledContent("GRI") {
                Text(patientValue(number(result.score), color: .primary))
            }
            .font(.headline)
        }
    }

    private func calculation(_ title: LocalizedStringKey, color: Color = .primary, formula: AttributedString) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Text(formula).monospacedDigit()
        }
    }

    private func patientValue(_ value: String, color: Color) -> AttributedString {
        var text = AttributedString(value)
        text.foregroundColor = color
        text.font = .body.weight(.semibold)
        return text
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    /// A fixed GRI threshold (defined in mg/dL) in the user's glucose units, with unit.
    private func threshold(_ mgdL: Decimal) -> String {
        mgdL.formatted(withUnits: units)
    }

    private func percentage(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(1)))
    }
}

/// GRI zone colors from the Aurelia palette, from the most favourable zone A (LoopGreen)
/// through Insulin, LoopYellow and loopHigh to the worst zone E (LoopRed).
private enum GRIPalette {
    static func color(for result: GRICalculator.Result, scheme: ColorScheme) -> Color {
        let index = ["A", "B", "C", "D", "E"].firstIndex(of: result.zone) ?? 0
        return color(zoneIndex: index, scheme: scheme)
    }

    /// - Parameter zoneIndex: 0 for zone A through 4 for zone E.
    static func color(zoneIndex: Int, scheme _: ColorScheme) -> Color {
        switch zoneIndex {
        case ...0: return ElaraPalette.green
        case 1: return Color("Insulin")
        case 2: return Color("LoopYellow")
        case 3: return ElaraPalette.high
        default: return ElaraPalette.red
        }
    }
}

/// Half-circle GRI meter in the style of the Aurelia home ring: zones A–E run from left to
/// right with rounded ends, and an arrow points at the score.
private struct GRIGaugeView: View {
    let result: GRICalculator.Result
    @Environment(\.colorScheme) private var colorScheme

    private let zones: [(score: Double, letter: String, title: LocalizedStringKey)] = [
        (20, "A", "Zone A (0-20)"),
        (40, "B", "Zone B (>20-40)"),
        (60, "C", "Zone C (>40-60)"),
        (80, "D", "Zone D (>60-80)"),
        (100, "E", "Zone E (>80-100)")
    ]

    /// Zones meet edge to edge; the gaps between them are cut out separately.
    private let blendWidth = 0.0

    private var zoneIndex: Int {
        ["A", "B", "C", "D", "E"].firstIndex(of: result.zone) ?? 0
    }

    private var zoneColor: Color {
        GRIPalette.color(zoneIndex: zoneIndex, scheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 16) {
            Canvas { context, size in
                if ElaraTheme.shared.isActive {
                    drawElara(in: &context, size: size)
                } else {
                    draw(in: &context, size: size)
                }
            }
            .aspectRatio(1.45, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("GRI risk grid, zone \(result.zone)")
            .accessibilityValue(
                "Hypoglycemia \(result.hypoComponent.formatted()) percent, hyperglycemia \(result.hyperComponent.formatted()) percent"
            )

            components
            legend
        }
    }

    // MARK: - Meter

    /// SwiftUI angle (0° = right, clockwise) for a score, from 0 on the left up over the top to 100 on
    /// the right. `cap` is the angle the band's rounded ends reach past the horizontal; including it
    /// spreads the scale over the whole visible band, so zones A and E are as long as B, C and D.
    private func angle(_ score: Double, cap: Double) -> Angle {
        .degrees(180 - cap + (180 + 2 * cap) * min(max(score, 0), 100) / 100)
    }

    private func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Angle) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle.radians), y: center.y + radius * sin(angle.radians))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let stroke = max(14, size.width * 0.07)
        let radius = min(size.width / 2 - stroke / 2 - 6, size.height - 64 - stroke / 2)
        let center = CGPoint(x: size.width / 2, y: radius + stroke / 2 + 6)
        let cap = Double(stroke / 2 / radius) * 180 / .pi
        func angle(_ score: Double) -> Angle { self.angle(score, cap: cap) }

        // Zone colors as one sweep; the conic gradient starts at 170° so the rounded ends
        // (which reach a little below the horizontal) keep the colors of zone A and E.
        let gradientStart = 170.0
        func location(_ score: Double) -> Double { (angle(score).degrees - gradientStart) / 360 }
        var stops: [Gradient.Stop] = []
        var lower = 0.0
        for (index, zone) in zones.enumerated() {
            let color = GRIPalette.color(zoneIndex: index, scheme: colorScheme)
            let from = index == 0 ? -6 : lower + blendWidth / 2
            let to = index == zones.count - 1 ? 106 : zone.score - blendWidth / 2
            stops.append(.init(color: color, location: max(0, location(from))))
            stops.append(.init(color: color, location: location(to)))
            lower = zone.score
        }

        var arc = Path()
        arc.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        context.drawLayer { layer in
            layer.stroke(
                arc,
                with: .conicGradient(Gradient(stops: stops), center: center, angle: .degrees(gradientStart)),
                style: StrokeStyle(lineWidth: stroke, lineCap: .round)
            )
            // Thin gaps between the zones that let the card background show through.
            layer.blendMode = .destinationOut
            for zone in zones.dropLast() {
                var gap = Path()
                gap.move(to: point(center, radius - stroke / 2 - 1, angle(zone.score)))
                gap.addLine(to: point(center, radius + stroke / 2 + 1, angle(zone.score)))
                layer.stroke(gap, with: .color(.black), lineWidth: 2)
            }
        }

        // Zone letters on the band.
        for zone in zones {
            context.draw(
                Text(zone.letter).font(.system(size: stroke * 0.55, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white),
                at: point(center, radius, angle(zone.score - 10))
            )
        }

        // Scale ends.
        let endFont = Font.system(size: 11, weight: .medium)
        context.draw(
            Text("0").font(endFont).foregroundStyle(.secondary),
            at: CGPoint(x: center.x - radius, y: center.y + stroke / 2 + 12)
        )
        context.draw(
            Text("100").font(endFont).foregroundStyle(.secondary),
            at: CGPoint(x: center.x + radius, y: center.y + stroke / 2 + 12)
        )

        // Arrow from the hub to the score. The hub sits a little above the arc's center and the
        // arrow stops short of the band, so it reads as a pointer inside the half circle.
        let innerRadius = radius - stroke / 2
        let pivot = CGPoint(x: center.x, y: center.y - innerRadius * 0.24)
        let needleLength = innerRadius * 0.66
        // Aim at the score's spot on the band, not along the score's angle: the pivot is off the
        // arc's center, so the same angle would land in a neighbouring zone.
        let target = point(center, radius, angle(result.score))
        let needleAngle = Angle.radians(atan2(target.y - pivot.y, target.x - pivot.x))
        let tip = point(pivot, needleLength, needleAngle)
        let headBase = point(pivot, needleLength - 17, needleAngle)
        let normal = Angle.radians(needleAngle.radians + .pi / 2)
        let hubRadius: CGFloat = 9
        var shaft = Path()
        shaft.move(to: point(pivot, hubRadius + 1.75, needleAngle))
        shaft.addLine(to: headBase)
        var head = Path()
        head.move(to: tip)
        head.addLine(to: point(headBase, 8, normal))
        head.addLine(to: point(headBase, -8, normal))
        head.closeSubpath()

        var needle = context
        needle.addFilter(.shadow(color: .black.opacity(0.2), radius: 2, y: 1))
        needle.stroke(shaft, with: .color(zoneColor), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        needle.fill(head, with: .color(zoneColor))
        needle.stroke(head, with: .color(zoneColor), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        // Hollow hub: only the ring is drawn, so the card shows through the middle.
        let hub = Path(ellipseIn: CGRect(
            x: pivot.x - hubRadius,
            y: pivot.y - hubRadius,
            width: hubRadius * 2,
            height: hubRadius * 2
        ))
        needle.stroke(hub, with: .color(zoneColor), lineWidth: 3.5)

        // Score under the hub.
        context.draw(
            Text(result.score, format: .number.precision(.fractionLength(1)))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.primary),
            at: CGPoint(x: center.x, y: center.y + 14)
        )
        context.draw(
            Text("Zone \(result.zone)").font(.footnote.weight(.semibold)).foregroundStyle(zoneColor),
            at: CGPoint(x: center.x, y: center.y + 45)
        )
    }

    // MARK: - Elara meter

    /// Elara: the zones as filled wedges around a light hub, an outer ring with the zone letters
    /// (the current zone tinted), and a slim needle from the hub to the score.
    private func drawElara(in context: inout GraphicsContext, size: CGSize) {
        let outer = min(size.width / 2 - 4, size.height - 74)
        let center = CGPoint(x: size.width / 2, y: outer + 4)
        let ringWidth = outer * 0.17
        let wedgeOuter = outer - ringWidth - 5
        let hubRadius = outer * 0.28
        func angle(_ score: Double) -> Angle { .degrees(180 + 1.8 * min(max(score, 0), 100)) }
        func sector(_ inner: CGFloat, _ outer: CGFloat, _ from: Double, _ to: Double) -> Path {
            var path = Path()
            path.addArc(center: center, radius: outer, startAngle: angle(from), endAngle: angle(to), clockwise: false)
            path.addArc(center: center, radius: inner, startAngle: angle(to), endAngle: angle(from), clockwise: true)
            path.closeSubpath()
            return path
        }

        let textColor = ElaraPalette.text(colorScheme)
        let ringFill = colorScheme == .dark ? Color.white.opacity(0.1) : textColor.opacity(0.06)

        context.drawLayer { layer in
            var lower = 0.0
            for (index, zone) in zones.enumerated() {
                let color = GRIPalette.color(zoneIndex: index, scheme: colorScheme)
                // Wedge, a little lighter toward the hub for depth
                layer.fill(
                    sector(hubRadius, wedgeOuter, lower, zone.score),
                    with: .radialGradient(
                        Gradient(colors: [ElaraPalette.lightened(color, by: 0.35), color]),
                        center: center,
                        startRadius: hubRadius,
                        endRadius: wedgeOuter
                    )
                )
                // Label segment of the outer ring
                layer.fill(
                    sector(outer - ringWidth, outer, lower, zone.score),
                    with: .color(index == zoneIndex ? color.opacity(0.28) : ringFill)
                )
                lower = zone.score
            }
            // Gaps between the zones let the card show through
            layer.blendMode = .destinationOut
            for zone in zones.dropLast() {
                var gap = Path()
                gap.move(to: point(center, hubRadius - 1, angle(zone.score)))
                gap.addLine(to: point(center, outer + 1, angle(zone.score)))
                layer.stroke(gap, with: .color(.black), lineWidth: 3)
            }
        }

        // Zone letters along the outer ring, turned with it
        var lower = 0.0
        for (index, zone) in zones.enumerated() {
            let middle = angle((lower + zone.score) / 2)
            let position = point(center, outer - ringWidth / 2, middle)
            let isCurrent = index == zoneIndex
            var label = context
            label.translateBy(x: position.x, y: position.y)
            label.rotate(by: .degrees(middle.degrees + 90))
            label.draw(
                Text(zone.letter)
                    .font(.system(size: ringWidth * 0.5, weight: isCurrent ? .heavy : .semibold))
                    // White by night; by day the current zone in its color and the rest muted
                    .foregroundStyle(
                        colorScheme == .dark ? Color.white :
                            isCurrent ? ElaraPalette.readable(
                                GRIPalette.color(zoneIndex: index, scheme: colorScheme),
                                colorScheme
                            ) :
                            ElaraPalette.muted(colorScheme)
                    ),
                at: .zero
            )
            lower = zone.score
        }

        // Light hub
        var hub = Path()
        hub.addArc(center: center, radius: hubRadius - 4, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        hub.closeSubpath()
        context.fill(hub, with: .color(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.9)))

        // Slim needle from the hub to the score, with a round knob
        let needleAngle = angle(result.score)
        let normal = Angle.radians(needleAngle.radians + .pi / 2)
        let tip = point(center, wedgeOuter - 6, needleAngle)
        var needle = Path()
        needle.move(to: tip)
        needle.addLine(to: point(center, 4.5, normal))
        needle.addLine(to: point(center, -4.5, normal))
        needle.closeSubpath()
        // Anthracite by day, platinum by night, both with a metallic sheen
        let isDark = colorScheme == .dark
        let needleColors: [Color] = isDark
            ? [
                Color(red: 244 / 255, green: 246 / 255, blue: 248 / 255),
                Color(red: 201 / 255, green: 206 / 255, blue: 212 / 255),
                Color(red: 154 / 255, green: 161 / 255, blue: 170 / 255)
            ]
            : [
                Color(red: 90 / 255, green: 96 / 255, blue: 105 / 255),
                Color(red: 58 / 255, green: 63 / 255, blue: 70 / 255),
                Color(red: 35 / 255, green: 39 / 255, blue: 44 / 255)
            ]
        let knobColors: [Color] = isDark
            ? [
                .white,
                Color(red: 201 / 255, green: 206 / 255, blue: 212 / 255),
                Color(red: 142 / 255, green: 149 / 255, blue: 158 / 255)
            ]
            : [
                Color(red: 122 / 255, green: 129 / 255, blue: 139 / 255),
                Color(red: 58 / 255, green: 63 / 255, blue: 70 / 255),
                Color(red: 30 / 255, green: 34 / 255, blue: 38 / 255)
            ]
        let knobRadius: CGFloat = 9
        let knobRect = CGRect(x: center.x - knobRadius, y: center.y - knobRadius, width: knobRadius * 2, height: knobRadius * 2)
        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(isDark ? 0.5 : 0.25), radius: 2, y: 1))
        shadowed.fill(
            needle,
            with: .linearGradient(Gradient(colors: needleColors), startPoint: point(center, 6, normal), endPoint: tip)
        )
        shadowed.fill(
            Path(ellipseIn: knobRect),
            with: .radialGradient(
                Gradient(colors: knobColors),
                center: CGPoint(x: center.x - knobRadius * 0.3, y: center.y - knobRadius * 0.4),
                startRadius: 0,
                endRadius: knobRadius * 1.4
            )
        )
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 2.6, y: center.y - 2.6, width: 5.2, height: 5.2)),
            with: .color(
                isDark ? Color(red: 107 / 255, green: 114 / 255, blue: 123 / 255) :
                    Color(red: 154 / 255, green: 161 / 255, blue: 170 / 255)
            )
        )

        // Scale ends, score and zone under the meter
        let endFont = Font.system(size: 11, weight: .medium)
        context.draw(
            Text("0").font(endFont).foregroundStyle(ElaraPalette.muted(colorScheme)),
            at: CGPoint(x: center.x - outer + ringWidth / 2, y: center.y + 12)
        )
        context.draw(
            Text("100").font(endFont).foregroundStyle(ElaraPalette.muted(colorScheme)),
            at: CGPoint(x: center.x + outer - ringWidth / 2, y: center.y + 12)
        )
        context.draw(
            Text(result.score, format: .number.precision(.fractionLength(1)))
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(textColor),
            at: CGPoint(x: center.x, y: center.y + 30)
        )
        context.draw(
            Text("Zone \(result.zone)").font(.footnote.weight(.semibold))
                .foregroundStyle(ElaraPalette.readable(zoneColor, colorScheme)),
            at: CGPoint(x: center.x, y: center.y + 58)
        )
    }

    // MARK: - Components

    /// Where the risk comes from, which a single score does not show.
    private var components: some View {
        VStack(spacing: 10) {
            componentRow("Hypoglycemia component", value: result.hypoComponent, scale: 30, color: ElaraPalette.red)
            componentRow(
                "Hyperglycemia component",
                value: result.hyperComponent,
                scale: 60,
                color: ElaraPalette.high
            )
        }
    }

    private func componentRow(_ title: LocalizedStringKey, value: Double, scale: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(1))) + "%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.14))
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, geometry.size.width * min(1, value / scale)))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Legend

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8, alignment: .leading)], spacing: 8) {
            ForEach(Array(zones.enumerated()), id: \.offset) { index, zone in
                HStack(spacing: 6) {
                    Circle()
                        .fill(GRIPalette.color(zoneIndex: index, scheme: colorScheme))
                        .frame(width: 9, height: 9)
                    Text(zone.title)
                        .font(.caption)
                        .foregroundStyle(index == zoneIndex ? .primary : .secondary)
                        .fontWeight(index == zoneIndex ? .semibold : .regular)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        GRIPalette.color(zoneIndex: index, scheme: colorScheme)
                            .opacity(index == zoneIndex ? 0.22 : 0.08)
                    )
                )
            }
        }
    }
}
