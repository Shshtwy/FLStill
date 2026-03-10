const { spawn } = require("child_process");
const fs = require("fs/promises");
const fsSync = require("fs");
const os = require("os");
const path = require("path");

const LANDSCAPE = { width: 1056, height: 594 };
const PORTRAIT = { width: 334, height: 594 };

function run(cmd, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { windowsHide: true });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    child.on("error", (err) => {
      reject(err);
    });

    child.on("close", (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        reject(new Error(`${cmd} failed (${code}): ${stderr || stdout}`));
      }
    });
  });
}

function assertMp4(videoPath) {
  if (!videoPath || path.extname(videoPath).toLowerCase() !== ".mp4") {
    throw new Error("Only .mp4 files are supported in this Windows port.");
  }
}

function parseNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function parseFrameRate(value) {
  if (typeof value !== "string" || value.length === 0) {
    return 0;
  }

  if (value.includes("/")) {
    const [numRaw, denRaw] = value.split("/");
    const num = parseNumber(numRaw, 0);
    const den = parseNumber(denRaw, 0);
    if (num > 0 && den > 0) {
      return num / den;
    }
    return 0;
  }

  return parseNumber(value, 0);
}

function parseFfprobeDuration(raw) {
  const duration = parseNumber(raw.format && raw.format.duration, 0);
  const streams = Array.isArray(raw.streams) ? raw.streams : [];
  const video = streams.find((s) => s.codec_type === "video") || streams[0] || {};

  const width = parseNumber(video.width, 0);
  const height = parseNumber(video.height, 0);
  const start = Math.max(0, parseNumber(video.start_time, parseNumber(raw.format && raw.format.start_time, 0)));
  const avgFps = parseFrameRate(video.avg_frame_rate);
  const realFps = parseFrameRate(video.r_frame_rate);
  const fps = avgFps > 0 ? avgFps : realFps > 0 ? realFps : 30;

  return {
    duration: Math.max(0, duration),
    width,
    height,
    start,
    fps,
    frameDuration: 1 / fps
  };
}

function resolveTarget(mode, width, height) {
  if (mode === "landscape") {
    return LANDSCAPE;
  }
  if (mode === "portrait") {
    return PORTRAIT;
  }

  return height > width ? PORTRAIT : LANDSCAPE;
}

function buildFilter(mode, width, height) {
  const target = resolveTarget(mode, width, height);
  const ratio = target.width / target.height;

  // Match the Swift behavior: fill target box, then center-crop.
  return `scale='if(gte(a,${ratio}),-2,${target.width})':'if(gte(a,${ratio}),${target.height},-2)',crop=${target.width}:${target.height}`;
}

function formatTime(seconds) {
  const safe = Math.max(0, seconds);
  return safe.toFixed(6);
}

async function ensureDir(folderPath) {
  await fs.mkdir(folderPath, { recursive: true });
}

function uniquePath(folder, fileName) {
  const ext = path.extname(fileName);
  const stem = path.basename(fileName, ext);

  let index = 1;
  let candidate = path.join(folder, fileName);

  while (fsSync.existsSync(candidate)) {
    index += 1;
    candidate = path.join(folder, `${stem} (${index})${ext}`);
  }

  return candidate;
}

async function extractFrame({ videoPath, seconds, outputPath, outputMode, width, height, accurateSeek = false }) {
  const filter = buildFilter(outputMode, width, height);
  const args = ["-v", "error"];

  if (accurateSeek) {
    args.push("-i", videoPath, "-ss", formatTime(seconds));
  } else {
    args.push("-ss", formatTime(seconds), "-i", videoPath);
  }

  args.push("-frames:v", "1", "-q:v", "2", "-vf", filter, "-y", outputPath);

  await run("ffmpeg", args);

  if (!fsSync.existsSync(outputPath)) {
    throw new Error(`Frame extraction did not produce output: ${outputPath}`);
  }
}

function middleTimes(start, end) {
  const safeStart = Math.max(0, start);
  const safeEnd = Math.max(safeStart, end);
  const span = safeEnd - safeStart;

  if (span <= 0) {
    return [safeStart, safeStart, safeStart];
  }

  return [0.25, 0.5, 0.75].map((f) => safeStart + span * f);
}

function buildLastFrameFallbacks(duration, start) {
  const exact = Math.max(start, duration - 1 / 600);
  const times = [exact];

  for (let i = 1; i <= 18; i += 1) {
    const candidate = exact - i / 30;
    if (candidate <= start) {
      break;
    }
    times.push(candidate);
  }

  if (!times.includes(start)) {
    times.push(start);
  }

  return times;
}

async function probeVideo(videoPath) {
  assertMp4(videoPath);

  const { stdout } = await run("ffprobe", [
    "-v",
    "error",
    "-select_streams",
    "v:0",
    "-show_entries",
    "stream=width,height,start_time:format=duration,start_time",
    "-of",
    "json",
    videoPath
  ]);

  let parsed;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    throw new Error("Failed to parse ffprobe output.");
  }

  const meta = parseFfprobeDuration(parsed);
  if (meta.width <= 0 || meta.height <= 0) {
    throw new Error("Could not read video dimensions.");
  }

  return meta;
}

async function processSingleVideo({ videoPath, cacheFolder, exportFiveFrames, outputMode }) {
  assertMp4(videoPath);

  const meta = await probeVideo(videoPath);
  const base = path.basename(videoPath, path.extname(videoPath));
  const firstTime = meta.start;
  const lastFallbacks = buildLastFrameFallbacks(meta.duration, firstTime);

  const firstPath = path.join(cacheFolder, `${base}_First.jpg`);
  await extractFrame({
    videoPath,
    seconds: firstTime,
    outputPath: firstPath,
    outputMode,
    width: meta.width,
    height: meta.height
  });

  const outputPaths = [firstPath];

  if (exportFiveFrames) {
    const lastHint = lastFallbacks[0];
    const mids = middleTimes(firstTime, lastHint);

    for (let i = 0; i < mids.length; i += 1) {
      const framePath = path.join(cacheFolder, `${base}_Frame${i + 2}.jpg`);
      await extractFrame({
        videoPath,
        seconds: mids[i],
        outputPath: framePath,
        outputMode,
        width: meta.width,
        height: meta.height
      });
      outputPaths.push(framePath);
    }
  }

  let lastError;
  const lastPath = path.join(cacheFolder, `${base}_Last.jpg`);
  for (const candidate of lastFallbacks) {
    try {
      await extractFrame({
        videoPath,
        seconds: candidate,
        outputPath: lastPath,
        outputMode,
        width: meta.width,
        height: meta.height
      });
      outputPaths.push(lastPath);
      return { outputPaths, lastFrameFailed: false };
    } catch (err) {
      lastError = err;
    }
  }

  return {
    outputPaths,
    lastFrameFailed: true,
    lastFrameError: lastError instanceof Error ? lastError.message : "unknown"
  };
}

async function moveCached(files, destinationFolder) {
  await ensureDir(destinationFolder);

  let saved = 0;
  for (const filePath of files) {
    const fileName = path.basename(filePath);
    const destination = uniquePath(destinationFolder, fileName);
    await fs.copyFile(filePath, destination);
    saved += 1;
  }

  return saved;
}

async function processVideos(payload, onProgress) {
  const {
    videos = [],
    outputFolder,
    exportFiveFrames = false,
    outputMode = "match-source"
  } = payload || {};

  const mp4Videos = videos.filter((video) => path.extname(video).toLowerCase() === ".mp4");
  if (mp4Videos.length === 0) {
    throw new Error("No supported videos found. Drop .mp4 files.");
  }

  if (!outputFolder) {
    throw new Error("Output folder is required.");
  }

  const cacheFolder = await fs.mkdtemp(path.join(os.tmpdir(), "flstill-"));

  const files = [];
  const lastFrameFailures = [];

  try {
    for (let i = 0; i < mp4Videos.length; i += 1) {
      const videoPath = mp4Videos[i];
      const result = await processSingleVideo({
        videoPath,
        cacheFolder,
        exportFiveFrames,
        outputMode
      });

      files.push(...result.outputPaths);
      if (result.lastFrameFailed) {
        lastFrameFailures.push(path.basename(videoPath));
      }

      if (onProgress) {
        onProgress({
          processed: i + 1,
          total: mp4Videos.length,
          ratio: (i + 1) / mp4Videos.length,
          currentFile: path.basename(videoPath)
        });
      }
    }

    if (files.length === 0) {
      throw new Error("No frames were generated.");
    }

    const savedCount = await moveCached(files, outputFolder);

    return {
      savedCount,
      outputFolder,
      lastFrameFailures
    };
  } finally {
    await fs.rm(cacheFolder, { recursive: true, force: true });
  }
}

function nextCustomFramePath(videoPath, outputFolder) {
  const base = path.basename(videoPath, path.extname(videoPath));
  let index = 1;

  while (true) {
    const fileName = `${base}_Frame${index}.jpg`;
    const candidate = path.join(outputFolder, fileName);
    if (!fsSync.existsSync(candidate)) {
      return candidate;
    }
    index += 1;
  }
}

async function captureFrame(payload) {
  const {
    videoPath,
    outputFolder,
    seconds,
    outputMode = "match-source"
  } = payload || {};

  assertMp4(videoPath);
  if (!outputFolder) {
    throw new Error("Output folder is required.");
  }

  await ensureDir(outputFolder);

  const meta = await probeVideo(videoPath);
  const outputPath = nextCustomFramePath(videoPath, outputFolder);

  await extractFrame({
    videoPath,
    seconds: Math.max(0, parseNumber(seconds, 0)),
    outputPath,
    outputMode,
    width: meta.width,
    height: meta.height,
    accurateSeek: true
  });

  return {
    outputPath,
    fileName: path.basename(outputPath)
  };
}

module.exports = {
  probeVideo,
  processVideos,
  captureFrame
};
