// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import Combine

/// IncomingConnection is use to read incoming message from an inbound
/// connection.   IncomingConnections are not instantiated directly,
/// they are returned by Listener.accept
public actor IncomingConnection {
    private let logger: LogSink?
    private var conn: TailscaleConnection = 0
    private let reader: SocketReader

    public let remoteAddress: String?

    @Published public var state: ConnectionState = .idle

    init(conn: TailscaleConnection, remoteAddress: String?, logger: LogSink? = nil) async {
        self.logger = logger
        self.conn = conn
        self.state = .connected
        self.remoteAddress = remoteAddress
        reader = SocketReader(conn: conn)
    }

    deinit {
        if conn != 0 {
            unistd.close(conn)
        }
    }

    public func close() {
        if conn != 0 {
            unistd.close(conn)
            conn = 0
        }
        state = .closed
    }

    /// Returns up to size bytes from the connection.  Blocks until
    /// data is available
    public func receive(maximumLength: Int = 4096, timeout: Int32) async throws -> Data {
        guard state == .connected else {
            throw TailscaleError.connectionClosed
        }

        return try await reader.read(timeout: timeout, len: maximumLength)
    }

    /// Reads a complete message from the connection
    public func receiveMessage( timeout: Int32) async throws -> Data {
        guard state == .connected else {
            throw TailscaleError.connectionClosed
        }

        return try await reader.readAll(timeout: timeout)
    }
}

/// Serializes read operations from an IncomingConnection
private actor SocketReader {
    // We'll read in 2048 byte chunks which should be sufficient to hold the payload
    // of a single packet
    private static let maxBufferSize = 2048
    private let conn: TailscaleConnection
    private var buffer = [UInt8](repeating:0, count: maxBufferSize)

    init(conn: TailscaleConnection) {
        self.conn = conn
    }

    func read(timeout: Int32, len: Int) throws -> Data {
        var p: pollfd = .init(fd: conn, events: Int16(POLLIN), revents: 0)
        let res = poll(&p, 1, timeout)
        guard res > 0 else {
            throw TailscaleError.readFailed
        }

        let bytesToRead = min(len, Self.maxBufferSize)
        var bytesRead = 0
        buffer.withUnsafeMutableBufferPointer { ptr in
            bytesRead = unistd.read(conn, ptr.baseAddress, bytesToRead)
        }

        if bytesRead < 0 {
            throw TailscaleError.readFailed
        }
        return Data(buffer[0..<bytesRead])
    }

    func readAll(timeout: Int32) throws -> Data {
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

