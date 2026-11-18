// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// "That's What She Synced": every switch this fork adds to the island, in
/// one card on the Dynamic Island's Activity page. The Office edition's
/// master comes first; under it, each extra's own switch and the song's look,
/// greyed while the master is off but still showing what comes back with it;
/// then where the companion and the music side are chosen, which keep their
/// own places rather than being repeated here.
///
/// Every change applies at once (NotchOfficeEditionSettings), with no relaunch.
struct NotchOfficeEditionCard: View {
    /// Shows the companion's tab; nil while the companion is not installed.
    let openCompanion: (() -> Void)?
    /// Shows the music section, where the music side is chosen.
    let openMusicSide: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchOfficeEditionEnabled) private var edition = true
    @AppStorage(DefaultsKey.notchSongModeEnabled) private var songColours = true
    @AppStorage(DefaultsKey.notchSongLook) private var look = NotchSongLook.vivid.rawValue
    @AppStorage(DefaultsKey.notchOfficeModeEnabled) private var officeAlerts = true
    @AppStorage(DefaultsKey.notchIdleGlowEnabled) private var idleGlow = true
    @AppStorage(DefaultsKey.notchMascotEnabled) private var companionOn = false
    @AppStorage(DefaultsKey.notchMascotStyle) private var companionStyle = NotchMascotStyle.minimal.rawValue
    @AppStorage(DefaultsKey.notchMusicSide) private var musicSide = NotchMusicSide.bars.rawValue

    private var text: NotchOfficeEditionStrings { FeatureStrings.notchOfficeEdition(l10n.language) }

    var body: some View {
        SettingsCard(title: text.cardTitle) {
            switchRow("mug", text.title, caption: text.settingsHint,
                      isOn: Binding(get: { edition }, set: { on in apply { NotchOfficeEdition.set(on) } }))
            VStack(alignment: .leading, spacing: 13) {
                switchRow("paintpalette", text.songColours, caption: text.songColoursHint,
                          isOn: binding(.songColours, songColours))
                SettingsRow(symbol: "circle.lefthalf.filled", title: text.look, caption: text.lookHint) {
                    // Read as the island reads it, so a value it does not know shows Vivid here too.
                    Picker(text.look, selection: Binding(
                        get: { NotchSongLook(rawValue: look) ?? .vivid },
                        set: { chosen in apply { NotchOfficeEditionSettings.setLook(chosen) } })) {
                        ForEach(NotchSongLook.allCases) { item in
                            Text(text.look(item)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                switchRow("briefcase", text.officeAlerts, caption: text.officeAlertsHint,
                          isOn: binding(.officeAlerts, officeAlerts))
                switchRow("sparkles", text.idleGlow, caption: text.idleGlowHint,
                          isOn: binding(.idleGlow, idleGlow))
            }
            // Off, the master holds them all off: each shows its own choice,
            // greyed, as it will be when the edition is back on.
            .disabled(!edition)
            .saturation(edition ? 1 : 0)
            .opacity(edition ? 1 : 0.45)
            Divider()
            if let openCompanion {
                let companion = FeatureStrings.notchMascot(l10n.language)
                let style = NotchMascotStyle(rawValue: companionStyle) ?? .minimal
                link(AppFeature.notchMascot.symbolName, companion.title,
                     value: companionOn ? companion.style(style) : text.off, action: openCompanion)
            }
            let dancers = FeatureStrings.notchDancers(l10n.language)
            link("figure.dance", dancers.musicSide, value: dancers.name(NotchMusicSide(stored: musicSide)),
                 action: openMusicSide)
        }
    }

    private func binding(_ extra: NotchOfficeEditionSettings.Extra, _ stored: Bool) -> Binding<Bool> {
        Binding(get: { stored }, set: { on in apply { NotchOfficeEditionSettings.set(extra, on) } })
    }

    /// Writes through the settings model, which drops every cache at once and
    /// lets the island's own sync redraw it. The open player observes only
    /// the music, so it is asked to draw again too.
    private func apply(_ write: () -> Void) {
        write()
        NotchMusicService.shared.objectWillChange.send()
    }

    /// An option with its icon, one line and a switch, as on the rest of the page.
    private func switchRow(_ symbol: String, _ title: String, caption: String, isOn: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol, title: title, caption: caption) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }

    /// A choice kept on its own page: what is chosen now, and the way there.
    private func link(_ symbol: String, _ title: String, value: String, action: @escaping () -> Void) -> some View {
        SettingsRow(symbol: symbol, title: title) {
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(value)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.link)
            .accessibilityLabel("\(title), \(value)")
            .accessibilityHint(text.openHint)
        }
    }
}
