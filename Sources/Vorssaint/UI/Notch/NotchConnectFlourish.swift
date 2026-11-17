// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The moment headphones or a speaker join: sound-wave rings pulse out from
/// the device's icon as from a speaker cone, the icon springs in, and one
/// sweep of light crosses the strip. It wears the island's colours: the loaded
/// song's palette, else the companion's. Reduce Motion keeps a plain fade.
enum NotchConnectFlourish {
    /// Whether a notice is an audio device connecting, as opposed to a mouse,
    /// a keyboard, or a battery warning.
    static func applies(to notice: NotchNotice) -> Bool {
        guard notice.event == .accessory, notice.level == nil else { return false }
        let symbol = notice.symbol.lowercased()
        return ["airpods", "headphones", "beats", "earbuds", "hifispeaker", "homepod", "speaker", "airplay"]
            .contains { symbol.contains($0) }
    }

    /// The island's colours for the flourish, never fewer than two.
    static func colors() -> [Color] {
        let paint = NotchLevelPaint.volume() ?? [.white, Color(white: 0.75)]
        return paint.count > 1 ? paint : paint + paint
    }

    /// The opened island's card below the camera's row.
    static let cardHeight: CGFloat = 112

    // A device announced by one path (Bluetooth, or the sound's route) is not
    // announced again by the other a moment later.
    private static var announced: [String: Date] = [:]

    static func noteAnnounced(_ name: String) {
        announced = announced.filter { $0.value.timeIntervalSinceNow > -30 }
        announced[name.lowercased()] = Date()
    }

    static func wasAnnounced(_ name: String, within seconds: TimeInterval = 8) -> Bool {
        guard let when = announced[name.lowercased()] else { return false }
        return -when.timeIntervalSinceNow < seconds
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
        let colors = NotchConnectFlourish.colors()
        let key = "\(notice.title)|\(notice.detail)|\(notice.symbol)"
        ZStack {
            // The glow the sound comes out of, breathing once as it arrives.
            RadialGradient(colors: [colors[0].opacity(0.42), colors[1].opacity(0.12), .clear],
                           center: .center, startRadius: 4, endRadius: 120)
                .scaleEffect(arrived ? 1 : 0.4)
                .opacity(arrived ? 1 : 0)
                .animation(.easeOut(duration: 0.8), value: arrived)
            if !reduceMotion {
                ForEach(0..<4, id: \.self) { ring in
                    Circle()
                        .strokeBorder(colors[ring % colors.count].opacity(0.9), lineWidth: 2)
                        .frame(width: 46, height: 46)
                        .scaleEffect(arrived ? 4.2 : 0.7)
                        .opacity(arrived ? 0 : 0.85)
                        .animation(.easeOut(duration: 1.3).delay(0.15 + Double(ring) * 0.22).repeatCount(2, autoreverses: false),
                                   value: arrived)
                }
            }
            HStack(spacing: 16) {
                Image(systemName: notice.symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 54, height: 54)
                    .scaleEffect(arrived || reduceMotion ? 1 : 0.3)
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.55),
                               value: arrived)
                    .symbolEffect(.bounce, options: .nonRepeating, value: arrived && !reduceMotion)
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
                .animation(.easeOut(duration: 0.45).delay(reduceMotion ? 0 : 0.12), value: arrived)
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
                        .animation(.easeOut(duration: 1.0).delay(0.12 + Double(ring) * 0.18).repeatCount(2, autoreverses: false),
                                   value: arrived)
                }
            }
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .scaleEffect(arrived || reduceMotion ? 1 : 0.35)
                .opacity(arrived || reduceMotion ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.55),
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

/// The device's name, arriving out of a soft blur just behind its icon.
struct NotchConnectTitle: ViewModifier {
    let trigger: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    func body(content: Content) -> some View {
        let shown = arrived
        content
            .offset(x: shown || reduceMotion ? 0 : 10)
            .blur(radius: shown || reduceMotion ? 0 : 5)
            .opacity(shown ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(reduceMotion ? 0 : 0.1), value: arrived)
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
                .animation(.easeInOut(duration: 0.95).delay(0.15), value: crossed)
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
    /// The connect title's arrival, on connect notices only; every other
    /// notice's title is left exactly as it was.
    @ViewBuilder func notchConnectTitle(_ trigger: String?) -> some View {
        if let trigger {
            modifier(NotchConnectTitle(trigger: trigger)).id(trigger)
        } else {
            self
        }
    }
}
