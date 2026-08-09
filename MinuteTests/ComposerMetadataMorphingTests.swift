import XCTest
@testable import Minute

@MainActor
final class ComposerMetadataMorphingTests: XCTestCase {
    func testParserReturnsDeterministicSourceSpansForRecognizedMetadata() {
        let text = "Review Essays due tomorrow 1h every week"
        let result = SmartInputParser.parseForComposer(
            text: text,
            projectNames: ["Essays"]
        )

        XCTAssertEqual(
            result.metadataSpans.map(\.kind),
            [.project, .dueDate, .duration, .recurrence]
        )
        XCTAssertEqual(
            result.metadataSpans.map(\.sourceText),
            ["Essays", "due tomorrow", "1h", "every week"]
        )
        XCTAssertTrue(result.metadataSpans.allSatisfy { $0.length > 0 })
    }

    func testInlineModelReconstructsRawInputWithoutDestructiveRewrite() {
        let text = "Review Essays due tomorrow 1h every week"
        let result = SmartInputParser.parseForComposer(
            text: text,
            projectNames: ["Essays"]
        )
        let model = ComposerMetadataMorphingModel(
            rawText: text,
            values: ComposerMetadataMorphingValues(
                projectName: result.projectName,
                dueDate: result.date,
                dateLabel: "Tomorrow",
                duration: result.duration,
                durationLabel: "1h",
                recurrence: result.recurrenceInterval
            ),
            recognizedSpans: result.metadataSpans
        )

        XCTAssertEqual(
            model.chips.map(\.kind),
            [.project, .dueDate, .duration, .recurrence]
        )
        XCTAssertEqual(model.reconstructedSourceText, text)
        XCTAssertEqual(
            model.inlineSegments.compactMap { segment in
                if case let .chip(_, chip) = segment { return chip.sourceText }
                return nil
            },
            ["Essays", "due tomorrow", "1h", "every week"]
        )
    }

    func testFuzzyProjectRecognitionDoesNotClaimAnArbitrarySourceSpan() {
        let result = SmartInputParser.parseForComposer(
            text: "write PIQ drafts",
            projectCandidates: [
                SmartInputParser.ProjectCandidate(
                    name: "Essays",
                    hints: ["PIQ drafts"]
                )
            ]
        )

        XCTAssertEqual(result.projectName, "Essays")
        XCTAssertFalse(result.metadataSpans.contains { $0.kind == .project })
    }

    func testEffectiveManualValuesStillProduceChipsWithoutSourceSpans() {
        let date = Date(timeIntervalSince1970: 1_000)
        let model = ComposerMetadataMorphingModel(
            rawText: "follow up with Alex",
            values: ComposerMetadataMorphingValues(
                projectName: "Inbox",
                dueDate: date,
                dateLabel: "Mon, Jan 1",
                duration: 30 * 60,
                durationLabel: "30m",
                recurrence: "daily"
            ),
            recognizedSpans: []
        )

        XCTAssertEqual(
            model.chips.map(\.label),
            ["Inbox", "Mon, Jan 1", "30m", "Daily"]
        )
        XCTAssertEqual(model.reconstructedSourceText, "follow up with Alex")
        XCTAssertEqual(model.inlineSegments, [
            .text(id: "text-0", value: "follow up with Alex")
        ])
    }

    func testEventSuppressesTaskOnlyProjectAndRecurrenceChips() {
        let text = "event: Team sync every week"
        let result = SmartInputParser.parseForComposer(
            text: text,
            projectNames: ["Team"]
        )
        let model = ComposerMetadataMorphingModel(
            rawText: text,
            values: ComposerMetadataMorphingValues(
                projectName: result.projectName,
                recurrence: result.recurrenceInterval,
                isEvent: result.isEvent
            ),
            recognizedSpans: result.metadataSpans
        )

        XCTAssertEqual(model.chips.map(\.kind), [.event])
        XCTAssertEqual(model.reconstructedSourceText, text)
    }
}
