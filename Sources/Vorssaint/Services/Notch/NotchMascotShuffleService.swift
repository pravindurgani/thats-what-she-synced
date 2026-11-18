// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Deals the member of the cast a companion set to Shuffle shows: another
/// one each time a new song starts, and with nothing playing at most once
/// an hour. A new song is dealt for once its names have settled
/// (NotchSongSettle), so a title arriving before its artist brings out one
/// member, not two in a row. It listens for songs only once a shuffled
/// companion has been drawn, and stops when the companion is switched off
/// or set to something else. A quiet deal waits on a single timer an hour
/// away, and is checked again when the companion comes back into sight,
/// since a sleeping Mac holds timers back. The hand is saved with each
/// deal, so a relaunch keeps the member out, and its quiet hour, until the
/// next. Main thread only.
final class NotchMascotShuffleService: ObservableObject {
    static let shared = NotchMascotShuffleService()

    /// The member out now: the one saved from the last deal, kept across a
    /// relaunch, or one dealt at random the first time.
    @Published private(set) var member: NotchMascotStyle
    private var hand: NotchMascotShuffle {
        didSet { if hand != oldValue { save() } }
    }
    /// Whether the hand is in defaults. A first one is saved only once a
    /// shuffled companion is drawn, never for a companion that only reads it.
    private var saved: Bool
    private var playbackSubscription: AnyCancellable?
    private var quietWork: DispatchWorkItem?
    private var playing = false
    /// A new song waiting for its names to settle, and the one read of it
    /// queued for when the wait is up.
    private var settle = NotchSongSettle()
    private var settleWork: DispatchWorkItem?

    private init() {
        let now = Date()
        let stored = NotchMascotShuffle(stored: UserDefaults.standard.dictionary(forKey: DefaultsKey.notchMascotShuffleHand),
                                        now: now)
        saved = stored != nil
        hand = stored ?? .first(at: now, random: Double.random(in: 0..<1))
        member = hand.member
    }

    private func save() {
        UserDefaults.standard.set(hand.stored, forKey: DefaultsKey.notchMascotShuffleHand)
        saved = true
    }

    /// Listens for songs, once, and deals now if a quiet hour has gone by.
    func start() {
        guard stillShuffled() else { return }
        if !saved { save() }
        guard playbackSubscription == nil else { rest(); return }
        // Nil while nothing plays; an empty key while something plays that
        // gives no names, which tells no song from the next. Heard on the
        // next turn of the main queue, so even the first reading finds the
        // subscription in place to schedule the quiet deal against.
        playbackSubscription = NotchMusicService.shared.$playback
            .map { playback -> String? in
                guard let playback, playback.isPlaying else { return nil }
                return NotchMascotShuffle.songKey(title: playback.track.title, artist: playback.track.artist) ?? ""
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] key in self?.hear(key) }
    }

    /// Picked again in Settings, Shuffle deals another member at once.
    func dealNow() {
        hand.redeal(at: Date(), random: Double.random(in: 0..<1))
        publish()
        scheduleQuietDeal()
    }

    private func hear(_ key: String?) {
        guard stillShuffled() else { return }
        playing = key != nil
        settleWork?.cancel()
        settleWork = nil
        if let key, !key.isEmpty { settles(key) } else { settle.forget() }
        scheduleQuietDeal()
    }

    /// Deals for a new song once the same key has held for a settle: read
    /// as it arrives, then once more when its wait is up. Another key in
    /// between, as the artist landing after the title makes, starts the wait
    /// over for that one. The song already dealt for needs no wait.
    private func settles(_ key: String) {
        guard key != hand.song else { settle.forget(); return }
        let now = ProcessInfo.processInfo.systemUptime
        if settle.hears(key, at: now) {
            if hand.hears(song: key, at: Date(), random: Double.random(in: 0..<1)) { publish() }
            return
        }
        guard let due = settle.due else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.settleWork = nil
            guard self.stillShuffled() else { return }
            self.settles(key)
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, due - now), execute: work)
    }

    private func rest() {
        guard stillShuffled(), !playing else { return }
        if hand.rests(at: Date(), random: Double.random(in: 0..<1)) { publish() }
        scheduleQuietDeal()
    }

    /// Switched off, or set to another style, it stops listening and drops
    /// any deal it was waiting on, until a shuffled companion is drawn
    /// again. A companion that is off never deals or saves a hand.
    private func stillShuffled() -> Bool {
        guard NotchMascotSupport.isEnabled(), NotchMascotSupport.look().style == .shuffle else {
            playbackSubscription = nil
            quietWork?.cancel()
            quietWork = nil
            settleWork?.cancel()
            settleWork = nil
            settle.forget()
            playing = false
            return false
        }
        return true
    }

    private func scheduleQuietDeal() {
        quietWork?.cancel()
        quietWork = nil
        guard !playing, playbackSubscription != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.quietWork = nil
            self?.rest()
        }
        quietWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, hand.quietDealDue.timeIntervalSinceNow), execute: work)
    }

    /// A deal can land while the island is drawing (it starts from a view
    /// appearing), so the new member is published on the next turn of the
    /// main queue, never from inside a view update.
    private func publish() {
        let next = hand.member
        DispatchQueue.main.async { [weak self] in
            guard let self, self.member != next else { return }
            self.member = next
        }
    }
}
