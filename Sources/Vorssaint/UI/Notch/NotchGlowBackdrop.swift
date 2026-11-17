// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Low Power Mode as it stands, for the glows and rings that rest in it.
/// Main thread only.
final class NotchLowPowerMode: ObservableObject {
    static let shared = NotchLowPowerMode()
    @Published private(set) var isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil,
                                                          queue: .main) { [weak self] _ in
            let on = ProcessInfo.processInfo.isLowPowerModeEnabled
            if self?.isOn != on { self?.isOn = on }
        }
    }
}

/// The companion's colours as the island wears them with no song: a palette
/// grown from its body (NotchIslandGlow.idleSeeds), toned as a cover's is, so
/// it stands as vivid as the music look. Read through the island's own look,
/// so whatever the companion wears, the glow follows. Main thread only.
enum NotchIdlePalette {
    private static var held: (paint: NotchMascotPaint, palette: NotchArtworkPalette)?

    static func current() -> NotchArtworkPalette {
        let paint = NotchMascotSupport.islandLook().paint
        if let held, held.paint == paint { return held.palette }
        func rgb(_ color: NotchMascotColor) -> NotchRGB {
            NotchRGB(red: Double(color.red), green: Double(color.green), blue: Double(color.blue))
        }
        let palette = NotchIslandGlow.idleSeeds(light: rgb(paint.light), shade: rgb(paint.shade))
            .map { NotchArtworkPalette(pure: $0.map(\.nsColor)) } ?? NotchArtworkPalette.coverless()
        held = (paint, palette)
        return palette
    }
}

/// The words' tints while the open island wears the companion's colours,
/// toned from them as a song's are (NotchSongText): opaque tints keep their
/// contrast over colour where white at a fixed opacity would mix with it.
/// Kept apart from NotchSongPaint, which also dresses the companion and sets
/// it bopping: the companion keeps its own colours and stays still.
/// Main thread only.
final class NotchIdlePaint: ObservableObject {
    static let shared = NotchIdlePaint()
    @Published private(set) var text: NotchSongText?
    private init() {}

    func wear(_ palette: NotchArtworkPalette?) {
        let next = palette.map(NotchSongText.init)
        if next != text { text = next }
    }
}

extension NotchSongMode {
    /// The companion's colours in the island while no song wears it (see
    /// NotchIslandGlow): on unless turned off with
    /// `defaults write <bundle id> notchIdleGlowEnabled -bool false`, then
    /// relaunch (a change from another process is read on the next launch).
    /// Low Power Mode turns it off as well.
    static var idleGlowEnabled: Bool { NotchIdleGlowPreferences.enabled }

    /// The closed island showing the agents' strip, where it is on screen.
    static func showsAgentStrip(_ notch: NotchService) -> Bool {
        notch.compactActivity == .agents && closedStripShows(notch) && !notch.showsCompactActivityPicker
    }

    /// The companion resting beside the camera with nothing else in the closed island.
    static func companionRests(_ notch: NotchService) -> Bool {
        notch.mascotAtRest && notch.compactActivity == nil && closedStripShows(notch)
            && !notch.geometry.floats && notch.geometry.restingWingWidth > 0
            && notch.departingMusic == nil && notch.lingeringMusic == nil
    }

    private static func closedStripShows(_ notch: NotchService) -> Bool {
        !notch.expanded && !notch.peeking && notch.notice == nil && !notch.dragPlaceholder
            && notch.captureControls == nil && !notch.fullscreenCompact
    }
}

/// The island's ground in colour when no song wears it: the working agents'
/// colours split across their wings, and the companion's colours around it
/// at rest and behind the open pages. One glow at a time, by the precedence
/// in NotchIslandGlow; it sits under the song's backdrop, which takes over
/// whenever a song is worn. Mirror windows never draw it.
struct NotchGlowBackdrop: View {
    @ObservedObject var presentation: NotchBackdropPresentation
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var finishes = NotchAgentFinishes.shared
    @ObservedObject private var lowPower = NotchLowPowerMode.shared
    @Environment(\.colorSchemeContrast) private var contrast
    /// Each glow's colours, held while it fades out, so it leaves with a fade, not a cut.
    @State private var heldWings: NotchWingGlowColors?
    @State private var heldIdle: NotchArtworkPalette?

    var body: some View {
        let box = presentation.contour.boundingRect.integral
        let idleAllowed = NotchIslandGlow.idleAllowed(enabled: NotchSongMode.idleGlowEnabled, lowPower: lowPower.isOn)
        let playing = music.playback?.isPlaying == true
        let closed = NotchIslandGlow.closed(
            agentStrip: NotchSongMode.showsAgentStrip(notch),
            songGlows: playing && (NotchSongMode.announcesSong(notch) || NotchSongMode.glowsClosed(notch, music)),
            companionRests: NotchSongMode.companionRests(notch), idleAllowed: idleAllowed)
        let open = notch.expanded
            ? NotchIslandGlow.open(wearsSong: NotchSongMode.wearsSong(notch, music),
                                   plainPage: notch.showingCommandBar || NotchSongMode.showsPlainPage(notch),
                                   companionOn: notch.mascotOn, idleAllowed: idleAllowed)
            : .none
        let wings = wingColors(for: closed)
        let idle = open == .idle ? NotchIdlePalette.current() : nil
        ZStack {
            if !box.isNull, box.width > 0, box.height > 0 {
                if let shown = wings ?? heldWings {
                    fitted(NotchWingGlow(colors: shown, camera: notch.geometry.floats ? 0 : notch.geometry.cameraWidth,
                                         veil: contrast == .increased ? .page : .open),
                           box: box)
                        .animation(NotchSongMotion.fade) { $0.opacity(wings == nil ? 0 : 1) }
                }
                if let palette = idle ?? heldIdle {
                    fitted(NotchMusicAurora(palette: palette, isPlaying: true,
                                            veil: NotchSongMode.veil(page: true, notch: notch,
                                                                     increasedContrast: contrast == .increased),
                                            quiet: true, shown: idle != nil, still: true)
                            .overlay(alignment: .top) {
                                if notch.geometry.isNotched {
                                    NotchCameraInk(camera: CGSize(width: notch.geometry.cameraWidth,
                                                                  height: notch.geometry.cameraHeight))
                                }
                            },
                           box: box)
                        .animation(NotchSongMotion.fade) { $0.opacity(idle == nil ? 0 : 1) }
                }
            }
        }
        .onChange(of: wings, initial: true) { _, next in if let next { heldWings = next } }
        .onChange(of: idle, initial: true) { _, next in
            if let next { heldIdle = next }
            // Words take the companion's tints while its colours are worn.
            NotchIdlePaint.shared.wear(next)
        }
        // Gone for good: the fade has run, so the held colours can go too.
        .task(id: wings == nil) {
            guard wings == nil, heldWings != nil else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            if !Task.isCancelled { heldWings = nil }
        }
        .task(id: idle == nil) {
            guard idle == nil, heldIdle != nil else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            if !Task.isCancelled { heldIdle = nil }
        }
        .onDisappear { NotchIdlePaint.shared.wear(nil) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The glow sized to the island's box and cut to its live outline, so it
    /// opens and closes with the island, as the song's backdrop is.
    private func fitted<Content: View>(_ content: Content, box: CGRect) -> some View {
        content
            .frame(width: box.width, height: box.height)
            .mask(NotchBackdropShape(contour: presentation.contour.offsetBy(dx: -box.minX, dy: -box.minY)))
            .padding(EdgeInsets(top: box.minY, leading: box.minX, bottom: 0, trailing: 0))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Each side's colours: the agents' own while their strip shows, one
    /// agent's on both sides; the companion's at rest, its lead colour on
    /// the side it rests on.
    private func wingColors(for glow: NotchIslandGlow) -> NotchWingGlowColors? {
        switch glow {
        case .agents:
            guard let sides = NotchAgentWings.glowSides(finishes.model(live: usage.snapshot.live).wings) else { return nil }
            return NotchWingGlowColors(left: sides.left.wingGlow, right: sides.right.wingGlow, fadesEdges: false)
        case .idle:
            let glow = NotchIslandGlow.restingGlow(NotchIdlePalette.current().pure.map(NotchRGB.init))
            guard glow.count >= 3 else { return nil }
            let near = [glow[0], glow[2], glow[1]], far = [glow[1], glow[2], glow[0]]
            let left = notch.mascotSide == .left
            return NotchWingGlowColors(left: left ? near : far, right: left ? far : near, fadesEdges: true)
        case .song, .none:
            return nil
        }
    }
}

private extension NotchRGB {
    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        self.init(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
    }
}

/// The closed island's static glow, one set of colours each side of the
/// camera (NotchWingGlowView). Decoration only: no clicks, no VoiceOver.
struct NotchWingGlow: View {
    let colors: NotchWingGlowColors
    let camera: CGFloat
    let veil: NotchAuroraVeil

    var body: some View {
        NotchWingGlowBridge(colors: colors, camera: camera, veil: veil)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct NotchWingGlowBridge: NSViewRepresentable {
    let colors: NotchWingGlowColors
    let camera: CGFloat
    let veil: NotchAuroraVeil

    func makeNSView(context: Context) -> NotchWingGlowView { NotchWingGlowView() }

    func updateNSView(_ view: NotchWingGlowView, context: Context) {
        view.apply(colors: colors, camera: camera, veil: veil)
    }
}

