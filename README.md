# FLStill
A tiny macOS SwiftUI utility that extracts First and Last frames from dropped videos and saves them as JPEG stills.

## What it does

- Drag and drop one or more video files into the window (supports: **.mp4**, **.mov**, **.m4v**).
- For each video, exports:
  - `<VideoName>_First.jpg`
  - `<VideoName>_Last.jpg`
- Stills are center-cropped and resized to **1056 × 594** and encoded as JPEG (compression factor **0.9**).
- Optional quality-of-life toggles:
  - **Default folder**: choose a folder once and always save there.
  - **Always on top**: pin the window above others.

## Requirements

- macOS 13+
- Xcode with a Swift 6.2 toolchain (see `Package.swift`)

## Build & Run

### Xcode

1. Open `FLStill.xcodeproj`
2. Select the `FLStill` scheme
3. Build and Run

### SwiftPM (optional)

From the repo root:

```bash
swift run FLStill
```

## Project layout

- `Sources/FLStill/*` contains the SwiftUI app and processing code
- `Package.swift` defines the Swift package
- `project.yml` is provided for XcodeGen workflows (optional)

## Notes

- The last-frame export uses a strict timestamp first, then tries several fallback timestamps slightly earlier if needed.
- If an output filename already exists in the destination folder, a numbered suffix is added automatically.
