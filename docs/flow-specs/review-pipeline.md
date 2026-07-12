# Flow spec: PR Review Pipeline

Trigger: **Manually trigger a flow** — inputs: `PullRequestId` (Number), `TriggerThreadId` (Number).
Quy ước: `REPO_API = concat(env prv_ADO_ORG_URL, '/', prv_ADO_PROJECT, '/_apis/git/repositories/', prv_ADO_REPO_ID)`.
Cách nhập expression: `@{...}` trong spec chỉ là ký hiệu đánh dấu "đây là expression" — khi nhập vào designer, bấm nút **fx** (Insert expression) và dán phần **bên trong** `@{...}`, **không gõ ký tự `@{` `}`**. Nhập đúng thì ô hiển thị token màu; thấy nguyên văn chữ `@{...}` dạng text là sai.
Mọi action tên `HTTP_*` = action **HTTP** built-in (Add an action → gõ "HTTP" → chọn action tên "HTTP"), điền Method + URI + Headers (+ Body với POST/PATCH). `@{REPO_API}` là ký hiệu viết tắt của tài liệu — trong ô URI phải dán expression ghép đầy đủ, ví dụ `HTTP_GetPR`:
`concat(parameters('prv_ADO_ORG_URL'), '/', parameters('prv_ADO_PROJECT'), '/_apis/git/repositories/', parameters('prv_ADO_REPO_ID'), '/pullRequests/', triggerBody()['number'], '?api-version=7.1')`.
Mọi HTTP action: header `Authorization` = `concat('Basic ', base64(concat(':', parameters('prv_ADO_PAT'))))`, retry policy mặc định.
Toàn bộ action 2→27 nằm trong **Scope_Try**; **Scope_Catch** (Configure run after: has failed, has timed out) ở cuối.
Ghi chú đọc spec: "Khối A/B/C" chỉ là tiêu đề tài liệu — **không phải** object trong designer. Container thật trong flow chỉ gồm: `Scope_Try`/`Scope_Catch` (action **Scope**, nhóm Control), các `Cond_*` (action **Condition**, action con nằm trong nhánh Yes/No), và `Apply_to_each_File` (action **Apply to each** — toàn bộ Khối B nằm bên trong nó). Khối A và C là action xếp nối tiếp bình thường trong Scope_Try.
Quy ước Condition "gác cổng" (`Cond_Active`, `Cond_RulesExist`): nhánh **Yes để trống**, action kế tiếp đặt **sau** khối Condition (điều kiện đúng → flow rơi xuống chạy tiếp); nhánh **No** chứa đúng những gì ghi sau "**No** →" và kết thúc bằng **Terminate** (Status = Succeeded — kết cục hợp lệ, không phải lỗi). Riêng `Cond_Budget` là ngoại lệ: action 18–23 nằm trong nhánh Yes như spec ghi. Các `Reply_*` gated "nếu >0": pilot chạy tay luôn truyền TriggerThreadId=0 nên có thể bỏ qua, chỉ giữ Terminate.

## Khối A — fetch & validate
1.  `Init_varSkipped` — Initialize variable, Array, `[]`
2.  `Init_varFindings` — Initialize variable, Array, `[]`  (mỗi phần tử: finding JSON + field `fingerprint` đã tính)
3.  `Init_varBudget` — Initialize variable, Integer, `@{parameters('prv_MAX_LINES')}`
4.  `HTTP_GetPR` — GET `@{REPO_API}/pullRequests/@{triggerBody()['number']}?api-version=7.1`
5.  `Cond_Active` — Condition: `@{body('HTTP_GetPR')?['status']}` equals `active`.
    **No** → `Reply_NotActive` (POST comment vào TriggerThreadId nếu >0: "❌ PR không ở trạng thái active.") → Terminate (Succeeded).
6.  `Compose_SourceBranch` — `@{replace(body('HTTP_GetPR')?['sourceRefName'],'refs/heads/','')}`
7.  `Compose_TargetBranch` — `@{replace(body('HTTP_GetPR')?['targetRefName'],'refs/heads/','')}`
8.  `GetRules_OneNote` — action **Get page content** (connector **OneNote (Business)**): chọn Notebook / Section / Page chứa review rules ngay trong designer (xem setup guide mục 0 bước 2; lần đầu thêm action sẽ yêu cầu đăng nhập tạo connection). Output: HTML của trang.
    `HtmlToText_Rules` — action **Html to text** (Content Conversion): input = output của `GetRules_OneNote`.
9.  `Cond_RulesExist` — Condition (Configure run after HtmlToText_Rules: succeeded **và** failed):
    `@{greater(length(trim(coalesce(body('HtmlToText_Rules'), ''))), 50)}` equals `true` (trang rỗng/không đọc được coi như không có rule).
    **No** → `Reply_NoRules` (POST comment vào TriggerThreadId nếu >0: "❌ Không đọc được review rules từ OneNote — kiểm tra trang rules và connection của flow.") → Terminate (Succeeded).
10. `HTTP_GetIterations` — GET `@{REPO_API}/pullRequests/@{...}/iterations?api-version=7.1`
    → `Compose_IterationId` = `@{last(body('HTTP_GetIterations')?['value'])?['id']}`
11. `HTTP_GetChanges` — GET `.../iterations/@{outputs('Compose_IterationId')}/changes?$compareTo=0&api-version=7.1`
12. `Filter_Files` — Filter array, From `@{body('HTTP_GetChanges')?['changeEntries']}`, điều kiện (Edit in advanced mode):
    `@and(
       not(contains(item()?['changeType'],'delete')),
       not(equals(item()?['item']?['isFolder'], true)),
       not(endswith(item()?['item']?['path'],'.min.js')),
       not(endswith(item()?['item']?['path'],'.lock')),
       not(endswith(item()?['item']?['path'],'-lock.json')),
       not(endswith(item()?['item']?['path'],'.dll')),
       not(endswith(item()?['item']?['path'],'.png')),
       not(endswith(item()?['item']?['path'],'.jpg')),
       not(endswith(item()?['item']?['path'],'.svg')),
       not(startswith(item()?['item']?['path'],'/.review/')))`
13. `Compose_Capped` — `@{take(body('Filter_Files'), parameters('prv_MAX_FILES'))}`
14. `Cond_OverCap` — nếu `@{length(body('Filter_Files'))}` > `prv_MAX_FILES` → Append to varSkipped:
    `@{concat('Vượt cap ', parameters('prv_MAX_FILES'), ' file — chỉ review ', parameters('prv_MAX_FILES'), '/', length(body('Filter_Files')), ' file.')}`

## Khối B — phân tích từng file (Apply_to_each_File, From `@{outputs('Compose_Capped')}`, concurrency = 1)
15. `HTTP_GetAfter` — GET items (như action 8) với path `@{items(...)?['item']?['path']}`, version = SourceBranch.
16. `Compose_Lines` — `@{split(body('HTTP_GetAfter')?['content'], decodeUriComponent('%0A'))}`
17. `Cond_Budget` — Condition: `@{length(outputs('Compose_Lines'))}` ≤ `@{variables('varBudget')}`.
    **No** → Append to varSkipped `@{concat(items(...)?['item']?['path'], ' (hết budget dòng)')}` → (bỏ qua phần còn lại của iteration — các action sau nằm trong nhánh Yes).
    **Yes** →
18. `Decrement_Budget` — Decrement varBudget by `@{length(outputs('Compose_Lines'))}`
19. `Select_Numbered` — Select: From `@{range(0, length(outputs('Compose_Lines')))}`,
    Map (text mode): `@{concat(add(item(),1), ': ', outputs('Compose_Lines')?[item()])}`
    → `Compose_AfterNumbered` = `@{join(body('Select_Numbered'), decodeUriComponent('%0A'))}`
20. `HTTP_GetBefore` — GET items với version = TargetBranch;
    `Compose_Before` (run after succeeded+failed) = `@{if(equals(outputs('HTTP_GetBefore')?['statusCode'],200), body('HTTP_GetBefore')?['content'], '')}`
21. `Prompt_Review` — action **Run a prompt** → "PR Code Review", map 4 inputs
    (RulesMarkdown = `@{body('HtmlToText_Rules')}`, FilePath = path, BeforeContent, AfterNumbered).
22. `Parse_Findings` — Parse JSON trên `@{outputs('Prompt_Review')?['body']?['responsev2']?['predictionOutput']?['text']}`
    (đường dẫn output chính xác: dùng dynamic content "Text" của Run a prompt).
    Schema: object `{findings: array of {file,line,type,ruleId,severity,message,suggestion,snippet}}` (mọi field string trừ line integer).
    **Retry 1 lần:** `Prompt_Review_2` + `Parse_Findings_2` với Configure run after `Parse_Findings` **has failed**;
    `Append_SkipParse` (run after Parse_Findings_2 failed): append vào varSkipped `@{concat(path, ' (JSON hỏng)')}`.
23. `Apply_to_each_Finding` (Configure run after `Append_SkipParse`: is successful **và** is skipped) — From `@{coalesce(body('Parse_Findings')?['findings'], body('Parse_Findings_2')?['findings'], json('[]'))}`:
    Append to varFindings object:
    `@{addProperty(item(), 'fingerprint', toLower(concat(if(startswith(item()?['file'],'/'), item()?['file'], concat('/', item()?['file'])), '|', if(equals(item()?['type'],'rule'), item()?['ruleId'], 'bug'), '|', take(replace(replace(replace(item()?['snippet'],' ',''), decodeUriComponent('%09'),''), decodeUriComponent('%0D'),''), 120))))}`

## Khối C — đối chiếu thread cũ & post
24. `HTTP_GetThreads` — GET `.../pullRequests/@{...}/threads?api-version=7.1`
    - `Filter_BotThreads` — From `@{body('HTTP_GetThreads')?['value']}`, điều kiện:
      `@and(not(equals(item()?['properties']?['prv.fingerprint'], null)), not(equals(item()?['isDeleted'], true)))`
    - `Select_BotFp_All` — Map: `@{item()?['properties']?['prv.fingerprint']?['$value']}` → mảng fingerprint mọi thread bot (mọi status)
    - `Filter_BotActive` — thêm điều kiện `equals(item()?['status'],'active')`.
    - `Select_NewFp` — From varFindings, Map `@{item()?['fingerprint']}`.
    - `Filter_UserResolved` — From `@{body('Filter_BotThreads')}`: `@and(not(equals(item()?['status'],'active')), contains(body('Select_NewFp'), item()?['properties']?['prv.fingerprint']?['$value']))` (thread đã đóng nhưng vi phạm vẫn còn trong findings hiện tại → user tự resolve).
25. `Filter_NewFindings` — From `@{variables('varFindings')}`: `@not(contains(body('Select_BotFp_All'), item()?['fingerprint']))`
    `Apply_to_each_New`: `HTTP_PostThread` — POST `.../threads?api-version=7.1`, body (đúng cấu trúc `New-PrInlineThread` trong scripts/ado-api.ps1):
    comments[0].content =
    `@{concat(if(equals(item()?['severity'],'error'),'🔴',if(equals(item()?['severity'],'warning'),'🟡','🔵')), ' **[', coalesce(item()?['ruleId'],'BUG'), ']** ', item()?['message'], if(empty(item()?['suggestion']),'',concat(decodeUriComponent('%0A%0A'),'💡 ', item()?['suggestion'])), decodeUriComponent('%0A%0A'), '<sub>PR Review Agent · ', item()?['type'], '</sub>')}`
    threadContext.filePath = `@{item()?['file']}` (đảm bảo bắt đầu '/': `@{if(startswith(item()?['file'],'/'), item()?['file'], concat('/', item()?['file']))}`),
    rightFileStart/End.line = `@{item()?['line']}`, properties prv.fingerprint/prv.rule như reference.
26. `Filter_FixedThreads` — From `@{body('Filter_BotActive')}`: `@not(contains(body('Select_NewFp'), item()?['properties']?['prv.fingerprint']?['$value']))`
    `Apply_to_each_Fixed`: `HTTP_ReplyFixed` — POST `.../threads/@{item()?['id']}/comments?api-version=7.1` `{"parentCommentId":1,"content":"✅ Đã fix — cảm ơn bạn!","commentType":1}` ; `HTTP_ResolveThread` — PATCH `.../threads/@{item()?['id']}?api-version=7.1` `{"status":"fixed"}`.
27. Đếm cho summary (Compose):
    `cntNew = length(body('Filter_NewFindings'))`, `cntFixed = length(body('Filter_FixedThreads'))`,
    `cntRemaining = sub(length(body('Filter_BotActive')), cntFixed)`,
    `cntUserResolved = length(body('Filter_UserResolved'))`.
    `Compose_Summary` (markdown):
    `## 🤖 PR Review Agent — kết quả`
    `| Mới | Đã fix | Còn lại | User tự resolve |` + số liệu; danh sách varSkipped nếu không rỗng ("### File bỏ qua"); dòng cuối: nguồn rules = OneNote (trang đã chọn trong flow).
    `Filter_SummaryThread` — From threads: `@not(equals(item()?['properties']?['prv.summary'], null))`.
    Condition: rỗng → `HTTP_PostSummary` (POST thread, properties prv.summary, không threadContext); ngược lại → `HTTP_PatchSummary` — PATCH `.../threads/@{first(body('Filter_SummaryThread'))?['id']}/comments/1?api-version=7.1` `{"content": <Compose_Summary>}`.
    Cuối: Condition `TriggerThreadId > 0` → `HTTP_ReplyTrigger` — POST reply:
    `@{concat('✅ Review xong — ', cntNew, ' finding mới, ', cntFixed, ' đã fix, ', cntRemaining, ' còn lại. Xem summary comment.')}`

## Scope_Catch (run after Scope_Try failed/timed out)
- Condition `TriggerThreadId > 0` → POST reply `"❌ Review thất bại — thử lại sau hoặc báo admin. (run: @{workflow()?['run']?['name']})"`.
