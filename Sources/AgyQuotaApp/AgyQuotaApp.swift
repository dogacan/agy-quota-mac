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
            let icon = MenuBarIconRenderer.render(
                snapshot: viewModel.snapshot,
                style: viewModel.menuBarStyle,
                metric: viewModel.menuBarMetric,
                monochrome: viewModel.monochromeIcons
            )
            Image(nsImage: icon)
                .renderingMode(viewModel.monochromeIcons ? .template : .original)
        }
        .menuBarExtraStyle(.window)
    }
}
