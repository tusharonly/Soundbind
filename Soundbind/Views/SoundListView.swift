import SwiftUI

/// Scrollable list of sound rows with selection and keyboard navigation.
struct SoundListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isListFocused: Bool

    var body: some View {
        let items = model.visibleItems

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(items) { item in
                        SoundRowView(item: item, isSelected: model.selection == item.id) {
                            isListFocused = true
                        }
                        .id(item.id)
                        .transition(Motion.rowTransition(reduceMotion: reduceMotion))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .animation(Motion.spring(reduceMotion: reduceMotion), value: items.map(\.id))
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                model.select(nil)
                isListFocused = true
            }
            .focusable()
            .focusEffectDisabled()
            .focused($isListFocused)
            .onKeyPress(.upArrow) { handled { model.moveSelection(by: -1) } }
            .onKeyPress(.downArrow) { handled { model.moveSelection(by: 1) } }
            .onKeyPress(.space) {
                guard model.selection != nil else { return .ignored }
                model.toggleSelectionPlayback()
                return .handled
            }
            .onKeyPress(.return) {
                guard let id = model.selection else { return .ignored }
                model.beginRenaming(id)
                return .handled
            }
            .onKeyPress(.escape) {
                guard model.selection != nil else { return .ignored }
                model.select(nil)
                return .handled
            }
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                guard model.selection != nil else { return .ignored }
                model.deleteSelection(undoManager: undoManager)
                return .handled
            }
            .onDeleteCommand { model.deleteSelection(undoManager: undoManager) }
            .onChange(of: model.selection) { _, selection in
                guard let selection else { return }
                withAnimation(Motion.spring(reduceMotion: reduceMotion)) {
                    proxy.scrollTo(selection)
                }
            }
            .onAppear { isListFocused = true }
            .accessibilityLabel("Sounds")
        }
    }

    private func handled(_ action: () -> Void) -> KeyPress.Result {
        action()
        return .handled
    }
}
