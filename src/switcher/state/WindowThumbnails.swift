import Cocoa

/// Off-main-thread screenshot capture for window thumbnails, plus the
/// "preview the selected window" overlay shown next to the switcher panel.
enum WindowThumbnails {
    /// 当前正被 PreviewPanel 预览的窗口 wid（启用预览时 = 选中窗口）。只有它需要全分辨率截图：
    /// tiles 在 titles/appIcons 风格根本不显示缩略图，thumbnails 风格也只按缩略图尺寸显示，全分辨率仅服务预览面板。
    /// 主线程读写；oneTimeScreenshots（主线程快照）据此让批量截图只给它截全分辨率、其余截缩略图尺寸，省下成倍内存。
    static var previewedWid: CGWindowID?

    static func previewSelectedIfNeeded() {
        let selected: Window?
        if let session = SwitcherSession.current, ScreenRecordingPermission.status == .granted,
           Preferences.effectivePreviewSelectedWindow(session.shortcutIndex), !Preferences.onlyShowApplications(session.shortcutIndex),
           TilesPanel.shared.isKeyWindow {
            selected = Windows.selectedWindow()
        } else {
            selected = nil
        }
        let newPreviewedWid = selected?.cgWindowId
        if newPreviewedWid != previewedWid {
            previewedWid = newPreviewedWid
            // 被预览窗口变化时补一次全分辨率截图；完成后 refreshThumbnail→PreviewPanel.updateIfShowing 让预览变清晰。
            // 不会回环：refreshThumbnail 只刷新显示、不触发截图，且本判断仅在 wid 变化时进入。
            if let selected, let id = newPreviewedWid {
                refreshAsync([selected], .refreshOnlyThumbnailsAfterShowUi, prioritizedIds: [id])
            }
        }
        if let selected, let id = selected.cgWindowId, let thumbnail = selected.thumbnail,
           let position = selected.position, let size = selected.size {
            PreviewPanel.show(id, thumbnail, position, size)
        } else {
            PreviewPanel.shared.orderOut(nil)
        }
    }

    // dispatch screenshot requests off the main-thread, then wait for completion
    static func refreshAsync(_ windows: [Window], _ source: RefreshCausedBy, windowRemoved: Bool = false, prioritizedIds: Set<CGWindowID>? = nil) {
        let shortcutIndex = SwitcherSession.activeShortcutIndex
        guard (!windows.isEmpty || windowRemoved) && ScreenRecordingPermission.status == .granted
               && !Preferences.onlyShowApplications(shortcutIndex)
               && (!Appearance.hideThumbnails || Preferences.effectivePreviewSelectedWindow(shortcutIndex))
               && (Preferences.captureWindowsInBackground || SwitcherSession.isActive) else { return }
        var eligibleWindows = [Window]()
        for window in windows {
            if !window.isWindowlessApp, let cgWindowId = window.cgWindowId, cgWindowId != CGWindowID(bitPattern: -1) {
                eligibleWindows.append(window)
            }
        }
        guard (!eligibleWindows.isEmpty || windowRemoved) else { return }
        if #available(macOS 14.0, *),
           // mitigate macOS 15 bugs with ScreenCapture Kit (see https://github.com/lwouis/alt-tab-macos/issues/5190)
           ProcessInfo.processInfo.operatingSystemVersion.majorVersion != 15 {
            WindowCaptureScreenshots.oneTimeScreenshots(eligibleWindows, source, prioritizedIds: prioritizedIds)
        } else {
            WindowCaptureScreenshotsPrivateApi.oneTimeScreenshots(eligibleWindows, source, prioritizedIds: prioritizedIds)
        }
    }
}
