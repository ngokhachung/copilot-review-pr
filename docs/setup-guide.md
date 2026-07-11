# Setup guide — AI PR Review Agent (Copilot Studio)

Hướng dẫn cấu hình Power Platform / Copilot Studio cho AI PR Review Agent trên
Azure DevOps. Tài liệu này là **hướng dẫn đầy đủ**, gồm 5 mục: (1) tạo
solution, agent (vỏ chứa) và toàn bộ environment variable; (2) Prompt node
(AI Builder); (3) service hook; (4) trigger flow; (5) kiểm tra sau setup.

## Điều kiện tiên quyết

- Đã tạo service account `svc-pr-review` trên Azure DevOps và có PAT của tài
  khoản này (Task 1) — copy `scripts/ado-env.sample.ps1` thành
  `scripts/ado-env.ps1`, điền `ADO_ORG_URL`, `ADO_PROJECT`, `ADO_REPO`,
  `ADO_PAT`.
- Đã chạy `scripts/test-ado-access.ps1` thành công — dòng
  `PASS: repo '<name>' (id <GUID>, ...)` cho biết **repo GUID**, cần dùng lại
  ở mục 1 bên dưới (biến `prv_ADO_REPO_ID`).
- Có quyền tạo solution mới trên môi trường Power Platform (make.powerapps.com)
  dự định dùng cho pilot.

## 1. Solution & environment variables

1. Vào **Power Apps** (make.powerapps.com) → chọn đúng environment → menu
   **Solutions → New solution**: đặt tên `PR Review Agent`, tạo publisher mới
   với prefix `prv`.
2. Trong solution vừa tạo → **New → Agent (Copilot Studio)**: đặt tên
   `PR Review Agent`. Không cần tạo topic hay knowledge — agent ở bước này chỉ
   là vỏ chứa để nhóm flows lại và phục vụ quản lý/billing.
3. Trong solution → **New → More → Environment variable**, tạo lần lượt các
   biến sau (Data type **Text** trừ khi ghi chú khác):

   | Tên biến | Data type | Giá trị mẫu | Lấy ở đâu |
   |---|---|---|---|
   | `prv_ADO_ORG_URL` | Text | `https://dev.azure.com/<org>` | URL tổ chức Azure DevOps |
   | `prv_ADO_PROJECT` | Text | tên project | Tên project Azure DevOps chứa repo pilot |
   | `prv_ADO_REPO_ID` | Text | *(repo GUID)* | Repo **GUID** — từ Task 1 Step 6, đọc trong output của `scripts/test-ado-access.ps1` |
   | `prv_RULES_PATH` | Text | `.review/rules.md` | Cố định — đường dẫn tới file rule (xem `templates/rules.md`) trong repo |
   | `prv_TRIGGER_KEYWORD` | Text | `/review` | Cố định |
   | `prv_MAX_FILES` | Number | `30` | Cố định — cap an toàn số file/lần review |
   | `prv_MAX_LINES` | Number | `3000` | Cố định — cap an toàn số dòng thay đổi/lần review |
   | `prv_BOT_ACCOUNT_ID` | Text | *(GUID của user `svc-pr-review`)* | Chạy script ở mục "Lấy `prv_BOT_ACCOUNT_ID`" bên dưới |
   | `prv_ADO_PAT` | Text | *(PAT của `svc-pr-review`)* | PAT tạo ở Task 1 — xem "Lưu ý pilot" bên dưới |
   | `prv_WEBHOOK_BASIC` | Text | `base64("hookuser:<mật khẩu ngẫu nhiên>")` | Tạo bằng script ở mục "Lấy `prv_WEBHOOK_BASIC`" bên dưới |

   ### Lấy `prv_BOT_ACCOUNT_ID`

   ```powershell
   . .\scripts\ado-env.ps1
   $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($env:ADO_PAT)"))
   (Invoke-RestMethod -Uri "$($env:ADO_ORG_URL)/_apis/connectionData" -Headers @{Authorization="Basic $b64"}).authenticatedUser.id
   ```

   ### Lưu ý pilot: `prv_ADO_PAT`

   `prv_ADO_PAT` = PAT. **Lưu ý pilot:** dùng Data type **Text** — kiểu Secret
   yêu cầu Azure Key Vault và flow phải đọc qua action riêng
   (`RetrieveEnvironmentVariableSecretValue`), phức tạp không đáng cho pilot.
   Ghi nợ bảo mật: nâng lên KV-backed Secret trước khi nhân rộng (đã ghi trong
   runbook).

   ### Lấy `prv_WEBHOOK_BASIC`

   `prv_WEBHOOK_BASIC` = chuỗi `base64("hookuser:<mật khẩu ngẫu nhiên>")`
   (Data type **Text**, cùng lưu ý pilot như trên) — tạo:

   ```powershell
   [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('hookuser:<password>'))
   ```

   Giữ lại password gốc (chưa base64) — sẽ cần khi cấu hình service hook ở
   Task 8.

## 2. Prompt node

1. Vào **AI hub → Prompts → New prompt**, đặt tên `PR Code Review`.
2. Dán nguyên văn phần "Prompt text" trong `prompts/review-prompt.md` vào nội
   dung prompt.
3. Tạo đúng 4 input variables (Data type Text): `RulesMarkdown`, `FilePath`,
   `BeforeContent`, `AfterNumbered`.
4. Bật **JSON output** (JSON response format).
5. Đặt temperature ở mức thấp nhất có thể.
6. Giữ model mặc định.
7. **Save** prompt vào solution `PR Review Agent`.

## Kiểm tra phần này

Trong test pane của AI Builder, bấm **Test** với input:

- `RulesMarkdown`: dán nội dung `templates/rules.md`
- `FilePath`: `src/Demo/OrderService.cs`
- `BeforeContent`: để trống
- `AfterNumbered`: dán `OrderService.cs` đã đánh số dòng thủ công 5 dòng đầu +
  dòng 20 (`20: var conn = "Server=prod;User=sa;Password=P@ss123";`)

Kết quả mong đợi: output là JSON hợp lệ `{"findings":[...]}`, có finding
`SEC-01` tại dòng 20, message viết bằng tiếng Việt. Nếu model trả về text thừa
nằm ngoài JSON → kiểm tra lại đã bật JSON output format ở Prompt node chưa.

## 3. Service hook

1. Tạo flow stub để bắt payload thật (giải quyết "việc mở" trong spec §11):
   agent flow mới **PR Review Trigger**, trigger **When an HTTP request is
   received** (method POST, schema để trống), thêm duy nhất action
   **Response** (status 200). Save → copy **HTTP POST URL**. Flow này **bắt
   buộc** phải được tạo như một agent flow **bên trong** solution/agent
   **"PR Review Agent"** (Copilot Studio → Agents → PR Review Agent → Flows)
   — tạo flow rời rạc bên ngoài agent sẽ không truy cập được các biến
   `parameters('prv_...')` và không dùng được action "Run a Child Flow".
2. Azure DevOps → **Project settings** → **Service hooks** → `+` →
   **Web Hooks** → Next:
   - Trigger: **Pull request commented on**; Repository = pilot repo; còn lại
     Any.
   - URL = HTTP POST URL vừa copy ở bước 1; **Basic authentication username**
     = `hookuser`, password = password gốc đã tạo khi lập `prv_WEBHOOK_BASIC`
     (mục 1 bên trên); Resource details to send = All.
   - Bấm **Test** → expected: Succeeded. Finish.
3. Bắt payload thật: comment `/review` lên Golden PR → mở run history của
   flow stub → copy toàn bộ trigger body, lưu vào
   `docs/flow-specs/sample-payload.json` (xoá thông tin nhạy cảm nếu có).
   Xác nhận các đường dẫn field sau tồn tại (đây là bước kiểm chứng spec
   §11):
   - `body.eventType` = `ms.vss-code.git-pullrequest-comment-event`
   - `body.resource.comment.content`, `body.resource.comment.author.id`
   - `body.resource.comment._links.self.href` (chứa
     `/threads/{threadId}/comments/`)
   - `body.resource.pullRequest.pullRequestId`,
     `body.resource.pullRequest.status`,
     `body.resource.pullRequest.repository.id`

   Nếu tên field thực tế khác → cập nhật `docs/flow-specs/trigger-flow.md`
   theo payload thật trước khi build tiếp.

## 4. Trigger flow

Sau khi đã bắt và xác nhận payload thật ở mục 3, hoàn thiện flow
**PR Review Trigger** theo `docs/flow-specs/trigger-flow.md` (thay stub
Response 200 bằng chuỗi action đầy đủ trong spec đó). Save.

Verify end-to-end trên Golden PR:

1. Comment `/review` → expected: bot reply vào thread đó "✅ Review xong — …",
   threads/summary như mục Review pipeline (Task 7).
2. Comment `hello` (không keyword) → expected: flow run kết thúc im lặng ở
   `Cond_Valid`, không có comment bot.
3. Kiểm tra chống vòng lặp: các reply bot vừa post ở bước (1) có sinh run mới
   không — expected: run mới kết thúc im lặng tại điều kiện author = bot.

## 5. Kiểm tra sau setup

Sau khi hoàn tất mục 1–4, chạy lần lượt các bước sau để xác nhận toàn bộ hệ
thống hoạt động đúng trước khi bắt đầu pilot:

1. Chạy `scripts/test-ado-access.ps1` → expected: 2 dòng PASS
   (`PASS: repo '...'`, `PASS: liet ke PR active ...`) và
   `PASS: doc duoc .review/rules.md (...)` (file rule trên pilot repo đọc
   được).
2. Test Prompt node trong test pane của AI Builder theo đúng input/kết quả
   mong đợi đã mô tả ở mục "Kiểm tra phần này" (mục 2 bên trên).
3. Vào flow designer của **PR Review Pipeline** → Test → Manually: nhập
   `PullRequestId` = Golden PR id (xem `docs/test-checklist.md`),
   `TriggerThreadId` = `0` → expected: run Succeeded, có inline comment đúng
   file/dòng và 1 summary comment trên Golden PR.
4. Comment `/review` lên Golden PR để test end-to-end qua service hook +
   trigger flow → expected: bot phản hồi như mô tả ở mục "Verify end-to-end
   trên Golden PR" (mục 4 bên trên).

Nếu bước nào không đạt, xem `docs/runbook.md` (mục "Sự cố thường gặp") để
chẩn đoán.
