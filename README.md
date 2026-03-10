# FLStill

FLStill is a desktop app for macOS and Windows that exports clean JPEG stills from video files.

It supports fast frame extraction for:
- first and last frame
- 5 evenly spaced frames
- custom manually selected frames

## Platforms

### macOS
Built with:
- Swift
- SwiftUI
- AVFoundation

Supported input formats:
- `.mp4`
- `.mov`
- `.m4v`

### Windows
Built with:
- Electron
- FFmpeg
- FFprobe

Current supported input format:
- `.mp4`

## Features

- Drag and drop one or more video files
- Export:
  - first frame
  - last frame
  - 5 evenly spaced frames
  - custom selected frames from a video preview
- Exact JPEG export sizing with center-crop
- Output aspect modes:
  - `Match Source`
  - `16:9`
  - `9:16`
- Session-based default export folder
- Always-on-top window toggle
- Clean minimal desktop UI

## Export Sizes

### Landscape
- `1056 x 594`

### Portrait
- `334 x 594`

### Match Source
- Automatically selects landscape or portrait output based on the source frame orientation

## Export Naming

### Standard export
- `<VideoBaseName>_First.jpg`
- `<VideoBaseName>_Last.jpg`

### 5 Frames export
- `<VideoBaseName>_First.jpg`
- `<VideoBaseName>_Frame2.jpg`
- `<VideoBaseName>_Frame3.jpg`
- `<VideoBaseName>_Frame4.jpg`
- `<VideoBaseName>_Last.jpg`

### Custom export
- `<VideoBaseName>_Frame1.jpg`
- `<VideoBaseName>_Frame2.jpg`
- `<VideoBaseName>_Frame3.jpg`

If a file already exists, FLStill appends an incrementing number automatically.

## How It Works

1. Drop one or more supported video files into the app
2. Choose your export mode:
   - first + last
   - 5 frames
   - custom capture
3. FLStill extracts frames from the video
4. Each image is resized and center-cropped to the selected output mode
5. Files are saved as JPEGs in your chosen folder

## Windows Notes

The current Windows build is focused on `.mp4` input and requires:
- Node.js 20+ for development
- `ffmpeg` and `ffprobe` available in `PATH`
