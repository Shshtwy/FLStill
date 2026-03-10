const state = {
  useDefaultFolder: false,
  defaultFolder: null,
  exportFiveFrames: false,
  useCustomCapture: false,
  outputMode: "match-source",
  isProcessing: false,
  previewVideoPath: null,
  previewDuration: 1,
  previewFrameDuration: 1 / 30,
  isAlwaysOnTop: false
};

const els = {
  useDefaultFolder: document.getElementById("useDefaultFolder"),
  exportFiveFrames: document.getElementById("exportFiveFrames"),
  useCustomCapture: document.getElementById("useCustomCapture"),
  setFolder: document.getElementById("setFolder"),
  toggleTop: document.getElementById("toggleTop"),
  outputMode: document.getElementById("outputMode"),
  dropZone: document.getElementById("dropZone"),
  defaultMessage: document.getElementById("defaultMessage"),
  customBlock: document.getElementById("customBlock"),
  previewVideo: document.getElementById("previewVideo"),
  timeSlider: document.getElementById("timeSlider"),
  timeNow: document.getElementById("timeNow"),
  timeDuration: document.getElementById("timeDuration"),
  captureFrame: document.getElementById("captureFrame"),
  status: document.getElementById("status"),
  error: document.getElementById("error"),
  progress: document.getElementById("progress")
};

function setStatus(text) {
  els.status.textContent = text;
}

function setError(text = "") {
  els.error.textContent = text;
}

function setProgress(value) {
  els.progress.value = Math.max(0, Math.min(1, value));
}

function formatTime(seconds) {
  const safe = Math.max(0, Math.floor(seconds));
  const m = Math.floor(safe / 60);
  const s = safe % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function updateModeButtons() {
  els.outputMode.querySelectorAll("button").forEach((button) => {
    button.classList.toggle("active", button.dataset.mode === state.outputMode);
  });
}

function updateTopButton() {
  els.toggleTop.textContent = state.isAlwaysOnTop ? "Unpin" : "Pin";
}

function setProcessing(isProcessing) {
  state.isProcessing = isProcessing;

  const disabled = isProcessing;
  els.useDefaultFolder.disabled = disabled;
  els.exportFiveFrames.disabled = disabled;
  els.useCustomCapture.disabled = disabled;
  els.setFolder.disabled = disabled;
  els.captureFrame.disabled = disabled;
}

function setCustomMode(enabled) {
  state.useCustomCapture = enabled;
  els.useCustomCapture.checked = enabled;

  els.defaultMessage.classList.toggle("hidden", enabled);
  els.customBlock.classList.toggle("hidden", !enabled);

  if (enabled) {
    setStatus("Custom mode enabled. Drop one .mp4 to preview.");
  } else {
    state.previewVideoPath = null;
    state.previewDuration = 1;
    state.previewFrameDuration = 1 / 30;
    els.previewVideo.removeAttribute("src");
    els.previewVideo.load();
    setStatus("Supports .mp4");
    setError("");
  }
}

function getDroppedMp4Paths(event) {
  const files = Array.from(event.dataTransfer.files || []);
  return files
    .map((file) => {
      const directPath = typeof file.path === "string" ? file.path : "";
      if (directPath) {
        return directPath;
      }

      // Packaged Electron builds can hide File.path; webUtils restores it safely.
      return window.flstill.getPathForFile(file) || "";
    })
    .filter((filePath) => String(filePath || "").toLowerCase().endsWith(".mp4"));
}

async function resolveOutputFolder() {
  if (state.useDefaultFolder && state.defaultFolder) {
    return state.defaultFolder;
  }

  const folder = await window.flstill.chooseFolder();
  if (!folder) {
    return null;
  }

  if (state.useDefaultFolder) {
    state.defaultFolder = folder;
    els.setFolder.textContent = folder;
  }

  return folder;
}

async function loadPreview(videoPath) {
  state.previewVideoPath = videoPath;
  els.previewVideo.src = videoPath;

  const meta = await window.flstill.probeVideo(videoPath);
  state.previewDuration = Math.max(0.001, meta.duration);
  state.previewFrameDuration = Math.max(1 / 120, Number(meta.frameDuration || 1 / 30));
  els.timeSlider.max = String(state.previewDuration);
  els.timeSlider.value = "0";
  els.timeNow.textContent = "0:00";
  els.timeDuration.textContent = formatTime(state.previewDuration);
  setStatus("Scrub and click Capture Frame.");
}

function setPreviewPosition(seconds) {
  const target = Math.max(0, Math.min(state.previewDuration, Number(seconds || 0)));
  els.previewVideo.currentTime = target;
  els.timeSlider.value = String(target);
  els.timeNow.textContent = formatTime(target);
}

async function processDrop(event) {
  if (state.isProcessing) {
    return;
  }

  const mp4Paths = getDroppedMp4Paths(event);
  if (mp4Paths.length === 0) {
    setError("Drop .mp4 files only.");
    return;
  }

  setError("");

  if (state.useCustomCapture) {
    await loadPreview(mp4Paths[0]);
    if (mp4Paths.length > 1) {
      setError("Custom mode uses the first dropped .mp4.");
    }
    return;
  }

  const outputFolder = await resolveOutputFolder();
  if (!outputFolder) {
    setStatus("Save cancelled.");
    return;
  }

  setProcessing(true);
  setStatus(`Processing ${mp4Paths.length} video(s)...`);
  setProgress(0);

  try {
    const result = await window.flstill.processVideos({
      videos: mp4Paths,
      outputFolder,
      exportFiveFrames: state.exportFiveFrames,
      outputMode: state.outputMode
    });

    setProgress(1);
    setStatus(`Saved ${result.savedCount} image(s) to ${result.outputFolder}.`);
    if (result.lastFrameFailures && result.lastFrameFailures.length > 0) {
      setError(`Couldn't export last frame of: ${result.lastFrameFailures.join(", ")}.`);
    }
  } catch (err) {
    setProgress(0);
    setStatus("Processing failed.");
    setError(err && err.message ? err.message : String(err));
  } finally {
    setProcessing(false);
  }
}

async function captureCurrentFrame() {
  if (state.isProcessing || !state.previewVideoPath) {
    return;
  }

  const outputFolder = await resolveOutputFolder();
  if (!outputFolder) {
    setStatus("Capture cancelled.");
    return;
  }

  setProcessing(true);
  setError("");

  try {
    const seconds = Number(els.previewVideo.currentTime || els.timeSlider.value || "0");
    const result = await window.flstill.captureFrame({
      videoPath: state.previewVideoPath,
      outputFolder,
      seconds,
      outputMode: state.outputMode
    });

    setStatus(`Saved ${result.fileName}.`);
  } catch (err) {
    setStatus("Capture failed.");
    setError(err && err.message ? err.message : String(err));
  } finally {
    setProcessing(false);
  }
}

els.outputMode.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-mode]");
  if (!button || state.isProcessing) {
    return;
  }

  state.outputMode = button.dataset.mode;
  updateModeButtons();
});

els.useDefaultFolder.addEventListener("change", async () => {
  if (state.isProcessing) {
    return;
  }

  state.useDefaultFolder = els.useDefaultFolder.checked;
  if (!state.useDefaultFolder) {
    state.defaultFolder = null;
    els.setFolder.textContent = "Choose Folder";
    setStatus("Supports .mp4");
    return;
  }

  const folder = await window.flstill.chooseFolder();
  if (!folder) {
    state.useDefaultFolder = false;
    els.useDefaultFolder.checked = false;
    setStatus("Default folder not set.");
    return;
  }

  state.defaultFolder = folder;
  els.setFolder.textContent = folder;
  setStatus(`Default folder: ${folder}`);
});

els.exportFiveFrames.addEventListener("change", () => {
  state.exportFiveFrames = els.exportFiveFrames.checked;
});

els.useCustomCapture.addEventListener("change", () => {
  if (state.isProcessing) {
    return;
  }

  setCustomMode(els.useCustomCapture.checked);
});

els.setFolder.addEventListener("click", async () => {
  if (state.isProcessing) {
    return;
  }

  const folder = await window.flstill.chooseFolder();
  if (!folder) {
    return;
  }

  state.defaultFolder = folder;
  state.useDefaultFolder = true;
  els.useDefaultFolder.checked = true;
  els.setFolder.textContent = folder;
  setStatus(`Default folder: ${folder}`);
});

els.toggleTop.addEventListener("click", async () => {
  state.isAlwaysOnTop = await window.flstill.toggleAlwaysOnTop();
  updateTopButton();
});

els.captureFrame.addEventListener("click", captureCurrentFrame);

els.timeSlider.addEventListener("input", () => {
  const seconds = Number(els.timeSlider.value || "0");
  setPreviewPosition(seconds);
});

els.previewVideo.addEventListener("timeupdate", () => {
  if (state.isProcessing) {
    return;
  }

  const now = els.previewVideo.currentTime;
  els.timeSlider.value = String(now);
  els.timeNow.textContent = formatTime(now);
});

document.addEventListener("keydown", (event) => {
  if (!state.useCustomCapture || !state.previewVideoPath || state.isProcessing) {
    return;
  }

  if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") {
    return;
  }

  event.preventDefault();
  const direction = event.key === "ArrowRight" ? 1 : -1;
  const step = state.previewFrameDuration;
  const now = Number(els.previewVideo.currentTime || 0);
  setPreviewPosition(now + direction * step);
});

["dragenter", "dragover"].forEach((name) => {
  els.dropZone.addEventListener(name, (event) => {
    event.preventDefault();
    els.dropZone.classList.add("targeted");
  });
});

["dragleave", "drop"].forEach((name) => {
  els.dropZone.addEventListener(name, (event) => {
    event.preventDefault();
    if (name === "drop") {
      processDrop(event).catch((err) => {
        setStatus("Processing failed.");
        setError(err && err.message ? err.message : String(err));
      });
    }
    els.dropZone.classList.remove("targeted");
  });
});

window.flstill.onProcessProgress((progress) => {
  const ratio = Number(progress && progress.ratio ? progress.ratio : 0);
  setProgress(ratio);
  if (progress && progress.currentFile) {
    setStatus(`Extracting: ${progress.currentFile}`);
  }
});

(async () => {
  state.isAlwaysOnTop = await window.flstill.getAlwaysOnTop();
  updateTopButton();
  updateModeButtons();
  setStatus("Supports .mp4");
})();
