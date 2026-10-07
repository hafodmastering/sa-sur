// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
let topLeftX = centre - inkCentreX * scale
let topLeftY = centre - inkCentreY * scale
let rect = CGRect(
    x: topLeftX,
    y: CGFloat(canvas) - topLeftY - drawHeight,
    width: drawWidth,
    height: drawHeight
)
out.draw(maskedImage, in: rect)

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
