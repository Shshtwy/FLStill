import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

enum OutputAspectMode: String, CaseIterable, Identifiable, Sendable {
    case matchSource = "Match Source"
    case landscape = "16:9"
    case portrait = "9:16"

    var id: String { rawValue }
}

struct VideoStillProcessor: Sendable {
    private let landscapeTargetSize = CGSize(width: 1056, height: 594)
    private let portraitTargetSize = CGSize(width: 334, height: 594)
    private let jpegCompression: CGFloat = 0.9

    func createTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FLStill-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func processVideo(
        _ videoURL: URL,
        cacheFolder: URL,
        exportFiveFrames: Bool,
        outputMode: OutputAspectMode
    ) async throws -> [URL] {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let frameBounds = try await readFrameBounds(asset: asset)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let baseName = videoURL.deletingPathExtension().lastPathComponent
        let firstFrameTime = frameBounds?.first ?? .zero
        let lastTime = frameBounds?.last ?? lastFrameTime(for: duration)

        let first = try extractFrame(generator: generator, at: firstFrameTime, strict: false)
        let targetSize = resolveTargetSize(for: first, mode: outputMode)
        let firstURL = cacheFolder.appendingPathComponent("\(baseName)_First.jpg")
        try writeJPEG(from: first, to: firstURL, targetSize: targetSize)

        if exportFiveFrames {
            let middleTimes = middleFrameTimes(start: firstFrameTime, end: lastTime)
            var urls: [URL] = [firstURL]

            for (index, time) in middleTimes.enumerated() {
                let image = try extractFrame(generator: generator, at: time, strict: true)
                let fileURL = cacheFolder.appendingPathComponent("\(baseName)_Frame\(index + 2).jpg")
                try writeJPEG(from: image, to: fileURL, targetSize: targetSize)
                urls.append(fileURL)
            }

            let last = try extractVerifiedLastFrame(
                generator: generator,
                lastTimestamp: lastTime,
                duration: duration,
                videoName: videoURL.lastPathComponent
            )
            let lastURL = cacheFolder.appendingPathComponent("\(baseName)_Last.jpg")
            try writeJPEG(from: last, to: lastURL, targetSize: targetSize)
            urls.append(lastURL)
            return urls
        } else {
            let last = try extractVerifiedLastFrame(
                generator: generator,
                lastTimestamp: lastTime,
                duration: duration,
                videoName: videoURL.lastPathComponent
            )
            let lastURL = cacheFolder.appendingPathComponent("\(baseName)_Last.jpg")
            try writeJPEG(from: last, to: lastURL, targetSize: targetSize)
            return [firstURL, lastURL]
        }
    }

    func processVideoInBackground(
        _ videoURL: URL,
        cacheFolder: URL,
        exportFiveFrames: Bool,
        outputMode: OutputAspectMode
    ) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            try await processVideo(
                videoURL,
                cacheFolder: cacheFolder,
                exportFiveFrames: exportFiveFrames,
                outputMode: outputMode
            )
        }.value
    }

    func moveCachedFiles(_ files: [URL], to destinationFolder: URL) throws -> Int {
        var savedCount = 0
        for file in files {
            let resolved = uniqueDestinationURL(for: file.lastPathComponent, folder: destinationFolder)
            try FileManager.default.copyItem(at: file, to: resolved)
            savedCount += 1
        }
        return savedCount
    }

    func moveCachedFilesInBackground(_ files: [URL], to destinationFolder: URL) async throws -> Int {
        try await Task.detached(priority: .userInitiated) {
            try moveCachedFiles(files, to: destinationFolder)
        }.value
    }

    func exportFrameInBackground(
        videoURL: URL,
        at time: CMTime,
        outputURL: URL,
        outputMode: OutputAspectMode,
        strict: Bool = true
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let image = try extractFrame(generator: generator, at: time, strict: strict)
            let targetSize = resolveTargetSize(for: image, mode: outputMode)
            try writeJPEG(from: image, to: outputURL, targetSize: targetSize)
        }.value
    }

    private func lastFrameTime(for duration: CMTime) -> CMTime {
        if duration.isNumeric && duration.seconds > 0 {
            let epsilon = CMTime(seconds: 1.0 / 600.0, preferredTimescale: 600)
            let candidate = duration - epsilon
            return candidate.seconds > 0 ? candidate : .zero
        }
        return .zero
    }

    private func writeJPEG(from image: CGImage, to url: URL, targetSize: CGSize) throws {
        let resized = try centerCropResize(image: image, to: targetSize)
        let bitmap = NSBitmapImageRep(cgImage: resized)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: jpegCompression]) else {
            throw ProcessingError.jpegEncodingFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private func resolveTargetSize(for image: CGImage, mode: OutputAspectMode) -> CGSize {
        switch mode {
        case .landscape:
            return landscapeTargetSize
        case .portrait:
            return portraitTargetSize
        case .matchSource:
            let isPortrait = image.height > image.width
            return isPortrait ? portraitTargetSize : landscapeTargetSize
        }
    }

    private func extractFrame(generator: AVAssetImageGenerator, at time: CMTime, strict: Bool) throws -> CGImage {
        if strict {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
        } else {
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
        }

        var actual = CMTime.zero
        return try generator.copyCGImage(at: time, actualTime: &actual)
    }

    private func extractVerifiedLastFrame(
        generator: AVAssetImageGenerator,
        lastTimestamp: CMTime,
        duration: CMTime,
        videoName: String
    ) throws -> CGImage {
        do {
            return try extractFrame(generator: generator, at: lastTimestamp, strict: true)
        } catch {
            for fallbackTime in fallbackLastFrameTimes(from: lastTimestamp, duration: duration) {
                if let image = try? extractFrame(generator: generator, at: fallbackTime, strict: true) {
                    return image
                }
            }
            throw ProcessingError.lastFrameExportFailed(videoName)
        }
    }

    private func fallbackLastFrameTimes(from start: CMTime, duration: CMTime) -> [CMTime] {
        let step = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        let earliest = CMTime.zero
        var times: [CMTime] = []
        var cursor = start

        for _ in 0..<18 {
            cursor = cursor - step
            if cursor <= earliest {
                break
            }
            times.append(cursor)
        }

        let durationFallback = lastFrameTime(for: duration)
        if durationFallback > earliest {
            times.append(durationFallback)
        }
        return times
    }

    private func middleFrameTimes(start: CMTime, end: CMTime) -> [CMTime] {
        guard start.isValid, end.isValid, start.isNumeric, end.isNumeric else {
            return [.zero, .zero, .zero]
        }

        let startSeconds = max(0, start.seconds)
        let endSeconds = max(startSeconds, end.seconds)
        let span = endSeconds - startSeconds

        if span <= 0 {
            let fallback = CMTime(seconds: startSeconds, preferredTimescale: 600)
            return [fallback, fallback, fallback]
        }

        return [0.25, 0.5, 0.75].map { fraction in
            let seconds = startSeconds + (span * fraction)
            return CMTime(seconds: seconds, preferredTimescale: 600)
        }
    }

    private func readFrameBounds(asset: AVAsset) async throws -> (first: CMTime, last: CMTime)? {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            return nil
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw ProcessingError.assetReadFailed
        }
        reader.add(output)

        guard reader.startReading() else {
            throw ProcessingError.assetReadFailed
        }

        var first: CMTime?
        var last: CMTime?

        while let sample = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            if first == nil {
                first = pts
            }
            if pts.isValid && pts.isNumeric {
                last = pts
            }
            CMSampleBufferInvalidate(sample)
        }

        if reader.status == .failed {
            throw ProcessingError.assetReadFailed
        }

        guard let first, let last else {
            return nil
        }
        return (first, last)
    }

    private func centerCropResize(image: CGImage, to target: CGSize) throws -> CGImage {
        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw ProcessingError.invalidImageSize
        }

        let scale = max(target.width / sourceWidth, target.height / sourceHeight)
        let drawWidth = sourceWidth * scale
        let drawHeight = sourceHeight * scale
        let drawRect = CGRect(
            x: (target.width - drawWidth) / 2,
            y: (target.height - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(target.width),
            height: Int(target.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ProcessingError.contextCreationFailed
        }

        context.interpolationQuality = .high
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: target))
        context.draw(image, in: drawRect)

        guard let output = context.makeImage() else {
            throw ProcessingError.imageCreationFailed
        }
        return output
    }

    private func uniqueDestinationURL(for fileName: String, folder: URL) -> URL {
        let ext = (fileName as NSString).pathExtension
        let stem = (fileName as NSString).deletingPathExtension
        var candidate = folder.appendingPathComponent(fileName)
        var counter = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = "\(stem) (\(counter)).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }
}

enum ProcessingError: LocalizedError {
    case invalidImageSize
    case contextCreationFailed
    case imageCreationFailed
    case jpegEncodingFailed
    case assetReadFailed
    case lastFrameExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImageSize:
            return "Video frame has an invalid image size."
        case .contextCreationFailed:
            return "Could not allocate image processing context."
        case .imageCreationFailed:
            return "Could not create resized image."
        case .jpegEncodingFailed:
            return "Could not encode JPEG output."
        case .assetReadFailed:
            return "Could not read video frame timestamps."
        case .lastFrameExportFailed(let name):
            return "Couldn't export last frame of \(name)."
        }
    }
}
