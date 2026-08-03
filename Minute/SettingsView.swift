//
//  SettingsView.swift
//  Minute
//
//  Settings panel with data management and configuration options
//

import SwiftUI
import SwiftData
import EventKit
import Combine

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var calendarManager: CalendarManager
    @Query private var allTasks: [TaskItem]
    @Query private var allProjects: [Project]
    @Query private var allAreas: [Area]
    @AppStorage(DayCapacitySettings.useFallbackDurationKey) private var useFallbackDuration = false
    @AppStorage(DayCapacitySettings.fallbackDurationMinutesKey) private var fallbackDurationMinutes = DayCapacitySettings.defaultFallbackDurationMinutes
    @AppStorage(DayCapacitySettings.sleepWeekdayWakeMinutesKey) private var sleepWeekdayWakeMinutes = DayCapacitySettings.defaultSleepWeekdayWakeMinutes
    @AppStorage(DayCapacitySettings.sleepWeekdayBedMinutesKey) private var sleepWeekdayBedMinutes = DayCapacitySettings.defaultSleepWeekdayBedMinutes
    @AppStorage(DayCapacitySettings.sleepWeekendWakeMinutesKey) private var sleepWeekendWakeMinutes = DayCapacitySettings.defaultSleepWeekendWakeMinutes
    @AppStorage(DayCapacitySettings.sleepWeekendBedMinutesKey) private var sleepWeekendBedMinutes = DayCapacitySettings.defaultSleepWeekendBedMinutes
    @AppStorage(CalendarManager.includeSpecialDaysKey) private var includeSpecialDays = true
    @AppStorage(CalendarManager.includeRecurringMeetingsKey) private var includeRecurringMeetings = true
    @AppStorage("shortcutActivationMode") private var shortcutActivationMode = ShortcutActivationMode.doubleOption.rawValue
    @AppStorage(CodexProjectInferenceSettings.enabledKey) private var experimentalCodexInferenceEnabled = false
    
    @State private var showClearCompletedConfirm = false
    @State private var isAccessibilityGranted = ShortcutManager.isAccessibilityTrusted
    
    private let accessibilityTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    @State private var showClearAllConfirm = false
    @State private var clearMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                experimentalInferenceSection
                
                dataManagementSection

                capacityPlanningSection

                calendarHighlightsSection
                
                keyboardShortcutsSection
                
                aboutSection
                
                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var experimentalInferenceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Experimental AI")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $experimentalCodexInferenceEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use local Codex for project inference")
                            .font(.body)
                        Text("When local matching is uncertain, let the installed Codex CLI suggest a project without delaying capture.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Text("Optional and off by default. Task text, project names, and recent task hints are sent to Codex. Minute never reads or stores Codex credentials; if Codex is unavailable, times out, or returns an unknown project, the task is still saved and the local parser or Inbox fallback is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    var calendarHighlightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calendar Highlights")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $includeSpecialDays) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include holidays and birthdays")
                            .font(.body)
                        Text("Show all-day holiday and birthday events in schedule highlights.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $includeRecurringMeetings) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include recurring meetings")
                            .font(.body)
                        Text("Show recurring meeting-series events in schedule highlights.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                if hasCalendarAccess {
                    let calendars = calendarManager.availableCalendars()

                    if calendars.isEmpty {
                        Text("No calendars available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(calendars, id: \.calendarIdentifier) { calendar in
                            calendarModeRow(calendar)
                        }
                    }
                } else if calendarManager.authorizationStatus == .notDetermined {
                    Button("Connect Calendar") {
                        calendarManager.requestAccess()
                    }
                    .buttonStyle(.bordered)
                } else if calendarManager.authorizationStatus == .writeOnly {
                    Text("Calendar is set to Add Only. Switch to Full Access in System Settings to configure and preview highlights.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Calendar access is off. Enable calendar access in System Settings to configure highlight filters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    var keyboardShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                // Shortcut type picker
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Composer Hotkey")
                            .font(.body)
                        Text("Quickly show or hide the composer overlay.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $shortcutActivationMode) {
                        ForEach(ShortcutActivationMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                
                // If hotkey is enabled (i.e. not .disabled), show accessibility information
                if shortcutActivationMode != ShortcutActivationMode.disabled.rawValue {
                    Divider()
                        .padding(.vertical, 4)
                    
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: isAccessibilityGranted ? "lock.shield.fill" : "exclamationmark.shield.fill")
                            .font(.title2)
                            .foregroundStyle(isAccessibilityGranted ? .green : .orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Global Activation Status")
                                .font(.body.weight(.medium))
                            
                            if isAccessibilityGranted {
                                Text("Accessibility permission granted. You can activate the composer from any application.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Accessibility permission required to detect shortcuts globally (while Minute is in the background). Otherwise, the hotkey only works when Minute is active.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Button("Grant Permission") {
                                    ShortcutManager.requestAccessibilityPermission()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .padding(.top, 4)
                            }
                        }
                    }
                }
            }
            .padding()
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
        }
        .onReceive(accessibilityTimer) { _ in
            let trusted = ShortcutManager.isAccessibilityTrusted
            if isAccessibilityGranted != trusted {
                isAccessibilityGranted = trusted
            }
        }
    }
    
    // MARK: - Header
    
    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.largeTitle.bold())
            Text("Manage your data and preferences")
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Data Management
    
    var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Management")
                .font(.headline)
            
            VStack(spacing: 12) {
                // Clear Completed
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear Completed Tasks")
                            .font(.body)
                        Text("Remove all completed tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Clear Completed") {
                        showClearCompletedConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .confirmationDialog("Clear completed tasks?", isPresented: $showClearCompletedConfirm) {
                        Button("Clear Completed", role: .destructive) {
                            clearCompletedTasks()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete all completed tasks. This cannot be undone.")
                    }
                }
                .padding()
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
                
                // Clear All
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear All Data")
                            .font(.body)
                        Text("Remove all areas, projects, and tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Clear All") {
                        showClearAllConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .confirmationDialog("Clear All Data?", isPresented: $showClearAllConfirm) {
                        Button("Clear Everything", role: .destructive) {
                            clearAllData()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete ALL areas, projects, and tasks. This cannot be undone.")
                    }
                }
                .padding()
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
            }
            
            if let message = clearMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.top, 4)
            }
        }
    }
    
    var storageSize: String {
        let storeURL = MinuteStoreLocation.resolvedURL()
        
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: storeURL.path)
            if let size = attrs[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        } catch {
            return "—"
        }
        return "—"
    }
    
    func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
    
    // MARK: - Capacity Planning

    var capacityPlanningSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capacity Planning")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $useFallbackDuration) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use fallback for unestimated tasks")
                            .font(.body)
                        Text("Include tasks with no estimate in the Daily Capacity Meter.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if useFallbackDuration {
                    Stepper(value: $fallbackDurationMinutes, in: 5...240, step: 5) {
                        HStack {
                            Text("Fallback Duration")
                            Spacer()
                            Text("\(fallbackDurationMinutes) min")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sleep Schedule")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    timeSettingRow("Weekday Wake", selection: weekdayWakeBinding)
                    timeSettingRow("Weekday Bedtime", selection: weekdayBedBinding)
                    timeSettingRow("Weekend Wake", selection: weekendWakeBinding)
                    timeSettingRow("Weekend Bedtime", selection: weekendBedBinding)
                }
            }
            .padding()
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - About
    
    var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.headline)
            
            VStack(spacing: 12) {
                statRow("Version", value: "0.2")
                statRow("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                statRow("Storage Size", value: storageSize)
                statRow("Areas", value: "\(allAreas.count)")
                statRow("Projects", value: "\(allProjects.count)")
                statRow("Tasks", value: "\(allTasks.count)")
            }
            .padding()
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    // MARK: - Actions

    private var weekdayWakeBinding: Binding<Date> {
        Binding(
            get: { minutesToTimeDate(sleepWeekdayWakeMinutes) },
            set: { sleepWeekdayWakeMinutes = timeDateToMinutes($0) }
        )
    }

    private var weekdayBedBinding: Binding<Date> {
        Binding(
            get: { minutesToTimeDate(sleepWeekdayBedMinutes) },
            set: { sleepWeekdayBedMinutes = timeDateToMinutes($0) }
        )
    }

    private var weekendWakeBinding: Binding<Date> {
        Binding(
            get: { minutesToTimeDate(sleepWeekendWakeMinutes) },
            set: { sleepWeekendWakeMinutes = timeDateToMinutes($0) }
        )
    }

    private var weekendBedBinding: Binding<Date> {
        Binding(
            get: { minutesToTimeDate(sleepWeekendBedMinutes) },
            set: { sleepWeekendBedMinutes = timeDateToMinutes($0) }
        )
    }

    private func timeSettingRow(_ label: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(label)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    private func minutesToTimeDate(_ minutes: Int) -> Date {
        let clamped = min(max(minutes, 0), 1439)
        let start = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .minute, value: clamped, to: start) ?? start
    }

    private func timeDateToMinutes(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return min(max(hour * 60 + minute, 0), 1439)
    }

    private var hasCalendarAccess: Bool {
        calendarManager.canReadEvents
    }

    private func calendarModeRow(_ calendar: EKCalendar) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(nsColor: calendar.color))
                .frame(width: 8, height: 8)

            Text(calendar.title)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Picker("", selection: calendarModeBinding(for: calendar)) {
                ForEach(CalendarVisibilityMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 135)
        }
    }

    private func calendarModeBinding(for calendar: EKCalendar) -> Binding<CalendarVisibilityMode> {
        Binding(
            get: { calendarManager.visibilityMode(for: calendar) },
            set: { calendarManager.setVisibilityMode($0, for: calendar.calendarIdentifier) }
        )
    }

    func clearCompletedTasks() {
        let completed = allTasks.filter { $0.isCompleted }
        for task in completed {
            modelContext.delete(task)
        }
        try? modelContext.save()
        clearMessage = "Cleared \(completed.count) completed tasks"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            clearMessage = nil
        }
    }
    
    func clearAllData() {
        let areaCount = allAreas.count
        let projectCount = allProjects.count
        let taskCount = allTasks.count
        
        for task in allTasks {
            modelContext.delete(task)
        }
        for project in allProjects {
            modelContext.delete(project)
        }
        for area in allAreas {
            modelContext.delete(area)
        }
        
        try? modelContext.save()
        clearMessage = "Cleared \(areaCount) areas, \(projectCount) projects, \(taskCount) tasks"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            clearMessage = nil
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(CalendarManager())
}
