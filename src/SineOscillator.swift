// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import Foundation

/// Phase-continuous sine oscillator with a smoothed gain envelope.
///
/// Deliberately free of AVFoundation so the DSP can be rendered into a plain
/// buffer and measured by tests instead of only by ear.
///
/// `frequency` and `targetGain` are written from the main thread while `render`
/// runs on the audio thread. Both are plain `Double` stores (individually atomic
/// on arm64 and x86_64) and the gain smoothing absorbs any transient, so no lock
/// is taken on the audio thread.
final class SineOscillator {
    var sampleRate: Double
    var frequency: Double = 440.0
    var targetGain: Double = 0.0

    private(set) var phase: Double = 0.0
    private(set) var gain: Double = 0.0
    private let smoothing: Double

    init(sampleRate: Double, rampSeconds: Double = 0.012) {
        self.sampleRate = sampleRate
        self.smoothing = 1.0 - exp(-1.0 / max(1.0, rampSeconds * sampleRate))
    }

    /// Writes `frameCount` mono samples. Phase and gain carry across calls, so
    /// changing pitch or gain mid-stream stays click-free.
    @inline(__always)
    func render(into out: UnsafeMutablePointer<Float>, frameCount: Int) {
        let nyquist = sampleRate * 0.45
        let inc = min(frequency, nyquist) / sampleRate
        var g = gain
        var p = phase
        let target = targetGain
        let a = smoothing
        for i in 0..<frameCount {
            g += (target - g) * a
            out[i] = Float(sin(2.0 * Double.pi * p) * g)
            p += inc
            if p >= 1.0 { p -= 1.0 }
        }
        gain = g
        phase = p
    }
}
