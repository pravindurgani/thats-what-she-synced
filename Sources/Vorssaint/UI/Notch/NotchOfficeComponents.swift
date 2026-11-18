// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore
import SwiftUI

/// The documentary's shared pieces, so every Office moment speaks one
/// language: the punch-in entrance, the lower third and the conference-room
/// blinds, plus the two loops that run on the render server (a desk phone's
/// rings and a mug's steam). The rules behind them are NotchOfficeMoments.
enum NotchOfficeInk {
    static let mustard = Color(red: 0xC9 / 255, green: 0xA2 / 255, blue: 0x27 / 255)
    static let paper = Color(red: 0xF4 / 255, green: 0xF1 / 255, blue: 0xE8 / 255)
    static let beet = Color(red: 0xC0 / 255, green: 0x39 / 255, blue: 0x2B / 255)
    static let jelly = Color(red: 0xF4 / 255, green: 0xD0 / 255, blue: 0x3F / 255)
    static let gold = Color(red: 0xE3 / 255, green: 0xB2 / 255, blue: 0x3C / 255)
    static let goldLight = Color(red: 0xF7 / 255, green: 0xD7 / 255, blue: 0x74 / 255)
    static let mug = Color(red: 0xF7 / 255, green: 0xF5 / 255, blue: 0xF0 / 255)
    static let ink = Color(red: 0x1B / 255, green: 0x1B / 255, blue: 0x1F / 255)
    static let boombox = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2E / 255)
    /// Coffee with no song or companion to colour it.
    static let latte = Color(red: 0xC8 / 255, green: 0x91 / 255, blue: 0x5A / 255)

    /// The moment's colours: the loaded song's, else the companion's, else
    /// the Office's own jelly yellow and mustard, never fewer than two. The island
    /// is never left grey for want of a song.
    static func colors() -> [Color] {
        guard let paint = NotchLevelPaint.volume(), !paint.isEmpty else { return [jelly, mustard] }
        return paint.count > 1 ? paint : paint + paint
    }

    /// The coffee in the mug: the moment's lead colour, or a latte.
    static func coffee() -> Color { NotchLevelPaint.volume()?.first ?? latte }
}

// MARK: - The punch-in

/// The documentary's snap-zoom: what the moment is about scales in from 0.9
/// on the song's spring, with the slightest overshoot, as it fades up.
/// Reduce Motion and Low Power Mode keep the fade alone.
struct NotchPunchIn: ViewModifier {
    let trigger: String
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared
    @State private var arrived = false

    private var calm: Bool { reduceMotion || lowPower.isOn }

    func body(content: Content) -> some View {
        content
            .opacity(arrived ? 1 : 0)
            .animation(calm ? NotchSongMotion.reduced : .easeOut(duration: 0.16).delay(delay), value: arrived)
            .scaleEffect(arrived || calm ? 1 : 0.9)
            .animation(calm ? nil : NotchSongMotion.spring.delay(delay), value: arrived)
            .task(id: trigger) {
                var reset = Transaction(animation: nil)
                reset.disablesAnimations = true
                withTransaction(reset) { arrived = false }
                try? await Task.sleep(nanoseconds: 16_000_000)
                arrived = true
            }
    }
}

extension View {
    /// The punch-in on Office moments only; anything else is left as it was.
    @ViewBuilder func notchPunchIn(_ trigger: String?, delay: Double = 0) -> some View {
        if let trigger {
            modifier(NotchPunchIn(trigger: trigger, delay: delay))
        } else {
            self
        }
    }
}

// MARK: - The lower third

/// The parody caption under the real information: small mono words beside
/// a thin mustard rule. It is decoration, so VoiceOver skips it and reads
/// only what the notice says.
struct NotchLowerThird: View {
    enum Size { case strip, card }

    let caption: String
    var size: Size = .strip
    var accent: Color = NotchOfficeInk.mustard
    /// Whether the rule leads the words: the second half of a caption split
    /// around the camera continues the line without one.
    var rule = true
    var trigger: String? = nil
    var delay: Double = 0.22

    var body: some View {
        let font = size == .strip ? NotchOfficeMoments.stripCaptionFont : NotchOfficeMoments.cardCaptionFont
        let marker = size == .strip ? NotchOfficeMoments.stripRule : NotchOfficeMoments.cardRule
        HStack(spacing: marker.gap) {
            if rule {
                RoundedRectangle(cornerRadius: marker.width / 2)
                    .fill(accent)
                    .frame(width: marker.width, height: NotchOfficeMoments.captionHeight(font) - 1)
            }
            Text(caption)
                .font(Font(font as CTFont))
                .foregroundStyle(NotchOfficeInk.paper.opacity(size == .strip ? 0.8 : 0.86))
                .lineLimit(1)
                .fixedSize()
        }
        .notchArrival(trigger, delay: delay)
        .accessibilityHidden(true)
    }
}

// MARK: - The steam puff

/// One puff of steam off a fresh cup: two wisps curl up out of the brim and
/// fade, once, in half a second, on the song's arrival curve. It never
/// loops: a new trigger plays it again from the start rather than adding
/// another. Reduce Motion and Low Power Mode leave it out. The Office
/// edition's mug puffs it in the island's bottom row and in its notice.
struct NotchOfficeSteamPuff: View {
    var color: Color = .white.opacity(0.85)
    /// Changes once per puff; nil keeps it still and unseen.
    let trigger: String?
    /// How long after the trigger the wisps leave the brim.
    var delay: Double = 0.08
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared
    @State private var risen = false
    @State private var shown = false

    var body: some View {
        NotchOfficeWisps()
            .stroke(color, style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            .scaleEffect(x: risen ? 1.2 : 0.7, y: 1, anchor: .bottom)
            .offset(y: risen ? -3 : 1)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: trigger) {
                var reset = Transaction(animation: nil)
                reset.disablesAnimations = true
                withTransaction(reset) { risen = false; shown = false }
                guard trigger != nil, !reduceMotion, !lowPower.isOn else { return }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                withAnimation(NotchSongMotion.arrive) { risen = true; shown = true }
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(NotchSongMotion.fade) { shown = false }
            }
    }
}

/// Two S-shaped wisps side by side, curling up from the bottom edge.
struct NotchOfficeWisps: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width / 2
        for index in 0..<2 {
            let x = rect.minX + width * (CGFloat(index) + 0.5)
            path.move(to: CGPoint(x: x, y: rect.maxY - 0.5))
            path.addCurve(to: CGPoint(x: x, y: rect.minY + 0.5),
                          control1: CGPoint(x: x + width * 0.45, y: rect.maxY - rect.height * 0.33),
                          control2: CGPoint(x: x - width * 0.45, y: rect.maxY - rect.height * 0.66))
        }
        return path
    }
}

// MARK: - The blinds

/// The talking-head window: faint horizontal slats, two points of light
/// every five, fading out toward the card's ends.
struct NotchBlinds: View {
    var opacity: Double = 0.06

    var body: some View {
        NotchBlindsShape()
            .fill(.white.opacity(opacity))
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.18),
                                         .init(color: .white, location: 0.82), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct NotchBlindsShape: Shape {
    var slat: CGFloat = 2
    var pitch: CGFloat = 5

    /// The brightness window's slats ease open and shut with the level.
    var animatableData: CGFloat {
        get { slat }
        set { slat = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var y = rect.minY + (pitch - slat) / 2
        while y < rect.maxY {
            path.addRect(CGRect(x: rect.minX, y: y, width: rect.width, height: min(slat, rect.maxY - y)))
            y += pitch
        }
        return path
    }
}

// MARK: - The loops

/// A view whose Core Animation loop runs only while its window is on screen
/// and visible: the render server plays it, and nothing ticks in the app.
class NotchOfficeLoopView: NSView {
    private var visibilityObserver: NSObjectProtocol?
    private(set) var animates = false
    private var moving = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setAnimates(_ animates: Bool) {
        self.animates = animates
        sync()
    }

    func stop() {
        animates = false
        sync()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in self?.sync() }
        }
        sync()
    }

    override func viewDidHide() { super.viewDidHide(); sync() }
    override func viewDidUnhide() { super.viewDidUnhide(); sync() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arrange()
        CATransaction.commit()
    }

    /// Starts the loop when it should show and stops it when it should not;
    /// stopped, the layers hold their resting look.
    func sync() {
        let wanted = animates && !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        guard wanted != moving else { return }
        moving = wanted
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if wanted { startLoop() } else { stopLoop() }
        CATransaction.commit()
    }

    var scale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    /// For subclasses: lay the layers out, start and stop the loop.
    func arrange() {}
    func startLoop() {}
    func stopLoop() {}
}

/// A desk phone ringing: two quick rings spread from the caller, then a
/// pause, over and over while the card shows, and the handset rattles with
/// each pair. At rest, under Reduce Motion, one quiet ring stays.
final class NotchOfficeRingView: NotchOfficeLoopView {
    private let rings = [CAShapeLayer(), CAShapeLayer()]
    private let disc = CAGradientLayer()
    private let discMask = CAShapeLayer()
    private let glyph = CALayer()
    private var colors: [NSColor] = [.white, .white]
    private var symbol: String?
    private var side: CGFloat = 40
    private var glyphSize: CGFloat = 16
    /// One ring, a beat, the second, then the rest of the pause.
    static let period: CFTimeInterval = 1.6
    static let secondRing: CFTimeInterval = 0.22

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for ring in rings {
            ring.fillColor = nil
            ring.lineWidth = 1.25
            layer?.addSublayer(ring)
        }
        disc.mask = discMask
        layer?.addSublayer(disc)
        layer?.addSublayer(glyph)
    }

    required init?(coder: NSCoder) { nil }

    func configure(colors: [NSColor], symbol: String?, side: CGFloat, glyphSize: CGFloat, animates: Bool) {
        let changed = colors != self.colors || symbol != self.symbol || side != self.side || glyphSize != self.glyphSize
        self.colors = colors.count > 1 ? colors : colors + colors + [.white, .white]
        self.symbol = symbol
        self.side = side
        self.glyphSize = glyphSize
        if changed {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            disc.colors = [self.colors[0].cgColor, self.colors[1].cgColor]
            disc.startPoint = CGPoint(x: 0, y: 1)
            disc.endPoint = CGPoint(x: 1, y: 0)
            rings[0].strokeColor = self.colors[0].cgColor
            rings[1].strokeColor = self.colors[1].cgColor
            disc.isHidden = symbol == nil
            renderGlyph()
            arrange()
            CATransaction.commit()
        }
        setAnimates(animates)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderGlyph()
    }

    override func arrange() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let box = CGRect(x: 0, y: 0, width: side, height: side)
        for layer in [rings[0], rings[1], disc] as [CALayer] {
            layer.bounds = box
            layer.position = center
        }
        for ring in rings { ring.path = CGPath(ellipseIn: box.insetBy(dx: 0.8, dy: 0.8), transform: nil) }
        discMask.frame = box
        discMask.path = CGPath(ellipseIn: box, transform: nil)
        glyph.bounds = CGRect(x: 0, y: 0, width: glyphSize * 1.4, height: glyphSize * 1.4)
        glyph.position = center
        if !isLooping { rest() }
    }

    private var isLooping: Bool { rings[0].animation(forKey: "ring") != nil }

    /// The quiet ring Reduce Motion keeps, and what shows before the loop starts.
    private func rest() {
        rings[0].opacity = 0.5
        rings[0].transform = CATransform3DMakeScale(1.22, 1.22, 1)
        rings[1].opacity = 0
        glyph.transform = CATransform3DIdentity
    }

    private func renderGlyph() {
        guard let symbol, glyphSize > 0,
              let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: glyphSize, weight: .semibold)) else {
            glyph.contents = nil
            return
        }
        let scale = self.scale
        let side = glyphSize * 1.4
        let pixels = max(1, Int(ceil(side * scale)))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let fit = min(CGFloat(pixels) / max(1, image.size.width), CGFloat(pixels) / max(1, image.size.height)) * 0.78
        let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        let rect = CGRect(x: (CGFloat(pixels) - size.width) / 2, y: (CGFloat(pixels) - size.height) / 2,
                          width: size.width, height: size.height)
        image.draw(in: rect)
        // Dark ink on a light colour, white on the rest, so it keeps its contrast.
        let lead = colors[0].usingColorSpace(.sRGB) ?? colors[0]
        let luminance = 0.2126 * lead.redComponent + 0.7152 * lead.greenComponent + 0.0722 * lead.blueComponent
        (luminance > 0.62 ? NSColor(srgbRed: 0x1B / 255, green: 0x1B / 255, blue: 0x1F / 255, alpha: 1) : .white).setFill()
        rect.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()
        glyph.contents = bitmap.cgImage
        glyph.contentsScale = scale
    }

    override func startLoop() {
        let now = CACurrentMediaTime()
        for (index, ring) in rings.enumerated() {
            ring.opacity = 0
            ring.transform = CATransform3DIdentity
            let spread = CABasicAnimation(keyPath: "transform.scale")
            spread.fromValue = 0.92
            spread.toValue = 1.8
            spread.duration = 0.85
            spread.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.95
            fade.toValue = 0
            fade.duration = 0.85
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            let group = CAAnimationGroup()
            group.animations = [spread, fade]
            group.duration = Self.period
            group.repeatCount = .infinity
            group.beginTime = now + (index == 0 ? 0 : Self.secondRing)
            ring.add(group, forKey: "ring")
        }
        // The handset rattles in its cradle with the pair of rings.
        let rattle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rattle.values = [0, 0.26, -0.26, 0.26, -0.26, 0.14, 0, 0]
        rattle.keyTimes = [0, 0.05, 0.1, 0.15, 0.2, 0.26, 0.32, 1]
        rattle.duration = Self.period
        rattle.repeatCount = .infinity
        rattle.beginTime = now
        glyph.add(rattle, forKey: "rattle")
    }

    override func stopLoop() {
        for ring in rings { ring.removeAnimation(forKey: "ring") }
        glyph.removeAnimation(forKey: "rattle")
        rest()
    }
}

/// A fresh mug's steam: two wisps curling up in turn while the mug fills.
/// At rest, under Reduce Motion, one faint wisp stays.
final class NotchOfficeSteamView: NotchOfficeLoopView {
    private let wisps = [CAShapeLayer(), CAShapeLayer()]
    private var color: NSColor = .white
    static let period: CFTimeInterval = 1.8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for wisp in wisps {
            wisp.fillColor = nil
            wisp.lineWidth = 1.1
            wisp.lineCap = .round
            layer?.addSublayer(wisp)
        }
    }

    required init?(coder: NSCoder) { nil }

    func configure(color: NSColor, animates: Bool) {
        if color != self.color {
            self.color = color
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for wisp in wisps { wisp.strokeColor = color.cgColor }
            CATransaction.commit()
        }
        setAnimates(animates)
    }

    override func arrange() {
        let width = bounds.width / 2
        for (index, wisp) in wisps.enumerated() {
            let box = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            wisp.bounds = box
            wisp.anchorPoint = CGPoint(x: 0.5, y: 0)
            wisp.position = CGPoint(x: width * (CGFloat(index) + 0.5), y: 0)
            // An S curling upward from the brim.
            let path = CGMutablePath()
            path.move(to: CGPoint(x: width / 2, y: 0.5))
            path.addCurve(to: CGPoint(x: width / 2, y: box.height - 0.5),
                          control1: CGPoint(x: width * 0.95, y: box.height * 0.33),
                          control2: CGPoint(x: width * 0.05, y: box.height * 0.66))
            wisp.path = path
        }
        if wisps[0].animation(forKey: "steam") == nil { rest() }
    }

    private func rest() {
        wisps[0].opacity = 0.45
        wisps[1].opacity = 0
        for wisp in wisps { wisp.transform = CATransform3DIdentity }
    }

    override func startLoop() {
        let now = CACurrentMediaTime()
        for (index, wisp) in wisps.enumerated() {
            wisp.opacity = 0
            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = -2
            rise.toValue = 3
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.75, 0]
            fade.keyTimes = [0, 0.35, 1]
            let curl = CABasicAnimation(keyPath: "transform.scale.x")
            curl.fromValue = 0.7
            curl.toValue = 1.25
            let group = CAAnimationGroup()
            group.animations = [rise, fade, curl]
            for animation in group.animations ?? [] { animation.duration = Self.period }
            group.duration = Self.period
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.beginTime = now + Double(index) * Self.period / 2
            wisp.add(group, forKey: "steam")
        }
    }

    override func stopLoop() {
        for wisp in wisps { wisp.removeAnimation(forKey: "steam") }
        rest()
    }
}

/// The ringing caller, for SwiftUI.
struct NotchOfficeRing: NSViewRepresentable {
    let colors: [Color]
    var symbol: String? = "phone.fill"
    let side: CGFloat
    var glyphSize: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Rests in Low Power Mode, as every other loop on the island does.
    @ObservedObject private var lowPower = NotchLowPowerMode.shared

    func makeNSView(context: Context) -> NotchOfficeRingView { NotchOfficeRingView() }

    func updateNSView(_ view: NotchOfficeRingView, context: Context) {
        view.configure(colors: colors.map { NSColor($0) }, symbol: symbol, side: side, glyphSize: glyphSize,
                       animates: !reduceMotion && !lowPower.isOn)
    }

    static func dismantleNSView(_ view: NotchOfficeRingView, coordinator: ()) { view.stop() }
}

/// The mug's steam, for SwiftUI.
struct NotchOfficeSteam: NSViewRepresentable {
    var color: Color = .white.opacity(0.8)
    var animates = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared

    func makeNSView(context: Context) -> NotchOfficeSteamView { NotchOfficeSteamView() }

    func updateNSView(_ view: NotchOfficeSteamView, context: Context) {
        view.configure(color: NSColor(color), animates: animates && !reduceMotion && !lowPower.isOn)
    }

    static func dismantleNSView(_ view: NotchOfficeSteamView, coordinator: ()) { view.stop() }
}
