import Foundation
import os

enum DiagnosticMode: Equatable {
    case `default`
    case diagnostic
}

enum DiagnosticSessionKind: String, Equatable {
    case monitoring
    case calibration
}

final class DiagnosticSession {
    let id: UUID
    let kind: DiagnosticSessionKind

    private var nextValue: UInt64 = 1
    private let lock = NSLock()

    init(id: UUID = UUID(), kind: DiagnosticSessionKind) {
        self.id = id
        self.kind = kind
    }

    func nextSequence() -> UInt64 {
        lock.lock()
        defer {
            lock.unlock()
        }

        let value = nextValue
        nextValue += 1
        return value
    }
}

enum DiagnosticCategory: String, Equatable {
    case monitoring
    case camera
    case attention
    case calibration
    case playback
    case bridge
    case runtimeSummary
}

enum DiagnosticEventName: String, Equatable, Hashable {
    case sessionStarted
    case sessionStopped
    case failure
    case attentionTransition
    case calibrationEnded
    case playbackAction
    case runtimeSummary
    case frameReceived
    case analysisCompleted
    case repeatedStableState
}

enum DiagnosticFieldName: String, Equatable, Hashable {
    case rawSignal
    case previousState
    case nextState
    case transitionReason
    case playbackState
    case speedPresent
    case intent
    case confirmation
    case framesReceived
    case framesAnalyzed
    case analyzerRateHz
    case semanticStateChanges
    case playbackSnapshots
    case playbackCommands
    case droppedSamples
    case analysisLatencyMillisecondsAverage
    case analysisLatencyMillisecondsMax
    case summaryKind
}

enum DiagnosticFieldValue: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case uuid(UUID)

    var logValue: String {
        switch self {
        case let .string(value):
            value
        case let .int(value):
            String(value)
        case let .double(value):
            String(format: "%.3f", value)
        case let .bool(value):
            String(value)
        case let .uuid(value):
            value.uuidString
        }
    }
}

enum DiagnosticFieldError: Error, Equatable {
    case disallowedPrivateField(String)
    case unsupportedField(String)
}

struct DiagnosticField: Equatable {
    let name: DiagnosticFieldName
    let value: DiagnosticFieldValue

    init(_ name: DiagnosticFieldName, _ value: DiagnosticFieldValue) throws {
        self.name = name
        self.value = value
    }

    init(name: String, value: DiagnosticFieldValue) throws {
        if Self.disallowedNames.contains(name) {
            throw DiagnosticFieldError.disallowedPrivateField(name)
        }

        guard let fieldName = DiagnosticFieldName(rawValue: name) else {
            throw DiagnosticFieldError.unsupportedField(name)
        }

        try self.init(fieldName, value)
    }

    private static let disallowedNames: Set<String> = [
        "sampleBuffer",
        "image",
        "faceBox",
        "rawPoseStream",
        "mediaPath",
        "mediaTitle",
        "rawBridgePayload",
        "token"
    ]
}

struct DiagnosticRuntimeMetrics: Equatable {
    var framesReceived: Int
    var framesAnalyzed: Int
    var analyzerRateHz: Double
    var semanticStateChanges: Int
    var playbackSnapshots: Int
    var playbackCommands: Int
    var droppedSamples: Int
    var analysisLatencyMillisecondsTotal: Double
    var analysisLatencyMillisecondsMax: Double

    var averageAnalysisLatencyMilliseconds: Double {
        guard framesAnalyzed > 0 else {
            return 0.0
        }

        return analysisLatencyMillisecondsTotal / Double(framesAnalyzed)
    }
}

struct DiagnosticEventRequest: Equatable {
    let category: DiagnosticCategory
    let name: DiagnosticEventName
    let fields: [DiagnosticField]
    let isPeriodicSummary: Bool

    init(
        category: DiagnosticCategory,
        name: DiagnosticEventName,
        fields: [DiagnosticField] = [],
        isPeriodicSummary: Bool = false
    ) {
        self.category = category
        self.name = name
        self.fields = fields
        self.isPeriodicSummary = isPeriodicSummary
    }

    static func runtimeSummary(_ metrics: DiagnosticRuntimeMetrics, periodic: Bool) -> DiagnosticEventRequest {
        DiagnosticEventRequest(
            category: .runtimeSummary,
            name: .runtimeSummary,
            fields: metrics.summaryFields(periodic: periodic),
            isPeriodicSummary: periodic
        )
    }
}

struct DiagnosticEvent: Equatable {
    let category: DiagnosticCategory
    let name: DiagnosticEventName
    let sessionID: UUID
    let sessionKind: DiagnosticSessionKind
    let sequence: UInt64
    let fields: [DiagnosticField]
}

protocol DiagnosticRecording: AnyObject {
    @discardableResult
    func record(_ request: DiagnosticEventRequest, in session: DiagnosticSession) -> DiagnosticEvent?
}

enum DiagnosticEventPolicy {
    static func shouldRecord(_ request: DiagnosticEventRequest, mode: DiagnosticMode) -> Bool {
        switch mode {
        case .diagnostic:
            return true
        case .default:
            if request.isPeriodicSummary {
                return false
            }

            return !request.name.isDiagnosticOnly && !request.name.isHighVolume
        }
    }
}

enum DiagnosticLogFormatter {
    static func message(for event: DiagnosticEvent) -> String {
        let base = [
            "category=\(event.category.rawValue)",
            "event=\(event.name.rawValue)",
            "session=\(event.sessionID.uuidString)",
            "sessionKind=\(event.sessionKind.rawValue)",
            "sequence=\(event.sequence)"
        ]
        let fields = event.fields.map { field in
            "\(field.name.rawValue)=\(field.value.logValue)"
        }

        return (base + fields).joined(separator: " ")
    }
}

final class LiveDiagnosticRecorder: DiagnosticRecording {
    private let mode: DiagnosticMode
    private let logger: Logger

    init(
        mode: DiagnosticMode,
        subsystem: String = "com.metatron.GlanceHold",
        category: String = "Diagnostics"
    ) {
        self.mode = mode
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    @discardableResult
    func record(_ request: DiagnosticEventRequest, in session: DiagnosticSession) -> DiagnosticEvent? {
        guard DiagnosticEventPolicy.shouldRecord(request, mode: mode) else {
            return nil
        }

        let event = DiagnosticEvent(
            category: request.category,
            name: request.name,
            sessionID: session.id,
            sessionKind: session.kind,
            sequence: session.nextSequence(),
            fields: request.fields
        )
        logger.info("\(DiagnosticLogFormatter.message(for: event), privacy: .public)")
        return event
    }
}

private extension DiagnosticEventName {
    var isDiagnosticOnly: Bool {
        switch self {
        case .attentionTransition, .playbackAction:
            return true
        case .sessionStarted, .sessionStopped, .failure, .calibrationEnded, .runtimeSummary, .frameReceived, .analysisCompleted, .repeatedStableState:
            return false
        }
    }

    var isHighVolume: Bool {
        switch self {
        case .frameReceived, .analysisCompleted, .repeatedStableState:
            return true
        case .sessionStarted, .sessionStopped, .failure, .attentionTransition, .calibrationEnded, .playbackAction, .runtimeSummary:
            return false
        }
    }
}

private extension DiagnosticRuntimeMetrics {
    func summaryFields(periodic: Bool) -> [DiagnosticField] {
        [
            field(.framesReceived, .int(framesReceived)),
            field(.framesAnalyzed, .int(framesAnalyzed)),
            field(.analyzerRateHz, .double(analyzerRateHz)),
            field(.semanticStateChanges, .int(semanticStateChanges)),
            field(.playbackSnapshots, .int(playbackSnapshots)),
            field(.playbackCommands, .int(playbackCommands)),
            field(.droppedSamples, .int(droppedSamples)),
            field(.analysisLatencyMillisecondsAverage, .double(averageAnalysisLatencyMilliseconds)),
            field(.analysisLatencyMillisecondsMax, .double(analysisLatencyMillisecondsMax)),
            field(.summaryKind, .string(periodic ? "periodic" : "final"))
        ]
    }

    private func field(_ name: DiagnosticFieldName, _ value: DiagnosticFieldValue) -> DiagnosticField {
        guard let field = try? DiagnosticField(name, value) else {
            preconditionFailure("Static diagnostic runtime metric field failed validation.")
        }

        return field
    }
}
