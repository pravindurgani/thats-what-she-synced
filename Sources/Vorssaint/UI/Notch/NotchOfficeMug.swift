// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The battery's gauge on the Office moments: a white boss-style mug, two
/// black bars standing for its printed words, filled with coffee to the
/// charge. Plugged in, a short pour raises the level and the steam starts;
/// full, a gold glint crosses it; unplugged, the steam stops and it sets
/// down with a hop; nearly empty, it tips its last drop out and shakes once.
/// The coffee wears the moment's colour and the mug always stays white.
/// Every move plays once on arrival and settles; only the steam loops, on
/// the render server. Reduce Motion shows the settled mug.
struct NotchOfficeMug: View {
    let state: NotchOfficeBattery
    /// The charge, 0 to 1.
    let level: Double
    var coffee: Color = NotchOfficeInk.latte
    /// Changes once per moment, so a new one plays again.
    let trigger: String
    /// The Office edition's mug (see `edition(_:coffee:trigger:)`) in
    /// place of a battery's: nil for a battery.
    var edition: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared

    @State private var fill: Double = 0
    @State private var pourIn: CGFloat = 0
    @State private var pourOut: CGFloat = 0
    @State private var hop: CGFloat = 0
    @State private var tilt: Double = 0
    @State private var drop: CGFloat = 0
    @State private var dropShown = false
    @State private var glint: CGFloat = -1
    @State private var steamShown = false

    /// The mug's own box: room above the brim for the pour and the steam.
    static let size = CGSize(width: NotchOfficeMoments.mugSide, height: NotchOfficeMoments.mugHeight)
    private static let cup = CGRect(x: 1, y: 7.5, width: 12, height: 14)
    private static let rim: CGFloat = 1.5

    private var settled: Double { min(1, max(0, level)) }
    private var brews: Bool { [.pluggedIn, .charging, .charged].contains(state) }
    private var liquid: Color { state == .low ? NotchOfficeInk.beet : coffee }

    var body: some View {
        let cup = Self.cup
        let inner = cup.insetBy(dx: Self.rim, dy: Self.rim)
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                handle(cup)
                UnevenRoundedRectangle(topLeadingRadius: 1.4, bottomLeadingRadius: 3.2,
                                       bottomTrailingRadius: 3.2, topTrailingRadius: 1.4, style: .continuous)
                    .fill(NotchOfficeInk.mug)
                    .frame(width: cup.width, height: cup.height)
                    .offset(x: cup.minX, y: cup.minY)
                coffeeLevel(inner)
                bars(cup)
                sheen(cup)
            }
            .rotationEffect(.degrees(tilt), anchor: UnitPoint(x: cup.minX / Self.size.width,
                                                               y: cup.maxY / Self.size.height))
            .offset(y: hop)
            pour(inner)
            lastDrop(cup)
            if let edition {
                // One puff as the edition comes on; never a loop.
                NotchOfficeSteamPuff(trigger: edition ? trigger : nil)
                    .frame(width: 8, height: 7)
                    .offset(x: cup.midX - 4, y: 0)
            } else if brews || steamShown {
                NotchOfficeSteam(color: .white.opacity(0.85), animates: brews)
                    .frame(width: 8, height: 7)
                    .offset(x: cup.midX - 4, y: 0)
                    .opacity(steamShown ? 1 : 0)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        // Off, the mug is set down empty and dimmed, as the bubble's is.
        .opacity(edition == false ? 0.62 : 1)
        .accessibilityHidden(true)
        .task(id: trigger) { await play() }
    }

    /// The Office edition's mug: on, filled with the moment's colour and
    /// brewing one puff of steam; off, set down empty. Each plays its one
    /// move as the notice lands, and again for each new tap.
    static func edition(_ on: Bool, coffee: Color, trigger: String) -> NotchOfficeMug {
        NotchOfficeMug(state: on ? .charged : .onBattery, level: on ? editionFill : 0, coffee: coffee,
                       trigger: trigger, edition: on)
    }

    /// How full the edition's mug stands: a fresh cup, short of the brim.
    static let editionFill = 0.72

    private func handle(_ cup: CGRect) -> some View {
        Path { path in
            path.move(to: CGPoint(x: cup.maxX - 0.6, y: cup.minY + 3))
            path.addCurve(to: CGPoint(x: cup.maxX - 0.6, y: cup.maxY - 4),
                          control1: CGPoint(x: cup.maxX + 5.2, y: cup.minY + 2.4),
                          control2: CGPoint(x: cup.maxX + 5.2, y: cup.maxY - 3.2))
        }
        .stroke(NotchOfficeInk.mug, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
    }

    /// The coffee from the bottom of the mug's inside up to the charge, with a
    /// lighter surface line where it meets the air.
    private func coffeeLevel(_ inner: CGRect) -> some View {
        // A nearly empty mug still shows its last sip.
        let height = fill > 0.005 ? max(1.8, inner.height * fill) : 0
        return VStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.35)).frame(height: height > 3 ? 0.8 : 0)
            Rectangle().fill(LinearGradient(colors: [liquid, liquid.opacity(0.78)], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: inner.width, height: height)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0.6, bottomLeadingRadius: 2,
                                          bottomTrailingRadius: 2, topTrailingRadius: 0.6, style: .continuous))
        .offset(x: inner.minX, y: inner.maxY - height)
    }

    /// The printed words, as two short black bars across the front.
    private func bars(_ cup: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Capsule().fill(NotchOfficeInk.ink).frame(width: 7, height: 1.4)
                .offset(x: cup.midX - 3.5, y: cup.minY + 4.6)
            Capsule().fill(NotchOfficeInk.ink).frame(width: 5, height: 1.4)
                .offset(x: cup.midX - 2.5, y: cup.minY + 7.4)
        }
    }

    /// One pass of light across the mug: white as it starts to fill, gold
    /// as a full one earns its title.
    private func sheen(_ cup: CGRect) -> some View {
        let tone = state == .charged ? NotchOfficeInk.goldLight : .white
        return LinearGradient(colors: [.clear, tone.opacity(state == .charged ? 0.95 : 0.7), .clear],
                              startPoint: .leading, endPoint: .trailing)
            .frame(width: 6, height: cup.height * 1.6)
            .rotationEffect(.degrees(24))
            .offset(x: cup.minX + glint * (cup.width + 6) + cup.width / 2 - 3, y: cup.minY - cup.height * 0.3)
            .blendMode(.plusLighter)
            .mask(UnevenRoundedRectangle(topLeadingRadius: 1.4, bottomLeadingRadius: 3.2,
                                         bottomTrailingRadius: 3.2, topTrailingRadius: 1.4, style: .continuous)
                    .frame(width: cup.width, height: cup.height)
                    .offset(x: cup.minX, y: cup.minY)
                    .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading))
    }

    /// A short stream of coffee from above the mug into it.
    private func pour(_ inner: CGRect) -> some View {
        let surface = inner.maxY - inner.height * fill
        let top = surface * pourOut
        let length = max(0, (surface - top) * pourIn)
        return Capsule()
            .fill(liquid)
            .frame(width: 1.6, height: length)
            .offset(x: inner.midX + 1.2, y: top)
    }

    /// The last drop, leaving the brim of a tipped mug.
    private func lastDrop(_ cup: CGRect) -> some View {
        Circle()
            .fill(NotchOfficeInk.beet)
            .frame(width: 2.2, height: 2.2)
            // From the brim of the tipped mug, down past its foot.
            .offset(x: cup.minX - 6, y: cup.minY + 1.5 + drop * 11)
            .opacity(dropShown ? 0.9 : 0)
    }

    @MainActor private func play() async {
        if let edition { await playEdition(edition); return }
        var reset = Transaction(animation: nil)
        reset.disablesAnimations = true
        withTransaction(reset) {
            fill = reduceMotion || !brews ? settled : state == .charged ? max(0, settled - 0.1) : max(0, settled - 0.28)
            pourIn = 0; pourOut = 0; hop = 0; tilt = 0; drop = 0; dropShown = false; glint = -1
            steamShown = brews || state == .onBattery
        }
        guard !reduceMotion else {
            if state == .onBattery { steamShown = false }
            return
        }
        func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        await pause(0.03)
        switch state {
        case .pluggedIn, .charging:
            withAnimation(.easeOut(duration: 0.16)) { pourIn = 1 }
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.0).delay(0.12)) { fill = settled }
            withAnimation(.easeInOut(duration: 0.8).delay(0.35)) { glint = 1 }
            await pause(0.62)
            withAnimation(.easeIn(duration: 0.2)) { pourOut = 1 }
        case .charged:
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)) { fill = settled }
            withAnimation(.easeInOut(duration: 0.95).delay(0.2)) { glint = 1 }
        case .onBattery:
            // The steam stops as the mug is set down.
            withAnimation(.easeOut(duration: 0.5)) { steamShown = false }
            withAnimation(.easeOut(duration: 0.14)) { hop = -3 }
            await pause(0.14)
            withAnimation(NotchSongMotion.spring) { hop = 0 }
        case .low:
            withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: 0.35)) { tilt = -22 }
            await pause(0.3)
            dropShown = true
            withAnimation(.easeIn(duration: 0.45)) { drop = 1 }
            withAnimation(.easeOut(duration: 0.2).delay(0.35)) { dropShown = false }
            await pause(0.3)
            withAnimation(.easeInOut(duration: 0.08)) { tilt = -12 }
            await pause(0.08)
            withAnimation(.easeInOut(duration: 0.08)) { tilt = -22 }
            await pause(0.08)
            withAnimation(NotchSongMotion.spring) { tilt = 0 }
        }
    }

    /// The edition's one move each way. On, the steam puff (drawn by
    /// NotchOfficeSteamPuff on the same trigger) is the move, and the cup
    /// stands full and still. Off, the empty mug is set down from a short
    /// lift on the song's spring. Reduce Motion and Low Power Mode show it
    /// settled.
    @MainActor private func playEdition(_ on: Bool) async {
        var reset = Transaction(animation: nil)
        reset.disablesAnimations = true
        let calm = reduceMotion || lowPower.isOn
        withTransaction(reset) {
            fill = settled
            pourIn = 0; pourOut = 0; tilt = 0; drop = 0; dropShown = false; glint = -1; steamShown = false
            hop = on || calm ? 0 : -3
        }
        guard !on, !calm else { return }
        try? await Task.sleep(nanoseconds: 30_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(NotchSongMotion.spring) { hop = 0 }
    }
}
