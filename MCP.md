# Dùng Antigravity Auto-Hub qua MCP

Repo cung cấp **MCP server stdio cho Windows**, dùng chung pool tài khoản và engine xoay của Hub. Không cần Node.js, Python hay cài thư viện MCP để chạy; chỉ cần Windows PowerShell 5.1.

## Phạm vi tích hợp

MCP này điều khiển **Antigravity Desktop trên cùng máy và cùng người dùng Windows**. Nếu OmniLogin gọi đúng phiên Desktop đó, có thể kết nối thêm server `antigravity-auto-hub` để xem quota và yêu cầu xoay tài khoản.

Nếu “Antigravity MCP” của bạn là một server riêng, proxy/API hay dịch vụ từ xa có kho token riêng, repo này **chưa đổi được tài khoản của server đó**. Cần adapter theo API đăng nhập, trạng thái đang chạy và cách xác minh tài khoản của nó. Chỉ thêm MCP Auto-Hub không tự kết nối vào một MCP khác.

Chưa xác minh OmniLogin hỗ trợ cấu hình MCP stdio dưới đây. Client phải cho phép chạy lệnh MCP cục bộ. Client chỉ nhận URL HTTP/SSE không thể dùng trực tiếp cấu hình này; bản hiện tại không mở cổng HTTP và không có endpoint `/mcp`.

## 1. Chuẩn bị sau khi clone

```powershell
git clone https://github.com/datdtpl-maker/Antigravity-Auto-Hub.git
cd Antigravity-Auto-Hub
powershell.exe -NoProfile -File .\Configure-OAuth.ps1
.\Setup-Install.bat
```

1. Cài Antigravity Desktop bản được hỗ trợ: 2.12.2, 2.13.0 hoặc 2.14.0 (bao gồm hậu tố `.0`).
2. Cấu hình OAuth client tương thích với refresh token của bạn. Không dùng credential của tác giả repo.
3. Mở Hub, đăng nhập và lưu các tài khoản Google vào pool trên máy bạn.
4. Để Antigravity Desktop đang mở. Không dùng phiên bản không hỗ trợ hoặc nhiều runtime đồng thời.

Không copy `oauth.local.clixml` sang người dùng/máy khác: DPAPI gắn với người dùng Windows. Có thể cấu hình hai biến môi trường OAuth như README; MCP không nhận hoặc trả token qua tool arguments/results.

## 2. Tạo cấu hình cho đúng thư mục clone

Chạy trong thư mục repo:

```powershell
# Chỉ đọc trạng thái và quota
powershell.exe -NoProfile -File .\Configure-Mcp.ps1

# Cho phép MCP yêu cầu chuyển tài khoản
powershell.exe -NoProfile -File .\Configure-Mcp.ps1 -AllowSwitch
```

Lệnh in JSON `mcpServers` với đường dẫn tuyệt đối của máy hiện tại. Ghép riêng mục `antigravity-auto-hub` vào cấu hình MCP hiện có, giữ các server khác. Nếu client dùng form thay vì JSON, lấy `command` và từng phần tử `args` từ kết quả. Không gộp toàn bộ `args` thành một đối số.

Ví dụ cho thư mục `D:\AntigravityAccounts`:

```json
{
  "mcpServers": {
    "antigravity-auto-hub": {
      "command": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
      "args": [
        "-NoLogo", "-NoProfile", "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-File", "D:\\AntigravityAccounts\\AntigravityMcp.ps1",
        "-AllowSwitch"
      ]
    }
  }
}
```

Khởi động lại kết nối MCP sau khi thêm cấu hình. Server chỉ hoạt động qua stdin/stdout do MCP client quản lý; chạy lệnh server trực tiếp rồi thấy cửa sổ chờ nhập là bình thường. Script sinh cấu hình không tự sửa file cấu hình OmniLogin.

## 3. Các lệnh MCP

| Tool | Chức năng |
|---|---|
| `antigravity_status` | Email runtime, idle, trạng thái giao dịch; không lộ token/CSRF |
| `antigravity_accounts` | Tên tài khoản, email, quota; dữ liệu chưa biết trả `null` |
| `antigravity_rotate_if_needed` | Chạy một lần kiểm tra và chỉ xoay khi quota thấp, IDE rảnh, không nhập dở |
| `antigravity_switch_account` | Chuyển tới `account` lấy từ danh sách, vẫn áp dụng toàn bộ điều kiện an toàn |
| `antigravity_reconcile` | Đối chiếu credential/runtime để gỡ trạng thái cần kiểm tra |

Ba lệnh cuối chỉ xuất hiện và thực thi khi server khởi động với `-AllowSwitch`. Quyền này cho phép MCP client đổi tài khoản dùng chung của Antigravity trên máy; áp dụng chính sách duyệt tool của client theo nhu cầu.

Ví dụ yêu cầu cho AI trong client: “Đọc trạng thái và quota Antigravity, kiểm tra xoay nếu quota thấp. Nếu bị hoãn thì báo lý do, không cố ép chuyển.”

`checkCompleted: true` chỉ có nghĩa hoàn tất kiểm tra, không có nghĩa đã đổi tài khoản. Với lệnh chuyển, xem `operationAccepted` và `status.rotation.status`: `Prepared` chỉ chuẩn bị cho lần mở IDE, `Verified` mới là engine đã xác minh runtime. Idle không đồng nghĩa ô nhập đã an toàn; engine còn kiểm tra CDP trước khi chuyển.

## Tự động, thời gian chờ và giới hạn

- **Tự động nền:** daemon do Setup cài vẫn theo dõi quota và dùng cùng mutex với MCP. MCP server không tự khởi chạy thêm daemon.
- **Theo workflow:** client có thể gọi `antigravity_rotate_if_needed` giữa các lượt làm việc. Nếu đang chạy agent, engine hoãn chuyển; không thể chuyển ngay trong lúc một prompt của Antigravity đang chờ tool này.
- Chuyển tài khoản có thể khởi động lại language server, gây khoảng nối lại. Không tự chạy lại prompt/workflow thất bại.
- Quota gọi Google theo từng tài khoản nên có thể mất nhiều thời gian. Đặt timeout tool của client đủ dài (khuyến nghị ít nhất 300 giây cho pool 5 tài khoản). Timeout phía client không hoàn tác một giao dịch đã bắt đầu; đọc trạng thái trước khi thử lại.
- Server xử lý tuần tự; notification `notifications/cancelled` không hủy giao dịch credential đang chạy. Đợi kết quả/trạng thái, không kill server giữa giao dịch.
- Không cung cấp API model/OpenAI-compatible, không proxy prompt, không tạo profile OmniLogin và không thay token riêng của nhà cung cấp MCP khác.

## Kiểm chứng

```powershell
powershell.exe -NoProfile -STA -File .\tests\Validate.ps1
```

Bộ kiểm tra gồm giao thức initialize/tools/ping, quyền chỉ đọc, validation, không lộ credential, lỗi engine, và tiến trình stdio thật từ thư mục có dấu cách, không chứa credential. Các thao tác chuyển trong kiểm thử dùng mock; chúng không xác nhận chuyển tài khoản thật hoặc kết nối OmniLogin thực tế.

Ngày 16/09/2026: 61 kiểm thử local đạt; lệnh MCP `antigravity_status` qua stdio thật đã đọc được runtime Desktop trên máy phát triển ở chế độ chỉ đọc. Chưa kiểm thử OmniLogin hoặc chuyển tài khoản thật qua MCP.
