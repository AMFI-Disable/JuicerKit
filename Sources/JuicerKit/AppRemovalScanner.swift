import Foundation

public final class AppRemovalScanner: @unchecked Sendable {
    public init() {}

    public func scan(application: AppIdentity, fileManager: FileManager = .default) -> RemovalPlan {
        let home = fileManager.homeDirectoryForCurrentUser
        let bundleID = application.bundleIdentifier.lowercased()
        let appName = application.name.lowercased()
        let roots: [(RemovalCandidateKind, URL)] = [
            (.applicationSupport, home.appendingPathComponent("Library/Application Support")),
            (.cache, home.appendingPathComponent("Library/Caches")),
            (.container, home.appendingPathComponent("Library/Containers")),
            (.groupContainer, home.appendingPathComponent("Library/Group Containers")),
            (.preference, home.appendingPathComponent("Library/Preferences")),
            (.log, home.appendingPathComponent("Library/Logs"))
        ]

        var candidates: [AppRemovalCandidate] = []
        if fileManager.fileExists(atPath: application.applicationURL.path) {
            candidates.append(AppRemovalCandidate(
                url: application.applicationURL,
                kind: .applicationBundle,
                size: size(of: application.applicationURL, fileManager: fileManager),
                confidence: .exactBundleIdentifier
            ))
        }

        for (kind, root) in roots {
            guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for child in children {
                let lower = child.lastPathComponent.lowercased()
                let matchesBundle = !bundleID.isEmpty && lower.contains(bundleID)
                let matchesName = !appName.isEmpty && lower.contains(appName)
                guard matchesBundle || matchesName else { continue }

                candidates.append(AppRemovalCandidate(
                    url: child,
                    kind: kind,
                    size: size(of: child, fileManager: fileManager),
                    confidence: matchesBundle ? .exactBundleIdentifier : .exactApplicationName
                ))
            }
        }

        return RemovalPlan(application: application, candidates: candidates.sorted { $0.url.path < $1.url.path })
    }

    private func size(of url: URL, fileManager: FileManager) -> Int64 {
        var directory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &directory) else { return 0 }
        if !directory.boolValue {
            return (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }

        var total: Int64 = 0
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsPackageDescendants]) {
            for case let child as URL in enumerator {
                total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }
}
