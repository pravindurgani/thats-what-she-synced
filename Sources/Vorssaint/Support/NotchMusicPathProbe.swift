// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import ObjectiveC
import QuartzCore

/// What the music path costs the main thread, without any music: twenty
/// synthetic readings a second, the same every run, go in where the live
/// levels reader would publish them (NotchAudioLevelService.probePublish)
/// and through the production views that answer the beat: the song's
/// aurora, the quick-access bubbles, the companion's bop and the dancers.
/// For each scene it counts the animations added (every `add(_:forKey:)`,
/// implicit ones included) and the presentation layers read, estimates the
/// frames those animations ask the compositor for, and times the main
/// thread. Then it checks that nothing on the path runs while the aurora is
/// covered, not shown or settled as Low Power Mode leaves it.
///
/// With `--frames <folder>` it also renders the beat's response and an
/// agent's wing frame by frame from their presentation layers, with a trace
/// of the moving values, for comparing one build with another.
///
/// Nothing plays, is tapped or reaches the screen: the window stays fully
/// transparent and reports itself visible.
///
/// `--music-path-probe [--seconds N] [--frames <folder>]`
enum NotchMusicPathProbe {
    private static let posix = Locale(identifier: "en_US_POSIX")
    static let reading: CFTimeInterval = 0.05

    static func runAndExit(arguments: [String]) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let seconds = value(after: "--seconds", in: arguments).flatMap(Double.init) ?? 20
        let frames = value(after: "--frames", in: arguments)
        Tally.install()
        var report = [String(format: "MUSIC PATH PROBE  %.0f s a scene, 20 readings a second (%d readings)",
                             locale: posix, seconds, Int(seconds * 20))]
        report.append(measure(.strip, seconds: seconds))
        report.append(measure(.page, seconds: seconds))
        report.append(quiet(seconds: min(seconds, 6)))
        if let frames {
            let root = URL(fileURLWithPath: frames, isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            report.append(render(.strip, seconds: 4, root: root))
            report.append(render(.page, seconds: 4, root: root))
            report.append(renderWing(seconds: 20, root: root))
        }
        let text = report.joined(separator: "\n")
        print(text)
        if let frames {
            try? text.write(to: URL(fileURLWithPath: frames).appendingPathComponent("report.txt"), atomically: true,
                            encoding: .utf8)
        }
        exit(0)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    // MARK: Scenes

    enum Kind: String {
        /// The closed island's strip: the quiet aurora, the dancers on one
        /// wing and a member of the cast on the other.
        case strip
        /// The open music page: the aurora at full voice, two bubbles and
        /// the minimal companion.
        case page
    }

    /// One scene's production views in a window that says it is on screen.
    private final class Scene {
        let window: ProbeWindow
        let container: NSView
        var aurora: NotchMusicAuroraView?
        var bubbles: [NotchAuroraBubbleView] = []
        var companion: NotchMascotHostView?
        var dancers: NotchDancersView?
        let palette: NotchArtworkPalette
        let kind: Kind

        init(_ kind: Kind, dancers withDancers: Bool = true) {
            self.kind = kind
            palette = NotchArtworkPalette(pure: [NSColor(srgbRed: 0.93, green: 0.36, blue: 0.48, alpha: 1),
                                                 NSColor(srgbRed: 0.98, green: 0.72, blue: 0.24, alpha: 1),
                                                 NSColor(srgbRed: 0.30, green: 0.52, blue: 0.98, alpha: 1)],
                                          energy: 0.6)
            NotchSongPaint.shared.wear(palette)
            let size = kind == .strip ? CGSize(width: 340, height: 32) : CGSize(width: 520, height: 170)
            window = ProbeWindow(size: size)
            container = NSView(frame: CGRect(origin: .zero, size: size))
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.black.cgColor
            window.contentView = container
            let aurora = NotchMusicAuroraView(frame: container.bounds)
            container.addSubview(aurora)
            self.aurora = aurora
            apply(shown: true, moves: true)
            let companion = NotchMascotHostView(frame: kind == .strip
                ? CGRect(x: size.width - 40, y: 0, width: 32, height: 32)
                : CGRect(x: size.width - 48, y: size.height - 44, width: 40, height: 40))
            var look = NotchMascotLook(style: kind == .strip ? .scarn : .minimal, shape: .ball, palette: .sky)
            look.followsSong = true
            companion.configure(look: look, size: kind == .strip ? 20 : 26, mood: .idle, idles: false,
                                reduceMotion: false, animated: false)
            container.addSubview(companion)
            self.companion = companion
            if kind == .page {
                for (index, phase) in [0.0, 0.35].enumerated() {
                    let bubble = NotchAuroraBubbleView(phase: phase)
                    bubble.frame = CGRect(x: 12 + CGFloat(index) * 52, y: 12, width: 40, height: 40)
                    bubble.apply(colors: palette.glow, playing: true, moves: true)
                    container.addSubview(bubble)
                    bubbles.append(bubble)
                }
            } else if withDancers {
                let floor = NotchDanceLayout(routine: .farewellThree, height: size.height)
                let dancers = NotchDancersView(frame: CGRect(x: 10, y: 0, width: floor.width, height: floor.height))
                dancers.configure(routine: .farewellThree, playing: true, moves: true,
                                  paint: NotchDancePaint(palette), floor: floor)
                container.addSubview(dancers)
                self.dancers = dancers
            }
            window.orderFrontRegardless()
            container.layoutSubtreeIfNeeded()
        }

        func apply(shown: Bool, moves: Bool) {
            let page = kind == .page
            aurora?.apply(colors: palette.glow, energy: palette.energy, playing: true, moves: moves, mood: .neutral,
                          veil: page ? .open : .strip, quiet: !page, shown: shown,
                          camera: CGSize(width: 180, height: 32), inkShown: page, presence: 1, fades: false)
        }

        /// Every layer each production view owns, by name.
        var owners: [(String, Set<ObjectIdentifier>)] {
            var list: [(String, Set<ObjectIdentifier>)] = []
            if let aurora { list.append(("aurora", Tally.tree(aurora.layer))) }
            if !bubbles.isEmpty {
                list.append(("bubbles", bubbles.reduce(into: Set()) { $0.formUnion(Tally.tree($1.layer)) }))
            }
            if let companion { list.append(("companion", Tally.tree(companion.layer))) }
            if let dancers { list.append(("dancers", Tally.tree(dancers.layer))) }
            return list
        }

        func close() {
            aurora?.teardown()
            dancers?.stop()
            bubbles.forEach { $0.teardown() }
            for view in container.subviews { view.removeFromSuperview() }
            window.orderOut(nil)
            window.close()
            NotchAudioLevelService.shared.probePublish(nil)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        }
    }

    /// A window that is never seen but tells the views it is.
    final class ProbeWindow: NSWindow {
        var exposed = true
        override var isVisible: Bool { true }
        override var occlusionState: NSWindow.OcclusionState { exposed ? [.visible] : [] }

        init(size: CGSize) {
            let origin = NSScreen.main.map { CGPoint(x: $0.frame.minX, y: $0.frame.minY) } ?? .zero
            super.init(contentRect: CGRect(origin: origin, size: size), styleMask: .borderless, backing: .buffered,
                       defer: false)
            isReleasedWhenClosed = false
            alphaValue = 0
            ignoresMouseEvents = true
            hasShadow = false
            backgroundColor = .clear
            isOpaque = false
        }

        func cover(_ covered: Bool) {
            exposed = !covered
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: self)
        }
    }

    // MARK: The readings

    /// Seven bands twenty times a second: a four-on-the-floor kick at 120
    /// beats a minute, a quiet passage, a faster stretch at 133, the reader
    /// stopping for a moment, and the kick again. The same numbers every
    /// run, smoothed as the live reader smooths them.
    struct Signal {
        private var smoother = NotchAudioLevelSupport.Smoother()
        private var lastKick = -100
        private var lastHat = -100

        mutating func reading(_ index: Int) -> [Double]? {
            let i = index % 400
            if (320..<350).contains(i) { smoother = NotchAudioLevelSupport.Smoother(); return nil }
            let quiet = (160..<200).contains(i)
            let beat = (200..<320).contains(i) ? 9 : 10
            let local = i < 200 ? i : i - 200
            if !quiet, local % beat == 0 { lastKick = i }
            if !quiet, local % beat == beat / 2 { lastHat = i }
            let kick = quiet ? 0.0 : 0.95 * pow(0.6, Double(i - lastKick))
            let hat = quiet ? 0.0 : 0.6 * pow(0.5, Double(i - lastHat))
            var raw: [Double] = []
            for band in 0..<NotchAudioLevelSupport.bandCount {
                let noise = Self.noise(i, band)
                switch band {
                case 0, 1: raw.append(max(quiet ? 0.22 : 0.3, kick) + 0.04 * noise)
                case 2, 3, 4: raw.append((quiet ? 0.2 : 0.35) + 0.12 * noise)
                default: raw.append(max(0.1, hat) + 0.08 * noise)
                }
            }
            return smoother.next(raw.map { min(1, max(0, $0)) })
        }

        /// A fixed number from -1 to 1 for each reading and band.
        private static func noise(_ index: Int, _ band: Int) -> Double {
            var x = UInt64(truncatingIfNeeded: index &* 7919 &+ band &* 104_729 &+ 12_345)
            x ^= x >> 33; x &*= 0xFF51_AFD7_ED55_8CCD; x ^= x >> 33; x &*= 0xC4CE_B9FE_1A85_EC53; x ^= x >> 33
            return Double(x % 20_001) / 10_000 - 1
        }
    }

    /// Feeds `seconds` of readings from `start`, each at its own moment, and
    /// calls `frame` `rate` times a second in between.
    private static func drive(seconds: Double, start: CFTimeInterval, frame: ((Double) -> Void)? = nil,
                              rate: Double = 30) {
        var signal = Signal()
        let readings = Int((seconds / reading).rounded())
        var nextReading = 0, nextFrame = 0
        let end = start + seconds
        while true {
            let readingAt = nextReading < readings ? start + Double(nextReading) * reading : .infinity
            let frameAt = frame == nil ? .infinity : start + Double(nextFrame) / rate
            let due = min(readingAt, frameAt)
            if due >= end, nextReading >= readings { break }
            if due > end + 0.001 { break }
            let wait = due - CACurrentMediaTime()
            if wait > 0.0005 {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: wait))
                continue
            }
            if readingAt <= frameAt {
                NotchAudioLevelService.shared.probePublish(signal.reading(nextReading))
                nextReading += 1
            } else {
                frame?(CACurrentMediaTime() - start)
                nextFrame += 1
            }
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.12))
    }

    // MARK: Counting

    private static func measure(_ kind: Kind, seconds: Double) -> String {
        let scene = Scene(kind)
        defer { scene.close() }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.2))
        let start = CACurrentMediaTime()
        Tally.begin(at: start, running: [scene.container.layer])
        let cpu = mainThreadCPU()
        drive(seconds: seconds, start: start)
        let used = mainThreadCPU() - cpu
        let end = CACurrentMediaTime()
        Tally.end(at: end)
        var lines = [Tally.summary(String(format: "%@ (%@)", locale: posix, kind.rawValue,
                                          kind == .strip ? "quiet aurora, dancers, Scarn" : "aurora, two bubbles, minimal companion"),
                                   owners: scene.owners, from: start, to: end)]
        lines.append(String(format: "  main thread %.0f ms in %.1f s (%.1f ms a second)", locale: posix,
                            used * 1000, end - start, used * 1000 / max(0.001, end - start)))
        return lines.joined(separator: "\n")
    }

    /// With the aurora covered, not shown or still as in Low Power Mode,
    /// nothing on the music path may add an animation or read a layer.
    private static func quiet(seconds: Double) -> String {
        var lines = ["unseen (each after a 0.6 s settle, \(Int(seconds)) s of readings):"]
        for state in ["covered", "not shown", "low power"] {
            let scene = Scene(.page)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.2))
            switch state {
            case "covered": scene.window.cover(true)
            case "not shown":
                scene.apply(shown: false, moves: true)
                for view in scene.container.subviews where view !== scene.aurora { view.isHidden = true }
            default:
                scene.apply(shown: true, moves: false)
                scene.bubbles.forEach { $0.apply(colors: scene.palette.glow, playing: true, moves: false) }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))
            let start = CACurrentMediaTime()
            Tally.begin(at: start, running: [scene.container.layer])
            let cpu = mainThreadCPU()
            drive(seconds: seconds, start: start)
            let used = mainThreadCPU() - cpu
            let end = CACurrentMediaTime()
            Tally.end(at: end)
            lines.append(String(format: "  %@ re-arms %d, presentation reads %d, frames asked %.0f, "
                                + "main thread %.1f ms a second",
                                locale: posix, state.padding(toLength: 10, withPad: " ", startingAt: 0),
                                Tally.totalRearms, Tally.totalReads, Tally.framesAsked(from: start, to: end),
                                used * 1000 / max(0.001, end - start)))
            scene.close()
        }
        return lines.joined(separator: "\n")
    }

    private static func mainThreadCPU() -> Double {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let thread = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, thread) }
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1e6
            + Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1e6
    }

    // MARK: Frames

    /// The scene drawn from its presentation layers `rate` times a second,
    /// with the values that move with the beat.
    private static func render(_ kind: Kind, seconds: Double, root: URL) -> String {
        let scene = Scene(kind)
        defer { scene.close() }
        let folder = root.appendingPathComponent(kind.rawValue, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.2))
        var images: [(Double, CGImage)] = []
        var trace = ["t,scrim,swell,rise,bubbleSwell,bubbleVeil,companionScale,companionTurn,spot"]
        let scale: CGFloat = kind == .strip ? 2 : 1
        drive(seconds: seconds, start: CACurrentMediaTime(), frame: { time in
            if let image = draw(scene.container, scale: scale) { images.append((time, image)) }
            trace.append(traceRow(scene, at: time))
        }, rate: 60)
        for (index, frame) in images.enumerated() {
            write(frame.1, to: folder.appendingPathComponent(String(format: "frame-%03d.png", locale: posix, index)))
        }
        if let sheet = contactSheet(images.enumerated().filter { $0.offset % 3 == 0 }.map(\.element), columns: kind == .strip ? 4 : 3) {
            write(sheet, to: root.appendingPathComponent("\(kind.rawValue)-sheet.png"))
        }
        try? trace.joined(separator: "\n").write(to: root.appendingPathComponent("\(kind.rawValue)-trace.csv"),
                                                 atomically: true, encoding: .utf8)
        return "frames \(kind.rawValue): \(images.count) at 60 a second in \(folder.path)"
    }

    private static func traceRow(_ scene: Scene, at time: Double) -> String {
        func shown(_ layer: CALayer?) -> CALayer? { layer.flatMap { $0.presentation() ?? $0 } }
        let canvas = scene.aurora?.layer?.sublayers?.first
        let stage = canvas?.sublayers?.dropFirst().first
        let scrim = canvas?.sublayers?.dropFirst(2).first
        let lift = stage?.sublayers?.dropFirst().first
        let bubble = scene.bubbles.first?.layer?.sublayers?.first
        let bubbleVeil = bubble?.sublayers?.last
        let companion = scene.companion?.mascot.root
        let spot = scene.dancers?.layer?.sublayers?.first?.sublayers?.dropFirst().first
        let turn = shown(companion).map { atan2(Double($0.sublayerTransform.m12), Double($0.sublayerTransform.m11)) } ?? 0
        let values: [Double] = [
            time,
            Double(shown(scrim)?.opacity ?? 0),
            Double(shown(stage)?.transform.m11 ?? 0),
            Double(shown(lift)?.transform.m42 ?? 0),
            Double(shown(bubble)?.sublayerTransform.m11 ?? 0),
            Double(shown(bubbleVeil)?.opacity ?? 0),
            Double(shown(companion).map { hypot($0.sublayerTransform.m11, $0.sublayerTransform.m12) } ?? 0),
            turn,
            Double(shown(spot)?.opacity ?? 0),
        ]
        return values.map { String(format: "%.5f", locale: posix, $0) }.joined(separator: ",")
    }

    /// An agent's wing: its glow, and its comet ring turning with the halo
    /// breathing, drawn 30 times a second.
    private static func renderWing(seconds: Double, root: URL) -> String {
        let size = CGSize(width: 300, height: 32)
        let window = ProbeWindow(size: size)
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = container
        let glow = NotchWingGlowView(frame: container.bounds)
        glow.apply(colors: NotchWingGlowColors(left: AgentProvider.claude.wingGlow, right: AgentProvider.claude.wingGlow,
                                               fadesEdges: false),
                   camera: CGSize(width: 180, height: 32), veil: .open, presence: 1, fades: false)
        container.addSubview(glow)
        let comet = NotchAgentCometView(frame: CGRect(x: 8, y: 1, width: 30, height: 30))
        comet.configure(stops: AgentProvider.claude.glowStops, diameter: 20, finished: false, moves: true)
        container.addSubview(comet)
        window.orderFrontRegardless()
        container.layoutSubtreeIfNeeded()
        let folder = root.appendingPathComponent("wing", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        let start = CACurrentMediaTime()
        Tally.begin(at: start, running: [container.layer])
        var images: [(Double, CGImage)] = []
        var trace = ["t,halo,orbit"]
        let halo = comet.layer?.sublayers?.first
        let orbit = comet.layer?.sublayers?.last
        let cometBox = CGRect(x: 0, y: 0, width: 46, height: 32)
        while CACurrentMediaTime() - start < seconds {
            let time = CACurrentMediaTime() - start
            Tally.pause {
                if let image = draw(container, scale: 3, crop: cometBox) { images.append((time, image)) }
                let shownHalo = halo?.presentation() ?? halo
                let turn = (orbit?.presentation() ?? orbit).map { atan2(Double($0.transform.m12), Double($0.transform.m11)) } ?? 0
                trace.append(String(format: "%.4f,%.4f,%.4f", locale: posix, time, Double(shownHalo?.opacity ?? 0), turn))
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 1.0 / 30))
        }
        let end = CACurrentMediaTime()
        Tally.end(at: end)
        let summary = Tally.summary("wing (glow, one comet)", owners: [("comet", Tally.tree(comet.layer)),
                                                                   ("glow", Tally.tree(glow.layer))],
                                    from: start, to: end, areas: true)
        comet.stop()
        window.orderOut(nil)
        window.close()
        for (index, frame) in images.enumerated() {
            write(frame.1, to: folder.appendingPathComponent(String(format: "frame-%03d.png", locale: posix, index)))
        }
        if let sheet = contactSheet(images.enumerated().filter { $0.offset % 6 == 0 }.map(\.element), columns: 10) {
            write(sheet, to: root.appendingPathComponent("wing-sheet.png"))
        }
        try? trace.joined(separator: "\n").write(to: root.appendingPathComponent("wing-trace.csv"), atomically: true,
                                                 encoding: .utf8)
        return summary + "\nframes wing: \(images.count) at 30 a second in \(folder.path)"
    }

    /// The view as it shows now, from its presentation layers, at `scale`.
    private static func draw(_ view: NSView, scale: CGFloat, crop: CGRect? = nil) -> CGImage? {
        guard let layer = view.layer else { return nil }
        let box = crop ?? view.bounds
        let width = Int(box.width * scale), height = Int(box.height * scale)
        guard width > 0, height > 0, let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        (layer.presentation() ?? layer).render(in: context)
        return context.makeImage()
    }

    private static func write(_ image: CGImage, to url: URL) {
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func contactSheet(_ frames: [(Double, CGImage)], columns: Int) -> CGImage? {
        guard let first = frames.first?.1 else { return nil }
        let tile = CGSize(width: first.width, height: first.height + 16)
        let rows = (frames.count + columns - 1) / columns
        let size = NSSize(width: tile.width * CGFloat(columns), height: tile.height * CGFloat(rows))
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(white: 0.3, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        for (index, frame) in frames.enumerated() {
            let x = CGFloat(index % columns) * tile.width
            let top = size.height - CGFloat(index / columns) * tile.height
            NSImage(cgImage: frame.1, size: NSSize(width: frame.1.width, height: frame.1.height))
                .draw(in: NSRect(x: x, y: top - tile.height, width: CGFloat(frame.1.width), height: CGFloat(frame.1.height)))
            (String(format: "%.3f s", locale: posix, frame.0) as NSString)
                .draw(at: CGPoint(x: x + 3, y: top - 14),
                      withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.white])
        }
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

// MARK: - The tally

/// Counts every animation added to a layer and every presentation layer
/// read, by swapping CALayer's own methods for counting ones while the probe
/// runs. Main thread only.
private enum Tally {
    private static var counting = false
    private static var rearms: [ObjectIdentifier: Int] = [:]
    private static var reads: [ObjectIdentifier: Int] = [:]
    private static var keyPaths: [String: Int] = [:]
    /// When each animation was set to run, and at what frame rate.
    private struct Span {
        let layer: ObjectIdentifier
        let area: CGFloat
        var start: Double
        var end: Double
        let rate: Double
    }
    private static var spans: [Span] = []
    private static var live: [String: Int] = [:]

    static var totalRearms: Int { rearms.values.reduce(0, +) }
    static var totalReads: Int { reads.values.reduce(0, +) }

    static func install() {
        swap(#selector(CALayer.add(_:forKey:)), #selector(CALayer.probeAdd(_:forKey:)))
        swap(NSSelectorFromString("presentationLayer"), #selector(CALayer.probePresentationLayer))
        swap(#selector(CALayer.removeAnimation(forKey:)), #selector(CALayer.probeRemoveAnimation(forKey:)))
        swap(#selector(CALayer.removeAllAnimations), #selector(CALayer.probeRemoveAllAnimations))
    }

    private static func swap(_ original: Selector, _ counting: Selector) {
        guard let a = class_getInstanceMethod(CALayer.self, original),
              let b = class_getInstanceMethod(CALayer.self, counting) else {
            print("MUSIC PATH PROBE: cannot count \(original)")
            return
        }
        method_exchangeImplementations(a, b)
    }

    /// Starts counting. The animations already running under `roots`, such
    /// as the aurora's drift, count toward the frames asked from now on.
    static func begin(at time: Double, running roots: [CALayer?] = []) {
        rearms = [:]; reads = [:]; keyPaths = [:]; spans = []; live = [:]
        func seed(_ layer: CALayer) {
            let id = ObjectIdentifier(layer)
            for key in layer.animationKeys() ?? [] {
                guard let animation = layer.animation(forKey: key) else { continue }
                var running = span(animation, on: layer, now: time)
                running.start = max(running.start, time)
                guard running.end > running.start else { continue }
                spans.append(running)
                live["\(id)|\(key)"] = spans.count - 1
            }
            layer.sublayers?.forEach(seed)
            if let mask = layer.mask { seed(mask) }
        }
        roots.compactMap { $0 }.forEach(seed)
        counting = true
    }

    static func end(at time: Double) {
        counting = false
        for index in spans.indices where spans[index].end > time { spans[index].end = time }
    }

    /// Runs `body` without counting what it does.
    static func pause(_ body: () -> Void) {
        let was = counting
        counting = false
        body()
        counting = was
    }

    static func added(_ animation: CAAnimation, key: String?, to layer: CALayer) {
        guard counting else { return }
        let id = ObjectIdentifier(layer)
        rearms[id, default: 0] += 1
        let path = (animation as? CAPropertyAnimation)?.keyPath
            ?? (animation is CAAnimationGroup ? "group" : String(describing: type(of: animation)))
        keyPaths["\(type(of: layer)) \(path)", default: 0] += 1
        let now = CACurrentMediaTime()
        if let key { close("\(id)|\(key)", at: now) }
        spans.append(span(animation, on: layer, now: now))
        if let key { live["\(id)|\(key)"] = spans.count - 1 }
    }

    /// When `animation` runs on `layer`, and at what rate: 120 a second, a
    /// ProMotion display's, when it asks for none. A duration of 0 is the
    /// transaction's, as an implicit animation's is.
    private static func span(_ animation: CAAnimation, on layer: CALayer, now: Double) -> Span {
        let begin = animation.beginTime > 0 ? layer.convertTime(animation.beginTime, to: nil) : now
        let duration = animation.duration > 0 ? animation.duration : CATransaction.animationDuration()
        let length: Double
        if animation.repeatDuration > 0 {
            length = animation.repeatDuration
        } else if animation.repeatCount == .infinity {
            length = .infinity
        } else {
            length = duration * Double(max(1, animation.repeatCount)) * (animation.autoreverses ? 2 : 1)
        }
        let preferred = Double(animation.preferredFrameRateRange.preferred ?? 0)
        return Span(layer: ObjectIdentifier(layer), area: layer.bounds.width * layer.bounds.height,
                    start: length.isInfinite ? now : max(now, begin),
                    end: length.isInfinite ? .infinity : begin + length, rate: preferred > 0 ? preferred : 120)
    }

    static func read(_ layer: CALayer) {
        guard counting else { return }
        reads[ObjectIdentifier(layer), default: 0] += 1
    }

    static func removed(_ key: String?, from layer: CALayer) {
        guard counting else { return }
        let id = ObjectIdentifier(layer)
        let now = CACurrentMediaTime()
        if let key {
            close("\(id)|\(key)", at: now)
        } else {
            for name in live.keys where name.hasPrefix("\(id)|") { close(name, at: now) }
        }
    }

    private static func close(_ name: String, at time: Double) {
        guard let index = live.removeValue(forKey: name) else { return }
        if spans[index].end > time { spans[index].end = max(spans[index].start, time) }
    }

    static func tree(_ root: CALayer?) -> Set<ObjectIdentifier> {
        guard let root else { return [] }
        var found: Set<ObjectIdentifier> = [ObjectIdentifier(root)]
        for layer in root.sublayers ?? [] { found.formUnion(tree(layer)) }
        if let mask = root.mask { found.formUnion(tree(mask)) }
        return found
    }

    /// Frames asked of the compositor: at each moment the highest rate any
    /// running animation asks for, summed over the run.
    private static func frames(_ chosen: [Span], from start: Double, to end: Double) -> (total: Double, at: [Int: Double]) {
        let bin = 1.0 / 240
        let count = max(1, Int(((end - start) / bin).rounded(.up)))
        var rates = [Double](repeating: 0, count: count)
        for span in chosen {
            let first = max(0, Int(((span.start - start) / bin).rounded(.down)))
            let last = min(count, Int(((min(span.end, end) - start) / bin).rounded(.up)))
            guard first < last else { continue }
            for index in first..<last where rates[index] < span.rate { rates[index] = span.rate }
        }
        var seconds: [Int: Double] = [:]
        for rate in rates where rate > 0 { seconds[Int(rate), default: 0] += bin }
        return (rates.reduce(0) { $0 + $1 * bin }, seconds)
    }

    static func framesAsked(from start: Double, to end: Double) -> Double { frames(spans, from: start, to: end).total }

    /// Animated area: each running animation's layer area times its frames.
    private static func pixelFrames(_ chosen: [Span], from start: Double, to end: Double) -> Double {
        chosen.reduce(0) { sum, span in
            let length = max(0, min(span.end, end) - max(span.start, start))
            return sum + Double(span.area) * span.rate * length
        }
    }

    static func summary(_ title: String, owners: [(String, Set<ObjectIdentifier>)], from start: Double, to end: Double,
                        areas: Bool = false) -> String {
        let posix = Locale(identifier: "en_US_POSIX")
        let length = max(0.001, end - start)
        let all = frames(spans, from: start, to: end)
        let rates = all.at.sorted { $0.key > $1.key }
            .map { String(format: "%d fps %.1f s", locale: posix, $0.key, $0.value) }.joined(separator: ", ")
        var lines = [String(format: "%@: re-arms %d (%.1f a second), presentation reads %d (%.1f a second), "
                            + "frames asked %.0f (%.1f a second; %@)", locale: posix, title, totalRearms,
                            Double(totalRearms) / length, totalReads, Double(totalReads) / length, all.total,
                            all.total / length, rates.isEmpty ? "none" : rates)]
        var claimed: Set<ObjectIdentifier> = []
        for (name, layers) in owners {
            claimed.formUnion(layers)
            let own = spans.filter { layers.contains($0.layer) }
            let ownRearms = rearms.filter { layers.contains($0.key) }.values.reduce(0, +)
            let ownReads = reads.filter { layers.contains($0.key) }.values.reduce(0, +)
            var line = String(format: "  %@ re-arms %5d, reads %5d, frames asked %6.0f", locale: posix,
                              name.padding(toLength: 10, withPad: " ", startingAt: 0),
                              ownRearms, ownReads, frames(own, from: start, to: end).total)
            if areas {
                line += String(format: ", animated area %.2f Mpt·frames", locale: posix,
                               pixelFrames(own, from: start, to: end) / 1e6)
            }
            lines.append(line)
        }
        let otherRearms = rearms.filter { !claimed.contains($0.key) }.values.reduce(0, +)
        let otherReads = reads.filter { !claimed.contains($0.key) }.values.reduce(0, +)
        if otherRearms + otherReads > 0 {
            lines.append(String(format: "  other      re-arms %5d, reads %5d", locale: posix, otherRearms, otherReads))
        }
        let top = keyPaths.sorted { $0.value > $1.value }.prefix(8)
            .map { "\($0.key) \($0.value)" }.joined(separator: "; ")
        if !top.isEmpty { lines.append("  by key path: " + top) }
        return lines.joined(separator: "\n")
    }
}

private extension CALayer {
    // After the swap each of these names the original, so calling it from
    // its own body runs CALayer's own method.
    @objc func probeAdd(_ animation: CAAnimation, forKey key: String?) {
        Tally.added(animation, key: key, to: self)
        probeAdd(animation, forKey: key)
    }

    @objc func probePresentationLayer() -> Any? {
        Tally.read(self)
        return probePresentationLayer()
    }

    @objc func probeRemoveAnimation(forKey key: String) {
        Tally.removed(key, from: self)
        probeRemoveAnimation(forKey: key)
    }

    @objc func probeRemoveAllAnimations() {
        Tally.removed(nil, from: self)
        probeRemoveAllAnimations()
    }
}
#endif
