import Cocoa

/// Off-main-thread screenshot capture for window thumbnails, plus the
/// "preview the selected window" overlay shown next to the switcher panel.
enum WindowThumbnails {
    /// 当前正被 PreviewPanel 预览的窗口 wid（启用预览时 = 选中窗口）。仅它会显示在预览面板，
    /// refreshThumbnail 据此丢弃晚到的低分辨率帧，避免把已清晰的预览刷糊。主线程读写。
    static var previewedWid: CGWindowID?
    /// 允许按全分辨率截图的窗口集合 = 被预览窗口 + 导航相邻的预取窗口。oneTimeScreenshots（主线程快照）
    /// 据此决定哪些截全分辨率、其余截缩略图尺寸。集合上界 = 1 + 2×radius，内存仍受控。主线程读写。
    static var fullResWids = Set<CGWindowID>()

    @discardableResult
    static func previewSelectedIfNeeded() -> Set<CGWindowID> {
        let selected: Window?
        if let session = SwitcherSession.current, ScreenRecordingPermission.status == .granted,
           Preferences.effectivePreviewSelectedWindow(session.shortcutIndex),
           TilesPanel.shared.isKeyWindow {
            selected = Windows.selectedWindow()
        } else {
            selected = nil
        }
        let newPreviewedWid = selected?.cgWindowId
        // 预取相邻窗口：被预览窗口 + 导航方向前后各若干个窗口都按全分辨率截，快速连切到相邻窗口时
        // 其全分辨率已就绪，不必等按需补截，消除瞬间模糊。
        let prefetch = selected != nil ? Windows.neighborWindowsForPreviewPrefetch() : []
        var newFullResWids = Set<CGWindowID>()
        var scheduledWids = Set<CGWindowID>()
        if let id = newPreviewedWid { newFullResWids.insert(id) }
        for w in prefetch { if let wid = w.cgWindowId { newFullResWids.insert(wid) } }
        if newPreviewedWid != previewedWid || newFullResWids != fullResWids {
            previewedWid = newPreviewedWid
            fullResWids = newFullResWids
            // 选中窗口优先级最高（当前就在显示），相邻窗口随后预取。完成后 refreshThumbnail→PreviewPanel.updateIfShowing 让预览变清晰。
            // 不会回环：refreshThumbnail 只刷新显示、不触发截图。重复请求由 screenshotThrottler 的 -fullRes 键限频去重。
            if let selected, let id = newPreviewedWid {
                refreshAsync([selected] + prefetch, .refreshOnlyThumbnailsAfterShowUi, prioritizedIds: [id])
                scheduledWids = newFullResWids
            }
        }
        if let selected, let id = selected.cgWindowId, let thumbnail = selected.thumbnail,
           let position = selected.position, let size = selected.size {
            PreviewPanel.show(id, thumbnail, position, size)
        } else {
            PreviewPanel.shared.orderOut(nil)
        }
        return scheduledWids
    }

    // dispatch screenshot requests off the main-thread, then wait for completion
    static func refreshAsync(_ windows: [Window], _ source: RefreshCausedBy, windowRemoved: Bool = false, prioritizedIds: Set<CGWindowID>? = nil) {
        let shortcutIndex = SwitcherSession.activeShortcutIndex
        let osMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        guard (!windows.isEmpty || windowRemoved) && ScreenRecordingPermission.status == .granted
               && !ScreenLockEvents.isScreenLocked
               && (!Appearance.hideThumbnails || Preferences.effectivePreviewSelectedWindow(shortcutIndex))
               && WindowCapturePolicy.shouldCapture(userAllowsBackground: Preferences.captureWindowsInBackground,
                   switcherIsActive: SwitcherSession.isActive, osMajorVersion: osMajorVersion) else { return }
        var eligibleWindows = [Window]()
        let previewTargetWids = fullResWids
        for window in windows {
            if !window.isWindowlessApp, let cgWindowId = window.cgWindowId, cgWindowId != CGWindowID(bitPattern: -1),
               WindowCapturePolicy.shouldCaptureWindow(showsThumbnails: !Appearance.hideThumbnails, isPreviewTarget: previewTargetWids.contains(cgWindowId)) {
                eligibleWindows.append(window)
            }
        }
        guard (!eligibleWindows.isEmpty || windowRemoved) else { return }
        if #available(macOS 14.0, *), WindowCapturePolicy.backend(osMajorVersion: osMajorVersion) == .screenCaptureKit {
            WindowCaptureScreenshots.oneTimeScreenshots(eligibleWindows, source, prioritizedIds: prioritizedIds)
        } else {
            WindowCaptureScreenshotsPrivateApi.oneTimeScreenshots(eligibleWindows, source, prioritizedIds: prioritizedIds)
        }
    }
}
