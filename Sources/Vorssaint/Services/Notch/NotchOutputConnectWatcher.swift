// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Announces an audio output joining, the moment the Mac switches its sound
/// to it: wired, USB or Bluetooth headphones, or a speaker. It needs no
/// Bluetooth access, since it reads the sound's route, not the radio, so it
/// also catches wired earphones the accessory service never sees.
///
/// Switching back to the Mac's own speakers is not a connection, nor is the
/// output already in use when the island starts, nor a virtual device such
/// as a call app's own audio. A Bluetooth device the accessory service has
/// just announced is not announced twice.
final class NotchOutputConnectWatcher {
    static let shared = NotchOutputConnectWatcher()

    private var subscription: AnyCancellable?
    private var lastUID: String?
    private var baselineTaken = false
    private init() {}

    func syncWithPreferences() {
        guard NotchAccessorySupport.isEnabled(), AppFeature.mixer.isAvailable else { stop(); return }
        guard subscription == nil else { return }
        baselineTaken = false
        let mixer = AppVolumeMixer.shared
        subscription = mixer.$currentOutputDeviceUID
            .removeDuplicates()
            // A route settles over a few readings as a device wakes; one notice for where it lands.
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] uid in self?.routed(to: uid) }
    }

    func stop() {
        subscription = nil
        lastUID = nil
        baselineTaken = false
    }

    private func routed(to uid: String?) {
        guard baselineTaken else { baselineTaken = true; lastUID = uid; return }
        guard let uid, uid != lastUID else { return }
        lastUID = uid
        guard NotchAccessorySupport.isEnabled(),
              let device = AppVolumeMixer.shared.outputDevices.first(where: { $0.uid == uid }),
              let symbol = Self.symbol(for: device) else { return }
        guard !NotchConnectFlourish.wasAnnounced(device.name) else { return }
        let text = FeatureStrings.notchActivities(L10n.shared.language)
        let notice = NotchNotice(event: .accessory, title: text.connected, detail: device.name, symbol: symbol)
        if NotchService.shared.showConnect(notice) { NotchConnectFlourish.noteAnnounced(device.name) }
    }

    /// The glyph for a device worth announcing, or nil for one that is not.
    static func symbol(for device: MixerOutputDevice) -> String? {
        let name = device.name.lowercased()
        let soundsLikeEarphones = ["headphone", "earphone", "earpods", "airpods", "buds", "headset", "beats"]
            .contains { name.contains($0) }
        if device.isHeadphones || soundsLikeEarphones {
            return NotchAccessorySupport.symbol(for: .audio, name: device.name)
        }
        switch device.priorityTier {
        case .hardware: return "hifispeaker"
        case .builtIn, .virtual: return nil
        }
    }
}
