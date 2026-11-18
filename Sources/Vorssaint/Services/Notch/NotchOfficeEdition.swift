// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// "Office edition": one switch over everything this fork adds to the island.
///
/// Off, the island behaves as plain Vorssaint: no song colours, glow, tinted
/// text or companion colours (NotchSongMode), no colourless-cover fallback,
/// no Office moments, no companion's glow or agents' wing glow, the bars in
/// place of the dancers, Vorssaint's own minimal companion in place of the
/// cast, the upstream agent strip in place of the comet rings and split
/// wings, and the upstream accessory notice in place of the connect card.
/// On, each of those follows its own switch exactly as it always has.
///
/// The person's own choices stay stored either way (the cast member or
/// Shuffle, the dance, each feature's switch), so turning the edition back on
/// restores them. The master is read wherever a feature resolves its own
/// switch, so every cache that already drops itself on a defaults change
/// (the song mode's, the Office moments', the companion glow's and the music
/// side's) picks the master up with it.
enum NotchOfficeEdition {
    /// On unless turned off, from the island's mug or Settings.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchOfficeEditionEnabled) as? Bool ?? true
    }

    /// A fork feature's own switch under the master: on only while both are.
    static func allows(_ own: Bool, in defaults: UserDefaults = .standard) -> Bool {
        own && isEnabled(in: defaults)
    }

    /// Writes the master. Each cache that reads it drops itself on the
    /// change's notification; for this process's own defaults they are
    /// dropped here too, so nothing read before that notification arrives
    /// keeps the old value. Main thread only.
    static func set(_ on: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: DefaultsKey.notchOfficeEditionEnabled)
        guard defaults === UserDefaults.standard else { return }
        NotchPreferenceCache.dropAll()
    }

    // MARK: Each extra, resolved

    /// The song mode's own switch, set in Settings (NotchOfficeEditionSettings).
    static let songModeKey = DefaultsKey.notchSongModeEnabled

    /// The island wearing the song: its colours, glow, tinted text and the
    /// companion's song colours.
    static func songModeEnabled(in defaults: UserDefaults = .standard) -> Bool {
        allows(defaults.object(forKey: songModeKey) as? Bool ?? true, in: defaults)
    }

    /// The companion's style as the island and the Command Bar draw it. With
    /// the edition off the cast, and a Shuffle of it, give way to Vorssaint's
    /// own minimal companion; the minimal body and the robot are upstream's
    /// and stay. The stored choice is never touched, so turning the edition
    /// back on brings the same member back.
    static func companionStyle(_ stored: NotchMascotStyle, in defaults: UserDefaults = .standard) -> NotchMascotStyle {
        guard stored.isCast || stored == .shuffle, !isEnabled(in: defaults) else { return stored }
        return .minimal
    }

    /// The agents' comet rings, their split wings and the ring that closes
    /// as a turn ends. Off, the closed island keeps upstream's agent strip.
    static func agentWings(in defaults: UserDefaults = .standard) -> Bool { isEnabled(in: defaults) }

    /// Headphones or a speaker joining open the connect card. Off, they are
    /// upstream's accessory notice in the strip.
    static func connectCard(in defaults: UserDefaults = .standard) -> Bool { isEnabled(in: defaults) }
}

/// How the island's main-thread preference caches hear a defaults change:
/// the song mode's, the Office moments' and the companion glow's, which all
/// resolve under the master. A change made on the main thread, as the mug and
/// Settings make it, drops the cache at once, so the island's next read has
/// it; one made on another thread drops it on the next turn of the main
/// queue, without that thread waiting for the main thread, as an observer on
/// the main queue would make it wait.
///
/// Only this process's own writes post that notification. A `defaults write`
/// from Terminal changes the stored value without one, so these caches keep
/// what they read until the app next launches.
enum NotchPreferenceCache {
    static func observeDefaults(_ drop: @escaping () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                               queue: nil) { _ in
            if Thread.isMainThread { drop() } else { DispatchQueue.main.async(execute: drop) }
        }
    }

    /// Every cache that resolves one of the fork's switches, dropped at once:
    /// the song mode's (its look included), the Office moments', the
    /// companion glow's and the music side's. The mug and Settings call it
    /// straight after a write, before the change's notification arrives.
    /// Main thread only.
    static func dropAll() {
        NotchSongPreferences.invalidate()
        NotchOfficeMoments.invalidate()
        NotchIdleGlowPreferences.invalidate()
        NotchMusicSide.invalidateCache()
    }
}

/// The fork's switches as Settings shows them, in the island's "That's What
/// She Synced" card: the master (NotchOfficeEdition), each extra's own switch
/// under it and the song's look.
///
/// Each reads the person's own stored choice, never its resolution under the
/// master, so a switch the master holds off still shows what comes back with
/// it. A write here applies at once, with no relaunch: every cache that
/// resolves it is dropped straight away, and the change's notification starts
/// the island's own preference sync, which measures and redraws it. A
/// `defaults write` from Terminal posts no notification here, so the island
/// reads it on the next launch.
enum NotchOfficeEditionSettings {
    /// The on or off extras under the master.
    enum Extra: String, CaseIterable, Identifiable {
        /// The island wearing the song's colours (NotchSongMode).
        case songColours
        /// The Office moments on the island's notices (NotchOfficeMoments).
        case officeAlerts
        /// The companion's colours while nothing plays (NotchIdleGlowPreferences).
        case idleGlow

        var id: String { rawValue }

        var key: String {
            switch self {
            case .songColours: return DefaultsKey.notchSongModeEnabled
            case .officeAlerts: return DefaultsKey.notchOfficeModeEnabled
            case .idleGlow: return DefaultsKey.notchIdleGlowEnabled
            }
        }
    }

    /// Every key the card writes, the master first. All are registered and
    /// carried by a settings backup.
    static let keys = [DefaultsKey.notchOfficeEditionEnabled] + Extra.allCases.map(\.key) + [DefaultsKey.notchSongLook]

    /// The person's own choice for an extra: on unless turned off.
    static func isOn(_ extra: Extra, in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: extra.key) as? Bool ?? true
    }

    /// Main thread only, as every cache it drops is.
    static func set(_ extra: Extra, _ on: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: extra.key)
        applied(in: defaults)
    }

    /// The look chosen: vivid unless one colour is, a value this version
    /// does not know included.
    static func look(in defaults: UserDefaults = .standard) -> NotchSongLook {
        NotchSongLook(rawValue: defaults.string(forKey: DefaultsKey.notchSongLook) ?? "") ?? .vivid
    }

    /// Main thread only, as every cache it drops is.
    static func setLook(_ look: NotchSongLook, in defaults: UserDefaults = .standard) {
        defaults.set(look.rawValue, forKey: DefaultsKey.notchSongLook)
        applied(in: defaults)
    }

    /// The extras and the look change only while the master is on. Off, they
    /// show their stored choices, greyed, for when it is back on.
    static func isEditable(in defaults: UserDefaults = .standard) -> Bool {
        NotchOfficeEdition.isEnabled(in: defaults)
    }

    /// Only this process's own defaults back the caches.
    private static func applied(in defaults: UserDefaults) {
        guard defaults === UserDefaults.standard else { return }
        NotchPreferenceCache.dropAll()
    }
}

/// The master as the views that draw it read it, as the island's mug does.
/// A change, from the mug, Settings or Terminal, is published on the next
/// turn of the main queue, never from inside a view update. Main thread only.
final class NotchOfficeEditionState: ObservableObject {
    static let shared = NotchOfficeEditionState()
    @Published private(set) var isOn: Bool
    private var subscription: AnyCancellable?
    private var readPending = false

    private init() {
        isOn = NotchOfficeEdition.isEnabled()
        subscription = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.readAgain() }
    }

    /// Once for a burst of changes.
    private func readAgain() {
        guard !readPending else { return }
        readPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.readPending = false
            let next = NotchOfficeEdition.isEnabled()
            if next != self.isOn { self.isOn = next }
        }
    }
}
