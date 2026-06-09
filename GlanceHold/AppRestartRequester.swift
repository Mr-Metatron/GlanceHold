import AppKit
import Foundation

protocol AppRestartRequesting: AnyObject {
    func requestRestart()
}

final class LiveAppRestartRequester: AppRestartRequesting {
    func requestRestart() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            NSApplication.shared.terminate(nil)
        }
    }
}
