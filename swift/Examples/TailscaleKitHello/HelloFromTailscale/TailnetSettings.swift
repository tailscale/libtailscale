// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

struct Settings {
    // An auth key generated from the Tailscale admin console.
    //
    // Leave this empty to authenticate interactively instead.  The node then asks
    // control for a login URL, which arrives on the IPN bus as
    // Ipn.Notify.BrowseToURL and is rendered by HelloView.  Open it to authorize
    // the node and the app carries on connecting.
    //
    // Either way, if your tailnet requires device approval the node waits in
    // NeedsMachineAuth until an admin approves it.
    static let authKey = ""
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
