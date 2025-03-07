// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import Foundation


public enum TailscaleError: Error {
    case badInterfaceHandle     ///< The tailscale handle is bad.
    case listenerClosed         ///< The listener was closed and cannot accept new connections
    case invalidTimeout         ///< The provided listener timeout is invalid
    case connectionClosed       ///< The underlying connection is closed
    case readFailed             ///< Read failed
    case shortWrite             ///< Some data was not written to the connection
    case invalidProxyAddress    ///< Some data was not written to the connection
    case invalidControlURL      ///< The provided control URL is invalid

    case cannotFetchIps(_ details: String? = nil)                   ///< The IPs for the Tailscale server could not be read
    case posixError(_ err: POSIXError, _ details: String? = nil)    ///< A posix error was thrown with the given err code and details
    case unknownPosixError(_ err: Int32, _ details: String? = nil)  ///< An unknown posix error occurred
    case internalError(_ details: String? = nil)                    ///< A generic internal error occurred

    /// Create a Tailscale error from an underlying posix error code
    static func fromPosixErrCode(_ code: Int32, _ details: String? = nil) -> TailscaleError {
        if code == -1 {
            return .internalError(details)
        }
        if let code = POSIXErrorCode(rawValue: code){
            return .posixError( POSIXError(code))
        }
        return unknownPosixError(code, details)
    }
}


extension TailscaleHandle {
    static let kMaxErrorMessageLength: Int = 256

    /// Returns the last error message in the Tailscale server as a string.
    /// Handles messages up to kMaxErrorMessageLength bytes only.
    internal func getErrorMessage() -> String {
        let buf = UnsafeMutablePointer<Int8>.allocate(capacity: Self.kMaxErrorMessageLength)
        defer {
            buf.deallocate()

        }
        let res = tailscale_errmsg(self, buf, 256)
        if res != 0 {
            return "Error fetch failure: \(res)"
        }
        return String(cString: buf)
    }
}
