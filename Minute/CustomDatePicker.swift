//
//  CustomDatePicker.swift
//  Minute
//
//  Created by Tycho Young on 1/6/26.
//

import SwiftUI

struct CustomDatePicker: View {
    @Binding var selection: Date?
    @State private var currentMonth: Date
    
    private let calendar = Calendar.current
    private let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    
    init(selection: Binding<Date?>) {
        self._selection = selection
        self._currentMonth = State(initialValue: selection.wrappedValue ?? Date())
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text(monthYearString(currentMonth))
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: { changeMonth(by: -1) }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { changeMonth(by: 1) }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            
            // Weekday Headers
            HStack(spacing: 0) {
                ForEach(Array(daysOfWeek.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Days Grid
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(daysInMonth().enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        DayCell(date: date, isSelected: isSelected(date), isToday: calendar.isDateInToday(date)) {
                            selection = date
                        }
                    } else {
                        Color.clear.frame(height: 24)
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Logic
    
    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
        }
    }
    
    private func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func isSelected(_ date: Date) -> Bool {
        guard let selection = selection else { return false }
        return calendar.isDate(date, inSameDayAs: selection)
    }
    
    private func daysInMonth() -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: currentMonth),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        // Adjust for 0-indexed offset (Sunday = 1) based on daysOfWeek
        let offset = firstWeekday - 1
        
        var days: [Date?] = Array(repeating: nil, count: offset)
        
        for day in 1...range.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        return days
    }
}

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 13, weight: isSelected || isToday ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : (isToday ? .green : .primary))
                .frame(width: 28, height: 28)
                .background(
                    ZStack {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else if isToday {
                            Circle().stroke(Color.green, lineWidth: 1)
                        }
                    }
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
