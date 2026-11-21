import SwiftUI

struct EmptyStateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            // The app icon itself, so the in-app logo can never drift from it.
            // The artwork has a built-in margin; the negative padding lines its tile up with the text.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .padding(-7)
                .accessibilityHidden(true)
                .padding(.bottom, 28)

            VStack(alignment: .center, spacing: 2) {
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
                .multilineTextAlignment(.center)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
