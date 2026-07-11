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
