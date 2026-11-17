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
    /// The song's text colours while the island wears it, else nil.
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
