const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('hubApi', {
  getSnapshot: () => ipcRenderer.invoke('hub:getSnapshot'),
  saveConfig: (partial) => ipcRenderer.invoke('hub:saveConfig', partial),
  switchAccount: (name) => ipcRenderer.invoke('hub:switchAccount', name),
  deleteAccount: (name) => ipcRenderer.invoke('hub:deleteAccount', name),
  saveCurrent: () => ipcRenderer.invoke('hub:saveCurrent'),
  addAccount: () => ipcRenderer.invoke('hub:addAccount'),
  openFolder: () => ipcRenderer.invoke('hub:openFolder'),
  openExternal: (url) => ipcRenderer.invoke('hub:openExternal', url),
  checkUpdate: () => ipcRenderer.invoke('hub:checkUpdate'),
  onTriggerRefresh: (cb) => ipcRenderer.on('trigger-refresh', () => cb()),
  onDaemonTick: (cb) => ipcRenderer.on('daemon-tick', () => cb())
});
