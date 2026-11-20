import SwiftUI

/// Shown over the whole window while audio files are dragged across it.
struct DropOverlayView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.thinMaterial)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.tint.opacity(0.08))
                .padding(10)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2.5, dash: [9, 6]))
                .padding(10)
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 40, weight: .light))
                Text("Drop to add")
                    .font(.title2.weight(.semibold))
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, 36)
            .padding(.vertical, 26)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 3)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Non-blocking inline messages (rejected files, long-sound warnings, …).
struct NoticeStackView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.notices) { notice in
                NoticeRow(notice: notice) { model.dismissNotice(notice.id) }
                    .transition(Motion.edgeTransition(.top, reduceMotion: reduceMotion))
            }
        }
        .animation(Motion.spring(reduceMotion: reduceMotion), value: model.notices)
    }
}

private struct NoticeRow: View {
    let notice: Notice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(notice.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12))
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch notice.kind {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch notice.kind {
        case .error: .red
        case .warning: .yellow
        case .info: .accentColor
        }
    }
}

/// Brief confirmation at the bottom of the window, optionally with an action (Undo).
struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.callout)
                .lineLimit(2)
            if let title = toast.actionTitle, let action = toast.action {
                Button(title, action: action)
                    .buttonStyle(.link)
                    .font(.callout.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.separator, lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
    }
}

/// One-time, dismissible tip. Goes away for good once a shortcut is recorded.
struct FirstRunHintView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text("Add a sound, then record a shortcut. It will play from anywhere, even with this window closed.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Got It") { model.dismissHint() }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tip")
    }
}
