// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import AVFoundation
import Foundation

var failures = 0
var checks = 0

func check(_ label: String, _ actual: Double, _ expected: Double, tol: Double) {
    checks += 1
    let delta = abs(actual - expected)
    if delta <= tol {
        print("PASS  \(label)  got \(actual)  expected \(expected) ± \(tol)")
    } else {
        failures += 1
        print("FAIL  \(label)  got \(actual)  expected \(expected) ± \(tol)  (delta \(delta))")
    }
}

func checkTrue(_ label: String, _ condition: Bool, detail: String) {
    checks += 1
    if condition {
        print("PASS  \(label)  \(detail)")
    } else {
        failures += 1
        print("FAIL  \(label)  \(detail)")
    }
}

func measure(_ samples: [Float], skip: Int, sampleRate: Double) -> (freq: Double, peak: Double) {
    var crossings: [Double] = []
    var peak = 0.0
    var previous = 0.0
    for index in skip..<samples.count {
        let value = Double(samples[index])
        peak = max(peak, abs(value))
        if index > skip, previous < 0, value >= 0 {
            let fraction = previous == value ? 0 : (-previous) / (value - previous)
            crossings.append(Double(index - 1) + fraction)
        }
        previous = value
    }
    guard crossings.count >= 2, let first = crossings.first, let last = crossings.last, last > first else {
        return (0, peak)
    }
    return (Double(crossings.count - 1) / (last - first) * sampleRate, peak)
}

print("=== A. Offline render through the live AVAudioEngine graph ===")
check("app output ceiling is the halved headroom", ToneGenerator.headroom, 0.11, tol: 1e-12)
checkTrue("full slider maps to the old mid-slider level", abs(ToneGenerator.headroom - 0.22 * 0.5) < 1e-12,
          detail: "headroom \(ToneGenerator.headroom) == 0.22 * 0.5")
print("")

let expectedGain = ToneGenerator.headroom
let targets: [(name: String, hz: Double)] = [
    ("C2", 65.40639132514966),
    ("A4", 440.0),
    ("Bb4 (466.1638)", 466.1637615180899),
    ("B8 (7902.13)", 7902.132820075085),
]

for (name, hz) in targets {
    let tone = ToneGenerator()
    tone.setFrequency(hz)
    guard let rendered = tone.measureOffline(seconds: 2.0, gain: expectedGain) else {
        failures += 1
        checks += 1
        print("FAIL  \(name): offline render returned nothing")
        continue
    }
    let left = measure(rendered.left, skip: Int(rendered.sampleRate * 0.05), sampleRate: rendered.sampleRate)
    let rightEmpty = rendered.right.count == rendered.left.count
    var identical = rightEmpty
    if rightEmpty {
        for index in 0..<rendered.left.count where rendered.left[index] != rendered.right[index] {
            identical = false
            break
        }
    }
    print("  \(name): \(rendered.left.count) frames @ \(Int(rendered.sampleRate)) Hz, \(rendered.channels) ch, measured \(String(format: "%.5f", left.freq)) Hz, peak \(String(format: "%.6f", left.peak))")
    check("\(name) graph output frequency", left.freq, hz, tol: max(0.01, hz * 1e-5))
    check("\(name) graph output level", left.peak, expectedGain, tol: 0.001)
    checkTrue("\(name) both channels identical", identical, detail: "\(rendered.right.count) frames on right")
    checkTrue("\(name) rendered the requested duration", rendered.left.count == Int(rendered.sampleRate * 2.0), detail: "\(rendered.left.count) frames")
    tone.shutdown()
}

print("\n=== B. Device mode: engine starts, retunes, stops (silent) ===")
do {
    let tone = ToneGenerator()
    tone.volume = 0.0
    tone.resumeDeviceMode()
    print("  configured sample rate: \(Int(tone.configuredSampleRate)) Hz")

    tone.setFrequency(440)
    tone.start()
    usleep(400_000)
    checkTrue("engine running after start", tone.engineIsRunning && tone.isRunning, detail: "engineIsRunning=\(tone.engineIsRunning) isRunning=\(tone.isRunning)")

    tone.setFrequency(739.988845423269)
    usleep(300_000)
    checkTrue("engine survives a retune", tone.engineIsRunning && tone.isRunning, detail: "engineIsRunning=\(tone.engineIsRunning)")

    tone.stop()
    usleep(200_000)
    checkTrue("engine still alive after stop (gain is zero, not a device teardown)", tone.engineIsRunning && !tone.isRunning, detail: "engineIsRunning=\(tone.engineIsRunning) isRunning=\(tone.isRunning)")

    tone.start()
    usleep(200_000)
    checkTrue("re-starts cleanly after stop", tone.engineIsRunning && tone.isRunning, detail: "engineIsRunning=\(tone.engineIsRunning)")

    tone.shutdown()
    usleep(300_000)
    checkTrue("engine released on shutdown", !tone.engineIsRunning, detail: "engineIsRunning=\(tone.engineIsRunning)")
}

print("\n---------------------------------------------")
print("checks: \(checks), failures: \(failures)")
if failures > 0 {
    print("AUDIO SMOKE: FAIL")
    exit(1)
}
print("AUDIO SMOKE: PASS")
