import HealthKit
import SwiftUI

/// The six groups of the Elara settings screen, as in Trio Elara. They hold the same rows as the
/// sections of the iAPS settings list.
enum ElaraSettingsSection: String, CaseIterable, Identifiable {
    case devices
    case services
    case therapy
    case openaps
    case extras
    case developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .devices: return NSLocalizedString("Devices", comment: "")
        case .services: return NSLocalizedString("Services", comment: "")
        case .therapy: return NSLocalizedString("Therapy", comment: "Elara settings group")
        case .openaps: return "OpenAPS"
        case .extras: return NSLocalizedString("Extras", comment: "Elara settings group")
        case .developer: return NSLocalizedString("Developer", comment: "")
        }
    }

    var symbol: String {
        switch self {
        case .devices: return "sensor.tag.radiowaves.forward"
        case .services: return "cloud"
        case .therapy: return "drop"
        case .openaps: return "arrow.triangle.2.circlepath"
        case .extras: return "sparkles"
        case .developer: return "terminal"
        }
    }
}

/// The settings screen in the Elara skin: a large title, the six groups as tiles, the rows of the
/// chosen group in one card and the closed loop switch at the bottom.
struct ElaraSettingsLayout<Rows: View>: View {
    let versionLines: [String]
    let releaseNotice: String?
    @Binding var selected: ElaraSettingsSection
    @Binding var closedLoop: Bool
    let showsGroups: Bool
    @ViewBuilder let rows: (ElaraSettingsSection) -> Rows

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            header
            if showsGroups {
                tiles
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        rows(selected)
                    }
                    .elaraCard(scheme)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
                    .id(selected)
                }
                .frame(maxHeight: .infinity)
            } else {
                Text("To enable settings, go to the App Config section in iOS Settings App")
                    .font(.system(size: 14))
                    .foregroundStyle(ElaraPalette.muted(scheme))
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            loopCard
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 34, weight: .heavy))
                .tracking(-0.7)
                .foregroundStyle(ElaraPalette.text(scheme))
            ForEach(versionLines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.system(size: 12))
                    .foregroundStyle(ElaraPalette.muted(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let releaseNotice {
                Text(releaseNotice)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    /// Rounded tiles in a 3 × 2 grid; the chosen one is tinted green.
    private var tiles: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(ElaraSettingsSection.allCases) { section in
                let isActive = section == selected
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selected = section }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 20, weight: .medium))
                        Text(section.title)
                            .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isActive ? ElaraPalette.text(scheme) : ElaraPalette.muted(scheme))
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(isActive ? ElaraPalette.green.opacity(0.4) : ElaraPalette.card(scheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isActive ? ElaraPalette.green.opacity(0.7) : ElaraPalette.cardBorder(scheme), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
    }

    private var loopCard: some View {
        Toggle(isOn: $closedLoop) {
            Text("Closed loop")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ElaraPalette.text(scheme))
        }
        .tint(ElaraPalette.green)
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .elaraCard(scheme)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 26)
    }
}

/// One row of the Elara settings card: a coloured dot, the title and what goes on the right.
struct ElaraSettingsRow<Trailing: View>: View {
    let title: String
    let dot: Color
    var first = false
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle().fill(ElaraPalette.hairline(scheme)).frame(height: 1)
            }
            HStack(spacing: 10) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(NSLocalizedString(title, comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ElaraPalette.text(scheme))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }
}

struct ElaraSettingsChevron: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ElaraPalette.text(scheme).opacity(0.35))
    }
}

extension Settings.RootView {
    private var versionLines: [String] {
        var lines = ["iAPS v\(state.versionNumber) (\(state.buildNumber)) · \(state.branch) \(state.copyrightNotice)"]
        if Bundle.main.profileExpirationDate != nil {
            lines.append(NSLocalizedString("Build Expires: ", comment: "") + BuildExpirationManager.shared.expirationDateText)
        }
        return lines
    }

    private var releaseNotice: String? {
        guard let latest = fetchedVersionNumber.first,
              let nr = Version(main: latest.nr ?? "", dev: latest.dev ?? "")
              .offered(for: state.versionNumber, branch: Version.runningBranchName)
        else { return nil }
        return NSLocalizedString("Newer release available at GitHub: ", comment: "") + nr
    }

    var elaraContent: some View {
        ElaraSettingsLayout(
            versionLines: versionLines,
            releaseNotice: releaseNotice,
            selected: $elaraSection,
            closedLoop: $state.closedLoop,
            showsGroups: !AppSettings.shared.hideSettingsToggle
        ) { section in
            switch section {
            case .devices:
                elaraLink("Pump", .pumpConfig, ElaraPalette.pump, first: true)
                elaraLink("CGM", .cgm, ElaraPalette.green)
                elaraLink("Watch", .watch, ElaraPalette.device)
            case .services:
                elaraLink("Nightscout", .nighscoutConfig, ElaraPalette.insulin, first: true)
                if HKHealthStore.isHealthDataAvailable() {
                    elaraLink("Apple Health", .healthkit, ElaraPalette.insulin)
                }
                elaraLink("Notifications", .notificationsConfig, ElaraPalette.insulin)
            case .therapy:
                elaraLink("Pump Settings", .pumpSettingsEditor, ElaraPalette.green, first: true)
                elaraLink("Basal Profile", .basalProfileEditor(saveNewConcentration: false), ElaraPalette.green)
                elaraLink("Insulin Sensitivities", .isfEditor, ElaraPalette.green)
                elaraLink("Carb Ratios", .crEditor, ElaraPalette.green)
                elaraLink("Target Glucose", .targetsEditor, ElaraPalette.green)
                ElaraSettingsRow(title: "Hypo Treatment", dot: ElaraPalette.green) {
                    Picker("", selection: $state.profileID) {
                        Text("Default  📉").tag("Hypo Treatment")
                        ForEach(fetchedProfiles) { item in
                            Text(item.name ?? "").tag(item.id?.string ?? "")
                        }
                        Text("None").tag("None")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            case .openaps:
                elaraLink("OpenAPS", .preferencesEditor, ElaraPalette.pump, first: true)
                elaraLink("Autotune", .autotuneConfig, ElaraPalette.pump)
            case .extras:
                elaraLink("App Icons", .iconConfig, ElaraPalette.carbs, first: true)
                elaraLink("Auto ISF", .autoISF, ElaraPalette.carbs)
                elaraLink("Bolus Calculator", .bolusCalculatorConfig, ElaraPalette.carbs)
                elaraLink("Calendar", .calendar, ElaraPalette.carbs)
                elaraLink("Contact Image", .contactTrick, ElaraPalette.carbs)
                elaraLink("Dynamic ISF", .dynamicISF, ElaraPalette.carbs)
                elaraLink("Fat And Protein Conversion", .fpuConfig, ElaraPalette.carbs)
                elaraLink("Sharing", .sharing, ElaraPalette.carbs)
                elaraLink("UI/UX", .uiConfig, ElaraPalette.carbs)
            case .developer:
                elaraDeveloperRows
            }
        }
    }

    private func elaraLink(_ title: String, _ screen: Screen, _ dot: Color, first: Bool = false) -> some View {
        ElaraSettingsRow(title: title, dot: dot, first: first) { ElaraSettingsChevron() }
            .navigationLink(to: screen, from: self)
            .buttonStyle(.plain)
    }

    private func elaraButtonRow(_ title: String, _ button: String, tint: Color? = nil, action: @escaping () -> Void)
        -> some View
    {
        ElaraSettingsRow(title: title, dot: ElaraPalette.device) {
            Button(button, action: action)
                .buttonStyle(.borderedProminent)
                .tint(tint)
        }
    }

    private func elaraToggleRow(_ title: String, _ isOn: Binding<Bool>, first: Bool = false) -> some View {
        ElaraSettingsRow(title: title, dot: ElaraPalette.device, first: first) {
            Toggle("", isOn: isOn).labelsHidden().tint(ElaraPalette.green)
        }
    }

    /// The developer rows of the iAPS settings list, with the same actions.
    @ViewBuilder private var elaraDeveloperRows: some View {
        elaraToggleRow("Debug options", $state.debugOptions, first: true)
        if state.debugOptions {
            elaraButtonRow("NS Upload Profile and Settings", "Upload") { state.uploadProfileAndSettings(true) }
            elaraButtonRow("Upload Previous Day's Log", "Upload") { state.uploadPreviousDayLog() }
            elaraToggleRow("Allow diluted insulin concentration settings", $state.allowDilution)
            elaraToggleRow("Max Override 400%", $state.extended_overrides)
            elaraButtonRow("Simulate a crash", "Crash", tint: .red) { simulateCrashAlert = true }
                .alert("Simulate a crash?", isPresented: $simulateCrashAlert) {
                    Button("Crash", role: .destructive) { CrashReportService.simulateCrash() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "iAPS will stop immediately and must be reopened. If \"Send crash reports\" is on in Sharing, the report is sent at the next start."
                    )
                }
            ForEach(Self.elaraConfigFiles, id: \.file) { item in
                elaraLink(item.title, .configEditor(file: item.file), ElaraPalette.device)
            }
            elaraToggleRow("Neglect Carbs in oref0", $state.noCarbs)
            elaraButtonRow("Delete All NS Overrides", "Delete", tint: .red) { state.deleteOverrides() }
            NavigationLink(destination: clearView) {
                ElaraSettingsRow(title: "Delete CoreData database records", dot: ElaraPalette.device) {
                    ElaraSettingsChevron()
                }
            }
            .buttonStyle(.plain)
            elaraButtonRow("Replay onboarding (new install)", "Reset") {
                let d = UserDefaults.standard
                d.removeObject(forKey: IAPSconfig.version)
                d.set(false, forKey: IAPSconfig.hasSeenWelcome)
                d.set(false, forKey: IAPSconfig.hasSeenSharingSetup)
                d.set(false, forKey: IAPSconfig.showUpgradeNotice)
            }
            elaraButtonRow("Replay onboarding (as upgrade)", "Reset") {
                let d = UserDefaults.standard
                d.set("reset", forKey: IAPSconfig.version)
                d.set(false, forKey: IAPSconfig.hasSeenSharingSetup)
            }
        }
        Button { showShareSheet = true } label: {
            ElaraSettingsRow(title: "Share logs", dot: ElaraPalette.device) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// The settings files the iAPS developer section opens, in the same order.
    private static var elaraConfigFiles: [(title: String, file: String)] {
        [
            ("Preferences", OpenAPS.Settings.preferences),
            ("Pump Settings", OpenAPS.Settings.settings),
            ("Autosense", OpenAPS.Settings.autosense),
            ("Pump History", OpenAPS.Monitor.pumpHistory),
            ("Temp Basals", OpenAPS.Monitor.tempBasal),
            ("Basal profile", OpenAPS.Settings.basalProfile),
            ("Targets ranges", OpenAPS.Settings.bgTargets),
            ("Temp targets", OpenAPS.Settings.tempTargets),
            ("Meal", OpenAPS.Monitor.meal),
            ("Pump profile", OpenAPS.Settings.pumpProfile),
            ("Profile", OpenAPS.Settings.profile),
            ("Carbs", OpenAPS.Monitor.carbHistory),
            ("Enacted", OpenAPS.Enact.enacted),
            ("Announcements", OpenAPS.FreeAPS.announcements),
            ("Enacted announcements", OpenAPS.FreeAPS.announcementsEnacted),
            ("Overrides Not Uploaded", OpenAPS.Nightscout.notUploadedOverrides),
            ("Autotune", OpenAPS.Settings.autotune),
            ("Glucose", OpenAPS.Monitor.glucose),
            ("Dynamic Variables", OpenAPS.Monitor.dynamicVariables),
            ("Target presets", OpenAPS.FreeAPS.tempTargetsPresets),
            ("Calibrations", OpenAPS.FreeAPS.calibrations),
            ("Middleware", OpenAPS.Middleware.determineBasal),
            ("Statistics", OpenAPS.Monitor.statistics),
            ("Edit settings json", OpenAPS.FreeAPS.settings)
        ]
    }
}
