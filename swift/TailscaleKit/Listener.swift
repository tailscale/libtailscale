// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import Combine
import Foundation

/// A Listener is used to await incoming connections from another
/// Tailnet node.
public actor Listener {
    private var tailscale: TailscaleHandle 
    private var listener: TailscaleListener = 0
    private var proto: NetProtocol
    private var address: String

    private let logger: LogSink?

    @Published var _state: ListenerState = .idle

    public func state() -> any AsyncSequence<ListenerState, Never> {
        $_state
            .removeDuplicates()
            .eraseToAnyPublisher()
            .values
    }

    /// Initializes and readies a new listener
    ///
    /// @param tailscale A handle to a Tailscale server
    /// @param proto The ip protocol to listen for
    /// @param address The address (ip:port or port) to listen on
    /// @param logger An optional LogSink
    public init(tailscale: TailscaleHandle,
         proto: NetProtocol,
         address: String,
         logger: LogSink? = nil) async throws {
        self.logger = logger
        self.tailscale = tailscale
        self.address = address
        self.proto = proto

        let res = tailscale_listen(tailscale, proto.rawValue, address, &listener)

        guard res == 0 else {
            _state = .failed
            let msg = tailscale.getErrorMessage()
            let err = TailscaleError.fromPosixErrCode(res, msg)
            logger?.log("Listener failed to initialize: \(msg) (\(err.localizedDescription))")
            throw err
        }
        _state = .listening
    }

    deinit {
        if listener != 0 {
            unistd.close(listener)
        }
    }

    /// Closes the listener.  It cannot be restarted
    /// Listeners will be closed automatically on deallocation
    public func close() {
        if listener != 0 {
            unistd.close(listener)
            listener = 0
        }
        _state = .closed
    }

    /// Blocks and awaits a new incoming connection
    ///
    /// @See tailscale_accept in Tailscale.h
    /// @See tailscale_getremoteaddr in Tailscale.h
    ///
    /// @param timeout The timeout for the underlying poll(2) in seconds.  This has a maximum
    ///                value of Int32.max ms and supports millisecond precision per poll(2)
    /// @throws TailscaleError on failure or timeout
    /// @returns An incoming connection from which you can receive() Data
    public func accept(timeout: TimeInterval = 60) async throws -> IncomingConnection {
        if timeout * 1000 > Double(Int32.max) || timeout < 0 {
            throw TailscaleError.invalidTimeout
        }

        logger?.log("Listening for \(proto.rawValue) on \(address)")

        var p: pollfd = .init(fd: listener, events: Int16(POLLIN), revents: 0)
        let ret = poll(&p, 1, Int32(timeout * 1000))
        guard ret > 0 else {
            close()
            throw TailscaleError.fromPosixErrCode(errno, "Poll failed")
        }

        logger?.log("Accepting \(proto.rawValue) connection via \(address)")
        guard listener != 0 else {
            close()
            throw TailscaleError.listenerClosed
        }

        var connfd: Int32 = 0
        let res = tailscale_accept(listener, &connfd)
        guard res == 0 else {
            close()
            let msg = tailscale.getErrorMessage()
            throw TailscaleError.fromPosixErrCode(res, msg)
        }

        /// We extract the remove address here for utility so you know
        /// who's calling, so you can dial back.
        var remoteAddress: String?
        var buffer = [Int8](repeating:0, count: 64)
        buffer.withUnsafeMutableBufferPointer { buf in
            let err = tailscale_getremoteaddr(listener, connfd, buf.baseAddress, 64)
            if err == 0 {
                remoteAddress = String(cString: buf.baseAddress!)
            } else {
                let msg = tailscale.getErrorMessage()
                let err = TailscaleError.fromPosixErrCode(err, msg)
                logger?.log("Failed to get remote address: \(msg) \(err.localizedDescription)")
                // Do not throw here.  Lack of a remote address is not fatal
                // The caller can directly invoke server.addrs() if required.
            }
        }

        logger?.log("Accepted \(proto.rawValue) fd:\(connfd) from:\(remoteAddress ?? "unknown")")
        return await IncomingConnection(conn: connfd,
                              remoteAddress: remoteAddress,
                              logger: logger)
    }
}
