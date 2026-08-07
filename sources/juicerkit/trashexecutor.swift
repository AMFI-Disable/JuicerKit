import Foundation

public final class TrashExecutor: @unchecked Sendable {
    private let fileManager: FileManager
    private let validator: PathSafetyValidator

    public init(fileManager: FileManager = .default, validator: PathSafetyValidator) {
        self.fileManager = fileManager
        self.validator = validator
    }

    public func execute(plan: RemovalPlan, cancellationCheck: (() -> Bool)? = nil) -> RemovalResult {
        var moved: [URL] = []
        var failures: [RemovalFailure] = []

        for candidate in plan.selectedCandidates {
            if cancellationCheck?() == true {
                let manifest = RemovalManifest(planID: plan.id, application: plan.application, movedURLs: moved, failures: failures)
                return .cancelled(manifest: manifest)
            }

            do {
                try validator.validate(candidate.url, fileManager: fileManager)
                try fileManager.trashItem(at: candidate.url, resultingItemURL: nil)
                moved.append(candidate.url)
            } catch {
                failures.append(RemovalFailure(url: candidate.url, reason: error.localizedDescription))
            }
        }

        let manifest = RemovalManifest(planID: plan.id, application: plan.application, movedURLs: moved, failures: failures)
        if moved.isEmpty && !failures.isEmpty { return .failed(reason: "No selected targets could be moved to the Trash.", manifest: manifest) }
        if failures.isEmpty { return .completed(manifest: manifest) }
        return .partiallyCompleted(manifest: manifest)
    }
}
