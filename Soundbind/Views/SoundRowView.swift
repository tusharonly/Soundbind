import SwiftUI

struct SoundRowView: View {
    let item: SoundItem
    let isSelected: Bool
    /// Called when the row is clicked, so the list can take keyboard focus.
    let onActivate: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var flash = 0.0

    private var owner: HotkeyOwner { .sound(item.id) }

    var body: some View {
        let isMissing = model.library.isMissing(item.id)
        let isExpanded = model.isExpanded(item.id)
        let playback = model.audio.playback[item.id]

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PlayButton(soundName: item.displayName, playback: playback) {
                    model.togglePlayback(item.id)
                }
                .disabled(isMissing)

                VStack(alignment: .leading, spacing: 3) {
                    SoundNameField(item: item, onFinish: onActivate)
                    detailLine(isMissing: isMissing, playback: playback)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ShortcutRecorderView(owner: owner, accessibilityLabel: "Shortcut for \(item.displayName)") { shortcut in
                    model.shortcutRecorded(shortcut, for: owner)
                }
                .fixedSize()

                volumeDisclosureButton(isExpanded: isExpanded)
                overflowMenu(isMissing: isMissing)
            }

            if isExpanded {
                SoundRowControls(item: item)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            if let conflict = model.hotkeys.pendingConflicts[owner] {
                ShortcutConflictView(owner: owner, conflict: conflict)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(background)
        .contentShape(Theme.card())
        .opacity(item.isEnabled ? 1 : 0.6)
        .onHover { isHovered = $0 }
        .onTapGesture {
            model.select(item.id)
            onActivate()
        }
        .contextMenu { SoundMenuItems(item: item, isMissing: isMissing) }
        .onChange(of: model.flashTokens[item.id]) {
            // Global hotkey fired: flash, then fade back.
            flash = 1
            withAnimation(.easeOut(duration: 0.7)) { flash = 0 }
        }
        .animation(Motion.spring(reduceMotion: reduceMotion), value: isExpanded)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: model.hotkeys.pendingConflicts[owner])
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary(isMissing: isMissing))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Pieces

    @ViewBuilder
    private func detailLine(isMissing: Bool, playback: AudioEngineService.Playback?) -> some View {
        HStack(spacing: 7) {
            if isMissing {
                Label("File missing", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize()
                Button("Relocate…") { model.presentRelocateImporter(for: item.id) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .fixedSize()
                    .help("Choose the audio file for this sound again")
            } else {
                WaveformThumbnail(samples: item.waveform, playback: playback)
                    .frame(width: 80, height: 16)
                Text(item.duration.soundDurationText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryInk)
                    .accessibilityLabel("Duration \(item.duration.spokenSoundDuration)")
                if item.isStreamed {
                    Image(systemName: "externaldrive")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("Long sound: streamed from disk rather than preloaded")
                        .accessibilityLabel("Streamed from disk")
                }
            }
            if !item.isEnabled {
                Text("Off")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.surfaceStrong, in: Capsule())
                    .help("Shortcut disabled")
                    .accessibilityLabel("Shortcut disabled")
            }
        }
        .lineLimit(1)
    }

    private func volumeDisclosureButton(isExpanded: Bool) -> some View {
        Button {
            model.toggleExpanded(item.id)
        } label: {
            Image(systemName: volumeSymbol)
                .symbolVariant(isExpanded ? .fill : .none)
                .foregroundStyle(isExpanded ? AnyShapeStyle(.tint) : AnyShapeStyle(Theme.secondaryInk))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide volume and retrigger options" : "Volume and retrigger options")
        .accessibilityLabel("Volume and options for \(item.displayName)")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    private func overflowMenu(isMissing: Bool) -> some View {
        Menu {
            SoundMenuItems(item: item, isMissing: isMissing)
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(Theme.secondaryInk)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions for \(item.displayName)")
    }

    private var volumeSymbol: String {
        switch item.volume {
        case 0: "speaker.slash"
        case ..<0.34: "speaker.wave.1"
        case ..<0.67: "speaker.wave.2"
        default: "speaker.wave.3"
        }
    }

    private var background: some View {
        let shape = Theme.card()
        return ZStack {
            if isSelected {
                shape.fill(Theme.highlight.opacity(0.32))
                shape.strokeBorder(Theme.highlight, lineWidth: 1.5)
            } else {
                shape.fill(isHovered ? Theme.surfaceHover : Theme.surface)
            }
            shape.fill(Theme.highlight.opacity(0.85 * flash))
        }
    }

    private func accessibilitySummary(isMissing: Bool) -> String {
        var parts = [item.displayName]
        if isMissing { parts.append("file missing") }
        if let shortcut = model.shortcutText(for: owner) {
            parts.append("shortcut \(shortcut)")
        } else {
            parts.append("no shortcut")
        }
        if model.audio.isPlaying(item.id) { parts.append("playing") }
        return parts.joined(separator: ", ")
    }
}

/// Inline-editable sound name. Double-click (or Return on the selected row) to edit.
struct SoundNameField: View {
    let item: SoundItem
    let onFinish: () -> Void

    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if model.editingID == item.id {
            TextField("Sound name", text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.rowTitle)
                .focused($isFocused)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.tint, lineWidth: 1.5)
                }
                .padding(.leading, -5)
                .onAppear {
                    draft = item.displayName
                    // Focus on the next runloop turn, once the field is in the window.
                    DispatchQueue.main.async { isFocused = true }
                }
                .onSubmit {
                    model.commitRename(item.id, to: draft)
                    onFinish()
                }
                .onExitCommand {
                    model.cancelRename(item.id)
                    onFinish()
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { model.commitRename(item.id, to: draft) }
                }
                .accessibilityLabel("Name")
        } else {
            Text(item.displayName)
                .font(Theme.rowTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.vertical, 2)
                .onTapGesture(count: 2) { model.beginRenaming(item.id) }
                .help("Double-click to rename")
        }
    }
}

/// Disclosure area: per-sound volume and retrigger behaviour.
struct SoundRowControls: View {
    let item: SoundItem
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { Double(item.volume) },
                    set: { model.setVolume(Float($0), for: item.id) }
                ),
                in: 0...1
            )
            .controlSize(.small)
            .frame(minWidth: 90, maxWidth: 170)
            .accessibilityLabel("Volume")
            .accessibilityValue("\(Int((item.volume * 100).rounded())) percent")
            Text("\(Int((item.volume * 100).rounded()))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
                .accessibilityHidden(true)

            Spacer(minLength: 8)

            Picker(
                "When retriggered",
                selection: Binding(
                    get: { item.retriggerMode },
                    set: { model.setRetriggerMode($0, for: item.id) }
                )
            ) {
                ForEach(RetriggerMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help(item.retriggerMode.explanation)
        }
        .padding(.leading, 42)
        .padding(.top, 2)
    }
}

/// Shared by the overflow menu and the context menu.
struct SoundMenuItems: View {
    let item: SoundItem
    let isMissing: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Button("Rename") { model.beginRenaming(item.id) }
        Button("Reveal in Finder") { model.revealInFinder(item.id) }
            .disabled(isMissing)
        Button("Duplicate") { model.duplicate(item.id) }
            .disabled(isMissing)
        if isMissing {
            Button("Relocate…") { model.presentRelocateImporter(for: item.id) }
        }

        Divider()

        Picker(
            "When Retriggered",
            selection: Binding(
                get: { item.retriggerMode },
                set: { model.setRetriggerMode($0, for: item.id) }
            )
        ) {
            ForEach(RetriggerMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        Toggle(
            "Shortcut Enabled",
            isOn: Binding(
                get: { item.isEnabled },
                set: { model.setEnabled($0, for: item.id) }
            )
        )
        if model.hotkeys.shortcuts[.sound(item.id)] != nil {
            Button("Clear Shortcut") { model.hotkeys.clearShortcut(for: .sound(item.id)) }
        }

        Divider()

        Button("Delete", role: .destructive) {
            model.delete(item.id, undoManager: undoManager)
        }
    }
}
