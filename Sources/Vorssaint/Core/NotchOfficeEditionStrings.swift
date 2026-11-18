// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The "Office edition" switch: the island's mug in its bottom row, the
/// notice it raises and its row in Settings. The edition is this fork's own
/// name, so it reads the same in every language.
struct NotchOfficeEditionStrings {
    /// The switch's name: the mug's tooltip and VoiceOver label, the notice's
    /// title and the Settings row.
    let title: String
    let on: String
    let off: String
    /// What the mug does, for VoiceOver.
    let hint: String
    /// Under the switch in Settings: what it covers, and that each extra
    /// keeps its own setting.
    let settingsHint: String

    func state(_ on: Bool) -> String { on ? self.on : off }

    static let english = NotchOfficeEditionStrings(
        title: "Office edition",
        on: "On",
        off: "Off",
        hint: "Turns all of the island’s Office extras on or off at once.",
        settingsHint: "The song’s colours and glow, the Office moments, the dancers, the cast, the companion’s glow "
            + "and the agents’ wings, all at once. Off, the island is plain Vorssaint, and each keeps its own "
            + "setting for when it is back on.")
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
