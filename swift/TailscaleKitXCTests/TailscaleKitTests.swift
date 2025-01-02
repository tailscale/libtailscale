// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import XCTest
@testable import TailscaleKit

final class TailscaleKitTests: XCTestCase {
    var controlURL: String = ""

    override func setUp() async throws {
        if controlURL == "" {
            var buf = [CChar](repeating:0, count: 1024)
            let res = buf.withUnsafeMutableBufferPointer { ptr in
                return run_control(ptr.baseAddress!, 1024)
            }
            controlURL = String(validatingCString: buf) ?? ""
            guard !controlURL.isEmpty else {
                throw TailscaleError.invalidControlURL
            }
            if res == 0 {
                print("Started control with url \(controlURL)")
            }
        }
    }

    override func tearDown() async throws {
        stop_control()
    }

    func testV4() async throws {
        try await runConnectionTests(for: .v4)
    }

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

            let msgReceived = expectation(description: "ex")
            let lisetnerUp = expectation(description: "lisetnerUp")

            var listenerAddr: String?
            var writerAddr: String?

            switch netType {
            case .v4:
                listenerAddr = ts1_addr.ip4
                writerAddr = ts2_addr.ip4
            case .v6:
                // barnstar: Validity of listener IPs is loadbearing.  accept fails
                // in the C code if you listen on an invalid addr.
                listenerAddr = if let a = ts1_addr.ip6 { "[\(a)]"} else { nil }
                writerAddr = if let a = ts2_addr.ip6 { "[\(a)]"} else { nil }
            case .none:
                XCTFail("Invalid IP Type")
            }

            guard let ts1Handle = await ts1.tailscale,
                  let ts2Handle = await ts2.tailscale,
                  let listenerAddr else {
                XCTFail()
                return
            }

            // Run a listener in a separate task, wait for the inbound
            // connection and read the data
            Task {
                let listener = try await Listener(tailscale: ts1Handle,
                                                  proto: .tcp,
                                                  address: ":8081",
                                                  logger: logger)
                lisetnerUp.fulfill()
                let inbound = try await listener.accept()
                await listener.close()

                // We can trust the backend here but this is slightly flaky since remoteAddress can be
                // nil for legitimate reasons.
                // let inboundIP = await inbound.remoteAddress
                // XCTAssertEqual(inboundIP, writerAddr)

                let got = try await inbound.receiveMessage(timeout: 2)
                print("got \(got)")
                XCTAssert(got == want)

                msgReceived.fulfill()
            }

            //Make sure somebody is listening
            await fulfillment(of: [lisetnerUp], timeout: 5.0)

            let outgoing = try await OutgoingConnection(tailscale: ts2Handle,
                                            to: "\(listenerAddr):8081",
                                            proto: .tcp,
                                            logger: logger)
            try await outgoing.connect()

            print("sending \(want)")
            try await outgoing.send(want)

            await fulfillment(of: [msgReceived], timeout: 5.0)

            print("closing  conn")
            await outgoing.close()

            try await ts1.down()
            try await ts2.down()
        } catch {
            XCTFail("Init Failed: \(error)")
        }
    }

    /// The hostCount here is load bearing.  Each mock host must have a unique
    /// path and hostname.
    var hostCount = 0
    func mockConfig() -> Configuration {
        let temp = getDocumentDirectoryPath().absoluteString + "tailscale\(hostCount)"
        hostCount += 1
        return Configuration(
            hostName: "testHost-\(hostCount)",
            path: temp,
            authKey: nil,
            controlURL: controlURL,
            ephemeral: false)
    }


    func testProxy() async throws {
        let config = mockConfig()
        let logger = BlackholeLogger()

        do {
            let ts1 = try TailscaleNode(config: config, logger: logger)
            try await ts1.up()

            let sessionConfig = try await URLSessionConfiguration.tailscaleSession(ts1)
            let session = URLSession(configuration: sessionConfig)

            let url = URL(string: "https://tailscale.com")!
            let req = URLRequest(url: url)
            let (data, _) = try await session.data(for: req)

            print("Got proxied data \(data.count)")
            XCTAssert(data.count > 0)
        }
    }


    func exampleProxiedTailnetRequest() async throws {
        let logger = DefaultLogger()

        do {
            let temp = getDocumentDirectoryPath().absoluteString + "tailscale\(hostCount)"
            let authKey = "put-you-auth-key-key-here"
            let config = Configuration(hostName: "TSNet-Test",
                                       path: temp,
                                       authKey: authKey,
                                       controlURL: Configuration.defaultControlURL,
                                       ephemeral: true)

            let ts1 = try TailscaleNode(config: config, logger: logger)
            try await ts1.up()

            let sessionConfig = try await URLSessionConfiguration.tailscaleSession(ts1)
            let session = URLSession(configuration: sessionConfig)

            // Replace this with the IP or fqdn of a service running on your tailnet
            let url = URL(string: "https://myservice.my-tailnet.ts.net")!
            let req = URLRequest(url: url)
            let (data, _) = try await session.data(for: req)

            print("Got proxied data \(data.count)")
            XCTAssert(data.count > 0)
        }
    }
}


func getDocumentDirectoryPath() -> URL {
    let arrayPaths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let docDirectoryPath = arrayPaths[0]
    return docDirectoryPath
}
