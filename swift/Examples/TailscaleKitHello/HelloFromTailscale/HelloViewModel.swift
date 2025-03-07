

import SwiftUI
import Combine
import TailscaleKit

class HelloViewModel: ObservableObject, @unchecked Sendable {
    @Published var message: String = "Ready to phone home!"

    func setMessage(_ message: String) async {
        await MainActor.run {
            self.message =  message
        }
    }

    func runRequest(_ dialer: Dialer) {
        Task {
            await dialer.phoneHome(setMessage)
        }
    }
}
