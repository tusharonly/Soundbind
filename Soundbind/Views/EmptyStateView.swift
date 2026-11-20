import SwiftUI

struct EmptyStateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Keycap tile, echoing the app icon.
            Image(systemName: "waveform")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.onInk)
                .frame(width: 56, height: 56)
                .background(Theme.ink, in: Theme.card(16))
                .accessibilityHidden(true)
                .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Drop in a ")
                    MarkedText(text: "sound")
                    Text(".")
                }
                Text("Bind a key. Done.")
            }
            .font(.system(size: 40, weight: .bold))
            .tracking(-1.1)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Drop in a sound. Bind a key. Done.")
            .accessibilityAddTraits(.isHeader)

            Text("Play any audio file from anywhere with a global shortcut.")
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            HStack(spacing: 18) {
                Button {
                    model.presentAddImporter()
                } label: {
                    Label("Add Sound", systemImage: "plus")
                }
                .buttonStyle(InkButtonStyle())
                .keyboardShortcut(.defaultAction)

                VStack(alignment: .leading, spacing: 1) {
                    Text("or drag files in")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Theme.secondaryInk)
                    Text("MP3, WAV, M4A, AAC, AIFF, CAF")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.tertiaryInk)
                }
            }
            .padding(.top, 34)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
