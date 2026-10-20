// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Limited and Sudeep Audio.com LLP

import AppKit
import SwiftUI

@main
struct SASurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("SA-Sur : Note to Frequency") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // The stock Help item does nothing without a help book registered in
            // the bundle, so the group is replaced by the documents the app
            // actually ships with.
            CommandGroup(replacing: .help) {
                Button("SA-Sur User Manual") { Manual.open() }
                Button("Licences and Notices") { Documents.showLicences() }
            }
        }
    }
}

enum Manual {
    /// docs/MANUAL.md rendered to PDF by tools/manual.sh and copied into
    /// Contents/Resources by build.sh. It opens in the reader's own PDF viewer.
    static let resource = "SA-Sur-Manual"

    static func open() {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "pdf") else {
            NSLog("SA-Sur: no \(resource).pdf in the bundle - run tools/manual.sh")
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/// The licence and notice documents the bundle carries, shown in one window.
///
/// A store copy is licensed under the EULA, not Apache-2.0, and the Apache-2.0
/// text and the third-party notices still travel with the build: a reader has to
/// be able to find all of it inside the app, not only in the repository.
enum Documents {
    static let files: [(name: String, heading: String)] = [
        ("EULA.txt", "SA-Sur End User Licence Agreement (this copy)"),
        ("LICENSE", "Apache License 2.0 (the source code)"),
        ("NOTICE", "NOTICE"),
        ("THIRD-PARTY-NOTICES.txt", "Third-party notices"),
        ("OFL.txt", "Nunito - SIL Open Font License 1.1"),
    ]

    private static var window: NSWindow?

    static func licencesText() -> String {
        files.map { file in
            guard let url = Bundle.main.url(forResource: file.name, withExtension: nil),
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else {
                return "\(file.heading)\n\n[This build does not carry \(file.name).]"
            }
            return "\(file.heading)\n\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        .joined(separator: "\n\n" + String(repeating: "-", count: 78) + "\n\n")
    }

    static func showLicences() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let frame = NSRect(x: 0, y: 0, width: 640, height: 580)
        let panel = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "SA-Sur licences"
        panel.isReleasedWhenClosed = false

        let scroll = NSScrollView(frame: frame)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true

        let text = NSTextView(frame: frame)
        text.isEditable = false
        text.isSelectable = true
        text.string = licencesText()
        text.textContainerInset = NSSize(width: 18, height: 18)
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true

        scroll.documentView = text
        panel.contentView = scroll
        panel.center()

        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
