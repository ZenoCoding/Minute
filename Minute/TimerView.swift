//
//  TimerView.swift
//  Minute
//
//  Created by Tycho Young on 1/3/26.
//

import SwiftUI
import Combine

// MARK: - Timer Manager

@MainActor
class TimerManager: ObservableObject {
    enum TimerState {
        case idle
        case tuningIn // The 1.5s entrance
        case running
        case paused
        case completed
    }
    
    @Published var state: TimerState = .idle
    @Published var totalDuration: TimeInterval = 25 * 60
    @Published var remainingTime: TimeInterval = 25 * 60
    
    private var timer: AnyCancellable?
    private var entranceTimer: AnyCancellable?
    
    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return remainingTime / totalDuration
    }
    
    func setDuration(_ minutes: Int) {
        stop()
        totalDuration = TimeInterval(minutes * 60)
        remainingTime = totalDuration
    }
    
    func start() {
        guard state == .idle || state == .completed || state == .paused else { return }
        
        // Start "Tuning In" phase
        withAnimation(.easeInOut(duration: 1.5)) {
            state = .tuningIn
        }
        
        // After 1.5 seconds, switch to real running
        entranceTimer = Just(())
            .delay(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                withAnimation {
                    self?.state = .running
                    self?.startTicker()
                }
            }
    }
    
    private func startTicker() {
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }
    
    func pause() {
        guard state == .running else { return }
        timer?.cancel()
        state = .paused
    }
    
    func resume() {
        guard state == .paused else { return }
        state = .running
        startTicker()
    }
    
    func stop() {
        timer?.cancel()
        entranceTimer?.cancel()
        state = .idle
        remainingTime = totalDuration
    }
    
    private func tick() {
        if remainingTime > 0 {
            remainingTime -= 0.1
        } else {
            state = .completed
            timer?.cancel()
        }
    }
}

// MARK: - Circular Timer View

struct TimerView: View {
    @StateObject private var timerManager = TimerManager()
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            // 1. Background
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            // 2. Liquid Glass Backdrop
             Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 600, height: 600)
                .blur(radius: 100)
                .offset(x: -200, y: -200)
            
            Circle()
                .fill(Color.purple.opacity(0.1))
                .frame(width: 500, height: 500)
                .blur(radius: 80)
                .offset(x: 200, y: 200)
            
            // 3. Content Layer
            VStack {
                Spacer()
                
                ZStack {
                    // Track Ring
                    Circle()
                        .stroke(lineWidth: 12)
                        .foregroundStyle(.tertiary.opacity(0.3))
                        .glassEffect(.regular, in: Circle().stroke(lineWidth: 12)) // Usage of native API
                    
                    // Progress Ring
                    Circle()
                        .trim(from: 0, to: CGFloat(timerManager.progress))
                        .stroke(
                            style: StrokeStyle(lineWidth: 12, lineCap: .butt)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: .purple.opacity(0.3), radius: 10, x: 0, y: 0)
                        .animation(.linear(duration: 0.1), value: timerManager.progress)
                    
                    // Time Display
                    Text(formatTime(timerManager.remainingTime))
                        .font(.system(size: 120, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.primary.opacity(0.8))
                        .shadow(color: .white.opacity(0.5), radius: 0, x: 0, y: 1)
                }
                .frame(maxWidth: 500, maxHeight: 500)
                .padding(40)
                .blur(radius: timerManager.state == .tuningIn ? 15 : 0)
                .scaleEffect(timerManager.state == .tuningIn ? 0.9 : 1.0)
                .opacity(timerManager.state == .tuningIn ? 0.8 : 1.0)
                .animation(.easeInOut(duration: 1.5), value: timerManager.state)
                
                Spacer()
                
                // Controls
                controlsSection
                    .opacity((timerManager.state == .running || timerManager.state == .tuningIn) && !isHovering ? 0 : 1)
                    .animation(.easeInOut(duration: 0.4), value: isHovering)
                    .padding(.bottom, 50)
            }
            .padding(40)
        }
        .onHover { hovering in
            withAnimation {
                isHovering = hovering
            }
        }
    }
    
    var controlsSection: some View {
        HStack(spacing: 20) {
            HStack(spacing: 8) {
                PresetButton(minutes: 15, manager: timerManager)
                PresetButton(minutes: 25, manager: timerManager)
                PresetButton(minutes: 45, manager: timerManager)
                PresetButton(minutes: 60, manager: timerManager)
            }
            .padding(.horizontal, 8)
            
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: 1, height: 24)
            
            HStack(spacing: 16) {
                Button { withAnimation { timerManager.stop() } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: Circle()) // Native
                .disabled(timerManager.state == .idle)
                .opacity(timerManager.state == .idle ? 0.3 : 1)
                
                Button { toggleTimer() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
                        .overlay(
                            Circle().stroke(.white.opacity(0.2), lineWidth: 1).blendMode(.overlay)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .glassEffect(.regular.interactive(), in: Capsule()) // Native interactive physics
    }
    
    var isPlaying: Bool { timerManager.state == .running || timerManager.state == .tuningIn }
    
    private func toggleTimer() {
        if isPlaying { timerManager.pause() } else if timerManager.state == .paused { timerManager.resume() } else { timerManager.start() }
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Helper

struct PresetButton: View {
    let minutes: Int
    @ObservedObject var manager: TimerManager
    
    var isSelected: Bool { manager.totalDuration == TimeInterval(minutes * 60) }
    
    var body: some View {
        Button { withAnimation { manager.setDuration(minutes) } } label: {
            Text("\(minutes)m")
                .font(.subheadline.bold())
                .frame(width: 50, height: 32)
                .background(isSelected ? AnyShapeStyle(Color.blue.opacity(0.2)) : AnyShapeStyle(.clear), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.pressScale)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }
}
