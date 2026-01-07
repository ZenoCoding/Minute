//
//  ClusterReviewView.swift
//  Minute
//
//  Focus Threads - shows AI-managed focus groups and session clusters
//

import SwiftUI
import SwiftData

struct ClusterReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.startTimestamp, order: .reverse) private var allSessions: [Session]
    @Query(sort: \FocusGroup.lastActiveAt, order: .reverse) private var allFocusGroups: [FocusGroup]
    
    @State private var clusters: [ClusterResult] = []
    @State private var selectedCluster: ClusterResult?
    @State private var selectedFocusGroup: FocusGroup?
    @State private var customLabel: String = ""
    
    // AI Inference
    @StateObject private var inferenceService = TaskInferenceService()
    @State private var showingAPIKeySheet = false
    @State private var apiKeyInput = ""
    
    private let clusterEngine = ClusterEngine()
    
    var todaySessions: [Session] {
        let calendar = Calendar.current
        return allSessions.filter { calendar.isDateInToday($0.startTimestamp) }
    }
    
    var todayFocusGroups: [FocusGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return allFocusGroups.filter { $0.date >= today }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                
                // Show AI Focus Groups if they exist
                if !todayFocusGroups.isEmpty {
                    focusGroupList
                } else if clusters.isEmpty {
                    emptyState
                } else {
                    clusterList
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshClusters()
        }
        .sheet(item: $selectedCluster) { cluster in
            ClusterDetailSheet(cluster: cluster, onLabel: { label in
                applyLabel(label, to: cluster)
            })
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
                            await inferenceService.inferTaskLabels(for: todaySessions, modelContext: modelContext)
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
                        Text("AI Label")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inferenceService.isProcessing)
                .help("Use AI to automatically label tasks")
                
                Button {
                    refreshClusters()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                // Settings gear for API key
                Button {
                    showingAPIKeySheet = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
            }
            
            HStack {
                Text("Your focus periods, broken by distractions")
                    .foregroundStyle(.secondary)
                
                if let error = inferenceService.lastError {
                    Text("• \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .sheet(isPresented: $showingAPIKeySheet) {
            apiKeySheet
        }
    }
    
    var apiKeySheet: some View {
        VStack(spacing: 20) {
            Text("Gemini API Key")
                .font(.headline)
            
            Text("Enter your Gemini API key for AI-powered task labeling")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            SecureField("API Key", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            HStack {
                Button("Cancel") {
                    showingAPIKeySheet = false
                }
                .keyboardShortcut(.escape)
                
                Button("Save") {
                    inferenceService.setAPIKey(apiKeyInput)
                    showingAPIKeySheet = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            
            Link("Get API Key from Google AI Studio", 
                 destination: URL(string: "https://aistudio.google.com/apikey")!)
                .font(.caption)
        }
        .padding(30)
        .onAppear {
            apiKeyInput = UserDefaults.standard.string(forKey: "GeminiAPIKey") ?? ""
        }
    }
    
    // MARK: - Empty State
    
    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("No focus groups yet")
                .font(.headline)
            
            Text("AI will create focus groups as you use your computer")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Focus Group List (AI-managed)
    
    var focusGroupList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Focus")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            ForEach(todayFocusGroups) { group in
                FocusGroupRow(group: group)
            }
        }
    }
    
    // MARK: - Cluster List
    
    var clusterList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's Focus Threads")
                .font(.headline)
            
            ForEach(clusters) { cluster in
                ClusterRow(cluster: cluster) {
                    selectedCluster = cluster
                }
            }
        }
    }
    
    // MARK: - Actions
    
    func refreshClusters() {
        clusters = clusterEngine.clusterSessions(todaySessions)
    }
    
    func applyLabel(_ label: String, to cluster: ClusterResult) {
        // Update all sessions in the cluster with the task label
        for session in cluster.sessions {
            session.userTaskLabel = label
        }
        try? modelContext.save()
        
        // Refresh clusters
        refreshClusters()
    }
}

// MARK: - Cluster Row

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
                
                // Color bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(cluster.confidence > 0.7 ? .green : .orange)
                    .frame(width: 4)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(cluster.label)
                            .font(.headline)
                        
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

// MARK: - Cluster Detail Sheet

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
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Focus Group Row

struct FocusGroupRow: View {
    let group: FocusGroup
    
    // Get time range
    var startTime: Date? {
        group.sessions.map(\.startTimestamp).min()
    }
    
    var endTime: Date? {
        group.sessions.compactMap(\.endTimestamp).max() ?? (group.sessions.isEmpty ? nil : Date())
    }
    
    // Get unique domains from all browser visits
    var uniqueDomains: [String] {
        var domains: [String: TimeInterval] = [:]
        for session in group.sessions {
            for visit in session.browserVisits {
                domains[visit.domain, default: 0] += visit.duration
            }
            if let domain = session.browserDomain {
                domains[domain, default: 0] += session.duration
            }
        }
        return domains.sorted { $0.value > $1.value }.map { $0.key }.prefix(5).map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with time
            HStack {
                // Time range
                VStack(alignment: .trailing, spacing: 2) {
                    if let start = startTime {
                        Text(start, style: .time)
                            .font(.caption.monospacedDigit())
                    }
                    Text(formatDuration(group.productiveTime))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 60, alignment: .trailing)
                
                // Color bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(.blue.gradient)
                    .frame(width: 4)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: group.icon ?? "sparkles")
                            .foregroundStyle(.blue)
                            .font(.caption)
                        Text(group.name)
                            .font(.headline)
                    }
                    
                    Text("\(group.sessionCount) sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Distraction badge
                if group.distractionTime > 60 {
                    Label(formatDuration(group.distractionTime), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            // Domains/websites visited (primary content)
            if !uniqueDomains.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(uniqueDomains, id: \.self) { domain in
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(domain)
                                .font(.caption)
                        }
                    }
                }
                .padding(.leading, 72)
            }
            
            // Apps used (secondary, collapsed)
            let apps = Dictionary(grouping: group.sessions.filter { !$0.isGroupDistraction }, by: \.appName)
                .sorted { $0.value.reduce(0) { $0 + $1.duration } > $1.value.reduce(0) { $0 + $1.duration } }
                .prefix(3)
            
            if !apps.isEmpty {
                HStack(spacing: 12) {
                    ForEach(apps.map { $0.key }, id: \.self) { appName in
                        Label(appName, systemImage: "app")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 72)
            }
        }
        .padding()
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
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

#Preview {
    ClusterReviewView()
}
