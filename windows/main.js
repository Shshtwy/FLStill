const { app, BrowserWindow, dialog, ipcMain } = require("electron");
const path = require("path");
const processor = require("./src/processor");

function createWindow() {
  const win = new BrowserWindow({
    width: 1100,
    height: 760,
    minWidth: 780,
    minHeight: 560,
    title: "FLStill",
    backgroundColor: "#232323",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  win.loadFile(path.join(__dirname, "renderer", "index.html"));
}

app.whenReady().then(() => {
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

ipcMain.handle("choose-folder", async () => {
  const result = await dialog.showOpenDialog({
    title: "Choose Destination Folder",
    properties: ["openDirectory", "createDirectory"]
  });

  if (result.canceled || result.filePaths.length === 0) {
    return null;
  }

  return result.filePaths[0];
});

ipcMain.handle("toggle-always-on-top", () => {
  const win = BrowserWindow.getFocusedWindow();
  if (!win) {
    return false;
  }

  const next = !win.isAlwaysOnTop();
  win.setAlwaysOnTop(next, "screen-saver");
  return next;
});

ipcMain.handle("get-always-on-top", () => {
  const win = BrowserWindow.getFocusedWindow();
  return Boolean(win && win.isAlwaysOnTop());
});

ipcMain.handle("probe-video", async (_event, videoPath) => {
  return processor.probeVideo(videoPath);
});

ipcMain.handle("process-videos", async (event, payload) => {
  const result = await processor.processVideos(payload, (progress) => {
    event.sender.send("process-progress", progress);
  });

  return result;
});

ipcMain.handle("capture-frame", async (_event, payload) => {
  return processor.captureFrame(payload);
});
