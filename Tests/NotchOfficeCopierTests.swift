// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// The copy moment's rules: the captions dealt in turn, the word naming what
/// was copied and never the copy, the copier's runs coalescing, and the
/// island holding still from one copy to the next.
enum NotchOfficeCopierTests {
    static func run(_ suite: TestSuite) {
        captionContracts(suite)
        kindContracts(suite)
        summaryContracts(suite)
        runContracts(suite)
        measureContracts(suite)
        capsuleContracts(suite)
    }

    private static func copyNotice(_ take: Int, _ kind: NotchOfficeCopyKind,
                                   language: AppLanguage = .enUS) -> NotchNotice {
        let text = FeatureStrings.clipboard(language)
        return NotchNotice(event: .clipboard, title: text.copied,
                           detail: NotchOfficeMoments.copySummary(kind, language: language), symbol: "doc.on.clipboard",
                           office: NotchOfficeMoments.copyCue(take: take, kind: kind, language: language))
    }

    /// Dealt in turn from the first copy, short, and only in English.
    private static func captionContracts(_ suite: TestSuite) {
        let captions = NotchOfficeMoments.copyCaptions
        suite.expect(captions.count >= 3 && Set(captions).count == captions.count,
                     "a copy has several captions, all different")
        suite.expect(captions.allSatisfy { $0.count <= 28 }, "every copy caption is at most 28 characters")
        suite.expect(captions.allSatisfy { !$0.lowercased().contains("dunder") && !$0.lowercased().contains("mifflin") },
                     "no caption names the show's paper company")
        suite.expect(NotchOfficeMoments.copyCaption(take: 1) == "Copy that."
                     && NotchOfficeMoments.copyCaption(take: 2) == "In triplicate."
                     && NotchOfficeMoments.copyCaption(take: 3) == "Filed under: important.",
                     "the first copies read \"Copy that.\", \"In triplicate.\", then \"Filed under: important.\"")
        suite.expect((1...20).allSatisfy {
                         NotchOfficeMoments.copyCaption(take: $0) != NotchOfficeMoments.copyCaption(take: $0 + 1)
                     },
                     "two copies in a row never read the same caption")
        suite.expect(NotchOfficeMoments.copyCaption(take: 1 + captions.count) == captions[0]
                     && NotchOfficeMoments.copyCaption(take: 0) == captions[captions.count - 1]
                     && captions.contains(NotchOfficeMoments.copyCaption(take: Int.min + 1))
                     && captions.contains(NotchOfficeMoments.copyCaption(take: Int.max)),
                     "the captions cycle, whatever the count, and never crash on its edges")
        let english = NotchOfficeMoments.copyCue(take: 2, kind: .text, language: .enUS)
        suite.expect(english.kind == .copy && english.caption == "In triplicate."
                     && english.widestCaption == NotchOfficeMoments.widest(captions)
                     && english.copy?.take == 2 && english.copy?.kind == .text,
                     "an English copy carries its turn's caption, the widest to size for, and the copy")
        let german = NotchOfficeMoments.copyCue(take: 2, kind: .text, language: .de)
        suite.expect(german.caption == nil && german.widestCaption == nil && german.copy?.take == 2,
                     "another language keeps the copier and drops the joke")
        suite.expect(english.holdsWidestCaption && !english.opensCard && !english.isLevel && !english.showsMug,
                     "a copy keeps its caption's widest room and draws in the strip, as no other moment")
    }

    /// The kind comes from the entry's kind, and a link only from one web address alone.
    private static func kindContracts(_ suite: TestSuite) {
        suite.expect(NotchOfficeMoments.copyKind(ClipboardHistoryEntry(text: "hunter2")) == .text,
                     "copied text is text")
        suite.expect(NotchOfficeMoments.copyKind(ClipboardHistoryEntry(text: " https://example.com/a?b=c\n")) == .link,
                     "one web address, however spaced, is a link")
        suite.expect(NotchOfficeMoments.copyKind(ClipboardHistoryEntry(text: "", kind: .image, imageFile: "a.png",
                                                                         imageWidth: 10, imageHeight: 10)) == .image,
                     "a copied image is an image")
        suite.expect(NotchOfficeMoments.copyKind(ClipboardHistoryEntry(text: "", kind: .files,
                                                                         filePaths: ["/a", "/b", "/c"])) == .files(3),
                     "copied files are counted")
        for text in ["see https://example.com", "https://", "example.com", "ftp://example.com", "mailto:a@b.c",
                     "https://a.com https://b.com", "javascript:alert(1)", ""] {
            suite.expect(!NotchOfficeMoments.isLink(text), "\"\(text)\" is not a link to name")
        }
        let long = "https://example.com/" + String(repeating: "a", count: NotchOfficeMoments.linkLimit)
        suite.expect(!NotchOfficeMoments.isLink(long), "a very long copy is not read through for a link")
        suite.expect(NotchOfficeMoments.isLink("HTTP://EXAMPLE.COM"), "a link's scheme reads in any case")
    }

    /// A word for the kind, in the app's words where it has them, and never the copy.
    private static func summaryContracts(_ suite: TestSuite) {
        let english = FeatureStrings.clipboard(.enUS)
        suite.expect(NotchOfficeMoments.copySummary(.text, language: .enUS) == "Text"
                     && NotchOfficeMoments.copySummary(.link, language: .enUS) == "Link"
                     && NotchOfficeMoments.copySummary(.image, language: .enUS) == english.imageEntryLabel
                     && NotchOfficeMoments.copySummary(.files(1), language: .enUS) == "File"
                     && NotchOfficeMoments.copySummary(.files(4), language: .enUS) == "4 files",
                     "English names text, a link, an image, a file and several files")
        let german = FeatureStrings.clipboard(.de)
        suite.expect(NotchOfficeMoments.copySummary(.text, language: .de) == german.title
                     && NotchOfficeMoments.copySummary(.link, language: .de) == german.title
                     && NotchOfficeMoments.copySummary(.files(1), language: .de) == german.title
                     && NotchOfficeMoments.copySummary(.image, language: .de) == german.imageEntryLabel
                     && NotchOfficeMoments.copySummary(.files(4), language: .de) == String(format: german.fileCountFormat, 4),
                     "another language uses the app's own words, and keeps \"Clipboard\" where it has none")
        // A password copied as text, or as a link carrying one, is never shown.
        for secret in ["correct horse battery staple", "https://admin:s3cr3t@example.com/login"] {
            let entry = ClipboardHistoryEntry(text: secret)
            let notice = copyNotice(1, NotchOfficeMoments.copyKind(entry))
            let shown = [notice.title, notice.detail, notice.accessibilityText, notice.office?.caption ?? ""]
                .joined(separator: " ")
            suite.expect(!shown.contains(secret) && !shown.contains("s3cr3t") && !shown.contains("horse"),
                         "the notice never shows what was copied")
        }
        suite.expect(copyNotice(1, .text).accessibilityText == "\(english.copied), Text",
                     "VoiceOver reads the copy and its kind, never the caption")
    }

    /// The first copy plays it all; one while it plays replays it quicker; one hard on its heels is absorbed.
    private static func runContracts(_ suite: TestSuite) {
        let run = NotchOfficeMoments.copyRun
        suite.expect(run(10, nil) == .full, "the first copy plays the whole motion")
        suite.expect(run(10.05, 10) == .absorbed && run(10 + NotchOfficeMoments.copyAbsorb - 0.001, 10) == .absorbed,
                     "a copy hard on the last one's heels is part of the same run")
        suite.expect(run(10 + NotchOfficeMoments.copyAbsorb, 10) == .quick && run(10.3, 10) == .quick,
                     "a copy while the last still plays replays it quicker, from the start")
        suite.expect(run(10 + NotchOfficeMoments.copyRunLength, 10) == .full && run(14, 10) == .full,
                     "a copy after the last has settled plays the whole motion again")
        suite.expect(run(9, 10) == .full, "a clock that went back never holds a copy back")
        suite.expect(NotchOfficeMoments.copyQuickSpeed > 1
                     && NotchOfficeMoments.copyAbsorb < NotchOfficeMoments.copyRunLength
                     && (0.3...0.5).contains(NotchOfficeMoments.copyRunLength),
                     "the motion lasts under half a second, and a replay is quicker still")
        let sheets = NotchOfficeMoments.copySheets
        suite.expect(sheets([], 0) == [0] && sheets([0], 1) == [0, 1] && sheets([0, 1], 2) == [0, 1, 2],
                     "each copy's sheet comes out over the last")
        suite.expect(sheets([0, 1, 2], 3) == [1, 2, 3] && sheets([1, 2, 3], 3) == [1, 2, 3],
                     "the pile under the newest stays at two sheets, and one copy is one sheet")
    }

    /// The island is sized once per moment: copy after copy, of any kind, it holds still.
    private static func measureContracts(_ suite: TestSuite) {
        let text = copyNotice(1, .text), image = copyNotice(2, .image), link = copyNotice(3, .link)
        let file = copyNotice(4, .files(1)), many = copyNotice(5, .files(42))
        let wings = text.preferredWings
        suite.expect([image, link, file, many].allSatisfy { $0.preferredWings == wings },
                     "one copy after another, of any kind and any caption, never resizes the island")
        let caption = NotchOfficeMoments.captionWidth(NotchOfficeMoments.widest(NotchOfficeMoments.copyCaptions) ?? "")
        suite.expect(wings.leading >= NotchOfficeMoments.copier.width + NotchOfficeMoments.levelMarkGap + caption + 16,
                     "the copier's side holds the copier and the widest caption whole")
        suite.expect(wings.trailing >= NotchOfficeMoments.copySummaryWidth("88 files") + 16,
                     "the far side holds the widest kind")
        let volume = NotchNotice(event: .volume, title: "Volume", detail: "50%", symbol: "speaker.wave.2.fill", level: 0.5,
                                 office: NotchOfficeMoments.volumeCue(level: 0.5, language: .enUS))
        suite.expect(text.inset(wing: wings.leading) == volume.inset(wing: volume.preferredWings.leading)
                     && wings == NotchOfficeMoments.copyWings(text.office!, title: text.title, detail: text.detail,
                                                              inset: NotchNotice.levelInset),
                     "the copier stands as far from the island's end as the boombox does")
        let short = text.preferredWings(wrapsMessage: false, captions: false)
        suite.expect(short.leading < wings.leading && short.trailing == wings.trailing,
                     "a strip too short for a caption narrows only the copier's side")
        let german = copyNotice(1, .image, language: .de), germanText = copyNotice(2, .text, language: .de)
        suite.expect(german.preferredWings == germanText.preferredWings,
                     "another language's copies hold still too, without a caption")
        let plainText = FeatureStrings.clipboard(.enUS)
        let off = NotchNotice(event: .clipboard, title: plainText.copied, detail: plainText.title, symbol: "doc.on.clipboard")
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        func measured(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        suite.expect(off.preferredWings == NotchNoticeWings(leading: ceil(measured(plainText.copied) + 18 + 8) + 16 + 6,
                                                            trailing: ceil(measured(plainText.title)) + 16 + 6),
                     "with the Office moments off, the notice measures exactly as upstream's")
    }

    /// The capsule: the copier at its size, and the caption only where it holds.
    private static func capsuleContracts(_ suite: TestSuite) {
        func capsule(bar: CGFloat, room: CGFloat? = 600) -> NotchGeometry {
            NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0, cameraWidth: 0,
                          layout: .spacious, menuBarHeight: bar, compactSideRoom: room, silhouette: .capsule)
        }
        typealias Layout = NotchCapsuleLayout
        let standard = capsule(bar: 24), crowded = capsule(bar: 24, room: 20), tall = capsule(bar: 37)
        for (name, geometry) in [("standard", standard), ("tall", tall)] {
            suite.expect(NotchOfficeMoments.copier.height * NotchOfficeMoments.capsuleCopierScale(geometry)
                            <= NotchOfficeMoments.capsuleLevelHeight(geometry) + 0.001,
                         "the copier fits a \(name) capsule's body")
        }
        func row(_ notice: NotchNotice, _ geometry: NotchGeometry) -> CGFloat {
            let base = NotchOfficeMoments.capsuleRow(notice.office, title: notice.title, detail: notice.detail,
                                                     level: false, geometry: geometry)
            return NotchOfficeMoments.capsuleContent(notice.office, base: base, maximum: Layout.Maximum.notice,
                                                     geometry: geometry)
        }
        let text = copyNotice(1, .text), image = copyNotice(2, .image), many = copyNotice(3, .files(12))
        suite.expect(row(text, standard) == row(image, standard) && row(text, standard) == row(many, standard),
                     "copy after copy, the capsule holds its width")
        let bare = NotchOfficeMoments.capsuleCopyRow(text.office!, title: text.title, detail: text.detail,
                                                     geometry: standard)
        let slot = NotchOfficeMoments.captionWidth(NotchOfficeMoments.widest(NotchOfficeMoments.copyCaptions) ?? "",
                                                   font: NotchOfficeMoments.stripCaptionFont)
        suite.expect(NotchOfficeMoments.capsuleCaption(text.office, content: bare, maximum: Layout.Maximum.notice,
                                                       geometry: standard) == "Copy that."
                     && row(text, standard) == bare + Layout.groupSpacing + slot,
                     "a standard capsule reads the caption after the kind, in the room of the widest")
        suite.expect(NotchOfficeMoments.capsuleCaption(text.office, content: bare, maximum: Layout.Maximum.notice,
                                                       geometry: crowded) == nil
                     && row(text, crowded) == bare,
                     "where the menus leave no room, the caption is left out and the copy stays whole")
        suite.expect(bare > Layout.noticeContent(title: text.title, detail: text.detail, level: false),
                     "the capsule's copy row is the copier's, not the plain symbol's")
    }
}
