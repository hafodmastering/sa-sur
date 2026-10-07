// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count >= 5,
      let path = arguments.dropFirst().first,
      let topFraction = Double(arguments[2]),
      let bottomFraction = Double(arguments[3]),
      let minXFraction = Double(arguments[4]) else {
    FileHandle.standardError.write("usage: MeasureRender <png> <topFrac> <bottomFrac> <minXFrac>\n".data(using: .utf8)!)
    exit(2)
}

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
    exit(1)
}

let width = image.width
let height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let index = (y * width + x) * 4
    return (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
}

let background = rgb(4, 4)
func isBackground(_ x: Int, _ y: Int) -> Bool {
    let colour = rgb(x, y)
    return abs(colour.0 - background.0) <= 6
        && abs(colour.1 - background.1) <= 6
        && abs(colour.2 - background.2) <= 6
}

let bandTop = Int(Double(height) * topFraction)
let bandBottom = Int(Double(height) * bottomFraction)
let minX = Int(Double(width) * minXFraction)

var columnHasInk = [Bool](repeating: false, count: width)
var rowHasInk = [Bool](repeating: false, count: height)
for y in bandTop..<bandBottom {
    for x in minX..<width where !isBackground(x, y) {
        columnHasInk[x] = true
        rowHasInk[y] = true
    }
}

let scale = 2.0 // the snapshot harness renders at 2x

do {
    var rowHasAnyInk = [Bool](repeating: false, count: height)
    var rowMinX = [Int](repeating: width, count: height)
    var rowMaxX = [Int](repeating: -1, count: height)
    for y in bandTop..<bandBottom {
        for x in 0..<width where !isBackground(x, y) {
            rowHasAnyInk[y] = true
            if x < rowMinX[y] { rowMinX[y] = x }
            if x > rowMaxX[y] { rowMaxX[y] = x }
        }
    }
    var rowBlocks: [(start: Int, end: Int)] = []
    var runStart: Int? = nil
    for y in bandTop..<bandBottom {
        if rowHasAnyInk[y] {
            if runStart == nil { runStart = y }
        } else if let start = runStart {
            rowBlocks.append((start, y - 1))
            runStart = nil
        }
    }
    if let start = runStart { rowBlocks.append((start, bandBottom - 1)) }
    print("  row bands (px, then pt from the top of the image):")
    for (index, block) in rowBlocks.enumerated() {
        var minXSeen = width
        var maxXSeen = -1
        for y in block.start...block.end {
            if rowMinX[y] < minXSeen { minXSeen = rowMinX[y] }
            if rowMaxX[y] > maxXSeen { maxXSeen = rowMaxX[y] }
        }
        print("    r\(index + 1)  y \(block.start)...\(block.end)  = \(String(format: "%.1f", Double(block.start) / scale))..."
              + "\(String(format: "%.1f", Double(block.end) / scale)) pt  (\(String(format: "%.1f", Double(block.end - block.start + 1) / scale)) pt tall)"
              + "   x \(minXSeen)...\(maxXSeen) = \(String(format: "%.1f", Double(maxXSeen) / scale)) pt right-most")
    }
}

var blocks: [(start: Int, end: Int)] = []
var current: Int? = nil
for x in minX..<width {
    if columnHasInk[x] {
        if current == nil { current = x }
    } else if let start = current {
        blocks.append((start, x - 1))
        current = nil
    }
}
if let start = current { blocks.append((start, width - 1)) }

var inkTop = -1
var inkBottom = -1
for y in bandTop..<bandBottom where rowHasInk[y] {
    if inkTop < 0 { inkTop = y }
    inkBottom = y
}

print("\(path)")
print("  image \(width) x \(height) px   background rgb\(background)   band y \(bandTop)...\(bandBottom)")
print("  ink block vertical extent: y \(inkTop)...\(inkBottom)  -> \(String(format: "%.1f", Double(inkBottom - inkTop + 1) / scale)) pt tall")
if blocks.isEmpty {
    print("  no ink found in that region")
} else {
    print("  horizontal blocks (px, then pt): px->pt at 2x")
    for (index, block) in blocks.enumerated() {
        let w = block.end - block.start + 1
        var blockTop = -1
        var blockBottom = -1
        for y in bandTop..<bandBottom {
            var hasInk = false
            for x in block.start...block.end where !isBackground(x, y) {
                hasInk = true
                break
            }
            if hasInk {
                if blockTop < 0 { blockTop = y }
                blockBottom = y
            }
        }
        let centre = Double(blockTop + blockBottom) / 2.0
        print("    #\(index + 1)  x \(block.start)...\(block.end)  \(w) px = \(String(format: "%.1f", Double(w) / scale)) pt wide"
              + "   |  y \(blockTop)...\(blockBottom) = \(String(format: "%.1f", Double(blockBottom - blockTop + 1) / scale)) pt tall"
              + "   |  vertical centre \(String(format: "%.1f", centre / scale)) pt")
    }
    var previousEnd: Int? = nil
    for block in blocks {
        if let end = previousEnd {
            print("    gap between blocks: \(block.start - end - 1) px = \(String(format: "%.1f", Double(block.start - end - 1) / scale)) pt")
        }
        previousEnd = block.end
    }
    let last = blocks[blocks.count - 1]
    print("  right-most ink edge: x \(last.end) px   (\(String(format: "%.1f", Double(width - 1 - last.end) / scale)) pt of margin to the image edge)")
}
