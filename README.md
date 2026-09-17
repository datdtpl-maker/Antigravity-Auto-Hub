# Antigravity Auto-Hub

**Quản lý nhiều tài khoản Google, theo dõi quota và điều phối chuyển tài khoản cho Antigravity Desktop trên Windows.**

[![Windows validation](https://github.com/datdtpl-maker/Antigravity-Auto-Hub/actions/workflows/validate.yml/badge.svg)](https://github.com/datdtpl-maker/Antigravity-Auto-Hub/actions/workflows/validate.yml)

Auto-Hub cung cấp giao diện WPF, tiến trình giám sát nền và MCP server chạy cục bộ. Engine chỉ thực hiện chuyển khi xác định được tài khoản đang dùng, quota đạt điều kiện và phiên làm việc cho phép chuyển.

> **Trạng thái kiểm chứng:** 66 kiểm thử tự động đã đạt trên máy phát triển; bản MCP trước đó đạt 61 kiểm thử trên CI Windows. Đã đọc được quota, danh tính phiên Antigravity và trạng thái qua MCP thật. Chưa kiểm chứng chuyển tài khoản thật xuyên suốt hoặc tích hợp OmniLogin thực tế. Xem [Kiểm thử và mức độ kiểm chứng](#kiểm-thử-và-mức-độ-kiểm-chứng).

## Mục lục

- [Tính năng](#tính-năng)
- [Yêu cầu hệ thống](#yêu-cầu-hệ-thống)
- [Cài đặt](#cài-đặt)
- [Sử dụng](#sử-dụng)
- [Cơ chế chuyển tài khoản](#cơ-chế-chuyển-tài-khoản)
- [Kết nối MCP](#kết-nối-mcp)
- [Xử lý sự cố](#xử-lý-sự-cố)
- [Dữ liệu và bảo mật](#dữ-liệu-và-bảo-mật)
- [Kiểm thử và mức độ kiểm chứng](#kiểm-thử-và-mức-độ-kiểm-chứng)
- [Cấu trúc mã nguồn](#cấu-trúc-mã-nguồn)

## Tính năng

- **Quản lý tài khoản:** thêm tài khoản qua trình đăng nhập Google, lưu credential hiện tại và xem danh sách tài khoản trong Hub.
- **Theo dõi quota:** hiển thị quota Gemini theo cửa sổ 5 giờ và tuần; dữ liệu không xác định được hiển thị `N/A`.
- **Điều phối tự động:** chọn tài khoản còn quota khi tài khoản hiện tại xuống dưới ngưỡng; hoãn chuyển nếu có tác vụ đang chạy hoặc nội dung nhập dở.
- **Xác minh sau chuyển:** đối chiếu email của phiên Antigravity mới trước khi ghi nhận trạng thái `Verified`.
- **Khôi phục khi lỗi:** cố khôi phục credential cũ và tạm dừng xoay nếu giao dịch không được xác minh.
- **MCP cục bộ:** cho phép client đọc trạng thái, xem quota và gọi các thao tác chuyển được cấp quyền.

## Yêu cầu hệ thống

| Thành phần | Yêu cầu |
| --- | --- |
| Hệ điều hành | Windows, chạy dưới người dùng đang sử dụng Antigravity |
| PowerShell | Windows PowerShell 5.1 (`powershell.exe`) |
| Antigravity Desktop | Phiên bản được chấp nhận: **2.12.2 / 2.13.0 / 2.14.0**, bao gồm hậu tố `.0` |
| Phiên làm việc | Một runtime Desktop cục bộ; API nội bộ và CDP phải truy cập được |
| Tài khoản | Tài khoản Google đăng nhập hợp lệ, được lưu vào pool trên máy |
| OAuth | Client ID/secret tương thích với refresh token của các tài khoản |
| Kết nối mạng | Truy cập được các dịch vụ xác thực và quota của Google |
| MCP — tùy chọn | Client hỗ trợ chạy MCP server qua **stdio** trên cùng máy |

Không cần Node.js hoặc Python để chạy Hub và MCP server. Bộ cài sử dụng Windows Script Host (`wscript.exe`) để khởi chạy nền.

## Cài đặt

### 1. Tải mã nguồn

```powershell
git clone https://github.com/datdtpl-maker/Antigravity-Auto-Hub.git
cd Antigravity-Auto-Hub
```

Các lệnh bên dưới được chạy từ thư mục repo. Giữ thư mục này ở vị trí cố định sau khi tạo shortcut.

### 2. Cấu hình OAuth

```powershell
powershell.exe -NoProfile -File .\Configure-OAuth.ps1
```

Nhập client ID và client secret khi được hỏi. Script lưu cấu hình vào `oauth.local.clixml`, bảo vệ secret bằng Windows DPAPI cho người dùng hiện tại.

**Repo không kèm OAuth client secret hoặc tài khoản dùng sẵn.** Refresh token được cấp cho client nào phải dùng với client tương thích; tạo một client Google bất kỳ không làm token hiện có hoạt động. Nếu chưa có cấu hình phù hợp, chức năng đọc quota và chuyển tài khoản chưa sẵn sàng.

Có thể dùng hai biến môi trường sau thay cho file cấu hình:

| Biến | Nội dung |
| --- | --- |
| `ANTIGRAVITY_GOOGLE_CLIENT_ID` | Google OAuth client ID |
| `ANTIGRAVITY_GOOGLE_CLIENT_SECRET` | Google OAuth client secret |

Khi cung cấp đủ cả hai biến, engine ưu tiên chúng. Nếu thay đổi cấu hình, khởi động lại Hub, daemon và kết nối MCP đang dùng để nạp giá trị mới. Không đưa secret vào mã nguồn hoặc lệnh được chia sẻ công khai.

### 3. Thiết lập Hub

```powershell
.\Setup-Install.bat
```

Script thực hiện:

1. Tạo thư mục tài khoản nếu chưa có.
2. Tạo shortcut **Antigravity Auto-Hub** trên Desktop.
3. Tạo shortcut trong thư mục Windows Startup để chạy daemon khi đăng nhập Windows.
4. Khởi chạy daemon và mở Hub.

Daemon là tiến trình nền của người dùng, không phải Windows Service. Setup không cài Antigravity hoặc tự cấu hình OAuth.

### 4. Thêm tài khoản

Mở Antigravity và đăng nhập Google, sau đó dùng Hub:

- **Lưu Acc Này:** lưu credential hiện tại vào pool tài khoản.
- **+ Thêm Tài Khoản Mới:** mở luồng đăng nhập Google để thêm tài khoản khác.

Chờ quá trình đăng nhập hoàn tất trước khi đóng Hub. Bước thêm tài khoản cố khôi phục lựa chọn credential trước đó và không tự khởi động lại Antigravity.

## Sử dụng

Mở shortcut trên Desktop hoặc chạy:

```powershell
.\Chuyen-Doi-Tai-Khoan.bat
```

| Thao tác | Hành vi |
| --- | --- |
| **Quét Quota** | Làm mới dữ liệu và thử đối chiếu trạng thái chuyển cần kiểm tra |
| **Chuyển Thủ Công** | Yêu cầu chuyển tới tài khoản đã chọn, vẫn kiểm tra quota, tác vụ và bản nháp |
| **Xóa** | Xóa file tài khoản đã chọn khỏi pool sau khi xác nhận |
| **Mở thư mục** | Mở thư mục cài đặt Hub |

Đóng cửa sổ Hub không dừng daemon. Khi đã cài Startup, daemon tiếp tục giám sát nền và tự chạy trong lần đăng nhập Windows sau.

## Cơ chế chuyển tài khoản

### Quy tắc mặc định

| Điều kiện | Giá trị / hành vi |
| --- | --- |
| Ngưỡng yêu cầu xoay | Quota 5H **≤ 12%** hoặc quota tuần **≤ 8%** |
| Tài khoản đích để xoay tự động | Quota 5H **> 15%** và quota tuần **> 10%** |
| Thứ tự ưu tiên | Quota 5H cao nhất, sau đó quota tuần cao nhất |
| Khoảng nghỉ giữa các lần quét | **25 giây sau khi quét xong**; thời gian gọi API được cộng thêm |
| Thời gian chờ giữa các lần chuyển | **120 giây**, lưu trong trạng thái trên đĩa |
| Lỗi mạng, quota không rõ hoặc không có tài khoản phù hợp | Giữ nguyên tài khoản |

Engine xác minh danh tính qua API của runtime, kiểm tra tác vụ và ô nhập, ghi credential mới, khởi động lại đúng tiến trình `language_server`, xác minh email rồi khôi phục đường dẫn cửa sổ. Hub, daemon và MCP dùng chung khóa giao dịch để tránh chuyển đồng thời.

### Trạng thái giao dịch

| Trạng thái | Ý nghĩa |
| --- | --- |
| `Prepared` | Credential đã chuẩn bị khi IDE đóng; chưa xác minh phiên đăng nhập mới |
| `Switching` | Giao dịch đã bắt đầu; chưa xác nhận hoàn tất |
| `Verified` | Engine đã xác minh email runtime sau chuyển hoặc đối chiếu lại |
| `NeedsAttention` | Cần kiểm tra/khôi phục; tự động xoay tạm dừng |

### Giới hạn vận hành

Chuyển tài khoản diễn ra **giữa các lượt làm việc**, có khoảng ngắt để tiến trình nối lại. Tool không chuyển tiếp từng request như một load balancer, không tự gửi lại prompt và không bảo đảm quota luôn còn đủ cho tác vụ hiện tại.

Engine hoãn chuyển khi có tác vụ đang chạy, trạng thái không rõ, ô nhập đang được chọn hoặc nội dung chưa gửi. Tuy nhiên, kiểm tra trạng thái rảnh và khởi động lại không phải thao tác nguyên tử của Antigravity; vẫn có khoảng đua nếu người dùng bắt đầu tác vụ mới ngay lúc chuyển. Khôi phục URL cũng không khôi phục toàn bộ trạng thái trong RAM.

Phiên bản Antigravity ngoài danh sách hỗ trợ, nhiều runtime hoặc thiếu CDP sẽ khiến engine hoãn chuyển. Các API nội bộ có thể thay đổi khi Antigravity cập nhật.

## Kết nối MCP

Sinh cấu hình cho đúng thư mục clone:

```powershell
# Chỉ đọc trạng thái và quota
powershell.exe -NoProfile -File .\Configure-Mcp.ps1

# Cho phép client yêu cầu chuyển tài khoản
powershell.exe -NoProfile -File .\Configure-Mcp.ps1 -AllowSwitch
```

Script in JSON để thêm vào cấu hình MCP của client; không tự sửa cấu hình ứng dụng khác. Mặc định server chỉ cung cấp công cụ đọc. `-AllowSwitch` bật thêm các thao tác có thể thay credential và khởi động lại language server.

| Tool | Quyền |
| --- | --- |
| `antigravity_status` | Đọc trạng thái runtime và giao dịch |
| `antigravity_accounts` | Đọc danh sách và quota |
| `antigravity_rotate_if_needed` | Cần `-AllowSwitch`; kiểm tra và xoay nếu đủ điều kiện |
| `antigravity_switch_account` | Cần `-AllowSwitch`; yêu cầu chuyển tài khoản cụ thể |
| `antigravity_reconcile` | Cần `-AllowSwitch`; đối chiếu và cập nhật trạng thái |

**Phạm vi:** MCP điều khiển Antigravity Desktop trên cùng máy và cùng người dùng Windows. Nó không thay credential của một MCP Antigravity độc lập, proxy hoặc dịch vụ từ xa; không cung cấp API model hay endpoint HTTP/SSE.

**OmniLogin:** chưa xác minh khả năng kết nối stdio và vận hành thực tế. Nếu MCP “Anti” trong OmniLogin có kho token riêng, cần adapter cho MCP đó.

Xem [hướng dẫn MCP](MCP.md) để cấu hình client, cấp quyền và xử lý timeout.

## Xử lý sự cố

| Hiện tượng | Hướng kiểm tra |
| --- | --- |
| `IDE …: chưa hỗ trợ` | Kiểm tra phiên bản Antigravity và danh sách hỗ trợ; không bỏ qua kiểm tra phiên bản |
| Chưa nhận diện được IDE | Mở Antigravity, hoàn tất đăng nhập và bảo đảm chỉ có một runtime được hỗ trợ |
| Quota hiển thị `N/A` | Kiểm tra OAuth client, quyền truy cập mạng và tính hợp lệ của tài khoản |
| Quota thấp nhưng chưa chuyển | Kiểm tra tác vụ đang chạy, ô nhập/bản nháp, CDP, cooldown và quota của tài khoản dự phòng |
| MCP không có lệnh chuyển | Sinh cấu hình với `-AllowSwitch`, rồi khởi động lại kết nối MCP |
| Trạng thái `Switching` kéo dài hoặc `NeedsAttention` | Xem `rotator.log` và `rotation-state.json`, sau đó đối chiếu lại theo hướng dẫn dưới đây |

Nếu credential đã khôi phục nhưng runtime còn dùng tài khoản khác, hoàn tất công việc rồi đóng/mở lại Antigravity. Bấm **Quét Quota** hoặc chạy:

```powershell
powershell.exe -NoProfile -File .\AutoRotator.ps1 -Reconcile
```

Lệnh chỉ gỡ trạng thái chờ khi email runtime khớp credential và tài khoản trong pool. Nó không ép chuyển tài khoản hoặc khởi động lại IDE. Không xóa file trạng thái để bỏ qua bước xác minh.

Khi [báo lỗi](https://github.com/datdtpl-maker/Antigravity-Auto-Hub/issues), cung cấp phiên bản Antigravity, thao tác tái hiện và đoạn log liên quan. Che email nếu cần; không gửi token, secret hoặc toàn bộ thư mục `accounts/`.

## Dữ liệu và bảo mật

| Dữ liệu | Lưu trữ |
| --- | --- |
| Token trong pool | `accounts/*.json` — file cục bộ, không được DPAPI mã hóa bởi Hub |
| Cấu hình OAuth | `oauth.local.clixml` — secret được DPAPI bảo vệ, gắn với người dùng Windows |
| Credential Antigravity | Windows Credential Manager và file token dự phòng trong thư mục `.gemini` của người dùng |
| Trạng thái vận hành | `current_active.txt`, `rotation-state.json`, `rotator.log` |

Các file riêng tư và thư mục `work/` được loại khỏi Git bằng `.gitignore`. MCP chỉ trả các trường được chọn, không xuất token hoặc CSRF. Không sao chép cấu hình DPAPI sang người dùng/máy khác; bảo vệ quyền truy cập thư mục tài khoản và các bản sao lưu.

Tool không chủ động sửa mã nguồn, file `.env` hoặc biến môi trường của các dự án đang mở. Credential đăng nhập là dữ liệu dùng chung của Antigravity, và thao tác khởi động lại language server có thể ảnh hưởng trạng thái phiên làm việc.

Source hiện tại không chứa client secret dùng sẵn. Việc loại secret khỏi bản hiện tại không xóa dữ liệu từng có trong lịch sử Git.

## Kiểm thử và mức độ kiểm chứng

```powershell
powershell.exe -NoProfile -STA -File .\tests\Validate.ps1
```

Bộ kiểm tra gồm cú pháp và ASCII của script PowerShell, nạp WPF XAML, cùng **66 kiểm thử**:

- **40 kiểm thử engine và tương thích:** quota, điều kiện xoay, rollback, trạng thái, phiên bản.
- **26 kiểm thử MCP:** giao thức, quyền chỉ đọc, validation, lọc dữ liệu nhạy cảm, UTF-8 BOM và tiến trình stdio thật từ thư mục không có credential.

Workflow [Windows validation](.github/workflows/validate.yml) chạy cùng bộ kiểm tra khi push hoặc mở pull request. Các thao tác chuyển trong kiểm thử dùng mock, không thay tài khoản thật.

| Hạng mục | Bằng chứng hiện có |
| --- | --- |
| Kiểm thử local | 66 kiểm thử đạt ngày 17/09/2026, bao gồm tương thích 2.14.0 |
| CI Windows | 61 kiểm thử đạt tại bản MCP ngày 16/09/2026; bản sửa 2.14.0 chưa chạy CI |
| Quota Google và email runtime | Đã đọc được trên máy phát triển |
| Trạng thái tác vụ và kiểm tra ô nhập qua CDP | Đã truy vấn trên runtime thật |
| MCP `antigravity_status` qua stdio | Đã đọc được runtime thật ở chế độ chỉ đọc |
| Chuyển tài khoản thật xuyên suốt | **Chưa kiểm chứng** |
| Luồng đăng nhập Google tương tác sau nâng cấp | **Chưa kiểm thử lại** |
| Tích hợp OmniLogin | **Chưa kiểm chứng** |

## Cấu trúc mã nguồn

| File / thư mục | Vai trò |
| --- | --- |
| `AntigravityHub.ps1`, `MainWindow.xaml` | Giao diện quản lý tài khoản |
| `AutoRotator.ps1` | Cấu hình, Credential Manager, thông báo và daemon |
| `RotationCore.ps1` | Quota, lựa chọn tài khoản, giao dịch và khôi phục |
| `RuntimeBridge.ps1` | Kết nối API nội bộ, CDP và xác minh runtime |
| `AntigravityMcp.ps1` | MCP server stdio |
| `Configure-OAuth.ps1`, `Configure-Mcp.ps1` | Thiết lập OAuth và sinh cấu hình MCP |
| `Setup.ps1`, `Setup-Install.bat` | Tạo shortcut và thiết lập khởi động nền |
| `launch-*.vbs` | Khởi chạy Hub/daemon ẩn console |
| `tests/` | Kiểm thử engine, tương thích và MCP |
| [MCP.md](MCP.md) | Hướng dẫn tích hợp MCP |
| [HANDOFF.md](HANDOFF.md) | Bàn giao kỹ thuật và các giới hạn cần tiếp tục xác minh |
