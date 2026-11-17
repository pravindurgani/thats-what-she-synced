// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// The island's backdrop while its music page is open: the song's own colours,
/// sized to the island's box and cut to its live outline, so it opens and
/// closes with the island. It sits beside the glass in the main island's
/// window background, under the page; mirror windows never draw it.
struct NotchMusicBackdrop: View {
    @ObservedObject var presentation: NotchBackdropPresentation
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var mood: NotchMusicMood = .neutral

    /// Only the music page itself, never the sections gallery, the app panel
    /// or a metric opened over it.
    private var showsMusicPage: Bool {
        notch.expanded && notch.selected == .music && notch.selectedMetric == nil
            && !notch.showingSections && !notch.showingAppPanel && !notch.modules.isEmpty
    }

    var body: some View {
        let box = presentation.contour.boundingRect.integral
        if showsMusicPage, !box.isNull, box.width > 0, box.height > 0,
           let playback = music.playback, let palette = NotchArtworkPalette.of(music.artwork) {
            let track = playback.track
            NotchMusicAurora(palette: palette, isPlaying: playback.isPlaying, mood: mood,
                             deepVeil: contrast == .increased || notch.musicDetailVisible)
                // The camera's strip stays black, meeting the housing as the
                // resting island does, and the colour rises out of it.
                .overlay(alignment: .top) {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: 0.5),
                                           .init(color: .black.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: presentation.stripHeight + 20)
                }
                .frame(width: box.width, height: box.height)
                .mask(NotchBackdropShape(contour: presentation.contour.offsetBy(dx: -box.minX, dy: -box.minY)))
                .padding(EdgeInsets(top: box.minY, leading: box.minX, bottom: 0, trailing: 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(presentation.openness)
                .task(id: [track.title, track.artist, track.album, track.appBundleIdentifier]
                        .map { $0 ?? "" }.joined(separator: "\u{1F}")) {
                    let next = await NotchMusicGenre.mood(for: track)
                    // A reply that arrives after the song changed belongs to the old song.
                    guard !Task.isCancelled else { return }
                    mood = next
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
    /// A heavier veil, for Increase Contrast and while lyrics or the queue are open.
    var deepVeil = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NotchMusicAuroraBridge(colors: palette.glow, playing: isPlaying, moves: !reduceMotion,
                               mood: mood, deepVeil: deepVeil)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct NotchMusicAuroraBridge: NSViewRepresentable {
    let colors: [NSColor]
    let playing: Bool
    let moves: Bool
    let mood: NotchMusicMood
    let deepVeil: Bool

    func makeNSView(context: Context) -> NotchMusicAuroraView { NotchMusicAuroraView() }

    func updateNSView(_ view: NotchMusicAuroraView, context: Context) {
        view.apply(colors: colors, playing: playing, moves: moves, mood: mood, deepVeil: deepVeil)
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
    private static let thinnestVeil: Double = 0.8

    /// Where each pool rests, as a fraction of the island, and its loops: how
    /// long one drift around its rest takes, and one breath in and out.
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
    private var deepVeil = false
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
    private var installedSize: CGSize = .zero
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
        for _ in Self.pools {
            let blob = Self.pool()
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

        // A dark veil over the colour keeps the player's white text, and its
        // softer secondary text, above WCAG AA on any cover.
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

    func apply(colors newColors: [NSColor], playing newPlaying: Bool, moves newMoves: Bool,
               mood newMood: NotchMusicMood, deepVeil newDeepVeil: Bool) {
        let colorsChanged = newColors.map(\.cgColor) != colors.map(\.cgColor)
        let firstColors = colors.isEmpty
        colors = newColors
        if colorsChanged {
            paint(animated: !firstColors)
            if !firstColors { bloom() }
        }
        if newDeepVeil != deepVeil {
            deepVeil = newDeepVeil
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
        let weight: CGFloat = deepVeil ? 1.9 : 1
        let stops: [CGFloat] = [0.26, 0.12, 0.22].map { min(0.6, $0 * weight) }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.3)
        scrim.colors = stops.map { NSColor.black.withAlphaComponent($0).cgColor }
        CATransaction.commit()
    }

    /// A new song's arrival: the veil lifts for a moment so the new colours
    /// flare across the island, then settles. Opacity only, so it stays under
    /// Reduce Motion as the one cue that the song changed.
    private func bloom() {
        let flare = CAKeyframeAnimation(keyPath: "opacity")
        flare.values = [1, 0.5, 1]
        flare.keyTimes = [0, 0.22, 1]
        flare.timingFunctions = [CAMediaTimingFunction(name: .easeOut), Self.settle]
        flare.duration = 1.25
        scrim.add(flare, forKey: "bloom")
        bloomUntil = CACurrentMediaTime() + flare.duration
    }

    /// Playing: full strength and moving. Paused: dimmer and still, held where
    /// it stood rather than snapping back.
    private func updatePlayback() {
        // Half strength behind lyrics or the queue, whose softer text needs a calmer ground.
        let target: Float = (playing ? 1 : Self.pausedOpacity) * (deepVeil ? 0.55 : 1)
        let from = canvas.presentation()?.opacity ?? canvas.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.opacity = target
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = target
        animation.duration = entered ? Self.pauseChange : Self.entrance
        animation.timingFunction = Self.settle
        canvas.add(animation, forKey: "opacity")
        entered = true
        syncClock()
    }

    // MARK: Clock

    /// Whether the drift's clock is running. Every change of its speed is
    /// re-anchored where it stands, so the pools never jump.
    private var running: Bool { clock.speed != 0 }

    private func stageTime() -> CFTimeInterval { stage.convertTime(CACurrentMediaTime(), from: nil) }

    /// The drift runs only while a song plays, the island shows, and motion
    /// is welcome. Stopping it freezes the pools in their current pose.
    private func syncClock() {
        let visible = window.map { $0.occlusionState.contains(.visible) } ?? false
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
        // The genre sets the character; the song's drive and the volume lean it.
        let lean = Float((0.75 + 0.6 * min(1, drive)) * (0.85 + 0.3 * loudness))
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
            bounce = max(bounce, min(1, 0.45 + flux * 6) * mood.response * intensity)
            if mood != .calm { kick(strength: bounce) }
        } else {
            // A quick fall after each hit, so the light jumps on the beat and
            // drops between beats, as a meter's needle does.
            bounce *= 0.72
        }

        // Nothing to move between beats once the light is at rest.
        let resting = bounce < 0.01 && appliedBounce < 0.01
        if resting { bounce = 0 } else { appliedBounce = bounce }
        if !resting {
        CATransaction.begin()
        CATransaction.setAnimationDuration(onset ? 0.06 : 0.09)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        scrim.opacity = Float(1 - min(1 - Self.thinnestVeil, bounce * 0.55))
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

    /// Adds the pools' drift and breath when the view first has a size in a
    /// window, when Reduce Motion changes, and once a resize has settled at a
    /// size well apart from the one the drift was made for. A re-made drift
    /// keeps each loop's begin time, so it carries on from where it was.
    private func installMotion(keepingPhase: Bool = false) {
        let size = bounds.size
        let began: [(drift: CFTimeInterval?, breath: CFTimeInterval?)] = blobs.map {
            keepingPhase ? ($0.animation(forKey: "drift")?.beginTime, $0.animation(forKey: "breath")?.beginTime) : (nil, nil)
        }
        for blob in blobs {
            blob.removeAnimation(forKey: "drift")
            blob.removeAnimation(forKey: "breath")
        }
        motionInstalled = false
        guard moves, window != nil, size.width > 1, size.height > 1 else { syncClock(); return }
        motionInstalled = true
        installedSize = size
        let reachX = size.width * 0.14, reachY = size.height * 0.26
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
            drift.beginTime = began[index].drift ?? now
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
            breath.beginTime = began[index].breath ?? now
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
        clock.frame = lift.bounds
        scrim.frame = canvas.bounds
        let poolSize = CGSize(width: size.width * 0.78, height: size.height * 1.7)
        for (index, blob) in blobs.enumerated() {
            let rest = Self.pools[index].rest
            blob.bounds = CGRect(origin: .zero, size: poolSize)
            blob.position = CGPoint(x: size.width * rest.x, y: size.height * rest.y)
        }
        CATransaction.commit()
        if !motionInstalled {
            installMotion()
        } else if installedSize.width > 1, installedSize.height > 1,
                  abs(size.width / installedSize.width - 1) > 0.1 || abs(size.height / installedSize.height - 1) > 0.1 {
            // The island opening, or lyrics unfolding, resizes it frame by
            // frame; the drift's reach is re-made once it has settled.
            reinstall?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.installMotion(keepingPhase: true) }
            reinstall = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
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
        installMotion()
    }
}

