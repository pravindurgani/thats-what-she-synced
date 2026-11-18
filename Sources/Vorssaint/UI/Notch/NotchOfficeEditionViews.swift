// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The Office edition's mug at the end of the open island's bottom row: one
/// tap turns every extra of this fork on or off at once (NotchOfficeEdition).
/// On, it is lit like its neighbours, in the song's colours or else the
/// companion's or the Office's, the mug in that colour, and a tap that turns
/// it on puffs a little steam. Off, it is a plain grey bubble with the mug
/// dimmed. Reduce Motion and Low Power Mode keep the puff out and the change
/// to a fade.
struct NotchOfficeEditionBubble: View {
    @ObservedObject var service: NotchService
    /// The song's palette while the island wears it, as the neighbours wear it.
    let song: NotchArtworkPalette?
    let playing: Bool
    /// Where in the turn its colour starts, as each neighbour's.
    let phase: Double
    /// Glass keeps every bubble's base nearly clear.
    let glass: Bool
    @ObservedObject private var edition = NotchOfficeEditionState.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var lowPower = NotchLowPowerMode.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    /// Counts the taps that turned it on, each one a puff.
    @State private var brews = 0

    private var calm: Bool { reduceMotion || lowPower.isOn }

    /// The Office's own colours, for a lit mug with no song and no companion.
    private static let office = NotchArtworkPalette(pure: [NotchOfficeInk.jelly, NotchOfficeInk.mustard,
                                                           NotchOfficeInk.beet].map { NSColor($0) })

    /// The song's colours, else the companion's while it is out, else the Office's.
    private var lit: NotchArtworkPalette {
        if let song { return song }
        if NotchMascotSupport.isEnabled() { return NotchIdlePalette.current() }
        return Self.office
    }

    var body: some View {
        let text = FeatureStrings.notchOfficeEdition(l10n.language)
        let on = edition.isOn
        let palette = lit
        Button {
            service.activateQuickAction(.officeEdition)
        } label: {
            ZStack {
                Image(systemName: "mug.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(on ? Color(nsColor: palette.marks[0])
                                     : .white.opacity(contrast == .increased ? 0.7 : 0.4))
                // From the cup, left of the handle, up into the bubble, as
                // white as the battery mug's steam.
                NotchOfficeSteamPuff(trigger: brews > 0 ? "\(brews)" : nil, delay: 0.04)
                    .frame(width: 8, height: 7)
                    .offset(x: -1.5, y: -14)
            }
            .frame(width: NotchQuickAccessLayout.diameter, height: NotchQuickAccessLayout.diameter)
            .background {
                ZStack {
                    Circle().fill(glass ? Color.black.opacity(0.02) : Color.black)
                    if on {
                        NotchAuroraBubble(colors: palette.glow, playing: playing && song != nil, phase: phase)
                            .clipShape(Circle())
                            .transition(.opacity)
                    } else {
                        Circle().fill(Color.white.opacity(glass ? 0.12 : 0.16))
                            .transition(.opacity)
                    }
                }
            }
            .overlay {
                Circle().strokeBorder(.white.opacity(on || contrast == .increased ? 0.6 : 0.16), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .animation(calm ? NotchSongMotion.reduced : NotchSongMotion.fade, value: on)
            .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: NotchQuickAccessLayout.diameter / 2))
        .help(text.title)
        .accessibilityLabel(text.title)
        .accessibilityValue(text.state(on))
        .accessibilityHint(text.hint)
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("notch.quickAccess.officeEdition")
        // A puff for each tap that turns it on, read after the change lands.
        .onChange(of: on) { _, now in if now { brews += 1 } }
    }
}

/// The edition's notice in the closed island, by the island's end: the mug,
/// the title large beside it and the lower third under the title, all
/// punching in, the words out of a blur and the caption a beat after.
struct NotchOfficeEditionReading: View {
    let on: Bool
    let title: String
    /// Nil outside English, or where the strip has no room for a second line.
    let caption: String?
    /// Changes with each tap, so the mug's move plays again.
    let trigger: String?

    var body: some View {
        HStack(spacing: NotchOfficeMoments.levelMarkGap) {
            NotchOfficeMug.edition(on, coffee: NotchOfficeInk.coffee(), trigger: trigger ?? "")
                .frame(width: NotchOfficeMoments.mugSide)
            NotchOfficeEditionWords(title: title, caption: caption, trigger: trigger)
        }
        .notchPunchIn(trigger)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The title and its lower third, as every edition notice writes them.
private struct NotchOfficeEditionWords: View {
    let title: String
    let caption: String?
    let trigger: String?
    /// The caption follows the title by about a third of a second.
    static let titleDelay = 0.1
    static let captionDelay = titleDelay + 0.32

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Font(NotchOfficeMoments.editionTitleFont as CTFont))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .notchArrival(trigger, delay: Self.titleDelay)
            if let caption {
                NotchLowerThird(caption: caption, trigger: trigger, delay: Self.captionDelay)
            }
        }
    }
}

/// The far side's state, On or Off, as a notice's reading.
struct NotchOfficeEditionStateText: View {
    let state: String
    let trigger: String?

    var body: some View {
        Text(state)
            .font(Font(NotchOfficeMoments.editionStateFont as CTFont))
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(1)
            .fixedSize()
            .notchPunchIn(trigger, delay: 0.05)
    }
}

/// The edition's notice in the open island's top row, where it covers one
/// side for the moment it shows: the mug, the title with its caption under
/// it where the side holds them (NotchOfficeMoments.expandedEdition), and
/// the state at the far end.
struct NotchOfficeExpandedEdition: View {
    let cue: NotchOfficeCue
    let title: String
    let detail: String
    let width: CGFloat?
    let trigger: String

    var body: some View {
        let fit = NotchOfficeMoments.expandedEdition(cue, title: title, detail: detail, width: width)
        HStack(spacing: NotchOfficeMoments.expandedSpacing) {
            NotchOfficeMug.edition(cue.edition == true, coffee: NotchOfficeInk.coffee(), trigger: trigger)
                .frame(width: NotchOfficeMoments.mugSide)
            if fit.title {
                NotchOfficeEditionWords(title: title, caption: fit.caption ? cue.caption : nil, trigger: trigger)
            }
            Spacer(minLength: 0)
            NotchOfficeEditionStateText(state: detail, trigger: trigger)
        }
        .notchPunchIn(trigger)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The edition's mug in a floating capsule's row, in a notice's symbol
/// slot, no taller than the capsule's body leaves it.
struct NotchOfficeCapsuleEditionMug: View {
    let on: Bool
    let geometry: NotchGeometry
    let trigger: String

    var body: some View {
        let scale = NotchOfficeMoments.capsuleMugScale(geometry)
        NotchOfficeMug.edition(on, coffee: NotchOfficeInk.coffee(), trigger: trigger)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: (NotchOfficeMoments.mugSide * scale).rounded(.up),
                   height: NotchOfficeMoments.mugHeight * scale, alignment: .topLeading)
            // The cup sits low in its box, under the steam's room; as the
            // row's mark it is centred on the words instead.
            .offset(y: -NotchOfficeMoments.mugSteamRoom / 2 * scale)
            .frame(width: NotchOfficeMoments.capsuleEditionMarkWidth(geometry))
            .notchPunchIn(trigger)
    }
}
