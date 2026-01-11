import SwiftUI
import SwiftData

struct SessionDebugView: View {
    @Query(sort: \Session.startTimestamp, order: .reverse) private var sessions: [Session]
    @Environment(\.modelContext) private var modelContext
    
    var activeSessions: [Session] {
        sessions.filter { $0.endTimestamp == nil }
    }
    
    var body: some View {
        VStack {
            Text("Active Sessions: \(activeSessions.count)")
                .font(.title)
                .foregroundStyle(activeSessions.count > 1 ? .red : .primary)
            
            List {
                Section("Active (Should be 1)") {
                    ForEach(activeSessions) { session in
                        DebugSessionRow(session: session)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            modelContext.delete(activeSessions[index])
                        }
                    }
                }
                
                Section("Recent History") {
                    ForEach(sessions.prefix(20)) { session in
                        DebugSessionRow(session: session)
                    }
                }
            }
        }
    }
}

struct DebugSessionRow: View {
    let session: Session
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.appName)
                    .font(.headline)
                Text(session.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(session.startTimestamp.formatted(date: .omitted, time: .standard))
                if let end = session.endTimestamp {
                    Text(end.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                } else {
                    Text("ACTIVE")
                        .foregroundStyle(.green)
                        .fontWeight(.bold)
                }
            }
        }
    }
}
