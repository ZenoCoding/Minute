//
//  GlassCard.swift
//  Minute
//
//  Reusable glassmorphism component with layered materials
//

import SwiftUI

/// A reusable glass card component with frosted glass aesthetic
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var accentColor: Color? = nil
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        content()
            .padding(padding)
            .background {
                ZStack {
                    // Base glass material
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                    
                    // Subtle gradient overlay for depth
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.12),
                                    .clear,
                                    .black.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Optional accent tint
                    if let color = accentColor {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(color.opacity(0.08))
                    }
                }
            }
            .overlay(
                // Frosted border for edge definition
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.25), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

/// Convenience initializer extensions
extension GlassCard {
    init(
        cornerRadius: CGFloat = 16,
        accentColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
        self.padding = 16
        self.content = content
    }
    
    init(
        cornerRadius: CGFloat = 16,
        padding: CGFloat,
        accentColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
        self.padding = padding
        self.content = content
    }
}

// MARK: - Hover Effect Modifier

struct HoverScaleEffect: ViewModifier {
    @State private var isHovered = false
    var scale: CGFloat = 1.02
    var shadowRadius: CGFloat = 8
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .shadow(
                color: .black.opacity(isHovered ? 0.12 : 0.06),
                radius: isHovered ? shadowRadius : 4,
                x: 0,
                y: isHovered ? 6 : 2
            )
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func hoverScale(_ scale: CGFloat = 1.02, shadowRadius: CGFloat = 8) -> some View {
        modifier(HoverScaleEffect(scale: scale, shadowRadius: shadowRadius))
    }
}

// MARK: - Pulse Animation Modifier

struct PulseEffect: ViewModifier {
    @State private var isPulsing = false
    var intensity: CGFloat = 0.03
    var duration: Double = 2.0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.0 + intensity : 1.0)
            .opacity(isPulsing ? 1.0 : 0.95)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
    }
}

extension View {
    func pulse(intensity: CGFloat = 0.03, duration: Double = 2.0) -> some View {
        modifier(PulseEffect(intensity: intensity, duration: duration))
    }
}

// MARK: - Staggered Entrance Animation

struct StaggeredEntranceModifier: ViewModifier {
    let index: Int
    let baseDelay: Double
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 12)
            .animation(
                .spring(response: 0.4, dampingFraction: 0.85)
                .delay(Double(index) * baseDelay),
                value: isVisible
            )
            .onAppear {
                isVisible = true
            }
    }
}

extension View {
    func staggeredEntrance(index: Int, baseDelay: Double = 0.05) -> some View {
        modifier(StaggeredEntranceModifier(index: index, baseDelay: baseDelay))
    }
}

// MARK: - Glow Effect for Selection/Hover

struct GlowEffect: ViewModifier {
    var color: Color
    var isActive: Bool
    var radius: CGFloat = 8
    
    func body(content: Content) -> some View {
        content
            .shadow(
                color: isActive ? color.opacity(0.4) : .clear,
                radius: isActive ? radius : 0
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isActive)
    }
}

extension View {
    func glow(color: Color, isActive: Bool, radius: CGFloat = 8) -> some View {
        modifier(GlowEffect(color: color, isActive: isActive, radius: radius))
    }
}

// MARK: - Press Scale Button Style

struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressScaleButtonStyle {
    static var pressScale: PressScaleButtonStyle {
        PressScaleButtonStyle()
    }
}
