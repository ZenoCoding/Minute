//
//  CompletedTaskRow.swift
//  Minute
//
//  Created by Tycho Young on 1/6/26.
//

import SwiftUI
import SwiftData

struct CompletedTaskRow: View {
    let item: StreamItem
    let modelContext: ModelContext
    @State private var isHovering = false
    
    var projectColor: Color {
        Color(hex: item.project.area?.themeColor ?? "8E8E93") ?? .gray
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox (Checked)
            Button(action: {
                withAnimation {
                    // Uncomplete
                    item.task.isCompleted = false
                    item.task.completedAt = nil
                }
            }) {
                ZStack {
                    Circle()
                        .fill(projectColor.opacity(0.8))
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(item.task.title)
                    .font(.body)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    if let icon = item.project.area?.iconName {
                        Image(systemName: icon)
                            .font(.caption2)
                    }
                    Text(item.project.name)
                        .font(.caption)
                }
                .foregroundStyle(projectColor.opacity(0.6))
            }
            
            Spacer()
            
            // Delete Button
            if isHovering {
                Button(action: {
                    withAnimation {
                        modelContext.delete(item.task)
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.7))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .opacity(0.6) // General dimming for completed stats
        .onHover { hover in
            isHovering = hover
        }
    }
}
