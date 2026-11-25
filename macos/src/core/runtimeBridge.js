const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');
const { getStoredCredential, getRefreshToken } = require('./keychain');
const { getCredentialEmail } = require('./oauth');
const { convertToModelDisplayName } = require('./quota');

let cachedStoredRt = '';
let cachedStoredEmail = '';

async function getStoredRuntimeEmail() {
  const raw = getStoredCredential();
  if (!raw) return '';
  let rt = '';
  try {
    rt = getRefreshToken(JSON.parse(raw));
  } catch { /* ignore */ }
  if (rt && cachedStoredRt === rt && cachedStoredEmail) {
    return cachedStoredEmail;
  }
  try {
    const email = await getCredentialEmail(raw);
    if (email && rt) {
      cachedStoredRt = rt;
      cachedStoredEmail = email;
    }
    return email;
  } catch {
    return '';
  }
}

function getLatestBrainTranscript() {
  const brainPath = path.join(os.homedir(), '.gemini', 'antigravity', 'brain');
  if (!fs.existsSync(brainPath)) return null;
  let latest = null;
  try {
    for (const entry of fs.readdirSync(brainPath, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const p = path.join(brainPath, entry.name, '.system_generated', 'logs', 'transcript.jsonl');
      if (!fs.existsSync(p)) continue;
      const st = fs.statSync(p);
      if (!latest || st.mtimeMs > latest.mtimeMs) {
        latest = { fullPath: p, mtimeMs: st.mtimeMs };
      }
    }
  } catch { /* ignore */ }
  return latest;
}

function readTailLines(filePath, maxLines = 25) {
  try {
    const stat = fs.statSync(filePath);
    const readSize = Math.min(stat.size, 65536);
    const fd = fs.openSync(filePath, 'r');
    const buf = Buffer.alloc(readSize);
    try {
      fs.readSync(fd, buf, 0, readSize, Math.max(0, stat.size - readSize));
    } finally {
      fs.closeSync(fd);
    }
    return buf.toString('utf8').split(/\r?\n/).filter(Boolean).slice(-maxLines);
  } catch {
    return [];
  }
}

function listMacProcesses() {
  if (process.platform !== 'darwin') return [];
  try {
    const out = execFileSync('/bin/ps', ['-axo', 'pid=,ppid=,command='], {
      encoding: 'utf8',
      maxBuffer: 4 * 1024 * 1024,
      timeout: 4000
    });
    const list = [];
    for (const line of out.split(/\r?\n/)) {
      const m = line.trim().match(/^(\d+)\s+(\d+)\s+(.+)$/);
      if (m) {
        list.push({ pid: Number(m[1]), ppid: Number(m[2]), command: m[3] });
      }
    }
    return list;
  } catch {
    return [];
  }
}

async function getAntigravityRuntime() {
  if (process.platform !== 'darwin') return [];
  const procs = listMacProcesses();
  const servers = procs.filter((p) =>
    /language_server\b/.test(p.command) &&
    /--standalone\b/.test(p.command) &&
    /Antigravity/i.test(p.command)
  );
  if (!servers.length) return [];

  const email = await getStoredRuntimeEmail();
  if (!email) throw new Error('Cannot verify IDE identity; rotation deferred.');

  return servers.map((s) => ({
    ProcessId: s.pid,
    ParentProcessId: s.ppid,
    Command: s.command,
    Email: email,
    NoCsrfBridge: true
  }));
}

function testRuntimeIdle() {
  const latest = getLatestBrainTranscript();
  if (!latest) return true;
  const ageSec = (Date.now() - latest.mtimeMs) / 1000;
  if (ageSec >= 15) return true;
  const lines = readTailLines(latest.fullPath, 2);
  if (lines.length) {
    try {
      const item = JSON.parse(lines[lines.length - 1]);
      if (item.type === 'PLANNER_RESPONSE' && item.status === 'DONE' &&
          (!Array.isArray(item.tool_calls) || item.tool_calls.length === 0)) {
        return true;
      }
    } catch { /* ignore */ }
  }
  return false;
}

async function getRuntimeIdentity() {
  const runtimes = await getAntigravityRuntime();
  if (!runtimes.length) return null;
  const emails = [...new Set(runtimes.map((r) => r.Email))];
  if (emails.length !== 1) throw new Error('Multiple IDE identities detected; rotation deferred.');
  return {
    Email: emails[0],
    Idle: testRuntimeIdle(),
    Runtimes: runtimes
  };
}

function getRuntimeSelectedModel() {
  const latest = getLatestBrainTranscript();
  if (!latest) return '';
  const lines = readTailLines(latest.fullPath, 25);
  for (let i = lines.length - 1; i >= 0; i--) {
    try {
      const item = JSON.parse(lines[i]);
      if (item.model) return convertToModelDisplayName(String(item.model));
    } catch { /* ignore */ }
  }
  return '';
}

function restartAntigravityRuntime(runtime, force = false) {
  if (!force && !testRuntimeIdle()) {
    throw new Error('An agent became active; switch deferred.');
  }
  // Antigravity.app supervises its child language_server and auto-respawns it with the new credential.
  process.kill(runtime.ProcessId, 'SIGTERM');
}

async function waitAntigravityIdentity(expectedEmail, previousPids = [], timeoutSeconds = 40) {
  const deadline = Date.now() + timeoutSeconds * 1000;
  const prevSet = new Set(previousPids);
  cachedStoredRt = '';
  cachedStoredEmail = '';
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 2000));
    try {
      const runtimes = await getAntigravityRuntime();
      if (runtimes.length && runtimes.every((r) => r.Email === expectedEmail)) {
        if (!prevSet.size || runtimes.every((r) => !prevSet.has(r.ProcessId))) {
          return true;
        }
      }
    } catch { /* keep polling */ }
  }
  return false;
}

module.exports = {
  getStoredRuntimeEmail,
  getLatestBrainTranscript,
  getAntigravityRuntime,
  testRuntimeIdle,
  getRuntimeIdentity,
  getRuntimeSelectedModel,
  restartAntigravityRuntime,
  waitAntigravityIdentity
};
