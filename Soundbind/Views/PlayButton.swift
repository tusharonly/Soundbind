import SwiftUI

/// Round play/stop button with a progress ring while the sound is audible.
struct PlayButton: View {
    let soundName: String
    let playback: AudioEngineService.Playback?
    var diameter: CGFloat = 32
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var isPlaying: Bool { playback != nil }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isPlaying ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(Theme.surfaceStrong))
                Circle()
                    .strokeBorder(.tint.opacity(isHovered && isEnabled ? 0.6 : 0), lineWidth: 1)
                if let playback {
                    PlaybackProgressView(playback: playback) { progress in
                        Circle()
                            .inset(by: 1.25)
                            .trim(from: 0, to: progress)
                            .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                }
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: diameter * 0.36, weight: .semibold))
                    .foregroundStyle(isPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(Theme.ink))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, options: .repeating, isActive: isPlaying && !reduceMotion)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(isPlaying ? "Stop" : "Play")
        .accessibilityLabel(isPlaying ? "Stop \(soundName)" : "Play \(soundName)")
    }
}
