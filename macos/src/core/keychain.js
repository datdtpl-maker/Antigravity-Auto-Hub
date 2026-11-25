const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { STANDALONE_TOKEN_PATH, writeAtomicText } = require('./storage');

const KEYCHAIN_SERVICES = [
  'jetski-standalone-oauth-token',
  'antigravity-jetski-standalone-oauth-token'
];

function isMac() {
  return process.platform === 'darwin';
}

function readKeychainService(service) {
  if (!isMac()) return null;
  try {
    const out = execFileSync('/usr/bin/security', ['find-generic-password', '-s', service, '-w'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: 4000
    }).trim();
    return out || null;
  } catch {
    return null;
  }
}

function writeKeychainService(service, secret) {
  if (!isMac()) return false;
  try {
    execFileSync('/usr/bin/security', [
      'add-generic-password',
      '-U',
      '-s', service,
      '-a', 'antigravity',
      '-w', secret
    ], {
      stdio: ['ignore', 'ignore', 'ignore'],
      timeout: 4000
    });
    return true;
  } catch {
    return false;
  }
}

function getStoredCredential() {
  // Prefer macOS Keychain first, then standalone file fallback (matches Antigravity macOS behavior)
  for (const svc of KEYCHAIN_SERVICES) {
    const val = readKeychainService(svc);
    if (val) return val;
  }
  if (fs.existsSync(STANDALONE_TOKEN_PATH)) {
    try {
      const text = fs.readFileSync(STANDALONE_TOKEN_PATH, 'utf8').trim();
      if (text) return text;
    } catch { /* ignore */ }
  }
  return null;
}

function setStoredCredential(jsonText) {
  const clean = typeof jsonText === 'string' ? jsonText : JSON.stringify(jsonText);
  // Write to standalone token path (0600)
  fs.mkdirSync(path.dirname(STANDALONE_TOKEN_PATH), { recursive: true });
  writeAtomicText(STANDALONE_TOKEN_PATH, clean, 0o600);
  // Sync into macOS Keychain if running on macOS
  if (isMac()) {
    writeKeychainService(KEYCHAIN_SERVICES[0], clean);
  }
  return true;
}

function getRefreshToken(tokenObj) {
  if (!tokenObj || typeof tokenObj !== 'object') return '';
  if (tokenObj.token && tokenObj.token.refresh_token) return String(tokenObj.token.refresh_token);
  if (tokenObj.refresh_token) return String(tokenObj.refresh_token);
  return '';
}

module.exports = {
  getStoredCredential,
  setStoredCredential,
  getRefreshToken,
  STANDALONE_TOKEN_PATH
};
