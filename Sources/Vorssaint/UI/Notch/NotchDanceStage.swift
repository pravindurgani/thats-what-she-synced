// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// What the dancers wear from the song: its accent colours for ties, rims,
/// collars, speaker cones and the floor's light, and the one fill every head
/// and hand shares. Outfits keep their own colours in every song.
struct NotchDancePaint: Equatable {
    var accents: [NSColor]
    var head: NSColor

    /// A warm light neutral: the same for every figure, never a skin tone.
    static let neutralHead = NSColor(srgbRed: 0.93, green: 0.91, blue: 0.87, alpha: 1)

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accents.map(\.cgColor) == rhs.accents.map(\.cgColor) && lhs.head.cgColor == rhs.head.cgColor
    }
}

/// The dancers' layers: one shape layer per drawn part of each figure, and
/// a soft light on the floor under them. It holds no timers; its view says
/// when to move, and every move is a Core Animation animation the render
/// server plays, from wherever the figures are when it starts.
final class NotchDanceStage {
    let layer = CALayer()
    private let glow = CAGradientLayer()
    private(set) var routine: NotchDanceRoutine?
    private(set) var poses: [NotchDancerPose] = []
    private var dancers: [NotchDancer] = []
    private var parts: [[CAShapeLayer]] = []
    private var floorHeight: CGFloat = 32
    private var paint: NotchDancePaint?
    private var contentsScale: CGFloat = 2

    /// The floor's light between beats, and how far a beat lifts it.
    private static let glowRest: Float = 0.42
    private static let glowLift: Float = 0.5

    init() {
        layer.masksToBounds = false
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.opacity = Self.glowRest
        layer.addSublayer(glow)
    }

    /// How long one dance takes to cross-fade into the next, as a new look
    /// does on the companion.
    static let danceChange: CFTimeInterval = 0.24

    /// Sets the dance on a floor `floorHeight` tall. A new dance or floor
    /// rebuilds the figures and stands them in `poses`. With `fades`, another
    /// dance cross-fades in over the last one rather than swapping figures in
    /// a single frame; the first dance, or the same one on a new floor, is
    /// simply there. A fade is no motion, so it plays under Reduce Motion too,
    /// as the colours' change does.
    func configure(routine: NotchDanceRoutine, floorHeight: CGFloat, poses: [NotchDancerPose],
                   contentsScale: CGFloat, fades: Bool = false) {
        guard routine != self.routine || floorHeight != self.floorHeight || parts.isEmpty else { return }
        let fade = fades && self.routine != nil && routine != self.routine
        self.routine = routine
        self.floorHeight = floorHeight
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
        parts.joined().forEach { $0.removeFromSuperlayer() }
        parts = dancers.map { dancer in
            dancer.layers.map { description in
                let shape = CAShapeLayer()
                shape.contentsScale = contentsScale
                shape.lineCap = .round
                shape.lineJoin = .round
                if let width = dancer.lineWidth(description, floorHeight: floorHeight) {
                    shape.lineWidth = width
                    shape.fillColor = nil
                } else {
                    shape.lineWidth = 0
                    shape.strokeColor = nil
                }
                layer.addSublayer(shape)
                return shape
            }
        }
        let ground = NotchDanceFloor.ground(height: floorHeight)
        let depth = 7 * NotchDanceFloor.scale(height: floorHeight)
        glow.frame = CGRect(x: 0, y: ground - depth / 2, width: NotchDanceFloor.width, height: depth)
        if let paint { colour(paint, animated: false) }
        show(poses, duration: 0)
    }

    func setContentsScale(_ scale: CGFloat) {
        guard scale != contentsScale else { return }
        contentsScale = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        parts.joined().forEach { $0.contentsScale = scale }
        glow.contentsScale = scale
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
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(NotchSongMotion.colorChange)
        CATransaction.setAnimationTimingFunction(NotchSongMotion.settleCurve)
        for (dancer, shapes) in zip(dancers, parts) {
            for (description, shape) in zip(dancer.layers, shapes) {
                let color = Self.color(description.paint, dancer: dancer, paint: paint)
                if dancer.lineWidth(description, floorHeight: floorHeight) == nil {
                    shape.fillColor = color
                } else {
                    shape.strokeColor = color
                }
            }
        }
        let light = paint.accents.first ?? .white
        glow.colors = [light.withAlphaComponent(0.75).cgColor, light.withAlphaComponent(0).cgColor]
        CATransaction.commit()
    }

    static func color(_ paint: NotchDancerLayer.Paint, dancer: NotchDancer, paint colors: NotchDancePaint) -> CGColor {
        switch paint {
        case .outfit(let hex):
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1).cgColor
        case .song(let offset):
            guard !colors.accents.isEmpty else { return NSColor.white.cgColor }
            return colors.accents[(dancer.accent + offset) % colors.accents.count].cgColor
        case .head:
            return colors.head.cgColor
        }
    }

    /// Stands every dancer in its pose, moving there from wherever it is
    /// over `duration`, or at once.
    func show(_ poses: [NotchDancerPose], duration: CFTimeInterval,
              curve: CAMediaTimingFunction = NotchSongMotion.settleCurve) {
        guard poses.count == dancers.count else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, dancer) in dancers.enumerated() {
            let paths = dancer.paths(poses[index], floorHeight: floorHeight)
            for (shape, path) in zip(parts[index], paths) {
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
        if duration <= 0 { glow.removeAnimation(forKey: "pulse") }
        CATransaction.commit()
        self.poses = poses
    }

    /// One dancer's answer to a beat, from wherever it is now: a quick
    /// ease-out into each key pose, then the settle the frames trace.
    func play(_ step: NotchDanceStep, dancer index: Int) {
        guard index < dancers.count, let last = step.frames.last, step.duration > 0 else { return }
        let dancer = dancers[index]
        let frames = step.frames.map { dancer.paths($0.pose, floorHeight: floorHeight) }
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
        for (part, shape) in parts[index].enumerated() {
            guard let from = shape.presentation()?.path ?? shape.path else { continue }
            let move = CAKeyframeAnimation(keyPath: "path")
            move.values = [from] + frames.map { $0[part] }
            move.keyTimes = times
            move.timingFunctions = curves
            move.duration = step.duration
            shape.path = frames[frames.count - 1][part]
            shape.add(move, forKey: "dance")
        }
        CATransaction.commit()
        poses[index] = last.pose
    }

    /// The floor's light swells with a beat and falls away with the settle.
    func pulse(_ strength: CGFloat) {
        let peak = Self.glowRest + Self.glowLift * Float(min(1, max(0, strength)))
        let swell = CAKeyframeAnimation(keyPath: "opacity")
        swell.values = [glow.presentation()?.opacity ?? glow.opacity, peak, Self.glowRest]
        swell.keyTimes = [0, NSNumber(value: NotchDanceTiming.attack / (NotchDanceTiming.attack + NotchSongMotion.beatReturn)), 1]
        swell.timingFunctions = [CAMediaTimingFunction(name: .easeOut), NotchSongMotion.settleCurve]
        swell.duration = NotchDanceTiming.attack + NotchSongMotion.beatReturn
        glow.add(swell, forKey: "pulse")
    }

    /// Every running move ends where it was headed.
    func halt() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        parts.joined().forEach { $0.removeAnimation(forKey: "dance") }
        glow.removeAnimation(forKey: "pulse")
        CATransaction.commit()
    }
}
