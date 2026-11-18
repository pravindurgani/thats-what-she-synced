// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// What the dancers wear from the song: outfits in tones of its lead colour
/// (NotchDanceTone), ties and collars in its second, its colours at full
/// voice for speaker cones and each figure's glow, the floor's spotlight in
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

/// The dancers' layers: per figure, one shape layer per drawn part over a
/// black keyline, the whole figure in a soft glow of its own colour; under
/// them a dark pool that keeps them clear of a bright aurora and a flat
/// spotlight that jumps with the beat. It holds no timers; its view says
/// when to move, and every move is a Core Animation animation the render
/// server plays, from wherever the figures are when it starts.
final class NotchDanceStage {
    let layer = CALayer()
    private let scrim = CAGradientLayer()
    private let spot = CAGradientLayer()
    private(set) var routine: NotchDanceRoutine?
    private(set) var poses: [NotchDancerPose] = []
    private var dancers: [NotchDancer] = []
    /// Per figure: the layer carrying its glow, its keyline group, its parts,
    /// and each part's keyline, where it has one.
    private var figures: [CALayer] = []
    private var parts: [[CAShapeLayer]] = []
    private var keylines: [[[CAShapeLayer]]] = []
    private var floor: NotchDanceLayout?
    private var paint: NotchDancePaint?
    private var contentsScale: CGFloat = 2

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
    /// The figures' glow in their own colour, and the keyline behind them.
    static let glowRadius: CGFloat = 2.5
    static let glowOpacity: Float = 0.6
    static let keylineOpacity: Float = 0.6
    /// The fine ring a head or hand keeps over the body: a share of the
    /// keyline, outside its edge, and lighter.
    static let ringShare: CGFloat = 0.55
    static let ringOpacity: Float = 0.42

    init() {
        layer.masksToBounds = false
        scrim.type = .radial
        scrim.startPoint = CGPoint(x: 0.5, y: 0.5)
        scrim.endPoint = CGPoint(x: 1, y: 1)
        scrim.colors = [NSColor.black.withAlphaComponent(Self.scrimStrength).cgColor,
                        NSColor.black.withAlphaComponent(Self.scrimStrength * 0.55).cgColor,
                        NSColor.black.withAlphaComponent(0).cgColor]
        scrim.locations = [0, 0.55, 1]
        layer.addSublayer(scrim)
        spot.type = .radial
        spot.startPoint = CGPoint(x: 0.5, y: 0.5)
        spot.endPoint = CGPoint(x: 1, y: 1)
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
        guard routine != self.routine || floor != self.floor || parts.isEmpty else { return }
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
        figures.forEach { $0.removeFromSuperlayer() }
        figures = []
        parts = []
        keylines = []
        let keyline = NotchDancer.keyline(floor)
        for dancer in dancers {
            let figure = CALayer()
            figure.frame = CGRect(x: 0, y: 0, width: floor.width, height: floor.height)
            figure.masksToBounds = false
            figure.shadowOffset = .zero
            figure.shadowRadius = Self.glowRadius * floor.scale
            figure.shadowOpacity = Self.glowOpacity
            // The keyline group fades as one, so where two parts' lines
            // cross they do not darken twice.
            let outline = CALayer()
            outline.frame = figure.bounds
            outline.opacity = Self.keylineOpacity
            outline.allowsGroupOpacity = true
            figure.addSublayer(outline)
            var shapes: [CAShapeLayer] = []
            var lines: [[CAShapeLayer]] = []
            for description in dancer.layers {
                let width = dancer.lineWidth(description, floor: floor)
                var partLines: [CAShapeLayer] = []
                if description.keyline {
                    let line = Self.shape(contentsScale)
                    line.strokeColor = NSColor.black.cgColor
                    line.lineWidth = (width ?? 0) + keyline * 2
                    line.fillColor = width == nil ? NSColor.black.cgColor : nil
                    outline.addSublayer(line)
                    partLines.append(line)
                }
                if description.keylineInFront {
                    // A fine ring over what lies behind, faded on its own:
                    // one ring, so nothing doubles up.
                    let ring = Self.shape(contentsScale)
                    ring.strokeColor = NSColor.black.cgColor
                    ring.fillColor = nil
                    ring.lineWidth = keyline * Self.ringShare * 2
                    ring.opacity = Self.ringOpacity
                    figure.addSublayer(ring)
                    partLines.append(ring)
                }
                lines.append(partLines)
                let shape = Self.shape(contentsScale)
                if let width {
                    shape.lineWidth = width
                    shape.fillColor = nil
                } else {
                    shape.lineWidth = 0
                    shape.strokeColor = nil
                }
                figure.addSublayer(shape)
                shapes.append(shape)
            }
            layer.addSublayer(figure)
            figures.append(figure)
            parts.append(shapes)
            keylines.append(lines)
        }
        // A dark pool behind the whole floor, and the spotlight at the feet.
        scrim.frame = CGRect(x: 0, y: 0, width: floor.width, height: floor.height)
        let spotWidth = min(Self.spotSize.width * floor.scale, floor.width)
        let spotHeight = Self.spotSize.height * floor.scale
        spot.frame = CGRect(x: (floor.width - spotWidth) / 2, y: floor.ground - spotHeight * 0.4,
                            width: spotWidth, height: spotHeight)
        if let paint { colour(paint, animated: false) }
        show(poses, duration: 0)
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
        parts.joined().forEach { $0.contentsScale = scale }
        keylines.joined().joined().forEach { $0.contentsScale = scale }
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
        for (index, (dancer, shapes)) in zip(dancers, parts).enumerated() {
            for (description, shape) in zip(dancer.layers, shapes) {
                let color = Self.color(description.paint, dancer: dancer, paint: paint)
                if dancer.lineWidth(description, floor: floor) == nil {
                    shape.fillColor = color
                } else {
                    shape.strokeColor = color
                }
            }
            figures[index].shadowColor = paint.accents[dancer.accent % paint.accents.count].cgColor
        }
        spot.colors = [paint.spot.cgColor, paint.spot.withAlphaComponent(0.45).cgColor,
                       paint.spot.withAlphaComponent(0).cgColor]
        spot.locations = [0, 0.45, 1]
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, dancer) in dancers.enumerated() {
            let paths = dancer.paths(poses[index], floor: floor)
            for (part, path) in paths.enumerated() {
                for shape in [parts[index][part]] + keylines[index][part] {
                    if duration > 0, let from = shape.presentation()?.path ?? shape.path {
                        let move = CABasicAnimation(keyPath: "path")
                        move.fromValue = from
                        move.toValue = path
                        move.duration = duration
                        move.timingFunction = curve
                        shape.add(move, forKey: "dance")
                    } else {
                        shape.removeAnimation(forKey: "dance")
                    }
                    shape.path = path
                }
            }
        }
        if duration <= 0 { spot.removeAnimation(forKey: "pulse") }
        CATransaction.commit()
        self.poses = poses
    }

    /// One dancer's answer to a beat, from wherever it is now: a quick
    /// ease-out into each key pose, then the settle the frames trace.
    func play(_ step: NotchDanceStep, dancer index: Int) {
        guard index < dancers.count, let floor, let last = step.frames.last, step.duration > 0 else { return }
        let dancer = dancers[index]
        let frames = step.frames.map { dancer.paths($0.pose, floor: floor) }
        let times = [NSNumber(value: 0)] + step.frames.map { NSNumber(value: $0.time / step.duration) }
        let curves = step.frames.map { frame -> CAMediaTimingFunction in
            switch frame.curve {
            case .attack: return CAMediaTimingFunction(name: .easeOut)
            case .glide: return CAMediaTimingFunction(name: .easeInEaseOut)
            case .settle: return CAMediaTimingFunction(name: .linear)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for part in parts[index].indices {
            for shape in [parts[index][part]] + keylines[index][part] {
                guard let from = shape.presentation()?.path ?? shape.path else { continue }
                let move = CAKeyframeAnimation(keyPath: "path")
                move.values = [from] + frames.map { $0[part] }
                move.keyTimes = times
                move.timingFunctions = curves
                move.duration = step.duration
                shape.path = frames[frames.count - 1][part]
                shape.add(move, forKey: "dance")
            }
        }
        CATransaction.commit()
        poses[index] = last.pose
    }

    /// The spotlight jumps with a beat and falls away before the next.
    func pulse(_ strength: CGFloat) {
        let share = Float(min(1, max(0, strength.isFinite ? strength : 0)))
        let peak = Self.spotRest + (Self.spotPeak - Self.spotRest) * share
        let swell = CAKeyframeAnimation(keyPath: "opacity")
        swell.values = [spot.presentation()?.opacity ?? spot.opacity, peak, Self.spotRest]
        swell.keyTimes = [0, NSNumber(value: Self.spotAttack / (Self.spotAttack + Self.spotDecay)), 1]
        swell.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        swell.duration = Self.spotAttack + Self.spotDecay
        spot.add(swell, forKey: "pulse")
    }

    /// Every running move ends where it was headed.
    func halt() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        parts.joined().forEach { $0.removeAnimation(forKey: "dance") }
        keylines.joined().joined().forEach { $0.removeAnimation(forKey: "dance") }
        spot.removeAnimation(forKey: "pulse")
        CATransaction.commit()
    }
}
