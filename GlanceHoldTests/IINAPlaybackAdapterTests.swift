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
        let adapter = IINAPlaybackAdapter(client: client, socketExists: { _ in true })

        let playing = await adapter.snapshot()
        XCTAssertEqual(playing, .playing(speed: 1.5))

        client.propertyValues["pause"] = .bool(true)
        let paused = await adapter.snapshot()
        XCTAssertEqual(paused, .paused(speed: 1.5))

        client.propertyValues["idle-active"] = .bool(true)
        let idle = await adapter.snapshot()
        XCTAssertEqual(idle, .idle)

        client.propertyFailure = .timeout
        let unavailable = await adapter.snapshot()
        XCTAssertEqual(unavailable, .playerUnavailable)
    }

    func testMissingSocketMapsToSetupNeededBeforeIPCRead() async {
        let client = FakeMPVJSONIPCClient()
        let adapter = IINAPlaybackAdapter(client: client, socketExists: { _ in false })

        let snapshot = await adapter.snapshot()

        XCTAssertEqual(snapshot, .setupNeeded)
        XCTAssertEqual(client.propertyReads, [])
    }

    func testExistingSocketWithIPCFailureMapsToUnavailable() async {
        let client = FakeMPVJSONIPCClient()
        client.propertyFailure = .unavailableSocket
        let adapter = IINAPlaybackAdapter(client: client, socketExists: { _ in true })

        let snapshot = await adapter.snapshot()

        XCTAssertEqual(snapshot, .playerUnavailable)
        XCTAssertEqual(client.propertyReads, ["speed"])
    }

    func testMissingOrNonNumericSpeedIsUnavailableForControl() async {
        let client = FakeMPVJSONIPCClient()
        client.propertyValues = [
            "pause": .bool(false),
            "idle-active": .bool(false)
        ]
        let adapter = IINAPlaybackAdapter(client: client, socketExists: { _ in true })

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

    func testPauseAndResumeMapToPausePropertyCommands() async throws {
        let client = FakeMPVJSONIPCClient()
        let adapter = IINAPlaybackAdapter(client: client)

        try await adapter.execute(.pause)
        XCTAssertEqual(client.commands, [
            [.string("set_property"), .string("pause"), .bool(true)]
        ])

        try await adapter.execute(.resume)
        XCTAssertEqual(client.commands, [
            [.string("set_property"), .string("pause"), .bool(true)],
            [.string("set_property"), .string("pause"), .bool(false)]
        ])
    }
}

private final class FakeMPVJSONIPCClient: MPVJSONIPCClienting {
    var propertyValues: [String: MPVJSONValue] = [:]
    var propertyFailure: MPVJSONIPCClientError?
    var propertyReads: [String] = []
    var commands: [[MPVJSONValue]] = []
    var socketPath = "/tmp/glancehold-iina-ipc.sock"

    func getProperty(_ name: String) async throws -> MPVJSONValue {
        propertyReads.append(name)

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
