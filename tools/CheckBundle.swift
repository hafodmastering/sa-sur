// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import AppKit
import Foundation

let appPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/SA-Sur.app"
var problems = 0

func check(_ label: String, _ passed: Bool, _ detail: String) {
    print("  \(passed ? "OK  " : "FAIL")  \(label): \(detail)")
    if !passed { problems += 1 }
}

guard let bundle = Bundle(path: appPath) else {
    print("FAIL  cannot open \(appPath) as a bundle")
    exit(1)
}

print("bundle: \(appPath)")

let info = bundle.infoDictionary ?? [:]
check("CFBundleIdentifier", info["CFBundleIdentifier"] as? String == "com.hafodsudeep.sasur",
      info["CFBundleIdentifier"] as? String ?? "missing")
check("CFBundleShortVersionString", (info["CFBundleShortVersionString"] as? String)?.isEmpty == false,
      info["CFBundleShortVersionString"] as? String ?? "missing")
check("LSMinimumSystemVersion", info["LSMinimumSystemVersion"] as? String == "13.0",
      info["LSMinimumSystemVersion"] as? String ?? "missing")

for name in ["sudeep-audio", "hafod-mastering"] {
    guard let url = bundle.url(forResource: name, withExtension: "png") else {
        check("resource \(name)", false, "not found by name")
        continue
    }
    guard let image = NSImage(contentsOf: url) else {
        check("resource \(name)", false, "found at \(url.path) but did not decode")
        continue
    }
    let rep = image.representations.first
    let pixels = "\(rep?.pixelsWide ?? 0)x\(rep?.pixelsHigh ?? 0) px"
    var bytes = 0
    if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
       let size = attributes[.size] as? Int {
        bytes = size
    }
    check("resource \(name)", image.size.width > 0, "\(pixels), drawn \(Int(image.size.width))x\(Int(image.size.height)) pt, \(bytes) bytes")
}

let iconPath = bundle.bundlePath + "/Contents/Resources/AppIcon.icns"
check("AppIcon.icns", FileManager.default.fileExists(atPath: iconPath),
      FileManager.default.fileExists(atPath: iconPath) ? "present" : "missing")

if let executable = bundle.executableURL {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: executable.path, isDirectory: &isDirectory)
    check("executable", exists && !isDirectory.boolValue, executable.lastPathComponent)
} else {
    check("executable", false, "CFBundleExecutable did not resolve")
}

print(problems == 0 ? "BUNDLE CHECK: PASS" : "BUNDLE CHECK: FAIL (\(problems) problem(s))")
exit(problems == 0 ? 0 : 1)
