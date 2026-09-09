# ANTIGRAVITY AUTO-ROTATION HUB - HANDOFF DOCUMENTATION (FOR CODEX AGENT)

> **Document Version:** 2.0.0  
> **Last Updated:** 2026-09-09  
> **Target Audience:** Codex Agent / Senior AI Developer  
> **Workspace Path:** `D:\AntigravityAccounts`  
> **Remote Repository:** `https://github.com/datdtpl-maker/Antigravity-Auto-Hub.git` (Branch: `main`)

---

## 1. TỔNG QUAN DỰ ÁN & MỤC TIÊU CỐT LÕI (OVERVIEW)

### 1.1. Bối cảnh & Bài toán cần giải quyết
* **Công cụ đích:** **Google Antigravity IDE** (Môi trường phát triển AI đa tác tử chạy trên nền tảng Electron/VS Code).
* **Vấn đề Quota:** Antigravity IDE phân bổ Quota cho các mô hình Gemini (Gemini 2.5/3.8 Flash, Pro, High) theo từng tài khoản Google cá nhân. Quota được chia làm 2 khung cửa sổ trượt:
  * **Quota 5 giờ (Gemini 5H window):** Tự reset sau mỗi 5 tiếng.
  * **Quota tuần (Gemini Weekly window):** Tự reset sau mỗi 7 ngày.
* **Hậu quả khi hết Quota:** Khi tài khoản đang dùng chạm mức 0%, Antigravity IDE sẽ lập tức ngắt phiên làm việc và hiển thị lỗi:
  > *"Baseline model quota reached. Your plan's baseline quota will refresh on ... Resets in ... Error Individual quota reached."*
* **Mục tiêu của dự án này:** 
  Xây dựng một hệ thống hoàn toàn tự động (Auto-Pilot) và bảng điều khiển trực quan (GUI Hub) quản lý một nhóm (pool) tài khoản Google cá nhân, tự động giám sát Quota theo thời gian thực và **chủ động xoay tua sang tài khoản khác từ sớm khi Quota còn 10–12%**, đảm bảo người dùng luôn có 100% Quota và không bao giờ bị gián đoạn công việc.

---

## 2. CẤU TRÚC THƯ MỤC & DANH SÁCH FILE (PROJECT STRUCTURE)

```text
D:\AntigravityAccounts\
│
├── accounts\                          # [GITIGNORED] Thư mục chứa các file JSON credential tài khoản
│   ├── datdt98.pl.json                # JSON token OAuth của datdt98.pl@gmail.com
│   ├── dannydt.0905.json              # JSON token OAuth của dannydt.0905@gmail.com
│   ├── khaihoan.pharma.pt.json        # JSON token OAuth của khaihoan.pharma.pt@gmail.com
│   ├── khaihoansk86.json              # JSON token OAuth của khaihoansk86@gmail.com
│   └── vyle190294.json                # JSON token OAuth của vyle190294@gmail.com
│
├── AntigravityHub.ps1                 # Giao diện đồ họa WPF/XAML quản lý tài khoản & Quota
├── MainWindow.xaml                    # Định nghĩa giao diện XAML hiện đại (Dark theme Catppuccin)
├── AutoRotator.ps1                    # Engine ngầm: Kiểm tra Quota, phát hiện tiêu thụ, tự xoay tua
├── launch-rotator-daemon.vbs          # VBScript khởi chạy AutoRotator ngầm 100% (không cửa sổ, không console)
├── launch-switcher.vbs                # VBScript khởi chạy AntigravityHub không hiện màn hình đen CMD
├── Chuyen-Doi-Tai-Khoan.bat           # Phím tắt mở nhanh giao diện Hub cho người dùng
├── Setup.ps1 / Setup-Install.bat      # Script thiết lập môi trường, tạo shortcut Desktop
├── current_active.txt                 # [GITIGNORED] Ghi nhớ tên tài khoản đang active (ví dụ: khaihoansk86)
├── rotator.log                        # [GITIGNORED] Nhật ký kiểm tra Quota & lịch sử xoay tua
├── .gitignore                         # Loại trừ accounts/, *.log, current_active.txt khỏi Git
└── README.md                          # Tài liệu hướng dẫn sử dụng nhanh
```

### Đường dẫn hệ thống liên quan:
* **Windows Credential Manager:** Target `LegacyGeneric:target=gemini:antigravity` (UserName: `antigravity`).
* **Fallback Token File:** `C:\Users\datdt\.gemini\jetski-standalone-oauth-token`.
* **Startup Shortcut (Tự chạy cùng Windows):**  
  `C:\Users\datdt\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\AntigravityAutoRotator.lnk`  
  Trỏ tới: `wscript.exe "D:\AntigravityAccounts\launch-rotator-daemon.vbs"`.
* **Antigravity IDE Install Dir:** `C:\Users\datdt\AppData\Local\Programs\Antigravity\Antigravity.exe`.
* **Antigravity User Data:** `C:\Users\datdt\AppData\Roaming\Antigravity`.
* **Chrome DevTools Protocol (CDP):** File `C:\Users\datdt\AppData\Roaming\Antigravity\DevToolsActivePort` (Mở port debug cục bộ khi Antigravity IDE chạy).

---

## 3. NGUYÊN LÝ HOẠT ĐỘNG VÀ KIẾN TRÚC KỸ THUẬT (SYSTEM ARCHITECTURE)

### 3.1. Cơ chế Lưu trữ & Nạp Token của Antigravity IDE
1. Khi Antigravity IDE khởi động, nó đọc thông tin đăng nhập Google từ **Windows Credential Manager** theo target `gemini:antigravity` (chuỗi UTF-8 JSON chứa `token.access_token`, `token.refresh_token`, `token.expiry`, và `auth_method: "consumer"`).
2. Ngoài ra, nó cũng đồng bộ với file `$HOME\.gemini\jetski-standalone-oauth-token`.
3. **Đặc tính kỹ thuật quan trọng của Electron:** Sau khi khởi chạy, Antigravity IDE lưu token vào **bộ nhớ RAM** của process. Khi hệ điều hành đổi token trong Credential Manager, cửa sổ Electron **chưa tự động re-read** cho đến khi:
   * Người dùng nhấn **`F5`** hoặc **`Ctrl + R`** (Reload Window).
   * Hoặc gửi lệnh reload qua Chrome DevTools Protocol (CDP).

### 3.2. Cơ chế Xoay tua Sớm (Early Rotation Engine - `AutoRotator.ps1`)
* **Chu kỳ quét:** Chạy lặp mỗi 25 giây (`-IntervalSeconds 25`).
* **Lấy chỉ số Quota từ Google Cloud Internal API:**
  * Endpoint refresh token: `POST https://oauth2.googleapis.com/token`
  * Endpoint lấy Project ID: `POST https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist`
  * Endpoint lấy Quota: `POST https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary`
  * Trích xuất chính xác 2 trường `remainingFraction` của bucket `5h` và `week`.
* **Phát hiện tài khoản đang được sử dụng (Delta Consumption Tracking):**
  * Script so sánh chỉ số Quota 5H của từng tài khoản giữa 2 chu kỳ quét liên tiếp.
  * Nếu tài khoản nào có Quota giảm `> 0.5%`, script xác định chính xác tài khoản đó đang được IDE kết nối và tiêu thụ.
* **Ngưỡng kích hoạt Xoay tua An Toàn (Early Rotation Threshold):**
  * `MinQuotaThreshold = 0.12` (12% Quota 5H).
  * `MinWeeklyThreshold = 0.08` (8% Quota Tuần).
  * **Tại sao không chờ về 0% mới xoay?** Nếu chờ về 0%, người dùng sẽ gặp lỗi chặn `Baseline model quota reached`. Xoay khi còn 10–12% giúp tài khoản cũ vẫn còn đủ quota để hoàn thành câu prompt đang gõ dở!
* **Thuật toán chọn tài khoản tối ưu (Best Account Selection):**
  * Lọc tất cả các tài khoản trong pool có `Gemini5H > 15%` và `GeminiWeekly > 10%`.
  * Sắp xếp ưu tiên: Tài khoản có `Gemini5H` cao nhất (100%), sau đó đến `GeminiWeekly` cao nhất.
* **Cơ chế chống lặp vô hạn (Infinite Loop Prevention & Cooldown):**
  * Khi tài khoản cũ bị cạn kiệt, hệ thống ghi nhớ và đặt thời gian cooldown 60 giây (`$script:LastSwitchTime`).
  * Tuyệt đối không nhận diện lại tài khoản đã cạn kiệt làm active account để tránh spam xoay tua.
* **Cơ chế Đơn tiến trình (Process Singleton):**
  * Kiểm tra qua `Get-CimInstance Win32_Process` với filter `AutoRotator.ps1%Daemon`.
  * Nếu đã có một tiến trình khác đang chạy ngầm, tiến trình mới sẽ tự thoát an toàn (tránh lỗi `AbandonedMutexException`).

### 3.3. Cơ chế Thông báo Thời gian thực (Real-time Toast Notification)
Khi kích hoạt xoay tua hoặc chuyển đổi tài khoản, script gửi Windows Toast Notification kèm:
* Mốc thời gian chuẩn xác từng giây: `[HH:mm:ss]`.
* Lý do xoay (Quota tài khoản cũ còn bao nhiêu %).
* Tài khoản mới được nạp kèm Quota 5H & Tuần.
* Lời nhắc hành động: `Bấm F5 hoặc Ctrl+R trên IDE để dùng ngay!`.
* Âm thanh hệ thống: `[System.Media.SystemSounds]::Asterisk.Play()` để báo hiệu ngay tức thì.

### 3.4. Cơ chế Đăng nhập Google 1-Click (`AntigravityHub.ps1`)
* Không bắt người dùng phải logout/login lằng nhằng trong IDE.
* Khi bấm `+ Thêm Tài Khoản Mới`, Hub mở trình duyệt mặc định với URL OAuth:
  `https://accounts.google.com/o/oauth2/v2/auth?...&prompt=select_account`
* Tham số `prompt=select_account` bắt buộc người dùng chọn tài khoản Google muốn thêm, tránh việc Chrome tự động đăng nhập tài khoản mặc định.
* Khi đăng nhập thành công, token được lưu thẳng vào `accounts/<tên_acc>.json`.

---

## 4. QUY TẮC PHÁT TRIỂN & RÀNG BUỘC MÃ NGUỒN (STRICT RULES FOR CODEX)

Khi tiếp tục chỉnh sửa hoặc mở rộng dự án này, Codex **BẮT BUỘC** tuân thủ các nguyên tắc sau:

1. **Chuẩn mã hóa 100% Pure 7-bit ASCII:**
   * Mọi file PowerShell (`.ps1`) phải được viết hoàn toàn bằng ký tự ASCII 7-bit.
   * Tuyệt đối không gõ trực tiếp chữ có dấu tiếng Việt vào string trong file `.ps1` (tránh lỗi font / mojibake khi chạy trên PowerShell 5.1).
   * Mọi chữ tiếng Việt phải dùng cú pháp mã hóa: `$([char]0xXXXX)` (Ví dụ: `T$([char]0x00E0)i kho$([char]0x1EA3)n`).
2. **Bảo mật Token & Thông tin nhạy cảm:**
   * Thư mục `accounts/` chứa Refresh Token cá nhân của người dùng, **tuyệt đối không bao giờ được commit lên Git**.
   * File `current_active.txt`, `rotator.log`, `*.log` phải luôn nằm trong `.gitignore`.
3. **Thao tác Chạy ngầm (Background / Headless):**
   * Tiến trình Daemon phải chạy độc lập qua [launch-rotator-daemon.vbs](file:///D:/AntigravityAccounts/launch-rotator-daemon.vbs) hoặc `Start-Process powershell.exe -WindowStyle Hidden`.
   * Không chạy lệnh dài hạn làm treo terminal của IDE hoặc tạo ra widget `1 task running` trong chat của người dùng.

---

## 5. CÁC HƯỚNG MỞ RỘNG TIỀM NĂNG (NEXT STEPS FOR CODEX)

Nếu người dùng yêu cầu nâng cấp tiếp, dưới đây là các giải pháp kỹ thuật đã được nghiên cứu sẵn:

### 5.1. Tự động Reload IDE không cần bấm F5 qua CDP (Chrome DevTools Protocol)
* **Khả thi 100%:** File `C:\Users\datdt\AppData\Roaming\Antigravity\DevToolsActivePort` chứa port debug cục bộ của Antigravity IDE (ví dụ: port `65438`).
* **Cách làm:** Khi `Switch-ActiveAccount` hoàn tất, script có thể kết nối WebSocket tới endpoint `/devtools/page/...` và gửi payload JSON:
  `{"id": 1, "method": "Page.reload", "params": {"ignoreCache": true}}`
  → IDE sẽ tự động làm mới ngay lập tức mà người dùng không cần bấm bất kỳ phím nào!
* *Lưu ý:* Cần kiểm tra xem người dùng có đang gõ prompt dở không trước khi reload.

### 5.2. Tối ưu hóa Quota Request (Smart Interval Fetching)
* Hiện tại mỗi 25s, script quét toàn bộ 5 tài khoản (~20 HTTP requests).
* Có thể tối ưu: Chỉ quét thường xuyên tài khoản đang `[DANG DUNG]`. Các tài khoản chờ (standby) chỉ cần quét 5-10 phút một lần hoặc chỉ quét khi tài khoản active bắt đầu chạm ngưỡng $\le 20\%$.

---

## 6. DANH SÁCH SKILLS ĐƯỢC ĐỀ XUẤT (SUGGESTED SKILLS FOR CODEX)
Khi làm việc trên dự án này, hãy sử dụng các skill sau:
* `error-handling`: Xử lý ngoại lệ token hết hạn, kết nối mạng Google API bị timeout.
* `latency-critical-systems`: Tối ưu hóa độ trễ chu kỳ quét quota và tốc độ tráo đổi Credential.
* `security-review`: Kiểm tra an toàn lưu trữ Credential Manager và quyền hạn file token.
