//
//  DistractionRules.swift
//  Minute
//
//  Single source of truth for distraction classification
//

import Foundation

/// Centralized rules for classifying surfaces as distractions, work, or communication
struct DistractionRules {
    
    // MARK: - Distraction Domains
    
    /// Domains that are always considered distractions
    static let distractionDomains: Set<String> = [
        // Video streaming
        "youtube.com", "netflix.com", "hulu.com", "disneyplus.com", "primevideo.com",
        "twitch.tv", "vimeo.com", "dailymotion.com",
        
        // Social media
        "twitter.com", "x.com", "facebook.com", "instagram.com", "tiktok.com",
        "snapchat.com", "linkedin.com/feed",
        
        // Entertainment/News rabbit holes
        "reddit.com", "9gag.com", "buzzfeed.com", "imgur.com",
        "tumblr.com", "pinterest.com",
        
        // Gaming
        "twitch.tv", "discord.com", "steampowered.com",
        
        // Shopping (casual browsing)
        "amazon.com", "ebay.com", "etsy.com"
    ]
    
    // MARK: - Distraction Apps
    
    /// Bundle IDs that are always considered distractions
    static let distractionApps: Set<String> = [
        "com.apple.TV",
        "com.spotify.client",
        "com.apple.Music",
        "com.netflix.Netflix",
        "com.google.ios.youtube",
        "tv.twitch.Twitch"
    ]
    
    // MARK: - Work Domains
    
    /// Domains considered productive work
    static let workDomains: Set<String> = [
        "github.com", "gitlab.com", "bitbucket.org",
        "stackoverflow.com", "developer.apple.com",
        "docs.google.com", "sheets.google.com", "slides.google.com",
        "notion.so", "figma.com", "linear.app",
        "vercel.com", "netlify.com", "aws.amazon.com",
        "console.cloud.google.com"
    ]
    
    // MARK: - Communication Domains
    
    /// Domains for communication (neutral - not distraction, not focused work)
    static let commsDomains: Set<String> = [
        "slack.com", "teams.microsoft.com",
        "mail.google.com", "outlook.com", "outlook.office.com",
        "zoom.us", "meet.google.com",
        "calendar.google.com", "outlook.office365.com/calendar"
    ]
    
    // MARK: - Classification Methods
    
    /// Check if a domain is a distraction
    static func isDistraction(domain: String) -> Bool {
        distractionDomains.contains { domain.contains($0) }
    }
    
    /// Check if an app bundle ID is a distraction
    static func isDistraction(bundleID: String) -> Bool {
        distractionApps.contains(bundleID)
    }
    
    /// Check if a session is a distraction (considers both app and browser domain)
    static func isDistraction(session: Session) -> Bool {
        // Check activity type first
        if session.activityType == .entertainment {
            return true
        }
        
        // Check app bundle ID
        if distractionApps.contains(session.bundleID) {
            return true
        }
        
        // Check browser domain
        if let domain = session.browserDomain {
            return isDistraction(domain: domain)
        }
        
        return false
    }
    
    /// Check if a browser visit is a distraction
    static func isDistraction(visit: BrowserVisit) -> Bool {
        isDistraction(domain: visit.domain)
    }
    
    /// Check if a domain is work-related
    static func isWork(domain: String) -> Bool {
        workDomains.contains { domain.contains($0) }
    }
    
    /// Check if a domain is communication-related
    static func isCommunication(domain: String) -> Bool {
        commsDomains.contains { domain.contains($0) }
    }
}
