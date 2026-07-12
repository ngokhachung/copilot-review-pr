# Code Review Rules

> Format bắt buộc: mỗi rule có ID duy nhất, mức độ, mô tả, ví dụ sai/đúng.
> Dán nội dung file này vào trang OneNote rules của team (xem setup guide
> mục 0 bước 2) — AI review agent đọc rule từ trang đó khi review PR.

## NAMING-01 — Async method phải có hậu tố `Async` (severity: warning)
Phương thức trả về `Task`/`Task<T>` phải đặt tên kết thúc bằng `Async`.
```csharp
// ❌ Sai
public async Task<Order> GetOrder(int id)
// ✅ Đúng
public async Task<Order> GetOrderAsync(int id)
```

## NAMING-02 — Private field dùng `_camelCase` (severity: info)
```csharp
// ❌ Sai
private readonly OrderRepository repo;
// ✅ Đúng
private readonly OrderRepository _repo;
```

## ERROR-01 — Cấm nuốt exception (severity: error)
Không được để catch block rỗng hoặc chỉ log rồi bỏ qua khi flow phía sau phụ thuộc kết quả.
```csharp
// ❌ Sai
try { Process(order); } catch { }
// ✅ Đúng
try { Process(order); }
catch (PaymentException ex) { _logger.LogError(ex, "Process failed for {Id}", order.Id); throw; }
```

## LOG-01 — Cấm `Console.WriteLine`, dùng `ILogger` (severity: warning)
```csharp
// ❌ Sai
Console.WriteLine("order created");
// ✅ Đúng
_logger.LogInformation("Order {Id} created", order.Id);
```

## SEC-01 — Cấm hardcode secret/connection string (severity: error)
Secret, API key, connection string phải lấy từ configuration/Key Vault.
```csharp
// ❌ Sai
var conn = "Server=prod;User=sa;Password=P@ss123";
// ✅ Đúng
var conn = _configuration.GetConnectionString("OrderDb");
```

## STRUCT-01 — Controller không chứa business logic (severity: warning)
Controller chỉ nhận request, gọi service, trả response. Logic nghiệp vụ (tính toán,
điều kiện nghiệp vụ, truy cập data) phải nằm trong service layer.
```csharp
// ❌ Sai: tính giá trực tiếp trong controller
[HttpPost] public IActionResult Create(OrderDto dto)
{ var total = dto.Items.Sum(i => i.Price * i.Qty) * 1.1m; ... }
// ✅ Đúng
[HttpPost] public IActionResult Create(OrderDto dto)
{ var order = _orderService.Create(dto); return Ok(order); }
```
