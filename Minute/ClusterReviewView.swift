//
//  ClusterReviewView.swift
//  Minute
//
//  Focus Threads - shows Task-based threads and unassigned session clusters
//

import SwiftUI
import SwiftData

struct ClusterReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.startTimestamp, order: .reverse) private var allSessions: [Session]
    
    @State private var clusters: [ClusterResult] = []
    @State private var selectedCluster: ClusterResult?
    
    // AI Inference
    @StateObject private var inferenceService = TaskInferenceService()
    @State private var showingAPIKeySheet = false
    @State private var apiKeyInput = ""
    
    private let clusterEngine = ClusterEngine()
    
    var todaySessions: [Session] {
        let calendar = Calendar.current
        return allSessions.filter { calendar.isDateInToday($0.startTimestamp) }
    }
    
    // 1. Sessions linked to a task
    var taskThreads: [(task: TaskItem, sessions: [Session], duration: TimeInterval)] {
        let linkedSessions = todaySessions.filter { $0.task != nil }
        let grouped = Dictionary(grouping: linkedSessions) { $0.task! }
        
        return grouped.map { task, sessions in
            let duration = sessions.reduce(0) { $0 + $1.duration }
            return (task, sessions.sorted { $0.startTimestamp < $1.startTimestamp }, duration)
        }.sorted { $0.duration > $1.duration }
    }
    
    // 2. Unassigned sessions (for clustering)
    var unassignedSessions: [Session] {
        todaySessions.filter { $0.task == nil }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                
                // Section 1: Task Threads (Intentional Work)
                if !taskThreads.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tracked Tasks")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        ForEach(taskThreads, id: \.task.id) { thread in
                            TaskThreadRow(task: thread.task, sessions: thread.sessions, totalDuration: thread.duration)
                        }
                    }
                }
                
                // Section 2: Unassigned / Free Flowing
                if !clusters.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Unassigned Flow")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            if !unassignedSessions.isEmpty {
                                Text("\(formatDuration(unassignedSessions.reduce(0){$0+$1.duration})) total")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        
                        ForEach(clusters) { cluster in
                            ClusterRow(cluster: cluster) {
                                selectedCluster = cluster
                            }
                        }
                    }
                } else if unassignedSessions.isEmpty && taskThreads.isEmpty {
                    emptyState
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshClusters()
        }
        // Refresh when sessions change
        .onChange(of: unassignedSessions.count) { _, _ in
            refreshClusters()
        }
        .sheet(item: $selectedCluster) { cluster in
            ClusterDetailSheet(cluster: cluster, onLabel: { label in
                applyLabel(label, to: cluster)
            })
        }
        .sheet(isPresented: $showingAPIKeySheet) {
            apiKeySheet
        }
    }
    
    // MARK: - Header
    
    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Focus Threads")
                    .font(.largeTitle.bold())
                
                Spacer()
                
                // AI Inference button
                Button {
                    if inferenceService.hasAPIKey {
                        Task {
                            await inferenceService.inferTaskLabels(for: unassignedSessions, modelContext: modelContext)
                            refreshClusters()
                        }
                    } else {
                        showingAPIKeySheet = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        if inferenceService.isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text("AI Group")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inferenceService.isProcessing || unassignedSessions.isEmpty)
                .help("Use AI to group unassigned sessions")
                
                Button {
                    refreshClusters()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                // Settings gear
                Button {
                    showingAPIKeySheet = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
            }
            
            Text("Your day, grouped by task contexts.")
                .foregroundStyle(.secondary)
        }
    }
    
    var apiKeySheet: some View {
        VStack(spacing: 20) {
            Text("Gemini API Key")
                .font(.headline)
            Text("Enter your Gemini API key for AI-powered task labeling")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("API Key", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            HStack {
                Button("Cancel") { showingAPIKeySheet = false }
                Button("Save") {
                    inferenceService.setAPIKey(apiKeyInput)
                    showingAPIKeySheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .onAppear {
            apiKeyInput = UserDefaults.standard.string(forKey: "GeminiAPIKey") ?? ""
        }
    }
    
    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No activity yet")
                .font(.headline)
            Text("Start working to see your focus threads appear here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Actions
    
    func refreshClusters() {
        // Only cluster UNASSIGNED sessions
        clusters = clusterEngine.clusterSessions(unassignedSessions)
    }
    
    func applyLabel(_ label: String, to cluster: ClusterResult) {
        for session in cluster.sessions {
            session.userTaskLabel = label
        }
        try? modelContext.save()
        refreshClusters()
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Task Thread Row (Assigned)

struct TaskThreadRow: View {
    let task: TaskItem
    let sessions: [Session]
    let totalDuration: TimeInterval
    
    @State private var isExpanded: Bool = false
    
    var productiveDuration: TimeInterval {
        sessions.filter { task.isRelevant($0) }.reduce(0) { $0 + $1.duration }
    }
    
    var lostDuration: TimeInterval {
        sessions.filter { !task.isRelevant($0) }.reduce(0) { $0 + $1.duration }
    }
    
    var metricsBadge: some View {
        HStack(spacing: 4) {
            // Productive
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                Text(formatDuration(productiveDuration))
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Color(hex: task.project?.area?.themeColor ?? "")?.opacity(0.2) ?? .blue.opacity(0.2),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .foregroundStyle(Color(hex: task.project?.area?.themeColor ?? "") ?? .blue)
            
            // Lost
            if lostDuration > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(formatDuration(lostDuration))
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Color.red.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(.red)
            }
        }
        .font(.subheadline.monospacedDigit())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack(spacing: 16) {
                    // Time Badge
                    metricsBadge
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.headline)
                        
                        if let project = task.project {
                            Text(project.name)
                                .font(.caption)
                                .foregroundStyle(Color(hex: project.area?.themeColor ?? "") ?? .secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Text("\(sessions.count) sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color.white.opacity(0.03))
            }
            .buttonStyle(.plain)
            
            // Expanded Details
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    ForEach(sessions) { session in
                        FocusThreadSessionRow(session: session, isRelevant: task.isRelevant(session))
                    }
                }
            }
        }
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
    func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

struct FocusThreadSessionRow: View {
    let session: Session
    let isRelevant: Bool
    
    var body: some View {
        HStack {
            Text(session.startTimestamp, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isRelevant ? .secondary : .tertiary)
                .frame(width: 60, alignment: .trailing)
            
            HStack(spacing: 6) {
                Text(session.appName)
                    .font(.caption)
                    .foregroundStyle(isRelevant ? .primary : .secondary)
                
                if let domain = session.browserDomain {
                    Text("• \(domain)")
                        .font(.caption)
                        .foregroundStyle(isRelevant ? .secondary : .tertiary)
                }
                
                if !isRelevant {
                    // Distraction Indicator
                    if let project = session.project {
                        // Belongs to another project
                        Text("→ \(project.name)")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(Color(hex: project.area?.themeColor ?? "")?.opacity(0.1) ?? .gray.opacity(0.1))
                            .foregroundStyle(Color(hex: project.area?.themeColor ?? "") ?? .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        // Generic Distraction
                        Image(systemName: "eye.slash")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.6))
                    }
                }
            }
            
            Spacer()
            
            Text(formatDuration(session.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(isRelevant ? Color.secondary : Color.red.opacity(0.8))
                .strikethrough(!isRelevant)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.white.opacity(isRelevant ? 0.01 : 0.005))
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Cluster Row (Unassigned)

struct ClusterRow: View {
    let cluster: ClusterResult
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Time range
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cluster.startTime, style: .time)
                        .font(.caption.monospacedDigit())
                    Text(formatDuration(cluster.duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 70, alignment: .trailing)
                
                // Color bar (Gray for unassigned)
                RoundedRectangle(cornerRadius: 2)
                    .fill(.gray.opacity(0.3))
                    .frame(width: 4)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(cluster.label)
                            .font(.headline)
                            .foregroundStyle(.secondary) // Muted for unassigned
                        
                        if cluster.suggestedLabel != nil {
                            Text("Suggested")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }
                    
                    HStack(spacing: 8) {
                        if let app = cluster.primaryApp {
                            Label(app, systemImage: "app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let domain = cluster.primaryDomain {
                            Label(domain, systemImage: "globe")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text("\(cluster.sessionCount) sessions")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Cluster Detail Sheet (Same as before)
struct ClusterDetailSheet: View {
    let cluster: ClusterResult
    let onLabel: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var customLabel: String = ""
    
    let quickLabels = [
        "Coding", "Email", "Meetings", "Research",
        "Design", "Writing", "Planning", "Admin",
        "Learning", "Break"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(cluster.label)
                        .font(.title2.bold())
                    
                    Text("\(cluster.startTime.formatted(date: .omitted, time: .shortened)) – \(cluster.endTime.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
            }
            
            // Quick labels
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Labels")
                    .font(.headline)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 100))
                ], spacing: 8) {
                    ForEach(quickLabels, id: \.self) { label in
                        Button(label) {
                            onLabel(label)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .tint(label == cluster.suggestedLabel ? .blue : .gray)
                    }
                }
            }
            
            // Custom label
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Label")
                    .font(.headline)
                
                HStack {
                    TextField("Enter label...", text: $customLabel)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Apply") {
                        if !customLabel.isEmpty {
                            onLabel(customLabel)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customLabel.isEmpty)
                }
            }
            
            // Sessions in cluster
            VStack(alignment: .leading, spacing: 8) {
                Text("Sessions (\(cluster.sessionCount))")
                    .font(.headline)
                
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(cluster.sessions, id: \.id) { session in
                            HStack {
                                Text(session.appName)
                                    .font(.caption)
                                
                                if let domain = session.browserDomain {
                                    Text("• \(domain)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Text(formatDuration(session.duration))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
            }
                .frame(maxHeight: 200)
            }
            
            Spacer()
        }
        .padding(24)
        .frame(width: 450, height: 500)
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
