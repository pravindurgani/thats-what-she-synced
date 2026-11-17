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
    /// around it as it rests beside the camera.
    static func closed(agentStrip: Bool, songGlows: Bool, companionRests: Bool, idleAllowed: Bool) -> NotchIslandGlow {
        if agentStrip { return .agents }
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

    /// Three vivid colours grown from the companion's body: its most
    /// colourful one, then its other one where that is a colour of its own,
    /// and close neighbours on the colour wheel for the rest, so the glow
    /// has depth without inventing colours the companion does not wear. Nil
    /// for a grey companion, which takes NotchArtworkPalette.coverless().
    static func idleSeeds(light: NotchRGB, shade: NotchRGB) -> [NotchRGB]? {
        let (lead, other) = shade.hsb.saturation >= light.hsb.saturation ? (shade, light) : (light, shade)
        let leading = lead.hsb
        guard leading.saturation >= 0.12 else { return nil }
        func vivid(_ hue: Double, _ saturation: Double) -> NotchRGB {
            NotchRGB(hue: hue, saturation: min(1, max(saturation, 0.7)), brightness: 0.95)
        }
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

/// The companion's glow switch, read once and again only after a change,
/// since the island asks for it on every frame of a resize. Main thread only.
enum NotchIdleGlowPreferences {
    private static var cached: Bool?
    private static var observer: NSObjectProtocol?

    static var enabled: Bool {
        if let cached { return cached }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                              object: nil, queue: .main) { _ in cached = nil }
        }
        let fresh = enabled(in: .standard)
        cached = fresh
        return fresh
    }

    static func enabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: DefaultsKey.notchIdleGlowEnabled) as? Bool ?? true
    }
}
