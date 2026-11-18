// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// "Employee of the Month", the agents' Office moments: which event is which
/// moment, the captions and how they vary, the ring's colours, the confetti's
/// layout, the room each moment takes, and the wing's check giving way to a
/// finish the notice already celebrated.
enum NotchOfficeAgentsTests {
    static func run(_ suite: TestSuite) {
        beats(suite)
        captions(suite)
        cues(suite)
        colours(suite)
        confetti(suite)
        measures(suite)
        capsule(suite)
        celebrations(suite)
    }

    private typealias Moments = NotchOfficeMoments

    private static let window = AgentLimitWindow(id: "claude-session", kind: .session, minutes: 300, scope: nil,
                                                 usedPercent: 82, resetsAt: nil)

    private static func finished(_ provider: AgentProvider = .claude, _ duration: TimeInterval = 94,
                                 _ cost: Double = 4.12) -> AgentUsageEvent {
        .finished(provider: provider, duration: duration, cost: cost, tokens: 1200, project: "app")
    }

    private static func beats(_ suite: TestSuite) {
        suite.expect(Moments.agentBeat(for: finished()) == .finished
                     && Moments.agentBeat(for: .limitWarning(provider: .codex, window: window)) == .limitWarning
                     && Moments.agentBeat(for: .limitReset(provider: .claude, window: window)) == .limitReset
                     && Moments.agentBeat(for: .budgetReached(spent: 12, budget: 10)) == .budgetReached,
                     "each agent event is its own moment")
        suite.expect(Moments.celebratesFinish(Moments.agentCue(for: finished(), language: .enUS))
                     && !Moments.celebratesFinish(Moments.agentCue(for: .limitWarning(provider: .claude, window: window),
                                                                   language: .enUS))
                     && !Moments.celebratesFinish(nil)
                     && !Moments.celebratesFinish(Moments.batteryCue(.charged, percent: 100, language: .enUS)),
                     "only a finish takes the place of its wing's check")
        suite.expect(Moments.batteryCue(.charged, percent: 100, language: .enUS).agentBeat == nil,
                     "other moments are no agent's")
    }

    private static func captions(_ suite: TestSuite) {
        suite.expect(Moments.finishCaptions == ["Employee of the Month.", "That's a wrap.", "Take the rest of the day."],
                     "a finish has its three captions")
        suite.expect(Moments.agentCaption(for: .limitWarning(provider: .claude, window: window)) == "Corporate is watching."
                     && Moments.agentCaption(for: .limitReset(provider: .codex, window: window)) == "Fresh quota. Go nuts."
                     && Moments.agentCaption(for: .budgetReached(spent: 12, budget: 10))
                        == "The budget has left the building.",
                     "a warning, a renewal and a spent budget each have theirs")
        suite.expect(Moments.finishCaption(provider: .claude, duration: Moments.marathon, cost: 3)
                        == "Take the rest of the day."
                     && Moments.finishCaption(provider: .codex, duration: 3 * 3600, cost: 0) == "Take the rest of the day.",
                     "a marathon earns the rest of the day")
        let picks = (0..<40).map { Moments.finishCaption(provider: .claude, duration: TimeInterval(60 + $0 * 7), cost: 1.5) }
        suite.expect(Set(picks) == Set(Moments.finishCaptions.prefix(2)),
                     "shorter turns read one of the first two, and both turn up")
        suite.expect(picks == (0..<40).map { Moments.finishCaption(provider: .claude, duration: TimeInterval(60 + $0 * 7),
                                                                   cost: 1.5) },
                     "the same finish always reads the same: picked, not drawn at random")
        suite.expect(Moments.finishCaptions.contains(Moments.finishCaption(provider: .codex, duration: .nan, cost: .infinity))
                     && Moments.finishCaptions.contains(Moments.finishCaption(provider: .claude, duration: -5, cost: 1e300)),
                     "a reading that is not a number still picks a caption")
        let all = Moments.finishCaptions + [Moments.limitWarningCaption, Moments.limitResetCaption, Moments.budgetCaption]
        suite.expect(all.allSatisfy { $0.count <= 34 }, "every caption stays short")
    }

    private static func cues(_ suite: TestSuite) {
        let cue = Moments.agentCue(for: finished(), language: .enUS)
        suite.expect(cue.kind == .agent(.finished) && cue.agentBeat == .finished
                     && Moments.finishCaptions.contains(cue.caption ?? "")
                     && cue.widestCaption == Moments.widest(Moments.finishCaptions),
                     "a finish carries its caption and sizes its side for the widest of the three")
        let german = Moments.agentCue(for: finished(), language: .de)
        suite.expect(german.kind == .agent(.finished) && german.caption == nil && german.widestCaption == nil,
                     "another language keeps the moment and drops the joke")
        let budget = Moments.agentCue(for: .budgetReached(spent: 12, budget: 10), language: .enUS)
        suite.expect(budget.caption == Moments.budgetCaption && budget.widestCaption == Moments.budgetCaption,
                     "a single caption is its own widest")
        suite.expect(!cue.opensCard && !cue.isLevel && !cue.showsMug, "an agent moment stays in the strip, a mark and words")
    }

    private static func colours(_ suite: TestSuite) {
        suite.expect(Moments.gold == NotchRGB(hex: 0xE3B23C) && Moments.goldLight == NotchRGB(hex: 0xF7D774)
                     && Moments.agentRing(.finished, provider: .codex) == [Moments.gold, Moments.goldLight, Moments.gold],
                     "a finish closes the ring in statuette gold, whoever finished")
        suite.expect(Moments.agentRing(.budgetReached, provider: nil).first == NotchRGB(hex: 0xC0392B),
                     "a spent budget closes it in beet")
        let amber = Moments.agentRing(.limitWarning, provider: .claude)
        suite.expect(amber.allSatisfy { $0.hsb.hue > 0.06 && $0.hsb.hue < 0.14 } && amber[1].luminance > amber[0].luminance,
                     "a warning closes it in amber, lit in the middle")
        let claude = AgentProvider.claude.glowStops, codex = AgentProvider.codex.glowStops
        suite.expect(Set(Moments.agentRing(.limitReset, provider: .claude)) == Set(claude)
                     && Set(Moments.agentRing(.limitReset, provider: .codex)) == Set(codex),
                     "a renewal closes it in the agent's own colours")
        suite.expect(Moments.agentConfetti(.claude) == claude && Moments.agentConfetti(.codex) == codex
                     && Moments.agentConfetti(nil).contains(Moments.gold),
                     "the confetti wears the agent's gradient")
    }

    private static func confetti(_ suite: TestSuite) {
        typealias Burst = NotchOfficeConfettiBurst
        let bits = Burst.bits(reach: 13, colors: 3)
        suite.expect(Burst.counts.contains(bits.count) && bits.count == Burst.defaultCount,
                     "a burst is eight to twelve pieces")
        suite.expect(Burst.bits(count: 2, reach: 13, colors: 3).count == 8 && Burst.bits(count: 40, reach: 13, colors: 3).count == 12,
                     "asked for too few or too many, it keeps to the range")
        suite.expect(bits.allSatisfy { ($0.x * $0.x + $0.y * $0.y).squareRoot() <= 13.001 && $0.fall > 0 && $0.fall <= 3 },
                     "every piece lands within its reach and drifts only a little")
        suite.expect(Set(bits.map(\.color)) == [0, 1, 2], "every colour of the gradient flies")
        suite.expect(bits == Burst.bits(reach: 13, colors: 3), "the burst is laid out the same every time")
        suite.expect(bits.contains { $0.y < -6 } && bits.contains { $0.y > 6 } && bits.contains { $0.x < -6 }
                        && bits.contains { $0.x > 6 },
                     "it bursts all the way round")
        suite.expect(!bits.contains { abs($0.y) < 0.5 }, "no piece flies flat along the strip")
        let odd = Burst.bits(reach: .infinity, colors: 0)
        suite.expect(odd.allSatisfy { $0.x == 0 && $0.y == 0 && $0.color == 0 }, "an impossible reach stays put")
        suite.expect(bits.allSatisfy { abs($0.y) <= 13 * Burst.flatten + 0.001 }
                     && Moments.confettiReach * Burst.flatten + Burst.fall < 32 / 2,
                     "the burst is flatter than wide and fits in a standard strip's height")
        func capsule(bar: CGFloat) -> NotchGeometry {
            NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0, cameraWidth: 0,
                          layout: .spacious, menuBarHeight: bar, compactSideRoom: 600, silhouette: .capsule)
        }
        for bar in [CGFloat(22), 24, 30, 37] {
            let geometry = capsule(bar: bar)
            let scale = Moments.capsuleAgentScale(geometry)
            let reach = Moments.capsuleConfettiReach(geometry)
            suite.expect(reach >= 0 && reach <= Moments.confettiReach
                         && (reach * Burst.flatten + Burst.fall) * scale <= geometry.stripBodyHeight / 2,
                         "a capsule's burst stays inside its body (\(bar) pt bar)")
        }
    }

    private static func measures(_ suite: TestSuite) {
        let cue = Moments.agentCue(for: finished(), language: .enUS)
        func wings(_ cue: NotchOfficeCue, _ title: String = "Claude finished", _ detail: String = "1m 34s · $4.12",
                   minimum: NotchNoticeWings = .zero) -> NotchNoticeWings {
            Moments.agentWings(cue, title: title, detail: detail, inset: 16, cameraGap: 6, minimumWing: 36, minimum: minimum)
        }
        let finish = wings(cue)
        let caption = Moments.captionWidth(Moments.widest(Moments.finishCaptions) ?? "")
        suite.expect(finish.leading >= 16 + Moments.agentBadgeWidth + Moments.agentMarkGap + caption + 6
                     && finish.leading >= 16 + Moments.agentBadgeWidth + Moments.agentMarkGap
                        + Moments.agentTextWidth("Claude finished", font: Moments.agentTitleFont) + 6,
                     "the title side holds the badge and the wider of the title and its widest caption")
        suite.expect(finish.trailing >= 6 + Moments.agentTextWidth("1m 34s · $4.12", font: Moments.agentDetailFont) + 16,
                     "the far side holds the time and cost at the title's size")
        suite.expect(Moments.finishCaptions.allSatisfy { picked in
            var shown = cue
            shown.caption = picked
            return wings(shown) == finish
        }, "whichever caption a finish reads, its side is the same width")
        let bare = wings(NotchOfficeCue(kind: .agent(.finished)))
        suite.expect(bare.leading < finish.leading && bare.trailing == finish.trailing,
                     "without a caption the title side is only as wide as the title")
        let held = wings(Moments.agentCue(for: finished(.codex, 9, 0), language: .enUS), "Codex finished", "9s",
                         minimum: finish)
        suite.expect(held == finish, "a moment replacing a wider one keeps the island's sides")
        let long = wings(cue, String(repeating: "Claude ", count: 60), String(repeating: "$9 ", count: 60))
        suite.expect(long.leading == Moments.agentWingLimit && long.trailing == Moments.agentWingLimit,
                     "no side grows past a notice's widest")
        let budget = wings(Moments.agentCue(for: .budgetReached(spent: 12, budget: 10), language: .enUS), "Daily budget",
                           "$12.40")
        suite.expect(budget.leading < Moments.agentWingLimit
                        && budget.leading >= 16 + Moments.agentBadgeWidth + Moments.agentMarkGap
                            + Moments.captionWidth(Moments.budgetCaption) + 6,
                     "the longest caption still fits whole, never cut for the title")
        suite.expect(wings(cue, "Claude finished", "").trailing == 36, "a side with nothing to read keeps its least width")
        suite.expect(Moments.agentBadgeWidth <= Moments.miniBoombox.width + 3
                     && Moments.trophySize.height <= Moments.agentRingSide
                     && Moments.agentBadgeWidth - Moments.trophySize.width >= Moments.agentRingSide - 2
                     && Moments.agentBadgeWidth + Moments.agentMarkGap == Moments.levelMarkWidth(Moments.volumeCue(
                        level: 0.5, language: .enUS)) + Moments.levelMarkGap,
                     "the badge is about the boombox's width, its trophy pinned to the ring's edge clear of the "
                        + "mark, and the words start where the volume's reading does")
    }

    private static func capsule(_ suite: TestSuite) {
        func capsule(bar: CGFloat) -> NotchGeometry {
            NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0, cameraWidth: 0,
                          layout: .spacious, menuBarHeight: bar, compactSideRoom: 600, silhouette: .capsule)
        }
        let standard = capsule(bar: 24)
        let cue = Moments.agentCue(for: finished(), language: .enUS)
        let row = Moments.capsuleRow(cue, title: "Claude finished", detail: "1m 34s · $4.12", level: false, geometry: standard)
        suite.expect(row == Moments.capsuleAgentRow(title: "Claude finished", detail: "1m 34s · $4.12", geometry: standard)
                     && row > NotchCapsuleLayout.noticeContent(title: "Claude finished", detail: "1m 34s · $4.12",
                                                               level: false),
                     "the capsule measures the badge in place of the symbol")
        let scale = Moments.capsuleAgentScale(standard)
        suite.expect(scale > 0 && Moments.agentRingSide * scale <= standard.stripBodyHeight
                     && Moments.capsuleAgentBadgeWidth(standard) == (Moments.agentBadgeWidth * scale).rounded(.up),
                     "the badge is scaled to the capsule's ring, inside its body")
        suite.expect(Moments.capsuleAgentScale(capsule(bar: 40)) >= scale, "a taller bar keeps a ring at least as large")
        let content = Moments.capsuleContent(cue, base: row, maximum: NotchCapsuleLayout.Maximum.notice, geometry: standard)
        suite.expect(content == row || content > row + NotchCapsuleLayout.groupSpacing,
                     "the caption follows the row only where the capsule holds it whole")
    }

    private static func celebrations(_ suite: TestSuite) {
        typealias Log = NotchAgentFinishLog
        let now = Date(timeIntervalSince1970: 7_000_000)
        func at(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }
        let claude = AgentLiveSession(id: "claude-a", provider: .claude, started: now, lastActivity: now, model: "",
                                      project: "", tokens: AgentTokens(), cost: 0)
        let codex = AgentLiveSession(id: "codex-a", provider: .codex, started: now, lastActivity: now, model: "",
                                     project: "", tokens: AgentTokens(), cost: 0)
        let end = AgentTurnEnd(provider: .claude, session: claude.id)

        // The finish notice covers the strip and celebrates the turn.
        var log = Log()
        log.update(live: [claude], now: now)
        log.ended(end, at: now)
        log.cover(at: now)
        log.celebrate(.claude)
        suite.expect(log.finished(live: []).isEmpty, "a celebrated finish keeps no wing for a check")
        log.update(live: [], now: at(1))
        suite.expect(log.finished.isEmpty && log.celebrated.isEmpty,
                     "its agent leaving starts no check, and the celebration is spent")
        log.uncover(at: at(5), stripShows: true)
        log.update(live: [], now: at(5))
        suite.expect(log.finished.isEmpty, "the notice going brings back no green check after the gold one")

        // Without the celebration, as with the Office moments off, the check still waits and plays.
        var plain = Log()
        plain.update(live: [claude], now: now)
        plain.ended(end, at: now)
        plain.cover(at: now)
        plain.update(live: [], now: at(1))
        plain.uncover(at: at(5), stripShows: true)
        plain.update(live: [], now: at(5))
        suite.expect(plain.finished == [.claude], "an uncelebrated finish still closes its wing's ring in green")

        // The agent already gone when the notice arrives: its check goes at once.
        var late = Log()
        late.update(live: [claude, codex], now: now)
        late.ended(end, at: now)
        late.update(live: [codex], now: at(0.2))
        suite.expect(late.finished == [.claude], "the check started before the notice")
        late.cover(at: at(0.3))
        late.celebrate(.claude)
        late.update(live: [codex], now: at(0.4))
        suite.expect(late.finished.isEmpty, "the notice takes over the check already showing")

        // A celebration with no end reported changes nothing, and does not
        // swallow the agent's next, uncelebrated finish.
        var unreported = Log()
        unreported.update(live: [claude], now: now)
        unreported.celebrate(.claude)
        suite.expect(unreported.celebrated.isEmpty, "a finish the island never saw at work has nothing to celebrate")
        unreported.ended(end, at: at(1))
        unreported.update(live: [], now: at(2))
        suite.expect(unreported.finished == [.claude], "the next finish still closes its ring")

        // A celebrated agent back at work on another turn: the celebration lapses with its report.
        var again = Log()
        again.update(live: [claude], now: now)
        again.ended(end, at: now)
        again.celebrate(.claude)
        again.update(live: [claude], now: at(Log.wait))
        suite.expect(again.celebrated.isEmpty && again.reported.isEmpty, "a celebration lapses with the end it was for")
        again.ended(end, at: at(Log.wait + 1))
        again.update(live: [], now: at(Log.wait + 2))
        suite.expect(again.finished == [.claude], "so the agent's next finish is its own")

        // A new end reported after a celebration starts afresh.
        var renewed = Log()
        renewed.update(live: [claude], now: now)
        renewed.ended(end, at: now)
        renewed.celebrate(.claude)
        renewed.ended(end, at: at(0.5))
        suite.expect(renewed.celebrated.isEmpty, "a new end reported is not yet celebrated")
    }
}
