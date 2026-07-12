# Setup guide — AI PR Review Agent (Copilot Studio)

Hướng dẫn cấu hình Power Platform / Copilot Studio cho AI PR Review Agent trên
Azure DevOps. Tài liệu này là **hướng dẫn đầy đủ**, gồm 4 mục: (1) tạo
solution, agent (vỏ chứa) và toàn bộ environment variable; (2) Prompt node
(AI Builder); (3) chạy review thủ công; (4) kiểm tra sau setup.

> **Cập nhật 2026-07-12:** bỏ service hook + trigger flow (người vận hành
> không có quyền "Edit subscriptions" trên Azure DevOps). Pilot chạy review
> bằng cách **run tay flow PR Review Pipeline** với PR id — xem mục 3. Spec
> thiết kế đã được amendment tương ứng.

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
   | `prv_MAX_FILES` | Number | `30` | Cố định — cap an toàn số file/lần review |
   | `prv_MAX_LINES` | Number | `3000` | Cố định — cap an toàn số dòng thay đổi/lần review |
   | `prv_ADO_PAT` | Text | *(PAT của `svc-pr-review`)* | PAT tạo ở Task 1 — xem "Lưu ý pilot" bên dưới |

   > Ghi chú: các biến `prv_TRIGGER_KEYWORD`, `prv_BOT_ACCOUNT_ID`,
   > `prv_WEBHOOK_BASIC` của thiết kế webhook cũ **không còn cần** — chúng chỉ
   > phục vụ trigger flow đã bị bỏ (amendment 2026-07-12). Nếu sau này khôi
   > phục trigger tự động, xem spec mục "Hướng mở rộng trigger".

   ### Lưu ý pilot: `prv_ADO_PAT`

   `prv_ADO_PAT` = PAT. **Lưu ý pilot:** dùng Data type **Text** — kiểu Secret
   yêu cầu Azure Key Vault và flow phải đọc qua action riêng
   (`RetrieveEnvironmentVariableSecretValue`), phức tạp không đáng cho pilot.
   Ghi nợ bảo mật: nâng lên KV-backed Secret trước khi nhân rộng (đã ghi trong
   runbook).

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

## 3. Chạy review (manual run)

Pilot dùng cơ chế **chạy thủ công** — không có trigger tự động, không cần
quyền tạo service hook trên Azure DevOps:

1. Vào Copilot Studio → **Agents → PR Review Agent → Flows** → mở flow
   **PR Review Pipeline** (flow này phải được tạo như agent flow **bên trong**
   solution/agent "PR Review Agent" — tạo flow rời rạc bên ngoài sẽ không truy
   cập được các biến `parameters('prv_...')`).
2. Bấm **Test → Manually** (hoặc Run), nhập:
   - `PullRequestId` = id của PR — là **số cuối trong URL** của PR
     (`.../pullrequest/123` → nhập `123`).
   - `TriggerThreadId` = `0` (luôn là 0 khi chạy tay).
3. Chờ run kết thúc — kết quả xuất hiện trực tiếp trên PR: inline comment
   đúng file/dòng + 1 summary comment. Run Failed → mở run history xem action
   nào lỗi (chẩn đoán theo `docs/runbook.md`).
4. **Re-review sau khi dev fix:** chạy lại flow với đúng `PullRequestId` đó —
   bot tự resolve các thread đã fix, không post trùng finding cũ.

Người chạy cần quyền truy cập environment Power Platform chứa solution. Nếu
sau này muốn khôi phục trigger tự động bằng comment `/review` (cần admin tạo
service hook, hoặc dùng polling), pipeline **không cần sửa gì** — chỉ cần thêm
một flow trigger gọi nó; xem mục "Hướng mở rộng trigger" trong spec.

## 4. Kiểm tra sau setup

Sau khi hoàn tất mục 1–3, chạy lần lượt các bước sau để xác nhận toàn bộ hệ
thống hoạt động đúng trước khi bắt đầu pilot:

1. Chạy `scripts/test-ado-access.ps1` → expected: 2 dòng PASS
   (`PASS: repo '...'`, `PASS: liet ke PR active ...`) và
   `PASS: doc duoc .review/rules.md (...)` (file rule trên pilot repo đọc
   được).
2. Test Prompt node trong test pane của AI Builder theo đúng input/kết quả
   mong đợi đã mô tả ở mục "Kiểm tra phần này" (mục 2 bên trên).
3. Chạy tay **PR Review Pipeline** theo mục 3 với `PullRequestId` = Golden PR
   id (xem `docs/test-checklist.md`) → expected: run Succeeded, có inline
   comment đúng file/dòng và 1 summary comment trên Golden PR (chấm điểm theo
   checklist).
4. Chạy lại pipeline lần nữa với cùng `PullRequestId` → expected: **không**
   sinh thread trùng (idempotency), summary được update chứ không tạo thread
   mới.

Nếu bước nào không đạt, xem `docs/runbook.md` (mục "Sự cố thường gặp") để
chẩn đoán.
