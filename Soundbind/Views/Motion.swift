import SwiftUI

/// Central place for animation choices, so Reduce Motion is honoured consistently.
enum Motion {
    static func spring(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.8)
    }

    static func rowTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
            removal: .scale(scale: 0.97).combined(with: .opacity)
        )
    }

    static func edgeTransition(_ edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}
