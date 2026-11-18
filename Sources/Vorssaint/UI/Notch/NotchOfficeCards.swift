// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The connect card's Office upgrade: a boombox rises under the device's
/// icon, which punches in where its tape deck would be, and its two cones
/// pump the sound-wave rings out in turn, left and right, as the card's
/// rings did from the icon. Its colours are the moment's. Every move plays
/// once and settles; Reduce Motion keeps the fades.
struct NotchOfficeBoombox: View {
    let symbol: String
    let colors: [Color]
    let trigger: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    static let size = CGSize(width: 112, height: 72)
    /// The body and its carrying handle, centred on the drawing's middle; the
    /// volume notice's mini boombox scales the same geometry down.
    static let body = CGSize(width: 106, height: 46)
    static let bodyY: CGFloat = 7
    static let bodyCorner: CGFloat = 9
    static let handle = CGSize(width: 54, height: 20)
    static let handleY: CGFloat = -20
    static let handleCorner: CGFloat = 6
    /// From the top of the handle to the foot of the body.
    static var outline: CGSize {
        CGSize(width: body.width, height: (bodyY + body.height / 2) - (handleY - handle.height / 2))
    }
    static let coneOffset: CGFloat = 34
    static let coneSide: CGFloat = 28
    /// Where the cones, the deck and the rings sit, below the handle.
    static let deckY: CGFloat = 10
    /// When each cone's first ring leaves; the second pair follows 1.3 s later.
    private static let firstBeat = (left: 0.12, right: 0.34)

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [colors[0].opacity(0.42), colors[1].opacity(0.12), .clear],
                                     center: .center, startRadius: 2, endRadius: 62))
                .frame(width: 124, height: 124)
                .offset(y: Self.deckY)
                .scaleEffect(arrived ? 1 : 0.4)
                .opacity(arrived ? 1 : 0)
                .animation(reduceMotion ? NotchSongMotion.reduced : NotchSongMotion.glow, value: arrived)
            boombox
            .offset(y: arrived || reduceMotion ? 0 : 22)
            .opacity(arrived ? 1 : 0)
            .animation(reduceMotion ? NotchSongMotion.reduced : NotchSongMotion.spring, value: arrived)
            deck
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
        .task(id: trigger) {
            var reset = Transaction(animation: nil)
            reset.disablesAnimations = true
            withTransaction(reset) { arrived = false }
            try? await Task.sleep(nanoseconds: 16_000_000)
            arrived = true
        }
    }

    /// Two rings from each cone, a beat apart and alternating sides, twice
    /// over. Only their spread takes the ripple's delay: they rise with the
    /// boombox itself, not a beat behind it.
    private var rings: some View {
        ForEach(0..<4, id: \.self) { ring in
            Circle()
                .strokeBorder(colors[ring % colors.count].opacity(0.8), lineWidth: 1.5)
                .frame(width: Self.coneSide, height: Self.coneSide)
                .animation(NotchSongMotion.ripple(1.1).delay(Self.firstBeat.left + Double(ring) * 0.22)
                            .repeatCount(2, autoreverses: false)) { content in
                    content
                        .scaleEffect(arrived ? 2.7 : 1)
                        .opacity(arrived ? 0 : 0.85)
                }
                .offset(x: ring % 2 == 0 ? -Self.coneOffset : Self.coneOffset, y: Self.deckY)
        }
    }

    private var boombox: some View {
        ZStack {
            // The carrying handle, mostly behind the body.
            RoundedRectangle(cornerRadius: Self.handleCorner, style: .continuous)
                .stroke(Color(white: 0.34), lineWidth: 3)
                .frame(width: Self.handle.width, height: Self.handle.height)
                .offset(y: Self.handleY)
            RoundedRectangle(cornerRadius: Self.bodyCorner, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.21), NotchOfficeInk.boombox],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.bodyCorner, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
                }
                .frame(width: Self.body.width, height: Self.body.height)
                .offset(y: Self.bodyY)
            // The top panel and its buttons.
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { button in
                    RoundedRectangle(cornerRadius: 1).fill(button == 1 ? colors[0] : Color(white: 0.42))
                        .frame(width: 6, height: 2.5)
                }
            }
            .offset(x: -26, y: -11)
            Capsule().fill(Color(white: 0.12)).frame(width: 22, height: 2.5).offset(x: 30, y: -11)
            if !reduceMotion { rings }
            cone(left: true)
            cone(left: false)
        }
    }

    private func cone(left: Bool) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.08))
            Circle().strokeBorder(AngularGradient(colors: colors + [colors[0]], center: .center), lineWidth: 2)
            Circle()
                .fill(RadialGradient(colors: [colors[0].opacity(0.95), colors[1].opacity(0.55), Color(white: 0.09)],
                                     center: .center, startRadius: 1, endRadius: 10))
                .padding(4.5)
            Circle().fill(colors[0]).frame(width: 7, height: 7)
                .overlay(alignment: .topLeading) {
                    Circle().fill(.white.opacity(0.55)).frame(width: 2.4, height: 2.4).offset(x: 1.2, y: 1.2)
                }
        }
        .frame(width: Self.coneSide, height: Self.coneSide)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: reduceMotion ? false : arrived) { content, pump in
            content.scaleEffect(pump)
        } keyframes: { _ in
            // A push as each of its rings leaves, then a rest until the next pair.
            KeyframeTrack {
                LinearKeyframe(1, duration: left ? Self.firstBeat.left : Self.firstBeat.right)
                CubicKeyframe(1.16, duration: 0.07)
                CubicKeyframe(1, duration: 0.15)
                LinearKeyframe(1, duration: 0.22)
                CubicKeyframe(1.16, duration: 0.07)
                CubicKeyframe(1, duration: 0.15)
                LinearKeyframe(1, duration: 0.64)
                CubicKeyframe(1.16, duration: 0.07)
                CubicKeyframe(1, duration: 0.15)
                LinearKeyframe(1, duration: 0.22)
                CubicKeyframe(1.16, duration: 0.07)
                CubicKeyframe(1, duration: 0.15)
            }
        }
        .offset(x: left ? -Self.coneOffset : Self.coneOffset, y: Self.deckY)
    }

    /// The device itself, where the tape would play.
    private var deck: some View {
        ZStack {
            Circle().fill(Color(white: 0.06))
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolEffect(.bounce, options: .nonRepeating, value: arrived && !reduceMotion)
        }
        .frame(width: 30, height: 30)
        .scaleEffect(arrived || reduceMotion ? 1 : 0.3)
        .opacity(arrived ? 1 : 0)
        .animation(reduceMotion ? NotchSongMotion.reduced : NotchSongMotion.spring.delay(0.08), value: arrived)
        .offset(y: Self.deckY)
    }
}

/// What the connect card says beside the boombox: the device's name large,
/// "Connected" under it, and the lower third.
struct NotchOfficeConnectText: View {
    let notice: NotchNotice
    let trigger: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(notice.detail)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(notice.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            if let caption = notice.office?.caption {
                NotchLowerThird(caption: caption, size: .card, trigger: trigger, delay: 0.4)
                    .padding(.top, 4)
            }
        }
        .notchPunchIn(trigger, delay: 0.1)
    }
}

/// A call ringing or a meeting starting, opened out of the island: the
/// talking head's room, its blinds behind, the real information large and
/// the lower third under it. Clicking it acts as clicking the notice.
struct NotchOfficeCard: View {
    let notice: NotchNotice

    var body: some View {
        Group {
            if notice.office?.kind == .meeting {
                NotchOfficeMeetingCard(notice: notice)
            } else {
                NotchOfficeCallCard(notice: notice, content: notice.notification ?? NotchNotificationContent(
                    app: "", title: notice.title, subtitle: "", body: notice.detail))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Unclipped: the glow and rings fade into the island's margins, and
        // the island's own silhouette is the edge.
        .background { NotchBlinds() }
    }
}

/// "Conference room. Now." The caller large, with the desk phone ringing
/// beside them in the moment's colours and the app it rings in on its corner.
struct NotchOfficeCallCard: View {
    let notice: NotchNotice
    let content: NotchNotificationContent

    private var detail: String {
        [content.subtitle, content.body].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        let colors = NotchOfficeInk.colors()
        let key = "call|\(notice.notificationID?.uuidString ?? content.compactTitle)"
        HStack(spacing: 16) {
            ZStack {
                NotchOfficeRing(colors: colors, symbol: "phone.fill", side: 44, glyphSize: 17)
                    .frame(width: 84, height: 84)
                // The app it rings in, when its icon is known.
                if NotchNotificationService.shared.icon(for: content.app) != nil {
                    NotchNotificationAppIcon(app: content.app, size: 18)
                        .offset(x: 17, y: 17)
                }
            }
            .frame(width: 64, height: 64)
            .notchPunchIn(key)
            VStack(alignment: .leading, spacing: 3) {
                // A long name shrinks rather than losing its end.
                Text(content.compactTitle)
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }
                if let caption = notice.office?.caption {
                    NotchLowerThird(caption: caption, size: .card, trigger: key, delay: 0.35)
                        .padding(.top, 4)
                }
            }
            .notchPunchIn(key, delay: 0.06)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityText)
    }
}

/// "Conference room. Now." The meeting that just began: its title large,
/// its hours and room under it, a badge in its calendar's colour.
struct NotchOfficeMeetingCard: View {
    let notice: NotchNotice
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let accent = notice.office?.accent?.color ?? NotchOfficeInk.colors()[0]
        let key = "meeting|\(notice.title)|\(notice.detail)"
        let detail = [FeatureStrings.notchCalendar(l10n.language).ongoing, notice.detail, notice.office?.place ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.45), .clear], center: .center,
                                         startRadius: 2, endRadius: 36))
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                    .overlay { Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1) }
                    .frame(width: 44, height: 44)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
            .frame(width: 64, height: 64)
            .notchPunchIn(key)
            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                if let caption = notice.office?.caption {
                    NotchLowerThird(caption: caption, size: .card, trigger: key, delay: 0.35)
                        .padding(.top, 4)
                }
            }
            .notchPunchIn(key, delay: 0.06)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([notice.title, detail].joined(separator: ", "))
    }
}
