const fs = require('fs');
const path = require('path');
const { OAUTH_FILE, writeAtomicText } = require('./storage');
const { getStoredCredential, getRefreshToken } = require('./keychain');

const MAC_LS_CANDIDATES = [
  '/Applications/Antigravity.app/Contents/Resources/bin/language_server',
  '/Applications/Antigravity.app/Contents/Resources/app/resources/bin/language_server',
  path.join(process.env.HOME || '', 'Applications/Antigravity.app/Contents/Resources/bin/language_server'),
  path.join(process.env.HOME || '', 'Applications/Antigravity.app/Contents/Resources/app/resources/bin/language_server')
];

let cachedOAuth = null;

function findMacLanguageServer() {
  for (const p of MAC_LS_CANDIDATES) {
    if (p && fs.existsSync(p)) return p;
  }
  return null;
}

function extractOAuthCandidatesFromBinary(binaryPath) {
  if (!binaryPath || !fs.existsSync(binaryPath)) {
    throw new Error('SetupAntigravityMissing');
  }
  const stat = fs.statSync(binaryPath);
  if (stat.size > 512 * 1024 * 1024) throw new Error('SetupOAuthUnsupported');

  const ids = new Set();
  const secrets = new Set();
  const idRe = /[0-9]{6,24}-[a-z0-9]{16,64}\.apps\.googleusercontent\.com/g;
  const secretRe = /GOCSPX-[A-Za-z0-9_-]{28}/g;

  const fd = fs.openSync(binaryPath, 'r');
  const chunkSize = 1024 * 1024;
  const buf = Buffer.alloc(chunkSize);
  let carry = '';
  try {
    let bytesRead;
    while ((bytesRead = fs.readSync(fd, buf, 0, chunkSize, null)) > 0) {
      const text = carry + buf.toString('latin1', 0, bytesRead);
      let m;
      while ((m = idRe.exec(text)) !== null) ids.add(m[0]);
      while ((m = secretRe.exec(text)) !== null) secrets.add(m[0]);
      if (ids.size > 6 || secrets.size > 6) break;
      carry = text.slice(Math.max(0, text.length - 256));
    }
  } finally {
    fs.closeSync(fd);
  }
  if (!ids.size || !secrets.size) throw new Error('SetupOAuthUnsupported');
  return { clientIds: Array.from(ids).sort(), secrets: Array.from(secrets).sort() };
}

async function postTokenRefresh(clientId, clientSecret, refreshToken) {
  const body = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    refresh_token: refreshToken,
    grant_type: 'refresh_token'
  });
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
    signal: AbortSignal.timeout(10000)
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.access_token) {
    const err = new Error(data.error || `HTTP ${res.status}`);
    err.status = res.status;
    err.code = data.error || '';
    throw err;
  }
  return data;
}

function loadSavedOAuth() {
  if (cachedOAuth && cachedOAuth.clientId && cachedOAuth.clientSecret) return cachedOAuth;
  if (process.env.ANTIGRAVITY_GOOGLE_CLIENT_ID && process.env.ANTIGRAVITY_GOOGLE_CLIENT_SECRET) {
    cachedOAuth = {
      clientId: process.env.ANTIGRAVITY_GOOGLE_CLIENT_ID,
      clientSecret: process.env.ANTIGRAVITY_GOOGLE_CLIENT_SECRET
    };
    return cachedOAuth;
  }
  if (fs.existsSync(OAUTH_FILE)) {
    try {
      const raw = JSON.parse(fs.readFileSync(OAUTH_FILE, 'utf8'));
      if (raw.clientId && raw.clientSecret) {
        cachedOAuth = { clientId: String(raw.clientId), clientSecret: String(raw.clientSecret) };
        return cachedOAuth;
      }
    } catch { /* ignore */ }
  }
  return null;
}

async function ensureOAuthConfig(sampleRefreshToken = '') {
  const existing = loadSavedOAuth();
  if (existing) return existing;

  let rt = sampleRefreshToken;
  if (!rt) {
    const rawCred = getStoredCredential();
    if (rawCred) {
      try { rt = getRefreshToken(JSON.parse(rawCred)); } catch { /* ignore */ }
    }
  }
  if (!rt) throw new Error('SetupOAuthLoginRequired');

  const lsPath = findMacLanguageServer();
  const { clientIds, secrets } = extractOAuthCandidatesFromBinary(lsPath);
  for (const cid of clientIds) {
    for (const sec of secrets) {
      try {
        await postTokenRefresh(cid, sec, rt);
        cachedOAuth = { clientId: cid, clientSecret: sec };
        writeAtomicText(OAUTH_FILE, JSON.stringify(cachedOAuth), 0o600);
        return cachedOAuth;
      } catch (e) {
        if (['invalid_client', 'invalid_grant', 'unauthorized_client'].includes(e.code)) continue;
        throw e;
      }
    }
  }
  throw new Error('SetupOAuthNoMatch');
}

async function getFreshToken(tokenObj) {
  const rt = getRefreshToken(tokenObj);
  if (!rt) throw new Error('Refresh token unavailable.');
  const oauth = await ensureOAuthConfig(rt);
  const res = await postTokenRefresh(oauth.clientId, oauth.clientSecret, rt);
  const expiry = new Date(Date.now() + (Number(res.expires_in) || 3600) * 1000).toISOString();
  return {
    token: {
      access_token: res.access_token,
      token_type: 'Bearer',
      refresh_token: rt,
      expiry
    }
  };
}

async function getCredentialEmail(rawJson) {
  if (!rawJson) return '';
  const parsed = typeof rawJson === 'string' ? JSON.parse(rawJson) : rawJson;
  const fresh = await getFreshToken(parsed);
  const res = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
    headers: { Authorization: `Bearer ${fresh.token.access_token}` },
    signal: AbortSignal.timeout(10000)
  });
  if (!res.ok) return '';
  const user = await res.json().catch(() => ({}));
  return String(user.email || '');
}

module.exports = {
  findMacLanguageServer,
  loadSavedOAuth,
  ensureOAuthConfig,
  getFreshToken,
  getCredentialEmail
};
