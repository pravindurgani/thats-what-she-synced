// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// The island's backdrop while it wears the song (see NotchSongMode): the
/// song's own colours, sized to the island's box and cut to its live outline,
/// so it opens and closes with the island. It sits beside the glass in the main
/// island's window background, under the page; mirror windows never draw it.
struct NotchMusicBackdrop: View {
    @ObservedObject var presentation: NotchBackdropPresentation
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var mood: NotchMusicMood = .neutral
    /// The last cover's palette, held while the colour fades out after the
    /// song, or its cover, goes away, so it leaves with a fade, not a cut.
    @State private var heldPalette: NotchArtworkPalette?

    /// One aurora for every place the island wears the song. It stays while a
    /// song is loaded and fades in and out as the island moves between them,
    /// so no page change, opening or closing cuts it; hidden, it does nothing.
    var body: some View {
        let box = presentation.contour.boundingRect.integral
        let live = music.playback == nil ? nil : NotchArtworkPalette.song(music.artwork)
        let page = live != nil && NotchSongMode.wearsSong(notch, music)
        let announcing = live != nil && !page && NotchSongMode.announcesSong(notch)
        let glowing = live != nil && !page && !announcing && NotchSongMode.glowsClosed(notch, music)
        let strip = announcing || glowing
        Group {
            if !box.isNull, box.width > 0, box.height > 0, let palette = live ?? heldPalette {
                aurora(palette: palette, box: box, page: page, strip: strip, glowing: glowing)
            }
        }
        // Text and the companion take the same colours while it is worn.
        .onChange(of: page || strip ? live : nil, initial: true) { _, worn in NotchSongPaint.shared.wear(worn) }
        .onChange(of: live, initial: true) { _, palette in if let palette { heldPalette = palette } }
        .task(id: live == nil) {
            // Gone for good: the fade has run, so the held colours can go too.
            guard live == nil, heldPalette != nil else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            if !Task.isCancelled { heldPalette = nil }
        }
        .onDisappear { NotchSongPaint.shared.wear(nil) }
    }

    @ViewBuilder private func aurora(palette: NotchArtworkPalette, box: CGRect, page: Bool, strip: Bool,
                                     glowing: Bool) -> some View {
        let track = music.playback?.track
        let genreKey = (page || strip) && track != nil
            ? [track?.title, track?.artist, track?.album, track?.appBundleIdentifier]
                .map { $0 ?? "" }.joined(separator: "\u{1F}") : ""
        NotchMusicAurora(palette: palette, isPlaying: music.playback?.isPlaying == true, mood: mood,
                             veil: NotchSongMode.veil(page: page, notch: notch, increasedContrast: contrast == .increased),
                             // Always in view, the closed island glows and swells
                             // with the beat but never flares.
                             quiet: glowing,
                             shown: page || strip)
                // Black only around the camera, fading out sideways and down,
                // so the notch melts into the island and the colour reaches
                // all the way into its top corners. The strip is the camera's
                // own row, so it keeps its colour; no notch, no ink.
                .overlay(alignment: .top) {
                    if notch.geometry.isNotched {
                        NotchCameraInk(camera: CGSize(width: notch.geometry.cameraWidth,
                                                      height: notch.geometry.cameraHeight))
                            .animation(NotchSongMotion.fade) { $0.opacity(strip ? 0 : 1) }
                    }
                }
                .frame(width: box.width, height: box.height)
                .mask(NotchBackdropShape(contour: presentation.contour.offsetBy(dx: -box.minX, dy: -box.minY)))
                .padding(EdgeInsets(top: box.minY, leading: box.minX, bottom: 0, trailing: 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Only the showing and hiding ease; the shape follows the island
                // frame by frame. Its own ground keeps it whole over glass, so it
                // needs no part of the glass's fade.
                .animation(NotchSongMotion.fade) { $0.opacity(page || strip ? 1 : 0) }
                // The genre is read only for a song the island shows.
                .task(id: genreKey) {
                    guard !genreKey.isEmpty, let track else { return }
                    let next = await NotchMusicGenre.mood(for: track)
                    // A reply that arrives after the song changed belongs to the old song.
                    guard !Task.isCancelled else { return }
                    mood = next
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
    }
}

/// What the island lends its words and its companion while it wears the song:
/// the cover's palette, or nil. Set by the backdrop; read by the island's root
/// text style and the companion. Main thread only.
final class NotchSongPaint: ObservableObject {
    static let shared = NotchSongPaint()
    @Published private(set) var palette: NotchArtworkPalette?
    private init() {}

    func wear(_ next: NotchArtworkPalette?) {
        if next != palette { palette = next }
    }

    var text: NotchSongText? { palette.map(NotchSongText.init) }

    var companion: NotchMascotPaint? { palette.map(Self.companion(for:)) }

    static func companion(for palette: NotchArtworkPalette) -> NotchMascotPaint {
        NotchMascotPaint(light: NotchMascotColor(palette.companionLight), shade: NotchMascotColor(palette.companionShade))
    }
}

extension NotchSongText {
    init(_ palette: NotchArtworkPalette) {
        self.init(primary: Color(nsColor: palette.textPrimary),
                  secondary: Color(nsColor: palette.textSecondary),
                  tertiary: Color(nsColor: palette.textTertiary))
    }
}

private extension NotchMascotColor {
    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}

/// How strongly the aurora is veiled for what sits over it.
enum NotchAuroraVeil {
    /// `vivid` is every other page by default: the colour well up and the
    /// island's text in the song's own tints, primary far above AA. Coloured
    /// status text and thin graphics can fall below AA and 3:1 there.
    /// `page` is the same pages under Increase Contrast, where all of it keeps AA.
    case open, calm, vivid, page

    /// The colour's strength under the veil.
    var strength: Float {
        switch self {
        case .open: return 1
        case .calm: return 0.55
        case .vivid: return 0.7
        // Measured on the busiest pages: their grey and orange text keeps
        // 4.5:1 and their larger bold status text 3:1 over the colour.
        case .page: return 0.45
        }
    }

    /// The veil's stops, from the bottom up: darker under the controls and
    /// the head row, lighter in the middle where the colour shows.
    var stops: [CGFloat] {
        switch self {
        case .open: return [0.26, 0.12, 0.22]
        case .calm: return [0.49, 0.23, 0.42]
        case .vivid: return [0.42, 0.18, 0.36]
        case .page: return [0.49, 0.26, 0.42]
        }
    }

    /// How far a beat may thin the veil, as a share of itself.
    var thinnest: Double {
        switch self {
        case .page: return 0.92
        case .vivid: return 0.86
        default: return 0.8
        }
    }

    /// How far a new song's bloom lifts the veil.
    var bloomDepth: Double {
        switch self {
        case .open: return 0.5
        case .calm: return 0.7
        case .vivid: return 0.65
        case .page: return 0.8
        }
    }
}

/// A soft pool of black around the camera: solid behind the housing, then
/// fading out sideways and downward, so the island's colour wraps around the
/// notch instead of stopping at a flat black band.
private struct NotchCameraInk: View {
    let camera: CGSize
    /// How far the black fades out beyond the camera, sideways and down.
    private static let reach: CGFloat = 84
    private static let depth: CGFloat = 38
    /// Smoothstep from solid to clear, so the pool's edge has no line or corner.
    private static let falloff: [(at: CGFloat, ink: Double)] = [(0, 1), (0.25, 0.84), (0.5, 0.5), (0.75, 0.16), (1, 0)]

    var body: some View {
        let width = camera.width + Self.reach * 2
        let height = camera.height + Self.depth
        let solid = camera.height / height
        let side = Self.reach / width
        LinearGradient(stops: Self.falloff.map {
                           .init(color: .black.opacity($0.ink), location: solid + (1 - solid) * $0.at)
                       },
                       startPoint: .top, endPoint: .bottom)
            .frame(width: width, height: height)
            .mask(LinearGradient(stops: Self.falloff.reversed().map { .init(color: .black.opacity($0.ink), location: side * (1 - $0.at)) }
                                    + Self.falloff.map { .init(color: .black.opacity($0.ink), location: 1 - side * (1 - $0.at)) },
                                 startPoint: .leading, endPoint: .trailing))
            .allowsHitTesting(false)
    }
}

/// Where the island wears the song: the open music page and the sections
/// gallery, with the bubbles beside them, and the strip that names a new song.
enum NotchSongMode {
    /// On unless turned off: `defaults write <bundle id> notchSongModeEnabled -bool false`.
    /// It turns off the island's colour, glow, bubbles, text tints and the
    /// companion's; the player's own cover-tinted controls stay.
    static var enabled: Bool { NotchSongPreferences.enabled }

    /// Pages showing an image the person is judging keep their plain ground.
    private static let plainPages: Set<NotchModule> = [.camera, .captures]

    /// The open island wears the song on every page while it plays, and on
    /// the player itself while paused too, dimmed and still. The Command Bar,
    /// which resizes with every keystroke, keeps its black.
    static func wearsSong(_ notch: NotchService, _ music: NotchMusicService) -> Bool {
        guard enabled, notch.expanded, !notch.modules.isEmpty, !notch.showingCommandBar, music.playback != nil else { return false }
        if !notch.showingSections, notch.selectedMetric == nil, plainPages.contains(notch.selected) { return false }
        return music.playback?.isPlaying == true || onMusicPage(notch)
    }

    /// How strongly the colour is veiled: fullest behind the player's large
    /// white type, calmer behind lyrics and the queue, and vivid behind the
    /// other pages, or calm enough there for all their text to keep AA when
    /// the person asks macOS for more contrast.
    static func veil(page: Bool, notch: NotchService, increasedContrast: Bool) -> NotchAuroraVeil {
        // The strip's words are few and bright; under Increase Contrast it calms too.
        guard page else { return increasedContrast ? .page : .open }
        if !onMusicPage(notch) { return increasedContrast ? .page : .vivid }
        return increasedContrast || notch.musicDetailVisible ? .calm : .open
    }

    /// The closed island while it shows the playing song, a volume change
    /// over it included, so the glow does not cut out for a second.
    static func glowsClosed(_ notch: NotchService, _ music: NotchMusicService) -> Bool {
        guard enabled, music.playback?.isPlaying == true, !notch.expanded, !notch.noticeExpanded else { return false }
        if notch.compactMusicIsVisible { return true }
        return notch.notice?.event == .volume && notch.compactActivity == .music
            && notch.captureControls == nil && !notch.dragPlaceholder && !notch.peeking && !notch.fullscreenCompact
    }

    static func onMusicPage(_ notch: NotchService) -> Bool {
        notch.selected == .music && notch.selectedMetric == nil && !notch.showingSections && !notch.showingAppPanel
    }

    /// The strip naming a new song, only where it is actually on screen.
    static func announcesSong(_ notch: NotchService) -> Bool {
        enabled && !notch.expanded && !notch.noticeExpanded && notch.notice?.event == .track
            && notch.captureControls == nil && !notch.dragPlaceholder && !notch.peeking && !notch.fullscreenCompact
    }
}

/// The song's own colours, drifting and answering the music.
///
/// Three soft pools of the cover's palette move and breathe on unequal loops,
/// so the light never visibly repeats. The music steers them: its energy lifts
/// the veil and swells the light on the beat, its kicks bloom bursts of colour,
/// and its average energy, with the genre's character, sets how fast the
/// light drifts. The output volume scales all of it, from a calm glow when
/// quiet to the full show when loud. A song change cross-fades to the new
/// cover with a brief bloom; a pause settles and dims it.
///
/// The motion is Core Animation, run by the render server; the app nudges a
/// few layer values up to twenty times a second while a song plays and the
/// island shows, and does nothing at all otherwise.
struct NotchMusicAurora: View {
    let palette: NotchArtworkPalette
    let isPlaying: Bool
    var mood: NotchMusicMood = .neutral
    var veil: NotchAuroraVeil = .open
    /// No bursts and no lifting of the veil: for the closed island, always in view.
    var quiet = false
    /// Hidden, it holds still and stops listening; it stays only so it can return without a cut.
    var shown = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NotchMusicAuroraBridge(colors: palette.glow, energy: palette.energy, playing: isPlaying, moves: !reduceMotion,
                               mood: mood, veil: veil, quiet: quiet, shown: shown)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct NotchMusicAuroraBridge: NSViewRepresentable {
    let colors: [NSColor]
    let energy: Double
    let playing: Bool
    let moves: Bool
    let mood: NotchMusicMood
    let veil: NotchAuroraVeil
    let quiet: Bool
    let shown: Bool

    func makeNSView(context: Context) -> NotchMusicAuroraView { NotchMusicAuroraView() }

    func updateNSView(_ view: NotchMusicAuroraView, context: Context) {
        view.apply(colors: colors, energy: energy, playing: playing, moves: moves, mood: mood, veil: veil, quiet: quiet,
                   shown: shown)
    }

    static func dismantleNSView(_ view: NotchMusicAuroraView, coordinator: ()) { view.teardown() }
}

final class NotchMusicAuroraView: NSView {
    private static let settle = NotchSongMotion.settleCurve
    private static let entrance: CFTimeInterval = 0.55
    private static let colorChange = NotchSongMotion.colorChange
    private static let pauseChange: CFTimeInterval = 0.7
    /// How bright the backdrop stands while paused, against 1 while playing.
    private static let pausedOpacity: Float = 0.5

    /// Where each pool rests, as a fraction of the island, and its loops: how
    /// long one drift around its rest takes, and one breath in and out.
    /// The side of the pools' proportional space, in points before scaling.
    private static let unit: CGFloat = 240

    private static let pools: [(rest: CGPoint, drift: CFTimeInterval, breath: CFTimeInterval)] = [
        (CGPoint(x: 0.16, y: 0.56), 11, 6),
        (CGPoint(x: 0.58, y: 0.26), 14, 8),
        (CGPoint(x: 0.88, y: 0.60), 17, 9),
    ]

    // Layers. The canvas carries the entrance and pause dimming, apart from
    // the view's own layer, which AppKit owns. The stage runs in real time and
    // carries the beat's swell, the colour cross-fade and the bursts; only the
    // clock beneath it pauses, and it holds nothing but the pools' drift.
    private let canvas = CALayer()
    private let ground = CALayer()
    private let stage = CALayer()
    private let base = CAGradientLayer()
    private let lift = CALayer()
    private let clock = CALayer()
    private var blobs: [CAGradientLayer] = []
    private var bursts: [CAGradientLayer] = []
    private let scrim = CAGradientLayer()

    private var colors: [NSColor] = []
    private var playing = false
    private var moves = true
    private var mood: NotchMusicMood = .neutral
    private var veil: NotchAuroraVeil = .open
    /// The cover's liveliness (see NotchArtworkPalette.energy).
    private var coverEnergy: Double = 0.5
    private var quiet = false
    private var shown = true
    /// The cover changed while hidden: its colours bloom when it next shows.
    private var unseenSong = false
    private var entered = false
    private var motionInstalled = false
    private var occlusionObserver: NSObjectProtocol?

    // Listening: a quick envelope for the beat, a slow one for the song's
    // drive, the output volume, and the drift speed they set.
    private var levelsSubscription: AnyCancellable?
    private var volumeSubscription: AnyCancellable?
    private var drive: Double = 0
    private var loudness: Double = 0.6
    private var rate: Float = 1
    private var ticks = 0
    private var nextBurst = 0
    private var bloomUntil: CFTimeInterval = 0
    private var appliedBounce: Double = 0
    private var reinstall: DispatchWorkItem?
    private var lastKick: CFTimeInterval = 0
    private var previousLevels: [Double] = []
    private var fluxAverage: Double = 0
    private var bounce: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // A layer-hosting view: the layer is set before wantsLayer, so AppKit
        // leaves its sublayers alone and their geometry stays bottom-left
        // origin, which the gradients below are written for.
        layer = CALayer()
        wantsLayer = true
        setAccessibilityElement(false)
        layer?.masksToBounds = true
        canvas.opacity = 0
        layer?.addSublayer(canvas)

        // A deep ground under the colour. Over Liquid Glass the colour would
        // otherwise mix with whatever sits behind the island; on this ground
        // the cover's palette glows the same over any wallpaper or window.
        ground.backgroundColor = NSColor(srgbRed: 0.035, green: 0.035, blue: 0.05, alpha: 0.94).cgColor
        canvas.addSublayer(ground)

        base.type = .axial
        base.startPoint = CGPoint(x: 0, y: 1)
        base.endPoint = CGPoint(x: 1, y: 0)
        stage.addSublayer(base)
        for pool in Self.pools {
            let blob = Self.pool()
            blob.bounds = CGRect(x: 0, y: 0, width: Self.unit * 0.78, height: Self.unit * 1.7)
            blob.position = CGPoint(x: Self.unit * pool.rest.x, y: Self.unit * pool.rest.y)
            clock.addSublayer(blob)
            blobs.append(blob)
        }
        lift.addSublayer(clock)
        for _ in 0..<3 {
            let burst = Self.pool()
            burst.opacity = 0
            lift.addSublayer(burst)
            bursts.append(burst)
        }
        stage.addSublayer(lift)
        canvas.addSublayer(stage)

        // A dark veil over the colour, its strength set by what sits over it
        // (see NotchAuroraVeil): the player's text keeps WCAG AA on any cover.
        scrim.type = .axial
        scrim.startPoint = CGPoint(x: 0.5, y: 1)
        scrim.endPoint = CGPoint(x: 0.5, y: 0)
        scrim.locations = [0, 0.55, 1]
        canvas.addSublayer(scrim)
        paintVeil()
    }

    private static func pool() -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
        return layer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    // MARK: State

    func apply(colors newColors: [NSColor], energy newEnergy: Double, playing newPlaying: Bool, moves newMoves: Bool,
               mood newMood: NotchMusicMood, veil newVeil: NotchAuroraVeil, quiet newQuiet: Bool,
               shown newShown: Bool) {
        quiet = newQuiet
        if abs(newEnergy - coverEnergy) > 0.01 {
            coverEnergy = newEnergy
            retime(towards: targetRate(), immediately: true)
        }
        let colorsChanged = newColors.map(\.cgColor) != colors.map(\.cgColor)
        let firstColors = colors.isEmpty
        colors = newColors
        if colorsChanged {
            paint(animated: !firstColors && shown)
            if !firstColors { if shown { bloom() } else { unseenSong = true } }
        }
        if newShown != shown {
            shown = newShown
            if shown {
                // A song that arrived while hidden blooms as it is first seen.
                if unseenSong { bloom() }
                unseenSong = false
                // The drift is made afresh once the island settles, from rest
                // at the size it will run at, so the pools never jump.
                scheduleMotion()
            } else {
                settleResponse()
                reinstall?.cancel(); reinstall = nil
                for blob in blobs {
                    blob.removeAnimation(forKey: "drift")
                    blob.removeAnimation(forKey: "breath")
                }
                motionInstalled = false
            }
            syncClock()
        }
        if newVeil != veil {
            veil = newVeil
            paintVeil(animated: true)
            if entered { updatePlayback() }
        }
        if newMood != mood {
            mood = newMood
            retime(towards: targetRate(), immediately: true)
        }
        if newMoves != moves {
            moves = newMoves
            installMotion()
            if !moves { settleResponse() }
        }
        if newPlaying != playing || !entered {
            if !entered { rate = targetRate() }
            playing = newPlaying
            updatePlayback()
            if !playing { settleResponse() }
        }
    }

    func teardown() {
        reinstall?.cancel(); reinstall = nil
        levelsSubscription = nil
        volumeSubscription = nil
        clock.sublayers?.forEach { $0.removeAllAnimations() }
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
    }

    /// The pools take the cover's colours: the lead colour largest and
    /// strongest, the others as accents. A new cover cross-fades over the old
    /// on the stage, which runs in real time, so it works while the drift is
    /// paused and under Reduce Motion alike.
    private func paint(animated: Bool) {
        guard !colors.isEmpty else { return }
        let lead = colors[0], second = colors[min(1, colors.count - 1)], third = colors[min(2, colors.count - 1)]
        let poolColors = [lead, second, third]
        let poolStrength: [CGFloat] = [0.96, 0.88, 0.84]
        // A new cross-fade replaces one under way. On the settle curve the
        // old one is nearly done within a few frames, so what it skips is small;
        // leaving it running would show the new colours at its own progress.
        if animated {
            let crossFade = CATransition()
            crossFade.type = .fade
            crossFade.duration = Self.colorChange
            crossFade.timingFunction = Self.settle
            stage.add(crossFade, forKey: "colors")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        base.colors = [lead.withAlphaComponent(0.55).cgColor,
                       second.withAlphaComponent(0.42).cgColor,
                       third.withAlphaComponent(0.50).cgColor]
        for (index, blob) in blobs.enumerated() {
            blob.colors = [poolColors[index].withAlphaComponent(poolStrength[index]).cgColor,
                           poolColors[index].withAlphaComponent(0).cgColor]
        }
        CATransaction.commit()
    }

    /// The veil's strength: lighter in the middle where the colour shows,
    /// darker under the head row and the controls; heavier for Increase
    /// Contrast and behind lyrics or the queue.
    private func paintVeil(animated: Bool = false) {
        let stops = veil.stops
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        // On the same timing as the colour's strength, which changes with it.
        CATransaction.setAnimationDuration(Self.pauseChange)
        CATransaction.setAnimationTimingFunction(Self.settle)
        scrim.colors = stops.map { NSColor.black.withAlphaComponent($0).cgColor }
        CATransaction.commit()
    }

    /// A new song's arrival: the veil lifts for a moment so the new colours
    /// flare across the island, then settles. Opacity only, so it stays under
    /// Reduce Motion as the one cue that the song changed.
    private func bloom() {
        let flare = CAKeyframeAnimation(keyPath: "opacity")
        // From wherever the veil stands, so a bloom over a bloom never jumps.
        let from = Double(scrim.presentation()?.opacity ?? scrim.opacity)
        flare.values = [from, veil.bloomDepth, 1]
        flare.keyTimes = [0, 0.22, 1]
        flare.timingFunctions = [CAMediaTimingFunction(name: .easeOut), Self.settle]
        flare.duration = 1.25
        scrim.add(flare, forKey: "bloom")
        bloomUntil = CACurrentMediaTime() + flare.duration
    }

    /// Playing: full strength and moving. Paused: dimmer and still, held where
    /// it stood rather than snapping back.
    private func updatePlayback() {
        // The veil's level sets the colour's strength for what sits over it
        // (see NotchAuroraVeil). Only the colour dims: the dark ground stays
        // whole, so the island never turns see-through over glass.
        let target: Float = (playing ? 1 : Self.pausedOpacity) * veil.strength
        fadeOpacity(of: stage, to: target, duration: entered ? Self.pauseChange : Self.entrance)
        if !entered { fadeOpacity(of: canvas, to: 1, duration: Self.entrance) }
        entered = true
        syncClock()
    }

    private func fadeOpacity(of layer: CALayer, to target: Float, duration: CFTimeInterval) {
        let from = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = target
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = target
        animation.duration = duration
        animation.timingFunction = Self.settle
        layer.add(animation, forKey: "opacity")
    }

    // MARK: Clock

    /// Whether the drift's clock is running. Every change of its speed is
    /// re-anchored where it stands, so the pools never jump.
    private var running: Bool { clock.speed != 0 }

    private func stageTime() -> CFTimeInterval { stage.convertTime(CACurrentMediaTime(), from: nil) }

    /// The drift runs only while a song plays, the island shows, and motion
    /// is welcome. Stopping it freezes the pools in their current pose.
    private func syncClock() {
        let visible = shown && (window.map { $0.occlusionState.contains(.visible) } ?? false)
        let run = playing && visible && moves
        if run, running, clock.speed != rate {
            let local = clock.convertTime(CACurrentMediaTime(), from: nil)
            clock.timeOffset = local
            clock.beginTime = stageTime()
            clock.speed = rate
        } else if run, !running {
            clock.beginTime = stageTime()
            clock.speed = rate
        } else if !run, running {
            let local = clock.convertTime(CACurrentMediaTime(), from: nil)
            clock.speed = 0
            clock.timeOffset = local
        }
        listen(playing && visible && moves)
    }

    /// Changes the drift speed without a jump in the pools' positions.
    private func retime(towards target: Float, immediately: Bool) {
        let next = immediately ? target : rate + (target - rate) * 0.5
        guard abs(next - rate) > 0.02 else { return }
        rate = next
        guard running else { return }
        let local = clock.convertTime(CACurrentMediaTime(), from: nil)
        clock.timeOffset = local
        clock.beginTime = stageTime()
        clock.speed = rate
    }

    private func targetRate() -> Float {
        // The genre sets the character; the song's drive, the volume and the
        // cover's liveliness lean it.
        let lean = Float((0.75 + 0.6 * min(1, drive)) * (0.85 + 0.3 * loudness) * (0.85 + 0.3 * coverEnergy))
        return min(2.2, max(0.45, mood.rate * lean))
    }

    /// How high the light stands in the island: the volume sets its level,
    /// as a meter's, and each beat bounces it up from there.
    private func riseHeight(beat push: Double) -> CGFloat {
        let height = bounds.height
        guard height > 1, moves else { return 0 }
        let level = (loudness - 0.5) * 0.22
        return height * CGFloat(level + 0.2 * min(1, push))
    }

    /// How much the volume lets the music move the light: a calm glow when
    /// quiet or muted, a little past the designed strength when loud.
    private var intensity: Double { 0.35 + 0.9 * loudness }

    // MARK: Listening

    private func listen(_ on: Bool) {
        guard on else { levelsSubscription = nil; volumeSubscription = nil; return }
        if levelsSubscription == nil {
            levelsSubscription = NotchAudioLevelService.shared.$levels
                .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] levels in self?.hear(levels) }
        }
        if volumeSubscription == nil {
            let mixer = AppVolumeMixer.shared
            volumeSubscription = mixer.$systemOutputVolume.combineLatest(mixer.$systemOutputMuted)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] volume, muted in
                    guard let self else { return }
                    self.loudness = muted == true ? 0 : min(1, max(0, volume ?? 0.6))
                    self.retime(towards: self.targetRate(), immediately: true)
                    // A volume change moves the light at once, beats or not.
                    CATransaction.begin()
                    CATransaction.setAnimationDuration(0.5)
                    CATransaction.setAnimationTimingFunction(Self.settle)
                    self.lift.transform = CATransform3DMakeTranslation(0, self.riseHeight(beat: 0), 0)
                    CATransaction.commit()
                }
        }
    }

    private func hear(_ levels: [Double]?) {
        guard playing, moves else { return }
        // The reader stopped (silence, or the live equalizer turned off): the
        // light settles instead of holding the last beat.
        guard let bands = levels, !bands.isEmpty else {
            if bounce > 0 || !previousLevels.isEmpty { previousLevels = []; settleResponse() }
            return
        }
        let energy = Self.energy(bands, bassWeight: mood.bassWeight)
        drive += (energy - drive) * 0.03

        // Onsets, not loudness: how much the bands jumped since the last
        // reading (spectral flux), led by the low end, against its own recent
        // average. A song that is loud all the way through still has its kicks.
        var flux = 0.0
        if bands.count == previousLevels.count, !bands.isEmpty {
            let lowBands = max(1, bands.count / 3)
            for index in bands.indices {
                let rise = max(0, bands[index] - previousLevels[index])
                flux += rise * (index < lowBands ? mood.bassWeight : 1)
            }
            flux /= Double(bands.count)
        }
        previousLevels = bands
        let now = CACurrentMediaTime()
        // At least 0.4 s apart, and none during a song change's bloom: under
        // three flashes in any second, the limit for flashing content.
        let onset = flux > fluxAverage * 1.5 + 0.012 && now - lastKick > 0.4 && now > bloomUntil
        fluxAverage += (flux - fluxAverage) * 0.08
        if onset {
            lastKick = now
            // A lively cover hits a little harder, a muted one a little softer.
            bounce = max(bounce, min(1, min(1, 0.45 + flux * 6) * mood.response * intensity * (0.8 + 0.4 * coverEnergy)))
            if mood != .calm, !quiet { kick(strength: bounce) }
        } else {
            // A quick fall after each hit, so the light jumps on the beat and
            // drops between beats, as a meter's needle does.
            bounce *= 0.72
        }

        // Nothing to move between beats once the light is at rest.
        let resting = bounce < 0.01 && appliedBounce < 0.01
        if resting { bounce = 0 } else { appliedBounce = bounce }
        if !resting {
            NotchMusicPulse.shared.beat.send(bounce)
            CATransaction.begin()
            CATransaction.setAnimationDuration(onset ? 0.06 : 0.09)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            // The veil never thins below its level's share, so text keeps its contrast at the loudest beat.
            scrim.opacity = quiet ? 1 : Float(1 - min(1 - veil.thinnest, bounce * 0.55))
            let swell = 1 + 0.07 * bounce
            stage.transform = CATransform3DMakeScale(swell, swell, 1)
            lift.transform = CATransform3DMakeTranslation(0, riseHeight(beat: bounce), 0)
            CATransaction.commit()
        }
        if resting { appliedBounce = 0 }

        ticks += 1
        // The drift's speed follows the song's drive, gently, every two seconds.
        if ticks % 40 == 0 { retime(towards: targetRate(), immediately: false) }
    }

    /// A soft burst of one of the cover's colours, blooming from where its
    /// pool rests and fading in under half a second. Below the veil, so text
    /// keeps its contrast through it.
    private func kick(strength: Double) {
        let size = bounds.size
        guard !colors.isEmpty, strength > 0.05, size.width > 1, size.height > 1 else { return }
        let burst = bursts[nextBurst]
        let pool = Self.pools[nextBurst % Self.pools.count]
        let color = colors[nextBurst % colors.count]
        nextBurst = (nextBurst + 1) % bursts.count
        let side = max(size.width, size.height) * 0.9
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        burst.bounds = CGRect(x: 0, y: 0, width: side, height: side * 0.7)
        burst.position = CGPoint(x: size.width * pool.rest.x, y: size.height * pool.rest.y)
        burst.colors = [color.withAlphaComponent(0.85).cgColor, color.withAlphaComponent(0).cgColor]
        CATransaction.commit()
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.45
        grow.toValue = 1.25
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, Float(min(0.85, 0.35 + 0.5 * strength)), 0]
        fade.keyTimes = [0, 0.18, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.45
        group.timingFunction = Self.settle
        burst.add(group, forKey: "kick")
    }

    /// The light's rest pose, eased back to when the music stops answering.
    /// The stage runs in real time, so this settles even with the drift paused.
    private func settleResponse() {
        bounce = 0
        appliedBounce = 0
        NotchMusicPulse.shared.beat.send(0)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        CATransaction.setAnimationTimingFunction(Self.settle)
        scrim.opacity = 1
        stage.transform = CATransform3DIdentity
        lift.transform = CATransform3DMakeTranslation(0, riseHeight(beat: 0), 0)
        CATransaction.commit()
    }

    /// One reading of how loud the music is now, from 0 to 1, with the low
    /// bands counted more for music led by them.
    static func energy(_ levels: [Double]?, bassWeight: Double) -> Double {
        guard let levels, !levels.isEmpty else { return 0 }
        let lowBands = max(1, levels.count / 3)
        var sum = 0.0, weights = 0.0
        for (index, level) in levels.enumerated() {
            let weight = index < lowBands ? bassWeight : 1
            sum += min(1, max(0, level.isFinite ? level : 0)) * weight
            weights += weight
        }
        return weights > 0 ? sum / weights : 0
    }

    // MARK: Motion

    /// Adds the pools' drift and breath, from rest, once the island settles
    /// after it first shows, and when Reduce Motion changes. A resize only
    /// stretches it (see layout), so it is never re-made mid-flight.
    private func installMotion() {
        let size = bounds.size
        for blob in blobs {
            blob.removeAnimation(forKey: "drift")
            blob.removeAnimation(forKey: "breath")
        }
        motionInstalled = false
        guard moves, shown, window != nil, size.width > 1, size.height > 1 else { syncClock(); return }
        motionInstalled = true
        // In the clock's proportional space (see layout), so the island
        // resizing stretches the drift with it rather than re-making it.
        let unit = Self.unit
        let reachX = unit * 0.14, reachY = unit * 0.26
        let now = clock.convertTime(CACurrentMediaTime(), from: nil)
        for (index, blob) in blobs.enumerated() {
            let pool = Self.pools[index]
            // A slow loop round the rest point; each pool turns the other way
            // to its neighbour, so the light swirls rather than slides.
            let turn: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let loop: [CGSize] = [
                CGSize(width: 0, height: 0),
                CGSize(width: reachX * turn, height: -reachY * 0.6),
                CGSize(width: reachX * 0.4 * turn, height: reachY),
                CGSize(width: -reachX * turn, height: reachY * 0.3),
                CGSize(width: 0, height: 0),
            ]
            let drift = CAKeyframeAnimation(keyPath: "transform.translation")
            drift.values = loop.map { NSValue(size: $0) }
            // Paced, so the loop keeps one speed through its seam.
            drift.calculationMode = .cubicPaced
            drift.duration = pool.drift
            drift.repeatCount = .infinity
            drift.beginTime = now
            blob.add(drift, forKey: "drift")

            let breath = CABasicAnimation(keyPath: "transform.scale")
            breath.fromValue = 0.86
            breath.toValue = 1.2
            breath.duration = pool.breath
            breath.autoreverses = true
            breath.repeatCount = .infinity
            breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // Each pool starts part-way into its breath, so they never pulse together.
            breath.timeOffset = pool.breath * Double(index) / 3
            breath.beginTime = now
            blob.add(breath, forKey: "breath")
        }
        syncClock()
    }

    // MARK: Layout and visibility

    override func layout() {
        super.layout()
        let size = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.frame = bounds
        ground.frame = canvas.bounds
        stage.bounds = CGRect(origin: .zero, size: size)
        stage.position = CGPoint(x: size.width / 2, y: size.height / 2)
        base.frame = stage.bounds
        lift.bounds = stage.bounds
        lift.position = CGPoint(x: size.width / 2, y: size.height / 2)
        // The pools rest, breathe and drift in a square of proportional space,
        // scaled to the island: the strip, the open island and lyrics
        // unfolding all stretch the same motion, which never jumps or restarts.
        let unit = Self.unit
        clock.bounds = CGRect(x: 0, y: 0, width: unit, height: unit)
        clock.position = CGPoint(x: size.width / 2, y: size.height / 2)
        clock.transform = CATransform3DMakeScale(max(size.width, 1) / unit, max(size.height, 1) / unit, 1)
        scrim.frame = canvas.bounds
        // The light's resting height follows the island's height as it resizes.
        lift.transform = CATransform3DMakeTranslation(0, riseHeight(beat: bounce), 0)
        CATransaction.commit()
        // Hidden, the island's resizes need no drift. Shown, it is made once,
        // when the island first settles, from rest.
        guard shown, !motionInstalled else { return }
        scheduleMotion()
    }

    private func scheduleMotion() {
        reinstall?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.installMotion() }
        reinstall = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        guard let window else {
            levelsSubscription = nil
            volumeSubscription = nil
            blobs.forEach { $0.removeAllAnimations() }
            motionInstalled = false
            reinstall?.cancel(); reinstall = nil
            return
        }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in self?.syncClock() }
        scheduleMotion()
    }
}

// MARK: - The beat, shared

/// The island's beat, as its aurora reads it, for the quick-access bubbles
/// beside the island to pulse with. Main thread only. Views subscribe from
/// their layers, not from SwiftUI, so a beat redraws nothing.
final class NotchMusicPulse {
    static let shared = NotchMusicPulse()
    let beat = PassthroughSubject<Double, Never>()
    private init() {}
}

// MARK: - The quick-access bubbles

/// A quick-access bubble's ground while the music page shows: the same cover
/// colours as the island's aurora, turning slowly, with the island's beat.
struct NotchAuroraBubble: View {
    let colors: [NSColor]
    let playing: Bool
    /// Where in the turn this bubble starts, so neighbours never spin in step.
    let phase: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NotchAuroraBubbleBridge(colors: colors, playing: playing, moves: !reduceMotion, phase: phase)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct NotchAuroraBubbleBridge: NSViewRepresentable {
    let colors: [NSColor]
    let playing: Bool
    let moves: Bool
    let phase: Double

    func makeNSView(context: Context) -> NotchAuroraBubbleView { NotchAuroraBubbleView(phase: phase) }

    func updateNSView(_ view: NotchAuroraBubbleView, context: Context) {
        view.apply(colors: colors, playing: playing, moves: moves)
    }

    static func dismantleNSView(_ view: NotchAuroraBubbleView, coordinator: ()) { view.teardown() }
}

/// The bubble's colour turns like a record while the song plays and holds
/// where it stood when paused; on the island's beat it swells and its veil
/// thins, never below what keeps the white glyph at 3:1.
final class NotchAuroraBubbleView: NSView {
    private static let turn: CFTimeInterval = 14
    private static let settle = NotchSongMotion.settleCurve
    private let canvas = CALayer()
    private let swirl = CAGradientLayer()
    private let shine = CAGradientLayer()
    private let veil = CALayer()
    private let phase: Double
    private var colors: [NSColor] = []
    private var playing = false
    private var moves = true
    private var configured = false
    private var beatSubscription: AnyCancellable?
    private var occlusionObserver: NSObjectProtocol?

    init(phase: Double) {
        self.phase = phase
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        setAccessibilityElement(false)
        layer?.masksToBounds = true
        layer?.addSublayer(canvas)
        // A wheel of the cover's colours, as the island's pools are.
        swirl.type = .conic
        swirl.startPoint = CGPoint(x: 0.5, y: 0.5)
        swirl.endPoint = CGPoint(x: 0.5, y: 0)
        canvas.addSublayer(swirl)
        // Light from above, as on the island.
        shine.type = .radial
        shine.startPoint = CGPoint(x: 0.5, y: 0.9)
        shine.endPoint = CGPoint(x: 1.15, y: 1.5)
        shine.colors = [NSColor.white.withAlphaComponent(0.14).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        canvas.addSublayer(shine)
        veil.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
        canvas.addSublayer(veil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    func apply(colors newColors: [NSColor], playing newPlaying: Bool, moves newMoves: Bool) {
        if newColors.map(\.cgColor) != colors.map(\.cgColor) {
            // A new cover cross-fades as the island's does.
            if !colors.isEmpty {
                let crossFade = CATransition()
                crossFade.type = .fade
                crossFade.duration = NotchSongMotion.colorChange
                crossFade.timingFunction = Self.settle
                canvas.add(crossFade, forKey: "colors")
            }
            colors = newColors
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let ring = newColors.isEmpty ? [NSColor.black, .black] : newColors + [newColors[0]]
            swirl.colors = ring.map(\.cgColor)
            CATransaction.commit()
        }
        guard !configured || newMoves != moves || newPlaying != playing else { return }
        configured = true
        moves = newMoves
        playing = newPlaying
        sync()
    }

    func teardown() {
        beatSubscription = nil
        swirl.removeAllAnimations()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
    }

    private func sync() {
        // A withdrawn bubble is hidden, not removed: it rests too.
        let visible = !isHiddenOrHasHiddenAncestor && (window.map { $0.occlusionState.contains(.visible) } ?? false)
        let run = playing && moves && visible
        if moves, window != nil, swirl.animation(forKey: "turn") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = -2 * Double.pi * phase
            spin.toValue = -2 * Double.pi * (phase + 1)
            spin.duration = Self.turn
            spin.repeatCount = .infinity
            swirl.speed = 0
            swirl.timeOffset = 0
            swirl.add(spin, forKey: "turn")
        } else if !moves {
            swirl.removeAnimation(forKey: "turn")
        }
        // Re-anchored where it stands, so the turn never jumps.
        if run, swirl.speed == 0 {
            swirl.beginTime = canvas.convertTime(CACurrentMediaTime(), from: nil)
            swirl.speed = 1
        } else if !run, swirl.speed != 0 {
            let local = swirl.convertTime(CACurrentMediaTime(), from: nil)
            swirl.speed = 0
            swirl.timeOffset = local
        }
        if run, beatSubscription == nil {
            beatSubscription = NotchMusicPulse.shared.beat.sink { [weak self] bounce in self?.pulse(bounce) }
        } else if !run, beatSubscription != nil {
            beatSubscription = nil
            pulse(0)
        }
    }

    private func pulse(_ bounce: Double) {
        let push = min(1, max(0, bounce))
        CATransaction.begin()
        CATransaction.setAnimationDuration(push > 0.05 ? 0.08 : NotchSongMotion.beatReturn)
        CATransaction.setAnimationTimingFunction(push > 0.05 ? CAMediaTimingFunction(name: .easeOut) : Self.settle)
        let swell = 1 + 0.12 * push
        canvas.sublayerTransform = CATransform3DMakeScale(swell, swell, 1)
        veil.opacity = Float(1 - 0.35 * push)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.frame = bounds
        // Wider than the circle, so its corners never show as it turns or swells.
        let side = max(bounds.width, bounds.height) * 1.5
        swirl.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        swirl.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shine.frame = canvas.bounds
        veil.frame = canvas.bounds.insetBy(dx: -bounds.width * 0.1, dy: -bounds.height * 0.1)
        CATransaction.commit()
    }

    override func viewDidHide() {
        super.viewDidHide()
        sync()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        sync()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        guard let window else { beatSubscription = nil; return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in self?.sync() }
        sync()
    }
}

