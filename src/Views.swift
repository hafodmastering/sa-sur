// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import AppKit
import SwiftUI

// MARK: - Reusable note button

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

// MARK: - Studio marks

/// Loads the logos. In the shipped app they sit in Contents/Resources (copied
/// there by build.sh); the offscreen snapshot harness has no bundle of its own,
/// so it points SASUR_LOGOS at a staged directory instead.
enum Branding {
    /// Reverted to the original size on request - bigger (72 pt) filled more of the
    /// space but read as heavy next to the readout. The layout still anchors them
    /// bottom-right, so this is the only number to change to resize them.
    static let logoHeight: CGFloat = 44

    /// Space either side of the collaboration's "+". Kept deliberately tight - the
    /// three read as one lockup, not as three things with gaps between them.
    static let logoGap: CGFloat = 4

    /// The collaboration's "+" reads as a connector, not a third brand, so it is
    /// drawn rather than staged as an asset - and at text size, on the marks' centre.
    static let plusPointSize: CGFloat = 13

    /// Sampled from Sudeep Audio's supplied artwork (#DD3938 in sRGB) so the
    /// connector agrees with the tile it sits beside.
    static let sudeepRed = Color(red: 0xDD / 255.0, green: 0x39 / 255.0, blue: 0x38 / 255.0)

    /// The studios' own sites; the marks are links to them.
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

/// Both marks are the studios' own self-contained colour artwork (Sudeep Audio's
/// supplied flat tile, Hafod's transparent wordmark) rather than dark or light
/// ink, so the same PNG is correct in light and dark appearance and must not be
/// tinted: recolouring them would misstate the brands' colours.
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
            // Push/pop in pairs and track it, so a window that loses focus mid-hover
            // cannot leave the pointing hand stuck on the cursor stack.
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

// MARK: - Appearance

/// The app follows the system appearance unless asked otherwise; the footer's
/// button cycles System -> Light -> Dark. Setting it on NSApp rather than with
/// SwiftUI's preferredColorScheme takes the title bar along with the content.
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

// MARK: - Main view

struct ContentView: View {
    @StateObject private var tone = ToneGenerator()

    @State private var semitone = 9          // A
    @State private var octave = 4            // A4, so the default readout is 440.00
    @State private var a4 = 440.0
    @State private var decimals = 2
    @State private var copied = false

    /// The appearance choice is the app's only stored preference; it survives a
    /// relaunch, which is what makes the button worth having.
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
            // Anchored to the bottom-right of the space beside the octave row and the
            // readout, so enlarging the marks expands them up and to the left into the
            // room the shorter octave row leaves. As an overlay it cannot push the
            // layout around: this region's size is fixed by the rows themselves.
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

    // MARK: Sections

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

    /// Hafod Mastering's mark, the collaboration's "+", then Sudeep Audio's - the
    /// running order the collaboration is written in everywhere else. Both marks
    /// link to their studio's site. Bottom-right of the space opposite the readout.
    ///
    /// Hafod's wordmark carries its own transparent margin on the left, which read
    /// as a gap between it and the "+" when it sat to the right of it: the swap
    /// puts the wordmark's tight edge against the "+" and the tile - whose ink runs
    /// to its own edge - on the other side, so the "+" looks centred without being
    /// nudged off the marks' axis.
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

            // Only the appearance control works as a bare icon; "Concert A" and
            // "Decimals" need their words, so the row keeps its labels and the
            // spacing does the work of fitting the appearance button in.
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

    // MARK: Actions

    /// Clicking a note only selects it. The tone starts and stops solely from the
    /// Play/Stop button (or Space), so browsing the keyboard stays silent.
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
