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

    private static let rowHeight: CGFloat = 38
    private static let maxListHeight: CGFloat = 320

    var body: some View {
        let items = model.library.items

        VStack(spacing: 0) {
            header
            rule

            VStack(spacing: 8) {
                SectionLabel(title: "Sounds")
                    .padding(.horizontal, 10)
                if items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(items) { item in
                                MenuBarSoundRow(item: item)
                                    .frame(height: Self.rowHeight)
                            }
                        }
                    }
                    .frame(height: min(CGFloat(items.count) * (Self.rowHeight + 2), Self.maxListHeight))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)

            rule

            VStack(spacing: 1) {
                MenuBarActionRow(title: "Open Soundbind…") {
                    openMainWindow()
                }
                MenuBarActionRow(title: "Stop All Sounds", trailing: model.shortcutText(for: .stopAll)) {
                    model.stopAll()
                }
                .disabled(!model.audio.isAnythingPlaying)
                MenuBarActionRow(title: "Soundbind Settings…", trailing: "⌘,") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
                MenuBarActionRow(title: "Quit Soundbind", trailing: "⌘Q") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(8)
        }
        .frame(width: 310)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .background(Theme.background.opacity(0.72))
    }

    private var rule: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .padding(.horizontal, 18)
    }

    /// Title plus master volume, always one click away.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Soundbind")
                .font(.title3.weight(.bold))
                .tracking(-0.3)
            VStack(spacing: 6) {
                SectionLabel(title: "Volume")
                Slider(
                    value: Binding(
                        get: { Double(model.settings.masterVolume) },
                        set: { model.setMasterVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .accessibilityLabel("Master volume")
                .accessibilityValue("\(Int((model.settings.masterVolume * 100).rounded())) percent")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var emptyState: some View {
        Text("No sounds yet. Open Soundbind to add your first one.")
            .font(.callout.weight(.medium))
            .foregroundStyle(Theme.tertiaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
            Text(item.displayName)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isMissing || !item.isEnabled ? Theme.tertiaryInk : Theme.ink)
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

            PlayButton(soundName: item.displayName, playback: model.audio.playback[item.id], diameter: 24) {
                model.togglePlayback(item.id)
            }
            .disabled(isMissing)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background {
            if isHovered {
                Theme.card(10).fill(Theme.surfaceHover)
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
    var trailing: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.tertiaryInk)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if isHovered && isEnabled {
                    Theme.card(10).fill(Theme.surfaceHover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .opacity(isEnabled ? 1 : 0.4)
    }
}
