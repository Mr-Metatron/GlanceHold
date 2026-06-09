import Foundation

struct PlaybackSemanticDeduper {
    private var currentSessionID: UUID?
    private var lastEmittedState: DebouncedAttentionState?

    mutating func startSession(_ sessionID: UUID) {
        guard currentSessionID != sessionID else {
            return
        }

        currentSessionID = sessionID
        lastEmittedState = nil
    }

    mutating func endSession() {
        currentSessionID = nil
        lastEmittedState = nil
    }

    mutating func shouldEmit(_ state: DebouncedAttentionState) -> Bool {
        guard currentSessionID != nil else {
            return false
        }

        guard lastEmittedState != state else {
            return false
        }

        lastEmittedState = state
        return true
    }
}
