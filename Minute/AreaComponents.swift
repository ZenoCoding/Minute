//
//  AreaComponents.swift
//  Minute
//
//  Shared components for Area management.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Drop Delegate
struct AreaDropDelegate: DropDelegate {
    let item: Area
    @Binding var items: [Area]
    @Binding var draggedItem: Area?
    let modelContext: ModelContext
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem else { return }
        
        if draggedItem != item {
            if let from = items.firstIndex(of: draggedItem),
               let to = items.firstIndex(of: item) {
                withAnimation(.default) {
                    items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        // Persist order
        for (index, area) in items.enumerated() {
            area.orderIndex = index
        }
        try? modelContext.save()
        self.draggedItem = nil
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Utilities
struct IconSuggester {
    static func suggest(for name: String) -> String? {
        let lower = name.lowercased()
        
        // STEM / Engineering / CS
        if lower.contains("phys") { return "atom" }
        if lower.contains("eng") { return "hammer.fill" }
        if lower.contains("code") || lower.contains("dev") || lower.contains("soft") || lower.contains("cs") || lower.contains("comp") { return "chevron.left.forwardslash.chevron.right" }
        if lower.contains("math") || lower.contains("calc") { return "function" }
        if lower.contains("bio") || lower.contains("chem") || lower.contains("sci") { return "flask.fill" }
        
        // Subjects
        if lower.contains("hist") { return "scroll.fill" }
        if lower.contains("lit") || lower.contains("writ") || lower.contains("lang") || lower.contains("read") { return "text.quote" }
        if lower.contains("art") || lower.contains("draw") || lower.contains("paint") { return "paintbrush.fill" }
        if lower.contains("music") { return "music.quarternote.3" }
        
        // General
        if lower.contains("work") || lower.contains("job") { return "briefcase.fill" }
        if lower.contains("home") || lower.contains("house") { return "house.fill" }
        if lower.contains("fin") || lower.contains("money") { return "creditcard.fill" }
        if lower.contains("travel") || lower.contains("trip") { return "airplane" }
        if lower.contains("gym") || lower.contains("fit") || lower.contains("health") { return "figure.run" }
        
        return nil
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0

        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }

        self.init(sRGBColorSpace: .sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - UI Components

struct AreaCard: View {
    let area: Area
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddProject = false
    @State private var showingEditArea = false
    @State private var showingDeleteAlert = false
    
    var themeColor: Color {
        Color(hex: area.themeColor) ?? .blue
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                // Drag Handle
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                
                Image(systemName: area.iconName)
                    .font(.title2)
                    .foregroundStyle(themeColor)
                    .frame(width: 40, height: 40)
                    .background(themeColor.opacity(0.1), in: Circle())
                
                Text(area.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Add Project Button
                Button(action: { showingAddProject = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .contentShape(Rectangle())
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add Project")
                
                // Menu Button
                Menu {
                    Button("Edit Area") { showingEditArea = true }
                    Button("Delete Area", role: .destructive) { showingDeleteAlert = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .contentShape(Rectangle())
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
            }
            
            // Projects List
            VStack(alignment: .leading, spacing: 8) {
                if area.projects.isEmpty {
                    Text("No active projects")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(area.projects) { project in
                        ProjectPill(project: project, themeColor: themeColor)
                    }
                }
            }
        }
        .padding()
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            Button("Delete Area", role: .destructive) {
                modelContext.delete(area)
            }
        }
        .sheet(isPresented: $showingAddProject) {
            NewProjectSheet(area: area)
        }
        .sheet(isPresented: $showingEditArea) {
            EditAreaSheet(area: area)
        }
        .alert("Delete Area?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                modelContext.delete(area)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete the area and all its projects. This cannot be undone.")
        }
    }
}

struct ProjectPill: View {
    let project: Project
    let themeColor: Color
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        HStack {
            // Status Dot
            Circle()
                .fill(project.status == .active ? themeColor : .secondary)
                .frame(width: 6, height: 6)
            
            Text(project.name)
                .font(.body)
            
            Spacer()
            
            // Time Spent (Placeholder)
            Text("0h")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Archive Project") {
                project.status = .archived
            }
            Button("Delete Project", role: .destructive) {
                modelContext.delete(project)
            }
        }
    }
}

struct EditAreaSheet: View {
    let area: Area
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var colorHex: String
    @State private var iconName: String
    
    init(area: Area) {
        self.area = area
        _name = State(initialValue: area.name)
        _colorHex = State(initialValue: area.themeColor)
        _iconName = State(initialValue: area.iconName)
    }
    
    let colors = ["007AFF", "34C759", "AF52DE", "FF9500", "FF2D55", "5856D6", "2AC0E4", "E4C92A", "8E8E93"]
    let icons = [
        "folder", "briefcase.fill", "person.fill", "house.fill", "star.fill", "heart.fill", "leaf.fill",
        "atom", "bolt.fill", "hammer.fill", "wrench.and.screwdriver.fill", "gear", "cpu", 
        "chevron.left.forwardslash.chevron.right", "terminal.fill", "desktopcomputer", "gamecontroller.fill",
        "function", "x.squareroot", "flask.fill", "ivfluid.bag.fill", "cross.case.fill",
        "graduationcap.fill", "book.fill", "book.closed.fill", "backpack.fill", "pencil", 
        "pencil.and.rulers.fill", "clipboard.fill", "scroll.fill", "clock.fill",
        "paintbrush.fill", "palette.fill", "music.quarternote.3", "guitars.fill", "theatermasks.fill", 
        "camera.fill", "puzzlepiece.fill", "lightbulb.fill", "text.quote",
        "cart.fill", "creditcard.fill", "airplane", "figure.run", "cup.and.saucer.fill",
        "newspaper", "mic.fill", "antenna.radiowaves.left.and.right", "tv.fill"
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Edit Area")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("Area Name", text: $name)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Theme")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 32))], spacing: 12) {
                    ForEach(colors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .blue)
                            .frame(width: 32, height: 32)
                            .overlay {
                                if colorHex == hex {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .shadow(radius: 1)
                                }
                            }
                            .onTapGesture { colorHex = hex }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 12) {
                        ForEach(icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .foregroundStyle(iconName == icon ? .white : .secondary)
                                .background(iconName == icon ? Color(hex: colorHex) ?? .blue : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { iconName = icon }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 200)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                
                Button("Save Changes") {
                    area.name = name
                    area.themeColor = colorHex
                    area.iconName = iconName
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(hex: colorHex) ?? .blue, in: RoundedRectangle(cornerRadius: 8))
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct NewAreaSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var colorHex = "007AFF"
    @State private var iconName = "folder"
    @State private var hasManuallySelectedIcon = false
    
    let colors = ["007AFF", "34C759", "AF52DE", "FF9500", "FF2D55", "5856D6", "2AC0E4", "E4C92A", "8E8E93"]
    let icons = [
        "folder", "briefcase.fill", "person.fill", "house.fill", "star.fill", "heart.fill", "leaf.fill",
        "atom", "bolt.fill", "hammer.fill", "wrench.and.screwdriver.fill", "gear", "cpu", 
        "chevron.left.forwardslash.chevron.right", "terminal.fill", "desktopcomputer", "gamecontroller.fill",
        "function", "x.squareroot", "flask.fill", "ivfluid.bag.fill", "cross.case.fill",
        "graduationcap.fill", "book.fill", "book.closed.fill", "backpack.fill", "pencil", 
        "pencil.and.rulers.fill", "clipboard.fill", "scroll.fill", "clock.fill",
        "paintbrush.fill", "palette.fill", "music.quarternote.3", "guitars.fill", "theatermasks.fill", 
        "camera.fill", "puzzlepiece.fill", "lightbulb.fill", "text.quote",
        "cart.fill", "creditcard.fill", "airplane", "figure.run", "cup.and.saucer.fill",
        "newspaper", "mic.fill", "antenna.radiowaves.left.and.right", "tv.fill"
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Create New Area")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                
                TextField("e.g. Work, Hobbies", text: $name)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .onChange(of: name) { oldValue, newValue in
                        if !hasManuallySelectedIcon, let suggested = IconSuggester.suggest(for: newValue) {
                            iconName = suggested
                        }
                    }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Theme Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 32))], spacing: 12) {
                    ForEach(colors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .blue)
                            .frame(width: 32, height: 32)
                            .overlay {
                                if colorHex == hex {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .shadow(radius: 1)
                                }
                            }
                            .onTapGesture { colorHex = hex }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 12) {
                        ForEach(icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .foregroundStyle(iconName == icon ? .white : .secondary)
                                .background(iconName == icon ? Color(hex: colorHex) ?? .blue : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { 
                                    iconName = icon
                                    hasManuallySelectedIcon = true
                                }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 200)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                
                Button("Create Area") {
                    let area = Area(name: name, themeColor: colorHex, iconName: iconName)
                    modelContext.insert(area)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(hex: colorHex) ?? .blue, in: RoundedRectangle(cornerRadius: 8))
                .disabled(name.isEmpty)
                .opacity(name.isEmpty ? 0.5 : 1)
            }
        }
        .padding(24)
        .frame(width: 400, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct NewProjectSheet: View {
    let area: Area
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    
    var themeColor: Color {
        Color(hex: area.themeColor) ?? .blue
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Text("New Project")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Project Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("e.g. Q4 Report, Lab Analysis", text: $name)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(themeColor.opacity(0.5), lineWidth: 1)
                    )
            }
            
            HStack {
                Text("Area:")
                    .foregroundStyle(.secondary)
                Image(systemName: area.iconName)
                    .foregroundStyle(themeColor)
                Text(area.name)
                    .fontWeight(.medium)
            }
            .font(.footnote)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                
                Button("Create Project") {
                    let project = Project(name: name, area: area)
                    modelContext.insert(project)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(themeColor, in: RoundedRectangle(cornerRadius: 8))
                .disabled(name.isEmpty)
                .opacity(name.isEmpty ? 0.5 : 1)
            }
        }
        .padding(24)
        .frame(width: 350, height: 280)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct NewTaskSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Project.createdAt) private var allProjects: [Project]
    var activeProjects: [Project] {
        allProjects.filter { $0.status == .active }
    }
    
    @State private var title = ""
    @State private var selectedProject: Project?
    
    var body: some View {
        VStack(spacing: 24) {
            Text("New Task")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("What needs doing?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("e.g. Draft Abstract", text: $title)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            
            if activeProjects.isEmpty {
                Text("No active projects found. Create a project first.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Picker("Project", selection: $selectedProject) {
                        Text("Select Project...").tag(nil as Project?)
                        ForEach(activeProjects) { project in
                            Text(project.name).tag(project as Project?)
                        }
                    }
                    .labelsHidden()
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                
                Button("Add Task") {
                    if let project = selectedProject {
                        let task = TaskItem(title: title, project: project)
                        modelContext.insert(task)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                .disabled(title.isEmpty || selectedProject == nil)
                .opacity((title.isEmpty || selectedProject == nil) ? 0.5 : 1)
            }
        }
        .padding(24)
        .frame(width: 400, height: 350)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if selectedProject == nil {
                selectedProject = activeProjects.first
            }
        }
    }
}
