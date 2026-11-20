import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { model.launchAtLogin.isEnabled },
                        set: { model.launchAtLogin.setEnabled($0) }
                    )
                )
                if model.launchAtLogin.requiresApproval {
                    HStack {
                        Text("Approve Soundbind under Login Items to finish turning this on.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") { model.launchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = model.launchAtLogin.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Toggle(
                    "Show Dock icon",
                    isOn: Binding(
                        get: { model.settings.showDockIcon },
                        set: { model.setShowDockIcon($0) }
                    )
                )
            }

            Section("Playback") {
                LabeledContent("Master volume") {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Slider(
                            value: Binding(
                                get: { Double(model.settings.masterVolume) },
                                set: { model.setMasterVolume(Float($0)) }
                            ),
                            in: 0...1
                        )
                        .frame(width: 180)
                        .accessibilityLabel("Master volume")
                        .accessibilityValue("\(Int((model.settings.masterVolume * 100).rounded())) percent")
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }

                Toggle(
                    isOn: Binding(
                        get: { model.settings.keepsEngineWarm },
                        set: { model.setKeepsEngineWarm($0) }
                    )
                ) {
                    Text("Keep audio engine running")
                    Text("Lowest possible latency. Keeps the output device active, which can stop your Mac from sleeping when idle.")
                }
            }

            Section("Shortcuts") {
                LabeledContent("Stop All Sounds") {
                    ShortcutRecorderView(
                        owner: .stopAll,
                        placeholder: "Record Shortcut",
                        accessibilityLabel: "Stop All Sounds shortcut"
                    ) { shortcut in
                        model.shortcutRecorded(shortcut, for: .stopAll)
                    }
                    .fixedSize()
                }
                if let conflict = model.hotkeys.pendingConflicts[.stopAll] {
                    ShortcutConflictView(owner: .stopAll, conflict: conflict)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .soundbindThemed()
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.launchAtLogin.refresh() }
    }
}
