// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Up to three vivid colours read from a cover, in order of how much of the
/// cover they hold, each toned for one job on the island's dark surface.
/// A cover with no colour of its own (black and white, greys) has no palette
/// of its own; the song then wears the companion's (NotchColourlessSong).
struct NotchArtworkPalette: Equatable {
    /// The cover's colours at full voice: vivid, never washed out.
    let pure: [NSColor]
    /// Colours for the backdrop behind the player. Deep jewel tones: at most
    /// 0.18 luminance, so white text keeps WCAG AA over them at full strength.
    let glow: [NSColor]
    /// Colours for marks on the backdrop (equalizer, timeline, meter): at
    /// least 0.64 luminance, 3:1 against the 0.18 backdrop, as controls must.
    let marks: [NSColor]
    /// The play button's plate: the cover's lead colour, deep enough that the
    /// white glyph on it keeps at least 3:1 contrast.
    let plate: NSColor
    /// Text in the cover's hue: a near-white for primary words, and softer
    /// levels toned to keep their contrast over the song's colour.
    let textPrimary: NSColor
    let textSecondary: NSColor
    let textTertiary: NSColor
    /// The companion's body while it wears the song: a light top and a shade.
    let companionLight: NSColor
    let companionShade: NSColor
    /// How lively the cover looks, 0 to 1: its overall saturation and
    /// brightness. Dark, muted covers move calmer; bright, vivid ones livelier.
    /// It gives every player a mood, not only those that report a genre.
    let energy: Double

    /// Toned once, here, so views that read the palette on every frame of a
    /// resize or every audio update only read stored colours.
    /// `text` is the colour words are toned from; the lead colour by default.
    init(pure: [NSColor], text: NSColor? = nil, energy: Double = 0.5) {
        self.pure = pure
        self.energy = min(1, max(0, energy))
        let words = text ?? pure[0]
        glow = pure.map { $0.notchToned(maxLuminance: 0.18, minLuminance: 0.07) }
        marks = pure.map { $0.notchToned(maxLuminance: 0.8, minLuminance: 0.64) }
        plate = pure[0].notchToned(maxLuminance: 0.22, minLuminance: 0.09)
        textPrimary = words.notchToned(maxLuminance: 0.94, minLuminance: 0.88)
        // Bright enough that secondary icons on the colour, as the player's
        // lyrics and queue buttons, clear 3:1 on the brightest covers.
        textSecondary = words.notchToned(maxLuminance: 0.56, minLuminance: 0.48)
        textTertiary = words.notchToned(maxLuminance: 0.26, minLuminance: 0.2)
        companionLight = pure[0].notchToned(maxLuminance: 0.86, minLuminance: 0.76)
        companionShade = pure[min(1, pure.count - 1)].notchToned(maxLuminance: 0.6, minLuminance: 0.48)
    }

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

    /// The palette a playing song wears: its cover's, or, for a player that
    /// publishes no cover at all (Firefox, many podcast and web players), the
    /// companion's: the cast member's own colours, or one grown from the
    /// companion's colour, so the island still wears the song. A cover with
    /// no colour of its own, black and white, wears the companion's colours
    /// too, so it glows rather than going black (NotchColourlessSong).
    /// `remembers` is false for a snapshot that may be a departing song's,
    /// as the closed strip's, so only the live cover is held. `song` is the
    /// track the cover belongs to, the playing one when not given.
    static func song(_ artwork: NSImage?, remembers: Bool = true,
                     song track: RadialNowPlayingSnapshot? = nil) -> NotchArtworkPalette? {
        // With the Office edition off a song lends no colour anywhere, so
        // the player, the bars and the strip are upstream's own.
        guard NotchSongPreferences.colours else { return nil }
        if let artwork {
            let palette = of(artwork)
            let song = track ?? NotchMusicService.shared.playback?.track
            // A black-and-white cover is held too, as the song it belongs
            // to, so its colours are dealt again as the companion changes.
            if remembers { lastCover = (palette, song, Date()) }
            return worn(palette ?? colourless(song))
        }
        // A cover that arrives late (a looked-up one, say) keeps the last
        // song's colours a moment, rather than passing through the
        // companion's: a black-and-white song's included, so a late cover
        // after one goes straight from its colours to the next song's.
        if let held = lastCover {
            let left = coverGrace - Date().timeIntervalSince(held.seen)
            if left > 0 {
                if graceWake == nil {
                    // When the wait ends, the island's views read the colours again.
                    let wake = DispatchWorkItem {
                        graceWake = nil
                        NotchMusicService.shared.objectWillChange.send()
                    }
                    graceWake = wake
                    DispatchQueue.main.asyncAfter(deadline: .now() + left, execute: wake)
                }
                return worn(held.palette ?? colourless(held.song))
            }
        }
        return worn(castMember().map { cast(NotchColourlessSong.seeds(cast: $0, song: nil)) } ?? coverless())
    }

    /// A cover with no colour of its own: the cast member's colours, or the
    /// Office palette the song is dealt. Main thread only.
    static func colourless(_ track: RadialNowPlayingSnapshot?) -> NotchArtworkPalette {
        let key = track.flatMap { NotchMascotShuffle.songKey(title: $0.title, artist: $0.artist) }
        return cast(NotchColourlessSong.seeds(cast: castMember(), song: key))
    }

    /// The member of the cast the island draws, while the companion is on.
    /// The views that wear a song observe it through NotchColourlessCompanion.
    static func castMember() -> NotchMascotStyle? {
        guard NotchMascotSupport.isEnabled() else { return nil }
        let drawn = NotchMascotSupport.islandLook().dealing(NotchMascotShuffleService.shared.member).style
        return drawn.isCast ? drawn : nil
    }

    /// A palette toned from `seeds`, made once per set of colours.
    private static func cast(_ seeds: [NotchRGB]) -> NotchArtworkPalette {
        if let made = seeded[seeds] { return made }
        if seeded.count > 16 { seeded.removeAll() }
        let made = NotchArtworkPalette(pure: seeds.map(\.nsColor))
        seeded[seeds] = made
        return made
    }

    private static var seeded: [[NotchRGB]: NotchArtworkPalette] = [:]

    /// A palette in the look the person chose (see NotchSongLook).
    static func worn(_ palette: NotchArtworkPalette?) -> NotchArtworkPalette? {
        guard let palette, NotchSongLook.current == .duotone else { return palette }
        let key = palette.pure[0].notchRGBA
        if let made = duotones[key] { return made }
        if duotones.count > 32 { duotones.removeAll() }
        let made = palette.duotone()
        duotones[key] = made
        return made
    }

    private static var duotones: [[Double]: NotchArtworkPalette] = [:]

    /// The cover's lead colour as the one accent, with a soft neutral of the
    /// same hue for everything else: the backdrop mostly calm charcoal with
    /// one glow of the song, bars and controls in the accent, words near-white.
    func duotone() -> NotchArtworkPalette {
        let lead = pure[0].usingColorSpace(.sRGB) ?? pure[0]
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        lead.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let neutral = NSColor(hue: hue, saturation: 0.06, brightness: 0.88, alpha: 1)
        return NotchArtworkPalette(pure: [lead, neutral], text: neutral, energy: energy)
    }

    /// How long a missing cover keeps the last one's colours.
    static let coverGrace: TimeInterval = 3
    /// The last cover read: its palette, nil for a black-and-white one, and its song.
    private static var lastCover: (palette: NotchArtworkPalette?, song: RadialNowPlayingSnapshot?, seen: Date)?
    private static var graceWake: DispatchWorkItem?

    private static var coverlessPalette: (base: NotchMascotPalette, palette: NotchArtworkPalette)?

    /// The companion's colour and its two neighbours on the colour wheel,
    /// vivid enough to tone like a cover's. With the default pearl companion,
    /// a near-grey, they come out blue and violet. Main thread only.
    static func coverless() -> NotchArtworkPalette {
        let base = NotchMascotSupport.look().palette
        if let held = coverlessPalette, held.base == base { return held.palette }
        let seed = (NSColor(cgColor: base.shade.cgColor) ?? .systemBlue).usingColorSpace(.sRGB) ?? .systemBlue
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        seed.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let pure = [hue, hue + 0.12, hue - 0.12].map {
            NSColor(hue: ($0 + 1).truncatingRemainder(dividingBy: 1), saturation: min(1, max(saturation, 0.7)),
                    brightness: 0.95, alpha: 1)
        }
        let palette = NotchArtworkPalette(pure: pure)
        coverlessPalette = (base, palette)
        return palette
    }

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
        var saturationSum = 0.0, brightnessSum = 0.0, counted = 0.0
        var sums = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: hueBins)
        for index in 0..<(side * side) {
            let offset = index * 4
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(pixels[offset]) / 255 / alpha
            let g = Double(pixels[offset + 1]) / 255 / alpha
            let b = Double(pixels[offset + 2]) / 255 / alpha
            let hsb = hsbOf(r: r, g: g, b: b)
            saturationSum += hsb.s
            brightnessSum += hsb.b
            counted += 1
            guard hsb.s >= 0.22, hsb.b >= 0.18 else { continue }
            let w = hsb.s * hsb.s * (0.35 + hsb.b)
            let bin = min(hueBins - 1, Int(hsb.h * Double(hueBins)))
            weight[bin] += w
            sums[bin].r += r * w
            sums[bin].g += g * w
            sums[bin].b += b * w
        }
        let total = weight.reduce(0, +)
        // Too little colour on the whole cover reads as a neutral cover. JPEG
        // noise never gets here (low saturation is skipped above) and a speck
        // does not reach this; a deliberate colour element, such as a prism's
        // thin rainbow on black, does.
        guard total > 0.008 * Double(side * side) else { return nil }

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
        let energy = counted > 0 ? 0.55 * saturationSum / counted + 0.45 * brightnessSum / counted : 0.5
        return NotchArtworkPalette(pure: colors, energy: energy)
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

/// The companion a song with no colour of its own wears: the member of the
/// cast the island draws (nil with the companion off or not of the cast),
/// and the companion's colour, which a song with no cover at all grows its
/// colours from (NotchArtworkPalette.coverless). The views that wear the
/// song's palette observe it, so a shuffle dealing another member, or the
/// companion switched on, off or to another look, recolours a black-and-white
/// song as it happens, cross-fading as a new cover does, rather than at the
/// next unrelated update. A deal can land while the island draws, so a
/// change is read and published on a later turn of the main queue, never
/// from inside a view update. Main thread only.
final class NotchColourlessCompanion: ObservableObject {
    struct Lender: Equatable {
        let member: NotchMascotStyle?
        let palette: NotchMascotPalette
    }

    static let shared = NotchColourlessCompanion()
    @Published private(set) var lender: Lender
    private var subscriptions: Set<AnyCancellable> = []
    private var readPending = false

    private init() {
        lender = Self.read()
        NotchMascotShuffleService.shared.$member
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.readAgain() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.readAgain() }
            .store(in: &subscriptions)
    }

    private static func read() -> Lender {
        Lender(member: NotchArtworkPalette.castMember(), palette: NotchMascotSupport.look().palette)
    }

    /// Once for a burst of changes, on the next turn of the main queue.
    private func readAgain() {
        guard !readPending else { return }
        readPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.readPending = false
            let next = Self.read()
            if next != self.lender { self.lender = next }
        }
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
        // Some hues (deep blue, violet) cannot reach a bright floor at any
        // brightness; those keep full brightness and give up saturation, toward
        // white, until they do.
        if target == minLuminance, at(1).notchLuminance < minLuminance {
            func pale(_ saturation: Double) -> NSColor {
                NSColor(colorSpace: .sRGB, hue: hsb.h, saturation: saturation, brightness: 1, alpha: 1).usingColorSpace(.sRGB)!
            }
            var low = 0.0, high = hsb.s
            for _ in 0..<18 {
                let mid = (low + high) / 2
                if pale(mid).notchLuminance >= minLuminance { low = mid } else { high = mid }
            }
            return pale(low)
        }
        var low = 0.0, high = 1.0
        for _ in 0..<18 {
            let mid = (low + high) / 2
            if at(mid).notchLuminance > target { high = mid } else { low = mid }
        }
        return at(target == maxLuminance ? low : high)
    }
}

import SwiftUI

/// The colours the island's volume meter wears: the moment's colours
/// (NotchMomentPaint), so turning it up feels part of the music, or of the
/// companion with no song, instead of falling back to grey. With neither,
/// the plain meter keeps the island's white.
enum NotchLevelPaint {
    static func volume() -> [Color]? {
        // The Office edition off keeps upstream's white meter.
        guard NotchSongPreferences.colours else { return nil }
        let source = NotchMomentPaint.source()
        guard source != .office else { return nil }
        return NotchMomentPaint.marks(source)
    }
}

/// The one resolver for an Office moment's colours, its props and its glow
/// alike (NotchMomentColours): the worn song's palette, else the companion's
/// glow palette while it is out, else the Office's own accents. Props take
/// the palette's marks, the glow its deep glow colours: one palette, toned
/// twice, so they are always the same hues. Main thread only.
enum NotchMomentPaint {
    /// Whose colours, read now: the song's while it plays, or while the
    /// island itself still wears them (the open player keeps a paused
    /// song's colours), so a notice never disagrees with the island behind it.
    static func source() -> NotchMomentColours {
        NotchMomentColours.of(
            songWorn: NotchMomentColours.songWorn(songMode: NotchSongMode.enabled,
                                                  playing: NotchMusicService.shared.playback?.isPlaying == true
                                                      || NotchSongPaint.shared.palette != nil),
            companionOn: NotchMascotSupport.isEnabled())
    }

    /// The Office's own accents as a palette, toned as a cover's.
    static let office = NotchArtworkPalette(pure: NotchMomentColours.officeSeeds.map(\.nsColor))

    static func palette(_ source: NotchMomentColours = source()) -> NotchArtworkPalette {
        switch source {
        case .song:
            // The song's own, or its colourless fallback; nil only with the
            // edition off, which no worn song can be.
            return NotchArtworkPalette.song(NotchMusicService.shared.artwork)
                ?? palette(NotchMascotSupport.isEnabled() ? .companion : .office)
        case .companion: return NotchIdlePalette.current()
        case .office: return office
        }
    }

    /// The props' colours: the palette's marks, never fewer than two.
    static func marks(_ source: NotchMomentColours = source()) -> [Color] {
        let marks = palette(source).marks.map { Color(nsColor: $0) }
        return marks.count > 1 ? marks : marks + marks
    }
}
