//
//  SettingsView.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import AppKit
import EventKit
import KeyboardShortcuts
import SwiftUI

/// Settings window using a macOS System Settings-style sidebar navigation.
struct SettingsView: View {
    private enum SettingsPane: String, Hashable, CaseIterable {
        case calendars
        case alerts
        case meetings
        case shortcuts
        case about

        /// Display label for the sidebar row.
        var label: String {
            switch self {
            case .calendars: "Calendars"
            case .alerts: "Alerts"
            case .meetings: "Meetings"
            case .shortcuts: "Shortcuts"
            case .about: "About"
            }
        }

        /// SF Symbol name for the sidebar row icon.
        var icon: String {
            switch self {
            case .calendars: "calendar"
            case .alerts: "bell"
            case .meetings: "video"
            case .shortcuts: "command"
            case .about: "info.circle"
            }
        }
    }

    @State private var selectedPane: SettingsPane = .calendars

    /// Watches the Settings window for Escape, which closes it.
    @State private var escapeMonitor = PanelKeyMonitor()

    /// Lays out the sidebar and the selected pane, and makes Escape close the window.
    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, id: \.self, selection: $selectedPane) { pane in
                Label(pane.label, systemImage: pane.icon)
            }
            .navigationSplitViewColumnWidth(180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch selectedPane {
            case .calendars:
                CalendarsPane()
            case .alerts:
                AlertsPane()
            case .meetings:
                MeetingsPane()
            case .shortcuts:
                ShortcutsPane()
            case .about:
                AboutPane()
            }
        }
        .frame(width: 660, height: 500)
        .onAppear {
            selectedPane = DemoMode.scene?.settingsPane.flatMap(SettingsPane.init(rawValue:)) ?? .calendars
        }
        .background(WindowReader { installEscapeToClose(for: $0) })
    }

    /// Closes the window on a plain Escape, like other macOS settings windows. Escape still goes
    /// to a text field or the shortcut recorder while one is being edited (the field editor is
    /// first responder then), so it can cancel the edit or the recording instead.
    private func installEscapeToClose(for window: NSWindow) {
        escapeMonitor.start(for: window) { [weak window] event in
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard let window, event.keyCode == KeyCode.escape, modifiers.isEmpty,
                  !(window.firstResponder is NSText) else { return event }
            window.performClose(nil)
            return nil
        }
    }
}

/// Pane for selecting which calendars to include in the event list and alarm system.
private struct CalendarsPane: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Group {
            if calendarService.sources.isEmpty {
                ContentUnavailableView {
                    Label("No Calendars", systemImage: "calendar")
                } description: {
                    Text("No calendar sources found. Grant calendar access first.")
                }
            } else {
                Form {
                    Section {
                        SettingsHelpText("Choose which calendars Baplet watches. Events from the selected calendars appear in the menu and can trigger alerts. The list comes from the accounts in the macOS Calendar app (iCloud, Google, Exchange and others). To add one, go to System Settings → [Internet Accounts](x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension).")
                    }

                    ForEach(calendarService.sources, id: \.sourceIdentifier) { source in
                        let sourceCalendars = calendarService.calendars(for: source)
                        if !sourceCalendars.isEmpty {
                            Section(source.title) {
                                ForEach(sourceCalendars, id: \.calendarIdentifier) { calendar in
                                    CalendarToggle(calendar: calendar)
                                }
                            }
                        }
                    }

                    Section {
                        HStack {
                            Spacer()
                            Button("Select All") {
                                settingsStore.enabledCalendarIDs = calendarService.allCalendarIDs
                            }
                            Button("Deselect All") {
                                settingsStore.enabledCalendarIDs = []
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("Calendars")
    }
}

/// Checkbox that includes or excludes one calendar, labelled with its colour and title.
/// Shared by Settings → Calendars and the welcome guide; `MenuBarLabel` re-fetches events
/// whenever the selection changes.
struct CalendarToggle: View {
    @Environment(SettingsStore.self) private var settingsStore
    let calendar: EKCalendar

    var body: some View {
        Toggle(isOn: isEnabled) {
            HStack(spacing: 8) {
                CalendarColorDot(calendar: calendar)
                Text(calendar.title)
            }
        }
    }

    /// Two-way binding to whether this calendar is in `SettingsStore.enabledCalendarIDs`.
    private var isEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.isCalendarEnabled(calendarID: calendar.calendarIdentifier) },
            set: { _ in settingsStore.toggleCalendar(calendarID: calendar.calendarIdentifier) }
        )
    }
}

/// Pane for configuring alert style and timing.
private struct AlertsPane: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        @Bindable var settings = settingsStore

        Form {
            Section {
                SettingsHelpText("Choose how Baplet alerts you before an event starts, and try it out with Test Alert. Declined and cancelled meetings don't alert unless you tick them. You can also choose how early the menu bar counts down, the working hours Baplet alerts in, and how many days of events the menu shows.")
            }

            Section {
                Picker("Style", selection: $settings.alertStyle) {
                    ForEach(AlertStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                LabeledContent("Alert before event") {
                    ValueStepper(value: $settings.minutesBefore, range: 1...60, unit: "min", pluralUnit: "min")
                }
                LabeledContent("Days of events shown") {
                    ValueStepper(value: $settings.daysToShow, range: 1...14, unit: "day", pluralUnit: "days")
                }
                Toggle("Alert for meetings I declined", isOn: $settings.alertForDeclinedMeetings)
                LabeledContent("Test the selected alert style") {
                    Button("Test Alert") {
                        AlertService.showTestAlert(settings: settingsStore)
                    }
                }
            }

            Section("Sound") {
                AlertSoundEditor()
            }

            Section {
                Picker("Show countdown in menu bar", selection: $settings.countdownRange) {
                    ForEach(CountdownRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
            }

            Section("Working hours") {
                WorkingHoursEditor()
                SettingsHelpText(WorkingHoursHelp.text)
            }

            Section("Focus (Experimental)") {
                Toggle("Hold back alerts during Focus", isOn: $settings.holdAlertsDuringFocus)
                SettingsHelpText("To choose which Focus holds back alerts, open System Settings → [Focus](x-apple.systempreferences:com.apple.Focus-Settings.extension), pick a Focus such as Do Not Disturb, and under Focus Filters add **Baplet** with Hold back alerts on. An alert that comes due during that Focus shows when it ends, if the meeting is still going.")
            }
        }
        .formStyle(.grouped)
        .playsPickedAlertSound()
        .navigationTitle("Alerts")
    }
}

/// Pane for choosing which browser, and which of its profiles, opens meeting links.
/// The profile picker appears only for browsers whose profiles Baplet can select
/// (Chromium family and Firefox).
private struct MeetingsPane: View {
    @Environment(SettingsStore.self) private var settingsStore
    @State private var browsers: [Browser] = []
    @State private var profiles: [BrowserProfile] = []

    var body: some View {
        @Bindable var settings = settingsStore

        Form {
            Section {
                SettingsHelpText("Choose the browser that opens meeting links when you join from an alert, the O/Return shortcut or the event list. For Chrome, Edge, Brave, Vivaldi and Firefox you can also pick which profile to use.")
            }

            Section {
                Picker("Browser", selection: $settings.meetingBrowserID) {
                    Text("System default").tag(String?.none)
                    Divider()
                    ForEach(browsers) { browser in
                        Label {
                            Text(browser.name)
                        } icon: {
                            Image(nsImage: Self.menuIcon(for: browser))
                        }
                        .tag(Optional(browser.bundleID))
                    }
                }

                if selectedBrowser?.profileFamily != nil {
                    Picker("Profile", selection: $settings.meetingBrowserProfileID) {
                        Text("Browser default").tag(String?.none)
                        if !profiles.isEmpty {
                            Divider()
                        }
                        ForEach(profiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    .disabled(profiles.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Meetings")
        .onAppear {
            browsers = BrowserService.installedBrowsers(keeping: settingsStore.meetingBrowserID)
            loadProfiles()
        }
        .onChange(of: settingsStore.meetingBrowserID) {
            settingsStore.meetingBrowserProfileID = nil
            loadProfiles()
        }
    }

    /// The installed browser matching the saved choice, or nil for the system default.
    private var selectedBrowser: Browser? {
        browsers.first { $0.bundleID == settingsStore.meetingBrowserID }
    }

    /// Re-reads the profile list for the selected browser (empty when it has none).
    private func loadProfiles() {
        profiles = selectedBrowser.map { BrowserService.profiles(for: $0) } ?? []
    }

    /// The browser's app icon scaled to menu size, so the picker rows stay compact.
    private static func menuIcon(for browser: Browser) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: browser.appURL.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

/// Pane for recording the global shortcut that shows today's events from any app, and for
/// choosing what Return does in that list.
private struct ShortcutsPane: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        @Bindable var settings = settingsStore

        Form {
            Section {
                SettingsHelpText(TodayShortcutHelp.text)
            }
            Section {
                KeyboardShortcuts.Recorder("Show today's events", name: .showToday)
            }
            Section {
                Picker("Return in today's events", selection: $settings.todayReturnAction) {
                    ForEach(TodayReturnAction.allCases) { action in
                        Text(action.label).tag(action)
                    }
                }
            } footer: {
                Text("In the list, ↑ and ↓ pick an event, Return does this, ⌘Return does the other, and D turns the alarm on or off. Join meeting opens Calendar when the event has no meeting link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Shortcuts")
    }
}

/// Pane with the app logo, name, version, creator, copyright, Baplet's own MIT licence and
/// GitHub link, the update check and its automatic toggle, plus credits for any
/// bundled open-source packages (that section is hidden while there are none).
private struct AboutPane: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(UpdateService.self) private var updateService
    @Environment(\.openURL) private var openURL
    @State private var licenseShown: OpenSourcePackage?

    /// The owner's GitHub Sponsors page, also linked from the website, README and install DMG.
    private static let sponsorURL = URL(string: "https://github.com/sponsors/lazee")!

    /// Lays out the app info, updates, the sponsor section and the open source credits.
    var body: some View {
        @Bindable var settings = settingsStore

        Form {
            Section {
                VStack(spacing: 6) {
                    Image("baplet")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .padding(.bottom, 4)
                    Text("Baplet")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("Version \(Self.infoValue("CFBundleShortVersionString")) (\(Self.infoValue("CFBundleVersion")))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Created by Jakob Vad Nielsen")
                        .padding(.top, 8)
                    Text(Self.infoValue("NSHumanReadableCopyright"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text("Licensed under the \(OpenSourcePackage.baplet.license) License")
                        Button("View License") { licenseShown = .baplet }
                            .buttonStyle(.link)
                        Text("·")
                        Link("GitHub", destination: OpenSourcePackage.baplet.url)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Button("Show Welcome Guide") {
                        openWindow.openWelcome()
                    }
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Updates") {
                LabeledContent {
                    Button("Check for Updates") {
                        Task { await checkForUpdates() }
                    }
                    .disabled(updateService.checkStatus == .checking)
                } label: {
                    Text(updateStatusLine)
                    if case .available = updateService.checkStatus {
                        Button("Show Update") { openWindow.openUpdate() }
                            .buttonStyle(.link)
                    }
                }
                Toggle("Check for updates automatically", isOn: $settings.checkForUpdatesAutomatically)
            }

            Section("Support Baplet") {
                LabeledContent {
                    Button {
                        openURL(Self.sponsorURL)
                    } label: {
                        Label("Sponsor", systemImage: "heart.fill")
                    }
                } label: {
                    Text("Baplet is free. Sponsoring helps pay Apple's yearly developer fee, so Baplet can one day open without the Open Anyway step.")
                }
            }

            if !OpenSourcePackage.all.isEmpty {
                Section("Built with open source") {
                    ForEach(OpenSourcePackage.all) { package in
                        LabeledContent {
                            Button("License") { licenseShown = package }
                        } label: {
                            Link(package.name, destination: package.url)
                            Text(package.license)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
        .sheet(item: $licenseShown) { package in
            LicenseSheet(package: package)
        }
    }

    /// The status line next to Check for Updates: the last result in this session, or when
    /// Baplet last checked if nothing has been checked since launch.
    private var updateStatusLine: String {
        if let message = updateService.checkStatus.message {
            return message
        }
        guard let lastCheck = settingsStore.lastUpdateCheck else {
            return "Not checked yet"
        }
        return "Last checked \(lastCheck.formatted(.relative(presentation: .named)))"
    }

    /// Runs a manual update check and opens the update dialog when it finds a new version,
    /// so the user can act on it straight away.
    private func checkForUpdates() async {
        if await updateService.checkNow(settings: settingsStore) {
            openWindow.openUpdate()
        }
    }

    /// Reads a string from the app's Info.plist, so version and copyright have one source.
    private static func infoValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}

/// Scrollable full license text for one open-source package, closed with Done or Escape.
private struct LicenseSheet: View {
    let package: OpenSourcePackage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(package.name) — \(package.license)")
                .font(.headline)
            ScrollView {
                Text(package.licenseText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 360)
    }
}

/// A settings value shown as "5 min" or "3 days" right next to its stepper arrows, so the row
/// label can stay a plain description while the number sits on the right like System Settings.
private struct ValueStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    let pluralUnit: String

    var body: some View {
        HStack(spacing: 6) {
            Text("\(value) \(value == 1 ? unit : pluralUnit)")
                .monospacedDigit()
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
    }
}

/// The explanation under the working hours settings, shared with the welcome guide.
enum WorkingHoursHelp {
    static let text: LocalizedStringKey = "Meetings that start outside your working hours don't alert and don't show in the menu bar countdown. They still appear in the menu, where you can tick a meeting's box to get its alert anyway."
}
