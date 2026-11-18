// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The connect moment's rules: which notices are an audio device joining,
/// the height of the card the island opens into, and which devices were just
/// announced, so one joining is announced once. Its views live with the
/// island's (NotchConnectFlourish.swift).
enum NotchConnectFlourish {
    /// Whether a notice is an audio device connecting, as opposed to a mouse,
    /// a keyboard, or a battery warning. With the Office edition off none
    /// is: the device keeps upstream's plain accessory notice.
    static func applies(to notice: NotchNotice) -> Bool {
        guard notice.event == .accessory, notice.level == nil, NotchOfficeEdition.connectCard() else { return false }
        let symbol = notice.symbol.lowercased()
        return ["airpods", "headphones", "beats", "earbuds", "hifispeaker", "homepod", "speaker", "airplay"]
            .contains { symbol.contains($0) }
    }

    /// The opened island's card below the camera's row.
    static let cardHeight: CGFloat = 112

    // A device announced by one path (Bluetooth, or the sound's route) is not
    // announced again by the other a moment later. The two can name a device a
    // little differently ("Buds" and "Buds Stereo"), so names are compared
    // by their letters and digits, one containing the other. Main thread only.
    private static var announced: [String: Date] = [:]

    private static func key(_ name: String) -> String {
        String(String.UnicodeScalarView(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    static func noteAnnounced(_ name: String) {
        announced = announced.filter { $0.value.timeIntervalSinceNow > -30 }
        announced[key(name)] = Date()
    }

    static func wasAnnounced(_ name: String, within seconds: TimeInterval = 8) -> Bool {
        let name = key(name)
        guard name.count >= 3 else { return false }
        return announced.contains { known, when in
            -when.timeIntervalSinceNow < seconds && known.count >= 3 && (known.contains(name) || name.contains(known))
        }
    }
}
