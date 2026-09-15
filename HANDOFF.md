# Bàn giao Antigravity Auto-Hub — 09/09/2026

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
