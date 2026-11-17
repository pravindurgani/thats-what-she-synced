// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Up to three vivid colours read from a cover, in order of how much of the
/// cover they hold, each toned for one job on the island's dark surface.
/// A cover with no colour of its own (black and white, greys) has no palette,
/// so the island keeps its neutral look for it.
struct NotchArtworkPalette: Equatable {
    /// The cover's colours at full voice: vivid, never washed out.
    let pure: [NSColor]

    /// Colours for the backdrop behind the player. Kept dark enough that white
    /// text, and the player's softer secondary text, stay legible over them.
    var glow: [NSColor] { pure.map { $0.notchToned(maxLuminance: 0.46, minLuminance: 0.14) } }

    /// Colours for small moving marks (the equalizer): bright enough to read
    /// as colour on a near-black island.
    var marks: [NSColor] { pure.map { $0.notchToned(maxLuminance: 0.62, minLuminance: 0.30) } }

    /// The play button's plate: the cover's lead colour, deep enough that the
    /// white glyph on it keeps at least 3:1 contrast.
    var plate: NSColor { pure[0].notchToned(maxLuminance: 0.26, minLuminance: 0.10) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pure.count == rhs.pure.count
            && zip(lhs.pure, rhs.pure).allSatisfy { $0.notchRGBA == $1.notchRGBA }
    }

    // MARK: Reading a cover

    private static let cache: NSCache<NSImage, Box> = {
        let cache = NSCache<NSImage, Box>()
        cache.countLimit = 24
        return cache
    }()

    private final class Box {
        let palette: NotchArtworkPalette?
        init(_ palette: NotchArtworkPalette?) { self.palette = palette }
    }

    /// The palette of `image`, read once per image and remembered.
    static func of(_ image: NSImage?) -> NotchArtworkPalette? {
        guard let image else { return nil }
        if let box = cache.object(forKey: image) { return box.palette }
        let palette = read(image)
        cache.setObject(Box(palette), forKey: image)
        return palette
    }

    private static let side = 24
    private static let hueBins = 18

    private static func read(_ image: NSImage) -> NotchArtworkPalette? {
        var rect = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        // Each hue bin gathers the colourful pixels that fall in it, weighted
        // by how colourful they are, so a small vivid area outweighs a large dull one
        // only as much as it should.
        var weight = [Double](repeating: 0, count: hueBins)
        var sums = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: hueBins)
        for index in 0..<(side * side) {
            let offset = index * 4
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(pixels[offset]) / 255 / alpha
            let g = Double(pixels[offset + 1]) / 255 / alpha
            let b = Double(pixels[offset + 2]) / 255 / alpha
            let hsb = hsbOf(r: r, g: g, b: b)
            guard hsb.s >= 0.22, hsb.b >= 0.18 else { continue }
            let w = hsb.s * hsb.s * (0.35 + hsb.b)
            let bin = min(hueBins - 1, Int(hsb.h * Double(hueBins)))
            weight[bin] += w
            sums[bin].r += r * w
            sums[bin].g += g * w
            sums[bin].b += b * w
        }
        let total = weight.reduce(0, +)
        // Too little colour on the whole cover reads as a neutral cover.
        guard total > 0.6 else { return nil }

        // Strongest bins first, each new pick far enough round the wheel from
        // the ones already taken to read as its own colour.
        var picks: [(h: Double, color: NSColor)] = []
        for bin in weight.indices.sorted(by: { weight[$0] > weight[$1] }) where weight[bin] > total * 0.06 {
            let w = weight[bin]
            let color = NSColor(srgbRed: sums[bin].r / w, green: sums[bin].g / w, blue: sums[bin].b / w, alpha: 1)
            let hue = (Double(bin) + 0.5) / Double(hueBins)
            guard picks.allSatisfy({ hueDistance($0.h, hue) >= 0.11 }) else { continue }
            picks.append((hue, color.notchVivid))
            if picks.count == 3 { break }
        }
        guard let lead = picks.first else { return nil }
        var colors = picks.map(\.color)
        // A cover with one colour gets close neighbours of it, so the backdrop
        // still has depth without inventing colours the cover does not have.
        if colors.count == 1 {
            colors.append(lead.color.notchRotated(by: 0.07))
            colors.append(lead.color.notchRotated(by: -0.06))
        } else if colors.count == 2 {
            colors.append(colors[0].notchRotated(by: -0.06))
        }
        return NotchArtworkPalette(pure: colors)
    }

    private static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(d, 1 - d)
    }

    fileprivate static func hsbOf(r: Double, g: Double, b: Double) -> (h: Double, s: Double, b: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        var hue = 0.0
        if delta > 0 {
            if maxC == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { hue = (b - r) / delta + 2 }
            else { hue = (r - g) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxC == 0 ? 0 : delta / maxC, maxC)
    }
}

extension NSColor {
    fileprivate var notchRGBA: [Double] {
        let c = usingColorSpace(.sRGB) ?? self
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { (Double($0) * 255).rounded() }
    }

    /// WCAG relative luminance of the sRGB colour.
    var notchLuminance: Double {
        let c = usingColorSpace(.sRGB) ?? self
        func linear(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }

    /// The colour pushed to a confident saturation and brightness.
    fileprivate var notchVivid: NSColor {
        let c = usingColorSpace(.sRGB) ?? self
        let hsb = NotchArtworkPalette.hsbOf(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
        return NSColor(colorSpace: .sRGB, hue: hsb.h, saturation: min(0.92, max(0.58, hsb.s * 1.12)),
                       brightness: min(1, max(0.78, hsb.b)), alpha: 1)
    }

    fileprivate func notchRotated(by turn: Double) -> NSColor {
        let c = usingColorSpace(.sRGB) ?? self
        let hsb = NotchArtworkPalette.hsbOf(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
        var hue = hsb.h + turn
        hue -= floor(hue)
        return NSColor(colorSpace: .sRGB, hue: hue, saturation: hsb.s, brightness: hsb.b, alpha: 1)
    }

    /// The same hue and saturation at the brightness that puts its luminance
    /// inside `minLuminance...maxLuminance`, found by bisection.
    func notchToned(maxLuminance: Double, minLuminance: Double) -> NSColor {
        let c = usingColorSpace(.sRGB) ?? self
        let hsb = NotchArtworkPalette.hsbOf(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
        func at(_ brightness: Double) -> NSColor {
            NSColor(colorSpace: .sRGB, hue: hsb.h, saturation: hsb.s, brightness: brightness, alpha: 1).usingColorSpace(.sRGB)!
        }
        let current = at(hsb.b)
        let luminance = current.notchLuminance
        if luminance >= minLuminance && luminance <= maxLuminance { return current }
        let target = luminance > maxLuminance ? maxLuminance : minLuminance
        var low = 0.0, high = 1.0
        for _ in 0..<18 {
            let mid = (low + high) / 2
            if at(mid).notchLuminance > target { high = mid } else { low = mid }
        }
        // Some hues (deep blue) cannot reach a bright target at any brightness;
        // the brightest they can manage is the best they have.
        return at(target == maxLuminance ? low : high)
    }
}

import SwiftUI

/// The colours the island's volume meter wears: the loaded song's palette, so
/// turning it up feels part of the music; with no song, the companion's own
/// colours, so the island keeps one identity instead of falling back to grey.
enum NotchLevelPaint {
    static func volume() -> [Color] {
        let music = NotchMusicService.shared
        if music.playback != nil, let palette = NotchArtworkPalette.of(music.artwork) {
            return palette.marks.map { Color(nsColor: $0) }
        }
        let companion = NotchMascotSupport.look().palette
        return [companion.shade, companion.light].map { Color(cgColor: $0.cgColor) }
    }
}
