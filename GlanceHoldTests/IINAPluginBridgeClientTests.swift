import XCTest
@testable import GlanceHold

final class IINAPluginBridgeClientTests: XCTestCase {
    func testSnapshotRequestUsesVersionedJSONMessage() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":2,"ok":true,"snapshot":{"state":"playing","speed":1.5}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        _ = try await client.snapshot()

        let request = try XCTUnwrap(transport.sentMessages.first)
        XCTAssertEqual(request["id"] as? Int, 1)
        XCTAssertEqual(request["version"] as? Int, 2)
        XCTAssertFalse(request.keys.contains("token"))
        XCTAssertEqual(request["type"] as? String, "snapshot")
    }

    func testCommandRequestsMapToSetSpeedPauseAndResume() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":2,"ok":true}"#,
            #"{"id":2,"version":2,"ok":true}"#,
            #"{"id":3,"version":2,"ok":true}"#,
            #"{"id":4,"version":2,"ok":true}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        try await client.execute(.holdSpeedAtOne)
        try await client.execute(.restoreSpeed(1.25))
        try await client.execute(.pause)
        try await client.execute(.resume)

        XCTAssertEqual(transport.sentMessages.map { $0["type"] as? String }, [
            "command",
            "command",
            "command",
            "command"
        ])
        XCTAssertEqual(transport.sentMessages.map { $0["command"] as? String }, [
            "setSpeed",
            "setSpeed",
            "pause",
            "resume"
        ])
        XCTAssertEqual(transport.sentMessages[0]["speed"] as? Double, 1.0)
        XCTAssertEqual(transport.sentMessages[1]["speed"] as? Double, 1.25)
        XCTAssertTrue(transport.sentMessages.allSatisfy { !$0.keys.contains("token") })
    }

    func testDefaultClientInitializerDoesNotRequireTokenStore() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":2,"ok":true,"snapshot":{"state":"idle"}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        let status = try await client.snapshot()

        XCTAssertEqual(status, .idle)
        let request = try XCTUnwrap(transport.sentMessages.first)
        XCTAssertFalse(request.keys.contains("token"))
    }

    func testConnectionRefusedMapsToPluginNeeded() async throws {
        let transport = FakeIINAPluginBridgeTransport(error: IINAPluginBridgeClientError.pluginNeeded)
        let client = IINAPluginBridgeClient(transport: transport)

        let status = await client.status()

        XCTAssertEqual(status, .setupNeeded)
    }

    func testStatusChangedMessageWithoutRequestIDDecodesAsPushedStatus() async throws {
        let transport = FakeIINAPluginBridgeTransport(streamMessages: [
            #"{"version":2,"type":"statusChanged","snapshot":{"state":"playing","speed":2.0}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        var iterator = client.statusUpdates().makeAsyncIterator()
        let status = await iterator.next()

        XCTAssertEqual(status, .playing(speed: 2.0))
        XCTAssertEqual(transport.sentMessages.count, 0)
    }

    func testHeartbeatMessageWithoutRequestIDDecodesAsLivenessOnly() async throws {
        let transport = FakeIINAPluginBridgeTransport(streamMessages: [
            #"{"version":2,"type":"heartbeat"}"#,
            #"{"version":2,"type":"statusChanged","snapshot":{"state":"playing","speed":2.0}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        var eventIterator = client.pushedEvents().makeAsyncIterator()
        let heartbeat = await eventIterator.next()
        let statusEvent = await eventIterator.next()
        let nextEvent = await eventIterator.next()

        XCTAssertEqual(heartbeat, .heartbeat)
        XCTAssertEqual(statusEvent, .status(.playing(speed: 2.0)))
        XCTAssertNil(nextEvent)

        var statusIterator = client.statusUpdates().makeAsyncIterator()
        let status = await statusIterator.next()
        let nextStatus = await statusIterator.next()

        XCTAssertEqual(status, .playing(speed: 2.0))
        XCTAssertNil(nextStatus)
        XCTAssertEqual(transport.sentMessages.count, 0)
    }

    func testToggleMonitoringRequestedMessageDecodesAsEventStreamWithoutCommand() async throws {
        let transport = FakeIINAPluginBridgeTransport(streamMessages: [
            #"{"version":2,"type":"toggleMonitoringRequested"}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        var iterator = client.monitoringToggleRequests().makeAsyncIterator()
        let request: Void? = await iterator.next()
        let nextRequest: Void? = await iterator.next()

        XCTAssertNotNil(request)
        XCTAssertNil(nextRequest)
        XCTAssertEqual(transport.sentMessages.count, 0)
    }

    func testToggleMonitoringStreamUsesLivenessTimeoutAndSurvivesHeartbeatIdleWindow() async throws {
        let transport = FakeIINAPluginBridgeTransport(streamMessages: [
            #"{"version":2,"type":"heartbeat"}"#,
            #"{"version":2,"type":"heartbeat"}"#,
            #"{"version":2,"type":"toggleMonitoringRequested"}"#
        ])
        let client = IINAPluginBridgeClient(
            transport: transport,
            timeout: 1.0,
            streamStaleTimeout: 15.0
        )

        var iterator = client.monitoringToggleRequests().makeAsyncIterator()
        let request: Void? = await iterator.next()

        XCTAssertNotNil(request)
        XCTAssertEqual(transport.messageTimeouts, [15.0])
        XCTAssertEqual(transport.sentMessages.count, 0)
    }

    func testStatusChangedMessageDoesNotSatisfySnapshotRequest() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"version":2,"type":"statusChanged","snapshot":{"state":"playing","speed":2.0}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        let status = await client.status()

        XCTAssertEqual(status, .unavailable)
        XCTAssertEqual(transport.sentMessages.count, 1)
    }

    func testStatusChangedBeforeSnapshotResponseDoesNotPoisonRequest() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"version":2,"type":"statusChanged","snapshot":{"state":"playing","speed":2.0}}"#,
            #"{"id":1,"version":2,"ok":true,"snapshot":{"state":"playing","speed":1.25}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        let status = await client.status()

        XCTAssertEqual(status, .playing(speed: 1.25))
        XCTAssertEqual(transport.sentMessages.count, 1)
    }

    func testHeartbeatBeforeSnapshotResponseDoesNotPoisonRequest() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"version":2,"type":"heartbeat"}"#,
            #"{"id":1,"version":2,"ok":true,"snapshot":{"state":"playing","speed":1.25}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        let status = await client.status()

        XCTAssertEqual(status, .playing(speed: 1.25))
        XCTAssertEqual(transport.sentMessages.count, 1)
    }

    func testToggleMonitoringRequestedBeforeSnapshotResponseDoesNotPoisonRequest() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"version":2,"type":"toggleMonitoringRequested"}"#,
            #"{"id":1,"version":2,"ok":true,"snapshot":{"state":"playing","speed":1.25}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        let status = await client.status()

        XCTAssertEqual(status, .playing(speed: 1.25))
        XCTAssertEqual(transport.sentMessages.count, 1)
    }

    func testToggleMonitoringRequestedStrictlyIgnoresUnsupportedShapes() async throws {
        let transport = FakeIINAPluginBridgeTransport(streamMessages: [
            #"{"version":3,"type":"toggleMonitoringRequested"}"#,
            #"{"id":7,"version":2,"type":"toggleMonitoringRequested"}"#,
            #"{"version":2,"type":"unknownEvent"}"#,
            #"not json"#,
            #"{"version":2,"type":"toggleMonitoringRequested"}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        var iterator = client.monitoringToggleRequests().makeAsyncIterator()
        let request: Void? = await iterator.next()
        let nextRequest: Void? = await iterator.next()

        XCTAssertNotNil(request)
        XCTAssertNil(nextRequest)
        XCTAssertEqual(transport.sentMessages.count, 0)
    }

    func testHeartbeatStrictlyIgnoresUnsupportedShapes() async throws {
        let transport = FakeIINAPluginBridgeTransport(streamMessages: [
            #"{"version":3,"type":"heartbeat"}"#,
            #"{"id":7,"version":2,"type":"heartbeat"}"#,
            #"{"version":2,"type":"heartbeat","snapshot":{"state":"playing","speed":2.0}}"#,
            #"{"version":2,"type":"unknownEvent"}"#,
            #"not json"#,
            #"{"version":2,"type":"heartbeat"}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        var iterator = client.pushedEvents().makeAsyncIterator()
        let event = await iterator.next()
        let nextEvent = await iterator.next()

        XCTAssertEqual(event, .heartbeat)
        XCTAssertNil(nextEvent)
        XCTAssertEqual(transport.sentMessages.count, 0)
    }

    func testRequestIDBearingHeartbeatIsStillTreatedAsResponseMismatch() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"id":7,"version":2,"type":"heartbeat","ok":true}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        let status = await client.status()

        XCTAssertEqual(status, .unavailable)
        XCTAssertEqual(transport.sentMessages.count, 1)
    }

    func testStatusChangedWithRequestIDIsStillTreatedAsResponse() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":2,"type":"statusChanged","ok":true,"snapshot":{"state":"playing","speed":1.75}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        let status = await client.status()

        XCTAssertEqual(status, .playing(speed: 1.75))
        XCTAssertEqual(transport.sentMessages.count, 1)
    }

    func testUnsupportedVersionResponseErrorMapsToProtocolFailure() async throws {
        let client = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":2,"ok":false,"error":"unsupported_version"}"#
        ]))

        await XCTAssertThrowsProtocolFailure(try await client.snapshot(), .unsupportedVersion)
    }

    func testUnknownTypeResponseErrorMapsToProtocolFailure() async throws {
        let client = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":2,"ok":false,"error":"unknown_type"}"#
        ]))

        await XCTAssertThrowsProtocolFailure(try await client.snapshot(), .unknownType)
    }

    func testUnknownCommandResponseErrorMapsToProtocolFailure() async throws {
        let client = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":2,"ok":false,"error":"unknown_command"}"#
        ]))

        await XCTAssertThrowsProtocolFailure(try await client.execute(.pause), .unknownCommand)
    }

    func testNonJSONResponseMapsToMalformedProtocolFailure() async throws {
        let client = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: ["not json"]))

        await XCTAssertThrowsProtocolFailure(try await client.snapshot(), .malformedResponse)
    }

    func testMismatchedResponseIDOrVersionMapsToRequestMismatchProtocolFailure() async throws {
        let mismatchedID = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":999,"version":2,"ok":true,"snapshot":{"state":"playing","speed":1.5}}"#
        ]))
        await XCTAssertThrowsProtocolFailure(try await mismatchedID.snapshot(), .requestMismatch)

        let mismatchedVersion = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":3,"ok":true,"snapshot":{"state":"playing","speed":1.5}}"#
        ]))
        await XCTAssertThrowsProtocolFailure(try await mismatchedVersion.snapshot(), .requestMismatch)
    }

    func testOldPluginUnauthorizedResponseMapsToPluginUpdateRequiredProtocolFailure() async throws {
        let client = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":2,"ok":false,"error":"unauthorized"}"#
        ]))

        await XCTAssertThrowsProtocolFailure(try await client.snapshot(), .pluginUpdateRequired)
    }

    func testStatusMapsOldPluginUnauthorizedResponseToPluginUpdateRequired() async throws {
        let client = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":2,"ok":false,"error":"unauthorized"}"#
        ]))

        let status = await client.status()

        XCTAssertEqual(status, .pluginUpdateRequired)
    }

    func testStatusMapsUnsupportedVersionResponseToPluginUpdateRequired() async throws {
        let client = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":2,"ok":false,"error":"unsupported_version"}"#
        ]))

        let status = await client.status()

        XCTAssertEqual(status, .pluginUpdateRequired)
    }

    func testStatusMapsNonJSONResponseToPluginUpdateRequired() async throws {
        let client = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            "not json"
        ]))

        let status = await client.status()

        XCTAssertEqual(status, .pluginUpdateRequired)
    }

    func testStatusMapsMismatchedResponseIDToPluginUpdateRequired() async throws {
        let client = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":999,"version":2,"ok":true,"snapshot":{"state":"playing","speed":1.5}}"#
        ]))

        let status = await client.status()

        XCTAssertEqual(status, .pluginUpdateRequired)
    }

    func testStatusMapsMismatchedResponseVersionToPluginUpdateRequired() async throws {
        let client = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":3,"ok":true,"snapshot":{"state":"playing","speed":1.5}}"#
        ]))

        let status = await client.status()

        XCTAssertEqual(status, .pluginUpdateRequired)
    }

    func testUnavailableResponseAndUnknownSnapshotStateStillMapToUnavailable() async throws {
        let unknownState = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":2,"ok":true,"snapshot":{"state":"buffering","speed":1.5}}"#
        ]))
        await XCTAssertEqualAsync(await unknownState.status(), .unavailable)

        let unavailableStatus = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":2,"ok":false,"error":"unavailable"}"#
        ]))
        await XCTAssertEqualAsync(await unavailableStatus.status(), .unavailable)

        let unavailable = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":2,"ok":false,"error":"unavailable"}"#
        ]))

        do {
            try await unavailable.execute(.pause)
            XCTFail("Expected unavailable failure")
        } catch let error as IINAPluginBridgeClientError {
            XCTAssertEqual(error, .unavailable)
        }
    }
}

final class FakeIINAPluginBridgeTransport: IINAPluginBridgeTransporting {
    private var responses: [String]
    private var streamMessages: [String]
    private let error: IINAPluginBridgeClientError?
    private(set) var sentMessages: [[String: Any]] = []
    private(set) var messageTimeouts: [TimeInterval] = []

    init(
        responses: [String] = [],
        streamMessages: [String] = [],
        error: IINAPluginBridgeClientError? = nil
    ) {
        self.responses = responses
        self.streamMessages = streamMessages
        self.error = error
    }

    func roundTrip(
        _ message: String,
        timeout: TimeInterval,
        ignoring shouldIgnore: @escaping (String) -> Bool
    ) async throws -> String {
        let data = try XCTUnwrap(message.data(using: .utf8))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        sentMessages.append(object)

        if let error {
            throw error
        }

        while !responses.isEmpty {
            let response = responses.removeFirst()
            if shouldIgnore(response) {
                continue
            }
            return response
        }

        return #"{"id":1,"version":2,"ok":true}"#
    }

    func messages(timeout: TimeInterval) -> AsyncThrowingStream<String, Error> {
        messageTimeouts.append(timeout)
        return AsyncThrowingStream<String, Error> { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }

            for message in streamMessages {
                continuation.yield(message)
            }
            continuation.finish()
        }
    }
}

private func XCTAssertEqualAsync<T: Equatable>(
    _ expression1: @autoclosure () async throws -> T,
    _ expression2: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        let value1 = try await expression1()
        let value2 = try await expression2()
        XCTAssertEqual(value1, value2, file: file, line: line)
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}

private func XCTAssertThrowsProtocolFailure<T>(
    _ expression: @autoclosure () async throws -> T,
    _ expected: BridgeProtocolFailure,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected protocol failure", file: file, line: line)
    } catch let IINAPluginBridgeClientError.protocolFailure(failure) {
        XCTAssertEqual(failure, expected, file: file, line: line)
    } catch {
        XCTFail("Expected protocol failure \(expected), got \(error)", file: file, line: line)
    }
}
