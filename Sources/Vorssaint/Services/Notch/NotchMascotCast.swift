// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

// The cast: companions drawn as nods to a mockumentary set in an office.
// Each keeps the companion's two ink eyes, so every face, blink, visit and
// the Command Bar's face work as they do on the minimal body; what each
// adds is an outfit or a prop, and a motion of its own. None has an actor's
// face or a show's branding: each reads by what it wears and holds.

extension NotchMascotStyle {
    /// The cast a shuffle deals from, in the order Settings lists them.
    static let cast: [NotchMascotStyle] = [.scarn, .goldenface, .jello, .mug, .beet]

    /// The order Settings offers the styles in: the shuffle the owner keeps,
    /// the cast, then the upstream companions.
    static let pickerOrder: [NotchMascotStyle] = [.shuffle] + cast + [.minimal, .robot]

    /// One of the cast, drawn with its own parts rather than a shape.
    var isCast: Bool { Self.cast.contains(self) }
}

extension NotchMascotLook {
    /// This look with a shuffle resolved to `member`, the one the shuffle
    /// dealt. Any other style, or a member that is not of the cast, stays.
    func dealing(_ member: NotchMascotStyle) -> NotchMascotLook {
        guard style == .shuffle, member.isCast else { return self }
        var dealt = self
        dealt.style = member
        return dealt
    }
}

extension NotchMascotColor {
    /// A colour written as the brief writes it, 0xRRGGBB.
    init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// `amount` of the way toward `other`, alpha included.
    func mixed(with other: NotchMascotColor, _ amount: CGFloat) -> NotchMascotColor {
        let share = min(1, max(0, amount))
        return NotchMascotColor(red: red + (other.red - red) * share, green: green + (other.green - green) * share,
                                blue: blue + (other.blue - blue) * share, alpha: alpha + (other.alpha - alpha) * share)
    }

    func with(alpha: CGFloat) -> NotchMascotColor {
        NotchMascotColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

/// The cast's own colours. These never take a song's: they are what keeps
/// each member recognisable, the suit dark, the face gold, the jelly yellow,
/// the mug white with black print and the beet beet-coloured.
enum NotchMascotCastColor {
    static let suit = NotchMascotColor(hex: 0x1B1B1F)
    static let shirt = NotchMascotColor(hex: 0xF4F1E8)
    /// Agent Scarn's head: the same paper-white, shaded softly toward the
    /// chin. A neutral, not a skin tone.
    static let paper = NotchMascotColor(hex: 0xF4F1E8)
    static let paperShade = NotchMascotColor(hex: 0xD6CFBF)
    /// The fold along the collar's points, so they stand off the shirt.
    static let collarEdge = NotchMascotColor(hex: 0xB4AD9D)
    /// The tie at rest with the pearl companion, whose own shade is too pale
    /// to read on a white shirt: corporate navy.
    static let navy = NotchMascotColor(hex: 0x1F3A5F)
    static let gold = NotchMascotColor(hex: 0xE3B23C)
    static let goldLight = NotchMascotColor(hex: 0xF7D774)
    /// The gold turning away from the light, so the face reads as metal.
    static let goldDeep = NotchMascotColor(hex: 0xC08E2A)
    static let blackClothes = NotchMascotColor(hex: 0x141417)
    static let lapel = NotchMascotColor(hex: 0x34343C)
    static let jello = NotchMascotColor(hex: 0xF4D03F)
    static let jelloTop = NotchMascotColor(hex: 0xFAE27E)
    static let jelloSide = NotchMascotColor(hex: 0xD9B52E)
    static let stapler = NotchMascotColor(hex: 0x2B2D31)
    /// The light along the stapler's top, so it reads as metal in the jelly.
    static let staplerEdge = NotchMascotColor(hex: 0x737885)
    static let mug = NotchMascotColor(hex: 0xF7F5F0)
    static let mugShade = NotchMascotColor(hex: 0xCFCABE)
    /// The printed words, as bars that are never legible text.
    static let print = NotchMascotColor(hex: 0x121214)
    static let coffee = NotchMascotColor(hex: 0x3B2416)
    static let steam = NotchMascotColor(hex: 0xFFFFFF, alpha: 0.85)
    static let beet = NotchMascotColor(hex: 0x7A1F3D)
    static let beetLight = NotchMascotColor(hex: 0xA12C52)
    static let beetDeep = NotchMascotColor(hex: 0x5C1630)
    static let leaf = NotchMascotColor(hex: 0x3F7D3A)
    static let leafLight = NotchMascotColor(hex: 0x5E9E4F)
    static let stem = NotchMascotColor(hex: 0xC2306E)

    // The colours each member lends the island's glow at rest (see
    // NotchMascotStyle.glowColors): its own, turned up where its body is
    // too dark or too pale to glow.
    /// Agent Scarn: an agent's blue, a tie's red and a shirt's blue.
    static let agentBlue = NotchMascotColor(hex: 0x2A5FC4)
    static let tieRed = NotchMascotColor(hex: 0xD2343F)
    static let shirtBlue = NotchMascotColor(hex: 0x8FB4F2)
    /// Goldenface's gold turning to amber.
    static let amber = NotchMascotColor(hex: 0xB26A12)
    /// The jelly's yellow deepening to orange, and its gloss.
    static let jelloOrange = NotchMascotColor(hex: 0xF29F2B)
    static let jelloGloss = NotchMascotColor(hex: 0xFFF0A0)
    /// The mug's coffee and cream, warmed, and a mustard.
    static let coffeeWarm = NotchMascotColor(hex: 0xC8742C)
    static let cream = NotchMascotColor(hex: 0xF3E2C4)
    static let mustard = NotchMascotColor(hex: 0xC9A227)
    /// The beet's bulb turned up, its leaves' green and its stems' pink.
    static let beetGlow = NotchMascotColor(hex: 0xC22E66)
    static let leafGlow = NotchMascotColor(hex: 0x3F9A3A)
    static let stemGlow = NotchMascotColor(hex: 0xE24A8A)
}

extension NotchMascotStyle {
    /// The colours a member of the cast lends the island's glow at rest, in
    /// the glow's order: the one around it, the one across the camera, and
    /// the accent both wings share. Nil for the minimal body and the robot,
    /// whose glow grows from the colour chosen in Settings, and for a
    /// shuffle, which is never drawn as itself.
    var glowColors: [NotchMascotColor]? {
        typealias Cast = NotchMascotCastColor
        switch self {
        case .scarn: return [Cast.agentBlue, Cast.tieRed, Cast.shirtBlue]
        case .goldenface: return [Cast.gold, Cast.amber, Cast.goldLight]
        case .jello: return [Cast.jello, Cast.jelloOrange, Cast.jelloGloss]
        case .mug: return [Cast.coffeeWarm, Cast.mustard, Cast.cream]
        case .beet: return [Cast.leafGlow, Cast.beetGlow, Cast.stemGlow]
        case .minimal, .robot, .shuffle: return nil
        }
    }
}

/// Where a member wears colour that is not its own: Scarn's tie and lapel
/// rim, Goldenface's rim and glint, a tint over the jelly, the mug's steam,
/// coffee and glow, and the beet's leaf rim and glow. While the island wears
/// a song these take its colours; at rest, the companion colour chosen in
/// Settings.
struct NotchMascotCastTint: Equatable {
    /// A mid tone that reads on white or on gold: a tie, notes, coffee.
    let accent: NotchMascotColor
    /// A light tone for rims and steam.
    let rim: NotchMascotColor
    /// The song's glow around the figure, nil at rest.
    let glow: NotchMascotColor?
    /// The song laid over the jelly at 35%, nil at rest, so yellow stays on top.
    let wash: NotchMascotColor?

    static let washShare: CGFloat = 0.35

    init(look: NotchMascotLook) {
        if let song = look.song {
            accent = song.shade
            rim = song.light
            glow = song.light
            wash = song.light.with(alpha: Self.washShare)
        } else {
            accent = look.palette == .pearl ? NotchMascotCastColor.navy : look.palette.shade
            rim = look.palette.light
            glow = nil
            wash = nil
        }
    }
}

extension NotchMascotGeometry {
    /// The face of each member: two ink eyes where the member's face is.
    /// The highlight values are unused, as each member draws its own.
    static func castFace(_ member: NotchMascotStyle) -> NotchMascotFaceLayout {
        func face(_ x: CGFloat, _ y: CGFloat, gap: CGFloat, eye: CGSize) -> NotchMascotFaceLayout {
            NotchMascotFaceLayout(leftEye: CGPoint(x: x - gap / 2, y: y), rightEye: CGPoint(x: x + gap / 2, y: y),
                                  eyeSize: eye, shineCenter: CGPoint(x: x - 0.15, y: y - 0.15),
                                  shineRadii: CGSize(width: 0.06, height: 0.04), shineAngle: -0.5)
        }
        switch member {
        case .scarn: return face(0.5, 0.36, gap: 0.21, eye: CGSize(width: 0.085, height: 0.17))
        case .goldenface: return face(0.5, 0.42, gap: 0.2, eye: CGSize(width: 0.085, height: 0.165))
        case .jello: return face(0.41, 0.54, gap: 0.21, eye: CGSize(width: 0.085, height: 0.17))
        case .mug: return face(0.40, 0.53, gap: 0.2, eye: CGSize(width: 0.085, height: 0.17))
        case .beet: return face(0.5, 0.645, gap: 0.19, eye: CGSize(width: 0.08, height: 0.16))
        case .minimal, .robot, .shuffle: return face(0.5, 0.5, gap: 0.28, eye: CGSize(width: 0.10, height: 0.20))
        }
    }

    /// The parts every member always shows, for its box: what a caller
    /// centres. Steam, notes and a glint come and go, so they do not count.
    static func castOutline(_ member: NotchMascotStyle, size: CGFloat) -> [CGPath] {
        switch member {
        case .scarn:
            let parts = scarn(size: size)
            return [parts.head, parts.suit, parts.leftArm, parts.rightArm]
        case .goldenface:
            let parts = goldenface(size: size)
            return [parts.head, parts.clothes]
        case .jello:
            let parts = jello(size: size)
            return [parts.front, parts.top, parts.side]
        case .mug:
            let parts = mug(size: size)
            return [parts.body, parts.rim, parts.handleOutline]
        case .beet:
            let parts = beet(size: size)
            return [parts.bulb, parts.tail] + parts.leaves + [parts.stemOutline]
        case .minimal, .robot, .shuffle:
            return []
        }
    }

    /// The box around what a member always shows.
    static func castBounds(_ member: NotchMascotStyle, size: CGFloat) -> CGRect {
        castOutline(member, size: size).reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
    }

    /// Where each member's face is, for its eyes to sit on.
    static func castFaceRegion(_ member: NotchMascotStyle, size: CGFloat) -> CGPath? {
        switch member {
        case .scarn: return scarn(size: size).head
        case .goldenface: return goldenface(size: size).head
        case .jello: return jello(size: size).front
        case .mug: return mug(size: size).body
        case .beet: return beet(size: size).bulb
        case .minimal, .robot, .shuffle: return nil
        }
    }

    // MARK: The members

    /// Points in a square of `size`, given as shares of it.
    private struct Sketch {
        let size: CGFloat
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: x * size, y: y * size, width: width * size, height: height * size)
        }
        func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> CGPath {
            let corner = min(radius, width / 2, height / 2) * size
            return CGPath(roundedRect: rect(x, y, width, height), cornerWidth: corner, cornerHeight: corner,
                          transform: nil)
        }
        func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, angle: CGFloat = 0) -> CGPath {
            var transform = CGAffineTransform(translationX: cx * size, y: cy * size).rotated(by: angle)
            return CGPath(ellipseIn: CGRect(x: -rx * size, y: -ry * size, width: rx * 2 * size, height: ry * 2 * size),
                          transform: &transform)
        }
        func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: points.map { p($0.0, $0.1) })
            path.closeSubpath()
            return path
        }
    }

    /// Agent Scarn: a round paper-white head on the shoulders of a dark
    /// suit, a white collar and shirt showing between the lapels and a thin
    /// tie. No sunglasses, nothing in his hands but a handshake.
    struct Scarn {
        /// The head, where the eyes are: neutral paper-white, never a skin tone.
        let head: CGPath
        /// The light catching the top of the head.
        let highlight: CGPath
        /// The jacket's shoulders and chest.
        let suit: CGPath
        let shirt: CGPath
        /// The collar's two points under the chin.
        let collar: CGPath
        let tie: CGPath
        /// The lapels' edges, stroked for the rim-light.
        let lapels: CGPath
        /// Each arm hangs from its shoulder behind the jacket and swings out
        /// from it for a handshake.
        let leftArm: CGPath
        let rightArm: CGPath
        let leftHand: CGPath
        let rightHand: CGPath
        let leftShoulder: CGPoint
        let rightShoulder: CGPoint
    }

    static func scarn(size: CGFloat) -> Scarn {
        let s = Sketch(size: size)
        let suit = CGMutablePath()
        suit.move(to: s.p(0.12, 0.965))
        suit.addLine(to: s.p(0.12, 0.80))
        suit.addCurve(to: s.p(0.32, 0.59), control1: s.p(0.12, 0.67), control2: s.p(0.21, 0.59))
        suit.addLine(to: s.p(0.68, 0.59))
        suit.addCurve(to: s.p(0.88, 0.80), control1: s.p(0.79, 0.59), control2: s.p(0.88, 0.67))
        suit.addLine(to: s.p(0.88, 0.965))
        suit.addQuadCurve(to: s.p(0.12, 0.965), control: s.p(0.5, 0.99))
        suit.closeSubpath()
        let shirt = s.polygon([(0.385, 0.6), (0.615, 0.6), (0.5, 0.9)])
        let collar = CGMutablePath()
        collar.addPath(s.polygon([(0.375, 0.6), (0.495, 0.648), (0.425, 0.72)]))
        collar.addPath(s.polygon([(0.625, 0.6), (0.505, 0.648), (0.575, 0.72)]))
        let tie = CGMutablePath()
        // The knot between the collar's points, then the blade to its point.
        tie.addPath(s.polygon([(0.47, 0.646), (0.53, 0.646), (0.517, 0.7), (0.483, 0.7)]))
        tie.addPath(s.polygon([(0.486, 0.7), (0.514, 0.7), (0.536, 0.83), (0.5, 0.875), (0.464, 0.83)]))
        let lapels = CGMutablePath()
        lapels.move(to: s.p(0.385, 0.6))
        lapels.addLine(to: s.p(0.5, 0.9))
        lapels.addLine(to: s.p(0.615, 0.6))
        // Arms hang behind the jacket, out of sight until one reaches out.
        let leftShoulder = s.p(0.22, 0.74), rightShoulder = s.p(0.78, 0.74)
        func arm(_ shoulder: CGPoint, outward: CGFloat) -> (arm: CGPath, hand: CGPath) {
            let length = 0.22 * size, width = 0.1 * size
            let rect = CGRect(x: shoulder.x - width / 2, y: shoulder.y - width / 2, width: width, height: length)
            var lean = CGAffineTransform(translationX: shoulder.x, y: shoulder.y).rotated(by: outward)
                .translatedBy(x: -shoulder.x, y: -shoulder.y)
            let arm = CGPath(roundedRect: rect, cornerWidth: width / 2, cornerHeight: width / 2, transform: &lean)
            let palm = 0.056 * size
            let hand = CGPath(ellipseIn: CGRect(x: shoulder.x - palm, y: shoulder.y + length - width / 2 - palm,
                                                width: palm * 2, height: palm * 2), transform: &lean)
            return (arm, hand)
        }
        // Positive turns clockwise on screen: the left arm leans out to the left.
        let left = arm(leftShoulder, outward: 0.06), right = arm(rightShoulder, outward: -0.06)
        return Scarn(head: s.ellipse(0.5, 0.35, 0.27, 0.285),
                     highlight: s.ellipse(0.39, 0.19, 0.085, 0.045, angle: -0.55),
                     suit: suit, shirt: shirt, collar: collar, tie: tie, lapels: lapels,
                     leftArm: left.arm, rightArm: right.arm, leftHand: left.hand, rightHand: right.hand,
                     leftShoulder: leftShoulder, rightShoulder: rightShoulder)
    }

    /// Goldenface: a face of gold over black clothes.
    struct Goldenface {
        let head: CGPath
        /// The light catching the top of the gold.
        let highlight: CGPath
        let clothes: CGPath
        /// The lapels of the black suit, a shade off black.
        let lapels: CGPath
        /// The glint's band, standing left of the face, to sweep across it.
        let glint: CGRect
        /// How far the glint travels to cross the face.
        let glintTravel: CGFloat
    }

    static func goldenface(size: CGFloat) -> Goldenface {
        let s = Sketch(size: size)
        let clothes = CGMutablePath()
        clothes.move(to: s.p(0.13, 0.96))
        clothes.addLine(to: s.p(0.13, 0.82))
        clothes.addCurve(to: s.p(0.33, 0.62), control1: s.p(0.13, 0.69), control2: s.p(0.22, 0.62))
        clothes.addLine(to: s.p(0.67, 0.62))
        clothes.addCurve(to: s.p(0.87, 0.82), control1: s.p(0.78, 0.62), control2: s.p(0.87, 0.69))
        clothes.addLine(to: s.p(0.87, 0.96))
        clothes.addQuadCurve(to: s.p(0.13, 0.96), control: s.p(0.5, 0.985))
        clothes.closeSubpath()
        let lapels = CGMutablePath()
        lapels.move(to: s.p(0.37, 0.70))
        lapels.addLine(to: s.p(0.5, 0.93))
        lapels.addLine(to: s.p(0.63, 0.70))
        return Goldenface(head: s.ellipse(0.5, 0.40, 0.29, 0.31),
                          highlight: s.ellipse(0.38, 0.22, 0.10, 0.05, angle: -0.55),
                          clothes: clothes, lapels: lapels,
                          glint: s.rect(0.0, -0.1, 0.13, 1.2), glintTravel: 0.9 * size)
    }

    /// The Jelly Stapler: a block of yellow jelly, a little see-through,
    /// with a dark stapler set inside it, as the prank had it.
    struct Jello {
        let front: CGPath
        let top: CGPath
        let side: CGPath
        let stapler: CGPath
        /// The top of its arm, as a line to stroke.
        let staplerEdge: CGPath
        /// The gloss on the front and along the top edge.
        let highlight: CGPath
        /// The whole block, for the song's wash and glow.
        let block: CGPath
    }

    static func jello(size: CGFloat) -> Jello {
        let s = Sketch(size: size)
        let front = s.rounded(0.10, 0.35, 0.62, 0.59, 0.08)
        let top = s.polygon([(0.12, 0.355), (0.255, 0.215), (0.885, 0.215), (0.715, 0.355)])
        let side = s.polygon([(0.715, 0.36), (0.885, 0.22), (0.885, 0.78), (0.715, 0.935)])
        // A closed desk stapler seen from the side, facing right: one long
        // slab, its arm sloping down from the hinge's hump at the back to a
        // rounded nose over the front of the base.
        let stapler = CGMutablePath()
        stapler.move(to: s.p(0.17, 0.845))
        stapler.addLine(to: s.p(0.63, 0.845))
        stapler.addQuadCurve(to: s.p(0.665, 0.81), control: s.p(0.665, 0.845))
        stapler.addLine(to: s.p(0.665, 0.765))
        stapler.addQuadCurve(to: s.p(0.62, 0.71), control: s.p(0.668, 0.712))
        stapler.addLine(to: s.p(0.27, 0.675))
        stapler.addQuadCurve(to: s.p(0.17, 0.72), control: s.p(0.17, 0.665))
        stapler.closeSubpath()
        // The light along the arm's top, and the seam between arm and base.
        let staplerEdge = CGMutablePath()
        staplerEdge.move(to: s.p(0.25, 0.69))
        staplerEdge.addLine(to: s.p(0.6, 0.724))
        staplerEdge.move(to: s.p(0.2, 0.795))
        staplerEdge.addLine(to: s.p(0.64, 0.795))
        let highlight = CGMutablePath()
        highlight.addPath(s.rounded(0.145, 0.41, 0.045, 0.20, 0.0225))
        highlight.addPath(s.ellipse(0.17, 0.66, 0.02, 0.02))
        highlight.addPath(s.polygon([(0.20, 0.335), (0.27, 0.255), (0.30, 0.255), (0.23, 0.335)]))
        let block = CGMutablePath()
        block.addPath(front)
        block.addPath(top)
        block.addPath(side)
        return Jello(front: front, top: top, side: side, stapler: stapler, staplerEdge: staplerEdge,
                     highlight: highlight, block: block)
    }

    /// The Best Boss Mug: a white mug with a C handle and its print as black
    /// bars, never legible words, and coffee inside.
    struct Mug {
        let body: CGPath
        /// The mug's open top, round, and the coffee inside it.
        let rim: CGPath
        let coffee: CGPath
        /// The handle, as a line to stroke, and its width.
        let handle: CGPath
        let handleWidth: CGFloat
        /// The handle's outline once stroked, for its box.
        let handleOutline: CGPath
        let bars: CGPath
        /// Wisps of steam above the coffee, as lines to stroke.
        let steam: [CGPath]
        let steamWidth: CGFloat
        /// Tiny notes the steam turns into on the beat.
        let notes: [CGPath]
        /// The coffee's middle, which a slosh tips about.
        let coffeeCenter: CGPoint
    }

    static func mug(size: CGFloat) -> Mug {
        let s = Sketch(size: size)
        let body = CGMutablePath()
        let left: CGFloat = 0.11, right: CGFloat = 0.69, top: CGFloat = 0.33, bottom: CGFloat = 0.95
        let foot: CGFloat = 0.09
        body.move(to: s.p(left, top))
        body.addLine(to: s.p(right, top))
        body.addLine(to: s.p(right, bottom - foot))
        body.addQuadCurve(to: s.p(right - foot, bottom), control: s.p(right, bottom))
        body.addLine(to: s.p(left + foot, bottom))
        body.addQuadCurve(to: s.p(left, bottom - foot), control: s.p(left, bottom))
        body.closeSubpath()
        let middle = (left + right) / 2
        let rim = s.ellipse(middle, top, (right - left) / 2, 0.055)
        let coffee = s.ellipse(middle, top + 0.004, (right - left) / 2 - 0.04, 0.034)
        let handle = CGMutablePath()
        handle.move(to: s.p(right - 0.01, 0.45))
        handle.addCurve(to: s.p(right - 0.01, 0.80), control1: s.p(0.93, 0.42), control2: s.p(0.93, 0.83))
        let handleWidth = 0.085 * size
        let handleOutline = handle.copy(strokingWithWidth: handleWidth, lineCap: .round, lineJoin: .round,
                                        miterLimit: 1)
        let bars = CGMutablePath()
        for (width, y) in [(0.30, 0.69), (0.21, 0.765), (0.27, 0.84)] as [(CGFloat, CGFloat)] {
            bars.addPath(s.rounded(middle - width / 2, y, width, 0.048, 0.012))
        }
        let steam: [CGPath] = [
            (0.27, 0.26, 0.25, 0.05, 0.19, 0.19, 0.33, 0.11),
            (0.40, 0.25, 0.41, 0.0, 0.47, 0.17, 0.33, 0.08),
            (0.53, 0.26, 0.55, 0.06, 0.47, 0.19, 0.61, 0.12),
        ].map { (x0, y0, x1, y1, cx0, cy0, cx1, cy1) in
            let wisp = CGMutablePath()
            wisp.move(to: s.p(x0, y0))
            wisp.addCurve(to: s.p(x1, y1), control1: s.p(cx0, cy0), control2: s.p(cx1, cy1))
            return wisp
        }
        let notes = [(0.24, 0.14), (0.42, 0.07), (0.57, 0.15)].map { note(at: s.p($0.0, $0.1), size: size) }
        return Mug(body: body, rim: rim, coffee: coffee, handle: handle, handleWidth: handleWidth,
                   handleOutline: handleOutline, bars: bars, steam: steam, steamWidth: 0.042 * size, notes: notes,
                   coffeeCenter: s.p(middle, top))
    }

    /// An eighth note whose head sits at `center`: a tilted head, a stem up
    /// from its right and a flag.
    private static func note(at center: CGPoint, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let rx = 0.052 * size, ry = 0.038 * size
        var tilt = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: -0.4)
        path.addPath(CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: &tilt))
        let stemX = center.x + rx * 0.8, stemTop = center.y - 0.17 * size, stem = 0.022 * size
        path.addRect(CGRect(x: stemX - stem, y: stemTop, width: stem, height: center.y - stemTop))
        let flag = CGMutablePath()
        flag.move(to: CGPoint(x: stemX - stem, y: stemTop))
        flag.addCurve(to: CGPoint(x: stemX + 0.06 * size, y: stemTop + 0.12 * size),
                      control1: CGPoint(x: stemX + 0.02 * size, y: stemTop + 0.03 * size),
                      control2: CGPoint(x: stemX + 0.08 * size, y: stemTop + 0.06 * size))
        flag.addCurve(to: CGPoint(x: stemX, y: stemTop + 0.06 * size),
                      control1: CGPoint(x: stemX + 0.05 * size, y: stemTop + 0.08 * size),
                      control2: CGPoint(x: stemX + 0.02 * size, y: stemTop + 0.06 * size))
        flag.closeSubpath()
        path.addPath(flag)
        return path
    }

    /// The Schrute Beet: a beet bulb with a tapered root, and green tops on
    /// magenta stems.
    struct Beet {
        let bulb: CGPath
        let tail: CGPath
        let highlight: CGPath
        /// The stems, as lines to stroke, and their width.
        let stems: [CGPath]
        let stemWidth: CGFloat
        /// The stems once stroked, for the box.
        let stemOutline: CGPath
        let leaves: [CGPath]
        /// Each leaf's middle vein, as a line to stroke.
        let veins: [CGPath]
        /// Where the tops grow from, which they sway about.
        let crown: CGPoint
        /// Where each leaf meets its stem, which it flutters about.
        let leafBases: [CGPoint]
    }

    static func beet(size: CGFloat) -> Beet {
        let s = Sketch(size: size)
        let bulb = CGMutablePath()
        bulb.move(to: s.p(0.5, 0.40))
        bulb.addCurve(to: s.p(0.79, 0.635), control1: s.p(0.68, 0.40), control2: s.p(0.79, 0.50))
        bulb.addCurve(to: s.p(0.545, 0.88), control1: s.p(0.79, 0.77), control2: s.p(0.665, 0.855))
        bulb.addLine(to: s.p(0.455, 0.88))
        bulb.addCurve(to: s.p(0.21, 0.635), control1: s.p(0.335, 0.855), control2: s.p(0.21, 0.77))
        bulb.addCurve(to: s.p(0.5, 0.40), control1: s.p(0.21, 0.50), control2: s.p(0.32, 0.40))
        bulb.closeSubpath()
        let tail = CGMutablePath()
        tail.move(to: s.p(0.45, 0.865))
        tail.addCurve(to: s.p(0.425, 0.995), control1: s.p(0.465, 0.925), control2: s.p(0.445, 0.965))
        tail.addCurve(to: s.p(0.55, 0.865), control1: s.p(0.475, 0.955), control2: s.p(0.53, 0.915))
        tail.closeSubpath()
        let crown = s.p(0.5, 0.415)
        let bases = [s.p(0.33, 0.235), s.p(0.515, 0.17), s.p(0.67, 0.235)]
        let stems: [CGPath] = zip(bases, [s.p(0.42, 0.30), s.p(0.5, 0.28), s.p(0.59, 0.30)]).map { base, bend in
            let stem = CGMutablePath()
            stem.move(to: crown)
            stem.addQuadCurve(to: base, control: bend)
            return stem
        }
        let stemWidth = 0.04 * size
        let stemOutline = CGMutablePath()
        for stem in stems {
            stemOutline.addPath(stem.copy(strokingWithWidth: stemWidth, lineCap: .round, lineJoin: .round, miterLimit: 1))
        }
        // Each leaf points away from the crown: up and out at the sides, up in the middle.
        let shapes: [(base: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat)] = [
            (bases[0], -2.25, 0.25, 0.17), (bases[1], -1.62, 0.165, 0.15), (bases[2], -0.89, 0.25, 0.17),
        ]
        var leaves: [CGPath] = [], veins: [CGPath] = []
        for shape in shapes {
            let direction = CGPoint(x: cos(shape.angle), y: sin(shape.angle))
            let across = CGPoint(x: -direction.y, y: direction.x)
            let length = shape.length * size, half = shape.width * size / 2
            func along(_ share: CGFloat, _ side: CGFloat) -> CGPoint {
                CGPoint(x: shape.base.x + direction.x * length * share + across.x * half * side,
                        y: shape.base.y + direction.y * length * share + across.y * half * side)
            }
            let leaf = CGMutablePath()
            leaf.move(to: shape.base)
            leaf.addCurve(to: along(1, 0), control1: along(0.25, 1.35), control2: along(0.8, 1.0))
            leaf.addCurve(to: shape.base, control1: along(0.8, -1.0), control2: along(0.25, -1.35))
            leaf.closeSubpath()
            leaves.append(leaf)
            let vein = CGMutablePath()
            vein.move(to: shape.base)
            vein.addLine(to: along(0.78, 0))
            veins.append(vein)
        }
        return Beet(bulb: bulb, tail: tail, highlight: s.ellipse(0.37, 0.52, 0.065, 0.035, angle: -0.6),
                    stems: stems, stemWidth: stemWidth, stemOutline: stemOutline, leaves: leaves, veins: veins,
                    crown: crown, leafBases: bases)
    }
}

/// The shuffle's hand: which member of the cast is out, when it was dealt
/// and for which song. A new song deals another; with no music, one is
/// dealt at most once an hour. A deal is never the member already out. The
/// hand is saved, so a relaunch keeps the member out until the next deal.
struct NotchMascotShuffle: Equatable {
    /// With nothing playing, another member comes out at most this often.
    static let quietInterval: TimeInterval = 3600

    private(set) var member: NotchMascotStyle
    private(set) var dealt: Date
    /// The song it last dealt for, so a song paused and played again, or
    /// still playing after a relaunch, keeps the member it brought. A digest
    /// of its names, so no title is ever saved.
    private(set) var song: String?

    init(member: NotchMascotStyle, dealt: Date, song: String? = nil) {
        self.member = member.isCast ? member : NotchMascotStyle.cast[0]
        self.dealt = dealt
        self.song = song
    }

    /// A first hand, picked by `random` in 0..<1.
    static func first(at date: Date, random: Double) -> NotchMascotShuffle {
        NotchMascotShuffle(member: deal(after: nil, random: random), dealt: date)
    }

    /// One of the cast other than `previous`, picked by `random` in 0..<1.
    static func deal(after previous: NotchMascotStyle?, random: Double) -> NotchMascotStyle {
        let choices = NotchMascotStyle.cast.filter { $0 != previous }
        let index = Int(min(max(random, 0), 0.999_999) * Double(choices.count))
        return choices[min(choices.count - 1, index)]
    }

    /// What tells one song from the next: its title and artist, as the
    /// island tells whether a reading is still the song it holds, in a
    /// stable digest (64-bit FNV-1a), so the key can be saved without the
    /// names. The album is left out: players send it last, so it would make
    /// one song read as yet another, and the same recording on another
    /// album is the same song. Nil for a reading with neither name, which
    /// tells nothing apart.
    static func songKey(title: String?, artist: String?) -> String? {
        let parts = [title, artist].map { $0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        guard !parts.allSatisfy(\.isEmpty) else { return nil }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in parts.joined(separator: "\u{1F}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    /// The hand as it is saved in defaults.
    var stored: [String: Any] {
        var stored: [String: Any] = ["member": member.rawValue, "dealt": dealt.timeIntervalSince1970]
        if let song { stored["song"] = song }
        return stored
    }

    /// A saved hand, or nil for one missing, damaged or holding anything but
    /// a member of the cast. A deal dated after `now`, from a clock set
    /// back, counts from `now`, so the quiet hour is never put off.
    init?(stored: [String: Any]?, now: Date) {
        guard let raw = stored?["member"] as? String, let member = NotchMascotStyle(rawValue: raw), member.isCast,
              let dealt = stored?["dealt"] as? Double, dealt.isFinite else { return nil }
        self.init(member: member, dealt: min(Date(timeIntervalSince1970: dealt), now), song: stored?["song"] as? String)
    }

    /// Deals another member now.
    mutating func redeal(at date: Date, random: Double) {
        member = Self.deal(after: member, random: random)
        dealt = date
    }

    /// A song is playing. A new one deals another member; the same one
    /// again keeps the one out. Returns whether it dealt.
    @discardableResult
    mutating func hears(song key: String, at date: Date, random: Double) -> Bool {
        guard key != song else { return false }
        song = key
        redeal(at: date, random: random)
        return true
    }

    /// Nothing is playing: once an hour has gone by since the last deal,
    /// another member comes out. Returns whether it dealt.
    @discardableResult
    mutating func rests(at date: Date, random: Double) -> Bool {
        guard date.timeIntervalSince(dealt) >= Self.quietInterval else { return false }
        redeal(at: date, random: random)
        return true
    }

    /// When a deal is due with nothing playing.
    var quietDealDue: Date { dealt.addingTimeInterval(Self.quietInterval) }
}

/// Waits for a new song's names to settle before a shuffle deals for it,
/// for the companion's cast and the strip's dancers alike. Players send a
/// new song's title a moment before its artist, so its first readings make
/// two keys; a deal on each would bring out one member or dance and swap it
/// for another straight away. A song counts once the same key has been read
/// for `interval`: read when it arrives, then again when `due`. A key read
/// again only after a long gap, with no reading in between, starts its wait
/// over, since nothing says it held still meanwhile. Times are seconds on a
/// clock that only runs forward, as the system's uptime does.
struct NotchSongSettle: Equatable {
    static let interval: TimeInterval = 0.8
    /// A reading a hair early, as a timer can fire, still counts.
    static let tolerance: TimeInterval = 0.05

    /// The key waiting to settle, nil while none is.
    private(set) var song: String?
    /// When it was first read, and when last.
    private(set) var since: TimeInterval = 0
    private(set) var seen: TimeInterval = 0

    /// `song` is read at `now`. True once the same key has been read for
    /// the interval, which ends its wait; false while it waits.
    mutating func hears(_ song: String, at now: TimeInterval) -> Bool {
        if song != self.song || now < seen || now - seen > Self.interval * 2 {
            self.song = song
            since = now
        }
        seen = now
        guard now - since >= Self.interval - Self.tolerance else { return false }
        self.song = nil
        return true
    }

    /// When to read the waiting key again for it to settle; nil while none waits.
    var due: TimeInterval? { song == nil ? nil : since + Self.interval }

    /// Nothing waits any more: the music stopped, or the shuffle let go.
    mutating func forget() { song = nil }
}
