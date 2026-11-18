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

/// Where a volume reading sits, read from the percentage the notice shows:
/// silent, quiet, middling, loud, or all the way up.
enum NotchOfficeVolumeBand: Equatable, CaseIterable {
    case mute, low, mid, high, full
}

/// Where a brightness reading sits: only its two ends earn a caption.
enum NotchOfficeBrightnessBand: Equatable, CaseIterable {
    case dark, lit, full
}

/// The Office treatment one notice carries. It is attached where the notice
/// is raised, and only while the Office moments are on, so a notice without
/// one draws exactly as it always has.
struct NotchOfficeCue: Equatable {
    enum Kind: Equatable {
        case battery(NotchOfficeBattery)
        /// An agent's notice: its turn ending, a limit or the budget
        /// (NotchOfficeAgents.swift).
        case agent(NotchOfficeAgentBeat)
        case connect(NotchOfficeSpeaker)
        case message
        case call
        case meeting
        /// An event starting in five minutes, where no countdown strip
        /// carries the caption: a notice in the strip, never a card.
        case meetingSoon
        /// "Cafe Disco": the volume keys, with a boombox and a VU meter.
        case volume
        /// The display's brightness, with a window's blinds.
        case brightness
        /// Something copied: the copier scans and a sheet slides out.
        case copy
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
    /// The longest caption a level moment can show as its reading moves, so
    /// its side is as wide as it will ever need and holds still while a key
    /// is held. Nil where the app is not in English.
    var widestCaption: String?
    /// The copy a copy moment plays: which one this launch, and what it held.
    var copy: NotchOfficeCopy?

    /// A call and a meeting starting open the island into a card of their own.
    var opensCard: Bool { kind == .call || kind == .meeting }

    /// The volume and brightness moments, drawn in a level notice's layout.
    var isLevel: Bool { kind == .volume || kind == .brightness }

    /// The battery moments draw the mug beside the percentage.
    var showsMug: Bool {
        if case .battery = kind { return true }
        return false
    }

    /// The moments whose caption changes while they show, so their room is
    /// kept for the widest: volume through its bands, copies in turn.
    var holdsWidestCaption: Bool { kind == .volume || kind == .copy }
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
    /// Apps that only ring: every notification is a call unless it says
    /// the call is over.
    static let callApps = ["facetime", "phone"]
    /// Apps that also ring, whose notifications are a call only when their
    /// buttons answer one or their words say it is ringing. Mail, calendars
    /// and every other app never are, whatever their words.
    static let ringingApps = ["whatsapp", "telegram", "signal", "discord", "microsoft teams", "teams", "slack",
                              "skype", "messenger", "zoom", "webex", "wechat", "viber"]

    /// A ringing call, or a message from a messaging app; nil for everything
    /// else. Only an app that can ring is read for a call: one of `callApps`
    /// rings unless its words say the call was missed, declined, ended or
    /// went to voicemail; one of `ringingApps` rings when the original
    /// banner's own buttons answer it (`controls`, read by the notification
    /// reader) or its words say it is ringing. A call that is over keeps the
    /// plain banner.
    static func channel(for content: NotchNotificationContent, controls: [String] = []) -> NotchOfficeChannel? {
        let app = words(content.app)
        let messages = messageApps.contains { app.containsWords($0) }
        let dedicated = callApps.contains { app.containsWords($0) }
        guard dedicated || ringingApps.contains(where: { app.containsWords($0) }) else {
            return messages ? .message : nil
        }
        let fields = [content.title, content.subtitle, content.body].map(folded).filter { !$0.isEmpty }
        let labels = controls.map(folded)
        // Read across the fields: "FaceTime Video" over "Declined" is over.
        if saysCallIsOver(fields.joined(separator: " \u{00B7} ")) || labels.contains(where: callsBack) { return nil }
        if dedicated || labels.contains(where: answers) { return .call }
        let slack = app.containsWords("slack")
        if fields.contains(where: { saysRinging($0) || slack && saysHuddle($0) }) { return .call }
        return messages ? .message : nil
    }

    static func communicationCue(for content: NotchNotificationContent, controls: [String] = [],
                                 language: AppLanguage) -> NotchOfficeCue? {
        guard let channel = channel(for: content, controls: controls) else { return nil }
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

    /// A ringing line names the caller first, if anyone: the phrase opens
    /// the line or follows a name of a few words, however long the rest.
    /// A chat that only mentions a call further in ("so I told her Jane is
    /// calling you later") stays a message.
    private static func opens(_ field: String, with phrase: String) -> Bool {
        guard let range = field.range(of: phrase) else { return false }
        return words(String(field[..<range.lowerBound])).count <= 3
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Lowercased and without accents, so "Appel manqué" and "appel manque"
    /// read alike and the phrases below are written once.
    static func folded(_ text: String) -> String {
        normalized(text).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Words that name a call, in the languages the phrases below cover.
    private static let callWords = ["call", "facetime", "llamada", "appel", "anruf", "chiamata", "chamada", "ligacao",
                                    "oproep", "gesprek", "звонок", "вызов", "전화"]

    /// A call still ringing, in its own words. Any length, since some apps
    /// name the meeting or channel too; only apps that ring are read.
    private static func saysRinging(_ field: String) -> Bool {
        if field.hasPrefix("incoming"), field.contains("call") || field.contains("facetime") { return true }
        if opens(field, with: "is calling you") || field.hasSuffix(" is calling") || field.hasSuffix(" is calling\u{2026}")
            || field.hasSuffix(" is calling...") { return true }
        if field == "calling" || field.hasPrefix("calling\u{2026}") || field.hasPrefix("calling...") { return true }
        if opens(field, with: "wants to facetime") || opens(field, with: "would like to facetime") { return true }
        // Discord's ringing line names who started the call.
        if ["started a call", "started a voice call", "started a video call", "started a group call"]
            .contains(where: { opens(field, with: $0) }) { return true }
        // "Llamada entrante", "Appel vidéo entrant", "Eingehender Anruf"...
        // both words of the pair, in either order.
        let pairs = [("llamada", "entrante"), ("appel", "entrant"), ("anruf", "eingehend"), ("chiamata", "in arrivo"),
                     ("chamada", "recebida"), ("oproep", "inkomend"), ("gesprek", "inkomend"), ("звонок", "входящ"),
                     ("вызов", "входящ")]
        if pairs.contains(where: { field.contains($0.0) && field.contains($0.1) }) { return true }
        if ["te esta llamando", "vous appelle", "ruft dich an", "ruft sie an", "ti sta chiamando", "esta ligando",
            "belt je", "着信中", "来电", "전화 수신"].contains(where: { opens(field, with: $0) }) { return true }
        // A line that is only the label, as some apps title a ringing call;
        // "Video call later?" is a message.
        let label = field.trimmingCharacters(in: CharacterSet(charactersIn: ".!\u{2026} "))
        return ["voice call", "video call", "audio call", "group call", "facetime audio", "facetime video", "ringing",
                "llamada", "videollamada", "appel vocal", "appel video", "sprachanruf", "videoanruf",
                "chiamata vocale", "videochiamata", "chamada de voz", "chamada de video"].contains(label)
    }

    /// Slack rings for a huddle it invites the person to; "come to a
    /// huddle" from a colleague is a message.
    private static func saysHuddle(_ field: String) -> Bool {
        ["you to a huddle", "huddle invite", "huddle invitation"].contains(where: field.contains)
    }

    /// A call that is no longer ringing: missed, declined, unanswered, ended
    /// or gone to voicemail, in English and in the common localised forms.
    /// "I missed you" is still a message: the missing needs a call beside it.
    private static func saysCallIsOver(_ text: String) -> Bool {
        let over = ["voicemail", "call ended", "call failed", "buzon de voz", "messagerie vocale",
                    "segreteria telefonica", "correio de voz", "llamada finalizada", "appel termine", "anruf beendet",
                    "chiamata terminata", "chamada encerrada", "chamada terminada", "不在着信", "未接"]
        if over.contains(where: text.contains) { return true }
        guard callWords.contains(where: text.contains) else { return false }
        return ["missed", "declined", "no answer", "unanswered", "perdida", "rechazada", "manque", "refuse",
                "verpasst", "abgelehnt", "persa", "rifiutata", "recusada", "gemist", "geweigerd", "пропущен",
                "отклонен", "부재중"]
            .contains(where: text.contains)
    }

    /// A button that picks up or turns down a ringing call.
    static func answers(_ label: String) -> Bool {
        let parts = Set(words(label))
        return !parts.isDisjoint(with: ["accept", "answer", "decline", "join", "aceptar", "contestar", "rechazar",
                                        "accepter", "decrocher", "refuser", "annehmen", "ablehnen", "accetta",
                                        "rifiuta", "aceitar", "atender", "recusar", "aannemen", "weigeren",
                                        "принять", "отклонить"])
            || ["pick up", "応答", "拒否", "接听", "拒绝", "수락", "거절"].contains(where: label.contains)
    }

    /// A button that returns a call, which only a call that is over offers.
    private static func callsBack(_ label: String) -> Bool {
        ["call back", "callback", "return call", "rappeler", "devolver llamada", "zuruckrufen", "richiama",
         "retornar", "terugbellen"].contains(where: label.contains)
    }

    // MARK: - Calendar

    /// How long before an event it earns its caption.
    static let meetingSoonLead: TimeInterval = 5 * 60

    /// The meeting the Office moments follow: the next timed event starting
    /// within five minutes, read from the calendar's own events whenever
    /// the moments and the calendar are on. Not the countdown strip's: that
    /// is off by default, and it prefers an event under way to the one
    /// starting as it ends.
    static func meeting(in events: [NotchCalendarEvent], now: Date) -> NotchCalendarCountdown? {
        NotchCalendarSupport.countdown(events, now: now, starts: true, ends: false, leadTime: meetingSoonLead)
    }

    /// When `meeting(in:now:)` next changes: five minutes before a start,
    /// and the start.
    static func meetingTransition(in events: [NotchCalendarEvent], now: Date) -> Date? {
        NotchCalendarSupport.countdownTransition(events, now: now, starts: true, ends: false, leadTime: meetingSoonLead)
    }

    /// An event that has not begun, starting within five minutes.
    static func meetingSoon(_ meeting: NotchCalendarCountdown?, now: Date) -> Bool {
        guard let meeting, !meeting.ongoing else { return false }
        let left = meeting.event.start.timeIntervalSince(now)
        return left > 0 && left <= meetingSoonLead
    }

    /// The event whose five minutes just opened as the meeting followed went
    /// from `before` to `after`, which an island without a countdown strip
    /// announces with a notice. Only in the first minute of the five, so an
    /// event added just before it starts, or a Mac that wakes late, is no news.
    static func meetingSoonArrived(from before: NotchCalendarCountdown?, to after: NotchCalendarCountdown?,
                                   at now: Date) -> NotchCalendarEvent? {
        guard let after, meetingSoon(after, now: now), before?.event.id != after.event.id,
              after.event.start.timeIntervalSince(now) > meetingSoonLead - 60 else { return nil }
        return after.event
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

    /// The event that began as a countdown went from `before` to `after` at
    /// `now`, if one just did. Only just begun, so a Mac that slept through
    /// the start, or an event moved or removed before it, is no news. Kept
    /// here, apart from the companion's own reading of the same moment, so
    /// either can change without the other.
    static func meetingThatBegan(from before: NotchCalendarCountdown?, to after: NotchCalendarCountdown?,
                                 at now: Date) -> NotchCalendarEvent? {
        guard let before else { return nil }
        // Its refresh may come a second early.
        func justBegan(_ event: NotchCalendarEvent) -> Bool {
            let since = now.timeIntervalSince(event.start)
            return since >= -2 && since < 60
        }
        if !before.ongoing, justBegan(before.event), after?.event.id != before.event.id || after?.ongoing == true {
            return before.event
        }
        // Back to back: a countdown that follows ends prefers the event under
        // way when the next starts as it ends, so it moves from one under way
        // to the next under way, and the next is the one that began.
        if let after, after.ongoing, after.event.id != before.event.id, justBegan(after.event) { return after.event }
        return nil
    }

    static func meetingBegan(from before: NotchCalendarCountdown?, to after: NotchCalendarCountdown?,
                             at now: Date) -> Bool {
        meetingThatBegan(from: before, to: after, at: now) != nil
    }

    static func meetingCue(_ event: NotchCalendarEvent, language: AppLanguage) -> NotchOfficeCue {
        let place = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return NotchOfficeCue(kind: .meeting, caption: showsCaptions(in: language) ? meetingCaption : nil,
                              accent: event.color, place: place.isEmpty ? nil : place)
    }

    /// Five minutes out with no countdown strip to carry the caption: the
    /// event's own notice, its title with the caption under it.
    static func meetingSoonCue(_ event: NotchCalendarEvent, language: AppLanguage) -> NotchOfficeCue {
        NotchOfficeCue(kind: .meetingSoon, caption: showsCaptions(in: language) ? meetingSoonCaption : nil,
                       accent: event.color)
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
    /// The mug's box is taller than wide: room above the brim for the steam.
    static let mugHeight: CGFloat = 22
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

    /// Whether a banner's caption fits under the sender in a side `wing`
    /// wide, beside the app's icon `icon` across. A narrow side keeps the
    /// icon and the sender whole and leaves the caption out.
    static func bannerCaptionFits(_ caption: String, wing: CGFloat, inset: CGFloat, icon: CGFloat) -> Bool {
        icon + NotchNotificationBannerLayout.spacing + captionWidth(caption) + inset <= wing
    }

    /// The held preview's extra height for the role under the sender's
    /// name, which a message without one leaves out.
    static func previewExtraHeight(_ cue: NotchOfficeCue?, title: String) -> CGFloat {
        cue?.kind == .message && cue?.caption != nil && !title.isEmpty ? 3 + captionHeight(cardCaptionFont) : 0
    }
}

// MARK: - The capsule

/// A capsule's body is a single row, too short for a second line under the
/// title on a standard bar, so its Office caption reads after the real
/// information, beside its rule, and only where the capsule can grow to hold
/// it: the real information is never cut for the joke.
extension NotchOfficeMoments {
    /// The strip's caption size in a standard bar, the card's in a capsule
    /// in a taller bar.
    static func capsuleCaptionFont(_ geometry: NotchGeometry) -> NSFont {
        geometry.stripBodyHeight >= 28 ? cardCaptionFont : stripCaptionFont
    }

    /// The mug, no taller than the capsule's body leaves.
    static func capsuleMugScale(_ geometry: NotchGeometry) -> CGFloat {
        min(1, max(0, geometry.stripBodyHeight - 2) / mugHeight)
    }

    /// The mug and its air before a battery's reading.
    static func capsuleMugWidth(_ cue: NotchOfficeCue?, geometry: NotchGeometry) -> CGFloat {
        cue?.showsMug == true ? (mugSide * capsuleMugScale(geometry)).rounded(.up) + NotchCapsuleLayout.spacing : 0
    }

    /// The caption a capsule notice shows after a row `content` wide, mug
    /// included, or nil where the row with it would pass `maximum` or the
    /// room the menu bar leaves. A level's caption changes with its band, so
    /// it is measured at its widest: every step of a held key agrees on
    /// whether it shows. So is a copy's, which changes with each copy.
    static func capsuleCaption(_ cue: NotchOfficeCue?, content: CGFloat, maximum: CGFloat,
                               geometry: NotchGeometry) -> String? {
        guard let cue, let caption = cue.caption else { return nil }
        let measured = cue.isLevel || cue.kind == .copy ? cue.widestCaption ?? caption : caption
        let layout = NotchCapsuleLayout.self
        let side = layout.side(geometry)
        let wanted = content + layout.groupSpacing + captionWidth(measured, font: capsuleCaptionFont(geometry))
        let limit = min(maximum + side * 2, layout.availableWidth(geometry)).rounded(.down)
        return wanted + layout.endPadding * 2 + side * 2 <= limit ? caption : nil
    }

    /// The caption whose room a capsule keeps after its row. Volume keeps its
    /// widest: a held key passes through every band, and the capsule holds
    /// still through them all. Brightness has words only at its two ends,
    /// which a held key reaches once and stays at, so through the middle of
    /// the range its capsule keeps the bare row rather than an empty slot.
    /// A copy's caption changes with each copy, so it keeps its widest too.
    static func capsuleCaptionSlot(_ cue: NotchOfficeCue, caption: String) -> String {
        cue.holdsWidestCaption ? cue.widestCaption ?? caption : caption
    }

    /// A capsule notice's row: `base` as it always measured, then the mug
    /// and the caption where they show.
    static func capsuleContent(_ cue: NotchOfficeCue?, base: CGFloat, maximum: CGFloat,
                               geometry: NotchGeometry) -> CGFloat {
        let content = base + capsuleMugWidth(cue, geometry: geometry)
        guard let cue, let caption = capsuleCaption(cue, content: content, maximum: maximum, geometry: geometry) else {
            return content
        }
        return content + NotchCapsuleLayout.groupSpacing
            + captionWidth(capsuleCaptionSlot(cue, caption: caption), font: capsuleCaptionFont(geometry))
    }

    // MARK: A level in the capsule

    /// The tallest a level moment's mark and meter stand in a capsule: its
    /// body less two points above and below.
    static func capsuleLevelHeight(_ geometry: NotchGeometry) -> CGFloat { max(0, geometry.stripBodyHeight - 4) }

    /// The boombox or the blinds, no taller than the capsule leaves them.
    static func capsuleMarkScale(_ cue: NotchOfficeCue, geometry: NotchGeometry) -> CGFloat {
        min(1, capsuleLevelHeight(geometry) / (cue.kind == .volume ? miniBoombox.height : blindsSide))
    }

    static func capsuleMarkWidth(_ cue: NotchOfficeCue, geometry: NotchGeometry) -> CGFloat {
        (levelMarkWidth(cue) * capsuleMarkScale(cue, geometry: geometry)).rounded(.up)
    }

    /// The VU meter's segments, no taller than the capsule leaves them. Its
    /// bars keep their width, so it reads as the strip's.
    static func capsuleMeterScale(_ geometry: NotchGeometry) -> CGFloat {
        min(1, capsuleLevelHeight(geometry) / vuHeights.highest)
    }

    /// The VU meter for the volume; brightness's daylight meter at the plain meter's length.
    static func capsuleMeterWidth(_ cue: NotchOfficeCue) -> CGFloat {
        cue.kind == .volume ? vuWidth : NotchCapsuleLayout.meterWidth
    }

    /// The reading, as large as the capsule's other readings, with the room
    /// of its widest value so the meter never moves.
    static func capsuleReadingWidth(_ reading: String) -> CGFloat {
        let layout = NotchCapsuleLayout.self
        return max(layout.width(reading, font: layout.readingFont), layout.width("100%", font: layout.readingFont))
    }

    /// A capsule notice's row before its mug and caption: as the capsule has
    /// always measured it, a level moment's mark, meter and reading, or a
    /// copy's copier, title and kind.
    static func capsuleRow(_ cue: NotchOfficeCue?, title: String, detail: String, level: Bool,
                           geometry: NotchGeometry) -> CGFloat {
        let layout = NotchCapsuleLayout.self
        if let cue, cue.kind == .copy, !level { return capsuleCopyRow(cue, title: title, detail: detail, geometry: geometry) }
        if !level, cue?.agentBeat != nil { return capsuleAgentRow(title: title, detail: detail, geometry: geometry) }
        guard level, let cue, cue.isLevel else { return layout.noticeContent(title: title, detail: detail, level: level) }
        return capsuleMarkWidth(cue, geometry: geometry) + layout.spacing + capsuleMeterWidth(cue) + layout.spacing
            + capsuleReadingWidth(detail)
    }
}

// MARK: - Volume and brightness

/// "Cafe Disco": the volume keys play a mini boombox whose cones swell with
/// the level and kick with each press, a nine-segment VU meter in the song's
/// colours with two beet segments at the top, and a caption for each band.
/// Brightness opens a window's blinds and earns a caption only at its ends.
/// The caption changes only when the band does, and the sides are sized for
/// the widest caption, so a held key moves neither.
extension NotchOfficeMoments {
    /// The whole percentage a level notice shows, as its reading is written.
    static func percent(_ level: Double) -> Int {
        guard level.isFinite else { return 0 }
        return Int((min(1, max(0, level)) * 100).rounded())
    }

    // MARK: Bands and captions

    static func volumeBand(percent: Int) -> NotchOfficeVolumeBand {
        switch percent {
        case ...0: return .mute
        case 1...33: return .low
        case 34...66: return .mid
        case 67...99: return .high
        default: return .full
        }
    }

    static func caption(for band: NotchOfficeVolumeBand) -> String {
        switch band {
        case .mute: return "Jinx."
        case .low: return "Inside voices."
        case .mid: return "Threat level: mid-tempo."
        case .high: return "Corporate can hear this."
        case .full: return "That's what she synced."
        }
    }

    static func brightnessBand(percent: Int) -> NotchOfficeBrightnessBand {
        percent <= 10 ? .dark : percent >= 100 ? .full : .lit
    }

    static func caption(for band: NotchOfficeBrightnessBand) -> String? {
        switch band {
        case .dark: return "Lights out. Go home."
        case .lit: return nil
        case .full: return "Fluorescent. As intended."
        }
    }

    /// The caption that takes the most room, which a level's side is sized for.
    static func widest(_ captions: [String]) -> String? {
        captions.max { captionWidth($0) < captionWidth($1) }
    }

    /// `level` is what the notice shows, 0 to 1, a muted output reading 0.
    static func volumeCue(level: Double, language: AppLanguage) -> NotchOfficeCue {
        let captions = showsCaptions(in: language)
        return NotchOfficeCue(kind: .volume,
                              caption: captions ? caption(for: volumeBand(percent: percent(level))) : nil,
                              level: min(1, max(0, level.isFinite ? level : 0)),
                              widestCaption: captions ? widest(NotchOfficeVolumeBand.allCases.map(caption(for:))) : nil)
    }

    static func brightnessCue(level: Double, language: AppLanguage) -> NotchOfficeCue {
        let captions = showsCaptions(in: language)
        return NotchOfficeCue(kind: .brightness,
                              caption: captions ? caption(for: brightnessBand(percent: percent(level))) : nil,
                              level: min(1, max(0, level.isFinite ? level : 0)),
                              widestCaption: captions ? widest(NotchOfficeBrightnessBand.allCases.compactMap(caption(for:)))
                                  : nil)
    }

    // MARK: The boombox's cones

    /// The cones at silence and all the way up; each press kicks them 12%.
    static let coneRange = (rest: CGFloat(1), loud: CGFloat(1.35))
    static let coneKick: CGFloat = 1.12
    /// One kick, out and back. A held key's steps arriving inside it are
    /// absorbed, so the cones pump in time instead of restarting each step.
    static let coneKickDuration: TimeInterval = 0.22

    static func coneScale(_ level: Double) -> CGFloat {
        let level = level.isFinite ? CGFloat(min(1, max(0, level))) : 0
        return coneRange.rest + (coneRange.loud - coneRange.rest) * level
    }

    /// Whether a step at `now` kicks the cones, given when they last kicked:
    /// only once the last kick has played out.
    static func coneKicks(at now: TimeInterval, lastKick: TimeInterval?) -> Bool {
        guard let lastKick else { return true }
        return now - lastKick >= coneKickDuration || now < lastKick
    }

    // MARK: The VU meter

    static let vuSegments = 9
    /// The top segments, lit in beet, whatever the song.
    static let vuHotSegments = 2
    static let vuBar: CGFloat = 3
    static let vuGap: CGFloat = 2
    static let vuHeights = (lowest: CGFloat(6), highest: CGFloat(18))
    static let vuHot = NSColor(srgbRed: 0xC0 / 255, green: 0x39 / 255, blue: 0x2B / 255, alpha: 1)

    static var vuWidth: CGFloat { CGFloat(vuSegments) * vuBar + CGFloat(vuSegments - 1) * vuGap }

    /// Each segment a step taller than the last, from the lowest to the highest.
    static func vuHeight(_ segment: Int) -> CGFloat {
        let step = (vuHeights.highest - vuHeights.lowest) / CGFloat(vuSegments - 1)
        return vuHeights.lowest + step * CGFloat(min(vuSegments - 1, max(0, segment)))
    }

    /// How many segments a level lights: any sound lights the first, and only
    /// the top ninth lights them all. Read from the percentage the notice
    /// shows, as the band is, so a level that reads 0% is silent everywhere.
    static func vuLit(_ level: Double) -> Int {
        let percent = percent(level)
        guard percent > 0 else { return 0 }
        return min(vuSegments, (percent * vuSegments + 99) / 100)
    }

    static func vuIsHot(_ segment: Int) -> Bool { segment >= vuSegments - vuHotSegments }

    /// The segments' colours, low to high: the moment's palette spread across
    /// the cool ones in its own order, then beet for the hot ones.
    static func vuColors(_ palette: [NSColor]) -> [NSColor] {
        let marks = palette.compactMap { $0.usingColorSpace(.sRGB) }
        let cool = vuSegments - vuHotSegments
        return (0..<vuSegments).map { segment in
            guard !vuIsHot(segment) else { return vuHot }
            guard let first = marks.first else { return .white }
            guard marks.count > 1, cool > 1 else { return first }
            let position = Double(segment) / Double(cool - 1) * Double(marks.count - 1)
            let lower = min(marks.count - 2, Int(position))
            let fraction = CGFloat(position - Double(lower))
            let (from, to) = (marks[lower], marks[lower + 1])
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * fraction }
            return NSColor(srgbRed: mix(from.redComponent, to.redComponent),
                           green: mix(from.greenComponent, to.greenComponent),
                           blue: mix(from.blueComponent, to.blueComponent),
                           alpha: mix(from.alphaComponent, to.alphaComponent))
        }
    }

    // MARK: Measures

    /// The boombox beside the volume reading: the connect card's, scaled.
    static let miniBoombox = CGSize(width: 22, height: 13)
    /// The window beside the brightness reading.
    static let blindsSide: CGFloat = 18
    /// The reading, large: the real information comes first.
    static let levelReadingFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    static let levelMarkGap: CGFloat = 7
    /// Air between a level moment's content and the camera.
    static let levelAir: CGFloat = 8

    static func levelMarkWidth(_ cue: NotchOfficeCue) -> CGFloat {
        cue.kind == .volume ? miniBoombox.width : blindsSide
    }

    static func levelReadingWidth(_ reading: String = "100%") -> CGFloat {
        ceil((reading as NSString).size(withAttributes: [.font: levelReadingFont]).width)
    }

    /// Whether a level moment's caption reads under its reading, beside the
    /// mark. Volume's does: it has one in every band. Brightness's only
    /// comes at the ends, so it reads under the meter, and the reading's
    /// side stays as narrow as the reading through the middle of the range.
    static func captionUnderReading(_ cue: NotchOfficeCue) -> Bool { cue.kind == .volume }

    /// A level moment's sides beside the camera, never narrower than the
    /// plain notice's `plain`: the mark and the widest reading on one, the
    /// VU meter or the plain meter on the other, and the widest caption on
    /// the side it reads on. `inset` is the room kept inside the island's
    /// curved ends.
    static func levelWings(_ cue: NotchOfficeCue, plain: NotchNoticeWings, inset: CGFloat) -> NotchNoticeWings {
        guard cue.isLevel else { return plain }
        let caption = cue.widestCaption.map { captionWidth($0) } ?? 0
        let under = captionUnderReading(cue)
        let leading = ceil(inset + levelMarkWidth(cue) + levelMarkGap + max(levelReadingWidth(), under ? caption : 0)
                           + levelAir)
        let meter = cue.kind == .volume ? vuWidth : 0
        let trailing = ceil(inset + max(meter, under ? 0 : caption) + levelAir)
        return NotchNoticeWings(leading: max(plain.leading, leading), trailing: max(plain.trailing, trailing))
    }

    // MARK: In the open island

    /// Between the open island's level reading's pieces, as its plain row spaces them.
    static let expandedSpacing: CGFloat = 8
    /// The daylight meter's least length beside a caption; it reaches the
    /// plain row's 96 points where the side has them.
    static let expandedMeterMinimum: CGFloat = 40

    /// The reading's column in the open island's row: the widest reading,
    /// and the widest caption under it where one reads. It holds that width
    /// through every band, so the meter never moves as the words change.
    static func expandedReadingColumn(_ cue: NotchOfficeCue, caption: Bool) -> CGFloat {
        max(levelReadingWidth(), caption ? cue.widestCaption.map { captionWidth($0) } ?? 0 : 0)
    }

    /// Whether the open island's row `width` wide holds the band's caption
    /// under the reading, beside the mark and the meter. Measured at the
    /// widest caption, so every band of a held key agrees; a side too
    /// narrow drops it whole and keeps the reading.
    static func expandedCaptionFits(_ cue: NotchOfficeCue, width: CGFloat?) -> Bool {
        guard cue.isLevel, cue.widestCaption != nil, let width else { return false }
        let meter = cue.kind == .volume ? vuWidth : expandedMeterMinimum
        return levelMarkWidth(cue) + expandedSpacing + meter + expandedSpacing
            + expandedReadingColumn(cue, caption: true) <= width
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
