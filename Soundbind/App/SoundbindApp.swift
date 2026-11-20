import SwiftUI

@main
struct SoundbindApp: App {
    var body: some Scene {
        Window("Soundbind", id: "main") {
            Text("Soundbind")
                .frame(minWidth: 440, minHeight: 360)
        }
        MenuBarExtra("Soundbind", systemImage: "waveform") {
            Text("Soundbind")
        }
    }
}
