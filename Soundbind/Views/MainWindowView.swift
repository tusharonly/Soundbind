import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model
        let isEmpty = model.library.items.isEmpty
        let spring = Motion.spring(reduceMotion: reduceMotion)

        VStack(spacing: 0) {
            NoticeStackView()

            ZStack {
                if isEmpty {
                    EmptyStateView().transition(.opacity)
                } else {
                    SoundListView().transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    ToastView(toast: toast)
                        .id(toast.id)
                        .transition(Motion.edgeTransition(.bottom, reduceMotion: reduceMotion))
                }
            }

            if model.showsFirstRunHint {
                FirstRunHintView()
                    .transition(Motion.edgeTransition(.bottom, reduceMotion: reduceMotion))
            }
        }
        .overlay {
            if isDropTargeted {
                DropOverlayView().transition(.opacity)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        // The whole window is a drop target. Unsupported files are reported inline.
        .dropDestination(for: URL.self) { urls, _ in
            model.importFiles(urls)
            return !urls.isEmpty
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isImporting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Importing sounds")
                }
                Button {
                    model.stopAll()
                } label: {
                    Label("Stop All Sounds", systemImage: "stop.fill")
                }
                .disabled(!model.audio.isAnythingPlaying)
                .help("Stop All Sounds")

                Button {
                    model.presentAddImporter()
                } label: {
                    Label("Add Sound", systemImage: "plus")
                }
                // Also on the menu command; kept here so ⌘O works without a visible menu bar.
                .keyboardShortcut("o", modifiers: .command)
                .help("Add Sound (⌘O)")
            }
        }
        .modifier(OptionalSearch(isEnabled: model.showsSearch, text: $model.searchText))
        .fileImporter(
            isPresented: $model.isImporterPresented,
            allowedContentTypes: SoundLibrary.supportedContentTypes,
            allowsMultipleSelection: model.importerMode == .add
        ) { result in
            model.handleImporterResult(result)
        }
        .animation(spring, value: isEmpty)
        .animation(spring, value: model.toast?.id)
        .animation(spring, value: model.showsFirstRunHint)
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .navigationTitle("Soundbind")
    }
}

/// Adds a toolbar search field only once the library is big enough to need one.
private struct OptionalSearch: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $text, placement: .toolbar, prompt: "Search sounds")
        } else {
            content
        }
    }
}
