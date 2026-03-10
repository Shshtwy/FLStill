const { contextBridge, ipcRenderer, webUtils } = require("electron");

contextBridge.exposeInMainWorld("flstill", {
  chooseFolder: () => ipcRenderer.invoke("choose-folder"),
  toggleAlwaysOnTop: () => ipcRenderer.invoke("toggle-always-on-top"),
  getAlwaysOnTop: () => ipcRenderer.invoke("get-always-on-top"),
  probeVideo: (videoPath) => ipcRenderer.invoke("probe-video", videoPath),
  processVideos: (payload) => ipcRenderer.invoke("process-videos", payload),
  captureFrame: (payload) => ipcRenderer.invoke("capture-frame", payload),
  getPathForFile: (file) => webUtils.getPathForFile(file),
  onProcessProgress: (callback) => {
    const handler = (_event, payload) => callback(payload);
    ipcRenderer.on("process-progress", handler);
    return () => ipcRenderer.removeListener("process-progress", handler);
  }
});
