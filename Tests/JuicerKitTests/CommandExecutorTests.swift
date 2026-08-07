import XCTest
@testable import JuicerKit

final class CommandExecutorTests: XCTestCase {
    func testCapturesOutputAndErrorsSeparately() {
        let result = CommandExecutor().run(executablePath: "/bin/sh", arguments: ["-c", "printf out; printf err >&2"])
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.standardOutput, "out")
        XCTAssertEqual(result.standardError, "err")
    }

    func testRejectsRelativeExecutable() {
        let result = CommandExecutor().run(executablePath: "brew")
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.launchErrorDescription, CommandExecutorError.executablePathMustBeAbsolute.localizedDescription)
    }

    func testPathValidatorRejectsProtectedRoot() throws {
        let validator = PathSafetyValidator(allowedRoots: [URL(fileURLWithPath: "/tmp")])
        XCTAssertThrowsError(try validator.validate(URL(fileURLWithPath: "/")))
    }

    func testRemovalPlanAggregatesSelectedBytes() {
        let app = AppIdentity(name: "Example", bundleIdentifier: "com.example.app", applicationURL: URL(fileURLWithPath: "/tmp/Example.app"))
        let plan = RemovalPlan(application: app, candidates: [
            AppRemovalCandidate(url: URL(fileURLWithPath: "/tmp/one"), kind: .cache, size: 10, confidence: .relatedPath),
            AppRemovalCandidate(url: URL(fileURLWithPath: "/tmp/two"), kind: .preference, size: 20, confidence: .relatedPath, isSelected: false)
        ])
        XCTAssertEqual(plan.selectedCount, 1)
        XCTAssertEqual(plan.selectedBytes, 10)
    }
}
