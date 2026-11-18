// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// "Employee of the Month": the agents' notices on the Office moments. The
/// agent's mark, exactly as its maker draws it (NotchAgentMark), sits in its
/// comet ring as the wing showed it at work, and the ring closes in the
/// moment's colour: gold for a finish, with a trophy springing in beside it,
/// one glint across the trophy and a short burst of confetti in the agent's
/// own colours; amber for a limit running low; the agent's colours for a
/// renewal; beet for a spent budget, with one shake. Everything plays once
/// as the notice arrives and settles; nothing loops. Reduce Motion and Low
/// Power Mode show it settled, with the fade alone. The rules behind it are
/// NotchOfficeAgents.swift.
struct NotchOfficeAgentBadge: View {
    let beat: NotchOfficeAgentBeat
    let provider: AgentProvider?
    /// Changes once per moment: a new one plays again from the start, and
    /// never on top of the last.
    let trigger: String
    /// How far the confetti flies, in the badge's own points: a capsule
    /// keeps it inside its body.
    var confettiReach = NotchOfficeMoments.confettiReach
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared
    @State private var closed: CGFloat = 0
    @State private var bloom = false
    @State private var awarded = false
    @State private var shakes = 0

    private typealias Moments = NotchOfficeMoments
    private var calm: Bool { reduceMotion || lowPower.isOn }
    private var side: CGFloat { Moments.agentRingSide }

    /// The ring closing, as the wing's ring closes when a turn ends, on the
    /// settling curve the island's arrivals share.
    static let close = Animation.timingCurve(0.16, 1, 0.3, 1, duration: NotchAgentWings.closing)

    var body: some View {
        let ring = Moments.agentRing(beat, provider: provider).map { Color(nsColor: $0.nsColor) }
        ZStack(alignment: .topLeading) {
            if beat == .finished {
                NotchOfficeConfetti(colors: Moments.agentConfetti(provider).map { Color(nsColor: $0.nsColor) },
                                    trigger: trigger, reach: confettiReach, origin: side / 2 - 1,
                                    delay: NotchAgentWings.closing * 0.8)
                    .frame(width: side, height: side)
            }
            NotchOfficeAgentRing(provider: provider, colors: ring, closed: calm ? 1 : closed, bloom: calm || bloom)
                .frame(width: side, height: side)
                .overlay { mark }
                .keyframeAnimator(initialValue: CGFloat(0), trigger: shakes) { content, sway in
                    content.offset(x: sway).rotationEffect(.degrees(Double(sway) * 3))
                } keyframes: { _ in
                    // One shake of the head, as the battery running out gives its mug.
                    KeyframeTrack {
                        CubicKeyframe(-2.4, duration: 0.07)
                        CubicKeyframe(2.2, duration: 0.09)
                        CubicKeyframe(-1.5, duration: 0.09)
                        CubicKeyframe(0.7, duration: 0.08)
                        CubicKeyframe(0, duration: 0.07)
                    }
                }
            if beat == .finished {
                NotchOfficeTrophy()
                    .frame(width: Moments.trophySize.width, height: Moments.trophySize.height)
                    .notchGlint(trigger, delay: NotchAgentWings.closing + 0.3)
                    .scaleEffect(awarded || calm ? 1 : 0.2, anchor: .bottom)
                    .rotationEffect(.degrees(awarded || calm ? 0 : -24), anchor: .bottom)
                    .opacity(awarded || calm ? 1 : 0)
                    .offset(x: Moments.agentBadgeWidth - Moments.trophySize.width,
                            y: side - Moments.trophySize.height + 2)
            }
        }
        .frame(width: Moments.agentBadgeWidth, height: side, alignment: .topLeading)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task(id: trigger) { await play() }
    }

    /// The agent's own mark, never redrawn; a spent budget, which no one
    /// agent owns, keeps the dollar sign.
    @ViewBuilder private var mark: some View {
        if beat != .budgetReached, let provider {
            NotchAgentMark(provider: provider, size: NotchAgentWings.markSize(ring: side))
        } else {
            Image(systemName: "dollarsign")
                .font(.system(size: (side * 0.5).rounded(), weight: .bold))
                .foregroundStyle(NotchOfficeInk.paper)
        }
    }

    @MainActor private func play() async {
        var reset = Transaction(animation: nil)
        reset.disablesAnimations = true
        withTransaction(reset) { closed = 0; bloom = false; awarded = false }
        guard !calm else { return }
        try? await Task.sleep(nanoseconds: 60_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(Self.close) { closed = 1 }
        withAnimation(NotchSongMotion.glow.delay(NotchAgentWings.closing * 0.8)) { bloom = true }
        if beat == .finished {
            // The trophy lands as the ring meets itself.
            withAnimation(NotchSongMotion.spring.delay(NotchAgentWings.closing * 0.6)) { awarded = true }
        }
        if beat == .budgetReached {
            try? await Task.sleep(nanoseconds: UInt64(NotchAgentWings.closing * 1_000_000_000))
            guard !Task.isCancelled else { return }
            shakes += 1
        }
    }
}

/// The ring: the agent's comet as the wing showed it at work, its head at
/// the top, with the moment's colour stroking round from the head until it
/// closes, then glowing softly. Without an agent it starts as a faint track.
struct NotchOfficeAgentRing: View {
    let provider: AgentProvider?
    /// Deep, light and deep again, as metal catches the light.
    let colors: [Color]
    /// How far round the closing colour has come, 0 to 1.
    let closed: CGFloat
    let bloom: Bool

    var body: some View {
        let line = NotchOfficeMoments.agentRingLine
        let paint = colors.count > 2 ? colors : colors + colors + colors
        let stops = provider?.glowStops.map { Color(nsColor: $0.nsColor) }
        ZStack {
            Circle().inset(by: line / 2)
                .stroke(paint[0].opacity(0.22), lineWidth: line)
            if let stops {
                // The comet's tail fades out behind its head, counterclockwise
                // from the top, as it orbits clockwise in the wing.
                Circle().inset(by: line / 2)
                    .stroke(AngularGradient(stops: [.init(color: stops[0].opacity(0), location: 0),
                                                    .init(color: stops[0].opacity(0), location: 0.32),
                                                    .init(color: stops[0].opacity(0.75), location: 0.62),
                                                    .init(color: stops[1].opacity(0.95), location: 0.86),
                                                    .init(color: stops[2], location: 1)],
                                            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                            lineWidth: line)
                    .overlay(alignment: .top) {
                        Circle().fill(.white.opacity(0.9)).frame(width: line + 0.4, height: line + 0.4)
                            .offset(y: -0.2)
                    }
                    .opacity(Double(1 - closed))
            }
            Circle().inset(by: line / 2)
                .trim(from: 0, to: closed)
                .stroke(AngularGradient(colors: [paint[0], paint[1], paint[2], paint[1], paint[0]], center: .center),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .shadow(color: paint[1].opacity(bloom ? 0.7 : 0), radius: bloom ? 3 : 0)
    }
}

/// A small, generic trophy: a cup with two handles on a short stem and a
/// two-step base, in statuette gold, with a dark keyline so it reads against
/// the ring it stands beside. An original shape, not any award's sculpt.
struct NotchOfficeTrophy: View {
    private static let deep = Color(red: 0xB0 / 255, green: 0x82 / 255, blue: 0x24 / 255)
    private static let base = Color(red: 0x5A / 255, green: 0x44 / 255, blue: 0x14 / 255)

    var body: some View {
        GeometryReader { proxy in
            let s = CGSize(width: proxy.size.width / 9, height: proxy.size.height / 12)
            let gold = LinearGradient(colors: [NotchOfficeInk.goldLight, NotchOfficeInk.gold, Self.deep],
                                      startPoint: .top, endPoint: .bottom)
            ZStack {
                Self.handles(s).stroke(.black.opacity(0.85), lineWidth: 2.4 * s.width)
                Self.cup(s).stroke(.black.opacity(0.85), lineWidth: 1.6 * s.width)
                Self.plinth(s).stroke(.black.opacity(0.85), lineWidth: 1.6 * s.width)
                Self.handles(s).stroke(gold, lineWidth: 1 * s.width)
                Self.cup(s).fill(gold)
                Self.plinth(s).fill(Self.base)
                // The base's lip and the rim catching the light.
                Path { $0.addRect(CGRect(x: 2.6 * s.width, y: 9.0 * s.height, width: 3.8 * s.width, height: 0.9 * s.height)) }
                    .fill(NotchOfficeInk.gold)
                Path { path in
                    path.move(to: CGPoint(x: 1.9 * s.width, y: 1.05 * s.height))
                    path.addLine(to: CGPoint(x: 7.1 * s.width, y: 1.05 * s.height))
                }
                .stroke(.white.opacity(0.75), lineWidth: 0.6 * s.height)
                Path { path in
                    path.move(to: CGPoint(x: 2.7 * s.width, y: 2.2 * s.height))
                    path.addQuadCurve(to: CGPoint(x: 3.6 * s.width, y: 5.2 * s.height),
                                      control: CGPoint(x: 2.7 * s.width, y: 4.3 * s.height))
                }
                .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 0.7 * s.width, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }

    /// The bowl, the stem and the collar under it, as one piece.
    private static func cup(_ s: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 1.6 * s.width, y: 0.6 * s.height))
            path.addLine(to: CGPoint(x: 7.4 * s.width, y: 0.6 * s.height))
            path.addCurve(to: CGPoint(x: 5.0 * s.width, y: 6.4 * s.height),
                          control1: CGPoint(x: 7.4 * s.width, y: 4.4 * s.height),
                          control2: CGPoint(x: 6.1 * s.width, y: 5.9 * s.height))
            path.addLine(to: CGPoint(x: 5.0 * s.width, y: 7.6 * s.height))
            path.addLine(to: CGPoint(x: 6.4 * s.width, y: 9.0 * s.height))
            path.addLine(to: CGPoint(x: 2.6 * s.width, y: 9.0 * s.height))
            path.addLine(to: CGPoint(x: 4.0 * s.width, y: 7.6 * s.height))
            path.addLine(to: CGPoint(x: 4.0 * s.width, y: 6.4 * s.height))
            path.addCurve(to: CGPoint(x: 1.6 * s.width, y: 0.6 * s.height),
                          control1: CGPoint(x: 2.9 * s.width, y: 5.9 * s.height),
                          control2: CGPoint(x: 1.6 * s.width, y: 4.4 * s.height))
            path.closeSubpath()
        }
    }

    /// Two loops either side of the bowl.
    private static func handles(_ s: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 1.7 * s.width, y: 1.6 * s.height))
            path.addCurve(to: CGPoint(x: 2.3 * s.width, y: 4.6 * s.height),
                          control1: CGPoint(x: 0.2 * s.width, y: 1.4 * s.height),
                          control2: CGPoint(x: 0.3 * s.width, y: 4.0 * s.height))
            path.move(to: CGPoint(x: 7.3 * s.width, y: 1.6 * s.height))
            path.addCurve(to: CGPoint(x: 6.7 * s.width, y: 4.6 * s.height),
                          control1: CGPoint(x: 8.8 * s.width, y: 1.4 * s.height),
                          control2: CGPoint(x: 8.7 * s.width, y: 4.0 * s.height))
        }
    }

    /// The dark block the cup stands on.
    private static func plinth(_ s: CGSize) -> Path {
        Path(roundedRect: CGRect(x: 1.7 * s.width, y: 9.6 * s.height, width: 5.6 * s.width, height: 2.0 * s.height),
             cornerRadius: 0.5 * s.width, style: .continuous)
    }
}

/// The real information beside the badge, large, with the caption under it.
struct NotchOfficeAgentWords: View {
    let title: String
    /// Nil where the strip has no room for a second line, or the language no joke.
    let caption: String?
    let beat: NotchOfficeAgentBeat
    let trigger: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Font(NotchOfficeMoments.agentTitleFont as CTFont))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .notchArrival(trigger)
            if let caption {
                NotchLowerThird(caption: caption,
                                accent: beat == .budgetReached ? NotchOfficeInk.beet : NotchOfficeInk.mustard,
                                trigger: trigger, delay: 0.32)
            }
        }
    }
}

/// The far side: the turn's time and cost, the share of the limit, or what
/// the budget came to, as large as the title.
struct NotchOfficeAgentReading: View {
    let detail: String
    let trigger: String

    var body: some View {
        Text(detail)
            .font(Font(NotchOfficeMoments.agentDetailFont as CTFont))
            .foregroundStyle(.white.opacity(0.88))
            .lineLimit(1)
            .notchArrival(trigger, delay: 0.2)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

extension NotchNotice {
    /// Changes once per agent moment: its kind, its words and its reading,
    /// so the same agent finishing again plays it again.
    var officeAgentKey: String? {
        guard let beat = office?.agentBeat else { return nil }
        return "agent|\(beat)|\(title)|\(detail)"
    }
}
