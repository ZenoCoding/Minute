//
//  ComposerMetadataMorphing.swift
//  Minute
//
//  Source-aware presentation helpers for the quick composer. The raw input
//  remains the editable source of truth; this file only derives visual tokens.
//

import Foundation
import SwiftUI

enum ComposerMetadataKind: String, CaseIterable, Hashable, Sendable {
    case project
    case dueDate
    case duration
    case recurrence
    case event
}

/// Effective values supplied by `CaptureView` after parser results and manual
/// overrides have been resolved.
struct ComposerMetadataMorphingValues: Equatable, Sendable {
    var projectName: String?
    var projectSystemImage: String?
    var dueDate: Date?
    var dateLabel: String?
    var duration: TimeInterval?
    var durationLabel: String?
    var recurrence: String?
    var isEvent: Bool
    var includesDatePlaceholder: Bool

    init(
        projectName: String? = nil,
        projectSystemImage: String? = nil,
        dueDate: Date? = nil,
        dateLabel: String? = nil,
        duration: TimeInterval? = nil,
        durationLabel: String? = nil,
        recurrence: String? = nil,
        isEvent: Bool = false,
        includesDatePlaceholder: Bool = false
    ) {
        self.projectName = projectName
        self.projectSystemImage = projectSystemImage
        self.dueDate = dueDate
        self.dateLabel = dateLabel
        self.duration = duration
        self.durationLabel = durationLabel
        self.recurrence = recurrence
        self.isEvent = isEvent
        self.includesDatePlaceholder = includesDatePlaceholder
    }
}

struct ComposerMetadataChip: Equatable, Identifiable, Sendable {
    let kind: ComposerMetadataKind
    let label: String
    let systemImage: String
    let sourceText: String?

    var id: ComposerMetadataKind { kind }

    var accessibilityLabel: String {
        switch kind {
        case .project:
            return "Project \(label)"
        case .dueDate:
            return "Due \(label)"
        case .duration:
            return "Duration \(label)"
        case .recurrence:
            return "Repeats \(label)"
        case .event:
            return "Calendar event"
        }
    }
}

/// A pure presentation model. `inlineSegments` can replace recognized source
/// phrases in a non-editable preview while preserving the exact original text
/// in `reconstructedSourceText`. The editable TextField should continue to use
/// the original raw string and should never be rewritten from these segments.
struct ComposerMetadataMorphingModel: Equatable, Sendable {
    enum InlineSegment: Equatable, Identifiable, Sendable {
        case text(id: String, value: String)
        case chip(id: String, chip: ComposerMetadataChip)

        var id: String {
            switch self {
            case let .text(id, _), let .chip(id, _):
                return id
            }
        }

        var sourceText: String {
            switch self {
            case let .text(_, value):
                return value
            case let .chip(_, chip):
                return chip.sourceText ?? ""
            }
        }
    }

    let chips: [ComposerMetadataChip]
    let inlineSegments: [InlineSegment]
    let reconstructedSourceText: String

    init(
        rawText: String,
        values: ComposerMetadataMorphingValues,
        recognizedSpans: [SmartInputParser.ComposerMetadataSpan]
    ) {
        let validSpans = recognizedSpans
            .compactMap { span -> (SmartInputParser.ComposerMetadataSpan, Range<String.Index>)? in
                guard let range = Range(span.range, in: rawText) else { return nil }
                return (span, range)
            }
            .sorted {
                if $0.0.location != $1.0.location { return $0.0.location < $1.0.location }
                return $0.0.length > $1.0.length
            }

        var sourceTextByKind: [ComposerMetadataKind: String] = [:]
        for (span, range) in validSpans {
            guard let kind = ComposerMetadataKind(rawValue: span.kind.rawValue) else { continue }
            sourceTextByKind[kind] = sourceTextByKind[kind] ?? String(rawText[range])
        }

        let chips = Self.makeChips(values: values, sourceTextByKind: sourceTextByKind)
        self.chips = chips
        self.inlineSegments = Self.makeInlineSegments(
            rawText: rawText,
            spans: validSpans,
            chips: chips
        )
        self.reconstructedSourceText = self.inlineSegments.map(\.sourceText).joined()
    }

    private static func makeChips(
        values: ComposerMetadataMorphingValues,
        sourceTextByKind: [ComposerMetadataKind: String]
    ) -> [ComposerMetadataChip] {
        var chips: [ComposerMetadataChip] = []

        if values.isEvent {
            chips.append(
                ComposerMetadataChip(
                    kind: .event,
                    label: "Event",
                    systemImage: "calendar.badge.plus",
                    sourceText: sourceTextByKind[.event]
                )
            )
        } else if let projectName = values.projectName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !projectName.isEmpty {
            chips.append(
                ComposerMetadataChip(
                    kind: .project,
                    label: projectName,
                    systemImage: values.projectSystemImage ?? "folder",
                    sourceText: sourceTextByKind[.project]
                )
            )
        }

        if let dueDate = values.dueDate {
            chips.append(
                ComposerMetadataChip(
                    kind: .dueDate,
                    label: values.dateLabel ?? Self.defaultDateLabel(for: dueDate),
                    systemImage: "calendar",
                    sourceText: sourceTextByKind[.dueDate]
                )
            )
        } else if values.includesDatePlaceholder {
            chips.append(
                ComposerMetadataChip(
                    kind: .dueDate,
                    label: "No date",
                    systemImage: "calendar",
                    sourceText: nil
                )
            )
        }

        if let duration = values.duration, duration >= 0 {
            chips.append(
                ComposerMetadataChip(
                    kind: .duration,
                    label: values.durationLabel ?? Self.defaultDurationLabel(for: duration),
                    systemImage: "hourglass",
                    sourceText: sourceTextByKind[.duration]
                )
            )
        }

        if !values.isEvent, let recurrence = values.recurrence {
            let label = recurrence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty {
                chips.append(
                    ComposerMetadataChip(
                        kind: .recurrence,
                        label: label.capitalized,
                        systemImage: "repeat",
                        sourceText: sourceTextByKind[.recurrence]
                    )
                )
            }
        }

        return chips
    }

    private static func makeInlineSegments(
        rawText: String,
        spans: [(SmartInputParser.ComposerMetadataSpan, Range<String.Index>)],
        chips: [ComposerMetadataChip]
    ) -> [InlineSegment] {
        let chipsByKind = Dictionary(uniqueKeysWithValues: chips.map { ($0.kind, $0) })
        var segments: [InlineSegment] = []
        var cursor = rawText.startIndex
        var segmentIndex = 0

        for (span, range) in spans {
            guard range.lowerBound >= cursor else { continue }

            if cursor < range.lowerBound {
                segments.append(
                    .text(
                        id: "text-\(segmentIndex)",
                        value: String(rawText[cursor..<range.lowerBound])
                    )
                )
                segmentIndex += 1
            }

            guard let kind = ComposerMetadataKind(rawValue: span.kind.rawValue),
                  let chip = chipsByKind[kind] else {
                segments.append(
                    .text(
                        id: "text-\(segmentIndex)",
                        value: String(rawText[range])
                    )
                )
                segmentIndex += 1
                cursor = range.upperBound
                continue
            }

            let sourceText = String(rawText[range])
            let sourceChip = ComposerMetadataChip(
                kind: chip.kind,
                label: chip.label,
                systemImage: chip.systemImage,
                sourceText: sourceText
            )
            segments.append(
                .chip(
                    id: "chip-\(sourceChip.kind.rawValue)-\(segmentIndex)",
                    chip: sourceChip
                )
            )
            segmentIndex += 1
            cursor = range.upperBound
        }

        if cursor < rawText.endIndex {
            segments.append(
                .text(
                    id: "text-\(segmentIndex)",
                    value: String(rawText[cursor..<rawText.endIndex])
                )
            )
        }

        if segments.isEmpty, !rawText.isEmpty {
            return [.text(id: "text-0", value: rawText)]
        }
        return segments
    }

    private static func defaultDateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private static func defaultDurationLabel(for seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds.rounded() / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}

/// Compact Liquid Glass metadata chips for the quick composer.
///
/// Pass the parser's `metadataSpans` from the same parse as `rawText`, plus
/// effective values after manual overrides. `onSelect` is optional; when it is
/// supplied, the parent can open the existing project/date/detail pickers.
struct ComposerMetadataMorphing: View {
    let rawText: String
    let values: ComposerMetadataMorphingValues
    let recognizedSpans: [SmartInputParser.ComposerMetadataSpan]
    let highlightedKind: ComposerMetadataKind?
    let onSelect: ((ComposerMetadataKind) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        rawText: String,
        values: ComposerMetadataMorphingValues,
        recognizedSpans: [SmartInputParser.ComposerMetadataSpan] = [],
        highlightedKind: ComposerMetadataKind? = nil,
        onSelect: ((ComposerMetadataKind) -> Void)? = nil
    ) {
        self.rawText = rawText
        self.values = values
        self.recognizedSpans = recognizedSpans
        self.highlightedKind = highlightedKind
        self.onSelect = onSelect
    }

    var body: some View {
        let model = ComposerMetadataMorphingModel(
            rawText: rawText,
            values: values,
            recognizedSpans: recognizedSpans
        )

        HStack(spacing: 8) {
            ForEach(model.chips) { chip in
                chipView(chip, isHighlighted: highlightedKind == chip.kind)
                    .transition(reduceMotion ? .identity : .scale(scale: 0.88).combined(with: .opacity))
                    .id(chip.id)
            }
            Spacer(minLength: 0)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84),
            value: model.chips
        )
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func chipView(_ chip: ComposerMetadataChip, isHighlighted: Bool) -> some View {
        let label = ComposerMetadataChipLabel(chip: chip, isHighlighted: isHighlighted)

        if let onSelect {
            Button {
                onSelect(chip.kind)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chip.accessibilityLabel)
            .accessibilityValue(sourceAccessibilityValue(for: chip))
        } else {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chip.accessibilityLabel)
                .accessibilityValue(sourceAccessibilityValue(for: chip))
        }
    }

    private func sourceAccessibilityValue(for chip: ComposerMetadataChip) -> String {
        guard let sourceText = chip.sourceText,
              !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return chip.label
        }
        return "Recognized from \(sourceText)"
    }
}

/// Optional source-aware preview for integrations that want the recognized
/// phrase and chip to occupy the same visual line. It is deliberately a
/// preview: it does not intercept editing or mutate the TextField's binding.
struct ComposerMetadataMorphingPreview: View {
    let rawText: String
    let values: ComposerMetadataMorphingValues
    let recognizedSpans: [SmartInputParser.ComposerMetadataSpan]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let model = ComposerMetadataMorphingModel(
            rawText: rawText,
            values: values,
            recognizedSpans: recognizedSpans
        )

        HStack(spacing: 0) {
            ForEach(model.inlineSegments) { segment in
                switch segment {
                case let .text(_, value):
                    Text(value)
                case let .chip(_, chip):
                    ComposerMetadataChipLabel(chip: chip, compact: true)
                        .transition(reduceMotion ? .identity : .scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .font(.body)
        .lineLimit(1)
        .truncationMode(.middle)
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84),
            value: model.inlineSegments
        )
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .accessibilityLabel("Input with recognized metadata")
        .accessibilityValue(model.reconstructedSourceText)
    }
}

private struct ComposerMetadataChipLabel: View {
    let chip: ComposerMetadataChip
    var compact = false
    var isHighlighted = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: chip.systemImage)
            Text(chip.label)
        }
        .font(compact ? .caption2 : .caption.weight(isHighlighted ? .semibold : .regular))
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 3 : 6)
        .glassEffect(.clear.interactive(), in: Capsule())
        .overlay {
            Capsule().stroke(
                isHighlighted ? Color.accentColor.opacity(0.7) : .primary.opacity(0.16),
                lineWidth: isHighlighted ? 1.5 : 1
            )
        }
        .scaleEffect(isHighlighted ? 1.08 : 1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var tint: Color {
        switch chip.kind {
        case .event, .duration:
            return .blue
        case .recurrence:
            return .purple
        case .project, .dueDate:
            return .primary
        }
    }
}
