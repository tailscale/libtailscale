// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI


struct HelloView: View {
    @State var viewModel : HelloViewModel
    let dialer: Dialer

    init(dialer: Dialer, model: HelloModel) {
        self.dialer = dialer
        self.viewModel = HelloViewModel(model: model)
    }

    var body: some View {
        VStack {
            Text("TailscaleKit Sample App.  See README.md for setup instructions.")
                .font(.title3)
                .padding(20)
            Spacer(minLength: 5)
            Text(viewModel.stateMessage)
            Text(viewModel.peerCountMessage)
            Spacer(minLength: 5)
            Text(viewModel.message)
                .font(.title3)
            Button("Phone Home") {
                viewModel.runRequest(dialer)
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
    HelloView(dialer: d, model: HelloModel(logger: Logger()))
}
