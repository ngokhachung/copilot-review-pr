# Code Review Rules — Angular / TypeScript

> Format bắt buộc: mỗi rule có ID duy nhất, mức độ, mô tả, ví dụ sai/đúng.
> Dán nội dung file này vào trang OneNote rules của team (xem setup guide
> mục 0 bước 2) — AI review agent đọc rule từ trang đó khi review PR.
> Repo dùng stack nào thì trang OneNote chứa bộ rule stack đó (bộ C# mẫu ở
> `rules.md`); có thể dán cả hai bộ nếu repo trộn backend + frontend.

## TS-01 — Cấm dùng `any` (severity: warning)
Khai báo kiểu tường minh hoặc dùng `unknown` + narrowing; `any` tắt toàn bộ
type-check ở chỗ nó đi qua.
```typescript
// ❌ Sai
function parseOrder(data: any) { return data.total * 1.1; }
// ✅ Đúng
function parseOrder(data: OrderDto): number { return data.total * 1.1; }
```

## TS-02 — So sánh bằng `===` / `!==` (severity: warning)
`==`/`!=` ép kiểu ngầm gây bug khó thấy (`'' == 0` là true).
```typescript
// ❌ Sai
if (status == 1) { ... }
// ✅ Đúng
if (status === OrderStatus.Active) { ... }
```

## NAMING-01 — Biến Observable có hậu tố `$` (severity: info)
Phân biệt stream với giá trị thường ngay từ tên biến.
```typescript
// ❌ Sai
orders = this.orderService.getOrders();
// ✅ Đúng
orders$ = this.orderService.getOrders();
```

## RXJS-01 — Subscription phải được giải phóng (severity: error)
Subscribe thủ công trong component mà không huỷ là memory leak. Ưu tiên
`async` pipe trong template; nếu buộc phải subscribe, dùng
`takeUntilDestroyed()` (hoặc unsubscribe trong `ngOnDestroy`).
```typescript
// ❌ Sai
ngOnInit() { this.orderService.getOrders().subscribe(o => this.orders = o); }
// ✅ Đúng
orders$ = this.orderService.getOrders();            // + async pipe ở template
// hoặc
ngOnInit() {
  this.orderService.getOrders()
    .pipe(takeUntilDestroyed(this.destroyRef))
    .subscribe(o => this.orders = o);
}
```

## RXJS-02 — Cấm subscribe lồng trong subscribe (severity: warning)
Chuỗi call phụ thuộc nhau dùng `switchMap`/`concatMap`/`exhaustMap`;
call song song dùng `forkJoin`/`combineLatest`.
```typescript
// ❌ Sai
this.userService.getUser(id).subscribe(u => {
  this.orderService.getOrders(u.id).subscribe(o => this.orders = o);
});
// ✅ Đúng
this.userService.getUser(id).pipe(
  switchMap(u => this.orderService.getOrders(u.id))
).subscribe(o => this.orders = o);
```

## NG-01 — Component không gọi `HttpClient` trực tiếp (severity: warning)
Mọi call API nằm trong service; component chỉ gọi service. Giữ component
mỏng, service tái sử dụng và test được.
```typescript
// ❌ Sai (trong component)
constructor(private http: HttpClient) {}
load() { this.http.get<Order[]>('/api/orders').subscribe(...); }
// ✅ Đúng
constructor(private orderService: OrderService) {}
load() { this.orderService.getOrders().subscribe(...); }
```

## NG-02 — Vòng lặp render phải có track (severity: info)
`*ngFor` phải có `trackBy`; control-flow mới `@for` phải có `track`. Thiếu
nó, Angular re-render cả list mỗi lần data đổi.
```typescript
// ❌ Sai
<div *ngFor="let order of orders">
// ✅ Đúng
<div *ngFor="let order of orders; trackBy: trackById">
// hoặc control flow mới
@for (order of orders; track order.id) { ... }
```

## NG-03 — Không mutate `@Input` trong component con (severity: warning)
Input là dữ liệu của cha; con sửa trực tiếp gây bug one-way data flow. Cần
đổi thì emit event lên cha hoặc copy ra state riêng.
```typescript
// ❌ Sai
@Input() order!: Order;
markDone() { this.order.status = 'done'; }
// ✅ Đúng
@Input() order!: Order;
@Output() statusChange = new EventEmitter<string>();
markDone() { this.statusChange.emit('done'); }
```

## ERROR-01 — Không nuốt lỗi HTTP/stream (severity: error)
`catchError` phải xử lý thực sự (báo user, log có chủ đích, ném tiếp) —
không trả `EMPTY`/`of(null)` im lặng khi flow phía sau phụ thuộc kết quả;
subscribe cho call quan trọng phải có error handler.
```typescript
// ❌ Sai
this.orderService.save(order).pipe(catchError(() => EMPTY)).subscribe();
// ✅ Đúng
this.orderService.save(order).pipe(
  catchError(err => { this.toast.error('Lưu order thất bại'); return throwError(() => err); })
).subscribe({ next: ..., error: ... });
```

## LOG-01 — Cấm `console.log` trong code production (severity: warning)
Debug xong phải dọn; log có chủ đích đi qua logging service.
```typescript
// ❌ Sai
console.log('order created', order);
// ✅ Đúng
this.logger.info('Order created', { id: order.id });
```

## SEC-01 — Cấm hardcode secret / API key / URL môi trường (severity: error)
Secret không được nằm trong source; URL/config theo môi trường lấy từ
`environment.*` hoặc config service.
```typescript
// ❌ Sai
const headers = { Authorization: 'Bearer eyJhbGciOi...' };
this.http.get('https://api-prod.company.com/orders');
// ✅ Đúng
this.http.get(`${environment.apiUrl}/orders`);   // token do interceptor gắn
```

## SEC-02 — Cấm bypass sanitizer / gán HTML thô (severity: error)
`bypassSecurityTrust*` và `[innerHTML]` với dữ liệu người dùng chưa
sanitize là cửa XSS.
```typescript
// ❌ Sai
this.html = this.sanitizer.bypassSecurityTrustHtml(userComment);
// ✅ Đúng
// bind text bình thường: {{ userComment }} — Angular tự escape;
// nếu buộc render HTML: sanitize phía server hoặc DomSanitizer.sanitize()
```
