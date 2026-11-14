# Antigravity Auto-Hub

**Quản lý đa tài khoản, theo dõi quota theo từng model và tự động xoay tài khoản Antigravity Desktop trên Windows.**

[![Windows validation](https://github.com/datdtpl-maker/Antigravity-Auto-Hub/actions/workflows/validate.yml/badge.svg)](https://github.com/datdtpl-maker/Antigravity-Auto-Hub/actions/workflows/validate.yml)

---

## Tính năng chính

- **Dashboard trực quan (WPF, không cần cài thêm thư viện):** Hiển thị toàn bộ pool tài khoản với gói (**Free / Pro / Ultra**), tìm kiếm, bộ lọc trạng thái, sắp xếp theo cột và nhật ký xoay.
- **Theo dõi đầy đủ từng dòng model:**
  - **Hạn mức chung:** `Gemini 5 giờ`, `Gemini Tuần`
  - **Nhóm Gemini:** `Gemini Flash`, `Gemini Argon`, `Gemini Hydrogen`, `Gemini Carbon`
  - **Nhóm Claude & GPT:** `Claude Opus`, `Claude Sonnet`, `GPT-OSS 120B`
- **Phân biệt rõ trạng thái quota:**
  - **Phần trăm (`0%` – `100%`):** Quota thực tế do Google trả về (`0%` là hết quota thật).
  - **Vòng nét đứt (`—`):** Model chưa được cấp quyền / bị tắt (`disabled: true`, ví dụ *Carbon Unavailable*) hoặc chưa có dữ liệu. Rê chuột vào vòng tròn hoặc bấm **ⓘ** để xem chi tiết từng biến thể và thời điểm reset.
- **Xoay tài khoản tự động & an toàn:**
  - Đọc trực tiếp model đang chọn trong Antigravity IDE (bao gồm `Gemini`, `Claude`, `GPT-OSS`, `Orchestrator (Argon)`).
  - Khi quota hiệu dụng của model đang chọn **< 20%**, tự động chuyển sang tài khoản có cùng model còn **> 20%** cao nhất.
  - **Bảo vệ tác vụ:** Chỉ chuyển khi IDE rảnh, không có bản nháp/ô nhập đang soạn dở và đã qua thời gian chờ (cooldown) **120 giây**.
- **Quản lý & xác minh tài khoản:** Hỗ trợ **Lưu acc hiện tại**, **+ Thêm tài khoản** qua helper riêng và mở liên kết **Xác minh Google** khi cần.

---

## Yêu cầu hệ thống

| Thành phần | Yêu cầu |
| --- | --- |
| Hệ điều hành | Windows (chạy cùng user Windows đang dùng Antigravity) |
| PowerShell | Windows PowerShell 5.1 (`powershell.exe`) |
| Antigravity Desktop | Bản 2.12 trở lên, cài ở đường dẫn mặc định (`%LOCALAPPDATA%\Programs\Antigravity`) |
| Mạng | Truy cập được dịch vụ đăng nhập và API quota Google |
| Node.js | *Không cần để chạy Hub*; chỉ cần khi chạy bộ kiểm thử (`Validate.ps1`) |

---

## Cài đặt lần đầu

### 1. Tải mã nguồn về vị trí cố định

> Giữ nguyên thư mục repo sau khi cài vì shortcut Desktop và Startup sẽ trỏ cố định vào đường dẫn này.

```powershell
git clone https://github.com/datdtpl-maker/Antigravity-Auto-Hub.git
cd Antigravity-Auto-Hub
```

### 2. Đăng nhập Antigravity Desktop
1. Mở **Antigravity Desktop** và đăng nhập tài khoản Google đầu tiên.
2. Hoàn tất các bước xác minh/điều khoản (nếu có) trong ứng dụng.

### 3. Chạy bộ cài đặt
Nhấp đúp **`Setup-Install.bat`** hoặc chạy trong PowerShell tại thư mục repo:

```powershell
.\Setup-Install.bat
```

Script cài đặt sẽ tự động:
1. Kiểm tra phiên bản Antigravity Desktop tương thích.
2. Tự dò và xác minh cấu hình OAuth từ Antigravity cục bộ, mã hóa bằng **Windows DPAPI** vào `oauth.local.clixml`.
3. Tạo shortcut **Antigravity Auto-Hub** trên Desktop và **AntigravityAutoRotator** trong Windows Startup.
4. Khởi chạy daemon chạy nền (quét mỗi 25 giây) và mở giao diện Hub.

<details>
<summary>Tùy chọn nâng cao (ConfigureOnly / nhập OAuth thủ công)</summary>

- Chỉ cấu hình & xác minh OAuth (không tạo shortcut, không chạy daemon):
  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -ConfigureOnly
  ```
- Nhập Client ID / Client Secret OAuth thủ công:
  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Configure-OAuth.ps1
  ```

</details>

---

## Sử dụng hằng ngày

1. Mở shortcut **Antigravity Auto-Hub** ngoài Desktop (hoặc chạy `Chuyen-Doi-Tai-Khoan.bat`).
2. **Thêm tài khoản vào pool xoay:**
   - **Cách khuyến nghị:** Đăng nhập tài khoản muốn lưu trong Antigravity Desktop → mở Hub bấm **Lưu acc hiện tại** → bấm **Quét quota**. Lặp lại cho các tài khoản khác.
   - **Hoặc:** Bấm **+ Thêm tài khoản** ngay trên Hub để đăng nhập qua trình duyệt.
3. **Sẵn sàng xoay:** Cần ít nhất **2 tài khoản** hợp lệ, tài khoản dự phòng có đúng model đang chọn với quota **> 20%**. Đóng cửa sổ Hub không làm tắt daemon chạy nền.

| Thao tác / Trạng thái | Ý nghĩa |
| --- | --- |
| **Quét quota** | Cập nhật ngay quota và gói cho toàn bộ tài khoản (mặc định tự quét mỗi 30s khi mở Hub) |
| **Chuyển** | Chuyển thủ công sang tài khoản đích (vẫn tuân thủ kiểm tra rảnh, bản nháp và cooldown 120s) |
| **ⓘ (Chi tiết)** | Xem toàn bộ model API trả về, nhóm quota 5h / tuần và giờ reset theo giờ máy |
| **Xác minh** | Mở link xác minh Google khi tài khoản bị yêu cầu `VALIDATION_REQUIRED` |

---

## Xử lý sự cố nhanh

| Hiện tượng | Cách khắc phục |
| --- | --- |
| **Báo `Chưa rõ quota` & khóa nút Chuyển** | Model đang chọn trên IDE chưa được cấp hoặc bị tắt (`disabled`) trên tài khoản đó. Bấm **ⓘ** để kiểm tra hoặc đổi model khác trong IDE |
| **Quota hiện `N/A`** | Chưa đọc được dữ liệu (lỗi mạng, hết hạn OAuth hoặc cần xác minh). Kiểm tra trạng thái trên thẻ và bấm **Quét quota** |
| **Quota thấp nhưng chưa tự xoay** | Kiểm tra xem IDE còn tác vụ đang chạy, còn bản nháp chưa gửi, đang trong cooldown 120s hay không có acc dự phòng > 20% |
| **Trạng thái `NeedsAttention` / `Switching` kéo dài** | Xem `rotator.log`, đóng/mở lại Antigravity nếu cần rồi bấm **Quét quota** hoặc chạy `.\AutoRotator.ps1 -Reconcile` |

---

## Kiểm thử & Cấu trúc mã nguồn

Chạy toàn bộ bộ kiểm thử tự động trên Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\tests\Validate.ps1
```

| File / Thư mục | Vai trò |
| --- | --- |
| `MainWindow.xaml`, `AntigravityHub.ps1` | Giao diện WPF và khởi chạy ứng dụng |
| `Dashboard.ps1`, `DashboardText.vi.json` | Dữ liệu dashboard, quét nền, lọc/sắp xếp, nhật ký và chuỗi tiếng Việt |
| `ModelQuota.ps1` | Chuẩn hóa họ model (`Flash`, `Argon`, `Hydrogen`, `Carbon`, `Opus`, `Sonnet`, `GptOss`) và nhóm quota |
| `AutoRotator.ps1`, `RotationCore.ps1` | Engine daemon, đọc quota, chọn tài khoản đích và chuyển đổi an toàn |
| `RuntimeBridge.ps1`, `AccountLogin.ps1` | Giao tiếp runtime/CDP, kiểm tra rảnh/bản nháp và hỗ trợ đăng nhập |
| `Setup.ps1`, `OAuthSetup.ps1`, `Setup-Install.bat` | Cài đặt, tự dò/xác minh OAuth và tạo shortcut |
| `AntigravityMcp.ps1`, `MCP.md` | Máy chủ MCP stdio đọc trạng thái và điều phối |
| `tests/` | Bộ kiểm thử giao diện, layout, model, xoay tài khoản và MCP |

> **Bảo mật:** Credential tài khoản (`accounts/*.json`) và cấu hình OAuth (`oauth.local.clixml`) được lưu cục bộ trên máy và tự động loại trừ khỏi Git qua `.gitignore`. Không chia sẻ token, secret hay thư mục `accounts/` khi báo lỗi.
