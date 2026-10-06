// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Prepares the app icon artwork for the Dock: takes Sudeep Audio's supplied
// app artwork (a dark squircle carrying the mark, a thin gold ring, waveform
// bars either side and a "built by Hafod" credit line) and produces the same
// tile with the ring, the waveforms and the credit removed and the mark scaled
// up inside it.
//
// usage: CleanIcon <artwork.png> <output.png> [zoom]
//
// Everything is measured from the supplied artwork rather than eyeballed, and
// the tool re-reads its own output before it exits:
//   * the ring is a circle of radius ~439 px about (630, 592) - it encloses the
//     mark, so it crosses any crop and has to be removed, not cropped away
//   * the waveform bars occupy two fields, x 89-309 and x 955-1163, y 268-927
//     (measured as warm, bright structures; the left field starts 19 px inside
//     the tile edge, so the mask stops short of the artwork's own rim - a mask
//     that eats the border pushes those pixels under MakeIcon's ink threshold
//     and the per-row silhouette extraction then notches the tile)
//   * the credit line sits at x 330-930, y 1025-1155
// Removal is by diffusion (blur, then restore everything outside the mask) so
// the smooth gradient behind the removed graphics is reconstructed rather than
// smeared, which a straight interpolation across a 220 px field would do.
//
// The zoom pastes a scaled copy of the mark over the tile. The paste mask has
// two zones: fully opaque out to 56 px beyond the mark (so no part of the
// lettering is ever half-blended with its un-scaled self, which reads as a
// ghost of the letter) and a ramp beyond that, which only ever crosses empty
// background.
//
// CoreGraphics and Foundation only, so it runs headless from a CLI.

func note(_ message: String) {
    FileHandle.standardError.write(("note: " + message + "\n").data(using: .utf8)!)
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fail("usage: CleanIcon <artwork.png> <output.png> [zoom]") }
let sourcePath = arguments[1]
let outputPath = arguments[2]
let zoom = arguments.count > 3 ? (Double(arguments[3]) ?? 1.25) : 1.25
let debugProbe = ProcessInfo.processInfo.environment["CLEANICON_DEBUG"] != nil

// --- measured geometry of the supplied artwork ----------------------------
let ringCentre = (x: 630.0, y: 592.0)
let ringRadius = 439.0
let ringHalfWidth = 14.0          // ring line plus its immediate glow
let markRegionRadius = 412.0      // the mark and its glow live inside the ring
// Stops 8 px short of the mark (which spans x 310...959) so the feathered mask
// edge below cannot graze the lettering.
let barFields = [(85, 302, 262, 938), (966, 1166, 262, 938)]
let creditLine = (350, 930, 1025, 1155)
let tileEdgeGuard = 20            // never mask the artwork's own border pixels

// --- load the artwork in sRGB --------------------------------------------
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("cannot read " + sourcePath)
}
let width = artwork.width
let height = artwork.height
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("cannot create a " + String(w) + "x" + String(h) + " context")
    }
    context.interpolationQuality = .high
    return context
}

var pixels = [UInt8](repeating: 0, count: width * height * 4)
pixels.withUnsafeMutableBytes { raw in
    guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4, space: sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("cannot create the read context")
    }
    context.draw(artwork, in: CGRect(x: 0, y: 0, width: width, height: height))
}

let count = width * height
func index(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }
func luma(_ i: Int) -> Double {
    0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
}
func luma(_ x: Int, _ y: Int) -> Double { luma(index(x, y)) }
// Both tests take the buffer they are classifying: the masks are built from the
// supplied artwork, the readback checks run against the output.
// Bars are dimmer than the ring's line, so they need a looser test - the same one
// the geometry above was measured with.
func isBarInk(_ buffer: [UInt8], _ x: Int, _ y: Int) -> Bool {
    let i = (y * width + x) * 4
    let r = Double(buffer[i]), g = Double(buffer[i + 1]), b = Double(buffer[i + 2])
    let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return l > 38 && r > b + 12
}
func isWarmInk(_ buffer: [UInt8], _ x: Int, _ y: Int) -> Bool {
    let i = (y * width + x) * 4
    let r = Double(buffer[i]), g = Double(buffer[i + 1]), b = Double(buffer[i + 2])
    let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return l > 52 && r > b + 22
}
func radius(_ x: Int, _ y: Int) -> Double {
    let dx = Double(x) - ringCentre.x, dy = Double(y) - ringCentre.y
    return (dx * dx + dy * dy).squareRoot()
}
func hex(_ i: Int) -> String {
    String(format: "#%02X%02X%02X", pixels[i], pixels[i + 1], pixels[i + 2])
}

// --- the mark: the bright components inside the ring ----------------------
// Four of them - the sa, the macron, the a, and the large Devanagari letter -
// all far wider than the thin waveform fillets that share their band.
var visited = [Bool](repeating: false, count: count)
var markMask = [UInt8](repeating: 0, count: count)
var markMinX = width, markMaxX = -1, markMinY = height, markMaxY = -1
var components = 0
var stack: [Int] = []
for y in 180..<min(1010, height) {
    for x in 250..<min(1010, width) {
        let start = y * width + x
        guard !visited[start], luma(x, y) > 45, radius(x, y) < markRegionRadius else { continue }
        var members: [Int] = []
        stack.removeAll(keepingCapacity: true)
        stack.append(start)
        visited[start] = true
        var minX = x, maxX = x, minY = y, maxY = y
        while let current = stack.popLast() {
            members.append(current)
            let cx = current % width, cy = current / width
            if cx < minX { minX = cx }
            if cx > maxX { maxX = cx }
            if cy < minY { minY = cy }
            if cy > maxY { maxY = cy }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 250, nx < 1010, ny >= 180, ny < 1010 else { continue }
                let neighbour = ny * width + nx
                guard !visited[neighbour], luma(nx, ny) > 45, radius(nx, ny) < markRegionRadius else { continue }
                visited[neighbour] = true
                stack.append(neighbour)
            }
        }
        guard maxX - minX + 1 >= 60 else { continue }
        components += 1
        for member in members { markMask[member] = 255 }
        if minX < markMinX { markMinX = minX }
        if maxX > markMaxX { markMaxX = maxX }
        if minY < markMinY { markMinY = minY }
        if maxY > markMaxY { markMaxY = maxY }
    }
}
note("labelled " + String(components) + " mark components, bbox x " + String(markMinX) + "..." + String(markMaxX) + " y " + String(markMinY) + "..." + String(markMaxY))
guard components == 4, markMaxX > markMinX else {
    fail("expected the mark to be four components, found " + String(components))
}

// --- morphology, by doubling: cheap and exact for a square structuring set --
func expand(_ mask: inout [UInt8], halfWidth: Int) {
    guard halfWidth >= 1 else { return }
    var pass = [UInt8](repeating: 0, count: count)
    for y in 0..<height {
        let row = y * width
        for x in 0..<width {
            var best: UInt8 = mask[row + x]
            if x - halfWidth >= 0 { best = max(best, mask[row + x - halfWidth]) }
            if x + halfWidth < width { best = max(best, mask[row + x + halfWidth]) }
            pass[row + x] = best
        }
    }
    var out = [UInt8](repeating: 0, count: count)
    for y in 0..<height {
        let row = y * width
        for x in 0..<width {
            var best: UInt8 = pass[row + x]
            if y - halfWidth >= 0 { best = max(best, pass[(y - halfWidth) * width + x]) }
            if y + halfWidth < height { best = max(best, pass[(y + halfWidth) * width + x]) }
            out[row + x] = best
        }
    }
    mask = out
}
func dilate(_ mask: [UInt8], radius: Int) -> [UInt8] {
    var out = mask
    var remaining = radius
    var step = 1
    while remaining > 0 {
        let use = min(step, remaining)
        expand(&out, halfWidth: use)
        remaining -= use
        step *= 2
    }
    return out
}

// --- the removal mask -----------------------------------------------------
var removal = [UInt8](repeating: 0, count: count)
let guardBand = dilate(markMask, radius: 24)
note("guard band dilated")
// The whole annulus goes, not just the pixels that read as warm ink: where the
// ring runs across the darker field its lower arc falls below the warmth test
// and a surviving sliver reads as a bright seam across the tile. The band is
// 32 px wide on a smooth gradient, so the reconstruction has nothing to smear.
for y in 0..<height {
    for x in 0..<width {
        let r = radius(x, y)
        guard r > ringRadius - ringHalfWidth - 2, r < ringRadius + ringHalfWidth + 2 else { continue }
        guard guardBand[y * width + x] == 0 else { continue }
        removal[y * width + x] = 255
    }
}
// Waveform bars can also sit *inside* the mark's x-range - x 316-333 and
// x 920-936 in this artwork, tucked against the lettering - where a rectangle
// cannot separate them from it. Those are found by shape instead: warm, tall,
// thin components in the side bands that the mark's own pixels do not account
// for. Without this the zoom carries them outward and they read as fragments of
// waveform stranded beside the letter.
var barMask = [UInt8](repeating: 0, count: count)
var barVisited = [Bool](repeating: false, count: count)
let tightGuard = dilate(markMask, radius: 4)
for (bandX0, bandX1) in [(85, 350), (930, 1180)] {
    for y in 240..<min(960, height) {
        for x in bandX0..<min(bandX1, width) {
            let start = y * width + x
            guard !barVisited[start], isBarInk(pixels, x, y), tightGuard[start] == 0 else { continue }
            var members: [Int] = []
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            barVisited[start] = true
            var minX = x, maxX = x, minY = y, maxY = y
            while let current = stack.popLast() {
                members.append(current)
                let cx = current % width, cy = current / width
                if cx < minX { minX = cx }
                if cx > maxX { maxX = cx }
                if cy < minY { minY = cy }
                if cy > maxY { maxY = cy }
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = cx + dx, ny = cy + dy
                    guard nx >= bandX0, nx < min(bandX1, width), ny >= 240, ny < min(960, height) else { continue }
                    let neighbour = ny * width + nx
                    guard !barVisited[neighbour], isBarInk(pixels, nx, ny), tightGuard[neighbour] == 0 else { continue }
                    barVisited[neighbour] = true
                    stack.append(neighbour)
                }
            }
            let barHeight = maxY - minY + 1
            let barWidth = maxX - minX + 1
            // Thin and tall - and clear of the tile's own edge, which the removal
            // rectangles already cover and the silhouette extraction depends on.
            guard barHeight >= 40, barWidth <= 45, minX >= 100, maxX <= 1160 else { continue }
            for member in members { barMask[member] = 255 }
        }
    }
}
barMask = dilate(barMask, radius: 12)
for p in 0..<count where barMask[p] != 0 { removal[p] = 255 }
note("bar-shaped structures masked")

removal = dilate(removal, radius: 16)
note("ring band masked")
for (x0, x1, y0, y1) in barFields {
    for y in max(0, y0)..<min(height, y1 + 1) {
        for x in max(0, x0)..<min(width, x1 + 1) {
            removal[y * width + x] = 255
        }
    }
}
for y in creditLine.2..<min(height, creditLine.3 + 1) {
    for x in creditLine.0..<min(width, creditLine.1 + 1) {
        removal[y * width + x] = 255
    }
}
// Feather the mask edge by a few pixels. The removed graphics all sit well inside
// the core, so this only softens the step where the reconstructed field meets the
// untouched one - a hard edge reads as a faint straight seam across a dark tile.
removal = blurMask(removal, radius: 4)
// The mark's own pixels are never repainted, whatever the masks above decided.
for p in 0..<count where markMask[p] != 0 { removal[p] = 0 }

// --- diffusion: blur, then restore every pixel outside the mask -----------
func blur(_ buffer: [UInt8], radius: Int) -> [UInt8] {
    var horizontal = [UInt8](repeating: 0, count: count * 4)
    var out = [UInt8](repeating: 0, count: count * 4)
    let window = 2 * radius + 1
    for y in 0..<height {
        let row = y * width
        var sums = [Int](repeating: 0, count: 4)
        for channel in 0..<4 {
            var sum = 0
            for x in -radius...radius {
                let sx = min(max(x, 0), width - 1)
                sum += Int(buffer[(row + sx) * 4 + channel])
            }
            sums[channel] = sum
            for x in 0..<width {
                horizontal[(row + x) * 4 + channel] = UInt8(min(max(sums[channel] / window, 0), 255))
                let leaving = min(max(x - radius, 0), width - 1)
                let entering = min(max(x + radius + 1, 0), width - 1)
                sums[channel] += Int(buffer[(row + entering) * 4 + channel]) - Int(buffer[(row + leaving) * 4 + channel])
            }
        }
    }
    for x in 0..<width {
        var sums = [Int](repeating: 0, count: 4)
        for channel in 0..<4 {
            var sum = 0
            for y in -radius...radius {
                let sy = min(max(y, 0), height - 1)
                sum += Int(horizontal[(sy * width + x) * 4 + channel])
            }
            sums[channel] = sum
            for y in 0..<height {
                out[(y * width + x) * 4 + channel] = UInt8(min(max(sums[channel] / window, 0), 255))
                let leaving = min(max(y - radius, 0), height - 1)
                let entering = min(max(y + radius + 1, 0), height - 1)
                sums[channel] += Int(horizontal[(entering * width + x) * 4 + channel]) - Int(horizontal[(leaving * width + x) * 4 + channel])
            }
        }
    }
    return out
}

note("removal mask built")
var cleaned = pixels
// Multi-scale and wide: one box blur has a support of only +-radius, which is far
// too local to erase what was removed - the bars' own brightness survives as a
// warm streak and the mask's straight edges show as plateaus. Three box passes
// approximate a Gaussian of roughly three times the support, and the small radii
// at the end settle any seam against the boundary.
for radius in [96, 48, 24, 12, 6, 3, 1] {
    note("diffusion radius " + String(radius))
    for _ in 0..<3 {
        let blurred = blur(blur(blur(cleaned, radius: radius), radius: radius), radius: radius)
        for p in 0..<count where removal[p] != 0 {
            let i = p * 4
            let alpha = Double(removal[p]) / 255.0
            for channel in 0..<3 {
                let blended = alpha * Double(blurred[i + channel]) + (1 - alpha) * Double(cleaned[i + channel])
                cleaned[i + channel] = UInt8(max(0, min(255, blended.rounded())))
            }
        }
    }
}

// --- the zoom: two-zone paste mask ---------------------------------------
let hardZone = dilate(markMask, radius: 56)
// The ramp is deliberately long: the scaled mark's own glow extends past the
// lettering, and a short ramp cuts it off as a faint straight edge across the
// dark field. Over ~150 px the fade is gradual enough to disappear.
// Reach is bounded by arithmetic, not taste: the paste is read in the scaled
// frame, so a ramp of r beyond the mark lands at 1040 + 1.25r across the tile.
// Much past 95 px the paste starts rewriting the tile's own rim glow, which
// dims the silhouette edge and makes MakeIcon's ink box shrink.
var rampZone = dilate(markMask, radius: 70)
rampZone = blurMask(rampZone, radius: 25)
var pasteMask = rampZone
for p in 0..<count where hardZone[p] != 0 { pasteMask[p] = 255 }
// No hard outer cutoff: a straight edge on the ramp slices through the mark's own
// scaled glow and lands as a bright line across the tile. The ramp is left to
// fade out on its own, and the body constraint below keeps it off the backdrop.
note("paste mask built")

func sampleBilinear(_ buffer: [UInt8], _ x: Double, _ y: Double, _ channel: Int, bytesPerPixel stride: Int) -> Double {
    let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
    let fx = x - Double(x0), fy = y - Double(y0)
    let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
    let cx0 = min(max(x0, 0), width - 1), cy0 = min(max(y0, 0), height - 1)
    let a = Double(buffer[(cy0 * width + cx0) * stride + channel])
    let b = Double(buffer[(cy0 * width + x1) * stride + channel])
    let c = Double(buffer[(y1 * width + cx0) * stride + channel])
    let d = Double(buffer[(y1 * width + x1) * stride + channel])
    return a * (1 - fx) * (1 - fy) + b * fx * (1 - fy) + c * (1 - fx) * fy + d * fx * fy
}

let markCentreX = Double(markMinX + markMaxX + 1) / 2.0
let markCentreY = Double(markMinY + markMaxY + 1) / 2.0

// The paste may only ever touch the tile's own body. Without this the ramp's
// tail (read in the scaled frame) reaches the artwork's edge glow and paints a
// faint band on the black backdrop above and below the tile - which also fools
// MakeIcon's silhouette extraction into a taller ink box.
var bodyMinX = [Int](repeating: -1, count: height)
var bodyMaxX = [Int](repeating: -1, count: height)
for y in 0..<height {
    for x in 0..<width {
        let i = index(x, y)
        if max(pixels[i], max(pixels[i + 1], pixels[i + 2])) > 20 {
            if bodyMinX[y] < 0 { bodyMinX[y] = x }
            bodyMaxX[y] = x
        }
    }
}

var zoomed = cleaned
for y in 0..<height {
    guard bodyMinX[y] >= 0 else { continue }
    for x in bodyMinX[y]...bodyMaxX[y] {
        let sourceX = markCentreX + (Double(x) + 0.5 - markCentreX) / zoom
        let sourceY = markCentreY + (Double(y) + 0.5 - markCentreY) / zoom
        guard sourceX >= 0, sourceX < Double(width), sourceY >= 0, sourceY < Double(height) else { continue }
        let alpha = sampleBilinear(pasteMask, sourceX, sourceY, 0, bytesPerPixel: 1) / 255.0
        guard alpha > 0.002 else { continue }
        let i = index(x, y)
        if debugProbe, (y == 602 && (x == 244 || x == 240 || x == 250)), (y == 602) {
            note("probe dest(" + String(x) + "," + String(y) + ") source(" + String(format: "%.2f", sourceX)
                 + "," + String(format: "%.2f", sourceY) + ") alpha " + String(format: "%.3f", alpha)
                 + " scaled " + String(format: "%.0f", sampleBilinear(cleaned, sourceX, sourceY, 1, bytesPerPixel: 4))
                 + " original " + String(format: "%.0f", Double(cleaned[i + 1])))
        }
        for channel in 0..<3 {
            let scaled = sampleBilinear(cleaned, sourceX, sourceY, channel, bytesPerPixel: 4)
            zoomed[i + channel] = UInt8(max(0, min(255, (scaled * alpha + Double(cleaned[i + channel]) * (1 - alpha)).rounded())))
        }
    }
}

note("zoom paste done")

// Debug aid: CLEANICON_DEBUG=<dir> dumps the two masks so a stray mark in the
// output can be traced to either the removal or the paste stage.
if let debugDir = ProcessInfo.processInfo.environment["CLEANICON_DEBUG"] {
    func dumpMask(_ mask: [UInt8], _ name: String) {
        var expanded = [UInt8](repeating: 0, count: count * 4)
        for p in 0..<count {
            let v = mask[p]
            expanded[p * 4] = v; expanded[p * 4 + 1] = v; expanded[p * 4 + 2] = v; expanded[p * 4 + 3] = 255
        }
        if let provider = CGDataProvider(data: Data(expanded) as CFData),
           let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: sRGB,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
           let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: debugDir + "/" + name) as CFURL,
                                                            UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
            note("dumped " + name)
        }
    }
    dumpMask(removal, "mask-removal.png")
    dumpMask(pasteMask, "mask-paste.png")
    dumpMask(markMask, "mask-mark.png")
}

// --- write the prepared artwork ------------------------------------------
guard let provider = CGDataProvider(data: Data(zoomed) as CFData),
      let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                          bytesPerRow: width * 4, space: sRGB,
                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                          provider: provider, decode: nil, shouldInterpolate: true,
                          intent: .defaultIntent) else {
    fail("cannot build the prepared artwork")
}
guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outputPath) as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil) else {
    fail("cannot open " + outputPath)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("cannot write the png") }

// --- readback ------------------------------------------------------------
var problems = 0
func check(_ label: String, _ passed: Bool, _ detail: String) {
    print("  " + (passed ? "OK  " : "FAIL") + "  " + label + ": " + detail)
    if !passed { problems += 1 }
}

func inkExtent(_ buffer: [UInt8], _ y: Int) -> (Int, Int) {
    var low = -1, high = -1
    for x in 0..<width {
        let i = (y * width + x) * 4
        if max(buffer[i], max(buffer[i + 1], buffer[i + 2])) > 20 {
            if low < 0 { low = x }
            high = x
        }
    }
    return (low, high)
}

// The mark itself is never repainted. The feathered mask edge can graze the
// glyph's faint anti-aliased rim, so allow a hair of blending but no real change.
var markTouched = 0
var markWorst = 0
for p in 0..<count where markMask[p] != 0 {
    let i = p * 4
    let delta = max(abs(Int(cleaned[i]) - Int(pixels[i])),
                    max(abs(Int(cleaned[i + 1]) - Int(pixels[i + 1])),
                        abs(Int(cleaned[i + 2]) - Int(pixels[i + 2]))))
    if delta > 8 { markTouched += 1 }
    if delta > markWorst { markWorst = delta }
}
// Leftovers are found the same way they are removed: by shape, not by a luma
// threshold in a band with a blind spot next to the mark. A surviving bar - or a
// bar the zoom carried outward - is a warm, tall, thin component sitting outside
// the letter. The letter itself is excluded by sampling the *source* position, so
// the check still works after the zoom has displaced it.
var leftoverBars: [[Int]] = []
do {
    var checkVisited = [Bool](repeating: false, count: count)
    for (bandX0, bandX1) in [(85, 350), (930, 1180)] {
        for y in 240..<min(960, height) {
            for x in bandX0..<min(bandX1, width) {
                let start = y * width + x
                guard !checkVisited[start], isBarInk(zoomed, x, y) else { continue }
                var members: [Int] = []
                stack.removeAll(keepingCapacity: true)
                stack.append(start)
                checkVisited[start] = true
                var minX = x, maxX = x, minY = y, maxY = y
                while let current = stack.popLast() {
                    members.append(current)
                    let cx = current % width, cy = current / width
                    if cx < minX { minX = cx }
                    if cx > maxX { maxX = cx }
                    if cy < minY { minY = cy }
                    if cy > maxY { maxY = cy }
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= bandX0, nx < min(bandX1, width), ny >= 240, ny < min(960, height) else { continue }
                        let neighbour = ny * width + nx
                        guard !checkVisited[neighbour], isBarInk(zoomed, nx, ny) else { continue }
                        checkVisited[neighbour] = true
                        stack.append(neighbour)
                    }
                }
                let h = maxY - minY + 1, w = maxX - minX + 1
                guard h >= 40, w <= 45 else { continue }
                // is any of it over the displaced letter?
                var overlapsLetter = false
                for member in members {
                    let cx = member % width, cy = member / width
                    let sx = markCentreX + (Double(cx) + 0.5 - markCentreX) / zoom
                    let sy = markCentreY + (Double(cy) + 0.5 - markCentreY) / zoom
                    guard sx >= 0, sx < Double(width), sy >= 0, sy < Double(height) else { continue }
                    if sampleBilinear(tightGuard, sx, sy, 0, bytesPerPixel: 1) > 40 { overlapsLetter = true; break }
                }
                if !overlapsLetter {
                    leftoverBars.append(members)
                    note("leftover bar: x " + String(minX) + "..." + String(maxX) + " y " + String(minY)
                         + "..." + String(maxY) + " (" + String(w) + "x" + String(h) + ")")
                }
            }
        }
    }
}
var warmOnRing = 0
let halfBand = ringHalfWidth - 4
for y in 0..<height {
    for x in 0..<width {
        let r = radius(x, y)
        guard abs(r - ringRadius) <= halfBand else { continue }
        guard guardBand[y * width + x] == 0 else { continue }
        var inField = false
        for (x0, x1, y0, y1) in barFields where x >= x0 && x <= x1 && y >= y0 && y <= y1 { inField = true }
        if inField { continue }
        let i = index(x, y)
        let l = 0.2126 * Double(cleaned[i]) + 0.7152 * Double(cleaned[i + 1]) + 0.0722 * Double(cleaned[i + 2])
        let warmth = Double(cleaned[i]) - Double(cleaned[i + 2])
        if l > 70 && warmth > 30 { warmOnRing += 1 }
    }
}
var brightInCredit = 0
for y in creditLine.2..<min(height, creditLine.3 + 1) {
    for x in creditLine.0..<min(width, creditLine.1 + 1) {
        let i = index(x, y)
        if 0.2126 * Double(cleaned[i]) + 0.7152 * Double(cleaned[i + 1]) + 0.0722 * Double(cleaned[i + 2]) > 70 { brightInCredit += 1 }
    }
}
var silhouetteChanged = 0
var y = 340
while y <= 860 {
    let before = inkExtent(pixels, y), after = inkExtent(zoomed, y)
    if abs(before.0 - after.0) > 2 || abs(before.1 - after.1) > 2 { silhouetteChanged += 1 }
    y += 20
}
// the hard zone must equal the scaled artwork exactly - that is what stops the
// un-scaled mark showing through as a ghost of itself
var ghostPixels = 0
var hardSamples = 0
for y in 0..<height {
    for x in 0..<width {
        let sourceX = markCentreX + (Double(x) + 0.5 - markCentreX) / zoom
        let sourceY = markCentreY + (Double(y) + 0.5 - markCentreY) / zoom
        guard sourceX >= 0, sourceX < Double(width), sourceY >= 0, sourceY < Double(height) else { continue }
        guard bodyMinX[y] >= 0, x >= bodyMinX[y], x <= bodyMaxX[y] else { continue }
        guard sampleBilinear(pasteMask, sourceX, sourceY, 0, bytesPerPixel: 1) > 253 else { continue }
        hardSamples += 1
        for channel in 0..<3 {
            let expected = sampleBilinear(cleaned, sourceX, sourceY, channel, bytesPerPixel: 4)
            let actual = Double(zoomed[index(x, y) + channel])
            if abs(expected - actual) > 1 { ghostPixels += 1; break }
        }
    }
}
let bodyRow = height / 2
let bodyExtent = inkExtent(zoomed, bodyRow)

print("CleanIcon: " + String(width) + "x" + String(height) + " artwork, zoom " + String(format: "%.2f", zoom))
print("  mark: " + String(components) + " components, bbox x " + String(markMinX) + "..." + String(markMaxX)
      + " y " + String(markMinY) + "..." + String(markMaxY)
      + " (" + String(markMaxX - markMinX + 1) + "x" + String(markMaxY - markMinY + 1) + " px)")
check("mark pixels untouched by the removal", markTouched == 0,
      String(markTouched) + " pixels changed, worst channel delta " + String(markWorst))
check("no waveform structure left beside the letter", leftoverBars.isEmpty,
      String(leftoverBars.count) + " bar-shaped component(s) remain")
check("credit line cleared", brightInCredit == 0, String(brightInCredit) + " bright pixels remain")
check("ring removed", warmOnRing == 0, String(warmOnRing) + " warm pixels left on the ring band")
check("tile silhouette intact", silhouetteChanged == 0, String(silhouetteChanged) + " of 27 sampled rows changed")
check("no ghost of the un-scaled mark", ghostPixels < 40,
      String(ghostPixels) + " of " + String(hardSamples) + " fully-opaque samples differ by more than 1 (rounding)")
check("tile spans the artwork", bodyExtent.0 < 80 && bodyExtent.1 > 1170,
      "row " + String(bodyRow) + " ink x " + String(bodyExtent.0) + "..." + String(bodyExtent.1))
if problems > 0 { fail("READBACK: " + String(problems) + " problem(s)") }
print("wrote " + outputPath + " (" + String(width) + "x" + String(height) + ")")

// A small mask-only blur, used to build the paste ramp.
func blurMask(_ mask: [UInt8], radius: Int) -> [UInt8] {
    var horizontal = [UInt8](repeating: 0, count: count)
    var out = [UInt8](repeating: 0, count: count)
    let window = 2 * radius + 1
    for y in 0..<height {
        let row = y * width
        var sum = 0
        for x in -radius...radius { sum += Int(mask[row + min(max(x, 0), width - 1)]) }
        for x in 0..<width {
            horizontal[row + x] = UInt8(min(max(sum / window, 0), 255))
            sum += Int(mask[row + min(max(x + radius + 1, 0), width - 1)]) - Int(mask[row + min(max(x - radius, 0), width - 1)])
        }
    }
    for x in 0..<width {
        var sum = 0
        for y in -radius...radius { sum += Int(horizontal[min(max(y, 0), height - 1) * width + x]) }
        for y in 0..<height {
            out[y * width + x] = UInt8(min(max(sum / window, 0), 255))
            sum += Int(horizontal[min(max(y + radius + 1, 0), height - 1) * width + x]) - Int(horizontal[min(max(y - radius, 0), height - 1) * width + x])
        }
    }
    return out
}
