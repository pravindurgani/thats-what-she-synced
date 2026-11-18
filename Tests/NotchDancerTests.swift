// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The dancers' model: the "Music side" setting, shuffle's deal, the loop
/// each dance counts, the Farewell Three's offsets and shared jump, the
/// frames one beat plays, the beat reading, the floor every pose keeps to,
/// the bold figures' sizes and tones, the wings and their step down, and the
/// colours a black-and-white cover borrows.
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
        toneContracts(suite)
        colourlessContracts(suite)
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
        let boss = box.dancers[0].body
        suite.expect(boxPoses[1].hip.dy > boxPoses[0].hip.dy + 1.5 && boxPoses[1].leftShrug > boxPoses[0].leftShrug
                        && NotchDancerRig(body: boss, pose: boxPoses[1]).boxCenter.y
                            > NotchDancerRig(body: boss, pose: boxPoses[0]).boxCenter.y + 1.5,
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
        suite.expect(abs(dancers[0].height - 26) <= 0.6 && abs(dancers[1].height - 24) <= 0.6
                        && abs(dancers[2].height - 25) <= 0.6,
                     "the three stand about 26, 24 and 25 points tall: \(dancers.map(\.height))")
        suite.expect(Set(dancers.map { [$0.body.headRadius, $0.body.torsoWidth, $0.body.shoulder, $0.body.hip,
                                        $0.body.legWidth, $0.body.armWidth, $0.body.handRadius] }).count == 1,
                     "the three share one build, told apart by height and outfit, never by body size")
        suite.expect(Set(dancers.map { String(describing: $0.layers.first { $0.shape == .torso }?.paint) }).count == 3,
                     "each of the three wears its own top")
        suite.expect(abs((dancers[1].position - dancers[0].position) - 16) < 0.01
                        && abs((dancers[2].position - dancers[1].position) - 16) < 0.01,
                     "the three stand 16 points apart at full size")
        // Arms never cross a neighbour's centre line, in any pose a step reaches.
        let floor = NotchDanceLayout(routine: three, height: 32)
        let centres = dancers.map { floor.width / 2 + $0.position * floor.scale }
        var crossing: [String] = []
        for (index, dancer) in dancers.enumerated() {
            var poses = [three.rest(index), three.groove(index), three.still(index)]
            for beat in 0..<NotchDanceRoutine.loop {
                poses += three.step(index, beat: beat, energy: 1, interval: 0.5, settle: 0.5).frames.map(\.pose)
            }
            for pose in poses {
                let paths = dancer.paths(pose, floor: floor)
                for (layer, path) in zip(dancer.layers, paths) where layer.shape == .arms || layer.shape == .hands {
                    let half = (dancer.lineWidth(layer, floor: floor) ?? 0) / 2
                    let reach = path.boundingBoxOfPath.insetBy(dx: -half, dy: -half)
                    if index > 0, reach.minX < centres[index - 1] { crossing.append("\(index) left") }
                    if index < dancers.count - 1, reach.maxX > centres[index + 1] { crossing.append("\(index) right") }
                }
            }
        }
        suite.expect(crossing.isEmpty, "no arm crosses a neighbour's centre line: \(Set(crossing))")
        for beat in [7, 15, -1] {
            let jumps = dancers.indices.map { three.move($0, beat: beat) }
            suite.expect(jumps.allSatisfy { $0.hits.count == 1 && $0.hits[0].at == 0
                                            && $0.hits[0].pose.lift + $0.hits[0].pose.leftFoot.dy > 2.5
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

    /// Every pose a dance can reach, its settles included: the trio's
    /// jump, hands up, the box pushed overhead, the hops.
    private static func reachablePoses(_ routine: NotchDanceRoutine, _ index: Int) -> [NotchDancerPose] {
        var poses = [routine.rest(index), routine.groove(index), routine.still(index)]
        for beat in 0..<NotchDanceRoutine.loop {
            poses += routine.move(index, beat: beat).hits.map { routine.groove(index).mixed($0.pose, 1) }
            poses += routine.step(index, beat: beat, energy: 1, interval: 0.5, settle: 0.5).frames.map(\.pose)
        }
        return poses
    }

    /// Every pose stays on its floor in every strip the dancers dance in,
    /// at full size and stepped down: within the floor's ends, so nothing
    /// is clipped at the strip's end or the camera's edge, and with its
    /// keyline at least NotchDanceFloor.clearance inside the strip's top and
    /// bottom. The figures are largest, and have the least room, in a strip
    /// about 36 points tall.
    private static func floorContracts(_ suite: TestSuite) {
        let clearance = NotchDanceFloor.clearance
        for height: CGFloat in [24, 26, 28, 30, 32, 33, 34, 35, 35.5, 36, 36.25, 36.5, 37, 38, 40, 48, 64] {
            for routine in NotchDanceRoutine.allCases {
                let stepped = NotchDanceLayout(routine: routine, height: height,
                                               scale: min(NotchDanceFloor.scale(height: height), NotchDanceFloor.steppedScale))
                for floor in [NotchDanceLayout(routine: routine, height: height), stepped] {
                    for (index, dancer) in routine.dancers.enumerated() {
                        var reach = CGRect.null
                        var drawn = CGRect.null
                        var shapes: [Int]?
                        var consistent = true
                        for pose in reachablePoses(routine, index) {
                            let paths = dancer.paths(pose, floor: floor)
                            for (layer, path) in zip(dancer.layers, paths) {
                                let half = (dancer.lineWidth(layer, floor: floor) ?? 0) / 2
                                reach = reach.union(path.boundingBoxOfPath.insetBy(dx: -half, dy: -half))
                            }
                            drawn = drawn.union(dancer.extent(pose, floor: floor))
                            guard height == 32 else { continue }
                            let drawing = dancer.drawing(pose, floor: floor)
                            let elements = (paths + [drawing.keyline, drawing.ring] + drawing.parts).map(elementCount)
                            if let shapes, shapes != elements { consistent = false }
                            shapes = elements
                        }
                        suite.expect(reach.minX >= 0 && reach.maxX <= floor.width,
                                     "\(routine.rawValue) \(index) stays within a \(height)-point floor's ends at \(floor.scale): \(reach)")
                        suite.expect(drawn.maxY <= height - clearance + 0.001 && drawn.minY >= clearance - 0.001,
                                     "\(routine.rawValue) \(index) keeps its keyline \(clearance) points inside a "
                                        + "\(height)-point strip's top and bottom at \(floor.scale): \(drawn)")
                        suite.expect(consistent, "\(routine.rawValue) \(index) draws every pose from the same outline, so it animates")
                    }
                }
            }
        }
        // The moves still read: the three leave the floor on the jump, and
        // a hop leaves it too.
        let trio = NotchDanceLayout(routine: .farewellThree, height: 32)
        for (index, dancer) in NotchDanceRoutine.farewellThree.dancers.enumerated() {
            let jump = NotchDanceRoutine.farewellThree.move(index, beat: NotchDanceRoutine.loop - 1).hits[0].pose
            let shoes = dancer.layers.firstIndex { $0.shape == .shoes } ?? 0
            let feet = dancer.paths(jump, floor: trio)[shoes].boundingBoxOfPath.minY
            suite.expect(feet >= trio.ground + 3, "the jump takes \(index)'s feet well off the floor: \(feet - trio.ground)")
        }
        let hop = NotchDanceRoutine.scarn.dancers[0].paths(NotchDanceRoutine.scarn.move(0, beat: 1).hits[0].pose,
                                                         floor: NotchDanceLayout(routine: .scarn, height: 32))
        let scarnShoes = NotchDanceRoutine.scarn.dancers[0].layers.firstIndex { $0.shape == .shoes } ?? 0
        suite.expect(hop[scarnShoes].boundingBoxOfPath.minY >= NotchDanceLayout(routine: .scarn, height: 32).ground + 2,
                     "the Scarn's hop leaves the floor")
        // A floating capsule's 20-point body, and a strip shorter than the
        // smallest figures need, keep the bars.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let capsule = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 24, compactSideRoom: 300,
                                    silhouette: .capsule)
        suite.expect(capsule.floats && NotchDanceRoutine.allCases.allSatisfy { NotchMusicStripLayout.danceFloor(capsule, routine: $0) == nil }
                        && !NotchMusicStripLayout.fitsDancers(capsule),
                     "a floating capsule keeps its bars: its 20-point body has no room for figures clear of its edges")
        let short = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 22, compactSideRoom: 300)
        suite.expect(short.compactActivityContentHeight < NotchDanceFloor.shortestStrip
                        && NotchDanceRoutine.allCases.allSatisfy { NotchMusicStripLayout.danceFloor(short, routine: $0) == nil },
                     "a strip shorter than \(NotchDanceFloor.shortestStrip) points keeps the bars")
        suite.expect(NotchDanceFloor.shortestStrip == 24 && NotchDanceFloor.clearance == 1.5,
                     "the figures dance in strips 24 points tall or more, 1.5 points clear of their edges")
        suite.expect(NotchDanceFloor.figureHeight(strip: 32) == 26 && NotchDanceFloor.figureHeight(strip: 20) == 18
                        && NotchDanceFloor.figureHeight(strip: 40) == 30 && NotchDanceFloor.figureHeight(strip: .nan) == 26,
                     "figures stand as tall as the strip less 6 points, 18 to 30")
        suite.expect(NotchDanceFloor.scale(height: 32) == 1 && NotchDanceFloor.scale(height: 24) < 1
                        && NotchDanceFloor.scale(height: 37) > 1 && NotchDanceFloor.scale(height: .nan) == 1,
                     "figures are full size in a usual strip, smaller in a short one and larger in a tall one")
        suite.expect(abs(NotchDanceFloor.steppedScale * NotchDanceFloor.fullFigure - 22) < 0.001
                        && NotchDanceFloor.steppedWing == 44,
                     "the step down is a 44-point wing with 22-point figures")
        let scarn = NotchDanceRoutine.scarn.dancers[0]
        suite.expect(abs(scarn.height * NotchDanceFloor.scale(height: 32) - 26) <= 0.5,
                     "a dancer stands about 26 points tall in a 32-point strip, not 19 or 20")
        suite.expect(NotchDanceRoutine.farewellThree.floorWidth == 48 && NotchDanceRoutine.farewellThree.wing == 60
                        && NotchDanceRoutine.scarn.floorWidth == 34 && NotchDanceRoutine.boomboxBoss.wing == 48,
                     "the three take a 60-point wing and a solo a 48-point one")
        // Bold, not hairline: limbs and torso at the designed widths, in points at full size.
        let full = NotchDanceLayout(routine: .scarn, height: 32)
        func points(_ shape: NotchDancerLayer.Shape) -> CGFloat {
            scarn.layers.first { $0.shape == shape }.flatMap { scarn.lineWidth($0, floor: full) } ?? 0
        }
        suite.expect(abs(points(.legs) - 2.8) < 0.05 && abs(points(.arms) - 2.4) < 0.05 && abs(points(.torso) - 7) < 0.05,
                     "legs 2.8 points, arms 2.4 and the torso a 7-point filled capsule")
        suite.expect(abs(scarn.body.handRadius * NotchDanceFloor.unit - 1.5) < 0.05
                        && abs(scarn.body.headRadius * 2 * NotchDanceFloor.unit - 7.1) < 0.6,
                     "hands 1.5 points in radius, heads about 7 to 8 across")
        let parts: [NotchDancerLayer.Shape] = [.legs, .shoes, .soles, .torso, .arms, .hands, .head]
        let silhouette: [NotchDancerLayer.Shape] = [.legs, .torso, .arms, .head, .hands, .shoes]
        for routine in NotchDanceRoutine.allCases {
            suite.expect(routine.dancers.allSatisfy { $0.layers.contains { $0.shape == .head && $0.paint == .head } }
                            && routine.dancers.allSatisfy { !$0.layers.contains { $0.paint == .head && $0.shape != .head
                                                                                   && $0.shape != .hands } },
                         "\(routine.rawValue): heads and hands share one fill, and nothing else wears it")
            suite.expect(routine.dancers.allSatisfy { dancer in
                             parts.allSatisfy { shape in dancer.layers.contains { $0.shape == shape } }
                         },
                         "\(routine.rawValue): every figure has legs, shoes with soles, a torso, arms, hands and a head")
            suite.expect(routine.dancers.allSatisfy { dancer in
                             dancer.layers.filter { silhouette.contains($0.shape) }.allSatisfy(\.keyline)
                         },
                         "\(routine.rawValue): the black keyline runs around every part of the silhouette")
            suite.expect(routine.dancers.allSatisfy { dancer in
                             dancer.layers.filter { $0.shape == .torso || $0.shape == .legs || $0.shape == .arms }
                                 .allSatisfy { $0.stroke == .limb && $0.paint != .head }
                         },
                         "\(routine.rawValue): bodies are filled, round-capped shapes, not outlines")
        }
        suite.expect(NotchDanceRoutine.scarn.dancers[0].layers.contains { $0.shape == .shirt }
                        && NotchDanceRoutine.scarn.dancers[0].layers.contains { $0.shape == .tie && $0.paint == .tie }
                        && NotchDanceRoutine.scarn.dancers[0].layers.first { $0.shape == .torso }?.paint == .tone(.suit),
                     "the Scarn wears a suit, a white shirt's V and a thin tie in the song's second colour")
        let boss = NotchDanceRoutine.boomboxBoss.dancers[0]
        suite.expect(!boss.layers.contains { $0.shape == .shirt } && boss.layers.contains { $0.shape == .tie }
                        && boss.layers.first { $0.shape == .torso }?.paint == .tone(.light)
                        && boss.layers.first { $0.shape == .legs }?.paint == .tone(.trousers) && boss.carriesBox,
                     "the Boombox Boss: a light shirt and no jacket, a skinny tie, slate trousers and the box")
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
        let floor = NotchDanceLayout(routine: .scarn, height: 32)
        let front = spun.paths(NotchDancerPose(), floor: floor)
        let back = spun.paths(NotchDancerPose.with { $0.facing = -1 }, floor: floor)
        suite.expect(zip(front, back).allSatisfy { abs($0.boundingBoxOfPath.midX - $1.boundingBoxOfPath.midX) < 0.01 },
                     "a symmetric pose turned around stands in the same place")
        let edgeOn = spun.paths(NotchDancerPose.with { $0.facing = 0.1 }, floor: floor)
        let legs = spun.layers.firstIndex { $0.shape == .legs } ?? 0
        let head = spun.layers.firstIndex { $0.shape == .head } ?? 0
        suite.expect(edgeOn[legs].boundingBoxOfPath.width < front[legs].boundingBoxOfPath.width * 0.2,
                     "midway through a spin the figure is seen edge on")
        suite.expect(abs(edgeOn[head].boundingBoxOfPath.width - front[head].boundingBoxOfPath.width) < 0.01,
                     "a head stays round through a spin")
        let mirrored = NotchDanceRoutine.scarn.move(0, beat: 1).hits[0].pose.mirrored.mirrored
        suite.expect(mirrored == NotchDanceRoutine.scarn.move(0, beat: 1).hits[0].pose, "mirroring twice is the same move")
        let bossBody = NotchDanceRoutine.boomboxBoss.dancers[0].body
        for pose in [NotchDanceRoutine.boomboxBoss.groove(0), NotchDanceRoutine.boomboxBoss.move(0, beat: 1).hits[0].pose] {
            let box = NotchDancerRig(body: bossBody, pose: pose)
            suite.expect(box.boxCenter.y - NotchBoombox.height / 2 > box.head.y + bossBody.headRadius + 0.5,
                         "the boombox is held clear of the head")
        }
        // On the accent the arms push the box up toward the strip's top
        // edge, its keyline stopping at the clearance.
        let top = NotchDanceRoutine.boomboxBoss.dancers[0]
            .extent(NotchDanceRoutine.boomboxBoss.move(0, beat: 1).hits[0].pose,
                    floor: NotchDanceLayout(routine: .boomboxBoss, height: 32)).maxY
        let ceiling = 32 - NotchDanceFloor.clearance
        suite.expect(top > ceiling - 1 && top <= ceiling, "the push takes the box up toward the strip's top edge: \(top)")
        drawingContracts(suite)
    }

    /// The stage draws each figure with few layers: one keyline path behind
    /// the whole figure, one ring over heads and hands, and a layer per
    /// part, the hands and head sharing one. Its keyline follows every part
    /// it outlines, a point outside its edge at full size.
    private static func drawingContracts(_ suite: TestSuite) {
        for routine in NotchDanceRoutine.allCases {
            for dancer in routine.dancers {
                let groups = dancer.drawnParts
                suite.expect(groups.flatMap { $0 } == Array(dancer.layers.indices)
                                && groups.contains { group in group.map { dancer.layers[$0].shape } == [.hands, .head] },
                             "\(routine.rawValue): every part is drawn once, in order, and the hands share the head's layer")
                suite.expect(groups.allSatisfy { group in
                                 group.allSatisfy { dancer.layers[$0].paint == dancer.layers[group[0]].paint
                                     && dancer.layers[$0].stroke == dancer.layers[group[0]].stroke }
                             },
                             "\(routine.rawValue): a shared layer holds parts of one paint and one stroke")
                let ring = dancer.ringPlace.map { groups[$0].contains { dancer.layers[$0].keylineInFront } } ?? false
                suite.expect(ring, "\(routine.rawValue): the ring goes in just before the head and hands")
                // One keyline, one ring and the parts: well under the layer
                // per part, its keyline and its ring the figures once took.
                let before = dancer.layers.count + dancer.layers.filter(\.keyline).count
                    + dancer.layers.filter(\.keylineInFront).count
                suite.expect(groups.count + 2 <= before * 2 / 3,
                             "\(routine.rawValue): \(groups.count + 2) shape layers a figure, down from \(before)")
            }
        }
        // The keyline runs a point outside every limb and the torso, as the
        // render server draws it between two poses too: an arm swinging
        // from down to up over one beat keeps its keyline all the way.
        let floor = NotchDanceLayout(routine: .farewellThree, height: 32)
        let dancer = NotchDanceRoutine.farewellThree.dancers[2]
        let line = NotchDancer.keyline(floor)
        let down = NotchDanceRoutine.farewellThree.groove(2)
        let up = NotchDanceRoutine.farewellThree.still(2)
        for share: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
            let keyline = blend(dancer.drawing(down, floor: floor).keyline, dancer.drawing(up, floor: floor).keyline, share)
            let parts = zip(dancer.paths(down, floor: floor), dancer.paths(up, floor: floor)).map { blend($0, $1, share) }
            let outlined: [NotchDancerLayer.Shape] = [.arms, .legs, .torso]
            for (layer, path) in zip(dancer.layers, parts) where layer.keyline && outlined.contains(layer.shape) {
                let half = (dancer.lineWidth(layer, floor: floor) ?? 0) / 2
                suite.expect(covers(keyline, around: path, halfWidth: half, keyline: line),
                             "the keyline runs a point outside the \(layer.shape) \(Int(share * 100))% of the way up")
            }
        }
        suite.expect(NotchDancer.beads(along: 3.1, radius: 0.96) >= 3 && NotchDancer.beads(along: 0, radius: 1) == 1
                        && NotchDancer.beads(along: .nan, radius: 1) == 1,
                     "a limb's keyline takes enough beads that its edge dips by a hair at most")
    }

    /// `a` moved `share` of the way to `b`, point by point, as Core
    /// Animation moves a path between two of the same shape.
    private static func blend(_ a: CGPath, _ b: CGPath, _ share: CGFloat) -> CGPath {
        func elements(_ path: CGPath) -> [(CGPathElementType, [CGPoint])] {
            var list: [(CGPathElementType, [CGPoint])] = []
            path.applyWithBlock { element in
                let count: Int
                switch element.pointee.type {
                case .moveToPoint, .addLineToPoint: count = 1
                case .addQuadCurveToPoint: count = 2
                case .addCurveToPoint: count = 3
                default: count = 0
                }
                list.append((element.pointee.type, (0..<count).map { element.pointee.points[$0] }))
            }
            return list
        }
        let path = CGMutablePath()
        for (from, to) in zip(elements(a), elements(b)) {
            let points = zip(from.1, to.1).map { CGPoint(x: $0.x + ($1.x - $0.x) * share, y: $0.y + ($1.y - $0.y) * share) }
            switch from.0 {
            case .moveToPoint: path.move(to: points[0])
            case .addLineToPoint: path.addLine(to: points[0])
            case .addQuadCurveToPoint: path.addQuadCurve(to: points[1], control: points[0])
            case .addCurveToPoint: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            default: path.closeSubpath()
            }
        }
        return path
    }

    /// Whether `keyline`, stroked as the stage strokes it, covers the band
    /// half a keyline wide just outside each segment of the stroked part
    /// `path`, `halfWidth` either side of its centre line.
    private static func covers(_ keyline: CGPath, around path: CGPath, halfWidth: CGFloat, keyline line: CGFloat) -> Bool {
        let band = keyline.copy(strokingWithWidth: line * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
        var lines: [[CGPoint]] = []
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint: lines.append([element.pointee.points[0]])
            case .addLineToPoint: lines[lines.count - 1].append(element.pointee.points[0])
            default: break
            }
        }
        for points in lines {
            for (start, end) in zip(points, points.dropFirst()) {
                let dx = end.x - start.x, dy = end.y - start.y
                let length = (dx * dx + dy * dy).squareRoot()
                guard length > 0.01 else { continue }
                let normal = CGVector(dx: -dy / length, dy: dx / length)
                for share: CGFloat in [0.2, 0.5, 0.8] {
                    let middle = CGPoint(x: start.x + dx * share, y: start.y + dy * share)
                    for side: CGFloat in [-1, 1] {
                        let reach = (halfWidth + line * 0.5) * side
                        guard band.contains(CGPoint(x: middle.x + normal.dx * reach, y: middle.y + normal.dy * reach)) else {
                            return false
                        }
                    }
                }
            }
        }
        return true
    }

    private static func wingContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        for safeArea: CGFloat in [32, 33, 37.5, 38] {
            let display = NotchGeometry(screen: screen, safeAreaTop: safeArea, cameraWidth: 185,
                                        menuBarHeight: 24, compactSideRoom: 120)
            let bars = display.compactMusicGeometry
            let shuffle = display.compactMusicGeometry(dancing: .shuffle)
            let solo = display.compactMusicGeometry(dancing: .scarn)
            let scale = NotchDanceFloor.scale(height: shuffle.compactActivityContentHeight)
            suite.expect(display.compactMusicGeometry(dancing: .bars) == bars, "the bars keep upstream's strip")
            suite.expect(shuffle.compactActivityWingWidth >= (60 * scale).rounded(.down)
                            && shuffle.compactActivityWingWidth <= (60 * scale).rounded(.up) + 2
                            && solo.compactActivityWingWidth >= (48 * scale).rounded(.down)
                            && solo.compactActivityWingWidth < shuffle.compactActivityWingWidth
                            && shuffle == display.compactMusicGeometry(dancing: .farewellThree),
                         "the three take about 60-point wings and a solo about 48, grown with the strip: "
                            + "\(shuffle.compactActivityWingWidth), \(solo.compactActivityWingWidth)")
            suite.expect(abs(shuffle.compactActivitySize.width - shuffle.compactActivityCameraGap
                             - shuffle.compactActivityWingWidth * 2) < 0.5,
                         "both wings grow alike, so the island stays balanced")
            for routine in NotchDanceRoutine.allCases {
                let geometry = display.compactMusicGeometry(dancing: .shuffle)
                guard let floor = NotchMusicStripLayout.danceFloor(geometry, routine: routine) else {
                    suite.expect(false, "\(routine.rawValue) fits a shuffle's wings")
                    continue
                }
                let inset = NotchMusicStripLayout.dancersInset(geometry, floor: floor)
                suite.expect(abs(floor.scale - scale) < 0.001,
                             "\(routine.rawValue) dances at full size in a shuffle's wings")
                suite.expect(inset >= geometry.compactMusicDancersInset(scale: floor.scale) - 0.01
                                && inset + floor.width <= geometry.compactActivityWingWidth + 0.01,
                             "\(routine.rawValue)'s floor reaches no closer to the end than its gap, nor past the camera")
            }
            suite.expect(shuffle.compactActivitySize.height == bars.compactActivitySize.height
                            && shuffle.compactActivityCameraGap == bars.compactActivityCameraGap
                            && shuffle.compactMusicArtworkSide == bars.compactMusicArtworkSide
                            && shuffle.compactMusicArtworkInset == bars.compactMusicArtworkInset,
                         "the strip keeps its height and the cover its size and place at the left end")
            suite.expect(display.lockScreenMusicGeometry.compactActivityWingWidth == bars.compactActivityWingWidth,
                         "the Lock Screen keeps the bars' strip")

            // Less room: the wings step down to 44 points and smaller figures.
            var tight = display
            tight.compactSideRoom = 50
            let stepped = tight.compactMusicGeometry(dancing: .shuffle)
            suite.expect(stepped.compactActivityWingWidth >= NotchDanceFloor.steppedWing
                            && stepped.compactActivityWingWidth <= NotchDanceFloor.steppedWing + 2
                            && (safeArea > 33 || stepped.compactActivityWingWidth == NotchDanceFloor.steppedWing),
                         "menus short of the full wings step them down to 44 points, a hair more in a tall strip: "
                            + "\(stepped.compactActivityWingWidth)")
            let trio = NotchMusicStripLayout.danceFloor(stepped, routine: .farewellThree)
            let single = NotchMusicStripLayout.danceFloor(stepped, routine: .boomboxBoss)
            suite.expect(single.map { abs($0.scale - min(scale, NotchDanceFloor.steppedScale)) < 0.001 } == true
                            && trio.map { $0.scale >= NotchDanceFloor.smallestScale && $0.scale < scale } == true,
                         "stepped down, a solo dances at 22 points and the three as large as the wing holds")
            suite.expect(NotchMusicStripLayout.fitsDancers(stepped), "the stepped-down wing still dances")

            // Less room still: the bars' wings and the bars.
            var crowded = display
            crowded.compactSideRoom = NotchDanceFloor.steppedWing - 1
            suite.expect(crowded.compactMusicGeometry(dancing: .shuffle) == crowded.compactMusicGeometry
                            && !NotchMusicStripLayout.fitsDancers(crowded.compactMusicGeometry(dancing: .shuffle))
                            && !NotchMusicStripLayout.fitsDancers(bars),
                         "menus leaving room only for the bars keep the bars' wings and the bars")
        }
        let simulated = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 180, menuBarHeight: 24,
                                      compactSideRoom: 100)
        suite.expect(simulated.compactMusicGeometry(dancing: .shuffle) == simulated.compactMusicGeometry
                        && NotchMusicStripLayout.fitsDancers(simulated.compactMusicGeometry)
                        && NotchDanceRoutine.allCases.allSatisfy {
                            NotchMusicStripLayout.danceFloor(simulated.compactMusicGeometry, routine: $0) != nil },
                     "a simulated camera's roomy wings already hold the dancers")
    }

    /// Outfits are tones of the song's lead colour, every one clear on the
    /// black island; ties take its second colour, deep enough for a white shirt.
    private static func toneContracts(_ suite: TestSuite) {
        let black = NotchRGB(red: 0, green: 0, blue: 0)
        let leads = [0xFF0000, 0x0000FF, 0xFFFF00, 0x00FF00, 0x808080, 0xFFFFFF, 0x000000, 0x0E9F96, 0x7A1F3D, 0xF4D03F]
            .map { NotchRGB(hex: UInt32($0)) }
        for lead in leads {
            let tones = Dictionary(uniqueKeysWithValues: NotchDanceTone.allCases.map { ($0, $0.of(lead)) })
            for tone in NotchDanceTone.allCases {
                let level = tones[tone]?.luminance ?? 0
                suite.expect(level >= tone.luminance.lowerBound - 0.005 && level <= tone.luminance.upperBound + 0.06,
                             "\(tone) of \(lead) lands at its luminance: \(level)")
            }
            suite.expect([NotchDanceTone.light, .mid, .greySuit].allSatisfy { NotchRGB.contrast(tones[$0]!, black) >= 7 }
                            && [NotchDanceTone.deep, .suit].allSatisfy { NotchRGB.contrast(tones[$0]!, black) >= 4.5 }
                            && (tones[.trousers]?.luminance ?? 0) >= 0.3 - 0.005,
                         "light and mid read at 7:1 on black, deep at 4.5:1, trousers never below 0.3")
            suite.expect((tones[.light]?.luminance ?? 0) > (tones[.mid]?.luminance ?? 0)
                            && (tones[.mid]?.luminance ?? 0) > (tones[.deep]?.luminance ?? 0),
                         "light, mid and deep step down in that order")
            let tie = NotchDanceTone.tie(lead)
            suite.expect(NotchRGB.contrast(tie, NotchDanceTone.paper) >= 2.4 && NotchRGB.contrast(tie, black) >= 4,
                         "a tie stands out on a white shirt and still clears black: \(tie)")
        }
        suite.expect(NotchDanceTone.paper == NotchRGB(hex: 0xF7F5F0), "heads and hands are paper, never a skin tone")
        let pink = NotchDanceTone.light.of(NotchRGB(hex: 0xFF0055)).hsb.saturation
        suite.expect(pink <= NotchDanceTone.light.saturationCap + 0.01, "a light shirt is a pastel, not a neon")
    }

    /// A cover with no colour of its own wears the companion's: the cast
    /// member's own colours, else an Office palette dealt by the song.
    private static func colourlessContracts(_ suite: TestSuite) {
        for member in NotchMascotStyle.allCases where member.isCast {
            let seeds = NotchColourlessSong.seeds(cast: member, song: "any song")
            let own = NotchIslandGlow.idleSeeds(look: NotchMascotLook(style: member, shape: .ball, palette: .pearl),
                                                dealt: member)
            suite.expect(seeds == own && seeds.count == 3 && seeds.allSatisfy { $0.hsb.saturation >= 0.5 },
                         "a black-and-white song wears \(member.rawValue)'s own colours, vivid, not grey")
        }
        for member in [NotchMascotStyle.minimal, .robot, .shuffle] {
            suite.expect(NotchColourlessSong.office.contains(NotchColourlessSong.seeds(cast: member, song: "k")),
                         "\(member.rawValue) is not of the cast, so the song is dealt an Office palette")
        }
        suite.expect(NotchColourlessSong.seeds(cast: nil, song: nil) == NotchColourlessSong.teapot,
                     "with no companion and no song key, the teapot's teal")
        suite.expect(NotchColourlessSong.office == [NotchColourlessSong.teapot, NotchColourlessSong.beet,
                                                    NotchColourlessSong.gold]
                        && NotchColourlessSong.teapot.first == NotchRGB(hex: 0x0E9F96)
                        && NotchColourlessSong.beet.first == NotchRGB(hex: 0x9E1F4E)
                        && NotchColourlessSong.gold.first == NotchRGB(hex: 0xC9A227),
                     "the Office palettes: teapot, beet and gold")
        let keys = (0..<40).map { "song \($0)" }
        let dealt = keys.map { NotchColourlessSong.officeIndex($0) }
        suite.expect(keys.map { NotchColourlessSong.officeIndex($0) } == dealt && Set(dealt) == [0, 1, 2],
                     "a song is dealt the same Office palette every time, and every palette comes up")
        // FNV-1a, the same in every launch, not Swift's per-process hash.
        suite.expect(NotchColourlessSong.officeIndex("a") == Int(0xaf63dc4c8601ec8c as UInt64 % 3),
                     "the deal hashes the song's key the same way in every launch")
        for member in NotchMascotStyle.allCases where member.isCast {
            let seeds = NotchColourlessSong.seeds(cast: member, song: nil)
            suite.expect(seeds.allSatisfy { $0.toned(maxLuminance: 0.18, minLuminance: 0.07).luminance >= 0.06 },
                         "\(member.rawValue)'s colours glow rather than going black")
        }
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
