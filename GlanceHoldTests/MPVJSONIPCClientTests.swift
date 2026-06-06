import Foundation
import XCTest
@testable import GlanceHold

final class MPVJSONIPCClientTests: XCTestCase {
    func testCommandFramingIncludesRequestIDAndNewline() async throws {
        let transport = FakeMPVJSONIPCTransport()
        transport.response = #"{"request_id":1,"error":"success","data":1.25}"#.data(using: .utf8)!
        let client = MPVJSONIPCClient(socketPath: "/tmp/glancehold-iina-ipc.sock", transport: transport)

        _ = try await client.getProperty("speed")

        let request = try XCTUnwrap(String(data: transport.requests[0], encoding: .utf8))
        XCTAssertTrue(request.hasSuffix("\n"))
        XCTAssertTrue(request.contains(#""request_id":1"#))
        XCTAssertTrue(request.contains(#""command":["get_property","speed"]"#))
    }

    func testMalformedErrorAndMismatchedRepliesThrow() async throws {
        let malformed = FakeMPVJSONIPCTransport(response: Data("not-json\n".utf8))
        let malformedClient = MPVJSONIPCClient(socketPath: "/tmp/glancehold-iina-ipc.sock", transport: malformed)
        await XCTAssertThrowsTypedError(try await malformedClient.getProperty("speed"), .malformedResponse)

        let commandError = FakeMPVJSONIPCTransport(
            response: #"{"request_id":1,"error":"property unavailable"}"#.data(using: .utf8)!
        )
        let commandErrorClient = MPVJSONIPCClient(socketPath: "/tmp/glancehold-iina-ipc.sock", transport: commandError)
        await XCTAssertThrowsTypedError(
            try await commandErrorClient.getProperty("speed"),
            .mpvCommandError("property unavailable")
        )

        let mismatch = FakeMPVJSONIPCTransport(
            response: #"{"request_id":2,"error":"success","data":1.25}"#.data(using: .utf8)!
        )
        let mismatchClient = MPVJSONIPCClient(socketPath: "/tmp/glancehold-iina-ipc.sock", transport: mismatch)
        await XCTAssertThrowsTypedError(try await mismatchClient.getProperty("speed"), .requestMismatch)
    }
}

private final class FakeMPVJSONIPCTransport: MPVJSONIPCTransporting {
    var requests: [Data] = []
    var response: Data

    init(response: Data = #"{"request_id":1,"error":"success","data":null}"#.data(using: .utf8)!) {
        self.response = response
    }

    func roundTrip(_ request: Data, socketPath: String, timeout: TimeInterval) async throws -> Data {
        requests.append(request)
        return response
    }
}

private func XCTAssertThrowsTypedError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ expected: MPVJSONIPCClientError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch let error as MPVJSONIPCClientError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Expected \(expected), got \(error)", file: file, line: line)
    }
}
