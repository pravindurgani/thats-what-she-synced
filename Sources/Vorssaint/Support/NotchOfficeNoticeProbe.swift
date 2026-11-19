// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import SwiftUI

/// `--office-notice-frames <folder>`: the Office edition's calendar notices
/// drawn by the window server as the closed island shows them (the island's
/// glow and the camera aside), so their look can be checked without waiting
/// for a meeting. Each sits a few seconds behind every window in the screen's
/// lower-left corner while it is captured; nothing is sent or saved but the
/// frames. Development builds only.
enum NotchOfficeNoticeProbe {
    static func runAndExit(folder: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.main else { print("OFFICE NOTICE FRAMES FAILED: no display"); exit(1) }
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cameraWidth = screen.auxiliaryTopRightArea.flatMap { right in
            screen.auxiliaryTopLeftArea.map { max(0, right.minX - $0.maxX) }
        } ?? 0
        var measurements = NotchMenuBarMeasurements()
        let geometry = NotchGeometry(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            cameraWidth: cameraWidth, menuBarHeight: measurements.height(
                displayID: screen.notchDisplayID, frame: screen.frame, visibleTop: screen.visibleFrame.maxY,
                scale: screen.backingScaleFactor, statusBarThickness: NSStatusBar.system.thickness))
        let start = Date().addingTimeInterval(300)
        var event = NotchCalendarEvent(id: "probe", title: "Adverity Check-in", calendar: "Work", start: start,
                                       end: start.addingTimeInterval(1800), allDay: false, location: "")
        event.color = NotchCalendarColor(red: 0.35, green: 0.65, blue: 1)
        let locale = L10n.shared.language.formattingLocale()
        let notices: [(String, NotchNotice)] = [
            ("meeting-soon", NotchNotice(event: .calendar, title: event.title,
                                         detail: NotchOfficeMoments.meetingHours(event, locale: locale),
                                         symbol: "calendar", office: NotchOfficeMoments.meetingSoonCue(event, language: .enUS))),
            ("meeting-now", NotchNotice(event: .calendar, title: event.title,
                                        detail: NotchOfficeMoments.meetingHours(event, locale: locale),
                                        symbol: "calendar", office: NotchOfficeMoments.meetingCue(event, language: .enUS))),
        ]
        var lines: [String] = []
        var failed = false
        for (name, notice) in notices {
            let size = geometry.noticeSize(wings: notice.wings(in: geometry))
            // The surface slides toward its wider wing while the words keep
            // their place beside the camera, as the island presents it.
            let shift = geometry.noticeShift(notice.wings(in: geometry))
            let canvas = CGSize(width: size.width + abs(shift) * 2, height: size.height)
            // Drawn by the window server as on the island, in the screen's
            // lower corner behind every other window, and captured alone.
            let window = CaptureWindow(size: canvas)
            window.setFrameOrigin(CGPoint(x: screen.frame.minX, y: screen.frame.minY))
            let host = NSHostingView(rootView: NotchNoticeView(notice: notice, geometry: geometry)
                .frame(width: size.width, height: size.height).background(Color.black.offset(x: shift))
                .frame(width: canvas.width, height: canvas.height))
            host.frame = CGRect(origin: .zero, size: canvas)
            host.wantsLayer = true
            window.contentView = host
            window.orderBack(nil)
            // Every arrival, the caption's beat included, has settled.
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 2.5))
            let url = root.appendingPathComponent("\(name).png")
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
            do {
                try capture.run()
                capture.waitUntilExit()
            } catch {
                lines.append("\(name): screencapture did not start: \(error.localizedDescription)")
            }
            let captured = capture.terminationReason == .exit && capture.terminationStatus == 0
                && FileManager.default.fileExists(atPath: url.path)
            if !captured { failed = true }
            lines.append("\(name): \(Int(size.width))x\(Int(size.height)) pt, " + (captured ? url.path : "not captured"))
            window.close()
        }
        print("OFFICE NOTICE FRAMES\n" + lines.joined(separator: "\n"))
        exit(failed ? 1 : 0)
    }

    /// A borderless window that tells the views it is on screen, so they
    /// play as on the island, and that the window server can capture alone.
    private final class CaptureWindow: NSWindow {
        override var isVisible: Bool { true }
        override var occlusionState: NSWindow.OcclusionState { [.visible] }

        init(size: CGSize) {
            super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered,
                       defer: false)
            isReleasedWhenClosed = false
            ignoresMouseEvents = true
            hasShadow = false
            backgroundColor = .clear
            isOpaque = false
        }
    }
}
#endif
