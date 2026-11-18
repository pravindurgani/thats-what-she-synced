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
    }

    /// The motion asks Core Animation for the frames it needs, as the comet
    /// rings always did: 30 a second for slow drifts and turns, 60 for a
    /// beat's moves, never a ProMotion display's 120, each a frame
    /// WindowServer composites. A beat's ease moves from where the layer
    /// shows to where it is headed, at the beat's rate.
    private static func frameRateContracts(_ suite: TestSuite) {
        suite.expect(NotchSongMotion.slowFrames.maximum == 30 && NotchSongMotion.slowFrames.preferred == 30
                     && NotchSongMotion.beatFrames.maximum == 60 && NotchSongMotion.beatFrames.preferred == 60,
                     "slow motion asks for 30 frames a second and a beat's moves for 60")
        // Inside a transaction, as the island eases within a turn of the main
        // queue: a layer on no screen drops its animations once one commits.
        CATransaction.begin()
        defer { CATransaction.commit() }
        let layer = CALayer()
        layer.opacity = 1
        NotchSongMotion.ease(layer, "opacity", to: Float(0.4), duration: 0.08,
                             curve: CAMediaTimingFunction(name: .easeOut))
        let move = layer.animation(forKey: "opacity") as? CABasicAnimation
        suite.expect(layer.opacity == 0.4 && move?.duration == 0.08 && (move?.fromValue as? Float) == 1
                     && (move?.toValue as? Float) == 0.4 && move?.preferredFrameRateRange.maximum == 60,
                     "a beat's ease lands on its value, from where the layer was, at 60 frames a second")
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

    /// The countdown strip carries the caption, and glows, on one answer.
    private static func countdownContracts(_ suite: TestSuite) {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = NotchCalendarEvent(id: "q", title: "Quarterly", calendar: "Work", start: now.addingTimeInterval(120),
                                       end: now.addingTimeInterval(3720), allDay: false, location: "")
        let soon = NotchCalendarCountdown(event: event, ongoing: false)
        func caption(enabled: Bool = true, meeting: NotchCalendarCountdown? = soon, language: AppLanguage = .enUS,
                     height: CGFloat = 26, room: CGFloat = 200) -> Bool {
            NotchOfficeMoments.countdownCaption(enabled: enabled, meeting: meeting, now: now, language: language,
                                                contentHeight: height, room: room) != nil
        }
        suite.expect(caption(), "five minutes out, a tall enough strip with room carries the caption")
        suite.expect(!caption(enabled: false) && !caption(meeting: nil) && !caption(language: .de)
                     && !caption(height: 20) && !caption(room: 40),
                     "off, with no meeting, outside English, in a short strip or a narrow wing it carries none")
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
