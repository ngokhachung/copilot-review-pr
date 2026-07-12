# Setup guide — AI PR Review Agent (Copilot Studio)

Hướng dẫn cấu hình Power Platform / Copilot Studio cho AI PR Review Agent trên
Azure DevOps. Tài liệu này là **hướng dẫn đầy đủ**, gồm 5 mục: (0) chuẩn bị
trên Azure DevOps; (1) tạo solution, agent (vỏ chứa) và environment variable;
(2) Prompt node (AI Builder); (3) chạy review thủ công; (4) kiểm tra sau setup.

> **Cập nhật 2026-07-12:** bỏ service hook + trigger flow (người vận hành
> không có quyền "Edit subscriptions" trên Azure DevOps). Pilot chạy review
> bằng cách **run tay flow PR Review Pipeline** với PR id — xem mục 3.
> **Toàn bộ các bước trong guide này làm qua web UI** — các script PowerShell
> trong `scripts/` chỉ là công cụ debug tuỳ chọn, không bắt buộc.

## Điều kiện tiên quyết

- Có quyền tạo solution mới trên môi trường Power Platform (make.powerapps.com)
  dự định dùng cho pilot.
- Có quyền tạo Personal Access Token trên Azure DevOps (quyền này mọi user
  đều có cho chính account của mình).

## 0. Chuẩn bị trên Azure DevOps (web UI, không cần script/git local)

1. **Tạo PAT**: lý tưởng là tạo service account `svc-pr-review` (cần admin
   org) rồi tạo PAT của account đó — comment của bot sẽ mang tên riêng. Nếu
   **không có quyền tạo account**, pilot dùng PAT của chính bạn (comment sẽ
   hiện tên bạn; đổi sang service account sau): avatar góc phải →
   **User settings → Personal access tokens → New Token** → scope
   **Code → Read & Write**, hạn 90 ngày. Copy PAT ngay (chỉ hiện 1 lần).
2. **Chuẩn bị trang OneNote chứa review rules** (amendment 2026-07-12: rule
   đọc từ OneNote thay vì file trong repo): tạo 1 trang trong notebook OneNote
   **thuộc OneDrive for Business/SharePoint** (connector không đọc được
   OneNote cá nhân consumer) mà account build flow truy cập được — ví dụ
   notebook của team, section `Dev`, page `Code Review Rules`. Dán nội dung
   `templates/rules.md` (repo này) vào trang, **giữ nguyên format**: mỗi rule
   có ID (`NAMING-01`…), severity, ví dụ ❌/✅ — prompt nhận diện rule qua
   format này. Ghi nhớ Notebook/Section/Page — sẽ chọn trong flow designer.
3. **Lấy repo GUID** (cho biến `prv_ADO_REPO_ID` ở mục 1): mở tab trình duyệt
   đang đăng nhập Azure DevOps, vào URL:
   `https://dev.azure.com/<org>/<project>/_apis/git/repositories/<tên-repo>?api-version=7.1`
   → trình duyệt hiện JSON → copy giá trị field `"id"` (dạng GUID).
4. **Tạo Golden PR** (PR gài lỗi để test — chưa cần làm ngay, cần trước mục
   4): Repos → **Branches → New branch** `test/golden-review` (từ default
   branch) → chuyển sang branch đó → **New → File** đường dẫn
   `src/Demo/OrderService.cs` → dán nội dung
   `templates/golden-pr/OrderService.cs` (repo này) → Commit → **Create a
   pull request** (KHÔNG merge). Ghi PR id vào `docs/test-checklist.md`.

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
   | `prv_ADO_REPO_ID` | Text | *(repo GUID)* | Repo **GUID** — lấy ở mục 0 bước 3 (URL API trên trình duyệt) |
   | `prv_MAX_FILES` | Number | `30` | Cố định — cap an toàn số file/lần review |
   | `prv_MAX_LINES` | Number | `3000` | Cố định — cap an toàn số dòng thay đổi/lần review |
   | `prv_ADO_PAT` | Text | *(PAT)* | PAT tạo ở mục 0 bước 1 — xem "Lưu ý pilot" bên dưới |

   > Ghi chú: các biến `prv_TRIGGER_KEYWORD`, `prv_BOT_ACCOUNT_ID`,
   > `prv_WEBHOOK_BASIC` của thiết kế webhook cũ **không còn cần** — chúng chỉ
   > phục vụ trigger flow đã bị bỏ (amendment 2026-07-12). `prv_RULES_PATH`
   > cũng bỏ — rule đọc từ OneNote (trang chọn trực tiếp trong flow designer,
   > không qua env var). Nếu sau này khôi phục trigger tự động / rule trong
   > repo, xem spec §4 và lịch sử git.

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

Sau khi hoàn tất mục 0–3, chạy lần lượt các bước sau để xác nhận toàn bộ hệ
thống hoạt động đúng trước khi bắt đầu pilot:

1. Test Prompt node trong test pane của AI Builder theo đúng input/kết quả
   mong đợi đã mô tả ở mục "Kiểm tra phần này" (mục 2 bên trên).
2. Chạy tay **PR Review Pipeline** theo mục 3 với `PullRequestId` = Golden PR
   id (tạo ở mục 0 bước 4, id ghi trong `docs/test-checklist.md`) → expected:
   run Succeeded, có inline comment đúng file/dòng và 1 summary comment trên
   Golden PR (chấm điểm theo checklist).
3. Chạy lại pipeline lần nữa với cùng `PullRequestId` → expected: **không**
   sinh thread trùng (idempotency), summary được update chứ không tạo thread
   mới.

Chẩn đoán khi run Failed (xem run history, action nào đỏ):

- Action HTTP lỗi **401/Unauthorized** → PAT sai/hết hạn → tạo PAT mới (mục 0
  bước 1), cập nhật `prv_ADO_PAT`.
- `GetRules_OneNote` lỗi hoặc pipeline dừng ở `Cond_RulesExist` → trang
  OneNote rules không đọc được: kiểm tra connection của flow (account còn
  quyền vào notebook?), trang chưa bị xoá/đổi chỗ, nội dung trang không rỗng
  (mục 0 bước 2).
- Chi tiết khác: `docs/runbook.md` (mục "Sự cố thường gặp"). Nếu máy có
  PowerShell, các script trong `scripts/` (tuỳ chọn) giúp gọi thử từng API để
  khoanh vùng lỗi nhanh hơn.
