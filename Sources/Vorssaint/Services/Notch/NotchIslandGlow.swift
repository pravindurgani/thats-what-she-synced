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
    /// An Office notice's colours (NotchNoticeGlow), on the same wings as
    /// the agents' and the companion's.
    case notice(NotchNoticeGlow)

    /// The closed island. A notice is its news while it shows, in its own
    /// colours, unless it is the song's own strip glowing (a volume change
    /// over the playing song). Otherwise the agents' glow wins while their
    /// strip is what shows, then a song's glow, while its strip shows, and,
    /// with nothing else there, the companion's colours around it as it
    /// rests beside the camera. The glows that are not the song's, the
    /// agents' and the companion's, share one switch (`idleAllowed`: on,
    /// and not in Low Power Mode); a notice's glow is resolved under it
    /// (`notice(office:agent:colours:idleAllowed:)`).
    static func closed(agentStrip: Bool, songGlows: Bool, companionRests: Bool, idleAllowed: Bool,
                       notice: NotchNoticeGlow? = nil) -> NotchIslandGlow {
        if let notice, !songGlows { return .notice(notice) }
        if agentStrip { return idleAllowed ? .agents : .none }
        if songGlows { return .song }
        return companionRests && idleAllowed ? .idle : .none
    }

    /// The colours an Office notice glows in, or nil for the plain black
    /// notice: without its Office moment (`office`, which the notice carries
    /// only while the Office moments are on), or with the glow switched off
    /// or in Low Power Mode. An agent's notice wears that agent's colours;
    /// any other wears the moment's (NotchMomentColours), as its props do.
    static func notice(office: Bool, agent: AgentProvider?, colours: NotchMomentColours,
                       idleAllowed: Bool) -> NotchNoticeGlow? {
        guard office, idleAllowed else { return nil }
        if let agent { return .agent(agent) }
        switch colours {
        case .song: return .song
        case .companion: return .companion
        case .office: return .office
        }
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

/// Whose colours an Office notice glows in.
enum NotchNoticeGlow: Equatable {
    /// The playing song's.
    case song
    /// The agent the notice is about.
    case agent(AgentProvider)
    /// The companion's (the cast member's own, or grown from its body).
    case companion
    /// The Office's own accents, with no song and no companion.
    case office
}

/// Whose colours an Office moment wears, its props and its glow alike, so a
/// prop never wears one colour over a glow of another: the song's while one
/// is worn, else the companion's while it is out, else the Office's own
/// accents. Every prop, the edition's bubble and every notice glow read it
/// through one resolver (NotchMomentPaint).
enum NotchMomentColours: Equatable {
    case song, companion, office

    /// A song is worn while it plays, with the song mode on. A paused song
    /// lends the island nothing, as the closed island's own song glow does
    /// not (NotchSongMode.glowsClosed): a volume change over a paused song
    /// wears the companion's colours, props and glow alike.
    static func songWorn(songMode: Bool, playing: Bool) -> Bool { songMode && playing }

    static func of(songWorn: Bool, companionOn: Bool) -> NotchMomentColours {
        songWorn ? .song : companionOn ? .companion : .office
    }

    /// The Office's own accents: jelly, mustard and the statuette's pale
    /// gold. Toned as a cover's are, the props take them bright and the
    /// glow deep, both the same yellows.
    static let officeSeeds = [NotchRGB(hex: 0xF4D03F), NotchRGB(hex: 0xC9A227), NotchRGB(hex: 0xFFF0A0)]
}

/// What an Office moment means, which leans its glow toward the edition's
/// own signal colours: beet for danger (a battery running out, a budget
/// spent), gold for success (an agent's turn done). Subtle: the moment's
/// colours stay, a share of the accent mixed in, and every colour stays as
/// deep as a song's glow, so the strip's words keep AA over it.
enum NotchMomentMood: Equatable {
    case danger, success

    static let beet = NotchRGB(hex: 0xC0392B)
    static let gold = NotchRGB(hex: 0xE3B23C)
    /// How far the glow leans toward the accent.
    static let lean = 0.35
    /// The glow's colours stay inside the song's glow's band, whose top keeps
    /// white words AA under the strip's veil (NotchAuroraVeil.strip).
    static let glowLuminance: ClosedRange<Double> = 0.07...0.18

    var accent: NotchRGB { self == .danger ? Self.beet : Self.gold }

    /// The mood of a moment: its battery state or its agent's beat.
    static func of(_ kind: NotchOfficeCue.Kind?) -> NotchMomentMood? {
        switch kind {
        case .battery(.low)?: return .danger
        case .agent(.budgetReached)?: return .danger
        case .agent(.finished)?: return .success
        default: return nil
        }
    }

    /// `colors` leaned toward the accent, toned back into the glow's band.
    func leaned(_ colors: [NotchRGB]) -> [NotchRGB] {
        colors.map {
            $0.mixed(with: accent, by: Self.lean)
                .toned(maxLuminance: Self.glowLuminance.upperBound, minLuminance: Self.glowLuminance.lowerBound)
        }
    }
}

/// One resize of the island, as its window plans it when the shape starts
/// to move: the glows fade along it, so they leave and arrive with the
/// island's own size and curve, frame by frame, rather than on a clock of
/// their own. Read against the outline drawn each frame, the one source of
/// the island's geometry.
struct NotchGlowPlan: Equatable {
    /// A new plan for every resize.
    var id = 0
    var start = CGSize.zero
    var end = CGSize.zero

    /// How far the island has come from `start` to `end` at `size`, from 0
    /// to 1, along whichever side travels further. A resize with nowhere to
    /// go is already there.
    func progress(at size: CGSize) -> Double {
        let width = end.width - start.width, height = end.height - start.height
        let travel = abs(height) >= abs(width) ? (height, size.height - start.height) : (width, size.width - start.width)
        guard abs(travel.0) >= 1 else { return 1 }
        return Double(min(1, max(0, travel.1 / travel.0)))
    }
}

/// Whether one glow is drawn and how strongly, as what the island shows
/// changes. A glow that comes or goes while the island resizes follows the
/// resize (NotchGlowPlan): fully drawn where its state is, gone where it is
/// not, so the island is never left sitting at one size in plain black, and
/// a glow never outlives the size it belongs to. A change with the island
/// staying still fades on the song's fade, run by Core Animation. Gone for
/// good, it is no longer drawn at all.
struct NotchGlowPresence: Equatable {
    struct Frame: Equatable {
        /// Drawn at all.
        var mounted: Bool
        /// How strongly, from 0 to 1.
        var opacity: Double
        /// Eased to `opacity` over `fade` rather than set at once.
        var fades: Bool
    }

    /// The song's fade (NotchSongMotion.fade).
    static let fade = NotchSongMotion.fadeDuration
    /// A resize already this far along is too nearly done to follow.
    static let followable: Double = 0.7

    private(set) var shown = false
    private(set) var opacity = 0.0
    private var seenPlan: Int?
    private var following: Int?
    private var from = 0.0
    private var origin = 0.0
    private var reached = 0.0
    /// Until when a fade with the island still is under way.
    private(set) var fadeEnd: Double?

    mutating func step(shown next: Bool, plan: NotchGlowPlan, progress: Double, now: Double) -> Frame {
        let target: Double = next ? 1 : 0
        let newPlan = seenPlan != plan.id
        seenPlan = plan.id
        let changed = next != shown
        shown = next
        if following == plan.id { reached = max(reached, progress) }
        if changed || (newPlan && opacity != target) {
            if progress < Self.followable {
                // Follows the rest of the resize, from wherever it stands.
                following = plan.id
                from = opacity
                origin = progress
                reached = progress
                fadeEnd = nil
            } else {
                following = nil
                fadeEnd = now + Self.fade
            }
        }
        if let end = fadeEnd, now >= end { fadeEnd = nil }
        if following == plan.id, reached < 1 {
            let share = (reached - origin) / max(0.000_1, 1 - origin)
            opacity = from + (target - from) * share
            return Frame(mounted: true, opacity: opacity, fades: false)
        }
        following = nil
        opacity = target
        let fading = fadeEnd != nil
        return Frame(mounted: next || fading, opacity: target, fades: fading)
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

    /// Read again on the next ask (NotchPreferenceCache.dropAll).
    static func invalidate() { cached = nil }

    /// Its own switch under the Office edition's master (NotchOfficeEdition),
    /// set in Settings (NotchOfficeEditionSettings).
    static func enabled(in defaults: UserDefaults) -> Bool {
        NotchOfficeEdition.allows(defaults.object(forKey: DefaultsKey.notchIdleGlowEnabled) as? Bool ?? true,
                                  in: defaults)
    }
}
