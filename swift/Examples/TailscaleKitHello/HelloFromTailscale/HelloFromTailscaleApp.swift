// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

@main
struct HelloFromTailscaleApp: App {
    let manager = HelloManager.shared

    var body: some Scene {
        WindowGroup {
            HelloView(dialer: manager, model: manager.model)
        }
    }
}
