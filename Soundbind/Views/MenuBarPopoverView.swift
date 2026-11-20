import SwiftUI

/// Template image for the menu bar; briefly switches variant when a hotkey fires.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Image(systemName: model.isMenuBarPulsing ? "waveform.circle.fill" : "waveform")
            .accessibilityLabel("Soundbind")
            .help("Soundbind")
    }
}

struct MenuBarPopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private static let rowHeight: CGFloat = 34
    private static let maxListHeight: CGFloat = 340

    var body: some View {
        let items = model.library.items

        VStack(spacing: 0) {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(items) { item in
                            MenuBarSoundRow(item: item)
                                .frame(height: Self.rowHeight)
                        }
                    }
                    .padding(6)
                }
                .frame(height: min(CGFloat(items.count) * (Self.rowHeight + 1) + 12, Self.maxListHeight))
            }

            Divider()

            VStack(spacing: 1) {
                MenuBarActionRow(title: "Open Soundbind…", systemImage: "macwindow") {
                    openMainWindow()
                }
                MenuBarActionRow(
                    title: "Stop All Sounds",
                    systemImage: "stop.fill",
                    trailing: model.shortcutText(for: .stopAll)
                ) {
                    model.stopAll()
                }
                .disabled(!model.audio.isAnythingPlaying)
                MenuBarActionRow(title: "Settings…", systemImage: "gearshape", trailing: "⌘,") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
                MenuBarActionRow(title: "Quit Soundbind", systemImage: "power", trailing: "⌘Q") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(6)
        }
        .frame(width: 300)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.title)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("No sounds yet")
                .font(.headline)
            Text("Open Soundbind to add your first sound.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    private func openMainWindow() {
        openWindow(id: AppModel.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MenuBarSoundRow: View {
    let item: SoundItem

    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        let isMissing = model.library.isMissing(item.id)

        HStack(spacing: 8) {
            PlayButton(soundName: item.displayName, playback: model.audio.playback[item.id], diameter: 24) {
                model.togglePlayback(item.id)
            }
            .disabled(isMissing)

            Text(item.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isMissing || !item.isEnabled ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("File missing. Open Soundbind to relocate it.")
                    .accessibilityLabel("File missing")
            } else if let shortcut = model.shortcutText(for: .sound(item.id)) {
                ShortcutBadge(text: shortcut)
                    .opacity(item.isEnabled ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if !isMissing { model.togglePlayback(item.id) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Footer command styled like a menu item.
private struct MenuBarActionRow: View {
    let title: String
    let systemImage: String
    var trailing: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if isHovered && isEnabled {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .opacity(isEnabled ? 1 : 0.45)
    }
}
