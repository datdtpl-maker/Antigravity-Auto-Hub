const fs = require('fs');
const path = require('path');
const { app, BrowserWindow, ipcMain, Tray, Menu, Notification, shell, nativeImage } = require('electron');

const {
  BASE_DIR,
  ACCOUNTS_DIR,
  ensureDirs,
  getHubConfig,
  saveHubConfig,
  readRotationState,
  readRecentLogs,
  writeRotatorLog
} = require('./core/storage');
const { getAllAccountsQuota, getFamilyRing, getSelectedModelQuota } = require('./core/quota');
const { getRuntimeIdentity, getRuntimeSelectedModel } = require('./core/runtimeBridge');
const { setNotifier, switchActiveAccount, invokeAutoRotationCheck } = require('./core/rotator');
const { saveCurrentAccount, startInteractiveAccountLogin } = require('./core/accountLogin');

const GITHUB_RELEASES_API = 'https://api.github.com/repos/datdtpl-maker/Antigravity-Auto-Hub/releases/latest';
const GITHUB_RELEASES_URL = 'https://github.com/datdtpl-maker/Antigravity-Auto-Hub/releases';

let mainWindow = null;
let tray = null;
let daemonTimer = null;
let daemonBusy = false;
let isQuitting = false;

function showNativeNotification(title, body) {
  if (Notification.isSupported()) {
    new Notification({ title, body }).show();
  }
}

setNotifier(showNativeNotification);

function applyLoginItem(enabled) {
  if (process.platform === 'darwin' || process.platform === 'win32') {
    try {
      app.setLoginItemSettings({ openAtLogin: Boolean(enabled), openAsHidden: true });
    } catch { /* ignore in dev */ }
  }
}

async function buildSnapshot() {
  ensureDirs();
  const cfg = getHubConfig();
  const state = readRotationState();
  let runtime = null;
  let runtimeError = '';
  let selectedModel = '';

  try {
    runtime = await getRuntimeIdentity();
    if (runtime) selectedModel = getRuntimeSelectedModel();
  } catch (err) {
    runtimeError = err.message || 'Không kết nối được IDE';
  }

  const accountsRaw = await getAllAccountsQuota(true);
  const threshold = cfg.MinQuotaPercent / 100.0;
  const activeEmail = runtime ? runtime.Email : '';

  const accounts = accountsRaw.map((a) => {
    const active = Boolean(activeEmail && a.Email && a.Email.toLowerCase() === activeEmail.toLowerCase());
    const known = Boolean(a.Success);
    const modelQuota = selectedModel ? getSelectedModelQuota(a, selectedModel) : null;
    const ready = selectedModel
      ? Boolean(modelQuota && modelQuota.Known && modelQuota.Remaining > threshold)
      : Boolean(known && a.Gemini5H > threshold && a.GeminiWeekly > 0.10);
    const stateKey = ((selectedModel && (!modelQuota || !modelQuota.Known)) || !known)
      ? 'Unknown'
      : (ready ? 'Ready' : 'Low');
    const verify = Boolean(a.VerificationUrl && a.ErrorCode === 'AccountVerificationRequired');

    return {
      AccountName: a.AccountName,
      Email: a.Email,
      Plan: a.Plan,
      IsActive: active,
      StateKey: stateKey,
      Verify: verify,
      VerificationUrl: a.VerificationUrl || '',
      Gemini5H: a.Gemini5H,
      GeminiWeekly: a.GeminiWeekly,
      ArgonWeekly: a.ArgonWeekly,
      ArgonStatus: a.ArgonStatus,
      CheckedAt: a.CheckedAt,
      QuotaGroups: a.QuotaGroups,
      ModelQuotas: a.ModelQuotas,
      Rings: {
        Flash: getFamilyRing(a, 'Flash'),
        Neon: getFamilyRing(a, 'Neon'),
        Argon: getFamilyRing(a, 'Argon'),
        Hydrogen: getFamilyRing(a, 'Hydrogen'),
        Carbon: getFamilyRing(a, 'Carbon'),
        Opus: getFamilyRing(a, 'Opus'),
        Sonnet: getFamilyRing(a, 'Sonnet'),
        GptOss: getFamilyRing(a, 'GptOss')
      }
    };
  }).sort((a, b) => {
    if (a.IsActive !== b.IsActive) return a.IsActive ? -1 : 1;
    return a.AccountName.localeCompare(b.AccountName);
  });

  const logs = readRecentLogs(200);
  const verifiedRotations = logs.filter((l) => l.type === 'Confirmed').length;

  return {
    at: new Date().toISOString(),
    baseDir: BASE_DIR,
    version: app.getVersion(),
    config: cfg,
    state,
    connected: Boolean(runtime),
    idle: runtime ? Boolean(runtime.Idle) : true,
    activeEmail,
    selectedModel,
    runtimeError,
    daemonRunning: Boolean(daemonTimer),
    accounts,
    logs,
    verifiedRotations
  };
}

function updateTrayMenu() {
  if (!tray) return;
  const cfg = getHubConfig();
  const menu = Menu.buildFromTemplate([
    { label: 'Mở Antigravity Auto-Hub', click: () => { if (mainWindow) { mainWindow.show(); mainWindow.focus(); } } },
    { label: 'Quét quota ngay', click: () => { if (mainWindow) mainWindow.webContents.send('trigger-refresh'); } },
    {
      label: cfg.AutoRotationEnabled ? 'Tạm dừng xoay tự động' : 'Bật xoay tự động',
      click: () => {
        saveHubConfig({ AutoRotationEnabled: !cfg.AutoRotationEnabled });
        updateTrayMenu();
        if (mainWindow) mainWindow.webContents.send('trigger-refresh');
      }
    },
    { type: 'separator' },
    { label: 'Thoát hẳn', click: () => { isQuitting = true; app.quit(); } }
  ]);
  tray.setContextMenu(menu);
}

function startDaemonLoop() {
  if (daemonTimer) return;
  const cfg = getHubConfig();
  writeRotatorLog('Daemon started (macOS Electron background loop; interval 25s).');
  writeRotatorLog(`Automatic rotation: Gemini 5h or selected model below ${cfg.MinQuotaPercent}%; target above ${cfg.MinQuotaPercent}%; idle only; cooldown ${cfg.CooldownSeconds}s.`);
  const tick = async () => {
    if (daemonBusy) return;
    daemonBusy = true;
    try {
      await invokeAutoRotationCheck();
      if (mainWindow && !mainWindow.isDestroyed() && mainWindow.isVisible()) {
        mainWindow.webContents.send('daemon-tick');
      }
    } catch (err) {
      writeRotatorLog(`Daemon scan failed: ${err.message}`);
    } finally {
      daemonBusy = false;
    }
  };
  daemonTimer = setInterval(tick, 25000);
  setTimeout(tick, 3000);
}

function createWindow() {
  const iconPath = path.join(__dirname, '..', 'build', 'icon.png');
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 1000,
    minHeight: 680,
    title: 'Antigravity Auto-Hub',
    icon: fs.existsSync(iconPath) ? iconPath : undefined,
    backgroundColor: '#F8FAFC',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  mainWindow.on('close', (e) => {
    if (!isQuitting) {
      e.preventDefault();
      mainWindow.hide();
      showNativeNotification('Antigravity Auto-Hub', 'Ứng dụng vẫn đang chạy ngầm trên thanh Menu Bar để tự động xoay tài khoản.');
    }
  });
}

function createTray() {
  const iconPath = path.join(__dirname, '..', 'build', 'icon.png');
  let icon = fs.existsSync(iconPath) ? nativeImage.createFromPath(iconPath).resize({ width: 18, height: 18 }) : nativeImage.createEmpty();
  tray = new Tray(icon);
  tray.setToolTip('Antigravity Auto-Hub');
  tray.on('click', () => {
    if (mainWindow) {
      if (mainWindow.isVisible()) mainWindow.focus();
      else mainWindow.show();
    }
  });
  updateTrayMenu();
}

function registerIpc() {
  ipcMain.handle('hub:getSnapshot', () => buildSnapshot());

  ipcMain.handle('hub:saveConfig', (_e, partial) => {
    const saved = saveHubConfig(partial);
    applyLoginItem(saved.LaunchAtLogin);
    updateTrayMenu();
    return saved;
  });

  ipcMain.handle('hub:switchAccount', async (_e, accountName) => {
    return switchActiveAccount(accountName, { manual: true, reason: 'Manual switch', notify: true });
  });

  ipcMain.handle('hub:deleteAccount', (_e, accountName) => {
    if (!/^[a-zA-Z0-9_.@-]+$/.test(accountName)) return { ok: false, message: 'Tên tài khoản không hợp lệ.' };
    const p = path.join(ACCOUNTS_DIR, `${accountName}.json`);
    if (fs.existsSync(p)) fs.unlinkSync(p);
    return { ok: true };
  });

  ipcMain.handle('hub:saveCurrent', async () => {
    try {
      const res = await saveCurrentAccount();
      return { ok: true, ...res };
    } catch (err) {
      return { ok: false, message: err.message };
    }
  });

  ipcMain.handle('hub:addAccount', async () => {
    try {
      const res = await startInteractiveAccountLogin((url) => shell.openExternal(url));
      return { ok: true, ...res };
    } catch (err) {
      return { ok: false, message: err.message };
    }
  });

  ipcMain.handle('hub:openFolder', () => {
    ensureDirs();
    shell.openPath(BASE_DIR);
    return true;
  });

  ipcMain.handle('hub:openExternal', (_e, url) => {
    if (/^https:\/\//.test(String(url || ''))) shell.openExternal(url);
    return true;
  });

  ipcMain.handle('hub:checkUpdate', async () => {
    try {
      const res = await fetch(GITHUB_RELEASES_API, {
        headers: { 'User-Agent': 'Antigravity-Auto-Hub-macOS' },
        signal: AbortSignal.timeout(10000)
      });
      if (!res.ok) {
        return { ok: true, hasUpdate: false, currentVersion: app.getVersion(), latestVersion: app.getVersion(), url: GITHUB_RELEASES_URL };
      }
      const data = await res.json();
      const latestTag = String(data.tag_name || '').replace(/^v/i, '');
      const current = app.getVersion();
      const hasUpdate = Boolean(latestTag && latestTag !== current);
      if (hasUpdate) {
        showNativeNotification('Antigravity Auto-Hub', `Có phiên bản mới v${latestTag} trên GitHub!`);
      }
      return {
        ok: true,
        hasUpdate,
        currentVersion: current,
        latestVersion: latestTag || current,
        url: data.html_url || GITHUB_RELEASES_URL
      };
    } catch (err) {
      return { ok: false, message: err.message };
    }
  });
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.show();
      mainWindow.focus();
    }
  });

  app.whenReady().then(() => {
    ensureDirs();
    const cfg = getHubConfig();
    applyLoginItem(cfg.LaunchAtLogin);
    registerIpc();
    createWindow();
    createTray();
    startDaemonLoop();

    app.on('activate', () => {
      if (mainWindow) mainWindow.show();
    });
  });

  app.on('before-quit', () => {
    isQuitting = true;
    if (daemonTimer) clearInterval(daemonTimer);
  });
}
