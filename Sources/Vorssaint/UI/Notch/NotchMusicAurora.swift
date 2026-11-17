// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// The island's backdrop while its music page is open: the song's own colours,
/// cut to the island's live outline so it opens and closes with the island.
/// It sits beside the glass in the window's background, under the page.
struct NotchMusicBackdrop: View {
    @ObservedObject var presentation: NotchBackdropPresentation
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @State private var mood: NotchMusicMood = .neutral

    var body: some View {
        if notch.expanded, notch.selected == .music, notch.selectedMetric == nil,
           let playback = music.playback, let palette = NotchArtworkPalette.of(music.artwork) {
            let track = playback.track
            NotchMusicAurora(palette: palette, isPlaying: playback.isPlaying, mood: mood)
                // The camera's strip stays black, meeting the housing as the
                // resting island does, and the colour rises out of it.
                .overlay(alignment: .top) {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: 0.5),
                                           .init(color: .black.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: presentation.stripHeight + 20)
                }
                .mask(NotchBackdropShape(contour: presentation.contour))
                .opacity(presentation.openness)
                .task(id: [track.title, track.artist, track.album, track.appBundleIdentifier]
                        .map { $0 ?? "" }.joined(separator: "\u{1F}")) {
                    mood = await NotchMusicGenre.mood(for: track)
                }
                .transition(.opacity.animation(.easeOut(duration: 0.25)))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The song's own colours, drifting and answering the music.
///
/// Three soft pools of the cover's palette move and breathe on long, unequal
/// loops, so the light never visibly repeats. The music steers them: its
/// energy lifts the veil and swells the light on the beat, and its average
/// energy, with the genre's character, sets how fast the light drifts. A song
/// change cross-fades to the new cover with a brief bloom; a pause settles and
/// dims it. The motion is Core Animation, run by the render server; the app
/// only nudges a few layer values about twelve times a second while a song
/// plays and the island shows, and nothing at all otherwise.
struct NotchMusicAurora: View {
    let palette: NotchArtworkPalette
    let isPlaying: Bool
    var mood: NotchMusicMood = .neutral
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NotchMusicAuroraBridge(colors: palette.glow, playing: isPlaying, moves: !reduceMotion, mood: mood)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct NotchMusicAuroraBridge: NSViewRepresentable {
    let colors: [NSColor]
    let playing: Bool
    let moves: Bool
    let mood: NotchMusicMood

    func makeNSView(context: Context) -> NotchMusicAuroraView { NotchMusicAuroraView() }

    func updateNSView(_ view: NotchMusicAuroraView, context: Context) {
        view.apply(colors: colors, playing: playing, moves: moves, mood: mood)
    }

    static func dismantleNSView(_ view: NotchMusicAuroraView, coordinator: ()) { view.teardown() }
}

final class NotchMusicAuroraView: NSView {
    /// Deceleration for arrivals: quick to start, long gentle settle.
    private static let settle = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    private static let entrance: CFTimeInterval = 0.55
    private static let colorChange: CFTimeInterval = 0.9
    private static let pauseChange: CFTimeInterval = 0.7
    /// How bright the backdrop stands while paused, against 1 while playing.
    private static let pausedOpacity: Float = 0.5
    /// The veil never thins below this share of itself, so text keeps its
    /// contrast at the loudest beat.
    private static let thinnestVeil: Double = 0.55

    /// Where each pool rests, as a fraction of the island, and its loops: how
    /// long one drift around its rest takes, and one breath in and out.
    private static let pools: [(rest: CGPoint, drift: CFTimeInterval, breath: CFTimeInterval)] = [
        (CGPoint(x: 0.16, y: 0.56), 11, 6),
        (CGPoint(x: 0.58, y: 0.26), 14, 8),
        (CGPoint(x: 0.88, y: 0.60), 17, 9),
    ]

    private let ground = CALayer()
    private let stage = CALayer()
    private let base = CAGradientLayer()
    private var blobs: [CAGradientLayer] = []
    private let scrim = CAGradientLayer()
    /// Soft bursts of the cover's colour, one per beat, reused in turn.
    private var bursts: [CAGradientLayer] = []
    private var nextBurst = 0
    private var lastEnergy: Double = 0
    private var lastKick: CFTimeInterval = 0

    private var colors: [NSColor] = []
    private var playing = false
    private var moves = true
    private var mood: NotchMusicMood = .neutral
    private var entered = false
    private var motionSize: CGSize = .zero
    private var occlusionObserver: NSObjectProtocol?

    // The music's energy: a quick envelope for the beat, a slow one for the
    // song's overall drive, and the drift speed they set.
    private var levelsSubscription: AnyCancellable?
    private var beat: Double = 0
    private var drive: Double = 0
    private var rate: Float = 1
    private var ticks = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // A layer-hosting view: the layer is set before wantsLayer, so AppKit
        // leaves its sublayers alone and their geometry stays bottom-left
        // origin, which the gradients below are written for.
        layer = CALayer()
        wantsLayer = true
        setAccessibilityElement(false)
        layer?.opacity = 0
        layer?.masksToBounds = true

        // A deep ground under the colour. Over Liquid Glass the colour would
        // otherwise mix with whatever sits behind the island; on this ground
        // the cover's palette glows the same over any wallpaper or window.
        ground.backgroundColor = NSColor(srgbRed: 0.035, green: 0.035, blue: 0.05, alpha: 0.94).cgColor
        layer?.addSublayer(ground)

        base.type = .axial
        base.startPoint = CGPoint(x: 0, y: 1)
        base.endPoint = CGPoint(x: 1, y: 0)
        stage.addSublayer(base)

        for _ in Self.pools {
            let blob = CAGradientLayer()
            blob.type = .radial
            blob.startPoint = CGPoint(x: 0.5, y: 0.5)
            blob.endPoint = CGPoint(x: 1, y: 1)
            stage.addSublayer(blob)
            blobs.append(blob)
        }
        for _ in 0..<3 {
            let burst = CAGradientLayer()
            burst.type = .radial
            burst.startPoint = CGPoint(x: 0.5, y: 0.5)
            burst.endPoint = CGPoint(x: 1, y: 1)
            burst.opacity = 0
            stage.addSublayer(burst)
            bursts.append(burst)
        }
        layer?.addSublayer(stage)

        // A dark veil over the colour keeps the player's white text, and its
        // softer secondary text, above WCAG AA on any cover.
        scrim.type = .axial
        scrim.startPoint = CGPoint(x: 0.5, y: 1)
        scrim.endPoint = CGPoint(x: 0.5, y: 0)
        scrim.colors = [NSColor.black.withAlphaComponent(0.26).cgColor,
                        NSColor.black.withAlphaComponent(0.12).cgColor,
                        NSColor.black.withAlphaComponent(0.22).cgColor]
        scrim.locations = [0, 0.55, 1]
        layer?.addSublayer(scrim)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    // MARK: State

    func apply(colors newColors: [NSColor], playing newPlaying: Bool, moves newMoves: Bool, mood newMood: NotchMusicMood) {
        let colorsChanged = newColors.map(\.cgColor) != colors.map(\.cgColor)
        let firstColors = colors.isEmpty
        colors = newColors
        if colorsChanged {
            paint(animated: !firstColors)
            if !firstColors { bloom() }
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
            playing = newPlaying
            updatePlayback()
            if !playing { settleResponse() }
        }
    }

    func teardown() {
        levelsSubscription = nil
        stage.sublayers?.forEach { $0.removeAllAnimations() }
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
    }

    /// The pools take the cover's colours: the lead colour largest and
    /// strongest, the others as accents. A new cover fades in over the old.
    private func paint(animated: Bool) {
        guard !colors.isEmpty else { return }
        let lead = colors[0], second = colors[min(1, colors.count - 1)], third = colors[min(2, colors.count - 1)]
        let baseColors = [lead.withAlphaComponent(0.55).cgColor,
                          second.withAlphaComponent(0.42).cgColor,
                          third.withAlphaComponent(0.50).cgColor]
        let poolColors = [lead, second, third]
        let poolStrength: [CGFloat] = [0.96, 0.88, 0.84]

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated {
            fade(base, to: baseColors)
            for (index, blob) in blobs.enumerated() {
                fade(blob, to: [poolColors[index].withAlphaComponent(poolStrength[index]).cgColor,
                                poolColors[index].withAlphaComponent(0).cgColor])
            }
        }
        base.colors = baseColors
        for (index, blob) in blobs.enumerated() {
            blob.colors = [poolColors[index].withAlphaComponent(poolStrength[index]).cgColor,
                           poolColors[index].withAlphaComponent(0).cgColor]
        }
        CATransaction.commit()
    }

    /// A new song's arrival: the veil lifts for a moment so the new colours
    /// flare across the island, then settles. Opacity only, so it stays under
    /// Reduce Motion as the one cue that the song changed.
    private func bloom() {
        let flare = CAKeyframeAnimation(keyPath: "opacity")
        flare.values = [1, 0.15, 1]
        flare.keyTimes = [0, 0.22, 1]
        flare.timingFunctions = [CAMediaTimingFunction(name: .easeOut), Self.settle]
        flare.duration = 1.25
        scrim.add(flare, forKey: "bloom")
    }

    private func fade(_ layer: CAGradientLayer, to colors: [CGColor]) {
        let animation = CABasicAnimation(keyPath: "colors")
        animation.fromValue = layer.presentation()?.colors ?? layer.colors
        animation.toValue = colors
        animation.duration = Self.colorChange
        animation.timingFunction = Self.settle
        layer.add(animation, forKey: "colors")
    }

    /// Playing: full strength and moving. Paused: dimmer and still, held where
    /// it stood rather than snapping back.
    private func updatePlayback() {
        guard let root = layer else { return }
        let target: Float = playing ? 1 : Self.pausedOpacity
        let from = root.presentation()?.opacity ?? root.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.opacity = target
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = target
        animation.duration = entered ? Self.pauseChange : Self.entrance
        animation.timingFunction = Self.settle
        root.add(animation, forKey: "opacity")
        entered = true
        syncClock()
    }

    // MARK: Clock

    /// The stage's local time, carried across every change of speed so the
    /// pools never jump: a change re-anchors the clock where it stands.
    private var running: Bool { stage.speed != 0 }

    private func parentTime() -> CFTimeInterval {
        layer?.convertTime(CACurrentMediaTime(), from: nil) ?? CACurrentMediaTime()
    }

    /// The stage's clock runs only while a song plays, the island shows, and
    /// motion is welcome. Stopping it freezes the pools in their current pose.
    private func syncClock() {
        let visible = window.map { $0.occlusionState.contains(.visible) } ?? false
        let run = playing && visible && moves
        if run, !running {
            stage.beginTime = parentTime()
            stage.speed = rate
        } else if !run, running {
            let local = stage.convertTime(CACurrentMediaTime(), from: nil)
            stage.speed = 0
            stage.timeOffset = local
        }
        listen(run)
    }

    /// Changes the drift speed without a jump in the pools' positions.
    private func retime(towards target: Float, immediately: Bool) {
        let next = immediately ? target : rate + (target - rate) * 0.5
        guard abs(next - rate) > 0.02 else { return }
        rate = next
        guard running else { return }
        let local = stage.convertTime(CACurrentMediaTime(), from: nil)
        stage.timeOffset = local
        stage.beginTime = parentTime()
        stage.speed = rate
    }

    private func targetRate() -> Float {
        // The genre sets the character; the song's drive leans it faster or slower.
        let lean = Float(0.75 + 0.6 * min(1, drive))
        return min(2.0, max(0.45, mood.rate * lean))
    }

    // MARK: Listening

    private func listen(_ on: Bool) {
        guard on else { levelsSubscription = nil; return }
        guard levelsSubscription == nil else { return }
        levelsSubscription = NotchAudioLevelService.shared.$levels
            .throttle(for: .milliseconds(80), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] levels in self?.hear(levels) }
    }

    private func hear(_ levels: [Double]?) {
        guard playing, moves else { return }
        let energy = Self.energy(levels, bassWeight: mood.bassWeight)
        // Quick to rise with a beat, slower to fall, so the light breathes
        // with the music instead of flickering.
        beat += (energy - beat) * (energy > beat ? 0.55 : 0.16)
        drive += (energy - drive) * 0.03
        let push = mood.response * beat
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        scrim.opacity = Float(1 - min(1 - Self.thinnestVeil, push * 0.6))
        let swell = 1 + 0.08 * push
        stage.transform = CATransform3DMakeScale(swell, swell, 1)
        CATransaction.commit()
        // A kick: the energy jumps clear of the song's own level, not merely
        // loud. Spaced at least 0.4 s apart, so never above 2.5 a second, under
        // the three-flashes-a-second limit for flashing content.
        let now = CACurrentMediaTime()
        if mood != .calm, energy - lastEnergy > 0.1, energy > drive * 1.2 + 0.05, now - lastKick > 0.4 {
            lastKick = now
            kick(strength: min(1, (energy - lastEnergy) * 4) * mood.response)
        }
        lastEnergy = energy
        ticks += 1
        // The drift's speed follows the song's drive, gently, every second and a half.
        if ticks % 18 == 0 { retime(towards: targetRate(), immediately: false) }
    }

    /// A soft burst of one of the cover's colours, blooming from where its
    /// pool rests and fading in under half a second. Below the veil, so text
    /// keeps its contrast through it.
    private func kick(strength: Double) {
        guard !colors.isEmpty, strength > 0.05, let size = Optional(bounds.size), size.width > 1 else { return }
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
        fade.values = [0, Float(0.35 + 0.5 * strength), 0]
        fade.keyTimes = [0, 0.18, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.45
        group.timingFunction = Self.settle
        burst.add(group, forKey: "kick")
    }

    /// The light's rest pose, eased back to when the music stops answering.
    private func settleResponse() {
        beat = 0
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        CATransaction.setAnimationTimingFunction(Self.settle)
        scrim.opacity = 1
        stage.transform = CATransform3DIdentity
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

    private func installMotion() {
        let size = bounds.size
        motionSize = size
        for blob in blobs {
            blob.removeAnimation(forKey: "drift")
            blob.removeAnimation(forKey: "breath")
        }
        guard moves, window != nil, size.width > 1, size.height > 1 else { syncClock(); return }
        let reachX = size.width * 0.14, reachY = size.height * 0.26
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
            drift.calculationMode = .cubic
            drift.duration = pool.drift
            drift.repeatCount = .infinity
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
        ground.frame = bounds
        stage.bounds = CGRect(origin: .zero, size: size)
        stage.position = CGPoint(x: size.width / 2, y: size.height / 2)
        base.frame = CGRect(origin: .zero, size: size)
        scrim.frame = bounds
        let poolSize = CGSize(width: size.width * 0.78, height: size.height * 1.7)
        for (index, blob) in blobs.enumerated() {
            let rest = Self.pools[index].rest
            blob.bounds = CGRect(origin: .zero, size: poolSize)
            blob.position = CGPoint(x: size.width * rest.x, y: size.height * rest.y)
        }
        CATransaction.commit()
        // The drift's reach follows the island; a lyrics panel opening resizes it.
        if abs(size.width - motionSize.width) > 1 || abs(size.height - motionSize.height) > 1 {
            installMotion()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        guard let window else {
            levelsSubscription = nil
            blobs.forEach { $0.removeAllAnimations() }
            motionSize = .zero
            return
        }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in self?.syncClock() }
        installMotion()
    }
}
