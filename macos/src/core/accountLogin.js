const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const https = require('https');
const { spawn } = require('child_process');
const { ACCOUNTS_DIR, sanitizeAccountName, writeAtomicText, writeRotatorLog } = require('./storage');
const { getStoredCredential, setStoredCredential } = require('./keychain');
const { findMacLanguageServer, getCredentialEmail } = require('./oauth');

function extractAuthUrl(line) {
  if (!line) return null;
  const matches = line.match(/https:\/\/[^\s<>"']+/g) || [];
  for (const m of matches) {
    try {
      const u = new URL(m);
      if (u.protocol === 'https:' && u.hostname === 'accounts.google.com' &&
          (u.pathname === '/o/oauth2/auth' || u.pathname === '/o/oauth2/v2/auth') && u.search) {
        return u.toString();
      }
    } catch { /* ignore */ }
  }
  return null;
}

function postLocalLogin(port, csrf) {
  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: '127.0.0.1',
      port,
      path: '/exa.language_server_pb.LanguageServerService/Login',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-codeium-csrf-token': csrf,
        'Content-Length': 2
      },
      rejectUnauthorized: false,
      timeout: 300000
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    req.write('{}');
    req.end();
  });
}

async function saveCurrentAccount() {
  const raw = getStoredCredential();
  if (!raw) throw new Error('Không tìm thấy tài khoản Antigravity đang đăng nhập trên máy.');
  const email = await getCredentialEmail(raw);
  if (!email) throw new Error('Không xác minh được email từ token hiện tại.');
  const accountName = sanitizeAccountName(email.split('@')[0]);
  const dest = path.join(ACCOUNTS_DIR, `${accountName}.json`);
  writeAtomicText(dest, raw, 0o600);
  writeRotatorLog(`Saved current IDE account: [${accountName}] (${email}).`);
  return { accountName, email };
}

async function startInteractiveAccountLogin(openExternalUrl) {
  const lsPath = findMacLanguageServer();
  if (!lsPath) {
    throw new Error('Không tìm thấy Antigravity.app trong /Applications. Hãy cài Antigravity IDE trước.');
  }

  const oldCredential = getStoredCredential();
  const csrf = crypto.randomUUID();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agh-login-'));
  let child = null;
  let browserOpened = false;

  try {
    writeRotatorLog('Account login: starting macOS Antigravity login helper.');
    const args = [
      '--standalone',
      '--subclient_type=hub',
      '--override_ide_name=antigravity',
      '--api_server_url=https://generativelanguage.googleapis.com',
      '--cloud_code_endpoint=https://daily-cloudcode-pa.googleapis.com',
      `--gemini_dir=${tempDir}`,
      '--app_data_dir=app',
      `--csrf_token=${csrf}`
    ];

    child = spawn(lsPath, args, {
      env: { ...process.env, ANTIGRAVITY_VSCODE_HOST: '1' },
      stdio: ['pipe', 'pipe', 'pipe']
    });
    child.stdin.end();

    let port = 0;
    let loginPromise = null;

    const handleLine = (line) => {
      const pm = line.match(/listening on \w+ port at (\d+) for HTTPS\b/);
      if (pm && !port) {
        port = Number(pm[1]);
        loginPromise = postLocalLogin(port, csrf);
      }
      const url = extractAuthUrl(line);
      if (url && !browserOpened) {
        browserOpened = true;
        writeRotatorLog('Account login: Google authorization opened.');
        openExternalUrl(url);
      }
    };

    const attach = (stream) => {
      let buf = '';
      stream.on('data', (chunk) => {
        buf += chunk.toString('utf8');
        const lines = buf.split(/\r?\n/);
        buf = lines.pop();
        for (const l of lines) handleLine(l);
      });
    };
    attach(child.stdout);
    attach(child.stderr);

    // Wait up to 15s for login helper port
    const portDeadline = Date.now() + 15000;
    while (!loginPromise && Date.now() < portDeadline) {
      await new Promise((r) => setTimeout(r, 250));
    }
    if (!loginPromise) throw new Error('Không khởi tạo được tiến trình đăng nhập Antigravity.');

    await loginPromise;

    // Read new credential from tempDir or Keychain
    const tempTokenPath = path.join(tempDir, 'jetski-standalone-oauth-token');
    let newRaw = null;
    if (fs.existsSync(tempTokenPath)) {
      newRaw = fs.readFileSync(tempTokenPath, 'utf8').trim();
    }
    if (!newRaw) newRaw = getStoredCredential();
    if (!newRaw) throw new Error('Không đọc được token sau khi đăng nhập.');

    const newEmail = await getCredentialEmail(newRaw);
    if (!newEmail) throw new Error('Không xác minh được email tài khoản mới.');

    const accountName = sanitizeAccountName(newEmail.split('@')[0]);
    const dest = path.join(ACCOUNTS_DIR, `${accountName}.json`);
    writeAtomicText(dest, newRaw, 0o600);
    writeRotatorLog(`Account login completed: saved [${accountName}] (${newEmail}).`);
    return { accountName, email: newEmail };
  } finally {
    if (child && !child.killed) {
      try { child.kill('SIGTERM'); } catch { /* ignore */ }
    }
    if (oldCredential) {
      try { setStoredCredential(oldCredential); } catch { /* ignore */ }
    }
    try { fs.rmSync(tempDir, { recursive: true, force: true }); } catch { /* ignore */ }
  }
}

module.exports = {
  saveCurrentAccount,
  startInteractiveAccountLogin
};
