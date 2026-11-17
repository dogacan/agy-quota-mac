import AgyQuotaCore
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct AgyQuotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = QuotaViewModel()

    var body: some Scene {
        MenuBarExtra {
            QuotaPopoverView(viewModel: viewModel)
        } label: {
            Image(nsImage: viewModel.menuBarIcon)
                .renderingMode(viewModel.monochromeIcons ? .template : .original)
        }
        .menuBarExtraStyle(.window)
    }
}
