// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 4,
      let outPixels = Int(arguments[3]), outPixels > 0 else {
    fail("usage: MakeMark <source> <output.png> <pixels> [radiusFraction] [edgeTrimPx]")
}
let sourcePath = arguments[1]
let outputPath = arguments[2]
let radiusFraction = arguments.count > 4 ? (Double(arguments[4]) ?? 0.225) : 0.225
let edgeTrim = arguments.count > 5 ? (Int(arguments[5]) ?? 2) : 2
guard radiusFraction > 0, radiusFraction < 0.5 else {
    fail("radiusFraction must be between 0 and 0.5")
}
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("cannot read " + sourcePath)
}
let artWidth = artwork.width
let artHeight = artwork.height
guard artWidth > 2 * edgeTrim + 4, artHeight > 2 * edgeTrim + 4 else {
    fail("artwork too small to trim " + String(edgeTrim) + "px per edge")
}

var sourcePixels = [UInt8](repeating: 0, count: artWidth * artHeight * 4)
guard let sourceContext = CGContext(
    data: &sourcePixels,
    width: artWidth,
    height: artHeight,
    bitsPerComponent: 8,
    bytesPerRow: artWidth * 4,
    space: sRGB,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fail("cannot create source context")
}
sourceContext.interpolationQuality = .high
sourceContext.draw(artwork, in: CGRect(x: 0, y: 0, width: artWidth, height: artHeight))

func sourcePixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let i = (y * artWidth + x) * 4
    return (Int(sourcePixels[i]), Int(sourcePixels[i + 1]), Int(sourcePixels[i + 2]))
}
func hex(_ c: (Int, Int, Int)) -> String {
    return String(format: "#%02X%02X%02X", c.0, c.1, c.2)
}
func line(_ parts: [String]) {
    print(parts.joined())
}
func number(_ value: Double, _ places: Int) -> String {
    return String(format: "%." + String(places) + "f", value)
}

let side = min(artWidth, artHeight) - 2 * edgeTrim
let originX = (artWidth - side) / 2
let originY = (artHeight - side) / 2
let cropRect = CGRect(x: originX, y: originY, width: side, height: side)
guard let cropped = artwork.cropping(to: cropRect) else {
    fail("cannot crop to " + String(side) + "px square")
}

let field = sourcePixel(originX + side / 2, originY + 4)
let fieldLuma = 0.2126 * Double(field.0) + 0.7152 * Double(field.1) + 0.0722 * Double(field.2)
var palestBorder = 0.0
let edgeSamples = [(originX, originY + side / 2), (originX + side - 1, originY + side / 2),
                   (originX + side / 2, originY), (originX + side / 2, originY + side - 1)]
for (x, y) in edgeSamples {
    let c = sourcePixel(x, y)
    let luma = 0.2126 * Double(c.0) + 0.7152 * Double(c.1) + 0.0722 * Double(c.2)
    palestBorder = max(palestBorder, luma - fieldLuma)
}

let supersample = 4
let big = outPixels * supersample
guard let maskContext = CGContext(
    data: nil,
    width: big,
    height: big,
    bitsPerComponent: 8,
    bytesPerRow: big * 4,
    space: sRGB,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fail("cannot create mask context")
}
maskContext.interpolationQuality = .high
maskContext.setAllowsAntialiasing(true)
let radius = CGFloat(radiusFraction) * CGFloat(big)
maskContext.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: big, height: big),
                           cornerWidth: radius, cornerHeight: radius, transform: nil))
maskContext.clip()
maskContext.draw(cropped, in: CGRect(x: 0, y: 0, width: big, height: big))
guard let maskedBig = maskContext.makeImage() else {
    fail("cannot snapshot mask context")
}

guard let out = CGContext(
    data: nil,
    width: outPixels,
    height: outPixels,
    bitsPerComponent: 8,
    bytesPerRow: outPixels * 4,
    space: sRGB,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fail("cannot create output context")
}
out.interpolationQuality = .high
out.draw(maskedBig, in: CGRect(x: 0, y: 0, width: outPixels, height: outPixels))

guard let image = out.makeImage() else {
    fail("cannot snapshot output context")
}
guard let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outputPath) as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fail("cannot open destination " + outputPath)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fail("cannot write png")
}

if let buffer = out.data {
    let base = buffer.assumingMemoryBound(to: UInt8.self)
    var minX = outPixels, maxX = -1, minY = outPixels, maxY = -1
    var cornerOpaque = 0
    var coverage = 0
    for y in 0..<outPixels {
        for x in 0..<outPixels {
            let a = Int(base[(y * outPixels + x) * 4 + 3])
            if a > 8 {
                coverage += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
            let cornerBlock = 4
            let inX = x < cornerBlock || x >= outPixels - cornerBlock
            let inY = y < cornerBlock || y >= outPixels - cornerBlock
            if inX && inY && a > 8 { cornerOpaque += 1 }
        }
    }
    func outPixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * outPixels + x) * 4
        return (Int(base[i]), Int(base[i + 1]), Int(base[i + 2]))
    }
    let tileRed = outPixel(outPixels / 2, outPixels / 8)
    let redDelta = abs(tileRed.0 - field.0) + abs(tileRed.1 - field.1) + abs(tileRed.2 - field.2)
    let expectedCoverage = 1.0 - (4.0 - Double.pi) * radiusFraction * radiusFraction

    line(["MakeMark: ", String(artWidth), "x", String(artHeight), " artwork -> ", String(outPixels), "px tile"])
    line(["  squared ", String(side), "px inside a ", String(edgeTrim), "px trim, radius ",
          number(radiusFraction, 3), " = ", number(Double(outPixels) * radiusFraction, 1), "px"])
    line(["  source field ", hex(field), ", palest border sample ",
          number(palestBorder, 1), " luma above the field (0 = no pale hairline)"])
    line(["  tile ink box x ", String(minX), "...", String(maxX), " y ", String(minY), "...", String(maxY),
          ", alpha coverage ", number(100.0 * Double(coverage) / Double(outPixels * outPixels), 1),
          "% (rounded square = ", number(100.0 * expectedCoverage, 1), "%)"])
    line(["  extreme-corner opaque pixels ", String(cornerOpaque), " (0 = corners are cut)"])
    line(["  tile red ", hex(tileRed), " vs source ", hex(field), " -> delta ", String(redDelta)])
    if palestBorder > 6 || cornerOpaque > 0 || redDelta > 3 {
        fail("readback out of tolerance")
    }
}
print("wrote " + outputPath + " (" + String(outPixels) + "x" + String(outPixels) + ")")
