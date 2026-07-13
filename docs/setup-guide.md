# Setup guide — AI PR Review Agent (Copilot Studio)

Hướng dẫn cấu hình Power Platform / Copilot Studio cho AI PR Review Agent trên
Azure DevOps. Tài liệu này là **hướng dẫn đầy đủ**: (0) chuẩn bị trên Azure
DevOps & OneNote; (1) tạo solution, agent (vỏ chứa) và environment variable;
(2) Prompt node (AI Builder); (3) build flow PR Review Pipeline; (4) chạy
review thủ công; (5) kiểm tra sau setup.

> **Cập nhật 2026-07-12:** bỏ service hook + trigger flow (người vận hành
> không có quyền "Edit subscriptions" trên Azure DevOps). Pilot chạy review
> bằng cách **run tay flow PR Review Pipeline** với PR id — xem mục 3.
> **Toàn bộ các bước trong guide này làm qua web UI** — các script PowerShell
> trong `scripts/` chỉ là công cụ debug tuỳ chọn, không bắt buộc.
>
> **Cập nhật 2026-07-13:** DLP policy của tenant **chặn connector HTTP** →
> mọi call Azure DevOps trong flow chuyển sang connector **Azure DevOps**
> (action "Send an HTTP request to Azure DevOps"), xác thực bằng connection
> sign-in. Hệ quả: **không cần PAT nữa** — bỏ env var `prv_ADO_PAT`, và
> `prv_ADO_ORG_URL` thay bằng `prv_ADO_ORG` (chỉ tên org).

## Điều kiện tiên quyết

- Có quyền tạo solution mới trên môi trường Power Platform (make.powerapps.com)
  dự định dùng cho pilot.
- Account dùng để sign-in connection Azure DevOps (mục 0 bước 1) có quyền vào
  repo pilot: đọc code + comment trên PR (quyền Contribute to pull requests).

## 0. Chuẩn bị trên Azure DevOps (web UI, không cần script/git local)

1. **Chọn account cho connection Azure DevOps** (amendment 2026-07-13: không
   dùng PAT nữa — flow xác thực bằng connection sign-in khi build, mục 3;
   comment của bot sẽ mang tên account đăng nhập connection): lý tưởng là tạo
   service account `svc-pr-review` (cần admin org) có quyền vào repo pilot
   (Code read + Contribute to pull requests) rồi sign-in bằng account đó. Nếu
   **không có quyền tạo account**, pilot sign-in bằng account của chính bạn
   (comment sẽ hiện tên bạn; đổi sang service account sau — chỉ cần sửa
   connection của flow, không sửa action nào).
2. **Chuẩn bị trang OneNote chứa review rules** (amendment 2026-07-12: rule
   đọc từ OneNote thay vì file trong repo): tạo notebook **trong OneDrive for
   Business của CHÍNH account sẽ tạo connection OneNote** khi build flow —
   dropdown của action "Get page content" **chỉ liệt kê notebook ở đó**.
   Hai loại notebook KHÔNG hiện trong dropdown: (a) notebook trên SharePoint
   site / Teams channel (notebook của team) — chỉ chọn được bằng "Enter
   custom value" với URL API dạng
   `siteCollections/{id}/sites/{id}/notes/sections/{id}` — lằng nhằng, tránh
   cho pilot; (b) OneNote cá nhân consumer (account Microsoft cá nhân) —
   connector Business không đọc được. Cách tạo đúng: office.com → OneNote →
   **New notebook** (mặc định nằm trong OneDrive for Business của account
   đang đăng nhập) → tạo section `Dev`, page `Code Review Rules`. Dán nội
   dung `templates/rules.md` (repo này) vào trang, **giữ nguyên format**: mỗi
   rule có ID (`NAMING-01`…), severity, ví dụ ❌/✅ — prompt nhận diện rule
   qua format này. Lưu ý: notebook mới tạo có thể mất vài phút mới hiện
   trong dropdown của designer — refresh/mở lại designer nếu chưa thấy.
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
   | `prv_ADO_ORG` | Text | `<org>` | **Tên** org Azure DevOps — phần sau `https://dev.azure.com/` trong URL |
   | `prv_ADO_PROJECT` | Text | tên project | Tên project Azure DevOps chứa repo pilot |
   | `prv_ADO_REPO_ID` | Text | *(repo GUID)* | Repo **GUID** — lấy ở mục 0 bước 3 (URL API trên trình duyệt) |
   | `prv_MAX_FILES` | Number | `30` | Cố định — cap an toàn số file/lần review |
   | `prv_MAX_LINES` | Number | `3000` | Cố định — cap an toàn số dòng thay đổi/lần review |

   > Ghi chú: các biến `prv_TRIGGER_KEYWORD`, `prv_BOT_ACCOUNT_ID`,
   > `prv_WEBHOOK_BASIC` của thiết kế webhook cũ **không còn cần** — chúng chỉ
   > phục vụ trigger flow đã bị bỏ (amendment 2026-07-12). `prv_RULES_PATH`
   > cũng bỏ — rule đọc từ OneNote (trang chọn trực tiếp trong flow designer,
   > không qua env var). `prv_ADO_PAT` và `prv_ADO_ORG_URL` bỏ từ amendment
   > 2026-07-13 — connector Azure DevOps xác thực bằng connection (không PAT)
   > và chỉ cần tên org (`prv_ADO_ORG`). Nếu sau này khôi phục trigger tự
   > động / rule trong repo, xem spec §4 và lịch sử git.

   Cách flow đọc env var: trong expression (fx) dùng
   `parameters('prv_ADO_PROJECT')` — tên trong ngoặc là **schema name**
   (trường "Name" của env var trong solution, không phải Display name; copy
   chính xác từ đó). Env var cũng hiện trong panel Dynamic content của
   designer để click chọn. Bốn lỗi hay gặp: (a) chạy ra chuỗi rỗng → env var
   chưa điền **Current Value**; (b) designer/save không tìm thấy parameter →
   flow **được tạo** ngoài solution (từ My flows) — lưu ý: add flow đó vào
   solution về sau **không sửa được lỗi này**, env var chỉ hoạt động với flow
   được TẠO từ trong solution/agent → phải tạo flow mới theo mục 3 và dựng
   lại action; (c) **double
   prefix**: khi tạo env var, nếu gõ `prv_ADO_ORG` vào ô Display name thì
   trường Name tự thành `prv_prv_ADO_ORG` (publisher prefix tự thêm vào) →
   expression `parameters('prv_ADO_ORG')` không khớp; luôn mở lại env var,
   nhìn trường **Name** thật và dùng đúng chuỗi đó trong expression; (d) env
   var tạo ở **environment khác** với environment của agent/flow — kiểm tra
   Environment góc trên phải ở cả hai nơi.

## 2. Prompt node

1. Mở prompt builder theo một trong hai cách, rồi đặt tên prompt là
   `PR Code Review`:
   - **Cách A:** vào make.powerapps.com (hoặc make.powerautomate.com) →
     kiểm tra **Environment** góc trên phải đúng environment chứa solution →
     sidebar trái tìm **AI hub**; nếu không thấy, bấm **More (⋯)** cuối
     sidebar → "Discover all" → nhóm **AI** → **AI hub** (ghim lại để lần
     sau hiện sẵn) → mục **Prompts** → **New prompt** (có bản UI ghi "Build
     your own prompt").
   - **Cách B (khó lạc hơn):** lúc build flow tới action **Run a prompt**
     (action 21 trong flow spec), trong dropdown chọn prompt bấm
     **+ New custom prompt** → prompt builder mở ngay tại chỗ, đảm bảo đúng
     environment và flow thấy prompt ngay.
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

## 3. Build flow "PR Review Pipeline"

Làm rõ thuật ngữ: **agent flow chính là flow Power Automate** — cùng một
designer, cùng loại action — chỉ khác là được tạo/quản lý **bên trong Copilot
Studio** (thuộc agent) và tính phí qua capacity Copilot Studio, nên không cần
license Power Automate Premium riêng cho connector Premium (ở đây là connector
**Azure DevOps**). Guide này dùng agent flow (tạo flow rời rạc bên ngoài
solution sẽ không truy cập được các biến `parameters('prv_...')`).

1. Vào **copilotstudio.microsoft.com** → kiểm tra **Environment** (góc trên
   phải) đúng environment chứa solution → **Agents** → mở agent
   **PR Review Agent** (tạo ở mục 1) → tab **Flows** → **+ New agent flow**.
   Designer mở ra — giao diện chính là Power Automate.
2. Designer mặc định có trigger **"When an agent calls the flow"** — xoá
   trigger này (chọn trigger → Delete), bấm **Add a trigger**, tìm
   **"Manually trigger a flow"** (nhóm *Flow button / Manual*) và thêm vào.
3. Trong trigger vừa thêm → **+ Add an input** → **Number**, đặt tên
   `PullRequestId`; thêm input **Number** thứ hai, đặt tên `TriggerThreadId`.
4. Build lần lượt 27 action theo đúng `docs/flow-specs/review-pipeline.md`
   (mỗi action có sẵn tên, loại action và expression để copy). Cách hiểu đúng:
   action **không "gọi" nhau** — bạn xếp chúng nối tiếp từ trên xuống (bấm
   **+** dưới action trước), engine tự chạy lần lượt; action sau đọc output
   action trước qua expression (`body('Tên_Action')`...). Ba quy tắc build:
   - **Rename action đúng y tên trong spec trước khi dán expression** (chọn
     action → ⋯ → Rename) — expression tham chiếu theo tên, tên khác là vỡ.
   - **Cấu trúc lồng nhau, không phẳng**: `Scope_Try` bao action 2→27;
     `Scope_Catch` nằm ngoài; các `Cond_*` là Condition có nhánh Yes/No chứa
     action con; action 15–23 nằm **bên trong** vòng lặp `Apply_to_each_File`
     (action 18–23 trong nhánh Yes của `Cond_Budget`).
   - **Configure run after**: chỗ nào spec ghi "Configure run after" phải
     chỉnh tay (⋯ trên action) — `Cond_RulesExist`, `Compose_Before`, chuỗi
     retry `Prompt_Review_2`/`Parse_Findings_2`, `Apply_to_each_Finding`,
     `Scope_Catch` — vì mặc định action chỉ chạy khi bước trước thành công.

   Ba chỗ sẽ hỏi connection lần đầu:
   - Action 4 (`HTTP_GetPR`): connector **Azure DevOps** yêu cầu **Sign in**
     → đăng nhập bằng account đã chọn ở mục 0 bước 1 (comment bot đứng tên
     account này). Mọi action ADO còn lại dùng lại connection này, không hỏi
     nữa. Nếu action **Send an HTTP request to Azure DevOps** không xuất hiện
     khi tìm hoặc flow báo DLP violation khi save → connector Azure DevOps
     cũng bị DLP chặn, liên hệ admin xin đưa nó vào cùng nhóm Business với
     OneNote/AI Builder.
   - Action 8 (`GetRules_OneNote`): connector **OneNote (Business)** yêu cầu
     đăng nhập → chọn Notebook/Section/Page đã chuẩn bị ở mục 0 bước 2.
   - Action 21 (`Prompt_Review`): action **Run a prompt** — nếu chưa tạo
     prompt ở mục 2 thì tạo tại đây theo Cách B (mục 2).
5. **Save** flow với tên `PR Review Pipeline`.

Dự phòng: nếu tenant của bạn không cho đổi trigger manual trong agent flow,
tạo cloud flow trong solution thay thế (make.powerapps.com → Solutions →
PR Review Agent → **New → Automation → Cloud flow → Instant** → "Manually
trigger a flow") — cùng designer, nhưng connector Azure DevOps khi đó cần
license Power Automate Premium; nếu bị chặn license, quay lại đường agent flow.

## 4. Chạy review (manual run)

Pilot dùng cơ chế **chạy thủ công** — không có trigger tự động, không cần
quyền tạo service hook trên Azure DevOps:

1. Vào Copilot Studio → **Agents → PR Review Agent → Flows** → mở flow
   **PR Review Pipeline** (đã build ở mục 3).
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

## 5. Kiểm tra sau setup

Sau khi hoàn tất mục 0–4, chạy lần lượt các bước sau để xác nhận toàn bộ hệ
thống hoạt động đúng trước khi bắt đầu pilot:

1. Test Prompt node trong test pane của AI Builder theo đúng input/kết quả
   mong đợi đã mô tả ở mục "Kiểm tra phần này" (mục 2 bên trên).
2. Chạy tay **PR Review Pipeline** theo mục 4 với `PullRequestId` = Golden PR
   id (tạo ở mục 0 bước 4, id ghi trong `docs/test-checklist.md`) → expected:
   run Succeeded, có inline comment đúng file/dòng và 1 summary comment trên
   Golden PR (chấm điểm theo checklist).
3. Chạy lại pipeline lần nữa với cùng `PullRequestId` → expected: **không**
   sinh thread trùng (idempotency), summary được update chứ không tạo thread
   mới.

Chẩn đoán khi run Failed (xem run history, action nào đỏ):

- Action ADO (Send an HTTP request to Azure DevOps) lỗi **401/403** →
  connection hỏng hoặc account mất quyền repo → mở flow → ⋯ → Connections →
  Sign in lại connection Azure DevOps; kiểm tra account còn quyền đọc code +
  comment PR trên repo pilot (mục 0 bước 1).
- `GetRules_OneNote` lỗi hoặc pipeline dừng ở `Cond_RulesExist` → trang
  OneNote rules không đọc được: kiểm tra connection của flow (account còn
  quyền vào notebook?), trang chưa bị xoá/đổi chỗ, nội dung trang không rỗng
  (mục 0 bước 2).
- Chi tiết khác: `docs/runbook.md` (mục "Sự cố thường gặp"). Nếu máy có
  PowerShell, các script trong `scripts/` (tuỳ chọn) giúp gọi thử từng API để
  khoanh vùng lỗi nhanh hơn.
