// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import CoreGraphics
import Foundation
import ImageIO

for path in CommandLine.arguments.dropFirst() {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        print("\(path): cannot read")
        continue
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
    ) else {
        print("\(path): cannot make context")
        continue
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var minX = width, minY = height, maxX = -1, maxY = -1
    var opaqueCount = 0
    for y in 0..<height {
        for x in 0..<width {
            let alpha = pixels[(y * width + x) * 4 + 3]
            if alpha > 8 {
                opaqueCount += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX >= minX, maxY >= minY else {
        print("\(path): fully transparent")
        continue
    }
    let inkWidth = maxX - minX + 1
    let inkHeight = maxY - minY + 1
    let name = (path as NSString).lastPathComponent
    print("""
    \(name)
      canvas      \(width) x \(height)
      ink box     x \(minX)...\(maxX), y \(minY)...\(maxY)  (\(inkWidth) x \(inkHeight))
      padding     left \(minX)  right \(width - 1 - maxX)  top \(minY)  bottom \(height - 1 - maxY)
      ink ratio   \(String(format: "%.3f", Double(inkWidth) / Double(inkHeight))) w/h  (canvas \(String(format: "%.3f", Double(width) / Double(height))))")
      coverage    \(String(format: "%.1f", 100.0 * Double(opaqueCount) / Double(width * height)))% of canvas is ink
    """)
}
