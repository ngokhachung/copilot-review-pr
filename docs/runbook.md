# Runbook — PR Review Agent

## Rotate PAT (mỗi 90 ngày — đặt reminder lịch!)
1. Đăng nhập svc-pr-review → tạo PAT mới (Code Read & Write, 90 ngày).
2. Power Apps → solution PR Review Agent → env var `prv_ADO_PAT` → cập nhật giá trị secret.
3. Chạy `scripts/test-ado-access.ps1` với PAT mới → 2 PASS.
4. Comment `/review` lên 1 PR test → bot phản hồi bình thường → revoke PAT cũ.

## Theo dõi chi phí (việc bắt buộc trong pilot — spec §8)
- Copilot Studio admin center → Capacity/Consumption: xem messages tiêu thụ theo agent.
- Sau tuần pilot đầu: ghi (số lượt /review, tổng messages, quy ra $ theo bảng giá hiện hành)
  vào bảng dưới. Quyết định nhân rộng dựa trên số thực này.

| Tuần | Lượt review | Messages | Chi phí ước | Ghi chú |
|------|-------------|----------|-------------|---------|

## Sự cố thường gặp
- Bot không phản hồi: kiểm tra Service hooks history (ADO) → flow run history (trigger flow)
  → run history pipeline. Lỗi 401 từ ADO API = PAT hết hạn → rotate.
- Comment sai dòng/"outdated": kiểm tra iteration mới nhất; nếu lặp lại, thêm
  pullRequestThreadContext.iterationContext vào HTTP_PostThread (xem flow spec).
- Muốn tắt khẩn cấp: disable service hook (ADO) hoặc turn off trigger flow.
- Vi phạm tái xuất hiện sau khi bot đã tự resolve ở lần chạy trước: thread cũ không được mở lại (nguyên tắc never-reopen) và lần chạy mới đếm nó vào "User tự resolve" trong summary — hạn chế đã biết của pilot. Xử lý: dev mở lại thread thủ công nếu muốn track tiếp.
- Hai vi phạm giống hệt nhau trong cùng file (cùng rule, cùng đoạn code, khác dòng): fingerprint trùng nhau nên chỉ dedupe được 1 thread; fix một chỗ sẽ không tự resolve thread (vi phạm còn lại vẫn giữ fingerprint sống). Hạn chế đã biết của pilot — xử lý thủ công.

## Nợ bảo mật pilot (bắt buộc xử lý trước khi nhân rộng)
- `prv_ADO_PAT` và `prv_WEBHOOK_BASIC` đang là env var Text. Nâng lên Secret
  backed by Azure Key Vault; flow đọc qua action Dataverse
  `RetrieveEnvironmentVariableSecretValue` (sửa 2 flow tại các chỗ dùng
  `parameters('prv_ADO_PAT')` / `parameters('prv_WEBHOOK_BASIC')`).

## Data residency (việc mở — spec §7)
- Xác nhận region của Power Platform environment (admin center → Environments)
  đáp ứng yêu cầu compliance trước khi nhân rộng.
