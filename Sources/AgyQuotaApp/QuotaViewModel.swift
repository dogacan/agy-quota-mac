import AgyQuotaCore
import AppKit
import Foundation
import ServiceManagement

/// Observable state and background polling coordinator for the menu bar app.
@MainActor
final class QuotaViewModel: ObservableObject {
    private enum DefaultsKey {
        static let menuBarStyle = "menuBarStyle"
        static let menuBarMetric = "menuBarMetric"
        static let monochromeIcons = "monochromeIcons"
        static let refreshInterval = "refreshIntervalSeconds"
        static let customAgyPath = "customAgyPath"
    }

    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var resolvedBinaryPath: String?
    @Published var showSettings: Bool = false
    @Published private(set) var now: Date = Date()
    @Published private(set) var launchAtLoginEnabled: Bool = false
    @Published private(set) var launchAtLoginError: String?

    @Published var menuBarStyle: MenuBarStyle {
        didSet {
            UserDefaults.standard.set(menuBarStyle.rawValue, forKey: DefaultsKey.menuBarStyle)
        }
    }

    @Published var menuBarMetric: MenuBarMetric {
        didSet {
            UserDefaults.standard.set(menuBarMetric.rawValue, forKey: DefaultsKey.menuBarMetric)
        }
    }

    @Published var monochromeIcons: Bool {
        didSet {
            UserDefaults.standard.set(monochromeIcons, forKey: DefaultsKey.monochromeIcons)
        }
    }

    @Published var refreshInterval: RefreshIntervalOption {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: DefaultsKey.refreshInterval)
            reschedulePolling()
        }
    }

    @Published var customAgyPath: String {
        didSet {
            UserDefaults.standard.set(customAgyPath, forKey: DefaultsKey.customAgyPath)
        }
    }

    private let runner = AgyRunner()
    private var pollingTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard

        if let rawStyle = defaults.string(forKey: DefaultsKey.menuBarStyle),
           let parsedStyle = MenuBarStyle(rawValue: rawStyle) {
            self.menuBarStyle = parsedStyle
        } else {
            self.menuBarStyle = .ringsAndPercent
        }

        if let rawMetric = defaults.string(forKey: DefaultsKey.menuBarMetric),
           let parsedMetric = MenuBarMetric(rawValue: rawMetric) {
            self.menuBarMetric = parsedMetric
        } else {
            self.menuBarMetric = .lowest
        }

        self.monochromeIcons = defaults.object(forKey: DefaultsKey.monochromeIcons) as? Bool ?? false

        if defaults.object(forKey: DefaultsKey.refreshInterval) != nil {
            let storedSeconds = defaults.integer(forKey: DefaultsKey.refreshInterval)
            self.refreshInterval = RefreshIntervalOption(rawValue: storedSeconds) ?? .fiveMinutes
        } else {
            self.refreshInterval = .fiveMinutes
        }

        self.customAgyPath = defaults.string(forKey: DefaultsKey.customAgyPath) ?? ""
        self.launchAtLoginEnabled = Self.currentLaunchAtLoginState()

        startClockTicker()
        observeSystemWake()
        reschedulePolling()

        Task { [weak self] in
            await self?.refresh()
        }
    }

    deinit {
        pollingTask?.cancel()
        clockTask?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    /// Manually or programmatically triggers an `agy --print "/quota"` refresh.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await runner.fetchSnapshot(customBinaryPath: customAgyPath)
            snapshot = result.snapshot
            resolvedBinaryPath = result.resolvedBinaryPath
            lastError = nil
            now = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Registers or unregisters the app as a login item via `SMAppService`.
    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = "Move app to /Applications to enable Launch at Login (\(error.localizedDescription))."
        }
        launchAtLoginEnabled = Self.currentLaunchAtLoginState()
    }

    /// Human-readable timestamp summary for the popover header.
    var lastUpdatedText: String {
        if isRefreshing && snapshot == nil {
            return "Refreshing…"
        }
        guard let fetchedAt = snapshot?.fetchedAt else {
            return "Not updated yet"
        }
        let elapsed = max(0, Int(now.timeIntervalSince(fetchedAt)))
        if elapsed < 60 {
            return isRefreshing ? "Refreshing…" : "Updated just now"
        }
        let minutes = elapsed / 60
        if minutes < 60 {
            return "Updated \(minutes)m ago"
        }
        let hours = minutes / 60
        return "Updated \(hours)h ago"
    }

    private static func currentLaunchAtLoginState() -> Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    private func reschedulePolling() {
        pollingTask?.cancel()
        guard let interval = refreshInterval.seconds else {
            pollingTask = nil
            return
        }

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }

    private func startClockTicker() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                self?.now = Date()
            }
        }
    }

    private func observeSystemWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }
}
