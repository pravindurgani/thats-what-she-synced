// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The "Office edition" switch: the island's mug in its bottom row, the
/// notice it raises, and the card in Settings that holds it with every other
/// switch this fork adds. The edition is this fork's own name, so it reads
/// the same in every language.
struct NotchOfficeEditionStrings {
    /// The switch's name: the mug's tooltip and VoiceOver label, the notice's
    /// title and the Settings row.
    let title: String
    let on: String
    let off: String
    /// What the mug does, for VoiceOver.
    let hint: String
    /// Under the switch in Settings: what it covers, and what off leaves.
    let settingsHint: String

    // The card in Settings, on the island's Activity page.

    /// The card's heading: the fork's name.
    let cardTitle: String
    let songColours: String
    let songColoursHint: String
    /// How much of a cover's colour the island wears (NotchSongLook).
    let look: String
    let vivid: String
    let oneColour: String
    let lookHint: String
    let officeAlerts: String
    let officeAlertsHint: String
    let idleGlow: String
    let idleGlowHint: String
    /// The links to the companion's and the music side's own choices, for
    /// VoiceOver.
    let openHint: String
    /// More words a search finds the card by.
    let keywords: [String]

    func state(_ on: Bool) -> String { on ? self.on : off }

    func look(_ look: NotchSongLook) -> String {
        switch look {
        case .vivid: return vivid
        case .duotone: return oneColour
        }
    }

    static let english = NotchOfficeEditionStrings(
        title: "Office edition",
        on: "On",
        off: "Off",
        hint: "Turns all of the island’s Office extras on or off at once.",
        settingsHint: "Every extra below at once. Off, the island is plain Vorssaint.",
        cardTitle: "That’s What She Synced",
        songColours: "Song colours",
        songColoursHint: "The island wears the colours of the song’s cover.",
        look: "Look",
        vivid: "Vivid",
        oneColour: "One colour",
        lookHint: "One colour keeps just the cover’s main colour.",
        officeAlerts: "Office alerts",
        officeAlertsHint: "Battery, calls, meetings and more, the Office way.",
        idleGlow: "Glow when nothing plays",
        idleGlowHint: "The companion’s colours light the island when no song is on.",
        openHint: "Opens where it is chosen.",
        keywords: ["Office", "mug", "colour", "color", "glow", "theme", "duotone", "alerts", "notices"])
}

extension FeatureStrings {
    /// English in every language for now: this fork's own setting, not yet
    /// translated. Each language is listed so a new one is a decision.
    static func notchOfficeEdition(_ language: AppLanguage) -> NotchOfficeEditionStrings {
        switch language {
        case .enUS, .ptBR, .tr, .ru, .es, .sk, .de, .fr, .it, .ja, .ko, .uk, .zhHans, .zhTW, .zhHK:
            return .english
        }
    }
}
