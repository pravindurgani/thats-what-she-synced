// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

// MARK: - The setting

/// What the closed island's music strip shows on the camera's right while a
/// song plays: upstream's equalizer bars, or faceless dancers wearing the
/// song's colours. Shuffle deals a different dance to each new song.
/// `defaults write <bundle id> notchMusicSide -string farewellThree`.
enum NotchMusicSide: String, CaseIterable, Identifiable {
    case bars, boomboxBoss, farewellThree, scarn, shuffle

    var id: String { rawValue }

    /// Anything unknown, nothing stored included, keeps upstream's bars.
    init(stored: String?) {
        self = stored.flatMap(NotchMusicSide.init(rawValue:)) ?? .bars
    }

    static func current(in defaults: UserDefaults) -> NotchMusicSide {
        NotchMusicSide(stored: defaults.string(forKey: DefaultsKey.notchMusicSide))
    }

    /// The stored choice, read again only after a preference changes: the
    /// island measures its music wings on every frame of a resize.
    static var current: NotchMusicSide { NotchMusicSideCache.shared.read() }

    var dances: Bool { self != .bars }

    /// The widest floor this choice may need, at full size: a shuffle may
    /// deal the three, so its wings are fitted to them.
    var floorWidth: CGFloat? {
        guard dances else { return nil }
        return routine.map(\.floorWidth) ?? NotchDanceRoutine.allCases.map(\.floorWidth).max()
    }

    /// The wings it asks for at full size: the three's wider, a solo's narrower.
    var wing: CGFloat? {
        guard dances else { return nil }
        return routine.map(\.wing) ?? NotchDanceRoutine.allCases.map(\.wing).max()
    }

    /// The dance this choice always shows; nil for the bars and for shuffle.
    var routine: NotchDanceRoutine? {
        switch self {
        case .boomboxBoss: return .boomboxBoss
        case .farewellThree: return .farewellThree
        case .scarn: return .scarn
        case .bars, .shuffle: return nil
        }
    }

    /// The dance for `song`, read at `now`: the chosen one, or the one
    /// shuffle dealt it. `pick` answers an index below the count it is given.
    func routine(for song: String?, at now: TimeInterval, shuffle: inout NotchDanceShuffle,
                 pick: (Int) -> Int) -> NotchDanceRoutine? {
        guard self == .shuffle else { return routine }
        return shuffle.routine(for: song, at: now, pick: pick)
    }
}

/// Cleared at once when any preference changes, on whichever thread changed
/// it, so the island's refresh after the change, which runs later on the
/// main thread, already measures the wings with the new choice.
private final class NotchMusicSideCache: @unchecked Sendable {
    static let shared = NotchMusicSideCache()
    private let lock = NSLock()
    private var value: NotchMusicSide?
    private var generation = 0
    private var observer: NSObjectProtocol?

    func read() -> NotchMusicSide {
        lock.lock()
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                              object: nil, queue: nil) { [weak self] _ in
                self?.clear()
            }
        }
        let cached = value
        let seen = generation
        lock.unlock()
        if let cached { return cached }
        // Read outside the lock: a write on another thread posts its change
        // while this one waits for the defaults.
        let fresh = NotchMusicSide.current(in: .standard)
        lock.lock()
        if generation == seen { value = fresh }
        lock.unlock()
        return fresh
    }

    private func clear() {
        lock.lock()
        value = nil
        generation &+= 1
        lock.unlock()
    }
}

/// Deals each new song a dance other than the last one, and keeps the same
/// dance for the same song, so the island's copies on other displays and a
/// strip on its way out all agree. Songs are keys from
/// NotchMascotShuffle.songKey; nil, a reading with no names, tells nothing
/// apart and keeps the dance.
struct NotchDanceShuffle: Equatable {
    private(set) var song: String?
    private(set) var routine: NotchDanceRoutine?
    /// A new song waiting for its names to settle. Its `due` says when to
    /// ask again, nil while no song waits.
    private(set) var settle = NotchSongSettle()

    /// The dance for `song`, read at `now`. The first song is dealt one at
    /// once, as there is nothing to keep; a later one keeps the last dance
    /// until the same song has been read for a settle. Asking for the song
    /// already dealt, as a strip on its way out does, leaves a waiting one
    /// waiting.
    mutating func routine(for song: String?, at now: TimeInterval, pick: (Int) -> Int) -> NotchDanceRoutine {
        if let routine {
            guard let song, song != self.song else {
                // A song that came and went before it settled, as on
                // skipping straight back, is dropped once its time has
                // passed, so nothing keeps asking after it.
                if let due = settle.due, due <= now { settle.forget() }
                return routine
            }
            guard settle.hears(song, at: now) else { return routine }
        }
        let choices = NotchDanceRoutine.allCases.filter { $0 != routine }
        let next = choices[min(choices.count - 1, max(0, pick(choices.count)))]
        self.song = song
        routine = next
        return next
    }
}

// MARK: - The floor

/// The patch of the strip the dancers stand on, beside the camera. Sizes are
/// in points at full size, the figures 26 points tall in a 32-point strip:
/// big enough to read at a glance, as the site draws them.
enum NotchDanceFloor {
    /// Points per unit of a dancer's body (NotchDancerBody) at full size. One
    /// scale for every figure, so they differ by height and outfit, never by
    /// how thick they are drawn.
    static let unit: CGFloat = 1.25
    /// The tallest figure at full size, and the strip that gives it.
    static let fullFigure: CGFloat = 26
    /// A figure stands as tall as its strip less 6 points, within these.
    static let figureRange: ClosedRange<CGFloat> = 18...30
    /// Where the menus leave too little room for full size, the figures step
    /// down to this height in a narrower wing before the strip shows bars.
    static let steppedFigure: CGFloat = 22
    static let steppedWing: CGFloat = 44

    /// The box the strip keeps clear of its rounded end: the figures from
    /// their feet to their heads. Feet are narrow, so its corners round off.
    static let figureBox: CGFloat = 26
    static let figureCorner: CGFloat = 7
    /// The gap the box keeps from the strip's end: a little less than the
    /// strip's own, as only a hand at the end of a move reaches it.
    static let edgeGap: CGFloat = 4

    /// The figures' height in a strip `height` tall.
    static func figureHeight(strip height: CGFloat) -> CGFloat {
        guard height.isFinite else { return fullFigure }
        return min(figureRange.upperBound, max(figureRange.lowerBound, height - 6))
    }

    /// The figures' full size in a strip `height` tall, as a share of 26
    /// points: 1 in a 32-point strip, less in a simulated camera's short one,
    /// more in a tall one.
    static func scale(height: CGFloat) -> CGFloat { figureHeight(strip: height) / fullFigure }

    /// The smallest the figures are drawn before the strip shows bars instead.
    static var smallestScale: CGFloat { figureRange.lowerBound / fullFigure }
    static var steppedScale: CGFloat { steppedFigure / fullFigure }

    /// Where their feet stand: a little below the middle of the strip, which
    /// leaves the room above them that a jump and a boombox overhead need.
    static func ground(height: CGFloat, scale: CGFloat) -> CGFloat {
        guard height.isFinite, scale.isFinite else { return 3 }
        return max(0, (height - figureBox * scale) * 0.42)
    }
}

/// One dance's floor in a strip: its height, the figures' size as a share of
/// full size, and the floor's width at that size.
struct NotchDanceLayout: Equatable {
    let height: CGFloat
    let scale: CGFloat
    let width: CGFloat

    /// At `scale`, or at full size for the strip when none is given.
    init(routine: NotchDanceRoutine, height: CGFloat, scale: CGFloat? = nil) {
        self.height = height
        let full = NotchDanceFloor.scale(height: height)
        let chosen = scale.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? full
        self.scale = chosen
        width = routine.floorWidth * chosen
    }

    var ground: CGFloat { NotchDanceFloor.ground(height: height, scale: scale) }
}

// MARK: - Timing

enum NotchDanceTiming {
    /// The quick ease-out into each pose, as the companion's bop pushes.
    static let attack: Double = 0.08
    /// With no beats coming in, a pose this often keeps them dancing.
    static let fallbackInterval: Double = 0.5
    /// The energy a stand-in step dances with: a lively middle.
    static let fallbackEnergy: Double = 0.6
    /// The beat's step this long after its onset, by default and at most.
    static let defaultInterval: Double = 0.5
    static let intervalRange: ClosedRange<Double> = 0.3...0.9

    /// How far a pose goes, from the dance's groove to its key: the beat's
    /// strength scales it, and even a soft beat reads as a move.
    static func amplitude(_ energy: Double) -> CGFloat {
        let energy = energy.isFinite ? min(1, max(0, energy)) : 0
        return CGFloat(0.62 + 0.38 * energy)
    }

    /// After a beat, the wait before steps stand in for the missing ones:
    /// long enough not to fire between two beats of a slow song.
    static func fallbackDelay(afterBeatInterval interval: Double) -> Double {
        max(0.9, (interval.isFinite ? interval : defaultInterval) * 1.6)
    }

    /// Whether a move held back half a beat, for `beat` of the dance counted
    /// as `generation`, still plays once its wait is over: only in that same
    /// dance, and only while no later beat has come. A quick beat, or a
    /// stand-in step landing just before one, can bring the next count
    /// first, and the late move would then cut short the one that count
    /// started, the eighth count's shared jump among them.
    static func heldStepPlays(beat: Int, generation: Int, latestBeat: Int, latestGeneration: Int) -> Bool {
        beat == latestBeat && generation == latestGeneration
    }

    /// Points along the settle, as shares of its duration. Each is drawn as
    /// a pose of its own, so a limb swinging back keeps its length instead
    /// of shrinking along a straight line between two outlines.
    static let settleTimes: [Double] = [0.08, 0.2, 0.38, 0.65, 1]

    /// How far the settle has gone by `time`, a share of its duration, on
    /// the island's settle curve (0.16, 1, 0.3, 1): quick to start, long and gentle to land.
    static func settleProgress(_ time: Double) -> Double {
        let t = time.isFinite ? min(1, max(0, time)) : 1
        func bezier(_ s: Double, _ first: Double, _ second: Double) -> Double {
            let inverse = 1 - s
            return 3 * inverse * inverse * s * first + 3 * inverse * s * s * second + s * s * s
        }
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if bezier(mid, 0.16, 0.3) < t { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, 1, 1)
    }
}

/// Reads the island's beat as onsets. The beat arrives as a push that jumps
/// on each hit and falls away between, many readings a second; a jump well
/// above the last reading is a new hit, as the companion's bop reads it.
struct NotchDanceTempo: Equatable {
    private(set) var lastPush = 0.0
    private(set) var lastOnset: Double?
    private(set) var interval = NotchDanceTiming.defaultInterval

    /// The strength of a new hit, or nil while the last one falls away.
    mutating func hear(_ bounce: Double, at time: Double) -> Double? {
        let push = bounce.isFinite ? min(1, max(0, bounce)) : 0
        defer { lastPush = push }
        guard push > lastPush + 0.12 else { return nil }
        if let lastOnset, time.isFinite {
            let gap = time - lastOnset
            // Two hits a usual beat apart retime the half-beat moves; a gap
            // across a quiet passage says nothing about the tempo.
            if gap >= 0.25, gap <= 1.2 {
                let range = NotchDanceTiming.intervalRange
                interval += (min(range.upperBound, max(range.lowerBound, gap)) - interval) * 0.5
            }
        }
        lastOnset = time
        return push
    }

    mutating func reset() { self = NotchDanceTempo() }
}

// MARK: - A pose

/// Where a dancer's body is at one moment, in points on a figure about 19
/// points tall, in the viewer's left and right. Every value blends, so a
/// pose mixed with its groove is the same move done smaller.
struct NotchDancerPose: Equatable {
    /// The whole figure sideways and up: hops and jumps.
    var shift: CGFloat = 0
    var lift: CGFloat = 0
    /// The pelvis from standing: hip bumps sideways, bent knees down.
    var hip = CGVector(dx: 0, dy: 0)
    /// The torso's tilt in radians; positive tips the shoulders left.
    var lean: CGFloat = 0
    /// Each shoulder raised, for shoulder rolls and a push overhead.
    var leftShrug: CGFloat = 0
    var rightShrug: CGFloat = 0
    /// Where each hand reaches, from its shoulder.
    var leftHand = CGVector(dx: -0.4, dy: -6)
    var rightHand = CGVector(dx: 0.4, dy: -6)
    /// Each foot from where it stands.
    var leftFoot = CGVector(dx: 0, dy: 0)
    var rightFoot = CGVector(dx: 0, dy: 0)
    /// 1 faces the viewer, -1 has turned around; a spin passes through 0.
    var facing: CGFloat = 1
    /// The boombox: 1 holds it in the left hand alone, tipped by `boxTilt`;
    /// `carry` 1 hangs it by its handle from the right hand.
    var oneHand: CGFloat = 0
    var boxTilt: CGFloat = 0
    var carry: CGFloat = 0
    /// The beat's accent: speaker cones swell with it.
    var accent: CGFloat = 0

    /// This pose `amount` of the way to `other`.
    func mixed(_ other: NotchDancerPose, _ amount: CGFloat) -> NotchDancerPose {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * amount }
        func mix(_ a: CGVector, _ b: CGVector) -> CGVector { CGVector(dx: mix(a.dx, b.dx), dy: mix(a.dy, b.dy)) }
        var pose = NotchDancerPose()
        pose.shift = mix(shift, other.shift)
        pose.lift = mix(lift, other.lift)
        pose.hip = mix(hip, other.hip)
        pose.lean = mix(lean, other.lean)
        pose.leftShrug = mix(leftShrug, other.leftShrug)
        pose.rightShrug = mix(rightShrug, other.rightShrug)
        pose.leftHand = mix(leftHand, other.leftHand)
        pose.rightHand = mix(rightHand, other.rightHand)
        pose.leftFoot = mix(leftFoot, other.leftFoot)
        pose.rightFoot = mix(rightFoot, other.rightFoot)
        pose.facing = mix(facing, other.facing)
        pose.oneHand = mix(oneHand, other.oneHand)
        pose.boxTilt = mix(boxTilt, other.boxTilt)
        pose.carry = mix(carry, other.carry)
        pose.accent = mix(accent, other.accent)
        return pose
    }

    /// The same move to the other side.
    var mirrored: NotchDancerPose {
        var pose = self
        pose.shift = -shift
        pose.hip = CGVector(dx: -hip.dx, dy: hip.dy)
        pose.lean = -lean
        pose.leftShrug = rightShrug
        pose.rightShrug = leftShrug
        pose.leftHand = CGVector(dx: -rightHand.dx, dy: rightHand.dy)
        pose.rightHand = CGVector(dx: -leftHand.dx, dy: leftHand.dy)
        pose.leftFoot = CGVector(dx: -rightFoot.dx, dy: rightFoot.dy)
        pose.rightFoot = CGVector(dx: -leftFoot.dx, dy: leftFoot.dy)
        pose.boxTilt = -boxTilt
        return pose
    }

    static func with(_ change: (inout NotchDancerPose) -> Void) -> NotchDancerPose {
        var pose = NotchDancerPose()
        change(&pose)
        return pose
    }
}

// MARK: - A dancer

/// One body's proportions in units of NotchDanceFloor.unit, 1.25 points at
/// full size: a figure of the standard build stands 26 points tall. Bold on
/// purpose, as the site draws them: a big round head, a filled capsule of a
/// torso about 7 points wide, limbs as thick round-capped strokes. Mild in
/// every other way, and no feature of any person.
struct NotchDancerBody: Equatable {
    /// About 7 points across, with a sliver of keyline between it and the
    /// torso, so a white shirt front never reads as part of the head.
    var headRadius: CGFloat = 2.85
    var neck: CGFloat = 0.45
    var torso: CGFloat = 6.6
    /// The torso capsule's width, about 7 points.
    var torsoWidth: CGFloat = 5.6
    /// Half the shoulders' width, and half the hips'.
    var shoulder: CGFloat = 2.3
    var hip: CGFloat = 1.15
    var upperArm: CGFloat = 3.1
    var foreArm: CGFloat = 2.95
    var thigh: CGFloat = 3.45
    var shin: CGFloat = 3.3
    /// Half the distance between the feet.
    var stance: CGFloat = 1.6
    /// Legs 2.8 points, arms 2.4, hands 1.5 across their radius.
    var legWidth: CGFloat = 2.24
    var armWidth: CGFloat = 1.92
    var handRadius: CGFloat = 1.2
    /// Shoes: dark caps about 3.4 by 1.8 points, each a little outward.
    var shoeWidth: CGFloat = 2.72
    var shoeHeight: CGFloat = 1.44
    var toeOut: CGFloat = 0.3

    /// A foot's point, the ankle, sits inside the shoe, so the leg's round end tucks into it.
    var footLift: CGFloat { shoeHeight * 0.85 }
    var standingHeight: CGFloat { footLift + thigh + shin + torso + neck + headRadius * 2 }
}

/// One drawn part of a dancer, back to front, as the island layers it.
struct NotchDancerLayer: Equatable {
    enum Shape: Equatable {
        case legs, shoes, soles, arms, torso, shirt, tie, collar, hands, head, box, handle, cones, caps
    }

    enum Paint: Equatable {
        /// An outfit or prop colour, 0xRRGGBB, the same in every song.
        case outfit(UInt32)
        /// One of the song's colours at full voice: 0 is the dancer's own, 1 the next.
        case song(Int)
        /// A tone of the song's lead colour (see NotchDanceTone).
        case tone(NotchDanceTone)
        /// Ties and collars: the song's second colour, deep enough to read on a light shirt.
        case tie
        /// Heads and hands: one paper fill for every figure, never a skin tone.
        case head
    }

    enum Stroke: Equatable {
        /// Filled.
        case fill
        /// The limb's own width, round-capped.
        case limb
        /// A line this many units wide.
        case line(CGFloat)
    }

    let shape: Shape
    let paint: Paint
    var stroke: Stroke = .fill

    /// Whether the figure's black keyline runs around this part. Details
    /// laid over a part (a shirt front, a tie, a collar, soles, cones) sit
    /// inside its outline and need none of their own.
    var keyline: Bool {
        switch shape {
        case .legs, .shoes, .arms, .torso, .hands, .head, .handle: return true
        case .box: return stroke == .fill
        case .soles, .shirt, .tie, .collar, .cones, .caps: return false
        }
    }

    /// Heads and hands lie over the body, often over light clothes, so
    /// their keyline is drawn over what lies behind them, a ring that keeps
    /// a paper head apart from a white shirt and a hand from a sleeve.
    var keylineInFront: Bool { shape == .head || shape == .hands }
}

/// The tones a dancer's outfit takes from the song's lead colour. Every one
/// reads on the black island: light and mid at 7:1 or more, deep at 4.5:1 or
/// more, nothing darker than trousers' slate.
enum NotchDanceTone: CaseIterable, Equatable {
    /// A light shirt: a pastel of the lead colour. Mid and deep: the lead
    /// colour itself, the deep one at full voice.
    case light, mid, deep
    /// A dark suit as the island can show one: a luminous slate, mixed
    /// about half and half with the song's lead colour.
    case suit
    /// A grey suit: the same slate at the mid tone.
    case greySuit
    /// Trousers: the slate a step deeper, never below 0.3 luminance.
    case trousers

    /// The luminance each is toned to.
    var luminance: ClosedRange<Double> {
        switch self {
        case .light: return 0.78...0.82
        case .mid, .greySuit: return 0.55...0.6
        case .deep: return 0.35...0.4
        case .suit: return 0.35...0.38
        case .trousers: return 0.3...0.33
        }
    }

    /// How much of the song's lead colour a slate takes; nil for the plain tones.
    var slateShare: Double? {
        switch self {
        case .suit, .greySuit, .trousers: return 0.45
        case .light, .mid, .deep: return nil
        }
    }

    /// The most colour each keeps: a light shirt is a pastel, not a neon.
    var saturationCap: Double {
        switch self {
        case .light: return 0.42
        case .mid: return 0.8
        case .deep, .suit, .greySuit, .trousers: return 1
        }
    }

    /// The slate a suit and trousers start from.
    static let slate = NotchRGB(hex: 0x4A5A6E)

    /// This tone of `lead`, the song's lead colour.
    func of(_ lead: NotchRGB) -> NotchRGB {
        let base = slateShare.map { Self.slate.mixed(with: lead, by: $0) } ?? lead
        return base.saturated(by: 1, atLeast: 0, atMost: saturationCap)
            .toned(maxLuminance: luminance.upperBound, minLuminance: luminance.lowerBound)
            .lifted(toLuminance: luminance.lowerBound)
    }

    /// The tie's tone of the song's second colour: vivid and deep enough to
    /// stand out on a white or light shirt, and still clear of black.
    static func tie(_ second: NotchRGB) -> NotchRGB {
        second.saturated(by: 1.1, atLeast: 0.6).toned(maxLuminance: 0.3, minLuminance: 0.2).lifted(toLuminance: 0.2)
    }

    /// Heads and hands: paper, the same on every figure.
    static let paper = NotchRGB(hex: 0xF7F5F0)
}

/// One figure: its body, where it stands and what it wears.
struct NotchDancer: Equatable {
    var body = NotchDancerBody()
    /// Its standing centre from the floor's middle, in points at full size.
    var position: CGFloat = 0
    /// Which of the song's colours is its own.
    var accent = 0
    var layers: [NotchDancerLayer]

    /// Standing height in points at full size.
    var height: CGFloat { body.standingHeight * NotchDanceFloor.unit }

    var carriesBox: Bool { layers.contains { $0.shape == .box } }

    /// Units on this figure to points on `floor`.
    func scale(_ floor: NotchDanceLayout) -> CGFloat { floor.scale * NotchDanceFloor.unit }

    /// A layer's stroke width on `floor`; nil fills it.
    func lineWidth(_ layer: NotchDancerLayer, floor: NotchDanceLayout) -> CGFloat? {
        let width: CGFloat
        switch layer.stroke {
        case .fill: return nil
        case .limb:
            switch layer.shape {
            case .legs: width = body.legWidth
            case .arms: width = body.armWidth
            case .torso: width = body.torsoWidth
            default: width = 0.6
            }
        case .line(let units): width = units
        }
        return width * scale(floor)
    }

    /// The black keyline around the figure, in points: 1 at full size.
    static func keyline(_ floor: NotchDanceLayout) -> CGFloat { floor.scale }
}

/// The boombox, in units on the figure.
enum NotchBoombox {
    static let width: CGFloat = 9
    static let height: CGFloat = 3.9
    static let corner: CGFloat = 1.05
    /// The hands hold it this far above its bottom edge.
    static let grip: CGFloat = 0.3
    static let handle: CGFloat = 0.6
    static let coneOffset: CGFloat = 2.35
    static let coneRadius: CGFloat = 1.2
}

// MARK: - The rig

/// A pose solved into joints, in points on the figure: x from its standing
/// centre, y up from the floor.
struct NotchDancerRig: Equatable {
    var root: CGPoint
    var pelvis: CGPoint
    var neck: CGPoint
    var head: CGPoint
    var up: CGVector
    var side: CGVector
    var shoulders: [CGPoint]
    var elbows: [CGPoint]
    var hands: [CGPoint]
    var hips: [CGPoint]
    var knees: [CGPoint]
    var feet: [CGPoint]
    var boxCenter: CGPoint
    var boxAngle: CGFloat

    init(body: NotchDancerBody, pose: NotchDancerPose) {
        root = CGPoint(x: pose.shift, y: pose.lift)
        pelvis = CGPoint(x: root.x + pose.hip.dx, y: root.y + body.footLift + body.thigh + body.shin + pose.hip.dy)
        up = CGVector(dx: -sin(pose.lean), dy: cos(pose.lean))
        side = CGVector(dx: cos(pose.lean), dy: sin(pose.lean))
        neck = pelvis.moved(up, body.torso)
        let shoulders = [neck.moved(side, -body.shoulder).moved(CGVector(dx: 0, dy: pose.leftShrug), 1),
                         neck.moved(side, body.shoulder).moved(CGVector(dx: 0, dy: pose.rightShrug), 1)]
        self.shoulders = shoulders
        // The head rides on the shoulders' own tilt, so a shrug nods it.
        let shrugTilt = atan2(shoulders[1].y - shoulders[0].y, shoulders[1].x - shoulders[0].x) * 0.5
        let headUp = CGVector(dx: -sin(pose.lean + shrugTilt), dy: cos(pose.lean + shrugTilt))
        head = neck.moved(headUp, body.neck + body.headRadius)
        hips = [pelvis.moved(side, -body.hip), pelvis.moved(side, body.hip)]
        // Elbows and knees bend outward, elbows a little down: the open,
        // readable shapes of a dance seen from the front. An arm reaching
        // forward looks shorter from the front before it looks bent, so a
        // hand near its shoulder, or swinging past it, throws the elbow out
        // only half as far.
        let arms = [Self.limb(from: shoulders[0], toward: shoulders[0].moved(pose.leftHand, 1),
                              upper: body.upperArm, lower: body.foreArm, bend: CGVector(dx: -1, dy: -0.6),
                              foreshortening: 0.7),
                    Self.limb(from: shoulders[1], toward: shoulders[1].moved(pose.rightHand, 1),
                              upper: body.upperArm, lower: body.foreArm, bend: CGVector(dx: 1, dy: -0.6),
                              foreshortening: 0.7)]
        elbows = arms.map { $0.joint }
        hands = arms.map { $0.end }
        let stand = [CGPoint(x: root.x - body.stance + pose.leftFoot.dx, y: root.y + body.footLift + pose.leftFoot.dy),
                     CGPoint(x: root.x + body.stance + pose.rightFoot.dx, y: root.y + body.footLift + pose.rightFoot.dy)]
        let legs = [Self.limb(from: hips[0], toward: stand[0], upper: body.thigh, lower: body.shin,
                              bend: CGVector(dx: -1, dy: 0.15)),
                    Self.limb(from: hips[1], toward: stand[1], upper: body.thigh, lower: body.shin,
                              bend: CGVector(dx: 1, dy: 0.15))]
        knees = legs.map { $0.joint }
        feet = legs.map { $0.end }

        // The box rests on both hands, tipped as they are; in one hand it
        // sits on that hand; carried, it hangs by its handle.
        let lift = NotchBoombox.height / 2 - NotchBoombox.grip
        let across = CGVector(dx: hands[1].x - hands[0].x, dy: hands[1].y - hands[0].y)
        let bothAngle = atan2(across.dy, max(abs(across.dx), 0.5))
        let both = CGPoint(x: (hands[0].x + hands[1].x) / 2, y: (hands[0].y + hands[1].y) / 2)
            .moved(CGVector(dx: 0, dy: lift).rotated(bothAngle), 1)
        let single = hands[0].moved(CGVector(dx: 0, dy: lift).rotated(pose.boxTilt), 1)
        let carried = hands[1].moved(CGVector(dx: 0, dy: -(NotchBoombox.height / 2 + NotchBoombox.handle)), 1)
        let held = both.mixed(single, pose.oneHand)
        boxCenter = held.mixed(carried, pose.carry)
        let heldAngle = bothAngle + (pose.boxTilt - bothAngle) * pose.oneHand
        boxAngle = heldAngle * (1 - pose.carry)
    }

    /// A two-part limb from `start` reaching for `target`, bent on the side
    /// `bend` points to. Out of reach, it stretches straight toward it. With
    /// `foreshortening` below 1 the limb may look that much shorter, as if
    /// pointing toward the viewer, before it bends at all.
    static func limb(from start: CGPoint, toward target: CGPoint, upper fullUpper: CGFloat, lower fullLower: CGFloat,
                     bend: CGVector, foreshortening: CGFloat = 1) -> (joint: CGPoint, end: CGPoint) {
        let dx = target.x - start.x, dy = target.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        let shown = min(1, max(foreshortening, length / (fullUpper + fullLower)))
        let upper = fullUpper * shown, lower = fullLower * shown
        let direction = length > 0.0001 ? CGVector(dx: dx / length, dy: dy / length) : CGVector(dx: 0, dy: -1)
        let reach = min(max(length, abs(upper - lower) + 0.01), (upper + lower) * 0.9995)
        let end = start.moved(direction, reach)
        let cosine = (upper * upper + reach * reach - lower * lower) / (2 * upper * reach)
        let angle = acos(min(1, max(-1, cosine)))
        let first = direction.rotated(angle), second = direction.rotated(-angle)
        let chosen = first.dx * bend.dx + first.dy * bend.dy >= second.dx * bend.dx + second.dy * bend.dy ? first : second
        return (start.moved(chosen, upper), end)
    }
}

extension NotchDancer {
    /// The figure in `pose`, one path per layer, in points on `floor` with
    /// its origin at the bottom left.
    func paths(_ pose: NotchDancerPose, floor: NotchDanceLayout) -> [CGPath] {
        let rig = NotchDancerRig(body: body, pose: pose)
        let place = Placement(originX: floor.width / 2 + position * floor.scale, originY: floor.ground,
                              unit: scale(floor), pivot: rig.root.x, facing: pose.facing)
        return layers.map { path(for: $0.shape, rig: rig, pose: pose, place: place) }
    }

    /// Figure points to floor points: turned about the figure's own middle
    /// for a spin, then scaled and set in its place.
    private struct Placement {
        let originX: CGFloat
        let originY: CGFloat
        let unit: CGFloat
        let pivot: CGFloat
        let facing: CGFloat

        var transform: CGAffineTransform {
            CGAffineTransform(translationX: -pivot, y: 0)
                .concatenating(CGAffineTransform(scaleX: facing, y: 1))
                .concatenating(CGAffineTransform(translationX: pivot, y: 0))
                .concatenating(CGAffineTransform(scaleX: unit, y: unit))
                .concatenating(CGAffineTransform(translationX: originX, y: originY))
        }

        func callAsFunction(_ point: CGPoint) -> CGPoint { point.applying(transform) }
    }

    private func path(for shape: NotchDancerLayer.Shape, rig: NotchDancerRig, pose: NotchDancerPose,
                      place: Placement) -> CGPath {
        let path = CGMutablePath()
        switch shape {
        case .legs:
            for index in 0..<2 {
                path.addLines(between: [rig.hips[index], rig.knees[index], rig.feet[index]].map(place.callAsFunction))
            }
        case .arms:
            for index in 0..<2 {
                path.addLines(between: [rig.shoulders[index], rig.elbows[index], rig.hands[index]].map(place.callAsFunction))
            }
        case .torso:
            // A capsule, drawn as one thick round-capped stroke: its top
            // tucks under the head and its bottom over the trousers.
            let radius = body.torsoWidth / 2
            path.addLines(between: [rig.neck.moved(rig.up, -0.15 - radius),
                                    rig.pelvis.moved(rig.up, radius - 0.7)].map(place.callAsFunction))
        case .shoes:
            for index in 0..<2 {
                var transform = place.transform
                let out: CGFloat = index == 0 ? -body.toeOut : body.toeOut
                let foot = rig.feet[index]
                let cap = CGRect(x: foot.x + out - body.shoeWidth / 2, y: foot.y - body.footLift,
                                 width: body.shoeWidth, height: body.shoeHeight)
                let round = body.shoeHeight / 2
                path.addPath(CGPath(roundedRect: cap, cornerWidth: round, cornerHeight: round, transform: &transform))
            }
        case .soles:
            for index in 0..<2 {
                let out: CGFloat = index == 0 ? -body.toeOut : body.toeOut
                let foot = rig.feet[index]
                let y = foot.y - body.footLift + 0.2
                let half = body.shoeWidth / 2 - 0.45
                path.addLines(between: [CGPoint(x: foot.x + out - half, y: y),
                                        CGPoint(x: foot.x + out + half, y: y)].map(place.callAsFunction))
            }
        case .shirt:
            // The shirt's V under an open jacket, a band of the jacket
            // above it, so it never joins the head.
            let collar = body.torsoWidth * 0.31
            path.addLines(between: [rig.neck.moved(rig.up, -0.9).moved(rig.side, -collar),
                                    rig.neck.moved(rig.up, -0.9).moved(rig.side, collar),
                                    rig.neck.moved(rig.up, -4.4)].map(place.callAsFunction))
            path.closeSubpath()
        case .tie:
            // A thin tie: a knot, then a blade to a point.
            path.addLines(between: [rig.neck.moved(rig.up, -0.75).moved(rig.side, -0.42),
                                    rig.neck.moved(rig.up, -0.75).moved(rig.side, 0.42),
                                    rig.neck.moved(rig.up, -3.9).moved(rig.side, 0.58),
                                    rig.neck.moved(rig.up, -4.8),
                                    rig.neck.moved(rig.up, -3.9).moved(rig.side, -0.58)].map(place.callAsFunction))
            path.closeSubpath()
        case .collar:
            let collar = body.torsoWidth * 0.26
            path.addLines(between: [rig.neck.moved(rig.up, -0.75).moved(rig.side, -collar),
                                    rig.neck.moved(rig.up, -2.3),
                                    rig.neck.moved(rig.up, -0.75).moved(rig.side, collar)].map(place.callAsFunction))
        case .hands:
            for hand in rig.hands { path.addPath(Self.circle(hand, radius: body.handRadius, place: place)) }
        case .head:
            path.addPath(Self.circle(rig.head, radius: body.headRadius, place: place))
        case .box:
            var transform = boxTransform(rig, place: place)
            let box = CGRect(x: -NotchBoombox.width / 2, y: -NotchBoombox.height / 2,
                             width: NotchBoombox.width, height: NotchBoombox.height)
            path.addPath(CGPath(roundedRect: box, cornerWidth: NotchBoombox.corner,
                                cornerHeight: NotchBoombox.corner, transform: &transform))
        case .handle:
            let top = NotchBoombox.height / 2
            path.addLines(between: [CGPoint(x: -2.5, y: top - 0.2), CGPoint(x: -2.05, y: top + NotchBoombox.handle),
                                    CGPoint(x: 2.05, y: top + NotchBoombox.handle), CGPoint(x: 2.5, y: top - 0.2)],
                          transform: boxTransform(rig, place: place))
        case .cones, .caps:
            // The cones swell on the beat's accent; their dust caps stay put.
            let radius = shape == .cones ? NotchBoombox.coneRadius * (1 + 0.24 * min(1, max(0, pose.accent))) : 0.42
            let transform = boxTransform(rig, place: place)
            for offset in [-NotchBoombox.coneOffset, NotchBoombox.coneOffset] {
                path.addEllipse(in: CGRect(x: offset - radius, y: -0.15 - radius, width: radius * 2, height: radius * 2),
                                transform: transform)
            }
        }
        return path
    }

    private func boxTransform(_ rig: NotchDancerRig, place: Placement) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: rig.boxAngle)
            .concatenating(CGAffineTransform(translationX: rig.boxCenter.x, y: rig.boxCenter.y))
            .concatenating(place.transform)
    }

    /// A head or hand: round from every side, so a spin moves it but never
    /// squashes it.
    private static func circle(_ center: CGPoint, radius: CGFloat, place: Placement) -> CGPath {
        let middle = place(center), size = radius * place.unit
        return CGPath(ellipseIn: CGRect(x: middle.x - size, y: middle.y - size, width: size * 2, height: size * 2),
                      transform: nil)
    }
}

// MARK: - The dances

/// A beat's move for one dancer: one or more key poses, each reached a
/// share of the beat after the onset, then a settle back toward the groove.
struct NotchDanceMove: Equatable {
    struct Hit: Equatable {
        /// Share of the beat interval after the onset.
        let at: Double
        let pose: NotchDancerPose
    }

    var hits: [Hit]
    var attack: Double = NotchDanceTiming.attack
    /// How much of the move remains once it settles: the groove between
    /// beats keeps a little of the last move, so the dance flows.
    var residual: CGFloat = 0.35

    init(_ hits: [Hit], attack: Double = NotchDanceTiming.attack, residual: CGFloat = 0.35) {
        self.hits = hits
        self.attack = attack
        self.residual = residual
    }

    init(_ pose: NotchDancerPose, at: Double = 0, attack: Double = NotchDanceTiming.attack, residual: CGFloat = 0.35) {
        self.init([Hit(at: at, pose: pose)], attack: attack, residual: residual)
    }
}

/// One frame of a dancer's step: the pose it reaches `time` seconds after
/// the step starts, and how it gets there.
struct NotchDanceFrame: Equatable {
    enum Curve: Equatable {
        /// Quick ease-out into a key pose.
        case attack
        /// Easing between two quick moves of the same beat.
        case glide
        /// One stretch of the settle, which the frames themselves curve.
        case settle
    }

    let time: Double
    let pose: NotchDancerPose
    let curve: Curve
}

/// A dancer's whole answer to one beat: started `delay` seconds after the
/// onset, then its frames, from wherever the dancer is when it starts.
struct NotchDanceStep: Equatable {
    let delay: Double
    let frames: [NotchDanceFrame]

    var duration: Double { frames.last?.time ?? 0 }
}

/// A dance: its dancers, their groove between beats, how they stand when
/// the song pauses, the still pose Reduce Motion shows, and the move each
/// of them makes on each beat of an eight-beat loop.
enum NotchDanceRoutine: String, CaseIterable, Identifiable {
    case boomboxBoss, farewellThree, scarn

    var id: String { rawValue }

    static let loop = 8

    /// The beat's place in the eight-beat loop, from 0.
    static func count(_ beat: Int) -> Int { ((beat % loop) + loop) % loop }

    /// The floor's width at full size: the three stand 16 points apart.
    var floorWidth: CGFloat {
        switch self {
        case .farewellThree: return 48
        case .boomboxBoss, .scarn: return 34
        }
    }

    /// The wings the strip takes for it at full size, both sides alike so
    /// the island stays balanced: the floor, and the even gap at the end.
    var wing: CGFloat {
        switch self {
        case .farewellThree: return 60
        case .boomboxBoss, .scarn: return 48
        }
    }

    /// The dancers, left to right.
    var dancers: [NotchDancer] {
        switch self {
        case .boomboxBoss: return [Self.boombox]
        case .farewellThree: return Self.three
        case .scarn: return [Self.scarnDancer]
        }
    }

    /// Between beats each move settles toward this: the dance's neutral.
    func groove(_ dancer: Int) -> NotchDancerPose {
        switch (self, dancer) {
        case (.boomboxBoss, _): return Boombox.groove
        case (.scarn, _): return Scarn.groove
        case (.farewellThree, 0): return Three.leftGroove
        case (.farewellThree, 1): return Three.middleGroove
        case (.farewellThree, _): return Three.rightGroove
        }
    }

    /// Standing still while the song pauses.
    func rest(_ dancer: Int) -> NotchDancerPose {
        switch self {
        case .boomboxBoss: return Boombox.rest
        case .farewellThree, .scarn: return NotchDancerPose()
        }
    }

    /// Reduce Motion's one pose: the dance's most telling shape.
    func still(_ dancer: Int) -> NotchDancerPose {
        switch (self, dancer) {
        case (.boomboxBoss, _): return Boombox.push
        case (.scarn, _): return Scarn.wide
        case (.farewellThree, 0): return Three.roll
        case (.farewellThree, 1): return Three.step
        case (.farewellThree, _): return Three.handsUp
        }
    }

    /// The move dancer `dancer` makes on beat `beat`, counted from 0.
    func move(_ dancer: Int, beat: Int) -> NotchDanceMove {
        let count = Self.count(beat)
        switch self {
        case .boomboxBoss: return Boombox.move(count)
        case .scarn: return Scarn.move(count)
        case .farewellThree: return Three.move(dancer, count)
        }
    }

    /// The frames of dancer `dancer`'s answer to beat `beat`, at `energy`
    /// from 0 to 1, with beats `interval` seconds apart and the settle
    /// taking `settle` seconds.
    func step(_ dancer: Int, beat: Int, energy: Double, interval: Double, settle: Double) -> NotchDanceStep {
        let move = move(dancer, beat: beat)
        let groove = groove(dancer)
        let amplitude = NotchDanceTiming.amplitude(energy)
        let beatLength = interval.isFinite ? min(NotchDanceTiming.intervalRange.upperBound,
                                                 max(NotchDanceTiming.intervalRange.lowerBound, interval))
            : NotchDanceTiming.defaultInterval
        let first = move.hits.first?.at ?? 0
        var frames: [NotchDanceFrame] = []
        var last = groove
        for hit in move.hits {
            let start = (hit.at - first) * beatLength
            // Between two quick moves of the same beat, ease part of the
            // way back first, so the second reads as a move of its own.
            if let previous = frames.last, start > previous.time + 0.01 {
                frames.append(NotchDanceFrame(time: start, pose: groove.mixed(last, amplitude * 0.7), curve: .glide))
            }
            let time = max(start + move.attack, (frames.last?.time ?? 0) + 0.01)
            frames.append(NotchDanceFrame(time: time, pose: groove.mixed(hit.pose, amplitude), curve: .attack))
            last = hit.pose
        }
        guard let landed = frames.last else { return NotchDanceStep(delay: 0, frames: []) }
        let settled = groove.mixed(last, amplitude * move.residual)
        let length = settle.isFinite ? max(0.05, settle) : 0.5
        for time in NotchDanceTiming.settleTimes {
            frames.append(NotchDanceFrame(time: landed.time + time * length,
                                          pose: landed.pose.mixed(settled, CGFloat(NotchDanceTiming.settleProgress(time))),
                                          curve: .settle))
        }
        return NotchDanceStep(delay: first * beatLength, frames: frames)
    }

    // MARK: Boombox Boss

    /// A solo dancer in a white shirt and thin tie, no jacket, dark
    /// trousers, holding a boombox. The box goes overhead and pushes up
    /// toward the island's top edge, as toward a ceiling vent.
    private static let boombox = NotchDancer(body: bossBody, layers: [
        NotchDancerLayer(shape: .legs, paint: .tone(.trousers), stroke: .limb),
        NotchDancerLayer(shape: .shoes, paint: .outfit(shoe)),
        NotchDancerLayer(shape: .soles, paint: .outfit(sole), stroke: .line(0.45)),
        NotchDancerLayer(shape: .torso, paint: .tone(.light), stroke: .limb),
        NotchDancerLayer(shape: .tie, paint: .tie),
        NotchDancerLayer(shape: .arms, paint: .tone(.light), stroke: .limb),
        NotchDancerLayer(shape: .hands, paint: .head),
        NotchDancerLayer(shape: .head, paint: .head),
        NotchDancerLayer(shape: .handle, paint: .outfit(steel), stroke: .line(0.7)),
        NotchDancerLayer(shape: .box, paint: .outfit(0x2A2A2E)),
        NotchDancerLayer(shape: .box, paint: .outfit(steel), stroke: .line(0.55)),
        NotchDancerLayer(shape: .cones, paint: .song(1)),
        NotchDancerLayer(shape: .caps, paint: .outfit(0x2A2A2E)),
    ])

    /// Shoes, their soles, and the boombox's metal.
    private static let shoe: UInt32 = 0x1C1D22
    private static let sole: UInt32 = 0xD9DCE2
    private static let steel: UInt32 = 0xB8BCC2
    /// A shirt front, under a jacket.
    private static let shirtFront: UInt32 = 0xF4F1E8

    /// A solo with the box overhead needs the strip's height for the box:
    /// the same build, its legs and torso shorter and its arms long enough
    /// to push the box clear of its head.
    private static let bossBody = NotchDancerBody(headRadius: 2.45, torso: 5.8, torsoWidth: 5.3, upperArm: 3.5,
                                                  foreArm: 3.3, thigh: 2.55, shin: 2.45)

    private enum Boombox {
        /// Hands under the box's bottom corners, the box clear of the head.
        /// Shoulders lift a little under the weight, which keeps the box
        /// clear of the head.
        static func overhead(_ pose: inout NotchDancerPose, left: CGFloat = 6, right: CGFloat = 6) {
            pose.leftHand = CGVector(dx: -1.35, dy: left)
            pose.rightHand = CGVector(dx: 1.35, dy: right)
            pose.leftShrug = 0.35
            pose.rightShrug = 0.35
        }

        static let groove = NotchDancerPose.with {
            $0.hip.dy = -0.7
            overhead(&$0)
        }

        /// Paused, the box hangs by its handle at the right side.
        static let rest = NotchDancerPose.with {
            $0.carry = 1
            $0.rightHand = CGVector(dx: 0.9, dy: -5.5)
        }

        /// Knees bent, the box overhead on straight arms.
        static let dip = NotchDancerPose.with {
            $0.hip.dy = -2.5
            overhead(&$0, left: 5.9, right: 5.9)
            $0.accent = 0.35
        }

        /// Legs straighten and the box pushes up toward the top edge.
        static let push = NotchDancerPose.with {
            overhead(&$0)
            $0.lift = 0.1
            $0.leftShrug = 0.5
            $0.rightShrug = 0.5
            $0.accent = 1
        }

        /// Knees bend, hips left, the box tipped down on the left.
        static let tipLeft = NotchDancerPose.with {
            $0.hip = CGVector(dx: -1.5, dy: -2)
            $0.lean = -0.14
            $0.leftShrug = 0.3
            $0.rightShrug = 0.3
            $0.leftHand = CGVector(dx: -1.15, dy: 4.95)
            $0.rightHand = CGVector(dx: 1.6, dy: 6)
            $0.accent = 0.5
        }

        /// Up again, hips right, the box tipped down on the right.
        static let pushRight = NotchDancerPose.with {
            $0.hip.dx = 1.5
            $0.lift = 0.1
            $0.lean = 0.14
            $0.leftShrug = 0.4
            $0.rightShrug = 0.4
            $0.leftHand = CGVector(dx: -1.6, dy: 6)
            $0.rightHand = CGVector(dx: 1.15, dy: 4.95)
            $0.accent = 1
        }

        /// The eighth beat: one hand lets go for a fist pump.
        static let fistPump = NotchDancerPose.with {
            $0.lift = 0.1
            $0.leftShrug = 0.5
            $0.rightShrug = 0.3
            $0.oneHand = 1
            $0.boxTilt = 0.22
            $0.leftHand = CGVector(dx: 1.1, dy: 5.9)
            $0.rightHand = CGVector(dx: 2.9, dy: 4.8)
            $0.lean = 0.05
            $0.accent = 1
        }

        static func move(_ count: Int) -> NotchDanceMove {
            switch count {
            case 0, 4: return NotchDanceMove(dip)
            case 1, 5: return NotchDanceMove(push)
            case 2, 6: return NotchDanceMove(tipLeft)
            case 3: return NotchDanceMove(pushRight)
            default: return NotchDanceMove(fistPump)
            }
        }
    }

    // MARK: The Scarn

    /// A solo dancer in a dark suit and tie: a hop to one side with a hand
    /// out to shake, a hop to the other, arms open to meet new friends,
    /// hands circling to tie the yarn, then pulling the knot tight.
    private static let scarnDancer = NotchDancer(layers: [
        NotchDancerLayer(shape: .legs, paint: .tone(.suit), stroke: .limb),
        NotchDancerLayer(shape: .shoes, paint: .outfit(shoe)),
        NotchDancerLayer(shape: .soles, paint: .outfit(sole), stroke: .line(0.45)),
        NotchDancerLayer(shape: .torso, paint: .tone(.suit), stroke: .limb),
        NotchDancerLayer(shape: .shirt, paint: .outfit(shirtFront)),
        NotchDancerLayer(shape: .tie, paint: .tie),
        NotchDancerLayer(shape: .arms, paint: .tone(.suit), stroke: .limb),
        NotchDancerLayer(shape: .hands, paint: .head),
        NotchDancerLayer(shape: .head, paint: .head),
    ])

    private enum Scarn {
        static let groove = NotchDancerPose.with {
            $0.hip.dy = -0.6
            $0.leftHand = CGVector(dx: -0.9, dy: -5.4)
            $0.rightHand = CGVector(dx: 0.9, dy: -5.4)
        }

        static let crouch = NotchDancerPose.with {
            $0.hip.dy = -2.3
            $0.leftFoot.dx = -0.5
            $0.rightFoot.dx = 0.5
            $0.leftHand = CGVector(dx: -0.6, dy: -5.6)
            $0.rightHand = CGVector(dx: 0.6, dy: -5.6)
        }

        /// A hop right, the right hand out at waist height to shake.
        static let shakeRight = NotchDancerPose.with {
            $0.shift = 2.4
            $0.lift = 1.7
            $0.hip.dy = -0.8
            $0.leftFoot.dy = 0.5
            $0.rightFoot.dy = 0.5
            $0.lean = -0.1
            $0.leftHand = CGVector(dx: -0.9, dy: -5.3)
            $0.rightHand = CGVector(dx: 4.5, dy: -2.3)
        }

        /// Arms open wide to meet new friends.
        static let wide = NotchDancerPose.with {
            $0.lift = 0.3
            $0.leftHand = CGVector(dx: -5.2, dy: 1.7)
            $0.rightHand = CGVector(dx: 5.2, dy: 1.7)
        }

        static let hold = NotchDancerPose.with {
            $0.hip.dy = -0.7
            $0.leftHand = CGVector(dx: -5.1, dy: 0.9)
            $0.rightHand = CGVector(dx: 5.1, dy: 0.9)
        }

        /// The hands on a small circle before the chest, opposite each other.
        static func yarn(_ angle: CGFloat) -> NotchDancerPose {
            .with {
                $0.hip.dy = -0.6
                let body = NotchDancerBody()
                let radius: CGFloat = 1.25
                $0.leftHand = CGVector(dx: body.shoulder + radius * cos(angle), dy: -2.5 + radius * sin(angle))
                $0.rightHand = CGVector(dx: -body.shoulder + radius * cos(angle + .pi), dy: -2.5 + radius * sin(angle + .pi))
            }
        }

        /// Hands together at the chest, then pulled apart to tighten the knot.
        static let knot = NotchDancerPose.with {
            $0.hip.dy = -0.4
            $0.leftHand = CGVector(dx: 1.9, dy: -2.4)
            $0.rightHand = CGVector(dx: -1.9, dy: -2.4)
        }

        static let pull = NotchDancerPose.with {
            $0.hip.dy = -0.9
            $0.leftShrug = 0.3
            $0.rightShrug = 0.3
            $0.leftHand = CGVector(dx: -2.6, dy: -2)
            $0.rightHand = CGVector(dx: 2.6, dy: -2)
        }

        static func move(_ count: Int) -> NotchDanceMove {
            switch count {
            case 0, 2: return NotchDanceMove(crouch)
            case 1: return NotchDanceMove(shakeRight)
            case 3: return NotchDanceMove(shakeRight.mirrored)
            case 4: return NotchDanceMove(wide, residual: 0.6)
            case 5: return NotchDanceMove(hold, residual: 0.6)
            case 6:
                return NotchDanceMove([.init(at: 0, pose: yarn(.pi / 2)), .init(at: 1.0 / 3, pose: yarn(.pi * 7 / 6)),
                                       .init(at: 2.0 / 3, pose: yarn(.pi * 11 / 6))])
            default:
                return NotchDanceMove([.init(at: 0, pose: knot), .init(at: 0.5, pose: pull)], residual: 0.2)
            }
        }
    }

    // MARK: The Farewell Three

    /// Three dancers in freestyle, each to their own count. Left: the
    /// tallest, a dark top, leaning into smooth shoulder rolls on the beat.
    /// Middle: a little wider, a grey suit and tie, step-touching with a hip
    /// bump and fists pumping, half a beat late. Right: trim, a light shirt,
    /// double time, hands up and a quick spin. Every eighth beat all three
    /// jump with their arms up together, then scatter back to their own.
    private static let three: [NotchDancer] = [
        // Tallest, about 26 points: a deep casual top, no tie.
        NotchDancer(position: -16, accent: 0, layers: [
            NotchDancerLayer(shape: .legs, paint: .tone(.trousers), stroke: .limb),
            NotchDancerLayer(shape: .shoes, paint: .outfit(shoe)),
            NotchDancerLayer(shape: .soles, paint: .outfit(sole), stroke: .line(0.45)),
            NotchDancerLayer(shape: .torso, paint: .tone(.deep), stroke: .limb),
            NotchDancerLayer(shape: .arms, paint: .tone(.deep), stroke: .limb),
            NotchDancerLayer(shape: .hands, paint: .head),
            NotchDancerLayer(shape: .head, paint: .head),
        ]),
        // About 24 points: a grey suit in the mid tone, a shirt front and a tie.
        NotchDancer(body: NotchDancerBody(torso: 5.95, thigh: 3, shin: 2.9), position: 0, accent: 1, layers: [
            NotchDancerLayer(shape: .legs, paint: .tone(.greySuit), stroke: .limb),
            NotchDancerLayer(shape: .shoes, paint: .outfit(shoe)),
            NotchDancerLayer(shape: .soles, paint: .outfit(sole), stroke: .line(0.45)),
            NotchDancerLayer(shape: .torso, paint: .tone(.greySuit), stroke: .limb),
            NotchDancerLayer(shape: .shirt, paint: .outfit(shirtFront)),
            NotchDancerLayer(shape: .tie, paint: .tie),
            NotchDancerLayer(shape: .arms, paint: .tone(.greySuit), stroke: .limb),
            NotchDancerLayer(shape: .hands, paint: .head),
            NotchDancerLayer(shape: .head, paint: .head),
        ]),
        // About 25 points, trim: a light collared shirt.
        NotchDancer(body: NotchDancerBody(torso: 6.2, thigh: 3.25, shin: 3.1), position: 16, accent: 2, layers: [
            NotchDancerLayer(shape: .legs, paint: .tone(.trousers), stroke: .limb),
            NotchDancerLayer(shape: .shoes, paint: .outfit(shoe)),
            NotchDancerLayer(shape: .soles, paint: .outfit(sole), stroke: .line(0.45)),
            NotchDancerLayer(shape: .torso, paint: .tone(.light), stroke: .limb),
            NotchDancerLayer(shape: .collar, paint: .tie, stroke: .line(0.7)),
            NotchDancerLayer(shape: .arms, paint: .tone(.light), stroke: .limb),
            NotchDancerLayer(shape: .hands, paint: .head),
            NotchDancerLayer(shape: .head, paint: .head),
        ]),
    ]

    private enum Three {
        static let leftGroove = NotchDancerPose.with {
            $0.hip.dy = -0.4
            $0.leftHand = CGVector(dx: 0.6, dy: -4.8)
            $0.rightHand = CGVector(dx: -0.6, dy: -4.8)
        }

        /// Leaning back into a roll of the left shoulder, elbows bent.
        static let roll = NotchDancerPose.with {
            $0.hip = CGVector(dx: 0.6, dy: -0.6)
            $0.lean = 0.16
            $0.leftShrug = 0.9
            $0.rightShrug = -0.25
            $0.leftHand = CGVector(dx: 0.5, dy: -3.5)
            $0.rightHand = CGVector(dx: 0.1, dy: -4.9)
        }

        static let middleGroove = NotchDancerPose.with {
            $0.hip.dy = -0.5
            $0.leftHand = CGVector(dx: 1, dy: -2.9)
            $0.rightHand = CGVector(dx: -1, dy: -2.9)
        }

        /// A step left and a hip bump, one fist pumping up at the chest.
        static let step = NotchDancerPose.with {
            $0.shift = -0.7
            $0.leftFoot = CGVector(dx: -0.9, dy: 0)
            $0.rightFoot = CGVector(dx: -0.4, dy: 0.55)
            $0.hip = CGVector(dx: -1.15, dy: -0.8)
            $0.lean = -0.08
            $0.leftHand = CGVector(dx: 0.7, dy: -0.3)
            $0.rightHand = CGVector(dx: -0.7, dy: -3.3)
        }

        static let rightGroove = NotchDancerPose.with {
            $0.hip.dy = -0.4
            $0.leftHand = CGVector(dx: -0.8, dy: -5.8)
            $0.rightHand = CGVector(dx: 0.8, dy: -5.8)
        }

        /// A knee pop to one side, arms swinging.
        static let pop = NotchDancerPose.with {
            $0.hip = CGVector(dx: 0.6, dy: -1.15)
            $0.lean = -0.12
            $0.leftHand = CGVector(dx: -1.3, dy: -5.6)
            $0.rightHand = CGVector(dx: 0.8, dy: -5.4)
        }

        static let handsUp = NotchDancerPose.with {
            $0.lift = 0.5
            $0.leftHand = CGVector(dx: -1.9, dy: 5.5)
            $0.rightHand = CGVector(dx: 1.9, dy: 5.5)
        }

        static let handsOut = NotchDancerPose.with {
            $0.hip.dy = -0.5
            $0.leftHand = CGVector(dx: -2.5, dy: 4.7)
            $0.rightHand = CGVector(dx: 2.5, dy: 4.7)
        }

        /// Turned partway, one arm up and one down, so the turn shows.
        static func spin(_ facing: CGFloat) -> NotchDancerPose {
            .with {
                $0.facing = facing
                $0.hip.dy = -0.3
                $0.leftHand = CGVector(dx: -0.8, dy: -5.6)
                $0.rightHand = CGVector(dx: 1.1, dy: 5.6)
            }
        }

        /// All three together on the eighth beat.
        static let jump = NotchDancerPose.with {
            $0.lift = 2.4
            $0.hip.dy = -0.8
            $0.leftFoot.dy = 0.9
            $0.rightFoot.dy = 0.9
            $0.leftHand = CGVector(dx: -1.3, dy: 5.6)
            $0.rightHand = CGVector(dx: 1.3, dy: 5.6)
        }

        static func move(_ dancer: Int, _ count: Int) -> NotchDanceMove {
            if count == NotchDanceRoutine.loop - 1 { return NotchDanceMove(jump, residual: 0.25) }
            switch dancer {
            case 0:
                // Smooth: a longer push in and more of each roll kept.
                return NotchDanceMove(count % 2 == 0 ? roll : roll.mirrored, attack: 0.14, residual: 0.6)
            case 1:
                return NotchDanceMove(count % 2 == 0 ? step : step.mirrored, at: 0.5)
            default:
                // Its own loop runs four beats off the others', so its spin
                // lands mid-loop and its fourth beat's hands-up is the jump.
                switch (count + 4) % NotchDanceRoutine.loop {
                case 1, 3:
                    return NotchDanceMove([.init(at: 0, pose: handsUp), .init(at: 0.5, pose: handsOut)],
                                          attack: 0.07, residual: 0.25)
                case 7:
                    return NotchDanceMove([.init(at: 0, pose: spin(0.15)), .init(at: 0.25, pose: spin(-1)),
                                           .init(at: 0.5, pose: spin(-0.15)), .init(at: 0.75, pose: spin(1))],
                                          attack: 0.07, residual: 0.2)
                default:
                    return NotchDanceMove([.init(at: 0, pose: pop), .init(at: 0.5, pose: pop.mirrored)],
                                          attack: 0.07, residual: 0.25)
                }
            }
        }
    }
}

// MARK: - Geometry helpers

private extension CGPoint {
    func moved(_ direction: CGVector, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: x + direction.dx * distance, y: y + direction.dy * distance)
    }

    func mixed(_ other: CGPoint, _ amount: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * amount, y: y + (other.y - y) * amount)
    }
}

private extension CGVector {
    func rotated(_ angle: CGFloat) -> CGVector {
        CGVector(dx: dx * cos(angle) - dy * sin(angle), dy: dx * sin(angle) + dy * cos(angle))
    }
}
