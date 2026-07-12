# Flow spec: PR Review Pipeline — bản build-ready

Mỗi action bên dưới ghi: **loại action** (gõ vào ô tìm kiếm Add an action), tên
rename, vị trí đặt, và từng ô điền gì. Ô đánh dấu **fx** = bấm nút fx (Insert
expression), dán nguyên chuỗi, bấm OK — **không gõ `@{ }`**. Ô đánh dấu
**text** = gõ/dán như văn bản thường. Rename action đúng tên **trước khi** dán
expression (expression tham chiếu theo tên).

Quy ước dùng lại nhiều lần:

- **AUTH** — mọi action HTTP đều có header `Authorization`, value (fx):
  ```
  concat('Basic ', base64(concat(':', parameters('prv_ADO_PAT'))))
  ```
  Action POST/PATCH thêm header thứ hai: `Content-Type` = `application/json` (text).
- Trigger inputs: `PullRequestId` = `triggerBody()['number']`,
  `TriggerThreadId` = `triggerBody()['number_1']` (hoặc chọn token từ Dynamic content).
- **Ô Body của action HTTP** là ô văn bản tự do (đừng nhầm với Queries — bảng
  key–value cho tham số URL, ta không dùng): dán khung JSON như text rồi thay
  từng ký hiệu ❶❷❸ bằng token fx — cảnh báo JSON đỏ trong lúc còn ký hiệu là
  bình thường, thay hết là hết. Nếu designer vẫn không chịu: thêm 1 action
  **Compose** ngay trước (ví dụ `Compose_ThreadBody`), dán khung + token vào ô
  Inputs của Compose, rồi Body của HTTP action chỉ còn fx
  `outputs('Compose_ThreadBody')`.
- Pilot chạy tay: `TriggerThreadId` luôn = 0 → các bước "Reply vào thread
  trigger" được lược bỏ, thay bằng Terminate như ghi ở từng chỗ.

## Trigger

**Manually trigger a flow** — thêm 2 input:
- **Number** tên `PullRequestId`
- **Number** tên `TriggerThreadId`

## Biến (đặt NGOÀI Scope_Try — Initialize variable không được phép nằm trong Scope)

**1. `Init_varSkipped`** — loại **Initialize variable**
- Name: `varSkipped` · Type: `Array` · Value: *(để trống)*

**2. `Init_varFindings`** — loại **Initialize variable**
- Name: `varFindings` · Type: `Array` · Value: *(để trống)*

**3. `Init_varBudget`** — loại **Initialize variable**
- Name: `varBudget` · Type: `Integer` · Value (fx): `parameters('prv_MAX_LINES')`

## `Scope_Try` — loại **Scope** (nhóm Control), chứa toàn bộ action 4→27

### Khối A — fetch & validate (action xếp nối tiếp trong Scope_Try)

**4. `HTTP_GetPR`** — loại **HTTP**
- Method: `GET`
- URI (fx):
  ```
  concat(parameters('prv_ADO_ORG_URL'), '/', parameters('prv_ADO_PROJECT'), '/_apis/git/repositories/', parameters('prv_ADO_REPO_ID'), '/pullRequests/', triggerBody()['number'], '?api-version=7.1')
  ```
- Headers: AUTH

**5. `Cond_Active`** — loại **Condition**
- Ô trái (fx): `body('HTTP_GetPR')?['status']` · toán tử **is equal to** · ô phải (text): `active`
- Nhánh **Yes: để trống** (action 6 trở đi đặt SAU khối Condition này)
- Nhánh **No**: 1 action **Terminate** — Status: `Succeeded`
  *(PR đã đóng = kết cục hợp lệ. Bản đầy đủ cho auto-trigger sau này: thêm
  Condition `TriggerThreadId > 0` → HTTP POST reply trước Terminate.)*

**6. `Compose_SourceBranch`** — loại **Compose**
- Inputs (fx): `replace(body('HTTP_GetPR')?['sourceRefName'], 'refs/heads/', '')`

**7. `Compose_TargetBranch`** — loại **Compose**
- Inputs (fx): `replace(body('HTTP_GetPR')?['targetRefName'], 'refs/heads/', '')`

**8a. `GetRules_OneNote`** — loại **Get page content** (connector **OneNote (Business)**)
- Lần đầu sẽ yêu cầu Sign in tạo connection
- Chọn Notebook / Section / Page chứa review rules bằng dropdown (trang đã
  chuẩn bị ở setup guide mục 0 bước 2)

**8b. `HtmlToText_Rules`** — loại **Html to text** (connector **Content Conversion**)
- Ô Content: chọn token output của `GetRules_OneNote` từ Dynamic content
  (hoặc fx: `body('GetRules_OneNote')`)

**9. `Cond_RulesExist`** — loại **Condition**
- **Configure run after** (⋯ trên action): tick cả **is successful** và **has failed** (của `HtmlToText_Rules`)
- Ô trái (fx): `greater(length(trim(coalesce(body('HtmlToText_Rules'), ''))), 50)` · **is equal to** · ô phải (fx): `true`
- Nhánh **Yes: để trống**
- Nhánh **No**: 1 action **Terminate** — Status: `Failed` · Message (text):
  `Không đọc được review rules từ OneNote — kiểm tra trang rules và connection của flow`
  *(Lỗi cấu hình → Failed để run history hiện rõ nguyên nhân.)*

**10a. `HTTP_GetIterations`** — loại **HTTP**
- Method: `GET`
- URI (fx):
  ```
  concat(parameters('prv_ADO_ORG_URL'), '/', parameters('prv_ADO_PROJECT'), '/_apis/git/repositories/', parameters('prv_ADO_REPO_ID'), '/pullRequests/', triggerBody()['number'], '/iterations?api-version=7.1')
  ```
- Headers: AUTH

**10b. `Compose_IterationId`** — loại **Compose**
- Inputs (fx): `last(body('HTTP_GetIterations')?['value'])?['id']`

**11. `HTTP_GetChanges`** — loại **HTTP**
- Method: `GET`
- URI (fx):
  ```
  concat(parameters('prv_ADO_ORG_URL'), '/', parameters('prv_ADO_PROJECT'), '/_apis/git/repositories/', parameters('prv_ADO_REPO_ID'), '/pullRequests/', triggerBody()['number'], '/iterations/', outputs('Compose_IterationId'), '/changes?$compareTo=0&api-version=7.1')
  ```
- Headers: AUTH

**12. `Filter_Files`** — loại **Filter array** (Data Operation)
- From (fx): `body('HTTP_GetChanges')?['changeEntries']`
- Điều kiện: bấm **Edit in advanced mode**, dán nguyên (GIỮ dấu `@` đầu — riêng advanced mode dùng cú pháp này):
  ```
  @and(not(contains(item()?['changeType'],'delete')), not(equals(item()?['item']?['isFolder'], true)), not(endswith(item()?['item']?['path'],'.min.js')), not(endswith(item()?['item']?['path'],'.lock')), not(endswith(item()?['item']?['path'],'-lock.json')), not(endswith(item()?['item']?['path'],'.dll')), not(endswith(item()?['item']?['path'],'.png')), not(endswith(item()?['item']?['path'],'.jpg')), not(endswith(item()?['item']?['path'],'.svg')), not(startswith(item()?['item']?['path'],'/.review/')))
  ```

**13. `Compose_Capped`** — loại **Compose**
- Inputs (fx): `take(body('Filter_Files'), parameters('prv_MAX_FILES'))`

**14. `Cond_OverCap`** — loại **Condition**
- Ô trái (fx): `length(body('Filter_Files'))` · **is greater than** · ô phải (fx): `parameters('prv_MAX_FILES')`
- Nhánh **Yes**: 1 action **Append to array variable** — Name: `varSkipped` · Value (fx):
  ```
  concat('Vượt cap ', parameters('prv_MAX_FILES'), ' file — chỉ review ', parameters('prv_MAX_FILES'), '/', length(body('Filter_Files')), ' file.')
  ```
- Nhánh **No: để trống**. Flow tiếp tục sau khối Condition dù Yes hay No.

### Khối B — `Apply_to_each_File` — loại **Apply to each** (Control)

- Select an output (fx): `outputs('Compose_Capped')`
- **Settings** của action (⋯ → Settings): bật **Concurrency control**, Degree of parallelism = **1**
- Action 15→23 nằm **bên trong** vòng lặp này:

**15. `HTTP_GetAfter`** — loại **HTTP**
- Method: `GET`
- URI (fx):
  ```
  concat(parameters('prv_ADO_ORG_URL'), '/', parameters('prv_ADO_PROJECT'), '/_apis/git/repositories/', parameters('prv_ADO_REPO_ID'), '/items?path=', encodeUriComponent(items('Apply_to_each_File')?['item']?['path']), '&versionDescriptor.version=', encodeUriComponent(outputs('Compose_SourceBranch')), '&versionDescriptor.versionType=branch&includeContent=true&$format=json&api-version=7.1')
  ```
- Headers: AUTH

**16. `Compose_Lines`** — loại **Compose**
- Inputs (fx): `split(body('HTTP_GetAfter')?['content'], decodeUriComponent('%0A'))`

**17. `Cond_Budget`** — loại **Condition**
- Ô trái (fx): `length(outputs('Compose_Lines'))` · **is less than or equal to** · ô phải (fx): `variables('varBudget')`
- Nhánh **No**: 1 action **Append to array variable** — Name: `varSkipped` · Value (fx):
  ```
  concat(items('Apply_to_each_File')?['item']?['path'], ' (hết budget dòng)')
  ```
- Nhánh **Yes**: chứa toàn bộ action 18→23 bên dưới.

**18. `Decrement_Budget`** — loại **Decrement variable**
- Name: `varBudget` · Value (fx): `length(outputs('Compose_Lines'))`

**19a. `Select_Numbered`** — loại **Select** (Data Operation)
- From (fx): `range(0, length(outputs('Compose_Lines')))`
- Map: bấm icon chuyển **text mode** (icon nhỏ bên phải ô Map) → (fx):
  ```
  concat(add(item(), 1), ': ', outputs('Compose_Lines')?[item()])
  ```

**19b. `Compose_AfterNumbered`** — loại **Compose**
- Inputs (fx): `join(body('Select_Numbered'), decodeUriComponent('%0A'))`

**20a. `HTTP_GetBefore`** — loại **HTTP**
- Method: `GET`
- URI (fx): giống `HTTP_GetAfter` nhưng version = TargetBranch:
  ```
  concat(parameters('prv_ADO_ORG_URL'), '/', parameters('prv_ADO_PROJECT'), '/_apis/git/repositories/', parameters('prv_ADO_REPO_ID'), '/items?path=', encodeUriComponent(items('Apply_to_each_File')?['item']?['path']), '&versionDescriptor.version=', encodeUriComponent(outputs('Compose_TargetBranch')), '&versionDescriptor.versionType=branch&includeContent=true&$format=json&api-version=7.1')
  ```
- Headers: AUTH

**20b. `Compose_Before`** — loại **Compose**
- **Configure run after**: tick cả **is successful** và **has failed** (file mới → GetBefore 404)
- Inputs (fx):
  ```
  if(equals(outputs('HTTP_GetBefore')?['statusCode'], 200), body('HTTP_GetBefore')?['content'], '')
  ```

**21. `Prompt_Review`** — loại **Run a prompt** (AI Builder)
- Prompt: chọn **PR Code Review** (hoặc tạo mới tại đây — setup guide mục 2 Cách B)
- Map 4 input — lưu ý: 4 ô này nằm trong **action ở flow designer** (hiện ra
  ngay dưới dropdown sau khi chọn prompt), KHÔNG phải trong prompt editor.
  Prompt editor chỉ định nghĩa placeholder `{...}` (không có fx ở đó); còn 4 ô
  của action là ô flow bình thường — click vào có fx/Dynamic content, điền
  giá trị runtime cho từng placeholder:
  - `RulesMarkdown` (fx): `body('HtmlToText_Rules')`
  - `FilePath` (fx): `items('Apply_to_each_File')?['item']?['path']`
  - `BeforeContent` (fx): `outputs('Compose_Before')`
  - `AfterNumbered` (fx): `outputs('Compose_AfterNumbered')`

**22a. `Parse_Findings`** — loại **Parse JSON** (Data Operation)
- Content: chọn token **Text** của `Prompt_Review` từ Dynamic content
  (nếu gõ fx: `outputs('Prompt_Review')?['body']?['responsev2']?['predictionOutput']?['text']`)
- Schema (dán nguyên vào ô Schema):
  ```json
  {
    "type": "object",
    "properties": {
      "findings": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "file": { "type": "string" },
            "line": { "type": "integer" },
            "type": { "type": "string" },
            "ruleId": { "type": "string" },
            "severity": { "type": "string" },
            "message": { "type": "string" },
            "suggestion": { "type": "string" },
            "snippet": { "type": "string" }
          }
        }
      }
    }
  }
  ```

**22b. `Prompt_Review_2`** — loại **Run a prompt** — cấu hình y hệt action 21
- **Configure run after**: chỉ tick **has failed** (của `Parse_Findings`) — đây là lần retry khi JSON hỏng

**22c. `Parse_Findings_2`** — loại **Parse JSON** — Schema y hệt 22a
- Content: token Text của `Prompt_Review_2`

**22d. `Append_SkipParse`** — loại **Append to array variable**
- **Configure run after**: chỉ tick **has failed** (của `Parse_Findings_2`)
- Name: `varSkipped` · Value (fx):
  ```
  concat(items('Apply_to_each_File')?['item']?['path'], ' (JSON hỏng)')
  ```

**23. `Apply_to_each_Finding`** — loại **Apply to each**
- **Configure run after**: tick **is successful** VÀ **is skipped** (của `Append_SkipParse`) — thiếu bước này thì nhánh thành công sẽ bị skip toàn bộ findings
- Select an output (fx): `coalesce(body('Parse_Findings')?['findings'], body('Parse_Findings_2')?['findings'], json('[]'))`
- Bên trong: 1 action **Append to array variable** — Name: `varFindings` · Value (fx):
  ```
  addProperty(item(), 'fingerprint', toLower(concat(if(startswith(item()?['file'],'/'), item()?['file'], concat('/', item()?['file'])), '|', if(equals(item()?['type'],'rule'), item()?['ruleId'], 'bug'), '|', take(replace(replace(replace(item()?['snippet'],' ',''), decodeUriComponent('%09'),''), decodeUriComponent('%0D'),''), 120))))
  ```

*(hết vòng lặp Apply_to_each_File — action 24 trở đi đặt SAU nó, vẫn trong Scope_Try)*

### Khối C — đối chiếu thread cũ & post (action nối tiếp trong Scope_Try)

**24a. `HTTP_GetThreads`** — loại **HTTP**
- Method: `GET`
- URI (fx):
  ```
  concat(parameters('prv_ADO_ORG_URL'), '/', parameters('prv_ADO_PROJECT'), '/_apis/git/repositories/', parameters('prv_ADO_REPO_ID'), '/pullRequests/', triggerBody()['number'], '/threads?api-version=7.1')
  ```
- Headers: AUTH

**24b. `Filter_BotThreads`** — loại **Filter array**
- From (fx): `body('HTTP_GetThreads')?['value']`
- Advanced mode (giữ `@`):
  ```
  @and(not(equals(item()?['properties']?['prv.fingerprint'], null)), not(equals(item()?['isDeleted'], true)))
  ```

**24c. `Select_BotFp_All`** — loại **Select**
- From (fx): `body('Filter_BotThreads')`
- Map (text mode, fx): `item()?['properties']?['prv.fingerprint']?['$value']`

**24d. `Filter_BotActive`** — loại **Filter array**
- From (fx): `body('Filter_BotThreads')`
- Advanced mode: `@equals(item()?['status'], 'active')`

**24e. `Select_NewFp`** — loại **Select**
- From (fx): `variables('varFindings')`
- Map (text mode, fx): `item()?['fingerprint']`

**24f. `Filter_UserResolved`** — loại **Filter array**
- From (fx): `body('Filter_BotThreads')`
- Advanced mode:
  ```
  @and(not(equals(item()?['status'],'active')), contains(body('Select_NewFp'), item()?['properties']?['prv.fingerprint']?['$value']))
  ```

**25a. `Filter_NewFindings`** — loại **Filter array**
- From (fx): `variables('varFindings')`
- Advanced mode: `@not(contains(body('Select_BotFp_All'), item()?['fingerprint']))`

**25b. `Apply_to_each_New`** — loại **Apply to each**
- Select an output (fx): `body('Filter_NewFindings')`
- Bên trong: **`HTTP_PostThread`** — loại **HTTP**
  - Method: `POST`
  - URI (fx):
    ```
    concat(parameters('prv_ADO_ORG_URL'), '/', parameters('prv_ADO_PROJECT'), '/_apis/git/repositories/', parameters('prv_ADO_REPO_ID'), '/pullRequests/', triggerBody()['number'], '/threads?api-version=7.1')
    ```
  - Headers: AUTH + `Content-Type` = `application/json`
  - Body: dán khung JSON sau như text, rồi tại 5 vị trí ❶–❺ xoá ký hiệu và chèn expression bằng fx:
    ```json
    {
      "comments": [ { "parentCommentId": 0, "content": "❶", "commentType": 1 } ],
      "status": 1,
      "threadContext": {
        "filePath": "❷",
        "rightFileStart": { "line": ❸, "offset": 1 },
        "rightFileEnd": { "line": ❸, "offset": 1 }
      },
      "properties": {
        "prv.fingerprint": { "$type": "System.String", "$value": "❹" },
        "prv.rule": { "$type": "System.String", "$value": "❺" }
      }
    }
    ```
    - ❶ (fx — chèn GIỮA 2 dấu nháy kép):
      ```
      concat(if(equals(item()?['severity'],'error'),'🔴',if(equals(item()?['severity'],'warning'),'🟡','🔵')), ' **[', coalesce(item()?['ruleId'],'BUG'), ']** ', item()?['message'], if(empty(item()?['suggestion']),'',concat(decodeUriComponent('%0A%0A'),'💡 ', item()?['suggestion'])), decodeUriComponent('%0A%0A'), '<sub>PR Review Agent · ', item()?['type'], '</sub>')
      ```
    - ❷ (fx, giữa nháy kép): `if(startswith(item()?['file'],'/'), item()?['file'], concat('/', item()?['file']))`
    - ❸ (fx, XOÁ luôn ký hiệu — số không có nháy, chèn ở cả 2 chỗ): `item()?['line']`
    - ❹ (fx, giữa nháy kép): `item()?['fingerprint']`
    - ❺ (fx, giữa nháy kép): `coalesce(item()?['ruleId'], '')`

**26a. `Filter_FixedThreads`** — loại **Filter array**
- From (fx): `body('Filter_BotActive')`
- Advanced mode:
  ```
  @not(contains(body('Select_NewFp'), item()?['properties']?['prv.fingerprint']?['$value']))
  ```

**26b. `Apply_to_each_Fixed`** — loại **Apply to each**
- Select an output (fx): `body('Filter_FixedThreads')`
- Bên trong, 2 action nối tiếp:
  - **`HTTP_ReplyFixed`** — loại **HTTP** — Method `POST` · Headers AUTH + Content-Type
    - URI (fx):
      ```
      concat(parameters('prv_ADO_ORG_URL'), '/', parameters('prv_ADO_PROJECT'), '/_apis/git/repositories/', parameters('prv_ADO_REPO_ID'), '/pullRequests/', triggerBody()['number'], '/threads/', items('Apply_to_each_Fixed')?['id'], '/comments?api-version=7.1')
      ```
    - Body (text, dán nguyên): `{ "parentCommentId": 1, "content": "✅ Đã fix — cảm ơn bạn!", "commentType": 1 }`
  - **`HTTP_ResolveThread`** — loại **HTTP** — Method `PATCH` · Headers AUTH + Content-Type
    - URI (fx):
      ```
      concat(parameters('prv_ADO_ORG_URL'), '/', parameters('prv_ADO_PROJECT'), '/_apis/git/repositories/', parameters('prv_ADO_REPO_ID'), '/pullRequests/', triggerBody()['number'], '/threads/', items('Apply_to_each_Fixed')?['id'], '?api-version=7.1')
      ```
    - Body (text): `{ "status": "fixed" }`

**27a. `Compose_Summary`** — loại **Compose**
- Inputs (fx, dán nguyên — tự tính đủ 4 số liệu + danh sách file bỏ qua):
  ```
  concat('## 🤖 PR Review Agent — kết quả', decodeUriComponent('%0A%0A'), '| Mới | Đã fix | Còn lại | User tự resolve |', decodeUriComponent('%0A'), '|---|---|---|---|', decodeUriComponent('%0A'), '| ', length(body('Filter_NewFindings')), ' | ', length(body('Filter_FixedThreads')), ' | ', sub(length(body('Filter_BotActive')), length(body('Filter_FixedThreads'))), ' | ', length(body('Filter_UserResolved')), ' |', decodeUriComponent('%0A%0A'), if(equals(length(variables('varSkipped')), 0), '', concat('### File bỏ qua', decodeUriComponent('%0A'), join(variables('varSkipped'), decodeUriComponent('%0A')), decodeUriComponent('%0A%0A'))), '_Nguồn rules: OneNote (trang đã chọn trong flow)._')
  ```

**27b. `Filter_SummaryThread`** — loại **Filter array**
- From (fx): `body('HTTP_GetThreads')?['value']`
- Advanced mode: `@not(equals(item()?['properties']?['prv.summary'], null))`

**27c. `Cond_SummaryExists`** — loại **Condition**
- Ô trái (fx): `length(body('Filter_SummaryThread'))` · **is equal to** · ô phải (text): `0`
- Nhánh **Yes** (chưa có summary → tạo mới): **`HTTP_PostSummary`** — loại **HTTP** — Method `POST` · Headers AUTH + Content-Type
  - URI (fx): giống URI của `HTTP_PostThread` (`.../threads?api-version=7.1`)
  - Body: dán khung, chèn ❶ = fx `outputs('Compose_Summary')` giữa nháy kép:
    ```json
    {
      "comments": [ { "parentCommentId": 0, "content": "❶", "commentType": 1 } ],
      "status": 1,
      "properties": { "prv.summary": { "$type": "System.String", "$value": "true" } }
    }
    ```
- Nhánh **No** (đã có → update): **`HTTP_PatchSummary`** — loại **HTTP** — Method `PATCH` · Headers AUTH + Content-Type
  - URI (fx):
    ```
    concat(parameters('prv_ADO_ORG_URL'), '/', parameters('prv_ADO_PROJECT'), '/_apis/git/repositories/', parameters('prv_ADO_REPO_ID'), '/pullRequests/', triggerBody()['number'], '/threads/', first(body('Filter_SummaryThread'))?['id'], '/comments/1?api-version=7.1')
    ```
  - Body: `{ "content": "❶" }` với ❶ = fx `outputs('Compose_Summary')` (giữa nháy kép)

**27d. Reply thread trigger** — *(pilot chạy tay: BỎ QUA — TriggerThreadId luôn 0)*
Bản đầy đủ: Condition `TriggerThreadId > 0` → HTTP POST `.../threads/{TriggerThreadId}/comments?api-version=7.1` với content = "✅ Review xong — … finding mới, … đã fix, … còn lại."

## `Scope_Catch` — loại **Scope**, đặt NGOÀI và SAU `Scope_Try`

- **Configure run after** (của `Scope_Try`): bỏ tick "is successful", tick **has failed** + **has timed out**
- Bên trong (pilot): 1 action **Terminate** — Status: `Failed` · Message (text):
  `Review thất bại giữa chừng — mở run history xem action đỏ trong Scope_Try`
- Bản đầy đủ cho auto-trigger: Condition `TriggerThreadId > 0` → HTTP POST reply "❌ Review thất bại" vào thread trigger.

## Checklist sau khi build xong

1. Đủ 3 Init variable **ngoài** Scope_Try; action 4→27 **trong** Scope_Try; Scope_Catch ngoài.
2. Các chỗ Configure run after: `Cond_RulesExist` (9), `Compose_Before` (20b), `Prompt_Review_2` (22b), `Append_SkipParse` (22d), `Apply_to_each_Finding` (23), `Scope_Catch`.
3. `Apply_to_each_File` bật Concurrency = 1.
4. Test → Manually: `PullRequestId` = Golden PR id, `TriggerThreadId` = 0 → xem setup guide mục 5.
