// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import QuartzCore
import SwiftUI

/// One motion vocabulary for everything the song paints, in SwiftUI and
/// Core Animation alike: the same curve, and a few durations by role.
enum NotchSongMotion {
    /// Quick to start, long gentle settle: arrivals, fades and colour.
    static let settleCurve = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    /// A surface wearing the song arriving or leaving: an even, standard
    /// curve, since a front-loaded one makes a fade read as a cut.
    static let fade = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.35)
    /// The same fade's curve, for Core Animation.
    static let fadeCurve = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
    /// Words arriving out of a blur.
    static let arrive = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.45)
    /// A glow opening behind something arriving.
    static let glow = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.8)
    /// An icon or a cover springing in.
    static let spring = Animation.spring(response: 0.5, dampingFraction: 0.6)
    /// Reduce Motion: a plain short fade in place of any of these.
    static let reduced = Animation.easeOut(duration: 0.2)
    /// A cover's colours replacing the last's.
    static let colorChange: CFTimeInterval = 0.9
    static let colour = Animation.timingCurve(0.16, 1, 0.3, 1, duration: colorChange)
    /// A beat's push falling away.
    static let beatReturn: CFTimeInterval = 0.5
    /// Sound-wave rings spreading out and fading, as sound decays.
    static func ripple(_ duration: Double) -> Animation { .easeOut(duration: duration) }
    /// One pass of light across a surface.
    static let sweep = Animation.easeInOut(duration: 0.95)
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
