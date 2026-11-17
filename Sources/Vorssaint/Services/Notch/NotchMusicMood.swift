// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How the music backdrop moves for a kind of music. The cover picks the
/// colours; the mood picks the motion's character: how fast the light drifts
/// and how strongly it answers the music's energy.
enum NotchMusicMood: String, Equatable {
    /// Classical, jazz, ambient, soundtracks: slow drift, soft response.
    case calm
    /// Hip-hop, R&B, soul, funk, reggae: mid tempo, led by the low end.
    case groove
    /// Rock, metal, punk, indie: firmer response, quicker drift.
    case drive
    /// Electronic, dance, pop: the quickest drift, the strongest beat.
    case pulse
    /// No genre known (another player, no permission): energy alone decides.
    case neutral

    /// The drift's base speed, against the designed loops at 1.
    var rate: Float {
        switch self {
        case .calm: return 0.6
        case .groove: return 1.0
        case .drive: return 1.2
        case .pulse: return 1.4
        case .neutral: return 1.0
        }
    }

    /// How strongly the light answers the music's energy, from 0 to 1.
    var response: Double {
        switch self {
        case .calm: return 0.3
        case .groove: return 0.6
        case .drive: return 0.75
        case .pulse: return 0.9
        case .neutral: return 0.55
        }
    }

    /// How much more the low bands count than the high ones in the energy read.
    var bassWeight: Double { self == .groove || self == .pulse ? 2.2 : 1.4 }

    static func from(genre: String) -> NotchMusicMood {
        let g = genre.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { g.contains($0) } }
        // Checked from the most specific family to the broadest, so "pop/rock"
        // reads as rock and "k-pop" as pop.
        if has(["classical", "ambient", "jazz", "soundtrack", "score", "new age", "acoustic", "folk",
                "easy listening", "lo-fi", "lofi", "chill", "instrumental", "piano", "meditation", "opera"]) {
            return .calm
        }
        if has(["rock", "metal", "punk", "alternative", "indie", "grunge", "hardcore", "emo"]) { return .drive }
        if has(["hip-hop", "hip hop", "rap", "r&b", "soul", "funk", "reggae", "latin", "blues", "afro",
                "dancehall", "gospel", "trap"]) {
            return .groove
        }
        if has(["electronic", "dance", "house", "techno", "edm", "trance", "dubstep", "drum", "pop", "disco",
                "synth", "electro", "bass"]) {
            return .pulse
        }
        return .neutral
    }
}

/// Reads the genre of the song Music is playing, once per song. Only Music is
/// asked: it answers through the same Automation permission the island's
/// playback buttons already use, and it is never launched by the question.
/// Other players, or Music without permission, leave the mood neutral.
enum NotchMusicGenre {
    private static let musicBundleID = "com.apple.Music"
    private static var cache: [String: NotchMusicMood] = [:]
    private static let lock = NSLock()

    static func mood(for track: RadialNowPlayingSnapshot) async -> NotchMusicMood {
        guard track.appBundleIdentifier == musicBundleID else { return .neutral }
        let key = [track.title, track.artist, track.album].map { $0 ?? "" }.joined(separator: "\u{1F}")
        lock.lock(); let known = cache[key]; lock.unlock()
        if let known { return known }
        let genre = await readGenre()
        let mood = genre.map(NotchMusicMood.from(genre:)) ?? .neutral
        // A failed read is not remembered, so granting permission later works
        // on the next song without a restart.
        if genre != nil {
            lock.lock()
            if cache.count > 256 { cache.removeAll() }
            cache[key] = mood
            lock.unlock()
        }
        return mood
    }

    private static func readGenre() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let script = """
                if application "Music" is running then
                    tell application "Music"
                        if player state is not stopped then return genre of current track
                    end tell
                end if
                return ""
                """
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch { continuation.resume(returning: nil); return }
                // Music answers in milliseconds; a hung reply must not hold the mood.
                let deadline = DispatchTime.now() + .seconds(3)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
                    if process.isRunning { process.terminate() }
                }
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { continuation.resume(returning: nil); return }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let genre = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: genre.isEmpty ? nil : genre)
            }
        }
    }
}
