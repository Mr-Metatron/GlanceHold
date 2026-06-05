import XCTest
@testable import GlanceHold

final class CameraPermissionClientTests: XCTestCase {
    func testUndeterminedPermissionRequestsAccessExactlyOnceFromEnableMonitoring() async {
        let provider = FakePermissionProvider(status: .undetermined, requestResult: true)
        var state = GlanceHoldState()

        XCTAssertEqual(provider.requestCount, 0)

        await state.enableMonitoring(permissionProvider: provider)

        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(state.status.visibleTitle, "Ready After Calibration")
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testDeniedPermissionBecomesDeniedRecoveryWithoutActiveMonitoring() async {
        let provider = FakePermissionProvider(status: .denied, requestResult: false)
        var state = GlanceHoldState()

        await state.enableMonitoring(permissionProvider: provider)

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(state.status.visibleTitle, "Camera Permission Denied")
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testRestrictedPermissionBecomesDeniedRecoveryWithoutActiveMonitoring() async {
        let provider = FakePermissionProvider(status: .restricted, requestResult: false)
        var state = GlanceHoldState()

        await state.enableMonitoring(permissionProvider: provider)

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(state.status.visibleTitle, "Camera Permission Denied")
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testUndeterminedPermissionDeniedByUserBecomesDeniedRecoveryWithoutActiveMonitoring() async {
        let provider = FakePermissionProvider(status: .undetermined, requestResult: false)
        var state = GlanceHoldState()

        await state.enableMonitoring(permissionProvider: provider)

        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(state.status.visibleTitle, "Camera Permission Denied")
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testGrantedPermissionProceedsToReadyAfterCalibration() async {
        let provider = FakePermissionProvider(status: .granted, requestResult: true)
        var state = GlanceHoldState()

        await state.enableMonitoring(permissionProvider: provider)

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(state.status.visibleTitle, "Ready After Calibration")
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testLaunchAndPassiveRenderingDoNotRequestCameraPermission() {
        let provider = FakePermissionProvider(status: .undetermined, requestResult: true)
        _ = GlanceHoldState()

        XCTAssertEqual(provider.requestCount, 0)
    }
}

private final class FakePermissionProvider: CameraPermissionProviding {
    private let status: CameraPermissionStatus
    private let requestResult: Bool
    private(set) var requestCount = 0

    init(status: CameraPermissionStatus, requestResult: Bool) {
        self.status = status
        self.requestResult = requestResult
    }

    func authorizationStatus() -> CameraPermissionStatus {
        status
    }

    func requestAccess() async -> Bool {
        requestCount += 1
        return requestResult
    }
}
