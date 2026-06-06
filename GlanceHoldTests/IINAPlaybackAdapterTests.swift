import XCTest
@testable import GlanceHold

final class IINAPlaybackAdapterTests: XCTestCase {
    func testPlayingPausedIdleAndUnavailableSnapshotsMapExactly() async {
        let client = FakeMPVJSONIPCClient()
        client.propertyValues = [
            "speed": .double(1.5),
            "pause": .bool(false),
            "idle-active": .bool(false)
        ]
        let adapter = IINAPlaybackAdapter(client: client)

        let playing = await adapter.snapshot()
        XCTAssertEqual(playing, .playing(speed: 1.5))

        client.propertyValues["pause"] = .bool(true)
        let paused = await adapter.snapshot()
        XCTAssertEqual(paused, .paused(speed: 1.5))

        client.propertyValues["idle-active"] = .bool(true)
        let idle = await adapter.snapshot()
        XCTAssertEqual(idle, .idle)

        client.propertyFailure = .unavailableSocket
        let unavailable = await adapter.snapshot()
        XCTAssertEqual(unavailable, .playerUnavailable)
    }

    func testMissingOrNonNumericSpeedIsUnavailableForControl() async {
        let client = FakeMPVJSONIPCClient()
        client.propertyValues = [
            "pause": .bool(false),
            "idle-active": .bool(false)
        ]
        let adapter = IINAPlaybackAdapter(client: client)

        let missingSpeed = await adapter.snapshot()
        XCTAssertEqual(missingSpeed, .playerUnavailable)

        client.propertyValues["speed"] = .string("1.5")
        let nonNumericSpeed = await adapter.snapshot()
        XCTAssertEqual(nonNumericSpeed, .playerUnavailable)
    }

    func testSpeedIntentsMapToSingleSetPropertyCommands() async throws {
        let client = FakeMPVJSONIPCClient()
        let adapter = IINAPlaybackAdapter(client: client)

        try await adapter.execute(.holdSpeedAtOne)
        XCTAssertEqual(client.commands, [
            [.string("set_property"), .string("speed"), .double(1.0)]
        ])

        try await adapter.execute(.restoreSpeed(1.25))
        XCTAssertEqual(client.commands, [
            [.string("set_property"), .string("speed"), .double(1.0)],
            [.string("set_property"), .string("speed"), .double(1.25)]
        ])
    }
}

private final class FakeMPVJSONIPCClient: MPVJSONIPCClienting {
    var propertyValues: [String: MPVJSONValue] = [:]
    var propertyFailure: MPVJSONIPCClientError?
    var commands: [[MPVJSONValue]] = []

    func getProperty(_ name: String) async throws -> MPVJSONValue {
        if let propertyFailure {
            throw propertyFailure
        }

        guard let value = propertyValues[name] else {
            throw MPVJSONIPCClientError.malformedResponse
        }

        return value
    }

    func send(command: [MPVJSONValue]) async throws {
        commands.append(command)
    }
}
