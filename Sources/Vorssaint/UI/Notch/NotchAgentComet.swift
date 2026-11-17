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

    var body: some View {
        let room = ring + NotchAgentWings.haloRoom * 2
        ZStack {
            NotchAgentCometBridge(stops: wing.provider.glowStops, diameter: ring, finished: wing.finished,
                                  moves: !reduceMotion && !lowPower.isOn)
                .frame(width: room, height: room)
            if wing.finished {
                Image(systemName: "checkmark")
                    .font(.system(size: (ring * 0.42).rounded(), weight: .bold))
                    .foregroundStyle(Color(nsColor: NotchAgentWings.done.nsColor))
                    .transition(.opacity)
            } else {
                NotchAgentMark(provider: wing.provider, size: NotchAgentWings.markSize(ring: ring))
                    .transition(.opacity)
            }
        }
        // The halo spills past the ring; only the ring takes room.
        .frame(width: ring, height: ring)
        // The check comes in as the ring finishes closing.
        .animation(reduceMotion ? NotchSongMotion.reduced
                    : .easeOut(duration: 0.25).delay(wing.finished ? NotchAgentWings.closing : 0),
                   value: wing.finished)
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
