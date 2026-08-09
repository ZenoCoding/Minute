import SwiftUI
import SwiftData

enum TaskSuggestionStripMode {
    case compact
    case wide
}

private struct TaskSuggestionProjectPresentation {
    let iconName: String
    let themeColor: String

    var color: Color {
        Color(hex: themeColor) ?? .secondary
    }
}

struct TaskSuggestionStrip: View {
    let mode: TaskSuggestionStripMode
    let onEdit: (TaskSuggestion) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskSuggestion.rank) private var allSuggestions: [TaskSuggestion]
    @Query(sort: \Project.createdAt) private var allProjects: [Project]
    @State private var isExpanded = false

    private var suggestions: [TaskSuggestion] {
        Array(
            allSuggestions
                .filter { $0.status == TaskSuggestionStatus.pending }
                .sorted {
                    if $0.rank != $1.rank { return $0.rank < $1.rank }
                    return $0.generatedAt > $1.generatedAt
                }
                .prefix(3)
        )
    }

    private var collapsedCount: Int {
        mode == .wide ? 2 : 1
    }

    private var visibleSuggestions: [TaskSuggestion] {
        isExpanded ? suggestions : Array(suggestions.prefix(collapsedCount))
    }

    private var remainingCount: Int {
        max(0, suggestions.count - collapsedCount)
    }

    private var projectPresentationsByName: [String: TaskSuggestionProjectPresentation] {
        var presentations: [String: TaskSuggestionProjectPresentation] = [:]
        for project in allProjects {
            let key = normalizedProjectName(project.name)
            guard !key.isEmpty, presentations[key] == nil else { continue }

            let iconName: String
            if let areaIcon = project.area?.iconName {
                let trimmedIcon = areaIcon.trimmingCharacters(in: .whitespacesAndNewlines)
                iconName = trimmedIcon.isEmpty ? "folder" : trimmedIcon
            } else {
                iconName = "folder"
            }
            presentations[key] = TaskSuggestionProjectPresentation(
                iconName: iconName,
                themeColor: project.area?.themeColor ?? "8E8E93"
            )
        }
        return presentations
    }

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("Suggestions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    if remainingCount > 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(isExpanded ? "Show less" : "\(remainingCount) more")
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(isExpanded ? "Show fewer suggestions" : "Show \(remainingCount) more suggestions")
                        .help(isExpanded ? "Show fewer suggestions" : "Show \(remainingCount) more suggestions")
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(visibleSuggestions) { suggestion in
                        TaskSuggestionRow(
                            suggestion: suggestion,
                            projectPresentation: projectPresentation(for: suggestion.inferredProjectName),
                            onEdit: { onEdit(suggestion) },
                            onAccept: { accept(suggestion) },
                            onDismiss: { dismiss(suggestion) }
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
            .onChange(of: suggestions.count) { _, count in
                if count <= collapsedCount {
                    isExpanded = false
                }
            }
        }
    }

    private func projectPresentation(for projectName: String?) -> TaskSuggestionProjectPresentation? {
        guard let projectName else { return nil }
        return projectPresentationsByName[normalizedProjectName(projectName)]
    }

    private func normalizedProjectName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func accept(_ suggestion: TaskSuggestion) {
        do {
            _ = try TaskSuggestionService(modelContext: modelContext).accept(suggestion)
        } catch {
            print("Failed to accept suggestion: \(error)")
        }
    }

    private func dismiss(_ suggestion: TaskSuggestion) {
        do {
            try TaskSuggestionService(modelContext: modelContext).dismiss(suggestion)
        } catch {
            print("Failed to dismiss suggestion: \(error)")
        }
    }
}

private struct TaskSuggestionRow: View {
    let suggestion: TaskSuggestion
    let projectPresentation: TaskSuggestionProjectPresentation?
    let onEdit: () -> Void
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Suggested task: \(suggestion.title)")
                    .accessibilityHint(suggestionContext)
                    .help(suggestionContext)

                if let metadata = metadataText {
                    HStack(spacing: 4) {
                        if let projectName {
                            if let projectPresentation {
                                Image(systemName: projectPresentation.iconName)
                                    .foregroundStyle(projectPresentation.color)
                                    .accessibilityHidden(true)
                            }
                            Text(projectName)
                        }

                        if projectName != nil, dueDateText != nil {
                            Text("·")
                                .accessibilityHidden(true)
                        }

                        if let dueDateText {
                            Text(dueDateText)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(metadata)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            HStack(spacing: 8) {
                Button("Edit", action: onEdit)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityLabel("Edit suggested task")
                    .accessibilityHint("Opens this suggestion in the task composer.")
                    .help("Edit suggested task")

                Button(action: onAccept) {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel("Add suggested task")
                .accessibilityHint("Adds this suggestion as a task.")
                .help("Add suggested task")

                if let sourceURL = suggestion.sourceURL, let url = URL(string: sourceURL) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .fixedSize()
                    .accessibilityLabel("Open \(suggestion.sourceLabel) source")
                    .accessibilityHint("Opens the source for this suggestion.")
                    .help("Open \(suggestion.sourceLabel) source")
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .fixedSize()
                .accessibilityLabel("Dismiss suggestion")
                .accessibilityHint("Removes this suggestion without adding it as a task.")
                .help("Dismiss suggestion")
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private var metadataText: String? {
        var values: [String] = []

        if let projectName {
            values.append(projectName)
        }

        if let dueDateText {
            values.append(dueDateText)
        }

        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private var projectName: String? {
        guard let name = suggestion.inferredProjectName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }
        return name
    }

    private var dueDateText: String? {
        suggestion.dueDate?.formatted(date: .abbreviated, time: .omitted)
    }

    private var suggestionContext: String {
        suggestion.reason
            ?? suggestion.evidenceSnippet
            ?? "Use Edit to adjust this suggestion or Add to create it as a task."
    }
}
