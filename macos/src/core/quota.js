const fs = require('fs');
const path = require('path');
const { listAccountFiles } = require('./storage');
const { getFreshToken } = require('./oauth');

const USER_AGENT = 'antigravity/hub/2.25.0 (os_type=darwin; arch=arm64; aidev_client; cl=1003374690; auth_method=consumer)';

function toQuotaFraction(val) {
  if (val === null || val === undefined || val === '') return -1.0;
  const num = Number(val);
  if (!Number.isFinite(num) || num < 0 || num > 1) return -1.0;
  return num;
}

function toQuotaReset(val) {
  if (!val) return '';
  const d = new Date(val);
  return Number.isNaN(d.getTime()) ? '' : d.toISOString();
}

function getModelSelectionKey(name) {
  const key = String(name || '')
    .replace(/[()]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
  return key.replace(/^(gemini 4 (?:neon|hydrogen)) extra(?: high)?$/, '$1 xhigh');
}

function getModelQuotaFamily(id, name) {
  const label = `${id || ''} ${name || ''}`;
  if (/\borchestrator\b|[-_]orchestrator[-_]/i.test(label)) return 'Orchestrator';
  if (/\bneon\b|[-_]neon[-_]/i.test(label)) return 'Neon';
  if (/\bargon\b|[-_]argon[-_]/i.test(label)) return 'Argon';
  if (/\bcarbon\b|[-_]carbon[-_]/i.test(label)) return 'Carbon';
  if (/\bhydrogen\b|[-_]hydrogen[-_]/i.test(label)) return 'Hydrogen';
  if (/claude.*opus/i.test(label)) return 'Opus';
  if (/claude.*sonnet/i.test(label)) return 'Sonnet';
  if (/gpt[- ]oss/i.test(label)) return 'GptOss';
  if (/gemini.*flash/i.test(label) && !/lite|image/i.test(label)) return 'Flash';
  return 'Other';
}

function convertToModelDisplayName(modelId) {
  if (!modelId) return '';
  const id = String(modelId).trim();
  let m = id.match(/^gemini-4-(neon|argon|hydrogen)-(xhigh|high|medium|low)$/i);
  if (m) {
    const fam = m[1][0].toUpperCase() + m[1].slice(1).toLowerCase();
    const eff = m[2].toLowerCase() === 'xhigh' ? 'XHigh' : m[2][0].toUpperCase() + m[2].slice(1).toLowerCase();
    return `Gemini 4 ${fam} (${eff})`;
  }
  if (/^gemini-4-carbon$/i.test(id)) return 'Gemini 4 Carbon';
  m = id.match(/^gemini-3\.8-flash-(high|medium|low)$/i);
  if (m) {
    const eff = m[1][0].toUpperCase() + m[1].slice(1).toLowerCase();
    return `Gemini 3.8 Flash (${eff})`;
  }
  if (/^gemini-3-flash$/i.test(id)) return 'Gemini 3 Flash';
  if (/^claude-opus-4-6/i.test(id)) return 'Claude Opus 4.6 (Thinking)';
  if (/^claude-sonnet-4-6/i.test(id)) return 'Claude Sonnet 4.6 (Thinking)';
  if (/^gpt-oss-120b-medium$/i.test(id)) return 'GPT-OSS 120B (Medium)';
  return id;
}

function convertQuotaSummary(response) {
  const five = [];
  const weekly = [];
  const argon = [];
  const groups = Array.isArray(response?.groups) ? response.groups : [];
  for (const group of groups) {
    const displayName = String(group.displayName || '');
    const groupText = `${displayName} ${group.description || ''}`;
    if (!/gemini|argon/i.test(groupText) || /orchestrator/i.test(displayName)) continue;
    // Ultra shares Gemini Models with Argon listed in description; match Argon group by displayName only.
    const groupIsArgon = /argon/i.test(displayName);
    const buckets = Array.isArray(group.buckets) ? group.buckets : [];
    for (const bucket of buckets) {
      const fraction = toQuotaFraction(bucket.remainingFraction);
      if (fraction < 0) continue;
      const bucketIsArgon = groupIsArgon || /argon/i.test(`${bucket.bucketId || ''} ${bucket.displayName || ''}`);
      const win = String(bucket.window || '');
      if (bucketIsArgon) {
        if (/^(5h|week|weekly|7d)$/i.test(win) || !win) argon.push(fraction);
      } else if (/^5h$/i.test(win)) {
        five.push(fraction);
      } else if (/^(week|weekly|7d)$/i.test(win)) {
        weekly.push(fraction);
      }
    }
  }
  if (!five.length || !weekly.length) {
    throw new Error('Quota windows unavailable; no rotation.');
  }
  return {
    Gemini5H: Math.min(...five),
    GeminiWeekly: Math.min(...weekly),
    ArgonWeekly: argon.length ? Math.min(...argon) : -1.0
  };
}

function convertArgonModelQuota(response) {
  const models = response?.models && typeof response.models === 'object' ? Object.entries(response.models) : [];
  const entries = models.filter(([id, m]) => {
    const label = `${id} ${m?.displayName || ''}`;
    return (/(^|[-_])argon([-_]|$)/i.test(id) || /\bargon\b/i.test(String(m?.displayName || ''))) &&
      !/orchestrator/i.test(label);
  });
  let disabled = 0;
  let incomplete = false;
  const fractions = [];
  for (const [, model] of entries) {
    if (model?.disabled === true) { disabled++; continue; }
    if (model?.disabled !== undefined && typeof model.disabled !== 'boolean') { incomplete = true; continue; }
    const f = toQuotaFraction(model?.quotaInfo?.remainingFraction);
    if (f < 0) { incomplete = true; continue; }
    fractions.push(f);
  }
  if (entries.length > 0 && disabled === entries.length) return { Status: 'Disabled', Remaining: -1.0 };
  if (fractions.length > 0 && !incomplete) return { Status: 'Available', Remaining: Math.min(...fractions) };
  return { Status: 'Unknown', Remaining: -1.0 };
}

function convertModelQuotaCatalog(response) {
  const out = [];
  const models = response?.models && typeof response.models === 'object' ? Object.entries(response.models) : [];
  for (const [rawId, model] of models) {
    const id = String(rawId || '').replace(/[\x00-\x1f]/g, ' ').trim();
    const name = String(model?.displayName || '').replace(/[\x00-\x1f]/g, ' ').trim();
    if (!name || id.length > 160 || name.length > 160) continue;
    let fraction = toQuotaFraction(model?.quotaInfo?.remainingFraction);
    let status = 'Unknown';
    if (model?.disabled === true) { status = 'Disabled'; fraction = -1.0; }
    else if (model?.disabled !== undefined && typeof model.disabled !== 'boolean') { fraction = -1.0; }
    else if (fraction >= 0) { status = 'Available'; }
    out.push({
      Id: id,
      Name: name,
      Family: getModelQuotaFamily(id, name),
      Status: status,
      Remaining: fraction,
      ResetAt: toQuotaReset(model?.quotaInfo?.resetTime)
    });
  }
  return out;
}

function convertQuotaGroups(response) {
  const out = [];
  const groups = Array.isArray(response?.groups) ? response.groups : [];
  for (const group of groups) {
    const buckets = Array.isArray(group.buckets) ? group.buckets : [];
    for (const bucket of buckets) {
      out.push({
        Name: String(group.displayName || ''),
        Window: String(bucket.window || ''),
        Remaining: toQuotaFraction(bucket.remainingFraction),
        ResetAt: toQuotaReset(bucket.resetTime)
      });
    }
  }
  return out;
}

function convertAccountPlan(response) {
  let tier = response?.currentTier || null;
  let source = 'CurrentTier';
  if (response?.paidTier) {
    tier = response.paidTier;
    source = 'PaidTier';
  }
  let name = 'Unknown';
  const id = String(tier?.id || '');
  if (id === 'free-tier' && source === 'CurrentTier') name = 'Free';
  else if (id === 'g1-pro-tier') name = 'Pro';
  else if (id === 'g1-ultra-tier') name = 'Ultra';
  return { Name: name, Source: tier ? source : '' };
}

function getSelectedModelQuota(account, selectedModel) {
  const unknown = { Known: false, Remaining: -1.0, Model: selectedModel || '' };
  if (!selectedModel || account.ModelsStatus !== 'Available' || !account.Email) return unknown;
  const key = getModelSelectionKey(selectedModel);
  const models = (account.ModelQuotas || []).filter((m) => getModelSelectionKey(m.Name) === key);
  if (!models.length || models.some((m) => m.Status !== 'Available' || toQuotaFraction(m.Remaining) < 0)) {
    return unknown;
  }
  const values = models.map((m) => toQuotaFraction(m.Remaining));
  const family = models[0].Family;
  const groups = (account.QuotaGroups || []).filter((g) => {
    const gName = String(g.Name || '');
    if (family === 'Orchestrator') return getModelSelectionKey(gName) === key;
    if (/orchestrator/i.test(gName)) return false;
    if (['Opus', 'Sonnet', 'GptOss'].includes(family)) return /claude|gpt/i.test(gName);
    if (family === 'Argon') return /argon/i.test(gName);
    if (family === 'Carbon') return /carbon/i.test(gName);
    const nh = gName.match(/\b(neon|hydrogen)\b/i);
    if (nh) return family.toLowerCase() === nh[1].toLowerCase();
    return /gemini/i.test(gName) && !/argon|carbon/i.test(gName);
  });
  if (!account.Success) return unknown;
  for (const g of groups) {
    const f = toQuotaFraction(g.Remaining);
    if (f < 0) return unknown;
    values.push(f);
  }
  return { Known: true, Remaining: Math.min(...values), Model: selectedModel };
}

function getFamilyRing(account, family) {
  const models = (account.ModelQuotas || []).filter((m) => m.Family === family);
  if (!models.length) return { status: 'Unknown', remaining: -1, variants: [] };
  const enabled = models.filter((m) => m.Status !== 'Disabled');
  if (!enabled.length) return { status: 'Disabled', remaining: -1, variants: models };
  const valid = enabled.filter((m) => m.Status === 'Available' && m.Remaining >= 0);
  if (valid.length !== enabled.length) return { status: 'Unknown', remaining: -1, variants: models };
  return { status: 'Available', remaining: Math.min(...valid.map((m) => m.Remaining)), variants: models };
}

async function fetchJsonPost(url, headers, bodyObj) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { ...headers, 'Content-Type': 'application/json' },
    body: JSON.stringify(bodyObj || {}),
    signal: AbortSignal.timeout(12000)
  });
  const text = await res.text();
  if (!res.ok) {
    const err = new Error(`HTTP ${res.status}`);
    err.status = res.status;
    err.body = text;
    throw err;
  }
  return JSON.parse(text || '{}');
}

async function getAccountQuotaInfo(tokenFilePath, includeModels = true) {
  const result = {
    Success: false,
    Email: '',
    Gemini5H: -1.0,
    GeminiWeekly: -1.0,
    ArgonWeekly: -1.0,
    ArgonStatus: 'Unknown',
    ArgonQuotaSource: '',
    Plan: 'Unknown',
    PlanSource: '',
    ModelQuotas: [],
    QuotaGroups: [],
    ModelsStatus: includeModels ? 'Unavailable' : 'NotRequested',
    CheckedAt: new Date().toISOString(),
    TokenPath: tokenFilePath,
    AccountName: path.basename(tokenFilePath, '.json'),
    Error: 'Quota unavailable',
    ErrorCode: 'QuotaUnavailable',
    VerificationUrl: null
  };
  try {
    const tokenObj = JSON.parse(fs.readFileSync(tokenFilePath, 'utf8'));
    const fresh = await getFreshToken(tokenObj);
    const headers = {
      Authorization: `Bearer ${fresh.token.access_token}`,
      'User-Agent': USER_AGENT
    };
    const userRes = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
      headers,
      signal: AbortSignal.timeout(10000)
    });
    if (!userRes.ok) throw new Error('Account email unavailable.');
    const user = await userRes.json();
    if (!user.email) throw new Error('Account email unavailable.');
    result.Email = String(user.email);

    const project = await fetchJsonPost('https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist', headers, {});
    const plan = convertAccountPlan(project);
    result.Plan = plan.Name;
    result.PlanSource = plan.Source;

    let projectId = project.cloudaicompanionProject;
    if (projectId && typeof projectId === 'object') projectId = projectId.id;
    if (!projectId) projectId = project.project;
    if (!projectId || typeof projectId !== 'string') throw new Error('Project ID unavailable.');

    let modelsResp = null;
    if (includeModels) {
      try {
        modelsResp = await fetchJsonPost('https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels', headers, { project: projectId });
        if (modelsResp && modelsResp.models) {
          result.ModelQuotas = convertModelQuotaCatalog(modelsResp);
          result.ModelsStatus = 'Available';
        }
      } catch { /* keep Unavailable */ }
    }

    const summary = await fetchJsonPost('https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary', headers, { project: projectId });
    if (includeModels) result.QuotaGroups = convertQuotaGroups(summary);
    const quota = convertQuotaSummary(summary);
    result.Gemini5H = quota.Gemini5H;
    result.GeminiWeekly = quota.GeminiWeekly;
    result.ArgonWeekly = quota.ArgonWeekly;
    if (quota.ArgonWeekly >= 0) {
      result.ArgonStatus = 'Available';
      result.ArgonQuotaSource = 'Summary';
    } else {
      try {
        if (!modelsResp) {
          modelsResp = await fetchJsonPost('https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels', headers, { project: projectId });
        }
        const argon = convertArgonModelQuota(modelsResp);
        result.ArgonStatus = argon.Status;
        result.ArgonWeekly = argon.Remaining;
        result.ArgonQuotaSource = 'ModelCatalog';
      } catch { /* keep Argon unknown */ }
    }
    result.Success = true;
    result.Error = '';
    result.ErrorCode = '';
  } catch (err) {
    if (err && err.body) {
      try {
        const parsed = JSON.parse(err.body);
        const details = Array.isArray(parsed?.error?.details) ? parsed.error.details : [];
        for (const d of details) {
          if (d['@type'] === 'type.googleapis.com/google.rpc.ErrorInfo' && d.reason === 'VALIDATION_REQUIRED') {
            result.ErrorCode = 'AccountVerificationRequired';
            result.Error = 'Account verification required';
            if (d.metadata?.validation_url && /^https:\/\/accounts\.google\.com\//.test(d.metadata.validation_url)) {
              result.VerificationUrl = d.metadata.validation_url;
            }
          }
        }
      } catch { /* ignore */ }
    }
  }
  return result;
}

async function getAllAccountsQuota(includeModels = true) {
  const files = listAccountFiles();
  return Promise.all(files.map((f) => getAccountQuotaInfo(f, includeModels)));
}

module.exports = {
  toQuotaFraction,
  getModelSelectionKey,
  getModelQuotaFamily,
  convertToModelDisplayName,
  convertQuotaSummary,
  convertArgonModelQuota,
  convertModelQuotaCatalog,
  convertQuotaGroups,
  convertAccountPlan,
  getSelectedModelQuota,
  getFamilyRing,
  getAccountQuotaInfo,
  getAllAccountsQuota
};
