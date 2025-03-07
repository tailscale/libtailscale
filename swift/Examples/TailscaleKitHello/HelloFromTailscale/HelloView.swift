// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI


struct HelloView: View {
    @ObservedObject var model : HelloViewModel
    let dialer: Dialer

    init(dialer: Dialer) {
        self.dialer = dialer
        self.model = HelloViewModel()
    }


    var body: some View {
        VStack {
            Text("TailscaleKit Sample App.  See README.md for setup instructions.")
                .font(.title)
                .padding(20)
            Text(model.message)
                .font(.title2)
            Button("Phone Home!") {
                model.runRequest(dialer)
            }
        }
        .padding()
    }
}

actor PreviewDialer: Dialer {
    func phoneHome(_ setMessage: @escaping @Sendable (String) async -> Void) async {
        await setMessage("Hello from Preview!")
    }
}

#Preview {
    let d = PreviewDialer()
    HelloView(dialer: d)
}
