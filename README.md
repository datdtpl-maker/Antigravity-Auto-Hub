# Antigravity Auto-Hub

Quản lý tài khoản Google và chuyển tài khoản khi quota thấp trên Windows. Tích hợp với **Antigravity Desktop 2.12.2 / 2.13.0** và Windows PowerShell 5.1.

## Khả năng và giới hạn

Hub kiểm tra quota, chờ tác vụ rảnh, nạp credential mới, khởi động lại **language_server do Antigravity quản lý**, khôi phục đường dẫn cửa sổ và xác minh email bằng API của phiên IDE mới. Không cần bấm F5 để áp dụng token.

Đây là chuyển tài khoản giữa các lượt làm việc, **không phải proxy cân bằng tải từng request**. Có khoảng nối lại khi tiến trình khởi động. Không bảo đảm quota luôn 100%, không bảo đảm prompt đang chạy tiếp tục bằng tài khoản khác, và không tự gửi lại prompt.

- Xoay khi quota Gemini 5H ≤ 12% hoặc tuần ≤ 8%.
- Chọn tài khoản có 5H > 15% và tuần > 10%, ưu tiên quota cao nhất.
- Quota thiếu, lỗi mạng, email không rõ hoặc pool cạn: giữ nguyên.
- Tác vụ đang chạy, trạng thái không nhận diện được, ô nhập đang được chọn hoặc có nội dung chưa gửi: hoãn chuyển.
- Xác minh PID, cổng localhost, phiên bản và email; không suy đoán qua biến động quota.
- Chỉ hỗ trợ một runtime desktop. Phiên bản ngoài 2.12.2 / 2.13.0 hoặc thiếu CDP: hoãn chuyển. Hub hiển thị rõ phiên bản chưa hỗ trợ.
- Cooldown 120 giây lưu trên đĩa; mutex chung giữa daemon, chuyển thủ công và thêm tài khoản.
- Ghi credential thất bại hoặc không xác minh được phiên mới: cố khôi phục credential cũ và chuyển trạng thái `NeedsAttention`.

Kiểm tra trạng thái rảnh và dừng tiến trình không phải một thao tác nguyên tử của IDE. Tránh bắt đầu tác vụ mới trong khoảng chuyển. Khôi phục URL không sao lưu mọi trạng thái trong RAM; cơ chế giữ bản nháp là hoãn chuyển, không sao chép nội dung.

## Cài đặt và OAuth

```powershell
git clone https://github.com/datdtpl-maker/Antigravity-Auto-Hub.git
cd Antigravity-Auto-Hub
.\Setup-Install.bat
```

Setup tạo shortcut Desktop/Startup và chạy daemon ẩn. Chu kỳ nghỉ mặc định 25 giây **sau mỗi lần quét**; thời gian gọi API cộng thêm vào chu kỳ.

Không còn client secret XOR trong source. Dùng OAuth client tương thích với refresh token:

```powershell
powershell.exe -NoProfile -File .\Configure-OAuth.ps1
```

Script hỏi client ID/secret, lưu `oauth.local.clixml` bằng Windows DPAPI cho người dùng Windows hiện tại. Khởi động lại Hub/daemon sau khi cấu hình. Có thể dùng biến môi trường `ANTIGRAVITY_GOOGLE_CLIENT_ID` và `ANTIGRAVITY_GOOGLE_CLIENT_SECRET`. Không đưa secret lên dòng lệnh, Git hoặc log.

Trên máy đã nâng cấp, cấu hình cũ được chuyển sang file DPAPI cục bộ. Clone mới không chứa cấu hình này. Refresh token đã cấp cho một client không thể dùng tùy ý với client khác.

## Sử dụng

Mở `Chuyen-Doi-Tai-Khoan.bat`. Thêm tài khoản qua trình đăng nhập Google có sẵn hoặc “Lưu Acc Này”. Tài khoản mới được lưu vào pool; bước thêm tài khoản khôi phục lựa chọn credential trước khi đăng nhập và không tự khởi động lại IDE. Không đóng cưỡng bức Hub trong lúc đăng nhập.

“Chuyển Thủ Công” cũng kiểm tra quota, tác vụ và bản nháp. Khi IDE đóng, tài khoản chỉ được đánh dấu `Prepared` cho lần khởi động sau, chưa được báo đang kết nối. “Quét Quota” cập nhật trạng thái và thử đối chiếu giao dịch cần kiểm tra.

### Khôi phục sau chuyển không thành công

Xem `rotator.log` và `rotation-state.json`. Nếu credential đã khôi phục nhưng runtime còn dùng tài khoản khác, hoàn tất công việc rồi đóng/mở Antigravity. Bấm “Quét Quota”, hoặc chạy:

```powershell
powershell.exe -NoProfile -File .\AutoRotator.ps1 -Reconcile
```

Lệnh chỉ bỏ trạng thái chờ khi email runtime khớp credential và tài khoản trong pool. Không ép đổi tài khoản, khởi động lại hoặc bỏ qua xác minh.

## Kiểm tra

```powershell
powershell.exe -NoProfile -STA -File .\tests\Validate.ps1
```

Kiểm tra cú pháp/ASCII PowerShell, nạp WPF XAML và 35 kiểm thử quyết định/giao dịch/tương thích phiên bản. Kiểm thử dùng file tạm trong `work/` và mock credential/process, không đổi tài khoản thật. GitHub Actions chạy cùng bộ kiểm tra trên Windows.

**Bằng chứng ngày 09/09/2026:** đọc được email runtime, trạng thái tác vụ, boolean ô nhập qua CDP và quota thật của 5 tài khoản. Chưa kiểm thử chuyển tài khoản thật xuyên suốt vì IDE có tác vụ hoạt động và cửa sổ chưa đạt điều kiện chuyển. Đăng nhập Google tương tác cũng chưa được kiểm thử lại trong phiên nâng cấp này. Không coi kiểm thử mock là bằng chứng chuyển thành công trên IDE thật.

## Cấu trúc

| File | Vai trò |
|---|---|
| `AutoRotator.ps1` | Cấu hình, Credential Manager, toast, daemon singleton |
| `RotationCore.ps1` | Quota, lựa chọn, giao dịch, rollback, đối chiếu trạng thái |
| `RuntimeBridge.ps1` | API localhost, runtime, CDP, chờ rảnh và nối lại |
| `AntigravityHub.ps1`, `MainWindow.xaml` | Hub tài khoản |
| `Configure-OAuth.ps1` | Cấu hình OAuth được DPAPI mã hóa |
| `tests/` | Kiểm thử Windows |

`accounts/`, cấu hình OAuth, log, trạng thái và `work/` được loại khỏi Git. Token tài khoản vẫn là file cục bộ: bảo vệ tài khoản Windows và thư mục này. Loại secret khỏi source hiện tại không xóa lịch sử Git cũ.
