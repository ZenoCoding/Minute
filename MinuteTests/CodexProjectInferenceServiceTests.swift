import XCTest
@testable import Minute

@MainActor
final class CodexProjectInferenceServiceTests: XCTestCase {
    private let candidates = [
        SmartInputParser.ProjectCandidate(name: "Essays", hints: ["PIQ drafts", "college applications"]),
        SmartInputParser.ProjectCandidate(name: "School", hints: ["classes", "homework"])
    ]

    func testExactCandidateIsReturned() throws {
        let response = CodexProjectInferenceService.Response(
            projectName: "essays",
            confidence: 0.94
        )

        XCTAssertEqual(
            try CodexProjectInferenceService.validatedProjectName(
                from: response,
                candidates: candidates
            ),
            "Essays"
        )
    }

    func testUnknownCandidateIsRejected() {
        let response = CodexProjectInferenceService.Response(
            projectName: "Invented project",
            confidence: 0.99
        )

        XCTAssertThrowsError(
            try CodexProjectInferenceService.validatedProjectName(
                from: response,
                candidates: candidates
            )
        ) { error in
            XCTAssertEqual(error as? CodexProjectInferenceService.ServiceError, .invalidProject)
        }
    }

    func testLowConfidenceFallsBackToLocalBehavior() throws {
        let response = CodexProjectInferenceService.Response(
            projectName: "Essays",
            confidence: 0.31
        )

        XCTAssertNil(
            try CodexProjectInferenceService.validatedProjectName(
                from: response,
                candidates: candidates
            )
        )
    }

    func testOutOfRangeConfidenceIsRejected() {
        let response = CodexProjectInferenceService.Response(
            projectName: "Essays",
            confidence: 1.1
        )

        XCTAssertThrowsError(
            try CodexProjectInferenceService.validatedProjectName(
                from: response,
                candidates: candidates
            )
        ) { error in
            XCTAssertEqual(error as? CodexProjectInferenceService.ServiceError, .invalidResponse)
        }
    }

    func testCorrectionMemoryGeneralizesAcrossDraftNumbers() {
        let examples = [
            ProjectInferenceMemory.Example(
                signature: "piq drafts",
                projectName: "Essays",
                updatedAt: Date()
            )
        ]

        XCTAssertEqual(
            ProjectInferenceMemory.bestMatch(
                for: "write piq drafts 6 and 7",
                examples: examples,
                candidateNames: ["Essays", "School"]
            ),
            "Essays"
        )
    }

    func testCorrectionMemoryRejectsRemovedProjects() {
        let examples = [
            ProjectInferenceMemory.Example(
                signature: "piq drafts",
                projectName: "Essays",
                updatedAt: Date()
            )
        ]

        XCTAssertNil(
            ProjectInferenceMemory.bestMatch(
                for: "write piq drafts 6 and 7",
                examples: examples,
                candidateNames: ["School"]
            )
        )
    }

    func testLiveCodexClassifiesPIQDrafts() async throws {
        guard ProcessInfo.processInfo.environment["MINUTE_RUN_LIVE_CODEX_TEST"] == "1" else {
            throw XCTSkip("Set MINUTE_RUN_LIVE_CODEX_TEST=1 in an unsandboxed local build.")
        }

        let result = try await CodexProjectInferenceService.inferProjectName(
            text: "write piq drafts 4 and 5",
            candidates: candidates,
            timeoutNanoseconds: 20_000_000_000
        )

        XCTAssertEqual(result, "Essays")
    }
}
