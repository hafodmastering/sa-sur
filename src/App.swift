// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

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
            // the bundle, so the group is replaced by one item that opens the
            // manual the app ships with.
            CommandGroup(replacing: .help) {
                Button("SA-Sur User Manual") { Manual.open() }
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
