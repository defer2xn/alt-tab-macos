import XCTest

final class WindowCapturePolicyTests: XCTestCase {
    func testScreenCaptureKitIsLimitedToValidatedMacOSVersion() {
        XCTAssertEqual(WindowCapturePolicy.backend(osMajorVersion: 15), .privateApi)
        XCTAssertEqual(WindowCapturePolicy.backend(osMajorVersion: 26), .screenCaptureKit)
        XCTAssertEqual(WindowCapturePolicy.backend(osMajorVersion: 27), .privateApi)
        XCTAssertEqual(WindowCapturePolicy.backend(osMajorVersion: 28), .privateApi)
    }

    func testUnvalidatedMacOSDisablesBackgroundCapture() {
        XCTAssertFalse(WindowCapturePolicy.shouldCapture(userAllowsBackground: true, switcherIsActive: false, osMajorVersion: 27))
        XCTAssertTrue(WindowCapturePolicy.shouldCapture(userAllowsBackground: true, switcherIsActive: false, osMajorVersion: 26))
        XCTAssertTrue(WindowCapturePolicy.shouldCapture(userAllowsBackground: false, switcherIsActive: true, osMajorVersion: 27))
    }

    func testUnvalidatedMacOSLimitsCaptureConcurrency() {
        XCTAssertEqual(WindowCapturePolicy.maxConcurrentOperations(osMajorVersion: 26), 8)
        XCTAssertEqual(WindowCapturePolicy.maxConcurrentOperations(osMajorVersion: 27), 2)
        XCTAssertEqual(WindowCapturePolicy.maxConcurrentOperations(osMajorVersion: 28), 2)
    }

    func testUnvalidatedMacOSAvoidsShareableContentPermissionProbe() {
        XCTAssertFalse(WindowCapturePolicy.shouldUsePreflightPermissionCheck(osMajorVersion: 26))
        XCTAssertTrue(WindowCapturePolicy.shouldUsePreflightPermissionCheck(osMajorVersion: 27))
        XCTAssertTrue(WindowCapturePolicy.shouldUsePreflightPermissionCheck(osMajorVersion: 28))
    }

    func testHiddenThumbnailsOnlyCapturePreviewTargets() {
        XCTAssertFalse(WindowCapturePolicy.shouldCaptureWindow(showsThumbnails: false, isPreviewTarget: false))
        XCTAssertTrue(WindowCapturePolicy.shouldCaptureWindow(showsThumbnails: false, isPreviewTarget: true))
        XCTAssertTrue(WindowCapturePolicy.shouldCaptureWindow(showsThumbnails: true, isPreviewTarget: false))
    }

    func testAlreadyScheduledPreviewIsExcludedFromFollowUpCapture() {
        let scheduled: Set<UInt32> = [11, 22]
        XCTAssertFalse(WindowCapturePolicy.shouldScheduleAdditionalCapture(windowId: 11, alreadyScheduled: scheduled))
        XCTAssertTrue(WindowCapturePolicy.shouldScheduleAdditionalCapture(windowId: 33, alreadyScheduled: scheduled))
        XCTAssertTrue(WindowCapturePolicy.shouldScheduleAdditionalCapture(windowId: nil, alreadyScheduled: scheduled))
    }
}
