// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import QuartzCore
import SwiftUI

/// One motion vocabulary for everything the song and the Office moments
/// paint, in SwiftUI and Core Animation alike: two curves, and a few
/// durations by role. Nothing on the island times a move of its own.
enum NotchSongMotion {
    // MARK: Curves

    /// Quick to start, long gentle settle: arrivals, fills and colour.
    static let settleCurve = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    /// The same fade's curve, for Core Animation: even and standard, since a
    /// front-loaded one makes a fade read as a cut.
    static let fadeCurve = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)

    /// The settle curve over `duration`, for SwiftUI.
    static func settle(_ duration: Double) -> Animation { .timingCurve(0.16, 1, 0.3, 1, duration: duration) }
    /// The fade curve over `duration`, for SwiftUI.
    static func even(_ duration: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: duration) }

    // MARK: Durations by role

    /// One frame, in nanoseconds: what an entrance waits after resetting, so
    /// the reset lands before its move starts.
    static let oneFrame: UInt64 = 16_000_000
    /// A blink: words leaving before the next arrive, a jiggle's swing.
    static let blink: Double = 0.08
    /// A reading stepping on: digits rolling, a meter, slats or segments
    /// easing to the next level, a mug's hop.
    static let step: Double = 0.14
    /// A punch-in's fade up under its spring, and a pour starting.
    static let punch: Double = 0.16
    /// Words, a state or a caption replacing the last in place; a stream stopping.
    static let swap: Double = 0.2
    /// A surface arriving or leaving.
    static let fadeDuration: Double = 0.35
    /// Words out of a blur; something falling.
    static let arriveDuration: Double = 0.45
    /// A glow opening behind something arriving; a mug filling.
    static let glowDuration: Double = 0.8
    /// One pass of light across a surface.
    static let sweepDuration: Double = 0.95

    // MARK: Moves

    /// A surface wearing the song arriving or leaving.
    static let fade = even(fadeDuration)
    /// Words arriving out of a blur.
    static let arrive = settle(arriveDuration)
    /// A glow opening behind something arriving.
    static let glow = settle(glowDuration)
    /// An icon or a cover springing in.
    static let spring = Animation.spring(response: 0.5, dampingFraction: 0.6)
    /// A level's marks following the level: a quicker, tighter spring.
    static let follow = Animation.spring(response: 0.28, dampingFraction: 0.62)
    /// Reduce Motion and Low Power Mode: a plain short fade in place of any of these.
    static let reduced = Animation.easeOut(duration: swap)
    /// The punch-in's fade, under its spring.
    static let punchFade = Animation.easeOut(duration: punch)
    /// A reading stepping on.
    static let stepEase = Animation.easeOut(duration: step)
    /// Words or a state replacing the last.
    static let swapEase = Animation.easeOut(duration: swap)
    /// Words leaving, in a blink.
    static let blinkOut = Animation.easeOut(duration: blink)
    /// One swing of a shake.
    static let jiggle = Animation.easeInOut(duration: blink)
    /// Something dropping: gravity's ease in.
    static let fall = Animation.easeIn(duration: arriveDuration)
    /// A stream or a light running out: the fade's curve, at a swap's length.
    static let runOut = even(swap)
    /// A cover's colours replacing the last's.
    static let colorChange: CFTimeInterval = 0.9
    static let colour = settle(colorChange)
    /// A beat's push falling away.
    static let beatReturn: CFTimeInterval = 0.5
    /// Sound-wave rings spreading out and fading, as sound decays: an ease
    /// out, in SwiftUI and Core Animation alike.
    static func ripple(_ duration: Double) -> Animation { .easeOut(duration: duration) }
    static let rippleCurve = CAMediaTimingFunction(name: .easeOut)
    /// The first ring leaves this long after the moment lands, and each next
    /// one a ring's gap later: from one icon, or alternating cones.
    static let ringLead: Double = 0.12
    static let ringGap: Double = 0.22
    /// One ring spreading out and fading: a strip's or a phone's quicker
    /// than a card's.
    static let ringSpread = (strip: 1.0, card: 1.2)
    /// A cone's push as its ring leaves: out in a blink, back in a step.
    static let push = (out: blink, back: step)
    /// One pass of light across a surface.
    static let sweep = Animation.easeInOut(duration: sweepDuration)

    // MARK: Frame rates

    // Every frame a layer moves is a frame WindowServer composites, and on a
    // ProMotion display Core Animation runs an animation at up to 120 a
    // second unless it is asked for fewer. Measured on the resting island,
    // its cost follows the frames asked for: the cast's idle bursts at 15
    // frames a second cost WindowServer less than half what they did at 30. The
    // island's motion asks for what it needs to look the same: the gentlest
    // moves 15, slow drifts, quicker sways, the comet's turn and a beat's
    // fall 30, a beat's hit 60, and only short one-offs more. Rates that
    // divide one another (15, 30, 60) share their frames; 20 beside 30 would
    // add frames of its own.

    /// Slow drifts, turns and quicker sways that take seconds, and a beat
    /// falling away: 30 frames a second moves a soft glow less than a point
    /// or two a frame.
    static let slowFrames = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
    /// The gentlest moves: a glow's breath, a sway of a few degrees, a wisp
    /// rising. 15 frames a second, every other one of a slow motion's, steps
    /// each of them well under a pixel.
    static let gentleFrames = CAFrameRateRange(minimum: 10, maximum: 15, preferred: 15)
    /// A beat's hit, its quick push: smooth at 60.
    static let beatFrames = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)

    /// Plays a beat's move on `layer` under `key`, starting at `time` (media
    /// time): its first `attack` seconds, the hit, at the beat's 60 frames a
    /// second, and the rest, the fall, at 30. The two are slices of the one
    /// animation, the second picking it up where the first leaves off, so
    /// the curve is the same as the whole; each replaces the slice its key
    /// held. An attack of 0 plays it all at 30, as a settle.
    static func play(_ animation: CAAnimation, attack: CFTimeInterval, on layer: CALayer, key: String,
                     at time: CFTimeInterval) {
        let begin = layer.convertTime(time, from: nil)
        let length = animation.duration
        let hit = min(max(0, attack), length)
        let fallKey = key + "Fall"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if hit > 0 {
            let slice = animation.copy() as! CAAnimation
            slice.beginTime = begin
            if hit < length { slice.repeatDuration = hit }
            slice.preferredFrameRateRange = beatFrames
            layer.add(slice, forKey: key)
        } else if layer.animation(forKey: key) != nil {
            layer.removeAnimation(forKey: key)
        }
        if hit < length {
            let slice = animation.copy() as! CAAnimation
            slice.beginTime = begin + hit
            slice.timeOffset = hit
            slice.repeatDuration = length - hit
            slice.preferredFrameRateRange = slowFrames
            layer.add(slice, forKey: fallKey)
        } else if layer.animation(forKey: fallKey) != nil {
            layer.removeAnimation(forKey: fallKey)
        }
    }

    /// Takes a move `play` set going off `layer`, whichever slice is on.
    static func stop(_ key: String, on layer: CALayer) {
        for name in [key, key + "Fall"] where layer.animation(forKey: name) != nil {
            layer.removeAnimation(forKey: name)
        }
    }
}

// MARK: - The beat

/// One hit of the island's beat, as the aurora hears it in the song's
/// levels, for everything that moves with it (NotchMusicPulse). It is sent
/// as a hit lands and as the beat settles, never on the readings between:
/// each listener plays the hit's push and its whole fall as one move,
/// worked out once (NotchBeatCurve), so the twenty readings a second
/// between hits cost nothing.
struct NotchMusicBeat: Equatable {
    /// The push the hit lands at, 0 to 1. A settle is 0.
    let push: Double
    /// Where the push stood at the reading before, as the last hit fell.
    let previous: Double

    /// The beat settling: the music stopped answering.
    static func settle(from previous: Double) -> NotchMusicBeat { NotchMusicBeat(push: 0, previous: previous) }

    var settles: Bool { push <= 0 }

    /// How far above the last reading a hit lands to count as a new one.
    static let newHitRise = 0.12
    /// A hit well above where the last had fallen to: the companion sways
    /// the other way, the cast plays its move and the dancers step.
    var isNewHit: Bool { push > previous + Self.newHitRise }

    /// The moves a listener eases through for this beat, one a reading: a
    /// quick ease out toward each push of the hit's fall, and a settle once
    /// it is nearly down, as the bubbles and the companion always eased.
    func moves(_ value: (Double) -> Double) -> [NotchBeatCurve.Move] {
        let pushes = settles ? [0.0] : NotchBeatFall.pushes(from: push)
        return pushes.map { push in
            let quick = push > 0.05
            return .init(target: value(push), duration: quick ? 0.08 : NotchSongMotion.beatReturn,
                         curve: quick ? CAMediaTimingFunction(name: .easeOut) : NotchSongMotion.settleCurve)
        }
    }

    /// How long a listener's move plays at the hit's frame rate: one
    /// reading, the hit itself; a settle has none.
    var attack: CFTimeInterval { settles ? 0 : NotchBeatFall.reading }
}

/// How a hit's push falls away. The aurora reads the music twenty times a
/// second; each reading without a hit keeps 0.72 of the last one's push,
/// and below 0.01 it rests. Between hits nothing new is heard, so the fall
/// is known the moment the hit lands.
enum NotchBeatFall {
    /// The time between two readings.
    static let reading: CFTimeInterval = 0.05
    static let keeps = 0.72
    static let rest = 0.01
    /// A hit lifting the push less than this above where its fall stands
    /// changes nothing on screen, so nothing is set going again.
    static let deadBand = 0.03

    /// The push at each reading from a hit of `push`: the hit's own, then
    /// each reading's fall, and last the rest, 0.
    static func pushes(from push: Double) -> [Double] {
        var value = push.isFinite ? min(1, max(0, push)) : 0
        var values: [Double] = []
        while value >= rest {
            values.append(value)
            value *= keeps
        }
        return values + [0]
    }
}

/// A value moved toward a new target at every reading, each move eased from
/// wherever the last had it and cut short by the next, as a layer's
/// animations moved it when each reading set one going. Worked out once, as
/// knots and the curve between them, it is one animation drawing that same
/// curve, and where it stands at any moment is known without asking the
/// screen.
struct NotchBeatCurve: Equatable {
    struct Move: Equatable {
        let target: Double
        let duration: CFTimeInterval
        let curve: CAMediaTimingFunction
    }

    /// Seconds from the start, the value there, and the curve of each span
    /// to the next knot.
    let times: [CFTimeInterval]
    let values: [Double]
    let curves: [CAMediaTimingFunction]

    init(times: [CFTimeInterval], values: [Double], curves: [CAMediaTimingFunction]) {
        self.times = times
        self.values = values
        self.curves = curves
    }

    /// From `start`, the first of `moves` at once and each next one
    /// `reading` seconds after the last, which it cuts short; the last runs
    /// its whole length.
    init(from start: Double, moves: [Move], every reading: CFTimeInterval = NotchBeatFall.reading) {
        var times: [CFTimeInterval] = [0], values = [start], curves: [CAMediaTimingFunction] = []
        var value = start
        for (index, move) in moves.enumerated() {
            let begin = Double(index) * reading
            let last = index == moves.count - 1
            let length = max(0.001, move.duration)
            if !last, length > reading {
                let share = reading / length
                value += (move.target - value) * move.curve.progress(at: share)
                times.append(begin + reading)
                values.append(value)
                curves.append(move.curve.cut(at: share))
            } else {
                value = move.target
                times.append(begin + length)
                values.append(value)
                curves.append(move.curve)
                if !last, length < reading {
                    times.append(begin + reading)
                    values.append(value)
                    curves.append(CAMediaTimingFunction(name: .linear))
                }
            }
        }
        self.init(times: times, values: values, curves: curves)
    }

    var duration: CFTimeInterval { times.last ?? 0 }
    /// Where it comes to rest.
    var end: Double { values.last ?? 0 }

    /// Where it stands `elapsed` seconds from its start.
    func value(at elapsed: CFTimeInterval) -> Double {
        guard let first = values.first else { return 0 }
        guard elapsed > 0 else { return first }
        guard elapsed < duration, times.count > 1 else { return end }
        var span = 0
        while span + 2 < times.count, times[span + 1] <= elapsed { span += 1 }
        let length = times[span + 1] - times[span]
        let share = length > 0 ? (elapsed - times[span]) / length : 1
        return values[span] + (values[span + 1] - values[span]) * curves[span].progress(at: share)
    }

    /// The curve as a keyframe animation of `keyPath`, its values mapped by
    /// `map`, or `values` given whole: a transform of two curves worked out
    /// alike, say.
    func animation(_ keyPath: String, additive: Bool = false, values given: [Any]? = nil,
                   map: (Double) -> Any = { $0 }) -> CAKeyframeAnimation {
        let move = CAKeyframeAnimation(keyPath: keyPath)
        move.values = given ?? values.map(map)
        move.keyTimes = times.map { NSNumber(value: duration > 0 ? $0 / duration : 0) }
        move.timingFunctions = curves
        move.duration = duration
        move.isAdditive = additive
        return move
    }
}

/// One layer's part in the beat: the move last set going on it, and when,
/// so the next starts from where it stands without reading the screen.
struct NotchBeatTrack {
    private(set) var curve: NotchBeatCurve?
    private(set) var begin: CFTimeInterval = 0

    /// Where the move stands at `time`; `resting` with none.
    func value(at time: CFTimeInterval, resting: Double = 0) -> Double {
        curve?.value(at: time - begin) ?? resting
    }

    /// Whether a move is still running at `time`.
    func moves(at time: CFTimeInterval) -> Bool {
        curve.map { time - begin < $0.duration } ?? false
    }

    /// A new move, from where this one stands at `time`, through `moves`
    /// a reading apart.
    mutating func start(_ moves: [NotchBeatCurve.Move], at time: CFTimeInterval, resting: Double = 0) -> NotchBeatCurve {
        start(NotchBeatCurve(from: value(at: time, resting: resting), moves: moves), at: time)
    }

    @discardableResult
    mutating func start(_ next: NotchBeatCurve, at time: CFTimeInterval) -> NotchBeatCurve {
        curve = next
        begin = time
        return next
    }

    mutating func stop() { curve = nil }
}

extension CAMediaTimingFunction {
    private var points: (x1: Double, y1: Double, x2: Double, y2: Double) {
        var first: [Float] = [0, 0], second: [Float] = [0, 0]
        getControlPoint(at: 1, values: &first)
        getControlPoint(at: 2, values: &second)
        return (Double(first[0]), Double(first[1]), Double(second[0]), Double(second[1]))
    }

    private static func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
        let r = 1 - s
        return 3 * r * r * s * a + 3 * r * s * s * b + s * s * s
    }

    /// Where on its curve `time`, a share of its duration, falls.
    private func parameter(at time: Double) -> Double {
        let p = points
        var low = 0.0, high = 1.0
        for _ in 0..<48 {
            let mid = (low + high) / 2
            if Self.bezier(mid, p.x1, p.x2) < time { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    /// How far it has eased, 0 to 1, at `time`, a share of its duration.
    func progress(at time: Double) -> Double {
        guard time.isFinite else { return 1 }
        if time <= 0 { return 0 }
        if time >= 1 { return 1 }
        let p = points
        return Self.bezier(parameter(at: time), p.y1, p.y2)
    }

    /// Its first `share` of the time, as a curve of its own: what this ease
    /// draws when the next cuts it short.
    func cut(at share: Double) -> CAMediaTimingFunction {
        guard share > 0, share < 1 else { return self }
        let p = points
        let u = parameter(at: share)
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * u }
        // De Casteljau: the first part of the curve split at u, from (0, 0).
        let x01 = lerp(0, p.x1), y01 = lerp(0, p.y1)
        let x12 = lerp(p.x1, p.x2), y12 = lerp(p.y1, p.y2)
        let x23 = lerp(p.x2, 1), y23 = lerp(p.y2, 1)
        let x012 = lerp(x01, x12), y012 = lerp(y01, y12)
        let x123 = lerp(x12, x23), y123 = lerp(y12, y23)
        let x = lerp(x012, x123), y = lerp(y012, y123)
        guard x > 0.000_001, y > 0.000_001 else { return CAMediaTimingFunction(name: .linear) }
        return CAMediaTimingFunction(controlPoints: Float(x01 / x), Float(y01 / y), Float(x012 / x), Float(y012 / y))
    }
}

/// Text in the cover's hue. The levels match the island's own hierarchy, a
/// near-white primary and softer secondary and tertiary, each toned so it
/// reads better over the colour than the plain white it replaces.
struct NotchSongText: Equatable {
    let primary: Color
    let secondary: Color
    let tertiary: Color

    /// Words drawn as white at a fixed opacity: the brightest take the primary,
    /// the rest the secondary, so a dimmed line still reads as dimmed.
    func soft(_ opacity: Double) -> Color {
        opacity >= 0.7 ? primary.opacity(max(opacity, 0.88)) : secondary
    }
}

private struct NotchSongTextKey: EnvironmentKey {
    static let defaultValue: NotchSongText? = nil
}

extension EnvironmentValues {
    /// The song's text colours while the island wears it, or the companion's
    /// while the open island wears its colours instead (NotchIdlePaint), else nil.
    var notchSongText: NotchSongText? {
        get { self[NotchSongTextKey.self] }
        set { self[NotchSongTextKey.self] = newValue }
    }
}

extension Optional where Wrapped == NotchSongText {
    /// White at the given opacity, as the island draws it, or the song's
    /// matching colour while it wears one.
    func soft(_ opacity: Double) -> Color { self?.soft(opacity) ?? .white.opacity(opacity) }

    /// Small words that must stand out over the colour: the full primary tint
    /// while a song is worn, otherwise white at the given opacity.
    func strong(_ opacity: Double) -> Color { self?.primary ?? .white.opacity(opacity) }
}

/// How strongly the aurora is veiled for what sits over it.
enum NotchAuroraVeil {
    /// `vivid` is every other page by default: the colour well up and the
    /// island's text in the song's own tints, primary far above AA. Coloured
    /// status text and thin graphics can fall below AA and 3:1 there.
    /// `page` is the same pages under Increase Contrast, where all of it keeps AA.
    /// `strip` is the closed island's strip: a cover, a few bright words in
    /// the song's primary tint over colour no lighter than 0.18 luminance,
    /// and the dancers, so the colour shows nearly in full (about 0.88 to
    /// 0.91) at the wings' outer ends. Its words keep 4.5:1 even at the
    /// veil's faintest, at a new song's bloom; the camera between the wings
    /// stays the hardware's own black.
    case open, calm, vivid, page, strip

    /// The colour's strength under the veil.
    var strength: Float {
        switch self {
        case .open, .strip: return 1
        case .calm: return 0.55
        case .vivid: return 0.7
        // Measured on the busiest pages: their grey and orange text keeps
        // 4.5:1 and their larger bold status text 3:1 over the colour.
        case .page: return 0.45
        }
    }

    /// The veil's stops, from the bottom up: darker under the controls and
    /// the head row, lighter in the middle where the colour shows.
    var stops: [CGFloat] {
        switch self {
        case .open: return [0.26, 0.12, 0.22]
        case .strip: return [0.12, 0.09, 0.1]
        case .calm: return [0.49, 0.23, 0.42]
        case .vivid: return [0.42, 0.18, 0.36]
        case .page: return [0.49, 0.26, 0.42]
        }
    }

    /// How far a beat may thin the veil, as a share of itself.
    var thinnest: Double {
        switch self {
        case .page: return 0.92
        case .vivid: return 0.86
        default: return 0.8
        }
    }

    /// How far a new song's bloom lifts the veil. The strip's is shallow:
    /// its veil is thin already, and a deeper lift would take its words
    /// under 4.5:1.
    var bloomDepth: Double {
        switch self {
        case .open: return 0.5
        case .strip: return 0.75
        case .calm: return 0.7
        case .vivid: return 0.65
        case .page: return 0.8
        }
    }

    /// The least the veil ever lays over the colour: its lightest stop,
    /// thinned as far as a beat or a new song's bloom takes it.
    var faintest: Double { Double(stops.min() ?? 0) * min(thinnest, bloomDepth) }
}
