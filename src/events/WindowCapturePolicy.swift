enum WindowCapturePolicy {
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
}
