import XCTest
@testable import GlanceHold

final class DiagnosticRecorderTests: XCTestCase {
    func testMonitoringAndCalibrationSessionsAllocateIndependentMonotonicSequences() {
        let monitoring = DiagnosticSession(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            kind: .monitoring
        )
        let calibration = DiagnosticSession(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            kind: .calibration
        )

        XCTAssertEqual(monitoring.kind, .monitoring)
        XCTAssertEqual(calibration.kind, .calibration)
        XCTAssertEqual(monitoring.nextSequence(), 1)
        XCTAssertEqual(monitoring.nextSequence(), 2)
        XCTAssertEqual(calibration.nextSequence(), 1)
        XCTAssertEqual(monitoring.nextSequence(), 3)
    }

    func testTypedCategoriesEventsAndStableLogFields() throws {
        let recorder = FakeDiagnosticRecorder(mode: .diagnostic)
        let session = DiagnosticSession(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            kind: .monitoring
        )

        let events = [
            DiagnosticEventRequest(category: .monitoring, name: .sessionStarted),
            DiagnosticEventRequest(category: .camera, name: .failure),
            DiagnosticEventRequest(category: .attention, name: .attentionTransition),
            DiagnosticEventRequest(category: .calibration, name: .calibrationEnded),
            DiagnosticEventRequest(category: .playback, name: .playbackAction),
            DiagnosticEventRequest(category: .bridge, name: .failure),
            DiagnosticEventRequest.runtimeSummary(.sample, periodic: false)
        ]

        for event in events {
            XCTAssertNotNil(recorder.record(event, in: session))
        }

        XCTAssertEqual(recorder.events.map(\.category), [
            .monitoring,
            .camera,
            .attention,
            .calibration,
            .playback,
            .bridge,
            .runtimeSummary
        ])
        XCTAssertEqual(recorder.events.map(\.sequence), [1, 2, 3, 4, 5, 6, 7])

        let message = DiagnosticLogFormatter.message(for: recorder.events[0])
        XCTAssertTrue(message.contains("category=monitoring"))
        XCTAssertTrue(message.contains("event=sessionStarted"))
        XCTAssertTrue(message.contains("session=33333333-3333-3333-3333-333333333333"))
        XCTAssertTrue(message.contains("sequence=1"))
    }

    func testDefaultModeDropsHighVolumeAndDetailEventsButKeepsLifecycleFailureAndFinalSummary() {
        let recorder = FakeDiagnosticRecorder(mode: .default)
        let session = DiagnosticSession(kind: .monitoring)

        XCTAssertNotNil(recorder.record(DiagnosticEventRequest(category: .monitoring, name: .sessionStarted), in: session))
        XCTAssertNotNil(recorder.record(DiagnosticEventRequest(category: .camera, name: .failure), in: session))
        XCTAssertNil(recorder.record(DiagnosticEventRequest(category: .camera, name: .frameReceived), in: session))
        XCTAssertNil(recorder.record(DiagnosticEventRequest(category: .attention, name: .analysisCompleted), in: session))
        XCTAssertNil(recorder.record(DiagnosticEventRequest(category: .attention, name: .repeatedStableState), in: session))
        XCTAssertNil(recorder.record(DiagnosticEventRequest(category: .attention, name: .attentionTransition), in: session))
        XCTAssertNil(recorder.record(DiagnosticEventRequest.runtimeSummary(.sample, periodic: true), in: session))
        XCTAssertNotNil(recorder.record(DiagnosticEventRequest.runtimeSummary(.sample, periodic: false), in: session))

        XCTAssertEqual(recorder.events.map(\.name), [.sessionStarted, .failure, .runtimeSummary])
        XCTAssertEqual(recorder.droppedEventCounts[.frameReceived], 1)
        XCTAssertEqual(recorder.droppedEventCounts[.analysisCompleted], 1)
        XCTAssertEqual(recorder.droppedEventCounts[.repeatedStableState], 1)
    }

    func testDiagnosticModeAcceptsDetailedBreadcrumbsAndPeriodicSummaries() throws {
        let recorder = FakeDiagnosticRecorder(mode: .diagnostic)
        let session = DiagnosticSession(kind: .monitoring)
        let transition = DiagnosticEventRequest(
            category: .attention,
            name: .attentionTransition,
            fields: [
                try DiagnosticField(.rawSignal, .string("lookingAway")),
                try DiagnosticField(.previousState, .string("facing")),
                try DiagnosticField(.nextState, .string("lookingAway")),
                try DiagnosticField(.transitionReason, .string("thresholdReached"))
            ]
        )
        let action = DiagnosticEventRequest(
            category: .playback,
            name: .playbackAction,
            fields: [
                try DiagnosticField(.playbackState, .string("playing")),
                try DiagnosticField(.speedPresent, .bool(true)),
                try DiagnosticField(.intent, .string("holdSpeedAtOne")),
                try DiagnosticField(.confirmation, .string("confirmed"))
            ]
        )

        XCTAssertNotNil(recorder.record(transition, in: session))
        XCTAssertNotNil(recorder.record(action, in: session))
        XCTAssertNotNil(recorder.record(DiagnosticEventRequest.runtimeSummary(.sample, periodic: true), in: session))

        XCTAssertEqual(recorder.events.map(\.name), [.attentionTransition, .playbackAction, .runtimeSummary])
    }

    func testDisallowedPrivacyFieldNamesAreRejected() {
        let disallowedNames = [
            "sampleBuffer",
            "image",
            "faceBox",
            "rawPoseStream",
            "mediaPath",
            "mediaTitle",
            "rawBridgePayload",
            "token"
        ]

        for name in disallowedNames {
            XCTAssertThrowsError(try DiagnosticField(name: name, value: .string("private")))
        }
    }

    func testRuntimeMetricsSummaryUsesScalarAggregateFields() {
        let metrics = DiagnosticRuntimeMetrics(
            framesReceived: 120,
            framesAnalyzed: 24,
            analyzerRateHz: 4.8,
            semanticStateChanges: 3,
            playbackSnapshots: 7,
            playbackCommands: 2,
            droppedSamples: 1,
            analysisLatencyMillisecondsTotal: 96.0,
            analysisLatencyMillisecondsMax: 8.0
        )
        let request = DiagnosticEventRequest.runtimeSummary(metrics, periodic: false)

        XCTAssertEqual(request.category, .runtimeSummary)
        XCTAssertEqual(request.name, .runtimeSummary)
        XCTAssertEqual(request.fields.map(\.name), [
            .framesReceived,
            .framesAnalyzed,
            .analyzerRateHz,
            .semanticStateChanges,
            .playbackSnapshots,
            .playbackCommands,
            .droppedSamples,
            .analysisLatencyMillisecondsAverage,
            .analysisLatencyMillisecondsMax,
            .summaryKind
        ])
    }
}

private final class FakeDiagnosticRecorder: DiagnosticRecording {
    let mode: DiagnosticMode
    private(set) var events: [DiagnosticEvent] = []
    private(set) var droppedEventCounts: [DiagnosticEventName: Int] = [:]

    init(mode: DiagnosticMode) {
        self.mode = mode
    }

    @discardableResult
    func record(_ request: DiagnosticEventRequest, in session: DiagnosticSession) -> DiagnosticEvent? {
        guard DiagnosticEventPolicy.shouldRecord(request, mode: mode) else {
            droppedEventCounts[request.name, default: 0] += 1
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
        events.append(event)
        return event
    }
}

private extension DiagnosticRuntimeMetrics {
    static let sample = DiagnosticRuntimeMetrics(
        framesReceived: 10,
        framesAnalyzed: 5,
        analyzerRateHz: 2.5,
        semanticStateChanges: 1,
        playbackSnapshots: 2,
        playbackCommands: 1,
        droppedSamples: 0,
        analysisLatencyMillisecondsTotal: 20.0,
        analysisLatencyMillisecondsMax: 5.0
    )
}
