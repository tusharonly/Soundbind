import Foundation

/// What happens when a sound is triggered while it is already playing.
enum RetriggerMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case restart
    case ignore
    case overlap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .restart: "Restart"
        case .ignore: "Ignore"
        case .overlap: "Overlap"
        }
    }

    var explanation: String {
        switch self {
        case .restart: "Pressing the shortcut again restarts the sound."
        case .ignore: "Pressing the shortcut again does nothing until the sound finishes."
        case .overlap: "Pressing the shortcut again layers another copy on top."
        }
    }
}

struct SoundItem: Identifiable, Codable, Equatable, Sendable {
    /// Sounds longer than this get a "long sound" warning on import.
    static let longDurationWarningThreshold: TimeInterval = 30
    /// Sounds longer than this are streamed from disk instead of preloaded.
    static let streamingThreshold: TimeInterval = 60

    let id: UUID
    var displayName: String
    /// File name (UUID-based) inside the library's `Sounds` directory.
    var fileName: String
    /// Linear gain, 0...1.
    var volume: Float
    var createdAt: Date
    var isEnabled: Bool
    var retriggerMode: RetriggerMode
    /// Cached at import so rows never need to open the file.
    var duration: TimeInterval
    /// Normalised peak values (0...1), generated once at import.
    var waveform: [Float]

    init(
        id: UUID = UUID(),
        displayName: String,
        fileName: String,
        volume: Float = 1,
        createdAt: Date = Date(),
        isEnabled: Bool = true,
        retriggerMode: RetriggerMode = .restart,
        duration: TimeInterval = 0,
        waveform: [Float] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.fileName = fileName
        self.volume = volume
        self.createdAt = createdAt
        self.isEnabled = isEnabled
        self.retriggerMode = retriggerMode
        self.duration = duration
        self.waveform = waveform
    }

    var isStreamed: Bool { duration > Self.streamingThreshold }
    var isLong: Bool { duration > Self.longDurationWarningThreshold }

    // Tolerant decoding: only `id` and `fileName` are required, so a library
    // written by an older or newer build still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fileName = try c.decode(String.self, forKey: .fileName)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? "Untitled"
        let rawVolume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? 1
        volume = min(max(rawVolume, 0), 1)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        retriggerMode = (try? c.decodeIfPresent(RetriggerMode.self, forKey: .retriggerMode)) ?? .restart
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        waveform = try c.decodeIfPresent([Float].self, forKey: .waveform) ?? []
    }
}

/// On-disk shape of the library file.
struct LibrarySnapshot: Codable {
    static let currentVersion = 1

    var version: Int = LibrarySnapshot.currentVersion
    var items: [SoundItem]
}

extension TimeInterval {
    /// "0:04", "1:23", or "0.4s" for very short clips.
    var soundDurationText: String {
        guard isFinite, self > 0 else { return "0:00" }
        if self < 1 { return String(format: "%.1fs", self) }
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var spokenSoundDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = self >= 60 ? [.minute, .second] : [.second]
        return formatter.string(from: max(self, 1)) ?? ""
    }
}
