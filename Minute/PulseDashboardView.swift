//
//  PulseDashboardView.swift
//  Minute
//
//  The high-signal "Heads Up" display for your day.
//  Replaces the static Areas grid as the daily driver.
//

import SwiftUI
import SwiftData
import Charts
import Combine
import UniformTypeIdentifiers

struct PulseDashboardView: View {
    @EnvironmentObject var tracker: TrackerService
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.startTimestamp, order: .forward) private var sessions: [Session]
    @Query(sort: \Area.orderIndex) private var areas: [Area]
    
    // Navigation to Areas
    let onNavigateToAreas: () -> Void
    
    @State private var lossReport: DailyLossReport?
    private let lossAnalyzer = LossAnalyzer()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                
                // Date Header
                HStack {
                    Text(Date(), format: .dateTime.weekday(.wide).month().day())
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                
                // 1. Hero: Current Focus
                CurrentFocusCard()
                
                // 2. Metrics Grid
                if let report = lossReport {
                    MetricsOverview(report: report)
                }
                
                // 3. Areas Summary (Navigation Entry)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Areas & Projects")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Manage All", action: onNavigateToAreas)
                            .buttonStyle(.link)
                            .font(.subheadline)
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(areas) { area in
                                AreaCompactCard(area: area)
                            }
                            
                            Button(action: onNavigateToAreas) {
                                VStack {
                                    Image(systemName: "square.grid.2x2")
                                        .font(.title2)
                                    Text("View All")
                                        .font(.caption)
                                }
                                .frame(width: 100, height: 100)
                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                    }
                }
                
                Spacer()
            }
            .padding(32)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { updateMetrics() }
        .onChange(of: sessions.count) { _, _ in updateMetrics() }
    }
    
    private func updateMetrics() {
        // Filter for today
        let calendar = Calendar.current
        let todaySessions = sessions.filter { calendar.isDateInToday($0.startTimestamp) }
        lossReport = lossAnalyzer.analyzeDay(sessions: todaySessions)
    }
}

// MARK: - Components

struct CurrentFocusCard: View {
    @EnvironmentObject var tracker: TrackerService
    @Environment(\.modelContext) private var modelContext
    @State private var timeElapsed: TimeInterval = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 24) {
            if let task = tracker.activeTask {
                // Active State
                VStack(spacing: 8) {
                    Text("NOW FOCUSING ON")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    
                    Text(task.title)
                        .font(.system(size: 32, weight: .bold))
                        .multilineTextAlignment(.center)
                    
                    if let project = task.project {
                        HStack {
                            Image(systemName: project.area?.iconName ?? "folder")
                            Text(project.name)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Color(hex: project.area?.themeColor ?? "")?.opacity(0.1) ?? Color.accentColor.opacity(0.1),
                            in: Capsule()
                        )
                        .foregroundStyle(Color(hex: project.area?.themeColor ?? "") ?? .primary)
                    }
                }
                
                // Timer
                Text(formatDuration(timeElapsed))
                    .font(.system(size: 64, weight: .light).monospacedDigit())
                    .contentTransition(.numericText())
                
                Button(action: { tracker.stopCurrentTask() }) {
                    Label("Stop Session", systemImage: "stop.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.red.opacity(0.1), in: Capsule())
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                
            } else {
                // Idle State
                VStack(spacing: 16) {
                    Image(systemName: "steeringwheel")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    
                    Text("Free Flowing")
                        .font(.title)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    Text("Select a task from the stream to begin focus.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 40)
            }
        }
        // ... styling ...
        .onDrop(of: [.text], delegate: FocusDropDelegate(tracker: tracker, modelContext: modelContext, isTargeted: $isTargeted))
        .onReceive(timer) { _ in
            if let task = tracker.activeTask, 
               let current = tracker.currentSession,
               current.task?.id == task.id {
                timeElapsed = current.duration
            } else {
                timeElapsed = 0
            }
        }
    }
    
    @State private var isTargeted = false
    
    func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%01d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

struct MetricsOverview: View {
    let report: DailyLossReport
    
    var body: some View {
        HStack(spacing: 16) {
            // Productive
            MetricTile(
                title: "Productive",
                value: formatMinutes(report.productiveMinutes),
                icon: "checkmark.circle.fill",
                color: .green
            )
            
            // Distracted
            MetricTile(
                title: "Distracted",
                value: formatMinutes(report.totalLossMinutes),
                icon: "exclamationmark.triangle.fill",
                color: report.totalLossMinutes > 30 ? .red : .orange
            )
            
            // Switches
            MetricTile(
                title: "Context Switches",
                value: "\(Int(report.switchingRate))/hr",
                icon: "arrow.left.arrow.right",
                color: .purple
            )
        }
    }
    
    func formatMinutes(_ minutes: Double) -> String {
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct AreaCompactCard: View {
    let area: Area
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: area.iconName)
                .font(.title2)
                .foregroundStyle(Color(hex: area.themeColor) ?? .blue)
            
            Text(area.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            
            Text("\(area.projects.filter { $0.status == .active }.count) projects")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120, height: 100)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Drop Delegate
struct FocusDropDelegate: DropDelegate {
    let tracker: TrackerService
    let modelContext: ModelContext
    @Binding var isTargeted: Bool
    
    func dropEntered(info: DropInfo) {
        withAnimation {
            isTargeted = true
        }
    }
    
    func dropExited(info: DropInfo) {
        withAnimation {
            isTargeted = false
        }
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [.text]).first else { return false }
        
        itemProvider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { (data, error) in
            guard let data = data as? Data,
                  let uuidString = String(data: data, encoding: .utf8),
                  let uuid = UUID(uuidString: uuidString) else { return }
            
            // Dispatch back to main thread
            Task { @MainActor in
                do {
                    let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == uuid })
                    if let task = try modelContext.fetch(descriptor).first {
                        tracker.startTask(task)
                    }
                } catch {
                    print("Failed to find task: \(error)")
                }
                
                withAnimation {
                    isTargeted = false
                }
            }
        }
        return true
    }
}
