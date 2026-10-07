// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import Foundation

enum NoteMath {
    static let noteNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"]
    static let octaves = Array(0...8)

    static func midiNumber(octave: Int, semitone: Int) -> Int {
        (octave + 1) * 12 + semitone
    }

    static func frequency(midi: Int, a4: Double) -> Double {
        a4 * pow(2.0, Double(midi - 69) / 12.0)
    }

    static func frequency(octave: Int, semitone: Int, a4: Double = 440.0) -> Double {
        frequency(midi: midiNumber(octave: octave, semitone: semitone), a4: a4)
    }

    static func label(octave: Int, semitone: Int) -> String {
        noteNames[semitone] + String(octave)
    }

    static func formatted(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(max(0, min(6, decimals)))f", value)
    }
}
