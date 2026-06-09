import AppKit
import Foundation

protocol AppRestartRequesting: AnyObject {
    func requestRestart(onFailure: @escaping () -> Void)
}

final class LiveAppRestartRequester: AppRestartRequesting {
    func requestRestart(onFailure: @escaping () -> Void) {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                guard app != nil, error == nil else {
                    onFailure()
                    return
                }

                NSApplication.shared.terminate(nil)
            }
        }
    }
}
