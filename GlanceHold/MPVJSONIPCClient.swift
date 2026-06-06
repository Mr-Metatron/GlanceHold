import Foundation
import Network

enum MPVJSONValue: Equatable, Codable {
    case string(String)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported mpv JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var doubleValue: Double? {
        if case let .double(value) = self {
            return value
        }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self {
            return value
        }
        return nil
    }
}

enum MPVJSONIPCClientError: Error, Equatable {
    case unavailableSocket
    case timeout
    case malformedResponse
    case requestMismatch
    case mpvCommandError(String)
}

protocol MPVJSONIPCTransporting {
    func roundTrip(_ request: Data, socketPath: String, timeout: TimeInterval) async throws -> Data
}

protocol MPVJSONIPCClienting {
    func getProperty(_ name: String) async throws -> MPVJSONValue
    func send(command: [MPVJSONValue]) async throws
}

final class MPVJSONIPCClient: MPVJSONIPCClienting {
    private struct Request: Encodable {
        var command: [MPVJSONValue]
        var request_id: Int
    }

    private struct Reply: Decodable {
        var request_id: Int?
        var error: String
        var data: MPVJSONValue?
    }

    private let socketPath: String
    private let transport: MPVJSONIPCTransporting
    private let timeout: TimeInterval
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let requestIDLock = NSLock()
    private var nextRequestID = 1

    init(
        socketPath: String = "/tmp/glancehold-iina-ipc.sock",
        transport: MPVJSONIPCTransporting = NetworkMPVJSONIPCTransport(),
        timeout: TimeInterval = 1.0,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.socketPath = socketPath
        self.transport = transport
        self.timeout = timeout
        self.encoder = encoder
        self.decoder = decoder
    }

    func getProperty(_ name: String) async throws -> MPVJSONValue {
        try await sendCommand([.string("get_property"), .string(name)])
    }

    func send(command: [MPVJSONValue]) async throws {
        _ = try await sendCommand(command)
    }

    private func sendCommand(_ command: [MPVJSONValue]) async throws -> MPVJSONValue {
        let requestID = nextID()
        let request = Request(command: command, request_id: requestID)
        var data = try encoder.encode(request)
        data.append(0x0A)

        let response = try await transport.roundTrip(data, socketPath: socketPath, timeout: timeout)
        guard let reply = try? decoder.decode(Reply.self, from: response) else {
            throw MPVJSONIPCClientError.malformedResponse
        }

        guard reply.request_id == requestID else {
            throw MPVJSONIPCClientError.requestMismatch
        }

        guard reply.error == "success" else {
            throw MPVJSONIPCClientError.mpvCommandError(reply.error)
        }

        return reply.data ?? .null
    }

    private func nextID() -> Int {
        requestIDLock.lock()
        defer { requestIDLock.unlock() }

        let requestID = nextRequestID
        nextRequestID += 1
        return requestID
    }
}

struct NetworkMPVJSONIPCTransport: MPVJSONIPCTransporting {
    func roundTrip(_ request: Data, socketPath: String, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(to: NWEndpoint.unix(path: socketPath), using: .tcp)
            let stateQueue = DispatchQueue(label: "com.metatron.GlanceHold.mpv.ipc")
            let box = CompletionBox(continuation: continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: request, completion: .contentProcessed { error in
                        if error != nil {
                            box.resume(throwing: MPVJSONIPCClientError.unavailableSocket)
                            connection.cancel()
                            return
                        }

                        receiveLine(from: connection, into: Data(), completion: box)
                    })
                case .failed, .cancelled:
                    box.resume(throwing: MPVJSONIPCClientError.unavailableSocket)
                default:
                    break
                }
            }

            stateQueue.asyncAfter(deadline: .now() + timeout) {
                box.resume(throwing: MPVJSONIPCClientError.timeout)
                connection.cancel()
            }

            connection.start(queue: stateQueue)
        }
    }

    private func receiveLine(
        from connection: NWConnection,
        into buffer: Data,
        completion: CompletionBox
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
            if error != nil {
                completion.resume(throwing: MPVJSONIPCClientError.unavailableSocket)
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if nextBuffer.contains(0x0A) || isComplete {
                completion.resume(returning: nextBuffer)
                connection.cancel()
                return
            }

            receiveLine(from: connection, into: nextBuffer, completion: completion)
        }
    }
}

private final class CompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<Data, Error>

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func resume(returning data: Data) {
        resume {
            continuation.resume(returning: data)
        }
    }

    func resume(throwing error: Error) {
        resume {
            continuation.resume(throwing: error)
        }
    }

    private func resume(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else {
            return
        }

        didResume = true
        block()
    }
}
