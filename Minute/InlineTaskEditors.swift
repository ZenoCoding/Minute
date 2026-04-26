//
//  InlineTaskEditors.swift
//  Minute
//
//  Reusable popover-based picker components for inline task editing.
//  Shared between InlineTaskComposer and TaskStreamRow.
//

import SwiftUI
import SwiftData

// MARK: - Project Picker Popover

struct ProjectPickerPopover: View {
    let projects: [Project]
    @Binding var selection: Project?
    let onSelect: (Project) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(projects) { project in
                    Button {
                        onSelect(project)
                    } label: {
                        HStack {
                            if let icon = project.area?.iconName {
                                Image(systemName: icon)
                                    .foregroundStyle(Color(hex: project.area?.themeColor ?? "") ?? .secondary)
                            }
                            Text(project.name)
                            Spacer()
                            if selection?.id == project.id {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .frame(width: 200, height: min(CGFloat(projects.count) * 36 + 24, 200))
    }
}

// MARK: - Date Picker Popover

struct DatePickerPopover: View {
    @Binding var selection: Date?
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // Presets
            HStack {
                Button("Today") {
                    selection = DueDateSupport.presetToday()
                    isPresented = false
                }
                Button("Tomorrow") {
                    selection = DueDateSupport.presetTomorrow()
                    isPresented = false
                }
                Button("Weekend") {
                    selection = DueDateSupport.presetNextSaturday()
                    isPresented = false
                }
            }
            .controlSize(.small)
            
            Divider()
            
            // Custom Calendar
            CustomDatePicker(selection: $selection)
            
            Divider()
            
            // Clear
            Button("Clear Date") {
                selection = nil
                isPresented = false
            }
            .foregroundStyle(.red)
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 280)
    }
}

// MARK: - Duration Picker Popover

struct DurationPickerPopover: View {
    @Binding var selection: TimeInterval?
    @Binding var isPresented: Bool
    @State private var customDurationText: String = ""
    
    private let presets: [TimeInterval] = [900, 1800, 2700, 3600, 7200] // 15m, 30m, 45m, 1h, 2h
    
    var body: some View {
        VStack(spacing: 12) {
            // Custom Input
            HStack {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                TextField("Custom min...", text: $customDurationText)
                    .textFieldStyle(.plain)
                    .frame(width: 80)
                    .onSubmit {
                        if let mins = Double(customDurationText) {
                            selection = mins * 60
                            isPresented = false
                            customDurationText = ""
                        }
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
            
            Divider()
            
            // Presets
            VStack(spacing: 4) {
                // None option
                Button {
                    selection = nil
                    isPresented = false
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("None")
                        Spacer()
                        if selection == nil {
                            Image(systemName: "checkmark")
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selection == nil ? Color.accentColor.opacity(0.1) : Color.clear)
                .cornerRadius(6)
                
                ForEach(presets, id: \.self) { seconds in
                    Button {
                        selection = seconds
                        isPresented = false
                    } label: {
                        HStack {
                            Image(systemName: seconds < 3600 ? "hourglass" : "timer")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            
                            Text(formatDuration(seconds))
                            Spacer()
                            
                            if selection == seconds {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(selection == seconds ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
            }
        }
        .padding()
        .frame(width: 160)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}

// MARK: - Recurrence Picker Popover

struct RecurrencePickerPopover: View {
    @Binding var isRecurring: Bool
    @Binding var recurrenceInterval: String?
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Button {
                isRecurring = false
                recurrenceInterval = nil
                isPresented = false
            } label: {
                Label("Never", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .background(!isRecurring ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            
            Divider()
            
            Button {
                isRecurring = true
                recurrenceInterval = "daily"
                isPresented = false
            } label: {
                Label("Daily", systemImage: "sun.max")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .background(recurrenceInterval == "daily" ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            
            Button {
                isRecurring = true
                recurrenceInterval = "weekly"
                isPresented = false
            } label: {
                Label("Weekly", systemImage: "calendar")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .background(recurrenceInterval == "weekly" ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .padding(8)
        .frame(width: 140)
    }
}

/// A clickable badge that opens a popover for editing
struct EditableBadge<Content: View, PopoverContent: View>: View {
    @Binding var showPopover: Bool
    let content: Content
    let popover: PopoverContent
    
    init(
        showPopover: Binding<Bool>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder popover: () -> PopoverContent
    ) {
        self._showPopover = showPopover
        self.content = content()
        self.popover = popover()
    }
    
    @State private var isHovering = false
    
    var body: some View {
        Button {
            // Use transaction to prevent animation delay on popover
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showPopover = true
            }
        } label: {
            content
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background {
                    if isHovering {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovering = hover
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            popover
        }
    }
}
