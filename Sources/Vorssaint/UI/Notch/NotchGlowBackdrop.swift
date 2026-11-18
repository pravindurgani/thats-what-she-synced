// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Low Power Mode as it stands, for the glows and rings that rest in it.
/// Main thread only.
final class NotchLowPowerMode: ObservableObject {
    static let shared = NotchLowPowerMode()
    @Published private(set) var isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil,
                                                          queue: .main) { [weak self] _ in
            let on = ProcessInfo.processInfo.isLowPowerModeEnabled
            if self?.isOn != on { self?.isOn = on }
        }
    }
}

/// The companion's colours as the island wears them with no song: a cast
/// member's own, or a palette grown from the minimal body's or the robot's
/// (NotchIslandGlow.idleSeeds), toned as a cover's is, so it stands as vivid
/// as the music look. Read through the island's own look and the member a
/// shuffle dealt, as the companion's rig draws it, so the glow follows
/// whoever is out. Main thread only.
enum NotchIdlePalette {
    /// What the palette was made for: the style chosen, the member dealt and the colour chosen.
    private struct Key: Equatable {
        let style: NotchMascotStyle
        let member: NotchMascotStyle
        let palette: NotchMascotPalette
    }

    private static var held: (key: Key, palette: NotchArtworkPalette)?

    static func current() -> NotchArtworkPalette {
        let look = NotchMascotSupport.islandLook()
        let member = NotchMascotShuffleService.shared.member
        let key = Key(style: look.style, member: look.dealing(member).style, palette: look.palette)
        if let held, held.key == key { return held.palette }
        let palette = NotchIslandGlow.idleSeeds(look: look, dealt: member)
            .map { NotchArtworkPalette(pure: $0.map(\.nsColor)) } ?? NotchArtworkPalette.coverless()
        held = (key, palette)
        return palette
    }
}

/// The words' tints while the open island wears the companion's colours,
/// toned from them as a song's are (NotchSongText): opaque tints keep their
/// contrast over colour where white at a fixed opacity would mix with it.
/// Kept apart from NotchSongPaint, which also dresses the companion and sets
/// it bopping: the companion keeps its own colours and stays still.
/// Main thread only.
final class NotchIdlePaint: ObservableObject {
    static let shared = NotchIdlePaint()
    @Published private(set) var text: NotchSongText?
    private init() {}

    func wear(_ palette: NotchArtworkPalette?) {
        let next = palette.map(NotchSongText.init)
        if next != text { text = next }
    }
}

extension NotchSongMode {
    /// The companion's colours in the island while no song wears it (see
    /// NotchIslandGlow): on unless turned off with
    /// `defaults write <bundle id> notchIdleGlowEnabled -bool false`, then
    /// relaunch (a change from another process is read on the next launch).
    /// Low Power Mode turns it off as well.
    static var idleGlowEnabled: Bool { NotchIdleGlowPreferences.enabled }

    /// The closed island showing the agents' strip, where it is on screen.
    static func showsAgentStrip(_ notch: NotchService) -> Bool {
        notch.compactActivity == .agents && closedStripShows(notch) && !notch.showsCompactActivityPicker
    }

    /// The companion resting beside the camera with nothing else in the closed island.
    static func companionRests(_ notch: NotchService) -> Bool {
        notch.mascotAtRest && notch.compactActivity == nil && closedStripShows(notch)
            && !notch.geometry.floats && notch.geometry.restingWingWidth > 0
            && notch.departingMusic == nil && notch.lingeringMusic == nil
    }

    /// The closed island's countdown strip carrying the Office caption five
    /// minutes before a meeting, read as the strip reads it
    /// (NotchCalendarStrip.officeCaption).
    static func countdownCarriesCaption(_ notch: NotchService, _ calendar: NotchCalendarService) -> Bool {
        guard notch.compactActivity == .calendar, closedStripShows(notch), notch.compactCompanion == nil,
              calendar.countdown != nil else { return false }
        return NotchCalendarStrip.officeCaption(geometry: notch.compactActivityGeometry, meeting: calendar.meeting,
                                                now: Date(), language: L10n.shared.language) != nil
    }

    private static func closedStripShows(_ notch: NotchService) -> Bool {
        !notch.expanded && !notch.peeking && notch.notice == nil && !notch.dragPlaceholder
            && notch.captureControls == nil && !notch.fullscreenCompact
    }

    /// The notice the closed island shows in its strip, where it is on screen.
    static func closedNotice(_ notch: NotchService) -> NotchNotice? {
        guard noticeShows(notch), !notch.noticeExpanded else { return nil }
        return notch.notice
    }

    /// The notice the island opened into a card (a call, a meeting, a
    /// connected speaker or a held message), where it is on screen.
    static func openNotice(_ notch: NotchService) -> NotchNotice? {
        guard noticeShows(notch), notch.noticeExpanded else { return nil }
        return notch.notice
    }

    private static func noticeShows(_ notch: NotchService) -> Bool {
        !notch.expanded && !notch.peeking && !notch.dragPlaceholder && notch.captureControls == nil
            && !notch.fullscreenCompact
    }
}

/// The island's ground in colour when no song wears it: the working agents'
/// colours split across their wings, an Office notice's colours under it, and
/// the companion's colours around it at rest and behind the open pages. One
/// glow at a time, by the precedence in NotchIslandGlow; it sits under the
/// song's backdrop, which takes over whenever a song is worn. Mirror windows
/// never draw it.
///
/// It decides what to draw and hands that to NotchGlowStages, which alone
/// follow the island frame by frame: the agents, the companion and the
/// notices are read only when they change, never on every frame of a resize.
/// The closed island's glows are one stage, so a glow passing from the
/// companion to a notice or the agents and back recolours in place.
struct NotchGlowBackdrop: View {
    /// Passed on, not observed: the stages follow the outline.
    let presentation: NotchBackdropPresentation
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var finishes = NotchAgentFinishes.shared
    @ObservedObject private var lowPower = NotchLowPowerMode.shared
    /// A shuffle dealing another member recolours the companion's glow,
    /// cross-faded as the member is.
    @ObservedObject private var shuffle = NotchMascotShuffleService.shared
    /// The meeting five minutes out, whose caption the countdown strip carries.
    @ObservedObject private var calendar = NotchCalendarService.shared
    @Environment(\.colorSchemeContrast) private var contrast
    /// The agents' colours, held while their strip still shows its last
    /// reading after the last agent stopped (NotchStripHold), so the strip
    /// never stands in plain black on its way out.
    @State private var heldAgents: NotchWingGlowColors?

    var body: some View {
        let idleAllowed = NotchIslandGlow.idleAllowed(enabled: NotchSongMode.idleGlowEnabled, lowPower: lowPower.isOn)
        let playing = music.playback?.isPlaying == true
        let songGlows = playing && (NotchSongMode.announcesSong(notch) || NotchSongMode.glowsClosed(notch, music))
        let closedNotice = NotchSongMode.closedNotice(notch)
        // The countdown strip carrying the Office caption glows as the
        // moment's notice does.
        let countdown = NotchSongMode.countdownCarriesCaption(notch, calendar)
            ? NotchIslandGlow.notice(office: true, agent: nil, colours: NotchMomentPaint.source(),
                                     idleAllowed: idleAllowed) : nil
        let closed = NotchIslandGlow.closed(
            agentStrip: NotchSongMode.showsAgentStrip(notch), songGlows: songGlows,
            companionRests: NotchSongMode.companionRests(notch), idleAllowed: idleAllowed,
            notice: closedNotice.flatMap { noticeGlow($0, idleAllowed: idleAllowed) } ?? countdown)
        let open: NotchIslandGlow = notch.expanded
            ? NotchIslandGlow.open(wearsSong: NotchSongMode.wearsSong(notch, music),
                                   plainPage: notch.showingCommandBar || NotchSongMode.showsPlainPage(notch),
                                   companionOn: notch.mascotOn, idleAllowed: idleAllowed)
            : NotchSongMode.openNotice(notch).flatMap { noticeGlow($0, idleAllowed: idleAllowed) }.map { .notice($0) } ?? .none
        let liveAgents = agentColors
        let wings = wingColors(for: closed, agents: liveAgents, mood: NotchMomentMood.of(closedNotice?.office?.kind))
        let palette = openPalette(for: open)
        let increased = contrast == .increased
        let camera = notch.geometry.isNotched
            ? CGSize(width: notch.geometry.cameraWidth, height: notch.geometry.cameraHeight) : nil
        ZStack {
            NotchGlowStage(presentation: presentation, art: wings.map { colors in
                .wings(colors, camera: notch.geometry.floats ? .zero
                           : CGSize(width: notch.geometry.cameraWidth, height: notch.geometry.cameraHeight),
                       // A notice's words keep AA over the strip's veil, as the song's strip does.
                       veil: increased ? .page : closed.isNotice ? .strip : .open)
            })
            NotchGlowStage(presentation: presentation, art: palette.map { palette in
                .aurora(NotchAuroraArt(
                    palette: palette, isPlaying: true,
                    veil: open.isNotice ? (increased ? .page : .vivid)
                        : NotchSongMode.veil(page: true, notch: notch, increasedContrast: increased),
                    quiet: true, still: true, camera: camera, inkShown: true))
            })
        }
        .onChange(of: liveAgents, initial: true) { _, next in if let next { heldAgents = next } }
        // Words take the open glow's tints while its colours are worn.
        .onChange(of: palette, initial: true) { _, next in NotchIdlePaint.shared.wear(next) }
        .onDisappear { NotchIdlePaint.shared.wear(nil) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The working agents' colours, one agent's on both sides, or nil once
    /// the last has stopped.
    private var agentColors: NotchWingGlowColors? {
        guard let sides = NotchAgentWings.glowSides(finishes.model(live: usage.snapshot.live).wings) else { return nil }
        return NotchWingGlowColors(left: sides.left.wingGlow, right: sides.right.wingGlow, fadesEdges: false)
    }

    /// Each side's colours: the agents' own while their strip shows; the
    /// companion's at rest, its lead colour on the side it rests on; a
    /// notice's own, toned for words as the song's strip is, and leaned
    /// toward beet or gold by what the moment means (`mood`).
    private func wingColors(for glow: NotchIslandGlow, agents: NotchWingGlowColors?,
                            mood: NotchMomentMood?) -> NotchWingGlowColors? {
        switch glow {
        case .agents:
            return agents ?? heldAgents
        case .idle:
            let glow = NotchIslandGlow.restingGlow(NotchIdlePalette.current().pure.map(NotchRGB.init))
            guard glow.count >= 3 else { return nil }
            let near = [glow[0], glow[2], glow[1]], far = [glow[1], glow[2], glow[0]]
            let left = notch.mascotSide == .left
            return NotchWingGlowColors(left: left ? near : far, right: left ? far : near, fadesEdges: true)
        case .notice(let source):
            return Self.noticeWings(palette(for: source), agent: source.agent, mood: mood)
        case .song, .none:
            return nil
        }
    }

    /// A notice's wings: an agent's own glow, or the palette's deep colours
    /// spread across both sides, leaned by the moment's mood.
    static func noticeWings(_ palette: NotchArtworkPalette, agent: AgentProvider?,
                            mood: NotchMomentMood?) -> NotchWingGlowColors? {
        func leaned(_ colors: [NotchRGB]) -> [NotchRGB] { mood?.leaned(colors) ?? colors }
        if let agent {
            let glow = leaned(agent.wingGlow)
            return NotchWingGlowColors(left: glow, right: glow, fadesEdges: false)
        }
        let glow = leaned(palette.glow.map(NotchRGB.init))
        guard let first = glow.first else { return nil }
        let three = [first, glow.count > 1 ? glow[1] : first, glow.count > 2 ? glow[2] : first]
        return NotchWingGlowColors(left: [three[0], three[2], three[1]], right: [three[1], three[2], three[0]],
                                   fadesEdges: false)
    }

    /// The open island's colours: the companion's behind its pages, or a
    /// notice's behind the card it opened into.
    private func openPalette(for glow: NotchIslandGlow) -> NotchArtworkPalette? {
        switch glow {
        case .idle: return NotchIdlePalette.current()
        case .notice(let source): return palette(for: source)
        case .song, .agents, .none: return nil
        }
    }

    /// The same palette the moment's props wear (NotchMomentPaint), or the agent's.
    private func palette(for source: NotchNoticeGlow) -> NotchArtworkPalette {
        switch source {
        case .song: return NotchMomentPaint.palette(.song)
        case .agent(let agent): return NotchAgentPalette.of(agent)
        case .companion: return NotchMomentPaint.palette(.companion)
        case .office: return NotchMomentPaint.palette(.office)
        }
    }

    private func noticeGlow(_ notice: NotchNotice, idleAllowed: Bool) -> NotchNoticeGlow? {
        NotchIslandGlow.notice(office: notice.office != nil, agent: notice.agent, colours: NotchMomentPaint.source(),
                               idleAllowed: idleAllowed)
    }
}

extension NotchNoticeGlow {
    /// The agent a notice glows for, if any.
    var agent: AgentProvider? {
        if case .agent(let agent) = self { return agent }
        return nil
    }
}

private extension NotchIslandGlow {
    var isNotice: Bool {
        if case .notice = self { return true }
        return false
    }
}

/// An agent's colours as a palette, for the card its notice opens into.
/// Main thread only.
enum NotchAgentPalette {
    private static var made: [AgentProvider: NotchArtworkPalette] = [:]

    static func of(_ agent: AgentProvider) -> NotchArtworkPalette {
        if let palette = made[agent] { return palette }
        let palette = NotchArtworkPalette(pure: agent.glowStops.map(\.nsColor))
        made[agent] = palette
        return palette
    }
}

private extension NotchRGB {
    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        self.init(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
    }
}

/// What one glow draws: the closed island's wings, or the drifting colour of
/// the open island and the song.
enum NotchGlowArt: Equatable {
    case wings(NotchWingGlowColors, camera: CGSize, veil: NotchAuroraVeil)
    case aurora(NotchAuroraArt)
}

struct NotchAuroraArt: Equatable {
    var palette: NotchArtworkPalette
    var isPlaying: Bool
    var mood: NotchMusicMood = .neutral
    var veil: NotchAuroraVeil
    var quiet = false
    var still = false
    var camera: CGSize?
    var inkShown = true
}

/// One glow, laid out to the island's box and cut to its live outline by the
/// island's own silhouette (the canvas's mask), so it opens and closes with
/// the island on every frame without a mask of its own. It is drawn only
/// while it shows or is fading, and fades along the island's own resize
/// (NotchGlowPresence), holding its last colours on the way out.
struct NotchGlowStage: View {
    @ObservedObject var presentation: NotchBackdropPresentation
    /// What to draw, or nil when the glow is not shown.
    let art: NotchGlowArt?
    @State private var book = Book()
    /// Wakes the stage when a fade in place has run, so a glow gone for good is no longer drawn.
    @State private var wake = 0

    final class Book {
        var presence = NotchGlowPresence()
        var art: NotchGlowArt?
    }

    var body: some View {
        let _ = wake
        let frame = book.presence.step(shown: art != nil, plan: presentation.glowPlan,
                                       progress: presentation.glowProgress, now: CACurrentMediaTime())
        if let art { book.art = art }
        if !frame.mounted { book.art = nil }
        let box = presentation.contour.boundingRect.integral
        return ZStack {
            if frame.mounted, let drawn = book.art, !box.isNull, box.width > 0, box.height > 0 {
                NotchGlowArtView(art: drawn, presence: frame.opacity, fades: frame.fades)
                    .frame(width: box.width, height: box.height)
                    .padding(EdgeInsets(top: box.minY, leading: box.minX, bottom: 0, trailing: 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task(id: book.presence.fadeEnd) {
            guard let end = book.presence.fadeEnd else { return }
            let wait = end - CACurrentMediaTime()
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            if !Task.isCancelled { wake &+= 1 }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct NotchGlowArtView: View {
    let art: NotchGlowArt
    let presence: Double
    let fades: Bool

    var body: some View {
        switch art {
        case .wings(let colors, let camera, let veil):
            NotchWingGlowBridge(colors: colors, camera: camera, veil: veil, presence: presence, fades: fades)
        case .aurora(let aurora):
            NotchMusicAurora(palette: aurora.palette, isPlaying: aurora.isPlaying, mood: aurora.mood, veil: aurora.veil,
                             quiet: aurora.quiet, shown: true, still: aurora.still, camera: aurora.camera,
                             inkShown: aurora.inkShown, presence: presence, fades: fades)
        }
    }
}

private struct NotchWingGlowBridge: NSViewRepresentable {
    let colors: NotchWingGlowColors
    let camera: CGSize
    let veil: NotchAuroraVeil
    let presence: Double
    let fades: Bool

    func makeNSView(context: Context) -> NotchWingGlowView { NotchWingGlowView() }

    func updateNSView(_ view: NotchWingGlowView, context: Context) {
        view.apply(colors: colors, camera: camera, veil: veil, presence: presence, fades: fades)
    }
}
