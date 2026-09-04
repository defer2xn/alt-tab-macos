enum WindowCaptureBackend: Equatable {
    case screenCaptureKit
    case privateApi
}

enum WindowCapturePolicy {
    static let validatedScreenCaptureKitMajorVersion = 26

    static func backend(osMajorVersion: Int) -> WindowCaptureBackend {
        osMajorVersion == validatedScreenCaptureKitMajorVersion ? .screenCaptureKit : .privateApi
    }

    static func shouldCapture(userAllowsBackground: Bool, switcherIsActive: Bool, osMajorVersion: Int) -> Bool {
        switcherIsActive || (userAllowsBackground && osMajorVersion < 27)
    }

    static func maxConcurrentOperations(osMajorVersion: Int) -> Int {
        osMajorVersion >= 27 ? 2 : 8
    }

    static func shouldUsePreflightPermissionCheck(osMajorVersion: Int) -> Bool {
        osMajorVersion >= 27
    }

    static func shouldCaptureWindow(showsThumbnails: Bool, isPreviewTarget: Bool) -> Bool {
        showsThumbnails || isPreviewTarget
    }

    static func shouldScheduleAdditionalCapture(windowId: UInt32?, alreadyScheduled: Set<UInt32>) -> Bool {
        guard let windowId else { return true }
        return !alreadyScheduled.contains(windowId)
    }
}
