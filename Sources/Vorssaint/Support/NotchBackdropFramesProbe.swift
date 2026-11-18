// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import SwiftUI

/// Renders the island frame by frame through the transitions where its glow
/// changes: the open island closing, a notice coming and going over the
/// resting companion, and the agents' strip emptying and leaving. It drives
/// the production window host and the glow's own views, as the island's
/// service drives them (each state change in a transaction that disables
/// animations, then the host's resize), and writes every frame it can draw,
/// cut to the silhouette on screen, to a folder of PNGs with a contact sheet.
/// The panel stays fully transparent; nothing reaches the screen.
///
/// `--backdrop-frames <folder>`
enum NotchBackdropFramesProbe {
    /// What the island shows, as the service would decide it.
    enum Closed: String { case resting, agents, agentsEmptied, notice }

    final class Scene: ObservableObject {
        @Published var expanded = false
        @Published var closed = Closed.resting
    }

    /// The report's numbers read the same in every region.
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func runAndExit(folder: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.main else { print("BACKDROP FRAMES FAILED: no display"); exit(1) }
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Room beside the camera for the resting companion's wings.
        let geometry = NotchGeometry(screen: screen.frame, safeAreaTop: 32, cameraWidth: 210, compactSideRoom: 200)
        var report: [String] = []
        for scenario in Scenario.allCases {
            report.append(run(scenario, geometry: geometry, root: root))
        }
        let text = report.joined(separator: "\n")
        try? text.write(to: root.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        print(text)
        exit(0)
    }

    enum Scenario: String, CaseIterable {
        /// The open island, wearing the companion's colours, closing to the
        /// resting companion's glow, with glass and the floating controls on.
        case collapse
        /// A notice arriving over the resting companion and leaving again.
        case notice
        /// The agents' strip: the last agent stops (the strip holds its
        /// reading), then the strip leaves for the resting companion.
        case agentsLeave
    }

    private struct Frame {
        let time: Double
        let image: CGImage
        let emptyBlack: Double
        let label: String
    }

    private static func run(_ scenario: Scenario, geometry: NotchGeometry, root: URL) -> String {
        let folder = root.appendingPathComponent(scenario.rawValue, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scene = Scene()
        let notice = geometry.noticeSize(wingWidth: 128)
        let agents = CGSize(width: geometry.collapsed.width + 150, height: geometry.collapsed.height)
        let host = NotchWindowHost(content: AnyView(ProbeContent(scene: scene)), geometry: geometry,
                                   size: geometry.collapsed,
                                   background: { presentation in
                                       AnyView(ZStack {
                                           NotchSurfaceBackground(presentation: presentation, glass: true)
                                           ProbeGlowScene(presentation: presentation, scene: scene, geometry: geometry)
                                       }.environment(\.colorScheme, .dark))
                                   },
                                   quickAccess: { _, _ in AnyView(Color.clear) })
        host.panel.alphaValue = 0
        host.panel.ignoresMouseEvents = true
        host.panel.orderFrontRegardless()
        func settle(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
        func change(_ body: () -> Void) {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction, body)
        }
        var frames: [Frame] = []
        var start = CACurrentMediaTime()
        var label = ""
        func record(_ seconds: TimeInterval) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                RunLoop.current.run(until: min(end, Date().addingTimeInterval(1.0 / 120)))
                guard let image = host.probeIslandImage() else { continue }
                frames.append(Frame(time: CACurrentMediaTime() - start, image: image,
                                    emptyBlack: emptyBlackShare(image, camera: geometry), label: label))
            }
        }
        switch scenario {
        case .collapse:
            change { scene.expanded = true }
            host.present(size: geometry.expanded, geometry: geometry, animated: false, quickAccess: .initial,
                         usesGlass: true)
            settle(1.2)
            start = CACurrentMediaTime()
            label = "open"
            record(0.05)
            start = CACurrentMediaTime()
            label = "closing"
            change { scene.expanded = false; scene.closed = .resting }
            host.present(size: geometry.collapsed, geometry: geometry, animated: true, transitionContent: .dismiss)
            record(0.9)
        case .notice:
            change { scene.closed = .resting }
            host.present(size: geometry.collapsed, geometry: geometry, animated: false)
            settle(1.2)
            start = CACurrentMediaTime()
            label = "notice"
            change { scene.closed = .notice }
            host.present(size: notice, geometry: geometry, animated: true, transitionContent: .replace)
            record(0.7)
            label = "notice ends"
            change { scene.closed = .resting }
            host.present(size: geometry.collapsed, geometry: geometry, animated: true, transitionContent: .depart)
            record(NotchMotion.departureHidden)
            host.finishDeparture()
            record(0.6)
        case .agentsLeave:
            change { scene.closed = .agents }
            host.present(size: agents, geometry: geometry, animated: false)
            settle(1.2)
            start = CACurrentMediaTime()
            label = "agent stops"
            change { scene.closed = .agentsEmptied }
            record(0.3)
            label = "strip leaves"
            change { scene.closed = .resting }
            host.present(size: geometry.collapsed, geometry: geometry, animated: true, transitionContent: .replace)
            record(0.8)
        }
        host.close()
        for (index, frame) in frames.enumerated() {
            let name = String(format: "frame-%03d.png", locale: Self.posix, index)
            write(frame.image, to: folder.appendingPathComponent(name))
        }
        if let sheet = contactSheet(frames) { write(sheet, to: root.appendingPathComponent("\(scenario.rawValue)-sheet.png")) }
        let worst = frames.max { $0.emptyBlack < $1.emptyBlack }
        let summary = String(format: "%@: %d frames, worst empty-black share %.2f at %.3f s (%@)", locale: Self.posix,
                             scenario.rawValue, frames.count, worst?.emptyBlack ?? 0, worst?.time ?? 0, worst?.label ?? "-")
        let series = frames.map { String(format: "%.3f:%.2f", locale: Self.posix, $0.time, $0.emptyBlack) }
        return summary + "\n  " + series.joined(separator: " ")
    }

    /// The share of the island's pixels, outside the camera's own black, that
    /// are plain black: no glow and no content.
    private static func emptyBlackShare(_ image: CGImage, camera geometry: NotchGeometry) -> Double {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let cameraMin = (width - Int(geometry.cameraWidth)) / 2, cameraMax = cameraMin + Int(geometry.cameraWidth)
        var island = 0, black = 0
        for row in 0..<height {
            // Rows run from the top in memory.
            let underCamera = row < Int(geometry.cameraHeight)
            for column in 0..<width {
                let offset = (row * width + column) * 4
                guard pixels[offset + 3] > 250 else { continue }
                if underCamera, column >= cameraMin, column < cameraMax { continue }
                island += 1
                if max(pixels[offset], pixels[offset + 1], pixels[offset + 2]) < 9 { black += 1 }
            }
        }
        return island == 0 ? 0 : Double(black) / Double(island)
    }

    private static func write(_ image: CGImage, to url: URL) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Every frame at its own size, four to a row from the top, with its
    /// time and how much of it is empty black, on grey so the shape shows.
    private static func contactSheet(_ frames: [Frame]) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        let columns = 4
        let tileWidth = frames.map(\.image.width).max() ?? 0
        let tileHeight = (frames.map(\.image.height).max() ?? 0) + 18
        let rows = (frames.count + columns - 1) / columns
        let size = NSSize(width: tileWidth * columns, height: tileHeight * rows)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(white: 0.55, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        for (index, frame) in frames.enumerated() {
            let column = index % columns, row = index / columns
            let top = size.height - CGFloat(row * tileHeight)
            let x = CGFloat(column * tileWidth)
            let width = CGFloat(frame.image.width), height = CGFloat(frame.image.height)
            NSImage(cgImage: frame.image, size: NSSize(width: width, height: height))
                .draw(in: NSRect(x: x + (CGFloat(tileWidth) - width) / 2, y: top - 18 - height, width: width, height: height))
            let text = String(format: "#%d %@ %.3fs  empty black %.0f%%", locale: Self.posix,
                              index, frame.label, frame.time, frame.emptyBlack * 100)
            (text as NSString).draw(at: CGPoint(x: x + 4, y: top - 15),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
                                                     .foregroundColor: NSColor.white])
        }
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Stand-in words where the island's content would be.
    private struct ProbeContent: View {
        @ObservedObject var scene: Scene
        var body: some View {
            Group {
                if scene.expanded {
                    VStack(spacing: 8) {
                        Text("Open page").font(.system(size: 22, weight: .semibold))
                        Text("Content fades with the island").font(.system(size: 13))
                    }
                    .padding(.top, 60)
                } else {
                    switch scene.closed {
                    case .resting: Color.clear
                    case .agents, .agentsEmptied:
                        HStack { Text("Claude"); Spacer(); Text("12m") }.padding(.horizontal, 24).padding(.top, 9)
                    case .notice:
                        HStack { Text("Coffee's on."); Spacer(); Text("84%") }.padding(.horizontal, 24).padding(.top, 9)
                    }
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    static let companion = NotchArtworkPalette(pure: (NotchIslandGlow.idleSeeds(
        light: NotchRGB(red: 0.62, green: 0.84, blue: 1), shade: NotchRGB(red: 0.18, green: 0.45, blue: 0.92)) ?? [])
        .map(\.nsColor))
}

/// The island's glows as NotchGlowBackdrop hands them to its stages, with
/// its decisions made from the probe's scene instead of the services: the
/// same precedence (NotchIslandGlow), the same colours and the same stages.
private struct ProbeGlowScene: View {
    let presentation: NotchBackdropPresentation
    @ObservedObject var scene: NotchBackdropFramesProbe.Scene
    let geometry: NotchGeometry
    @State private var heldAgents: NotchWingGlowColors?

    var body: some View {
        let closed = scene.expanded ? NotchIslandGlow.none : NotchIslandGlow.closed(
            agentStrip: scene.closed == .agents || scene.closed == .agentsEmptied, songGlows: false,
            companionRests: scene.closed == .resting, idleAllowed: true,
            notice: scene.closed == .notice
                ? NotchIslandGlow.notice(office: true, agent: nil, colours: .companion, idleAllowed: true) : nil)
        let live = scene.closed == .agents ? Self.agents : nil
        let wings: NotchWingGlowColors? = {
            switch closed {
            case .idle: return Self.resting
            case .agents: return live ?? heldAgents
            case .notice:
                let glow = NotchBackdropFramesProbe.companion.glow.map(Self.rgb)
                return NotchWingGlowColors(left: [glow[0], glow[2], glow[1]], right: [glow[1], glow[2], glow[0]],
                                           fadesEdges: false)
            case .song, .none: return nil
            }
        }()
        let camera = CGSize(width: geometry.cameraWidth, height: geometry.cameraHeight)
        ZStack {
            NotchGlowStage(presentation: presentation, art: wings.map {
                .wings($0, camera: camera, veil: closed == .notice(.companion) ? .strip : .open)
            })
            NotchGlowStage(presentation: presentation, art: scene.expanded
                ? .aurora(NotchAuroraArt(palette: NotchBackdropFramesProbe.companion, isPlaying: true, veil: .vivid,
                                         quiet: true, still: true, camera: camera)) : nil)
        }
        .onChange(of: live, initial: true) { _, next in if let next { heldAgents = next } }
    }

    private static func rgb(_ color: NSColor) -> NotchRGB {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return NotchRGB(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
    }

    private static let resting: NotchWingGlowColors = {
        let glow = NotchIslandGlow.restingGlow(NotchBackdropFramesProbe.companion.pure.map(rgb))
        return NotchWingGlowColors(left: [glow[0], glow[2], glow[1]], right: [glow[1], glow[2], glow[0]], fadesEdges: true)
    }()

    private static let agents = NotchWingGlowColors(left: AgentProvider.claude.wingGlow, right: AgentProvider.claude.wingGlow,
                                                    fadesEdges: false)
}
#endif
