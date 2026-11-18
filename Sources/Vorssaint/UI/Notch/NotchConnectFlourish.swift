// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The moment headphones or a speaker join: sound-wave rings pulse out from
/// the device's icon as from a speaker cone, the icon springs in, and one
/// sweep of light crosses the island. It wears the island's colours: the
/// loaded song's palette, else the companion's. Reduce Motion keeps a fade.
extension NotchConnectFlourish {
    /// The island's colours for the flourish, never fewer than two.
    static func colors() -> [Color] {
        let paint = NotchLevelPaint.volume() ?? [.white, Color(white: 0.75)]
        return paint.count > 1 ? paint : paint + paint
    }

}

/// The opened island when headphones or a speaker join: the device's icon
/// large in the cover's colours over a soft glow, sound-wave rings rippling out
/// across the island, its name and "Connected" arriving out of a blur, and one
/// sweep of colour. It closes by itself as a notice does.
struct NotchConnectCard: View {
    let notice: NotchNotice
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        if notice.office != nil { office } else { plain }
    }

    /// With the Office moments on: the boombox, and the name as a lower third.
    private var office: some View {
        let colors = NotchOfficeInk.colors()
        let key = "\(notice.title)|\(notice.detail)|\(notice.symbol)"
        return ZStack {
            HStack(spacing: 14) {
                NotchOfficeBoombox(symbol: notice.symbol, colors: colors, trigger: key)
                NotchOfficeConnectText(notice: notice, trigger: key)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            // The sweep fades out at every edge, so it crosses the open
            // island as light rather than as a band with edges.
            NotchConnectSweep(colors: colors, trigger: key)
                .clipped()
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.3),
                                             .init(color: .white, location: 0.7), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.15),
                                             .init(color: .white, location: 0.85), .init(color: .clear, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
        }
        // Unclipped: the glow and rings fade into the island's margins.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityText)
    }

    private var plain: some View {
        let colors = NotchConnectFlourish.colors()
        let key = "\(notice.title)|\(notice.detail)|\(notice.symbol)"
        return ZStack {
            HStack(spacing: 16) {
                // The sound comes out of the device: its glow and rings
                // spread from the icon, under the words beside it.
                ZStack {
                    // A soft disc that is clear at its own edge, so it never
                    // shows a frame as it grows.
                    Circle()
                        .fill(RadialGradient(colors: [colors[0].opacity(0.45), colors[1].opacity(0.14), .clear],
                                             center: .center, startRadius: 2, endRadius: 52))
                        .frame(width: 104, height: 104)
                        .scaleEffect(arrived ? 1 : 0.4)
                        .opacity(arrived ? 1 : 0)
                        .animation(reduceMotion ? NotchSongMotion.reduced : NotchSongMotion.glow, value: arrived)
                    if !reduceMotion {
                        ForEach(0..<4, id: \.self) { ring in
                            Circle()
                                .strokeBorder(colors[ring % colors.count].opacity(0.7), lineWidth: 1.5)
                                .frame(width: 46, height: 46)
                                .scaleEffect(arrived ? 3.4 : 0.7)
                                .opacity(arrived ? 0 : 0.8)
                                .animation(NotchSongMotion.ripple(1.3).delay(0.12 + Double(ring) * 0.22)
                                            .repeatCount(2, autoreverses: false), value: arrived)
                        }
                    }
                    Image(systemName: notice.symbol)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .scaleEffect(arrived || reduceMotion ? 1 : 0.3)
                        .animation(reduceMotion ? NotchSongMotion.reduced : NotchSongMotion.spring, value: arrived)
                        .symbolEffect(.bounce, options: .nonRepeating, value: arrived && !reduceMotion)
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.detail)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(notice.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .offset(x: arrived || reduceMotion ? 0 : 14)
                .blur(radius: arrived || reduceMotion ? 0 : 6)
                .opacity(arrived ? 1 : 0)
                .animation(reduceMotion ? NotchSongMotion.reduced : NotchSongMotion.arrive.delay(0.12), value: arrived)
            }
            .foregroundStyle(.white)
            NotchConnectSweep(colors: colors, trigger: key)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityText)
        .task(id: key) {
            var reset = Transaction(animation: nil)
            reset.disablesAnimations = true
            withTransaction(reset) { arrived = false }
            try? await Task.sleep(nanoseconds: 16_000_000)
            arrived = true
        }
    }
}

/// The device's icon with its sound-wave rings.
struct NotchConnectIcon: View {
    let symbol: String
    let colors: [Color]
    /// Changes once per connection, so a second device in a row plays again.
    let trigger: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .strokeBorder(colors[ring % colors.count], lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                        .scaleEffect(arrived ? 2.2 : 0.55)
                        .opacity(arrived ? 0 : 0.9)
                        // Each ring leaves a beat after the last, twice over,
                        // as sound leaves a cone.
                        .animation(NotchSongMotion.ripple(1.0).delay(0.12 + Double(ring) * 0.18).repeatCount(2, autoreverses: false),
                                   value: arrived)
                }
            }
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .scaleEffect(arrived || reduceMotion ? 1 : 0.35)
                .opacity(arrived || reduceMotion ? 1 : 0)
                .animation(reduceMotion ? NotchSongMotion.reduced : NotchSongMotion.spring,
                           value: arrived)
                .symbolEffect(.bounce, options: .nonRepeating, value: arrived && !reduceMotion)
        }
        .frame(width: 18, height: 18)
        .task(id: trigger) {
            var reset = Transaction(animation: nil)
            reset.disablesAnimations = true
            withTransaction(reset) { arrived = false }
            try? await Task.sleep(nanoseconds: 16_000_000)
            arrived = true
        }
    }
}

/// Words arriving out of a soft blur just behind their icon: a device's name
/// as it connects, a new song's title and artist.
struct NotchArrival: ViewModifier {
    let trigger: String
    var delay: Double = 0.1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    func body(content: Content) -> some View {
        let shown = arrived
        content
            .offset(x: shown || reduceMotion ? 0 : 10)
            .blur(radius: shown || reduceMotion ? 0 : 5)
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? NotchSongMotion.reduced : NotchSongMotion.arrive.delay(delay), value: arrived)
            .task(id: trigger) {
                var reset = Transaction(animation: nil)
                reset.disablesAnimations = true
                withTransaction(reset) { arrived = false }
                try? await Task.sleep(nanoseconds: 16_000_000)
                arrived = true
            }
    }
}

/// One sweep of the island's colours across the strip, left to right.
struct NotchConnectSweep: View {
    let colors: [Color]
    let trigger: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var crossed = false

    var body: some View {
        GeometryReader { proxy in
            let band = proxy.size.width * 0.45
            LinearGradient(colors: [.clear] + colors.map { $0.opacity(0.45) } + [.clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: band)
                .offset(x: crossed ? proxy.size.width : -band)
                .blendMode(.plusLighter)
                .animation(NotchSongMotion.sweep.delay(0.15), value: crossed)
        }
        .opacity(reduceMotion ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: trigger) {
            var reset = Transaction(animation: nil)
            reset.disablesAnimations = true
            withTransaction(reset) { crossed = false }
            try? await Task.sleep(nanoseconds: 16_000_000)
            crossed = true
        }
    }
}

extension View {
    /// The arrival, on connect and song notices only; every other notice's
    /// words are left exactly as they were.
    @ViewBuilder func notchArrival(_ trigger: String?, delay: Double = 0.1) -> some View {
        if let trigger {
            modifier(NotchArrival(trigger: trigger, delay: delay)).id(trigger)
        } else {
            self
        }
    }
}
