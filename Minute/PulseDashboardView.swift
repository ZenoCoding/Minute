//
//  PulseDashboardView.swift
//  Minute
//
//  The high-signal "Heads Up" display for your day.
//  Replaces the static Areas grid as the daily driver.
//

import SwiftUI
import SwiftData

struct PulseDashboardView: View {
    @Query(sort: \Area.orderIndex) private var areas: [Area]
    
    // Navigation to Areas
    let onNavigateToAreas: () -> Void
    
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
                
                // Areas Summary (Navigation Entry)
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
    }
}

struct AreaCompactCard: View {
    let area: Area
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: area.iconName)
                .font(.title2)
                .foregroundStyle(Color(hex: area.themeColor) ?? .blue)
            
            Text(area.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Text("\(area.projects.filter { $0.status == .active }.count) projects")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 140, height: 110)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}
