// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif


/// Shown while the node waits for interactive authorization.  The URL is
/// selectable and copyable as well as clickable, since the node may be running
/// somewhere the link can't usefully be opened.
struct AuthPrompt: View {
    let url: URL
    @State private var copied = false

    var body: some View {
        VStack(spacing: 8) {
            Text("This node needs to be authorized.")
            Link("Open in browser", destination: url)
            HStack(spacing: 8) {
                Text(url.absoluteString)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Button(copied ? "Copied" : "Copy") {
                    copy(url.absoluteString)
                    copied = true
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func copy(_ string: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}


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
            Text(viewModel.selfNodeMessage)
            Text(viewModel.peerCountMessage)
            if let authURL = viewModel.authURL {
                AuthPrompt(url: authURL)
            }
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
