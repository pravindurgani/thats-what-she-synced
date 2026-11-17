// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The charge reading a battery notice shows, as its title names it.
enum NotchOfficeBattery: Equatable {
    case pluggedIn, charging, charged, onBattery, low
}

/// What joined: something worn on the head, or something that fills a room.
enum NotchOfficeSpeaker: Equatable {
    case earphones, speaker
}

/// What a mirrored notification is, read from its app and its words.
enum NotchOfficeChannel: Equatable {
    case message, call
}

/// The Office treatment one notice carries. It is attached where the notice
/// is raised, and only while the Office moments are on, so a notice without
/// one draws exactly as it always has.
struct NotchOfficeCue: Equatable {
    enum Kind: Equatable {
        case battery(NotchOfficeBattery)
        case connect(NotchOfficeSpeaker)
        case message
        case call
        case meeting
    }

    let kind: Kind
    /// The lower third's words, or nil where the app is not in English: the
    /// visuals stay and only the joke is dropped.
    var caption: String?
    /// How full the mug is, 0 to 1, for a battery moment.
    var level: Double?
    /// The calendar's own colour for a meeting starting.
    var accent: NotchCalendarColor?
    /// Where a meeting starting is held, when its event says.
    var place: String?

    /// A call and a meeting starting open the island into a card of their own.
    var opensCard: Bool { kind == .call || kind == .meeting }

    /// The battery moments draw the mug beside the percentage.
    var showsMug: Bool {
        if case .battery = kind { return true }
        return false
    }
}

/// The rules behind the island's Office moments: when they are on, which
/// moment a notice is, the words under it and how much room those take. The
/// views live with the island's (NotchOfficeComponents.swift and its siblings).
///
/// The captions are a parody of documentary lower thirds and only work in
/// English, so they are plain constants here rather than localised strings.
enum NotchOfficeMoments {
    // MARK: - The master switch

    private static var cached: Bool?
    private static var observer: NSObjectProtocol?

    /// On unless turned off with
    /// `defaults write <bundle id> notchOfficeModeEnabled -bool false`, then a
    /// relaunch: a change from another process is read on the next launch, as
    /// the song mode's is. Read on every notice, so it is cached and dropped
    /// whenever this process changes its own defaults.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults === UserDefaults.standard else { return read(defaults) }
        if let cached { return cached }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                              object: nil, queue: .main) { _ in cached = nil }
        }
        let fresh = read(defaults)
        cached = fresh
        return fresh
    }

    private static func read(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: DefaultsKey.notchOfficeModeEnabled) as? Bool ?? true
    }

    /// The jokes are written in English and do not survive translation, so
    /// every other language keeps the visuals and loses the caption.
    static func showsCaptions(in language: AppLanguage) -> Bool { language == .enUS }

    // MARK: - Captions

    static let callCaption = "Conference room. Now."
    static let meetingCaption = "Conference room. Now."
    static let meetingSoonCaption = "Conference room, five minutes."
    /// The roles a sender is given, one each, for as long as they keep writing.
    static let roles = ["Assistant to the Regional Texter", "Regional Messenger", "Head of Sending"]

    static func caption(for battery: NotchOfficeBattery) -> String {
        switch battery {
        case .pluggedIn: return "Coffee's on."
        case .charging: return "Refilling the mug."
        case .charged: return "World's Best Battery."
        case .onBattery: return "Back to the field."
        case .low: return "I DECLARE\u{2026} BANKRUPTCY!"
        }
    }

    static func caption(for speaker: NotchOfficeSpeaker) -> String {
        switch speaker {
        case .earphones: return "Cafe Disco is open."
        case .speaker: return "Everybody, dance."
        }
    }

    // MARK: - Battery

    /// The reading a battery notice names, as `powerChanged` titles it: a low
    /// charge first, then the adapter's state.
    static func battery(low: Bool, externalConnected: Bool, charging: Bool, percent: Int?) -> NotchOfficeBattery {
        if low { return .low }
        guard externalConnected else { return .onBattery }
        if charging { return .charging }
        return percent == 100 ? .charged : .pluggedIn
    }

    static func batteryCue(_ battery: NotchOfficeBattery, percent: Int?, language: AppLanguage) -> NotchOfficeCue {
        let level = percent.map { min(1, max(0, Double($0) / 100)) }
        return NotchOfficeCue(kind: .battery(battery),
                              caption: showsCaptions(in: language) ? caption(for: battery) : nil,
                              level: level)
    }

    // MARK: - Headphones and speakers

    /// Read from the symbol the connect notice already chose for the device.
    static func speaker(forSymbol symbol: String) -> NotchOfficeSpeaker {
        let symbol = symbol.lowercased()
        return ["airpods", "headphones", "beats", "earbuds", "earpods"].contains { symbol.contains($0) }
            ? .earphones : .speaker
    }

    static func connectCue(symbol: String, language: AppLanguage) -> NotchOfficeCue {
        let speaker = speaker(forSymbol: symbol)
        return NotchOfficeCue(kind: .connect(speaker), caption: showsCaptions(in: language) ? caption(for: speaker) : nil)
    }

    // MARK: - Messages and calls

    /// Apps whose notifications are someone writing. Matched as whole words,
    /// ignoring case, so "Microsoft Teams (work or school)" and "Telegram
    /// Desktop" count and "iPhone Mirroring" is not the Phone app.
    static let messageApps = ["messages", "imessage", "whatsapp", "telegram", "signal", "slack", "discord",
                              "microsoft teams", "teams", "messenger", "skype", "wechat", "viber", "beeper"]
    /// Apps whose notifications are a call, unless they say it was missed.
    static let callApps = ["facetime", "phone"]

    /// A ringing call from a call app or from any app whose words say so, or
    /// a message from a messaging app; nil for everything else. A call that
    /// was missed, declined or ended is not ringing, and keeps the plain banner.
    static func channel(for content: NotchNotificationContent) -> NotchOfficeChannel? {
        let app = words(content.app)
        let fields = [content.title, content.subtitle, content.body].map(normalized)
        if fields.contains(where: saysCallIsOver) { return nil }
        if callApps.contains(where: { app.containsWords($0) }) || fields.contains(where: saysRinging) { return .call }
        return messageApps.contains(where: { app.containsWords($0) }) ? .message : nil
    }

    static func communicationCue(for content: NotchNotificationContent, language: AppLanguage) -> NotchOfficeCue? {
        guard let channel = channel(for: content) else { return nil }
        let captions = showsCaptions(in: language)
        switch channel {
        case .call: return NotchOfficeCue(kind: .call, caption: captions ? callCaption : nil)
        case .message: return NotchOfficeCue(kind: .message, caption: captions ? role(forSender: content.compactTitle) : nil)
        }
    }

    /// The same sender keeps the same role from one message, and one launch,
    /// to the next: Swift's own `hashValue` is seeded per launch, so the
    /// role is picked from a fixed FNV-1a hash of the sender's name instead.
    static func role(forSender sender: String) -> String {
        roles[Int(stableHash(normalized(sender)) % UInt64(roles.count))]
    }

    /// 64-bit FNV-1a over the UTF-8 bytes.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// Lowercased, with runs of white space as one space and none at the ends.
    static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Only a short line is read as a call's label: a long message that
    /// mentions a call is still a message.
    private static let callLabelLength = 48

    private static func saysRinging(_ field: String) -> Bool {
        guard !field.isEmpty, field.count <= callLabelLength else { return false }
        if field.hasPrefix("incoming"), field.contains("call") || field.contains("facetime") { return true }
        if field.contains("is calling you") || field.hasSuffix(" is calling") || field.hasSuffix(" is calling\u{2026}")
            || field.hasSuffix(" is calling...") { return true }
        if field == "calling" || field.hasPrefix("calling\u{2026}") || field.hasPrefix("calling...") { return true }
        if field.contains("wants to facetime") || field.contains("would like to facetime") { return true }
        if field.contains("to a huddle") { return true }
        // A line that is only the label, as some apps title a ringing call;
        // "Video call later?" is a message.
        let label = field.trimmingCharacters(in: CharacterSet(charactersIn: ".!\u{2026} "))
        return ["voice call", "video call", "audio call", "group call", "facetime audio", "facetime video", "ringing"]
            .contains(label)
    }

    /// A call that is no longer ringing, said in its own short line. "I
    /// missed you" is still a message.
    private static func saysCallIsOver(_ field: String) -> Bool {
        guard !field.isEmpty, field.count <= callLabelLength else { return false }
        if field.contains("voicemail") || field.contains("call ended") || field.contains("call failed") { return true }
        guard field.contains("call") || field.contains("facetime") else { return false }
        return field.contains("missed") || field.contains("declined") || field.contains("no answer")
    }

    // MARK: - Calendar

    /// How long before an event its countdown earns its caption.
    static let meetingSoonLead: TimeInterval = 5 * 60

    /// An event that has not begun, starting within five minutes.
    static func meetingSoon(_ countdown: NotchCalendarCountdown?, now: Date) -> Bool {
        guard let countdown, !countdown.ongoing else { return false }
        let left = countdown.event.start.timeIntervalSince(now)
        return left > 0 && left <= meetingSoonLead
    }

    /// When the caption should appear for the countdown, if that is still ahead.
    static func meetingSoonBegins(_ countdown: NotchCalendarCountdown?, now: Date) -> Date? {
        guard let countdown, !countdown.ongoing else { return nil }
        let begins = countdown.event.start.addingTimeInterval(-meetingSoonLead)
        return begins > now ? begins : nil
    }

    /// The countdown's caption, in two halves that sit either side of the
    /// camera, under the title and under the clock: the wings are too narrow
    /// for it whole, and it reads straight across the camera.
    static func meetingSoonHalves(_ countdown: NotchCalendarCountdown?, now: Date,
                                  language: AppLanguage) -> (leading: String, trailing: String)? {
        guard showsCaptions(in: language), meetingSoon(countdown, now: now) else { return nil }
        return halves(meetingSoonCaption)
    }

    /// Split after the comma nearest the middle, else the space nearest it.
    static func halves(_ caption: String) -> (leading: String, trailing: String) {
        let characters = Array(caption)
        let middle = characters.count / 2
        let breaks = characters.indices.filter { characters[$0] == " " && $0 > 0 }
        let commas = breaks.filter { characters[$0 - 1] == "," }
        guard let cut = (commas.isEmpty ? breaks : commas).min(by: { abs($0 - middle) < abs($1 - middle) }) else {
            return (caption, "")
        }
        return (String(characters[..<cut]), String(characters[(cut + 1)...]))
    }

    /// Whether the event the island counted down to, as `before`, began as
    /// the countdown became `after` at `now`. Only just begun, so a Mac that
    /// slept through the start, or an event moved or removed before it, is
    /// no news. Kept here, apart from the companion's own reading of the
    /// same moment, so either can change without the other.
    static func meetingBegan(from before: NotchCalendarCountdown?, to after: NotchCalendarCountdown?,
                             at now: Date) -> Bool {
        guard let before, !before.ongoing else { return false }
        let since = now.timeIntervalSince(before.event.start)
        // Its refresh may come a second early.
        guard since >= -2, since < 60 else { return false }
        guard let after else { return true }
        return after.event.id != before.event.id || after.ongoing
    }

    static func meetingCue(_ event: NotchCalendarEvent, language: AppLanguage) -> NotchOfficeCue {
        let place = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return NotchOfficeCue(kind: .meeting, caption: showsCaptions(in: language) ? meetingCaption : nil,
                              accent: event.color, place: place.isEmpty ? nil : place)
    }

    /// The meeting's hours, as the island's other times are written.
    static func meetingHours(_ event: NotchCalendarEvent, locale: Locale) -> String {
        let style = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        return event.start.formatted(style) + "\u{2009}\u{2013}\u{2009}" + event.end.formatted(style)
    }

    // MARK: - Measures

    /// The caption beside a closed notice's title, and on the cards.
    static let stripCaptionFont = NSFont.monospacedSystemFont(ofSize: 7.5, weight: .medium)
    static let cardCaptionFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
    static let stripRule = (width: CGFloat(1.5), gap: CGFloat(3))
    static let cardRule = (width: CGFloat(2), gap: CGFloat(5))
    /// The mug beside a battery's percentage, and the air between them.
    static let mugSide: CGFloat = 18
    static let mugGap: CGFloat = 5
    /// A banner's sender side may reach this far for its role, a little past
    /// the plain banner's widest, since the role is what the moment is about.
    static let bannerWingLimit: CGFloat = 214
    /// The cards a call and a meeting starting open into, below the camera's
    /// row, as tall as the connect card.
    static let cardHeight: CGFloat = 112
    /// How long a card stays: long enough for three rings of a call.
    static let cardDuration: TimeInterval = 5

    /// A strip shorter than a title and a caption keeps just the title.
    static func stripFitsCaption(_ stripHeight: CGFloat) -> Bool { stripHeight >= 28 }

    static func captionWidth(_ caption: String, font: NSFont = stripCaptionFont, rule: Bool = true) -> CGFloat {
        guard !caption.isEmpty else { return 0 }
        let text = (caption as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        let marker = font === cardCaptionFont ? cardRule : stripRule
        return text + (rule ? marker.width + marker.gap : 0) + 1
    }

    static func captionHeight(_ font: NSFont = stripCaptionFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    /// The width a closed notice's title side needs for the caption under it.
    static func captionWidth(_ cue: NotchOfficeCue?) -> CGFloat {
        cue?.caption.map { captionWidth($0) } ?? 0
    }

    /// The extra width beside a closed notice's reading: the mug and its air.
    static func readingAccessoryWidth(_ cue: NotchOfficeCue?) -> CGFloat {
        cue?.showsMug == true ? mugSide + mugGap : 0
    }

    /// A banner's sides with the role or the call's caption under the sender.
    static func bannerWings(_ cue: NotchOfficeCue?, fitted: NotchNoticeWings) -> NotchNoticeWings {
        guard let caption = cue?.caption else { return fitted }
        let layout = NotchNotificationBannerLayout.self
        let side = layout.iconSize + layout.spacing + captionWidth(caption) + layout.inset + layout.air
        return NotchNoticeWings(leading: max(fitted.leading, min(bannerWingLimit, side)), trailing: fitted.trailing)
    }

    /// The held preview's extra height for the role under the sender's
    /// name, which a message without one leaves out.
    static func previewExtraHeight(_ cue: NotchOfficeCue?, title: String) -> CGFloat {
        cue?.kind == .message && cue?.caption != nil && !title.isEmpty ? 3 + captionHeight(cardCaptionFont) : 0
    }
}

private extension Array where Element == String {
    /// Whether `phrase`'s words appear here in order, side by side.
    func containsWords(_ phrase: String) -> Bool {
        let wanted = phrase.split(separator: " ").map(String.init)
        guard !wanted.isEmpty, wanted.count <= count else { return false }
        return (0...(count - wanted.count)).contains { Array(self[$0..<($0 + wanted.count)]) == wanted }
    }
}
