//
//  OnboardingView.swift
//  baplet
//

import EventKit
import KeyboardShortcuts
import SwiftUI

/// The welcome guide: Welcome → Calendars → Theme → Shortcut (optional) → Finish. Shown on a fresh install when no
/// calendars are selected, and reopened from Settings → About. Finishing it marks onboarding
/// as completed; closing the window early leaves it pending for the next launch.
struct OnboardingView: View {
    /// The guide's pages, in order.
    enum Step: Int, CaseIterable {
        case welcome, calendars, theme, sound, workingHours, shortcut, finish
    }

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var step: Step = .welcome
    @State private var hasTodayShortcut = KeyboardShortcuts.getShortcut(for: .showToday) != nil

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: OnboardingWelcomeStep()
                case .calendars: OnboardingCalendarsStep()
                case .theme: OnboardingThemeStep()
                case .sound: OnboardingSoundStep()
                case .workingHours: OnboardingWorkingHoursStep()
                case .shortcut: OnboardingShortcutStep(hasShortcut: $hasTodayShortcut)
                case .finish: OnboardingFinishStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()
            footer
                .layoutPriority(1)
        }
        .frame(width: 600, height: 560)
        .onAppear {
            step = DemoMode.scene == .welcomeTheme ? .theme : .welcome
        }
    }

    /// Back button, progress dots and the primary action for the current step.
    private var footer: some View {
        HStack {
            Button("Back") { move(by: -1) }
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)

            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Circle()
                        .fill(item == step ? Color.primary : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()

            Button(primaryTitle) { primaryAction() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// Label of the primary button for the current step.
    private var primaryTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .calendars, .theme, .sound, .workingHours: "Next"
        case .shortcut: hasTodayShortcut ? "Next" : "Skip for Now"
        case .finish: "Finish"
        }
    }

    /// Advances to the next step, or on the last step marks onboarding done and closes the guide.
    private func primaryAction() {
        if step == .finish {
            settingsStore.onboardingCompleted = true
            dismissWindow(id: WindowID.welcome)
        } else {
            move(by: 1)
        }
    }

    /// Moves the given number of steps forwards or backwards, staying within the guide.
    private func move(by offset: Int) {
        if let next = Step(rawValue: step.rawValue + offset) {
            withAnimation(.easeInOut(duration: 0.2)) {
                step = next
            }
        }
    }
}

/// Step 1: the goldfish bowl and a short hello.
private struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Image("goldfish")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 230)
            Text("Hi, welcome to Baplet")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Stay focused. Join meetings on time. Get lost in your work without watching the clock. Baplet makes sure you look up in time for the next meeting.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
        }
        .padding(.top, 8)
    }
}

/// Step 2: grant calendar access if needed, pick calendars, and preview their upcoming events
/// with Test. When no calendars exist yet, explains how to add an account instead.
private struct OnboardingCalendarsStep: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(SettingsStore.self) private var settingsStore
    @State private var preview: [EKEvent]?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose your calendars")
                .font(.title2)
                .fontWeight(.bold)

            switch calendarService.authorizationStatus {
            case .fullAccess:
                if calendarService.calendars.isEmpty {
                    noCalendars
                } else {
                    calendarPicker
                }
            case .notDetermined:
                SettingsHelpText("Baplet needs access to your calendars to see your upcoming meetings.")
                Button("Allow Calendar Access") {
                    Task { await calendarService.requestAccess() }
                }
            default:
                SettingsHelpText("Baplet doesn't have access to your calendars. Turn it on in System Settings → [Privacy & Security → Calendars](x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars), then restart Baplet.")
            }
        }
    }

    /// Shown when access is granted but the Calendar app has no calendars at all.
    private var noCalendars: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHelpText("Baplet didn't find any calendars. It reads the calendars from the accounts in the macOS Calendar app. Add your work or personal account (iCloud, Google, Exchange and others) in System Settings → [Internet Accounts](x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension), then come back and check again.")
            Button("Check Again") {
                calendarService.loadCalendars()
            }
        }
    }

    /// Calendars grouped by account, with Select All and Test underneath.
    private var calendarPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHelpText("Pick the calendars Baplet should watch. Press Test to check that your meetings show up.")

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(calendarService.sources, id: \.sourceIdentifier) { source in
                        let sourceCalendars = calendarService.calendars(for: source)
                        if !sourceCalendars.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(source.title)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                ForEach(sourceCalendars, id: \.calendarIdentifier) { calendar in
                                    CalendarToggle(calendar: calendar)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .frame(maxHeight: .infinity)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Select All") {
                    settingsStore.enabledCalendarIDs = calendarService.allCalendarIDs
                }
                Spacer()
                Button("Test") {
                    preview = calendarService.upcomingEvents(in: settingsStore.enabledCalendarIDs)
                }
                .disabled(settingsStore.enabledCalendarIDs.isEmpty)
            }
        }
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            previewSheet(preview ?? [])
        }
        .onChange(of: settingsStore.enabledCalendarIDs) {
            preview = nil
        }
    }

    /// The Test result in a sheet over the guide: the next few events in the selected
    /// calendars, or a note that none were found. Closed with Done or Return.
    private func previewSheet(_ events: [EKEvent]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Next events")
                .font(.title3)
                .fontWeight(.bold)

            if events.isEmpty {
                Text("No events in the next 7 days in the selected calendars.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(events, id: \.calendarItemIdentifier) { event in
                        HStack(spacing: 8) {
                            CalendarColorDot(calendar: event.calendar, size: 8)
                            Text(Self.when(event))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)
                            Text(event.displayTitle)
                                .lineLimit(1)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { preview = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    /// Short day-and-time label for a preview row, e.g. "Mon 09:30" or "Tue All day".
    private static func when(_ event: EKEvent) -> String {
        let day = event.startDate.formatted(.dateTime.weekday(.abbreviated))
        let time = event.isAllDay ? "All day" : EventTimeFormat.time(event.startDate)
        return "\(day) \(time)"
    }
}

/// Step 3: pick an alert style from live miniature previews, and try it full size with Test.
private struct OnboardingThemeStep: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Pick your alert style")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Test \(settingsStore.alertStyle.label)") {
                    AlertService.showTestAlert(settings: settingsStore)
                }
            }
            SettingsHelpText("This is what pops up before a meeting. Click a style to choose it, and press Test to see it full size.")

            LazyVGrid(columns: [GridItem(.fixed(200), spacing: 24), GridItem(.fixed(200))], spacing: 12) {
                ForEach(AlertStyle.allCases) { style in
                    themeCard(style)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// One selectable card: the style's miniature with its name underneath.
    private func themeCard(_ style: AlertStyle) -> some View {
        let isSelected = settingsStore.alertStyle == style
        return VStack(spacing: 6) {
            AlertStylePreview(style: style)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 3 : 1)
                )
            Text(style.label)
                .font(.callout)
                .fontWeight(isSelected ? .semibold : .regular)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            settingsStore.alertStyle = style
        }
    }
}

/// A miniature of one alert style: the real alert view rendered on a 1024×640 "screen" with a
/// sample event, scaled down to fit. Rendering the real views keeps the previews in step with
/// any future design changes. Not interactive.
struct AlertStylePreview: View {
    let style: AlertStyle

    private static let canvas = CGSize(width: 1024, height: 640)

    var body: some View {
        GeometryReader { geometry in
            content
                .frame(width: Self.canvas.width, height: Self.canvas.height)
                .scaleEffect(geometry.size.width / Self.canvas.width, anchor: .topLeading)
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
        .clipped()
        .allowsHitTesting(false)
    }

    /// The alert drawn the way it appears on screen: the popup floating over a desktop-like
    /// backdrop, full-screen styles over the same dark backdrop their panel uses.
    @ViewBuilder
    private var content: some View {
        switch style {
        case .popupDialog:
            ZStack {
                LinearGradient(colors: [Color(red: 0.35, green: 0.4, blue: 0.6), Color(red: 0.55, green: 0.45, blue: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                AlertPopupView(props: Self.sample)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 20)
            }
        case .fullScreenGlassmorphic, .fullScreenBoldMinimal, .fullScreenWarmPlayful:
            ZStack {
                Color.black.opacity(0.85)
                FullScreenAlertRouter(style: style, props: Self.sample)
            }
        }
    }

    /// The sample event shown in every preview.
    private static let sample = AlertProps(
        title: "Design Review",
        time: "Now 09:58 \u{00b7} 10:00 \u{2013} 10:30",
        location: "Room 4",
        calendarName: "Work",
        meetingLink: .sample,
        onDismiss: {},
        onSnooze: { _ in },
        onOpenMeeting: {},
        onOpenInCalendar: {}
    )
}

/// Step 4: the alert sound and its volume, from a soft hint to loud ringing.
private struct OnboardingSoundStep: View {
    /// Shows the question, the shared sound rows (picking a sound plays it) and where to
    /// change it later.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick an alert sound")
                .font(.title2)
                .fontWeight(.bold)
            SettingsHelpText("Choose how your alerts sound, from a soft hint to loud ringing. Pick one to hear it, and set how loud it plays.")
            Form {
                AlertSoundEditor()
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 160)
            .playsPickedAlertSound()
            SettingsHelpText("You can change this any time in Settings → Alerts.")
        }
    }
}

/// Step 5 (optional): working hours, so meetings in the evening or at the weekend stay quiet.
private struct OnboardingWorkingHoursStep: View {
    /// Shows the question with the watch fish, the shared working hours rows and where to
    /// change them later.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("When do you want alerts?")
                        .font(.title2)
                        .fontWeight(.bold)
                    SettingsHelpText(WorkingHoursHelp.text)
                }
                Image("fish_clock")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 110)
                    .accessibilityHidden(true)
            }
            Form {
                WorkingHoursEditor()
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 200)
            SettingsHelpText("Leave it off to get alerts for every meeting. You can change this any time in Settings → Alerts.")
        }
    }
}

/// Step 6 (optional): record the global shortcut for the Today list. The primary button reads
/// "Skip for Now" until a shortcut is recorded.
private struct OnboardingShortcutStep: View {
    @Binding var hasShortcut: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a shortcut for today's events")
                .font(.title2)
                .fontWeight(.bold)
            SettingsHelpText(TodayShortcutHelp.text)
            Form {
                KeyboardShortcuts.Recorder("Show today's events", name: .showToday) { shortcut in
                    hasShortcut = shortcut != nil
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 80)
            SettingsHelpText("You can skip this and add or change it later in Settings → Shortcuts.")
        }
    }
}

/// Step 7: where to find Baplet from now on.
private struct OnboardingFinishStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .padding(.top, 30)
            Text("You're all set!")
                .font(.largeTitle)
                .fontWeight(.bold)
            HStack(spacing: 8) {
                Text("Baplet lives in your menu bar. Look for")
                Image("BapletToolbar")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                Text("at the top of your screen.")
            }
            .font(.title3)
            Text("Click it to see your upcoming meetings. You can change calendars, alert style and meeting browser any time in Settings.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
        }
    }
}
