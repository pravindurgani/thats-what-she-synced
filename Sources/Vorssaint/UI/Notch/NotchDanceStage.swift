// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// What the dancers wear from the song: outfits in tones of its lead colour
/// (NotchDanceTone), ties and collars in its second, its colours at full
/// voice for speaker cones and each figure's halo, the floor's spotlight in
/// its second colour, and the one paper fill every head and hand shares.
struct NotchDancePaint: Equatable {
    var accents: [NSColor]
    var tones: [NotchDanceTone: NSColor]
    var tie: NSColor
    var spot: NSColor
    var head: NSColor

    /// Paper, the same for every figure: never a skin tone.
    static let paper = NotchDanceTone.paper.nsColor

    /// From the song's colours at full voice, `pure`, and its bright marks.
    init(pure: [NSColor], marks: [NSColor], head: NSColor = NotchDancePaint.paper) {
        let lead = Self.rgb(pure.first ?? .white)
        let second = Self.rgb(pure.count > 1 ? pure[1] : pure.first ?? .white)
        tones = Dictionary(uniqueKeysWithValues: NotchDanceTone.allCases.map { ($0, $0.of(lead).nsColor) })
        tie = NotchDanceTone.tie(second).nsColor
        accents = marks.isEmpty ? [.white] : marks
        spot = accents[min(1, accents.count - 1)]
        self.head = head
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accents.map(\.cgColor) == rhs.accents.map(\.cgColor) && lhs.head.cgColor == rhs.head.cgColor
            && lhs.tie.cgColor == rhs.tie.cgColor && lhs.spot.cgColor == rhs.spot.cgColor
            && NotchDanceTone.allCases.allSatisfy { lhs.tones[$0]?.cgColor == rhs.tones[$0]?.cgColor }
    }

    private static func rgb(_ color: NSColor) -> NotchRGB {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        return NotchRGB(red: Double(srgb.redComponent), green: Double(srgb.greenComponent),
                        blue: Double(srgb.blueComponent))
    }
}

/// The dancers' layers. Under them, a dark pool that keeps them clear of a
/// bright aurora, a flat spotlight that jumps with the beat, and behind each
/// figure a soft halo of its own colour. Per figure, back to front: its
/// black keyline as one path, then a shape layer per drawn part, neighbouring
/// filled parts in one paint as one, with one fine ring over heads and hands
/// (NotchDancer.drawing). Nothing here asks for a pass of its own: no layer
/// shadow, no group opacity, and the pool, the spotlight and the halos are
/// glows drawn once into images (NotchGlowImage), which the render server
/// only places again on each frame the figures over them move.
/// It holds no timers; its view says when to move, and every move is a Core
/// Animation animation the render server plays, from wherever the figures
/// are when it starts.
final class NotchDanceStage {
    let layer = CALayer()
    private let scrim = CALayer()
    private let spot = CALayer()
    private(set) var routine: NotchDanceRoutine?
    private(set) var poses: [NotchDancerPose] = []
    private var dancers: [NotchDancer] = []
    private var halos: [CALayer] = []
    private var figures: [Figure] = []
    private var floor: NotchDanceLayout?
    private var paint: NotchDancePaint?
    private var contentsScale: CGFloat = 2
    /// Each figure's move as last set going, and the spotlight's, so the
    /// next starts from where they stand without reading the screen.
    private var motions: [Motion?] = []
    private var spotlight = NotchBeatTrack()

    /// A figure's move: when it started, its knots' times from then, each
    /// shape's path at each knot, and the curve of each span between.
    private struct Motion {
        let begin: CFTimeInterval
        let times: [CFTimeInterval]
        let paths: [[CGPath]]
        let curves: [CAMediaTimingFunction]
    }

    /// The shares of a settle played at 60 frames a second and from which
    /// it plays at 15 (NotchDanceTiming.quickShare and calmShare).
    private static let quickShare = NotchDanceTiming.quickShare
    private static let calmShare = NotchDanceTiming.calmShare

    /// One figure's shape layers.
    private struct Figure {
        let keyline: CAShapeLayer
        let ring: CAShapeLayer?
        /// One per group of NotchDancer.drawnParts, back to front.
        let parts: [CAShapeLayer]

        /// Every one of them, in the order `paths` lists their paths.
        var shapes: [CAShapeLayer] { [keyline] + (ring.map { [$0] } ?? []) + parts }

        func paths(_ drawing: NotchDancerDrawing) -> [CGPath] {
            [drawing.keyline] + (ring == nil ? [] : [drawing.ring]) + drawing.parts
        }
    }

    /// The spotlight between beats and at a beat's peak.
    static let spotRest: Float = 0.3
    static let spotPeak: Float = 0.75
    /// The spotlight's beat: out quickly, then a short fall.
    static let spotAttack: CFTimeInterval = 0.08
    static let spotDecay: CFTimeInterval = 0.24
    /// About 44 by 6 points at full size, never wider than the floor.
    static let spotSize = CGSize(width: 44, height: 6)
    /// The dark pool's strength at its middle.
    static let scrimStrength: CGFloat = 0.5
    /// The halo of each figure's own colour, where it stands: about 18 by
    /// 32 points at full size, strongest behind the body, so what shows is
    /// a soft light around it, and gone by its edge.
    static let haloSize = CGSize(width: 18, height: 32)
    static let haloStops: [(at: CGFloat, alpha: CGFloat)] = [(0, 0.6), (0.4, 0.42), (0.7, 0.14), (1, 0)]
    /// The keyline behind each figure, one path, faded as one.
    static let keylineOpacity: CGFloat = 0.6
    /// The fine ring a head or hand keeps over the body (NotchDancer.ringShare), lighter.
    static let ringOpacity: CGFloat = 0.42

    init() {
        layer.masksToBounds = false
        scrim.contents = NotchGlowImage.radial([NSColor.black.withAlphaComponent(Self.scrimStrength).cgColor,
                                                NSColor.black.withAlphaComponent(Self.scrimStrength * 0.55).cgColor,
                                                NSColor.black.withAlphaComponent(0).cgColor],
                                               locations: [0, 0.55, 1])
        layer.addSublayer(scrim)
        spot.opacity = Self.spotRest
        layer.addSublayer(spot)
    }

    /// How long one dance takes to cross-fade into the next, as a new look
    /// does on the companion.
    static let danceChange: CFTimeInterval = 0.24

    /// Sets the dance on `floor`. A new dance or floor rebuilds the figures
    /// and stands them in `poses`. With `fades`, another dance cross-fades
    /// in over the last one rather than swapping figures in a single frame;
    /// the first dance, or the same one on a new floor, is simply there. A
    /// fade is no motion, so it plays under Reduce Motion too, as the
    /// colours' change does.
    func configure(routine: NotchDanceRoutine, floor: NotchDanceLayout, poses: [NotchDancerPose],
                   contentsScale: CGFloat, fades: Bool = false) {
        guard routine != self.routine || floor != self.floor || figures.isEmpty else { return }
        let fade = fades && self.routine != nil && routine != self.routine
        self.routine = routine
        self.floor = floor
        self.contentsScale = contentsScale
        dancers = routine.dancers
        // One transaction for the rebuild, its colours and its poses, so the
        // fade runs from the whole last dance to the whole new one.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if fade {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = Self.danceChange
            transition.timingFunction = NotchSongMotion.settleCurve
            layer.add(transition, forKey: "routine")
        }
        halos.forEach { $0.removeFromSuperlayer() }
        figures.flatMap(\.shapes).forEach { $0.removeFromSuperlayer() }
        // Every halo under every figure, so none lies over a neighbour.
        halos = dancers.map { dancer in
            let halo = Self.halo(for: dancer, floor: floor, scale: contentsScale)
            layer.addSublayer(halo)
            return halo
        }
        figures = dancers.map { dancer in
            // The keyline and the ring come grown already (NotchDancer.drawing),
            // and are filled: the parts over them leave only the line showing.
            let outline = Self.shape(contentsScale)
            outline.fillColor = NSColor.black.withAlphaComponent(Self.keylineOpacity).cgColor
            outline.strokeColor = nil
            outline.lineWidth = 0
            layer.addSublayer(outline)
            var ring: CAShapeLayer?
            var parts: [CAShapeLayer] = []
            for (place, group) in dancer.drawnParts.enumerated() {
                if place == dancer.ringPlace {
                    // One ring for the head and both hands, so none doubles up.
                    let fine = Self.shape(contentsScale)
                    fine.fillColor = NSColor.black.withAlphaComponent(Self.ringOpacity).cgColor
                    fine.strokeColor = nil
                    fine.lineWidth = 0
                    layer.addSublayer(fine)
                    ring = fine
                }
                let shape = Self.shape(contentsScale)
                if let width = dancer.lineWidth(dancer.layers[group[0]], floor: floor) {
                    shape.lineWidth = width
                    shape.fillColor = nil
                } else {
                    shape.lineWidth = 0
                    shape.strokeColor = nil
                }
                layer.addSublayer(shape)
                parts.append(shape)
            }
            return Figure(keyline: outline, ring: ring, parts: parts)
        }
        motions = Array(repeating: nil, count: figures.count)
        spotlight.stop()
        // A dark pool behind the whole floor, and the spotlight at the feet.
        scrim.frame = CGRect(x: 0, y: 0, width: floor.width, height: floor.height)
        let spotWidth = min(Self.spotSize.width * floor.scale, floor.width)
        let spotHeight = Self.spotSize.height * floor.scale
        spot.frame = CGRect(x: (floor.width - spotWidth) / 2, y: floor.ground - spotHeight * 0.4,
                            width: spotWidth, height: spotHeight)
        if let paint { colour(paint, animated: false) }
        show(poses, duration: 0)
    }

    /// A soft halo behind `dancer`, centred where it stands and kept within
    /// the floor's height. It stays put while the figure moves.
    private static func halo(for dancer: NotchDancer, floor: NotchDanceLayout, scale: CGFloat) -> CALayer {
        let halo = CALayer()
        halo.contentsScale = scale
        let middle = CGPoint(x: floor.width / 2 + dancer.position * floor.scale,
                             y: floor.ground + dancer.height * floor.scale / 2)
        let width = haloSize.width * floor.scale
        let half = max(0, min(haloSize.height * floor.scale / 2, middle.y, floor.height - middle.y))
        halo.frame = CGRect(x: middle.x - width / 2, y: middle.y - half, width: width, height: half * 2)
        return halo
    }

    private static func shape(_ scale: CGFloat) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.contentsScale = scale
        shape.lineCap = .round
        shape.lineJoin = .round
        return shape
    }

    func setContentsScale(_ scale: CGFloat) {
        guard scale != contentsScale else { return }
        contentsScale = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        figures.flatMap(\.shapes).forEach { $0.contentsScale = scale }
        halos.forEach { $0.contentsScale = scale }
        spot.contentsScale = scale
        scrim.contentsScale = scale
        CATransaction.commit()
    }

    /// Puts on the song's colours. A new song's colours flow in as the
    /// bars' do; the first ones are simply there.
    func wear(_ paint: NotchDancePaint, animated: Bool) {
        guard paint != self.paint else { return }
        let first = self.paint == nil
        self.paint = paint
        colour(paint, animated: animated && !first)
    }

    private func colour(_ paint: NotchDancePaint, animated: Bool) {
        guard let floor else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(NotchSongMotion.colorChange)
        CATransaction.setAnimationTimingFunction(NotchSongMotion.settleCurve)
        for (index, (dancer, figure)) in zip(dancers, figures).enumerated() {
            for (group, shape) in zip(dancer.drawnParts, figure.parts) {
                let description = dancer.layers[group[0]]
                let color = Self.color(description.paint, dancer: dancer, paint: paint)
                if dancer.lineWidth(description, floor: floor) == nil {
                    shape.fillColor = color
                } else {
                    shape.strokeColor = color
                }
            }
            let own = paint.accents[dancer.accent % paint.accents.count]
            // Drawn once a colour; a new song's cross-fades in on the transaction's timing.
            halos[index].contents = NotchGlowImage.radial(Self.haloStops.map { own.withAlphaComponent($0.alpha).cgColor },
                                                          locations: Self.haloStops.map(\.at))
        }
        spot.contents = NotchGlowImage.radial([paint.spot.cgColor, paint.spot.withAlphaComponent(0.45).cgColor,
                                               paint.spot.withAlphaComponent(0).cgColor], locations: [0, 0.45, 1])
        CATransaction.commit()
    }

    static func color(_ paint: NotchDancerLayer.Paint, dancer: NotchDancer, paint colors: NotchDancePaint) -> CGColor {
        switch paint {
        case .outfit(let hex):
            return NotchRGB(hex: hex).cgColor
        case .song(let offset):
            guard !colors.accents.isEmpty else { return NSColor.white.cgColor }
            return colors.accents[(dancer.accent + offset) % colors.accents.count].cgColor
        case .tone(let tone):
            return (colors.tones[tone] ?? .white).cgColor
        case .tie:
            return colors.tie.cgColor
        case .head:
            return colors.head.cgColor
        }
    }

    /// Stands every dancer in its pose, moving there from wherever it is
    /// over `duration`, or at once.
    func show(_ poses: [NotchDancerPose], duration: CFTimeInterval,
              curve: CAMediaTimingFunction = NotchSongMotion.settleCurve) {
        guard poses.count == dancers.count, let floor else { return }
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, (dancer, figure)) in zip(dancers, figures).enumerated() {
            let paths = figure.paths(dancer.drawing(poses[index], floor: floor))
            let standing = duration > 0 ? self.standing(index, at: now) : []
            var starts: [CGPath] = []
            for (place, (shape, path)) in zip(figure.shapes, paths).enumerated() {
                if duration > 0, let from = standing[place] ?? shape.presentation()?.path ?? shape.path {
                    starts.append(from)
                    let move = CABasicAnimation(keyPath: "path")
                    move.fromValue = from
                    move.toValue = path
                    move.duration = duration
                    move.timingFunction = curve
                    // The settle's quick start at 60 frames a second, its long
                    // end at 30, and its last hair at 15.
                    NotchSongMotion.play(move, attack: duration * Self.quickShare, tail: duration * Self.calmShare,
                                         on: shape, key: "dance", at: now)
                } else {
                    starts.append(path)
                    NotchSongMotion.stop("dance", on: shape)
                }
                shape.path = path
            }
            motions[index] = duration > 0
                ? Motion(begin: now, times: [0, duration], paths: [starts, paths], curves: [curve]) : nil
        }
        if duration <= 0 {
            NotchSongMotion.stop("pulse", on: spot)
            spotlight.stop()
        }
        CATransaction.commit()
        self.poses = poses
    }

    /// One dancer's answer to a beat, from wherever it is now: a quick
    /// ease-out into each key pose, then the settle the frames trace. Every
    /// frame anything in the island moves is a frame WindowServer draws the
    /// island again, so a step asks for few: its first hit, on the beat,
    /// at the beat's 60 frames a second, with the light's own hit under it;
    /// the rest at 30, and the settle's last hair, from 93 % of the way, at
    /// 15 (NotchSongMotion.play), as the light under them falls. A move off
    /// the beat (`onBeat` false), the Farewell Three's middle dancer half a
    /// beat late, hits at 30 too, so it asks for no 60s of its own.
    func play(_ step: NotchDanceStep, dancer index: Int, onBeat: Bool = true) {
        guard index < dancers.count, let floor, let last = step.frames.last, step.duration > 0 else { return }
        let dancer = dancers[index]
        let figure = figures[index]
        let now = CACurrentMediaTime()
        let standing = standing(index, at: now)
        let frames = step.frames.map { figure.paths(dancer.drawing($0.pose, floor: floor)) }
        let times = [0] + step.frames.map(\.time)
        let keyTimes = times.map { NSNumber(value: $0 / step.duration) }
        let curves = step.frames.map { frame -> CAMediaTimingFunction in
            switch frame.curve {
            case .attack: return CAMediaTimingFunction(name: .easeOut)
            case .glide: return CAMediaTimingFunction(name: .easeInEaseOut)
            case .settle: return CAMediaTimingFunction(name: .linear)
            }
        }
        let landed = step.frames.last { $0.curve != .settle }?.time ?? 0
        let calm = landed + (step.duration - landed) * Self.calmShare
        let hit = onBeat ? step.frames.first?.time ?? 0 : 0
        var starts: [CGPath] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (place, shape) in figure.shapes.enumerated() {
            let end = frames[frames.count - 1][place]
            guard let from = standing[place] ?? shape.presentation()?.path ?? shape.path else {
                starts.append(end)
                continue
            }
            starts.append(from)
            let move = CAKeyframeAnimation(keyPath: "path")
            move.values = [from] + frames.map { $0[place] }
            move.keyTimes = keyTimes
            move.timingFunctions = curves
            move.duration = step.duration
            shape.path = end
            NotchSongMotion.play(move, attack: hit, tail: calm, on: shape, key: "dance", at: now)
        }
        CATransaction.commit()
        motions[index] = Motion(begin: now, times: times, paths: [starts] + frames, curves: curves)
        poses[index] = last.pose
    }

    /// Where each of figure `index`'s shapes stands at `time`, worked out
    /// from the move last set going, as Core Animation draws it; its own
    /// path once that move is done. Nil for a shape whose outlines are not
    /// drawn alike, which is then read from the screen.
    private func standing(_ index: Int, at time: CFTimeInterval) -> [CGPath?] {
        let shapes = figures[index].shapes
        guard index < motions.count, let motion = motions[index], motion.times.count > 1,
              let last = motion.times.last, time - motion.begin < last else { return shapes.map(\.path) }
        let elapsed = max(0, time - motion.begin)
        var span = 0
        while span + 2 < motion.times.count, motion.times[span + 1] <= elapsed { span += 1 }
        let length = motion.times[span + 1] - motion.times[span]
        let share = CGFloat(motion.curves[span].progress(at: length > 0 ? (elapsed - motion.times[span]) / length : 1))
        return shapes.indices.map { place -> CGPath? in
            guard place < motion.paths[span].count, place < motion.paths[span + 1].count else { return nil }
            return NotchPathBlend.mix(motion.paths[span][place], motion.paths[span + 1][place], share)
        }
    }

    /// The spotlight jumps with a beat at 60 frames a second, as the steps
    /// over it do, and falls away before the next at 30.
    func pulse(_ strength: CGFloat) {
        let share = Double(min(1, max(0, strength.isFinite ? strength : 0)))
        let rest = Double(Self.spotRest)
        let peak = rest + Double(Self.spotPeak - Self.spotRest) * share
        let now = CACurrentMediaTime()
        let from = spotlight.value(at: now, resting: rest)
        let swell = spotlight.start(NotchBeatCurve(times: [0, Self.spotAttack, Self.spotAttack + Self.spotDecay],
                                                   values: [from, peak, rest],
                                                   curves: [CAMediaTimingFunction(name: .easeOut),
                                                            CAMediaTimingFunction(name: .easeIn)]), at: now)
        NotchSongMotion.play(swell.animation("opacity"), attack: Self.spotAttack, on: spot, key: "pulse", at: now)
    }

    /// Every running move ends where it was headed.
    func halt() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        figures.flatMap(\.shapes).forEach { NotchSongMotion.stop("dance", on: $0) }
        NotchSongMotion.stop("pulse", on: spot)
        CATransaction.commit()
        motions = Array(repeating: nil, count: figures.count)
        spotlight.stop()
    }
}
