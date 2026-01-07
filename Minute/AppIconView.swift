
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppIconView: View {
    let bundleID: String
    let size: CGFloat
    
    @State private var icon: NSImage?
    
    var body: some View {
        Group {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Fallback while loading or if not found
                RoundedRectangle(cornerRadius: size * 0.225)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "app.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: size * 0.5))
                    )
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            fetchIcon()
        }
    }
    
    private func fetchIcon() {
        // Fast path: Check if we can get URL immediately
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            self.icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            // It might be a system app or not found by bundle ID directly
            // Try fallback to generic icon
            let genericIcon = NSWorkspace.shared.icon(for: .applicationBundle)
            self.icon = genericIcon
        }
    }
}
