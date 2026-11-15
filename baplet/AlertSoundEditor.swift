//
//  AlertSoundEditor.swift
//  baplet
//

import SwiftUI

/// Form rows for alert sound: the on/off switch, then (while on) the sound picker with a play
/// button and the volume slider. Picking a sound plays it once. Shared by Settings → Alerts
/// and the welcome guide, so both edit the same settings the same way.
struct AlertSoundEditor: View {
    @Environment(SettingsStore.self) private var settingsStore

    /// Lays out the switch, and while sound is on the picker, play button and volume slider.
    var body: some View {
        @Bindable var settings = settingsStore

        Toggle("Play sound on alert", isOn: $settings.soundEnabled)
        if settingsStore.soundEnabled {
            LabeledContent("Sound") {
                HStack(spacing: 8) {
                    Picker("Sound", selection: $settings.alertSound) {
                        ForEach(AlertSound.allCases) { sound in
                            Text(sound.label).tag(sound)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button {
                        AlertSoundPlayer.play(settings: settingsStore)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .help("Play sound")
                    .accessibilityLabel("Play sound")
                }
            }
            LabeledContent("Volume") {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: $settings.alertVolume, in: 0.1...1) { editing in
                        if !editing { AlertSoundPlayer.play(settings: settingsStore) }
                    }
                    .frame(width: 160)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Plays the newly picked sound once, so the user hears what they chose. Attached where the
/// editor is shown rather than inside it, since `onChange` belongs on a view, not on rows.
struct PlaysPickedAlertSound: ViewModifier {
    @Environment(SettingsStore.self) private var settingsStore

    /// Watches the chosen sound and plays it whenever it changes.
    func body(content: Content) -> some View {
        content.onChange(of: settingsStore.alertSound) {
            AlertSoundPlayer.play(settings: settingsStore)
        }
    }
}

extension View {
    /// Plays the alert sound whenever the user picks a different one.
    func playsPickedAlertSound() -> some View {
        modifier(PlaysPickedAlertSound())
    }
}
