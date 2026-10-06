// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import CoreGraphics
import Foundation

// Lists on-screen windows owned by a given app, for screenshotting.
// usage: ListWindows [ownerSubstring]

let needle = (CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "sa-sur").lowercased()
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.lowercased().contains(needle) else { continue }
    let number = window[kCGWindowNumber as String] as? Int ?? 0
    let name = window[kCGWindowName as String] as? String ?? ""
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let layer = window[kCGWindowLayer as String] as? Int ?? -999
    print("WINDOW|\(number)|\(owner)|\(name)|layer=\(layer)|\(bounds)")
}
