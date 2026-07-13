# Giải thích chức năng từng action — PR Review Pipeline

Tài liệu này giải thích **mỗi action làm gì và vì sao cần nó**. Cách build
từng action (loại, ô điền, expression) xem `review-pipeline.md` — hai file
dùng chung tên action và số thứ tự.

## Bức tranh tổng thể

Pipeline chạy qua 3 khối trong một cặp try/catch:

- **Khối A (4→14):** lấy thông tin PR từ Azure DevOps, đọc review rules từ
  OneNote, lập danh sách file đáng review (đã lọc rác, đã cắt theo cap).
- **Khối B (15→23):** lặp qua từng file — tải nội dung trước/sau thay đổi,
  đưa cho AI review theo rules, gom findings lại kèm "fingerprint" định danh.
- **Khối C (24→27):** đối chiếu findings với các thread bot đã có trên PR để
  quyết định: post comment mới / resolve thread đã fix / không đụng thread
  user tự đóng — rồi cập nhật 1 comment summary duy nhất.

Kết quả trên PR: mỗi finding = 1 comment inline đúng file đúng dòng, cộng
đúng 1 comment summary thống kê. Chạy lại lần sau không post trùng
(idempotency nhờ fingerprint).

## Trigger

**Manually trigger a flow** — điểm vào của pipeline. Nhận `PullRequestId`
(PR cần review — số cuối URL của PR) và `TriggerThreadId` (ID thread nơi
lệnh review được gọi trong thiết kế auto-trigger; pilot chạy tay luôn nhập
`0` nên mọi bước "reply vào thread trigger" bị lược bỏ).

## Biến khởi tạo (1–3)

Ba action **Initialize variable** phải nằm ngoài `Scope_Try` vì Power
Automate không cho khởi tạo biến bên trong Scope.

1. **`Init_varSkipped`** (Array) — sổ ghi các file bị bỏ qua kèm lý do
   (vượt cap file, hết budget dòng, AI trả JSON hỏng). Summary cuối đọc sổ
   này để báo minh bạch "tôi đã KHÔNG review những gì".
2. **`Init_varFindings`** (Array) — giỏ gom mọi finding từ tất cả file sau
   khi AI review. Khối C làm việc hoàn toàn trên giỏ này.
3. **`Init_varBudget`** (Integer, = `prv_MAX_LINES`) — ngân sách tổng số
   dòng được review trong một lần chạy. Mỗi file review xong bị trừ đi số
   dòng của nó; hết budget thì các file sau bị bỏ qua. Đây là cầu chì chi
   phí: PR khổng lồ không thể đốt tiền AI vô hạn.

## `Scope_Try`

Gói toàn bộ nghiệp vụ (action 4→27) để `Scope_Catch` bắt lỗi tập trung —
pattern try/catch: bất kỳ action nào bên trong chết, flow nhảy xuống Catch
thay vì chết không dấu vết.

## Khối A — fetch & validate (4→14)

**4. `HTTP_GetPR`** — hỏi Azure DevOps metadata của PR: status, source
branch, target branch. Là nguyên liệu cho 3 action kế tiếp.

**5. `Cond_Active`** — cổng chặn đầu tiên: PR không còn `active` (đã
complete/abandon) thì dừng ngay với Succeeded — review một PR đã đóng là vô
nghĩa và tốn tiền. Succeeded (không phải Failed) vì "PR đã đóng" là kết cục
hợp lệ, không phải sự cố.

**6. `Compose_SourceBranch`** / **7. `Compose_TargetBranch`** — bóc tên
branch sạch (bỏ tiền tố `refs/heads/`) từ metadata PR. Dùng ở Khối B để tải
nội dung file theo đúng 2 phiên bản: source = sau thay đổi, target = trước
thay đổi.

**8a. `GetRules_OneNote`** — đọc HTML trang OneNote chứa review rules. Đây
là "bộ luật" mà AI sẽ soi code theo — đổi rule chỉ cần sửa trang OneNote,
không đụng flow.

**8b. `HtmlToText_Rules`** — OneNote trả về HTML; action này lột thẻ HTML
thành text thuần để nhét vào prompt cho AI.

**9. `Cond_RulesExist`** — cổng an toàn: rules đọc ra rỗng hoặc quá ngắn
(≤50 ký tự sau khi trim) nghĩa là trang OneNote hỏng/mất quyền → Terminate
**Failed** kèm message chỉ thẳng nguyên nhân. Không có cổng này, AI sẽ
review "chay" không rule và trả kết quả rác. Được cấu hình run-after chạy cả
khi 8b lỗi — để lỗi đọc OneNote cũng rơi vào đây thay vì chết mù.

**10a. `HTTP_GetIterations`** — lấy danh sách iteration của PR (mỗi lần
push thêm commit, ADO tạo 1 iteration mới).

**10b. `Compose_IterationId`** — lấy ID của iteration **mới nhất** — để
bước sau hỏi đúng "hiện giờ PR thay đổi những file nào" chứ không phải theo
một lần push cũ.

**11. `HTTP_GetChanges`** — lấy danh sách file thay đổi của PR (so iteration
mới nhất với mốc 0 = tổng thay đổi của cả PR).

**12. `Filter_Files`** — lọc bỏ những entry không đáng đưa cho AI: file bị
xoá (không còn gì để review), folder, file build/khoá dependency
(`.min.js`, `.lock`, `-lock.json`), binary (`.dll`, ảnh `.png/.jpg/.svg`),
và thư mục `/.review/`. Giảm nhiễu và tiết kiệm tiền AI.

**13. `Compose_Capped`** — cắt danh sách còn tối đa `prv_MAX_FILES` file.
Cầu chì thứ hai (cùng với budget dòng) chống PR quá to.

**14. `Cond_OverCap`** — nếu danh sách bị cắt thật, ghi một dòng vào
`varSkipped` để summary nói rõ "chỉ review x/y file" — người đọc biết review
không phủ hết.

## Khối B — `Apply_to_each_File` (vòng lặp, chứa 15→23)

Lặp qua từng file trong danh sách đã cắt. **Concurrency = 1** là bắt buộc:
các action bên trong cộng/trừ biến dùng chung (`varBudget`, `varFindings`,
`varSkipped`) — chạy song song sẽ giẫm chân nhau (race condition) làm sai
budget và mất finding.

**15. `HTTP_GetAfter`** — tải nội dung file ở **source branch** = phiên bản
SAU thay đổi. Đây là code sẽ bị soi.

**16. `Compose_Lines`** — tách nội dung thành mảng từng dòng, phục vụ 2
việc: đếm số dòng (cho budget) và đánh số dòng (cho comment inline).

**17. `Cond_Budget`** — cổng ngân sách: file này còn vừa trong budget dòng
không? Không vừa → ghi vào `varSkipped` "(hết budget dòng)" rồi bỏ qua file;
vừa → toàn bộ 18→23 chạy trong nhánh Yes.

**18. `Decrement_Budget`** — trừ số dòng của file này khỏi `varBudget` —
các file sau còn ít ngân sách hơn.

**19a. `Select_Numbered`** — sinh mảng dòng dạng `"1: nội dung"`, `"2: nội
dung"`. Đánh số để AI trả về **đúng số dòng** cho từng finding — không có nó
AI đoán số dòng rất trật, comment inline sẽ trỏ sai chỗ.

**19b. `Compose_AfterNumbered`** — ghép mảng đã đánh số thành một chuỗi —
định dạng cuối cùng đưa vào prompt.

**20a. `HTTP_GetBefore`** — tải phiên bản file ở **target branch** = TRƯỚC
thay đổi. Cho AI thấy được "cái gì đã đổi" thay vì chỉ thấy kết quả cuối.

**20b. `Compose_Before`** — xử lý ca đặc biệt: file mới tinh thì target
branch không có nó → `HTTP_GetBefore` lỗi 404. Action này được run-after cả
khi 20a lỗi, và trả chuỗi rỗng khi không lấy được — chuẩn hoá "trước = rỗng"
cho file mới, vòng lặp không chết.

**21. `Prompt_Review`** — trái tim của pipeline: gọi AI Builder prompt
"PR Code Review" với 4 input (rules, đường dẫn file, nội dung trước, nội
dung sau có đánh số). AI trả về JSON `{"findings": [...]}` — mỗi finding có
file, dòng, loại (rule/bug), severity, message, suggestion, snippet.

**22a. `Parse_Findings`** — parse chuỗi JSON của AI theo schema, biến text
thành object mà expression đọc được. AI đôi khi trả JSON hỏng → action này
fail → kích hoạt chuỗi retry bên dưới.

**22b. `Prompt_Review_2`** / **22c. `Parse_Findings_2`** — retry đúng một
lần: chỉ chạy khi `Parse_Findings` failed (run-after has failed), gọi lại AI
và parse lại. JSON hỏng thường do ngẫu nhiên — thử lại một lần cứu được đa
số ca.

**22d. `Append_SkipParse`** — retry vẫn hỏng thì ghi file vào `varSkipped`
"(JSON hỏng)" và đi tiếp — một file lỗi không được phép giết cả run.

**23. `Apply_to_each_Finding`** — duyệt findings của lần parse thành công
(coalesce ưu tiên lần 1, rồi lần 2, rồi mảng rỗng); mỗi finding được gắn
thêm **fingerprint** = chuỗi chuẩn hoá `file|rule|snippet` rồi bỏ vào
`varFindings`. Fingerprint là chìa khoá idempotency: hai lần chạy khác nhau
sinh cùng fingerprint cho cùng một vi phạm → Khối C nhận ra "thread này đã
có rồi". Run-after phải tick cả successful lẫn skipped — vì 22d thường bị
skip (nhánh thành công), thiếu tick là cả action này bị skip theo, mất sạch
findings.

## Khối C — đối chiếu thread cũ & post (24→27)

**24a. `HTTP_GetThreads`** — lấy toàn bộ comment thread hiện có trên PR —
bức ảnh hiện trạng để đối chiếu.

**24b. `Filter_BotThreads`** — trong đó, lọc ra thread **do bot tạo** (nhận
diện bằng property `prv.fingerprint` mà bot gắn khi post) và chưa bị xoá.
Thread của người thường không có property này nên không bao giờ bị bot đụng.

**24c. `Select_BotFp_All`** — rút danh sách fingerprint của **mọi** thread
bot, kể cả đã resolve — dùng để khử trùng lặp (finding đã có thread thì
không post lại, dù thread đó đang đóng).

**24d. `Filter_BotActive`** — riêng các thread bot còn **active** — đây là
ứng viên cho việc auto-resolve nếu vi phạm đã biến mất.

**24e. `Select_NewFp`** — danh sách fingerprint của findings **lần chạy
này** — vế còn lại của phép đối chiếu.

**24f. `Filter_UserResolved`** — thread bot đã bị đóng bởi user nhưng
fingerprint vẫn còn trong findings mới = vi phạm chưa fix mà user tự
resolve. Bot **không mở lại** (nguyên tắc never-reopen — tôn trọng quyết
định con người), chỉ đếm số này vào summary.

**25a. `Filter_NewFindings`** — findings có fingerprint **chưa từng có
thread** → đây mới là danh sách cần post comment.

**25b. `Apply_to_each_New`** → **`HTTP_PostThread`** — post 1 thread inline
cho từng finding mới: nội dung comment (icon severity + rule + message +
suggestion), toạ độ file/dòng để ADO neo vào đúng chỗ trong tab Files, và 2
property `prv.fingerprint`/`prv.rule` để các lần chạy sau nhận diện.

**26a. `Filter_FixedThreads`** — thread bot đang active nhưng fingerprint
**không còn** trong findings mới = vi phạm đã được fix trong code.

**26b. `Apply_to_each_Fixed`** — với mỗi thread như vậy, 2 bước:
**`HTTP_ReplyFixed`** reply "✅ Đã fix — cảm ơn bạn!" rồi
**`HTTP_ResolveThread`** đổi status thread thành `fixed` — dev không phải
tự tay đóng comment của bot.

**27a. `Compose_Summary`** — dựng nội dung markdown cho comment tổng: bảng
4 số (Mới / Đã fix / Còn lại / User tự resolve — tính từ kết quả các filter
trên) + danh sách file bỏ qua từ `varSkipped`.

**27b. `Filter_SummaryThread`** — tìm thread summary cũ trên PR (nhận diện
bằng property `prv.summary`).

**27c. `Cond_SummaryExists`** — chưa có summary → **`HTTP_PostSummary`**
tạo thread mới (gắn `prv.summary` để lần sau tìm thấy); có rồi →
**`HTTP_PatchSummary`** sửa nội dung comment đầu của thread cũ. Nhờ vậy mỗi
PR chỉ có đúng 1 comment summary, chạy bao nhiêu lần cũng không đẻ thêm.

**27d. Reply thread trigger** — chỉ tồn tại trong bản auto-trigger đầy đủ:
báo kết quả về đúng thread nơi dev gõ lệnh review. Pilot chạy tay
(`TriggerThreadId = 0`) nên bỏ qua.

## `Scope_Catch`

Lưới an toàn cuối: được run-after theo **has failed / has timed out** của
`Scope_Try`, nên bất kỳ action nào bên trong chết không được xử lý là rơi
vào đây → Terminate **Failed** với message hướng dẫn mở run history tìm
action đỏ. Bản auto-trigger đầy đủ sẽ reply "❌ Review thất bại" về thread
trigger thay vì chỉ Terminate.
