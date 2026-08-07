import Foundation
import Darwin

public enum CommandCategory: String, Codable, Equatable, Sendable {
    case readOnly
    case reversibleMutation
    case destructiveMutation
    case privilegedOrUnsupported
}

public enum CommandExecutorError: LocalizedError, Equatable {
    case executablePathMustBeAbsolute
    case outputLimitMustBePositive

    public var errorDescription: String? {
        switch self {
        case .executablePathMustBeAbsolute:
            return "The executable path must be absolute."
        case .outputLimitMustBePositive:
            return "The command output limit must be greater than zero."
        }
    }
}

public struct CommandResult: Sendable {
    public let standardOutput: String
    public let standardError: String
    public let terminationStatus: Int32?
    public let wasTerminated: Bool
    public let didTimeOut: Bool
    public let wasCancelled: Bool
    public let standardOutputWasTruncated: Bool
    public let standardErrorWasTruncated: Bool
    public let category: CommandCategory
    public let launchErrorDescription: String?

    public var succeeded: Bool {
        !didTimeOut && !wasCancelled && !wasTerminated && launchErrorDescription == nil && terminationStatus == 0
    }

    public init(
        standardOutput: String,
        standardError: String,
        terminationStatus: Int32?,
        wasTerminated: Bool,
        didTimeOut: Bool,
        wasCancelled: Bool,
        standardOutputWasTruncated: Bool,
        standardErrorWasTruncated: Bool,
        category: CommandCategory,
        launchErrorDescription: String?
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.terminationStatus = terminationStatus
        self.wasTerminated = wasTerminated
        self.didTimeOut = didTimeOut
        self.wasCancelled = wasCancelled
        self.standardOutputWasTruncated = standardOutputWasTruncated
        self.standardErrorWasTruncated = standardErrorWasTruncated
        self.category = category
        self.launchErrorDescription = launchErrorDescription
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false

    func capture(from handle: FileHandle, maximumBytes: Int) {
        var captured = Data()
        var didTruncate = false

        while true {
            let chunk = handle.readData(ofLength: 64 * 1024)
            guard !chunk.isEmpty else { break }

            let remaining = maximumBytes - captured.count
            if remaining > 0 {
                captured.append(chunk.prefix(remaining))
            }
            if chunk.count > max(remaining, 0) {
                didTruncate = true
            }
        }

        lock.lock()
        data = captured
        truncated = didTruncate
        lock.unlock()
    }

    func snapshot() -> (data: Data, truncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, truncated)
    }
}

public final class CommandExecutor: @unchecked Sendable {
    public static let shared = CommandExecutor()

    public init() {}

    public func run(
        executablePath: String,
        arguments: [String] = [],
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval = 30,
        category: CommandCategory = .readOnly,
        maximumOutputBytes: Int = 1_048_576,
        cancellationCheck: (() -> Bool)? = nil
    ) -> CommandResult {
        guard executablePath.hasPrefix("/") else {
            return failure(.executablePathMustBeAbsolute, category: category)
        }
        guard maximumOutputBytes > 0 else {
            return failure(.outputLimitMustBePositive, category: category)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return CommandResult(
                standardOutput: "",
                standardError: "",
                terminationStatus: nil,
                wasTerminated: false,
                didTimeOut: false,
                wasCancelled: false,
                standardOutputWasTruncated: false,
                standardErrorWasTruncated: false,
                category: category,
                launchErrorDescription: error.localizedDescription
            )
        }

        let group = DispatchGroup()
        let output = OutputBuffer()
        let error = OutputBuffer()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            output.capture(from: outputPipe.fileHandleForReading, maximumBytes: maximumOutputBytes)
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            error.capture(from: errorPipe.fileHandleForReading, maximumBytes: maximumOutputBytes)
            group.leave()
        }

        let effectiveTimeout = timeout.isFinite ? max(timeout, 0) : 30
        let deadline = Date().addingTimeInterval(effectiveTimeout)
        var wasCancelled = cancellationCheck?() == true

        while process.isRunning && Date() < deadline {
            if cancellationCheck?() == true {
                wasCancelled = true
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        let didTimeOut = process.isRunning && !wasCancelled && Date() >= deadline
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        process.waitUntilExit()
        group.wait()
        let outputSnapshot = output.snapshot()
        let errorSnapshot = error.snapshot()

        return CommandResult(
            standardOutput: String(data: outputSnapshot.data, encoding: .utf8) ?? "",
            standardError: String(data: errorSnapshot.data, encoding: .utf8) ?? "",
            terminationStatus: process.terminationStatus,
            wasTerminated: didTimeOut || wasCancelled || process.terminationReason == .uncaughtSignal,
            didTimeOut: didTimeOut,
            wasCancelled: wasCancelled,
            standardOutputWasTruncated: outputSnapshot.truncated,
            standardErrorWasTruncated: errorSnapshot.truncated,
            category: category,
            launchErrorDescription: nil
        )
    }

    private func failure(_ error: CommandExecutorError, category: CommandCategory) -> CommandResult {
        CommandResult(
            standardOutput: "",
            standardError: "",
            terminationStatus: nil,
            wasTerminated: false,
            didTimeOut: false,
            wasCancelled: false,
            standardOutputWasTruncated: false,
            standardErrorWasTruncated: false,
            category: category,
            launchErrorDescription: error.localizedDescription
        )
    }
}
