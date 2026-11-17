// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The "Music side" choice: what the closed island's music strip shows on
/// the camera's right. The dances keep generic names in every language.
struct NotchDancerStrings {
    let musicSide: String
    let bars: String
    let boomboxBoss: String
    let farewellThree: String
    let scarn: String
    /// A different dance for each new song.
    let shuffle: String

    func name(_ side: NotchMusicSide) -> String {
        switch side {
        case .bars: return bars
        case .boomboxBoss: return boomboxBoss
        case .farewellThree: return farewellThree
        case .scarn: return scarn
        case .shuffle: return shuffle
        }
    }

    static let english = NotchDancerStrings(
        musicSide: "Music side",
        bars: "Bars",
        boomboxBoss: "Boombox Boss",
        farewellThree: "The Farewell Three",
        scarn: "The Scarn",
        shuffle: "Shuffle")
}

extension FeatureStrings {
    /// English in every language for now: this fork's own setting, not yet
    /// translated. Each language is listed so a new one is a decision.
    static func notchDancers(_ language: AppLanguage) -> NotchDancerStrings {
        switch language {
        case .enUS, .ptBR, .tr, .ru, .es, .sk, .de, .fr, .it, .ja, .ko, .uk, .zhHans, .zhTW, .zhHK:
            return .english
        }
    }
}
