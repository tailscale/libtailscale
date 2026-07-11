// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

// Namespace for the platform libc calls. Actor types in this module declare
// their own close()/read() methods, which shadow the global libc functions
enum System {
    #if canImport(Darwin)
        static let close = Darwin.close
        static let read = Darwin.read
        static let write = Darwin.write
    #elseif canImport(Glibc)
        static let close = Glibc.close
        static let read = Glibc.read
        static let write = Glibc.write
    #elseif canImport(Musl)
        static let close = Musl.close
        static let read = Musl.read
        static let write = Musl.write
    #endif
}
