// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// The island's backdrop while it wears the song (see NotchSongMode): the
/// song's own colours, laid out to the island's box and cut to its live
/// outline by the island's own silhouette, so it opens and closes with the
/// island. It sits beside the glass in the main island's window background,
/// under the page; mirror windows never draw it.
///
/// It decides what to draw and hands that to a NotchGlowStage, which alone
/// follows the island frame by frame: a song's state is read only when it
/// changes, never on every frame of a resize.
struct NotchMusicBackdrop: View {
    /// Passed on, not observed: the stage follows the outline.
    let presentation: NotchBackdropPresentation
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var music = NotchMusicService.shared
    /// A black-and-white song's colours follow the companion it borrows them
    /// from, and the text and the companion follow them (NotchSongPaint).
    @ObservedObject private var colourless = NotchColourlessCompanion.shared
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var mood: NotchMusicMood = .neutral

    /// One aurora for every place the island wears the song. It fades in and
    /// out as the island moves between them, with the island's own resize, so
    /// no page change, opening or closing cuts it; gone, it is not drawn at all.
    var body: some View {
        let live = music.playback == nil ? nil : NotchArtworkPalette.song(music.artwork)
        let page = live != nil && NotchSongMode.wearsSong(notch, music)
        let announcing = live != nil && !page && NotchSongMode.announcesSong(notch)
        let glowing = live != nil && !page && !announcing && NotchSongMode.glowsClosed(notch, music)
        let strip = announcing || glowing
        let track = music.playback?.track
        let genreKey = (page || strip) && track != nil
            ? [track?.title, track?.artist, track?.album, track?.appBundleIdentifier]
                .map { $0 ?? "" }.joined(separator: "\u{1F}") : ""
        NotchGlowStage(presentation: presentation, art: (page || strip ? live : nil).map { palette in
            .aurora(NotchAuroraArt(
                palette: palette, isPlaying: music.playback?.isPlaying == true, mood: mood,
                veil: NotchSongMode.veil(page: page, notch: notch, increasedContrast: contrast == .increased),
                // Always in view, the closed island glows and swells with
                // the beat but never flares.
                quiet: glowing,
                // Black only around the camera, fading out sideways and
                // down, so the notch melts into the island and the colour
                // reaches all the way into its top corners. The strip is the
                // camera's own row, so it keeps its colour; no notch, no ink.
                camera: notch.geometry.isNotched
                    ? CGSize(width: notch.geometry.cameraWidth, height: notch.geometry.cameraHeight) : nil,
                inkShown: !strip))
        })
        // Text and the companion take the same colours while it is worn.
        .onChange(of: page || strip ? live : nil, initial: true) { _, worn in NotchSongPaint.shared.wear(worn) }
        // The genre is read only for a song the island shows.
        .task(id: genreKey) {
            guard !genreKey.isEmpty, let track else { return }
            let next = await NotchMusicGenre.mood(for: track)
            // A reply that arrives after the song changed belongs to the old song.
            guard !Task.isCancelled else { return }
            mood = next
        }
        .onDisappear { NotchSongPaint.shared.wear(nil) }
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

/// A soft pool of black around the camera: solid behind the housing, then
/// fading out sideways and downward, so the island's colour wraps around the
/// notch instead of stopping at a flat black band. Drawn once per camera into
/// an image the aurora's own layer shows, rather than as a gradient masked by
/// another, which cost an offscreen pass on every frame.
enum NotchCameraInk {
    /// How far the black fades out beyond the camera, sideways and down.
    private static let reach: CGFloat = 84
    private static let depth: CGFloat = 38
    /// Smoothstep from solid to clear, so the pool's edge has no line or corner.
    private static let falloff: [(at: CGFloat, ink: CGFloat)] = [(0, 1), (0.25, 0.84), (0.5, 0.5), (0.75, 0.16), (1, 0)]
    /// Main thread only.
    private static var drawn: [String: CGImage] = [:]

    static func size(camera: CGSize) -> CGSize {
        CGSize(width: camera.width + reach * 2, height: camera.height + depth)
    }

    /// The pool for a camera, at a display's scale. Main thread only.
    static func image(camera: CGSize, scale: CGFloat) -> CGImage? {
        let key = "\(camera.width)x\(camera.height)@\(scale)"
        if let image = drawn[key] { return image }
        let size = size(camera: camera)
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let across = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        // Sideways: clear at the ends, solid across the camera.
        let side = reach / size.width
        let sideways = falloff.reversed().map { (location: side * (1 - $0.at), ink: $0.ink) }
            + falloff.map { (location: 1 - side * (1 - $0.at), ink: $0.ink) }
        guard let grey = CGGradient(colorSpace: CGColorSpaceCreateDeviceGray(),
                                    colorComponents: sideways.flatMap { [$0.ink, 1] },
                                    locations: sideways.map(\.location), count: sideways.count) else { return nil }
        across.drawLinearGradient(grey, start: .zero, end: CGPoint(x: width, y: 0), options: [])
        guard let mask = across.makeImage() else { return nil }
        context.clip(to: CGRect(x: 0, y: 0, width: width, height: height), mask: mask)
        // Downward: solid over the housing, then fading out below it.
        let solid = camera.height / size.height
        let down = falloff.map { (location: solid + (1 - solid) * $0.at, ink: $0.ink) }
        guard let black = CGGradient(colorSpace: sRGB, colorComponents: down.flatMap { [0, 0, 0, $0.ink] },
                                     locations: down.map(\.location), count: down.count) else { return nil }
        // The bitmap runs bottom up: the camera is its last row.
        context.drawLinearGradient(black, start: CGPoint(x: 0, y: height), end: .zero,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let image = context.makeImage()
        drawn[key] = image
        return image
    }
}

/// Where the island wears the song: the open music page and the sections
/// gallery, with the bubbles beside them, and the strip that names a new song.
enum NotchSongMode {
    /// On unless Song colours is turned off in Settings, which applies at once
    /// (NotchOfficeEditionSettings); Terminal's `defaults write` waits for a relaunch.
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
        if showsPlainPage(notch) { return false }
        return music.playback?.isPlaying == true || onMusicPage(notch)
    }

    /// A page showing an image the person is judging, which keeps its plain
    /// ground whatever the island would otherwise wear.
    static func showsPlainPage(_ notch: NotchService) -> Bool {
        !notch.showingSections && notch.selectedMetric == nil && plainPages.contains(notch.selected)
    }

    /// How strongly the colour is veiled: fullest behind the player's large
    /// white type, calmer behind lyrics and the queue, and vivid behind the
    /// other pages, or calm enough there for all their text to keep AA when
    /// the person asks macOS for more contrast.
    static func veil(page: Bool, notch: NotchService, increasedContrast: Bool) -> NotchAuroraVeil {
        // The strip's words are few and bright; under Increase Contrast it calms too.
        guard page else { return increasedContrast ? .page : .strip }
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
/// The motion is Core Animation, run by the render server. While a song
/// plays and the island shows, the app reads the music twenty times a
/// second, but sets something going only when a hit lands: the hit and its
/// whole fall, worked out at once (NotchBeatCurve), its push at 60 frames a
/// second and its fall at 30. Otherwise it does nothing at all.
struct NotchMusicAurora: View {
    let palette: NotchArtworkPalette
    let isPlaying: Bool
    var mood: NotchMusicMood = .neutral
    var veil: NotchAuroraVeil = .open
    /// No bursts and no lifting of the veil: for the closed island, always in view.
    var quiet = false
    /// Hidden, it holds still and stops listening; it stays only so it can return without a cut.
    var shown = true
    /// Settled, as Reduce Motion leaves it: no drift and no listening. The
    /// companion's colours behind the open pages, which have no song to follow.
    var still = false
    /// The camera's size, for the black pool around it (NotchCameraInk), or
    /// nil with no camera; and whether the pool shows (not in the strip,
    /// which is the camera's own row).
    var camera: CGSize? = nil
    var inkShown = true
    /// How strongly it shows (NotchGlowPresence), and whether to ease there.
    var presence: Double = 1
    var fades = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Low Power Mode settles it as Reduce Motion does: the colours stay, the drift and the beat rest.
    @ObservedObject private var lowPower = NotchLowPowerMode.shared

    var body: some View {
        NotchMusicAuroraBridge(colors: palette.glow, energy: palette.energy, playing: isPlaying,
                               moves: !reduceMotion && !still && !lowPower.isOn,
                               mood: mood, veil: veil, quiet: quiet, shown: shown, camera: camera, inkShown: inkShown,
                               presence: presence, fades: fades)
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
    let camera: CGSize?
    let inkShown: Bool
    let presence: Double
    let fades: Bool

    func makeNSView(context: Context) -> NotchMusicAuroraView { NotchMusicAuroraView() }

    func updateNSView(_ view: NotchMusicAuroraView, context: Context) {
        view.apply(colors: colors, energy: energy, playing: playing, moves: moves, mood: mood, veil: veil, quiet: quiet,
                   shown: shown, camera: camera, inkShown: inkShown, presence: presence, fades: fades)
    }

    static func dismantleNSView(_ view: NotchMusicAuroraView, coordinator: ()) { view.teardown() }
}

final class NotchMusicAuroraView: NSView {
    private static let settle = NotchSongMotion.settleCurve
    /// A beat's push and its quick fall, made once rather than on every reading.
    private static let beatCurve = CAMediaTimingFunction(name: .easeOut)
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
    // The base, the pools, the bursts and the veil are glows drawn once
    // into images (NotchGlowImage) that the layers move and fade.
    private let canvas = CALayer()
    private let ground = CALayer()
    private let stage = CALayer()
    private let base = CALayer()
    private let lift = CALayer()
    private let clock = CALayer()
    private var blobs: [CALayer] = []
    private var bursts: [CALayer] = []
    private let scrim = CALayer()
    /// The black pool around the camera, over everything, drawn once.
    private let ink = CALayer()
    private var camera: CGSize?
    private var inkShown = true
    private let presence = NotchGlowPresenceLayer()

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
    /// When, on the clock, the pools' drift was made from rest. The drift is
    /// on the pools only while it runs; held, it comes off and each pool
    /// keeps the pose it stood in, and it goes back on from this same start,
    /// so the clock's held time picks it up where it stopped.
    private var motionBegin: CFTimeInterval?
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
    private var reinstall: DispatchWorkItem?
    private var lastKick: CFTimeInterval = 0
    private var previousLevels: [Double] = []
    private var fluxAverage: Double = 0
    /// The beat's push at the last reading: a hit's, then its fall.
    private var bounce: Double = 0
    /// What each hit set going, on top of each layer's rest: the veil
    /// thinning, the swell, the light bouncing up, and the light's level
    /// easing after a volume change. Each is added to the layer's own
    /// value, which stays at rest, so a resize, the volume or a new song's
    /// bloom can change that value while a fall runs.
    private var thinning = NotchBeatTrack()
    private var swelling = NotchBeatTrack()
    private var rising = NotchBeatTrack()
    private var levelling = NotchBeatTrack()
    /// The quick part of a burst, its bloom, at 60 frames a second; it
    /// fades at 30.
    private static let burstAttack: CFTimeInterval = 0.1
    /// The share of a burst's time after which what is left plays at 15.
    private static let burstCalm: CFTimeInterval = 0.38

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
        canvas.addSublayer(scrim)
        ink.isHidden = true
        canvas.addSublayer(ink)
        paintVeil()
    }

    private static func pool() -> CALayer { CALayer() }

    /// A pool of `color`, `strength` at its middle and gone at its edge.
    private static func pool(_ color: NSColor, strength: CGFloat) -> CGImage? {
        NotchGlowImage.radial([color.withAlphaComponent(strength).cgColor, color.withAlphaComponent(0).cgColor])
    }

    /// The veil from top to bottom: its stops are for 0, 0.55 and 1 of the way down.
    private static let veilLocations: [CGFloat] = [0, 0.55, 1]

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    // MARK: State

    func apply(colors newColors: [NSColor], energy newEnergy: Double, playing newPlaying: Bool, moves newMoves: Bool,
               mood newMood: NotchMusicMood, veil newVeil: NotchAuroraVeil, quiet newQuiet: Bool,
               shown newShown: Bool, camera newCamera: CGSize? = nil, inkShown newInkShown: Bool = true,
               presence strength: Double = 1, fades: Bool = false) {
        if newQuiet, !quiet {
            // The closed island never lifts its veil: one a beat on the open
            // page thinned settles as the island closes.
            settle(&thinning, "opacity", on: scrim, at: CACurrentMediaTime())
        }
        quiet = newQuiet
        if newCamera != camera {
            camera = newCamera
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let scale = window?.backingScaleFactor ?? 2
            let image: CGImage? = newCamera.flatMap { NotchCameraInk.image(camera: $0, scale: scale) }
            ink.contents = image
            ink.contentsScale = scale
            ink.isHidden = newCamera == nil
            CATransaction.commit()
            needsLayout = true
        }
        if newInkShown != inkShown {
            inkShown = newInkShown
            // On the song's fade, as the strip takes the camera's row.
            presence.apply(newInkShown ? 1 : 0, fades: entered, to: ink)
        }
        presence.apply(strength, fades: fades, to: canvas)
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
                restPools()
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
        // Corner to corner, top left to bottom right.
        base.contents = NotchGlowImage.axial([lead.withAlphaComponent(0.55).cgColor,
                                              second.withAlphaComponent(0.42).cgColor,
                                              third.withAlphaComponent(0.50).cgColor],
                                             from: CGPoint(x: 0, y: 1), to: CGPoint(x: 1, y: 0))
        for (index, blob) in blobs.enumerated() {
            blob.contents = Self.pool(poolColors[index], strength: poolStrength[index])
        }
        CATransaction.commit()
    }

    /// The veil's strength: lighter in the middle where the colour shows,
    /// darker under the head row and the controls; heavier for Increase
    /// Contrast and behind lyrics or the queue.
    private func paintVeil(animated: Bool = false) {
        let stops = veil.stops
        let image = NotchGlowImage.axial(stops.map { NSColor.black.withAlphaComponent($0).cgColor },
                                         locations: Self.veilLocations, from: CGPoint(x: 0.5, y: 1),
                                         to: CGPoint(x: 0.5, y: 0), width: 4, height: 256)
        guard (scrim.contents as AnyObject?) !== (image as AnyObject?) else { return }
        if animated {
            // On the same timing as the colour's strength, which changes with
            // it: one veil fading into the next, as its stops easing would.
            let fade = CATransition()
            fade.type = .fade
            fade.duration = Self.pauseChange
            fade.timingFunction = Self.settle
            scrim.add(fade, forKey: "veil")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrim.contents = image
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
    /// Held, the drift comes off the pools altogether, so a paused or covered
    /// island asks the compositor for nothing.
    private func syncClock() {
        let visible = shown && !isHiddenOrHasHiddenAncestor && window?.isVisible == true
            && window?.occlusionState.contains(.visible) == true
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
            // The pose first, read while the clock still runs, then the hold.
            detachDrift()
            let local = clock.convertTime(CACurrentMediaTime(), from: nil)
            clock.speed = 0
            clock.timeOffset = local
        } else if !run {
            detachDrift()
        }
        if run { attachDrift() }
        listen(playing && visible && moves)
    }

    /// Whether the pools carry their drift now.
    var isDrifting: Bool { blobs.contains { $0.animation(forKey: "drift") != nil } }
    /// Whether anything on the aurora is set to move: its pools' drift and breath.
    var hasRunningMotion: Bool { blobs.contains { !($0.animationKeys() ?? []).isEmpty } }

    /// Puts the drift made at `motionBegin` back on the pools, on the clock's
    /// time, where it carries on from the held pose.
    private func attachDrift() {
        guard let begin = motionBegin, !isDrifting else { return }
        let unit = Self.unit
        let reachX = unit * 0.14, reachY = unit * 0.26
        CATransaction.begin()
        CATransaction.setDisableActions(true)
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
            drift.beginTime = begin
            // The pools are soft all the way out: at 15 frames a second the
            // drift steps a point or so, which no edge shows. A beat's
            // swell, at 30 and 60, shares those frames.
            drift.preferredFrameRateRange = NotchSongMotion.gentleFrames
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
            breath.beginTime = begin
            breath.preferredFrameRateRange = NotchSongMotion.gentleFrames
            blob.add(breath, forKey: "breath")
        }
        CATransaction.commit()
    }

    /// Takes the drift off the pools, each keeping the pose it stands in.
    private func detachDrift() {
        guard isDrifting else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for blob in blobs {
            blob.transform = blob.presentation()?.transform ?? blob.transform
            blob.removeAnimation(forKey: "drift")
            blob.removeAnimation(forKey: "breath")
        }
        CATransaction.commit()
    }

    /// No drift made, and every pool at its rest.
    private func restPools() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for blob in blobs {
            blob.removeAnimation(forKey: "drift")
            blob.removeAnimation(forKey: "breath")
            blob.transform = CATransform3DIdentity
        }
        CATransaction.commit()
        motionBegin = nil
        motionInstalled = false
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
    /// as a meter's, and each beat bounces it up from there (beatRise).
    private var restingRise: CGFloat {
        let height = bounds.height
        guard height > 1, moves else { return 0 }
        return height * CGFloat((loudness - 0.5) * 0.22)
    }

    /// How far a beat's full push lifts the light above its level.
    private var beatRise: Double {
        let height = bounds.height
        guard height > 1, moves else { return 0 }
        return Double(height) * 0.2
    }

    /// Puts the light at its level, eased over a settle from where it stood,
    /// or at once.
    private func level(eased: Bool, at now: CFTimeInterval) {
        let target = restingRise
        let from = lift.transform.m42 + CGFloat(levelling.value(at: now))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lift.transform = CATransform3DMakeTranslation(0, target, 0)
        CATransaction.commit()
        guard eased, abs(from - target) > 0.01 else {
            if !eased { levelling.stop(); NotchSongMotion.stop("level", on: lift) }
            return
        }
        let glide = levelling.start(NotchBeatCurve(from: Double(from - target), moves: [
            .init(target: 0, duration: NotchSongMotion.beatReturn, curve: Self.settle)]), at: now)
        NotchSongMotion.play(glide.animation("transform.translation.y", additive: true), attack: 0, on: lift,
                             key: "level", at: now)
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
                    self.level(eased: true, at: CACurrentMediaTime())
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
        // A quick fall after each hit, so the light jumps on the beat and
        // drops between beats, as a meter's needle does. The fall was set
        // going with its hit, so a reading without one only keeps count.
        let previous = bounce
        let falling = bounce * NotchBeatFall.keeps >= NotchBeatFall.rest ? bounce * NotchBeatFall.keeps : 0
        bounce = falling
        if onset {
            lastKick = now
            // A lively cover hits a little harder, a muted one a little
            // softer. A hit holds the push where it stood if it lands lower.
            let hit = max(previous, min(1, min(1, 0.45 + flux * 6) * mood.response * intensity * (0.8 + 0.4 * coverEnergy)))
            if mood != .calm, !quiet { kick(strength: hit) }
            // One that lifts the push barely above its fall changes nothing to see.
            if hit > falling + NotchBeatFall.deadBand {
                bounce = hit
                strike(previous: previous, at: now)
            }
        }

        ticks += 1
        // The drift's speed follows the song's drive, gently, every two seconds.
        if ticks % 40 == 0 { retime(towards: targetRate(), immediately: false) }
    }

    /// A hit of `bounce`: the veil thins, the colour swells and the light
    /// bounces up, and all three fall away, as one move each, worked out
    /// now for every reading until the next hit (NotchBeatCurve): each
    /// reading's ease toward the fall, a quick ease out cut short by the
    /// next, the same curve twenty animations a second drew. The hit plays
    /// at 60 frames a second and the fall at 30. Each move is added to its
    /// layer's resting value and starts from where the last stands, read
    /// from that last move rather than from the screen.
    private func strike(previous: Double, at now: CFTimeInterval) {
        let pushes = NotchBeatFall.pushes(from: bounce)
        func moves(_ value: (Double) -> Double) -> [NotchBeatCurve.Move] {
            pushes.enumerated().map { index, push in
                .init(target: value(push), duration: index == 0 ? 0.06 : 0.09, curve: Self.beatCurve)
            }
        }
        let attack = NotchBeatFall.reading
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The veil never thins below its level's share, so text keeps its
        // contrast at the loudest beat; the closed island's never thins.
        if !quiet || thinning.moves(at: now) {
            let thinnest = 1 - veil.thinnest, closed = quiet
            let thin = thinning.start(moves { closed ? 0 : -min(thinnest, $0 * 0.55) }, at: now)
            NotchSongMotion.play(thin.animation("opacity", additive: true), attack: attack,
                                 tail: thin.calm(within: stillness("opacity")), on: scrim, key: "beat", at: now)
        }
        let swell = swelling.start(moves { 0.07 * $0 }, at: now)
        NotchSongMotion.play(swell.animation("transform.scale", additive: true), attack: attack,
                             tail: swell.calm(within: stillness("transform.scale")), on: stage, key: "beat", at: now)
        let reach = beatRise
        let rise = rising.start(moves { reach * min(1, $0) }, at: now)
        NotchSongMotion.play(rise.animation("transform.translation.y", additive: true), attack: attack,
                             tail: rise.calm(within: stillness("transform.translation.y")), on: lift, key: "beat",
                             at: now)
        CATransaction.commit()
        NotchMusicPulse.shared.beat.send(NotchMusicBeat(push: bounce, previous: previous))
    }

    /// Eases what `track` set going on `layer` back to rest over the beat's
    /// return, from where it stands, at 30 frames a second, or 15 when it
    /// stands too near rest for more to show.
    private func settle(_ track: inout NotchBeatTrack, _ keyPath: String, on layer: CALayer, at now: CFTimeInterval) {
        let from = track.value(at: now)
        guard from != 0 || track.moves(at: now) else { return }
        let back = track.start([.init(target: 0, duration: NotchSongMotion.beatReturn, curve: Self.settle)], at: now)
        NotchSongMotion.play(back.animation(keyPath, additive: true), attack: 0,
                             tail: back.calm(within: stillness(keyPath)), on: layer, key: "beat", at: now)
    }

    /// How near rest a beat's move on `keyPath` stands once what is left of
    /// it moves well under a point a frame at 15 frames a second
    /// (NotchBeatFall.stillPoints): that far of travel, measured at the
    /// island's edge for the swell, or a few hundredths of the veil.
    private func stillness(_ keyPath: String) -> Double {
        switch keyPath {
        case "opacity": return NotchBeatFall.stillOpacity
        case "transform.scale": return NotchBeatFall.stillPoints / Double(max(1, max(bounds.width, bounds.height) / 2))
        default: return NotchBeatFall.stillPoints
        }
    }

    /// A soft burst of one of the cover's colours, blooming from where its
    /// pool rests and fading in under half a second. Below the veil, so text
    /// keeps its contrast through it. The bloom plays at 60 frames a second
    /// and the fade at 30.
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
        burst.contents = Self.pool(color, strength: 0.85)
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
        // On the settle curve it has gone 93 % of its way two fifths of the
        // way in: the faint rest of its fade plays at 15 frames a second.
        NotchSongMotion.play(group, attack: Self.burstAttack, tail: group.duration * Self.burstCalm, on: burst,
                             key: "kick", at: CACurrentMediaTime())
    }

    /// The light's rest pose, eased back to when the music stops answering.
    /// The stage runs in real time, so this settles even with the drift paused.
    private func settleResponse() {
        let previous = bounce
        bounce = 0
        NotchMusicPulse.shared.beat.send(.settle(from: previous))
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        settle(&thinning, "opacity", on: scrim, at: now)
        settle(&swelling, "transform.scale", on: stage, at: now)
        settle(&rising, "transform.translation.y", on: lift, at: now)
        level(eased: true, at: now)
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

    /// Makes the pools' drift and breath, from rest, once the island settles
    /// after it first shows, and when Reduce Motion or Low Power Mode changes.
    /// A resize only stretches it (see layout), so it is never re-made
    /// mid-flight. It is on the pools only while it runs (see syncClock).
    private func installMotion() {
        let size = bounds.size
        restPools()
        guard moves, shown, window != nil, size.width > 1, size.height > 1 else { syncClock(); return }
        motionInstalled = true
        // In the clock's proportional space (see layout), so the island
        // resizing stretches the drift with it rather than re-making it.
        motionBegin = clock.convertTime(CACurrentMediaTime(), from: nil)
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
        if let camera {
            // Centred at the top, where SwiftUI hung it over the colour.
            let inkSize = NotchCameraInk.size(camera: camera)
            ink.frame = CGRect(x: (size.width - inkSize.width) / 2, y: size.height - inkSize.height,
                               width: inkSize.width, height: inkSize.height)
        }
        // The light's resting height follows the island's height as it resizes.
        lift.transform = CATransform3DMakeTranslation(0, restingRise, 0)
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
            restPools()
            reinstall?.cancel(); reinstall = nil
            return
        }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in self?.syncClock() }
        scheduleMotion()
    }

    // Hidden, it holds still and stops listening, as when covered.
    override func viewDidHide() { super.viewDidHide(); syncClock() }
    override func viewDidUnhide() { super.viewDidUnhide(); syncClock() }

    /// The camera's pool is an image, drawn for the display's scale.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let camera, let scale = window?.backingScaleFactor, ink.contentsScale != scale else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ink.contents = NotchCameraInk.image(camera: camera, scale: scale)
        ink.contentsScale = scale
        CATransaction.commit()
    }
}

// MARK: - The beat, shared

/// The island's beat, as its aurora reads it, for the quick-access bubbles,
/// the companion and the dancers to move with: each hit as it lands, and
/// the beat settling (NotchMusicBeat), never the readings between. Main
/// thread only. Views subscribe from their layers, not from SwiftUI, so a
/// beat redraws nothing.
final class NotchMusicPulse {
    static let shared = NotchMusicPulse()
    let beat = PassthroughSubject<NotchMusicBeat, Never>()
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
    @ObservedObject private var lowPower = NotchLowPowerMode.shared

    var body: some View {
        NotchAuroraBubbleBridge(colors: colors, playing: playing, moves: !reduceMotion && !lowPower.isOn, phase: phase)
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
    /// Where the colour's turn stands while it is held, in radians.
    private var angle: Double
    private var colors: [NSColor] = []
    private var playing = false
    private var moves = true
    private var configured = false
    private var beatSubscription: AnyCancellable?
    private var occlusionObserver: NSObjectProtocol?

    init(phase: Double) {
        self.phase = phase
        // Where in the turn it starts, so neighbours never spin in step.
        angle = -2 * Double.pi * phase
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
        swirl.transform = CATransform3DMakeRotation(CGFloat(angle), 0, 0, 1)
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

    /// Whether the colour is turning now.
    var isTurning: Bool { swirl.animation(forKey: "turn") != nil }

    /// The turn runs only while the song plays, motion is welcome and the
    /// bubble shows. Held, it comes off and the colour keeps the angle it
    /// stood at, so a paused or hidden bubble asks the compositor for
    /// nothing; it goes on again from that angle, so it never jumps.
    private func sync() {
        // A withdrawn bubble is hidden, not removed: it rests too.
        let visible = !isHiddenOrHasHiddenAncestor && (window.map { $0.occlusionState.contains(.visible) } ?? false)
        let run = playing && moves && visible
        if run, !isTurning {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = angle
            spin.toValue = angle - 2 * Double.pi
            spin.duration = Self.turn
            spin.repeatCount = .infinity
            spin.preferredFrameRateRange = NotchSongMotion.slowFrames
            swirl.add(spin, forKey: "turn")
        } else if !run, isTurning {
            let held = (swirl.presentation()?.value(forKeyPath: "transform.rotation.z") as? NSNumber)?.doubleValue
            angle = held ?? angle
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            swirl.transform = CATransform3DMakeRotation(CGFloat(angle), 0, 0, 1)
            swirl.removeAnimation(forKey: "turn")
            CATransaction.commit()
        }
        if run, beatSubscription == nil {
            beatSubscription = NotchMusicPulse.shared.beat.sink { [weak self] beat in self?.pulse(beat) }
        } else if !run, beatSubscription != nil {
            beatSubscription = nil
            pulse(.settle(from: 0))
        }
    }

    /// The swell and the thinning veil a beat sets going, added to their
    /// resting values.
    private var swelling = NotchBeatTrack()
    private var thinning = NotchBeatTrack()

    /// A hit swells the bubble and thins its veil, and both fall away with
    /// it, as one move each (NotchMusicBeat.moves); a settle eases them back.
    private func pulse(_ beat: NotchMusicBeat) {
        let now = CACurrentMediaTime()
        guard !beat.settles || swelling.value(at: now) != 0 || thinning.value(at: now) != 0 else { return }
        CATransaction.begin()
        defer { CATransaction.commit() }
        // Each falls at 30 frames a second until it is near rest, a point
        // from the rim or a few hundredths of the veil, then at 15.
        let swell = swelling.start(beat.moves { 0.12 * min(1, max(0, $0)) }, at: now)
        let rim = Double(max(1, max(bounds.width, bounds.height) / 2))
        NotchSongMotion.play(swell.animation("sublayerTransform.scale", additive: true), attack: beat.attack,
                             tail: swell.calm(within: NotchBeatFall.stillPoints / 2 / rim), on: canvas, key: "beat",
                             at: now)
        let thin = thinning.start(beat.moves { -0.35 * min(1, max(0, $0)) }, at: now)
        NotchSongMotion.play(thin.animation("opacity", additive: true), attack: beat.attack,
                             tail: thin.calm(within: NotchBeatFall.stillOpacity), on: veil, key: "beat", at: now)
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

/// The closed strip's cover, ringed in the song's own colours while the
/// island wears them, so it is set into the strip as the dancers are across
/// the camera. One stroke inside the cover's edge, drawn once: the layout
/// does not move and nothing redraws while the song plays. It softens while
/// the song is paused, and a new song's ring fades in over the last's.
struct NotchCoverRing: ViewModifier {
    @ObservedObject private var paint = NotchSongPaint.shared
    let radius: CGFloat
    /// Whether the song is playing.
    let lit: Bool
    static let width: CGFloat = 1.25

    func body(content: Content) -> some View {
        let colours = NotchOfficeEdition.isEnabled() ? paint.palette.map(Self.colours) : nil
        content
            .overlay {
                if let colours {
                    RoundedRectangle(cornerRadius: radius, style: .circular)
                        .strokeBorder(LinearGradient(colors: colours, startPoint: .topLeading, endPoint: .bottomTrailing),
                                      lineWidth: Self.width)
                        .opacity(lit ? 0.95 : 0.45)
                        .id(colours)
                        .transition(.opacity)
                }
            }
            .animation(NotchSongMotion.colour, value: colours)
            .animation(NotchSongMotion.swapEase, value: lit)
    }

    /// The palette's marks, light enough to read on the island's dark: the
    /// lead colour into the next, never fewer than two.
    static func colours(_ palette: NotchArtworkPalette) -> [Color] {
        let marks = palette.marks.prefix(2).map { Color(nsColor: $0) }
        return marks.count > 1 ? marks : marks + marks
    }
}
