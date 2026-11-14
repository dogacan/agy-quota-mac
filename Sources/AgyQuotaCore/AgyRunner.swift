import Foundation

/// Failures encountered while locating or invoking the `agy` CLI binary.
public enum AgyRunnerError: LocalizedError, Sendable {
    case binaryNotFound(checkedPaths: [String])
    case executionFailed(exitCode: Int32, stderr: String)
    case timedOut(seconds: Int)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Could not find the `agy` CLI binary. Set a custom path in Options if installed elsewhere."
        case .executionFailed(let exitCode, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "`agy --print \"/quota\"` exited with status \(exitCode)."
            }
            return "`agy` failed (\(exitCode)): \(String(trimmed.prefix(160)))"
        case .timedOut(let seconds):
            return "`agy --print \"/quota\"` timed out after \(seconds)s."
        }
    }
}

/// Discovers the `agy` executable in GUI environments and fetches current quota snapshots.
public struct AgyRunner: Sendable {
    public static let mockOutputEnvKey = "AGY_QUOTA_MOCK_OUTPUT"

    public init() {}

    /// Standard installation paths checked in priority order when resolving `agy`.
    public static func candidateBinaryPaths(
        customBinaryPath: String? = nil,
        homeDirectory: String = NSHomeDirectory(),
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        var candidates: [String] = []

        if let custom = customBinaryPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            candidates.append((custom as NSString).expandingTildeInPath)
        }

        candidates.append(contentsOf: [
            "\(homeDirectory)/Library/Application Support/Antigravity/bin/agy",
            "\(homeDirectory)/.gemini/antigravity/bin/agy",
            "\(homeDirectory)/.antigravity/antigravity/bin/agy",
            "\(homeDirectory)/.antigravity-ide/antigravity-ide/bin/agy",
            "\(homeDirectory)/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy"
        ])

        if let rawPath = processEnvironment["PATH"] {
            for dir in rawPath.split(separator: ":") {
                candidates.append("\(dir)/agy")
            }
        }

        // Preserve priority order while deduplicating.
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    /// Runs `agy --print "/quota"` and parses the resulting snapshot.
    public func fetchSnapshot(
        customBinaryPath: String? = nil,
        timeoutSeconds: Int = 30
    ) async throws -> (snapshot: QuotaSnapshot, resolvedBinaryPath: String) {
        if let mockOutput = ProcessInfo.processInfo.environment[Self.mockOutputEnvKey],
           !mockOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let snapshot = try QuotaParser.parse(mockOutput)
            return (snapshot, "env:\(Self.mockOutputEnvKey)")
        }

        let binaryPath = try await resolveBinaryPath(customBinaryPath: customBinaryPath)
        let result = try await runProcess(
            executablePath: binaryPath,
            arguments: ["--print", "/quota"],
            timeoutSeconds: timeoutSeconds
        )

        if let snapshot = try? QuotaParser.parse(result.stdout) {
            return (snapshot, binaryPath)
        }

        if result.exitCode != 0 {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw AgyRunnerError.executionFailed(exitCode: result.exitCode, stderr: message)
        }

        let snapshot = try QuotaParser.parse(result.stdout)
        return (snapshot, binaryPath)
    }

    private func resolveBinaryPath(customBinaryPath: String?) async throws -> String {
        let fileManager = FileManager.default
        let candidates = Self.candidateBinaryPaths(customBinaryPath: customBinaryPath)

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return path
        }

        // Fallback: ask login zsh where `agy` lives in case user configured PATH in ~/.zprofile / ~/.zshrc.
        if let shellResult = try? await runProcess(
            executablePath: "/bin/zsh",
            arguments: ["-lic", "command -v agy"],
            timeoutSeconds: 5
        ), shellResult.exitCode == 0 {
            let resolved = shellResult.stdout
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .last(where: { $0.hasPrefix("/") && fileManager.isExecutableFile(atPath: $0) })
            if let resolved {
                return resolved
            }
        }

        throw AgyRunnerError.binaryNotFound(checkedPaths: candidates)
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: Int
    ) async throws -> ProcessOutput {
        let env = Self.enrichedEnvironment(forExecutable: executablePath)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                // Avoid workspace indexing or TCC Desktop/Documents prompts from Finder-launched apps.
                process.currentDirectoryURL = FileManager.default.temporaryDirectory
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                process.standardInput = FileHandle.nullDevice

                let stdoutBuffer = LockedData()
                let stderrBuffer = LockedData()
                let state = ContinuationGate()

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if !chunk.isEmpty {
                        stdoutBuffer.append(chunk)
                    }
                }
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if !chunk.isEmpty {
                        stderrBuffer.append(chunk)
                    }
                }

                let timeoutWorkItem = DispatchWorkItem {
                    guard state.markCompleted() else { return }
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    if process.isRunning {
                        process.terminate()
                    }
                    continuation.resume(throwing: AgyRunnerError.timedOut(seconds: timeoutSeconds))
                }

                process.terminationHandler = { finishedProcess in
                    timeoutWorkItem.cancel()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    let remainingOut = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let remainingErr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                    stdoutBuffer.append(remainingOut)
                    stderrBuffer.append(remainingErr)

                    guard state.markCompleted() else { return }

                    let stdout = String(data: stdoutBuffer.snapshot(), encoding: .utf8) ?? ""
                    let stderr = String(data: stderrBuffer.snapshot(), encoding: .utf8) ?? ""
                    continuation.resume(returning: ProcessOutput(
                        exitCode: finishedProcess.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                }

                do {
                    try process.run()
                    DispatchQueue.global(qos: .utility).asyncAfter(
                        deadline: .now() + .seconds(timeoutSeconds),
                        execute: timeoutWorkItem
                    )
                } catch {
                    timeoutWorkItem.cancel()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    if state.markCompleted() {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private static func enrichedEnvironment(forExecutable executablePath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let execDir = (executablePath as NSString).deletingLastPathComponent
        let extraDirs = [
            execDir,
            "\(home)/Library/Application Support/Antigravity/bin",
            "\(home)/.gemini/antigravity/bin",
            "\(home)/.antigravity/antigravity/bin",
            "\(home)/.antigravity-ide/antigravity-ide/bin",
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]

        let existingDirs = (env["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        var seen = Set<String>()
        let merged = (extraDirs + existingDirs).filter { !$0.isEmpty && seen.insert($0).inserted }

        env["PATH"] = merged.joined(separator: ":")
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        return env
    }
}

private struct ProcessOutput: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let copy = data
        lock.unlock()
        return copy
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func markCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}
