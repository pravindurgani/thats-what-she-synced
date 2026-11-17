// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Deals the member of the cast a companion set to Shuffle shows: another
/// one each time a new song starts, and with nothing playing at most once
/// an hour. It listens for songs only once a shuffled companion has been
/// drawn, and stops when the companion is set to something else. A quiet
/// deal waits on a single timer an hour away, and is checked again when
/// the companion comes back into sight, since a sleeping Mac holds timers
/// back. Main thread only.
final class NotchMascotShuffleService: ObservableObject {
    static let shared = NotchMascotShuffleService()

    /// The member out now. A fresh launch deals one at random.
    @Published private(set) var member: NotchMascotStyle
    private var hand: NotchMascotShuffle
    private var playbackSubscription: AnyCancellable?
    private var quietWork: DispatchWorkItem?
    private var playing = false

    private init() {
        hand = .first(at: Date(), random: Double.random(in: 0..<1))
        member = hand.member
    }

    /// Listens for songs, once, and deals now if a quiet hour has gone by.
    func start() {
        guard stillShuffled() else { return }
        guard playbackSubscription == nil else { rest(); return }
        // Nil while nothing plays; an empty key while something plays that
        // gives no names, which tells no song from the next. Heard on the
        // next turn of the main queue, so even the first reading finds the
        // subscription in place to schedule the quiet deal against.
        playbackSubscription = NotchMusicService.shared.$playback
            .map { playback -> String? in
                guard let playback, playback.isPlaying else { return nil }
                return NotchMascotShuffle.songKey(title: playback.track.title, artist: playback.track.artist,
                                                  album: playback.track.album) ?? ""
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
        if let key, !key.isEmpty, hand.hears(song: key, at: Date(), random: Double.random(in: 0..<1)) { publish() }
        scheduleQuietDeal()
    }

    private func rest() {
        guard stillShuffled(), !playing else { return }
        if hand.rests(at: Date(), random: Double.random(in: 0..<1)) { publish() }
        scheduleQuietDeal()
    }

    /// Set to another style, it stops listening until a shuffled companion
    /// is drawn again.
    private func stillShuffled() -> Bool {
        guard NotchMascotSupport.look().style == .shuffle else {
            playbackSubscription = nil
            quietWork?.cancel()
            quietWork = nil
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

    private func publish() {
        if member != hand.member { member = hand.member }
    }
}
