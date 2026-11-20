import Accelerate
import AVFoundation

struct AudioAnalysis: Sendable, Equatable {
    let duration: TimeInterval
    let waveform: [Float]
}

enum AudioAnalysisError: Error {
    case empty
    case unreadable
}

/// Reads an audio file once to validate it and derive duration + a waveform thumbnail.
/// Reads in chunks so even hour-long files never load fully into memory.
enum AudioAnalyzer {
    static let waveformBucketCount = 40

    static func analyze(url: URL, buckets: Int = waveformBucketCount) throws -> AudioAnalysis {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = file.length
        guard totalFrames > 0, format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioAnalysisError.empty
        }

        let chunkSize: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            throw AudioAnalysisError.unreadable
        }

        var peaks = [Float](repeating: 0, count: buckets)
        var position: AVAudioFramePosition = 0
        let bucketCount = Int64(buckets)

        while position < totalFrames {
            do {
                try file.read(into: buffer, frameCount: chunkSize)
            } catch {
                // A failure before any audio was decoded means the file is unusable.
                // A failure near the end (estimated lengths, truncated files) is tolerated.
                if position == 0 { throw AudioAnalysisError.unreadable }
                break
            }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let channels = buffer.floatChannelData else { break }

            for channel in 0..<Int(format.channelCount) {
                let samples = channels[channel]
                var index = 0
                while index < frames {
                    let globalFrame = position + Int64(index)
                    let bucket = min(buckets - 1, Int(globalFrame * bucketCount / totalFrames))
                    let bucketEnd = Int64(bucket + 1) * totalFrames / bucketCount
                    let segmentEnd = min(frames, Int(max(bucketEnd, globalFrame + 1) - position))
                    var magnitude: Float = 0
                    vDSP_maxmgv(samples + index, 1, &magnitude, vDSP_Length(segmentEnd - index))
                    if magnitude > peaks[bucket] { peaks[bucket] = magnitude }
                    index = segmentEnd
                }
            }
            position += Int64(frames)
        }

        guard position > 0 else { throw AudioAnalysisError.unreadable }

        let maxPeak = peaks.max() ?? 0
        if maxPeak > 0 {
            peaks = peaks.map { (($0 / maxPeak) * 1000).rounded() / 1000 }
        }
        // Prefer the number of frames actually decoded when the header over-reports.
        let frameCount = min(position, totalFrames)
        return AudioAnalysis(duration: Double(frameCount) / format.sampleRate, waveform: peaks)
    }
}

/// Decodes a whole file into a stereo float buffer in the engine's canonical format,
/// so every preloaded sound can play on any pooled player node without reconnecting.
enum AudioBufferLoader {
    static func load(url: URL, format target: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let length = AVAudioFrameCount(clamping: file.length)
        guard length > 0,
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: length)
        else { throw AudioAnalysisError.empty }
        try file.read(into: source)
        guard source.frameLength > 0 else { throw AudioAnalysisError.empty }

        let stereo = try makeStereo(source)
        if stereo.format.sampleRate == target.sampleRate { return stereo }
        return try resample(stereo, to: target)
    }

    private static func makeStereo(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let input = source.floatChannelData,
              let format = AVAudioFormat(standardFormatWithSampleRate: source.format.sampleRate, channels: 2),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: source.frameLength),
              let destination = output.floatChannelData
        else { throw AudioAnalysisError.unreadable }

        let frames = Int(source.frameLength)
        let channelCount = Int(source.format.channelCount)
        output.frameLength = source.frameLength
        let byteCount = frames * MemoryLayout<Float>.size
        // Mono is duplicated to both sides; anything wider keeps its first two channels.
        memcpy(destination[0], input[0], byteCount)
        memcpy(destination[1], input[channelCount > 1 ? 1 : 0], byteCount)
        return output
    }

    private static func resample(_ source: AVAudioPCMBuffer, to target: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: source.format, to: target) else {
            throw AudioAnalysisError.unreadable
        }
        let ratio = target.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw AudioAnalysisError.unreadable
        }

        var delivered = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .endOfStream
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return source
        }
        if status == .error || output.frameLength == 0 {
            throw conversionError ?? AudioAnalysisError.unreadable
        }
        return output
    }
}
