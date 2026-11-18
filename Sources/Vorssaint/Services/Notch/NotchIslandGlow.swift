// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What colours the island's ground. One glow at a time, in order of
/// precedence, so two never stack: the island is never plain black while
/// something of its own has colours to lend it.
enum NotchIslandGlow: Equatable {
    /// Plain black: the camera, captures and the Command Bar, Low Power
    /// Mode, or the glow switched off.
    case none
    /// The playing song's colours (NotchMusicBackdrop).
    case song
    /// The working agents' colours, split across their wings.
    case agents
    /// The companion's colours.
    case idle

    /// The closed island. The agents' glow wins while their strip is what
    /// shows: it is the island's news. Otherwise a song's glow, while its
    /// strip shows, and, with nothing else there, the companion's colours
    /// around it as it rests beside the camera. The glows that are not the
    /// song's, the agents' and the companion's, share one switch
    /// (`idleAllowed`: on, and not in Low Power Mode).
    static func closed(agentStrip: Bool, songGlows: Bool, companionRests: Bool, idleAllowed: Bool) -> NotchIslandGlow {
        if agentStrip { return idleAllowed ? .agents : .none }
        if songGlows { return .song }
        return companionRests && idleAllowed ? .idle : .none
    }

    /// The open island: the song's colours while it wears one, otherwise
    /// the companion's, except on the pages that keep their plain ground.
    static func open(wearsSong: Bool, plainPage: Bool, companionOn: Bool, idleAllowed: Bool) -> NotchIslandGlow {
        if wearsSong { return .song }
        return !plainPage && companionOn && idleAllowed ? .idle : .none
    }

    /// The companion's glow: on unless switched off, and off in Low Power
    /// Mode, where a Mac asked to save energy gets its plain black back.
    static func idleAllowed(enabled: Bool, lowPower: Bool) -> Bool { enabled && !lowPower }

    /// The resting island's glow, from the companion's vivid colours. Its
    /// wings hold only the companion, no words, so the glow may stand a
    /// little brighter than a song's behind the strip's title, while the
    /// companion's light top still stands out against it.
    static let restingLuminance: ClosedRange<Double> = 0.09...0.22

    /// Yellows toned that deep turn olive, so they keep more light: a gold
    /// companion glows gold.
    static let restingYellowLuminance = 0.32

    static func restingGlow(_ seeds: [NotchRGB]) -> [NotchRGB] {
        seeds.map {
            $0.toned(maxLuminance: isYellow($0.hsb.hue) ? restingYellowLuminance : restingLuminance.upperBound,
                     minLuminance: restingLuminance.lowerBound)
        }
    }

    /// The hues that read as yellow, between orange and green.
    static func isYellow(_ hue: Double) -> Bool { (0.1...0.22).contains(hue - floor(hue)) }

    /// The glow's colours for the companion the island draws: `look`, with
    /// a shuffle resolved to `member`, the one it dealt, as the companion's
    /// rig resolves it. A member of the cast lends its own colours
    /// (NotchMascotStyle.glowColors); the minimal body and the robot grow
    /// theirs from their body's colours (idleSeeds(light:shade:)). Each is
    /// made as vivid as a song's. Nil for a grey body, which takes
    /// NotchArtworkPalette.coverless().
    static func idleSeeds(look: NotchMascotLook, dealt member: NotchMascotStyle) -> [NotchRGB]? {
        let drawn = look.dealing(member)
        if let own = drawn.style.glowColors {
            return own.map { NotchRGB($0).hsb }.map { vivid(hue: $0.hue, saturation: $0.saturation) }
        }
        return idleSeeds(light: NotchRGB(drawn.paint.light), shade: NotchRGB(drawn.paint.shade))
    }

    /// A colour at the glow's full strength: its own hue, at least as
    /// saturated as a song's glow colours, at the brightness they are drawn from.
    private static func vivid(hue: Double, saturation: Double) -> NotchRGB {
        NotchRGB(hue: hue, saturation: min(1, max(saturation, 0.7)), brightness: 0.95)
    }

    /// Three vivid colours grown from the companion's body: its most
    /// colourful one, then its other one where that is a colour of its own,
    /// and close neighbours on the colour wheel for the rest, so the glow
    /// has depth without inventing colours the companion does not wear. Nil
    /// for a grey companion, which takes NotchArtworkPalette.coverless().
    static func idleSeeds(light: NotchRGB, shade: NotchRGB) -> [NotchRGB]? {
        let (lead, other) = shade.hsb.saturation >= light.hsb.saturation ? (shade, light) : (light, shade)
        let leading = lead.hsb
        guard leading.saturation >= 0.12 else { return nil }
        func vivid(_ hue: Double, _ saturation: Double) -> NotchRGB { Self.vivid(hue: hue, saturation: saturation) }
        func distance(_ a: Double, _ b: Double) -> Double {
            let d = abs(a - b).truncatingRemainder(dividingBy: 1)
            return min(d, 1 - d)
        }
        // A neighbour that would land in yellow, which the glow's depth turns
        // olive, steps the other way round the wheel instead, unless the
        // companion is yellow itself.
        func neighbour(_ step: Double) -> NotchRGB {
            let hue = leading.hue + step
            let away = isYellow(hue) && !isYellow(leading.hue) ? leading.hue - step * 2 : hue
            return vivid(away, leading.saturation)
        }
        let second = other.hsb
        let own = second.saturation >= 0.25 && distance(second.hue, leading.hue) >= 0.06
        return [vivid(leading.hue, leading.saturation),
                own ? vivid(second.hue, second.saturation) : neighbour(0.1), neighbour(-0.1)]
    }
}

/// The colours a song wears when its cover has none of its own: black and
/// white, greys, or too little colour to read (NotchArtworkPalette.of finds
/// no palette, which takes a peak saturation of about 0.2 or more). The rule
/// everywhere is "the song's colours, else the companion's", so a colourless
/// cover takes the companion's: the cast member the island draws lends its
/// own glow colours. With the companion off, or not of the cast, the song is
/// dealt one of three Office palettes, the same one every time it plays.
enum NotchColourlessSong {
    /// The teapot's teal, the beet's pink and the statuette's gold.
    static let teapot = [NotchRGB(hex: 0x0E9F96), NotchRGB(hex: 0x22D3C5), NotchRGB(hex: 0x9AF5EA)]
    static let beet = [NotchRGB(hex: 0x9E1F4E), NotchRGB(hex: 0xE24A8A), NotchRGB(hex: 0xFFC4DC)]
    static let gold = [NotchRGB(hex: 0xC9A227), NotchRGB(hex: 0xF4D03F), NotchRGB(hex: 0xFFF0A0)]
    static let office = [teapot, beet, gold]

    /// The song's colours: `cast`, the member of the cast the island draws
    /// (nil with the companion off or not of the cast), lends its own; else
    /// the Office palette `song`, its key, is dealt.
    static func seeds(cast member: NotchMascotStyle?, song: String?) -> [NotchRGB] {
        if let member, member.isCast,
           let own = NotchIslandGlow.idleSeeds(look: NotchMascotLook(style: member, shape: .ball, palette: .pearl),
                                               dealt: member) {
            return own
        }
        return office[officeIndex(song)]
    }

    /// The Office palette for a song: a stable hash of its key, the same in
    /// every launch, so a song keeps its colours. No key takes the first.
    static func officeIndex(_ song: String?) -> Int {
        guard let song, !song.isEmpty else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in song.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(hash % UInt64(office.count))
    }
}

extension NotchRGB {
    /// A companion's colour as plain numbers, its alpha left behind.
    init(_ color: NotchMascotColor) {
        self.init(red: Double(color.red), green: Double(color.green), blue: Double(color.blue))
    }
}

/// The companion's glow switch, read once and again only after a change,
/// since the island asks for it on every frame of a resize. Main thread only.
enum NotchIdleGlowPreferences {
    private static var cached: Bool?
    private static var observer: NSObjectProtocol?

    static var enabled: Bool {
        if let cached { return cached }
        if observer == nil { observer = NotchPreferenceCache.observeDefaults { cached = nil } }
        let fresh = enabled(in: .standard)
        cached = fresh
        return fresh
    }

    /// Read again on the next ask (NotchOfficeEdition.set).
    static func invalidate() { cached = nil }

    /// Its own switch under the Office edition's master (NotchOfficeEdition).
    static func enabled(in defaults: UserDefaults) -> Bool {
        NotchOfficeEdition.allows(defaults.object(forKey: DefaultsKey.notchIdleGlowEnabled) as? Bool ?? true,
                                  in: defaults)
    }
}
