import AVFoundation
import Observation
import OSLog

/// Plays sounds through one long-lived `AVAudioEngine`.
///
/// Short sounds are decoded once into memory in a single canonical format and played on a
/// pool of pre-connected player nodes, so triggering one is just "schedule buffer + play".
/// Sounds over `SoundItem.streamingThreshold` are streamed from disk on a dedicated node.
@MainActor
@Observable
final class AudioEngineService {
    struct Playback: Equatable {
        let startedAt: Date
        let duration: TimeInterval

        func progress(at date: Date) -> Double {
            guard duration > 0 else { return 0 }
            return min(max(date.timeIntervalSince(startedAt) / duration, 0), 1)
        }
    }

    /// Sounds that are currently audible, keyed by sound id. Drives play buttons and progress rings.
    private(set) var playback: [UUID: Playback] = [:]
    private(set) var masterVolume: Float = 1
    private(set) var keepsEngineWarm = false

    static let maxPooledVoices = 24
    private static let initialPoolSize = 8
    private static let idleTimeout: Duration = .seconds(30)

    private final class Voice {
        let token = UUID()
        let soundID: UUID
        let node: AVAudioPlayerNode
        let isPooled: Bool

        init(soundID: UUID, node: AVAudioPlayerNode, isPooled: Bool) {
            self.soundID = soundID
            self.node = node
            self.isPooled = isPooled
        }
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    @ObservationIgnored private var buffers: [UUID: AVAudioPCMBuffer] = [:]
    @ObservationIgnored private var urls: [UUID: URL] = [:]
    @ObservationIgnored private var idleNodes: [AVAudioPlayerNode] = []
    @ObservationIgnored private var pooledNodeCount = 0
    @ObservationIgnored private var voices: [Voice] = []
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var configurationObserver: NSObjectProtocol?
    @ObservationIgnored private let log = Logger(subsystem: "Soundbind", category: "Audio")

    init() {
        for _ in 0..<Self.initialPoolSize {
            if let node = makePooledNode() { idleNodes.append(node) }
        }
        engine.mainMixerNode.outputVolume = masterVolume
        engine.prepare()

        // Posted when the output device changes (headphones unplugged, sample rate switched…).
        // The engine has already stopped itself by the time this arrives.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
    }

    // MARK: - Loading

    /// Makes a sound playable. Short sounds are decoded into memory off the main thread.
    func preload(_ item: SoundItem, url: URL) async {
        urls[item.id] = url
        guard !item.isStreamed else {
            buffers[item.id] = nil
            return
        }
        let format = self.format
        let loaded = await Task.detached(priority: .userInitiated) {
            UncheckedSendable(value: try? AudioBufferLoader.load(url: url, format: format))
        }.value
        // The sound may have been deleted while decoding.
        guard urls[item.id] == url else { return }
        if let buffer = loaded.value {
            buffers[item.id] = buffer
        } else {
            log.error("Preload failed for \(url.lastPathComponent, privacy: .public); will stream instead")
        }
    }

    func unload(_ id: UUID) {
        stop(id)
        buffers[id] = nil
        urls[id] = nil
    }

    func isLoaded(_ id: UUID) -> Bool { urls[id] != nil }
    func isPreloaded(_ id: UUID) -> Bool { buffers[id] != nil }

    // MARK: - Playback

    func isPlaying(_ id: UUID) -> Bool { playback[id] != nil }
    var isAnythingPlaying: Bool { !playback.isEmpty }

    /// Plays a sound, honouring its retrigger mode. Returns whether a new voice started.
    @discardableResult
    func play(_ item: SoundItem) -> Bool {
        switch item.retriggerMode {
        case .ignore:
            if isPlaying(item.id) { return false }
        case .restart:
            stop(item.id)
        case .overlap:
            break
        }

        guard ensureRunning() else { return false }

        let started: Bool
        if let buffer = buffers[item.id] {
            started = startBuffered(item, buffer: buffer)
        } else if let url = urls[item.id] {
            started = startStreamed(item, url: url)
        } else {
            started = false
        }
        if started {
            playback[item.id] = Playback(startedAt: Date(), duration: item.duration)
        } else {
            scheduleIdlePauseIfNeeded()
        }
        return started
    }

    func stop(_ id: UUID) {
        let stopping = voices.filter { $0.soundID == id }
        guard !stopping.isEmpty || playback[id] != nil else { return }
        voices.removeAll { $0.soundID == id }
        stopping.forEach(retire)
        playback[id] = nil
        scheduleIdlePauseIfNeeded()
    }

    func stopAll() {
        let stopping = voices
        voices.removeAll()
        stopping.forEach(retire)
        playback.removeAll()
        scheduleIdlePauseIfNeeded()
    }

    /// Applies a volume change to a sound that is already playing.
    func setVolume(_ volume: Float, for id: UUID) {
        for voice in voices where voice.soundID == id {
            voice.node.volume = volume
        }
    }

    func setMasterVolume(_ volume: Float) {
        masterVolume = min(max(volume, 0), 1)
        engine.mainMixerNode.outputVolume = masterVolume
    }

    /// When on, the engine keeps running between sounds: lowest latency, at the cost of
    /// holding the output device open (which also keeps the Mac from idle-sleeping).
    func setKeepsEngineWarm(_ keepWarm: Bool) {
        keepsEngineWarm = keepWarm
        if keepWarm {
            ensureRunning()
        } else {
            scheduleIdlePauseIfNeeded()
        }
    }

    // MARK: - Voices

    private func startBuffered(_ item: SoundItem, buffer: AVAudioPCMBuffer) -> Bool {
        guard let node = dequeuePooledNode() else { return false }
        node.volume = item.volume
        let voice = Voice(soundID: item.id, node: node, isPooled: true)
        let token = voice.token
        node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.voiceFinished(token) }
        }
        guard start(node) else {
            node.stop()
            idleNodes.append(node)
            return false
        }
        voices.append(voice)
        return true
    }

    private func startStreamed(_ item: SoundItem, url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        let node = AVAudioPlayerNode()
        let connected = guarded("connect stream node") {
            self.engine.attach(node)
            self.engine.connect(node, to: self.engine.mainMixerNode, format: file.processingFormat)
        }
        guard connected else {
            engine.detach(node)
            return false
        }
        node.volume = item.volume
        let voice = Voice(soundID: item.id, node: node, isPooled: false)
        let token = voice.token
        node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.voiceFinished(token) }
        }
        guard ensureRunning(), start(node) else {
            node.stop()
            engine.detach(node)
            return false
        }
        voices.append(voice)
        return true
    }

    /// Called (on the main actor) when a voice played to its end. Stopped voices were
    /// already removed from `voices`, so their late callbacks are ignored here.
    private func voiceFinished(_ token: UUID) {
        guard let index = voices.firstIndex(where: { $0.token == token }) else { return }
        let voice = voices.remove(at: index)
        retire(voice)
        if !voices.contains(where: { $0.soundID == voice.soundID }) {
            playback[voice.soundID] = nil
        }
        scheduleIdlePauseIfNeeded()
    }

    private func retire(_ voice: Voice) {
        voice.node.stop()
        if voice.isPooled {
            idleNodes.append(voice.node)
        } else {
            engine.detach(voice.node)
        }
    }

    private func dequeuePooledNode() -> AVAudioPlayerNode? {
        if let node = idleNodes.popLast() { return node }
        if pooledNodeCount < Self.maxPooledVoices, let node = makePooledNode() { return node }
        // Pool exhausted: steal the oldest pooled voice.
        guard let index = voices.firstIndex(where: \.isPooled) else { return nil }
        let victim = voices.remove(at: index)
        victim.node.stop()
        if !voices.contains(where: { $0.soundID == victim.soundID }) {
            playback[victim.soundID] = nil
        }
        return victim.node
    }

    private func makePooledNode() -> AVAudioPlayerNode? {
        let node = AVAudioPlayerNode()
        let connected = guarded("connect pooled node") {
            self.engine.attach(node)
            self.engine.connect(node, to: self.engine.mainMixerNode, format: self.format)
        }
        guard connected else { return nil }
        pooledNodeCount += 1
        return node
    }

    // MARK: - Engine lifecycle

    @discardableResult
    private func ensureRunning() -> Bool {
        idleTask?.cancel()
        idleTask = nil
        if engine.isRunning { return true }

        // With no output device the engine raises instead of throwing; don't even try.
        let output = engine.outputNode.outputFormat(forBus: 0)
        guard output.channelCount > 0, output.sampleRate > 0 else {
            log.error("No usable audio output device")
            return false
        }
        var startError: Error?
        let ok = guarded("start engine") {
            do { try self.engine.start() } catch { startError = error }
        }
        if let startError {
            log.error("Engine failed to start: \(startError.localizedDescription, privacy: .public)")
        }
        return ok && startError == nil && engine.isRunning
    }

    private func start(_ node: AVAudioPlayerNode) -> Bool {
        // `play()` raises if the engine stopped between the check above and now (route change).
        guard engine.isRunning else { return false }
        return guarded("start player") { node.play() }
    }

    private func handleConfigurationChange() {
        log.info("Audio configuration changed; resetting voices")
        // Everything that was scheduled is gone. Recycle voices and restart lazily
        // (or immediately when the engine is meant to stay warm).
        let interrupted = voices
        voices.removeAll()
        interrupted.forEach(retire)
        playback.removeAll()
        engine.mainMixerNode.outputVolume = masterVolume
        if keepsEngineWarm { ensureRunning() }
    }

    private func scheduleIdlePauseIfNeeded() {
        idleTask?.cancel()
        idleTask = nil
        guard voices.isEmpty, !keepsEngineWarm, engine.isRunning else { return }
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard !Task.isCancelled, let self, self.voices.isEmpty, !self.keepsEngineWarm else { return }
            self.engine.pause()
        }
    }

    /// Runs AVAudioEngine calls that may raise Objective-C exceptions.
    @discardableResult
    private func guarded(_ what: String, _ block: () -> Void) -> Bool {
        do {
            try ObjCExceptionCatcher.perform(block)
            return true
        } catch {
            log.error("Audio engine raised during \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}
