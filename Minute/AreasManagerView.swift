//
//  AreasManagerView.swift
//  Minute
//
//  Management interface for Areas and Projects.
//  MOVED from OrbitView to be a secondary page.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AreasManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Area.createdAt) private var areas: [Area]
    private let goalService = GoalService()
    @State private var showingNewArea = false
    
    // Drag/Drop State
    @State private var orderedAreas: [Area] = []
    @State private var draggedArea: Area?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Areas")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Weekly Overview")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: { showingNewArea = true }) {
                        Label("New Area", systemImage: "plus")
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Areas Grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)], spacing: 16) {
                    ForEach(orderedAreas) { area in
                        NavigationLink(value: area) {
                            AreaCard(area: area)
                        }
                        .opacity(draggedArea?.id == area.id ? 0.0 : 1.0)
                        .buttonStyle(.plain)
                        .onDrag {
                            self.draggedArea = area
                            return NSItemProvider(object: area.id.uuidString as NSString)
                        } preview: {
                            AreaCard(area: area)
                                .frame(width: 300) // Fixed width for predictable preview
                                .background(Color(nsColor: .windowBackgroundColor))
                                .cornerRadius(16)
                        }
                        .onDrop(of: [.text], delegate: AreaDropDelegate(item: area, items: $orderedAreas, draggedItem: $draggedArea, modelContext: modelContext))
                    }
                }
                .padding(.horizontal)
                .onAppear {
                    syncOrderedAreas()
                }
                .onChange(of: areas) { _, _ in
                    syncOrderedAreas()
                }
                
                // Seed Button (Dev)
                if areas.isEmpty {
                    Button("Seed Default Areas") {
                        goalService.seedDefaultAreas(modelContext: modelContext)
                    }
                    .padding()
                }
            }
        }
        .background(Color(.windowBackgroundColor))
        .navigationDestination(for: Area.self) { area in
            AreaDetailView(area: area)
        }
        .sheet(isPresented: $showingNewArea) {
            NewAreaSheet()
        }
    }
    
    private func syncOrderedAreas() {
        if orderedAreas.isEmpty {
            orderedAreas = areas.sorted { $0.orderIndex < $1.orderIndex }
        } else {
            let currentIDs = Set(orderedAreas.map { $0.id })
            let newAreas = areas.filter { !currentIDs.contains($0.id) }
            if !newAreas.isEmpty {
                orderedAreas.append(contentsOf: newAreas)
            }
            let existIDs = Set(areas.map { $0.id })
            orderedAreas.removeAll { !existIDs.contains($0.id) }
        }
    }
}
