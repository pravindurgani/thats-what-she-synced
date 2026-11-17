// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// An sRGB colour as plain numbers. The strip's and the glow's colour rules
/// work on these, so their contrast can be checked without drawing anything.
struct NotchRGB: Equatable, Hashable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        func unit(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        self.red = unit(red)
        self.green = unit(green)
        self.blue = unit(blue)
    }

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue - floor(hue)) * 6
        let s = min(1, max(0, saturation)), v = min(1, max(0, brightness))
        let sector = Int(h) % 6
        let f = h - floor(h)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch sector {
        case 0: self.init(red: v, green: t, blue: p)
        case 1: self.init(red: q, green: v, blue: p)
        case 2: self.init(red: p, green: v, blue: t)
        case 3: self.init(red: p, green: q, blue: v)
        case 4: self.init(red: t, green: p, blue: v)
        default: self.init(red: v, green: p, blue: q)
        }
    }

    var cgColor: CGColor { cgColor(alpha: 1) }

    func cgColor(alpha: Double) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: min(1, max(0, alpha)))
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let high = max(red, green, blue), low = min(red, green, blue), delta = high - low
        var hue = 0.0
        if delta > 0 {
            if high == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if high == green { hue = (blue - red) / delta + 2 }
            else { hue = (red - green) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, high == 0 ? 0 : delta / high, high)
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The WCAG contrast ratio between two colours, 1 to 21.
    static func contrast(_ a: NotchRGB, _ b: NotchRGB) -> Double {
        let high = max(a.luminance, b.luminance), low = min(a.luminance, b.luminance)
        return (high + 0.05) / (low + 0.05)
    }

    /// Mixed toward `other`, in sRGB, as the compositor mixes layers.
    func mixed(with other: NotchRGB, by amount: Double) -> NotchRGB {
        let t = min(1, max(0, amount))
        return NotchRGB(red: red + (other.red - red) * t, green: green + (other.green - green) * t,
                        blue: blue + (other.blue - blue) * t)
    }

    /// As it shows under a black veil of `alpha`.
    func veiled(by alpha: Double) -> NotchRGB { mixed(with: NotchRGB(red: 0, green: 0, blue: 0), by: alpha) }

    /// The same hue and brightness, its saturation scaled by `factor` and
    /// kept within `floor...ceiling`.
    func saturated(by factor: Double, atLeast floor: Double, atMost ceiling: Double = 1) -> NotchRGB {
        let (hue, saturation, brightness) = hsb
        return NotchRGB(hue: hue, saturation: min(ceiling, max(saturation * factor, floor)), brightness: brightness)
    }

    /// Lightened toward white just enough to reach `target` luminance, so a
    /// tint keeps as much of its colour as legibility allows.
    func lifted(toLuminance target: Double) -> NotchRGB {
        guard luminance < target else { return self }
        let white = NotchRGB(red: 1, green: 1, blue: 1)
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if mixed(with: white, by: mid).luminance >= target { high = mid } else { low = mid }
        }
        return mixed(with: white, by: high)
    }

    /// The same hue and saturation at the brightness that brings its
    /// luminance inside `minLuminance...maxLuminance`, as the song's glow
    /// colours are toned (NSColor.notchToned), so both glows stand alike.
    func toned(maxLuminance: Double, minLuminance: Double) -> NotchRGB {
        let (hue, saturation, brightness) = hsb
        func at(_ value: Double) -> NotchRGB { NotchRGB(hue: hue, saturation: saturation, brightness: value) }
        let current = at(brightness)
        let level = current.luminance
        if level >= minLuminance && level <= maxLuminance { return current }
        let target = level > maxLuminance ? maxLuminance : minLuminance
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if at(mid).luminance > target { high = mid } else { low = mid }
        }
        return at(target == maxLuminance ? low : high)
    }
}

extension AgentProvider {
    /// The agent's own colour: the island's page, the strip and notices all
    /// read it from here.
    var rgb: NotchRGB {
        switch self {
        case .claude: return NotchRGB(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: return NotchRGB(red: 0.49, green: 0.60, blue: 1.0)
        case .opencode: return NotchRGB(red: 0.06, green: 0.73, blue: 0.51)
        case .copilot: return NotchRGB(red: 0.30, green: 0.78, blue: 0.68)
        }
    }

    /// Three stops for the agent's ring and glow, deep to highlight: the
    /// makers' own for Claude and Codex, and grown from the agent's colour
    /// toward white for the others, as Claude's are.
    var glowStops: [NotchRGB] {
        switch self {
        case .claude: return [NotchRGB(hex: 0xD97757), NotchRGB(hex: 0xEB9F7F), NotchRGB(hex: 0xFFD0B5)]
        case .codex: return [NotchRGB(hex: 0x3941FF), NotchRGB(hex: 0x7A9DFF), NotchRGB(hex: 0xB1A7FF)]
        case .opencode, .copilot:
            let white = NotchRGB(red: 1, green: 1, blue: 1)
            return [rgb, rgb.mixed(with: white, by: 0.35), rgb.mixed(with: white, by: 0.68)]
        }
    }

    /// The agent's reading over its glow: its highlight, lightened until it
    /// keeps WCAG AA on the brightest glow the strip can show.
    var readingColor: NotchRGB { glowStops[2].lifted(toLuminance: NotchAgentWings.readingLuminance) }

    /// The glow's colours for this agent's wing, toned as deep as a song's
    /// glow is, so its reading keeps AA. Saturated first: a warm colour this
    /// deep reads brown unless it keeps its full colour, and short of pure,
    /// so Codex's indigo stays indigo.
    var wingGlow: [NotchRGB] {
        glowStops.map { $0.saturated(by: 1.3, atLeast: 0.75, atMost: 0.9).toned(maxLuminance: 0.18, minLuminance: 0.07) }
    }
}

/// One side of the closed island while agents work: an agent's ring and
/// reading, or its check for a moment once its turn ends.
struct NotchAgentWing: Equatable, Identifiable {
    let provider: AgentProvider
    let finished: Bool
    var id: AgentProvider { provider }
}

/// What the agent strip shows: the turns at work, and the wings they take.
struct NotchAgentStripModel: Equatable {
    let live: [AgentLiveSession]
    let wings: [NotchAgentWing]

    init(live: [AgentLiveSession], finished: Set<AgentProvider>) {
        self.live = live
        let working = Set(live.map(\.provider))
        wings = NotchAgentWings.assign(working: working, finished: finished)
    }

    /// Two agents keep a wing each: the first on the left, the second, mirrored, on the right.
    var twoSided: Bool { wings.count > 1 }
}

/// The closed island's wings while agents work. One agent keeps its ring on
/// the left and the chosen reading on the right; two take a wing each, the
/// first in the agents' own order on the left, the second on the right.
enum NotchAgentWings {
    /// The wing a single agent's strip may take, as before, and the wider
    /// one two agents may take, each with its ring and its own reading.
    static let twoSidedRange: ClosedRange<CGFloat> = 44...104
    /// Between a ring and the reading beside it.
    static let markGap: CGFloat = 5
    /// The ring's stroke and its bright head, after the agents' own spinners.
    static let ringLine: CGFloat = 1.6
    static let headSize: CGFloat = 2
    /// Room the breathing halo takes beyond the ring, on every side.
    static let haloRoom: CGFloat = 5
    /// The least luminance a reading keeps over the glow (see readingColor):
    /// enough for 4.5:1 over the glow's brightest point under its lightest veil.
    static let readingLuminance = 0.8
    /// One revolution of the comet, and one breath of the halo in or out.
    static let orbit: CFTimeInterval = 1.4
    static let breath: CFTimeInterval = 1.6
    static let haloRange: ClosedRange<Float> = 0.25...0.6
    /// The ring closing when a turn ends, and the check's colour.
    static let closing: CFTimeInterval = 0.35
    static let done = NotchRGB(hex: 0x4EBA65)

    /// The first two agents in the agents' own order, at work or with a turn
    /// just ended, so a wing never jumps sides while its agent finishes.
    static func assign(working: Set<AgentProvider>, finished: Set<AgentProvider>) -> [NotchAgentWing] {
        Array(AgentProvider.allCases.compactMap { provider -> NotchAgentWing? in
            if working.contains(provider) { return NotchAgentWing(provider: provider, finished: false) }
            return finished.contains(provider) ? NotchAgentWing(provider: provider, finished: true) : nil
        }.prefix(2))
    }

    /// Whose colours glow on each side of the camera: each agent's on its
    /// own wing, or one agent's on both.
    static func glowSides(_ wings: [NotchAgentWing]) -> (left: AgentProvider, right: AgentProvider)? {
        guard let first = wings.first?.provider else { return nil }
        return (first, wings.count > 1 ? wings[1].provider : first)
    }

    /// The ring around a mark in a strip `height` tall, clear of its top and bottom.
    static func ringDiameter(contentHeight height: CGFloat) -> CGFloat {
        min(22, max(12, (height - NotchLayout.compactEdgeGap * 2 - 2).rounded(.down)))
    }

    /// The mark inside the ring, as NotchAgentMark sizes it: the widest
    /// mark, Claude's, drawn 1.45 times this, still clears the ring.
    static func markSize(ring: CGFloat) -> CGFloat { max(6, (ring * 0.5).rounded()) }

    /// A wing's reading beside its ring: smaller than a single agent's, so two fit.
    static func readingSize(contentHeight height: CGFloat) -> CGFloat {
        min(12, max(9, (height * 0.38).rounded()))
    }

    /// The width a reading takes, measured by its shape (see
    /// NotchAgentSupport.readingShape) in the font the strip draws it in.
    static func readingWidth(_ reading: String, size: CGFloat) -> CGFloat {
        let shape = NotchAgentSupport.readingShape(reading) as NSString
        return shape.size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)])
            .width.rounded(.up)
    }

    /// The width each wing needs beside the camera, air included. One agent:
    /// the wider of its ring at the left end and the reading at the right.
    /// Two: the wider of the two agents' ring and reading, which sets both
    /// wings, so the island stays balanced around the camera.
    static func wingWidth(ring: CGFloat, ringInset: CGFloat, readings: [CGFloat], readingInset: CGFloat,
                          twoSided: Bool, cameraGap: CGFloat) -> CGFloat {
        if twoSided {
            let widest = readings.filter(\.isFinite).max() ?? 0
            return ringInset + ring + (widest > 0 ? markGap + widest : 0) + cameraGap
        }
        let reading = readings.first.map { $0.isFinite ? $0 : 0 } ?? 0
        return max(ringInset + ring, reading > 0 ? reading + readingInset : 0) + cameraGap
    }

    /// Whether a two-sided wing has room for a reading beside its ring once
    /// the menus have their say; without it, the ring shows alone.
    static func readingFits(wing: CGFloat, ring: CGFloat, ringInset: CGFloat, reading: CGFloat,
                            cameraGap: CGFloat) -> Bool {
        reading > 0 && wing + 0.5 >= ringInset + ring + markGap + reading + cameraGap
    }

    /// An agent's reading on its own wing: the chosen reading for its turns
    /// alone, held where it stood once the turn ended.
    static func reading(_ snapshot: AgentUsageSnapshot, sessions: [AgentLiveSession], finished: Bool,
                        readout: NotchAgentReadout, display: NotchAgentLimitDisplay,
                        focus: NotchAgentLimitFocus, now: Date) -> String {
        var own = snapshot
        own.live = sessions
        let at = finished ? sessions.map(\.lastActivity).max() ?? now : now
        return NotchAgentSupport.stripReading(own, readout: readout, display: display, focus: focus, now: at)
    }
}

/// Turns that ended, held long enough for their agent's ring to close and
/// show a check. A turn's end is reported a moment before its agent leaves
/// the working list, so the check starts when the agent does, not before;
/// one whose agent keeps working (another of its turns) shows nothing.
struct NotchAgentFinishLog: Equatable {
    /// How long the check holds once its agent stops working.
    static let check: TimeInterval = 1.6
    /// How long a reported end waits for its agent to stop working.
    static let wait: TimeInterval = 4

    private(set) var reported: [AgentProvider: Date] = [:]
    private(set) var checks: [AgentProvider: Date] = [:]

    /// The agents showing their check now.
    var finished: Set<AgentProvider> { Set(checks.keys) }

    mutating func ended(_ provider: AgentProvider, at now: Date) {
        checks[provider] = nil
        reported[provider] = now
    }

    /// Moves on to `now` with the agents at work. Returns when it next needs
    /// to move on by itself, or nil when nothing is pending.
    @discardableResult
    mutating func update(working: Set<AgentProvider>, now: Date) -> Date? {
        for (provider, time) in reported {
            if !working.contains(provider) {
                reported[provider] = nil
                checks[provider] = now
            } else if now.timeIntervalSince(time) >= Self.wait {
                reported[provider] = nil
            }
        }
        for (provider, time) in checks where working.contains(provider) || now.timeIntervalSince(time) >= Self.check {
            checks[provider] = nil
        }
        let deadlines = reported.values.map { $0.addingTimeInterval(Self.wait) }
            + checks.values.map { $0.addingTimeInterval(Self.check) }
        return deadlines.min()
    }
}
