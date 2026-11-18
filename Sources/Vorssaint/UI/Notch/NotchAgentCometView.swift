// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// The comet ring. A conic gradient in the agent's three colours, cut to a
/// thin ring, turns once every 1.4 seconds with a bright head leading it;
/// behind it a halo breathes in and out. Both are Core Animation run by the
/// render server, so the app does no work per frame, and both are removed
/// whenever the ring is hidden, its window covered or its agent done.
final class NotchAgentCometView: NSView {
    private let halo = CAGradientLayer()
    /// A dark lens inside the ring, so the mark keeps its contrast over the glow.
    private let lens = CAShapeLayer()
    private let track = CAShapeLayer()
    private let orbit = CALayer()
    private let comet = CAGradientLayer()
    private let band = CAShapeLayer()
    private let headGlow = CAGradientLayer()
    private let head = CALayer()
    /// The ring closing in green when the turn ends, from where the head stood.
    private let seal = CAShapeLayer()

    private var stops: [NotchRGB] = []
    private var diameter: CGFloat = 0
    private var finished = false
    private var moves = true
    private var configured = false
    private var visibilityObserver: NSObjectProtocol?

    /// Whether the orbit is installed, and the orbit, the halo's breath and
    /// the closing ring as installed, so tests can check their timing.
    var isMoving: Bool { orbit.animation(forKey: "orbit") != nil }
    var orbitAnimation: CABasicAnimation? { orbit.animation(forKey: "orbit") as? CABasicAnimation }
    var breathAnimation: CABasicAnimation? { halo.animation(forKey: "breath") as? CABasicAnimation }
    var sealShows: Bool { seal.opacity == 1 && seal.strokeEnd == 1 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Layer-hosting, so the geometry below stays bottom-left origin.
        layer = CALayer()
        wantsLayer = true
        setAccessibilityElement(false)
        halo.type = .radial
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        halo.opacity = Self.restingHalo
        lens.fillColor = NSColor.black.withAlphaComponent(0.55).cgColor
        track.fillColor = nil
        track.lineWidth = NotchAgentWings.ringLine
        comet.type = .conic
        comet.startPoint = CGPoint(x: 0.5, y: 0.5)
        comet.endPoint = CGPoint(x: 0.5, y: 1)
        // A conic gradient runs counterclockwise from the top: the head
        // first, its tail fading out behind it as the orbit turns clockwise.
        comet.locations = [0, 0.14, 0.38, 0.7, 1]
        band.fillColor = nil
        band.strokeColor = NSColor.black.cgColor
        band.lineWidth = NotchAgentWings.ringLine
        comet.mask = band
        headGlow.type = .radial
        headGlow.startPoint = CGPoint(x: 0.5, y: 0.5)
        headGlow.endPoint = CGPoint(x: 1, y: 1)
        seal.fillColor = nil
        seal.lineWidth = NotchAgentWings.ringLine + 0.2
        seal.lineCap = .round
        seal.strokeColor = NotchAgentWings.done.cgColor
        seal.strokeEnd = 0
        seal.opacity = 0
        orbit.addSublayer(comet)
        orbit.addSublayer(headGlow)
        orbit.addSublayer(head)
        orbit.addSublayer(seal)
        for sublayer in [halo, lens, track, orbit] { layer?.addSublayer(sublayer) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Where the halo rests when it does not breathe: between its two ends.
    private static let restingHalo: Float = 0.42

    func configure(stops newStops: [NotchRGB], diameter newDiameter: CGFloat, finished newFinished: Bool,
                   moves newMoves: Bool) {
        let restyle = newStops != stops || newDiameter != diameter
        let ending = configured && newFinished != finished
        stops = newStops
        diameter = newDiameter
        moves = newMoves
        let wasFinished = finished
        finished = newFinished
        if restyle {
            paint()
            needsLayout = true
        }
        if ending {
            show(finished: finished, animated: true, from: wasFinished)
        } else if !configured {
            // A ring that first shows finished, as the strip comes back from
            // the finish notice that covered it, still closes as it arrives.
            show(finished: finished, animated: finished, from: false)
        }
        configured = true
        sync()
    }

    /// Dismantled: no motion, no observer.
    func stop() {
        orbit.removeAllAnimations()
        halo.removeAnimation(forKey: "breath")
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = nil
    }

    private func paint() {
        guard stops.count >= 3 else { return }
        let (deep, middle, light) = (stops[0], stops[1], stops[2])
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The head in the lightest stop, its tail deepening and fading to nothing.
        comet.colors = [light.cgColor, middle.cgColor(alpha: 0.95), deep.cgColor(alpha: 0.75),
                        deep.cgColor(alpha: 0), deep.cgColor(alpha: 0)]
        track.strokeColor = deep.cgColor(alpha: 0.24)
        let white = NotchRGB(red: 1, green: 1, blue: 1)
        head.backgroundColor = light.mixed(with: white, by: 0.5).cgColor
        headGlow.colors = [light.cgColor(alpha: 0.95), light.cgColor(alpha: 0)]
        paintHalo()
        CATransaction.commit()
    }

    /// A ring of light just outside the comet, clear in the middle.
    private func paintHalo() {
        let color = finished ? NotchAgentWings.done : stops.first ?? NotchAgentWings.done
        halo.colors = [color.cgColor(alpha: 0), color.cgColor(alpha: 0), color.cgColor(alpha: 0.85),
                       color.cgColor(alpha: 0)]
        halo.locations = [0, 0.48, 0.66, 1]
    }

    /// The comet, or the closed green ring. The turn ending freezes the
    /// orbit where it stands and strokes the green ring from the head round,
    /// in 0.35 seconds; a new turn on the same agent brings the comet back.
    private func show(finished: Bool, animated: Bool, from previous: Bool) {
        let strokes = animated && moves && finished && !previous
        if finished, let turning = orbit.presentation()?.transform, orbit.animation(forKey: "orbit") != nil {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            orbit.transform = turning
            CATransaction.commit()
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.2 : 0)
        CATransaction.setDisableActions(!animated)
        for part in [comet, head, headGlow, track] as [CALayer] { part.opacity = finished ? 0 : 1 }
        seal.opacity = finished ? 1 : 0
        paintHalo()
        CATransaction.commit()
        // Leaving, the green ring fades whole rather than unwinding.
        if finished {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            seal.strokeEnd = 1
            CATransaction.commit()
        }
        if strokes {
            let close = CABasicAnimation(keyPath: "strokeEnd")
            close.fromValue = 0
            close.toValue = 1
            close.duration = NotchAgentWings.closing
            close.timingFunction = CAMediaTimingFunction(name: .easeOut)
            seal.add(close, forKey: "close")
        }
        if !finished {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            orbit.transform = CATransform3DIdentity
            CATransaction.commit()
        }
    }

    // MARK: Motion

    private var visible: Bool {
        !isHiddenOrHasHiddenAncestor && window?.isVisible == true
            && window?.occlusionState.contains(.visible) == true
    }

    /// The orbit and the breath run only while the agent works, motion is
    /// welcome and the ring is on screen; otherwise they are removed, not
    /// paused, and the ring rests with its head at the top.
    private func sync() {
        let runs = configured && !finished && moves && visible && diameter > 0
        guard runs else {
            if orbit.animation(forKey: "orbit") != nil || halo.animation(forKey: "breath") != nil {
                orbit.removeAnimation(forKey: "orbit")
                halo.removeAnimation(forKey: "breath")
            }
            return
        }
        if orbit.animation(forKey: "orbit") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            // Clockwise, the way the head leads its tail.
            spin.toValue = -2 * Double.pi
            spin.duration = NotchAgentWings.orbit
            spin.repeatCount = .infinity
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            // Smooth, yet not at a ProMotion display's 120 frames a second:
            // a two-point head moving this fast reads the same at 60.
            spin.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            orbit.add(spin, forKey: "orbit")
        }
        if halo.animation(forKey: "breath") == nil {
            let breath = CABasicAnimation(keyPath: "opacity")
            breath.fromValue = NotchAgentWings.haloRange.lowerBound
            breath.toValue = NotchAgentWings.haloRange.upperBound
            breath.duration = NotchAgentWings.breath
            breath.autoreverses = true
            breath.repeatCount = .infinity
            breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breath.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            halo.add(breath, forKey: "breath")
        }
    }

    // MARK: Layout and visibility

    override func layout() {
        super.layout()
        let size = diameter
        guard size > 0 else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = (size - NotchAgentWings.ringLine) / 2
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let haloSide = size + NotchAgentWings.haloRoom * 2
        halo.bounds = CGRect(x: 0, y: 0, width: haloSide, height: haloSide)
        halo.position = center
        let inner = size - NotchAgentWings.ringLine * 2
        lens.path = CGPath(ellipseIn: CGRect(x: (size - inner) / 2, y: (size - inner) / 2, width: inner, height: inner),
                           transform: nil)
        for part in [lens, track] {
            part.bounds = box
            part.position = center
        }
        let circle = CGPath(ellipseIn: box.insetBy(dx: NotchAgentWings.ringLine / 2, dy: NotchAgentWings.ringLine / 2),
                            transform: nil)
        track.path = circle
        orbit.bounds = box
        orbit.position = center
        comet.frame = box
        band.frame = box
        band.path = circle
        // The head sits where the gradient ends, at the top of the ring.
        let top = CGPoint(x: size / 2, y: size / 2 + radius)
        let headSide = NotchAgentWings.headSize
        head.bounds = CGRect(x: 0, y: 0, width: headSide, height: headSide)
        head.cornerRadius = headSide / 2
        head.position = top
        let glowSide = headSide * 3.5
        headGlow.bounds = CGRect(x: 0, y: 0, width: glowSide, height: glowSide)
        headGlow.position = top
        seal.frame = box
        let arc = CGMutablePath()
        arc.addArc(center: CGPoint(x: size / 2, y: size / 2), radius: radius, startAngle: .pi / 2,
                   endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        seal.path = arc
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in self?.sync() }
        }
        rescale()
        sync()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rescale()
    }

    override func viewDidHide() { super.viewDidHide(); sync() }
    override func viewDidUnhide() { super.viewDidUnhide(); sync() }

    /// Shapes and gradients draw at the display's own scale, or a ring this
    /// thin turns soft.
    private func rescale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for part in [halo, lens, track, orbit, comet, band, headGlow, head, seal] as [CALayer] { part.contentsScale = scale }
        CATransaction.commit()
    }
}
