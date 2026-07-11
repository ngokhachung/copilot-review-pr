# Golden PR — checklist vàng

Golden PR id: `<điền sau khi tạo>` · Branch: `test/golden-review` · File: `src/Demo/OrderService.cs`

## Findings kỳ vọng (7)

| # | Loại | Rule    | Dòng | Nội dung                              |
|---|------|---------|------|---------------------------------------|
| 1 | rule | NAMING-02 |  9 | field `repo` thiếu prefix `_`         |
| 2 | rule | NAMING-01 | 18 | `GetOrder` async thiếu hậu tố `Async` |
| 3 | rule | SEC-01    | 20 | hardcode connection string            |
| 4 | rule | LOG-01    | 22 | dùng `Console.WriteLine`              |
| 5 | bug  | —         | 23 | `order` có thể null trước `.Normalize()` |
| 6 | bug  | —         | 29 | off-by-one `i <= count`               |
| 7 | rule | ERROR-01  | 39 | catch block rỗng                      |

## Cách chấm

- **Recall** = số finding kỳ vọng được báo (đúng loại, dòng ±2) / 7. Đạt: ≥ 5/7.
- **Precision**: finding ngoài bảng trên = false positive. Đạt: ≤ 2 FP.
- Kết quả từng lần chạy ghi vào bảng dưới.

| Ngày | Recall | FP | Ghi chú / chỉnh prompt |
|------|--------|----|------------------------|

## Kịch bản E2E

### 1. Kịch bản fix-flow

**Mục đích:** Xác nhận hệ thống reply "✅ Đã fix" khi user fix các code issue được bot phát hiện.

**Các bước:**
- Trong clone pilot repo, checkout branch `test/golden-review`
- Sửa file `src/Demo/OrderService.cs`:
  - Fix finding #2 (NAMING-01): đổi `GetOrder` → `GetOrderAsync`
  - Fix finding #4 (LOG-01): thay `Console.WriteLine(...)` bằng `_logger.LogInformation("order loaded {Id}", id);`
- Commit + push code
- Comment `/review` trên Golden PR

**Kết quả kỳ vọng:**
- 2 thread tương ứng NAMING-01 và LOG-01 được reply "✅ Đã fix" + status Resolved
- Các thread còn lại giữ nguyên active, không bị reply thêm, không có thread trùng mới
- Summary update: Đã fix = 2, Còn lại = 5

### 2. Kịch bản user tự resolve

**Mục đích:** Xác nhận hệ thống không mở lại thread khi user resolve thủ công mà không sửa code.

**Các bước:**
- Tự tay resolve 1 thread bot còn active (ví dụ: NAMING-02) trên web UI **không sửa code**
- Comment `/review` trên PR

**Kết quả kỳ vọng:**
- Thread đó không bị mở lại
- Không có thread mới trùng finding đó
- Summary ghi nhận "User tự resolve = 1"

### 3. Kịch bản PR lớn vượt cấp

**Mục đích:** Xác nhận hệ thống giới hạn review 30 file tối đa và báo cáo chính xác "File bỏ qua".

**Các bước:**
Tạo branch/PR test với 35 file thay đổi:
```bash
git checkout -b test/large-pr
mkdir -p src/Large
for i in $(seq 1 35); do printf 'public class F%s {\n  private int x%s = %s;\n}\n' "$i" "$i" "$i" > "src/Large/File$i.cs"; done
git add src/Large && git commit -m "test: large PR" && git push -u origin test/large-pr
# tạo PR trên web UI, comment /review
```

**Kết quả kỳ vọng:**
- Chỉ 30 file được review
- Summary có mục "File bỏ qua" ghi rõ vượt cấp
- Sau khi xong: abandon PR, xoá branch

### Kết quả E2E

| Kịch bản | Ngày | Đạt/Không đạt | Ghi chú |
|----------|------|---------------|---------|
| Fix-flow | | | |
| User tự resolve | | | |
| PR lớn vượt cấp | | | |
