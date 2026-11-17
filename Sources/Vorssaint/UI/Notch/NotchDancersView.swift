// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// Dancers in place of the closed strip's bars: a dance from the "Music
/// side" setting, on the island's beat, in the song's colours. Like the
/// bars, only this small view observes what it draws from, so its updates
/// never re-render the island. Under Reduce Motion, and in Low Power Mode,
/// they stand in one pose and only their colours change, as the agents'
/// rings rest.
struct NotchDancers: View {
    let routine: NotchDanceRoutine
    var isPlaying = true
    /// The strip's own song palette, for when the island is not wearing one.
    var palette: NotchArtworkPalette?
    var height: CGFloat
    @ObservedObject private var paint = NotchSongPaint.shared
    @ObservedObject private var lowPower = NotchLowPowerMode.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NotchDancersBridge(routine: routine, playing: isPlaying, moves: !reduceMotion && !lowPower.isOn,
                           paint: NotchDancePaint(paint.palette ?? palette ?? NotchArtworkPalette.coverless()),
                           height: height)
            .frame(width: NotchDanceFloor.width, height: height)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

extension NotchDancePaint {
    /// The cover's mark colours, bright enough to read on the island's
    /// colour, for ties, rims and cones; heads keep one neutral fill.
    init(_ palette: NotchArtworkPalette) {
        self.init(accents: palette.marks, head: NotchDancePaint.neutralHead)
    }
}

/// Which dance the strip shows for a song. Shuffle's deal is shared, so the
/// island's copies on other displays and a strip on its way out agree on it.
/// A song is told by its title and artist, as the companion's shuffle tells
/// it, and a new one keeps the last dance until its names settle: players
/// send the title before the artist, and a deal on each reading would change
/// the dance twice for one song. The strips observe this, so they are drawn
/// again, and ask again, once the wait is up; with no song waiting, nothing
/// is scheduled. Main thread only.
final class NotchDanceSelection: ObservableObject {
    static let shared = NotchDanceSelection()
    private var shuffle = NotchDanceShuffle()
    private var askWork: DispatchWorkItem?
    private var askAt: TimeInterval?

    private init() {}

    func routine(for side: NotchMusicSide, track: RadialNowPlayingSnapshot) -> NotchDanceRoutine? {
        guard side == .shuffle else { return side.routine }
        let song = NotchMascotShuffle.songKey(title: track.title, artist: track.artist)
        let now = ProcessInfo.processInfo.systemUptime
        let routine = side.routine(for: song, at: now, shuffle: &shuffle) { Int.random(in: 0..<max(1, $0)) }
        askAgain(at: shuffle.settle.due, now: now)
        return routine
    }

    /// Asked from a strip's body, so it only schedules: the strips are drawn
    /// again on a later turn of the main queue, once the waiting song is due.
    private func askAgain(at due: TimeInterval?, now: TimeInterval) {
        guard due != askAt else { return }
        askWork?.cancel()
        askWork = nil
        askAt = due
        // Only a song still settling is worth asking about again; a time
        // already past belongs to a song that is no longer playing.
        guard let due, due > now else { askAt = nil; return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.askWork = nil
            self.askAt = nil
            self.objectWillChange.send()
        }
        askWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, due - now), execute: work)
    }
}

private struct NotchDancersBridge: NSViewRepresentable {
    let routine: NotchDanceRoutine
    let playing: Bool
    let moves: Bool
    let paint: NotchDancePaint
    let height: CGFloat

    func makeNSView(context: Context) -> NotchDancersView { NotchDancersView() }

    func updateNSView(_ view: NotchDancersView, context: Context) {
        view.configure(routine: routine, playing: playing, moves: moves, paint: paint, height: height)
    }

    static func dismantleNSView(_ view: NotchDancersView, coordinator: ()) { view.stop() }
}

/// Hosts the dancers' layers and decides when they move. While a song plays
/// and the view is on screen they join the conductor, which hands them each
/// beat; paused, they settle into their rest; hidden, covered or closed,
/// they stop listening and nothing runs. Without `moves`, under Reduce
/// Motion or in Low Power Mode, they stand in one pose with no timer
/// running, and only their colours change.
final class NotchDancersView: NSView {
    private let stage = NotchDanceStage()
    private var routine: NotchDanceRoutine?
    private var playing = false
    private var moves = true
    private var height: CGFloat = 0
    private(set) var isDancing = false
    private var visibilityObserver: NSObjectProtocol?
    /// Bumped whenever the dance stops or changes, so a half-beat move
    /// still waiting to start is dropped.
    private var generation = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(stage.layer)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(routine: NotchDanceRoutine, playing: Bool, moves: Bool, paint: NotchDancePaint, height: CGFloat) {
        let fresh = routine != self.routine || height != self.height
        self.playing = playing
        self.moves = moves
        self.height = height
        if fresh {
            // A new dance opens on its loop's first count, even when one
            // song runs straight into the next without a pause.
            if self.routine != nil, routine != self.routine { NotchDanceConductor.shared.restartCount() }
            self.routine = routine
            generation &+= 1
            // A new song's dance mid-song starts in its groove; the next
            // beat moves it on. Seen, another dance cross-fades in over the last.
            let poses = isDancing && moves ? routine.dancers.indices.map(routine.groove) : standingPoses(routine)
            stage.configure(routine: routine, floorHeight: height, poses: poses, contentsScale: backingScale,
                            fades: window != nil)
            stage.layer.frame = CGRect(x: 0, y: 0, width: NotchDanceFloor.width, height: height)
        }
        stage.wear(paint, animated: window != nil)
        sync()
    }

    /// Off the island for good: no beat, no waiting move.
    func stop() {
        playing = false
        leaveDance()
        stage.halt()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = nil
    }

    /// One beat from the conductor. The middle of the Farewell Three answers
    /// half a beat late, so its move waits; one that would start after the
    /// dance stopped or changed, or after the next beat already came, is
    /// dropped (NotchDanceTiming.heldStepPlays).
    func dance(beat: Int, energy: Double, interval: Double) {
        guard isDancing, let routine else { return }
        let token = generation
        for index in routine.dancers.indices {
            let step = routine.step(index, beat: beat, energy: energy, interval: interval,
                                    settle: NotchSongMotion.beatReturn)
            if step.delay > 0.005 {
                DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) { [weak self] in
                    guard let self, self.isDancing,
                          NotchDanceTiming.heldStepPlays(beat: beat, generation: token,
                                                         latestBeat: NotchDanceConductor.shared.beat,
                                                         latestGeneration: self.generation) else { return }
                    self.stage.play(step, dancer: index)
                }
            } else {
                stage.play(step, dancer: index)
            }
        }
        stage.pulse(NotchDanceTiming.amplitude(energy))
    }

    private var exposed: Bool {
        !isHiddenOrHasHiddenAncestor && window?.isVisible == true
            && window?.occlusionState.contains(.visible) == true
    }

    /// Paused, standing at rest; without `moves`, the dance's one pose.
    private func standingPoses(_ routine: NotchDanceRoutine) -> [NotchDancerPose] {
        routine.dancers.indices.map { moves ? routine.rest($0) : routine.still($0) }
    }

    private func sync() {
        guard let routine else { return }
        if playing && moves && exposed {
            guard !isDancing else { return }
            isDancing = true
            // Into the groove from wherever they stand; the conductor's next
            // beat, or its stand-in, starts the dance.
            stage.show(routine.dancers.indices.map(routine.groove), duration: NotchSongMotion.beatReturn)
            NotchDanceConductor.shared.join(self)
            return
        }
        leaveDance()
        let standing = standingPoses(routine)
        guard stage.poses != standing else { return }
        // Seen pausing, they settle; hidden or still, they are simply there.
        stage.show(standing, duration: moves && exposed ? NotchSongMotion.beatReturn : 0)
    }

    private func leaveDance() {
        guard isDancing else { return }
        isDancing = false
        generation &+= 1
        NotchDanceConductor.shared.leave(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in self?.sync() }
        }
        stage.setContentsScale(backingScale)
        sync()
    }

    override func viewDidHide() { super.viewDidHide(); sync() }
    override func viewDidUnhide() { super.viewDidUnhide(); sync() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        stage.setContentsScale(backingScale)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.layer.frame = CGRect(x: 0, y: 0, width: NotchDanceFloor.width, height: height)
        CATransaction.commit()
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
}

/// One count for every copy of the dancers on screen: the island's and the
/// ones on other displays step together. It listens to the island's beat
/// only while some dancers dance, and when no beat comes, through a quiet
/// passage or with the live levels off, it stands in with a step every half
/// second so a playing song never leaves them frozen. With no dancers it
/// holds no subscription and no timer. Main thread only.
final class NotchDanceConductor {
    static let shared = NotchDanceConductor()
    private let dancers = NSHashTable<NotchDancersView>.weakObjects()
    private var beatSubscription: AnyCancellable?
    private var tempo = NotchDanceTempo()
    private var standIn: Timer?
    private(set) var beat = -1

    private init() {}

    var isRunning: Bool { beatSubscription != nil }

    func join(_ view: NotchDancersView) {
        dancers.add(view)
        guard beatSubscription == nil else { return }
        // The first to join starts the count again, so a new song's dance
        // opens on the loop's first beat, not wherever the last one stopped.
        beat = -1
        tempo.reset()
        beatSubscription = NotchMusicPulse.shared.beat.sink { [weak self] bounce in self?.hear(bounce) }
        // The first step comes as the groove settles in, beats or not.
        scheduleStandIn(after: NotchSongMotion.beatReturn)
    }

    /// The next beat is the loop's first: a new dance starts at the top.
    func restartCount() { beat = -1 }

    func leave(_ view: NotchDancersView) {
        dancers.remove(view)
        if dancers.allObjects.isEmpty { halt() }
    }

    private func halt() {
        beatSubscription = nil
        standIn?.invalidate()
        standIn = nil
    }

    private func hear(_ bounce: Double) {
        guard let energy = tempo.hear(bounce, at: CACurrentMediaTime()) else { return }
        advance(energy: energy, interval: tempo.interval)
        scheduleStandIn(after: NotchDanceTiming.fallbackDelay(afterBeatInterval: tempo.interval))
    }

    private func scheduleStandIn(after delay: Double) {
        standIn?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.advance(energy: NotchDanceTiming.fallbackEnergy, interval: NotchDanceTiming.fallbackInterval)
            if self.isRunning { self.scheduleStandIn(after: NotchDanceTiming.fallbackInterval) }
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        standIn = timer
    }

    private func advance(energy: Double, interval: Double) {
        let views = dancers.allObjects.filter(\.isDancing)
        guard !views.isEmpty else { halt(); return }
        beat &+= 1
        views.forEach { $0.dance(beat: beat, energy: energy, interval: interval) }
    }
}
