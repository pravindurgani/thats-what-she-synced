// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// The Office edition's master switch: every extra resolves under it, the
/// caches that hold those resolutions drop them when it changes, the
/// companion keeps its chosen style, and the island's mug joins the bottom
/// row and raises its own notice.
enum NotchOfficeEditionTests {
    static func run(_ suite: TestSuite) {
        masterContracts(suite)
        gatingContracts(suite)
        companionContracts(suite)
        quickAccessContracts(suite)
        layoutContracts(suite)
        noticeContracts(suite)
        capsuleContracts(suite)
        cacheContracts(suite)
        stateContracts(suite)
    }

    /// One isolated suite, emptied before and after each use.
    private static func withSuite(_ name: String, _ body: (UserDefaults) -> Void) {
        let domain = "com.vorssaint.tests.notch-office-edition"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        body(defaults)
    }

    // MARK: The master

    private static func masterContracts(_ suite: TestSuite) {
        suite.expect(DefaultsKey.notchOfficeEditionEnabled == "notchOfficeEditionEnabled",
                     "the master keeps its documented name")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchOfficeEditionEnabled] as? Bool == true,
                     "the master is registered on, beside the fork's other keys")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchOfficeEditionEnabled),
                     "settings backup carries the master")
        withSuite("master") { defaults in
            suite.expect(NotchOfficeEdition.isEnabled(in: defaults), "a fresh install has the edition on")
            NotchOfficeEdition.set(false, in: defaults)
            suite.expect(!NotchOfficeEdition.isEnabled(in: defaults)
                         && defaults.object(forKey: DefaultsKey.notchOfficeEditionEnabled) as? Bool == false,
                         "turned off, it is stored off")
            for own in [false, true] {
                suite.expect(!NotchOfficeEdition.allows(own, in: defaults), "off, the master holds every switch off (own \(own))")
            }
            NotchOfficeEdition.set(true, in: defaults)
            suite.expect(NotchOfficeEdition.allows(true, in: defaults) && !NotchOfficeEdition.allows(false, in: defaults),
                         "on, each feature's own switch applies as before")
        }
    }

    // MARK: Every extra's own switch, under the master

    private static func gatingContracts(_ suite: TestSuite) {
        withSuite("gating") { defaults in
            for master in [false, true] {
                defaults.set(master, forKey: DefaultsKey.notchOfficeEditionEnabled)
                for own in [false, true] {
                    let expected = master && own
                    defaults.set(own, forKey: NotchOfficeEdition.songModeKey)
                    suite.expect(NotchOfficeEdition.songModeEnabled(in: defaults) == expected,
                                 "song colours and glow: master \(master), own \(own)")
                    defaults.set(own, forKey: DefaultsKey.notchOfficeModeEnabled)
                    suite.expect(NotchOfficeMoments.isEnabled(in: defaults) == expected,
                                 "the Office moments: master \(master), own \(own)")
                    defaults.set(own, forKey: DefaultsKey.notchIdleGlowEnabled)
                    let idle = NotchIdleGlowPreferences.enabled(in: defaults)
                    suite.expect(idle == expected, "the companion's glow: master \(master), own \(own)")
                    let allowed = NotchIslandGlow.idleAllowed(enabled: idle, lowPower: false)
                    suite.expect((NotchIslandGlow.closed(agentStrip: true, songGlows: false, companionRests: false,
                                                         idleAllowed: allowed) == .agents) == expected,
                                 "the agents' wing glow: master \(master), own \(own)")
                }
                // Nothing of its own set: each switch's own default, on.
                defaults.removeObject(forKey: NotchOfficeEdition.songModeKey)
                defaults.removeObject(forKey: DefaultsKey.notchOfficeModeEnabled)
                defaults.removeObject(forKey: DefaultsKey.notchIdleGlowEnabled)
                suite.expect(NotchOfficeEdition.songModeEnabled(in: defaults) == master
                             && NotchOfficeMoments.isEnabled(in: defaults) == master
                             && NotchIdleGlowPreferences.enabled(in: defaults) == master,
                             "untouched switches follow the master alone (master \(master))")
                suite.expect(NotchOfficeEdition.agentWings(in: defaults) == master
                             && NotchOfficeEdition.connectCard(in: defaults) == master,
                             "the agents' comet rings and split wings, and the connect card, follow the master (\(master))")
            }

            // The dancers show as bars, the dance kept.
            for side in NotchMusicSide.allCases {
                defaults.set(side.rawValue, forKey: DefaultsKey.notchMusicSide)
                defaults.set(false, forKey: DefaultsKey.notchOfficeEditionEnabled)
                suite.expect(NotchMusicSide.resolved(in: defaults) == .bars && NotchMusicSide.current(in: defaults) == side,
                             "off, \(side.rawValue) shows the bars and stays chosen")
                defaults.set(true, forKey: DefaultsKey.notchOfficeEditionEnabled)
                suite.expect(NotchMusicSide.resolved(in: defaults) == side, "on, \(side.rawValue) comes back")
            }

            // A meeting notice exists only with the moments, so only with the master.
            for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
            for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
            defaults.set(true, forKey: DefaultsKey.notchEnabled)
            defaults.set(true, forKey: DefaultsKey.notchCalendarEnabled)
            suite.expect(NotchSupport.routes(.calendar, in: defaults), "on, a meeting starting is announced")
            defaults.set(false, forKey: DefaultsKey.notchOfficeEditionEnabled)
            suite.expect(!NotchSupport.routes(.calendar, in: defaults), "off, upstream has no meeting notice")
            suite.expect(NotchSupport.routes(.officeEdition, in: defaults),
                         "the switch's own notice still shows on the way out")
            defaults.set(false, forKey: DefaultsKey.notchEnabled)
            suite.expect(!NotchSupport.routes(.officeEdition, in: defaults), "but never with the island off")
        }
    }

    // MARK: The companion

    private static func companionContracts(_ suite: TestSuite) {
        withSuite("companion") { defaults in
            for style in NotchMascotStyle.allCases {
                suite.expect(NotchOfficeEdition.companionStyle(style, in: defaults) == style,
                             "on, \(style.rawValue) draws as chosen")
            }
            defaults.set(false, forKey: DefaultsKey.notchOfficeEditionEnabled)
            for style in NotchMascotStyle.allCases {
                let expected: NotchMascotStyle = style.isCast || style == .shuffle ? .minimal : style
                suite.expect(NotchOfficeEdition.companionStyle(style, in: defaults) == expected,
                             "off, \(style.rawValue) draws as \(expected.rawValue)")
            }
            defaults.set(NotchMascotStyle.beet.rawValue, forKey: DefaultsKey.notchMascotStyle)
            defaults.set(NotchMascotShape.pill.rawValue, forKey: DefaultsKey.notchMascotShape)
            defaults.set(NotchMascotPalette.lilac.rawValue, forKey: DefaultsKey.notchMascotPalette)
            suite.expect(NotchMascotSupport.look(in: defaults)
                            == NotchMascotLook(style: .minimal, shape: .pill, palette: .lilac)
                         && NotchMascotSupport.islandLook(in: defaults).style == .minimal,
                         "off, the cast gives way to Vorssaint's own minimal companion in its chosen shape and colour")
            suite.expect(NotchMascotSupport.storedLook(in: defaults).style == .beet
                         && defaults.string(forKey: DefaultsKey.notchMascotStyle) == "beet",
                         "the chosen member stays stored")
            defaults.set(NotchMascotStyle.robot.rawValue, forKey: DefaultsKey.notchMascotStyle)
            suite.expect(NotchMascotSupport.look(in: defaults).style == .robot, "the robot is upstream's own and stays")
            defaults.set(NotchMascotStyle.shuffle.rawValue, forKey: DefaultsKey.notchMascotStyle)
            suite.expect(NotchMascotSupport.look(in: defaults).dealing(.mug).style == .minimal,
                         "off, a shuffle deals nobody")
            defaults.set(true, forKey: DefaultsKey.notchOfficeEditionEnabled)
            suite.expect(NotchMascotSupport.look(in: defaults).style == .shuffle
                         && NotchMascotSupport.look(in: defaults).dealing(.mug).style == .mug,
                         "back on, the same choice comes back")
        }
    }

    // MARK: The mug in the bottom row

    private static func quickAccessContracts(_ suite: TestSuite) {
        typealias Access = NotchQuickAccessConfiguration
        suite.expect(NotchQuickAction(id: "officeEdition") == .officeEdition && NotchQuickAction.officeEdition.id == "officeEdition",
                     "the mug's action reads back by its id")
        suite.expect(!NotchQuickAction.optionalActions.contains(.officeEdition),
                     "the mug is the island's own, never one of the choices")
        withSuite("access") { defaults in
            for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
            for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
            defaults.set(true, forKey: DefaultsKey.notchEnabled)

            // A full bottom row of the person's own: the mug joins it, after them.
            let full = Access(buttons: [
                NotchQuickButton(action: .explore, side: .bottom),
                NotchQuickButton(action: .settings, side: .bottom),
                NotchQuickButton(action: .pin, side: .bottom),
                NotchQuickButton(action: .explore, side: .left),
            ])
            defaults.set(full.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
            let shown = Access.island(in: defaults)
            let bottom = shown.buttons.filter { $0.side == .bottom }
            suite.expect(bottom.count == Access.maximumShownPerSide && bottom.last?.action == .officeEdition
                         && bottom.last?.id == Access.officeEditionButtonID,
                         "a full bottom row gains the mug at its end")
            suite.expect(Array(shown.buttons.dropLast()) == Access.stored(in: defaults).buttons
                         && Access.stored(in: defaults).buttons == full.buttons
                         && Access.current(in: defaults).buttons == full.buttons,
                         "the person's own buttons stay, in their order, and the mug is never saved or chosen")
            suite.expect(Access.stored(in: defaults).hasRoom(on: .left) && !Access.stored(in: defaults).hasRoom(on: .bottom),
                         "the mug takes none of the person's three places")

            // Side buttons only: the mug still has a bottom row of its own.
            let sides = Access(side: .left, actions: [.explore, .settings])
            defaults.set(sides.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
            let withMug = Access.island(in: defaults)
            suite.expect(withMug.hasBottom && withMug.buttons.filter { $0.side == .bottom }.map(\.action) == [.officeEdition],
                         "an island with only side buttons still offers the mug below")

            // No buttons at all: none is forced on the island.
            defaults.set(Access(buttons: []).encoded, forKey: DefaultsKey.notchQuickAccessLayout)
            suite.expect(Access.island(in: defaults).buttons.isEmpty, "an island without buttons keeps none")

            // The default layout: music below, and the mug beside it.
            defaults.removeObject(forKey: DefaultsKey.notchQuickAccessLayout)
            let initial = Access.island(in: defaults)
            suite.expect(initial.buttons.filter { $0.side == .bottom }.last?.action == .officeEdition,
                         "the default bottom row ends in the mug")
        }

        // A saved mug, which only a hand edit could make, is dropped, so it never shows twice.
        let edited = Access(buttons: [
            NotchQuickButton(action: .officeEdition, side: .left),
            NotchQuickButton(id: Access.officeEditionButtonID, action: .pin, side: .right),
            NotchQuickButton(action: .settings, side: .right),
        ]).sanitized()
        suite.expect(edited.buttons.map(\.action) == [.settings], "a stored mug, or its place, is dropped from the saved layout")
    }

    private static func layoutContracts(_ suite: TestSuite) {
        typealias Layout = NotchQuickAccessLayout
        let buttons = [NotchQuickAction.explore, .settings, .pin].map { NotchQuickButton(action: $0, side: .bottom) }
            + [NotchQuickButton(id: NotchQuickAccessConfiguration.officeEditionButtonID, action: .officeEdition, side: .bottom)]
        let body = CGRect(x: 100, y: 0, width: 420, height: 260)
        let placements = Layout.placements(NotchQuickAccessConfiguration(buttons: buttons), body: body, headerTop: 40)
        let centers = placements.map { $0.center(progress: 1) }
        suite.expect(centers.count == 4 && abs((centers[0].x + centers[3].x) / 2 - body.midX) < 0.001,
                     "four bubbles in the bottom row stay centred under the island")
        suite.expect(zip(centers, centers.dropFirst()).allSatisfy { abs($1.x - $0.x - Layout.rowSpacing) < 0.001 },
                     "the mug keeps its neighbours' spacing")
        guard let first = placements.first else { return }
        let hover = Layout.hoverRect(count: 4, edge: first.edge, top: first.top, side: .bottom)
        suite.expect(hover.contains(centers[3]) && Layout.hitTest(centers[3], count: 4, edge: first.edge, top: first.top,
                                                                   side: .bottom),
                     "the mug is in the row's hover corridor and takes its clicks")
    }

    // MARK: The notice

    private static let states = (on: "On", off: "Off")

    private static func notice(_ on: Bool, language: AppLanguage = .enUS) -> NotchNotice {
        NotchNotice(event: .officeEdition, title: "Office edition", detail: on ? states.on : states.off, symbol: "mug.fill",
                    office: NotchOfficeMoments.editionCue(on: on, states: states, language: language))
    }

    private static func noticeContracts(_ suite: TestSuite) {
        let on = NotchOfficeMoments.editionCue(on: true, states: states, language: .enUS)
        let off = NotchOfficeMoments.editionCue(on: false, states: states, language: .enUS)
        suite.expect(on.edition == true && off.edition == false && on.caption == "Back to work."
                     && off.caption == "Casual Friday.",
                     "on goes back to work, off is casual Friday")
        suite.expect(on.widestCaption == off.widestCaption && on.widestCaption == "Casual Friday."
                     && on.widestDetail == "Off" && off.widestDetail == "Off",
                     "both ways are sized for the wider caption and state")
        let german = NotchOfficeMoments.editionCue(on: true, states: states, language: .de)
        suite.expect(german.caption == nil && german.widestCaption == nil && german.edition == true,
                     "other languages keep the mug and drop the joke")
        suite.expect(!on.opensCard && !on.isLevel && !on.showsMug, "the edition is a strip notice of its own")
        suite.expect(NotchEvent.officeEdition.priority == NotchEvent.volume.priority
                     && NotchEvent.officeEdition.duration == 2
                     && NotchEvent.officeEdition.preferenceKey == DefaultsKey.notchEnabled,
                     "a tap's answer outranks other notices and stays long enough to read")

        let strings = FeatureStrings.notchOfficeEdition(.enUS)
        suite.expect(strings.title == "Office edition" && strings.state(true) == "On" && strings.state(false) == "Off"
                     && AppLanguage.allCases.allSatisfy { FeatureStrings.notchOfficeEdition($0).title == "Office edition" },
                     "the edition is named the same in every language")
        suite.expect(notice(true).accessibilityText == "Office edition, On"
                     && notice(false).accessibilityText == "Office edition, Off",
                     "VoiceOver reads only the real information, never the caption")

        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, cameraWidth: 185)
        let wingsOn = notice(true).wings(in: geometry)
        let wingsOff = notice(false).wings(in: geometry)
        suite.expect(wingsOn == wingsOff, "tapping the mug back at once never resizes the island")
        let title = NotchOfficeMoments.editionWidth("Office edition", font: NotchOfficeMoments.editionTitleFont)
        suite.expect(wingsOn.leading >= NotchOfficeMoments.mugSide + NotchOfficeMoments.levelMarkGap
                        + max(title, NotchOfficeMoments.captionWidth("Casual Friday.")) + 16
                     && wingsOn.trailing >= NotchOfficeMoments.editionWidth("Off", font: NotchOfficeMoments.editionStateFont) + 16,
                     "the mug, the title and its caption on one side, the state on the other")
        let short = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 24, cameraWidth: 185)
        suite.expect(notice(true).wings(in: short) == notice(false).wings(in: short)
                     && notice(true).wings(in: short).leading <= wingsOn.leading,
                     "a strip too short for the caption keeps both ways alike")
        suite.expect(notice(true, language: .de).wings(in: geometry) == notice(false, language: .de).wings(in: geometry),
                     "and so does a language without the caption")

        // In the open island's top row: the caption, then the title, give way first.
        let wide = NotchOfficeMoments.expandedEdition(on, title: "Office edition", detail: "On", width: 300)
        let snug = NotchOfficeMoments.expandedEdition(on, title: "Office edition", detail: "On",
                                                      width: NotchOfficeMoments.mugSide + NotchOfficeMoments.expandedSpacing * 2
                                                        + NotchOfficeMoments.editionTrailing(on, detail: "On") + title)
        let tight = NotchOfficeMoments.expandedEdition(on, title: "Office edition", detail: "On", width: 60)
        suite.expect(wide == (true, true) && snug.title && tight == (false, false)
                     && NotchOfficeMoments.expandedEdition(german, title: "Office edition", detail: "On", width: 300) == (true, false),
                     "the open island's row keeps the title where it fits, and the caption only where both fit")
    }

    private static func capsuleContracts(_ suite: TestSuite) {
        let capsule = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0, cameraWidth: 0,
                                    layout: .spacious, menuBarHeight: 24, compactSideRoom: 600, silhouette: .capsule)
        let on = NotchOfficeMoments.editionCue(on: true, states: states, language: .enUS)
        let off = NotchOfficeMoments.editionCue(on: false, states: states, language: .enUS)
        let rowOn = NotchOfficeMoments.capsuleRow(on, title: "Office edition", detail: "On", level: false, geometry: capsule)
        let rowOff = NotchOfficeMoments.capsuleRow(off, title: "Office edition", detail: "Off", level: false, geometry: capsule)
        suite.expect(rowOn == rowOff && rowOn > NotchCapsuleLayout.noticeContent(title: "Office edition", detail: "On", level: false) - 1,
                     "the capsule's row holds the mug and the wider state both ways")
        suite.expect(NotchOfficeMoments.capsuleEditionMarkWidth(capsule) >= NotchCapsuleLayout.symbolWidth
                     && NotchOfficeMoments.mugHeight * NotchOfficeMoments.capsuleMugScale(capsule) <= capsule.stripBodyHeight,
                     "the mug fits the capsule's body in the symbol's place")
        let maximum = NotchCapsuleLayout.Maximum.notice
        let captionOn = NotchOfficeMoments.capsuleCaption(on, content: rowOn, maximum: maximum, geometry: capsule)
        let captionOff = NotchOfficeMoments.capsuleCaption(off, content: rowOff, maximum: maximum, geometry: capsule)
        suite.expect((captionOn == nil) == (captionOff == nil)
                     && NotchOfficeMoments.capsuleContent(on, base: rowOn, maximum: maximum, geometry: capsule)
                        == NotchOfficeMoments.capsuleContent(off, base: rowOff, maximum: maximum, geometry: capsule),
                     "the capsule shows the caption both ways or neither, at one width")
    }

    // MARK: The caches

    /// Every cache that holds a resolution reads the master again when it
    /// changes: at once when written through NotchOfficeEdition.set, and on
    /// the change's notification when written any other way, as Settings
    /// or Terminal write it.
    private static func cacheContracts(_ suite: TestSuite) {
        let standard = UserDefaults.standard
        let keys = [DefaultsKey.notchOfficeEditionEnabled, DefaultsKey.notchMusicSide, NotchOfficeEdition.songModeKey,
                    DefaultsKey.notchOfficeModeEnabled, DefaultsKey.notchIdleGlowEnabled]
        let saved = keys.map { standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { standard.set(value, forKey: key) } else { standard.removeObject(forKey: key) }
            }
            settle()
            NotchSongPreferences.invalidate()
            NotchOfficeMoments.invalidate()
            NotchIdleGlowPreferences.invalidate()
            NotchMusicSide.invalidateCache()
        }
        standard.set(NotchMusicSide.scarn.rawValue, forKey: DefaultsKey.notchMusicSide)
        for key in [NotchOfficeEdition.songModeKey, DefaultsKey.notchOfficeModeEnabled, DefaultsKey.notchIdleGlowEnabled] {
            standard.set(true, forKey: key)
        }
        NotchOfficeEdition.set(true)
        settle()

        func caches() -> [Bool] {
            [NotchSongPreferences.enabled, NotchSongPreferences.colours, NotchOfficeMoments.isEnabled(),
             NotchIdleGlowPreferences.enabled, NotchMusicSide.current == .scarn]
        }
        suite.expect(caches().allSatisfy { $0 }, "on, every cached flag reads its own switch")
        // Read once more, so each is held.
        _ = caches()

        NotchOfficeEdition.set(false)
        suite.expect(caches().allSatisfy { !$0 }, "turned off from the mug, every cache drops at once")
        settle()
        suite.expect(caches().allSatisfy { !$0 }, "and stays off once the change's notification has been heard")

        // Written as Settings' switch or Terminal would, without the mug.
        standard.set(true, forKey: DefaultsKey.notchOfficeEditionEnabled)
        settle()
        suite.expect(caches().allSatisfy { $0 }, "turned on elsewhere, every cache reads it on the change's notification")
        standard.set(false, forKey: DefaultsKey.notchOfficeEditionEnabled)
        settle()
        suite.expect(caches().allSatisfy { !$0 }, "and off again the same way")

        // Written on another thread while the main thread is busy: the
        // writer never waits for the main thread, and the caches drop on
        // the main queue's next turn.
        let written = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            standard.set(true, forKey: DefaultsKey.notchOfficeEditionEnabled)
            written.signal()
        }
        suite.expect(written.wait(timeout: .now() + 2) == .success,
                     "a write on another thread never waits for the main thread")
        settle()
        suite.expect(caches().allSatisfy { $0 }, "and every cache reads it on the main queue's next turn")
        NotchOfficeEdition.set(false)
        suite.expect(standard.string(forKey: DefaultsKey.notchMusicSide) == NotchMusicSide.scarn.rawValue,
                     "the dance chosen is never touched")
    }

    /// The mug's own state is published on a later turn, never inside the write.
    private static func stateContracts(_ suite: TestSuite) {
        let standard = UserDefaults.standard
        let saved = standard.object(forKey: DefaultsKey.notchOfficeEditionEnabled)
        defer {
            if let saved { standard.set(saved, forKey: DefaultsKey.notchOfficeEditionEnabled) }
            else { standard.removeObject(forKey: DefaultsKey.notchOfficeEditionEnabled) }
            settle()
        }
        NotchOfficeEdition.set(true)
        settle()
        let state = NotchOfficeEditionState.shared
        settle()
        suite.expect(state.isOn, "the mug reads the edition on")
        NotchOfficeEdition.set(false)
        suite.expect(state.isOn, "the change is not published inside the write")
        settle()
        suite.expect(!state.isOn, "and arrives on the next turns of the main queue")
        NotchOfficeEdition.set(true)
        settle()
        suite.expect(state.isOn, "back on, the mug lights again")
    }

    /// Lets the main queue deliver what a write scheduled.
    private static func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
