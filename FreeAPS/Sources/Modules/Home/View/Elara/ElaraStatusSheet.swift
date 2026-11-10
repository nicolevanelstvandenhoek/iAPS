import CoreData
import SwiftUI

/// Elara version of the loop status popup: the loop's decision (temp basal, SMB, eventual
/// glucose) in large numbers, the values it calculated with in two columns, and the algorithm's
/// own reasoning with every tag kept. Shows the same information as the iAPS popup.
struct ElaraStatusSheet: View {
    @ObservedObject var state: Home.StateModel

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(fetchRequest: Home.RootView.latestReasonRequest) private var latestReason: FetchedResults<Reasons>

    private var suggestion: Suggestion? { state.data.suggestion }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Status

    private var statusColor: Color {
        if state.errorMessage != nil { return ElaraPalette.red }
        if state.isLooping { return ElaraPalette.insulin }
        return isStale ? Color.orange : ElaraPalette.green
    }

    private var statusLabel: String {
        if state.errorMessage != nil { return NSLocalizedString("Error", comment: "Elara loop status") }
        if state.isLooping { return NSLocalizedString("Looping", comment: "Elara loop status") }
        return isStale ? NSLocalizedString("Delayed", comment: "Elara loop status") :
            NSLocalizedString("Active", comment: "Elara loop status")
    }

    private var isStale: Bool { Date().timeIntervalSince(state.lastLoopDate) > 15 * 60 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let message = state.errorMessage {
                    errorCard(message)
                        .padding(.top, 14)
                } else if let suggestion, (suggestion.bg ?? 100) == 400 {
                    errorCard(NSLocalizedString("SMBs and High Temps Disabled.", comment: ""))
                        .padding(.top, 14)
                }
                if let suggestion {
                    section(NSLocalizedString("Decision", comment: "Elara loop")) { decisionCard(suggestion) }
                    section(NSLocalizedString("Calculation", comment: "Elara loop")) { calculationCard(suggestion) }
                    section(NSLocalizedString("Explanation", comment: "Elara loop")) { reasonCard(suggestion) }
                } else {
                    Text("No suggestion found")
                        .font(.system(size: 14))
                        .foregroundStyle(ElaraPalette.muted(scheme))
                        .padding(.top, 16)
                        .padding(.horizontal, 6)
                }
                runLoopButton
                    .padding(.top, 18)
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .background(ElaraBackground())
        .foregroundStyle(ElaraPalette.text(scheme))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Loop")
                    .font(.system(size: 32, weight: .heavy))
                    .kerning(-0.6)
                Text(state.statusTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(ElaraPalette.muted(scheme))
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ElaraPalette.readable(statusColor, scheme))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(statusColor.opacity(0.16)))
        }
        .padding(.horizontal, 4)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let date = state.errorDate, state.errorMessage != nil {
                Text(NSLocalizedString("Status at", comment: "") + " " + dateFormatter.string(from: date))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ElaraPalette.readable(ElaraPalette.red, scheme))
            } else {
                Text("Invalid CGM reading (HIGH).")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ElaraPalette.readable(ElaraPalette.red, scheme))
            }
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(ElaraPalette.muted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(ElaraPalette.red.opacity(scheme == .dark ? 0.16 : 0.1))
        )
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ElaraPalette.muted(scheme))
                .padding(.horizontal, 6)
            content()
        }
        .padding(.top, 16)
    }

    // MARK: - Decision

    private func decisionCard(_ suggestion: Suggestion) -> some View {
        let smb = suggestion.units ?? 0
        let unit = NSLocalizedString("U", comment: "Insulin unit")
        return HStack(alignment: .top, spacing: 0) {
            tile(
                ElaraPalette.insulin,
                NSLocalizedString("Temp basal", comment: "Elara"),
                value: suggestion.rate.map { insulin($0) } ?? "—",
                unit: unit + "/h",
                detail: suggestion.duration.map { "\($0) min" }
            )
            tileDivider
            tile(
                ElaraPalette.insulin,
                "SMB",
                value: insulin(smb),
                unit: unit,
                detail: nil
            )
            tileDivider
            tile(
                ElaraPalette.green,
                NSLocalizedString("Eventual", comment: "Elara forecast"),
                value: glucose(suggestion.eventualBG.map { Decimal($0) }),
                unit: nil,
                detail: state.data.units.rawValue
            )
        }
        .padding(14)
        .elaraCard(scheme)
    }

    private var tileDivider: some View {
        Rectangle().fill(ElaraPalette.hairline(scheme)).frame(width: 1).padding(.horizontal, 10)
    }

    private func tile(_ color: Color, _ title: String, value: String, unit: String?, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(ElaraPalette.muted(scheme))
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .heavy))
                    .kerning(-0.4)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ElaraPalette.muted(scheme))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(detail ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(ElaraPalette.muted(scheme))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Calculation

    private func calculationCard(_ suggestion: Suggestion) -> some View {
        let unit = NSLocalizedString("U", comment: "Insulin unit")
        let reason = latestReason.first
        let rows: [(Color, String, String)] = [
            (ElaraPalette.insulin, "IOB", suggestion.iob.map { insulin($0) + " " + unit } ?? "—"),
            (ElaraPalette.carbs, "COB", suggestion.cob.map { number($0, digits: 0) + " g" } ?? "—"),
            (
                ElaraPalette.green,
                "ISF",
                reason?.isf.map { number($0.decimalValue, digits: state.data.units == .mmolL ? 1 : 0) } ?? "—"
            ),
            (ElaraPalette.carbs, "CR", reason?.cr.map { number($0.decimalValue, digits: 1) } ?? "—"),
            (ElaraPalette.pump, "Autosens", suggestion.sensitivityRatio.map { number($0, digits: 2) } ?? "—"),
            (ElaraPalette.green, NSLocalizedString("Target", comment: ""), glucose(suggestion.targetBG)),
            (
                ElaraPalette.device,
                NSLocalizedString("Insulin req.", comment: "Elara"),
                insulin(suggestion.insulinReq ?? 0) + " " + unit
            ),
            (ElaraPalette.device, "TDD", reason?.tdd.map { number($0.decimalValue, digits: 1) + " " + unit } ?? "—")
        ]
        return Grid(horizontalSpacing: 16, verticalSpacing: 0) {
            ForEach(0 ..< rows.count / 2, id: \.self) { line in
                GridRow {
                    calcRow(rows[line * 2])
                    calcRow(rows[line * 2 + 1])
                }
                if line < rows.count / 2 - 1 {
                    GridRow {
                        Rectangle().fill(ElaraPalette.hairline(scheme)).frame(height: 1)
                        Rectangle().fill(ElaraPalette.hairline(scheme)).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .elaraCard(scheme)
    }

    private func calcRow(_ row: (Color, String, String)) -> some View {
        HStack(spacing: 8) {
            Circle().fill(row.0).frame(width: 7, height: 7)
            Text(row.1)
                .foregroundStyle(ElaraPalette.muted(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(row.2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.system(size: 14))
        .frame(minHeight: 40)
    }

    // MARK: - Reasoning

    private func reasonCard(_ suggestion: Suggestion) -> some View {
        let tags = suggestion.reasonParts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return VStack(alignment: .leading, spacing: 12) {
            Text(suggestion.reasonConclusion.capitalizingFirstLetter())
                .font(.system(size: 14))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            ElaraFlowLayout(spacing: 6) {
                ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ElaraPalette.muted(scheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ElaraPalette.control(scheme)))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elaraCard(scheme)
    }

    /// Runs the loop now, as a long press on the loop does.
    private var runLoopButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            state.runLoop()
            dismiss()
        } label: {
            Label(NSLocalizedString("Run loop now", comment: "Elara loop"), systemImage: "arrow.clockwise")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ElaraPalette.green))
        }
        .buttonStyle(.plain)
        .disabled(state.isLooping)
        .opacity(state.isLooping ? 0.5 : 1)
    }

    // MARK: - Formatting

    private func number(_ value: Decimal, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    private func insulin(_ value: Decimal) -> String { number(value, digits: 2) }

    /// A value in mg/dL in the user's unit.
    private func glucose(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return state.data.units == .mmolL ? number(value.asMmolL, digits: 1) : number(value, digits: 0)
    }
}

/// Lays out its children left to right and wraps to a new line when a row is full.
struct ElaraFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
