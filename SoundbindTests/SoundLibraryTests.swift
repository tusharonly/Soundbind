import AVFoundation
import XCTest
@testable import Soundbind

@MainActor
final class SoundLibraryTests: XCTestCase {
    private var root: URL!
    private var sources: URL!

    override func setUp() async throws {
        root = try makeTemporaryDirectory()
        sources = try makeTemporaryDirectory()
    }

    private func makeLibrary(debounce: Duration = .seconds(60)) -> SoundLibrary {
        let library = SoundLibrary(rootURL: root, saveDebounce: debounce)
        library.load()
        return library
    }

    // MARK: Import

    func testImportCopiesFileUnderUUIDNameAndCreatesItem() async throws {
        let library = makeLibrary()
        let source = try TestAudio.writeTone(to: sources, name: "Air Horn.wav", seconds: 0.25)

        let item = try await library.importFile(at: source)

        XCTAssertEqual(library.items, [item])
        XCTAssertEqual(item.displayName, "Air Horn")
        XCTAssertEqual(item.fileName, "\(item.id.uuidString).wav")
        XCTAssertEqual(item.volume, 1)
        XCTAssertTrue(item.isEnabled)
        XCTAssertEqual(item.retriggerMode, .restart)
        XCTAssertEqual(item.duration, 0.25, accuracy: 0.02)
        XCTAssertEqual(item.waveform.count, AudioAnalyzer.waveformBucketCount)
        XCTAssertEqual(item.waveform.max() ?? 0, 1, accuracy: 0.001)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.fileURL(for: item).path))
        XCTAssertEqual(library.fileURL(for: item).deletingLastPathComponent().lastPathComponent, "Sounds")
    }

    func testImportedSoundSurvivesOriginalBeingDeleted() async throws {
        let library = makeLibrary()
        let source = try TestAudio.writeTone(to: sources)
        let item = try await library.importFile(at: source)

        try FileManager.default.removeItem(at: source)
        library.refreshMissingFiles()

        XCTAssertTrue(FileManager.default.fileExists(atPath: library.fileURL(for: item).path))
        XCTAssertFalse(library.isMissing(item.id))
    }

    func testImportRejectsUnsupportedExtension() async throws {
        let library = makeLibrary()
        let source = sources.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: source)

        do {
            try await library.importFile(at: source)
            XCTFail("Expected unsupportedType")
        } catch let error as SoundImportError {
            XCTAssertEqual(error, .unsupportedType(fileName: "notes.txt"))
        }
        XCTAssertTrue(library.items.isEmpty)
        XCTAssertTrue(contents(of: library.soundsURL).isEmpty)
    }

    func testImportOfCorruptAudioFailsAndCleansUpCopiedFile() async throws {
        let library = makeLibrary()
        let source = sources.appendingPathComponent("broken.wav")
        try Data((0..<4096).map { _ in UInt8.random(in: 0...255) }).write(to: source)

        do {
            try await library.importFile(at: source)
            XCTFail("Expected unreadable")
        } catch let error as SoundImportError {
            XCTAssertEqual(error, .unreadable(fileName: "broken.wav"))
        }
        XCTAssertTrue(library.items.isEmpty)
        XCTAssertTrue(contents(of: library.soundsURL).isEmpty, "The copied file must be removed again")
    }

    func testImportOfMissingSourceReportsCopyFailure() async throws {
        let library = makeLibrary()
        let source = sources.appendingPathComponent("ghost.mp3")

        do {
            try await library.importFile(at: source)
            XCTFail("Expected copyFailed")
        } catch let error as SoundImportError {
            XCTAssertEqual(error, .copyFailed(fileName: "ghost.mp3"))
        }
        XCTAssertTrue(library.items.isEmpty)
    }

    func testImportFilesReportsSuccessesAndFailuresTogether() async throws {
        let library = makeLibrary()
        let good = try TestAudio.writeTone(to: sources, name: "good.wav")
        let alsoGood = try TestAudio.writeTone(to: sources, name: "also.caf")
        let bad = sources.appendingPathComponent("movie.mov")
        try Data("x".utf8).write(to: bad)

        let report = await library.importFiles([good, bad, alsoGood])

        XCTAssertEqual(report.added.map(\.displayName), ["good", "also"])
        XCTAssertEqual(report.failures, [.unsupportedType(fileName: "movie.mov")])
        XCTAssertEqual(library.items.count, 2)
        XCTAssertEqual(contents(of: library.soundsURL).count, 2)
    }

    // MARK: Delete

    func testDeleteRemovesItemAndTakesFileOutOfSounds() async throws {
        let library = makeLibrary()
        let first = try await library.importFile(at: TestAudio.writeTone(to: sources, name: "a.wav"))
        let second = try await library.importFile(at: TestAudio.writeTone(to: sources, name: "b.wav"))

        let removed = library.remove(id: first.id)

        XCTAssertEqual(removed, RemovedSound(item: first, index: 0))
        XCTAssertEqual(library.items, [second])
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.fileURL(for: first).path))
        XCTAssertEqual(contents(of: library.soundsURL), [second.fileName])
        XCTAssertNil(library.remove(id: first.id), "Deleting twice is a no-op")
    }

    func testRestoreUndoesDeleteAtOriginalPosition() async throws {
        let library = makeLibrary()
        let first = try await library.importFile(at: TestAudio.writeTone(to: sources, name: "a.wav"))
        let second = try await library.importFile(at: TestAudio.writeTone(to: sources, name: "b.wav"))
        let removed = try XCTUnwrap(library.remove(id: first.id))

        library.restore(removed)
        library.restore(removed) // idempotent

        XCTAssertEqual(library.items, [first, second])
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.fileURL(for: first).path))
        XCTAssertFalse(library.isMissing(first.id))
    }

    func testDeletedFilesArePurgedOnNextLoad() async throws {
        let library = makeLibrary()
        let item = try await library.importFile(at: TestAudio.writeTone(to: sources))
        library.remove(id: item.id)
        XCTAssertEqual(contents(of: library.trashURL), [item.fileName])
        library.saveNow()

        let reloaded = makeLibrary()

        XCTAssertTrue(reloaded.items.isEmpty)
        XCTAssertTrue(contents(of: reloaded.trashURL).isEmpty)
    }

    // MARK: Persistence

    func testPersistenceRoundTrip() async throws {
        let library = makeLibrary()
        let a = try await library.importFile(at: TestAudio.writeTone(to: sources, name: "a.wav"))
        let b = try await library.importFile(at: TestAudio.writeTone(to: sources, name: "b.wav"))
        library.update(a.id) {
            $0.displayName = "Renamed"
            $0.volume = 0.4
            $0.retriggerMode = .overlap
            $0.isEnabled = false
        }
        XCTAssertTrue(library.saveNow())

        let reloaded = makeLibrary()

        XCTAssertNil(reloaded.loadIssue)
        XCTAssertEqual(reloaded.items.map(\.id), [a.id, b.id])
        let restored = try XCTUnwrap(reloaded.item(a.id))
        XCTAssertEqual(restored.displayName, "Renamed")
        XCTAssertEqual(restored.volume, 0.4, accuracy: 0.0001)
        XCTAssertEqual(restored.retriggerMode, .overlap)
        XCTAssertFalse(restored.isEnabled)
        XCTAssertEqual(restored.fileName, a.fileName)
        XCTAssertEqual(restored.duration, a.duration, accuracy: 0.0001)
        XCTAssertEqual(restored.waveform, a.waveform)
        XCTAssertEqual(
            restored.createdAt.timeIntervalSince1970, a.createdAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertTrue(reloaded.missingFileIDs.isEmpty)
    }

    func testEditsAreSavedAfterDebounce() async throws {
        let library = makeLibrary(debounce: .milliseconds(40))
        let item = try await library.importFile(at: TestAudio.writeTone(to: sources))
        for step in 1...5 { library.update(item.id) { $0.volume = Float(step) / 10 } }
        XCTAssertTrue(library.hasPendingSave)

        try await Task.sleep(for: .milliseconds(400))

        XCTAssertFalse(library.hasPendingSave)
        let reloaded = makeLibrary()
        XCTAssertEqual(try XCTUnwrap(reloaded.item(item.id)).volume, 0.5, accuracy: 0.0001)
    }

    func testMissingStoreFileStartsEmptyWithoutIssue() {
        let library = makeLibrary()

        XCTAssertTrue(library.items.isEmpty)
        XCTAssertNil(library.loadIssue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.storeURL.path))
    }

    func testCorruptJSONStartsEmptyAndKeepsBackup() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let garbage = Data("{ this is not json ]".utf8)
        try garbage.write(to: root.appendingPathComponent("library.json"))

        let library = makeLibrary()

        XCTAssertTrue(library.items.isEmpty)
        XCTAssertNotNil(library.loadIssue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.storeURL.path))
        let backups = contents(of: root).filter { $0.hasPrefix("library.corrupt-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(backups[0])), garbage)

        // The library stays usable and can save over the bad state.
        XCTAssertTrue(library.saveNow())
        XCTAssertNil(makeLibrary().loadIssue)
    }

    func testValidJSONWithWrongShapeIsTreatedAsCorrupt() throws {
        try Data(#"{"items": "nope"}"#.utf8).write(to: root.appendingPathComponent("library.json"))

        let library = makeLibrary()

        XCTAssertTrue(library.items.isEmpty)
        XCTAssertNotNil(library.loadIssue)
    }

    func testItemsWithOnlyRequiredFieldsDecodeWithDefaults() throws {
        let id = UUID()
        let json = #"{"version":1,"items":[{"id":"\#(id.uuidString)","fileName":"x.wav","volume":7}]}"#
        try Data(json.utf8).write(to: root.appendingPathComponent("library.json"))

        let library = makeLibrary()

        XCTAssertNil(library.loadIssue)
        let item = try XCTUnwrap(library.item(id))
        XCTAssertEqual(item.displayName, "Untitled")
        XCTAssertEqual(item.volume, 1, "Out-of-range volume is clamped")
        XCTAssertEqual(item.retriggerMode, .restart)
        XCTAssertTrue(item.isEnabled)
    }

    func testSoundWhoseFileVanishedIsFlaggedMissingAndCanBeRelocated() async throws {
        let library = makeLibrary()
        let item = try await library.importFile(at: TestAudio.writeTone(to: sources, seconds: 0.25))
        library.saveNow()
        try FileManager.default.removeItem(at: library.fileURL(for: item))

        let reloaded = makeLibrary()
        XCTAssertEqual(reloaded.missingFileIDs, [item.id])

        let replacement = try TestAudio.writeTone(to: sources, name: "replacement.wav", seconds: 0.5)
        try await reloaded.relocate(id: item.id, from: replacement)

        let relocated = try XCTUnwrap(reloaded.item(item.id))
        XCTAssertTrue(reloaded.missingFileIDs.isEmpty)
        XCTAssertNotEqual(relocated.fileName, item.fileName)
        XCTAssertEqual(relocated.duration, 0.5, accuracy: 0.02)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reloaded.fileURL(for: relocated).path))
    }

    func testRelocateWithBadFileLeavesItemUntouched() async throws {
        let library = makeLibrary()
        let item = try await library.importFile(at: TestAudio.writeTone(to: sources))
        let bad = sources.appendingPathComponent("bad.wav")
        try Data(repeating: 7, count: 512).write(to: bad)

        do {
            try await library.relocate(id: item.id, from: bad)
            XCTFail("Expected failure")
        } catch {}

        XCTAssertEqual(library.item(item.id), item)
        XCTAssertEqual(contents(of: library.soundsURL), [item.fileName])
    }

    // MARK: Duplicate

    func testDuplicateCopiesFileAndInsertsAfterOriginal() async throws {
        let library = makeLibrary()
        let a = try await library.importFile(at: TestAudio.writeTone(to: sources, name: "a.wav"))
        let b = try await library.importFile(at: TestAudio.writeTone(to: sources, name: "b.wav"))
        library.update(a.id) { $0.volume = 0.3 }

        let copy = try XCTUnwrap(library.duplicate(id: a.id))

        XCTAssertEqual(library.items.map(\.id), [a.id, copy.id, b.id])
        XCTAssertEqual(copy.displayName, "a copy")
        XCTAssertEqual(copy.volume, 0.3, accuracy: 0.0001)
        XCTAssertNotEqual(copy.fileName, a.fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.fileURL(for: copy).path))
        // Deleting the original must not affect the copy's audio.
        library.remove(id: a.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.fileURL(for: copy).path))
    }
}

final class AudioAnalyzerTests: XCTestCase {
    func testAnalyzeReportsDurationAndNormalisedWaveform() throws {
        let directory = try makeTemporaryDirectory()
        let url = try TestAudio.writeTone(to: directory, seconds: 1.0)

        let analysis = try AudioAnalyzer.analyze(url: url, buckets: 16)

        XCTAssertEqual(analysis.duration, 1.0, accuracy: 0.01)
        XCTAssertEqual(analysis.waveform.count, 16)
        XCTAssertTrue(analysis.waveform.allSatisfy { $0 > 0.9 && $0 <= 1 }, "A steady tone has a flat envelope")
    }

    func testBufferLoaderProducesCanonicalStereoBuffer() throws {
        let directory = try makeTemporaryDirectory()
        let url = try TestAudio.writeTone(to: directory, seconds: 0.5, sampleRate: 22_050)
        let target = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

        let buffer = try AudioBufferLoader.load(url: url, format: target)

        XCTAssertEqual(buffer.format.sampleRate, 48_000)
        XCTAssertEqual(buffer.format.channelCount, 2)
        XCTAssertEqual(Double(buffer.frameLength) / 48_000, 0.5, accuracy: 0.02)
        let left = buffer.floatChannelData![0], right = buffer.floatChannelData![1]
        var peak: Float = 0
        for frame in 0..<Int(buffer.frameLength) {
            XCTAssertEqual(left[frame], right[frame])
            peak = max(peak, abs(left[frame]))
        }
        XCTAssertEqual(peak, 0.5, accuracy: 0.05)
    }

    func testAnalyzeThrowsForGarbage() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent("junk.mp3")
        try Data(repeating: 0x41, count: 2048).write(to: url)

        XCTAssertThrowsError(try AudioAnalyzer.analyze(url: url))
    }
}
