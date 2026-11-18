// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The dancers' model: the "Music side" setting, shuffle's deal, the loop
/// each dance counts, the Farewell Three's offsets and shared jump, the
/// frames one beat plays, the beat reading, and the floor every pose keeps to.
enum NotchDancerTests {
    static func run(_ suite: TestSuite) {
        settingContracts(suite)
        shuffleContracts(suite)
        loopContracts(suite)
        threeContracts(suite)
        stepContracts(suite)
        tempoContracts(suite)
        floorContracts(suite)
        rigContracts(suite)
        wingContracts(suite)
        stringContracts(suite)
    }

    private static func settingContracts(_ suite: TestSuite) {
        suite.expect(NotchMusicSide.allCases.map(\.rawValue) == ["bars", "boomboxBoss", "farewellThree", "scarn", "shuffle"],
                     "the music side's stored values are the ones `defaults write` takes")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchMusicSide] as? String == NotchMusicSide.shuffle.rawValue,
                     "this fork dances by default, a new act each song")
        suite.expect(NotchMusicSide(stored: nil) == .bars && NotchMusicSide(stored: "moonwalk") == .bars,
                     "nothing stored, or an unknown value, keeps the bars")
        let domain = "com.vorssaint.tests.notch-music-side"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(NotchMusicSide.current(in: defaults) == .bars, "a fresh install shows the bars")
        defaults.set("farewellThree", forKey: DefaultsKey.notchMusicSide)
        suite.expect(NotchMusicSide.current(in: defaults) == .farewellThree, "the chosen side is read")
        suite.expect(NotchMusicSide.allCases.filter { !$0.dances } == [.bars], "every choice but the bars dances")
        suite.expect(NotchMusicSide.boomboxBoss.routine == .boomboxBoss && NotchMusicSide.farewellThree.routine == .farewellThree
                        && NotchMusicSide.scarn.routine == .scarn && NotchMusicSide.shuffle.routine == nil
                        && NotchMusicSide.bars.routine == nil,
                     "each named side always plays its own dance; shuffle deals one per song")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchMusicSide),
                     "settings backup carries the music side")
    }

    private static func shuffleContracts(_ suite: TestSuite) {
        let wait = NotchSongSettle.interval
        var shuffle = NotchDanceShuffle()
        var dealt: [NotchDanceRoutine] = []
        var keptWhileSettling = true
        // A fixed pseudo-random sequence, so the run is repeatable.
        var seed: UInt32 = 12_345
        for song in 0..<30 {
            seed = seed &* 1_103_515_245 &+ 12_345
            let draw = Int(seed >> 16)
            let pick = { (count: Int) in draw % count }
            let start = Double(song) * 10
            // Read as it arrives, then again once its names have settled.
            let arriving = NotchMusicSide.shuffle.routine(for: "song \(song)", at: start, shuffle: &shuffle, pick: pick)
            if let last = dealt.last { keptWhileSettling = keptWhileSettling && arriving == last }
            guard let routine = NotchMusicSide.shuffle.routine(for: "song \(song)", at: start + wait,
                                                                shuffle: &shuffle, pick: pick) else {
                suite.expect(false, "shuffle deals a dance for every song")
                return
            }
            dealt.append(routine)
            suite.expect(NotchMusicSide.shuffle.routine(for: "song \(song)", at: start + 2, shuffle: &shuffle,
                                                        pick: { _ in 1 }) == routine,
                         "the same song keeps its dance, so every copy of the strip agrees")
        }
        suite.expect(keptWhileSettling, "a new song keeps the last dance until its names settle")
        suite.expect(zip(dealt, dealt.dropFirst()).allSatisfy { $0 != $1 }, "a new song never gets the dance just shown")
        suite.expect(Set(dealt) == Set(NotchDanceRoutine.allCases), "shuffle deals every dance over time")
        var untouched = NotchDanceShuffle()
        suite.expect(NotchMusicSide.scarn.routine(for: "any", at: 0, shuffle: &untouched, pick: { _ in 0 }) == .scarn
                        && untouched == NotchDanceShuffle(),
                     "a chosen dance ignores shuffle and leaves its deal alone")
        var wild = NotchDanceShuffle()
        let first = wild.routine(for: "a", at: 0, pick: { _ in 99 })
        _ = wild.routine(for: "b", at: 1, pick: { _ in -5 })
        let second = wild.routine(for: "b", at: 1 + wait, pick: { _ in -5 })
        suite.expect(first != second, "an out-of-range pick still deals a different dance")

        // A title landing before its artist, and a strip on its way out
        // still asking for the last song, change the dance once.
        var burst = NotchDanceShuffle()
        let opening = burst.routine(for: "one", at: 0, pick: { _ in 0 })
        var changes = 0
        var showing = opening
        for (key, time) in [("two", 1.0), ("two+artist", 1.05), ("one", 1.3), ("two+artist", 1.5),
                            ("one", 1.6), ("two+artist", 1.05 + wait), ("two+artist", 2.5)] {
            let routine = burst.routine(for: key, at: time, pick: { _ in 0 })
            if key != "one", routine != showing { changes += 1; showing = routine }
        }
        suite.expect(opening == NotchDanceRoutine.allCases[0] && changes == 1 && showing != opening
                        && burst.song == "two+artist" && burst.settle.due == nil,
                     "a new song's dance changes once, for the whole song, whoever else asks meanwhile")
        var nameless = NotchDanceShuffle()
        let named = nameless.routine(for: "one", at: 0, pick: { _ in 0 })
        suite.expect(nameless.routine(for: nil, at: 1, pick: { _ in 1 }) == named
                        && nameless.routine(for: nil, at: 1 + wait, pick: { _ in 1 }) == named
                        && nameless.settle.due == nil,
                     "a reading with no names tells no song from the next and keeps the dance")
        var blank = NotchDanceShuffle()
        suite.expect(blank.routine(for: nil, at: 0, pick: { _ in 2 }) == NotchDanceRoutine.allCases[2],
                     "the first song is dealt a dance at once, named or not")
        var skipped = NotchDanceShuffle()
        let kept = skipped.routine(for: "a", at: 0, pick: { _ in 0 })
        _ = skipped.routine(for: "b", at: 1, pick: { _ in 0 })
        let back = skipped.routine(for: "a", at: 1 + wait / 2, pick: { _ in 0 })
        let waiting = skipped.settle.due != nil
        let after = skipped.routine(for: "a", at: 1 + wait * 2, pick: { _ in 0 })
        suite.expect(back == kept && waiting && after == kept && skipped.settle.due == nil,
                     "a song skipped past before it settles is dropped once its time is up, so nothing asks again")
    }

    private static func loopContracts(_ suite: TestSuite) {
        for routine in NotchDanceRoutine.allCases {
            for dancer in routine.dancers.indices {
                for beat in 0..<NotchDanceRoutine.loop {
                    suite.expect(routine.move(dancer, beat: beat) == routine.move(dancer, beat: beat + NotchDanceRoutine.loop)
                                    && routine.move(dancer, beat: beat) == routine.move(dancer, beat: beat - NotchDanceRoutine.loop),
                                 "\(routine.rawValue) loops every eight beats, counted from any beat")
                    suite.expect(!routine.move(dancer, beat: beat).hits.isEmpty,
                                 "\(routine.rawValue) has a move on every beat")
                }
            }
        }
        let box = NotchDanceRoutine.boomboxBoss
        let boxPoses = (0..<8).map { box.move(0, beat: $0).hits[0].pose }
        suite.expect(Set((0..<4).map { boxPoses[$0].leftHand.dy + boxPoses[$0].hip.dx * 10 + boxPoses[$0].hip.dy * 100 }).count == 4,
                     "the boombox loop has four distinct key poses")
        suite.expect(boxPoses[4] == boxPoses[0] && boxPoses[5] == boxPoses[1] && boxPoses[6] == boxPoses[2],
                     "beats five to seven repeat the four-pose loop")
        suite.expect(boxPoses[7].oneHand == 1 && boxPoses[7].rightHand.dy > 0
                        && boxPoses.prefix(7).allSatisfy { $0.oneHand == 0 },
                     "only the eighth beat lets one hand go for a fist pump")
        suite.expect(boxPoses[1].lift > boxPoses[0].lift && boxPoses[1].hip.dy > boxPoses[0].hip.dy
                        && boxPoses[1].leftShrug > boxPoses[0].leftShrug,
                     "the second pose straightens the legs and pushes the box up")
        suite.expect(boxPoses[2].hip.dx < 0 && boxPoses[3].hip.dx > 0
                        && boxPoses[2].leftHand.dy < boxPoses[2].rightHand.dy
                        && boxPoses[3].leftHand.dy > boxPoses[3].rightHand.dy,
                     "hips go left with the box tipped left, then right with it tipped right")
        suite.expect(box.rest(0).carry == 1 && box.groove(0).carry == 0,
                     "paused, the boombox hangs by its handle; dancing, it goes overhead")

        let scarn = NotchDanceRoutine.scarn
        let moves = (0..<8).map { scarn.move(0, beat: $0) }
        suite.expect(moves[0] == moves[2] && moves[0].hits[0].pose.hip.dy < -2,
                     "the Scarn crouches on beats one and three")
        suite.expect(moves[1].hits[0].pose.shift > 0 && moves[1].hits[0].pose.rightHand.dx > 4
                        && moves[3].hits[0].pose.shift < 0 && moves[3].hits[0].pose.leftHand.dx < -4,
                     "it hops right with the right hand out, then left with the left")
        suite.expect(moves[4].hits[0].pose.leftHand.dx < -4 && moves[4].hits[0].pose.rightHand.dx > 4,
                     "beat five opens both arms wide")
        suite.expect(moves[6].hits.count == 3 && moves[7].hits.count == 2,
                     "the yarn circles in three moves and the knot pulls in two")
        let knot = moves[7].hits, shoulder = NotchDancerBody().shoulder
        suite.expect(abs((knot[0].pose.leftHand.dx - shoulder) - (knot[0].pose.rightHand.dx + shoulder)) < 1.5
                        && knot[1].pose.leftHand.dx < 0 && knot[1].pose.rightHand.dx > 0,
                     "hands meet at the chest, then pull apart")
    }

    private static func threeContracts(_ suite: TestSuite) {
        let three = NotchDanceRoutine.farewellThree
        let dancers = three.dancers
        suite.expect(dancers.count == 3 && dancers[0].position < dancers[1].position && dancers[1].position < dancers[2].position,
                     "the Farewell Three stand side by side, left to right")
        suite.expect(dancers[0].height > dancers[1].height && dancers[0].height > dancers[2].height,
                     "the left one is the tallest")
        suite.expect(dancers[1].body.shoulder > dancers[0].body.shoulder && dancers[1].body.shoulder > dancers[2].body.shoulder
                        && dancers[1].body.shoulder < dancers[0].body.shoulder * 1.2,
                     "the middle one is a little wider, and only a little")
        for beat in [7, 15, -1] {
            let jumps = dancers.indices.map { three.move($0, beat: beat) }
            suite.expect(jumps.allSatisfy { $0.hits.count == 1 && $0.hits[0].at == 0 && $0.hits[0].pose.lift > 2
                                            && $0.hits[0].pose.leftHand.dy > 4 && $0.hits[0].pose.rightHand.dy > 4 },
                         "every eighth beat all three jump together with their arms up")
        }
        for beat in 0..<7 {
            let left = three.move(0, beat: beat), middle = three.move(1, beat: beat), right = three.move(2, beat: beat)
            suite.expect(left.hits.count == 1 && left.hits[0].at == 0, "the left one moves on the beat")
            suite.expect(middle.hits.count == 1 && middle.hits[0].at == 0.5, "the middle one moves half a beat late")
            suite.expect(right.hits.count >= 2 && right.hits[0].at == 0 && right.hits.contains { $0.at == 0.5 },
                         "the right one dances double time")
            let step = three.step(1, beat: beat, energy: 1, interval: 0.5, settle: 0.5)
            suite.expect(abs(step.delay - 0.25) < 0.0001, "the middle one's move waits half of the beat's interval")
        }
        let rightHits = (0..<8).flatMap { three.move(2, beat: $0).hits.map(\.pose) }
        suite.expect(rightHits.contains { $0.facing < 0 }, "the right one spins once around its loop")
        suite.expect((0..<7).filter { beat in
            three.move(2, beat: beat).hits[0].pose.leftHand.dy > 4 && three.move(2, beat: beat).hits[0].pose.rightHand.dy > 4
        }.count == 1, "outside the jump, the right one throws its hands up once a loop, on its own count")
        suite.expect(three.move(0, beat: 0).hits[0].pose == three.move(0, beat: 1).hits[0].pose.mirrored
                        && three.move(1, beat: 0).hits[0].pose == three.move(1, beat: 1).hits[0].pose.mirrored,
                     "shoulder rolls and step-touches alternate sides")
        suite.expect(three.move(0, beat: 0).hits[0].pose.leftShrug > three.move(0, beat: 0).hits[0].pose.rightShrug,
                     "a shoulder roll raises one shoulder")
    }

    private static func stepContracts(_ suite: TestSuite) {
        suite.expectClose(Double(NotchDanceTiming.amplitude(0)), 0.62, "a soft beat still moves")
        suite.expectClose(Double(NotchDanceTiming.amplitude(1)), 1, "the strongest beat reaches the key pose")
        suite.expect(NotchDanceTiming.amplitude(.nan) == NotchDanceTiming.amplitude(0)
                        && NotchDanceTiming.amplitude(5) == NotchDanceTiming.amplitude(1),
                     "energy outside 0 to 1 is clamped")
        suite.expectClose(NotchDanceTiming.settleProgress(0), 0, "the settle starts where the move landed", tol: 0.001)
        suite.expectClose(NotchDanceTiming.settleProgress(1), 1, "the settle ends at its pose", tol: 0.001)
        let samples = stride(from: 0.0, through: 1, by: 0.05).map(NotchDanceTiming.settleProgress)
        suite.expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 } && NotchDanceTiming.settleProgress(0.2) > 0.6,
                     "the settle follows the island's curve: quick to start, gentle to land")
        suite.expect(NotchDanceTiming.settleTimes.last == 1
                        && zip(NotchDanceTiming.settleTimes, NotchDanceTiming.settleTimes.dropFirst()).allSatisfy { $0 < $1 },
                     "the settle's frames run in order to its end")
        suite.expect(NotchDanceTiming.heldStepPlays(beat: 6, generation: 3, latestBeat: 6, latestGeneration: 3),
                     "a move held back half a beat plays while its beat is still the latest")
        suite.expect(!NotchDanceTiming.heldStepPlays(beat: 6, generation: 3, latestBeat: 7, latestGeneration: 3),
                     "a held move whose next beat already came is dropped, so it never cuts short the eighth count's jump")
        suite.expect(!NotchDanceTiming.heldStepPlays(beat: 6, generation: 3, latestBeat: 6, latestGeneration: 4),
                     "a held move from a dance since stopped or changed is dropped, even on the same count")
        // The middle of the Farewell Three answers the count before the jump
        // half a beat late, and the jump on time, so a quick jump can come
        // while that move still waits.
        let jump = NotchDanceRoutine.loop - 1
        let three = NotchDanceRoutine.farewellThree
        suite.expect(three.step(1, beat: jump - 1, energy: 1, interval: 0.5, settle: 0.5).delay > 0
                        && three.step(1, beat: jump, energy: 1, interval: 0.5, settle: 0.5).delay == 0,
                     "the middle dancer's move before the jump is held back and the jump is not, so it needs the guard")

        for routine in NotchDanceRoutine.allCases {
            for dancer in routine.dancers.indices {
                for beat in 0..<NotchDanceRoutine.loop {
                    for (energy, interval) in [(1.0, 0.5), (0.2, 0.3), (0.7, 0.9), (0.5, 4.0), (0.5, Double.nan)] {
                        let move = routine.move(dancer, beat: beat)
                        let step = routine.step(dancer, beat: beat, energy: energy, interval: interval, settle: 0.5)
                        let times = step.frames.map(\.time)
                        let glides = step.frames.filter { $0.curve == .glide }.count
                        suite.expect(step.frames.filter { $0.curve == .attack }.count == move.hits.count
                                        && glides <= move.hits.count - 1
                                        && step.frames.filter { $0.curve == .settle }.count
                                            == NotchDanceTiming.settleTimes.count,
                                     "a step has a frame per move, a glide between moves with room for one, and the settle")
                        if interval == 0.5 {
                            suite.expect(glides == move.hits.count - 1, "at a usual tempo every quick move eases in")
                        }
                        suite.expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 } && (times.first ?? 0) > 0,
                                     "\(routine.rawValue) \(dancer) beat \(beat): frames run strictly forward")
                        suite.expect(abs((times.first ?? 0) - move.attack) < 0.0001 && step.frames.first?.curve == .attack,
                                     "the first key pose lands after the quick ease-out")
                        let landed = step.frames.last { $0.curve != .settle }
                        suite.expect(abs(step.duration - ((landed?.time ?? 0) + 0.5)) < 0.0001,
                                     "the settle takes the island's beat return")
                        let amplitude = NotchDanceTiming.amplitude(energy)
                        let settled = routine.groove(dancer).mixed(move.hits[move.hits.count - 1].pose, amplitude * move.residual)
                        suite.expect(step.frames.last.map { close($0.pose, settled) } == true,
                                     "it settles toward the groove, keeping part of the move")
                        suite.expect(step.delay >= 0 && step.delay <= NotchDanceTiming.intervalRange.upperBound,
                                     "a late move waits no longer than a beat")
                    }
                }
            }
        }
        let late = NotchDanceRoutine.farewellThree.step(1, beat: 0, energy: 1, interval: 4, settle: 0.5)
        suite.expectClose(late.delay, NotchDanceTiming.intervalRange.upperBound * 0.5,
                          "a gap across a quiet passage never stretches the half-beat wait")
    }

    private static func close(_ a: NotchDancerPose, _ b: NotchDancerPose) -> Bool {
        let values: [(CGFloat, CGFloat)] = [(a.shift, b.shift), (a.lift, b.lift), (a.hip.dx, b.hip.dx), (a.hip.dy, b.hip.dy),
                                            (a.lean, b.lean), (a.leftHand.dx, b.leftHand.dx), (a.leftHand.dy, b.leftHand.dy),
                                            (a.rightHand.dx, b.rightHand.dx), (a.rightHand.dy, b.rightHand.dy),
                                            (a.facing, b.facing), (a.carry, b.carry), (a.oneHand, b.oneHand)]
        return values.allSatisfy { abs($0 - $1) < 0.001 }
    }

    private static func tempoContracts(_ suite: TestSuite) {
        var tempo = NotchDanceTempo()
        suite.expect(tempo.hear(0.8, at: 10) == 0.8, "a jump in the beat is a new hit, at its strength")
        suite.expect(tempo.hear(0.58, at: 10.05) == nil && tempo.hear(0.42, at: 10.1) == nil
                        && tempo.hear(0.48, at: 10.15) == nil,
                     "the push falling away, or wavering, is no new hit")
        suite.expect(tempo.hear(0.9, at: 10.5) != nil, "the next hit is heard")
        suite.expectClose(tempo.interval, 0.5, "two hits half a second apart keep a half-second beat")
        _ = tempo.hear(0, at: 10.6)
        _ = tempo.hear(0.9, at: 11.3)
        suite.expect(tempo.interval > 0.5 && tempo.interval <= NotchDanceTiming.intervalRange.upperBound,
                     "a slower beat lengthens the half-beat moves")
        _ = tempo.hear(0, at: 11.4)
        let before = tempo.interval
        _ = tempo.hear(0.9, at: 20)
        suite.expectClose(tempo.interval, before, "a gap across a quiet passage leaves the tempo alone")
        suite.expect(tempo.hear(.nan, at: 21) == nil, "an unreadable push is silence")
        tempo.reset()
        suite.expect(tempo == NotchDanceTempo(), "a fresh start forgets the last song's tempo")
        suite.expectClose(NotchDanceTiming.fallbackDelay(afterBeatInterval: 0.5), 0.9,
                          "after a beat, steps stand in only once a beat is clearly missing")
        suite.expectClose(NotchDanceTiming.fallbackDelay(afterBeatInterval: 0.8), 1.28, "a slow song waits longer")
        suite.expectClose(NotchDanceTiming.fallbackInterval, 0.5, "without beats, a pose every half second")
    }

    /// Every pose a dance can reach, its settles included, stays on its floor
    /// on short, usual and tall strips, so nothing is clipped at the strip's
    /// top, its ends or the camera's edge.
    private static func floorContracts(_ suite: TestSuite) {
        for height: CGFloat in [24, 32, 37] {
            for routine in NotchDanceRoutine.allCases {
                for (index, dancer) in routine.dancers.enumerated() {
                    var poses = [routine.rest(index), routine.groove(index), routine.still(index)]
                    for beat in 0..<NotchDanceRoutine.loop {
                        poses += routine.move(index, beat: beat).hits.map { routine.groove(index).mixed($0.pose, 1) }
                        poses += routine.step(index, beat: beat, energy: 1, interval: 0.5, settle: 0.5).frames.map(\.pose)
                    }
                    var reach = CGRect.null
                    var shapes: [Int]?
                    var consistent = true
                    for pose in poses {
                        let paths = dancer.paths(pose, floorHeight: height)
                        for (layer, path) in zip(dancer.layers, paths) {
                            let half = (dancer.lineWidth(layer, floorHeight: height) ?? 0) / 2
                            reach = reach.union(path.boundingBoxOfPath.insetBy(dx: -half, dy: -half))
                        }
                        let elements = paths.map(elementCount)
                        if let shapes, shapes != elements { consistent = false }
                        shapes = elements
                    }
                    suite.expect(reach.minX >= 0 && reach.maxX <= NotchDanceFloor.width
                                    && reach.minY >= 0 && reach.maxY <= height - 0.25,
                                 "\(routine.rawValue) \(index) stays on a \(height)-point floor: \(reach)")
                    suite.expect(consistent, "\(routine.rawValue) \(index) draws every pose from the same outline, so it animates")
                }
            }
        }
        suite.expect(NotchDanceFloor.scale(height: 32) == 1 && NotchDanceFloor.scale(height: 24) < 1
                        && NotchDanceFloor.scale(height: .nan) == 1,
                     "figures are full size in a usual strip and shrink only in a short one")
        let standing = NotchDanceRoutine.boomboxBoss.dancers[0]
        let full = standing.scale(floorHeight: 32) * standing.body.standingHeight
        suite.expect(full >= 17.5 && full <= 20.5, "a dancer stands about 18 to 20 points tall in a 32-point strip")
        for routine in NotchDanceRoutine.allCases {
            suite.expect(routine.dancers.allSatisfy { $0.layers.contains { $0.shape == .head && $0.paint == .head } }
                            && routine.dancers.allSatisfy { !$0.layers.contains { $0.paint == .head && $0.shape != .head
                                                                                   && $0.shape != .hands } },
                         "\(routine.rawValue): heads and hands share one fill, and nothing else wears it")
        }
    }

    private static func elementCount(_ path: CGPath) -> Int {
        var count = 0
        path.applyWithBlock { _ in count += 1 }
        return count
    }

    private static func rigContracts(_ suite: TestSuite) {
        let body = NotchDancerBody()
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() }
        let crouch = NotchDancerRig(body: body, pose: NotchDancerPose.with { $0.hip.dy = -2 })
        for index in 0..<2 {
            suite.expect(abs(distance(crouch.hips[index], crouch.knees[index]) - body.thigh) < 0.001
                            && abs(distance(crouch.knees[index], crouch.feet[index]) - body.shin) < 0.001,
                         "a bent leg keeps its length")
            suite.expect(abs(crouch.feet[index].y - body.footLift) < 0.001, "a crouch keeps the feet on the floor")
        }
        suite.expect(crouch.knees[0].x < crouch.hips[0].x && crouch.knees[1].x > crouch.hips[1].x,
                     "knees bend outward, open to the viewer")
        let reach = NotchDancerRig(body: body, pose: NotchDancerPose.with { $0.rightHand = CGVector(dx: 20, dy: 0) })
        suite.expect(abs(distance(reach.shoulders[1], reach.hands[1]) - (body.upperArm + body.foreArm)) < 0.01
                        && abs(reach.hands[1].y - reach.shoulders[1].y) < 0.01,
                     "an arm out of reach stretches straight toward its target")
        let close = NotchDancerRig(body: body, pose: NotchDancerPose.with { $0.leftHand = CGVector(dx: 0.5, dy: -3) })
        suite.expect(abs(close.hands[0].x - (close.shoulders[0].x + 0.5)) < 0.01 && close.elbows[0].x < close.shoulders[0].x,
                     "a hand near its shoulder is reached, the elbow out to the side")
        let spun = NotchDanceRoutine.scarn.dancers[0]
        let front = spun.paths(NotchDancerPose(), floorHeight: 32)
        let back = spun.paths(NotchDancerPose.with { $0.facing = -1 }, floorHeight: 32)
        suite.expect(zip(front, back).allSatisfy { abs($0.boundingBoxOfPath.midX - $1.boundingBoxOfPath.midX) < 0.01 },
                     "a symmetric pose turned around stands in the same place")
        let edgeOn = spun.paths(NotchDancerPose.with { $0.facing = 0.1 }, floorHeight: 32)
        suite.expect(edgeOn[edgeOn.count - 1].boundingBoxOfPath.width < front[front.count - 1].boundingBoxOfPath.width * 0.2,
                     "midway through a spin the figure is seen edge on")
        let mirrored = NotchDanceRoutine.scarn.move(0, beat: 1).hits[0].pose.mirrored.mirrored
        suite.expect(mirrored == NotchDanceRoutine.scarn.move(0, beat: 1).hits[0].pose, "mirroring twice is the same move")
        let box = NotchDancerRig(body: body, pose: NotchDanceRoutine.boomboxBoss.groove(0))
        suite.expect(box.boxCenter.y - NotchBoombox.height / 2 > box.head.y + body.headRadius + 0.5,
                     "the boombox is held clear of the head")
    }

    private static func wingContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        for safeArea: CGFloat in [32, 33, 37.5, 38] {
            let display = NotchGeometry(screen: screen, safeAreaTop: safeArea, cameraWidth: 185,
                                        menuBarHeight: 24, compactSideRoom: 100)
            let bars = display.compactMusicGeometry
            let dancing = display.compactMusicGeometry(dancing: true)
            suite.expect(display.compactMusicGeometry(dancing: false) == bars, "the bars keep upstream's strip")
            suite.expect(dancing.compactActivityWingWidth > bars.compactActivityWingWidth
                            && dancing.compactActivityWingWidth <= 48
                            && NotchMusicStripLayout.fitsDancers(dancing) && !NotchMusicStripLayout.fitsDancers(bars),
                         "dancers widen both wings just enough for their floor: \(dancing.compactActivityWingWidth)")
            suite.expect(abs(NotchMusicStripLayout.dancersInset(dancing) + NotchDanceFloor.width
                             - dancing.compactActivityWingWidth) <= 1,
                         "the floor reaches from the camera to the strip's even end gap")
            suite.expect(dancing.compactActivitySize.height == bars.compactActivitySize.height
                            && dancing.compactActivityCameraGap == bars.compactActivityCameraGap
                            && dancing.compactMusicArtworkSide == bars.compactMusicArtworkSide
                            && dancing.compactMusicArtworkInset == bars.compactMusicArtworkInset,
                         "the strip keeps its height and the cover its size and place at the left end")
            suite.expect(display.lockScreenMusicGeometry.compactActivityWingWidth == bars.compactActivityWingWidth,
                         "the Lock Screen keeps the bars' strip")
            let roomForBars = bars.compactActivityWingWidth + 1
            var crowded = display
            crowded.compactSideRoom = roomForBars
            suite.expect(crowded.compactMusicGeometry(dancing: true) == crowded.compactMusicGeometry
                            && !NotchMusicStripLayout.fitsDancers(crowded.compactMusicGeometry(dancing: true)),
                         "menus leaving room only for the bars keep the bars' wings and the bars")
        }
        let simulated = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 180, menuBarHeight: 24,
                                      compactSideRoom: 100)
        suite.expect(simulated.compactMusicGeometry(dancing: true) == simulated.compactMusicGeometry
                        && NotchMusicStripLayout.fitsDancers(simulated.compactMusicGeometry),
                     "a simulated camera's roomy wings already hold the dancers")
    }

    private static func stringContracts(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.notchDancers(language)
            let names = NotchMusicSide.allCases.map(strings.name)
            suite.expect(!strings.musicSide.isEmpty && names.allSatisfy { !$0.isEmpty } && Set(names).count == names.count,
                         "every music side has its own name in \(language.rawValue)")
        }
        let english = FeatureStrings.notchDancers(.enUS)
        suite.expect(NotchMusicSide.allCases.map(english.name)
                        == ["Bars", "Boombox Boss", "The Farewell Three", "The Scarn", "Shuffle"],
                     "the dances keep their generic names")
    }
}
