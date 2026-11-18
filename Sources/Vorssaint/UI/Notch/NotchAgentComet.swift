// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore
import SwiftUI

/// An agent's mark in its wing: the mark as its maker draws it, never
/// redrawn, inside a comet ring that orbits while the agent works and closes
/// into a green check for a moment when its turn ends. Under Reduce Motion,
/// and in Low Power Mode, the ring rests and colour carries the state.
struct NotchAgentWingMark: View {
    let wing: NotchAgentWing
    let ring: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var lowPower = NotchLowPowerMode.shared
    /// Whether it has shown: a wing that first shows finished, as the strip
    /// comes back from the finish notice, closes its ring before its check.
    @State private var shown = false

    var body: some View {
        let room = ring + NotchAgentWings.haloRoom * 2
        let moves = !reduceMotion && !lowPower.isOn
        let checked = wing.finished && (shown || !moves)
        ZStack {
            NotchAgentCometBridge(stops: wing.provider.glowStops, diameter: ring, finished: wing.finished,
                                  moves: moves)
                .frame(width: room, height: room)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: (ring * 0.42).rounded(), weight: .bold))
                    .foregroundStyle(Color(nsColor: NotchAgentWings.done.nsColor))
                    .transition(.opacity)
            } else if !wing.finished {
                NotchAgentMark(provider: wing.provider, size: NotchAgentWings.markSize(ring: ring))
                    .transition(.opacity)
            }
        }
        // The halo spills past the ring; only the ring takes room.
        .frame(width: ring, height: ring)
        // The check comes in as the ring finishes closing.
        .animation(reduceMotion ? NotchSongMotion.reduced
                    : .easeOut(duration: 0.25).delay(checked ? NotchAgentWings.closing : 0),
                   value: checked)
        .onAppear { shown = true }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct NotchAgentCometBridge: NSViewRepresentable {
    let stops: [NotchRGB]
    let diameter: CGFloat
    let finished: Bool
    let moves: Bool

    func makeNSView(context: Context) -> NotchAgentCometView { NotchAgentCometView() }

    func updateNSView(_ view: NotchAgentCometView, context: Context) {
        view.configure(stops: stops, diameter: diameter, finished: finished, moves: moves)
    }

    static func dismantleNSView(_ view: NotchAgentCometView, coordinator: ()) { view.stop() }
}
