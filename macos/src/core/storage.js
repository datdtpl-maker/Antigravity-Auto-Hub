const fs = require('fs');
const path = require('path');
const os = require('os');

const BASE_DIR = process.env.ANTIGRAVITY_HUB_DIR || path.join(os.homedir(), 'AntigravityAccounts');
const ACCOUNTS_DIR = path.join(BASE_DIR, 'accounts');
const CONFIG_FILE = path.join(BASE_DIR, 'hub-config.json');
const STATE_FILE = path.join(BASE_DIR, 'rotation-state.json');
const ACTIVE_FILE = path.join(BASE_DIR, 'current_active.txt');
const LOG_FILE = path.join(BASE_DIR, 'rotator.log');
const OAUTH_FILE = path.join(BASE_DIR, 'oauth.local.json');
const STANDALONE_TOKEN_PATH = path.join(os.homedir(), '.gemini', 'jetski-standalone-oauth-token');

const DEFAULT_CONFIG = {
  AutoRotationEnabled: true,
  CliRotationEnabled: true,
  MinQuotaPercent: 15,
  CooldownSeconds: 60,
  EnableNotifications: true,
  LaunchAtLogin: true,
  Theme: 'Light'
};

function ensureDirs() {
  fs.mkdirSync(BASE_DIR, { recursive: true });
  fs.mkdirSync(ACCOUNTS_DIR, { recursive: true });
}

function writeAtomicText(filePath, content, mode = 0o600) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmpPath = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(tmpPath, content, { encoding: 'utf8', mode });
  fs.renameSync(tmpPath, filePath);
}

function getHubConfig() {
  ensureDirs();
  const cfg = { ...DEFAULT_CONFIG };
  if (fs.existsSync(CONFIG_FILE)) {
    try {
      const raw = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
      if (typeof raw.AutoRotationEnabled === 'boolean') cfg.AutoRotationEnabled = raw.AutoRotationEnabled;
      if (typeof raw.CliRotationEnabled === 'boolean') cfg.CliRotationEnabled = raw.CliRotationEnabled;
      if (Number.isFinite(Number(raw.MinQuotaPercent))) {
        const pct = Math.round(Number(raw.MinQuotaPercent));
        if (pct >= 5 && pct <= 50) cfg.MinQuotaPercent = pct;
      }
      if (Number.isFinite(Number(raw.CooldownSeconds))) {
        const cd = Math.round(Number(raw.CooldownSeconds));
        if (cd >= 30 && cd <= 600) cfg.CooldownSeconds = cd;
      }
      if (typeof raw.EnableNotifications === 'boolean') cfg.EnableNotifications = raw.EnableNotifications;
      if (typeof raw.LaunchAtLogin === 'boolean') cfg.LaunchAtLogin = raw.LaunchAtLogin;
      if (raw.Theme === 'Light' || raw.Theme === 'Amoled') cfg.Theme = raw.Theme;
    } catch { /* keep defaults */ }
  }
  return cfg;
}

function saveHubConfig(config) {
  ensureDirs();
  const merged = { ...getHubConfig(), ...config };
  writeAtomicText(CONFIG_FILE, JSON.stringify(merged), 0o600);
  return merged;
}

function readRotationState() {
  ensureDirs();
  if (!fs.existsSync(STATE_FILE)) {
    return { Account: '', Status: 'Idle', Email: '', UpdatedAt: '' };
  }
  try {
    const raw = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
    return {
      Account: String(raw.Account || ''),
      Status: String(raw.Status || 'Idle'),
      Email: String(raw.Email || ''),
      UpdatedAt: String(raw.UpdatedAt || '')
    };
  } catch {
    return { Account: '', Status: 'Idle', Email: '', UpdatedAt: '' };
  }
}

function setRotationState(status, account = '', email = '', updatedAt = null) {
  ensureDirs();
  const payload = {
    Account: account || '',
    Status: status || 'Idle',
    Email: email || '',
    UpdatedAt: updatedAt || new Date().toISOString()
  };
  writeAtomicText(STATE_FILE, JSON.stringify(payload), 0o600);
  return payload;
}

function writeRotatorLog(message) {
  ensureDirs();
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const ts = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
  const line = `[${ts}] ${message}\n`;
  try {
    if (fs.existsSync(LOG_FILE) && fs.statSync(LOG_FILE).size > 1048576) {
      const keep = fs.readFileSync(LOG_FILE, 'utf8').split(/\r?\n/).filter(Boolean).slice(-2000);
      writeAtomicText(LOG_FILE, keep.join('\n') + '\n', 0o600);
    }
    fs.appendFileSync(LOG_FILE, line, 'utf8');
  } catch { /* ignore */ }
}

function readRecentLogs(limit = 200) {
  if (!fs.existsSync(LOG_FILE)) return [];
  try {
    const text = fs.readFileSync(LOG_FILE, 'utf8');
    const lines = text.split(/\r?\n/).filter(Boolean).slice(-5000);
    const events = [];
    for (let i = lines.length - 1; i >= 0 && events.length < limit; i--) {
      const m = lines[i].match(/^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]\s*(.+)$/);
      if (!m) continue;
      const msg = m[2];
      let type = 'Info';
      if (/Verified IDE account:/i.test(msg)) type = 'Confirmed';
      else if (/prepared for next IDE launch/i.test(msg)) type = 'Prepared';
      else if (/Switch deferred:|waiting for|Low quota;/i.test(msg)) type = 'Deferred';
      else if (/Switch unverified|failed|paused/i.test(msg)) type = 'Failed';
      else if (/Daemon started/i.test(msg)) type = 'Started';
      else if (/Active \[|CLI active \[/i.test(msg)) continue;
      events.push({ time: m[1], type, detail: msg });
    }
    return events;
  } catch {
    return [];
  }
}

function listAccountFiles() {
  ensureDirs();
  try {
    return fs.readdirSync(ACCOUNTS_DIR)
      .filter((f) => f.endsWith('.json'))
      .sort()
      .map((f) => path.join(ACCOUNTS_DIR, f));
  } catch {
    return [];
  }
}

function sanitizeAccountName(name) {
  return String(name || '').replace(/[^a-zA-Z0-9_.@-]/g, '_').replace(/^\.+$/, 'account');
}

module.exports = {
  BASE_DIR,
  ACCOUNTS_DIR,
  CONFIG_FILE,
  STATE_FILE,
  ACTIVE_FILE,
  LOG_FILE,
  OAUTH_FILE,
  STANDALONE_TOKEN_PATH,
  ensureDirs,
  writeAtomicText,
  getHubConfig,
  saveHubConfig,
  readRotationState,
  setRotationState,
  writeRotatorLog,
  readRecentLogs,
  listAccountFiles,
  sanitizeAccountName
};
