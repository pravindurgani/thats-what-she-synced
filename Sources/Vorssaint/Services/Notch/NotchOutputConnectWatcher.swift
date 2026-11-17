// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Announces an audio output joining: wired, USB or Bluetooth headphones the
/// moment they appear as an output, and a speaker once the Mac switches its
/// sound to it. It needs no Bluetooth access, since it reads the sound's
/// outputs, not the radio, so it also catches wired earphones the accessory
/// service never sees.
///
/// Only a device that has just appeared counts. Choosing between outputs
/// already attached is not a connection, nor is the Mac's own speakers, a
/// monitor's speakers, a virtual device such as a call app's, the output in
/// use when the island starts, or a device returning after the Mac or its
/// display wakes. A device the accessory service has just announced is not
/// announced twice. All of it runs on the main thread.
final class NotchOutputConnectWatcher {
    static let shared = NotchOutputConnectWatcher()

    /// How recently a device must have appeared for a switch to it to count.
    private static let appearanceWindow: TimeInterval = 15
    /// How long after starting, a wake or a re-sync routes are only learned.
    private static let quietPeriod: TimeInterval = 10

    private var subscription: AnyCancellable?
    private var wakeObservers: [NSObjectProtocol] = []
    private var lastUID: String?
    /// Devices present, with when each appeared; the first list is the baseline.
    private var present: [String: Date] = [:]
    private var baselineTaken = false
    private var quietUntil = Date.distantPast
    private var retry: DispatchWorkItem?
    private init() {}

    func syncWithPreferences() {
        guard NotchAccessorySupport.isEnabled(), AppFeature.mixer.isAvailable else { stop(); return }
        guard subscription == nil else { return }
        baselineTaken = false
        present = [:]
        quiet()
        let mixer = AppVolumeMixer.shared
        subscription = mixer.$outputDevices.combineLatest(mixer.$currentOutputDeviceUID)
            // A route settles over a few readings as a device wakes; one notice for where it lands.
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] devices, uid in self?.update(devices: devices, route: uid) }
        let center = NSWorkspace.shared.notificationCenter
        wakeObservers = [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification].map {
            center.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in self?.quiet() }
        }
    }

    func stop() {
        subscription = nil
        wakeObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        wakeObservers = []
        retry?.cancel(); retry = nil
        lastUID = nil
        present = [:]
        baselineTaken = false
    }

    private func quiet() { quietUntil = Date().addingTimeInterval(Self.quietPeriod) }

    private func update(devices: [MixerOutputDevice], route uid: String?) {
        // The mixer reports nothing while it starts or restarts; the baseline
        // is the first real reading, so what is already attached stays quiet.
        guard baselineTaken else {
            guard uid != nil, !devices.isEmpty else { return }
            baselineTaken = true
            present = Dictionary(devices.map { ($0.uid, Date.distantPast) }, uniquingKeysWith: { first, _ in first })
            lastUID = uid
            return
        }
        // A mixer restarting reports no devices for a moment; what returns
        // after it was attached all along.
        guard !devices.isEmpty else { quiet(); return }
        let now = Date()
        let uids = Set(devices.map(\.uid))
        present = present.filter { uids.contains($0.key) }
        var joined: [MixerOutputDevice] = []
        for device in devices where present[device.uid] == nil {
            // After a wake, what reappears was attached all along.
            present[device.uid] = now < quietUntil ? .distantPast : now
            if now >= quietUntil { joined.append(device) }
        }
        // Earphones are announced as they connect, not seconds later when
        // macOS moves the sound to them.
        if NotchAccessorySupport.isEnabled(), let device = joined.first(where: Self.isEarphones) {
            announce(device: device, symbol: NotchAccessorySupport.symbol(for: .audio, name: device.name), retrying: true)
        }
        guard let uid, uid != lastUID else { return }
        lastUID = uid
        // A speaker counts once the sound moves to it, so a monitor or a dock
        // attaching never opens the island by itself.
        guard now >= quietUntil, let appeared = present[uid], now.timeIntervalSince(appeared) < Self.appearanceWindow,
              NotchAccessorySupport.isEnabled(),
              let device = devices.first(where: { $0.uid == uid }), !Self.isEarphones(device),
              let symbol = Self.symbol(for: device) else { return }
        announce(device: device, symbol: symbol, retrying: true)
    }

    private func announce(device: MixerOutputDevice, symbol: String, retrying: Bool) {
        guard !NotchConnectFlourish.wasAnnounced(device.name) else { return }
        let text = FeatureStrings.notchActivities(L10n.shared.language)
        let notice = NotchNotice(event: .accessory, title: text.connected, detail: device.name, symbol: symbol)
        if NotchService.shared.showConnect(notice) {
            NotchConnectFlourish.noteAnnounced(device.name)
        } else if retrying {
            // A notice of the switch itself (volume) may hold the strip for a moment.
            let work = DispatchWorkItem { [weak self] in
                // Still connected: it is announced late rather than not at all.
                guard let self, self.present[device.uid] != nil else { return }
                self.announce(device: device, symbol: symbol, retrying: false)
            }
            retry?.cancel()
            retry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
        }
    }

    static func isEarphones(_ device: MixerOutputDevice) -> Bool {
        let name = device.name.lowercased()
        return device.isHeadphones
            || ["headphone", "earphone", "earpods", "airpods", "buds", "headset", "beats"].contains { name.contains($0) }
    }

    /// The glyph for a device worth announcing, or nil for one that is not.
    static func symbol(for device: MixerOutputDevice) -> String? {
        if isEarphones(device) {
            return NotchAccessorySupport.symbol(for: .audio, name: device.name)
        }
        switch device.priorityTier {
        case .hardware:
            // A display's own speakers come and go with the display.
            return AppVolumeMixer.shared.outputIsMonitorSpeakers ? nil : "hifispeaker"
        case .builtIn, .virtual:
            return nil
        }
    }
}
