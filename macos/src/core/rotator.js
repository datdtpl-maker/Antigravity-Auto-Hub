const fs = require('fs');
const path = require('path');
const {
  ACCOUNTS_DIR,
  ACTIVE_FILE,
  getHubConfig,
  readRotationState,
  setRotationState,
  writeAtomicText,
  writeRotatorLog,
  listAccountFiles
} = require('./storage');
const { getStoredCredential, setStoredCredential, getRefreshToken } = require('./keychain');
const { getFreshToken, getCredentialEmail } = require('./oauth');
const { getAccountQuotaInfo, getAllAccountsQuota, getSelectedModelQuota } = require('./quota');
const {
  getRuntimeIdentity,
  getRuntimeSelectedModel,
  restartAntigravityRuntime,
  waitAntigravityIdentity
} = require('./runtimeBridge');

let switchInProgress = false;
let notifierCallback = null;

function setNotifier(fn) {
  notifierCallback = fn;
}

function notifyUser(message) {
  const cfg = getHubConfig();
  if (cfg.EnableNotifications && typeof notifierCallback === 'function') {
    try { notifierCallback('Antigravity Auto-Hub', message); } catch { /* ignore */ }
  }
}

async function repairRotationState() {
  if (switchInProgress) return false;
  const state = readRotationState();
  if (!['Switching', 'NeedsAttention', 'Prepared'].includes(state.Status)) return true;
  try {
    const runtime = await getRuntimeIdentity();
    if (!runtime) return false;
    const raw = getStoredCredential();
    if (!raw) return false;
    const storedEmail = await getCredentialEmail(raw);
    if (storedEmail !== runtime.Email) return false;
    const storedRt = getRefreshToken(JSON.parse(raw));
    let matchedName = '';
    for (const file of listAccountFiles()) {
      try {
        const saved = JSON.parse(fs.readFileSync(file, 'utf8'));
        if (getRefreshToken(saved) === storedRt) {
          matchedName = path.basename(file, '.json');
          break;
        }
      } catch { /* ignore */ }
    }
    if (matchedName) {
      setRotationState('Verified', matchedName, runtime.Email, state.UpdatedAt || new Date().toISOString());
      writeAtomicText(ACTIVE_FILE, matchedName, 0o600);
      return true;
    }
  } catch { /* ignore */ }
  return false;
}

async function switchActiveAccount(targetAccountName, options = {}) {
  const { manual = false, reason = '', expectedEmail = '', notify = false } = options;
  if (switchInProgress) return { ok: false, message: 'Đang thực hiện chuyển tài khoản khác.' };
  switchInProgress = true;
  let oldCredential = null;
  let oldEmail = '';
  let written = false;

  try {
    const cfg = getHubConfig();
    const threshold = cfg.MinQuotaPercent / 100.0;
    let state = readRotationState();
    if (['Switching', 'NeedsAttention'].includes(state.Status)) {
      if (!(await repairRotationState())) {
        throw new Error('Lần chuyển trước chưa xác minh; tự động xoay đang tạm dừng.');
      }
      state = readRotationState();
    }
    if (!manual && state.UpdatedAt) {
      const elapsed = (Date.now() - new Date(state.UpdatedAt).getTime()) / 1000;
      if (elapsed < cfg.CooldownSeconds) {
        throw new Error('Đang trong thời gian nghỉ (Cooldown) giữa 2 lần chuyển.');
      }
    }
    if (!/^[a-zA-Z0-9_.@-]+$/.test(targetAccountName) || targetAccountName === '.' || targetAccountName === '..') {
      throw new Error('Tên tài khoản không hợp lệ.');
    }
    const source = path.join(ACCOUNTS_DIR, `${targetAccountName}.json`);
    if (!fs.existsSync(source)) throw new Error('Không tìm thấy tệp tài khoản đích.');

    const runtime = await getRuntimeIdentity();
    if (!manual && expectedEmail && runtime && runtime.Email !== expectedEmail) {
      throw new Error('Tài khoản đang hoạt động đã thay đổi.');
    }
    if (!manual && runtime && !runtime.Idle) {
      throw new Error('IDE đang chạy tác vụ; hoãn chuyển để tránh gián đoạn.');
    }

    const quota = await getAccountQuotaInfo(source, true);
    if (!quota.Success) throw new Error('Không đọc được quota của tài khoản đích.');
    if (!manual && quota.Gemini5H <= threshold) {
      throw new Error('Quota 5 giờ của tài khoản đích không đủ ngưỡng.');
    }
    if (runtime && runtime.Email === quota.Email) {
      return { ok: true, message: `Đang dùng sẵn tài khoản [${targetAccountName}].` };
    }

    const fresh = await getFreshToken(JSON.parse(fs.readFileSync(source, 'utf8')));
    oldCredential = getStoredCredential();
    if (runtime) oldEmail = runtime.Email;

    setRotationState('Switching', targetAccountName, quota.Email);
    setStoredCredential(JSON.stringify(fresh));
    written = true;

    if (runtime) {
      const prevPids = runtime.Runtimes.map((r) => r.ProcessId);
      for (const srv of runtime.Runtimes) {
        restartAntigravityRuntime(srv, manual);
      }
      const verified = await waitAntigravityIdentity(quota.Email, prevPids, 40);
      if (!verified) throw new Error('Chưa xác minh được tài khoản mới trong IDE.');
      setRotationState('Verified', targetAccountName, quota.Email);
      writeAtomicText(ACTIVE_FILE, targetAccountName, 0o600);
      writeRotatorLog(`Verified IDE account: [${targetAccountName}] (${reason || (manual ? 'Manual' : 'Auto')}).`);
      const msg = `Đã xác minh tài khoản IDE: [${targetAccountName}]`;
      if (notify) notifyUser(msg);
      return { ok: true, message: msg };
    } else {
      setRotationState('Prepared', targetAccountName, quota.Email);
      writeAtomicText(ACTIVE_FILE, targetAccountName, 0o600);
      writeRotatorLog(`Account [${targetAccountName}] prepared for next IDE launch (${reason || 'CLI/Manual'}).`);
      const msg = `Đã chuẩn bị tài khoản cho lần mở IDE tiếp theo: [${targetAccountName}]`;
      if (notify) notifyUser(msg);
      return { ok: true, message: msg };
    }
  } catch (err) {
    if (written && oldCredential) {
      try { setStoredCredential(oldCredential); } catch { /* ignore */ }
      setRotationState('NeedsAttention', '', oldEmail);
      writeRotatorLog(`Switch unverified; rolled back credential. Error: ${err.message}`);
    } else {
      writeRotatorLog(`Switch deferred: ${err.message}`);
    }
    if (notify) notifyUser(err.message);
    return { ok: false, message: err.message };
  } finally {
    switchInProgress = false;
  }
}

async function invokeAutoRotationCheck() {
  const cfg = getHubConfig();
  if (!cfg.AutoRotationEnabled) return { status: 'Paused' };
  const threshold = cfg.MinQuotaPercent / 100.0;

  let state = readRotationState();
  if (['Switching', 'NeedsAttention'].includes(state.Status)) {
    if (!(await repairRotationState())) {
      writeRotatorLog('Rotation paused: previous switch requires verification.');
      return { status: 'NeedsAttention' };
    }
    state = readRotationState();
  }
  if (state.UpdatedAt) {
    const elapsed = (Date.now() - new Date(state.UpdatedAt).getTime()) / 1000;
    if (elapsed < cfg.CooldownSeconds) return { status: 'Cooldown' };
  }

  let runtime = null;
  try {
    runtime = await getRuntimeIdentity();
  } catch (err) {
    writeRotatorLog(`IDE runtime error: ${err.message}`);
    return { status: 'RuntimeError', message: err.message };
  }

  const accounts = await getAllAccountsQuota(true);

  // CLI mode when IDE is closed
  if (!runtime) {
    if (!cfg.CliRotationEnabled) return { status: 'IdeClosed' };
    const raw = getStoredCredential();
    if (!raw) return { status: 'NoCredential' };
    const activeEmail = await getCredentialEmail(raw).catch(() => '');
    const current = accounts.find((a) => a.Email === activeEmail);
    if (!current || !current.Success) return { status: 'UnknownQuota' };
    writeRotatorLog(`CLI active [${current.AccountName}]: Gemini5H=${(current.Gemini5H * 100).toFixed(1)}% (threshold=${cfg.MinQuotaPercent}%).`);
    if (current.Gemini5H >= threshold) return { status: 'Healthy' };
    const best = accounts
      .filter((a) => a.AccountName !== current.AccountName && a.Success && a.Gemini5H > threshold)
      .sort((a, b) => b.Gemini5H - a.Gemini5H)[0];
    if (!best) {
      writeRotatorLog('CLI mode: no healthy account available; waiting for quota reset.');
      return { status: 'NoTarget' };
    }
    return switchActiveAccount(best.AccountName, {
      manual: false,
      reason: `CLI Gemini 5h below ${cfg.MinQuotaPercent}%`,
      notify: true
    });
  }

  const selectedModel = getRuntimeSelectedModel();
  const current = accounts.find((a) => a.Email === runtime.Email);
  if (!current || !current.Success) {
    writeRotatorLog('Active quota unknown; no rotation.');
    return { status: 'UnknownQuota' };
  }

  const currentModelQuota = selectedModel ? getSelectedModelQuota(current, selectedModel) : { Known: false, Remaining: -1 };
  const g5Text = current.Gemini5H >= 0 ? `${(current.Gemini5H * 100).toFixed(1)}%` : 'N/A';
  const mText = currentModelQuota.Known ? `${(currentModelQuota.Remaining * 100).toFixed(1)}%` : 'N/A';
  writeRotatorLog(`Active [${current.AccountName}]: Gemini5H=${g5Text}, model=${mText} (threshold=${cfg.MinQuotaPercent}%).`);

  const low5h = current.Gemini5H >= 0 && current.Gemini5H < threshold;
  const lowModel = currentModelQuota.Known && currentModelQuota.Remaining < threshold;
  if (!low5h && !lowModel) return { status: 'Healthy' };

  if (!runtime.Idle) {
    writeRotatorLog('Low quota; waiting for running agents to finish.');
    return { status: 'Busy' };
  }

  // Prefer account with both Selected Model & Gemini 5h > threshold; fallback to highest Gemini 5h > threshold
  let best = null;
  if (selectedModel) {
    best = accounts
      .filter((a) => a.Email !== runtime.Email && a.Success && a.Gemini5H > threshold)
      .map((a) => ({ acc: a, mq: getSelectedModelQuota(a, selectedModel) }))
      .filter((x) => x.mq.Known && x.mq.Remaining > threshold)
      .sort((a, b) => Math.min(b.mq.Remaining, b.acc.Gemini5H) - Math.min(a.mq.Remaining, a.acc.Gemini5H))[0]?.acc || null;
  }
  if (!best && low5h) {
    best = accounts
      .filter((a) => a.Email !== runtime.Email && a.Success && a.Gemini5H > threshold)
      .sort((a, b) => b.Gemini5H - a.Gemini5H)[0] || null;
  }
  if (!best) {
    writeRotatorLog('No healthy account available; waiting for quota reset.');
    return { status: 'NoTarget' };
  }

  const reason = low5h
    ? `Gemini 5h quota below ${cfg.MinQuotaPercent}%`
    : `Selected model below ${cfg.MinQuotaPercent}%`;
  return switchActiveAccount(best.AccountName, {
    manual: false,
    reason,
    expectedEmail: runtime.Email,
    notify: true
  });
}

module.exports = {
  setNotifier,
  repairRotationState,
  switchActiveAccount,
  invokeAutoRotationCheck
};
