import SwiftUI

@main
struct GlanceHoldApp: App {
    @State private var glanceHoldState = GlanceHoldState()

    var body: some Scene {
        MenuBarExtra("GlanceHold", systemImage: "display") {
            GlanceHoldMenu(state: $glanceHoldState)
        }

        Window("About GlanceHold", id: "about") {
            ContentView()
        }
        .defaultSize(width: 420, height: 260)
    }
}

enum GlanceHoldPrimaryAction: Equatable {
    case enable
    case disable
    case wait
    case openCameraSettings

    static func resolve(for status: MonitoringStatus) -> GlanceHoldPrimaryAction {
        switch status {
        case .off, .cameraPermissionNeeded:
            .enable
        case .requestingCameraPermission:
            .wait
        case .cameraPermissionDenied:
            .openCameraSettings
        default:
            .disable
        }
    }

    var title: String {
        switch self {
        case .enable:
            "Enable Monitoring"
        case .disable:
            "Disable Monitoring"
        case .wait:
            "Requesting Camera Permission..."
        case .openCameraSettings:
            "Open Camera Settings..."
        }
    }

    var isEnabled: Bool {
        self != .wait
    }
}

private struct GlanceHoldMenu: View {
    @Binding var state: GlanceHoldState
    @State private var permissionRequestID: UUID?
    @Environment(\.openWindow) private var openWindow

    private let privacyNote = "Camera stays on this Mac. Frames are not saved or uploaded."
    private let permissionExplanation = "GlanceHold uses the camera only on this Mac to tell whether you are facing the screen. Frames are not saved or uploaded."

    private var primaryAction: GlanceHoldPrimaryAction {
        GlanceHoldPrimaryAction.resolve(for: state.status)
    }

    var body: some View {
        Text("Status: \(state.status.visibleTitle)")
            .accessibilityLabel("Status: \(state.status.visibleTitle)")

        if state.status == .cameraPermissionNeeded {
            Text(permissionExplanation)
                .foregroundStyle(.secondary)
        } else if !state.status.detailText.isEmpty {
            Text(state.status.detailText)
                .foregroundStyle(state.status == .cameraPermissionDenied ? .orange : .secondary)
        }

        Divider()

        Button(primaryAction.title) {
            performPrimaryAction(primaryAction)
        }
        .disabled(!primaryAction.isEnabled)

        Divider()

        Picker("Mode", selection: $state.mode) {
            Text("Speed Control").tag(MonitoringMode.speedControl)
            Text("Pause/Resume").tag(MonitoringMode.pauseResume)
        }

        Divider()

        Button("Calibrate Facing Pose...") {}
            .disabled(true)

        Text(privacyNote)
            .foregroundStyle(.secondary)

        Divider()

        Button("About GlanceHold...") {
            openWindow(id: "about")
        }

        Button("Quit GlanceHold") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func performPrimaryAction(_ action: GlanceHoldPrimaryAction) {
        switch action {
        case .enable:
            enableMonitoring()
        case .disable:
            permissionRequestID = nil
            state.disableMonitoring()
        case .wait:
            break
        case .openCameraSettings:
            openCameraSettings()
        }
    }

    private func enableMonitoring() {
        guard state.status != .requestingCameraPermission else {
            return
        }

        let requestID = UUID()
        permissionRequestID = requestID
        state.status = .requestingCameraPermission

        let pendingState = state

        Task {
            let nextStatus = await pendingState.resolvedStatusAfterEnable(permissionProvider: CameraPermissionClient.live)
            await MainActor.run {
                guard permissionRequestID == requestID else {
                    return
                }

                permissionRequestID = nil
                state.status = nextStatus
            }
        }
    }

    private func openCameraSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
