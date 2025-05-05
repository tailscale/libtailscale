// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

struct Settings {
    // Replace with an actual auth key generated from the Tailscale admin console
    static let authKey = "tskey-auth-your-auth-key"
    // Note: The sample has a transport exception for http on ts.net so http:// is ok...
    // The "Phone Home" button will load the contents of this URL, it should be on your Tailnet.
    static let tailnetURL = "http://myserver.my-tailnet.ts.net"
    // Identifies this application in the Tailscale admin console.
    static let hostName = "Hello-From-Tailsacle-Sample-App"
}


func getDocumentDirectoryPath() -> URL {
    let arrayPaths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let docDirectoryPath = arrayPaths[0]
    return docDirectoryPath
}
