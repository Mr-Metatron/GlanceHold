import AVFoundation

enum CameraPermissionStatus: Equatable {
    case undetermined
    case granted
    case denied
    case restricted

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .undetermined
        case .authorized:
            self = .granted
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .denied
        }
    }
}

protocol CameraPermissionProviding {
    func authorizationStatus() -> CameraPermissionStatus
    func requestAccess() async -> Bool
}

struct CameraPermissionClient: CameraPermissionProviding {
    var authorizationStatusProvider: () -> CameraPermissionStatus
    var requestAccessProvider: () async -> Bool

    init(
        authorizationStatusProvider: @escaping () -> CameraPermissionStatus,
        requestAccessProvider: @escaping () async -> Bool
    ) {
        self.authorizationStatusProvider = authorizationStatusProvider
        self.requestAccessProvider = requestAccessProvider
    }

    func authorizationStatus() -> CameraPermissionStatus {
        authorizationStatusProvider()
    }

    func requestAccess() async -> Bool {
        await requestAccessProvider()
    }

    static let live = CameraPermissionClient(
        authorizationStatusProvider: {
            CameraPermissionStatus(AVCaptureDevice.authorizationStatus(for: .video))
        },
        requestAccessProvider: {
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    )
}
