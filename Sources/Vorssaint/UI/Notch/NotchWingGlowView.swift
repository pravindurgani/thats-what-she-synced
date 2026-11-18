// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// Each wing's colours, deep first: the pool, the accent, and the colour the
/// base gradient carries toward the camera.
struct NotchWingGlowColors: Equatable {
    let left: [NotchRGB]
    let right: [NotchRGB]
    /// The resting island's glow fades toward its ends and its lower edge,
    /// so its outline still reads as the notch's own black.
    let fadesEdges: Bool
}

/// A soft glow behind the closed island's wings, one set of colours on each
/// side of the camera and black over the camera itself. It is drawn as the
/// song's closed glow is, on the same deep ground under the same veil, with
/// pools of colour toned as a cover's are, but it never moves: once drawn it
/// costs the compositor nothing more. A change of colours cross-fades. How
/// strongly it shows is handed in (NotchGlowPresence) and applied to its own
/// layer, so its fades run in Core Animation whatever transaction SwiftUI is in.
final class NotchWingGlowView: NSView {
    private let canvas = CALayer()
    private let ground = CALayer()
    private let stage = CALayer()
    private let base = CAGradientLayer()
    private let pools = (left: CAGradientLayer(), right: CAGradientLayer())
    private let accents = (left: CAGradientLayer(), right: CAGradientLayer())
    private let ink = CAGradientLayer()
    private let ends = CAGradientLayer()
    private let floor = CAGradientLayer()
    private let scrim = CAGradientLayer()
    private var colors: NotchWingGlowColors?
    /// The camera's housing, or zero with none (a floating capsule).
    private var camera = CGSize.zero
    private var veil: NotchAuroraVeil = .open
    private let presence = NotchGlowPresenceLayer()
    /// The glow changed between an agents' and the resting island's, whose
    /// edges and camera ink differ: the next layout eases them across with
    /// the colours instead of cutting.
    private var edgesChanging = false

    /// How far the black over the camera fades out into each wing: well
    /// into an agent's wing, so the two glows stand apart, and only a little
    /// into the resting island's narrow wings, which the colour should fill.
    private static func inkReach(wing: CGFloat, resting: Bool) -> CGFloat {
        resting ? min(14, wing * 0.35) : min(26, wing * 0.6)
    }
    /// The camera ink's falloff, a smoothstep, as the song's camera ink fades.
    private static let falloff: [(at: Double, ink: Double)] = [(0, 1), (0.25, 0.84), (0.5, 0.5), (0.75, 0.16), (1, 0)]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer = CALayer()
        wantsLayer = true
        setAccessibilityElement(false)
        layer?.masksToBounds = true
        canvas.opacity = 0
        layer?.addSublayer(canvas)
        // The same deep ground as the song's glow, so the colour stands the
        // same over glass, wallpaper or windows.
        ground.backgroundColor = NSColor(srgbRed: 0.035, green: 0.035, blue: 0.05, alpha: 0.94).cgColor
        canvas.addSublayer(ground)
        base.type = .axial
        base.startPoint = CGPoint(x: 0, y: 0.5)
        base.endPoint = CGPoint(x: 1, y: 0.5)
        base.locations = [0, 0.42, 0.58, 1]
        stage.addSublayer(base)
        for layer in [pools.left, pools.right, accents.left, accents.right] {
            layer.type = .radial
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 1)
            stage.addSublayer(layer)
        }
        canvas.addSublayer(stage)
        ink.type = .axial
        ink.startPoint = CGPoint(x: 0, y: 0.5)
        ink.endPoint = CGPoint(x: 1, y: 0.5)
        canvas.addSublayer(ink)
        ends.type = .axial
        ends.startPoint = CGPoint(x: 0, y: 0.5)
        ends.endPoint = CGPoint(x: 1, y: 0.5)
        floor.type = .axial
        floor.startPoint = CGPoint(x: 0.5, y: 0)
        floor.endPoint = CGPoint(x: 0.5, y: 1)
        floor.colors = [NSColor.black.withAlphaComponent(0.45).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
        floor.locations = [0, 0.45]
        ends.colors = [NSColor.black.withAlphaComponent(0.6).cgColor, NSColor.black.withAlphaComponent(0).cgColor,
                       NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.6).cgColor]
        canvas.addSublayer(ends)
        canvas.addSublayer(floor)
        // The song's veil over the colour (NotchAuroraVeil), laid out as its own.
        scrim.type = .axial
        scrim.startPoint = CGPoint(x: 0.5, y: 1)
        scrim.endPoint = CGPoint(x: 0.5, y: 0)
        scrim.locations = [0, 0.55, 1]
        canvas.addSublayer(scrim)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(colors next: NotchWingGlowColors, camera nextCamera: CGSize, veil nextVeil: NotchAuroraVeil,
               presence shown: Double, fades: Bool) {
        let recolor = next != colors
        let first = colors == nil
        if recolor, !first {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = NotchSongMotion.colorChange
            fade.timingFunction = NotchSongMotion.settleCurve
            stage.add(fade, forKey: "colors")
        }
        let edgesChange = !first && next.fadesEdges != colors?.fadesEdges
        colors = next
        let moved = nextCamera != camera
        camera = nextCamera
        let veiled = nextVeil != veil || first
        veil = nextVeil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if recolor { paint(next) }
        if veiled {
            scrim.colors = veil.stops.map { NSColor.black.withAlphaComponent($0).cgColor }
            stage.opacity = veil.strength
        }
        CATransaction.commit()
        if edgesChange { edgesChanging = true }
        // The resting island's edges fade in and out with its colours.
        easingEdges(edgesChange) {
            for edge in [ends, floor] { edge.opacity = next.fadesEdges ? 1 : 0 }
        }
        if moved || recolor { needsLayout = true }
        presence.apply(shown, fades: fades, to: canvas)
    }

    private func paint(_ colors: NotchWingGlowColors) {
        func pick(_ list: [NotchRGB], _ index: Int) -> NotchRGB {
            list.isEmpty ? NotchRGB(red: 0, green: 0, blue: 0) : list[min(index, list.count - 1)]
        }
        let (left, right) = (colors.left, colors.right)
        base.colors = [pick(left, 0).cgColor(alpha: 0.55), pick(left, 2).cgColor(alpha: 0.42),
                       pick(right, 2).cgColor(alpha: 0.42), pick(right, 0).cgColor(alpha: 0.55)]
        pools.left.colors = [pick(left, 0).cgColor(alpha: 0.96), pick(left, 0).cgColor(alpha: 0)]
        pools.right.colors = [pick(right, 0).cgColor(alpha: 0.96), pick(right, 0).cgColor(alpha: 0)]
        accents.left.colors = [pick(left, 1).cgColor(alpha: 0.88), pick(left, 1).cgColor(alpha: 0)]
        accents.right.colors = [pick(right, 1).cgColor(alpha: 0.88), pick(right, 1).cgColor(alpha: 0)]
    }

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        let wing = max(1, (size.width - camera.width) / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.frame = bounds
        for layer in [ground, stage, base, ends, floor, scrim] as [CALayer] { layer.frame = bounds }
        // The camera's black stands as tall as the housing, which the closed
        // strip is: an island taller than that, closing or opening around
        // this glow, keeps its colour below the camera.
        let inkHeight = camera.height > 0 ? min(size.height, camera.height) : size.height
        ink.frame = CGRect(x: 0, y: size.height - inkHeight, width: size.width, height: inkHeight)
        // A pool fills each wing and an accent glows toward its outer end,
        // where an agent's ring or the companion sits.
        let poolSize = CGSize(width: max(wing * 1.6, size.height * 2.2), height: size.height * 1.9)
        let accentSize = CGSize(width: max(wing * 0.95, size.height * 1.3), height: size.height * 1.4)
        pools.left.bounds = CGRect(origin: .zero, size: poolSize)
        pools.left.position = CGPoint(x: wing * 0.45, y: size.height * 0.55)
        pools.right.bounds = CGRect(origin: .zero, size: poolSize)
        pools.right.position = CGPoint(x: size.width - wing * 0.45, y: size.height * 0.55)
        accents.left.bounds = CGRect(origin: .zero, size: accentSize)
        accents.left.position = CGPoint(x: wing * 0.24, y: size.height * 0.42)
        accents.right.bounds = CGRect(origin: .zero, size: accentSize)
        accents.right.position = CGPoint(x: size.width - wing * 0.24, y: size.height * 0.42)
        CATransaction.commit()
        // The camera's ink reaches further into an agent's wing than into the
        // resting island's: a change between the two eases across with the colours.
        let easing = edgesChanging
        edgesChanging = false
        easingEdges(easing) {
            paintInk(width: size.width)
            let end = Double(min(0.5, wing * 0.22 / size.width))
            ends.locations = [0, end, 1 - end, 1].map { NSNumber(value: $0) }
        }
    }

    /// Changes made in `change`, eased over the colours' cross-fade when
    /// `eased`, otherwise at once.
    private func easingEdges(_ eased: Bool, _ change: () -> Void) {
        CATransaction.begin()
        if eased {
            CATransaction.setAnimationDuration(NotchSongMotion.colorChange)
            CATransaction.setAnimationTimingFunction(NotchSongMotion.settleCurve)
        } else {
            CATransaction.setDisableActions(true)
        }
        change()
        CATransaction.commit()
    }

    /// Solid black over the camera, fading out into each wing, so the
    /// wings glow apart and the housing melts into the island.
    private func paintInk(width: CGFloat) {
        let camera = camera.width
        guard camera > 0, width > camera else {
            ink.isHidden = true
            return
        }
        ink.isHidden = false
        let reach = Self.inkReach(wing: (width - camera) / 2, resting: colors?.fadesEdges == true)
        let start = (width - camera) / 2, end = (width + camera) / 2
        // Clear `reach` before the camera's left edge, solid at it; mirrored on the right.
        let leftStops = Self.falloff.reversed().map { (Double(start - reach * CGFloat($0.at)) / Double(width), $0.ink) }
        let rightStops = Self.falloff.map { (Double(end + reach * CGFloat($0.at)) / Double(width), $0.ink) }
        let stops = leftStops + rightStops
        // The colours never change; only where they fall does, with the width.
        if ink.colors == nil { ink.colors = stops.map { NSColor.black.withAlphaComponent($0.1).cgColor } }
        ink.locations = stops.map { NSNumber(value: min(1, max(0, $0.0))) }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [canvas, ground, stage, base, pools.left, pools.right, accents.left, accents.right, ink, ends,
                      floor, scrim] as [CALayer] { layer.contentsScale = scale }
        CATransaction.commit()
    }
}

/// Puts a glow's presence (NotchGlowPresence) on its layer: at once while
/// the glow follows the island's resize frame by frame, or eased over the
/// song's fade, from wherever it stands, while the island stays still.
struct NotchGlowPresenceLayer {
    private static let key = "presence"

    func apply(_ value: Double, fades: Bool, to layer: CALayer) {
        let target = Float(min(1, max(0, value)))
        if fades {
            guard layer.opacity != target else { return }
            let from = layer.presentation()?.opacity ?? layer.opacity
            set(target, on: layer)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = from
            fade.toValue = target
            fade.duration = NotchGlowPresence.fade
            fade.timingFunction = NotchSongMotion.fadeCurve
            layer.add(fade, forKey: Self.key)
        } else {
            guard layer.opacity != target || layer.animation(forKey: Self.key) != nil else { return }
            layer.removeAnimation(forKey: Self.key)
            set(target, on: layer)
        }
    }

    private func set(_ opacity: Float, on layer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        CATransaction.commit()
    }
}
