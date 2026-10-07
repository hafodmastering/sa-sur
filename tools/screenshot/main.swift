// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import AppKit
import Foundation
import SwiftUI

let outputScale: CGFloat = 2

let prefix = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ui-snapshot"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
    exit(1)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)

    for (suffix, scheme, appearanceName, mode) in [("dark", ColorScheme.dark, NSAppearance.Name.darkAqua, ThemeMode.dark),
                                                   ("light", ColorScheme.light, NSAppearance.Name.aqua, ThemeMode.light)] {
        UserDefaults.standard.set(mode.rawValue, forKey: "appearance")

        let root = ZStack {
            Color(nsColor: .windowBackgroundColor)
            ContentView()
        }
        .environment(\.colorScheme, scheme)

        let hosting = NSHostingView(rootView: root)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        print("\(suffix): intrinsic content size \(Int(size.width)) x \(Int(size.height)) pt")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearanceName)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let bounds = hosting.bounds
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * outputScale),
            pixelsHigh: Int(bounds.height * outputScale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            fail("cannot allocate bitmap for \(suffix)")
        }
        rep.size = NSSize(width: bounds.width, height: bounds.height)
        hosting.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fail("cannot encode png for \(suffix)")
        }
        let path = "\(prefix)-\(suffix).png"
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            fail("write failed: \(error)")
        }
        print("\(suffix): wrote \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh) px)")
    }
}
