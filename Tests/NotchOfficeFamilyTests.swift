// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Every Office moment as one family: one colour rule for props and glow, one
/// title size, one reading, one caption beat, one motion vocabulary, and
/// Low Power Mode calming every move as Reduce Motion does.
enum NotchOfficeFamilyTests {
    static func run(_ suite: TestSuite) {
        colourContracts(suite)
        moodContracts(suite)
        typeContracts(suite)
        timingContracts(suite)
        measureContracts(suite)
        countdownContracts(suite)
        sourceContracts(suite)
        frameRateContracts(suite)
        NotchSongHoldTests.run(suite)
    }

    /// The motion asks Core Animation for the frames it needs, as the comet
    /// rings always did: 30 a second for slow drifts, turns and a beat's
    /// fall, 60 for a beat's hit, never a ProMotion display's 120, each a
    /// frame WindowServer composites.
    private static func frameRateContracts(_ suite: TestSuite) {
        suite.expect(NotchSongMotion.slowFrames.maximum == 30 && NotchSongMotion.slowFrames.preferred == 30
                     && NotchSongMotion.beatFrames.maximum == 60 && NotchSongMotion.beatFrames.preferred == 60,
                     "slow motion asks for 30 frames a second and a beat's hit for 60")
        suite.expect(NotchSongMotion.gentleFrames.maximum == 15 && NotchSongMotion.gentleFrames.preferred == 15,
                     "the softest breaths ask for 15 frames a second, every other one of a slow motion's")
        beatContracts(suite)
        let directory = "Sources/Vorssaint/UI/Notch/"
        for file in ["NotchMusicAurora.swift", "NotchOfficeComponents.swift", "NotchAgentCometView.swift"] {
            guard let source = try? String(contentsOfFile: directory + file, encoding: .utf8) else {
                suite.expect(false, "\(file) is readable from the repository root")
                continue
            }
            let loops = source.components(separatedBy: "repeatCount = .infinity").count - 1
            let rates = source.components(separatedBy: ".preferredFrameRateRange = ").count - 1
            suite.expect(loops > 0 && rates >= loops, "\(file): every endless loop asks for its frame rate")
        }
    }

    /// The beat sets one move going per hit, never one per reading: the hit
    /// and its whole fall, worked out at once as the curve the per-reading
    /// eases drew, its hit at 60 frames a second and its fall at 30.
    private static func beatContracts(_ suite: TestSuite) {
        let pushes = NotchBeatFall.pushes(from: 0.5)
        suite.expect(pushes.first == 0.5 && pushes.last == 0
                        && zip(pushes, pushes.dropFirst().dropLast()).allSatisfy { abs($1 - $0 * 0.72) < 1e-12 }
                        && pushes.dropLast().allSatisfy { $0 >= NotchBeatFall.rest }
                        && pushes.dropLast().last.map { $0 * 0.72 < NotchBeatFall.rest } == true,
                     "a hit's push keeps 0.72 of itself each reading until it rests")
        suite.expect(NotchBeatFall.pushes(from: 0.005) == [0] && NotchBeatFall.pushes(from: .nan) == [0]
                        && NotchBeatFall.pushes(from: 3).first == 1,
                     "a push too faint to see rests at once, and none goes past full")

        let linear = CAMediaTimingFunction(name: .linear)
        let easeOut = CAMediaTimingFunction(name: .easeOut)
        let inOut = CAMediaTimingFunction(name: .easeInEaseOut)
        suite.expectClose(linear.progress(at: 0.3), 0.3, "a linear curve is its own progress", tol: 1e-6)
        suite.expectClose(inOut.progress(at: 0.5), 0.5, "an even ease is half way at half time", tol: 1e-6)
        suite.expect(easeOut.progress(at: 0.2) > 0.2 && easeOut.progress(at: 0) == 0 && easeOut.progress(at: 1) == 1,
                     "an ease out leads its time and ends where it should")
        for share in [0.25, 0.556, 0.625] {
            let cut = easeOut.cut(at: share)
            let whole = easeOut.progress(at: share)
            let agrees = stride(from: 0.05, through: 1, by: 0.05).allSatisfy { x in
                abs(cut.progress(at: x) * whole - easeOut.progress(at: x * share)) < 1e-4
            }
            suite.expect(agrees, "an ease cut short at \(share) of its time draws the first part of the same curve")
        }

        // What twenty eases a second drew: each reading an ease from where
        // the last had the value, cut short by the next.
        let beat = NotchMusicBeat(push: 0.6, previous: 0.1)
        let moves = NotchBeatFall.pushes(from: beat.push).enumerated().map { index, push in
            NotchBeatCurve.Move(target: 0.07 * push, duration: index == 0 ? 0.06 : 0.09, curve: easeOut)
        }
        func chain(_ start: Double, at time: Double) -> Double {
            var value = start
            for (index, move) in moves.enumerated() {
                let begin = Double(index) * 0.05
                if index == moves.count - 1 || time < begin + 0.05 {
                    return value + (move.target - value) * move.curve.progress(at: min(1, max(0, (time - begin) / move.duration)))
                }
                value += (move.target - value) * move.curve.progress(at: 0.05 / move.duration)
            }
            return value
        }
        let curve = NotchBeatCurve(from: 0.01, moves: moves)
        let traced = stride(from: 0.0, through: curve.duration + 0.1, by: 0.004).allSatisfy {
            abs(curve.value(at: $0) - chain(0.01, at: $0)) < 1e-5
        }
        suite.expect(traced && curve.end == 0 && curve.value(at: 0) == 0.01,
                     "one curve per hit traces the per-reading eases exactly, from where the last stood, to rest")
        let settle = NotchMusicBeat.settle(from: 0.4)
        suite.expect(beat.isNewHit && !NotchMusicBeat(push: 0.6, previous: 0.5).isNewHit && settle.settles
                        && !settle.isNewHit && settle.attack == 0 && beat.attack == NotchBeatFall.reading,
                     "a hit well above the fall is new, a settle is none, and only a hit has an attack")
        let listener = beat.moves { $0 }
        suite.expect(listener.first?.duration == 0.08 && listener.last?.duration == NotchSongMotion.beatReturn
                        && listener.last?.target == 0 && beat.moves { $0 }.count == moves.count
                        && settle.moves { $0 }.map(\.target) == [0],
                     "a listener eases quickly with the hit and settles as it comes down")

        // Played as two slices of one animation, inside a transaction as the
        // island plays it: a layer on no screen drops its animations once one commits.
        CATransaction.begin()
        defer { CATransaction.commit() }
        let layer = CALayer()
        let animation = curve.animation("transform.scale", additive: true)
        let values = animation.values as? [Double] ?? []
        NotchSongMotion.play(animation, attack: 0.05, on: layer, key: "beat", at: 100)
        let hit = layer.animation(forKey: "beat") as? CAKeyframeAnimation
        let fall = layer.animation(forKey: "beatFall") as? CAKeyframeAnimation
        func drawn(_ slices: [CAKeyframeAnimation?]) -> [Double] {
            slices.compactMap { $0?.values as? [Double] }.enumerated().flatMap { $0.offset == 0 ? $0.element : Array($0.element.dropFirst()) }
        }
        suite.expect(animation.isAdditive && values.count == curve.values.count
                        && abs((hit?.duration ?? 0) - 0.05) < 1e-9 && hit?.preferredFrameRateRange.preferred == 60
                        && abs((fall?.duration ?? 0) - (animation.duration - 0.05)) < 1e-9
                        && abs((fall?.beginTime ?? 0) - (hit?.beginTime ?? 0) - 0.05) < 1e-9
                        && fall?.preferredFrameRateRange.preferred == 30 && fall?.isAdditive == true
                        && drawn([hit, fall]) == values && hit?.keyTimes?.last == 1 && fall?.keyTimes?.first == 0,
                     "a hit plays its first reading at 60 frames a second and its fall, picked up there, at 30, "
                        + "each with only its own knots")
        let calm = curve.calm(within: 0.07 * 0.1)
        let calmIndex = curve.times.firstIndex(of: calm) ?? 0
        suite.expect(calmIndex > 1 && curve.values[calmIndex...].allSatisfy { abs($0 - curve.end) <= 0.07 * 0.1 }
                        && abs(curve.values[calmIndex - 1] - curve.end) > 0.07 * 0.1
                        && NotchBeatCurve(from: 0.001, moves: Array(moves.suffix(1))).calm(within: 0.01) == 0,
                     "a fall is calm from the first knot after which it keeps within reach of rest")
        NotchSongMotion.play(animation, attack: 0.05, tail: calm, on: layer, key: "beat", at: 100)
        let tail = layer.animation(forKey: "beatTail") as? CAKeyframeAnimation
        let calmFall = layer.animation(forKey: "beatFall") as? CAKeyframeAnimation
        suite.expect(tail?.preferredFrameRateRange.preferred == 15
                        && abs((tail?.beginTime ?? 0) - (layer.animation(forKey: "beat")?.beginTime ?? 0) - calm) < 1e-9
                        && abs((calmFall?.duration ?? 0) - (calm - 0.05)) < 1e-9
                        && drawn([layer.animation(forKey: "beat") as? CAKeyframeAnimation, calmFall, tail]) == values,
                     "once it is calm the rest of a fall plays at 15 frames a second, picked up where the 30 left off")
        let between = CABasicAnimation(keyPath: "opacity")
        between.duration = 0.5
        NotchSongMotion.play(between, attack: 0.07, on: layer, key: "beat", at: 100)
        suite.expect(layer.animation(forKey: "beat")?.repeatDuration == 0.07
                        && layer.animation(forKey: "beatFall")?.timeOffset == 0.07
                        && abs((layer.animation(forKey: "beatFall")?.repeatDuration ?? 0) - 0.43) < 1e-9
                        && layer.animation(forKey: "beatTail") == nil,
                     "a move cut between its knots plays its slices from copies of the whole")
        NotchSongMotion.play(animation, attack: 0, on: layer, key: "beat", at: 100)
        suite.expect(layer.animation(forKey: "beat") == nil && layer.animation(forKey: "beatFall")?.repeatDuration
                        == animation.duration,
                     "a settle plays whole at 30 frames a second")
        NotchSongMotion.play(animation, attack: 0.05, tail: calm, on: layer, key: "beat", at: 100)
        NotchSongMotion.stop("beat", on: layer)
        suite.expect(layer.animationKeys() == nil || layer.animationKeys()?.isEmpty == true, "a move stops whole")
        var track = NotchBeatTrack()
        _ = track.start(moves, at: 10)
        suite.expectClose(track.value(at: 10.2), NotchBeatCurve(from: 0, moves: moves).value(at: 0.2),
                          "a track starts from rest and stands where its curve does", tol: 1e-12)
        let midway = track.value(at: 10.12)
        _ = track.start(moves, at: 10.12)
        suite.expectClose(track.value(at: 10.12), midway, "the next move starts where the last one stands",
                          tol: 1e-12)
        suite.expect(track.moves(at: 10.2) && !track.moves(at: 12) && track.value(at: 12) == 0
                        && NotchBeatTrack().value(at: 1, resting: 0.3) == 0.3,
                     "a track runs its curve's length, then rests")
    }

    /// One resolver: the song while it plays, else the companion while it is
    /// out, else the Office's accents; the glow reads the same answer.
    private static func colourContracts(_ suite: TestSuite) {
        for songWorn in [false, true] {
            for companionOn in [false, true] {
                let colours = NotchMomentColours.of(songWorn: songWorn, companionOn: companionOn)
                let expected: NotchMomentColours = songWorn ? .song : companionOn ? .companion : .office
                suite.expect(colours == expected, "moment colours: song \(songWorn), companion \(companionOn)")
                let glow = NotchIslandGlow.notice(office: true, agent: nil, colours: colours, idleAllowed: true)
                let matches: Bool
                switch (colours, glow) {
                case (.song, .song?), (.companion, .companion?), (.office, .office?): matches = true
                default: matches = false
                }
                suite.expect(matches, "the notice glows in the colours its props wear: \(colours)")
            }
        }
        suite.expect(!NotchMomentColours.songWorn(songMode: true, playing: false)
                     && NotchMomentColours.songWorn(songMode: true, playing: true)
                     && !NotchMomentColours.songWorn(songMode: false, playing: true),
                     "a paused song lends the moment nothing, nor does a song with the song mode off")
        suite.expect(NotchMomentColours.of(songWorn: NotchMomentColours.songWorn(songMode: true, playing: false),
                                           companionOn: true) == .companion,
                     "a paused song: props and glow both wear the companion's colours")
        let seeds = NotchMomentColours.officeSeeds
        suite.expect(seeds.count == 3 && seeds.allSatisfy { NotchIslandGlow.isYellow($0.hsb.hue) }
                     && seeds.contains(NotchRGB(hex: 0xF4D03F)) && seeds.contains(NotchRGB(hex: 0xC9A227)),
                     "with no song and no companion the moment wears the Office's own jelly and mustard")
    }

    /// Danger leans the glow toward beet, success toward gold, and every
    /// colour stays deep enough for the strip's words to keep AA.
    private static func moodContracts(_ suite: TestSuite) {
        suite.expect(NotchMomentMood.of(.battery(.low)) == .danger
                     && NotchMomentMood.of(.agent(.budgetReached)) == .danger
                     && NotchMomentMood.of(.agent(.finished)) == .success
                     && NotchMomentMood.of(.battery(.charging)) == nil && NotchMomentMood.of(.volume) == nil
                     && NotchMomentMood.of(nil) == nil,
                     "a battery running out and a spent budget are danger, a turn done is success, the rest neither")
        suite.expect(NotchMomentMood.beet == NotchRGB(hex: 0xC0392B) && NotchMomentMood.gold == NotchRGB(hex: 0xE3B23C),
                     "the moods lean toward the edition's beet and gold")
        let white = NotchRGB(red: 1, green: 1, blue: 1)
        let glows: [[NotchRGB]] = [AgentProvider.claude.wingGlow, AgentProvider.codex.wingGlow,
                                   NotchMomentColours.officeSeeds.map { $0.toned(maxLuminance: 0.18, minLuminance: 0.07) },
                                   [NotchRGB(hex: 0x2B2F8F), NotchRGB(hex: 0x1C6E8C), NotchRGB(hex: 0x5B2A86)]]
        for mood in [NotchMomentMood.danger, .success] {
            for glow in glows {
                let leaned = mood.leaned(glow)
                suite.expect(leaned.count == glow.count
                             && leaned.allSatisfy { NotchMomentMood.glowLuminance.contains($0.luminance - 0.0005)
                                 || NotchMomentMood.glowLuminance.contains($0.luminance + 0.0005) },
                             "a leaned glow stays inside the song's glow band: \(mood)")
                suite.expect(leaned.allSatisfy { NotchRGB.contrast(white, $0) >= 4.5 },
                             "white words keep AA over a leaned glow, before any veil: \(mood)")
                let toward = zip(glow, leaned).allSatisfy { original, lean in
                    let accent = mood.accent.hsb.hue
                    func distance(_ a: Double, _ b: Double) -> Double { let d = abs(a - b); return min(d, 1 - d) }
                    return distance(lean.hsb.hue, accent) <= distance(original.hsb.hue, accent) + 0.001
                }
                suite.expect(toward, "the glow's hues move toward the mood's accent, never away: \(mood)")
            }
        }
    }

    /// One title, one reading: every Office title and reading font is the family's.
    private static func typeContracts(_ suite: TestSuite) {
        let title = NotchOfficeMoments.titleFont, detail = NotchOfficeMoments.detailFont
        suite.expect(title.pointSize == 13
                     && (title.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])
                        .flatMap { $0[.weight] as? CGFloat }.map { abs($0 - NSFont.Weight.semibold.rawValue) < 0.01 } == true,
                     "the family's title is 13 pt semibold")
        suite.expect(NotchOfficeMoments.editionTitleFont === title && NotchOfficeMoments.copyTitleFont === title
                     && NotchOfficeMoments.agentTitleFont === title,
                     "the edition's, the copy's and an agent's titles are the family's title")
        suite.expect(NotchOfficeMoments.levelReadingFont.pointSize == title.pointSize,
                     "a level's reading, its title, is the title's size")
        suite.expect(NotchOfficeMoments.editionStateFont === detail && NotchOfficeMoments.copySummaryFont === detail
                     && NotchOfficeMoments.agentDetailFont === detail && detail.pointSize < title.pointSize,
                     "every far-side reading is the one reading font, a step below the title")
        let office = NotchOfficeMoments.bannerFonts(NotchOfficeCue(kind: .message, caption: "Head of Sending"))
        let plain = NotchOfficeMoments.bannerFonts(nil)
        suite.expect(office.title === title && office.message === detail
                     && plain.title === NotchNotificationBannerLayout.titleFont
                     && plain.message === NotchNotificationBannerLayout.messageFont,
                     "an Office banner draws and measures in the family's fonts; a plain one keeps its own")
        suite.expect(NotchOfficeMoments.cardTitleFont.pointSize > title.pointSize,
                     "the cards share one title size, larger than the strip's")
    }

    /// One beat for each part of every moment.
    private static func timingContracts(_ suite: TestSuite) {
        suite.expect(NotchOfficeMoments.captionBeat == 0.32, "the lower third arrives 0.32 s after the moment lands")
        suite.expect(NotchOfficeMoments.titleBeat < NotchOfficeMoments.readingBeat
                     && NotchOfficeMoments.readingBeat < NotchOfficeMoments.captionBeat
                     && NotchOfficeMoments.readingBeat == 0.2,
                     "the title, then the far side's reading, then the caption")
        suite.expect(NotchSongMotion.punch == 0.16 && NotchSongMotion.step == 0.14 && NotchSongMotion.swap == 0.2
                     && NotchSongMotion.blink < NotchSongMotion.step,
                     "the vocabulary's short durations by role")
        suite.expect(NotchOfficeMoments.coneKickDuration == NotchSongMotion.push.out + NotchSongMotion.push.back,
                     "a volume kick is the connect card's cone push")
        suite.expect(NotchGlowPresence.fade == NotchSongMotion.fadeDuration,
                     "the glow fades on the vocabulary's fade")
    }

    /// The strip is measured in the fonts it draws with.
    private static func measureContracts(_ suite: TestSuite) {
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, cameraWidth: 185)
        let connect = NotchNotice(event: .accessory, title: "Connected", detail: "AirPods Pro", symbol: "airpodspro",
                                  office: NotchOfficeMoments.connectCue(symbol: "airpodspro", language: .de))
        suite.expect(connect.preferredWings.leading >= NotchOfficeMoments.titleWidth("Connected") + 18 + 8 + 16
                     && connect.preferredWings.trailing >= NotchOfficeMoments.detailWidth("AirPods Pro") + 16,
                     "an Office title and its reading are measured in the family's fonts")
        let content = NotchNotificationContent(app: "Messages", title: "Pam Beesly", subtitle: "", body: "Did you take my yogurt?")
        let banner = NotchNotice(event: .systemNotification, title: "Pam Beesly", detail: content.body, symbol: "bell.fill",
                                 notification: content, notificationID: UUID(),
                                 office: NotchOfficeMoments.communicationCue(for: content, language: .enUS))
        let layout = NotchNotificationBannerLayout.self
        let wings = banner.wings(in: geometry)
        suite.expect(wings.leading >= layout.iconSize + layout.spacing + NotchOfficeMoments.titleWidth("Pam Beesly") + layout.inset
                     && wings.trailing >= NotchOfficeMoments.detailWidth(content.body) + layout.inset,
                     "an Office banner's sender and message keep their sides whole in the family's fonts")
        let edition = NotchNotice(event: .officeEdition, title: "Office edition", detail: "On", symbol: "mug.fill",
                                  office: NotchOfficeMoments.editionCue(on: true, states: ("On", "Off"), language: .enUS))
        suite.expect(edition.inset(wing: edition.preferredWings.leading) == NotchNotice.levelInset,
                     "the edition's mug stands where the boombox does, as the battery's does")
    }

    /// "Conference room, five minutes." is said whole, by a notice: the
    /// countdown strip, Vorssaint's own, never splits it across the camera.
    private static func countdownContracts(_ suite: TestSuite) {
        let strip = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Notch/NotchCalendarStrip.swift", encoding: .utf8)) ?? ""
        suite.expect(!strip.isEmpty && !strip.contains("NotchLowerThird") && !strip.contains("Office"),
                     "the countdown strip carries no Office caption")
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = NotchCalendarEvent(id: "q", title: "Quarterly", calendar: "Work", start: now.addingTimeInterval(300),
                                       end: now.addingTimeInterval(3900), allDay: false, location: "")
        let soon = NotchCalendarCountdown(event: event, ongoing: false)
        suite.expect(NotchOfficeMoments.meetingSoonArrived(from: nil, to: soon, at: now.addingTimeInterval(1)) == event,
                     "as the five minutes open, the notice says so, countdown strip or not")
    }

    /// The views follow the family's rules: Low Power Mode wherever Reduce
    /// Motion is read, one caption beat, and no motion literals.
    private static func sourceContracts(_ suite: TestSuite) {
        let directory = "Sources/Vorssaint/UI/Notch/"
        let files = ["NotchOfficeMug.swift", "NotchOfficeCards.swift", "NotchConnectFlourish.swift",
                     "NotchOfficeLevels.swift", "NotchOfficeCopier.swift", "NotchOfficeComponents.swift",
                     "NotchOfficeAgentViews.swift", "NotchOfficeEditionViews.swift"]
        var sources: [String: String] = [:]
        for file in files {
            guard let source = try? String(contentsOfFile: directory + file, encoding: .utf8) else {
                suite.expect(false, "\(file) is readable from the repository root")
                continue
            }
            sources[file] = source
        }
        for (file, source) in sources {
            let lines = source.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            let gates = lines.filter { $0.contains("reduceMotion") && !$0.contains("@Environment") }
            suite.expect(gates.allSatisfy { $0.contains("lowPower") || $0.contains("calm") },
                         "\(file): every Reduce Motion gate calms in Low Power Mode too")
            let literals = lines.filter {
                $0.contains("duration: 0.") || $0.contains("timingCurve(0") || $0.contains("CAMediaTimingFunction(name")
                    || $0.range(of: "nanoseconds: [0-9]", options: .regularExpression) != nil
                    || $0.range(of: "delay: 0\\.[0-9]", options: .regularExpression) != nil
            }
            suite.expect(literals.isEmpty, "\(file): moves come from the vocabulary, not literals: \(literals)")
        }
        if let mug = sources["NotchOfficeMug.swift"] {
            suite.expect(mug.contains("let calm = reduceMotion || lowPower.isOn")
                         && !mug.contains("guard !reduceMotion else"),
                         "the battery mug settles in Low Power Mode as in Reduce Motion")
        }
        let notice = (try? String(contentsOfFile: directory + "NotchNoticeView.swift", encoding: .utf8)) ?? ""
        let allViews = files.compactMap { sources[$0] } + [notice,
            (try? String(contentsOfFile: directory + "NotchCapsuleViews.swift", encoding: .utf8)) ?? "",
            (try? String(contentsOfFile: directory + "NotchCalendarStrip.swift", encoding: .utf8)) ?? ""]
        let thirds = allViews.flatMap { $0.components(separatedBy: "NotchLowerThird(caption:").dropFirst() }
        suite.expect(!thirds.isEmpty && thirds.allSatisfy { call in
            let line = call.prefix { $0 != ")" }
            return !line.contains("delay:")
        }, "every lower third arrives on the one caption beat")
        suite.expect(notice.components(separatedBy: "NotchOfficeMoments.titleFont").count - 1 >= 2
                     && notice.contains(".transition(notice.office != nil ? .opacity.animation(NotchSongMotion.reduced)"),
                     "the strip's Office titles are the family's title, and one notice fades out under the next")
    }
}

/// The song's slow motion runs only while it is seen moving: a paused song,
/// a covered island and Low Power Mode or Reduce Motion take the aurora's
/// drift and the bubble's turn off their layers altogether, rather than
/// holding them at speed zero, so a still island asks the compositor for
/// nothing; playing and in sight again, they go back on from where they
/// stood. The wings' glow, which never moves, is one bitmap under whatever
/// moves over it.
enum NotchSongHoldTests {
    private final class Window: NSWindow {
        override var isVisible: Bool { true }
        override var occlusionState: NSWindow.OcclusionState { [.visible] }
    }

    static func run(_ suite: TestSuite) {
        holdContracts(suite)
        wingContracts(suite)
    }

    /// The aurora's view reaches the whole island, so it is read rather than run.
    private static func holdContracts(_ suite: TestSuite) {
        guard let source = try? String(contentsOfFile: "Sources/Vorssaint/UI/Notch/NotchMusicAurora.swift",
                                       encoding: .utf8) else {
            suite.expect(false, "NotchMusicAurora.swift is readable from the repository root")
            return
        }
        func body(of function: String) -> String {
            guard let start = source.range(of: function) else { return "" }
            let rest = source[start.upperBound...]
            let end = rest.range(of: "\n    }\n")?.lowerBound ?? rest.endIndex
            return String(rest[..<end])
        }
        let syncClock = body(of: "private func syncClock()")
        suite.expect(syncClock.contains("detachDrift()") && syncClock.contains("attachDrift()"),
                     "the aurora's drift comes off its pools whenever it holds, and goes back on as it runs")
        let detach = body(of: "private func detachDrift()")
        suite.expect(detach.contains("presentation()?.transform") && detach.contains("removeAnimation(forKey: \"drift\")")
                        && detach.contains("removeAnimation(forKey: \"breath\")"),
                     "held, each pool keeps the pose it stood in with nothing left running")
        let attach = body(of: "private func attachDrift()")
        suite.expect(attach.contains("beginTime = begin") && attach.contains("guard let begin = motionBegin"),
                     "the drift goes back on from the start it was made at, so the held clock picks it up")
        let install = body(of: "private func installMotion()")
        suite.expect(!install.contains("blob.add("), "making the drift attaches nothing until it runs")
        let bubble = body(of: "    private func sync() {\n        // A withdrawn bubble")
        suite.expect(!bubble.isEmpty && !bubble.contains("speed") && bubble.contains("removeAnimation(forKey: \"turn\")")
                        && bubble.contains("spin.fromValue = angle"),
                     "the bubble's turn comes off when held, never at speed zero, and goes on from its angle")
        suite.expect(source.contains("moves: !reduceMotion && !still && !lowPower.isOn")
                        && source.contains("moves: !reduceMotion && !lowPower.isOn"),
                     "Low Power Mode stills the aurora and the bubbles as Reduce Motion does")
        // Twenty readings a second come in; only a hit sets anything going.
        let hear = body(of: "private func hear(_ levels: [Double]?)")
        let strike = body(of: "private func strike(previous: Double, at now: CFTimeInterval)")
        suite.expect(!hear.isEmpty && !hear.contains("presentation()") && !hear.contains(".add(")
                        && !hear.contains("NotchSongMotion.play") && !hear.contains("beat.send")
                        && hear.contains("strike(previous:") && !strike.isEmpty && !strike.contains("presentation()"),
                     "a reading without a hit adds no animation and sends no beat; a hit reads nothing off the screen")
    }

    private static func wingContracts(_ suite: TestSuite) {
        let window = Window(contentRect: CGRect(x: 0, y: 0, width: 240, height: 80),
                            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        window.contentView = container
        let wings = NotchWingGlowView(frame: CGRect(x: 0, y: 0, width: 200, height: 32))
        container.addSubview(wings)
        let glow = [NotchRGB(hex: 0xD97757), NotchRGB(hex: 0xEB9F7F), NotchRGB(hex: 0xFFD0B5)]
        let colours = NotchWingGlowColors(left: glow, right: glow, fadesEdges: false)
        wings.apply(colors: colours, camera: CGSize(width: 60, height: 32), veil: .strip, presence: 1, fades: false)
        suite.expect(wings.drawsOnce, "the wings' glow, shown in full, is drawn once")
        wings.apply(colors: colours, camera: CGSize(width: 60, height: 32), veil: .strip, presence: 0.4, fades: false)
        suite.expect(!wings.drawsOnce, "fading with the island's resize, the wings' glow is drawn live")
        wings.removeFromSuperview()
        window.close()
    }
}
