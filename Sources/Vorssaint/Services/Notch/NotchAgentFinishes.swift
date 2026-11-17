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
        usage.turnsEnded.sink { [weak self] provider in self?.ended(provider) }.store(in: &subscriptions)
        // The published value arrives before the snapshot changes, so it is
        // read here rather than from the service.
        usage.$snapshot.map(\.live).removeDuplicates()
            .sink { [weak self] live in self?.saw(live) }
            .store(in: &subscriptions)
    }

    /// The agents whose ring has closed, with `live` the turns at work now.
    /// A reported end counts as soon as its agent has left the list, before
    /// the log has caught up, so nothing between the two can drop the wing.
    func finished(live: [AgentLiveSession]) -> Set<AgentProvider> {
        let working = Set(live.map(\.provider))
        return log.finished.union(log.reported.keys.filter { !working.contains($0) })
    }

    func model(live: [AgentLiveSession]) -> NotchAgentStripModel {
        NotchAgentStripModel(live: live, finished: finished(live: live))
    }

    /// The turns a wing reads: those at work, or, once its ring has
    /// closed, the agent's last turns.
    func sessions(for wing: NotchAgentWing, live: [AgentLiveSession]) -> [AgentLiveSession] {
        wing.finished ? lastSessions[wing.provider] ?? [] : live.filter { $0.provider == wing.provider }
    }

    private func ended(_ provider: AgentProvider) {
        // A turn the island never showed at work, too short for a reading
        // to land, has no ring to close.
        guard lastSessions[provider] != nil else { return }
        var next = log
        next.ended(provider, at: Date())
        apply(next, live: AgentUsageService.shared.snapshot.live)
    }

    private func saw(_ live: [AgentLiveSession]) {
        for provider in Set(live.map(\.provider)) { lastSessions[provider] = live.filter { $0.provider == provider } }
        apply(log, live: live)
    }

    private func apply(_ candidate: NotchAgentFinishLog, live: [AgentLiveSession]) {
        var next = candidate
        let working = Set(live.map(\.provider))
        let deadline = next.update(working: working, now: Date())
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
