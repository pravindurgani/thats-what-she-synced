// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// The Office moments' rules: the switch, which notices become which moment,
/// the captions and their language, and the room they take on the island.
enum NotchOfficeMomentsTests {
    static func run(_ suite: TestSuite) {
        switchContracts(suite)
        batteryContracts(suite)
        connectContracts(suite)
        channelContracts(suite)
        falsePositiveContracts(suite)
        controlContracts(suite)
        roleContracts(suite)
        calendarContracts(suite)
        backToBackContracts(suite)
        captionContracts(suite)
        measureContracts(suite)
        capsuleContracts(suite)
        volumeContracts(suite)
        brightnessContracts(suite)
        meterContracts(suite)
        levelMeasureContracts(suite)
        expandedLevelContracts(suite)
        NotchOfficeCopierTests.run(suite)
    }

    private static func content(_ app: String, _ title: String = "Jane", subtitle: String = "",
                                _ body: String = "") -> NotchNotificationContent {
        NotchNotificationContent(app: app, title: title, subtitle: subtitle, body: body)
    }

    /// On by default, off when turned off, and the meeting notice routes only while it is on.
    private static func switchContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-office"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(NotchOfficeMoments.isEnabled(in: defaults), "the Office moments are on when nothing was chosen")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchOfficeModeEnabled] as? Bool == true,
                     "the switch is registered on, beside the island's other notice switches")
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchCalendarEnabled)
        suite.expect(NotchSupport.routes(.calendar, in: defaults), "a meeting starting is announced with the moments on")
        defaults.set(false, forKey: DefaultsKey.notchOfficeModeEnabled)
        suite.expect(!NotchOfficeMoments.isEnabled(in: defaults) && !NotchSupport.routes(.calendar, in: defaults),
                     "switched off, no meeting notice exists, as upstream has none")
        defaults.set(true, forKey: DefaultsKey.notchOfficeModeEnabled)
        defaults.set(false, forKey: DefaultsKey.notchCalendarEnabled)
        suite.expect(!NotchSupport.routes(.calendar, in: defaults), "a meeting notice needs the calendar on")
        suite.expect(NotchEvent.calendar.priority == NotchEvent.timer.priority
                     && NotchEvent.calendar.priority > NotchEvent.systemNotification.priority
                     && NotchEvent.calendar.duration == NotchOfficeMoments.cardDuration,
                     "a meeting starting outranks a message and stays as long as its card")
    }

    private static func batteryContracts(_ suite: TestSuite) {
        typealias Moments = NotchOfficeMoments
        suite.expect(Moments.battery(low: true, externalConnected: true, charging: true, percent: 20) == .low
                     && Moments.battery(low: true, externalConnected: false, charging: false, percent: 19) == .low,
                     "a low charge is the news, plugged in or not")
        suite.expect(Moments.battery(low: false, externalConnected: false, charging: false, percent: 80) == .onBattery,
                     "unplugged reads as back on battery")
        suite.expect(Moments.battery(low: false, externalConnected: true, charging: true, percent: 64) == .charging,
                     "an adapter that charges reads as charging")
        suite.expect(Moments.battery(low: false, externalConnected: true, charging: false, percent: 100) == .charged,
                     "a full battery on the adapter reads as charged")
        suite.expect(Moments.battery(low: false, externalConnected: true, charging: false, percent: 80) == .pluggedIn
                     && Moments.battery(low: false, externalConnected: true, charging: false, percent: nil) == .pluggedIn,
                     "an adapter that holds the charge reads as plugged in")
        let captions: [NotchOfficeBattery: String] = [
            .pluggedIn: "Coffee's on.", .charging: "Refilling the mug.", .charged: "World's Best Battery.",
            .onBattery: "Back to the field.", .low: "I DECLARE\u{2026} BANKRUPTCY!",
        ]
        suite.expect(captions.allSatisfy { Moments.caption(for: $0.key) == $0.value }, "each charge reading has its caption")
        let cue = Moments.batteryCue(.charging, percent: 64, language: .enUS)
        suite.expect(cue.kind == .battery(.charging) && cue.caption == "Refilling the mug." && cue.showsMug
                     && abs((cue.level ?? 0) - 0.64) < 0.0001 && !cue.opensCard,
                     "the mug fills to the charge, in the strip")
        suite.expect(Moments.batteryCue(.charged, percent: 140, language: .enUS).level == 1
                     && Moments.batteryCue(.low, percent: -5, language: .enUS).level == 0
                     && Moments.batteryCue(.onBattery, percent: nil, language: .enUS).level == nil,
                     "the mug never fills past its brim or below its base")
    }

    private static func connectContracts(_ suite: TestSuite) {
        for symbol in ["airpods", "airpodspro", "airpodsmax", "headphones", "beats.headphones", "earbuds"] {
            suite.expect(NotchOfficeMoments.speaker(forSymbol: symbol) == .earphones, "\(symbol) is worn")
        }
        for symbol in ["hifispeaker", "homepod", "speaker.wave.2", "airplayaudio"] {
            suite.expect(NotchOfficeMoments.speaker(forSymbol: symbol) == .speaker, "\(symbol) fills a room")
        }
        suite.expect(NotchOfficeMoments.connectCue(symbol: "airpodspro", language: .enUS).caption == "Cafe Disco is open."
                     && NotchOfficeMoments.connectCue(symbol: "hifispeaker", language: .enUS).caption == "Everybody, dance.",
                     "earphones open the cafe; a speaker gets everybody dancing")
    }

    private static func channelContracts(_ suite: TestSuite) {
        func channel(_ content: NotchNotificationContent) -> NotchOfficeChannel? { NotchOfficeMoments.channel(for: content) }
        suite.expect(channel(content("FaceTime", "Jane", "FaceTime Video")) == .call
                     && channel(content("Phone", "Jane", "Incoming Call")) == .call,
                     "FaceTime and Phone ring as calls")
        suite.expect(channel(content("FaceTime", "Missed FaceTime Video", "Jane")) == nil
                     && channel(content("WhatsApp", "Jane", "Missed voice call")) == nil
                     && channel(content("Phone", "Jane", "Voicemail (0:32)")) == nil,
                     "a call that is no longer ringing keeps the plain banner")
        suite.expect(channel(content("WhatsApp", "Jane", "Incoming voice call")) == .call
                     && channel(content("Signal", "Jane", "Incoming video call")) == .call
                     && channel(content("Microsoft Teams (work or school)", "Jane is calling you")) == .call
                     && channel(content("Telegram", "Jane", "Incoming Call")) == .call
                     && channel(content("Slack", "Jane", "Jane invited you to a huddle")) == .call
                     && channel(content("Discord", "Jane", "Ringing\u{2026}")) == .call,
                     "a messaging app's ringing call is a call")
        suite.expect(channel(content("zoom.us", "Incoming call from Jane")) == .call,
                     "an app that rings and says so is a call")
        suite.expect(channel(content("WhatsApp", "Jane", "Llamada entrante")) == .call
                     && channel(content("WhatsApp", "Jane", "Appel vidéo entrant")) == .call
                     && channel(content("Telegram", "Jane", "Eingehender Anruf")) == .call
                     && channel(content("Discord", "Jane started a call")) == .call
                     && channel(content("Microsoft Teams", "Jane Levinson is calling you from Weekly Sales Sync "
                                        + "(Scranton branch, all hands)")) == .call,
                     "a ringing call reads in other languages, in Discord's words and at any length")
        for app in ["Messages", "WHATSAPP", "whatsapp", "Telegram Desktop", "Signal", "Slack", "Discord PTB",
                    "Microsoft Teams", "Microsoft Teams (work or school)", "Messenger"] {
            suite.expect(channel(content(app, "Jane", "See you at four")) == .message, "\(app) is a message, in any case")
        }
        suite.expect(channel(content("Messages", "Jane", "Video call later?")) == .message
                     && channel(content("Messages", "Jane", "I missed you")) == .message
                     && channel(content("Messages", "Jane",
                                        "Long story short, the incoming call I mentioned is now at four")) == .message,
                     "a message that only mentions a call stays a message")
        suite.expect(channel(content("Mail", "Jane", "Quarterly numbers")) == nil
                     && channel(content("iPhone Mirroring", "Jane", "Hello")) == nil
                     && channel(content("Calendar", "Standup", "In 5 minutes")) == nil,
                     "other apps keep their plain banner; iPhone Mirroring is not the Phone app")
        let call = NotchOfficeMoments.communicationCue(for: content("FaceTime", "Jane", "FaceTime Video"), language: .enUS)
        suite.expect(call?.kind == .call && call?.caption == "Conference room. Now." && call?.opensCard == true,
                     "a call rings in its own card with the conference room's caption")
        let message = NotchOfficeMoments.communicationCue(for: content("Messages", "Jane", "Hi"), language: .enUS)
        suite.expect(message?.kind == .message && message.map { NotchOfficeMoments.roles.contains($0.caption ?? "") } == true
                     && message?.opensCard == false,
                     "a message stays a banner and its sender gets a role")
    }

    /// Only an app that can ring is read for a call; a message that only
    /// mentions one stays what it is.
    private static func falsePositiveContracts(_ suite: TestSuite) {
        func channel(_ content: NotchNotificationContent) -> NotchOfficeChannel? { NotchOfficeMoments.channel(for: content) }
        suite.expect(channel(content("Mail", "Program Committee", subtitle: "Incoming call for papers",
                                     "Submissions close Friday")) == nil,
                     "a mail about an incoming call for papers is not a call")
        suite.expect(channel(content("Messages", "Jane", "mom is calling")) == .message
                     && channel(content("Messages", "Mom is calling")) == .message,
                     "a text saying someone is calling is a message: Messages does not ring")
        suite.expect(channel(content("Slack", "Jane", "come to a huddle")) == .message
                     && channel(content("Slack", "Jane", "Jane is inviting you to a huddle")) == .call
                     && channel(content("Discord", "Jane", "Jane invited you to a huddle")) == .message,
                     "only Slack's own invitation to a huddle rings, and only in Slack")
        suite.expect(channel(content("WhatsApp", "Jane", "so I told her that Jane is calling you later")) == .message
                     && channel(content("Discord", "Jane", "so yesterday the two of us finally started a call about it")) == .message
                     && channel(content("WhatsApp", "Jane Levinson Gould is calling you")) == .call,
                     "a chat that mentions a call further in is a message; a caller's name may come first")
        suite.expect(channel(content("Calendar", "Incoming call with the board", "In 5 minutes")) == nil
                     && channel(content("Mail", "Jane is calling you")) == nil
                     && channel(content("", "Jane", "Incoming FaceTime Audio")) == nil,
                     "mail, calendars and an unnamed app are never read for a call")
        for (title, body) in [("Llamada perdida de FaceTime", "Jane"), ("Appel FaceTime manqué", "Jane"),
                              ("Verpasster FaceTime-Anruf", "Jane"), ("Chiamata FaceTime persa", "Jane"),
                              ("Chamada perdida do FaceTime", "Jane"), ("Jane", "Buzón de voz (0:12)"),
                              ("Jane", "Call Ended"), ("FaceTime Video", "Declined"), ("不在着信", "Jane")] {
            suite.expect(channel(content("FaceTime", title, body)) == nil,
                         "\(title) / \(body) is a call that is over, in its own language")
        }
        suite.expect(channel(content("FaceTime", "Jane", "FaceTime Video")) == .call
                     && channel(content("WhatsApp", "Jane", "I missed you")) == .message
                     && channel(content("WhatsApp", "Jane", "Llamada perdida")) == nil,
                     "missing someone is a message; a missed call keeps its plain banner")
    }

    /// The original banner's own buttons, read by the notification reader,
    /// say a call is ringing in any words.
    private static func controlContracts(_ suite: TestSuite) {
        func channel(_ content: NotchNotificationContent, _ controls: [String]) -> NotchOfficeChannel? {
            NotchOfficeMoments.channel(for: content, controls: controls)
        }
        suite.expect(channel(content("WhatsApp", "Jane", "Jane"), ["Accept", "Decline"]) == .call
                     && channel(content("Signal", "Jane", "Signal"), ["Rechazar", "Aceptar"]) == .call
                     && channel(content("Slack", "Jane", "Huddle in #sales"), ["Join", "Decline"]) == .call,
                     "a call app's banner that offers to answer is ringing")
        suite.expect(channel(content("FaceTime", "Jane", "FaceTime"), ["Call Back", "Message"]) == nil
                     && channel(content("Phone", "Jane", "Mobile"), ["Rappeler"]) == nil,
                     "a banner that offers to call back is a call that is over")
        suite.expect(channel(content("Telegram", "Jane", "See you"), ["Reply", "Mark as Read"]) == .message
                     && channel(content("Mail", "Jane", "Lunch?"), ["Accept"]) == nil
                     && channel(content("Messages", "Jane", "Hi"), ["Accept"]) == .message,
                     "buttons only say a call where the app can ring")
        let cue = NotchOfficeMoments.communicationCue(for: content("WhatsApp", "Jane", "Jane"),
                                                      controls: ["Answer"], language: .enUS)
        suite.expect(cue?.kind == .call && cue?.opensCard == true, "an answerable banner opens the call card")
    }

    private static func roleContracts(_ suite: TestSuite) {
        suite.expect(NotchOfficeMoments.stableHash("") == 0xcbf2_9ce4_8422_2325
                     && NotchOfficeMoments.stableHash("a") == 0xaf63_dc4c_8601_ec8c
                     && NotchOfficeMoments.stableHash("foobar") == 0x8594_4171_f739_67e8,
                     "the role's hash is FNV-1a, the same on every launch")
        let role = NotchOfficeMoments.role(forSender: "Jane Levinson")
        suite.expect((0..<5).allSatisfy { _ in NotchOfficeMoments.role(forSender: "Jane Levinson") == role }
                     && NotchOfficeMoments.role(forSender: "  JANE   levinson ") == role,
                     "a sender keeps one role, whatever the case or spacing of their name")
        let senders = (0..<60).map { "Sender \($0)" }
        suite.expect(Set(senders.map(NotchOfficeMoments.role(forSender:))) == Set(NotchOfficeMoments.roles),
                     "every role is handed out across senders")
    }

    private static func calendarContracts(_ suite: TestSuite) {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = NotchCalendarEvent(id: "standup", title: "Standup", calendar: "Work", start: start,
                                       end: start.addingTimeInterval(1800), allDay: false, location: "  Room 4B ")
        let upcoming = NotchCalendarCountdown(event: event, ongoing: false)
        let ongoing = NotchCalendarCountdown(event: event, ongoing: true)
        suite.expect(NotchOfficeMoments.meetingSoon(upcoming, now: start.addingTimeInterval(-299))
                     && NotchOfficeMoments.meetingSoon(upcoming, now: start.addingTimeInterval(-300))
                     && !NotchOfficeMoments.meetingSoon(upcoming, now: start.addingTimeInterval(-301))
                     && !NotchOfficeMoments.meetingSoon(upcoming, now: start)
                     && !NotchOfficeMoments.meetingSoon(ongoing, now: start.addingTimeInterval(-60))
                     && !NotchOfficeMoments.meetingSoon(nil, now: start),
                     "the countdown earns its caption in the last five minutes before a start")
        suite.expect(NotchOfficeMoments.meeting(in: [event], now: start.addingTimeInterval(-3600)) == nil
                     && NotchOfficeMoments.meeting(in: [event], now: start.addingTimeInterval(-300)) == upcoming
                     && NotchOfficeMoments.meeting(in: [event], now: start) == nil,
                     "the moments follow an event from the calendar itself, in its five minutes, strip or not")
        suite.expect(NotchOfficeMoments.meetingTransition(in: [event], now: start.addingTimeInterval(-3600))
                        == start.addingTimeInterval(-300)
                     && NotchOfficeMoments.meetingTransition(in: [event], now: start.addingTimeInterval(-60)) == start,
                     "the calendar is read again as the five minutes open and as the event starts")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchCalendarCountdown] as? Bool == false
                     && NotchOfficeMoments.meeting(in: [event], now: start.addingTimeInterval(-120)) != nil,
                     "with the countdown strip off by default, the moments still have their meeting")
        let allDay = NotchCalendarEvent(id: "holiday", title: "Holiday", calendar: "Home", start: start,
                                        end: start.addingTimeInterval(86_400), allDay: true, location: "")
        suite.expect(NotchOfficeMoments.meeting(in: [allDay], now: start.addingTimeInterval(-60)) == nil,
                     "an all-day event never calls anyone to the conference room")
        suite.expect(NotchOfficeMoments.meetingSoonArrived(from: nil, to: upcoming, at: start.addingTimeInterval(-299))
                        == event
                     && NotchOfficeMoments.meetingSoonArrived(from: upcoming, to: upcoming,
                                                              at: start.addingTimeInterval(-290)) == nil
                     && NotchOfficeMoments.meetingSoonArrived(from: nil, to: upcoming,
                                                              at: start.addingTimeInterval(-200)) == nil
                     && NotchOfficeMoments.meetingSoonArrived(from: upcoming, to: nil, at: start) == nil,
                     "a strip-less island says five minutes once, as they open, and never late")
        let halves = NotchOfficeMoments.meetingSoonHalves(upcoming, now: start.addingTimeInterval(-120), language: .enUS)
        suite.expect(halves?.leading == "Conference room," && halves?.trailing == "five minutes.",
                     "the caption splits at its comma, either side of the camera")
        suite.expect(NotchOfficeMoments.meetingSoonHalves(upcoming, now: start.addingTimeInterval(-120), language: .de) == nil,
                     "only English gets the caption")
        let split = NotchOfficeMoments.halves("Head of Sending")
        suite.expect(split.leading + " " + split.trailing == "Head of Sending" && NotchOfficeMoments.halves("Solo").trailing.isEmpty,
                     "a caption without a comma splits at the space nearest its middle, and one word stays whole")
        suite.expect(NotchOfficeMoments.meetingBegan(from: upcoming, to: ongoing, at: start.addingTimeInterval(1))
                     && NotchOfficeMoments.meetingBegan(from: upcoming, to: nil, at: start)
                     && !NotchOfficeMoments.meetingBegan(from: upcoming, to: ongoing, at: start.addingTimeInterval(90))
                     && !NotchOfficeMoments.meetingBegan(from: upcoming, to: upcoming, at: start.addingTimeInterval(-30))
                     && !NotchOfficeMoments.meetingBegan(from: ongoing, to: nil, at: start.addingTimeInterval(1800))
                     && !NotchOfficeMoments.meetingBegan(from: nil, to: ongoing, at: start),
                     "only an event that just began opens the meeting card")
        let cue = NotchOfficeMoments.meetingCue(event, language: .enUS)
        suite.expect(cue.kind == .meeting && cue.caption == "Conference room. Now." && cue.place == "Room 4B"
                     && cue.accent == event.color && cue.opensCard,
                     "the meeting card names the room and wears the calendar's colour")
        let bare = NotchCalendarEvent(id: event.id, title: event.title, calendar: event.calendar, start: event.start,
                                      end: event.end, allDay: false, location: " ")
        suite.expect(NotchOfficeMoments.meetingCue(bare, language: .enUS).place == nil, "no room, no room line")
        let hours = NotchOfficeMoments.meetingHours(event, locale: Locale(identifier: "en_GB"))
        suite.expect(hours.contains("\u{2013}") && hours.split(separator: "\u{2013}").count == 2,
                     "the hours read start to end")
    }

    /// One meeting ending as the next begins: the next is announced, and its
    /// five minutes are told while the first is still under way.
    private static func backToBackContracts(_ suite: TestSuite) {
        let nine = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let first = NotchCalendarEvent(id: "a", title: "Sales call", calendar: "Work", start: nine,
                                       end: nine.addingTimeInterval(3600), allDay: false, location: "")
        let second = NotchCalendarEvent(id: "b", title: "Conference room", calendar: "Work",
                                        start: first.end, end: first.end.addingTimeInterval(1800), allDay: false,
                                        location: "")
        let events = [first, second]
        let ten = first.end
        // A countdown that follows ends prefers the event under way at the tie.
        let strip = NotchCalendarSupport.countdown(events, now: ten.addingTimeInterval(-120), starts: true, ends: true,
                                                   leadTime: 15 * 60)
        suite.expect(strip == NotchCalendarCountdown(event: first, ongoing: true),
                     "the strip keeps the event under way as the next is about to start")
        let afterStrip = NotchCalendarSupport.countdown(events, now: ten.addingTimeInterval(1), starts: true, ends: true,
                                                        leadTime: 15 * 60)
        suite.expect(NotchOfficeMoments.meetingThatBegan(from: strip, to: afterStrip, at: ten.addingTimeInterval(1))
                        == second
                     && NotchOfficeMoments.meetingThatBegan(from: strip, to: afterStrip, at: ten.addingTimeInterval(90))
                        == nil
                     && NotchOfficeMoments.meetingThatBegan(from: NotchCalendarCountdown(event: second, ongoing: true),
                                                            to: NotchCalendarCountdown(event: second, ongoing: true),
                                                            at: ten.addingTimeInterval(1)) == nil,
                     "a countdown moving from one event under way to the next announces the next, once and only then")
        let watched = NotchOfficeMoments.meeting(in: events, now: ten.addingTimeInterval(-120))
        suite.expect(watched == NotchCalendarCountdown(event: second, ongoing: false)
                     && NotchOfficeMoments.meetingSoonHalves(watched, now: ten.addingTimeInterval(-120),
                                                             language: .enUS) != nil,
                     "the next meeting's five minutes are told while the first is still under way")
        let afterWatch = NotchOfficeMoments.meeting(in: events, now: ten.addingTimeInterval(1))
        suite.expect(afterWatch == nil
                     && NotchOfficeMoments.meetingThatBegan(from: watched, to: afterWatch, at: ten.addingTimeInterval(1))
                        == second,
                     "the meeting the moments follow begins as the first ends, and opens its card")
        suite.expect(NotchOfficeMoments.meetingThatBegan(from: watched, to: afterWatch, at: ten.addingTimeInterval(-1.5))
                        == second
                     && NotchOfficeMoments.meetingThatBegan(from: watched, to: afterWatch, at: ten.addingTimeInterval(-3))
                        == nil,
                     "a refresh a second early still counts, one any earlier does not")
    }

    private static func captionContracts(_ suite: TestSuite) {
        let all = [NotchOfficeMoments.callCaption, NotchOfficeMoments.meetingCaption, NotchOfficeMoments.meetingSoonCaption]
            + NotchOfficeMoments.roles
            + [NotchOfficeBattery.pluggedIn, .charging, .charged, .onBattery, .low].map(NotchOfficeMoments.caption(for:))
            + [NotchOfficeSpeaker.earphones, .speaker].map(NotchOfficeMoments.caption(for:))
        suite.expect(all.allSatisfy { !$0.isEmpty && $0.count <= 32 }, "every caption stays short")
        suite.expect(NotchOfficeMoments.showsCaptions(in: .enUS)
                     && AppLanguage.allCases.filter { NotchOfficeMoments.showsCaptions(in: $0) } == [.enUS],
                     "captions show in English only")
        let german = NotchOfficeMoments.batteryCue(.low, percent: 9, language: .de)
        let japanese = NotchOfficeMoments.communicationCue(for: content("FaceTime", "Jane", "FaceTime Video"), language: .ja)
        suite.expect(german.caption == nil && german.kind == .battery(.low) && german.level == 0.09
                     && japanese?.caption == nil && japanese?.kind == .call
                     && NotchOfficeMoments.connectCue(symbol: "airpods", language: .fr).caption == nil
                     && NotchOfficeMoments.meetingCue(NotchCalendarEvent(id: "x", title: "x", calendar: "x", start: Date(),
                                                                         end: Date(), allDay: false, location: ""),
                                                      language: .es).caption == nil,
                     "other languages keep the visuals and drop the joke")
    }

    private static func measureContracts(_ suite: TestSuite) {
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, cameraWidth: 185)
        let plain = NotchNotice(event: .battery, title: "Charging", detail: "64%", symbol: "battery.100percent.bolt")
        var office = plain
        office.office = NotchOfficeMoments.batteryCue(.charging, percent: 64, language: .enUS)
        suite.expect(plain.preferredWings(wrapsMessage: false, captions: true) == plain.preferredWings,
                     "a notice without a moment measures as it always has")
        let wide = office.wings(in: geometry)
        let narrow = plain.wings(in: geometry)
        let prop = NotchOfficeMoments.mugSide + NotchOfficeMoments.levelMarkGap
        suite.expect(wide.leading > narrow.leading
                     && wide.leading == ceil(prop + max(NotchOfficeMoments.titleWidth("Charging"),
                                                        NotchOfficeMoments.captionWidth("Refilling the mug.")))
                        + NotchNotice.levelInset + office.cameraGap,
                     "the title's side holds the mug in the prop's place and the caption under the title, and no more")
        suite.expect(wide.trailing == ceil(NotchOfficeMoments.detailWidth("64%")) + NotchNotice.levelInset + office.cameraGap
                     && office.inset(wing: wide.leading) == NotchNotice.levelInset,
                     "the charge reads alone across the camera, and the mug stands where the boombox does")
        let short = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 24, cameraWidth: 185)
        suite.expect(!NotchOfficeMoments.stripFitsCaption(short.stripHeight)
                     && office.wings(in: short).leading
                        == ceil(prop + NotchOfficeMoments.titleWidth("Charging")) + NotchNotice.levelInset + office.cameraGap,
                     "a strip too short for two lines drops the caption's room and keeps the mug and title")

        let message = content("Messages", "Jane", "See you at four")
        var banner = NotchNotice(event: .systemNotification, title: "Jane", detail: "See you at four", symbol: "bell.fill",
                                 notification: message, notificationID: UUID())
        let bare = banner.wings(in: geometry)
        banner.office = NotchOfficeMoments.communicationCue(for: message, language: .enUS)
        let roled = banner.wings(in: geometry)
        let fonts = NotchOfficeMoments.bannerFonts(banner.office)
        let family = NotchNotificationBannerLayout.wings(for: message, titleFont: fonts.title, messageFont: fonts.message)
        suite.expect(roled.leading >= bare.leading && roled.leading <= NotchOfficeMoments.bannerWingLimit
                     && banner.preferredWings.trailing == family.trailing && roled.trailing >= bare.trailing,
                     "the role widens the sender's side, never past its limit, and the message keeps its side in the family's reading")
        let width = geometry.notificationPreviewContentWidth
        suite.expect(banner.previewContentHeight(width: width)
                     == NotchNotificationPreviewLayout.contentHeight(for: message, width: width)
                        + 3 + NotchOfficeMoments.captionHeight(NotchOfficeMoments.cardCaptionFont),
                     "the held message makes room for the role under the sender")
        banner.office = NotchOfficeMoments.communicationCue(for: content("FaceTime", "Jane", "FaceTime Video"),
                                                           language: .enUS)
        suite.expect(banner.previewContentHeight(width: width) == NotchOfficeMoments.cardHeight
                     && NotchOfficeMoments.cardHeight == NotchConnectFlourish.cardHeight,
                     "a call opens into a card as tall as the connect card")
        let meeting = NotchNotice(event: .calendar, title: "Standup", detail: "10:00 – 10:30", symbol: "calendar",
                                  office: NotchOfficeCue(kind: .meeting, caption: NotchOfficeMoments.meetingCaption))
        suite.expect(meeting.previewContentHeight(width: width) == NotchOfficeMoments.cardHeight
                     && meeting.readsFromEnds,
                     "a meeting starting opens into the same card, and reads from the ends in the strip")
        suite.expect(NotchOfficeMoments.captionWidth("") == 0
                     && NotchOfficeMoments.captionWidth("Head of Sending", rule: false)
                        < NotchOfficeMoments.captionWidth("Head of Sending"),
                     "the rule's room is only taken with the rule")

        let role = "Assistant to the Regional Texter"
        let icon = NotchNotificationBannerLayout.iconSize
        let needed = icon + NotchNotificationBannerLayout.spacing + NotchOfficeMoments.captionWidth(role) + 8
        suite.expect(NotchOfficeMoments.bannerCaptionFits(role, wing: needed, inset: 8, icon: icon)
                     && !NotchOfficeMoments.bannerCaptionFits(role, wing: needed - 1, inset: 8, icon: icon)
                     && !NotchOfficeMoments.bannerCaptionFits(role, wing: 120, inset: 8, icon: icon),
                     "a side too narrow for the role leaves it out, so the icon and sender stay whole")
        let soon = NotchCalendarEvent(id: "s", title: "Standup", calendar: "Work", start: Date(),
                                      end: Date().addingTimeInterval(900), allDay: false, location: "")
        let soonNotice = NotchNotice(event: .calendar, title: "Standup", detail: "10:00 – 10:15", symbol: "calendar",
                                     office: NotchOfficeMoments.meetingSoonCue(soon, language: .enUS))
        suite.expect(soonNotice.office?.caption == NotchOfficeMoments.meetingSoonCaption
                     && soonNotice.office?.opensCard == false && soonNotice.previewContentHeight(width: width) == 0
                     && soonNotice.wings(in: geometry).leading
                        >= NotchOfficeMoments.captionWidth(NotchOfficeMoments.meetingSoonCaption),
                     "five minutes out without a strip, the event's notice stays in the strip with the caption under it")
        suite.expect(NotchOfficeMoments.meetingSoonCue(soon, language: .fr).caption == nil,
                     "and only English gets the joke")
    }

    /// A capsule's single row takes the mug in its symbol's slot and the
    /// caption after the real information, sized to its body, and only where
    /// it can grow to hold them.
    private static func capsuleContracts(_ suite: TestSuite) {
        func capsule(bar: CGFloat, room: CGFloat? = 600) -> NotchGeometry {
            NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0, cameraWidth: 0,
                          layout: .spacious, menuBarHeight: bar, compactSideRoom: room, silhouette: .capsule)
        }
        typealias Layout = NotchCapsuleLayout
        let standard = capsule(bar: 24)
        let cue = NotchOfficeMoments.batteryCue(.charging, percent: 64, language: .enUS)
        let base = Layout.noticeContent(title: "Charging", detail: "64%", level: false)
        let mug = NotchOfficeMoments.capsuleMugWidth(cue, geometry: standard)
        suite.expect(mug >= 0 && NotchOfficeMoments.mugHeight * NotchOfficeMoments.capsuleMugScale(standard)
                        <= standard.stripBodyHeight
                     && mug == NotchOfficeMoments.capsuleEditionMarkWidth(standard) - Layout.symbolWidth
                     && NotchOfficeMoments.capsuleMugWidth(nil, geometry: standard) == 0,
                     "the mug fits the capsule's body in the symbol's slot, adding only what it needs past a symbol")
        suite.expect(NotchOfficeMoments.capsuleCaption(cue, content: base + mug, maximum: Layout.Maximum.notice,
                                                       geometry: standard) == "Refilling the mug."
                     && NotchOfficeMoments.capsuleContent(cue, base: base, maximum: Layout.Maximum.notice,
                                                          geometry: standard)
                        == base + mug + Layout.groupSpacing
                        + NotchOfficeMoments.captionWidth("Refilling the mug.", font: NotchOfficeMoments.stripCaptionFont),
                     "a standard bar's capsule reads the caption after the reading, at the strip's size")
        suite.expect(NotchOfficeMoments.capsuleCaptionFont(standard) === NotchOfficeMoments.stripCaptionFont
                     && NotchOfficeMoments.capsuleCaptionFont(capsule(bar: 34))
                        === NotchOfficeMoments.cardCaptionFont,
                     "a capsule in a taller bar takes the card's caption size")
        let crowded = capsule(bar: 24, room: 20)
        suite.expect(NotchOfficeMoments.capsuleCaption(cue, content: base + mug, maximum: Layout.Maximum.notice,
                                                       geometry: crowded) == nil
                     && NotchOfficeMoments.capsuleContent(cue, base: base, maximum: Layout.Maximum.notice,
                                                          geometry: crowded) == base + mug,
                     "where the menus leave no room, the caption is left out and the reading stays whole")
        let message = content("Messages", "Pam Beesly", "Did you take my yogurt? It had my name on it, Michael.")
        let role = NotchOfficeMoments.communicationCue(for: message, language: .enUS)
        let long = Layout.notificationContent(title: message.compactTitle,
                                              message: String(repeating: message.compactDetail, count: 3),
                                              geometry: standard)
        suite.expect(NotchOfficeMoments.capsuleCaption(role, content: long, maximum: Layout.Maximum.notification,
                                                       geometry: standard) == nil,
                     "a message that already fills the capsule is never cut for the role")
        let plain = NotchOfficeMoments.capsuleContent(nil, base: base, maximum: Layout.Maximum.notice, geometry: standard)
        suite.expect(plain == base, "a notice without a moment measures as it always has")
        capsuleLevelContracts(suite, standard: standard, crowded: crowded, tall: capsule(bar: 37))
    }

    /// Cafe Disco and the blinds in a capsule: the mark and the meter at its
    /// size, and the caption after the reading only where the capsule holds
    /// the widest, so a held key never resizes it for the words.
    private static func capsuleLevelContracts(_ suite: TestSuite, standard: NotchGeometry, crowded: NotchGeometry,
                                              tall: NotchGeometry) {
        typealias Moments = NotchOfficeMoments
        typealias Layout = NotchCapsuleLayout
        func volume(_ percent: Int, _ language: AppLanguage = .enUS) -> NotchOfficeCue {
            Moments.volumeCue(level: Double(percent) / 100, language: language)
        }
        func brightness(_ percent: Int, _ language: AppLanguage = .enUS) -> NotchOfficeCue {
            Moments.brightnessCue(level: Double(percent) / 100, language: language)
        }
        func row(_ cue: NotchOfficeCue?, _ percent: Int, _ geometry: NotchGeometry) -> CGFloat {
            Moments.capsuleRow(cue, title: "Volume", detail: "\(percent)%", level: true, geometry: geometry)
        }
        func content(_ cue: NotchOfficeCue?, _ percent: Int, _ geometry: NotchGeometry) -> CGFloat {
            Moments.capsuleContent(cue, base: row(cue, percent, geometry), maximum: Layout.Maximum.notice,
                                   geometry: geometry)
        }
        func caption(_ cue: NotchOfficeCue, _ percent: Int, _ geometry: NotchGeometry) -> String? {
            Moments.capsuleCaption(cue, content: row(cue, percent, geometry), maximum: Layout.Maximum.notice,
                                   geometry: geometry)
        }

        let plain = Layout.noticeContent(title: "Volume", detail: "56%", level: true)
        suite.expect(row(nil, 56, standard) == plain && content(nil, 56, standard) == plain
                     && Moments.capsuleRow(Moments.batteryCue(.charging, percent: 56, language: .enUS), title: "Volume",
                                           detail: "56%", level: true, geometry: standard) == plain,
                     "with the moments off, a level's capsule measures exactly as it always has")

        for geometry in [standard, tall] {
            let height = Moments.capsuleLevelHeight(geometry)
            suite.expect(height <= geometry.stripBodyHeight
                         && Moments.miniBoombox.height * Moments.capsuleMarkScale(volume(56), geometry: geometry) <= height
                         && Moments.blindsSide * Moments.capsuleMarkScale(brightness(56), geometry: geometry) <= height
                         && Moments.vuHeights.highest * Moments.capsuleMeterScale(geometry) <= height,
                         "the boombox, the blinds and the VU meter all fit the capsule's body")
        }
        suite.expect(Moments.capsuleMarkScale(volume(56), geometry: tall) == 1
                     && Moments.capsuleMeterScale(tall) == 1 && Moments.capsuleMarkScale(brightness(56), geometry: standard) < 1,
                     "a taller bar draws them at the strip's size; a standard bar shrinks only what is too tall")
        suite.expect(row(volume(56), 56, standard) == Moments.capsuleMarkWidth(volume(56), geometry: standard)
                        + Layout.spacing + Moments.vuWidth + Layout.spacing + Moments.capsuleReadingWidth("56%")
                     && row(brightness(56), 56, standard) == Moments.capsuleMarkWidth(brightness(56), geometry: standard)
                        + Layout.spacing + Layout.meterWidth + Layout.spacing + Moments.capsuleReadingWidth("56%"),
                     "the capsule's row is the mark, the VU meter or the daylight meter, and the reading")

        let widest = Moments.captionWidth(volume(0).widestCaption ?? "", font: Moments.stripCaptionFont)
        suite.expect(caption(volume(56), 56, standard) == "Threat level: mid-tempo."
                     && caption(volume(0), 0, standard) == "Jinx."
                     && content(volume(56), 56, standard) == row(volume(56), 56, standard) + Layout.groupSpacing + widest,
                     "where the capsule can grow, the band's caption reads after the reading, in the widest's room")
        let volumes = Set((0...100).map { content(volume($0), $0, standard) })
        suite.expect(volumes.count == 1, "under a held key the volume's capsule never resizes, whatever the band")
        suite.expect((0...100).allSatisfy { caption(volume($0), $0, crowded) == nil }
                     && Set((0...100).map { content(volume($0), $0, crowded) }) == [row(volume(56), 56, crowded)],
                     "where the menus leave too little, every band drops the caption, even the short ones")
        suite.expect(caption(volume(56, .de), 56, standard) == nil
                     && content(volume(56, .de), 56, standard) == row(volume(56), 56, standard),
                     "other languages keep the boombox and the meter and drop the joke")

        let middle = Set((11...99).map { content(brightness($0), $0, standard) })
        let dark = Set((0...10).map { content(brightness($0), $0, standard) })
        suite.expect(middle == [row(brightness(56), 56, standard)] && dark.count == 1
                     && content(brightness(100), 100, standard) > row(brightness(100), 100, standard)
                     && (dark.first ?? 0) > row(brightness(5), 5, standard)
                     && caption(brightness(5), 5, standard) == "Lights out. Go home."
                     && caption(brightness(100), 100, standard) == "Fluorescent. As intended.",
                     "brightness keeps the bare row through the middle and grows for its words only at either end")
        suite.expect(caption(brightness(5), 5, crowded) == nil && caption(brightness(100), 100, crowded) == nil,
                     "and drops them at both ends where the widest would not fit")
    }

    /// The open island's top row: the mark, the meter and the reading, with
    /// the caption under the reading where the side holds the widest.
    private static func expandedLevelContracts(_ suite: TestSuite) {
        typealias Moments = NotchOfficeMoments
        let volume = Moments.volumeCue(level: 0.56, language: .enUS)
        let brightness = Moments.brightnessCue(level: 0.5, language: .enUS)
        suite.expect(Moments.expandedCaptionFits(volume, width: 220) && Moments.expandedCaptionFits(brightness, width: 220),
                     "a full row's reading side holds the caption under the reading")
        suite.expect(!Moments.expandedCaptionFits(volume, width: 150) && !Moments.expandedCaptionFits(brightness, width: 150)
                     && !Moments.expandedCaptionFits(volume, width: nil),
                     "a side too narrow for the widest caption drops it whole")
        suite.expect(!Moments.expandedCaptionFits(Moments.volumeCue(level: 0.56, language: .de), width: 400)
                     && !Moments.expandedCaptionFits(Moments.batteryCue(.charging, percent: 56, language: .enUS), width: 400),
                     "only a level moment in English has one")
        let needed = Moments.levelMarkWidth(volume) + Moments.expandedSpacing + Moments.vuWidth + Moments.expandedSpacing
            + Moments.expandedReadingColumn(volume, caption: true)
        suite.expect(Moments.expandedCaptionFits(volume, width: needed) && !Moments.expandedCaptionFits(volume, width: needed - 1),
                     "the caption fits exactly when the mark, the meter and the widest caption do")
        let columns = Set((0...100).map {
            Moments.expandedReadingColumn(Moments.volumeCue(level: Double($0) / 100, language: .enUS), caption: true)
        })
        suite.expect(columns.count == 1
                     && Moments.expandedReadingColumn(volume, caption: true)
                        >= Moments.captionWidth(volume.widestCaption ?? "")
                     && Moments.expandedReadingColumn(volume, caption: false) == Moments.levelReadingWidth(),
                     "the reading's column holds the widest caption's room through every band, so the meter stays put")
    }

    // MARK: - Volume and brightness

    /// Cafe Disco's bands and captions, read from the percentage the notice shows.
    private static func volumeContracts(_ suite: TestSuite) {
        typealias Moments = NotchOfficeMoments
        let bands: [(Int, NotchOfficeVolumeBand)] = [(-3, .mute), (0, .mute), (1, .low), (33, .low), (34, .mid),
                                                     (66, .mid), (67, .high), (99, .high), (100, .full), (140, .full)]
        suite.expect(bands.allSatisfy { Moments.volumeBand(percent: $0.0) == $0.1 },
                     "silence is mute, 1-33 low, 34-66 mid, 67-99 high and only 100 full")
        let captions: [NotchOfficeVolumeBand: String] = [
            .mute: "Jinx.", .low: "Inside voices.", .mid: "Threat level: mid-tempo.",
            .high: "Corporate can hear this.", .full: "That's what she synced.",
        ]
        suite.expect(NotchOfficeVolumeBand.allCases.allSatisfy { Moments.caption(for: $0) == captions[$0] },
                     "each band has its caption")
        suite.expect(Set(captions.values).count == captions.count,
                     "no two bands share a caption, so the caption's words say which band it is")
        suite.expect(Moments.percent(0.564) == 56 && Moments.percent(0.996) == 100 && Moments.percent(1.4) == 100
                     && Moments.percent(-1) == 0 && Moments.percent(.nan) == 0,
                     "the band is read from the percentage the notice shows")
        let cue = Moments.volumeCue(level: 0.56, language: .enUS)
        suite.expect(cue.kind == .volume && cue.isLevel && cue.caption == "Threat level: mid-tempo."
                     && cue.level == 0.56 && !cue.opensCard && !cue.showsMug,
                     "a volume moment stays in the strip with its band's caption")
        suite.expect(Moments.volumeCue(level: 0, language: .enUS).caption == "Jinx."
                     && Moments.volumeCue(level: 1, language: .enUS).caption == "That's what she synced."
                     && Moments.volumeCue(level: .nan, language: .enUS).level == 0,
                     "muted reads jinx, and only all the way up is synced")
        // A held key steps through every percentage: the caption changes
        // exactly where the band does, and nowhere else.
        let steps = (0...100).map { Moments.volumeCue(level: Double($0) / 100, language: .enUS) }
        let changes = zip(steps, steps.dropFirst()).filter { $0.caption != $1.caption }.count
        suite.expect(changes == 4 && Set(steps.map(\.widestCaption)).count == 1,
                     "under a held key the caption changes only at the four band edges, and the widest never changes")
        let widest = cue.widestCaption ?? ""
        suite.expect(captions.values.allSatisfy { Moments.captionWidth($0) <= Moments.captionWidth(widest) },
                     "the side is sized for the widest caption of all the bands")
        let german = Moments.volumeCue(level: 0.56, language: .de)
        suite.expect(german.caption == nil && german.widestCaption == nil && german.kind == .volume,
                     "other languages keep the boombox and the meter and drop the joke")
        suite.expect(captions.values.allSatisfy { $0.count <= 28 }, "every volume caption is at most 28 characters")
    }

    /// The blinds: a caption only at either end of the range.
    private static func brightnessContracts(_ suite: TestSuite) {
        typealias Moments = NotchOfficeMoments
        let bands: [(Int, NotchOfficeBrightnessBand)] = [(0, .dark), (5, .dark), (10, .dark), (11, .lit), (50, .lit),
                                                         (99, .lit), (100, .full)]
        suite.expect(bands.allSatisfy { Moments.brightnessBand(percent: $0.0) == $0.1 },
                     "ten percent or below is dark, a hundred is full, and the rest is lit")
        suite.expect(Moments.caption(for: NotchOfficeBrightnessBand.dark) == "Lights out. Go home."
                     && Moments.caption(for: NotchOfficeBrightnessBand.full) == "Fluorescent. As intended."
                     && Moments.caption(for: NotchOfficeBrightnessBand.lit) == nil,
                     "only the ends of the range earn a caption")
        let dim = Moments.brightnessCue(level: 0.05, language: .enUS)
        let middle = Moments.brightnessCue(level: 0.5, language: .enUS)
        let full = Moments.brightnessCue(level: 1, language: .enUS)
        suite.expect(dim.kind == .brightness && dim.isLevel && dim.caption == "Lights out. Go home."
                     && middle.caption == nil && full.caption == "Fluorescent. As intended."
                     && Set([dim, middle, full].map(\.widestCaption)) == ["Fluorescent. As intended."],
                     "the middle has no caption but keeps room for the widest")
        let german = Moments.brightnessCue(level: 0.05, language: .de)
        suite.expect(german.caption == nil && german.widestCaption == nil,
                     "other languages keep the blinds and drop the joke")
        suite.expect([dim, full].compactMap(\.caption).allSatisfy { $0.count <= 28 },
                     "every brightness caption is at most 28 characters")
    }

    /// The VU meter and the boombox's cones.
    private static func meterContracts(_ suite: TestSuite) {
        typealias Moments = NotchOfficeMoments
        let heights = (0..<Moments.vuSegments).map(Moments.vuHeight)
        suite.expect(Moments.vuSegments == 9 && heights.first == 6 && heights.last == 18
                     && zip(heights, heights.dropFirst()).allSatisfy { $1 > $0 }
                     && Moments.vuWidth == 9 * 3 + 8 * 2,
                     "nine bars three points wide, two apart, stepping from 6 to 18 points tall")
        suite.expect(Moments.vuLit(0) == 0 && Moments.vuLit(0.01) == 1 && Moments.vuLit(0.5) == 5
                     && Moments.vuLit(0.85) == 8 && Moments.vuLit(1) == 9 && Moments.vuLit(1.4) == 9
                     && Moments.vuLit(.nan) == 0 && Moments.vuLit(-0.2) == 0,
                     "any sound lights the first segment and all the way up lights the ninth")
        let lit = (0...100).map { Moments.vuLit(Double($0) / 100) }
        suite.expect(zip(lit, lit.dropFirst()).allSatisfy { $1 >= $0 && $1 - $0 <= 1 },
                     "turning it up lights the segments one at a time, in order")
        suite.expect(Moments.vuLit(0.004) == 0 && Moments.vuLit(0.0049) == 0 && Moments.vuLit(0.006) == 1
                     && Moments.vuLit(0.884) == 8 && Moments.vuLit(0.886) == 9,
                     "a level that reads 0% lights nothing, as it reads Jinx.; the segments follow the rounded reading")
        let fine = (0...2000).map { Double($0) / 2000 }
        suite.expect(fine.allSatisfy { level in
                        let percent = Moments.percent(level)
                        return (Moments.vuLit(level) == 0) == (Moments.volumeBand(percent: percent) == .mute)
                            && Moments.vuLit(level) == Moments.vuLit(Double(percent) / 100)
                     },
                     "the meter, the band and the reading agree at every level, between whole percentages too")
        suite.expect(!Moments.vuIsHot(6) && Moments.vuIsHot(7) && Moments.vuIsHot(8), "the top two are the hot ones")

        func rgb(_ color: NSColor) -> [Int] {
            let color = color.usingColorSpace(.sRGB) ?? color
            return [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        let pink = NSColor(srgbRed: 0.96, green: 0.33, blue: 0.47, alpha: 1)
        let indigo = NSColor(srgbRed: 0.36, green: 0.42, blue: 0.98, alpha: 1)
        let teal = NSColor(srgbRed: 0.18, green: 0.85, blue: 0.75, alpha: 1)
        let song = Moments.vuColors([pink, indigo])
        suite.expect(song.count == 9 && rgb(song[0]) == rgb(pink) && rgb(song[6]) == rgb(indigo)
                     && rgb(song[7]) == [0xC0, 0x39, 0x2B] && rgb(song[8]) == [0xC0, 0x39, 0x2B],
                     "the song's colours run low to high across the cool segments, and the top two are beet")
        let middle = rgb(song[3])
        suite.expect(middle != rgb(pink) && middle != rgb(indigo)
                     && zip(middle, zip(rgb(pink), rgb(indigo))).allSatisfy { $0 >= min($1.0, $1.1) && $0 <= max($1.0, $1.1) },
                     "the segments between blend from one colour to the next")
        let three = Moments.vuColors([teal, pink, indigo])
        suite.expect(rgb(three[0]) == rgb(teal) && rgb(three[3]) == rgb(pink) && rgb(three[6]) == rgb(indigo),
                     "a palette of three passes through each colour in its order")
        suite.expect(Moments.vuColors([teal]).prefix(7).allSatisfy { rgb($0) == rgb(teal) }
                     && Moments.vuColors([]).prefix(7).allSatisfy { rgb($0) == [255, 255, 255] }
                     && rgb(Moments.vuColors([])[8]) == [0xC0, 0x39, 0x2B],
                     "one colour fills the cool segments, none leaves them white, and the hot ones stay beet")

        suite.expect(Moments.coneScale(0) == 1 && abs(Moments.coneScale(1) - 1.35) < 0.0001
                     && abs(Moments.coneScale(0.5) - 1.175) < 0.0001 && Moments.coneScale(3) == Moments.coneScale(1)
                     && Moments.coneScale(.nan) == 1 && abs(Moments.coneKick - 1.12) < 0.0001,
                     "the cones swell from 1 to 1.35 with the level and kick 12% on a press")
        suite.expect(Moments.coneKicks(at: 10, lastKick: nil) && !Moments.coneKicks(at: 10.1, lastKick: 10)
                     && Moments.coneKicks(at: 10 + Moments.coneKickDuration, lastKick: 10)
                     && Moments.coneKicks(at: 5, lastKick: 10),
                     "a press kicks once the last kick has played out, and a clock that went back never blocks one")
        // A key held for a second, stepping every 60 ms: the steps inside a
        // kick are absorbed, so the cones pump in time rather than restart.
        var last: TimeInterval?
        var kicks = 0
        for step in 0..<17 {
            let now = Double(step) * 0.06
            if Moments.coneKicks(at: now, lastKick: last) { last = now; kicks += 1 }
        }
        suite.expect(kicks == 5, "a held key's seventeen steps kick the cones five times, not seventeen")
    }

    /// The island holds still under a held key and is exactly as upstream with the moments off.
    private static func levelMeasureContracts(_ suite: TestSuite) {
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, cameraWidth: 185)
        func volume(_ percent: Int, _ language: AppLanguage? = .enUS) -> NotchNotice {
            let level = Double(percent) / 100
            return NotchNotice(event: .volume, title: "Volume", detail: "\(percent)%", symbol: "speaker.wave.2.fill",
                               level: level,
                               office: language.map { NotchOfficeMoments.volumeCue(level: level, language: $0) })
        }
        func brightness(_ percent: Int, _ language: AppLanguage? = .enUS) -> NotchNotice {
            let level = Double(percent) / 100
            return NotchNotice(event: .brightness, title: "Brightness", detail: "\(percent)%", symbol: "sun.max.fill",
                               level: level,
                               office: language.map { NotchOfficeMoments.brightnessCue(level: level, language: $0) })
        }
        let volumes = (0...100).map { volume($0).wings(in: geometry) }
        let brightnesses = (0...100).map { brightness($0).wings(in: geometry) }
        suite.expect(volumes.allSatisfy { $0 == volumes[0] } && brightnesses.allSatisfy { $0 == brightnesses[0] },
                     "a held key never resizes the island: every reading and band takes the same sides")

        let plain = volume(56, nil).wings(in: geometry)
        let plainWing = ceil(NotchNotice.levelInset + 18 + 8
                             + ("100%" as NSString).size(withAttributes: [
                                 .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)]).width)
        suite.expect(plain == NotchNoticeWings(leading: plainWing, trailing: plainWing)
                     && brightness(56, nil).wings(in: geometry) == plain,
                     "with the moments off, a level measures exactly as upstream")

        let cafe = volume(56).wings(in: geometry)
        let widest = NotchOfficeMoments.captionWidth(NotchOfficeMoments.volumeCue(level: 0.5, language: .enUS)
                                                        .widestCaption ?? "")
        suite.expect(cafe.leading >= NotchNotice.levelInset + NotchOfficeMoments.miniBoombox.width
                        + NotchOfficeMoments.levelMarkGap + widest
                     && cafe.trailing >= NotchNotice.levelInset + NotchOfficeMoments.vuWidth
                     && cafe.trailing >= plain.trailing && cafe.leading > plain.leading,
                     "the boombox and the widest caption fit one side, the VU meter the other")
        let german = volume(56, .de).wings(in: geometry)
        suite.expect(german.leading < cafe.leading && german.leading >= NotchNotice.levelInset
                        + NotchOfficeMoments.miniBoombox.width + NotchOfficeMoments.levelReadingWidth()
                     && german.trailing == cafe.trailing,
                     "without the joke the reading's side is only as wide as the boombox and the reading")
        let short = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 24, cameraWidth: 185)
        suite.expect(volume(56).wings(in: short) == volume(56, .de).wings(in: short),
                     "a strip too short for the caption keeps no room for it")

        let blinds = brightness(50).wings(in: geometry)
        let dark = NotchOfficeMoments.captionWidth("Fluorescent. As intended.")
        suite.expect(blinds.leading == brightness(50, .de).wings(in: geometry).leading
                     && blinds.trailing >= NotchNotice.levelInset + dark && blinds.trailing > plain.trailing,
                     "brightness keeps a narrow reading side and reads its caption under the meter")
        suite.expect(NotchOfficeMoments.captionUnderReading(NotchOfficeMoments.volumeCue(level: 0, language: .enUS))
                     && !NotchOfficeMoments.captionUnderReading(NotchOfficeMoments.brightnessCue(level: 0, language: .enUS)),
                     "volume's caption reads under its reading, brightness's under its meter")
        suite.expect(volume(56).accessibilityText == "Volume, 56%" && volume(56).previewContentHeight(width: 400) == 0,
                     "VoiceOver reads only the volume, and the moment never opens a card")
    }
}
