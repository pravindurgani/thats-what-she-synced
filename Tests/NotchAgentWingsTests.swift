// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// The closed island's agent wings: which agent takes which side, how wide
/// the wings are, how their colours keep the readings legible, and how a
/// finished turn holds its wing for its check.
enum NotchAgentWingsTests {
    static func run(_ suite: TestSuite) {
        wings(suite)
        colours(suite)
        sizes(suite)
        readings(suite)
        finishes(suite)
        NotchAgentCometViewTests.run(suite)
    }

    private static func wings(_ suite: TestSuite) {
        typealias Wings = NotchAgentWings
        suite.expect(Wings.assign(working: [.codex, .claude], finished: [])
                        == [NotchAgentWing(provider: .claude, finished: false), NotchAgentWing(provider: .codex, finished: false)],
                     "Claude takes the left wing and Codex the right, whatever order they started in")
        suite.expect(Wings.assign(working: [.copilot, .opencode, .codex], finished: []).map(\.provider) == [.codex, .opencode],
                     "the first two working agents in the agents' own order take the wings")
        suite.expect(Wings.assign(working: [.codex], finished: [.claude])
                        == [NotchAgentWing(provider: .claude, finished: true), NotchAgentWing(provider: .codex, finished: false)],
                     "an agent whose turn just ended keeps its side for its check")
        suite.expect(Wings.assign(working: [.claude], finished: [.claude]) == [NotchAgentWing(provider: .claude, finished: false)],
                     "an agent at work again is working, not finished")
        suite.expect(Wings.assign(working: [], finished: []).isEmpty, "no agent, no wings")

        let one = Wings.assign(working: [.codex], finished: [])
        let two = Wings.assign(working: [.claude, .codex], finished: [])
        suite.expect(Wings.glowSides(one).map { [$0.left, $0.right] } == [.codex, .codex]
                        && Wings.glowSides(two).map { [$0.left, $0.right] } == [.claude, .codex]
                        && Wings.glowSides([]) == nil,
                     "one agent glows on both sides; two split the glow, warm left and indigo right")

        let now = Date(timeIntervalSince1970: 3_000_000)
        func session(_ provider: AgentProvider) -> AgentLiveSession {
            AgentLiveSession(id: provider.rawValue, provider: provider, started: now, lastActivity: now, model: "",
                             project: "", tokens: AgentTokens(), cost: 0)
        }
        suite.expect(!NotchAgentStripModel(live: [session(.claude)], finished: []).twoSided
                        && NotchAgentStripModel(live: [session(.claude), session(.codex)], finished: []).twoSided
                        && NotchAgentStripModel(live: [session(.codex)], finished: [.claude]).twoSided,
                     "two wings only while two agents work or one has just finished beside another")
    }

    private static func colours(_ suite: TestSuite) {
        suite.expect(AgentProvider.claude.glowStops == [NotchRGB(hex: 0xD97757), NotchRGB(hex: 0xEB9F7F), NotchRGB(hex: 0xFFD0B5)]
                        && AgentProvider.codex.glowStops == [NotchRGB(hex: 0x3941FF), NotchRGB(hex: 0x7A9DFF), NotchRGB(hex: 0xB1A7FF)],
                     "Claude and Codex wear their makers' own gradients")
        for provider in [AgentProvider.opencode, .copilot] {
            let stops = provider.glowStops
            suite.expect(stops.first == provider.rgb && stops[0].luminance < stops[1].luminance
                            && stops[1].luminance < stops[2].luminance,
                         "\(provider.rawValue)'s gradient grows from its own colour toward a highlight")
        }
        // The closed strip's veil is lightest, 0.12, in its middle, where the readings sit.
        let lightestVeil = 0.12
        let worstGlow = NotchRGB(red: 0.18, green: 0.18, blue: 0.18).toned(maxLuminance: 0.18, minLuminance: 0.18)
        for provider in AgentProvider.allCases {
            let reading = provider.readingColor
            suite.expect(provider.wingGlow.allSatisfy { $0.luminance <= 0.1801 },
                         "\(provider.rawValue)'s glow is toned as deep as a song's glow")
            suite.expect(provider.wingGlow.allSatisfy { NotchRGB.contrast(reading, $0.veiled(by: lightestVeil)) >= 4.5 }
                            && NotchRGB.contrast(reading, worstGlow.veiled(by: lightestVeil)) >= 4.5,
                         "\(provider.rawValue)'s reading keeps WCAG AA over the brightest glow")
            suite.expect(reading.hsb.saturation > 0.05 || provider.glowStops[2].hsb.saturation < 0.05,
                         "\(provider.rawValue)'s reading keeps a tint of its colour")
            suite.expect(NotchRGB.contrast(NotchAgentWings.done, NotchRGB(red: 0, green: 0, blue: 0).mixed(
                            with: provider.wingGlow[0], by: 0.45)) >= 3,
                         "the finished check stands at 3:1 on the dark lens inside \(provider.rawValue)'s ring")
        }
        suite.expect(abs(NotchRGB(red: 1, green: 1, blue: 1).luminance - 1) < 0.0001
                        && NotchRGB(red: 0, green: 0, blue: 0).luminance == 0
                        && abs(NotchRGB.contrast(NotchRGB(red: 1, green: 1, blue: 1), NotchRGB(red: 0, green: 0, blue: 0)) - 21) < 0.001,
                     "luminance and contrast follow WCAG")
        let lifted = NotchRGB(hex: 0x3941FF).lifted(toLuminance: 0.8)
        suite.expect(lifted.luminance >= 0.8 && lifted.luminance < 0.81, "a tint lightens only as far as it must")
        let toned = NotchRGB(hex: 0xFFD0B5).toned(maxLuminance: 0.18, minLuminance: 0.07)
        suite.expect(toned.luminance <= 0.1801 && toned.luminance >= 0.069
                        && abs(toned.hsb.hue - NotchRGB(hex: 0xFFD0B5).hsb.hue) < 0.01,
                     "toning keeps the hue and lands in the luminance asked for")
        let wheel = NotchRGB(hue: 0.6, saturation: 0.7, brightness: 0.95).hsb
        suite.expect(abs(wheel.hue - 0.6) < 0.001 && abs(wheel.saturation - 0.7) < 0.001 && abs(wheel.brightness - 0.95) < 0.001,
                     "colours round-trip through hue, saturation and brightness")
    }

    private static func sizes(_ suite: TestSuite) {
        typealias Wings = NotchAgentWings
        for height in stride(from: CGFloat(22), through: 44, by: 1) {
            let ring = Wings.ringDiameter(contentHeight: height)
            suite.expect(ring >= 12 && ring <= 22 && (height < 24 || ring + NotchLayout.compactEdgeGap * 2 <= height),
                         "the ring stays clear of a \(height)-point strip's top and bottom")
            // The widest mark, Claude's, is drawn 1.45 times its size.
            suite.expect(Wings.markSize(ring: ring) * 1.45 <= ring - Wings.ringLine * 2 + 0.5,
                         "the mark fits inside its ring in a \(height)-point strip")
        }
        let one = Wings.wingWidth(ring: 20, ringInset: 8, readings: [40], readingInset: 7, twoSided: false, cameraGap: 6)
        suite.expect(one == max(28, 47) + 6, "one agent's wings take the wider of the ring and the reading")
        suite.expect(Wings.wingWidth(ring: 20, ringInset: 8, readings: [], readingInset: 7, twoSided: false, cameraGap: 6) == 34,
                     "with no reading, the ring alone sets the wing")
        let two = Wings.wingWidth(ring: 20, ringInset: 8, readings: [30, 42], readingInset: 0, twoSided: true, cameraGap: 6)
        suite.expect(two == 8 + 20 + Wings.markGap + 42 + 6
                        && two == Wings.wingWidth(ring: 20, ringInset: 8, readings: [42, 30], readingInset: 0,
                                                  twoSided: true, cameraGap: 6),
                     "two agents' wings both take the wider side, so the island stays balanced")
        suite.expect(Wings.readingFits(wing: two, ring: 20, ringInset: 8, reading: 42, cameraGap: 6)
                        && !Wings.readingFits(wing: two - 1, ring: 20, ringInset: 8, reading: 42, cameraGap: 6)
                        && !Wings.readingFits(wing: 200, ring: 20, ringInset: 8, reading: 0, cameraGap: 6),
                     "a wing shows its reading only when the menus leave room for it")

        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                                     cameraWidth: 185, layout: .spacious, compactSideRoom: 300)
        suite.expect(geometry.compactAgentGeometry(wing: 300, twoSided: true).compactActivityWingWidth
                        == Wings.twoSidedRange.upperBound
                        && geometry.compactAgentGeometry(wing: 300).compactActivityWingWidth
                        == NotchAgentSupport.stripWingRange.upperBound,
                     "two agents may take wider wings than one")
        suite.expect(geometry.compactAgentGeometry(wing: 87.3, twoSided: true).compactActivitySize.width == 185 + 88 * 2,
                     "two wings, each as wide as the wider side needs, with the camera between them")
        var crowded = geometry
        crowded.compactSideRoom = 60
        suite.expect(crowded.compactAgentGeometry(wing: 90, twoSided: true).compactActivityWingWidth == 60,
                     "the menus' room still caps two agents' wings")
        let readingWidth = Wings.readingWidth("12:34", size: 12)
        suite.expect(readingWidth == Wings.readingWidth("59:59", size: 12) && readingWidth < Wings.readingWidth("1:00:00", size: 12),
                     "a wing's reading is measured by its shape")

        let capsule = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 24,
                                    cameraWidth: 0, layout: .spacious, compactSideRoom: 400)
        let single = NotchCapsuleLayout.agentSurface(readings: ["12:34"], geometry: capsule)
        let pair = NotchCapsuleLayout.agentSurface(readings: ["12:34", "4:05"], geometry: capsule)
        suite.expect(pair.width > single.width && pair.height == single.height,
                     "a capsule with two agents makes room for both rings and both readings")
    }

    private static func readings(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 4_000_000)
        let ended = start.addingTimeInterval(100)
        let session = AgentLiveSession(id: "s", provider: .claude, started: start, lastActivity: ended, model: "",
                                       project: "", tokens: AgentTokens(output: 2000), cost: 1.25)
        var snapshot = AgentUsageSnapshot()
        snapshot.live = [session]
        let later = ended.addingTimeInterval(50)
        suite.expect(NotchAgentWings.reading(snapshot, sessions: [session], finished: false, readout: .elapsed,
                                             display: .remaining, focus: .mostUsed, now: later) == "2:30"
                        && NotchAgentWings.reading(snapshot, sessions: [session], finished: true, readout: .elapsed,
                                                   display: .remaining, focus: .mostUsed, now: later) == "1:40",
                     "a working wing counts on; a finished one holds the time its turn took")
        let codex = AgentLiveSession(id: "c", provider: .codex, started: start, lastActivity: ended, model: "",
                                     project: "", tokens: AgentTokens(output: 500), cost: 0.5)
        snapshot.live = [session, codex]
        suite.expect(NotchAgentWings.reading(snapshot, sessions: [codex], finished: false, readout: .cost,
                                             display: .remaining, focus: .mostUsed, now: later) == AgentFormat.cost(0.5),
                     "each wing reads its own agent's turns in the chosen reading")
    }

    private static func finishes(_ suite: TestSuite) {
        typealias Log = NotchAgentFinishLog
        let now = Date(timeIntervalSince1970: 5_000_000)
        func at(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }
        func turn(_ provider: AgentProvider, _ id: String) -> AgentLiveSession {
            AgentLiveSession(id: id, provider: provider, started: now, lastActivity: now, model: "", project: "",
                             tokens: AgentTokens(), cost: 0)
        }
        func end(_ session: AgentLiveSession) -> AgentTurnEnd {
            AgentTurnEnd(provider: session.provider, session: session.id)
        }
        let claude = turn(.claude, "claude-a"), codex = turn(.codex, "codex-a")
        var log = Log()
        log.update(live: [claude, codex], now: now)
        log.ended(end(claude), at: now)
        var next = log.update(live: [claude, codex], now: now)
        suite.expect(log.finished.isEmpty && next == at(Log.wait), "a reported end waits for its agent to stop working")
        suite.expect(log.finished(live: [codex]) == [.claude],
                     "a reported end counts as soon as its agent leaves the list, before the log moves on")
        next = log.update(live: [codex], now: at(1))
        suite.expect(log.finished == [.claude] && next == at(1 + Log.check),
                     "the check starts when the agent leaves the working list")
        log.update(live: [codex], now: at(1 + Log.check - 0.1))
        suite.expect(log.finished == [.claude], "the check holds for its moment")
        next = log.update(live: [codex], now: at(1 + Log.check))
        suite.expect(log.finished.isEmpty && next == nil, "then the wing goes")

        log.ended(end(codex), at: now)
        log.update(live: [codex], now: at(Log.wait))
        suite.expect(log.finished.isEmpty && log.reported.isEmpty,
                     "an agent still at work after its turn's end, on another turn, shows no check")

        log.ended(end(claude), at: now)
        log.update(live: [], now: now)
        log.update(live: [claude], now: at(0.5))
        suite.expect(log.finished.isEmpty, "an agent back at work loses its check at once")

        // Two turns of one agent: only the turn that was its last at work closes its ring.
        let first = turn(.claude, "claude-1"), second = turn(.claude, "claude-2")
        var interrupted = Log()
        interrupted.update(live: [first, second], now: now)
        interrupted.ended(end(first), at: now)
        interrupted.update(live: [second], now: at(1))
        suite.expect(interrupted.finished(live: []).isEmpty, "a stale end never counts once its agent's other turn goes")
        interrupted.update(live: [], now: at(3))
        suite.expect(interrupted.finished.isEmpty,
                     "a turn interrupted moments after another of its agent's finished closes no ring green")
        var together = Log()
        together.update(live: [first, second], now: now)
        together.ended(end(first), at: now)
        together.update(live: [], now: at(1))
        suite.expect(together.finished.isEmpty, "two turns gone at once, one without a report, close no ring green")
        var both = together
        both.update(live: [first, second], now: at(2))
        both.ended(end(first), at: at(2))
        both.ended(end(second), at: at(2))
        both.update(live: [], now: at(3))
        suite.expect(both.finished == [.claude], "two turns both finished close the ring")
        var lastFinished = Log()
        lastFinished.update(live: [first, second], now: now)
        lastFinished.update(live: [first], now: at(1))
        lastFinished.ended(end(first), at: at(2))
        lastFinished.update(live: [], now: at(3))
        suite.expect(lastFinished.finished == [.claude], "the last turn at work finishing closes the ring")

        // The finish notice covers the strip: the check waits, and starts as the strip comes back.
        var covered = Log()
        covered.update(live: [claude], now: now)
        covered.ended(end(claude), at: now)
        covered.cover(at: now)
        covered.update(live: [], now: at(1))
        next = covered.update(live: [], now: at(1 + Log.check + 2))
        suite.expect(covered.finished == [.claude] && next == at(Log.coverLimit),
                     "a check waits under the notice that covers it")
        covered.uncover(at: at(5), stripShows: true)
        next = covered.update(live: [], now: at(5))
        suite.expect(covered.finished == [.claude] && next == at(5 + Log.check),
                     "the check starts again as the strip comes back")
        covered.update(live: [], now: at(5 + Log.check))
        suite.expect(covered.finished.isEmpty, "and holds only its moment")
        var elsewhere = Log()
        elsewhere.update(live: [claude], now: now)
        elsewhere.ended(end(claude), at: now)
        elsewhere.cover(at: now)
        elsewhere.update(live: [], now: at(1))
        elsewhere.uncover(at: at(5), stripShows: false)
        suite.expect(elsewhere.finished.isEmpty, "a check goes with the notice when the strip does not come back")
        var unheard = Log()
        unheard.update(live: [claude], now: now)
        unheard.ended(end(claude), at: now)
        unheard.cover(at: now)
        unheard.update(live: [], now: at(1))
        unheard.update(live: [], now: at(Log.coverLimit))
        suite.expect(unheard.finished.isEmpty && unheard.covered == nil, "a notice never heard leaving holds a check no longer than its limit")
    }
}

/// The comet ring's motion: on the render server, at its specified timing,
/// and removed whenever it is not seen or its agent is done.
enum NotchAgentCometViewTests {
    private final class Window: NSWindow {
        var shown = true
        var exposed = true
        override var isVisible: Bool { shown }
        override var occlusionState: NSWindow.OcclusionState { exposed ? [.visible] : [] }
        func notifyVisibility() {
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: self)
        }
    }

    static func run(_ suite: TestSuite) {
        let window = Window(contentRect: CGRect(x: 0, y: 0, width: 60, height: 60),
                            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: window.frame)
        window.contentView = container
        let view = NotchAgentCometView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        let stops = AgentProvider.claude.glowStops
        view.configure(stops: stops, diameter: 20, finished: false, moves: true)
        suite.expect(!view.isMoving, "an unattached ring does not turn")
        container.addSubview(view)
        suite.expect(view.isMoving, "a working agent's ring turns once it shows")
        let orbit = view.orbitAnimation
        suite.expect(orbit?.duration == NotchAgentWings.orbit && orbit?.repeatCount == .infinity
                        && orbit?.timingFunction == CAMediaTimingFunction(name: .linear)
                        && (orbit?.toValue as? Double).map { abs(abs($0) - 2 * .pi) < 0.0001 } == true,
                     "the comet turns once every 1.4 seconds, linearly, without end")
        suite.expect((orbit?.preferredFrameRateRange.maximum ?? 0) <= 60,
                     "the comet never asks a ProMotion display for 120 frames a second")
        let breath = view.breathAnimation
        suite.expect(breath?.duration == NotchAgentWings.breath && breath?.autoreverses == true
                        && breath?.timingFunction == CAMediaTimingFunction(name: .easeInEaseOut)
                        && (breath?.fromValue as? Float) == 0.25 && (breath?.toValue as? Float) == 0.6,
                     "the halo breathes over 1.6 seconds, eased, between 0.25 and 0.6")
        view.configure(stops: stops, diameter: 20, finished: false, moves: true)
        suite.expect(view.orbitAnimation === orbit, "an update keeps the orbit's phase")

        window.exposed = false
        window.notifyVisibility()
        suite.expect(!view.isMoving && view.breathAnimation == nil, "a covered island removes the ring's motion")
        window.exposed = true
        window.notifyVisibility()
        suite.expect(view.isMoving, "uncovered, the ring turns again")
        container.isHidden = true
        suite.expect(!view.isMoving, "a hidden island removes the ring's motion")
        container.isHidden = false
        suite.expect(view.isMoving, "shown again, the ring turns again")

        view.configure(stops: stops, diameter: 20, finished: false, moves: false)
        suite.expect(!view.isMoving && view.breathAnimation == nil, "under Reduce Motion the ring rests")
        view.configure(stops: stops, diameter: 20, finished: false, moves: true)
        view.configure(stops: stops, diameter: 20, finished: true, moves: true)
        suite.expect(!view.isMoving && view.breathAnimation == nil && view.sealShows,
                     "a finished turn stops the comet and closes the ring")
        view.configure(stops: stops, diameter: 20, finished: false, moves: true)
        suite.expect(view.isMoving && !view.sealShows, "a new turn brings the comet back")
        suite.expect(view.hitTest(.zero) == nil && !view.isAccessibilityElement(),
                     "the ring never takes clicks or VoiceOver's focus")
        view.stop()
        window.notifyVisibility()
        view.removeFromSuperview()
        suite.expect(!view.isMoving, "a dismantled ring stays still")

        weak var released: NotchAgentCometView?
        autoreleasepool {
            let discarded = NotchAgentCometView(frame: .zero)
            released = discarded
            discarded.configure(stops: stops, diameter: 20, finished: false, moves: true)
            container.addSubview(discarded)
            discarded.removeFromSuperview()
        }
        suite.expect(released == nil, "watching the window never keeps a discarded ring alive")
    }
}
