// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The copy moment's prop, at the boombox's scale: a desk photocopier, its
/// charcoal lid over a strip of glass, a cabinet-grey body with a control
/// panel, a ready light and an output slot. Each copy plays its one motion:
/// the scan light sweeps the glass in the moment's colour as a printed sheet
/// slides out of the slot and settles. A copy while one still plays replays
/// it quicker, and its sheet comes out over the last, which joins the pile;
/// one hard on its heels is absorbed. Nothing loops, and everything stops
/// with the notice. Reduce Motion and Low Power Mode keep the sheet out and
/// only fade the glass's light. The rules are NotchOfficeMoments' copy ones.
struct NotchOfficeCopier: View {
    let copy: NotchOfficeCopy?
    let colors: [Color]
    /// Reduce Motion or Low Power Mode: no sweep and no slide, a fade only.
    let calm: Bool

    /// Runs played in this notice; each one restarts the motion, never stacking it.
    @State private var runs = 0
    @State private var lastStart: TimeInterval?
    @State private var quick = false
    /// The light's way across the glass, 0 to 1.
    @State private var scan: CGFloat = 0
    @State private var light: Double = 0
    /// The sheets out, oldest first: the newest on top, the rest its pile.
    @State private var sheets: [Int] = []

    static let size = NotchOfficeMoments.copier
    private static let lid = CGRect(x: 1.5, y: 0.5, width: 19, height: 2.7)
    private static let glass = CGRect(x: 2.5, y: 3.2, width: 17, height: 2.1)
    private static let cabinet = CGRect(x: 1, y: 5.3, width: 20, height: 6.9)
    private static let slot = CGRect(x: 4.5, y: 9.4, width: 13, height: 1.2)
    /// The scan light's bar.
    private static let lampWidth: CGFloat = 1.7
    /// The cabinet, steel at its top to grey at its foot.
    private static let steel = Color(red: 0xB8 / 255, green: 0xBC / 255, blue: 0xC2 / 255)
    private static let cabinetGrey = Color(red: 0x7E / 255, green: 0x83 / 255, blue: 0x89 / 255)
    /// Smoked glass, so the light crossing it reads bright.
    private static let glassTint = [Color(red: 0.17, green: 0.21, blue: 0.24), Color(red: 0.08, green: 0.10, blue: 0.12)]

    private var lamp: Color { colors.first ?? NotchOfficeInk.jelly }
    /// The ready light, in the moment's second colour.
    private var ready: Color { colors.dropFirst().first ?? lamp }
    private var speed: Double { quick ? NotchOfficeMoments.copyQuickSpeed : 1 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            machine
            scanLight
            output
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
        .onChange(of: copy?.take) { replay() }
        .task(id: runs) { await play() }
    }

    // MARK: The machine

    private var machine: some View {
        let lid = Self.lid, glass = Self.glass, cabinet = Self.cabinet, slot = Self.slot
        let shell = UnevenRoundedRectangle(topLeadingRadius: 0.8, bottomLeadingRadius: 2.2, bottomTrailingRadius: 2.2,
                                           topTrailingRadius: 0.8, style: .continuous)
        return ZStack(alignment: .topLeading) {
            shell
                .fill(LinearGradient(colors: [Self.steel, Self.cabinetGrey], startPoint: .top, endPoint: .bottom))
                .overlay { shell.strokeBorder(.white.opacity(0.3), lineWidth: 0.6) }
                .frame(width: cabinet.width, height: cabinet.height)
                .offset(x: cabinet.minX, y: cabinet.minY)
            // The glass, holding a little of the lamp's colour at rest.
            Rectangle()
                .fill(LinearGradient(colors: Self.glassTint, startPoint: .top, endPoint: .bottom))
                .overlay { lamp.opacity(0.2) }
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.22)).frame(height: 0.4) }
                .frame(width: glass.width, height: glass.height)
                .offset(x: glass.minX, y: glass.minY)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.4), NotchOfficeInk.boombox], startPoint: .top,
                                     endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 1, style: .continuous).strokeBorder(.white.opacity(0.32), lineWidth: 0.6)
                }
                .frame(width: lid.width, height: lid.height)
                .offset(x: lid.minX, y: lid.minY)
            // The control panel's display, lit in the lamp's colour, and the
            // ready light; both flare as it copies.
            RoundedRectangle(cornerRadius: 0.6, style: .continuous)
                .fill(Color(white: 0.1))
                .frame(width: 5, height: 2.2)
                .offset(x: 10.9, y: 6.35)
            RoundedRectangle(cornerRadius: 0.3, style: .continuous)
                .fill(lamp.opacity(0.7 + 0.3 * light))
                .frame(width: 3.8, height: 1.1)
                .shadow(color: lamp.opacity(0.8 * light), radius: 1.4 * light)
                .offset(x: 11.5, y: 6.9)
            Circle()
                .fill(ready.opacity(0.75 + 0.25 * light))
                .frame(width: 1.9, height: 1.9)
                .shadow(color: ready.opacity(0.9 * light), radius: 1.6 * light)
                .offset(x: 17.4, y: 6.5)
            Capsule()
                .fill(Color(white: 0.06))
                .frame(width: slot.width, height: slot.height)
                .offset(x: slot.minX, y: slot.minY)
        }
    }

    /// The light under the lid: a white-hot bar in the moment's colour that
    /// lights the glass behind it as it passes, glowing past the glass's
    /// edges. Calm, the whole glass lights and goes out.
    private var scanLight: some View {
        let glass = Self.glass
        let head = (glass.width - Self.lampWidth) * scan
        return ZStack(alignment: .topLeading) {
            if calm {
                lamp.opacity(0.85)
            } else {
                LinearGradient(colors: [lamp.opacity(0), lamp.opacity(0.85)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: head + Self.lampWidth)
                Rectangle()
                    .fill(LinearGradient(colors: [lamp, .white, lamp], startPoint: .top, endPoint: .bottom))
                    .frame(width: Self.lampWidth)
                    .offset(x: head)
            }
        }
        .frame(width: glass.width, height: glass.height, alignment: .topLeading)
        .clipped()
        .shadow(color: lamp.opacity(0.9), radius: 2.6)
        .offset(x: glass.minX, y: glass.minY)
        .opacity(light)
    }

    /// The sheets out of the slot, clipped where they leave it.
    private var output: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(sheets.enumerated()), id: \.element) { index, _ in
                NotchOfficeCopierSheet(depth: sheets.count - 1 - index, kind: copy?.kind, colors: colors, calm: calm,
                                       speed: speed, delay: Self.sheetDelay / speed)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipShape(NotchOfficeBelowSlot(top: Self.slot.midY))
    }

    // MARK: The run

    /// The sheet starts out as the light crosses the glass's first part.
    private static let sheetDelay = NotchSongMotion.step
    /// The light goes out as its crossing ends.
    private static let lightOut = NotchSongMotion.fadeDuration
    /// The first run waits for the punch-in's fade, as the boombox's first kick does.
    private static let firstDelay = UInt64(NotchSongMotion.punch * 1_000_000_000)

    private func replay() {
        let now = ProcessInfo.processInfo.systemUptime
        let run = NotchOfficeMoments.copyRun(at: now, lastStart: lastStart)
        guard run != .absorbed else { return }
        quick = run == .quick
        runs += 1
    }

    @MainActor private func play() async {
        if runs == 0, !calm {
            try? await Task.sleep(nanoseconds: Self.firstDelay)
            guard !Task.isCancelled else { return }
        }
        lastStart = ProcessInfo.processInfo.systemUptime
        var reset = Transaction(animation: nil)
        reset.disablesAnimations = true
        withTransaction(reset) {
            scan = 0
            light = calm ? 0 : 1
        }
        if calm {
            // The newest sheet, out already; the glass lights and goes out.
            sheets = [runs]
            withAnimation(NotchSongMotion.reduced) { light = 1 }
            try? await Task.sleep(nanoseconds: UInt64(NotchSongMotion.swap * 1_000_000_000))
            withAnimation(NotchSongMotion.reduced) { light = 0 }
            return
        }
        // The light snaps on as a copier's lamp does; it moves a frame later.
        try? await Task.sleep(nanoseconds: NotchSongMotion.oneFrame)
        guard !Task.isCancelled else { return }
        sheets = NotchOfficeMoments.copySheets(sheets, adding: runs)
        // An even curve, so the light is seen crossing rather than cutting across.
        withAnimation(NotchSongMotion.fade.speed(speed)) { scan = 1 }
        withAnimation(NotchSongMotion.fade.speed(speed).delay(Self.lightOut / speed)) { light = 0 }
    }
}

/// One copied sheet: it slides down out of the slot on the song's spring and
/// settles, then steps back into the pile as the next one comes out over it.
/// Calm, it is out from the start.
private struct NotchOfficeCopierSheet: View {
    /// 0 for the newest, on top; each sheet under it one more.
    let depth: Int
    let kind: NotchOfficeCopyKind?
    let colors: [Color]
    let calm: Bool
    let speed: Double
    let delay: Double
    @State private var out: CGFloat = 0
    /// What this sheet was printed with as it came out, kept as later copies pile on.
    @State private var printed: NotchOfficeCopyKind??

    /// The sheet out, at rest: its top edge in the slot.
    static let paper = CGRect(x: 6, y: 10, width: 10, height: 5)
    /// How far each sheet under the newest sits from the one above it.
    static let step = CGSize(width: 0.8, height: 0.5)

    var body: some View {
        let paper = Self.paper
        let shown = calm ? 1 : out
        let depth = CGFloat(self.depth)
        face
            .frame(width: paper.width, height: paper.height)
            .offset(x: paper.minX + Self.step.width * depth,
                    y: paper.minY + Self.step.height * depth - paper.height * (1 - shown))
            .animation(calm ? NotchSongMotion.reduced : NotchSongMotion.spring.speed(speed), value: self.depth)
            .transition(.opacity.animation(NotchSongMotion.reduced))
            .task {
                if printed == nil { printed = .some(kind) }
                guard !calm else { return }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                withAnimation(NotchSongMotion.spring.speed(speed)) { out = 1 }
            }
    }

    /// Copy paper, printed with what was copied: lines of text, a link in
    /// the moment's colour, or a picture in its colours. Sheets under the top
    /// one sit in its shade.
    private var face: some View {
        let shade = depth == 0 ? 0 : 0.14
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 0.7, style: .continuous)
                .fill(NotchOfficeInk.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 0.7, style: .continuous)
                        .strokeBorder(.black.opacity(0.22), lineWidth: 0.4)
                }
            switch printed ?? kind {
            case .image:
                RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                    .fill(LinearGradient(colors: Array((colors + colors).prefix(2)), startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 7, height: 2.9)
                    .offset(x: 1.5, y: 1)
            case .link:
                line(6.6, y: 1.1, color: colors.first ?? NotchOfficeInk.jelly)
                line(4.8, y: 2.4)
            default:
                line(7, y: 1.1)
                line(5.4, y: 2.25)
                line(6.2, y: 3.4)
            }
            Rectangle().fill(.black.opacity(shade))
        }
        .clipShape(RoundedRectangle(cornerRadius: 0.7, style: .continuous))
    }

    private func line(_ width: CGFloat, y: CGFloat, color: Color = NotchOfficeInk.ink.opacity(0.55)) -> some View {
        Capsule().fill(color).frame(width: width, height: 0.75).offset(x: 1.5, y: y)
    }
}

/// Everything below the copier's slot, and a little past the box, so a sheet
/// shows only where it has left the machine.
private struct NotchOfficeBelowSlot: Shape {
    let top: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - 2, y: top, width: rect.width + 4, height: rect.maxY + 4 - top))
    }
}

// MARK: - On the island

/// The copy moment's side by the island's end, laid out as a level moment's:
/// the copier, "Copied" large beside it, and the caption under it, which
/// changes with each copy.
struct NotchOfficeCopyReading: View {
    let cue: NotchOfficeCue
    let title: String
    /// Nil where the app is not in English or the strip has no room for a second line.
    let caption: String?
    /// Changes once per moment, so another copy replays the copier without punching in again.
    let trigger: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared

    private var calm: Bool { reduceMotion || lowPower.isOn }

    var body: some View {
        HStack(spacing: NotchOfficeMoments.levelMarkGap) {
            NotchOfficeCopier(copy: cue.copy, colors: NotchOfficeInk.colors(), calm: calm)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Font(NotchOfficeMoments.copyTitleFont as CTFont))
                    .lineLimit(1)
                    .fixedSize()
                    .notchArrival(trigger)
                if let caption {
                    NotchOfficeBandCaption(kind: cue.kind, caption: caption, calm: calm)
                }
            }
            .animation(calm ? NotchSongMotion.reduced : NotchSongMotion.swapEase, value: caption)
        }
        .notchPunchIn(trigger)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What was copied, in a word, at the island's far end: the kind, never the
/// copy. A new kind fades in over the last.
struct NotchOfficeCopySummary: View {
    let summary: String
    let trigger: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared

    private var calm: Bool { reduceMotion || lowPower.isOn }

    var body: some View {
        Text(summary)
            .font(Font(NotchOfficeMoments.copySummaryFont as CTFont))
            .foregroundStyle(.white.opacity(NotchOfficeMoments.detailOpacity))
            .lineLimit(1)
            .contentTransition(.opacity)
            .animation(calm ? NotchSongMotion.reduced : NotchSongMotion.fade, value: summary)
            .notchArrival(trigger, delay: NotchOfficeMoments.readingBeat)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// A copy in a floating capsule's one row: the copier at the capsule's size,
/// "Copied" and the kind, then the caption where the capsule holds it,
/// measured as the service measures the capsule (NotchOfficeMoments.capsuleCopyRow).
struct NotchOfficeCapsuleCopy: View {
    let cue: NotchOfficeCue
    let title: String
    let detail: String
    let geometry: NotchGeometry
    /// Nil where the app is not in English or the capsule has no room for it.
    let caption: String?
    let trigger: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared

    private var calm: Bool { reduceMotion || lowPower.isOn }

    var body: some View {
        let layout = NotchCapsuleLayout.self
        let font = NotchOfficeMoments.capsuleCaptionFont(geometry)
        HStack(spacing: layout.spacing) {
            NotchOfficeCopier(copy: cue.copy, colors: NotchOfficeInk.colors(), calm: calm)
                .scaleEffect(NotchOfficeMoments.capsuleCopierScale(geometry))
                .frame(width: NotchOfficeMoments.capsuleCopierWidth(geometry),
                       height: NotchOfficeMoments.capsuleLevelHeight(geometry))
            Text(title)
                .font(Font(layout.titleFont as CTFont))
                .lineLimit(1)
                .fixedSize()
                .notchArrival(trigger)
            Text(detail)
                .font(Font(layout.detailFont as CTFont))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .contentTransition(.opacity)
                .frame(width: NotchOfficeMoments.capsuleCopySummaryWidth(cue, detail: detail), alignment: .leading)
                .padding(.leading, layout.groupSpacing - layout.spacing)
            if let caption {
                // In the room of the widest caption, so the row holds still as copies deal the next.
                NotchOfficeBandCaption(kind: cue.kind, caption: caption, calm: calm,
                                       size: font === NotchOfficeMoments.cardCaptionFont ? .card : .strip)
                    .frame(width: NotchOfficeMoments.captionWidth(NotchOfficeMoments.capsuleCaptionSlot(cue, caption: caption),
                                                                  font: font),
                           alignment: .leading)
                    .padding(.leading, layout.groupSpacing - layout.spacing)
            }
        }
        .animation(calm ? NotchSongMotion.reduced : NotchSongMotion.swapEase, value: caption)
        .animation(calm ? NotchSongMotion.reduced : NotchSongMotion.fade, value: detail)
        .notchPunchIn(trigger)
        .transaction { $0.disablesAnimations = false }
    }
}
