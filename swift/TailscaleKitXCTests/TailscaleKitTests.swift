// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(CTstestControl)
import CTstestControl
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TailscaleKit

@Suite 
struct TailscaleKitTests: ~Copyable {
    let controlURL: String

    init() throws {
        var buf = [CChar](repeating: 0, count: 1024)
        let res = buf.withUnsafeMutableBufferPointer { ptr in
            run_control(ptr.baseAddress!, 1024)
        }
        let len = buf.firstIndex(where: { $0 == 0 }) ?? 0
        controlURL = String(validating: buf[0..<len], as: UTF8.self) ?? ""
        guard !controlURL.isEmpty else {
            throw TailscaleError.invalidControlURL
        }
        if res == 0 {
            print("Started control with url \(controlURL)")
        }
    }

    deinit {
        stop_control()
    }

    @Test 
    func testV4() async throws {
        try await runConnectionTests(for: .v4)
    }

    @Test 
    func testV6() async throws {
        try await runConnectionTests(for: .v6)
    }

    func runConnectionTests(for netType: IPAddrType) async throws {
        let logger = BlackholeLogger()

        let want = "Hello Tailscale".data(using: .utf8)!

        do {
            let ts1 = try TailscaleNode(config: mockConfig(), logger: logger)
            try await ts1.up()

            let ts2 = try TailscaleNode(config: mockConfig(), logger: logger)
            try await ts2.up()

            let ts1_addr = try await ts1.addrs()
            let ts2_addr = try await ts2.addrs()

            print("ts1 addresses are \(ts1_addr)")
            print("ts2_adddreses are \(ts2_addr)")

            var listenerAddr: String?

            switch netType {
            case .v4:
                listenerAddr = ts1_addr.ip4
            case .v6:
                // barnstar: Validity of listener IPs is loadbearing.  accept fails
                // in the C code if you listen on an invalid addr.
                listenerAddr = if let a = ts1_addr.ip6 { "[\(a)]"} else { nil }
            case .none:
                Issue.record("Invalid IP Type")
            }

            guard let ts1Handle = await ts1.tailscale,
                  let ts2Handle = await ts2.tailscale,
                  let listenerAddr else {
                Issue.record("Setup failed")
                return
            }

            // Creating the Listener performs tailscale_listen synchronously, so
            // by the time this returns something is already listening.
            let listener = try await Listener(tailscale: ts1Handle,
                                              proto: .tcp,
                                              address: ":8081",
                                              logger: logger)

            // Accept the inbound connection and read the message concurrently
            // with dialing out below.
            func receiveMessage() async throws -> Data {
                let inbound = try await listener.accept()
                await listener.close()

                // We can trust the backend here but this is slightly flaky since remoteAddress can be
                // nil for legitimate reasons.
                // let inboundIP = await inbound.remoteAddress
                // #expect(inboundIP == writerAddr)

                return try await inbound.receiveMessage(timeout: 2)
            }
            async let receivedMessage = receiveMessage()

            let outgoing = try await OutgoingConnection(tailscale: ts2Handle,
                                            to: "\(listenerAddr):8081",
                                            proto: .tcp,
                                            logger: logger)
            try await outgoing.connect()

            print("sending \(want)")
            try await outgoing.send(want)

            let got = try await receivedMessage
            print("got \(got)")
            #expect(got == want)

            print("closing  conn")
            await outgoing.close()

            try await ts1.down()
            try await ts2.down()
        } catch {
            Issue.record("Init Failed: \(error)")
        }
    }

    /// Each mock host must have a unique path and hostname; a UUID guarantees
    /// that without needing mutable state on the suite.
    func mockConfig() -> Configuration {
        let id = UUID().uuidString
        let temp = getDocumentDirectoryPath().appending(path: "tailscale-\(id)").path
        return Configuration(
            hostName: "testHost-\(id)",
            path: temp,
            authKey: nil,
            controlURL: controlURL,
            ephemeral: false)
    }

    #if canImport(Network)
    /// Tests that we can fetch a URL via our proxy (though this isn't a URL
    /// on the tailnet...)
    @Test 
    func testProxy() async throws {
        let config = mockConfig()
        let logger = BlackholeLogger()

        do {
            let ts1 = try TailscaleNode(config: config, logger: logger)
            try await ts1.up()

            let (sessionConfig, _) = try await URLSessionConfiguration.tailscaleSession(ts1)
            let session = URLSession(configuration: sessionConfig)

            let url = URL(string: "https://tailscale.com")!
            let req = URLRequest(url: url)
            let (data, _) = try await session.data(for: req)

            print("Got proxied data \(data.count)")
            #expect(data.count > 0)
        }
    }
    #endif

    /// Tests that localAPI is functional
    @Test 
    func testStatus() async throws {
        let config = mockConfig()
        let logger = BlackholeLogger()

        do {
            let ts1 = try TailscaleNode(config: config, logger: logger)
            try await ts1.up()

            // The local node should be running and online
            let api = LocalAPIClient(localNode: ts1, logger: logger)
            let status = try await api.backendStatus()
            #expect(status.BackendState == "Running")

            let peerStatus = status.SelfStatus!
            #expect(peerStatus.Online)
        } catch {
            Issue.record("\(error.localizedDescription)")
        }
    }
}

func getDocumentDirectoryPath() -> URL {
    let arrayPaths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let docDirectoryPath = arrayPaths[0]
    return docDirectoryPath
}
