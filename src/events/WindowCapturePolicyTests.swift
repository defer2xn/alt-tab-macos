import XCTest

final class WindowCapturePolicyTests: XCTestCase {
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
}
