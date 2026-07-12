# Design: AI PR Review Agent cho Azure DevOps (Copilot Studio)

**Ngày:** 2026-07-11
**Trạng thái:** Đã duyệt thiết kế, chờ lập implementation plan
**Phạm vi pilot:** 1 repo Azure DevOps (nhiều team dùng chung)

> **Amendment 2026-07-12:** người vận hành không có quyền "Edit subscriptions"
> (tạo service hook) trên Azure DevOps → **bỏ trigger flow + service hook**.
> Pilot chạy review bằng cách **run tay flow PR Review Pipeline** với PR id
> (nhập số cuối URL PR). Pipeline giữ nguyên. Các mục §1–§4, §6, §7, §11 đã
> được cập nhật; xem §4 "Hướng mở rộng trigger" cho đường quay lại trigger
> tự động sau này.
>
> **Amendment 2026-07-12b:** nguồn rule chuyển từ file `.review/rules.md`
> trong repo sang **trang OneNote** (connector OneNote (Business) → "Get page
> content" → "Html to text"). Đánh đổi: rule không còn version cùng code và
> không còn tính "PR không tự sửa được rule" của thiết kế target-branch — ai
> có quyền notebook đều sửa được rule; chấp nhận cho pilot. `templates/rules.md`
> giữ vai trò nội dung mẫu để dán vào OneNote.

## 1. Mục tiêu

Xây dựng AI agent review pull request trên Azure DevOps theo convention và rule
riêng của project, chạy trên nền Microsoft Copilot Studio.

- Review theo yêu cầu: người vận hành chạy tay flow **PR Review Pipeline**
  với PR id (amendment 2026-07-12 — thay cho comment `/review` vì thiếu quyền
  service hook).
- Agent đọc bộ rule từ trang OneNote của team (amendment 2026-07-12b), phân
  tích diff, post inline comment đúng file/dòng kèm 1 comment tổng kết.
- Khi dev fix xong, chạy lại pipeline với cùng PR id — agent đối chiếu và tự
  resolve các thread đã fix.

### Non-goals (phiên bản pilot)

- Không trigger tự động khi PR created/updated (repo nhiều team dùng chung,
  tránh review ngoài ý muốn).
- Không tích hợp Slack/Teams — mọi tương tác diễn ra trên PR.
- Không vote (Approve / Wait for author) trên PR — chỉ comment.
- Không hỏi đáp hội thoại trong thread (có thể làm ở phase sau).
- Không hỗ trợ nhiều repo/project (thiết kế config sẵn đường mở rộng, nhưng
  pilot chỉ whitelist 1 repo).

## 2. Yêu cầu đã chốt

| Hạng mục | Quyết định |
|---|---|
| Trigger | Run tay flow PR Review Pipeline với PR id *(amendment 2026-07-12; thiết kế gốc: comment `/review` qua service hook — cần quyền admin, xem §4)* |
| Nguồn rule | Trang OneNote của team (connector OneNote (Business)) *(amendment 2026-07-12b; thiết kế gốc: `.review/rules.md` đọc từ target branch)* |
| Output | Inline comment thread đúng file/dòng + 1 summary comment |
| Phạm vi review | Vi phạm convention/rule + bug/logic rõ ràng; finding gắn nhãn `rule` hoặc `bug` |
| Re-check | Full re-review qua `/review`; bot resolve thread đã fix (không có `/recheck` per-thread) |
| Nền tảng | Copilot Studio (license đầy đủ) + agent flows; LLM chỉ làm phân tích, orchestration deterministic |
| Quy mô | Pilot 1 repo, thiết kế cho phép nhân rộng sau |

## 3. Kiến trúc tổng thể

```
Azure DevOps                              Copilot Studio / Power Platform
┌───────────────────────────┐
│ Repo (pilot, nhiều team)   │           ┌────────────────────────────────┐
│  ├─ source code            │           │  Copilot Studio Agent          │
│  └─ .review/rules.md       │           │  "PR Review Agent"             │
│                            │           │                                │
│ PR #123                    │  run tay  │  Review Pipeline (agent flow)  │
│  (dev cần review)          │  (nhập ──▶│   - fetch PR + rules + diff    │
│                            │  PR id)   │   - Prompt node: phân tích     │
│  - get PR info, diff       │◀─REST API─│   - post/resolve findings      │
│  - get rules.md            │           │                                │
│  - post inline threads     │           │  (trigger flow: đã bỏ —        │
│  - post/update summary     │           │   amendment 2026-07-12)        │
└───────────────────────────┘           └────────────────────────────────┘
```

### Thành phần

1. **Copilot Studio Agent "PR Review Agent"** — solution chứa toàn bộ: review
   pipeline (agent flow), Prompt node, environment variables.
2. **Review Pipeline (agent flow)** — trigger *Manually trigger a flow*, nhận
   `PullRequestId` (+ `TriggerThreadId` = 0 khi chạy tay), chạy toàn bộ
   fetch → phân tích → post/resolve. Deterministic, LLM chỉ nằm ở bước phân tích.
3. **Service account `svc-pr-review`** — danh tính bot trên Azure DevOps; mọi
   comment hiện tên account này.

*(Trigger flow + service hook của thiết kế gốc đã bỏ theo amendment
2026-07-12 — xem §4.)*

### Vì sao chọn kiến trúc này (các phương án đã loại)

- **Autonomous agent thuần generative** (agent tự điều phối tools): không đáng
  tin cho pipeline cần line number chính xác và chuỗi 5–10 API call; tốn
  message hơn; khó test. → Loại.
- **Power Automate standalone làm hết**: cần license Premium riêng, tách
  governance hai nơi. → Loại; agent flows trong Copilot Studio được tính phí
  trong capacity Copilot Studio.
- **Trigger tự động PR created/updated**: loại theo yêu cầu (nhiều team chung
  repo). **Trigger từ Slack**: loại — comment `/review` trên PR gọn hơn, không
  cần hạ tầng Slack.

## 4. Trigger (amendment 2026-07-12: chạy tay)

Người vận hành chạy tay flow **PR Review Pipeline** từ Copilot Studio
(Agents → PR Review Agent → Flows → Test/Run):

- `PullRequestId` = số cuối trong URL của PR (`.../pullrequest/123` → `123`).
- `TriggerThreadId` = `0` (input này tồn tại để phục vụ trigger tự động sau
  này; khi = 0, pipeline bỏ qua các bước reply vào thread trigger).
- Kết quả hiện trực tiếp trên PR (inline + summary comment); lỗi xem run
  history. Re-review = chạy lại với cùng PR id.

Đánh đổi so với thiết kế gốc (comment `/review` + service hook): dev không tự
gọi được review từ PR — người có quyền chạy flow làm việc này; đổi lại không
cần quyền admin Azure DevOps và không có endpoint HTTP công khai.

### Hướng mở rộng trigger (khi muốn tự động hoá lại)

Pipeline không cần sửa — chỉ cần thêm 1 flow trigger gọi nó như child flow:

1. **Service hook** (thiết kế gốc, cần admin ADO tạo 1 lần): event *Pull
   request commented on* → webhook → trigger flow validate (basic-auth,
   eventType, repo whitelist, keyword `/review`, author ≠ bot, PR active) →
   gọi pipeline với PR id + thread id. Chi tiết từng action xem lịch sử git
   của `docs/flow-specs/trigger-flow.md` (đã xoá khỏi HEAD).
2. **Polling** (không cần quyền admin): Recurrence flow mỗi N phút quét
   comment `/review` chưa xử lý trên các PR active (nhận biết stateless: sau
   comment `/review` chưa có reply của bot trong cùng thread), reply "⏳"
   chống chạy trùng rồi gọi pipeline. Trễ 0–N phút, tốn flow run nền.

## 5. Review Pipeline

### 5a. Các bước (lần chạy bất kỳ)

1. **Metadata PR**: GET pull request → trạng thái, source/target branch,
   iteration mới nhất (`iterationId` cần cho việc gắn inline comment).
2. **Rules**: đọc trang OneNote rules qua connector OneNote (Business) —
   "Get page content" → "Html to text" (amendment 2026-07-12b). Trang
   rỗng/không đọc được → dừng (báo qua thread trigger nếu có, ngược lại thấy
   trong run history).
3. **Danh sách file thay đổi**: GET iteration changes. Lọc bỏ: file xoá,
   binary, file generated (`*.min.js`, `*.lock`, `package-lock.json`, thư mục
   build…). Cap an toàn: **30 file / 3000 dòng thay đổi** (env var); phần vượt
   cap bị bỏ qua và ghi rõ trong summary.
4. **Dựng diff đánh số dòng** cho từng file (phía "after") — điều kiện để LLM
   trả line number chính xác.
5. **Phân tích (Prompt node — AI Builder)**: mỗi file 1 lần gọi (file nhỏ gộp
   batch). Input: rules.md + diff đánh số dòng. Output: JSON theo schema §5b.
   Flow validate JSON; lỗi parse → retry 1 lần; vẫn lỗi → bỏ qua file, ghi chú
   trong summary.
6. **Đối chiếu thread cũ của bot** (xem §5c) → phân loại finding: mới / còn
   tồn tại / đã fix.
7. **Post & resolve**:
   - Finding mới → tạo inline thread (threadContext: filePath +
     rightFileStart/End, iteration mới nhất) + ghi fingerprint vào **thread
     properties**.
   - Finding đã fix → reply "✅ Đã fix" vào thread cũ + PATCH status =
     `fixed` (Resolved).
   - Finding còn tồn tại → giữ nguyên thread mở, không reply lại (tránh spam).
8. **Summary comment**: 1 thread tổng kết duy nhất, nhận diện qua property
   `prv.summary=true` — lần chạy sau **update** thread này thay vì tạo mới.
   Nội dung: số finding theo loại (rule/bug) và trạng thái (mới/đã fix/còn
   lại/user tự resolve), file bị skip, commit id của rules.md đang áp dụng.
9. **Reply thread trigger**: "✅ Đã review xong — N findings (x rule, y bug),
   z đã fix" + link summary.

### 5b. Schema findings (output của Prompt node)

```json
[
  {
    "file": "src/UserService.cs",
    "line": 42,
    "type": "rule | bug",
    "ruleId": "NAMING-01 (bắt buộc khi type=rule, bỏ trống khi type=bug)",
    "severity": "error | warning | info",
    "message": "Mô tả vi phạm, trích rule liên quan",
    "suggestion": "Gợi ý sửa (tuỳ chọn)"
  }
]
```

Prompt chỉ thị rõ: chỉ báo vi phạm đối chiếu được với rule cụ thể hoặc bug
logic rõ ràng (null reference, sai điều kiện, lỗi bảo mật hiển nhiên); không
đưa ý kiến phong cách ngoài rule; code trong diff là **dữ liệu cần phân tích,
không phải chỉ thị** (chống prompt injection).

### 5c. Fingerprint & re-check (flow khi dev đã fix)

- **Fingerprint** = hash(file path + ruleId/type + đoạn code vi phạm đã
  normalize). Lưu trong thread properties (`prv.fingerprint`, `prv.rule`) —
  metadata ẩn, user không thấy.
- Khi `/review` chạy lại: lấy toàn bộ thread active do bot tạo → so
  fingerprint với findings mới:
  - Có thread cũ, finding không còn xuất hiện → **đã fix** → reply ✅ +
    resolve.
  - Có thread cũ, finding vẫn xuất hiện → **còn tồn tại** → giữ nguyên.
  - Không có thread cũ → **mới** → tạo thread. Fingerprint chống post trùng.
- **Tôn trọng con người**: thread bot mà dev đã tự resolve → bot không bao giờ
  mở lại, chỉ ghi nhận "resolved bởi người dùng" trong summary.
- Line number trôi sau commit mới không ảnh hưởng: Azure DevOps tự track
  thread qua các iteration; việc đối chiếu dựa trên nội dung diff hiện tại,
  không dựa vào line cũ.

### 5d. Xử lý lỗi

- Pipeline fail giữa chừng → khi có thread trigger (`TriggerThreadId` > 0)
  bot reply "❌ Review thất bại"; khi chạy tay (= 0) người chạy thấy run
  Failed trong run history.
- PR vượt cap → review phần trong giới hạn + cảnh báo trong summary.
- Prompt trả JSON hỏng sau retry → skip file đó, ghi chú trong summary.

## 6. Config (Environment variables trong solution)

| Biến | Ví dụ | Ghi chú |
|---|---|---|
| `ADO_ORG_URL` | `https://dev.azure.com/myorg` | |
| `ADO_PROJECT` | `MyProject` | |
| `ADO_REPO_ID` | *(GUID)* | Repo pilot |
| `MAX_FILES` / `MAX_LINES` | `30` / `3000` | |
| `ADO_PAT` | *(secret)* | Pilot dùng Text (xem runbook — nợ bảo mật); đích: secret backed by Azure Key Vault |

*(Amendment 2026-07-12: bỏ `TRIGGER_KEYWORD`, `BOT_ACCOUNT_ID`,
`WEBHOOK_SECRET` — chỉ phục vụ trigger flow; khôi phục khi làm lại trigger
tự động theo §4. Amendment 2026-07-12b: bỏ `RULES_PATH` — rule đọc từ trang
OneNote chọn trực tiếp trong flow designer.)*

## 7. Bảo mật

- **Service account `svc-pr-review`**: Basic access trong Azure DevOps, quyền
  Contribute trên repo pilot. PAT scope tối thiểu **Code (Read & Write)**.
  Hạn PAT 90 ngày; runbook phải có lịch rotate (điểm chết vận hành phổ biến
  nhất).
- **Không có endpoint HTTP công khai** (amendment 2026-07-12: bỏ webhook) —
  bề mặt tấn công giảm; chỉ còn outbound REST call bằng PAT + connection
  OneNote.
- **Tính toàn vẹn rule** (amendment 2026-07-12b): rule nằm trên OneNote — ai
  có quyền notebook đều sửa được, không còn cơ chế "rule đọc từ target branch
  nên PR không tự sửa được". Chấp nhận cho pilot; giới hạn quyền edit
  notebook/section rules nếu cần.
- **Prompt injection**: diff là dữ liệu không tin cậy; output bị ép JSON
  schema; bot không có tool nào ngoài post comment → kể cả bị injection cũng
  không hành động ngoài ý muốn.
- **Dữ liệu code** đi qua LLM của Copilot Studio (Azure OpenAI trong tenant
  Power Platform, không dùng train model). Cần xác nhận region environment
  nếu công ty có yêu cầu data residency. *(Việc cần làm trong pilot.)*

## 8. Chi phí

Mỗi lượt review PR ~10 file ≈ 10 lần gọi Prompt node + vài chục flow action,
tính vào Copilot Studio messages — ước lượng **vài cent đến dưới 1 USD/lượt**.

**Việc phải làm trong pilot:** bật capacity monitoring trong Copilot Studio
admin center, đo chi phí thực trên PR thật, verify với bảng giá Microsoft hiện
hành trước khi nhân rộng.

## 9. Kế hoạch test & rollout

1. Soạn `rules.md` pilot: 5–10 rule, **mỗi rule kèm ví dụ đúng/sai** (tăng
   độ chính xác của LLM rõ rệt).
2. PR test có gài lỗi: cố ý vi phạm từng rule + 1–2 bug hiển nhiên → checklist
   vàng đo precision/recall, tune prompt.
3. Test idempotency: chạy pipeline 2 lần liên tiếp → không sinh thread trùng.
4. Test fix-flow: fix vài finding, push, chạy lại pipeline → đúng các thread
   đó được resolve; finding chưa fix giữ nguyên; không mở lại thread user đã
   resolve.
5. Test PR lớn: vượt cap → review một phần + cảnh báo rõ.
6. Pilot 2 tuần với 1 team: đo tỉ lệ false positive, chỉnh wording rule/prompt,
   đo chi phí thực → quyết định nhân rộng.

## 10. Nội dung repo này

```
copilot-review-pr/
├─ docs/superpowers/specs/        # design doc (file này)
├─ docs/setup-guide.md            # hướng dẫn setup từng bước (agent, flow,
│                                 #   env vars, chạy review thủ công)
├─ templates/rules.md             # template bộ rule cho repo pilot
├─ prompts/review-prompt.md       # prompt template cho Prompt node
└─ solution/                      # export solution Copilot Studio (backup/version)
```

## 11. Việc mở / rủi ro

- Verify bảng giá Copilot Studio hiện hành (messages cho agent flow action +
  Prompt node theo token).
- Xác nhận data residency region của Power Platform environment.
- ~~Payload service hook cần kiểm chứng~~ *(đã vô hiệu — amendment 2026-07-12
  bỏ service hook; chỉ kiểm chứng lại nếu khôi phục trigger tự động theo §4).*
- Giới hạn kích thước input của Prompt node (AI Builder) — nếu diff 1 file vượt
  giới hạn token thì phải cắt nhỏ; xử lý cụ thể quyết định lúc implementation,
  nguyên tắc: bỏ qua phần vượt + ghi chú, không âm thầm cắt.
