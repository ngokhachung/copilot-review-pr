# Solution export

Backup solution sau mỗi thay đổi flow/prompt:
Power Apps → Solutions → PR Review Agent → Export solution → **Unmanaged**
→ lưu file zip vào thư mục này và commit.

Lưu ý: giá trị env var chứa PAT/webhook secret hiện là Text (pilot) và **có thể
nằm trong export** — trước khi export, xoá "Current value" của `prv_ADO_PAT` và
`prv_WEBHOOK_BASIC` trong solution (giữ default trống), export xong điền lại.
Kiểm tra file `environmentvariablevalues.json` trong zip không chứa secret
trước khi commit.
