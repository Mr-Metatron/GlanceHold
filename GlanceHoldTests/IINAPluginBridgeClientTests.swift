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
    private let error: IINAPluginBridgeClientError?
    private(set) var sentMessages: [[String: Any]] = []

    init(responses: [String] = [], error: IINAPluginBridgeClientError? = nil) {
        self.responses = responses
        self.error = error
    }

    func roundTrip(_ message: String, timeout: TimeInterval) async throws -> String {
        let data = try XCTUnwrap(message.data(using: .utf8))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        sentMessages.append(object)

        if let error {
            throw error
        }

        return responses.isEmpty ? #"{"id":1,"version":1,"ok":true}"# : responses.removeFirst()
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
