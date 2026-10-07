// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import Foundation

/// Phase-continuous sine with a smoothed gain envelope; no AVFoundation, so it renders offline for measurement.
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

    // Plain double stores and per-sample gain smoothing: the audio thread takes no lock.
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
