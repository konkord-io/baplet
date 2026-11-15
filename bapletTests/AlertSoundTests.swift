//
//  AlertSoundTests.swift
//  bapletTests
//

import Foundation
import Testing
@testable import Baplet

/// Tests for `AlertSound`, the synthesized rings and the sound settings.
struct AlertSoundTests {
    /// Checks that there are ten sounds, Ping is the default, and the seven system sounds come
    /// before the three synthesized rings (soft to loud in the picker).
    @Test
    func soundListOrderAndDefault() {
        #expect(AlertSound.allCases.count == 10)
        #expect(AlertSound.defaultSound == .ping)
        let systemFlags = AlertSound.allCases.map { $0.systemSoundName != nil }
        #expect(systemFlags == Array(repeating: true, count: 7) + Array(repeating: false, count: 3))
    }

    /// Checks that every synthesized ring produces a valid WAV file of 0.5–3 seconds, and that
    /// system sounds have no synthesized samples.
    @Test
    func synthesizedRingsAreValidWAV() {
        for sound in AlertSound.allCases where sound.systemSoundName == nil {
            let data = ToneSynthesizer.wavData(for: sound)
            #expect(data.prefix(4) == Data("RIFF".utf8))
            #expect(data.subdata(in: 8..<16) == Data("WAVEfmt ".utf8))
            let seconds = Double(data.count - 44) / 2 / Double(ToneSynthesizer.sampleRate)
            #expect(seconds > 0.5 && seconds < 3, "\(sound) lasts \(seconds) s")
            #expect(ToneSynthesizer.samples(for: sound).contains { $0 != 0 })
        }
        #expect(ToneSynthesizer.samples(for: .ping).isEmpty)
    }

    /// Checks that sound settings default to Ping at full volume and survive a reload.
    @Test
    func soundSettingsDefaultAndPersist() {
        let name = "bapletTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let missingPlist = URL(fileURLWithPath: "/nonexistent/baplet-tests.plist")

        let store = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
        #expect(store.alertSound == .ping)
        #expect(store.alertVolume == 1)

        store.alertSound = .phoneRing
        store.alertVolume = 0.4
        let reloaded = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
        #expect(reloaded.alertSound == .phoneRing)
        #expect(reloaded.alertVolume == 0.4)
    }
}
