# ⚡ Antigravity Auto-Rotation Hub (Auto-Pilot Multi-Account Quota Manager)

<p align="center">
  <img src="https://img.shields.io/badge/Release-v1.2.0-blue?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Platform-Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white" />
  <img src="https://img.shields.io/badge/Antigravity_IDE-Native_Integration-4285F4?style=for-the-badge&logo=google&logoColor=white" />
  <img src="https://img.shields.io/badge/Auto--Pilot-100%25_Background-10B981?style=for-the-badge" />
  <img src="https://img.shields.io/badge/License-MIT-purple?style=for-the-badge" />
</p>

Hệ thống quản lý đa tài khoản Google và **tự động xoay tua hạn mức (Quota Auto-Pilot) 100% ngầm** dành riêng cho **Antigravity IDE** trên Windows.

---

## 🌟 Tính Năng Nổi Bật (Phiên bản v1.2.0)

* ⚡ **Xoay Sớm Thông Minh (Early Auto-Rotation - Không Bao Giờ Cạn 0%):**
  * Tự động kích hoạt đổi tài khoản ngay khi Quota 5H còn **10% - 12%** (hoặc Quota Tuần $\le 8\%$).
  * Tuyệt đối không để tài khoản rơi về 0%, bảo toàn trạng thái prompt mượt mà liên tục.
* ⏱️ **Tần Suất Quét Siêu Tốc (Fast-Scan Cycle 25s):**
  * Chu kỳ kiểm tra ngầm được rút ngắn từ 60 giây xuống **25 giây/lần**, bắt kịp tốc độ prompting của các phiên chat cường độ cao.
* 🧠 **Bộ Nhận Diện Tiêu Thụ Thực Tế (Smart Consumption Tracker):**
  * Tự động phát hiện tài khoản nào đang thực sự bị trừ Quota trong Antigravity IDE qua từng chu kỳ để điều phối chuẩn xác 100%.
* 🚀 **Tích hợp trực tiếp Antigravity IDE (Không cần mở nhiều Profile/Window):** Hoạt động ngay trên cửa sổ Antigravity IDE chính của bạn.
* 🔔 **Thông báo Windows (Native Toast Notifications):**
  * Sử dụng WinRT Toast Notifications của Windows 10/11.
  * Tự động hiển thị banner thông báo nhỏ góc phải màn hình kèm âm thanh mỗi khi tài khoản được xoay ngầm:  
    `⚡ Antigravity Auto-Hub: Đã kết nối tài khoản [tên_tài_khoản] (5H: 100% | Tuần: 100%)`.
* 🤖 **Tương thích 100% Mô hình Mới:** Hỗ trợ đầy đủ các mô hình Gemini mới nhất (**Gemini 3.8 Flash**, **Gemini 3.7 Flash**, **Gemini Pro**).
* 🔐 **Tích hợp Native Windows Credential Manager:** Đọc & nạp Token trực tiếp qua API bảo mật `advapi32.dll` (`gemini:antigravity`), tự động nhận diện Email Google khi đăng nhập.
* 🎨 **Giao diện WPF Dark Mode Hiện Đại & Chuẩn Quốc Tế:** Hiển thị song song 2 thanh tiến trình Quota (5H & Tuần) cho từng tài khoản, 100% chuẩn mã hóa Unicode không bao giờ lỗi font chữ.
* 📦 **1-Click Portable Setup:** Chỉ cần clone repo về bất kỳ thư mục nào trên máy mới và chạy `Setup-Install.bat`, hệ thống tự tạo Shortcut Desktop và kích hoạt Service khởi động cùng Windows.
* 🔒 **Bảo mật Tuyệt đối:** Toàn bộ OAuth tokens và thông tin tài khoản được lưu cục bộ trên máy bạn và được cấu hình `.gitignore` loại trừ triệt để, không bao giờ bị đẩy lên GitHub.

---

## 📂 Cấu Trúc Dự Án (Project Architecture)

```text
Antigravity-Auto-Hub/
├── accounts/                  # Thư mục lưu token các tài khoản Google (Được bảo vệ bởi .gitignore)
├── MainWindow.xaml            # Giao diện WPF Dark Mode (Chuẩn XML Entity Unicode)
├── AntigravityHub.ps1         # Bảng điều khiển quản trị tài khoản & Quota Dashboard
├── AutoRotator.ps1            # Engine theo dõi Quota thời gian thực & Auto-Rotation ngầm
├── launch-switcher.vbs        # VBScript khởi chạy giao diện hoàn toàn ẩn
├── Chuyen-Doi-Tai-Khoan.bat   # Phím tắt mở Hub nhanh
├── Setup-Install.bat          # Kịch bản cài đặt 1-Click cho máy mới
├── Setup.ps1                  # Trình thiết lập Shortcut & Startup Service
├── .gitignore                 # Chặn rò rỉ token OAuth & logs
└── README.md                  # Hướng dẫn sử dụng chi tiết
```

---

## 🚀 Hướng Dẫn Cài Đặt & Sử Dụng Trên Máy Mới

### 1. Clone Kho Mã Nguồn
```powershell
git clone https://github.com/datdtpl-maker/Antigravity-Auto-Hub.git
cd Antigravity-Auto-Hub
```

### 2. Cài Đặt 1-Click
* Nhấp đúp chuột vào file **`Setup-Install.bat`**.
* Hệ thống sẽ tự động:
  1. Tạo phím tắt **`Antigravity Auto-Hub`** ngoài màn hình Desktop.
  2. Đăng ký Service ngầm **`AutoRotator.ps1`** vào thư mục Windows Startup để tự khởi động cùng máy.
  3. Mở ngay giao diện điều khiển.

---

## 💡 Cách Thêm Tài Khoản Google Vào Kho Xoay Tua

1. Mở **`Antigravity Auto-Hub`** ngoài Desktop $\rightarrow$ Bấm **`+ Thêm Tài Khoản Mới`**.
2. Quay lại Antigravity IDE $\rightarrow$ Tiến hành Đăng nhập tài khoản Google mới.
3. Đăng nhập xong trên IDE $\rightarrow$ Mở lại Hub và bấm **`Lưu Acc Này`**.
4. Hệ thống sẽ tự động nhận diện Email Google và nạp vào danh sách xoay tua!

---

## ⚙️ Cơ Chế Tự Động Xoay Tua (Auto-Pilot Logic)

```mermaid
graph TD
    A[AutoRotator Daemon Chạy Ngầm 60s/chu kỳ] --> B[Gọi API Google Quota: retrieveUserQuotaSummary]
    B --> C{Tài khoản Active: Quota 5H <= 10% HOẶC Quota Tuần <= 5%?}
    C -->|Không| D[Tiếp tục giữ phiên làm việc hiện tại]
    C -->|Có| E[Tìm tài khoản thỏa mãn: 5H > 10% VÀ Tuần > 5%]
    E --> F[Inject Token vào Windows Credential Manager: gemini:antigravity]
    F --> G[Cập nhật jetski-standalone-oauth-token]
    G --> H[Bắn Windows Toast Notification góc phải màn hình]
    H --> I[Antigravity IDE tự động sử dụng Quota mới mà không gián đoạn]
```

---

## 🔒 Bảo Mật & Quyền Riêng Tư

* Dự án **KHÔNG** gửi bất kỳ dữ liệu hay Token nào về máy chủ bên thứ ba. Toàn bộ Token chỉ giao tiếp trực tiếp với máy chủ chính thức của Google (`oauth2.googleapis.com` & `cloudcode-pa.googleapis.com`).
* File `.gitignore` đã loại trừ toàn bộ thư mục `accounts/*.json`, `current_active.txt` và `*.log`. Bạn có thể yên tâm chia sẻ hoặc commit mã nguồn lên GitHub công khai.

---

## 📄 Bản Quyền
Phát hành theo giấy phép [MIT License](LICENSE).
