//
//  AlertSound.swift
//  baplet
//

import AppKit

/// The sound an alert plays, from a soft hint to loud ringing, in that order in the picker.
/// The first seven are macOS system sounds; the last three are rings Baplet synthesizes
/// itself, so no audio files (or their licenses) ship with the app.
enum AlertSound: String, CaseIterable, Identifiable {
    case tink
    case pop
    case purr
    case ping
    case glass
    case hero
    case submarine
    case phoneRing
    case alarmClock
    case urgentBeeps

    /// The sound used until the user picks one; Ping is what every alert played before.
    static let defaultSound: AlertSound = .ping

    /// Identity for `ForEach` and pickers: the stored raw value.
    var id: String { rawValue }

    /// Name shown in the picker.
    var label: String {
        switch self {
        case .tink: "Tink"
        case .pop: "Pop"
        case .purr: "Purr"
        case .ping: "Ping"
        case .glass: "Glass"
        case .hero: "Hero"
        case .submarine: "Submarine"
        case .phoneRing: "Phone ring"
        case .alarmClock: "Alarm clock"
        case .urgentBeeps: "Urgent beeps"
        }
    }

    /// The macOS system sound name behind this choice, or nil for a synthesized ring.
    var systemSoundName: String? {
        switch self {
        case .tink: "Tink"
        case .pop: "Pop"
        case .purr: "Purr"
        case .ping: "Ping"
        case .glass: "Glass"
        case .hero: "Hero"
        case .submarine: "Submarine"
        case .phoneRing, .alarmClock, .urgentBeeps: nil
        }
    }

    /// A fresh `NSSound` for this choice: the system sound, or the synthesized ring wrapped as
    /// in-memory WAV data. Fresh each time so a replay can overlap and carry its own volume.
    func makeSound() -> NSSound? {
        if let systemSoundName {
            return NSSound(named: systemSoundName)?.copy() as? NSSound
        }
        return NSSound(data: ToneSynthesizer.wavData(for: self))
    }
}

/// Plays alert sounds at the volume chosen in Settings. Holds the sound that is playing,
/// because an `NSSound` that is released stops.
enum AlertSoundPlayer {
    /// The sound currently playing, kept alive until the next one starts.
    private static var current: NSSound?

    /// Plays `sound` at `volume` (0–1, relative to the Mac's own volume), stopping any sound
    /// this player started before.
    static func play(_ sound: AlertSound, volume: Double) {
        current?.stop()
        guard let nsSound = sound.makeSound() else { return }
        nsSound.volume = Float(min(max(volume, 0), 1))
        nsSound.play()
        current = nsSound
    }

    /// Plays the sound and volume chosen in Settings; used by alerts and Test Alert.
    static func play(settings: SettingsStore) {
        play(settings.alertSound, volume: settings.alertVolume)
    }
}

/// Builds the synthesized ringing sounds as 16-bit mono PCM WAV data. Pure, so the output
/// can be checked in tests.
enum ToneSynthesizer {
    /// Samples per second of the generated audio.
    static let sampleRate = 44_100

    /// One stretch of the pattern: a mix of sine frequencies (empty for silence), optionally
    /// trilled on and off `trillHz` times a second, lasting `seconds`.
    struct Segment {
        var frequencies: [Double]
        var seconds: Double
        var trillHz: Double = 0
    }

    /// The pattern for a synthesized sound; empty for system sounds.
    static func segments(for sound: AlertSound) -> [Segment] {
        switch sound {
        case .phoneRing:
            let ring = Segment(frequencies: [400, 450], seconds: 0.4, trillHz: 20)
            let gap = Segment(frequencies: [], seconds: 0.2)
            return [ring, gap, ring, Segment(frequencies: [], seconds: 0.6), ring, gap, ring]
        case .alarmClock:
            let beep = Segment(frequencies: [2_600], seconds: 0.07)
            let gap = Segment(frequencies: [], seconds: 0.06)
            let group = [beep, gap, beep, gap, beep, gap, beep]
            return group + [Segment(frequencies: [], seconds: 0.35)] + group + [Segment(frequencies: [], seconds: 0.35)] + group
        case .urgentBeeps:
            let beep = Segment(frequencies: [1_000, 2_000], seconds: 0.14)
            let gap = Segment(frequencies: [], seconds: 0.08)
            return Array(repeating: [beep, gap], count: 7).flatMap { $0 }
        default:
            return []
        }
    }

    /// The pattern as 16-bit samples. Each tone fades in and out over a few milliseconds so it
    /// doesn't click, and mixed frequencies are scaled down so they never clip.
    static func samples(for sound: AlertSound) -> [Int16] {
        let fade = Int(Double(sampleRate) * 0.004)
        var output: [Int16] = []
        for segment in segments(for: sound) {
            let count = Int(Double(sampleRate) * segment.seconds)
            guard !segment.frequencies.isEmpty else {
                output.append(contentsOf: repeatElement(0, count: count))
                continue
            }
            let scale = 0.8 / Double(segment.frequencies.count)
            for index in 0..<count {
                let time = Double(index) / Double(sampleRate)
                var value = segment.frequencies.reduce(0) { $0 + sin(2 * .pi * $1 * time) } * scale
                if segment.trillHz > 0, sin(2 * .pi * segment.trillHz * time) < 0 {
                    value = 0
                }
                let envelope = min(1, Double(min(index, count - 1 - index)) / Double(max(fade, 1)))
                output.append(Int16(value * envelope * Double(Int16.max)))
            }
        }
        return output
    }

    /// The sound as a complete WAV file in memory, for `NSSound(data:)`.
    static func wavData(for sound: AlertSound) -> Data {
        let samples = samples(for: sound)
        let dataSize = UInt32(samples.count * 2)
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(littleEndian: 36 + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        data.append(littleEndian: UInt32(16))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: UInt32(sampleRate * 2))
        data.append(littleEndian: UInt16(2))
        data.append(littleEndian: UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        data.append(littleEndian: dataSize)
        samples.withUnsafeBufferPointer { buffer in
            for sample in buffer {
                data.append(littleEndian: sample)
            }
        }
        return data
    }
}

private extension Data {
    /// Appends a fixed-width integer in little-endian byte order, as WAV headers need.
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
