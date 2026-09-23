# Bàn giao Antigravity Auto-Hub — 09/09/2026

## Tương thích Antigravity 2.15.1 — 23/09/2026

Tái hiện lỗi `IDE 2.15.1.0: chưa hỗ trợ` trên bản cài thực tế. Đối chiếu `dist/languageServer.js` và `dist/main.js` từ app.asar 2.15.1 với bản trích xuất 2.14.0: nội dung không đổi sau chuẩn hóa xuống dòng. Bổ sung chính xác 2.15.1/2.15.1.0; vẫn chặn bản chưa kiểm tra như 2.15.0.0, 2.15.1.1 và 2.15.2.0.

Kiểm thử tương thích thất bại trước sửa, đạt sau sửa. Bộ kiểm tra local đạt 74/74, parser/ASCII và WPF đạt. API thật xác minh được danh tính một runtime, trạng thái idle và CDP trả về `Safe=True`. Chưa thực hiện chuyển tài khoản thật xuyên suốt; bản sửa chưa chạy CI.

Đã nạp lại Hub/daemon, xác minh mỗi loại có một tiến trình. Log chu kỳ mới lúc 10:11:51 nhận diện tài khoản active và đọc quota 5H=100%, week=100%; không còn bị chặn ở bước kiểm tra phiên bản.

## Sửa nhãn daemon — 17/09/2026

Hub báo `Daemon chưa chạy` dù tiến trình nền vẫn quét quota. Nguyên nhân: khi truy vấn CIM chỉ trả một tiến trình, đối tượng đơn không có `.Count` trên Windows PowerShell 5.1. `Get-DaemonStatus` được sửa để luôn dùng mảng trước khi đếm. Kiểm thử hồi quy dùng đối tượng CIM thật trong bộ giả lập truy vấn, kiểm tra 0/1/2 tiến trình; trường hợp 1 thất bại trước sửa và đạt sau sửa. Bộ kiểm tra local đạt 69/69; kiểm tra trên daemon đang chạy trả về `True`.

## Tương thích Antigravity 2.14.0 — 17/09/2026

Sửa lỗi `IDE 2.14.0.0: chưa hỗ trợ` bằng cách thêm chính xác 2.14.0 và 2.14.0.0 vào whitelist. `dist/languageServer.js` và `dist/main.js` trong app.asar đang cài không đổi so với bản trích xuất 2.13.0 trước đó. Vẫn chặn các bản chưa xác minh như 2.14.1 hoặc revision khác 0.

Bộ kiểm tra local đạt 66/66, gồm parser/ASCII và nạp WPF. API thật đọc được email, trạng thái idle và CDP trả về trạng thái ô nhập không an toàn để chuyển. Không ép chuyển tài khoản; chưa kiểm chứng chuyển thật xuyên suốt. Bản sửa này chưa chạy CI.

Đã đóng Hub bình thường và nạp lại Hub/daemon; xác minh mỗi loại chỉ có một tiến trình. Log chu kỳ mới lúc 09:25:37 đọc được quota tài khoản active: 5H=60%, week=75%, không còn bị chặn bởi phiên bản 2.14.0.0.

## MCP — 16/09/2026

Thêm `AntigravityMcp.ps1` (stdio JSON-RPC, mặc định chỉ đọc) và `Configure-Mcp.ps1` (sinh cấu hình portable). Các mutation yêu cầu `-AllowSwitch`, vẫn đi qua engine/khóa giao dịch hiện có. Tài liệu `MCP.md` mô tả cách clone, OAuth, cấu hình và giới hạn. Chỉ điều khiển Desktop cục bộ; chưa có adapter đổi token của một MCP Antigravity độc lập. Chưa kiểm chứng OmniLogin; không quảng bá cấu hình stdio là endpoint HTTP hay proxy model. `tests/Mcp.Tests.ps1` kiểm thử giao thức, bảo mật projection và tiến trình stdio từ thư mục không có credential.

## Cập nhật 15/09/2026

Antigravity cập nhật lên 2.13.0.0 khiến whitelist 2.12.2 cũ chặn nhận diện, dù quota vẫn đọc được. Đã kiểm tra code giám sát/khởi động lại language server và nối lại cửa sổ trong app.asar 2.13.0; bổ sung phiên bản này vào danh sách hỗ trợ chính xác, không mở cho mọi bản tương lai. API thật xác minh được email và trạng thái idle. Hub/log hiển thị rõ phiên bản chưa hỗ trợ thay vì nuốt lỗi. Bộ kiểm thử local tăng lên 35, parser/ASCII và WPF đều đạt. Chưa dùng việc nhận diện thành công làm bằng chứng chuyển tài khoản thật.

Repo: `D:\AntigravityAccounts`, remote `https://github.com/datdtpl-maker/Antigravity-Auto-Hub.git`, nhánh `main`. Bản trước sửa: `1c1b2de`. Tài liệu cũ nằm trong lịch sử Git tại commit đó.

## Kết luận về bản cũ

- Chỉ ghi token rồi nhắc F5. Không xác minh runtime đổi email.
- Quota thiếu bị coi là 100%; lỗi mạng có thể kích hoạt xoay.
- Fallback có thể xoay qua lại giữa tài khoản hết quota.
- Delta quota không chứng minh tài khoản của IDE cục bộ.
- Bỏ qua kết quả ghi Credential Manager; thiếu rollback/khóa giao dịch chung.
- Client secret XOR trong source không phải mã hóa bảo mật.

## Kiến trúc đã xác minh

Máy chạy **Antigravity Desktop 2.12.2**, không có bố cục VS Code `resources/app` như tài liệu cũ. Electron trong `resources/app.asar` quản lý language server, tự khởi động lại child khi child thoát và tải lại cửa sổ khi cổng thay đổi.

API đọc qua HTTPS localhost + CSRF của đúng tiến trình: `GetUserStatus`, `GetAllCascadeTrajectories`. Không ghi CSRF/token vào log. CDP kiểm tra boolean bản nháp/ô nhập và giữ đường dẫn cửa sổ. Cổng debugger phải thuộc PID cha của language server.

Không tìm thấy RPC thay token trong service descriptor đã kiểm tra. Có message `SaveOAuthTokenInfoRequest` trong bundle không có nghĩa service công bố endpoint đó. Không dùng endpoint phỏng đoán hoặc coi `Page.reload` là bằng chứng đổi đăng nhập.

## Luồng mới

`quota thấp → xác minh runtime → idle + không nhập dở → khóa giao dịch → refresh token đích → Switching → ghi/read-back credential → restart đúng child → xác minh email → khôi phục URL → Verified`.

- IDE đóng: chuyển thủ công chỉ tạo `Prepared`.
- Thiếu quota/runtime/CDP, nhiều runtime hoặc phiên bản khác: không chuyển.
- Lỗi sau ghi: khôi phục credential cũ, giữ nhãn active cũ, `NeedsAttention`; không restart hàng loạt.
- `-Reconcile`/“Quét Quota” chỉ tiếp tục khi runtime và credential khớp.
- Giữ bản nháp bằng cách hoãn; không đảm bảo nối lại request đang chạy. Có khoảng nối lại, không tương đương proxy load balancer.
- Có khoảng đua giữa kiểm tra idle và restart vì IDE không cung cấp khóa nhận prompt mới. Không mô tả là không gián đoạn tuyệt đối.

## Kiểm chứng và việc còn lại

Xem README cho module, cấu hình DPAPI và lệnh kiểm tra. 26 kiểm thử mock + PowerShell 5.1 parser/ASCII + WPF XAML đã đạt. Đã đọc quota thật cả 5 tài khoản, runtime email và kiểm tra CDP.

**Còn cần kiểm thử thực tế:** chuyển khi mọi agent idle, không có ô nhập đang chọn/nội dung chưa gửi; đối chiếu email trước/sau, URL và một lượt làm việc mới. Phiên nâng cấp không ép dừng tác vụ đang chạy để thực hiện bước này. Luồng thêm tài khoản tương tác chưa được kiểm thử lại.

## Quy tắc duy trì

- PowerShell giữ ASCII 7-bit, tiếng Việt dùng mã Unicode trong chuỗi; Markdown UTF-8.
- Không commit `accounts/`, `oauth.local.clixml`, log, trạng thái hoặc `work/`.
- Không xuất token/CSRF/raw HTTP auth response trong công cụ hoặc log.
- Kiểm tra phiên bản Antigravity trước khi mở rộng whitelist restart.
- Không chạy `-RunOnce` để xem trạng thái: lệnh có thể chuyển tài khoản thật khi đủ điều kiện. Dùng hàm đọc và chỉ xuất trường an toàn.
