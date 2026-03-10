import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

@MainActor
final class DropZoneViewModel: ObservableObject {
    @Published var isTargeted = false
    @Published var isProcessing = false
    @Published var isAlwaysOnTop = false
    @Published var useDefaultFolder = false
    @Published var exportFiveFrames = false
    @Published var useCustomCapture = false
    @Published var outputMode: OutputAspectMode = .matchSource
    @Published private(set) var defaultFolderURL: URL?
    @Published private(set) var previewPlayer: AVPlayer?
    @Published var previewDuration: Double = 1
    @Published var previewTime: Double = 0
    @Published var progress = 0.0
    @Published var statusText = "Supports .mp4, .mov, .m4v"
    @Published var errorMessage: String?

    private let processor = VideoStillProcessor()
    private let allowedExtensions: Set<String> = ["mp4", "mov", "m4v"]
    private weak var window: NSWindow?
    private var previewTimeObserver: Any?
    private var isScrubbingPreview = false
    private var previewVideoURL: URL?
    private var nextCustomFrameIndex = 1

    var defaultFolderDisplayName: String {
        defaultFolderURL?.lastPathComponent ?? "Not set"
    }

    var previewTimeLabel: String {
        formatTime(previewTime)
    }

    var previewDurationLabel: String {
        formatTime(previewDuration)
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        Task {
            await processDrop(providers: providers)
        }
        return true
    }

    func setWindow(_ window: NSWindow) {
        self.window = window
        applyWindowLevel()
    }

    func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        applyWindowLevel()
    }

    func setUseCustomCapture(_ enabled: Bool) {
        guard !isProcessing else { return }
        useCustomCapture = enabled

        if enabled {
            statusText = "Custom mode enabled. Drop one video to preview."
            errorMessage = nil
        } else {
            clearPreviewState()
            statusText = "Supports .mp4, .mov, .m4v"
        }
    }

    func setPreviewScrubbing(_ isScrubbing: Bool) {
        isScrubbingPreview = isScrubbing
        if !isScrubbing {
            seekPreview(to: previewTime)
        }
    }

    func seekPreview(to seconds: Double) {
        guard let player = previewPlayer else { return }
        let clamped = min(max(0, seconds), max(previewDuration, 0))
        previewTime = clamped
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func captureCustomFrame() {
        Task {
            await captureCustomFrameAtCurrentTime()
        }
    }

    func setUseDefaultFolder(_ enabled: Bool) {
        guard !isProcessing else { return }

        if enabled {
            guard let folder = chooseDestinationFolder(
                title: "Choose Default Export Folder",
                prompt: "Use Folder"
            ) else {
                useDefaultFolder = false
                statusText = "Default folder not set."
                return
            }

            defaultFolderURL = folder
            useDefaultFolder = true
            statusText = "Default folder: \(folder.lastPathComponent)"
        } else {
            useDefaultFolder = false
            defaultFolderURL = nil
            statusText = "Supports .mp4, .mov, .m4v"
        }
    }

    func chooseNewDefaultFolder() {
        guard !isProcessing else { return }
        guard let folder = chooseDestinationFolder(
            title: "Choose Default Export Folder",
            prompt: "Use Folder"
        ) else {
            return
        }
        defaultFolderURL = folder
        useDefaultFolder = true
        statusText = "Default folder: \(folder.lastPathComponent)"
    }

    private func processDrop(providers: [NSItemProvider]) async {
        guard !isProcessing else { return }
        errorMessage = nil
        statusText = "Loading dropped files..."

        do {
            let urls = try await loadDroppedURLs(from: providers)
            let videos = urls.filter { allowedExtensions.contains($0.pathExtension.lowercased()) }

            guard !videos.isEmpty else {
                statusText = "No supported videos found."
                errorMessage = "Drop .mp4, .mov, or .m4v files."
                return
            }

            if useCustomCapture {
                try await loadPreviewVideo(from: videos)
                return
            }

            isProcessing = true
            progress = 0
            statusText = "Processing \(videos.count) video(s)..."

            let tempFolder = try processor.createTempFolder()
            var cachedFiles: [URL] = []
            var processedCount = 0
            var lastFrameFailures: [String] = []

            for videoURL in videos {
                statusText = "Extracting: \(videoURL.lastPathComponent)"
                do {
                    let output = try await processor.processVideoInBackground(
                        videoURL,
                        cacheFolder: tempFolder,
                        exportFiveFrames: exportFiveFrames,
                        outputMode: outputMode
                    )
                    cachedFiles.append(contentsOf: output)
                } catch let error as ProcessingError {
                    if case .lastFrameExportFailed(let videoName) = error {
                        lastFrameFailures.append(videoName)
                    } else {
                        throw error
                    }
                }
                processedCount += 1
                progress = Double(processedCount) / Double(videos.count)
            }

            guard !cachedFiles.isEmpty else {
                try? FileManager.default.removeItem(at: tempFolder)
                isProcessing = false
                progress = 0
                statusText = "Processing failed."
                if !lastFrameFailures.isEmpty {
                    errorMessage = lastFrameFailureMessage(names: lastFrameFailures)
                }
                return
            }

            let destination: URL
            if useDefaultFolder {
                guard let folder = defaultFolderURL,
                      FileManager.default.fileExists(atPath: folder.path) else {
                    throw DropError.defaultFolderMissing
                }
                destination = folder
                statusText = "Saving to default folder..."
            } else {
                statusText = "Choose destination folder..."
                guard let selected = chooseDestinationFolder(
                    title: "Choose Destination Folder",
                    prompt: "Save Here"
                ) else {
                    statusText = "Save cancelled."
                    isProcessing = false
                    try? FileManager.default.removeItem(at: tempFolder)
                    return
                }
                destination = selected
            }

            let saved = try await processor.moveCachedFilesInBackground(cachedFiles, to: destination)
            try? FileManager.default.removeItem(at: tempFolder)
            statusText = "Saved \(saved) image(s) to \(destination.lastPathComponent)."
            if !lastFrameFailures.isEmpty {
                errorMessage = lastFrameFailureMessage(names: lastFrameFailures)
            }
            isProcessing = false
            progress = 1.0
        } catch {
            isProcessing = false
            progress = 0
            statusText = "Processing failed."
            errorMessage = error.localizedDescription
        }
    }

    private func loadPreviewVideo(from videos: [URL]) async throws {
        clearPreviewState()

        let selected = videos[0]
        if videos.count > 1 {
            errorMessage = "Custom mode uses the first dropped video."
        } else {
            errorMessage = nil
        }

        let asset = AVURLAsset(url: selected)
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.isNumeric && duration.seconds > 0 ? duration.seconds : 1

        let player = AVPlayer(url: selected)
        previewPlayer = player
        previewVideoURL = selected
        previewDuration = durationSeconds
        previewTime = 0
        nextCustomFrameIndex = 1
        statusText = "Scrub and tap camera to capture."

        installPreviewObserver(on: player)
        player.pause()
        await player.seek(to: .zero)
    }

    private func installPreviewObserver(on player: AVPlayer) {
        removePreviewObserver()
        previewTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                if !self.isScrubbingPreview {
                    let seconds = max(0, time.seconds)
                    self.previewTime = min(seconds, self.previewDuration)
                }
            }
        }
    }

    private func removePreviewObserver() {
        if let player = previewPlayer, let token = previewTimeObserver {
            player.removeTimeObserver(token)
        }
        previewTimeObserver = nil
    }

    private func clearPreviewState() {
        removePreviewObserver()
        previewPlayer?.pause()
        previewPlayer = nil
        previewVideoURL = nil
        previewDuration = 1
        previewTime = 0
        nextCustomFrameIndex = 1
        isScrubbingPreview = false
    }

    private func captureCustomFrameAtCurrentTime() async {
        guard useCustomCapture else { return }
        guard let videoURL = previewVideoURL, let player = previewPlayer else {
            errorMessage = "Drop a video first to capture custom frames."
            return
        }
        guard !isProcessing else { return }

        do {
            isProcessing = true
            errorMessage = nil

            let destination: URL
            if useDefaultFolder {
                guard let folder = defaultFolderURL,
                      FileManager.default.fileExists(atPath: folder.path) else {
                    throw DropError.defaultFolderMissing
                }
                destination = folder
            } else {
                guard let selected = chooseDestinationFolder(
                    title: "Choose Destination Folder",
                    prompt: "Save Here"
                ) else {
                    statusText = "Capture cancelled."
                    isProcessing = false
                    return
                }
                destination = selected
            }

            let baseName = videoURL.deletingPathExtension().lastPathComponent
            let output = nextCustomFrameURL(baseName: baseName, in: destination)
            let requestedTime = CMTime(seconds: previewTime, preferredTimescale: 600)

            player.pause()
            await player.seek(to: requestedTime, toleranceBefore: .zero, toleranceAfter: .zero)
            let captureTime = player.currentTime()
            previewTime = min(max(0, captureTime.seconds), previewDuration)

            statusText = "Capturing \(output.lastPathComponent)..."
            try await processor.exportFrameInBackground(
                videoURL: videoURL,
                at: captureTime,
                outputURL: output,
                outputMode: outputMode,
                strict: true
            )

            nextCustomFrameIndex += 1
            statusText = "Saved \(output.lastPathComponent)."
            isProcessing = false
        } catch {
            isProcessing = false
            statusText = "Capture failed."
            errorMessage = error.localizedDescription
        }
    }

    private func nextCustomFrameURL(baseName: String, in destination: URL) -> URL {
        var index = max(1, nextCustomFrameIndex)
        while true {
            let candidate = destination.appendingPathComponent("\(baseName)_Frame\(index).jpg")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                nextCustomFrameIndex = index
                return candidate
            }
            index += 1
        }
    }

    private func lastFrameFailureMessage(names: [String]) -> String {
        if names.count == 1 {
            return "Couldn't export last frame of \(names[0])."
        }
        return "Couldn't export last frame of: \(names.joined(separator: ", "))."
    }

    private func chooseDestinationFolder(title: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func applyWindowLevel() {
        window?.level = isAlwaysOnTop ? .floating : .normal
    }

    private func formatTime(_ seconds: Double) -> String {
        let safe = max(0, Int(seconds.rounded(.down)))
        let minutes = safe / 60
        let secs = safe % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func loadDroppedURLs(from providers: [NSItemProvider]) async throws -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url = try await provider.loadDroppedFileURL()
            urls.append(url)
        }
        return urls
    }
}

private extension NSItemProvider {
    @MainActor
    func loadDroppedFileURL() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let data = item as? Data,
                   let string = String(data: data, encoding: .utf8),
                   let url = URL(string: string) {
                    continuation.resume(returning: url)
                    return
                }

                continuation.resume(throwing: DropError.invalidDropItem)
            }
        }
    }
}

enum DropError: LocalizedError {
    case invalidDropItem
    case defaultFolderMissing

    var errorDescription: String? {
        switch self {
        case .invalidDropItem:
            return "Could not read one of the dropped files."
        case .defaultFolderMissing:
            return "Default folder is missing. Turn off Default folder or choose it again."
        }
    }
}
