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
        roleContracts(suite)
        calendarContracts(suite)
        captionContracts(suite)
        measureContracts(suite)
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
        suite.expect(channel(content("zoom.us", "Incoming call from Jane")) == .call
                     && channel(content("", "Jane", "Incoming FaceTime Audio")) == .call,
                     "any app whose words say a call is ringing is a call")
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
        suite.expect(NotchOfficeMoments.meetingSoonBegins(upcoming, now: start.addingTimeInterval(-3600))
                        == start.addingTimeInterval(-300)
                     && NotchOfficeMoments.meetingSoonBegins(upcoming, now: start.addingTimeInterval(-60)) == nil,
                     "the strip is measured again when the caption is due, never in the past")
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
        suite.expect(wide.leading > narrow.leading
                     && wide.leading >= ceil(NotchOfficeMoments.captionWidth("Refilling the mug.")) + 18 + 8 + 16,
                     "the title's side widens for the caption under it, and only as far as it needs")
        suite.expect(wide.trailing == narrow.trailing + NotchOfficeMoments.mugSide + NotchOfficeMoments.mugGap,
                     "the reading's side makes room for the mug")
        let short = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 24, cameraWidth: 185)
        suite.expect(!NotchOfficeMoments.stripFitsCaption(short.stripHeight)
                     && office.wings(in: short).leading == plain.wings(in: short).leading,
                     "a strip too short for two lines keeps its width and drops the caption")

        let message = content("Messages", "Jane", "See you at four")
        var banner = NotchNotice(event: .systemNotification, title: "Jane", detail: "See you at four", symbol: "bell.fill",
                                 notification: message, notificationID: UUID())
        let bare = banner.wings(in: geometry)
        banner.office = NotchOfficeMoments.communicationCue(for: message, language: .enUS)
        let roled = banner.wings(in: geometry)
        suite.expect(roled.leading >= bare.leading && roled.leading <= NotchOfficeMoments.bannerWingLimit
                     && roled.trailing == bare.trailing,
                     "the role widens the sender's side, never past its limit, and the message keeps its side")
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
    }
}
