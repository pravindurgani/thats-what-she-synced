// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Watches agents' turns end, so the closed island can close the finished
/// agent's ring and show its check for a moment before its wing goes. The
/// island's service and its strip read the same log, so the strip's width
/// and what it draws agree. Main thread only.
final class NotchAgentFinishes: ObservableObject {
    static let shared = NotchAgentFinishes()

    @Published private(set) var log = NotchAgentFinishLog()
    /// Each agent's turns as last seen at work: a finished wing's reading
    /// holds where its turn ended.
    private var lastSessions: [AgentProvider: [AgentLiveSession]] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    private var wake: DispatchWorkItem?

    private init() {}

    /// Starts listening; again does nothing.
    func start() {
        guard subscriptions.isEmpty else { return }
        let usage = AgentUsageService.shared
        usage.turnsEnded.sink { [weak self] end in self?.ended(end) }.store(in: &subscriptions)
        // The published value arrives before the snapshot changes, so it is
        // read here rather than from the service.
        usage.$snapshot.map(\.live).removeDuplicates()
            .sink { [weak self] live in self?.saw(live) }
            .store(in: &subscriptions)
    }

    /// The agents whose ring has closed, with `live` the turns at work now.
    func finished(live: [AgentLiveSession]) -> Set<AgentProvider> { log.finished(live: live) }

    func model(live: [AgentLiveSession]) -> NotchAgentStripModel {
        NotchAgentStripModel(live: live, finished: finished(live: live))
    }

    /// The turns a wing reads: those at work, or, once its ring has
    /// closed, the agent's last turns.
    func sessions(for wing: NotchAgentWing, live: [AgentLiveSession]) -> [AgentLiveSession] {
        wing.finished ? lastSessions[wing.provider] ?? [] : live.filter { $0.provider == wing.provider }
    }

    /// A notice covering the closed island holds the checks, so they are
    /// seen once it goes; `stripShows` tells, as it goes, whether the
    /// agents' strip comes back to show them.
    func cover(_ covered: Bool, stripShows: Bool = false) {
        var next = log
        if covered { next.cover(at: Date()) } else { next.uncover(at: Date(), stripShows: stripShows) }
        guard next != log else { return }
        apply(next, live: AgentUsageService.shared.snapshot.live)
    }

    private func ended(_ end: AgentTurnEnd) {
        // A turn the island never showed at work, too short for a reading
        // to land, has no ring to close.
        guard lastSessions[end.provider] != nil else { return }
        var next = log
        next.ended(end, at: Date())
        apply(next, live: AgentUsageService.shared.snapshot.live)
    }

    private func saw(_ live: [AgentLiveSession]) {
        for provider in Set(live.map(\.provider)) { lastSessions[provider] = live.filter { $0.provider == provider } }
        apply(log, live: live)
    }

    private func apply(_ candidate: NotchAgentFinishLog, live: [AgentLiveSession]) {
        var next = candidate
        let working = Set(live.map(\.provider))
        let deadline = next.update(live: live, now: Date())
        lastSessions = lastSessions.filter { working.contains($0.key) || next.finished.contains($0.key)
            || next.reported[$0.key] != nil }
        if next != log { log = next }
        wake?.cancel()
        wake = nil
        guard let deadline else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.apply(self.log, live: AgentUsageService.shared.snapshot.live)
        }
        wake = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, deadline.timeIntervalSinceNow), execute: work)
    }
}
