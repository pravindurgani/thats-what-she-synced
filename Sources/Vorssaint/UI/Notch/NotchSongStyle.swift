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
    // second unless it is asked for fewer. The song's motion asks for what
    // it needs to look the same, as the comet rings and the cast's idle
    // loops already do.

    /// Slow drifts, breaths and turns that take seconds: 30 frames a second
    /// moves a soft glow less than a point a frame.
    static let slowFrames = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
    /// A beat's quick moves: smooth at 60, as the comet's head is.
    static let beatFrames = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)

    /// Moves `layer`'s `key` to `value` from where it shows now, over
    /// `duration` on `curve`, at the beat's frame rate: what a transaction's
    /// implicit animation does, without asking for 120 frames a second for
    /// each of the twenty readings a second the beat follows.
    static func ease(_ layer: CALayer, _ key: String, to value: Any, duration: CFTimeInterval,
                     curve: CAMediaTimingFunction) {
        let move = CABasicAnimation(keyPath: key)
        move.fromValue = layer.presentation()?.value(forKey: key) ?? layer.value(forKey: key)
        move.toValue = value
        move.duration = duration
        move.timingFunction = curve
        move.preferredFrameRateRange = beatFrames
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKey: key)
        layer.add(move, forKey: key)
        CATransaction.commit()
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
