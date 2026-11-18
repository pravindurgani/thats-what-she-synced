// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// What an agent's notice is about, for its Office moment.
enum NotchOfficeAgentBeat: Equatable, CaseIterable {
    /// A turn ended with its work done: "Employee of the Month".
    case finished
    /// A plan window running low.
    case limitWarning
    /// A warned window renewed.
    case limitReset
    /// The day's spending passed its budget.
    case budgetReached
}

extension NotchOfficeCue {
    /// The agent moment this cue is, or nil for every other moment.
    var agentBeat: NotchOfficeAgentBeat? {
        if case .agent(let beat) = kind { return beat }
        return nil
    }
}

/// One piece of a confetti burst: where it lands from the burst's centre,
/// how far it drifts down as it fades, how far it turns, its size and which
/// of the burst's colours it wears. Laid out once, the same every time, so a
/// burst is a fixed, finite flourish rather than a simulation.
struct NotchOfficeConfettiBit: Equatable {
    let x: CGFloat
    let y: CGFloat
    let fall: CGFloat
    let spin: Double
    let width: CGFloat
    let height: CGFloat
    let color: Int
}

/// A short burst of confetti from one point, for any Office moment that
/// earns one. The view is NotchOfficeConfetti in NotchOfficeComponents.swift.
enum NotchOfficeConfettiBurst {
    /// Enough to read as confetti at the island's size, few enough to stay small.
    static let counts: ClosedRange<Int> = 8...12
    static let defaultCount = 12
    /// The burst is wider than tall, as the strip is.
    static let flatten: CGFloat = 0.8
    /// The furthest a piece drifts down as it fades.
    static let fall: CGFloat = 3

    /// `count` bits (kept within `counts`) spread evenly around the centre,
    /// alternately near and far, reaching at most `reach` points, in
    /// `colors` colours taken in turn.
    static func bits(count: Int = defaultCount, reach: CGFloat, colors: Int) -> [NotchOfficeConfettiBit] {
        let count = min(counts.upperBound, max(counts.lowerBound, count))
        let reach = reach.isFinite ? max(0, reach) : 0
        let colors = max(1, colors)
        return (0..<count).map { index in
            // A quarter step off the axes, so no bit flies flat along the strip.
            let angle = (Double(index) + 0.25) / Double(count) * 2 * Double.pi
            let distance = reach * (index.isMultiple(of: 2) ? 1 : 0.78)
            // Long strips and short squares, turning either way.
            let strip = index % 3 != 1
            return NotchOfficeConfettiBit(x: CGFloat(cos(angle)) * distance,
                                          y: CGFloat(sin(angle)) * distance * flatten,
                                          fall: index.isMultiple(of: 2) ? fall : fall * 0.66,
                                          spin: (index.isMultiple(of: 2) ? 1 : -1) * Double(160 + index * 23),
                                          width: strip ? 3.6 : 2.4, height: strip ? 1.7 : 2.4,
                                          color: index % colors)
        }
    }
}

/// "Employee of the Month": the agents' notices on the Office moments. A
/// turn ending closes the agent's ring in gold, a trophy springs in beside
/// its mark and a short burst of confetti in the agent's own colours goes
/// off; a limit running low closes it in amber, a renewal in the agent's
/// colours and a spent budget in beet. The real information stays first:
/// what happened large, the time and cost or the share on the far side.
/// The views are NotchOfficeAgentViews.swift.
extension NotchOfficeMoments {
    // MARK: Captions

    /// The finish's three captions, one picked from the turn itself.
    static let finishCaptions = ["Employee of the Month.", "That's a wrap.", "Take the rest of the day."]
    static let limitWarningCaption = "Corporate is watching."
    static let limitResetCaption = "Fresh quota. Go nuts."
    static let budgetCaption = "The budget has left the building."
    /// A turn this long has earned the afternoon off.
    static let marathon: TimeInterval = 20 * 60

    static func agentBeat(for event: AgentUsageEvent) -> NotchOfficeAgentBeat {
        switch event {
        case .finished: return .finished
        case .limitWarning: return .limitWarning
        case .limitReset: return .limitReset
        case .budgetReached: return .budgetReached
        }
    }

    /// A marathon earns the rest of the day; any other turn gets one of the
    /// first two, picked by a fixed hash of the agent, the whole seconds and
    /// the cents, so the same finish always reads the same and the next one
    /// usually reads differently, with no randomness.
    static func finishCaption(provider: AgentProvider, duration: TimeInterval, cost: Double) -> String {
        if duration.isFinite, duration >= marathon { return finishCaptions[2] }
        func whole(_ value: Double) -> Int64 { value.isFinite ? Int64(min(1e12, max(0, value)).rounded()) : 0 }
        let seed = "\(provider.rawValue)|\(whole(duration))|\(whole(cost * 100))"
        return finishCaptions[Int(stableHash(seed) % 2)]
    }

    static func agentCaption(for event: AgentUsageEvent) -> String {
        switch event {
        case .finished(let provider, let duration, let cost, _, _):
            return finishCaption(provider: provider, duration: duration, cost: cost)
        case .limitWarning: return limitWarningCaption
        case .limitReset: return limitResetCaption
        case .budgetReached: return budgetCaption
        }
    }

    /// Every caption a beat can show, so its side is sized once for the widest.
    static func agentCaptions(for beat: NotchOfficeAgentBeat) -> [String] {
        switch beat {
        case .finished: return finishCaptions
        case .limitWarning: return [limitWarningCaption]
        case .limitReset: return [limitResetCaption]
        case .budgetReached: return [budgetCaption]
        }
    }

    static func agentCue(for event: AgentUsageEvent, language: AppLanguage) -> NotchOfficeCue {
        let beat = agentBeat(for: event)
        let captions = showsCaptions(in: language)
        return NotchOfficeCue(kind: .agent(beat), caption: captions ? agentCaption(for: event) : nil,
                              widestCaption: captions ? widest(agentCaptions(for: beat)) : nil)
    }

    /// Only a finish is the agent's own moment, which its wing's check
    /// would otherwise repeat once the notice goes.
    static func celebratesFinish(_ cue: NotchOfficeCue?) -> Bool { cue?.agentBeat == .finished }

    // MARK: Colours

    /// Statuette gold, as the full mug's glint.
    static let gold = NotchRGB(hex: 0xE3B23C)
    static let goldLight = NotchRGB(hex: 0xF7D774)
    static let amber = NotchRGB(hex: 0xF29A1F)
    static let amberLight = NotchRGB(hex: 0xFFC65C)
    static let beet = NotchRGB(hex: 0xC0392B)
    static let beetLight = NotchRGB(hex: 0xE8705C)

    /// The ring's colours as it closes, deep to light to deep, so it reads
    /// as metal: gold for a finish, amber for a warning, the agent's own for
    /// a renewal and beet for a spent budget.
    static func agentRing(_ beat: NotchOfficeAgentBeat, provider: AgentProvider?) -> [NotchRGB] {
        switch beat {
        case .finished: return [gold, goldLight, gold]
        case .limitWarning: return [amber, amberLight, amber]
        case .limitReset:
            guard let provider else { return [gold, goldLight, gold] }
            return [provider.glowStops[0], provider.glowStops[2], provider.glowStops[1]]
        case .budgetReached: return [beet, beetLight, beet]
        }
    }

    /// The confetti wears the agent's three colours, and gold where no
    /// agent is named.
    static func agentConfetti(_ provider: AgentProvider?) -> [NotchRGB] {
        provider?.glowStops ?? [gold, goldLight, NotchRGB(hex: 0xF4F1E8)]
    }

    // MARK: Measures

    /// The ring around the mark beside the camera, and the line it closes in.
    static let agentRingSide: CGFloat = 18
    static let agentRingLine: CGFloat = 2
    /// The trophy, and how far past the ring's right edge it stands: pinned
    /// to the ring's frame, clear of the mark inside it.
    static let trophySize = CGSize(width: 8.5, height: 11.5)
    static let trophyReach: CGFloat = 7
    /// How far the confetti flies from the ring's centre, inside the strip.
    static let confettiReach: CGFloat = 15
    /// Between the badge and the words: the words start where a volume
    /// moment's reading does, beside its boombox.
    static var agentMarkGap: CGFloat { max(3, miniBoombox.width + levelMarkGap - agentBadgeWidth) }
    /// The real information in the family's title size, and the reading
    /// across the camera as every moment's.
    static var agentTitleFont: NSFont { titleFont }
    static var agentDetailFont: NSFont { detailFont }
    /// The widest an agent moment's side grows, as a plain notice's.
    static let agentWingLimit: CGFloat = 240

    /// Every beat's badge takes the same room, so its words start in one
    /// place whatever the moment.
    static var agentBadgeWidth: CGFloat { agentRingSide + trophyReach }

    static func agentTextWidth(_ text: String, font: NSFont) -> CGFloat {
        text.isEmpty ? 0 : (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    /// An agent moment's sides beside the camera: the badge, the title and
    /// the widest caption the beat can show on one; the detail on the
    /// other. `inset` is the room kept inside the island's curved ends and
    /// `cameraGap` the room kept beside the camera. Never narrower than
    /// `minimum`, so a moment replacing another holds the island still.
    static func agentWings(_ cue: NotchOfficeCue, title: String, detail: String, inset: CGFloat, cameraGap: CGFloat,
                           minimumWing: CGFloat, minimum: NotchNoticeWings = .zero) -> NotchNoticeWings {
        let caption = (cue.widestCaption ?? cue.caption).map { captionWidth($0) } ?? 0
        let words = max(agentTextWidth(title, font: agentTitleFont), caption)
        func fitted(_ content: CGFloat) -> CGFloat { min(agentWingLimit, max(minimumWing, ceil(content))) }
        let leading = fitted(inset + agentBadgeWidth + agentMarkGap + words + cameraGap + 2)
        let reading = agentTextWidth(detail, font: agentDetailFont)
        let trailing = fitted(reading > 0 ? cameraGap + reading + inset + 2 : 0)
        return NotchNoticeWings(leading: max(minimum.leading, leading), trailing: max(minimum.trailing, trailing))
    }

    // MARK: In the capsule

    /// The ring as the capsule draws a working agent's, and the badge scaled to it.
    static func capsuleAgentScale(_ geometry: NotchGeometry) -> CGFloat {
        NotchCapsuleLayout.agentRing(geometry) / agentRingSide
    }

    static func capsuleAgentBadgeWidth(_ geometry: NotchGeometry) -> CGFloat {
        (agentBadgeWidth * capsuleAgentScale(geometry)).rounded(.up)
    }

    /// The confetti's reach in the badge's own points, short enough that a
    /// burst scaled into the capsule stays inside its body.
    static func capsuleConfettiReach(_ geometry: NotchGeometry) -> CGFloat {
        let scale = capsuleAgentScale(geometry)
        guard scale > 0 else { return 0 }
        let room = (geometry.stripBodyHeight / 2 - 1) / scale - NotchOfficeConfettiBurst.fall
        return min(confettiReach, max(0, room / NotchOfficeConfettiBurst.flatten))
    }

    /// A capsule agent moment's row before its caption: the badge, the title
    /// and the detail, in the capsule's own fonts.
    static func capsuleAgentRow(title: String, detail: String, geometry: NotchGeometry) -> CGFloat {
        let layout = NotchCapsuleLayout.self
        let detailWidth = layout.width(detail, font: layout.detailFont)
        return capsuleAgentBadgeWidth(geometry) + layout.spacing + layout.width(title, font: layout.titleFont)
            + (detailWidth > 0 ? layout.groupSpacing + detailWidth : 0)
    }
}
