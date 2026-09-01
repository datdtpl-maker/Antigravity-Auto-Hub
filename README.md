# ⚡ Antigravity Auto-Hub (Windows Native Multi-Account & Auto-Rotator)

Effortless Multi-Account Google Cloud Code Quota Management & Automated Auto-Pilot Rotation for **Google Antigravity IDE**.

---

## ✨ Features
* 🛡️ **Zero-Collision Token Sandboxing:** Isolates multiple Google accounts into clean token storage on Windows (`D:\AntigravityAccounts\accounts\`).
* ⚡ **100% Automated Auto-Rotation (Daemon Watcher):** Background daemon continuously monitors real-time Gemini 5H and Weekly quota via Google Cloud Code endpoint (`daily-cloudcode-pa`). When the active profile quota reaches $\le 10\%$, it automatically swaps tokens to the healthiest Google account.
* 📊 **Live Quota HUD & Dashboard:** Modern Dark-Mode GUI (WPF) displaying real-time % quota bars, emails, and active connection status.
* 🚀 **Zero-Dependency Native:** Runs directly on Windows PowerShell / WPF without requiring Node.js, Python, or external heavy runtimes.

---

## 📁 Repository Structure
* `AntigravityHub.ps1`: Modern Dark Mode WPF Dashboard.
* `AutoRotator.ps1`: Background Quota Engine & Auto-Pilot Rotation Watcher.
* `launch-switcher.vbs`: Silent windowless launcher.
* `Chuyen-Doi-Tai-Khoan.bat`: Quick Batch launcher.

---

## 🚀 Quick Start
1. Clone repository to `D:\AntigravityAccounts`.
2. Double-click `Chuyen-Doi-Tai-Khoan.bat` or run `launch-switcher.vbs`.
3. Add your Google Accounts and let the Auto-Pilot Daemon handle rotation seamlessly!
