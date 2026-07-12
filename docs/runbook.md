# Runbook — PR Review Agent

## Rotate PAT (mỗi 90 ngày — đặt reminder lịch!)
1. Đăng nhập account bot (svc-pr-review, hoặc account cá nhân nếu pilot dùng
   PAT cá nhân — xem setup guide mục 0) → tạo PAT mới (Code Read & Write, 90 ngày).
2. Power Apps → solution PR Review Agent → env var `prv_ADO_PAT` → cập nhật giá trị.
3. Chạy tay flow **PR Review Pipeline** với 1 PR test (setup guide mục 3) →
   run Succeeded, có comment trên PR → revoke PAT cũ.
   (Tuỳ chọn: `scripts/test-ado-access.ps1` kiểm tra PAT nhanh nếu máy có PowerShell.)

## Theo dõi chi phí (việc bắt buộc trong pilot — spec §8)
- Copilot Studio admin center → Capacity/Consumption: xem messages tiêu thụ theo agent.
- Sau tuần pilot đầu: ghi (số lượt review, tổng messages, quy ra $ theo bảng giá hiện hành)
  vào bảng dưới. Quyết định nhân rộng dựa trên số thực này.

| Tuần | Lượt review | Messages | Chi phí ước | Ghi chú |
|------|-------------|----------|-------------|---------|

## Sự cố thường gặp
- Run tay không ra comment trên PR: mở run history của flow **PR Review
  Pipeline** xem action nào fail. Lỗi 401 từ ADO API = PAT hết hạn → rotate.
  (Hệ thống không có trigger tự động — amendment 2026-07-12 — nên không có
  service hook/trigger flow để kiểm tra.)
- Comment sai dòng/"outdated": kiểm tra iteration mới nhất; nếu lặp lại, thêm
  pullRequestThreadContext.iterationContext vào HTTP_PostThread (xem flow spec).
- Vi phạm tái xuất hiện sau khi bot đã tự resolve ở lần chạy trước: thread cũ không được mở lại (nguyên tắc never-reopen) và lần chạy mới đếm nó vào "User tự resolve" trong summary — hạn chế đã biết của pilot. Xử lý: dev mở lại thread thủ công nếu muốn track tiếp.
- Hai vi phạm giống hệt nhau trong cùng file (cùng rule, cùng đoạn code, khác dòng): fingerprint trùng nhau nên chỉ dedupe được 1 thread; fix một chỗ sẽ không tự resolve thread (vi phạm còn lại vẫn giữ fingerprint sống). Hạn chế đã biết của pilot — xử lý thủ công.

## Nợ bảo mật pilot (bắt buộc xử lý trước khi nhân rộng)
- `prv_ADO_PAT` đang là env var Text. Nâng lên Secret backed by Azure Key
  Vault; flow đọc qua action Dataverse
  `RetrieveEnvironmentVariableSecretValue` (sửa flow PR Review Pipeline tại
  các chỗ dùng `parameters('prv_ADO_PAT')`).

## Data residency (việc mở — spec §7)
- Xác nhận region của Power Platform environment (admin center → Environments)
  đáp ứng yêu cầu compliance trước khi nhân rộng.
