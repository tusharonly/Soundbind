import AppKit
import KeyboardShortcuts
import SwiftUI

/// Hosts the KeyboardShortcuts recorder (AppKit flavour, so the idle placeholder and
/// width can be customised). System-reserved combos are still handled by the recorder itself.
struct ShortcutRecorderView: NSViewRepresentable {
    let owner: HotkeyOwner
    var placeholder = "Click to record shortcut"
    var accessibilityLabel = "Shortcut"
    let onChange: (KeyboardShortcuts.Shortcut?) -> Void

    static let width: CGFloat = 164
    private static let font = NSFont.systemFont(ofSize: 12)

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .init(owner.key)) { [weak coordinator] shortcut in
            coordinator?.onChange?(shortcut)
        }
        recorder.font = Self.font
        recorder.setAccessibilityLabel(accessibilityLabel)
        recorder.toolTip = "Click, then press the keys for this shortcut. Press Delete to clear it."
        coordinator.attach(to: recorder, placeholder: placeholder)
        return recorder
    }

    func updateNSView(_ recorder: KeyboardShortcuts.RecorderCocoa, context: Context) {
        context.coordinator.onChange = onChange
        let name = KeyboardShortcuts.Name(owner.key)
        if recorder.shortcutName != name { recorder.shortcutName = name }
        recorder.setAccessibilityLabel(accessibilityLabel)
        if context.coordinator.placeholder != placeholder {
            context.coordinator.placeholder = placeholder
            context.coordinator.applyPlaceholder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: KeyboardShortcuts.RecorderCocoa, context: Context) -> CGSize? {
        CGSize(width: Self.width, height: nsView.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator {
        var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?
        var placeholder = ""
        private weak var recorder: KeyboardShortcuts.RecorderCocoa?
        private var observer: NSObjectProtocol?

        func attach(to recorder: KeyboardShortcuts.RecorderCocoa, placeholder: String) {
            self.recorder = recorder
            self.placeholder = placeholder
            applyPlaceholder()
            // The recorder swaps in its own placeholder whenever recording ends; put ours back.
            observer = NotificationCenter.default.addObserver(
                forName: Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange"),
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard notification.userInfo?["isActive"] as? Bool == false else { return }
                MainActor.assumeIsolated { self?.applyPlaceholder() }
            }
        }

        /// Accent-coloured so rows without a shortcut invite a click.
        func applyPlaceholder() {
            guard let recorder else { return }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            recorder.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: Theme.accentNSColor,
                    .font: ShortcutRecorderView.font,
                    .paragraphStyle: paragraph,
                ]
            )
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

/// Read-only keycap-style label for a shortcut, e.g. "⌃⌥1".
struct ShortcutBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Theme.secondaryInk)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.surfaceStrong, in: Theme.card(7))
            .accessibilityLabel("Shortcut \(text)")
    }
}

/// Inline warning shown when a recorded shortcut already belongs to something else.
struct ShortcutConflictView: View {
    let owner: HotkeyOwner
    let conflict: ShortcutConflict

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text("\(conflict.shortcut.description) is already used by \(model.name(of: conflict.holder)).")
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Cancel") { model.hotkeys.cancelConflict(for: owner) }
                .controlSize(.small)
            Button("Replace") { model.replaceConflictingShortcut(for: owner) }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .help("Move this shortcut here and remove it from \(model.name(of: conflict.holder))")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.yellow.opacity(0.18), in: Theme.card(11))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shortcut conflict")
    }
}
