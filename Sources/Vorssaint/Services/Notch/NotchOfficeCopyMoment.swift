// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// What a copy held, in a word. Read from the entry's kind and, for text,
/// only whether it is one web address: the island names a copy without ever
/// showing it, since it may be a password.
enum NotchOfficeCopyKind: Equatable {
    case text, link, image
    case files(Int)
}

/// One copy on the island: its number this launch, which picks its caption
/// and replays the copier, what it held, and the widest word its kind can
/// take, whose room the far side keeps.
struct NotchOfficeCopy: Equatable {
    let take: Int
    let kind: NotchOfficeCopyKind
    let widestSummary: String
}

/// How the copier answers a copy, given when its last run began.
enum NotchOfficeCopyRun: Equatable {
    /// The whole motion: the scan and the sheet, as a first copy plays them.
    case full
    /// A copy while the last still plays: the same motion from the start,
    /// quicker, over the sheet already out.
    case quick
    /// A copy hard on the last one's heels, as one copy written twice: the
    /// run already playing stands for both.
    case absorbed
}

/// "The copier": a copy runs a desk photocopier's scan light across its glass
/// and slides a sheet out, beside "Copied" and a caption from the copy room.
/// The far side names what was copied in a word, never the copy itself.
extension NotchOfficeMoments {
    // MARK: Captions

    /// One per copy, in turn, so a run of copies reads down the list.
    static let copyCaptions = ["Copy that.", "In triplicate.", "Filed under: important.", "Collated and stapled.",
                               "Paper trail started."]

    /// The caption for the `take`th copy this launch, counting from one.
    static func copyCaption(take: Int) -> String {
        let count = copyCaptions.count
        return copyCaptions[((take - 1) % count + count) % count]
    }

    static func copyCue(take: Int, kind: NotchOfficeCopyKind, language: AppLanguage) -> NotchOfficeCue {
        let captions = showsCaptions(in: language)
        let widestSummary = copySummaries(language: language).max { copySummaryWidth($0) < copySummaryWidth($1) } ?? ""
        return NotchOfficeCue(kind: .copy, caption: captions ? copyCaption(take: take) : nil,
                              widestCaption: captions ? widest(copyCaptions) : nil,
                              copy: NotchOfficeCopy(take: take, kind: kind, widestSummary: widestSummary))
    }

    // MARK: What was copied

    static func copyKind(_ entry: ClipboardHistoryEntry) -> NotchOfficeCopyKind {
        switch entry.kind {
        case .text: return isLink(entry.text) ? .link : .text
        case .image: return .image
        case .files: return .files(entry.filePaths.count)
        }
    }

    /// Text longer than this is never a link worth naming, and is not read through.
    static let linkLimit = 2048

    /// One web address and nothing else around it.
    static func isLink(_ text: String) -> Bool {
        guard text.utf8.count <= linkLimit else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// The copy's kind in a word, for the far side. The app has words of its
    /// own for an image and for several files in every language; text, a
    /// link and a single file are named in English only, and elsewhere keep
    /// the plain notice's "Clipboard".
    static func copySummary(_ kind: NotchOfficeCopyKind, language: AppLanguage) -> String {
        let strings = FeatureStrings.clipboard(language)
        let english = language == .enUS
        switch kind {
        case .text: return english ? "Text" : strings.title
        case .link: return english ? "Link" : strings.title
        case .image: return strings.imageEntryLabel
        case .files(let count):
            if count > 1 { return String(format: strings.fileCountFormat, count) }
            return english ? "File" : strings.title
        }
    }

    /// Every word the far side can show, files counted to two digits: its
    /// room is the widest, so text after an image never resizes the island.
    static func copySummaries(language: AppLanguage) -> [String] {
        [NotchOfficeCopyKind.text, .link, .image, .files(1), .files(88)].map { copySummary($0, language: language) }
    }

    // MARK: The copier's run

    /// The copier's whole motion: the scan crossing the glass on the song's
    /// even curve as the sheet springs out of the slot.
    static let copyRunLength: TimeInterval = 0.5
    /// Copies closer than this make one run.
    static let copyAbsorb: TimeInterval = 0.15
    /// A quick replay plays the same curves this much faster.
    static let copyQuickSpeed = 1.5
    /// Sheets left under the newest as copies pile up in one notice.
    static let copyPileLimit = 2

    static func copyRun(at now: TimeInterval, lastStart: TimeInterval?) -> NotchOfficeCopyRun {
        guard let lastStart, now >= lastStart else { return .full }
        let since = now - lastStart
        if since < copyAbsorb { return .absorbed }
        return since < copyRunLength ? .quick : .full
    }

    /// The sheets out once `take` comes out over `sheets`, oldest first:
    /// the newest on top, and under it a pile of at most `copyPileLimit`.
    static func copySheets(_ sheets: [Int], adding take: Int) -> [Int] {
        Array((sheets.filter { $0 != take } + [take]).suffix(copyPileLimit + 1))
    }

    // MARK: Measures

    /// The copier beside "Copied", at the boombox's scale.
    static let copier = CGSize(width: 22, height: 16)
    /// "Copied", in the family's title size: the real information comes first.
    static var copyTitleFont: NSFont { titleFont }
    /// The kind at the far side, as every moment's reading.
    static var copySummaryFont: NSFont { detailFont }

    static func copySummaryWidth(_ summary: String) -> CGFloat {
        ceil((summary as NSString).size(withAttributes: [.font: copySummaryFont]).width)
    }

    static func copyTitleWidth(_ title: String) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: copyTitleFont]).width)
    }

    /// What a copy's two sides hold beside the camera, before their insets:
    /// the copier and "Copied" with the widest caption under it on one, the
    /// widest kind on the other. Every copy measures alike, so a run of them
    /// never resizes the island.
    static func copyContent(_ cue: NotchOfficeCue, title: String,
                            detail: String) -> (leading: CGFloat, trailing: CGFloat) {
        let caption = (cue.widestCaption ?? cue.caption).map { captionWidth($0) } ?? 0
        let leading = copier.width + levelMarkGap + max(copyTitleWidth(title), caption)
        let trailing = max(copySummaryWidth(detail), cue.copy.map { copySummaryWidth($0.widestSummary) } ?? 0)
        return (leading, trailing)
    }

    /// A copy's sides beside the camera, inset from the island's ends as a
    /// level moment's are, so the copier stands where the boombox does.
    static func copyWings(_ cue: NotchOfficeCue, title: String, detail: String, inset: CGFloat) -> NotchNoticeWings {
        let content = copyContent(cue, title: title, detail: detail)
        return NotchNoticeWings(leading: ceil(inset + content.leading + levelAir),
                                trailing: ceil(inset + content.trailing + levelAir))
    }

    // MARK: In the capsule

    /// The copier, no taller than the capsule's body leaves it.
    static func capsuleCopierScale(_ geometry: NotchGeometry) -> CGFloat {
        min(1, capsuleLevelHeight(geometry) / copier.height)
    }

    static func capsuleCopierWidth(_ geometry: NotchGeometry) -> CGFloat {
        (copier.width * capsuleCopierScale(geometry)).rounded(.up)
    }

    /// The kind's room in the capsule: the widest it can show.
    static func capsuleCopySummaryWidth(_ cue: NotchOfficeCue, detail: String) -> CGFloat {
        let layout = NotchCapsuleLayout.self
        return max(layout.width(detail, font: layout.detailFont),
                   layout.width(cue.copy?.widestSummary ?? "", font: layout.detailFont))
    }

    /// A copy's row in the capsule, before its caption: the copier, "Copied"
    /// in the capsule's title size, as every capsule moment's title, and the
    /// kind in the room of the widest.
    static func capsuleCopyRow(_ cue: NotchOfficeCue, title: String, detail: String,
                               geometry: NotchGeometry) -> CGFloat {
        let layout = NotchCapsuleLayout.self
        return capsuleCopierWidth(geometry) + layout.spacing + layout.width(title, font: layout.titleFont)
            + layout.groupSpacing + capsuleCopySummaryWidth(cue, detail: detail)
    }
}
