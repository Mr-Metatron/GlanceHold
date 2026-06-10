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
            DiagnosticEventRequest.runtimeSummary(.sample, periodic: false, source: .attention)
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
        XCTAssertNil(recorder.record(DiagnosticEventRequest.runtimeSummary(.sample, periodic: true, source: .attention), in: session))
        XCTAssertNotNil(recorder.record(DiagnosticEventRequest.runtimeSummary(.sample, periodic: false, source: .attention), in: session))

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
        XCTAssertNotNil(recorder.record(DiagnosticEventRequest.runtimeSummary(.sample, periodic: true, source: .attention), in: session))

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
            "bridgeToken",
            "token"
        ]

        for name in disallowedNames {
            XCTAssertThrowsError(try DiagnosticField(name: name, value: .string("private")))
        }
    }

    func testPlaybackActionDiagnosticFieldsAreTypedAndScalar() throws {
        let fields = [
            try DiagnosticField(name: "snapshotState", value: .string("playing")),
            try DiagnosticField(name: "speedPresent", value: .bool(true)),
            try DiagnosticField(name: "intentType", value: .string("holdSpeedAtOne")),
            try DiagnosticField(name: "commandType", value: .string("holdSpeedAtOne")),
            try DiagnosticField(name: "confirmationOutcome", value: .string("confirmed")),
            try DiagnosticField(name: "completedActionEmitted", value: .string("heldSpeedAtOne")),
            try DiagnosticField(name: "errorCategory", value: .string("none"))
        ]

        XCTAssertEqual(fields.map(\.name), [
            .snapshotState,
            .speedPresent,
            .intentType,
            .commandType,
            .confirmationOutcome,
            .completedActionEmitted,
            .errorCategory
        ])
    }

    func testPlaybackNoOpDiagnosticFieldsAreTypedScalarAndPrivacySafe() throws {
        let fields = [
            try DiagnosticField(name: "noOpReason", value: .string("missingSpeed")),
            try DiagnosticField(name: "noOpCount", value: .int(3)),
            try DiagnosticField(name: "firstAttentionState", value: .string("lookingAway")),
            try DiagnosticField(name: "latestAttentionState", value: .string("lookingAway")),
            try DiagnosticField(name: "firstSnapshotState", value: .string("playing")),
            try DiagnosticField(name: "latestSnapshotState", value: .string("playing")),
            try DiagnosticField(name: "firstSpeedPresent", value: .bool(false)),
            try DiagnosticField(name: "latestSpeedPresent", value: .bool(false)),
            try DiagnosticField(name: "firstIntentType", value: .string("none")),
            try DiagnosticField(name: "latestIntentType", value: .string("none"))
        ]

        XCTAssertEqual(fields.map(\.name), [
            .noOpReason,
            .noOpCount,
            .firstAttentionState,
            .latestAttentionState,
            .firstSnapshotState,
            .latestSnapshotState,
            .firstSpeedPresent,
            .latestSpeedPresent,
            .firstIntentType,
            .latestIntentType
        ])

        for field in fields {
            XCTAssertFalse(field.name.rawValue.contains("sampleBuffer"))
            XCTAssertFalse(field.name.rawValue.contains("image"))
            XCTAssertFalse(field.name.rawValue.contains("faceBox"))
            XCTAssertFalse(field.name.rawValue.contains("rawPoseStream"))
            XCTAssertFalse(field.name.rawValue.contains("mediaPath"))
            XCTAssertFalse(field.name.rawValue.contains("mediaTitle"))
            XCTAssertFalse(field.name.rawValue.contains("rawBridgePayload"))
            XCTAssertFalse(field.name.rawValue.contains("bridgeToken"))
            XCTAssertFalse(field.name.rawValue.contains("token"))
        }
    }

    func testDefaultModeDropsNoOpSummaryEvents() throws {
        let recorder = FakeDiagnosticRecorder(mode: .default)
        let session = DiagnosticSession(kind: .monitoring)
        let request = DiagnosticEventRequest(
            category: .playback,
            name: .playbackNoOpSummary,
            fields: [
                try DiagnosticField(name: "noOpReason", value: .string("policyEvaluatedWithoutIntent")),
                try DiagnosticField(name: "noOpCount", value: .int(1))
            ]
        )

        XCTAssertNil(recorder.record(request, in: session))
        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(recorder.droppedEventCounts[.playbackNoOpSummary], 1)
    }

    func testDiagnosticModeAcceptsBoundedNoOpSummaryBreadcrumbs() throws {
        let recorder = FakeDiagnosticRecorder(mode: .diagnostic)
        let session = DiagnosticSession(kind: .monitoring)
        let request = DiagnosticEventRequest(
            category: .playback,
            name: .playbackNoOpSummary,
            fields: [
                try DiagnosticField(name: "noOpReason", value: .string("recoveringNoCommand")),
                try DiagnosticField(name: "noOpCount", value: .int(5)),
                try DiagnosticField(name: "firstAttentionState", value: .string("recovering")),
                try DiagnosticField(name: "latestAttentionState", value: .string("recovering")),
                try DiagnosticField(name: "firstSnapshotState", value: .string("playing")),
                try DiagnosticField(name: "latestSnapshotState", value: .string("playing")),
                try DiagnosticField(name: "firstSpeedPresent", value: .bool(true)),
                try DiagnosticField(name: "latestSpeedPresent", value: .bool(true)),
                try DiagnosticField(name: "firstIntentType", value: .string("none")),
                try DiagnosticField(name: "latestIntentType", value: .string("none"))
            ]
        )

        XCTAssertNotNil(recorder.record(request, in: session))
        XCTAssertEqual(recorder.events.map(\.name), [.playbackNoOpSummary])
        XCTAssertEqual(recorder.events[0].fields.first { $0.name == .noOpCount }?.value.logValue, "5")
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
            skippedSamples: 96,
            analysisLatencyMillisecondsTotal: 96.0,
            analysisLatencyMillisecondsMax: 8.0
        )
        let request = DiagnosticEventRequest.runtimeSummary(metrics, periodic: false, source: .attention)

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
            .skippedSamples,
            .analysisLatencyMillisecondsAverage,
            .analysisLatencyMillisecondsMax,
            .summaryKind,
            .summarySource
        ])
        XCTAssertEqual(request.fields.first { $0.name == .skippedSamples }?.value.logValue, "96")
        XCTAssertEqual(request.fields.first { $0.name == .summarySource }?.value.logValue, "attention")
    }

    func testDefaultModeCoalescesRepeatedHighVolumeEventsInsteadOfRecordingUnboundedArrays() {
        let recorder = FakeDiagnosticRecorder(mode: .default)
        let session = DiagnosticSession(kind: .monitoring)

        for _ in 0..<50 {
            XCTAssertNil(recorder.record(DiagnosticEventRequest(category: .camera, name: .frameReceived), in: session))
            XCTAssertNil(recorder.record(DiagnosticEventRequest(category: .attention, name: .analysisCompleted), in: session))
            XCTAssertNil(recorder.record(DiagnosticEventRequest(category: .attention, name: .repeatedStableState), in: session))
        }

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(recorder.droppedEventCounts[.frameReceived], 50)
        XCTAssertEqual(recorder.droppedEventCounts[.analysisCompleted], 50)
        XCTAssertEqual(recorder.droppedEventCounts[.repeatedStableState], 50)
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
        skippedSamples: 0,
        analysisLatencyMillisecondsTotal: 20.0,
        analysisLatencyMillisecondsMax: 5.0
    )
}
