import AgyQuotaCore
import AppKit
import SwiftUI

/// Expanded menu bar popover showing full 5-hour/weekly quotas, reset timers, and preferences.
struct QuotaPopoverView: View {
    @ObservedObject var viewModel: QuotaViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        QuotaCategoryCard(
                            category: .gemini,
                            iconName: "sparkles",
                            quota: viewModel.snapshot?.gemini,
                            metric: viewModel.menuBarMetric,
                            now: viewModel.now,
                            isErrorState: viewModel.lastError != nil
                        )

                        QuotaCategoryCard(
                            category: .thirdParty,
                            iconName: "square.stack.3d.up",
                            quota: viewModel.snapshot?.thirdParty,
                            metric: viewModel.menuBarMetric,
                            now: viewModel.now,
                            isErrorState: viewModel.lastError != nil
                        )

                        if let error = viewModel.lastError {
                            errorBanner(message: error)
                        }

                        optionsCard
                            .id("optionsSection")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: viewModel.showSettings) { _, isShown in
                    if isShown {
                        Task { @MainActor in
                            await Task.yield()
                            withAnimation(.easeOut(duration: 0.2)) {
                                scrollProxy.scrollTo("optionsSection", anchor: .top)
                            }
                        }
                    }
                }
            }

            Divider()

            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 380, height: 500)
        .onAppear {
            NSApp.activate()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Antigravity Quota")
                    .font(.headline)
                Text(viewModel.lastUpdatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await viewModel.refresh()
                }
            } label: {
                if viewModel.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh quota (⌘R)")

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    viewModel.showSettings.toggle()
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(viewModel.showSettings ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.borderless)
            .help("Options")
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 1)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button("Retry") {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(viewModel.isRefreshing)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Options Card & Section

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    viewModel.showSettings.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(viewModel.showSettings ? Color.accentColor : Color.secondary)

                    Text("Options")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: viewModel.showSettings ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if viewModel.showSettings {
                Divider()
                settingsSection
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        )
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Menu Bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Menu Bar", selection: $viewModel.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Show Value")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Show Value", selection: $viewModel.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Refresh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Auto-Refresh", selection: $viewModel.refreshInterval) {
                    ForEach(RefreshIntervalOption.allCases) { interval in
                        Text(interval.shortLabel).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Text("Color-Coded Rings")
                    .font(.caption)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { !viewModel.monochromeIcons },
                    set: { viewModel.monochromeIcons = !$0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Launch at Login")
                        .font(.caption)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { viewModel.launchAtLoginEnabled },
                        set: { viewModel.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                if let loginError = viewModel.launchAtLoginError {
                    Text(loginError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("`agy` CLI Path")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    TextField("Auto-detect", text: $viewModel.customAgyPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit {
                            Task {
                                await viewModel.refresh()
                            }
                        }

                    Button("Apply") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .controlSize(.small)
                    .disabled(viewModel.isRefreshing)
                }

                if let resolved = viewModel.resolvedBinaryPath {
                    Text("Resolved: \(resolved)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Auto-detects Antigravity CLI from standard locations")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text("Auto-refresh: \(viewModel.refreshInterval.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit Antigravity Quota (⌘Q)")
        }
    }
}

// MARK: - Category Card

private struct QuotaCategoryCard: View {
    let category: QuotaCategory
    let iconName: String
    let quota: CategoryQuota?
    let metric: MenuBarMetric
    let now: Date
    let isErrorState: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            cardHeader

            if let quota, !quota.windows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(quota.windows) { window in
                        QuotaWindowRow(window: window, now: now)
                    }
                }
            } else {
                Text(isErrorState ? "Quota unavailable" : "Waiting for quota data…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        )
    }

    private var cardHeader: some View {
        let displayPercent = quota?.percent(for: metric)
        let color = QuotaColors.statusColor(for: displayPercent)

        return HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)

            Text(quota?.title ?? category.defaultTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer()

            HStack(spacing: 5) {
                MiniCircularRing(percent: displayPercent, color: color)

                Text(displayPercent.map { "\($0)%" } ?? "--%")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(displayPercent == nil ? Color.secondary : color)
            }
        }
    }
}

// MARK: - Window Row

private struct QuotaWindowRow: View {
    let window: QuotaWindow
    let now: Date

    var body: some View {
        let color = QuotaColors.statusColor(for: window.roundedPercent)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.kind.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(window.roundedPercent)%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.10))

                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: max(0, proxy.size.width * window.fraction))
                }
            }
            .frame(height: 6)

            if let resetSummary = window.formattedResetSummary(relativeTo: now) {
                Text(resetSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MiniCircularRing: View {
    let percent: Int?
    let color: Color

    var body: some View {
        let fraction = percent.map { min(max(Double($0) / 100.0, 0.0), 1.0) } ?? 0.0

        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: 2.2)

            if fraction > 0.001 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 14, height: 14)
    }
}

private enum QuotaColors {
    static func statusColor(for percent: Int?) -> Color {
        guard let percent else { return .secondary }
        if percent >= 50 {
            return .green
        }
        if percent >= 20 {
            return .orange
        }
        return .red
    }
}
