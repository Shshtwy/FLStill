# FLStill Windows (MP4)

This folder contains a Windows-focused port of FLStill using Electron and FFmpeg.

## Scope
- Input support: `.mp4` only.
- Features:
- Drag and drop video files.
- Export first/last frame or 5-frame set.
- Output modes: Match Source, 16:9, 9:16.
- Custom capture from preview timeline.
- Default output folder toggle.
- Always-on-top pin toggle.

## Prerequisites (Windows)
1. Install Node.js 20+.
2. Install `ffmpeg` and `ffprobe`, and ensure both are available in `PATH`.

## Run
```bash
cd windows
npm install
npm start
```

## Build .exe
From a Windows terminal in `windows/`:

```bash
npm install
npm run dist:win
```

Installer output:
- `windows/dist/FLStill-1.0.0-nsis.exe`

Portable single-file output:

```bash
npm run dist:portable
```

- `windows/dist/FLStill-1.0.0-portable.exe`

## Notes
- Current packaging/signing is not included yet.
- If ffmpeg is missing from `PATH`, exports fail with a command error.
