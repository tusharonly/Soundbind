import SwiftUI

/// Vertical bars mirrored around the centre line.
struct WaveformShape: Shape {
    let samples: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !samples.isEmpty, rect.width > 0 else { return path }
        let pitch = rect.width / CGFloat(samples.count)
        let barWidth = max(pitch * 0.6, 1)
        for (index, sample) in samples.enumerated() {
            let height = max(CGFloat(sample) * rect.height, 1.5)
            let bar = CGRect(
                x: rect.minX + CGFloat(index) * pitch + (pitch - barWidth) / 2,
                y: rect.midY - height / 2,
                width: barWidth,
                height: height
            )
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }
        return path
    }
}

/// Re-renders its content every frame with the current playback progress (0...1).
struct PlaybackProgressView<Content: View>: View {
    let playback: AudioEngineService.Playback
    @ViewBuilder var content: (Double) -> Content

    var body: some View {
        TimelineView(.animation) { context in
            content(playback.progress(at: context.date))
        }
    }
}

/// Small waveform; the played portion fills with the accent colour during playback.
struct WaveformThumbnail: View {
    let samples: [Float]
    let playback: AudioEngineService.Playback?

    var body: some View {
        let shape = WaveformShape(samples: samples)
        ZStack {
            shape.fill(.tertiary)
            if let playback {
                PlaybackProgressView(playback: playback) { progress in
                    shape
                        .fill(.tint)
                        .mask(alignment: .leading) {
                            GeometryReader { proxy in
                                Rectangle().frame(width: proxy.size.width * progress)
                            }
                        }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
