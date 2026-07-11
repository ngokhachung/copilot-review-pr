# Design: AI PR Review Agent cho Azure DevOps (Copilot Studio)

**Ngày:** 2026-07-11
**Trạng thái:** Đã duyệt thiết kế, chờ lập implementation plan
**Phạm vi pilot:** 1 repo Azure DevOps (nhiều team dùng chung)

## 1. Mục tiêu

Xây dựng AI agent review pull request trên Azure DevOps theo convention và rule
riêng của project, chạy trên nền Microsoft Copilot Studio.

- Dev chủ động gọi review bằng cách comment `/review` ngay trên PR.
- Agent đọc bộ rule sống trong repo, phân tích diff, post inline comment đúng
  file/dòng kèm 1 comment tổng kết.
- Khi dev fix và gọi `/review` lại, agent đối chiếu và tự resolve các thread
  đã fix.

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
| Trigger | Comment `/review` trên PR (service hook "Pull request commented on") |
| Nguồn rule | File markdown trong repo: `.review/rules.md`, đọc từ **target branch** |
| Output | Inline comment thread đúng file/dòng + 1 summary comment |
| Phạm vi review | Vi phạm convention/rule + bug/logic rõ ràng; finding gắn nhãn `rule` hoặc `bug` |
| Re-check | Full re-review qua `/review`; bot resolve thread đã fix (không có `/recheck` per-thread) |
| Nền tảng | Copilot Studio (license đầy đủ) + agent flows; LLM chỉ làm phân tích, orchestration deterministic |
| Quy mô | Pilot 1 repo, thiết kế cho phép nhân rộng sau |

## 3. Kiến trúc tổng thể

```
Azure DevOps                              Copilot Studio / Power Platform
┌───────────────────────────┐
│ Repo (pilot, nhiều team)   │
│  ├─ source code            │           ┌────────────────────────────────┐
│  └─ .review/rules.md       │           │  Copilot Studio Agent          │
│                            │           │  "PR Review Agent"             │
│ PR #123                    │           │                                │
│  └─ dev comment: "/review" │           │  ① Trigger flow                │
│         │                  │           │     (HTTP request received)    │
│         ▼                  │──webhook─▶│     - validate + parse comment │
│ Service Hook               │           │     - đúng keyword? author     │
│ (PR commented on)          │           │       không phải bot? → gọi ②  │
│                            │           │            │                   │
│  - get PR info, diff       │◀─REST API─│  ② Review Pipeline (agent flow)│
│  - get rules.md            │           │     - fetch PR + rules + diff  │
│  - post inline threads     │           │     - Prompt node: phân tích   │
│  - reply thread "/review"  │           │     - post/resolve findings    │
└───────────────────────────┘           └────────────────────────────────┘
```

### Thành phần

1. **Copilot Studio Agent "PR Review Agent"** — solution chứa toàn bộ: trigger
   flow, review pipeline (agent flows), Prompt node, environment variables.
2. **Trigger flow** — trigger "When an HTTP request is received", nhận webhook
   từ Azure DevOps service hook event *Pull request commented on*.
3. **Review Pipeline (agent flow)** — nhận `pullRequestId`, chạy toàn bộ
   fetch → phân tích → post/resolve. Deterministic, LLM chỉ nằm ở bước phân tích.
4. **Service account `svc-pr-review`** — danh tính bot trên Azure DevOps; mọi
   comment hiện tên account này.

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

## 4. Trigger flow

1. Service hook (event `Pull request commented on`, scope: đúng 1 repo pilot)
   POST vào URL của flow.
2. Flow validate:
   - Basic-auth header khớp secret cấu hình trong service hook.
   - `eventType` đúng, repository id thuộc whitelist (env var).
   - Nội dung comment chứa trigger keyword `/review` (hoặc chuỗi `@ai-review`).
   - Tác giả comment **không phải** `svc-pr-review` (chặn vòng lặp bot tự
     trigger).
   - PR đang ở trạng thái `active`.
3. Không thoả điều kiện nào → kết thúc im lặng (HTTP 200). Thoả → gọi Review
   Pipeline với `pullRequestId` + id thread của comment trigger (để reply kết
   quả vào đúng thread đó).

Lưu ý: @mention "thật" trong Azure DevOps được mã hoá dạng GUID nên nhận diện
bằng keyword trong nội dung comment là cách bền; quy ước chính thức cho dev là
gõ `/review`.

## 5. Review Pipeline

### 5a. Các bước (lần chạy bất kỳ)

1. **Metadata PR**: GET pull request → trạng thái, source/target branch,
   iteration mới nhất (`iterationId` cần cho việc gắn inline comment).
2. **Rules**: GET `.review/rules.md` từ **target branch** (PR không thể tự sửa
   rule để pass). Không có file → bot reply hướng dẫn tạo, dừng.
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

- Pipeline fail giữa chừng → bot reply vào thread trigger: "❌ Review thất
  bại: \<lý do tóm tắt\>" — không bao giờ im lặng.
- PR vượt cap → review phần trong giới hạn + cảnh báo trong summary.
- Prompt trả JSON hỏng sau retry → skip file đó, ghi chú trong summary.
- Mọi comment do `svc-pr-review` tạo đều bị trigger flow bỏ qua.

## 6. Config (Environment variables trong solution)

| Biến | Ví dụ | Ghi chú |
|---|---|---|
| `ADO_ORG_URL` | `https://dev.azure.com/myorg` | |
| `ADO_PROJECT` | `MyProject` | |
| `ADO_REPO_ID` | *(GUID)* | Whitelist — webhook repo khác bị bỏ qua |
| `RULES_PATH` | `.review/rules.md` | |
| `TRIGGER_KEYWORD` | `/review` | |
| `MAX_FILES` / `MAX_LINES` | `30` / `3000` | |
| `BOT_ACCOUNT_ID` | *(GUID của svc-pr-review)* | Để lọc comment của chính bot |
| `ADO_PAT` | *(secret)* | Environment variable dạng secret, backed by Azure Key Vault |
| `WEBHOOK_SECRET` | *(secret)* | Basic-auth cho service hook |

## 7. Bảo mật

- **Service account `svc-pr-review`**: Basic access trong Azure DevOps, quyền
  Contribute trên repo pilot. PAT scope tối thiểu **Code (Read & Write)**.
  Hạn PAT 90 ngày; runbook phải có lịch rotate (điểm chết vận hành phổ biến
  nhất).
- **Webhook**: URL flow có SAS signature sẵn; thêm basic-auth header validate
  trong flow; validate eventType + repo whitelist.
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
3. Test idempotency: `/review` 2 lần liên tiếp → không sinh thread trùng.
4. Test fix-flow: fix vài finding, push, `/review` → đúng các thread đó được
   resolve; finding chưa fix giữ nguyên; không mở lại thread user đã resolve.
5. Test PR lớn: vượt cap → review một phần + cảnh báo rõ.
6. Pilot 2 tuần với 1 team: đo tỉ lệ false positive, chỉnh wording rule/prompt,
   đo chi phí thực → quyết định nhân rộng.

## 10. Nội dung repo này

```
copilot-review-pr/
├─ docs/superpowers/specs/        # design doc (file này)
├─ docs/setup-guide.md            # hướng dẫn setup từng bước (service hook,
│                                 #   agent, flows, env vars, service account)
├─ templates/rules.md             # template bộ rule cho repo pilot
├─ prompts/review-prompt.md       # prompt template cho Prompt node
└─ solution/                      # export solution Copilot Studio (backup/version)
```

## 11. Việc mở / rủi ro

- Verify bảng giá Copilot Studio hiện hành (messages cho agent flow action +
  Prompt node theo token).
- Xác nhận data residency region của Power Platform environment.
- Payload service hook "Pull request commented on" cần kiểm chứng cấu trúc
  thực tế (field chứa nội dung comment, thread id) ngay bước đầu implementation.
- Giới hạn kích thước input của Prompt node (AI Builder) — nếu diff 1 file vượt
  giới hạn token thì phải cắt nhỏ; xử lý cụ thể quyết định lúc implementation,
  nguyên tắc: bỏ qua phần vượt + ghi chú, không âm thầm cắt.
