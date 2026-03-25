import SwiftUI

@main
struct HeadSafeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var audioManager = AudioDeviceManager()
    @AppStorage("volumeLimit") private var volumeLimit: Double = 0.7
    @AppStorage("isEnabled") private var isEnabled: Bool = true

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(audioManager: audioManager)
        } label: {
            Image(systemName: audioManager.isLimiting ? "headphones.circle.fill" : "headphones.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)
    }
}
