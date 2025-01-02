// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

/// A generic interface for sinking log messages from the Swift wrapper
/// and go
public protocol LogSink: Sendable {
    /// An optional file handle.  The go backend will write all internal logs
    /// to this.  STDOUT_FILENO or a handle to a writable file.
    var logFileHandle: Int32? { get }

    /// Called for swfit interal logs.
    func log(_ message: String)
}

/// Dumps all internal logs to NSLog and go logs to stdout
struct DefaultLogger: LogSink {
    var logFileHandle: Int32? = STDOUT_FILENO

    func log(_ message: String) {
        NSLog(message)
    }
}

/// Discards all logs
struct BlackholeLogger: LogSink {
    var logFileHandle: Int32?
    
    func log(_ message: String) {
        // Go back to the Shadow!
    }
}
