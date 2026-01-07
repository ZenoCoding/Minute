//
//  OrbitView.swift
//  Minute
//
//  The main dashboard: Your Life Orbit.
//  New Architecture:
//  - Left: Task Stream (List)
//  - Right: Pulse Dashboard (Default) or Areas Manager (Navigation)
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct OrbitView: View {
    @State private var navigationPath = NavigationPath()
    
    enum NavigationDestination: Hashable {
        case areasManager
        case areaDetail(Area)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left: The Task Stream (Primary Focus)
            TaskStreamView()
                .frame(width: 350)
                .background(Color.black.opacity(0.1)) // Subtle separation
                .overlay(
                    Rectangle()
                        .frame(width: 1)
                        .foregroundStyle(Color.white.opacity(0.1)),
                    alignment: .trailing
                )
            
            // Right: The Orbit (Context/Planning)
            NavigationStack(path: $navigationPath) {
                PulseDashboardView(
                    onNavigateToAreas: {
                        navigationPath.append(NavigationDestination.areasManager)
                    }
                )
                .navigationDestination(for: NavigationDestination.self) { destination in
                    switch destination {
                    case .areasManager:
                        AreasManagerView()
                    case .areaDetail(let area):
                        AreaDetailView(area: area)
                    }
                }
                // Handle direct Area selection from PulseDashboard or AreasManager
                .navigationDestination(for: Area.self) { area in
                    AreaDetailView(area: area)
                }
            }
        }
        .background(Color(.windowBackgroundColor))
    }
}
