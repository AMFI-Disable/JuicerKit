import Foundation

public enum RemovalCandidateKind: String, Codable, CaseIterable, Sendable {
    case applicationBundle
    case applicationSupport
    case cache
    case container
    case groupContainer
    case preference
    case helperTool
    case log
    case unknown
}

public enum RemovalConfidence: String, Codable, CaseIterable, Sendable {
    case exactBundleIdentifier
    case exactApplicationName
    case relatedPath
    case unknown
}

public struct AppIdentity: Codable, Hashable, Sendable {
    public let name: String
    public let bundleIdentifier: String
    public let applicationURL: URL

    public init(name: String, bundleIdentifier: String, applicationURL: URL) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.applicationURL = applicationURL
    }
}

public struct AppRemovalCandidate: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let kind: RemovalCandidateKind
    public let size: Int64
    public let confidence: RemovalConfidence
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        kind: RemovalCandidateKind,
        size: Int64,
        confidence: RemovalConfidence,
        isSelected: Bool = true
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.size = max(0, size)
        self.confidence = confidence
        self.isSelected = isSelected
    }
}

public struct RemovalPlan: Codable, Identifiable, Sendable {
    public let id: UUID
    public let application: AppIdentity
    public let createdAt: Date
    public var candidates: [AppRemovalCandidate]

    public init(id: UUID = UUID(), application: AppIdentity, createdAt: Date = Date(), candidates: [AppRemovalCandidate]) {
        self.id = id
        self.application = application
        self.createdAt = createdAt
        self.candidates = candidates
    }

    public var selectedCandidates: [AppRemovalCandidate] { candidates.filter(\.isSelected) }
    public var selectedCount: Int { selectedCandidates.count }
    public var selectedBytes: Int64 { selectedCandidates.reduce(0) { $0 + $1.size } }
}

public struct RemovalFailure: Codable, Hashable, Sendable {
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }
}

public struct RemovalManifest: Codable, Identifiable, Sendable {
    public let id: UUID
    public let planID: UUID
    public let application: AppIdentity
    public let movedURLs: [URL]
    public let failures: [RemovalFailure]
    public let createdAt: Date

    public init(id: UUID = UUID(), planID: UUID, application: AppIdentity, movedURLs: [URL], failures: [RemovalFailure], createdAt: Date = Date()) {
        self.id = id
        self.planID = planID
        self.application = application
        self.movedURLs = movedURLs
        self.failures = failures
        self.createdAt = createdAt
    }
}

public enum RemovalResult: Sendable {
    case completed(manifest: RemovalManifest)
    case partiallyCompleted(manifest: RemovalManifest)
    case cancelled(manifest: RemovalManifest)
    case failed(reason: String, manifest: RemovalManifest?)
}
