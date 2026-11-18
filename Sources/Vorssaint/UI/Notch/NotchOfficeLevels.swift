// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The volume and brightness moments' side by the island's end: the mark,
/// the reading large beside it and the lower third under the reading. The
/// volume's mark is the connect card's boombox in miniature, the
/// brightness's a window whose blinds open with the level. The rules behind
/// them are NotchOfficeMoments' level moments.
struct NotchOfficeLevelReading: View {
    let cue: NotchOfficeCue
    let level: Double
    let reading: String
    /// Nil where the band has none or the strip has no room for a second line.
    let caption: String?
    /// Changes once per moment, so a held key's steps do not punch in again.
    let trigger: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared

    /// Low Power Mode calms the moment as Reduce Motion does.
    private var calm: Bool { reduceMotion || lowPower.isOn }

    var body: some View {
        HStack(spacing: NotchOfficeMoments.levelMarkGap) {
            NotchOfficeLevelMark(cue: cue, level: level, calm: calm)
                .frame(width: NotchOfficeMoments.levelMarkWidth(cue))
            VStack(alignment: .leading, spacing: 0) {
                Text(reading)
                    .font(Font(NotchOfficeMoments.levelReadingFont as CTFont))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(calm ? .identity : .numericText())
                if let caption { NotchOfficeBandCaption(kind: cue.kind, caption: caption, calm: calm) }
            }
            .animation(calm ? NotchSongMotion.reduced : .easeOut(duration: 0.2), value: caption)
        }
        .notchPunchIn(trigger)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The digits roll to a new reading; calm, they change in place.
        .animation(calm ? nil : .easeOut(duration: 0.14), value: reading)
    }
}

/// A level moment's side by the island's other end: the VU meter for the
/// volume; for brightness the meter in daylight's colours, with the caption
/// under it at either end of the range.
struct NotchOfficeLevelMeter: View {
    let cue: NotchOfficeCue
    let level: Double
    /// Nil where the band has none or the strip has no room for a second line.
    let caption: String?
    let trigger: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared

    /// Brightness's meter, in daylight's colours.
    static let daylight = [NotchOfficeInk.mustard, NotchOfficeInk.jelly, NotchOfficeInk.paper]

    private var calm: Bool { reduceMotion || lowPower.isOn }

    var body: some View {
        Group {
            if cue.kind == .volume {
                NotchOfficeVUMeter(level: level, colors: NotchOfficeInk.colors())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    NotchMeter(value: level, height: 5, colors: Self.daylight)
                        .animation(calm ? nil : .easeOut(duration: 0.14), value: level)
                    if let caption { NotchOfficeBandCaption(kind: cue.kind, caption: caption, calm: calm) }
                }
                .padding(.leading, NotchOfficeMoments.levelAir)
                .animation(calm ? NotchSongMotion.reduced : .easeOut(duration: 0.2), value: caption)
            }
        }
        .notchPunchIn(trigger, delay: 0.05)
        .transaction { $0.disablesAnimations = false }
    }
}

/// A level moment in a floating capsule's one row, in the plain row's order:
/// the boombox or the blinds and the meter at the capsule's size, the
/// reading, then the band's caption where the capsule holds it, measured as
/// the service measures the capsule (NotchOfficeMoments.capsuleContent).
struct NotchOfficeCapsuleLevel: View {
    let cue: NotchOfficeCue
    let level: Double
    let reading: String
    let geometry: NotchGeometry
    /// Nil where the band has none or the capsule has no room for it.
    let caption: String?
    /// Changes once per moment, so a held key's steps do not punch in again.
    let trigger: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared

    private var calm: Bool { reduceMotion || lowPower.isOn }

    var body: some View {
        let layout = NotchCapsuleLayout.self
        let font = NotchOfficeMoments.capsuleCaptionFont(geometry)
        HStack(spacing: layout.spacing) {
            NotchOfficeLevelMark(cue: cue, level: level, calm: calm)
                .scaleEffect(NotchOfficeMoments.capsuleMarkScale(cue, geometry: geometry))
                .frame(width: NotchOfficeMoments.capsuleMarkWidth(cue, geometry: geometry),
                       height: NotchOfficeMoments.capsuleLevelHeight(geometry))
            meter
            Text(reading)
                .font(Font(layout.readingFont as CTFont))
                .lineLimit(1)
                .contentTransition(calm ? .identity : .numericText())
                .frame(width: NotchOfficeMoments.capsuleReadingWidth(reading), alignment: .trailing)
            if let caption {
                // In the room the capsule keeps for it (capsuleCaptionSlot),
                // so the row holds still as the band's words change.
                NotchOfficeBandCaption(kind: cue.kind, caption: caption, calm: calm,
                                       size: font === NotchOfficeMoments.cardCaptionFont ? .card : .strip)
                    .frame(width: NotchOfficeMoments.captionWidth(NotchOfficeMoments.capsuleCaptionSlot(cue, caption: caption),
                                                                  font: font),
                           alignment: .leading)
                    .padding(.leading, layout.groupSpacing - layout.spacing)
            }
        }
        .animation(calm ? NotchSongMotion.reduced : .easeOut(duration: 0.2), value: caption)
        .animation(calm ? nil : .easeOut(duration: 0.14), value: reading)
        .notchPunchIn(trigger)
        .transaction { $0.disablesAnimations = false }
    }

    @ViewBuilder private var meter: some View {
        if cue.kind == .volume {
            NotchOfficeVUMeter(level: level, colors: NotchOfficeInk.colors(),
                               scale: NotchOfficeMoments.capsuleMeterScale(geometry))
        } else {
            NotchMeter(value: level, height: NotchCapsuleLayout.meterHeight, colors: NotchOfficeLevelMeter.daylight)
                .frame(width: NotchCapsuleLayout.meterWidth)
                .animation(calm ? nil : .easeOut(duration: 0.14), value: level)
        }
    }
}

/// A level moment in the open island's top row, where a reading covers one
/// side for the moment it shows, in the plain reading's order: the mark and
/// the meter as the strip draws them, then the reading large with the band's
/// caption under it where the side holds it
/// (NotchOfficeMoments.expandedCaptionFits).
struct NotchOfficeExpandedLevel: View {
    let cue: NotchOfficeCue
    let level: Double
    let reading: String
    /// A side too narrow for the percentage keeps the mark and the meter.
    let showsReading: Bool
    /// Whether the side holds the caption. Its column keeps the widest
    /// caption's room through every band, words or none.
    let captionFits: Bool
    let trigger: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared

    private var calm: Bool { reduceMotion || lowPower.isOn }

    var body: some View {
        let caption = showsReading && captionFits ? cue.caption : nil
        HStack(spacing: NotchOfficeMoments.expandedSpacing) {
            NotchOfficeLevelMark(cue: cue, level: level, calm: calm)
                .frame(width: NotchOfficeMoments.levelMarkWidth(cue))
            if cue.kind == .volume {
                NotchOfficeVUMeter(level: level, colors: NotchOfficeInk.colors())
            } else {
                NotchMeter(value: level, height: 5, colors: NotchOfficeLevelMeter.daylight)
                    .frame(maxWidth: 96)
                    .animation(calm ? nil : .easeOut(duration: 0.14), value: level)
            }
            if showsReading {
                VStack(alignment: .leading, spacing: 0) {
                    Text(reading)
                        .font(Font(NotchOfficeMoments.levelReadingFont as CTFont))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .contentTransition(calm ? .identity : .numericText())
                    if let caption { NotchOfficeBandCaption(kind: cue.kind, caption: caption, calm: calm) }
                }
                .frame(width: NotchOfficeMoments.expandedReadingColumn(cue, caption: captionFits), alignment: .leading)
                .animation(calm ? NotchSongMotion.reduced : .easeOut(duration: 0.2), value: caption)
            }
        }
        .animation(calm ? nil : .easeOut(duration: 0.14), value: reading)
        .notchPunchIn(trigger)
        .transaction { $0.disablesAnimations = false }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The boombox for the volume, the window's blinds for brightness.
private struct NotchOfficeLevelMark: View {
    let cue: NotchOfficeCue
    let level: Double
    let calm: Bool

    var body: some View {
        if cue.kind == .volume {
            NotchOfficeMiniBoombox(level: level, colors: NotchOfficeInk.colors(), calm: calm)
        } else {
            NotchOfficeWindowBlinds(level: level, calm: calm)
        }
    }
}

/// A lower third whose words change while its moment shows: a level's band,
/// or a copy's turn. Its words are its identity, so it arrives again only
/// when they change, never on a step inside a band: the last words are gone
/// in a blink, before the next come in out of their blur, so the two never
/// overlap. Calm, the next ones fade in.
struct NotchOfficeBandCaption: View {
    let kind: NotchOfficeCue.Kind
    let caption: String
    let calm: Bool
    /// A capsule in a taller bar reads it at the card's size.
    var size: NotchLowerThird.Size = .strip
    /// How long after its words change they arrive: a level's follow the
    /// key at once, a copy's land after its title, as the sheet comes out.
    var delay: Double = 0.1

    var body: some View {
        ZStack(alignment: .leading) {
            NotchLowerThird(caption: caption, size: size, trigger: calm ? nil : "\(kind)|\(caption)", delay: delay)
                .id(caption)
                // Calm, the next words wait for the last to go, so the two
                // never show over each other.
                .transition(.asymmetric(insertion: calm ? .opacity.animation(NotchSongMotion.reduced.delay(0.08)) : .opacity,
                                        removal: .opacity.animation(.easeOut(duration: 0.08))))
        }
        .transition(.opacity)
    }
}

/// The connect card's boombox at the size of a notice's mark. Its cones
/// swell with the level and kick with each press; muted, they go flat and
/// grey and a slash draws across. A held key's steps kick it in time rather
/// than restarting the kick each step.
struct NotchOfficeMiniBoombox: View {
    let level: Double
    let colors: [Color]
    /// Reduce Motion or Low Power Mode: no kick, and the slash fades in.
    let calm: Bool
    @State private var kicks = 0
    @State private var lastKick: TimeInterval?
    @State private var slashed = false

    private typealias Big = NotchOfficeBoombox
    /// The connect card's geometry, scaled to the mini's width.
    private static let scale = NotchOfficeMoments.miniBoombox.width / Big.outline.width

    private var muted: Bool {
        NotchOfficeMoments.volumeBand(percent: NotchOfficeMoments.percent(level)) == .mute
    }

    private var paint: [Color] { colors.count > 1 ? colors : colors + colors + [.white, .white] }

    var body: some View {
        let s = Self.scale
        let size = NotchOfficeMoments.miniBoombox
        ZStack {
            // The carrying handle, mostly behind the body.
            RoundedRectangle(cornerRadius: Big.handleCorner * s + 0.6, style: .continuous)
                .stroke(Color(white: 0.52), lineWidth: 1.1)
                .frame(width: Big.handle.width * s, height: Big.handle.height * s)
                .offset(y: Big.handleY * s)
            RoundedRectangle(cornerRadius: Big.bodyCorner * s + 0.4, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.33), NotchOfficeInk.boombox],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: Big.bodyCorner * s + 0.4, style: .continuous)
                        .strokeBorder(.white.opacity(0.32), lineWidth: 0.6)
                }
                .frame(width: Big.body.width * s, height: Big.body.height * s)
                .offset(y: Big.bodyY * s)
            // The tape deck between the cones, its window lit in the song's colour.
            RoundedRectangle(cornerRadius: 0.6, style: .continuous)
                .fill(Color(white: 0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 0.6, style: .continuous)
                        .fill(paint[0].opacity(muted ? 0.15 : 0.75))
                        .padding(.horizontal, 1)
                        .padding(.vertical, 1)
                }
                .frame(width: 4.4, height: 3)
                .offset(y: Big.deckY * s - 0.6)
            cones
            slash(size)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
        .onChange(of: level) { kick() }
        .task {
            // One kick as the moment lands, with the punch-in.
            try? await Task.sleep(nanoseconds: 120_000_000)
            kick()
        }
        .task(id: muted) {
            guard muted, !calm, !slashed else {
                withAnimation(calm ? NotchSongMotion.reduced : .easeOut(duration: 0.16)) { slashed = muted }
                return
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(.easeOut(duration: 0.22)) { slashed = true }
        }
    }

    private var cones: some View {
        ZStack {
            cone(left: true)
            cone(left: false)
        }
        .keyframeAnimator(initialValue: CGFloat(1), trigger: kicks) { content, kick in
            content.scaleEffect(kick)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(NotchOfficeMoments.coneKick, duration: 0.07)
                CubicKeyframe(1, duration: NotchOfficeMoments.coneKickDuration - 0.07)
            }
        }
    }

    private func cone(left: Bool) -> some View {
        let s = Self.scale
        let side = Big.coneSide * s
        return ZStack {
            Circle().fill(Color(white: 0.06))
            Circle()
                .fill(RadialGradient(colors: [paint[0].opacity(0.95), paint[1].opacity(0.6), Color(white: 0.1)],
                                     center: .center, startRadius: 0, endRadius: side / 2))
                .padding(0.8)
            Circle().strokeBorder(AngularGradient(colors: paint + [paint[0]], center: .center), lineWidth: 0.9)
            // The dust cap, catching the light, as the connect card's does.
            Circle().fill(paint[0]).frame(width: side * 0.3, height: side * 0.3)
                .overlay(alignment: .topLeading) {
                    Circle().fill(.white.opacity(0.7)).frame(width: side * 0.11, height: side * 0.11)
                        .offset(x: side * 0.04, y: side * 0.04)
                }
        }
        .frame(width: side, height: side)
        // Flat and grey at silence.
        .saturation(muted ? 0 : 1)
        .opacity(muted ? 0.42 : 1)
        .scaleEffect(x: muted ? 0.92 : NotchOfficeMoments.coneScale(level),
                     y: muted ? 0.92 : NotchOfficeMoments.coneScale(level))
        .animation(calm ? nil : .spring(response: 0.28, dampingFraction: 0.62), value: level)
        .offset(x: (left ? -Big.coneOffset : Big.coneOffset) * s, y: Big.deckY * s)
    }

    /// A slash across the whole boombox, cut out of it by a dark keyline.
    private func slash(_ size: CGSize) -> some View {
        let line = Path { path in
            path.move(to: CGPoint(x: 1.2, y: 0.6))
            path.addLine(to: CGPoint(x: size.width - 1.2, y: size.height - 0.2))
        }
        return ZStack {
            line.trim(from: 0, to: slashed || calm ? 1 : 0)
                .stroke(.black, style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
            line.trim(from: 0, to: slashed || calm ? 1 : 0)
                .stroke(NotchOfficeInk.beet, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
        }
        .frame(width: size.width, height: size.height)
        .opacity(slashed ? 1 : 0)
    }

    /// One kick per press, unless the last one is still playing out.
    private func kick() {
        guard !calm, !muted else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard NotchOfficeMoments.coneKicks(at: now, lastKick: lastKick) else { return }
        lastKick = now
        kicks += 1
    }
}

/// A conference-room window beside the brightness reading: five slats that
/// open with the level, the daylight behind them brightening as they do.
/// The slats are the blinds texture's own (NotchBlindsShape).
struct NotchOfficeWindowBlinds: View {
    let level: Double
    let calm: Bool

    private static let slats = 5
    /// What is left of a slat fully open.
    private static let openSlat: CGFloat = 0.8

    var body: some View {
        let side = NotchOfficeMoments.blindsSide
        let open = CGFloat(level.isFinite ? min(1, max(0, level)) : 0)
        let pane = side - 3
        let pitch = pane / CGFloat(Self.slats)
        // Closed, a hairline still parts each slat from the next.
        let closed = pitch - 0.55
        ZStack {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(LinearGradient(colors: [NotchOfficeInk.jelly, NotchOfficeInk.paper],
                                     startPoint: .top, endPoint: .bottom))
                // Light comes quickly as the slats part, as through real blinds.
                .opacity(0.1 + 0.9 * sqrt(open))
                .shadow(color: NotchOfficeInk.jelly.opacity(0.6 * open), radius: 4 * open)
                .frame(width: pane, height: pane)
            NotchBlindsShape(slat: closed - (closed - Self.openSlat) * open, pitch: pitch)
                .fill(Color(white: 0.44))
                .frame(width: pane, height: pane)
            RoundedRectangle(cornerRadius: 2.4, style: .continuous)
                .strokeBorder(NotchOfficeInk.paper.opacity(0.9), lineWidth: 1.2)
                .frame(width: side, height: side)
        }
        .frame(width: side, height: side)
        .animation(calm ? nil : .easeOut(duration: 0.18), value: open)
        .accessibilityHidden(true)
    }
}

/// Nine segments stepping up from the camera to the island's end, lit low
/// to high in the moment's colours, the top two in beet. Under Reduce Motion
/// or in Low Power Mode they switch without easing.
struct NotchOfficeVUMeter: View {
    let level: Double
    let colors: [Color]
    /// The segments' heights in a capsule shorter than the strip; their
    /// widths stay.
    var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared

    var body: some View {
        let lit = NotchOfficeMoments.vuLit(level)
        let paints = NotchOfficeMoments.vuColors(colors.map { NSColor($0) }).map { Color(nsColor: $0) }
        HStack(alignment: .bottom, spacing: NotchOfficeMoments.vuGap) {
            ForEach(0..<NotchOfficeMoments.vuSegments, id: \.self) { segment in
                let on = segment < lit
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(on ? paints[segment] : Color.white.opacity(0.14))
                    .shadow(color: on ? paints[segment].opacity(0.55) : .clear, radius: on ? 2.5 : 0)
                    .frame(width: NotchOfficeMoments.vuBar, height: NotchOfficeMoments.vuHeight(segment) * scale)
            }
        }
        .frame(height: NotchOfficeMoments.vuHeights.highest * scale, alignment: .bottom)
        .animation(reduceMotion || lowPower.isOn ? nil : .easeOut(duration: 0.12), value: lit)
        .accessibilityHidden(true)
    }
}
