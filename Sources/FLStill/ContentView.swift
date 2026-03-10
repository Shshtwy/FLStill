import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = DropZoneViewModel()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = max(0.58, min(1.0, min(size.width / 760, size.height / 520)))
            let outerPadding = max(12, 24 * scale)
            let contentPadding = max(12, 44 * scale)
            let iconSize = max(34, 62 * scale)
            let titleSize = max(22, 48 * scale)
            let statusSize = max(11, 14 * scale)
            let controlsSize = max(11, 13 * scale)
            let spacing = max(12, 24 * scale)
            let progressWidth = min(max(180, size.width * 0.6), 360)

            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [Color(red: 0.19, green: 0.19, blue: 0.2), Color(red: 0.15, green: 0.15, blue: 0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: spacing) {
                    Spacer(minLength: 0)

                    if viewModel.useCustomCapture {
                        if let player = viewModel.previewPlayer {
                            let previewWidth = min(max(260, size.width * 0.58), 860)
                            let previewHeight = previewWidth * 9 / 16

                            VStack(spacing: max(10, 14 * scale)) {
                                VideoPlayer(player: player)
                                    .frame(width: previewWidth, height: previewHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: max(10, 14 * scale), style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: max(10, 14 * scale), style: .continuous)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )

                                VStack(spacing: max(8, 10 * scale)) {
                                    Slider(
                                        value: Binding(
                                            get: { viewModel.previewTime },
                                            set: {
                                                viewModel.previewTime = $0
                                                viewModel.seekPreview(to: $0)
                                            }
                                        ),
                                        in: 0...max(viewModel.previewDuration, 0.1),
                                        onEditingChanged: { editing in
                                            viewModel.setPreviewScrubbing(editing)
                                        }
                                    )

                                    HStack(spacing: max(10, 12 * scale)) {
                                        Text(viewModel.previewTimeLabel)
                                        Spacer()
                                        Text(viewModel.previewDurationLabel)
                                    }
                                    .foregroundStyle(.white.opacity(0.86))
                                    .font(.system(size: statusSize, weight: .medium))
                                    .frame(width: previewWidth)

                                    Button(action: viewModel.captureCustomFrame) {
                                        Image(systemName: "camera.circle.fill")
                                            .font(.system(size: max(34, 44 * scale), weight: .medium))
                                            .foregroundStyle(.white.opacity(0.95))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Capture frame")
                                    .disabled(viewModel.isProcessing)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                        } else {
                            VStack(spacing: max(10, 14 * scale)) {
                                Image(systemName: "film.stack")
                                    .font(.system(size: iconSize, weight: .light))
                                    .foregroundStyle(.white.opacity(0.72))
                                Text("Drop one video to start custom capture")
                                    .font(.system(size: max(16, titleSize * 0.45), weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    } else {
                        Image(systemName: "film.stack")
                            .font(.system(size: iconSize, weight: .light))
                            .foregroundStyle(.white.opacity(0.72))

                        Text("Drop your videos here")
                            .font(.system(size: titleSize, weight: .light))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    }

                    if viewModel.isProcessing {
                        VStack(spacing: max(6, 10 * scale)) {
                            ProgressView(value: viewModel.progress)
                                .progressViewStyle(.linear)
                                .tint(.white.opacity(0.9))
                                .frame(width: progressWidth)
                            Text(viewModel.statusText)
                                .foregroundStyle(.white.opacity(0.82))
                                .font(.system(size: statusSize, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 2)
                    } else if !viewModel.statusText.isEmpty {
                        Text(viewModel.statusText)
                            .foregroundStyle(.white.opacity(0.82))
                            .font(.system(size: statusSize, weight: .medium))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
                            .font(.system(size: max(10, 13 * scale), weight: .semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: max(220, size.width * 0.82))
                            .lineLimit(3)
                            .padding(.top, 4)
                    }

                    Spacer(minLength: 0)
                }
                .padding(contentPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: max(14, 26 * scale), style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: max(2, 3 * scale), dash: [10 * scale, 8 * scale])
                        )
                        .foregroundStyle(viewModel.isTargeted ? .white.opacity(0.85) : .white.opacity(0.3))
                        .padding(outerPadding)
                )
                .onDrop(of: [UTType.fileURL], isTargeted: $viewModel.isTargeted) { providers in
                    viewModel.handleDrop(providers: providers)
                }
                .background(WindowAccessor { window in
                    viewModel.setWindow(window)
                })

                VStack(alignment: .leading, spacing: max(6, 10 * scale)) {
                    HStack(spacing: max(10, 18 * scale)) {
                        Toggle(
                            "Default folder",
                            isOn: Binding(
                                get: { viewModel.useDefaultFolder },
                                set: { viewModel.setUseDefaultFolder($0) }
                            )
                        )
                        .toggleStyle(.switch)
                        .font(.system(size: controlsSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .disabled(viewModel.isProcessing)

                        Toggle("Export 5 Frames", isOn: $viewModel.exportFiveFrames)
                            .toggleStyle(.switch)
                            .font(.system(size: controlsSize, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .disabled(viewModel.isProcessing)

                        Toggle(
                            "Custom",
                            isOn: Binding(
                                get: { viewModel.useCustomCapture },
                                set: { viewModel.setUseCustomCapture($0) }
                            )
                        )
                        .toggleStyle(.switch)
                        .font(.system(size: controlsSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .disabled(viewModel.isProcessing)
                    }

                    Picker("Output", selection: $viewModel.outputMode) {
                        ForEach(OutputAspectMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: min(max(240, size.width * 0.36), 380))
                    .disabled(viewModel.isProcessing)

                    if viewModel.useDefaultFolder {
                        Button(action: viewModel.chooseNewDefaultFolder) {
                            Text(viewModel.defaultFolderDisplayName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.system(size: max(10, 12 * scale), weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(scale < 0.8 ? .mini : .small)
                        .disabled(viewModel.isProcessing)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, max(24, 38 * scale))
                .padding(.leading, max(22, 40 * scale))

                Button(action: viewModel.toggleAlwaysOnTop) {
                    Image(systemName: viewModel.isAlwaysOnTop ? "pin.fill" : "pin")
                        .font(.system(size: max(11, 14 * scale), weight: .semibold))
                        .padding(max(7, 10 * scale))
                        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(viewModel.isAlwaysOnTop ? "Disable Always on Top" : "Enable Always on Top")
                .padding(max(14, 20 * scale))
            }
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}
