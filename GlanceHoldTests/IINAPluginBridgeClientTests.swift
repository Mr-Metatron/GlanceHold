import XCTest
@testable import GlanceHold

final class IINAPluginBridgeClientTests: XCTestCase {
    func testSnapshotRequestUsesVersionedJSONMessage() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":1,"ok":true,"snapshot":{"state":"playing","speed":1.5}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        _ = try await client.snapshot()

        let request = try XCTUnwrap(transport.sentMessages.first)
        XCTAssertEqual(request["id"] as? Int, 1)
        XCTAssertEqual(request["version"] as? Int, 1)
        XCTAssertEqual(request["type"] as? String, "snapshot")
    }

    func testCommandRequestsMapToSetSpeedPauseAndResume() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":1,"ok":true}"#,
            #"{"id":2,"version":1,"ok":true}"#,
            #"{"id":3,"version":1,"ok":true}"#,
            #"{"id":4,"version":1,"ok":true}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        try await client.execute(.holdSpeedAtOne)
        try await client.execute(.restoreSpeed(1.25))
        try await client.execute(.pause)
        try await client.execute(.resume)

        XCTAssertEqual(transport.sentMessages.map { $0["command"] as? String }, [
            "setSpeed",
            "setSpeed",
            "pause",
            "resume"
        ])
        XCTAssertEqual(transport.sentMessages[0]["speed"] as? Double, 1.0)
        XCTAssertEqual(transport.sentMessages[1]["speed"] as? Double, 1.25)
    }

    func testConnectionRefusedMapsToPluginNeeded() async throws {
        let transport = FakeIINAPluginBridgeTransport(error: IINAPluginBridgeClientError.pluginNeeded)
        let client = IINAPluginBridgeClient(transport: transport)

        let status = await client.status()

        XCTAssertEqual(status, .setupNeeded)
    }

    func testStatusChangedMessageWithoutRequestIDDecodesAsPushedStatus() async throws {
        let transport = FakeIINAPluginBridgeTransport(streamMessages: [
            #"{"version":1,"type":"statusChanged","snapshot":{"state":"playing","speed":2.0}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        var iterator = client.statusUpdates().makeAsyncIterator()
        let status = await iterator.next()

        XCTAssertEqual(status, .playing(speed: 2.0))
        XCTAssertEqual(transport.sentMessages.count, 0)
    }

    func testToggleMonitoringRequestedMessageDecodesAsEventStreamWithoutCommand() async throws {
        let transport = FakeIINAPluginBridgeTransport(streamMessages: [
            #"{"version":1,"type":"toggleMonitoringRequested"}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        var iterator = client.monitoringToggleRequests().makeAsyncIterator()
        let request: Void? = await iterator.next()
        let nextRequest: Void? = await iterator.next()

        XCTAssertNotNil(request)
        XCTAssertNil(nextRequest)
        XCTAssertEqual(transport.sentMessages.count, 0)
    }

    func testStatusChangedMessageDoesNotSatisfySnapshotRequest() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"version":1,"type":"statusChanged","snapshot":{"state":"playing","speed":2.0}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        let status = await client.status()

        XCTAssertEqual(status, .unavailable)
        XCTAssertEqual(transport.sentMessages.count, 1)
    }

    func testStatusChangedBeforeSnapshotResponseDoesNotPoisonRequest() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"version":1,"type":"statusChanged","snapshot":{"state":"playing","speed":2.0}}"#,
            #"{"id":1,"version":1,"ok":true,"snapshot":{"state":"playing","speed":1.25}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        let status = await client.status()

        XCTAssertEqual(status, .playing(speed: 1.25))
        XCTAssertEqual(transport.sentMessages.count, 1)
    }

    func testToggleMonitoringRequestedBeforeSnapshotResponseDoesNotPoisonRequest() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"version":1,"type":"toggleMonitoringRequested"}"#,
            #"{"id":1,"version":1,"ok":true,"snapshot":{"state":"playing","speed":1.25}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        let status = await client.status()

        XCTAssertEqual(status, .playing(speed: 1.25))
        XCTAssertEqual(transport.sentMessages.count, 1)
    }

    func testToggleMonitoringRequestedStrictlyIgnoresUnsupportedShapes() async throws {
        let transport = FakeIINAPluginBridgeTransport(streamMessages: [
            #"{"version":2,"type":"toggleMonitoringRequested"}"#,
            #"{"id":7,"version":1,"type":"toggleMonitoringRequested"}"#,
            #"{"version":1,"type":"unknownEvent"}"#,
            #"not json"#,
            #"{"version":1,"type":"toggleMonitoringRequested"}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        var iterator = client.monitoringToggleRequests().makeAsyncIterator()
        let request: Void? = await iterator.next()
        let nextRequest: Void? = await iterator.next()

        XCTAssertNotNil(request)
        XCTAssertNil(nextRequest)
        XCTAssertEqual(transport.sentMessages.count, 0)
    }

    func testStatusChangedWithRequestIDIsStillTreatedAsResponse() async throws {
        let transport = FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":1,"type":"statusChanged","ok":true,"snapshot":{"state":"playing","speed":1.75}}"#
        ])
        let client = IINAPluginBridgeClient(transport: transport)

        let status = await client.status()

        XCTAssertEqual(status, .playing(speed: 1.75))
        XCTAssertEqual(transport.sentMessages.count, 1)
    }

    func testMalformedProtocolAndFailedCommandMapToUnavailable() async throws {
        let malformed = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: ["not json"]))
        await XCTAssertEqualAsync(await malformed.status(), .unavailable)

        let mismatched = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":999,"version":1,"ok":true,"snapshot":{"state":"playing","speed":1.5}}"#
        ]))
        await XCTAssertEqualAsync(await mismatched.status(), .unavailable)

        let unknownState = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":1,"ok":true,"snapshot":{"state":"buffering","speed":1.5}}"#
        ]))
        await XCTAssertEqualAsync(await unknownState.status(), .unavailable)

        let failed = IINAPluginBridgeClient(transport: FakeIINAPluginBridgeTransport(responses: [
            #"{"id":1,"version":1,"ok":false,"error":"unavailable"}"#
        ]))

        do {
            try await failed.execute(.pause)
            XCTFail("Expected command failure")
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

        return #"{"id":1,"version":1,"ok":true}"#
    }

    func messages(timeout: TimeInterval) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
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
