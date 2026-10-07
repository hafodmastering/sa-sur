// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import AppKit
import SwiftUI

struct NoteButton: View {
    let title: String
    let selected: Bool
    let width: CGFloat
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .bold : .medium, design: .rounded))
                .frame(width: width, height: 30)
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected
                              ? Color.accentColor
                              : Color.primary.opacity(hovering ? 0.17 : 0.08))
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

enum Branding {
    // 44 pt; stage-logos.sh stages the PNGs at 176 px for 2x headroom - keep the two in step.
    static let logoHeight: CGFloat = 44

    static let logoGap: CGFloat = 4

    // Deliberate divergence: the Windows port draws its "+" at 18 pt - different glyph metrics.
    static let plusPointSize: CGFloat = 13

    // #DD3938, sampled from the brand tile so the connector agrees with it.
    static let sudeepRed = Color(red: 0xDD / 255.0, green: 0x39 / 255.0, blue: 0x38 / 255.0)

    static let sudeepURL = URL(string: "https://sudeepaudio.com")!
    static let hafodURL = URL(string: "https://hafodmastering.co.uk")!

    static func image(named name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let directory = ProcessInfo.processInfo.environment["SASUR_LOGOS"],
           let image = NSImage(contentsOfFile: "\(directory)/\(name).png") {
            return image
        }
        return nil
    }
}

struct LogoMark: View {
    let name: String
    let url: URL

    @State private var cursorPushed = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            if let image = Branding.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: Branding.logoHeight)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .help(url.host ?? name)
        .accessibilityLabel(name)
        .onHover { inside in
            if inside && !cursorPushed {
                NSCursor.pointingHand.push()
                cursorPushed = true
            } else if !inside && cursorPushed {
                NSCursor.pop()
                cursorPushed = false
            }
        }
    }
}

enum ThemeMode: String {
    case system, light, dark

    var next: ThemeMode {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var help: String {
        switch self {
        case .system: return "Appearance: following the system - click for light"
        case .light: return "Appearance: light - click for dark"
        case .dark: return "Appearance: dark - click to follow the system"
        }
    }
}

struct ContentView: View {
    @StateObject private var tone = ToneGenerator()

    @State private var semitone = 9          // A
    @State private var octave = 4            // A4, so the default readout is 440.00
    @State private var a4 = 440.0
    @State private var decimals = 2
    @State private var copied = false

    @AppStorage("appearance") private var appearanceRaw = ThemeMode.system.rawValue

    private var theme: ThemeMode { ThemeMode(rawValue: appearanceRaw) ?? .system }

    private static let a4Presets: [Double] = [440, 432, 415, 442]

    private var frequency: Double {
        NoteMath.frequency(octave: octave, semitone: semitone, a4: a4)
    }

    private var displayValue: String {
        NoteMath.formatted(frequency, decimals: decimals)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            noteRow
            VStack(alignment: .leading, spacing: 16) {
                octaveRow
                readout
            }
            .overlay(alignment: .bottomTrailing) { brandLogos }
            Divider()
            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .fixedSize()
        .onAppear {
            tone.setFrequency(frequency)
            applyTheme()
        }
        .onDisappear { tone.shutdown() }
    }

    private var noteRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<12, id: \.self) { index in
                NoteButton(
                    title: NoteMath.noteNames[index],
                    selected: index == semitone,
                    width: 48
                ) {
                    select(semitone: index)
                }
            }
        }
    }

    private var octaveRow: some View {
        HStack(spacing: 6) {
            ForEach(NoteMath.octaves, id: \.self) { value in
                NoteButton(
                    title: String(value),
                    selected: value == octave,
                    width: 48
                ) {
                    octave = value
                    applyPitch()
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(displayValue)
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .textSelection(.enabled)
            Text("Hz")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Button {
                copyFrequency()
            } label: {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy \(displayValue) to the clipboard")
            .padding(.leading, 2)
            .offset(y: -6)

            Spacer(minLength: 0)
        }
    }

    private var brandLogos: some View {
        HStack(spacing: Branding.logoGap) {
            LogoMark(name: "hafod-mastering", url: Branding.hafodURL)
            Image(systemName: "plus")
                .font(.system(size: Branding.plusPointSize, weight: .semibold))
                .foregroundStyle(Branding.sudeepRed)
                .accessibilityHidden(true)
            LogoMark(name: "sudeep-audio", url: Branding.sudeepURL)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                tone.toggle()
            } label: {
                Label(tone.isRunning ? "Stop" : "Play",
                      systemImage: tone.isRunning ? "stop.fill" : "play.fill")
                    .frame(minWidth: 58)
            }
            .keyboardShortcut(.space, modifiers: [])
            .help("Start or stop the tone (Space)")

            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(value: $tone.volume, in: 0...1)
                    .frame(width: 96)
            }

            Spacer(minLength: 20)

            Text("Concert A")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Picker("Concert A", selection: $a4) {
                ForEach(Self.a4Presets, id: \.self) { value in
                    Text(NoteMath.formatted(value, decimals: 0)).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 184)
            .onChange(of: a4) { _ in applyPitch() }

            Stepper(value: $decimals, in: 0...6) {
                Text("Decimals: " + String(decimals))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .fixedSize()

            Button {
                cycleTheme()
            } label: {
                Image(systemName: theme.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(theme.help)
            .accessibilityLabel("Appearance")
        }
    }

    private func select(semitone index: Int) {
        semitone = index
        applyPitch()
    }

    private func applyPitch() {
        tone.setFrequency(frequency)
    }

    private func copyFrequency() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(displayValue, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }

    private func cycleTheme() {
        appearanceRaw = theme.next.rawValue
        applyTheme()
    }

    private func applyTheme() {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
