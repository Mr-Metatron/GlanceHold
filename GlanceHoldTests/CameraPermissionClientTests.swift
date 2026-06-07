import XCTest
@testable import GlanceHold

final class CameraPermissionClientTests: XCTestCase {
    func testUndeterminedPermissionRequestsAccessExactlyOnceFromEnableMonitoring() async {
        let provider = FakePermissionProvider(status: .undetermined, requestResult: true)
        var state = GlanceHoldState()

        XCTAssertEqual(provider.requestCount, 0)

        await state.enableMonitoring(permissionProvider: provider)

        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(state.status.visibleTitle, GlanceHoldStrings.text(.monitoringNeedsCalibrationTitle))
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testDeniedPermissionBecomesDeniedRecoveryWithoutActiveMonitoring() async {
        let provider = FakePermissionProvider(status: .denied, requestResult: false)
        var state = GlanceHoldState()

        await state.enableMonitoring(permissionProvider: provider)

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(state.status.visibleTitle, GlanceHoldStrings.text(.monitoringCameraPermissionDeniedTitle))
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testRestrictedPermissionBecomesDeniedRecoveryWithoutActiveMonitoring() async {
        let provider = FakePermissionProvider(status: .restricted, requestResult: false)
        var state = GlanceHoldState()

        await state.enableMonitoring(permissionProvider: provider)

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(state.status.visibleTitle, GlanceHoldStrings.text(.monitoringCameraPermissionDeniedTitle))
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testUndeterminedPermissionDeniedByUserBecomesDeniedRecoveryWithoutActiveMonitoring() async {
        let provider = FakePermissionProvider(status: .undetermined, requestResult: false)
        var state = GlanceHoldState()

        await state.enableMonitoring(permissionProvider: provider)

        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(state.status.visibleTitle, GlanceHoldStrings.text(.monitoringCameraPermissionDeniedTitle))
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testGrantedPermissionProceedsToReadyAfterCalibration() async {
        let provider = FakePermissionProvider(status: .granted, requestResult: true)
        var state = GlanceHoldState(settings: .defaults.withCalibration(permissionSnapshot()))

        await state.enableMonitoring(permissionProvider: provider)

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(state.status.visibleTitle, GlanceHoldStrings.text(.monitoringReadyAfterCalibrationTitle))
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testGrantedPermissionWithoutCalibrationNeedsCalibration() async {
        let provider = FakePermissionProvider(status: .granted, requestResult: true)
        var state = GlanceHoldState()

        await state.enableMonitoring(permissionProvider: provider)

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(state.status.visibleTitle, GlanceHoldStrings.text(.monitoringNeedsCalibrationTitle))
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testLaunchAndPassiveRenderingDoNotRequestCameraPermission() {
        let provider = FakePermissionProvider(status: .undetermined, requestResult: true)
        _ = GlanceHoldState()

        XCTAssertEqual(provider.requestCount, 0)
    }

    func testPendingPermissionDoesNotStartAnotherRequestFromStateEnable() async {
        let provider = FakePermissionProvider(status: .undetermined, requestResult: true)
        var state = GlanceHoldState(status: .requestingCameraPermission)

        await state.enableMonitoring(permissionProvider: provider)

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(state.status, .requestingCameraPermission)
    }

    func testPrimaryMenuActionIsTypedForPermissionStates() {
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .off), .enable)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .cameraPermissionNeeded), .enable)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .requestingCameraPermission), .wait)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .cameraPermissionDenied), .openCameraSettings)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .facing), .disable)

        XCTAssertEqual(GlanceHoldPrimaryAction.wait.title, GlanceHoldStrings.text(.actionWaitingCameraPermission))
        XCTAssertFalse(GlanceHoldPrimaryAction.wait.isEnabled)
        XCTAssertEqual(GlanceHoldPrimaryAction.openCameraSettings.title, GlanceHoldStrings.text(.actionOpenCameraSettings))
        XCTAssertTrue(GlanceHoldPrimaryAction.openCameraSettings.isEnabled)
    }
}

private func permissionSnapshot() -> CalibrationSnapshot {
    CalibrationSnapshot(
        neutralPose: PoseSample(yawDegrees: 0.0, pitchDegrees: 0.0, rollDegrees: 0.0, time: 0.0),
        quality: .high,
        createdAt: Date(timeIntervalSince1970: 1.0)
    )
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
