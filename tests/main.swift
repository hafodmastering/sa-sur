// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

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

func checkEqual(_ label: String, _ actual: Int, _ expected: Int) {
    checks += 1
    if actual == expected {
        print("PASS  \(label)  got \(actual)")
    } else {
        failures += 1
        print("FAIL  \(label)  got \(actual)  expected \(expected)")
    }
}

print("=== 1. Anchor points ===")
check("A4 = 440", NoteMath.frequency(midi: 69, a4: 440), 440.0, tol: 1e-9)
check("C4 (261.6256)", NoteMath.frequency(octave: 4, semitone: 0, a4: 440), 261.6255653005986, tol: 1e-9)
check("C0 (16.3516)", NoteMath.frequency(octave: 0, semitone: 0, a4: 440), 16.351597831287414, tol: 1e-9)
check("C2 (65.4064)", NoteMath.frequency(octave: 2, semitone: 0, a4: 440), 65.40639132514966, tol: 1e-9)
checkEqual("C4 -> MIDI 60", NoteMath.midiNumber(octave: 4, semitone: 0), 60)
checkEqual("A4 -> MIDI 69", NoteMath.midiNumber(octave: 4, semitone: 9), 69)
checkEqual("C0 -> MIDI 12", NoteMath.midiNumber(octave: 0, semitone: 0), 12)

print("\n=== 2. Octave = exact doubling ===")
for o in 0..<8 {
    let low = NoteMath.frequency(octave: o, semitone: 9, a4: 440)
    let high = NoteMath.frequency(octave: o + 1, semitone: 9, a4: 440)
    check("A\(o) -> A\(o + 1) doubles", high / low, 2.0, tol: 1e-12)
}

print("\n=== 3. Semitone ratio = 2^(1/12) ===")
let ratio = NoteMath.frequency(octave: 4, semitone: 10, a4: 440) / NoteMath.frequency(octave: 4, semitone: 9, a4: 440)
check("Bb4 / A4", ratio, pow(2.0, 1.0 / 12.0), tol: 1e-12)

print("\n=== 4. A4 presets ===")
check("A4 at 432", NoteMath.frequency(octave: 4, semitone: 9, a4: 432), 432.0, tol: 1e-9)
check("C4 at 432", NoteMath.frequency(octave: 4, semitone: 0, a4: 432), 432.0 * pow(2.0, -9.0 / 12.0), tol: 1e-12)
check("A4 at 415", NoteMath.frequency(octave: 4, semitone: 9, a4: 415), 415.0, tol: 1e-9)
check("A4 at 442", NoteMath.frequency(octave: 4, semitone: 9, a4: 442), 442.0, tol: 1e-9)

print("\n=== 5. Formatter ===")
for (d, expected) in [(0, "262"), (1, "261.6"), (2, "261.63"), (3, "261.626")] {
    let got = NoteMath.formatted(261.6255653005986, decimals: d)
    checks += 1
    if got == expected {
        print("PASS  C4 with \(d) decimals -> \(got)")
    } else {
        failures += 1
        print("FAIL  C4 with \(d) decimals -> \(got), expected \(expected)")
    }
}

print("\n=== 6. Rounded values vs a published note-frequency chart ===")
let published: [Int: [Int]] = [
    0:  [16, 33, 65, 131, 262, 523, 1047, 2093, 4186],   // C
    1:  [17, 35, 69, 139, 277, 554, 1109, 2217, 4435],   // C#
    2:  [18, 37, 73, 147, 294, 587, 1175, 2349, 4699],   // D
    3:  [19, 39, 78, 156, 311, 622, 1245, 2489, 4978],   // Eb
    4:  [21, 41, 82, 165, 330, 659, 1319, 2637, 5274],   // E
    5:  [22, 44, 87, 175, 349, 698, 1397, 2794, 5588],   // F
    6:  [23, 46, 93, 185, 370, 740, 1480, 2960, 5920],   // F#
    7:  [25, 49, 98, 196],                               // G (published rows 0-3 only)
]
let chartErrata: [String: (published: Int, correct: Int)] = [
    "F#2": (published: 93, correct: 92),
    "G0": (published: 25, correct: 24),
]
var chartCompared = 0
var errataSeen = 0
for (semitone, row) in published.sorted(by: { $0.key < $1.key }) {
    for octave in 0..<row.count {
        let label = NoteMath.label(octave: octave, semitone: semitone)
        let mine = Int(NoteMath.formatted(NoteMath.frequency(octave: octave, semitone: semitone, a4: 440), decimals: 0)) ?? Int.min
        let expected = row[octave]
        chartCompared += 1
        checks += 1
        if mine == expected {
            print("PASS  \(label) = \(mine) matches published \(expected)")
        } else if let errata = chartErrata[label], errata.published == expected, errata.correct == mine {
            errataSeen += 1
            print("ERRATUM  \(label) = \(mine); site publishes \(expected) (site value looks rounded from a 1-dp intermediate)")
        } else {
            failures += 1
            print("FAIL  \(label) = \(mine), published \(expected)")
        }
    }
}
print("compared \(chartCompared) published values (\(errataSeen) documented chart errata)")

print("\n=== 7. Full table dump for independent diff (CSV on stdout) ===")
print("@@TABLE@@")
for octave in NoteMath.octaves {
    for semitone in 0..<12 {
        let f = NoteMath.frequency(octave: octave, semitone: semitone, a4: 440)
        print("\(NoteMath.label(octave: octave, semitone: semitone)),\(NoteMath.formatted(f, decimals: 6))")
    }
}
print("@@END@@")

print("\n=== 8. Oscillator: measured frequency, envelope, clicks ===")

func measure(_ buf: UnsafeMutablePointer<Float>, count: Int, from: Int, sampleRate: Double) -> (freq: Double, cycleCount: Int, peak: Double) {
    var crossings: [Double] = []
    var peak = 0.0
    for n in from..<count {
        let v = Double(buf[n])
        peak = max(peak, abs(v))
        if n > from {
            let prev = Double(buf[n - 1])
            if prev < 0 && v >= 0 {
                let frac = prev == v ? 0 : (-prev) / (v - prev)
                crossings.append(Double(n - 1) + frac)
            }
        }
    }
    guard crossings.count >= 2, let first = crossings.first, let last = crossings.last, last > first else {
        return (0, crossings.count, peak)
    }
    let freq = Double(crossings.count - 1) / (last - first) * sampleRate
    return (freq, crossings.count, peak)
}

let detuneTargets: [(name: String, hz: Double)] = [
    ("C2 65.4064", NoteMath.frequency(octave: 2, semitone: 0, a4: 440)),
    ("A4 440", 440.0),
    ("F#5 739.9888", NoteMath.frequency(octave: 5, semitone: 6, a4: 440)),
    ("C0 16.3516", NoteMath.frequency(octave: 0, semitone: 0, a4: 440)),
    ("B8 7902.13", NoteMath.frequency(octave: 8, semitone: 11, a4: 440)),
]

let sampleRate = 48000.0
for (name, target) in detuneTargets {
    let osc = SineOscillator(sampleRate: sampleRate)
    osc.frequency = target
    osc.targetGain = 0.22
    let seconds = 5.0
    let count = Int(sampleRate * seconds)
    let buf = UnsafeMutablePointer<Float>.allocate(capacity: count)
    defer { buf.deallocate() }
    osc.render(into: buf, frameCount: count)
    let measured = measure(buf, count: count, from: Int(sampleRate * 0.05), sampleRate: sampleRate)
    print("  \(name): measured \(String(format: "%.5f", measured.freq)) Hz over \(measured.cycleCount) cycles, peak \(String(format: "%.5f", measured.peak))")
    check("\(name) rendered frequency", measured.freq, target, tol: max(0.01, target * 1e-5))
    check("\(name) peak amplitude", measured.peak, 0.22, tol: 0.0005)
}

do {
    let osc = SineOscillator(sampleRate: sampleRate)
    osc.frequency = 440
    osc.targetGain = 0.22
    let count = 480
    let buf = UnsafeMutablePointer<Float>.allocate(capacity: count)
    defer { buf.deallocate() }
    osc.render(into: buf, frameCount: count)
    print("  first 4 samples: \(buf[0]), \(buf[1]), \(buf[2]), \(buf[3])")
    check("first sample is silent (no click)", Double(buf[0]), 0.0, tol: 1e-6)
    var maxStep = 0.0
    for n in 1..<count { maxStep = max(maxStep, abs(Double(buf[n] - buf[n - 1]))) }
    let theoretical = 2.0 * Double.pi * 440.0 / sampleRate * 0.22 * 2.0
    print("  max sample-to-sample step \(String(format: "%.6f", maxStep)), theoretical bound \(String(format: "%.6f", theoretical))")
    check("no start discontinuity", maxStep < theoretical ? 0 : 1, 0, tol: 0)
}

do {
    let osc = SineOscillator(sampleRate: sampleRate)
    osc.frequency = 220
    osc.targetGain = 0.22
    let chunk = 9600
    var buf = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    osc.render(into: buf, frameCount: chunk)
    osc.frequency = 880
    var maxStep = 0.0
    buf = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    osc.render(into: buf, frameCount: chunk)
    for n in 1..<chunk { maxStep = max(maxStep, abs(Double(buf[n] - buf[n - 1]))) }
    let theoretical = 2.0 * Double.pi * 880.0 / sampleRate * 0.22 * 1.5
    print("  max step after 220 -> 880 Hz jump: \(String(format: "%.6f", maxStep)), bound \(String(format: "%.6f", theoretical))")
    check("no discontinuity on pitch change", maxStep < theoretical ? 0 : 1, 0, tol: 0)
    buf.deallocate()
}

do {
    let osc = SineOscillator(sampleRate: sampleRate)
    osc.frequency = 440
    osc.targetGain = 0.22
    let chunk = 48000
    let buf = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    defer { buf.deallocate() }
    osc.render(into: buf, frameCount: chunk)      // fully settled at target gain
    osc.targetGain = 0.0
    osc.render(into: buf, frameCount: chunk)      // the fade region

    func peak(from: Double, to: Double) -> Double {
        var p = 0.0
        for n in Int(sampleRate * from)..<min(chunk, Int(sampleRate * to)) { p = max(p, abs(Double(buf[n]))) }
        return p
    }

    let firstWindow = peak(from: 0, to: 0.005)
    let at50 = peak(from: 0.050, to: 0.100)
    let at100 = peak(from: 0.100, to: 0.200)
    let predicted50 = 0.22 * exp(-0.050 / 0.012)
    print("  peak first 5 ms after stop: \(String(format: "%.6f", firstWindow))")
    print("  peak 50-100 ms after stop:  \(String(format: "%.9f", at50)) (one-pole predicts \(String(format: "%.9f", predicted50)))")
    print("  peak 100-200 ms after stop: \(String(format: "%.9f", at100))")

    check("release follows the 12 ms one-pole", at50, predicted50, tol: predicted50 * 0.25)
    check("fade begins immediately, not an instant cut", (firstWindow > 0.10 && firstWindow <= 0.2201) ? 0 : 1, 0, tol: 0)
    let db50 = 20 * log10(at50 / 0.22)
    print("  level 50-100 ms after stop: \(String(format: "%.1f", db50)) dBFS")
    check("at least 35 dB down 50 ms after stop", db50 < -35 ? 0 : 1, 0, tol: 0)
    check("inaudible (<-66 dB) within 100 ms", at100 < 1e-4 ? 0 : 1, 0, tol: 0)
    check("gain reached zero", osc.gain, 0.0, tol: 1e-9)
}

print("\n=== 9. Nyquist guard ===")
do {
    let osc = SineOscillator(sampleRate: sampleRate)
    osc.frequency = 40000 // absurd input must not alias into the audible band
    osc.targetGain = 0.22
    let count = 48000
    let buf = UnsafeMutablePointer<Float>.allocate(capacity: count)
    defer { buf.deallocate() }
    osc.render(into: buf, frameCount: count)
    let measured = measure(buf, count: count, from: 2400, sampleRate: sampleRate)
    print("  requested 40000 Hz -> measured \(String(format: "%.3f", measured.freq)) Hz")
    check("clamped to 0.45 * sample rate", measured.freq, sampleRate * 0.45, tol: 0.5)
}

print("\n---------------------------------------------")
print("checks: \(checks), failures: \(failures)")
if failures > 0 {
    print("RESULT: FAIL")
    exit(1)
}
print("RESULT: PASS")
