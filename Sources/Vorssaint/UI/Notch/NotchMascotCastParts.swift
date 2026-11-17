// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import QuartzCore

/// The cast's own parts inside the companion's rig, and what moves them.
/// The rig keeps its layers, its eyes and every face; this adds two stages
/// the whole figure rides on, between the squasher and the tilter, and the
/// member's drawing under the face. One stage plays the member's idle loop
/// and the other its reaction to a beat, so neither undoes the other or
/// anything the rig plays.
///
/// Idle loops are short episodes chained through Core Animation, as the
/// rig's blinks are: each begins a few seconds after the last ends, and
/// nothing runs in between. They play only while the rig idles, which it
/// does only while it can be seen, and never under Reduce Motion.
final class NotchMascotCastParts {
    /// The whole figure on the beat.
    let beatStage = CALayer()
    /// The whole figure in its idle loop.
    let idleStage = CALayer()
    /// The member's drawing, under the face.
    let drawing = CALayer()
    private(set) var member: NotchMascotStyle?
    var reduceMotion = false
    private var size: CGFloat = 0
    private var scale: CGFloat = 2
    private var idling = false
    private var idleRelay: NotchMascotCastRelay?
    /// Goldenface tilts to one side and then, next time, to the other.
    private var tiltSide: CGFloat = 1
    /// Which wisp of steam turns into a note on the next beat.
    private var nextNote = 0

    // The parts that move on their own.
    private var arms: [CALayer] = []
    private var glint: CALayer?
    private var rim: CALayer?
    private var steam = CALayer()
    private var wisps: [CAShapeLayer] = []
    private var notes: [CAShapeLayer] = []
    private var coffee: CALayer?
    private var tops: CALayer?
    private var leaves: [CALayer] = []

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "path": NSNull(), "opacity": NSNull(),
        "hidden": NSNull(), "contents": NSNull(), "colors": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(),
        "frame": NSNull(), "sublayers": NSNull(), "shadowColor": NSNull(), "shadowOpacity": NSNull(),
        "anchorPoint": NSNull(), "mask": NSNull(), "lineWidth": NSNull(),
    ]

    init() {
        for layer in [beatStage, idleStage, drawing] { layer.actions = Self.noActions }
    }

    /// The eyes each member wears: ink, and on the dark beet a light rim so
    /// they still read.
    var eyeStroke: (color: NotchMascotColor, width: CGFloat)? {
        member == .beet ? (NotchMascotCastColor.shirt, max(0.4, size * 0.024)) : nil
    }

    // MARK: Drawing

    /// Draws `look`'s member, already dealt, at `size`; anything else clears
    /// the drawing. Every part is drawn anew, which a configure does only
    /// when the look, the size or the scale changed.
    func configure(look: NotchMascotLook, size: CGFloat, contentsScale scale: CGFloat) {
        let member: NotchMascotStyle? = look.style.isCast ? look.style : nil
        stopIdling()
        self.member = member
        self.size = size
        self.scale = scale
        arms = []; glint = nil; rim = nil; wisps = []; notes = []; coffee = nil; tops = nil; leaves = []
        steam = CALayer()
        drawing.sublayers = nil
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        // The stages turn and squash about the figure's feet.
        let pivot = member.map { NotchMascotGeometry.castBounds($0, size: 1).maxY } ?? 0.5
        for layer in [beatStage, idleStage] {
            layer.removeAllAnimations()
            layer.bounds = box
            layer.anchorPoint = CGPoint(x: 0.5, y: min(1, max(0.5, pivot)))
            layer.position = CGPoint(x: size / 2, y: size * layer.anchorPoint.y)
            layer.transform = CATransform3DIdentity
            layer.contentsScale = scale
        }
        drawing.frame = box
        drawing.contentsScale = scale
        guard let member, size > 0 else { return }
        let tint = NotchMascotCastTint(look: look)
        switch member {
        case .scarn: drawScarn(look: look, tint: tint)
        case .goldenface: drawGoldenface(tint: tint)
        case .jello: drawJello(tint: tint)
        case .mug: drawMug(tint: tint)
        case .beet: drawBeet(tint: tint)
        case .minimal, .robot, .shuffle: break
        }
        if idling { scheduleIdle(after: 0.6) }
    }

    private func layer<T: CALayer>(_ layer: T, in parent: CALayer) -> T {
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.contentsScale = scale
        layer.actions = Self.noActions
        parent.addSublayer(layer)
        return layer
    }

    @discardableResult
    private func shape(_ path: CGPath, fill: NotchMascotColor?, stroke: NotchMascotColor? = nil, width: CGFloat = 0,
                       in parent: CALayer) -> CAShapeLayer {
        let shape = layer(CAShapeLayer(), in: parent)
        shape.path = path
        shape.fillColor = fill?.cgColor
        shape.strokeColor = stroke?.cgColor
        shape.lineWidth = width
        shape.lineCap = .round
        shape.lineJoin = .round
        return shape
    }

    /// A container showing only what lies inside `path`.
    private func clip(_ path: CGPath, in parent: CALayer) -> CALayer {
        let container = layer(CALayer(), in: parent)
        let mask = CAShapeLayer()
        mask.path = path
        mask.frame = container.bounds
        mask.contentsScale = scale
        mask.actions = Self.noActions
        container.mask = mask
        return container
    }

    @discardableResult
    private func gradient(_ colors: [NotchMascotColor], from start: CGPoint, to end: CGPoint, locations: [Double]? = nil,
                          in parent: CALayer) -> CAGradientLayer {
        let fill = layer(CAGradientLayer(), in: parent)
        fill.colors = colors.map(\.cgColor)
        fill.locations = locations?.map { NSNumber(value: $0) }
        fill.startPoint = start
        fill.endPoint = end
        return fill
    }

    /// A container that turns about `pivot`, in points.
    private func pivoting(at pivot: CGPoint, in parent: CALayer) -> CALayer {
        let container = layer(CALayer(), in: parent)
        container.anchorPoint = CGPoint(x: pivot.x / size, y: pivot.y / size)
        container.position = pivot
        return container
    }

    /// A soft song glow around `path`, drawn by a shadow with a set path, so
    /// it costs no offscreen pass.
    private func glow(_ path: CGPath, color: NotchMascotColor?, in parent: CALayer) {
        guard let color else { return }
        let halo = shape(path, fill: color, in: parent)
        halo.shadowPath = path
        halo.shadowColor = color.cgColor
        halo.shadowOpacity = 0.9
        halo.shadowRadius = max(1, size * 0.1)
        halo.shadowOffset = .zero
    }

    /// Agent Scarn: the suit stays dark; the song goes on his tie and the
    /// rim-light along his lapels and jacket.
    private func drawScarn(look: NotchMascotLook, tint: NotchMascotCastTint) {
        let parts = NotchMascotGeometry.scarn(size: size)
        let skin = look.palette
        // Soft at rest, just enough to set the dark suit off the black island.
        let rimAlpha: CGFloat = look.song == nil ? 0.32 : 0.95
        // Arms behind the body: at rest only the hands show at its sides.
        for (arm, hand, shoulder) in [(parts.leftArm, parts.leftHand, parts.leftShoulder),
                                      (parts.rightArm, parts.rightHand, parts.rightShoulder)] {
            let holder = pivoting(at: shoulder, in: drawing)
            shape(arm, fill: NotchMascotCastColor.suit, stroke: tint.rim.with(alpha: rimAlpha * 0.8),
                  width: size * 0.035, in: holder)
            shape(hand, fill: skin.light, in: holder)
            arms.append(holder)
        }
        let figure = clip(parts.body, in: drawing)
        gradient([skin.light, skin.shade], from: CGPoint(x: 0.5, y: 0), to: CGPoint(x: 0.5, y: 1), in: figure)
        shape(NotchMascotGeometry.shine(NotchMascotGeometry.castFace(.scarn), size: size), fill: NotchMascotColor.shine,
              in: figure)
        shape(parts.suit, fill: NotchMascotCastColor.suit, in: figure)
        // The rim-light along the jacket's edge: the body's outline, kept
        // inside the body and below the collar.
        let jacketRim = clip(parts.suit, in: figure)
        rim = shape(parts.body, fill: nil, stroke: tint.rim.with(alpha: rimAlpha), width: size * 0.09, in: jacketRim)
        shape(parts.shirt, fill: NotchMascotCastColor.shirt, in: figure)
        shape(parts.tie, fill: tint.accent, in: figure)
        shape(parts.lapels, fill: nil, stroke: tint.rim.with(alpha: rimAlpha), width: size * 0.035, in: figure)
    }

    /// Goldenface: the face stays gold; the song tints the rim-light on his
    /// black clothes and the glint that crosses his face on the beat.
    private func drawGoldenface(tint: NotchMascotCastTint) {
        let parts = NotchMascotGeometry.goldenface(size: size)
        shape(parts.clothes, fill: NotchMascotCastColor.blackClothes, in: drawing)
        let clothesRim = clip(parts.clothes, in: drawing)
        rim = shape(parts.clothes, fill: nil, stroke: tint.rim.with(alpha: tint.glow == nil ? 0.55 : 0.95),
                    width: size * 0.08, in: clothesRim)
        shape(parts.lapels, fill: nil, stroke: NotchMascotCastColor.lapel, width: size * 0.035, in: drawing)
        let face = clip(parts.head, in: drawing)
        gradient([NotchMascotCastColor.goldLight, NotchMascotCastColor.gold, NotchMascotCastColor.goldDeep],
                 from: CGPoint(x: 0.25, y: 0.05), to: CGPoint(x: 0.8, y: 0.75), locations: [0, 0.5, 1], in: face)
        shape(parts.highlight, fill: NotchMascotCastColor.goldLight.mixed(with: NotchMascotColor(red: 1, green: 1, blue: 1),
                                                                          0.45), in: face)
        // The glint: a bright band leaning across, waiting left of the face.
        let band = layer(CAGradientLayer(), in: face)
        let shine = NotchMascotColor(red: 1, green: 1, blue: 1).mixed(with: tint.rim, tint.glow == nil ? 0.15 : 0.4)
        band.colors = [shine.with(alpha: 0), shine.with(alpha: 0.95), shine.with(alpha: 0)].map(\.cgColor)
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        band.frame = parts.glint
        band.transform = CATransform3DMakeRotation(0.4, 0, 0, 1)
        band.opacity = 0
        glint = band
    }

    /// The Jell-O Stapler: a see-through yellow block, the stapler dark
    /// inside it. A song lays its colour over the yellow at 35%.
    private func drawJello(tint: NotchMascotCastTint) {
        let parts = NotchMascotGeometry.jello(size: size)
        // See-through, but no more than keeps it Jell-O yellow over the black
        // island: two thirds opaque reads as olive there.
        shape(parts.side, fill: NotchMascotCastColor.jelloSide.with(alpha: 0.86), in: drawing)
        shape(parts.top, fill: NotchMascotCastColor.jelloTop.with(alpha: 0.92), in: drawing)
        let front = clip(parts.front, in: drawing)
        gradient([NotchMascotCastColor.jelloTop.with(alpha: 0.9), NotchMascotCastColor.jello.with(alpha: 0.84),
                  NotchMascotCastColor.jelloSide.with(alpha: 0.82)],
                 from: CGPoint(x: 0.3, y: 0.35), to: CGPoint(x: 0.6, y: 0.95), in: front)
        // The stapler, seen through the jelly in front of it, its top edge
        // catching the light.
        shape(parts.stapler, fill: NotchMascotCastColor.stapler, in: front)
        shape(parts.staplerEdge, fill: nil, stroke: NotchMascotCastColor.staplerEdge, width: size * 0.025, in: front)
        shape(parts.front, fill: NotchMascotCastColor.jello.with(alpha: 0.2), in: front)
        // The song over the yellow at 35%, blended softly so yellow stays on top.
        if let wash = tint.wash {
            let over = shape(parts.block, fill: wash, in: drawing)
            over.compositingFilter = "softLightBlendMode"
        }
        shape(parts.highlight, fill: NotchMascotColor(red: 1, green: 1, blue: 1, alpha: 0.75), in: drawing)
    }

    /// The Best Boss Mug: white with black bars, always. The song goes on
    /// the steam, the coffee and a glow around the mug.
    private func drawMug(tint: NotchMascotCastTint) {
        let parts = NotchMascotGeometry.mug(size: size)
        glow(parts.body, color: tint.glow, in: drawing)
        shape(parts.handle, fill: nil, stroke: NotchMascotCastColor.mug.mixed(with: NotchMascotCastColor.mugShade, 0.3),
              width: parts.handleWidth, in: drawing)
        let body = clip(parts.body, in: drawing)
        gradient([NotchMascotColor(red: 1, green: 1, blue: 1), NotchMascotCastColor.mug, NotchMascotCastColor.mugShade],
                 from: CGPoint(x: 0.1, y: 0.5), to: CGPoint(x: 0.7, y: 0.5), locations: [0, 0.45, 1], in: body)
        shape(parts.bars, fill: NotchMascotCastColor.print, in: drawing)
        shape(parts.rim, fill: NotchMascotColor(red: 1, green: 1, blue: 1), in: drawing)
        let well = clip(parts.rim, in: drawing)
        let surface = pivoting(at: parts.coffeeCenter, in: well)
        let brew = tint.glow == nil ? NotchMascotCastColor.coffee : NotchMascotCastColor.coffee.mixed(with: tint.accent, 0.4)
        shape(parts.coffee, fill: brew, in: surface)
        coffee = surface
        steam = layer(CALayer(), in: drawing)
        for wisp in parts.steam {
            let line = shape(wisp, fill: nil, stroke: tint.glow == nil ? NotchMascotCastColor.steam : tint.rim,
                             width: parts.steamWidth, in: steam)
            line.opacity = 0
            wisps.append(line)
        }
        for note in parts.notes {
            let mark = shape(note, fill: tint.rim, in: drawing)
            mark.opacity = 0
            notes.append(mark)
        }
    }

    /// The Schrute Beet: beet-coloured always. The song goes on the leaves'
    /// rim-light and a glow around the bulb.
    private func drawBeet(tint: NotchMascotCastTint) {
        let parts = NotchMascotGeometry.beet(size: size)
        let crown = pivoting(at: parts.crown, in: drawing)
        for stem in parts.stems {
            shape(stem, fill: nil, stroke: NotchMascotCastColor.stem, width: parts.stemWidth, in: crown)
        }
        let rimColor = tint.glow == nil ? NotchMascotCastColor.leafLight.mixed(with: tint.rim, 0.35) : tint.rim
        for (index, leaf) in parts.leaves.enumerated() {
            let holder = pivoting(at: parts.leafBases[index], in: crown)
            shape(leaf, fill: NotchMascotCastColor.leaf, stroke: rimColor.with(alpha: tint.glow == nil ? 0.6 : 0.95),
                  width: size * 0.03, in: holder)
            shape(parts.veins[index], fill: nil, stroke: NotchMascotCastColor.stem, width: size * 0.02, in: holder)
            leaves.append(holder)
        }
        tops = crown
        glow(parts.bulb, color: tint.glow, in: drawing)
        shape(parts.tail, fill: NotchMascotCastColor.beet, in: drawing)
        let bulb = clip(parts.bulb, in: drawing)
        gradient([NotchMascotCastColor.beetLight, NotchMascotCastColor.beet, NotchMascotCastColor.beetDeep],
                 from: CGPoint(x: 0.25, y: 0.35), to: CGPoint(x: 0.75, y: 0.95), locations: [0, 0.5, 1], in: bulb)
        shape(parts.highlight, fill: NotchMascotCastColor.beetLight.mixed(with: NotchMascotColor(red: 1, green: 1, blue: 1),
                                                                          0.35).with(alpha: 0.85), in: bulb)
    }

    // MARK: Idle loops

    /// Plays the member's idle loop while `on`, from a moment from now.
    func setIdling(_ on: Bool) {
        guard on != idling else { return }
        idling = on
        if on { scheduleIdle(after: Double.random(in: 0.4...1.6)) } else { stopIdling() }
    }

    private func stopIdling() {
        idleRelay?.target = nil
        idleRelay = nil
        for layer in movingParts { layer.removeAnimation(forKey: "castIdle") }
    }

    /// Slow motions need no more than 30 frames a second.
    private static let slowRate = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)

    /// One episode of the member's idle loop, `gap` seconds from now, and the
    /// next one queued as it ends.
    private func scheduleIdle(after gap: TimeInterval) {
        guard idling, !reduceMotion, let member, size > 0 else { return }
        let begin = CACurrentMediaTime() + gap
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        // The animation that ends last carries the relay that queues the next.
        func play(_ animation: CAAnimation, on layer: CALayer, carries: Bool = false) {
            animation.beginTime = begin + animation.beginTime
            if carries {
                let relay = NotchMascotCastRelay(target: self)
                idleRelay = relay
                animation.delegate = relay
            }
            layer.add(animation, forKey: "castIdle")
        }
        switch member {
        case .scarn:
            // A gentle sway from the feet, side to side and back.
            let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            sway.values = [0, 0.055, -0.05, 0.035, 0]
            sway.keyTimes = [0, 0.25, 0.55, 0.8, 1]
            sway.timingFunctions = Array(repeating: ease, count: 4)
            sway.duration = 3.4
            sway.preferredFrameRateRange = Self.slowRate
            play(sway, on: idleStage, carries: true)
        case .goldenface:
            // A slow, menacing tilt to one side, held, and back.
            let tilt = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            tilt.values = [0, 0.1 * tiltSide, 0.1 * tiltSide, 0]
            tilt.keyTimes = [0, 0.38, 0.7, 1]
            tilt.timingFunctions = Array(repeating: ease, count: 3)
            tilt.duration = 4.4
            tilt.preferredFrameRateRange = Self.slowRate
            tiltSide = -tiltSide
            play(tilt, on: idleStage, carries: true)
        case .jello:
            // A soft wobble, the top swinging over its base.
            let wobble = CAKeyframeAnimation(keyPath: "transform")
            wobble.values = [(0, 1, 1), (0.09, 0.97, 1.02), (-0.07, 1.02, 0.98), (0.04, 0.99, 1.01), (-0.015, 1, 1),
                             (0, 1, 1)].map { NSValue(caTransform3D: Self.jiggle(shear: $0.0, x: $0.1, y: $0.2)) }
            wobble.keyTimes = [0, 0.18, 0.4, 0.62, 0.82, 1]
            wobble.timingFunctions = Array(repeating: ease, count: 5)
            wobble.duration = 1.1
            play(wobble, on: idleStage, carries: true)
        case .mug:
            // Two or three wisps curl up from the coffee and thin away.
            for (index, wisp) in wisps.enumerated() {
                let draw = CAKeyframeAnimation(keyPath: "strokeEnd")
                draw.values = [0, 1, 1]
                draw.keyTimes = [0, 0.55, 1]
                let thin = CAKeyframeAnimation(keyPath: "strokeStart")
                thin.values = [0, 0, 1]
                thin.keyTimes = [0, 0.45, 1]
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [0, 0.9, 0.7, 0]
                fade.keyTimes = [0, 0.25, 0.7, 1]
                let rise = CABasicAnimation(keyPath: "transform.translation.y")
                rise.fromValue = 0
                rise.toValue = -size * 0.08
                let puff = CAAnimationGroup()
                puff.animations = [draw, thin, fade, rise]
                puff.duration = 2.1
                puff.timingFunction = ease
                puff.beginTime = Double(index) * 0.32
                puff.preferredFrameRateRange = Self.slowRate
                play(puff, on: wisp, carries: index == wisps.count - 1)
            }
        case .beet:
            // The tops sway about the crown, each leaf a little on its own.
            let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            sway.values = [0, 0.08, -0.06, 0.04, 0]
            sway.keyTimes = [0, 0.27, 0.55, 0.8, 1]
            sway.timingFunctions = Array(repeating: ease, count: 4)
            sway.duration = 3
            sway.preferredFrameRateRange = Self.slowRate
            play(sway, on: tops ?? drawing, carries: true)
            for (index, leaf) in leaves.enumerated() {
                let flutter = CAKeyframeAnimation(keyPath: "transform.rotation.z")
                let way: CGFloat = index % 2 == 0 ? 1 : -1
                flutter.values = [0, 0.12 * way, -0.08 * way, 0]
                flutter.keyTimes = [0, 0.35, 0.7, 1]
                flutter.timingFunctions = Array(repeating: ease, count: 3)
                flutter.duration = 2.6
                flutter.beginTime = 0.15 * Double(index)
                flutter.preferredFrameRateRange = Self.slowRate
                play(flutter, on: leaf)
            }
        case .minimal, .robot, .shuffle:
            return
        }
    }

    /// The next episode waits a few seconds after this one; the mug's steam
    /// comes every six to eight.
    fileprivate func idleDidStop(finished: Bool, relay: NotchMascotCastRelay) {
        guard finished, relay === idleRelay, idling else { return }
        idleRelay = nil
        let gap: ClosedRange<TimeInterval>
        switch member {
        case .scarn: gap = 1.2...3.2
        case .goldenface: gap = 1.8...4
        case .jello: gap = 2.2...4.2
        // The puffs take about three seconds, so one starts every six to eight.
        case .mug: gap = 3.2...5.2
        case .beet: gap = 1...2.6
        default: return
        }
        scheduleIdle(after: Double.random(in: gap))
    }

    // MARK: The beat

    /// The member's move for a beat onset of `strength`, 0 to 1, toward
    /// `side`: positive to the right. Each move starts from where the last
    /// one has the figure, so a quick beat never makes it jump.
    func beat(strength: CGFloat, side: CGFloat) {
        guard let member, !reduceMotion, size > 0 else { return }
        let push = 0.55 + 0.45 * min(1, max(0, strength))
        let way: CGFloat = side >= 0 ? 1 : -1
        switch member {
        case .scarn:
            // The Scarn: a hop to one side with a hand out to shake, then the
            // other side on the next beat.
            let reach = size * 0.12 * push * way, lift = size * 0.1 * push
            move(beatStage, [Self.at(x: reach, y: -lift), Self.at(x: reach, y: 0, squash: 0.06),
                             Self.at(x: reach * 0.4, y: 0), CATransform3DIdentity],
                 times: [0.28, 0.45, 0.72, 1], duration: 0.62)
            // The left arm reaches out by turning clockwise, the right the other way.
            let arm = way < 0 ? arms.first : arms.last
            let out: CGFloat = way < 0 ? 1 : -1
            let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            shake.values = [0, 1.4, 1.14, 1.44, 1.18, 0].map { $0 * out }
            shake.keyTimes = [0, 0.22, 0.38, 0.52, 0.68, 1]
            shake.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shake.duration = 0.62
            arm?.add(shake, forKey: "castBeat")
        case .goldenface:
            // A gold glint sweeps across the face.
            if let glint {
                let sweep = CABasicAnimation(keyPath: "transform.translation.x")
                sweep.fromValue = 0
                sweep.toValue = NotchMascotGeometry.goldenface(size: size).glintTravel
                sweep.isAdditive = true
                let shine = CAKeyframeAnimation(keyPath: "opacity")
                shine.values = [0, 1, 1, 0]
                shine.keyTimes = [0, 0.2, 0.7, 1]
                let pass = CAAnimationGroup()
                pass.animations = [sweep, shine]
                pass.duration = 0.48
                pass.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                glint.add(pass, forKey: "castBeat")
            }
            if let rim {
                let flare = CAKeyframeAnimation(keyPath: "opacity")
                flare.values = [1, 0.4, 1]
                flare.keyTimes = [0, 0.3, 1]
                flare.duration = 0.45
                rim.add(flare, forKey: "castBeat")
            }
            move(beatStage, [Self.at(x: 0, y: 0, scale: 1 + 0.04 * push), CATransform3DIdentity],
                 times: [0.35, 1], duration: 0.36)
        case .jello:
            // Squash and stretch, the top skewing one way and back: a jiggle.
            let amount = push
            move(beatStage, [Self.jiggle(shear: 0, x: 1 + 0.14 * amount, y: 1 - 0.14 * amount),
                             Self.jiggle(shear: 0.07 * amount * way, x: 1 - 0.1 * amount, y: 1 + 0.12 * amount),
                             Self.jiggle(shear: -0.05 * amount * way, x: 1 + 0.06 * amount, y: 1 - 0.05 * amount),
                             Self.jiggle(shear: 0.02 * amount * way, x: 1 - 0.02 * amount, y: 1 + 0.02 * amount),
                             CATransform3DIdentity],
                 times: [0.14, 0.34, 0.55, 0.78, 1], duration: 0.55)
        case .mug:
            // A hop, the coffee sloshing, and a wisp of steam turned into a note.
            move(beatStage, [Self.at(x: 0, y: -size * 0.13 * push, squash: -0.05),
                             Self.at(x: 0, y: 0, squash: 0.07), Self.at(x: 0, y: 0, squash: -0.02),
                             CATransform3DIdentity],
                 times: [0.3, 0.55, 0.75, 1], duration: 0.48)
            if let coffee {
                let slosh = CAKeyframeAnimation(keyPath: "transform.rotation.z")
                slosh.values = [0, 0.3 * way, -0.18 * way, 0.07 * way, 0]
                slosh.keyTimes = [0, 0.2, 0.45, 0.72, 1]
                slosh.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                slosh.duration = 0.62
                coffee.add(slosh, forKey: "castBeat")
            }
            guard !notes.isEmpty else { return }
            let note = notes[nextNote % notes.count]
            nextNote += 1
            let show = CAKeyframeAnimation(keyPath: "opacity")
            show.values = [0, 1, 1, 0]
            show.keyTimes = [0, 0.15, 0.6, 1]
            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = size * 0.04
            rise.toValue = -size * 0.08
            let float = CAAnimationGroup()
            float.animations = [show, rise]
            float.duration = 0.8
            float.timingFunction = CAMediaTimingFunction(name: .easeOut)
            note.add(float, forKey: "castBeat")
            let clear = CAKeyframeAnimation(keyPath: "opacity")
            clear.values = [1, 0, 0, 1]
            clear.keyTimes = [0, 0.12, 0.8, 1]
            clear.duration = 0.8
            steam.add(clear, forKey: "castBeat")
        case .beet:
            // The leaves flick and the bulb bounces.
            if let tops {
                let flick = CAKeyframeAnimation(keyPath: "transform.rotation.z")
                flick.values = [0, 0.32 * push * way, -0.14 * push * way, 0.05 * push * way, 0]
                flick.keyTimes = [0, 0.18, 0.45, 0.72, 1]
                flick.timingFunction = CAMediaTimingFunction(name: .easeOut)
                flick.isAdditive = true
                flick.duration = 0.52
                tops.add(flick, forKey: "castBeat")
            }
            move(beatStage, [Self.at(x: 0, y: -size * 0.09 * push, squash: -0.05),
                             Self.at(x: 0, y: 0, squash: 0.08), Self.at(x: 0, y: 0, squash: -0.02),
                             CATransform3DIdentity],
                 times: [0.3, 0.55, 0.78, 1], duration: 0.46)
        case .minimal, .robot, .shuffle:
            break
        }
    }

    /// Takes off every move the cast plays, as the rig resets.
    func stopMoving() {
        for layer in movingParts { layer.removeAnimation(forKey: "castBeat") }
        stopIdling()
        if idling { scheduleIdle(after: 1) }
    }

    /// Every layer an idle loop or a beat moves.
    private var movingParts: [CALayer] {
        var parts: [CALayer] = [beatStage, idleStage, steam]
        parts += [coffee, tops, glint, rim].compactMap { $0 }
        parts += arms
        parts += wisps as [CALayer]
        parts += notes as [CALayer]
        parts += leaves
        return parts
    }

    /// Plays `frames` on `layer` from where it shows now, at `times` after
    /// the start, and leaves it where it was.
    private func move(_ layer: CALayer, _ frames: [CATransform3D], times: [Double], duration: TimeInterval) {
        let move = CAKeyframeAnimation(keyPath: "transform")
        move.values = ([layer.presentation()?.transform ?? layer.transform] + frames).map { NSValue(caTransform3D: $0) }
        move.keyTimes = ([0] + times).map { NSNumber(value: $0) }
        move.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: frames.count)
        move.duration = duration
        layer.add(move, forKey: "castBeat")
    }

    /// Moved by `x` and `y` points, grown by `scale`, and squashed by
    /// `squash`: positive flattens, negative stretches.
    private static func at(x: CGFloat, y: CGFloat, scale: CGFloat = 1, squash: CGFloat = 0) -> CATransform3D {
        let move = CATransform3DMakeTranslation(x, y, 0)
        return CATransform3DConcat(CATransform3DMakeScale(scale * (1 + squash * 0.8), scale * (1 - squash), 1), move)
    }

    /// Scaled and skewed about the stage's anchor, the figure's feet.
    private static func jiggle(shear: CGFloat, x: CGFloat, y: CGFloat) -> CATransform3D {
        var transform = CATransform3DMakeScale(x, y, 1)
        transform.m21 = shear
        return transform
    }
}

/// Keeps only a weak reference to the parts, as the rig's blink relay does,
/// so a companion taken off screen is let go with an episode pending.
private final class NotchMascotCastRelay: NSObject, CAAnimationDelegate {
    weak var target: NotchMascotCastParts?

    init(target: NotchMascotCastParts) { self.target = target }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        target?.idleDidStop(finished: flag, relay: self)
    }
}
