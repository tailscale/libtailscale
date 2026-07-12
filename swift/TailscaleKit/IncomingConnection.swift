// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(Combine)
import Combine
#endif

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// IncomingConnection is use to read incoming message from an inbound
/// connection. IncomingConnections are not instantiated directly,
/// they are returned by Listener.accept
public actor IncomingConnection {
    private let logger: (any LogSink)?
    private var conn: TailscaleConnection = 0
    private let reader: SocketReader

    public let remoteAddress: String?

    #if canImport(Combine)
    @Published var _state: ConnectionState = .idle
    #else
    private var stateBroadcaster = StateBroadcaster<ConnectionState>(.idle)
    #endif

    public func state() -> some AsyncSequence<ConnectionState, Never> {
        #if canImport(Combine)
        $_state
            .removeDuplicates()
            .eraseToAnyPublisher()
            .values
        #else
        stateBroadcaster.subscribe()
        #endif
    }

    init(conn: TailscaleConnection, remoteAddress: String?, logger: (any LogSink)? = nil) async {
        self.logger = logger
        self.conn = conn
        self.remoteAddress = remoteAddress
        self.reader = SocketReader(conn: conn)
        setConnectionState(.connected)
    }

    deinit {
        if conn != 0 {
            _ = System.close(conn)
        }
    }

    public func close() {
        if conn != 0 {
            _ = System.close(conn)
            conn = 0
        }
        setConnectionState(.closed)
    }

    /// Returns up to size bytes from the connection.  Blocks until
    /// data is available
    public func receive(maximumLength: Int = 4096, timeout: TimeInterval) async throws -> Data {
        guard connectionState == .connected else {
            throw TailscaleError.connectionClosed
        }

        return try await reader.read(timeout: timeout, len: maximumLength)
    }

    /// Reads a complete message from the connection
    public func receiveMessage(timeout: TimeInterval) async throws -> Data {
        guard connectionState == .connected else {
            throw TailscaleError.connectionClosed
        }

        return try await reader.readAll(timeout: timeout)
    }

    private var connectionState: ConnectionState {
        #if canImport(Combine)
        _state
        #else
        stateBroadcaster.value
        #endif
    }

    private func setConnectionState(_ state: ConnectionState) {
        #if canImport(Combine)
        _state = state
        #else
        stateBroadcaster.set(state)
        if state == .closed {
            stateBroadcaster.finish()
        }
        #endif
    }
}

/// Serializes read operations from an IncomingConnection
private actor SocketReader {
    // We'll read in 2048 byte chunks which should be sufficient to hold the payload
    // of a single packet
    private static let maxBufferSize = 2048
    private let conn: TailscaleConnection
    private var buffer = [UInt8](repeating: 0, count: maxBufferSize)

    init(conn: TailscaleConnection) {
        self.conn = conn
    }

    func read(timeout: TimeInterval, len: Int) throws -> Data {
        guard timeout >= 0, timeout * 1000 <= Double(Int32.max) else {
            throw TailscaleError.invalidTimeout
        }

        var p: pollfd = .init(fd: conn, events: Int16(POLLIN), revents: 0)
        let res = poll(&p, 1, Int32(timeout * 1000))
        guard res > 0 else {
            throw TailscaleError.readFailed
        }

        let bytesToRead = min(len, Self.maxBufferSize)
        let bytesRead = buffer.withUnsafeMutableBufferPointer { ptr in
            System.read(conn, ptr.baseAddress, bytesToRead)
        }

        if bytesRead < 0 {
            throw TailscaleError.readFailed
        }
        return Data(buffer[0..<bytesRead])
    }

    func readAll(timeout: TimeInterval) throws -> Data {
        var data: Data = .init()
        while true {
            let read = try read(timeout: timeout, len: Self.maxBufferSize)
            data.append(read)
            if read.count < Self.maxBufferSize {
                break
            }
        }
        return data
    }
}
