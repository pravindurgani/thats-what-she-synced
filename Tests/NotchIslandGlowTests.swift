// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Which glow colours the island, in which order, and the colours the
/// companion lends it.
enum NotchIslandGlowTests {
    static func run(_ suite: TestSuite) {
        precedence(suite)
        companionColours(suite)
        restingTone(suite)
        preferences(suite)
    }

    private static func precedence(_ suite: TestSuite) {
        for agentStrip in [false, true] {
            for songGlows in [false, true] {
                for companionRests in [false, true] {
                    for idleAllowed in [false, true] {
                        let glow = NotchIslandGlow.closed(agentStrip: agentStrip, songGlows: songGlows,
                                                          companionRests: companionRests, idleAllowed: idleAllowed)
                        let expected: NotchIslandGlow = agentStrip ? .agents : songGlows ? .song
                            : companionRests && idleAllowed ? .idle : .none
                        suite.expect(glow == expected,
                                     "closed glow: agents \(agentStrip), song \(songGlows), companion \(companionRests), allowed \(idleAllowed)")
                    }
                }
            }
        }
        suite.expect(NotchIslandGlow.closed(agentStrip: true, songGlows: true, companionRests: true, idleAllowed: true) == .agents,
                     "the agents' glow wins while their strip is what shows")
        suite.expect(NotchIslandGlow.open(wearsSong: true, plainPage: false, companionOn: true, idleAllowed: true) == .song
                        && NotchIslandGlow.open(wearsSong: false, plainPage: false, companionOn: true, idleAllowed: true) == .idle,
                     "the open island wears the song, or else the companion's colours")
        suite.expect(NotchIslandGlow.open(wearsSong: false, plainPage: true, companionOn: true, idleAllowed: true) == .none
                        && NotchIslandGlow.open(wearsSong: false, plainPage: false, companionOn: false, idleAllowed: true) == .none
                        && NotchIslandGlow.open(wearsSong: false, plainPage: false, companionOn: true, idleAllowed: false) == .none,
                     "the camera, captures and Command Bar, a switched-off companion and a switched-off glow keep black")
        suite.expect(NotchIslandGlow.idleAllowed(enabled: true, lowPower: false)
                        && !NotchIslandGlow.idleAllowed(enabled: true, lowPower: true)
                        && !NotchIslandGlow.idleAllowed(enabled: false, lowPower: false),
                     "Low Power Mode and the switch both turn the companion's glow off")
    }

    private static func companionColours(_ suite: TestSuite) {
        func rgb(_ red: Double, _ green: Double, _ blue: Double) -> NotchRGB { NotchRGB(red: red, green: green, blue: blue) }
        suite.expect(NotchIslandGlow.idleSeeds(light: rgb(0.99, 0.98, 0.96), shade: rgb(0.84, 0.85, 0.90)) == nil,
                     "a grey companion leaves its colours to the coverless palette")
        let peachShade = rgb(0.98, 0.64, 0.50)
        if let seeds = NotchIslandGlow.idleSeeds(light: rgb(1.00, 0.86, 0.74), shade: peachShade) {
            suite.expect(seeds.count == 3 && abs(seeds[0].hsb.hue - peachShade.hsb.hue) < 0.01,
                         "the companion's most colourful colour leads its glow")
            suite.expect(seeds.allSatisfy { $0.hsb.saturation >= 0.69 && abs($0.hsb.brightness - 0.95) < 0.001 },
                         "the companion's glow is as vivid as a song's")
            suite.expect(Set(seeds).count == 3, "three distinct colours give the glow depth")
            suite.expect(!seeds.contains { NotchIslandGlow.isYellow($0.hsb.hue) },
                         "an orange companion's glow steps away from yellow, which turns olive this deep")
        } else {
            suite.expect(false, "a peach companion lends its colours")
        }
        // A beet: magenta bulb, green leaves, each a colour of its own.
        let bulb = NotchRGB(hex: 0x7A1F3D), leaves = NotchRGB(hex: 0x3F7D3A)
        let beet = NotchIslandGlow.idleSeeds(light: leaves, shade: bulb)
        suite.expect(beet.map { abs($0[0].hsb.hue - bulb.hsb.hue) < 0.01 && abs($0[1].hsb.hue - leaves.hsb.hue) < 0.01 } == true,
                     "a companion of two colours lends both")
    }

    private static func restingTone(_ suite: TestSuite) {
        let seeds = [NotchRGB(hue: 0.6, saturation: 0.8, brightness: 0.95), NotchRGB(hue: 0.14, saturation: 0.8, brightness: 0.95)]
        let glow = NotchIslandGlow.restingGlow(seeds)
        suite.expect(glow[0].luminance <= NotchIslandGlow.restingLuminance.upperBound + 0.001
                        && glow[0].luminance >= NotchIslandGlow.restingLuminance.lowerBound - 0.001,
                     "the resting glow is toned deep enough for the companion to stand out")
        suite.expect(glow[1].luminance > NotchIslandGlow.restingLuminance.upperBound
                        && glow[1].luminance <= NotchIslandGlow.restingYellowLuminance + 0.001,
                     "a gold companion's glow keeps enough light to read gold")
        // The companion's lit top, in any of its colours, stands out at 3:1
        // against its glow, which lies under the veil's lightest stop, 0.12,
        // across the middle of the strip where the companion rests.
        let lightest = [NotchRGB(red: 1, green: 0.96, blue: 0.64), NotchRGB(red: 1, green: 0.86, blue: 0.74),
                        NotchRGB(red: 0.88, green: 0.83, blue: 1), NotchRGB(red: 0.77, green: 0.9, blue: 1)]
        for top in lightest {
            suite.expect(NotchRGB.contrast(top, glow[0].veiled(by: 0.12)) >= 3,
                         "the companion stands out against its resting glow")
        }
        suite.expect(NotchRGB.contrast(lightest[0], glow[1].veiled(by: 0.12)) >= 3,
                     "a yellow companion stands out against its own gold glow")
    }

    private static func preferences(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-idle-glow"
        guard let defaults = UserDefaults(suiteName: domain) else {
            suite.expect(false, "the idle glow test suite opens")
            return
        }
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(NotchIdleGlowPreferences.enabled(in: defaults), "the companion's glow is on unless switched off")
        defaults.set(false, forKey: DefaultsKey.notchIdleGlowEnabled)
        suite.expect(!NotchIdleGlowPreferences.enabled(in: defaults), "the switch turns the companion's glow off")
        suite.expect(DefaultsKey.notchIdleGlowEnabled == "notchIdleGlowEnabled", "the switch keeps its documented name")
    }
}
