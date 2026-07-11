# Flow spec: PR Review Trigger

Trigger: **When an HTTP request is received** (POST, schema trống — parse thủ công để webhook lạ không làm fail trigger).

1. `Cond_Auth` — Condition:
   `@{coalesce(triggerOutputs()?['headers']?['Authorization'], '')}` equals
   `@{concat('Basic ', parameters('prv_WEBHOOK_BASIC'))}`
   **No** → Response 401 → Terminate (Succeeded).
2. `Response_202` — Response, status 202 (trả sớm để service hook không timeout; mọi xử lý sau chạy nền).
3. `Compose_Body` — `@{triggerBody()}`; các giá trị dùng lại:
   - `evt = @{outputs('Compose_Body')?['eventType']}`
   - `commentContent = @{outputs('Compose_Body')?['resource']?['comment']?['content']}`
   - `authorId = @{outputs('Compose_Body')?['resource']?['comment']?['author']?['id']}`
   - `prId = @{outputs('Compose_Body')?['resource']?['pullRequest']?['pullRequestId']}`
   - `prStatus = @{outputs('Compose_Body')?['resource']?['pullRequest']?['status']}`
   - `repoId = @{outputs('Compose_Body')?['resource']?['pullRequest']?['repository']?['id']}`
4. `Cond_Valid` — Condition (advanced mode, tất cả AND):
   `@and(
      equals(outputs('Compose_Body')?['eventType'], 'ms.vss-code.git-pullrequest-comment-event'),
      equals(toLower(string(outputs('Compose_Body')?['resource']?['pullRequest']?['repository']?['id'])), toLower(parameters('prv_ADO_REPO_ID'))),
      equals(outputs('Compose_Body')?['resource']?['pullRequest']?['status'], 'active'),
      not(equals(toLower(string(outputs('Compose_Body')?['resource']?['comment']?['author']?['id'])), toLower(parameters('prv_BOT_ACCOUNT_ID')))),
      or(contains(toLower(coalesce(outputs('Compose_Body')?['resource']?['comment']?['content'],'')), toLower(parameters('prv_TRIGGER_KEYWORD'))),
         contains(toLower(coalesce(outputs('Compose_Body')?['resource']?['comment']?['content'],'')), '@ai-review')))`
   **No** → Terminate (Succeeded) — kết thúc im lặng.
5. `Compose_ThreadId` — trích thread id từ comment link:
   `@{int(first(split(last(split(outputs('Compose_Body')?['resource']?['comment']?['_links']?['self']?['href'], '/threads/')), '/comments')))}`
6. `Run_Child_Pipeline` — **Run a Child Flow** → "PR Review Pipeline",
   PullRequestId = prId, TriggerThreadId = `@{outputs('Compose_ThreadId')}`.
