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
/// The idle motion comes in short bursts chained through Core Animation, as
/// the rig's blinks are: a sway, a wobble, a tilt and a glint, a puff of
/// steam or a flutter of leaves, about two seconds long, eased in from rest
/// and back to it, starting every eight to twelve seconds. In between the
/// member stands still with nothing running but its blinks. Bursts play only
/// while the rig idles, which it does only while it can be seen and awake,
/// and never under Reduce Motion or in Low Power Mode.
///
/// The parts that move on their own, Scarn's arms, the Beet's tops, the
/// Mug's steam and notes and Goldenface's glint, sit apart from the rest of
/// the figure, behind it or in front, as they are drawn. The rest holds
/// still within itself, so while the member idles it is drawn once into a
/// bitmap the render server moves with the stages (see syncStill), rather
/// than every mask, gradient and glow of it drawn again on each frame.
final class NotchMascotCastParts {
    /// The whole figure on the beat.
    let beatStage = CALayer()
    /// The whole figure in its idle loop.
    let idleStage = CALayer()
    /// Parts that move on their own behind the figure: Scarn's arms, the Beet's tops.
    let underlay = CALayer()
    /// The member's drawing, under the face.
    let drawing = CALayer()
    /// Parts that move on their own in front of the figure: the Mug's steam
    /// and notes, Goldenface's glint.
    let overlay = CALayer()
    private(set) var member: NotchMascotStyle?
    var reduceMotion = false
    private var size: CGFloat = 0
    private var scale: CGFloat = 2
    private var idling = false
    private var idleRelay: NotchMascotCastRelay?
    /// How long the last burst ran, so the next starts a period after it began.
    private var lastBurst: TimeInterval = 0
    /// Each burst leans the other way to the last: Goldenface's tilt,
    /// Scarn's sway, the Jello's wobble and the Beet's tops.
    private var burstSide: CGFloat = 1
    /// Which wisp of steam turns into a note on the next beat.
    private var nextNote = 0

    // The parts that move on their own.
    private var arms: [CALayer] = []
    /// Goldenface's glint, and the face-shaped window in front of the figure
    /// it crosses, which shows only while it does.
    private var glint: CALayer?
    private var sheen: CALayer?
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

    /// When a beat last moved a part inside the still figure: Goldenface's
    /// glint or rim, or the Mug's coffee.
    private var partBeat: CFTimeInterval = -.infinity

    init() {
        for layer in [beatStage, idleStage, underlay, drawing, overlay] { layer.actions = Self.noActions }
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
        arms = []; glint = nil; sheen = nil; rim = nil; wisps = []; notes = []; coffee = nil; tops = nil; leaves = []
        steam = CALayer()
        for layer in [underlay, drawing, overlay] { layer.sublayers = nil }
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
        for layer in [underlay, drawing, overlay] {
            layer.frame = box
            layer.contentsScale = scale
        }
        syncStill()
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

    /// Agent Scarn: the suit stays dark and the head paper-white; the song
    /// goes on his tie and the rim-light along his lapels and jacket.
    private func drawScarn(look: NotchMascotLook, tint: NotchMascotCastTint) {
        let parts = NotchMascotGeometry.scarn(size: size)
        // Soft at rest, just enough to set the dark suit off the black island.
        let rimAlpha: CGFloat = look.song == nil ? 0.32 : 0.95
        // Arms behind the jacket, out of sight until one reaches out.
        for (arm, hand, shoulder) in [(parts.leftArm, parts.leftHand, parts.leftShoulder),
                                      (parts.rightArm, parts.rightHand, parts.rightShoulder)] {
            let holder = pivoting(at: shoulder, in: underlay)
            shape(arm, fill: NotchMascotCastColor.suit, stroke: tint.rim.with(alpha: rimAlpha * 0.8),
                  width: size * 0.035, in: holder)
            shape(hand, fill: NotchMascotCastColor.paper, in: holder)
            arms.append(holder)
        }
        shape(parts.suit, fill: NotchMascotCastColor.suit, in: drawing)
        // The rim-light along the jacket's edge, kept inside it.
        let jacketRim = clip(parts.suit, in: drawing)
        rim = shape(parts.suit, fill: nil, stroke: tint.rim.with(alpha: rimAlpha), width: size * 0.08, in: jacketRim)
        shape(parts.shirt, fill: NotchMascotCastColor.shirt, in: drawing)
        shape(parts.lapels, fill: nil, stroke: tint.rim.with(alpha: rimAlpha), width: size * 0.035, in: drawing)
        shape(parts.collar, fill: NotchMascotCastColor.shirt, stroke: NotchMascotCastColor.collarEdge,
              width: size * 0.02, in: drawing)
        shape(parts.tie, fill: tint.accent, in: drawing)
        // The head on the collar, outlined in the suit's dark so the chin
        // stands off the white shirt below it.
        let head = clip(parts.head, in: drawing)
        gradient([NotchMascotCastColor.paper, NotchMascotCastColor.paperShade],
                 from: CGPoint(x: 0.35, y: 0.1), to: CGPoint(x: 0.6, y: 0.65), in: head)
        shape(parts.highlight, fill: NotchMascotColor.shine, in: head)
        shape(parts.head, fill: nil, stroke: NotchMascotCastColor.suit, width: size * 0.035, in: drawing)
    }

    /// Goldenface: the face stays gold; the song tints the rim-light on his
    /// black clothes and the glint that crosses his face, now and then at
    /// rest and on the beat.
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
        // The glint: a bright band leaning across, waiting left of the face,
        // in a window the face's shape in front of the still figure, so it
        // crosses without the figure being drawn again. The window shows
        // only while it crosses; otherwise it is left out of every frame.
        let window = clip(parts.head, in: overlay)
        window.opacity = 0
        let band = layer(CAGradientLayer(), in: window)
        let shine = NotchMascotColor(red: 1, green: 1, blue: 1).mixed(with: tint.rim, tint.glow == nil ? 0.15 : 0.4)
        band.colors = [shine.with(alpha: 0), shine.with(alpha: 0.95), shine.with(alpha: 0)].map(\.cgColor)
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        band.frame = parts.glint
        band.transform = CATransform3DMakeRotation(0.4, 0, 0, 1)
        glint = band
        sheen = window
    }

    /// The glint sweeping once across Goldenface's face over `duration`,
    /// `delay` seconds into whatever plays it, on `curve` at `rate`.
    private func glintPass(duration: CFTimeInterval, delay: CFTimeInterval = 0,
                           curve: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut),
                           rate: CAFrameRateRange) -> (band: CAAnimation, window: CAAnimation)? {
        guard glint != nil, sheen != nil else { return nil }
        let sweep = CABasicAnimation(keyPath: "transform.translation.x")
        sweep.fromValue = 0
        sweep.toValue = NotchMascotGeometry.goldenface(size: size).glintTravel
        sweep.isAdditive = true
        sweep.duration = duration
        sweep.timingFunction = curve
        sweep.beginTime = delay
        sweep.preferredFrameRateRange = rate
        let shine = CAKeyframeAnimation(keyPath: "opacity")
        shine.values = [0, 1, 1, 0]
        shine.keyTimes = [0, 0.2, 0.7, 1]
        shine.duration = duration
        shine.timingFunction = curve
        shine.beginTime = delay
        shine.preferredFrameRateRange = rate
        return (sweep, shine)
    }

    /// The Jelly Stapler: a see-through yellow block, the stapler dark
    /// inside it. A song lays its colour over the yellow at 35%.
    private func drawJello(tint: NotchMascotCastTint) {
        let parts = NotchMascotGeometry.jello(size: size)
        // See-through, but no more than keeps it jelly yellow over the black
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
        steam = layer(CALayer(), in: overlay)
        for wisp in parts.steam {
            let line = shape(wisp, fill: nil, stroke: tint.glow == nil ? NotchMascotCastColor.steam : tint.rim,
                             width: parts.steamWidth, in: steam)
            line.opacity = 0
            wisps.append(line)
        }
        for note in parts.notes {
            let mark = shape(note, fill: tint.rim, in: overlay)
            mark.opacity = 0
            notes.append(mark)
        }
    }

    /// The Schrute Beet: beet-coloured always. The song goes on the leaves'
    /// rim-light and a glow around the bulb.
    private func drawBeet(tint: NotchMascotCastTint) {
        let parts = NotchMascotGeometry.beet(size: size)
        let crown = pivoting(at: parts.crown, in: underlay)
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

    // MARK: Idle bursts

    /// Plays the member's idle bursts while `on`, the first a moment from now.
    func setIdling(_ on: Bool) {
        guard on != idling else { return }
        idling = on
        syncStill()
        if on { scheduleIdle(after: Double.random(in: 0.4...1.6)) } else { stopIdling() }
    }

    private func stopIdling() {
        idleRelay?.target = nil
        idleRelay = nil
        for layer in movingParts { layer.removeAnimation(forKey: "castIdle") }
    }

    /// A burst's sways, tilts, wisps and leaves move a few degrees, or a
    /// point or two, over a second or more: 15 frames a second steps each
    /// well under a pixel, at half the compositing of 30. What crosses
    /// quicker, Goldenface's glint and the Jello's wobble, asks for 30.
    private static let gentleRate = NotchSongMotion.gentleFrames
    private static let quickRate = NotchSongMotion.slowFrames

    /// How long one burst of idle motion lasts, and how often one starts,
    /// start to start: alive, without a frame drawn between them.
    static let burstLength: ClosedRange<TimeInterval> = 1.5...2.5
    static let burstPeriod: ClosedRange<TimeInterval> = 8...12

    /// The rest between the end of a burst `length` seconds long and the
    /// start of the next, so they start eight to twelve seconds apart.
    static func restAfter(burst length: TimeInterval) -> TimeInterval {
        max(burstPeriod.lowerBound - burstLength.upperBound, Double.random(in: burstPeriod) - length)
    }

    /// A beat inside the figure draws it live until the beats have paused this long.
    static let stillAfterBeat: CFTimeInterval = 1.5

    /// Whether the still figure is drawn once and moved as a bitmap: while
    /// the member idles, unless a beat has just moved a part inside it. At
    /// twice the display's scale, so its edges stay as fine as drawn ones
    /// while the stages turn and squash it; between bursts, at rest, it is
    /// the same figure. Each change to its parts, a song's colours, a new
    /// look, draws the bitmap again once.
    var drawsStill: Bool { drawing.shouldRasterize }

    private func syncStill() {
        let still = idling && member != nil && size > 0
            && CACurrentMediaTime() - partBeat >= Self.stillAfterBeat
        guard still != drawing.shouldRasterize || (still && drawing.rasterizationScale != scale * 2) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        drawing.rasterizationScale = scale * 2
        drawing.shouldRasterize = still
        CATransaction.commit()
    }

    /// One burst of the member's idle motion, `gap` seconds from now, and the
    /// next queued as it ends. Every burst leaves from rest and comes back to
    /// it on the island's fade curve (NotchSongMotion.fadeCurve), so the
    /// figure never snaps, and nothing runs between bursts. Low Power Mode is
    /// read again before each one, so bursts that were playing when it came
    /// on stop once the one playing ends, even if the rig has not yet heard
    /// of the change.
    private func scheduleIdle(after gap: TimeInterval) {
        // Beats that moved a part inside the figure may have paused since the last burst.
        syncStill()
        guard idling, !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled, let member, size > 0 else { return }
        let begin = CACurrentMediaTime() + gap
        let ease = NotchSongMotion.fadeCurve
        let side = burstSide
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
        /// A turn through `values`, from rest and back to it, eased at every key.
        func swing(_ values: [CGFloat], at times: [Double], duration: CFTimeInterval) -> CAKeyframeAnimation {
            let turn = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            turn.values = values
            turn.keyTimes = times.map { NSNumber(value: $0) }
            turn.timingFunctions = Array(repeating: ease, count: max(1, values.count - 1))
            turn.duration = duration
            turn.preferredFrameRateRange = Self.gentleRate
            return turn
        }
        let length: TimeInterval
        switch member {
        case .scarn:
            // A gentle sway from the feet, to one side, the other, and home.
            length = Double.random(in: 1.9...2.4)
            play(swing([0, 0.05, -0.04, 0.018, 0].map { $0 * side }, at: [0, 0.28, 0.6, 0.84, 1], duration: length),
                 on: idleStage, carries: true)
        case .goldenface:
            // A slow, menacing tilt to one side, held while a glint crosses
            // his face, and back.
            length = Double.random(in: 2.1...2.5)
            play(swing([0, 0.09 * side, 0.09 * side, 0], at: [0, 0.32, 0.7, 1], duration: length),
                 on: idleStage, carries: true)
            if let glint, let sheen,
               let pass = glintPass(duration: 0.75, delay: length * 0.3, curve: ease, rate: Self.quickRate) {
                play(pass.band, on: glint)
                play(pass.window, on: sheen)
            }
        case .jello:
            // A soft wobble, the top swinging over its base and settling.
            length = Double.random(in: 1.5...1.7)
            let wobble = CAKeyframeAnimation(keyPath: "transform")
            wobble.values = [(0, 1, 1), (0.085, 0.97, 1.02), (-0.065, 1.02, 0.98), (0.04, 0.99, 1.01),
                             (-0.018, 1.004, 0.997), (0, 1, 1)]
                .map { NSValue(caTransform3D: Self.jiggle(shear: $0.0 * side, x: $0.1, y: $0.2)) }
            wobble.keyTimes = [0, 0.16, 0.36, 0.57, 0.78, 1]
            wobble.timingFunctions = Array(repeating: ease, count: 5)
            wobble.duration = length
            // Quicker than the others' sways: 30 frames a second, about a
            // third of a point a frame at its quickest.
            wobble.preferredFrameRateRange = Self.quickRate
            play(wobble, on: idleStage, carries: true)
        case .mug:
            // Two or three wisps curl up from the coffee in turn and thin away.
            guard !wisps.isEmpty else { return }
            let puffLength = Double.random(in: 1.6...1.8), stagger = 0.3
            length = puffLength + stagger * Double(wisps.count - 1)
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
                puff.duration = puffLength
                puff.timingFunction = ease
                puff.beginTime = Double(index) * stagger
                puff.preferredFrameRateRange = Self.gentleRate
                play(puff, on: wisp, carries: index == wisps.count - 1)
            }
        case .beet:
            // The tops sway about the crown, each leaf fluttering a little on its own.
            length = Double.random(in: 1.9...2.3)
            play(swing([0, 0.08, -0.06, 0.03, 0].map { $0 * side }, at: [0, 0.27, 0.56, 0.8, 1], duration: length),
                 on: tops ?? underlay, carries: true)
            let lead = 0.12, flutterLength = (length - lead * Double(max(0, leaves.count - 1))) * 0.95
            for (index, leaf) in leaves.enumerated() {
                let way: CGFloat = (index % 2 == 0 ? 1 : -1) * side
                let flutter = swing([0, 0.12 * way, -0.08 * way, 0], at: [0, 0.35, 0.7, 1], duration: flutterLength)
                flutter.beginTime = lead * Double(index)
                play(flutter, on: leaf)
            }
        case .minimal, .robot, .shuffle:
            return
        }
        lastBurst = length
        // The next leans the other way.
        burstSide = -side
    }

    /// The next burst starts eight to twelve seconds after this one did.
    fileprivate func idleDidStop(finished: Bool, relay: NotchMascotCastRelay) {
        guard finished, relay === idleRelay, idling else { return }
        idleRelay = nil
        scheduleIdle(after: Self.restAfter(burst: lastBurst))
    }

    // MARK: The beat

    /// The member's move for a beat onset of `strength`, 0 to 1, toward
    /// `side`: positive to the right. Each move starts from where the last
    /// one has the figure, so a quick beat never makes it jump.
    func beat(strength: CGFloat, side: CGFloat) {
        guard let member, !reduceMotion, size > 0 else { return }
        // Goldenface's rim and the Mug's coffee move inside the still
        // figure, which is then drawn live while the beats go on.
        if member == .goldenface || member == .mug {
            partBeat = CACurrentMediaTime()
            syncStill()
        }
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
            if let arm { Self.playBeat(shake, on: arm) }
        case .goldenface:
            // A gold glint sweeps across the face, in place of one an idle
            // burst may have under way.
            if let glint, let sheen, let pass = glintPass(duration: 0.48, rate: NotchSongMotion.beatFrames) {
                for part in [glint, sheen] { part.removeAnimation(forKey: "castIdle") }
                glint.add(pass.band, forKey: "castBeat")
                sheen.add(pass.window, forKey: "castBeat")
            }
            if let rim {
                let flare = CAKeyframeAnimation(keyPath: "opacity")
                flare.values = [1, 0.4, 1]
                flare.keyTimes = [0, 0.3, 1]
                flare.duration = 0.45
                Self.playBeat(flare, on: rim)
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
                Self.playBeat(slosh, on: coffee)
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
            note.add(Self.atBeatRate(float), forKey: "castBeat")
            let clear = CAKeyframeAnimation(keyPath: "opacity")
            clear.values = [1, 0, 0, 1]
            clear.keyTimes = [0, 0.12, 0.8, 1]
            clear.duration = 0.8
            Self.playBeat(clear, on: steam)
        case .beet:
            // The leaves flick and the bulb bounces.
            if let tops {
                let flick = CAKeyframeAnimation(keyPath: "transform.rotation.z")
                flick.values = [0, 0.32 * push * way, -0.14 * push * way, 0.05 * push * way, 0]
                flick.keyTimes = [0, 0.18, 0.45, 0.72, 1]
                flick.timingFunction = CAMediaTimingFunction(name: .easeOut)
                flick.isAdditive = true
                flick.duration = 0.52
                Self.playBeat(flick, on: tops)
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
        for layer in movingParts { NotchSongMotion.stop("castBeat", on: layer) }
        stopIdling()
        if idling { scheduleIdle(after: 1) }
    }

    /// The idle burst set to play, or playing: nothing between bursts.
    var burstAnimations: [CAAnimation] { movingParts.compactMap { $0.animation(forKey: "castIdle") } }

    /// Every layer an idle burst or a beat moves.
    private var movingParts: [CALayer] {
        var parts: [CALayer] = [beatStage, idleStage, steam]
        parts += [coffee, tops, glint, sheen, rim].compactMap { $0 }
        parts += arms
        parts += wisps as [CALayer]
        parts += notes as [CALayer]
        parts += leaves
        return parts
    }

    /// Plays `frames` on `layer` from where it shows now, at `times` after
    /// the start, and leaves it where it was.
    private func move(_ layer: CALayer, _ frames: [CATransform3D], times: [Double], duration: TimeInterval) {
        let now = CACurrentMediaTime()
        let from = layer === beatStage ? standingStage(at: now) : layer.presentation()?.transform ?? layer.transform
        let poses = [from] + frames
        let move = CAKeyframeAnimation(keyPath: "transform")
        move.values = poses.map { NSValue(caTransform3D: $0) }
        move.keyTimes = ([0] + times).map { NSNumber(value: $0) }
        move.timingFunctions = Array(repeating: Self.moveCurve, count: frames.count)
        move.duration = duration
        Self.playBeat(move, on: layer, at: now)
        if layer === beatStage { stageMove = (now, [0] + times, poses, duration) }
    }

    private static let moveCurve = CAMediaTimingFunction(name: .easeInEaseOut)

    /// The beat's last move on the stage: when it started, its key times as
    /// shares of its length, its poses, and that length.
    private var stageMove: (begin: CFTimeInterval, times: [Double], poses: [CATransform3D], duration: CFTimeInterval)?

    /// Where the stage stands at `time`, worked out from the move last set
    /// going on it rather than read from the screen: each of the
    /// transform's numbers its eased share of the way between two poses.
    /// The poses only move and squash, where that is how Core Animation
    /// blends them; the Jello's slight shear blends within a hair of it.
    private func standingStage(at time: CFTimeInterval) -> CATransform3D {
        guard let move = stageMove, move.duration > 0, move.poses.count == move.times.count, move.times.count > 1,
              NotchSongMotion.isPlaying("castBeat", on: beatStage) else { return beatStage.transform }
        let elapsed = (time - move.begin) / move.duration
        guard elapsed < 1 else { return beatStage.transform }
        var span = 0
        while span + 2 < move.times.count, move.times[span + 1] <= elapsed { span += 1 }
        let length = move.times[span + 1] - move.times[span]
        let share = CGFloat(Self.moveCurve.progress(at: length > 0 ? (max(0, elapsed) - move.times[span]) / length : 1))
        let a = move.poses[span], b = move.poses[span + 1]
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * share }
        return CATransform3D(m11: mix(a.m11, b.m11), m12: mix(a.m12, b.m12), m13: mix(a.m13, b.m13), m14: mix(a.m14, b.m14),
                             m21: mix(a.m21, b.m21), m22: mix(a.m22, b.m22), m23: mix(a.m23, b.m23), m24: mix(a.m24, b.m24),
                             m31: mix(a.m31, b.m31), m32: mix(a.m32, b.m32), m33: mix(a.m33, b.m33), m34: mix(a.m34, b.m34),
                             m41: mix(a.m41, b.m41), m42: mix(a.m42, b.m42), m43: mix(a.m43, b.m43), m44: mix(a.m44, b.m44))
    }

    /// Plays a beat's move on `layer`: its hit, up to its first pose but no
    /// longer than the dancers' (NotchDanceTiming.attack), at the beat's 60
    /// frames a second, with the light's and the dancers' hits, and on from
    /// there at 30, as every move on the beat plays (NotchSongMotion.play).
    private static func playBeat(_ animation: CAKeyframeAnimation, on layer: CALayer,
                                 at now: CFTimeInterval = CACurrentMediaTime()) {
        let first = (animation.keyTimes?.count ?? 0) > 1 ? animation.keyTimes?[1].doubleValue ?? 1 : 1
        NotchSongMotion.play(animation, attack: min(animation.duration * first, NotchDanceTiming.attack), on: layer,
                             key: "castBeat", at: now)
    }

    /// A beat's move, at the song's beat frame rate (NotchSongMotion.beatFrames).
    private static func atBeatRate(_ animation: CAAnimation) -> CAAnimation {
        animation.preferredFrameRateRange = NotchSongMotion.beatFrames
        return animation
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
