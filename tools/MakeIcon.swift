// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Composes the SA-Sur artwork (a rounded square on a pure-black backdrop) into
// the app icon master and the in-window mark.
//
// usage: MakeIcon <artwork.png> <output.png> <pixels> [grid|full]
//   grid  fits the artwork's silhouette into Apple's macOS icon grid - an 824 pt
//         body centred in the canvas, which is the standard 1024 px master
//   full  fills the whole canvas edge to edge - used for the 176 px app mark
//
// The black backdrop around the artwork is removed by silhouette extraction:
// ink extents are measured row by row, so the artwork's own edge is followed
// exactly. (Its corners are a squircle, not a circular arc, so a geometric
// rounded-rect mask would sit slightly wrong and leave black wedges.)
// CoreGraphics only, so it runs headless from a CLI.

let arguments = CommandLine.arguments
guard arguments.count >= 4,
      let canvas = Int(arguments[3]), canvas > 0 else {
    FileHandle.standardError.write("usage: MakeIcon <artwork.png> <output.png> <pixels> [grid|full]\n".data(using: .utf8)!)
    exit(2)
}
let sourcePath = arguments[1]
let outputPath = arguments[2]
let mode = arguments.count > 4 ? arguments[4] : "grid"
guard mode == "grid" || mode == "full" else {
    FileHandle.standardError.write("mode must be grid or full\n".data(using: .utf8)!)
    exit(2)
}

// --- load the artwork -----------------------------------------------------
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("cannot read \(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}
let width = artwork.width
let height = artwork.height

var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard let readContext = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("cannot create read context\n".data(using: .utf8)!)
    exit(1)
}
readContext.draw(artwork, in: CGRect(x: 0, y: 0, width: width, height: height))

// --- silhouette: per-row ink extents --------------------------------------
// Two sources of truth, chosen once from the artwork itself:
//   alpha    - artwork with a real alpha channel is masked by alpha. Needed for
//              a black tile on transparency, where there is no brightness
//              difference between the tile and the void to measure.
//   brightness - the original case: opaque artwork on a pure-black backdrop,
//              where "ink" is anything brighter than the backdrop (0-1 on a
//              0-255 scale; 20 leaves headroom for compression noise while
//              every pixel of the artwork itself is comfortably above it).
let inkThreshold = 20
var transparentSamples = 0
for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] < 8 {
    transparentSamples += 1
}
let useAlpha = transparentSamples > (width * height) / 100
print(useAlpha
      ? "MakeIcon: silhouette from the artwork's alpha channel (\(transparentSamples) transparent samples)"
      : "MakeIcon: silhouette from brightness (artwork is opaque)")

func isInk(_ x: Int, _ y: Int) -> Bool {
    let index = (y * width + x) * 4
    guard !useAlpha else { return pixels[index + 3] > 8 }
    return max(pixels[index], max(pixels[index + 1], pixels[index + 2])) > UInt8(inkThreshold)
}

var rowMin = [Int](repeating: -1, count: height)
var rowMax = [Int](repeating: -1, count: height)
var minX = width, maxX = -1, minY = height, maxY = -1
for y in 0..<height {
    var low = -1
    var high = -1
    for x in 0..<width where isInk(x, y) {
        if low < 0 { low = x }
        high = x
    }
    rowMin[y] = low
    rowMax[y] = high
    if low >= 0 {
        if low < minX { minX = low }
        if high > maxX { maxX = high }
        if y < minY { minY = y }
        maxY = y
    }
}
guard minX >= 0, minY >= 0, maxX >= minX, maxY >= minY else {
    FileHandle.standardError.write("no ink found in \(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}
let inkWidth = maxX - minX + 1
let inkHeight = maxY - minY + 1

// --- mask: everything outside the silhouette becomes transparent ----------
var masked = [UInt8](repeating: 0, count: width * height * 4)
for y in 0..<height {
    let low = rowMin[y]
    let high = rowMax[y]
    guard low >= 0, high >= low else { continue }
    for x in low...high {
        let index = (y * width + x) * 4
        masked[index] = pixels[index]
        masked[index + 1] = pixels[index + 1]
        masked[index + 2] = pixels[index + 2]
        // Alpha artwork keeps its own coverage, so the tile edge stays
        // antialiased instead of being forced to a hard edge.
        masked[index + 3] = useAlpha ? pixels[index + 3] : 255
    }
}
guard let provider = CGDataProvider(data: Data(masked) as CFData),
      let maskedImage = CGImage(
          width: width,
          height: height,
          bitsPerComponent: 8,
          bitsPerPixel: 32,
          bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
          provider: provider,
          decode: nil,
          shouldInterpolate: true,
          intent: .defaultIntent
      ) else {
    FileHandle.standardError.write("cannot build masked image\n".data(using: .utf8)!)
    exit(1)
}

// --- compose onto the output canvas ---------------------------------------
// grid: Apple's macOS icon grid - body is 824/1024 of the canvas, centred.
// The silhouette is fitted to the body (or the full canvas for the mark),
// its ink centre placed at the canvas centre.
guard let out = CGContext(
    data: nil,
    width: canvas,
    height: canvas,
    bitsPerComponent: 8,
    bytesPerRow: canvas * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("cannot create output context\n".data(using: .utf8)!)
    exit(1)
}
out.setAllowsAntialiasing(true)
out.interpolationQuality = .high

let bodyFraction = 824.0 / 1024.0
let fitSize: CGFloat = mode == "grid"
    ? CGFloat(canvas) * bodyFraction
    : CGFloat(canvas)
let scale: CGFloat = fitSize / CGFloat(max(inkWidth, inkHeight))
let centre = CGFloat(canvas) / 2.0
let inkCentreX = (CGFloat(minX) + CGFloat(maxX) + 1.0) / 2.0
let inkCentreY = (CGFloat(minY) + CGFloat(maxY) + 1.0) / 2.0
let drawWidth = CGFloat(width) * scale
let drawHeight = CGFloat(height) * scale
// Source top-left in canvas top-left coordinates, then flipped for CoreGraphics.
let topLeftX = centre - inkCentreX * scale
let topLeftY = centre - inkCentreY * scale
let rect = CGRect(
    x: topLeftX,
    y: CGFloat(canvas) - topLeftY - drawHeight,
    width: drawWidth,
    height: drawHeight
)
out.draw(maskedImage, in: rect)

// --- write PNG -----------------------------------------------------------
guard let image = out.makeImage() else {
    FileHandle.standardError.write("cannot snapshot context\n".data(using: .utf8)!)
    exit(1)
}
guard let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outputPath) as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    FileHandle.standardError.write("cannot open destination \(outputPath)\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write("cannot write png\n".data(using: .utf8)!)
    exit(1)
}

// --- readback: prove the output's ink sits where it should ---------------
if let buffer = out.data {
    let base = buffer.assumingMemoryBound(to: UInt8.self)
    var ox = canvas, oy = canvas, mx = -1, my = -1
    for y in 0..<canvas {
        for x in 0..<canvas where base[(y * canvas + x) * 4 + 3] > 8 {
            if x < ox { ox = x }
            if x > mx { mx = x }
            if y < oy { oy = y }
            if y > my { my = y }
        }
    }
    print("MakeIcon: \(mode) \(canvas)px from \(width)x\(height) artwork")
    print("  artwork ink box x \(minX)...\(maxX) y \(minY)...\(maxY) (\(inkWidth)x\(inkHeight)), scale \(String(format: "%.4f", scale))")
    if mx >= ox, my >= oy {
        print("  output ink box x \(ox)...\(mx) y \(oy)...\(my)  margins L \(ox) R \(canvas - 1 - mx) T \(oy) B \(canvas - 1 - my)")
    } else {
        print("  output is empty - something went wrong")
        exit(1)
    }
}
print("wrote \(outputPath) (\(canvas)x\(canvas))")
