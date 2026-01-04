//
//  BrowserBridge.swift
//  Minute
//
//  Reads rich browser context from shared file written by native messaging host
//

import Foundation
import Combine

struct BrowserContext: Codable {
    let domain: String
    let title: String
    let timestamp: Int
    let updatedAt: Int
    
    // Rich context for AI task inference
    let path: String?
    let query: String?
    let description: String?
    let keywords: String?
    let ogType: String?
    let ogTitle: String?
    let ogDescription: String?
    let ogSiteName: String?
    let contentSnippet: String?
    let selectedText: String?
    let lang: String?
}

@MainActor
class BrowserBridge: ObservableObject {
    
    // Current browser context
    @Published private(set) var currentDomain: String?
    @Published private(set) var currentTitle: String?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isConnected: Bool = false
    
    // File monitoring
    private var fileMonitor: DispatchSourceFileSystemObject?
    private let contextFilePath: URL
    
    init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Minute")
        contextFilePath = appSupport.appendingPathComponent("browser_context.json")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        
        startMonitoring()
        
        // Initial read
        readContextFile()
    }
    
    private func startMonitoring() {
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: contextFilePath.path) {
            FileManager.default.createFile(atPath: contextFilePath.path, contents: nil)
        }
        
        let fd = open(contextFilePath.path, O_EVTONLY)
        guard fd >= 0 else {
            print("BrowserBridge: Failed to open context file for monitoring")
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .attrib],
            queue: .global()
        )
        
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.readContextFile()
            }
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        source.resume()
        fileMonitor = source
        
        // Also poll every 2 seconds as fallback (file events can be unreliable)
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let weakSelf = self else { return }
            Task { @MainActor in
                weakSelf.readContextFile()
            }
        }
        
        print("BrowserBridge: Monitoring context file at \(contextFilePath.path)")
    }
    
    private func readContextFile() {
        guard let data = try? Data(contentsOf: contextFilePath),
              let context = try? JSONDecoder().decode(BrowserContext.self, from: data) else {
            return
        }
        
        let updateTime = Date(timeIntervalSince1970: Double(context.updatedAt) / 1000)
        
        // Only update if this is recent (within last 30 seconds)
        guard Date().timeIntervalSince(updateTime) < 30 else {
            isConnected = false
            return
        }
        
        // Check if domain changed
        let previousDomain = currentDomain
        let domainChanged = previousDomain != nil && previousDomain != context.domain
        
        currentDomain = context.domain
        currentTitle = context.title
        lastUpdate = updateTime
        isConnected = true
        
        // Notify and log only if domain changed
        if domainChanged {
            onDomainChange?(previousDomain!, context.domain, context.title)
            print("BrowserBridge: Domain changed \(previousDomain!) -> \(context.domain)")
        } else if previousDomain == nil {
            print("BrowserBridge: Initial context - \(context.domain)")
        }
        
        // Store full context for rich access
        currentRichContext = context
        
        // Log rich context for debugging
        if let snippet = context.contentSnippet, !snippet.isEmpty {
            print("BrowserBridge: Rich context - path:\(context.path ?? "/"), snippet:\(snippet.prefix(60))...")
        }
    }
    
    // Callback for domain changes
    var onDomainChange: ((String, String, String?) -> Void)?
    
    // Current rich context (for AI inference)
    private(set) var currentRichContext: BrowserContext?
    
    // Get the current browser context for a session
    func getCurrentContext() -> (domain: String?, title: String?) {
        // Check if context is fresh (within last 5 seconds)
        if let lastUpdate = lastUpdate, Date().timeIntervalSince(lastUpdate) < 5 {
            return (currentDomain, currentTitle)
        }
        return (nil, nil)
    }
    
    /// Get rich context for AI task inference
    func getRichContext() -> BrowserContext? {
        guard let lastUpdate = lastUpdate, Date().timeIntervalSince(lastUpdate) < 5 else {
            return nil
        }
        return currentRichContext
    }
    
    deinit {
        fileMonitor?.cancel()
    }
}

