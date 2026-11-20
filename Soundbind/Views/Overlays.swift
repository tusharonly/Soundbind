import SwiftUI

/// Shown over the whole window while audio files are dragged across it.
struct DropOverlayView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.thinMaterial)
            Theme.card(22)
                .fill(Theme.highlight.opacity(0.14))
                .padding(10)
            Theme.card(22)
                .strokeBorder(Theme.highlight, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10, 8]))
                .padding(10)
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 36, weight: .semibold))
                Text("Drop to add")
                    .font(.title.weight(.bold))
                    .tracking(-0.5)
            }
            .foregroundStyle(Theme.onInk)
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .background(Theme.ink, in: Theme.card(24))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
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
                .font(.callout.weight(.medium))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(tint.opacity(0.16), in: Theme.card(12))
        .padding(.horizontal, 12)
        .padding(.top, 8)
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
                .font(.callout.weight(.semibold))
                .lineLimit(2)
            if let title = toast.actionTitle, let action = toast.action {
                Button(action: action) {
                    Text(title)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.highlight, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Theme.onInk)
        .padding(.leading, 18)
        .padding(.trailing, toast.actionTitle == nil ? 18 : 8)
        .padding(.vertical, toast.actionTitle == nil ? 11 : 8)
        .background(Theme.ink, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
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
                .foregroundStyle(Theme.ink)
                .frame(width: 28, height: 28)
                .background(Theme.highlight, in: Theme.card(9))
                .accessibilityHidden(true)
            Text("Add a sound, then record a shortcut. It will play from anywhere, even with this window closed.")
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Got It") { model.dismissHint() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface, in: Theme.card())
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tip")
    }
}
