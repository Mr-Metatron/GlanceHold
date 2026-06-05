import SwiftUI

@main
struct GlanceHoldApp: App {
    @State private var glanceHoldState = GlanceHoldState()

    var body: some Scene {
        MenuBarExtra("GlanceHold", systemImage: "eye") {
            GlanceHoldMenu(state: $glanceHoldState)
        }

        Window("About GlanceHold", id: "about") {
            ContentView()
        }
        .defaultSize(width: 420, height: 260)
    }
}

private struct GlanceHoldMenu: View {
    @Binding var state: GlanceHoldState
    @Environment(\.openWindow) private var openWindow

    private let privacyNote = "Camera stays on this Mac. Frames are not saved or uploaded."
    private let permissionExplanation = "GlanceHold uses the camera only on this Mac to tell whether you are facing the screen. Frames are not saved or uploaded."

    private var primaryActionTitle: String {
        switch state.status {
        case .off, .cameraPermissionNeeded:
            "Enable Monitoring"
        default:
            "Disable Monitoring"
        }
    }

    var body: some View {
        Text("Status: \(state.status.visibleTitle)")
            .accessibilityLabel("Status: \(state.status.visibleTitle)")

        if state.status == .cameraPermissionNeeded {
            Text("Camera Permission Needed")
            Text(permissionExplanation)
                .foregroundStyle(.secondary)
        }

        Divider()

        Button(primaryActionTitle) {
            if primaryActionTitle == "Enable Monitoring" {
                enableMonitoring()
            } else {
                state.disableMonitoring()
            }
        }

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

    private func enableMonitoring() {
        let currentState = state

        Task {
            let nextStatus = await currentState.resolvedStatusAfterEnable(permissionProvider: CameraPermissionClient.live)
            await MainActor.run {
                state.status = nextStatus
            }
        }
    }
}
