# Antigravity Auto-Hub

**Quản lý nhiều tài khoản, theo dõi quota Gemini và tự động chuyển tài khoản Antigravity Desktop trên Windows.**

[![Windows validation](https://github.com/datdtpl-maker/Antigravity-Auto-Hub/actions/workflows/validate.yml/badge.svg)](https://github.com/datdtpl-maker/Antigravity-Auto-Hub/actions/workflows/validate.yml)

Hub theo dõi các tài khoản bạn đã lưu và chọn tài khoản còn quota khi Antigravity rảnh. Bạn cũng có thể chuyển thủ công và xử lý yêu cầu xác minh Google từ giao diện.

> **Trước khi bắt đầu:** cần Antigravity Desktop, tài khoản Google của bạn và cấu hình OAuth tương thích. Repo không cung cấp tài khoản, token hoặc client secret dùng sẵn. Chỉ clone repo và chạy Setup chưa đủ để đọc quota.

## Mục lục

1. [Chuẩn bị](#chuẩn-bị)
2. [Cài đặt lần đầu](#cài-đặt-lần-đầu)
3. [Thêm tài khoản](#thêm-tài-khoản)
4. [Sử dụng hằng ngày](#sử-dụng-hằng-ngày)
5. [Xoay tự động](#xoay-tự-động)
6. [Xử lý sự cố](#xử-lý-sự-cố)
7. [Cập nhật và tắt chạy nền](#cập-nhật-và-tắt-chạy-nền)
8. [Kết nối MCP](#kết-nối-mcp)
9. [Dữ liệu và bảo mật](#dữ-liệu-và-bảo-mật)
10. [Dành cho người phát triển](#dành-cho-người-phát-triển)

## Chuẩn bị

| Thành phần | Yêu cầu |
| --- | --- |
| Máy tính | Windows, dùng cùng người dùng Windows đang chạy Antigravity |
| PowerShell | Windows PowerShell 5.1, lệnh `powershell.exe` |
| Antigravity Desktop | Bản 2.x từ 2.12 trở lên, vượt qua kiểm tra tương thích của Hub; đã kiểm tra bản cài 2.19.1 |
| Tài khoản | Một tài khoản để theo dõi; ít nhất hai tài khoản hợp lệ để xoay |
| OAuth | Client ID và client secret tương thích với refresh token của tài khoản |
| Mạng | Truy cập được dịch vụ đăng nhập và quota Google |
| Git | Chỉ cần nếu tải/cập nhật bằng lệnh Git |

Không cần Node.js, Python hoặc MCP để **sử dụng Hub**. Node.js chỉ cần khi chạy bộ kiểm thử. Bộ cài dùng Windows Script Host (`wscript.exe`) để mở ứng dụng không kèm console.

Nút **Thêm Tài Khoản Mới** hiện tìm helper ở đường dẫn cài mặc định:

```text
%LOCALAPPDATA%\Programs\Antigravity\resources\bin\language_server.exe
```

Hub cần một runtime Antigravity Desktop cục bộ và kết nối được API nội bộ/CDP của ứng dụng. Kiểm tra tương thích là bước sàng lọc, không bảo đảm mọi bản cập nhật tương lai đều hoạt động.

## Cài đặt lần đầu

### Bước 1 — Tải repo

**Có Git:** mở PowerShell ở thư mục muốn lưu dự án, chạy:

```powershell
git clone https://github.com/datdtpl-maker/Antigravity-Auto-Hub.git
cd Antigravity-Auto-Hub
```

**Không có Git:** mở [trang GitHub](https://github.com/datdtpl-maker/Antigravity-Auto-Hub), chọn **Code → Download ZIP**, rồi giải nén vào thư mục riêng. Không chạy trực tiếp bên trong ZIP.

Các lệnh tiếp theo chạy **trong thư mục có `Setup-Install.bat`**. Bạn có thể mở thư mục bằng File Explorer, nhập `powershell` vào thanh địa chỉ rồi nhấn Enter.

Giữ repo ở vị trí cố định sau khi cài vì shortcut trỏ tới đường dẫn đó. Ưu tiên thư mục riêng trên máy, tránh đồng bộ dữ liệu tài khoản lên nơi dùng chung.

### Bước 2 — Cấu hình OAuth

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Configure-OAuth.ps1
```

1. Nhập **Google OAuth client ID**.
2. Nhập **Google OAuth client secret**; nội dung secret được che khi nhập.
3. Kiểm tra thông báo đã lưu và file `oauth.local.clixml` trong repo.

Đây là thông tin ứng dụng OAuth, **không phải email/mật khẩu Google, API key Gemini hoặc tên gói AI Pro**. Refresh token được cấp cho client nào phải dùng với client tương thích. Tạo một client Google Cloud bất kỳ không làm token hiện có trong Antigravity hoạt động với client đó.

**Nếu chưa có cấu hình tương thích, bước này chưa thể hoàn tất.** Repo chưa có trình tự động cấp hoặc tìm cấu hình OAuth cho người mới. Cần cấu hình từ nguồn tích hợp bạn được phép sử dụng; không lấy credential của người khác. Hub mở được giao diện chưa chứng minh đã cấu hình quota thành công.

Secret được Windows DPAPI bảo vệ theo người dùng hiện tại. Tham số `-ExecutionPolicy Bypass` chỉ áp dụng cho tiến trình PowerShell đang chạy, không thay chính sách toàn máy.

<details>
<summary>Nâng cao: cấu hình bằng biến môi trường</summary>

Có thể cung cấp `ANTIGRAVITY_GOOGLE_CLIENT_ID` và `ANTIGRAVITY_GOOGLE_CLIENT_SECRET` trong môi trường của tiến trình Hub/daemon/MCP. Khi đủ cả hai biến, engine ưu tiên chúng; nếu thiếu, engine thử nạp file cấu hình cục bộ.

Không đưa secret vào mã nguồn hoặc lệnh được chia sẻ. Sau khi thay cấu hình, phải nạp lại các tiến trình. Lưu công việc rồi khởi động lại Windows là cách đơn giản để nạp lại cả daemon đã cài Startup.

</details>

### Bước 3 — Chạy Setup

Nhấp đúp **`Setup-Install.bat`**, hoặc chạy:

```powershell
.\Setup-Install.bat
```

Setup tạo thư mục `accounts/`, shortcut **Antigravity Auto-Hub** trên Desktop, shortcut **AntigravityAutoRotator** trong Windows Startup, rồi mở Hub và tiến trình giám sát nền (*daemon*).

Setup không cài Antigravity hoặc cấu hình OAuth thay bạn. Daemon là tiến trình người dùng, không phải Windows Service.

## Thêm tài khoản

### Cách 1 — Lưu tài khoản đang dùng

Khuyến nghị khi bắt đầu; cách này đã được người dùng xác nhận hoạt động.

1. Mở Antigravity chính thức và đăng nhập tài khoản muốn lưu.
2. Mở Hub, bấm **Lưu Acc Này**.
3. Kiểm tra email trên thẻ, rồi bấm **Quét Quota**.
4. Muốn lưu tài khoản tiếp theo, hoàn tất tác vụ, đổi tài khoản trong Antigravity chính thức và lặp lại bước 2–3.

**Lưu thành công không đồng nghĩa đọc quota thành công.** Tài khoản có thể đã được lưu nhưng vẫn hiện `N/A` do OAuth, mạng hoặc yêu cầu xác minh Google.

Lưu lại cùng tên file sẽ cập nhật bản cũ. Tên file lấy từ phần email trước `@`; các email khác miền nhưng trùng phần tên có thể ghi đè nhau, nên chưa dùng chúng chung trong pool.

### Cách 2 — Đăng nhập từ Hub

1. Bấm **+ Thêm Tài Khoản Mới**.
2. Chọn đúng tài khoản trong trình duyệt Google và hoàn tất đăng nhập.
3. Hoàn tất trang xác minh Google nếu được mở.
4. Chờ Hub thông báo đã thêm và xuất hiện thẻ tài khoản, rồi bấm **Quét Quota**.

Hub chạy helper riêng và cố khôi phục credential trước đó khi kết thúc. Có thể bấm **Hủy đăng nhập** hoặc **Hủy xác minh** để dừng. Giới hạn chờ: 30 giây lấy URL, 5 phút đăng nhập và tối đa 5 phút cho bước xác minh.

Google báo thành công chỉ xác nhận bước OAuth. Hub vẫn cần Antigravity xác nhận hợp lệ và token khớp email trước khi lưu. **Luồng này đã có kiểm thử tự động, nhưng chưa được xác nhận hoàn tất toàn bộ đăng nhập/xác minh/lưu tài khoản thật trong lần kiểm chứng gần nhất.** Nếu vướng lỗi, dùng Cách 1 và xem phần xử lý sự cố.

### Kiểm tra đã sẵn sàng xoay

- Có ít nhất **hai tài khoản khác nhau** trong danh sách.
- Tài khoản hiện tại có nhãn **ĐANG KẾT NỐI**.
- Quota tài khoản hiện tại và dự phòng đọc được thành phần trăm.
- Tài khoản dự phòng còn trên **20% quota 5H** và **10% quota tuần**.
- Daemon đang chạy, không có trạng thái yêu cầu kiểm tra.

Để thử thủ công lần đầu: chờ mọi tác vụ hoàn tất, gửi hoặc lưu bản nháp, chuyển sang cửa sổ Hub rồi bấm **Chuyển Thủ Công** trên tài khoản đích. Đợi kết quả trước khi bấm tiếp. Kiểm tra email trong Antigravity và thử một yêu cầu ngắn sau chuyển.

## Sử dụng hằng ngày

Mở shortcut Desktop hoặc nhấp đúp `Chuyen-Doi-Tai-Khoan.bat`.

| Nút / trạng thái | Ý nghĩa |
| --- | --- |
| **Quét Quota** | Đọc lại quota và thử đối chiếu trạng thái chuyển cần kiểm tra |
| **Lưu Acc Này** | Lưu credential Antigravity hiện tại |
| **+ Thêm Tài Khoản Mới** | Mở luồng đăng nhập qua helper riêng |
| **Chuyển Thủ Công** | Yêu cầu chuyển; vẫn áp dụng điều kiện quota, tác vụ, bản nháp và thời gian chờ |
| **Xác minh Google** | Mở liên kết xác minh; xong thì bấm Quét Quota |
| **ĐANG KẾT NỐI** | Email runtime hiện tại khớp tài khoản này |
| **Đã hoãn chuyển — xem lý do** | Đọc thông báo Windows hoặc rê chuột lên trạng thái để xem lý do |
| **Xóa** | Xóa file tài khoản khỏi pool sau xác nhận; không xóa tài khoản Google hoặc thu hồi quyền OAuth |
| **Mở thư mục** | Mở thư mục repo và log |

**Đóng Hub không tắt xoay tự động.** Daemon tiếp tục chạy và được Startup mở lại khi đăng nhập Windows. Quét quota gọi API theo từng tài khoản nên có thể mất thời gian; chờ lượt quét hoàn tất trước khi bấm lại.

## Xoay tự động

Sau Setup không cần bật thêm: daemon đã được khởi chạy. Chuyển chỉ diễn ra khi đủ điều kiện.

| Điều kiện mặc định | Giá trị |
| --- | --- |
| Tìm tài khoản thay thế | Quota 5H **< 20%** hoặc tuần **≤ 8%** |
| Tài khoản đích cho xoay tự động | Quota 5H **> 20%** và tuần **> 10%** |
| Ưu tiên | Quota 5H cao nhất, sau đó quota tuần cao nhất |
| Khoảng nghỉ giữa lượt quét | **25 giây sau khi lượt trước hoàn tất** |
| Khoảng chờ giữa lần chuyển | **120 giây** |

Ví dụ: A còn 19% quota 5H, B còn 80%. Daemon chuyển từ A sang B ngay trong lượt quét phát hiện quota thấp nếu Antigravity rảnh, không có bản nháp, B đạt ngưỡng quota tuần và đã hết thời gian chờ. Đúng 20% chưa kích hoạt điều kiện quota 5H. Nếu tác vụ còn chạy, Hub chờ lượt quét sau.

Quota được kiểm tra theo lượt quét, không theo từng request. Khoảng chờ 120 giây được tính theo UTC để không bị kéo dài do múi giờ Windows.

Engine xác minh danh tính, kiểm tra trạng thái rảnh, ghi credential đích, khởi động lại đúng tiến trình `language_server`, rồi xác minh email mới và khôi phục đường dẫn cửa sổ.

Các trường hợp hoãn:

- Có tác vụ chạy hoặc không xác định được trạng thái.
- Có bản nháp hoặc ô nhập đang được chọn trong cửa sổ Antigravity có focus. **Ô nhập trống ở cửa sổ nền không chặn chuyển.**
- Quota chưa đọc được, tài khoản đích chưa đủ quota hoặc còn thời gian chờ 120 giây.
- Có phiên đăng nhập/chuyển khác, nhiều runtime, thiếu CDP hoặc bản Antigravity không qua kiểm tra tương thích.

Đây là chuyển tài khoản Desktop giữa các lượt làm việc, **không phải proxy load balancer từng request**. Có khoảng nối lại; Hub không tự gửi lại prompt bị lỗi. Kiểm tra rảnh và restart không phải thao tác nguyên tử: vẫn có khoảng đua nếu bạn bắt đầu tác vụ ngay lúc chuyển. Khôi phục URL không khôi phục toàn bộ trạng thái trong RAM.

## Xử lý sự cố

| Hiện tượng | Cách xử lý |
| --- | --- |
| **Quota `N/A`** | Nghĩa là chưa đọc được dữ liệu, không phải 0%. Kiểm tra dòng trạng thái trên thẻ, OAuth và mạng |
| **Cần xác minh Google để đọc quota** | Bấm Xác minh Google, hoàn tất bằng đúng tài khoản, rồi Quét Quota. API có thể trả 403 `VALIDATION_REQUIRED` dù tài khoản đã được lưu |
| **Google thành công nhưng Hub báo `ineligible`** | Hoàn tất trang xác minh nếu Hub mở; nếu không có liên kết hỗ trợ, kiểm tra trong Antigravity chính thức. Mã này hoặc việc có AI Pro chưa đủ để kết luận nguyên nhân |
| **Thêm tài khoản không mở trình duyệt** | Chờ thông báo tối đa 30 giây; kiểm tra ứng dụng mở HTTPS mặc định, mạng và đường dẫn helper |
| **Lưu Acc Này không tìm thấy token** | Đăng nhập Antigravity chính thức bằng cùng người dùng Windows, chờ ứng dụng nhận tài khoản rồi thử lại |
| **Daemon chưa chạy** | Mở lại Hub hoặc chạy Setup; kiểm tra Windows có chặn PowerShell/`wscript.exe` không |
| **Quota thấp nhưng chưa xoay** | Chờ tác vụ, gửi/lưu bản nháp, chuyển focus sang Hub; kiểm tra quota dự phòng và thời gian chờ 120 giây |
| **Chuyển thủ công bị hoãn** | Đọc thông báo hoặc tooltip; chuyển thủ công không bỏ qua điều kiện bảo vệ |
| **IDE chưa hỗ trợ / chưa nhận diện** | Chờ Antigravity khởi động; dùng một runtime Desktop cục bộ. Nếu lỗi sau cập nhật, gửi phiên bản và log; không xóa kiểm tra tương thích |
| **Đổi OAuth nhưng vẫn lỗi** | Tiến trình cũ giữ cấu hình trong bộ nhớ. Lưu công việc rồi khởi động lại Windows để nạp lại |

### Trạng thái cần kiểm tra

| Trạng thái | Ý nghĩa |
| --- | --- |
| `Prepared` | Đã chuẩn bị credential khi IDE đóng; chưa xác minh runtime mới |
| `Switching` | Giao dịch chuyển chưa hoàn tất |
| `Verified` | Email runtime đã được xác minh hoặc đối chiếu thành công |
| `NeedsAttention` | Chuyển chưa được xác minh; tự động xoay tạm dừng |

Nếu `Switching` kéo dài hoặc `NeedsAttention`:

1. Đọc các dòng cuối `rotator.log` trong thư mục repo.
2. Hoàn tất/lưu công việc. Nếu runtime còn dùng tài khoản khác credential đã khôi phục, đóng và mở lại Antigravity.
3. Bấm **Quét Quota**, hoặc chạy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AutoRotator.ps1 -Reconcile
```

Lệnh chỉ đối chiếu danh tính và cập nhật trạng thái khi khớp; không ép chuyển hay restart IDE. Không xóa `rotation-state.json` để bỏ qua xác minh. Không dùng `-RunOnce` chỉ để xem trạng thái: lệnh có thể chuyển tài khoản thật.

Khi [báo lỗi](https://github.com/datdtpl-maker/Antigravity-Auto-Hub/issues), gửi phiên bản Antigravity, thao tác, thời điểm và đoạn log liên quan. Che email nếu cần; không gửi token, secret, URL xác minh có query hoặc thư mục tài khoản.

## Cập nhật và tắt chạy nền

### Cập nhật bản clone bằng Git

1. Chờ đăng nhập/chuyển tài khoản kết thúc, lưu công việc và đóng Hub.
2. Sao lưu dữ liệu riêng tư vào nơi chỉ bạn truy cập được nếu cần.
3. Trong thư mục repo, chạy:

```powershell
git status --short
git pull --ff-only
```

Nếu Git báo sửa đổi cục bộ hoặc không thể fast-forward, giữ nguyên dữ liệu và xử lý thay đổi trước; không dùng `reset --hard` để ép cập nhật.

4. Khởi động lại Windows sau khi lưu công việc để daemon nạp code mới, rồi mở Hub. Chỉ đóng/mở Hub không cập nhật daemon đang chạy.

Với ZIP: giải nén bản mới vào thư mục khác, giữ bản cũ làm sao lưu. Khi tiến trình cũ đã dừng, chuyển `accounts/` và cấu hình OAuth sang thư mục mới **trên cùng máy/người dùng Windows**, rồi chạy Setup ở đó. Không dùng cách này để bỏ qua trạng thái `NeedsAttention`; cần đối chiếu trạng thái trước. Không chạy hai bản Hub/daemon đồng thời.

### Tắt Startup hoặc gỡ Hub

1. Nhấn **Win + R**, nhập `shell:startup`, Enter.
2. Xóa shortcut **AntigravityAutoRotator** để ngừng tự chạy cùng Windows.
3. Chờ đăng nhập/chuyển hoàn tất, lưu công việc rồi đăng xuất Windows hoặc khởi động lại máy để dừng daemon hiện tại.

Mở Hub sẽ tự khởi chạy daemon dù đã xóa shortcut Startup. Muốn gỡ hẳn, sau khi dừng tiến trình hãy xóa shortcut Desktop và thư mục repo nếu không cần dữ liệu. Thao tác này không gỡ Antigravity hoặc đăng xuất Google trong ứng dụng chính thức.

## Kết nối MCP

Phần này **tùy chọn**. Bỏ qua nếu chỉ dùng giao diện Hub.

```powershell
# Chỉ đọc trạng thái và quota
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Configure-Mcp.ps1

# Cho phép thao tác chuyển tài khoản
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Configure-Mcp.ps1 -AllowSwitch
```

Script in JSON theo đường dẫn clone thực tế. Ghép riêng mục `antigravity-auto-hub` vào cấu hình client, giữ các server khác rồi khởi động lại kết nối. Script không tự sửa cấu hình ứng dụng khác.

| Tool | Quyền |
| --- | --- |
| `antigravity_status`, `antigravity_accounts` | Đọc trạng thái và quota |
| `antigravity_rotate_if_needed`, `antigravity_switch_account`, `antigravity_reconcile` | Cần `-AllowSwitch` |

Server dùng **stdio**, không có URL HTTP/SSE hoặc API model. Nó điều khiển Desktop của cùng người dùng Windows, không đổi token của MCP/proxy từ xa có kho riêng. **OmniLogin thực tế chưa được kiểm chứng.** Xem [MCP.md](MCP.md) để cấu hình và xử lý timeout.

## Dữ liệu và bảo mật

| Vị trí | Nội dung |
| --- | --- |
| `accounts/*.json` | Token tài khoản; file **không được Hub mã hóa DPAPI** |
| `oauth.local.clixml` | Cấu hình OAuth; secret được DPAPI bảo vệ |
| Windows Credential Manager | Credential Antigravity dùng chung |
| `%USERPROFILE%\.gemini\jetski-standalone-oauth-token` | Token dự phòng engine có thể ghi/khôi phục |
| `rotation-state.json`, `current_active.txt` | Trạng thái chuyển và nhãn tài khoản |
| `rotator.log` | Log vận hành, có thể chứa tên tài khoản/email |

`.gitignore` loại dữ liệu riêng tư và `work/` khỏi Git, nhưng **không ngăn phần mềm đồng bộ khác sao chép chúng**. Bảo vệ thư mục repo và bản sao lưu. DPAPI không mang sang máy/người dùng khác được; cần cấu hình lại tại đó.

Hub không chủ động sửa source, `.env` hoặc biến môi trường dự án. Tuy nhiên, credential dùng chung và restart language server ảnh hưởng phiên Antigravity. MCP chỉ trả trường được chọn, không trả token/CSRF. Source hiện tại không có client secret dùng sẵn; điều này không xóa dữ liệu có thể từng tồn tại trong lịch sử Git.

## Dành cho người phát triển

### Kiểm thử

Cần Windows PowerShell 5.1, WPF và Node.js:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\tests\Validate.ps1
```

Ngày **05/10/2026**, local đạt **156 mục PASS**, gồm kiểm tra bản Antigravity đã cài. Runner không cài Antigravity bỏ qua kiểm tra bản cài, còn **155 mục PASS**. Kiểm thử giao dịch dùng mock, không đổi tài khoản thật; có kiểm thử ngưỡng 20% và thời gian chờ khi đọc timestamp UTC từ file.

Workflow [Windows validation](.github/workflows/validate.yml) chạy khi push/PR. [CI bản sửa focus `6c99e18`](https://github.com/datdtpl-maker/Antigravity-Auto-Hub/actions/runs/36971936784) đã thành công.

### Mức độ kiểm chứng

| Hạng mục | Bằng chứng |
| --- | --- |
| Lưu Acc Này | Người dùng xác nhận hoạt động; file token đã kiểm tra hợp lệ |
| Quota, email runtime, trạng thái rảnh và ô nhập | Đã truy vấn trên máy thật |
| Chuyển tự động | Log 02/10/2026 12:56:17 xác nhận thành công; runtime, credential và state khớp. Chưa kiểm chứng lượt chat mới sau chuyển hoặc ép chuyển lại sau bản sửa focus |
| Thêm Tài Khoản Mới qua helper | Mở được Google và có bước chờ xác minh; test đạt. Chưa xác nhận toàn bộ luồng lưu tài khoản thật sau sửa |
| MCP stdio | Đã kiểm thử giao thức và đọc trạng thái thật; chưa kiểm chứng chuyển thật qua MCP/OmniLogin |

### Cấu trúc mã nguồn

| File / thư mục | Vai trò |
| --- | --- |
| `AntigravityHub.ps1`, `MainWindow.xaml` | Giao diện |
| `AccountLogin.ps1` | Helper đăng nhập và xác minh Google |
| `AutoRotator.ps1` | Cấu hình, Credential Manager, thông báo, daemon |
| `RotationCore.ps1` | Quota, chọn tài khoản, chuyển và khôi phục |
| `RuntimeBridge.ps1` | Runtime/CDP, kiểm tra rảnh và bản nháp |
| `AntigravityMcp.ps1` | MCP stdio |
| `Configure-OAuth.ps1`, `Configure-Mcp.ps1` | Thiết lập OAuth/MCP |
| `Setup-Install.bat`, `Setup.ps1`, `launch-*.vbs` | Cài shortcut và khởi chạy |
| `tests/` | Kiểm thử engine, đăng nhập, quota, cửa sổ và MCP |

PowerShell giữ ASCII, chuỗi tiếng Việt dùng mã Unicode; Markdown dùng UTF-8. Khi đóng góp, giữ điều kiện bảo vệ tác vụ/bản nháp, không commit credential và nêu rõ phần đã kiểm thử thực tế.
