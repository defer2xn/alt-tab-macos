import Cocoa
import ScreenCaptureKit

@available(macOS 14.0, *)
class WindowCaptureScreenshots {
    // SCShareableContent.getExcludingDesktopWindows is expensive for the OS; we cache as much as possible.
    // Wrapped in ConcurrentArray because reads and writes happen from different operations on
    // BackgroundWork.screenshotsQueue, whose concurrency is selected by WindowCapturePolicy.
    static let cachedSCWindows = ConcurrentArray<SCWindow>()

    struct CaptureRequest {
        let window: Window
        let size: CGSize
        let scaleFactor: CGFloat
        let fullRes: Bool
    }

    static func oneTimeScreenshots(_ windowsToScreenshot: [Window], _ source: RefreshCausedBy, prioritizedIds: Set<CGWindowID>? = nil) {
        // Snapshot Window state on the main thread before hopping to screenshotsQueue. Windows.byWindowId,
        // Window.size, Window.screenId, Screens.all, and NSScreen.preferred are plain (lock-free) dictionaries
        // and mutable properties touched only on main; reading them from screenshotsQueue (8-way concurrent)
        // races with main-thread mutation and can corrupt the heap.
        // Trade-off: size is fixed at call time, so a window resized between snapshot and capture will be captured
        // at the old size. Acceptable because the next refresh will re-snapshot.
        // 仅「被预览窗口 + 导航相邻的预取窗口」需要全分辨率（见 WindowThumbnails.fullResWids）；其余截缩略图尺寸即可，
        // 省下成倍内存。fullResWids 在主线程维护，这里也在主线程读取，无竞态。
        let fullResWids = WindowThumbnails.fullResWids
        var requests = [CGWindowID: CaptureRequest]()
        for window in windowsToScreenshot {
            guard let wid = window.cgWindowId, let size = window.size else { continue }
            let scaleFactor: CGFloat
            if let screenId = window.screenId, let screen = Screens.all[screenId] {
                scaleFactor = screen.backingScaleFactor
            } else {
                scaleFactor = NSScreen.preferred.backingScaleFactor
            }
            requests[wid] = CaptureRequest(window: window, size: size, scaleFactor: scaleFactor, fullRes: fullResWids.contains(wid))
        }
        guard !requests.isEmpty else { return }
        let prioritized = prioritizedIds ?? []
        BackgroundWork.screenshotsQueue.addOperation {
            guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
            let (cachedWindows, notCachedWindows) = sortCachedAndNotCached(Array(requests.keys))
            Logger.debug { "cached:\(cachedWindows.map { $0.windowID }) notCached:\(notCachedWindows)" }
            // iterate prioritized windows first so they enqueue (and grab queue slots) ahead of the rest
            let sortedCached = cachedWindows.sorted { prioritized.contains($0.windowID) && !prioritized.contains($1.windowID) }
            let sortedNotCached = notCachedWindows.sorted { prioritized.contains($0) && !prioritized.contains($1) }
            handleCachedWindows(sortedCached, requests, source, prioritized)
            handleNotCachedWindows(sortedNotCached, requests, source, prioritized)
        }
    }

    private static func handleCachedWindows(_ cachedWindows: [SCWindow], _ requests: [CGWindowID: CaptureRequest], _ source: RefreshCausedBy, _ prioritized: Set<CGWindowID>) {
        guard !cachedWindows.isEmpty else { return }
        for cachedWindow in cachedWindows {
            guard let request = requests[cachedWindow.windowID] else { continue }
            oneTimeCapture(cachedWindow, request, source, prioritized.contains(cachedWindow.windowID))
        }
    }

    private static func handleNotCachedWindows(_ notCachedWindows: [CGWindowID], _ requests: [CGWindowID: CaptureRequest], _ source: RefreshCausedBy, _ prioritized: Set<CGWindowID>) {
        guard !notCachedWindows.isEmpty else { return }
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { shareableContent, error in
            guard let shareableContent, error == nil else { Logger.error { "\(shareableContent == nil) \(error)" }; return }
            guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
            // this callback is executed on an undetermined queue; we move execution to screenshotsQueue
            BackgroundWork.screenshotsQueue.addOperation {
                cachedSCWindows.withLock { $0 = shareableContent.windows }
                guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
                // O(N) 一次性建 wid→SCWindow 索引，下方循环 O(1) 查询；保留首个匹配以等价 first { ... } 语义
                let scWindowsByWid = Dictionary(shareableContent.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
                for notCachedWindow in notCachedWindows {
                    guard let request = requests[notCachedWindow] else { continue }
                    if let cachedWindow = scWindowsByWid[notCachedWindow] {
                        oneTimeCapture(cachedWindow, request, source, prioritized.contains(notCachedWindow))
                    } else {
                        Logger.debug { "wid:\(notCachedWindow) was not found in SCShareableContent windows" }
                    }
                }
            }
        }
    }

    private static func sortCachedAndNotCached(_ windows: [CGWindowID]) -> ([SCWindow], [CGWindowID]) {
        // 锁内只做 O(1) 的 Array COW 快照，立刻释放锁；O(N) 的 dict 构建和 O(M) 查询放锁外，避免阻塞其它截图回调写 cache
        let snapshot = cachedSCWindows.withLock { $0 }
        let scWindowsByWid = Dictionary(snapshot.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        var cachedWindows = [SCWindow]()
        var notCachedWindows = [CGWindowID]()
        for window in windows {
            if let cachedWindow = scWindowsByWid[window] {
                cachedWindows.append(cachedWindow)
            } else {
                notCachedWindows.append(window)
            }
        }
        return (cachedWindows, notCachedWindows)
    }

    private static func oneTimeCapture(_ scWindow: SCWindow, _ request: CaptureRequest, _ source: RefreshCausedBy, _ isPrioritized: Bool = false) {
        let size = request.size
        let scaleFactor = request.scaleFactor
        let fullRes = request.fullRes // 值类型，单独取出避免在内层 completion 强引用 request（保住 [weak window]）
        // 全分辨率补截只服务被预览的那个窗口，必须和同一 wid 的缩略图截图分用不同的节流键：
        // show/导航时整批窗口刚按缩略图尺寸截过，占用了 "capture-wid-<wid>" 的 200ms 配额；
        // 若全分辨率补截共用该键，会被 scheduleTail 推迟最多 200ms，预览就停在缩略图重采样的模糊态。
        // 独立键仍对全分辨率截图自身限频 200ms，不会因此连发而冲击 OS 截图调用。
        let throttleKey = fullRes ? "capture-wid-\(scWindow.windowID)-fullRes" : "capture-wid-\(scWindow.windowID)"
        // [weak window] avoids keeping a closed Window alive while the capture is queued or in-flight with the OS
        Applications.screenshotThrottler.throttleOrProceed(key: throttleKey, queue: BackgroundWork.screenshotsQueue, priority: isPrioritized ? .high : .normal) { [weak window = request.window] in
            guard !App.isTerminating, !ScreenLockEvents.isScreenLocked, let window else { return }
            let config = SCStreamConfiguration.forWindow(scWindow, size, scaleFactor, false, fullRes)
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            ActiveWindowCaptures.increment()
            SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config) { [weak window] sampleBuffer, error in
                ActiveWindowCaptures.decrement()
                guard let window else { return }
                guard let sampleBuffer, error == nil else { Logger.error { "\(window.debugId) \(sampleBuffer == nil) \(error)" }; return }
                guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
                guard let pixelBuffer = sampleBuffer.pixelBuffer() ?? sampleBuffer.imageBuffer else { Logger.error { "\(window.debugId) no pixelBuffer" }; return }
                DispatchQueue.main.async {
                    guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
                    window.refreshThumbnail(.pixelBuffer(pixelBuffer), fullRes)
                }
            }
        }
    }
}

class WindowCaptureScreenshotsPrivateApi {
    struct CaptureRequest {
        let window: Window
        let wid: CGWindowID
        let fullRes: Bool
    }

    static func oneTimeScreenshots(_ eligibleWindows: [Window], _ source: RefreshCausedBy, prioritizedIds: Set<CGWindowID>? = nil) {
        let prioritized = prioritizedIds ?? []
        let fullResWids = WindowThumbnails.fullResWids
        // iterate prioritized windows first so they enqueue (and grab queue slots) ahead of the rest
        let requests = eligibleWindows.compactMap { window -> CaptureRequest? in
            guard let wid = window.cgWindowId else { return nil }
            return CaptureRequest(window: window, wid: wid, fullRes: fullResWids.contains(wid))
        }
        let sorted = requests.sorted { a, b in
            prioritized.contains(a.wid) && !prioritized.contains(b.wid)
        }
        for request in sorted {
            let wid = request.wid
            let fullRes = request.fullRes
            let isPrioritized = prioritized.contains(wid)
            let throttleKey = fullRes ? "capture-wid-\(wid)-fullRes" : "capture-wid-\(wid)"
            Applications.screenshotThrottler.throttleOrProceed(key: throttleKey, queue: BackgroundWork.screenshotsQueue, priority: isPrioritized ? .high : .normal) { [weak window = request.window] in
                guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
                guard let window, let cgImage = oneTimeCapture(wid, fullRes) else { return }
                guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
                DispatchQueue.main.async { [weak window] in
                    guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
                    window?.refreshThumbnail(.cgImage(cgImage), fullRes)
                }
            }
        }
    }

    private static func oneTimeCapture(_ wid: CGWindowID, _ fullRes: Bool) -> CGImage? {
        guard !App.isTerminating, !ScreenLockEvents.isScreenLocked else { return nil }
        // we use CGSHWCaptureWindowList because it can screenshot minimized windows, which CGWindowListCreateImage can't
        var windowId_ = wid
        ActiveWindowCaptures.increment()
        let resolution: CGSWindowCaptureOptions = fullRes ? .bestResolution : .nominalResolution
        let list = CGSHWCaptureWindowList(CGS_CONNECTION, &windowId_, 1, [.ignoreGlobalClipShape, resolution, .fullSize]).takeRetainedValue() as! [CGImage]
        ActiveWindowCaptures.decrement()
        return list.first
    }
}

// @available(macOS 12.3, *)
// class WindowCaptureVideos {
//     private static var streams = [CGWindowID: SCStream]()
//     private static var streamOutputs = [CGWindowID: StreamOutput]()
//     // SCStream.backgroundColor is [unowned], so we must keep own these variables
//     static let scStreamBackgroundColorDark = NSColor(white: 0.23, alpha: 1).cgColor
//     static let scStreamBackgroundColorLight = NSColor.white.cgColor
//
//     static func startCapturing(_ windowsWhichMayHaveChanged: [Window]) {
//         let windowsToShow = Set<CGWindowID>(Windows.list.filter { !$0.isWindowlessApp && $0.shouldShowTheUser }.compactMap { $0.cgWindowId })
//         let windowsAlreadyStreaming = Set<CGWindowID>(streams.keys)
//         let windowsToStop = windowsAlreadyStreaming.subtracting(windowsToShow)
//         stopCaptures(windowsToStop)
//         let windowsToStart = windowsToShow.subtracting(windowsAlreadyStreaming)
//         let windowsWhichMayHaveChanged_ = windowsWhichMayHaveChanged.compactMap { $0.cgWindowId }
//         if !windowsToStart.isEmpty || !windowsWhichMayHaveChanged_.isEmpty {
//             SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { shareableContent, error in
//                 guard let shareableContent, error == nil else {
//                     Logger.error { "\(shareableContent == nil) \(error)" }
//                     return
//                 }
//                 // this callback is executed on an undetermined queue
//                 // we move execution to main-thread to avoid races with starting/stopping streams and the app being shown/hidden
//                 DispatchQueue.main.async {
//                     guard SwitcherSession.isActive else { return }
//                     startCaptures(windowsToStart, shareableContent)
//                     updateCaptures(windowsWhichMayHaveChanged_, shareableContent)
//                     Logger.debug { streams.keys }
//                 }
//             }
//         }
//     }
//
//     static func stopCapturing() {
//         Logger.debug { streams.keys }
//         for stream in streams.values {
//             stream.stopCapture()
//         }
//         streams.removeAll()
//         streamOutputs.removeAll()
//     }
//
//     private static func updateCaptures(_ windowsWhichMayHaveChanged: [CGWindowID], _ shareableContent: SCShareableContent) {
//         for wid in windowsWhichMayHaveChanged {
//             if let stream = streams[wid],
//                let scWindow = shareableContent.windows.first(where: { $0.windowID == wid }) {
//                 stream.updateConfiguration(SCStreamConfiguration.forWindow(scWindow, true)) { error in
//                     if let error { Logger.error { error } }
//                 }
//             }
//         }
//     }
//
//     private static func startCaptures(_ windowsToStart: Set<CGWindowID>, _ shareableContent: SCShareableContent) {
//         for wid in windowsToStart {
//             if let scWindow = shareableContent.windows.first(where: { $0.windowID == wid }) {
//                 startCapture(scWindow)
//             }
//         }
//     }
//
//
//     private static func startCapture(_ window: SCWindow) {
//         let wid = window.windowID
//         let output = StreamOutput(wid)
//         let config = SCStreamConfiguration.forWindow(window, true)
//         let filter = SCContentFilter(desktopIndependentWindow: window)
//         let stream = SCStream(filter: filter, configuration: config, delegate: output)
//         do {
//             try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: BackgroundWork.screenshotsQueue.strongUnderlyingQueue)
//             stream.startCapture { error in
//                 if let error { Logger.error { error } }
//             }
//             streams[wid] = stream
//             streamOutputs[wid] = output
//         } catch {
//             Logger.error { error }
//         }
//     }
//
//     private static func stopCaptures(_ windowsToStop: Set<CGWindowID>) {
//         for wid in windowsToStop {
//             stopCapture(wid)
//         }
//     }
//
//     private static func stopCapture(_ wid: CGWindowID) {
//         if let stream = streams[wid] {
//             stream.stopCapture()
//             streams.removeValue(forKey: wid)
//             streamOutputs.removeValue(forKey: wid)
//         }
//     }
//
//     class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
//         let wid: CGWindowID
//
//         init(_ wid: CGWindowID) {
//             self.wid = wid
//         }
//
//         // from SCStreamOutput; handle captured samples
//         func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
//             BackgroundWork.screenshotsQueue.trackCallbacks {
//                 if sampleBuffer.isValid,
//                    let pixelBuffer = sampleBuffer.pixelBuffer() {
//                     DispatchQueue.main.async {
//                         if let window = (Windows.list.first { $0.cgWindowId == self.wid }) {
//                             window.refreshThumbnail(.pixelBuffer(pixelBuffer))
//                         }
//                     }
//                 }
//             }
//         }
//
//         // from SCStreamDelegate; handle errors when opening a stream
//         func stream(_ stream: SCStream, didStopWithError error: any Error) {
//             BackgroundWork.screenshotsQueue.trackCallbacks {
//                 Logger.error { error }
//             }
//         }
//     }
// }

@available(macOS 12.3, *)
extension SCStreamConfiguration {
    // size/scaleFactor are snapshotted on the main thread by the caller; we do not touch Window state here
    // (Window properties are mutated on main and would race with this background work).
    static func forWindow(_ scWindow: SCWindow, _ size: CGSize, _ scaleFactor: CGFloat, _ video: Bool, _ fullRes: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.setWindowSize(size, scaleFactor, fullRes)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        // if video {
        //     config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(60))
        //     config.queueDepth = 8
        //     // ~60% memory reduction compared to kCVPixelFormatType_32BGRA
        //     config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        //     // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange doesn't have transparency, so we end up with an opaque background color around the window corners
        //     // we use a background color that try and hide these corners as much as possible
        //     config.backgroundColor = Appearance.currentTheme == .dark ? WindowCaptureVideos.scStreamBackgroundColorDark : WindowCaptureVideos.scStreamBackgroundColorLight
        // }
        // config.scalesToFit = true
        return config
    }

    private func setWindowSize(_ size: CGSize, _ scaleFactor: CGFloat, _ fullRes: Bool) {
        // window.size is the logical size and doesn't change with scaleFactor. We need to correct for this as we need to capture more or less pixels depending on DPI.
        let originalSize = NSSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        guard originalSize.width > 0, originalSize.height > 0 else { return }
        // 全分辨率仅用于「正被预览的那个窗口」（预览面板按窗口真实逻辑尺寸 1:1 显示，需要 logical×scale 的像素）。
        // 其余窗口只在 tiles 里按缩略图尺寸显示，截缩略图尺寸即可，省下成倍 IOSurface 内存。由调用方按 previewedWid 决定。
        if fullRes {
            width = Int(originalSize.width)
            height = Int(originalSize.height)
        } else {
            // capture screenshots as small as needed for the thumbnails
            let maxSize = TilesPanel.maxPossibleThumbnailSize
            guard maxSize.width > 0, maxSize.height > 0 else { return }
            let scale = min(1.0, maxSize.width / originalSize.width, maxSize.height / originalSize.height)
            width = Int((originalSize.width * scale).rounded())
            height = Int((originalSize.height * scale).rounded())
        }
    }
}

extension CMSampleBuffer {
    @available(macOS 12.3, *)
    func pixelBuffer() -> CVPixelBuffer? {
        if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let attachments = attachmentsArray.first,
           let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRawValue),
           status == .complete || status == .started { // new frame was generated
            return imageBuffer
        }
        return nil
    }

    @available(macOS 12.3, *)
    func metalTexture(_ device: MTLDevice) -> MTLTexture? {
        guard let pixelBuffer = pixelBuffer(),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            mipmapped: false
        )
        return device.makeTexture(descriptor: desc, iosurface: surface, plane: 0)
    }
}

class ActiveWindowCaptures {
    private static var _count: Int32 = 0

    static func increment() { OSAtomicIncrement32(&_count) }
    static func decrement() { OSAtomicDecrement32(&_count) }
    static func value() -> Int { Int(OSAtomicAdd32(0, &_count)) }
}
