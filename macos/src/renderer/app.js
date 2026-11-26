let currentSnapshot = null;
let currentFilter = 'All';
let isScanning = false;
let latestReleaseUrl = '';

const $ = (id) => document.getElementById(id);

function applyTheme(theme) {
  document.body.className = theme === 'Amoled' ? 'theme-amoled' : 'theme-light';
}

function renderSvgRing(fraction, status = 'Available', title = '') {
  const known = status === 'Available' && typeof fraction === 'number' && fraction >= 0;
  const pct = known ? Math.round(fraction * 1000) / 10 : -1;
  const label = known ? `${pct}%` : '—';
  const r = 16;
  const c = 2 * Math.PI * r;
  const dashOffset = known ? c * (1 - Math.max(0, Math.min(1, fraction))) : 0;
  let stroke = '#64748B';
  if (known) {
    if (fraction <= 0.10) stroke = '#B42318';
    else if (fraction <= 0.20) stroke = '#B45309';
    else stroke = '#087F73';
  }
  const dashAttr = known ? `stroke-dasharray="${c.toFixed(1)}" stroke-dashoffset="${dashOffset.toFixed(1)}"` : 'stroke-dasharray="3 3"';
  return `<div class="ring-cell" title="${escapeHtml(title)}">
    <svg width="40" height="40" viewBox="0 0 40 40">
      <circle cx="20" cy="20" r="${r}" fill="none" stroke="rgba(148,163,184,0.25)" stroke-width="3" />
      <circle cx="20" cy="20" r="${r}" fill="none" stroke="${stroke}" stroke-width="3" ${dashAttr}
        stroke-linecap="round" transform="rotate(-90 20 20)" />
      <text x="20" y="23" text-anchor="middle" font-size="9.5" font-weight="700" fill="${stroke}">${label}</text>
    </svg>
  </div>`;
}

function escapeHtml(s) {
  return String(s || '').replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));
}

function formatReset(iso) {
  if (!iso) return 'Chưa rõ thời điểm đặt lại';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return 'Chưa rõ';
  const diffMin = Math.max(0, Math.round((d.getTime() - Date.now()) / 60000));
  const h = Math.floor(diffMin / 60);
  const m = diffMin % 60;
  const timeStr = d.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' });
  return `Còn ${h}g ${m}p (${timeStr})`;
}

function renderAccounts() {
  if (!currentSnapshot) return;
  const q = $('searchInput').value.trim().toLowerCase();
  const list = currentSnapshot.accounts.filter((a) => {
    if (currentFilter === 'Ready' && a.StateKey !== 'Ready') return false;
    if (currentFilter === 'Attention' && a.StateKey === 'Ready') return false;
    if (q && !a.AccountName.toLowerCase().includes(q) && !(a.Email || '').toLowerCase().includes(q)) return false;
    return true;
  });

  const tbody = $('accountsBody');
  $('emptyState').classList.toggle('hidden', list.length > 0);
  tbody.innerHTML = list.map((a) => {
    const statusLabel = a.IsActive ? 'Đang kết nối'
      : a.Verify ? 'Cần xác minh'
      : a.StateKey === 'Ready' ? 'Đủ quota'
      : a.StateKey === 'Low' ? 'Quota thấp' : 'Chưa rõ quota';
    const dotCls = (a.IsActive || a.StateKey === 'Ready') ? 'ok' : (a.StateKey === 'Low' ? 'warn' : 'err');
    const actionBtn = a.Verify
      ? `<button class="btn-outline" data-verify="${escapeHtml(a.VerificationUrl)}">Xác minh</button>`
      : `<button class="btn-outline" data-switch="${escapeHtml(a.AccountName)}" ${a.IsActive ? 'disabled' : ''}>Chuyển</button>`;

    return `<tr class="${a.IsActive ? 'active-row' : ''}">
      <td class="col-acc">
        <div class="acc-name">${escapeHtml(a.AccountName)}</div>
        <div class="acc-status"><span class="dot ${dotCls}"></span>${statusLabel}</div>
      </td>
      <td><span class="badge-plan ${escapeHtml(a.Plan)}">${escapeHtml(a.Plan)}</span></td>
      <td>${renderSvgRing(a.Gemini5H, a.Gemini5H >= 0 ? 'Available' : 'Unknown', 'Quota Gemini 5 giờ')}</td>
      <td>${renderSvgRing(a.GeminiWeekly, a.GeminiWeekly >= 0 ? 'Available' : 'Unknown', 'Quota Gemini Tuần')}</td>
      <td>${renderSvgRing(a.Rings.Flash.remaining, a.Rings.Flash.status, 'Gemini Flash')}</td>
      <td>${renderSvgRing(a.Rings.Neon.remaining, a.Rings.Neon.status, 'Gemini 4 Neon')}</td>
      <td>${renderSvgRing(a.Rings.Argon.remaining, a.Rings.Argon.status, 'Gemini 4 Argon')}</td>
      <td>${renderSvgRing(a.Rings.Hydrogen.remaining, a.Rings.Hydrogen.status, 'Gemini 4 Hydrogen')}</td>
      <td>${renderSvgRing(a.Rings.Carbon.remaining, a.Rings.Carbon.status, 'Gemini 4 Carbon')}</td>
      <td>${renderSvgRing(a.Rings.Opus.remaining, a.Rings.Opus.status, 'Claude Opus')}</td>
      <td>${renderSvgRing(a.Rings.Sonnet.remaining, a.Rings.Sonnet.status, 'Claude Sonnet')}</td>
      <td>${renderSvgRing(a.Rings.GptOss.remaining, a.Rings.GptOss.status, 'GPT-OSS 120B')}</td>
      <td class="col-act">
        <div class="act-btns">
          <button class="btn-outline" data-detail="${escapeHtml(a.AccountName)}" title="Xem chi tiết quota">i</button>
          ${actionBtn}
          <button class="btn-danger-sm" data-delete="${escapeHtml(a.AccountName)}" title="Xóa tài khoản">✕</button>
        </div>
      </td>
    </tr>`;
  }).join('');
}

function renderHistory() {
  if (!currentSnapshot) return;
  const tbody = $('historyBody');
  if (!currentSnapshot.logs.length) {
    tbody.innerHTML = '<tr><td colspan="3" style="padding:30px;color:var(--muted)">Chưa có sự kiện xoay trong nhật ký gần đây.</td></tr>';
    return;
  }
  const typeMap = {
    Confirmed: 'Đã xác minh',
    Prepared: 'Đã chuẩn bị',
    Deferred: 'Tạm hoãn',
    Failed: 'Cần kiểm tra',
    Started: 'Khởi chạy',
    Info: 'Thông tin'
  };
  tbody.innerHTML = currentSnapshot.logs.map((l) => `<tr>
    <td>${escapeHtml(l.time)}</td>
    <td><b>${escapeHtml(typeMap[l.type] || l.type)}</b></td>
    <td style="text-align:left">${escapeHtml(l.detail)}</td>
  </tr>`).join('');
}

function renderSettings(cfg) {
  $('selTheme').value = cfg.Theme || 'Light';
  $('chkAutoRotate').checked = Boolean(cfg.AutoRotationEnabled);
  $('chkCliRotate').checked = Boolean(cfg.CliRotationEnabled);
  $('chkLaunchLogin').checked = Boolean(cfg.LaunchAtLogin);
  $('selMinQuota').value = String(cfg.MinQuotaPercent || 15);
  $('selCooldown').value = String(cfg.CooldownSeconds || 60);
  $('chkNotify').checked = Boolean(cfg.EnableNotifications);
  applyTheme(cfg.Theme);
}

function renderSnapshot(snap) {
  currentSnapshot = snap;
  const cfg = snap.config;
  const minPct = cfg.MinQuotaPercent || 15;

  $('statTotal').textContent = String(snap.accounts.length);
  $('statReady').textContent = String(snap.accounts.filter((a) => a.StateKey === 'Ready').length);
  $('statAttention').textContent = String(snap.accounts.filter((a) => a.StateKey !== 'Ready').length);
  $('statVerified').textContent = String(snap.verifiedRotations || 0);

  $('hintReady').textContent = snap.selectedModel ? `Model đang chọn > ${minPct}%` : `Quota 5 giờ > ${minPct}%`;
  $('sidebarPolicyLow').textContent = `Quota 5h / Model < ${minPct}%`;
  $('sidebarPolicyHigh').textContent = `Acc đích > ${minPct}%`;
  $('pageSubtitle').textContent = snap.selectedModel
    ? `Tự động ưu tiên: ${snap.selectedModel} · Xoay khi dưới ${minPct}%, chỉ khi IDE rảnh`
    : `Tự động giám sát Quota 5 giờ · Xoay khi dưới ${minPct}%, chỉ khi IDE rảnh`;

  let statusText = 'Đang giám sát · Xoay khi quota thấp và IDE rảnh';
  let dotCls = 'ok';
  if (!cfg.AutoRotationEnabled) { statusText = 'Tự động xoay đang tạm dừng · Chỉ theo dõi quota'; dotCls = 'warn'; }
  else if (snap.runtimeError) { statusText = snap.runtimeError; dotCls = 'err'; }
  else if (!snap.connected) { statusText = 'Chưa kết nối Antigravity (Đang chạy chế độ CLI nếu bật)'; dotCls = 'warn'; }
  else if (!snap.idle) { statusText = 'IDE đang chạy tác vụ · Chờ hoàn tất để chuyển'; dotCls = 'warn'; }

  $('txtDaemonStatus').textContent = statusText;
  $('statusDot').className = `dot ${dotCls}`;
  $('txtActiveAccount').textContent = snap.activeEmail ? `Đang dùng: ${snap.activeEmail}` : 'Chưa xác minh tài khoản trong Antigravity';
  const scanSuffix = snap.scanMs > 0 ? ` (${(snap.scanMs / 1000).toFixed(1)}s)` : '';
  $('txtUpdated').textContent = `Cập nhật ${new Date(snap.at).toLocaleTimeString('vi-VN')}${scanSuffix}`;
  $('btnPauseToggle').textContent = cfg.AutoRotationEnabled ? 'Tạm dừng xoay' : 'Bật xoay tự động';
  $('txtFooterPath').textContent = `Thư mục lưu trữ: ${snap.baseDir} · v${snap.version}`;

  renderSettings(cfg);
  renderAccounts();
  renderHistory();
}

function showDetailsModal(accountName) {
  const acc = currentSnapshot?.accounts.find((a) => a.AccountName === accountName);
  if (!acc) return;
  $('modalTitle').textContent = `Chi tiết quota · ${acc.AccountName} (${acc.Plan})`;
  const groupsHtml = (acc.QuotaGroups || []).map((g) => `<div class="detail-item">
    <span><b>${escapeHtml(g.Name)}</b> (${escapeHtml(g.Window)})</span>
    <span>${g.Remaining >= 0 ? `${Math.round(g.Remaining * 1000) / 10}%` : '—'} · ${formatReset(g.ResetAt)}</span>
  </div>`).join('') || '<div class="setting-desc">Chưa có dữ liệu hạn mức nhóm.</div>';

  const modelsHtml = (acc.ModelQuotas || []).map((m) => `<div class="detail-item">
    <span>${escapeHtml(m.Name)}</span>
    <span>${m.Status === 'Available' ? `${Math.round(m.Remaining * 1000) / 10}%` : m.Status} · ${formatReset(m.ResetAt)}</span>
  </div>`).join('') || '<div class="setting-desc">Chưa có dữ liệu model.</div>';

  $('modalBody').innerHTML = `
    <div><h4>HẠN MỨC NHÓM</h4>${groupsHtml}</div>
    <div><h4>TẤT CẢ MODEL</h4>${modelsHtml}</div>
  `;
  $('detailsModal').classList.remove('hidden');
}

async function refreshSnapshot() {
  if (isScanning) return;
  isScanning = true;
  $('btnScan').disabled = true;
  $('btnScan').textContent = 'Đang quét…';
  try {
    const snap = await window.hubApi.getSnapshot();
    renderSnapshot(snap);
  } finally {
    isScanning = false;
    $('btnScan').disabled = false;
    $('btnScan').textContent = 'Quét quota';
  }
}

document.querySelectorAll('.nav-item').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.nav-item').forEach((b) => b.classList.remove('active'));
    btn.classList.add('active');
    const page = btn.dataset.page;
    document.querySelectorAll('.page').forEach((p) => p.classList.remove('active'));
    $(`page-${page}`).classList.add('active');
    const titles = { accounts: 'Tổng quan quota', history: 'Nhật ký xoay', settings: 'Cài đặt hệ thống' };
    $('pageTitle').textContent = titles[page] || 'Tổng quan quota';
  });
});

document.querySelectorAll('.filter-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.filter-btn').forEach((b) => b.classList.remove('active'));
    btn.classList.add('active');
    currentFilter = btn.dataset.filter;
    renderAccounts();
  });
});

$('searchInput').addEventListener('input', renderAccounts);
$('btnScan').addEventListener('click', refreshSnapshot);
$('btnOpenFolder').addEventListener('click', () => window.hubApi.openFolder());
$('btnCloseModal').addEventListener('click', () => $('detailsModal').classList.add('hidden'));

$('btnThemeToggle').addEventListener('click', async () => {
  const next = (currentSnapshot?.config?.Theme === 'Amoled') ? 'Light' : 'Amoled';
  await window.hubApi.saveConfig({ Theme: next });
  applyTheme(next);
  if (currentSnapshot) currentSnapshot.config.Theme = next;
  $('selTheme').value = next;
});

$('btnPauseToggle').addEventListener('click', async () => {
  if (!currentSnapshot) return;
  const next = !currentSnapshot.config.AutoRotationEnabled;
  await window.hubApi.saveConfig({ AutoRotationEnabled: next });
  await refreshSnapshot();
});

$('btnSaveCurrent').addEventListener('click', async () => {
  const res = await window.hubApi.saveCurrent();
  alert(res.ok ? `Đã lưu tài khoản hiện tại: ${res.accountName} (${res.email})` : `Lỗi: ${res.message}`);
  if (res.ok) await refreshSnapshot();
});

$('btnAddAccount').addEventListener('click', async () => {
  $('btnAddAccount').disabled = true;
  $('btnAddAccount').textContent = 'Đang mở đăng nhập…';
  try {
    const res = await window.hubApi.addAccount();
    alert(res.ok ? `Đã thêm tài khoản thành công: ${res.accountName} (${res.email})` : `Chưa thêm được: ${res.message}`);
    if (res.ok) await refreshSnapshot();
  } finally {
    $('btnAddAccount').disabled = false;
    $('btnAddAccount').textContent = '+ Thêm tài khoản';
  }
});

$('accountsBody').addEventListener('click', async (e) => {
  const btn = e.target.closest('button');
  if (!btn) return;
  if (btn.dataset.detail) {
    showDetailsModal(btn.dataset.detail);
  } else if (btn.dataset.verify) {
    window.hubApi.openExternal(btn.dataset.verify);
  } else if (btn.dataset.switch) {
    btn.disabled = true;
    btn.textContent = 'Đang chuyển…';
    const res = await window.hubApi.switchAccount(btn.dataset.switch);
    if (!res.ok) alert(res.message);
    await refreshSnapshot();
  } else if (btn.dataset.delete) {
    if (confirm(`Xóa tài khoản '${btn.dataset.delete}' khỏi kho xoay trên máy này?`)) {
      await window.hubApi.deleteAccount(btn.dataset.delete);
      await refreshSnapshot();
    }
  }
});

$('btnSaveSettings').addEventListener('click', async () => {
  await window.hubApi.saveConfig({
    Theme: $('selTheme').value,
    AutoRotationEnabled: $('chkAutoRotate').checked,
    CliRotationEnabled: $('chkCliRotate').checked,
    LaunchAtLogin: $('chkLaunchLogin').checked,
    MinQuotaPercent: Number($('selMinQuota').value),
    CooldownSeconds: Number($('selCooldown').value),
    EnableNotifications: $('chkNotify').checked
  });
  $('txtSettingsSaved').textContent = 'Đã lưu cài đặt. Daemon sẽ áp dụng ngay ở lượt quét kế tiếp.';
  await refreshSnapshot();
});

$('btnCheckUpdate').addEventListener('click', async () => {
  $('txtUpdateStatus').textContent = 'Đang kiểm tra cập nhật từ GitHub…';
  $('btnDownloadUpdate').classList.add('hidden');
  const res = await window.hubApi.checkUpdate();
  if (!res.ok) {
    $('txtUpdateStatus').textContent = 'Không kiểm tra được cập nhật. Kiểm tra kết nối mạng.';
    return;
  }
  if (res.hasUpdate) {
    latestReleaseUrl = res.url;
    $('txtUpdateStatus').textContent = `Có phiên bản mới v${res.latestVersion} (hiện tại v${res.currentVersion})!`;
    $('btnDownloadUpdate').classList.remove('hidden');
  } else {
    $('txtUpdateStatus').textContent = `Bạn đang dùng phiên bản mới nhất (v${res.currentVersion}).`;
  }
});

$('btnDownloadUpdate').addEventListener('click', () => {
  if (latestReleaseUrl) window.hubApi.openExternal(latestReleaseUrl);
});

window.hubApi.onTriggerRefresh(() => refreshSnapshot());
window.hubApi.onDaemonTick(() => refreshSnapshot());

refreshSnapshot();
