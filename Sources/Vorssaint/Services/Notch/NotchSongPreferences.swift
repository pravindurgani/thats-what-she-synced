// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How much colour the island wears with a song: `vivid`, the cover's whole
/// palette (the default), or `duotone`, its lead colour and a neutral
/// ("One colour" in Settings). Chosen in Settings, where a change applies at
/// once (NotchOfficeEditionSettings). A `defaults write` from Terminal posts
/// no notification in this process, so it is read on the next launch.
enum NotchSongLook: String, CaseIterable, Identifiable {
    case vivid, duotone

    var id: String { rawValue }

    static var current: NotchSongLook { NotchSongPreferences.look }
}

/// The song mode's two settings, and the Office edition's master over every
/// colour a song lends the island, read once and again only after a change,
/// since the island asks for them on every frame of a resize. Main thread only.
enum NotchSongPreferences {
    private static var cached: (look: NotchSongLook, enabled: Bool, colours: Bool)?
    private static var observer: NSObjectProtocol?

    static var look: NotchSongLook { read().look }
    /// The island wearing the song, under the Office edition's master.
    static var enabled: Bool { read().enabled }
    /// Whether a song colours the island at all: the player's plate, timeline
    /// and bars, the volume meter, the colourless-cover fallback. Off only
    /// with the Office edition, which leaves the player upstream's.
    static var colours: Bool { read().colours }

    private static func read() -> (look: NotchSongLook, enabled: Bool, colours: Bool) {
        if let cached { return cached }
        if observer == nil { observer = NotchPreferenceCache.observeDefaults { cached = nil } }
        let defaults = UserDefaults.standard
        let fresh = (look: NotchOfficeEditionSettings.look(in: defaults),
                     enabled: NotchOfficeEdition.songModeEnabled(in: defaults),
                     colours: NotchOfficeEdition.isEnabled(in: defaults))
        cached = fresh
        return fresh
    }

    /// Read again on the next ask. Every write from Settings or the mug
    /// calls it straight after writing (NotchPreferenceCache.dropAll), so
    /// nothing drawn before the change's notification arrives keeps the old
    /// value.
    static func invalidate() { cached = nil }
}
