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
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
