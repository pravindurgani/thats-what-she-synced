// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The closed island while agents work. One agent keeps its mark, in its
/// comet ring, on one side of the camera and the reading the person chose
/// on the other. Two take a wing each, the first in the agents' own order on
/// the left and the second mirrored on the right, each with its own reading
/// when the menus leave room. The wings are as wide as their content needs,
/// alike on both sides, and sit at the ends, where the island shows.
struct NotchAgentStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var finishes = NotchAgentFinishes.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue

    var body: some View {
        let model = finishes.model(live: usage.snapshot.live)
        // The last agent stopping empties the list before the strip has left.
        NotchStripHold(model, shows: !model.wings.isEmpty) { strip(model: $0) }
    }

    @ViewBuilder private func strip(model: NotchAgentStripModel) -> some View {
        // Resolve layout once per presentation update. The timeline captures
        // these values, so ticking the clock never remeasures the island or
        // walks the preferences for every font, inset and frame.
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let ring = NotchAgentWings.ringDiameter(contentHeight: geometry.compactActivityContentHeight)
        let ringInset = !geometry.compactActivityUsesFooter
            ? geometry.compactActivityEdgeInset(boxHeight: ring, radius: ring / 2) : 0
        HStack(spacing: 0) {
            if model.twoSided {
                twoSided(model, geometry: geometry, ring: ring, ringInset: ringInset)
            } else {
                oneSided(model, geometry: geometry, ring: ring, ringInset: ringInset)
            }
        }
        .frame(height: geometry.compactActivityContentHeight)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.wings.map(\.provider.displayName).joined(separator: ", "))
        .accessibilityValue(spokenReading(model))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { service.openActivity(.agents) }
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    /// One agent: its ring at the left end, the chosen reading at the right.
    @ViewBuilder private func oneSided(_ model: NotchAgentStripModel, geometry: NotchGeometry, ring: CGFloat,
                                       ringInset: CGFloat) -> some View {
        let wing = geometry.compactActivityWingWidth
        let height = geometry.compactActivityContentHeight
        let textSize = NotchAgentSupport.stripTextSize(height: height)
        let textInset = !geometry.compactActivityUsesFooter
            ? geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0) : 0
        let first = model.wings.first
        Button { service.openActivity(.agents) } label: {
            HStack(spacing: 0) {
                if let first, wing >= 28 { NotchAgentWingMark(wing: first, ring: ring) }
            }
            .padding(.leading, ringInset)
            .frame(width: wing, height: height, alignment: .leading)
            .contentShape(Rectangle())
        }
        Color.clear.frame(width: geometry.compactActivityCameraGap)
        Button { service.openActivity(.agents) } label: {
            Group {
                if wing >= 42, let first {
                    NotchAgentReadoutTimeline(readout: chosenReadout) { date in
                        readingText(reading(first, model: model, at: date), size: textSize, provider: first.provider)
                    }
                }
            }
            .padding(.trailing, textInset)
            .frame(width: wing, height: height, alignment: .trailing)
            .contentShape(Rectangle())
        }
    }

    /// Two agents: each ring at its own end, mirrored, with that agent's
    /// reading toward the camera when both readings fit.
    @ViewBuilder private func twoSided(_ model: NotchAgentStripModel, geometry: NotchGeometry, ring: CGFloat,
                                       ringInset: CGFloat) -> some View {
        let wing = geometry.compactActivityWingWidth
        let height = geometry.compactActivityContentHeight
        let size = NotchAgentWings.readingSize(contentHeight: height)
        let now = Date()
        let widest = model.wings.map { NotchAgentWings.readingWidth(reading($0, model: model, at: now), size: size) }
            .max() ?? 0
        // Both or neither, so the two wings read as one piece.
        let fits = NotchAgentWings.readingFits(wing: wing, ring: ring, ringInset: ringInset, reading: widest,
                                               cameraGap: NotchAgentSupport.stripCameraGap)
        let showsRings = wing >= ringInset + ring
        Button { service.openActivity(.agents) } label: {
            HStack(spacing: NotchAgentWings.markGap) {
                if showsRings { NotchAgentWingMark(wing: model.wings[0], ring: ring) }
                if fits { wingReading(model.wings[0], model: model, size: size) }
            }
            .padding(.leading, ringInset)
            .frame(width: wing, height: height, alignment: .leading)
            .contentShape(Rectangle())
        }
        Color.clear.frame(width: geometry.compactActivityCameraGap)
        Button { service.openActivity(.agents) } label: {
            HStack(spacing: NotchAgentWings.markGap) {
                if fits { wingReading(model.wings[1], model: model, size: size) }
                if showsRings { NotchAgentWingMark(wing: model.wings[1], ring: ring) }
            }
            .padding(.trailing, ringInset)
            .frame(width: wing, height: height, alignment: .trailing)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder private func wingReading(_ wing: NotchAgentWing, model: NotchAgentStripModel,
                                          size: CGFloat) -> some View {
        if wing.finished {
            readingText(reading(wing, model: model, at: Date()), size: size, provider: wing.provider)
        } else {
            NotchAgentReadoutTimeline(readout: chosenReadout) { date in
                readingText(reading(wing, model: model, at: date), size: size, provider: wing.provider)
            }
        }
    }

    private func readingText(_ text: String, size: CGFloat, provider: AgentProvider) -> some View {
        Text(text)
            .font(.system(size: size, weight: .medium))
            .monospacedDigit()
            // Light enough to keep AA over the agents' glow.
            .foregroundStyle(Color(nsColor: provider.readingColor.nsColor))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            // A reading that gains a digit, like an hour passing, needs wider
            // wings; the service measures the same reading.
            .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                DispatchQueue.main.async { service.refreshPresentation() }
            }
    }

    private var chosenReadout: NotchAgentReadout { NotchAgentReadout(rawValue: readout) ?? .elapsed }

    /// One agent's reading on its wing, held where it stood once its turn ended.
    private func reading(_ wing: NotchAgentWing, model: NotchAgentStripModel, at now: Date) -> String {
        NotchAgentWings.reading(usage.snapshot, sessions: finishes.sessions(for: wing, live: model.live),
                                finished: wing.finished, readout: chosenReadout,
                                display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining,
                                focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
    }

    /// Each agent named with its reading, or as finished.
    private func spokenReading(_ model: NotchAgentStripModel) -> String {
        let text = FeatureStrings.notchAgents(l10n.language)
        return model.wings.map { wing in
            wing.finished ? text.finished(wing.provider.displayName)
                : "\(wing.provider.displayName) \(reading(wing, model: model, at: Date()))"
        }.joined(separator: ", ")
    }
}

/// Keep the original one-second cadence for time-dependent readings, but
/// install no clock at all for values updated by the observed usage snapshot.
struct NotchAgentReadoutTimeline<Content: View>: View {
    let readout: NotchAgentReadout
    @ViewBuilder var content: (Date) -> Content

    var body: some View {
        if readout.advancesWithClock {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(context.date)
            }
        } else {
            content(.now)
        }
    }
}

/// The resting island's wings: the chosen allowance, by default the one
/// closest to running out, as a ring and a number, or today's API value when
/// no allowance is known.
struct NotchAgentRestingWing: View {
    let leading: Bool
    @ObservedObject private var usage = AgentUsageService.shared
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let snapshot = usage.snapshot
        let limit = NotchAgentSupport.restingLimit(snapshot, focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
        let used = display == NotchAgentLimitDisplay.used.rawValue
        if let limit {
            let tint = agentLimitTint(limit.provider, usedFraction: limit.window.usedFraction)
            if leading {
                NotchAgentRing(value: used ? limit.window.usedFraction : limit.window.remainingFraction,
                               tint: tint, lineWidth: 2)
                    .frame(width: 11, height: 11)
            } else {
                Text(AgentFormat.percent(used ? limit.window.usedFraction : limit.window.remainingFraction))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        } else if let provider = AgentProvider.allCases.first(where: snapshot.seen.contains) {
            if leading {
                NotchAgentMark(provider: provider, size: 10)
            } else {
                Text(AgentFormat.cost(snapshot.usage(.today).total.cost))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
