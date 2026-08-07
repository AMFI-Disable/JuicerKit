import Foundation

public enum PathSafetyError: LocalizedError, Equatable {
    case emptyPath
    case targetDoesNotExist(URL)
    case protectedPath(URL)
    case outsideAllowedRoots(URL)

    public var errorDescription: String? {
        switch self {
        case .emptyPath: return "The target path is empty."
        case .targetDoesNotExist(let url): return "The target does not exist: \(url.path)"
        case .protectedPath(let url): return "The target is protected from removal: \(url.path)"
        case .outsideAllowedRoots(let url): return "The target is outside the allowed removal scope: \(url.path)"
        }
    }
}

public struct PathSafetyValidator: Sendable {
    public let allowedRoots: [URL]

    public init(allowedRoots: [URL]) {
        self.allowedRoots = allowedRoots.map { $0.standardizedFileURL }
    }

    public func validate(_ url: URL, fileManager: FileManager = .default) throws {
        let path = url.standardizedFileURL.path
        guard !path.isEmpty else { throw PathSafetyError.emptyPath }
        guard fileManager.fileExists(atPath: path) else { throw PathSafetyError.targetDoesNotExist(url) }

        let protected = [
            "/",
            fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path,
            "/System",
            "/Applications",
            "/System/Applications"
        ]
        if protected.contains(path) {
            throw PathSafetyError.protectedPath(url)
        }

        guard allowedRoots.contains(where: { root in
            path == root.path || path.hasPrefix(root.path + "/")
        }) else {
            throw PathSafetyError.outsideAllowedRoots(url)
        }
    }
}
