# Runbook — PR Review Agent

## Connection Azure DevOps (thay cho rotate PAT — amendment 2026-07-13)
Flow không dùng PAT nữa: mọi call Azure DevOps đi qua connector **Azure
DevOps**, xác thực bằng connection sign-in — không có secret nào phải rotate
định kỳ. Khi account connection đổi mật khẩu / mất quyền / bị disable:
1. Mở flow **PR Review Pipeline** → ⋯ → Connections → **Sign in lại**
   connection Azure DevOps (bằng account bot — setup guide mục 0 bước 1).
2. Chạy tay flow với 1 PR test (setup guide mục 4) → run Succeeded, có
   comment trên PR.
   (Tuỳ chọn: `scripts/test-ado-access.ps1` vẫn dùng PAT riêng để gọi thử API
   khi debug — PAT đó chỉ phục vụ debug local, không liên quan flow.)

## Theo dõi chi phí (việc bắt buộc trong pilot — spec §8)
- Copilot Studio admin center → Capacity/Consumption: xem messages tiêu thụ theo agent.
- Sau tuần pilot đầu: ghi (số lượt review, tổng messages, quy ra $ theo bảng giá hiện hành)
  vào bảng dưới. Quyết định nhân rộng dựa trên số thực này.

| Tuần | Lượt review | Messages | Chi phí ước | Ghi chú |
|------|-------------|----------|-------------|---------|

## Sự cố thường gặp
- Run tay không ra comment trên PR: mở run history của flow **PR Review
  Pipeline** xem action nào fail. Lỗi 401/403 từ ADO API = connection hỏng
  hoặc account mất quyền → sign in lại connection (mục trên).
  (Hệ thống không có trigger tự động — amendment 2026-07-12 — nên không có
  service hook/trigger flow để kiểm tra.)
- Pipeline dừng sớm với comment "Không đọc được review rules từ OneNote"
  (hoặc dừng ở `Cond_RulesExist` trong run history): kiểm tra connection
  OneNote của flow còn hiệu lực, trang rules chưa bị xoá/di chuyển, nội dung
  trang không rỗng (setup guide mục 0 bước 2). Lưu ý: sửa trang rules có hiệu
  lực ngay lần chạy sau — rule không version cùng code (hạn chế đã biết,
  amendment 2026-07-12b).
- Comment sai dòng/"outdated": kiểm tra iteration mới nhất; nếu lặp lại, thêm
  pullRequestThreadContext.iterationContext vào HTTP_PostThread (xem flow spec).
- Vi phạm tái xuất hiện sau khi bot đã tự resolve ở lần chạy trước: thread cũ không được mở lại (nguyên tắc never-reopen) và lần chạy mới đếm nó vào "User tự resolve" trong summary — hạn chế đã biết của pilot. Xử lý: dev mở lại thread thủ công nếu muốn track tiếp.
- Hai vi phạm giống hệt nhau trong cùng file (cùng rule, cùng đoạn code, khác dòng): fingerprint trùng nhau nên chỉ dedupe được 1 thread; fix một chỗ sẽ không tự resolve thread (vi phạm còn lại vẫn giữ fingerprint sống). Hạn chế đã biết của pilot — xử lý thủ công.

## Nợ bảo mật pilot (bắt buộc xử lý trước khi nhân rộng)
- ~~`prv_ADO_PAT` đang là env var Text — nâng lên KV-backed Secret~~ **Đã
  giải quyết** (amendment 2026-07-13): flow không dùng PAT — xác thực qua
  connection Azure DevOps. Việc còn lại trước khi nhân rộng: chuyển connection
  sang service account riêng nếu pilot đang sign-in bằng account cá nhân
  (setup guide mục 0 bước 1).

## Data residency (việc mở — spec §7)
- Xác nhận region của Power Platform environment (admin center → Environments)
  đáp ứng yêu cầu compliance trước khi nhân rộng.
