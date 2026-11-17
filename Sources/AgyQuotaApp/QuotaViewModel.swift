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

    private struct MenuBarIconKey: Equatable {
        let geminiPercent: Int?
        let thirdPartyPercent: Int?
        let style: MenuBarStyle
        let monochrome: Bool
    }

    @Published private(set) var snapshot: QuotaSnapshot? {
        didSet {
            updateMenuBarIconIfNeeded()
        }
    }
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var resolvedBinaryPath: String?
    @Published var showSettings: Bool = false
    @Published private(set) var now: Date = Date()
    @Published private(set) var launchAtLoginEnabled: Bool = false
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var menuBarIcon: NSImage

    @Published var menuBarStyle: MenuBarStyle {
        didSet {
            UserDefaults.standard.set(menuBarStyle.rawValue, forKey: DefaultsKey.menuBarStyle)
            updateMenuBarIconIfNeeded()
        }
    }

    @Published var menuBarMetric: MenuBarMetric {
        didSet {
            UserDefaults.standard.set(menuBarMetric.rawValue, forKey: DefaultsKey.menuBarMetric)
            updateMenuBarIconIfNeeded()
        }
    }

    @Published var monochromeIcons: Bool {
        didSet {
            UserDefaults.standard.set(monochromeIcons, forKey: DefaultsKey.monochromeIcons)
            updateMenuBarIconIfNeeded()
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
    private var lastIconKey: MenuBarIconKey
    private var isPopoverVisible: Bool = false

    init() {
        let defaults = UserDefaults.standard

        let initialStyle: MenuBarStyle
        if let rawStyle = defaults.string(forKey: DefaultsKey.menuBarStyle),
           let parsedStyle = MenuBarStyle(rawValue: rawStyle) {
            initialStyle = parsedStyle
        } else {
            initialStyle = .ringsAndPercent
        }

        let initialMetric: MenuBarMetric
        if let rawMetric = defaults.string(forKey: DefaultsKey.menuBarMetric),
           let parsedMetric = MenuBarMetric(rawValue: rawMetric) {
            initialMetric = parsedMetric
        } else {
            initialMetric = .lowest
        }

        let initialMonochrome = defaults.object(forKey: DefaultsKey.monochromeIcons) as? Bool ?? false

        let initialRefreshInterval: RefreshIntervalOption
        if defaults.object(forKey: DefaultsKey.refreshInterval) != nil {
            let storedSeconds = defaults.integer(forKey: DefaultsKey.refreshInterval)
            initialRefreshInterval = RefreshIntervalOption(rawValue: storedSeconds) ?? .fiveMinutes
        } else {
            initialRefreshInterval = .fiveMinutes
        }

        let initialCustomPath = defaults.string(forKey: DefaultsKey.customAgyPath) ?? ""

        self.menuBarStyle = initialStyle
        self.menuBarMetric = initialMetric
        self.monochromeIcons = initialMonochrome
        self.refreshInterval = initialRefreshInterval
        self.customAgyPath = initialCustomPath
        self.launchAtLoginEnabled = Self.currentLaunchAtLoginState()

        self.lastIconKey = MenuBarIconKey(
            geminiPercent: nil,
            thirdPartyPercent: nil,
            style: initialStyle,
            monochrome: initialMonochrome
        )
        self.menuBarIcon = MenuBarIconRenderer.render(
            snapshot: nil,
            style: initialStyle,
            metric: initialMetric,
            monochrome: initialMonochrome
        )

        observeSystemWake()
        reschedulePolling()

        Task(priority: .utility) { [weak self] in
            await self?.refresh(isUserInitiated: false)
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
    func refresh(isUserInitiated: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let qos: QualityOfService = isUserInitiated ? .userInitiated : .utility
            let result = try await runner.fetchSnapshot(customBinaryPath: customAgyPath, qos: qos)
            snapshot = result.snapshot
            resolvedBinaryPath = result.resolvedBinaryPath
            lastError = nil
            now = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Starts or stops the relative-timestamp clock ticker based on whether the popover window is on screen.
    func setPopoverVisible(_ isVisible: Bool) {
        guard isPopoverVisible != isVisible else { return }
        isPopoverVisible = isVisible
        if isVisible {
            now = Date()
            startClockTicker()
        } else {
            stopClockTicker()
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

        let tolerance = refreshInterval.toleranceSeconds ?? 0
        pollingTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(tolerance))
                guard !Task.isCancelled else { break }
                await self?.refresh(isUserInitiated: false)
            }
        }
    }

    private func startClockTicker() {
        clockTask?.cancel()
        clockTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30), tolerance: .seconds(5))
                guard !Task.isCancelled else { break }
                self?.now = Date()
            }
        }
    }

    private func stopClockTicker() {
        clockTask?.cancel()
        clockTask = nil
    }

    private func updateMenuBarIconIfNeeded() {
        let newKey = MenuBarIconKey(
            geminiPercent: snapshot?.gemini?.percent(for: menuBarMetric),
            thirdPartyPercent: snapshot?.thirdParty?.percent(for: menuBarMetric),
            style: menuBarStyle,
            monochrome: monochromeIcons
        )
        guard newKey != lastIconKey else { return }
        lastIconKey = newKey
        menuBarIcon = MenuBarIconRenderer.render(
            snapshot: snapshot,
            style: menuBarStyle,
            metric: menuBarMetric,
            monochrome: monochromeIcons
        )
    }

    private func observeSystemWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task(priority: .utility) { @MainActor [weak self] in
                await self?.refresh(isUserInitiated: false)
            }
        }
    }
}
