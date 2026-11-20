import XCTest
@testable import Soundbind

/// Exercises the real `AVAudioEngine` with the master volume at zero.
/// Skipped on machines without an audio output device (e.g. some CI runners).
@MainActor
final class AudioEngineServiceTests: XCTestCase {
    private var audio: AudioEngineService!
    private var directory: URL!

    override func setUp() async throws {
        audio = AudioEngineService()
        try XCTSkipUnless(audio.hasOutputDevice, "No audio output device available")
        audio.setMasterVolume(0)
        directory = try makeTemporaryDirectory()
    }

    override func tearDown() async throws {
        audio?.stopAll()
        audio = nil
    }

    private func makeSound(seconds: Double, mode: RetriggerMode = .restart) async throws -> SoundItem {
        let id = UUID()
        let url = try TestAudio.writeTone(to: directory, name: "\(id.uuidString).wav", seconds: seconds)
        let item = SoundItem(id: id, displayName: "Tone", fileName: url.lastPathComponent, retriggerMode: mode, duration: seconds)
        await audio.preload(item, url: url)
        return item
    }

    private func waitUntil(timeout: Double = 4, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testShortSoundIsPreloadedPlaysAndFinishesOnItsOwn() async throws {
        let item = try await makeSound(seconds: 0.2)
        XCTAssertTrue(audio.isPreloaded(item.id))

        XCTAssertTrue(audio.play(item))
        XCTAssertTrue(audio.isPlaying(item.id))
        XCTAssertEqual(audio.playback[item.id]?.duration, 0.2)

        try await waitUntil { !self.audio.isPlaying(item.id) }
        XCTAssertFalse(audio.isPlaying(item.id), "Playback state clears when the sound ends")
        XCTAssertEqual(audio.voiceCount(for: item.id), 0)
    }

    func testRestartModeReplacesTheRunningVoice() async throws {
        let item = try await makeSound(seconds: 2, mode: .restart)
        audio.play(item)
        let firstStart = try XCTUnwrap(audio.playback[item.id]?.startedAt)
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertTrue(audio.play(item))

        XCTAssertEqual(audio.voiceCount(for: item.id), 1)
        XCTAssertGreaterThan(try XCTUnwrap(audio.playback[item.id]?.startedAt), firstStart)
        // The stopped voice's late completion callback must not clear the new one.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(audio.isPlaying(item.id))
    }

    func testIgnoreModeLeavesTheRunningVoiceAlone() async throws {
        let item = try await makeSound(seconds: 2, mode: .ignore)
        audio.play(item)
        let firstStart = audio.playback[item.id]?.startedAt

        XCTAssertFalse(audio.play(item))

        XCTAssertEqual(audio.voiceCount(for: item.id), 1)
        XCTAssertEqual(audio.playback[item.id]?.startedAt, firstStart)
    }

    func testOverlapModeLayersVoices() async throws {
        let item = try await makeSound(seconds: 2, mode: .overlap)

        audio.play(item)
        audio.play(item)
        audio.play(item)

        XCTAssertEqual(audio.voiceCount(for: item.id), 3)
        audio.stop(item.id)
        XCTAssertEqual(audio.voiceCount(for: item.id), 0)
        XCTAssertFalse(audio.isPlaying(item.id))
    }

    func testManyOverlappingTriggersNeverExceedThePool() async throws {
        let item = try await makeSound(seconds: 2, mode: .overlap)

        for _ in 0..<(AudioEngineService.maxPooledVoices + 10) { audio.play(item) }

        XCTAssertEqual(audio.voiceCount(for: item.id), AudioEngineService.maxPooledVoices)
        XCTAssertTrue(audio.isPlaying(item.id))
    }

    func testStopAllSilencesEverything() async throws {
        let a = try await makeSound(seconds: 2)
        let b = try await makeSound(seconds: 2)
        audio.play(a)
        audio.play(b)
        XCTAssertTrue(audio.isAnythingPlaying)

        audio.stopAll()

        XCTAssertFalse(audio.isAnythingPlaying)
        XCTAssertTrue(audio.play(a), "Nodes are reusable after stopAll")
    }

    func testSoundOverAMinuteIsStreamedNotPreloaded() async throws {
        let item = try await makeSound(seconds: 61)
        XCTAssertTrue(item.isStreamed)
        XCTAssertFalse(audio.isPreloaded(item.id))
        XCTAssertTrue(audio.isLoaded(item.id))

        XCTAssertTrue(audio.play(item))
        XCTAssertTrue(audio.isPlaying(item.id))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(audio.isPlaying(item.id))

        audio.stop(item.id)
        XCTAssertFalse(audio.isPlaying(item.id))
    }

    func testUnloadedSoundDoesNotPlay() async throws {
        let item = try await makeSound(seconds: 0.5)
        audio.unload(item.id)

        XCTAssertFalse(audio.play(item))
        XCTAssertFalse(audio.isPlaying(item.id))
    }
}
