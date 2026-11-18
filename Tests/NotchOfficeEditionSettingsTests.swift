// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The "That's What She Synced" card: every switch this fork adds is a
/// registered, backed-up preference the settings model reads as stored and
/// writes live, every cache that resolves it drops at once, search finds
/// each by its label, and every language has the card's words.
enum NotchOfficeEditionSettingsTests {
    typealias Model = NotchOfficeEditionSettings

    static func run(_ suite: TestSuite) {
        keyContracts(suite)
        modelContracts(suite)
        liveContracts(suite)
        searchContracts(suite)
        stringContracts(suite)
    }

    /// One isolated suite, emptied before and after each use.
    private static func withSuite(_ body: (UserDefaults) -> Void) {
        let domain = "com.vorssaint.tests.notch-office-edition-settings"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        body(defaults)
    }

    // MARK: Keys, registration and backup

    private static func keyContracts(_ suite: TestSuite) {
        suite.expect(Model.keys == [DefaultsKey.notchOfficeEditionEnabled, DefaultsKey.notchSongModeEnabled,
                                    DefaultsKey.notchOfficeModeEnabled, DefaultsKey.notchIdleGlowEnabled,
                                    DefaultsKey.notchSongLook],
                     "the card writes the master, its three extras and the look")
        suite.expect(Set(Model.keys).count == Model.keys.count && Model.keys.allSatisfy { $0.hasPrefix("notch") },
                     "each key once, each an island key a backup keeps with the island's")
        suite.expect(DefaultsKey.notchSongModeEnabled == "notchSongModeEnabled"
                     && DefaultsKey.notchSongLook == "notchSongLook"
                     && NotchOfficeEdition.songModeKey == DefaultsKey.notchSongModeEnabled,
                     "the keys keep the names Terminal and older builds wrote")
        let registered = Defaults.registeredDefaults
        suite.expect(Model.Extra.allCases.allSatisfy { registered[$0.key] as? Bool == true }
                     && registered[DefaultsKey.notchOfficeEditionEnabled] as? Bool == true
                     && registered[DefaultsKey.notchSongLook] as? String == NotchSongLook.vivid.rawValue,
                     "every switch is registered on, and the look vivid")
        let exported = SettingsBackupSupport.exportKeys()
        let carried = Model.keys + [DefaultsKey.notchMusicSide, DefaultsKey.notchMascotStyle, DefaultsKey.notchMascotEnabled]
        suite.expect(Set(carried).isSubset(of: exported)
                     && Set(carried).isDisjoint(with: SettingsBackupSupport.machineStateKeys),
                     "a settings backup carries every switch in the card, and the choices it links to")
    }

    // MARK: The settings model

    private static func modelContracts(_ suite: TestSuite) {
        withSuite { defaults in
            suite.expect(Model.Extra.allCases.allSatisfy { Model.isOn($0, in: defaults) }
                         && Model.look(in: defaults) == .vivid && Model.isEditable(in: defaults),
                         "a fresh install has every extra on, the vivid look, and the card editable")
            for extra in Model.Extra.allCases {
                Model.set(extra, false, in: defaults)
                suite.expect(!Model.isOn(extra, in: defaults) && defaults.object(forKey: extra.key) as? Bool == false,
                             "\(extra.rawValue) turned off is stored off")
                Model.set(extra, true, in: defaults)
                suite.expect(Model.isOn(extra, in: defaults), "\(extra.rawValue) turned back on")
            }
            Model.setLook(.duotone, in: defaults)
            suite.expect(Model.look(in: defaults) == .duotone && defaults.string(forKey: DefaultsKey.notchSongLook) == "duotone",
                         "One colour is stored as duotone, the value Terminal wrote")
            defaults.set("sepia", forKey: DefaultsKey.notchSongLook)
            suite.expect(Model.look(in: defaults) == .vivid, "a look this version does not know reads vivid")

            // Off, the master holds every extra off, and each keeps its own choice.
            Model.setLook(.duotone, in: defaults)
            Model.set(.officeAlerts, false, in: defaults)
            NotchOfficeEdition.set(false, in: defaults)
            suite.expect(!Model.isEditable(in: defaults), "with the edition off, the card's extras are greyed")
            suite.expect(Model.isOn(.songColours, in: defaults) && !Model.isOn(.officeAlerts, in: defaults)
                         && Model.isOn(.idleGlow, in: defaults) && Model.look(in: defaults) == .duotone,
                         "off, each switch still shows its own stored choice")
            suite.expect(!NotchOfficeEdition.songModeEnabled(in: defaults) && !NotchOfficeMoments.isEnabled(in: defaults)
                         && !NotchIdleGlowPreferences.enabled(in: defaults),
                         "and the island resolves every one of them off")
            NotchOfficeEdition.set(true, in: defaults)
            suite.expect(Model.isEditable(in: defaults) && NotchOfficeEdition.songModeEnabled(in: defaults)
                         && !NotchOfficeMoments.isEnabled(in: defaults) && NotchIdleGlowPreferences.enabled(in: defaults),
                         "back on, each comes back as it was chosen")
        }
    }

    // MARK: Live, with no relaunch

    /// What the island reads, through its caches.
    private static func resolved(_ extra: Model.Extra) -> Bool {
        switch extra {
        case .songColours: return NotchSongPreferences.enabled
        case .officeAlerts: return NotchOfficeMoments.isEnabled()
        case .idleGlow: return NotchIdleGlowPreferences.enabled
        }
    }

    private static func liveContracts(_ suite: TestSuite) {
        let standard = UserDefaults.standard
        let keys = Model.keys + [DefaultsKey.notchMusicSide]
        let saved = keys.map { standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { standard.set(value, forKey: key) } else { standard.removeObject(forKey: key) }
            }
            settle()
            NotchPreferenceCache.dropAll()
        }
        for extra in Model.Extra.allCases { Model.set(extra, true) }
        Model.setLook(.vivid)
        NotchOfficeEdition.set(true)
        settle()

        // Each switch, held in its cache, then written from the card.
        for extra in Model.Extra.allCases {
            suite.expect(resolved(extra), "\(extra.rawValue) reads on, and is held")
            Model.set(extra, false)
            suite.expect(!resolved(extra), "\(extra.rawValue) off from Settings applies at once")
            suite.expect(Model.Extra.allCases.filter { $0 != extra }.allSatisfy(resolved),
                         "turning \(extra.rawValue) off leaves the others on")
            settle()
            suite.expect(!resolved(extra), "and stays off once the change's notification is heard")
            Model.set(extra, true)
            suite.expect(resolved(extra), "\(extra.rawValue) back on applies at once")
        }

        suite.expect(NotchSongLook.current == .vivid, "the look reads vivid, and is held")
        Model.setLook(.duotone)
        suite.expect(NotchSongLook.current == .duotone, "One colour from Settings applies at once")
        Model.setLook(.vivid)
        suite.expect(NotchSongLook.current == .vivid, "and Vivid again")

        // The master from the card holds each extra off at once, choices kept.
        Model.set(.idleGlow, false)
        NotchOfficeEdition.set(false)
        suite.expect(Model.Extra.allCases.allSatisfy { !resolved($0) } && !NotchSongPreferences.colours,
                     "the edition off from Settings holds every extra off at once")
        suite.expect(Model.isOn(.songColours) && Model.isOn(.officeAlerts) && !Model.isOn(.idleGlow),
                     "while the card still shows each one's own choice")
        NotchOfficeEdition.set(true)
        suite.expect(resolved(.songColours) && resolved(.officeAlerts) && !resolved(.idleGlow),
                     "back on, the island has each as chosen at once")
        Model.set(.idleGlow, true)

        // A write to another suite never reaches what the island reads.
        withSuite { other in
            _ = NotchOfficeMoments.isEnabled()
            Model.set(.officeAlerts, false, in: other)
            Model.setLook(.duotone, in: other)
            suite.expect(NotchOfficeMoments.isEnabled() && NotchSongLook.current == .vivid,
                         "another suite's write leaves the island's switches as they are")
        }

        // Written elsewhere in this process, as a restored backup writes them,
        // on another thread: read on the main queue's next turn.
        _ = (NotchSongLook.current, resolved(.songColours))
        let written = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            standard.set(NotchSongLook.duotone.rawValue, forKey: DefaultsKey.notchSongLook)
            standard.set(false, forKey: DefaultsKey.notchSongModeEnabled)
            written.signal()
        }
        suite.expect(written.wait(timeout: .now() + 2) == .success, "a write on another thread never waits")
        settle()
        suite.expect(NotchSongLook.current == .duotone && !resolved(.songColours),
                     "a restored look and switch reach the island on the change's notification")
    }

    // MARK: Search

    private static func searchContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-office-edition-search"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let state = SettingsSearchState(defaults: defaults, hardware: .init(
            battery: true, notchedDisplay: true, plainDisplay: false,
            keyboardLight: true, bluetoothSleep: true, brightnessOSD: true))
        let card = FeatureSettingsDestination(notch: .activity)

        func routes(_ query: String, titled label: String? = nil, language: AppLanguage) -> [FeatureSettingsDestination] {
            let items = SettingsDirectory.searchItems(Strings.localized(language), language: language, state: state)
            return SettingsSearchSupport.groupedMatchingItems(query: query, items: items, isAvailable: { _ in true })
                .flatMap(\.suggestions)
                .filter { label == nil || $0.title == label }
                .map { SettingsSearchSupport.route(for: $0, isAvailable: { _ in true }).destination }
        }

        for language in [AppLanguage.enUS, .de, .ja] {
            let text = FeatureStrings.notchOfficeEdition(language)
            for label in [text.cardTitle, text.title, text.songColours, text.look, text.vivid, text.oneColour,
                          text.officeAlerts, text.idleGlow] {
                suite.expect(routes(label, titled: label, language: language).contains(card),
                             "searching \"\(label)\" in \(language.rawValue) opens the island's Activity page")
            }
        }
        for query in ["synced", "That's What She Synced", "duotone", "color", "colour", "glow", "mug", "theme"] {
            suite.expect(routes(query, language: .enUS).contains(card),
                         "searching \"\(query)\" offers the That's What She Synced card")
        }
    }

    // MARK: Words

    private static func stringContracts(_ suite: TestSuite) {
        let english = FeatureStrings.notchOfficeEdition(.enUS)
        func labels(_ text: NotchOfficeEditionStrings) -> [String] {
            [text.cardTitle, text.title, text.songColours, text.look, text.vivid, text.oneColour,
             text.officeAlerts, text.idleGlow]
        }
        func hints(_ text: NotchOfficeEditionStrings) -> [String] {
            [text.settingsHint, text.songColoursHint, text.lookHint, text.officeAlertsHint, text.idleGlowHint]
        }
        for language in AppLanguage.allCases {
            let text = FeatureStrings.notchOfficeEdition(language)
            suite.expect((labels(text) + hints(text) + [text.openHint, text.appliesWithEdition]).allSatisfy { !$0.isEmpty }
                         && labels(text) == labels(english) && hints(text) == hints(english),
                         "\(language.rawValue) has every word of the card, in English for now")
        }
        suite.expect(Set(labels(english)).count == labels(english).count, "every label in the card is its own")
        suite.expect((hints(english) + [english.appliesWithEdition]).allSatisfy { $0.count <= 70 && !$0.contains("\n") },
                     "each hint is one short line")
        suite.expect(english.appliesWithEdition.contains(english.title),
                     "the companion and music side links say they wait for the Office edition, by its name")
        // The card is SwiftUI, so it is read rather than drawn: off, the
        // links grey as the switches do and carry that line.
        let card = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Settings/NotchOfficeEditionCard.swift",
                                encoding: .utf8)) ?? ""
        let links = card.components(separatedBy: "Divider()").last ?? ""
        suite.expect(links.contains(".disabled(!edition)") && links.contains(".saturation(edition ? 1 : 0)")
                        && links.contains(".opacity(edition ? 1 : 0.45)")
                        && links.contains("edition ? nil : text.appliesWithEdition")
                        && links.components(separatedBy: "caption: waiting").count == 3,
                     "with the edition off, the companion and music side links grey and say they apply when it is on")
        suite.expect(english.look(.vivid) == english.vivid && english.look(.duotone) == english.oneColour
                     && NotchSongLook.allCases == [.vivid, .duotone],
                     "the look reads Vivid or One colour, in that order")
        suite.expect(english.cardTitle == "That’s What She Synced", "the card carries the fork's name")
    }

    /// Lets the main queue deliver what a write scheduled.
    private static func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
