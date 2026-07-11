using System;
using System.Linq;
using System.Threading.Tasks;

namespace Demo.Services
{
    public class OrderService
    {
        private readonly OrderRepository repo;            // VI PHAM NAMING-02 (line 9)
        private readonly ILogger<OrderService> _logger;

        public OrderService(OrderRepository repo, ILogger<OrderService> logger)
        {
            this.repo = repo;
            _logger = logger;
        }

        public async Task<Order> GetOrder(int id)          // VI PHAM NAMING-01 (line 18)
        {
            var conn = "Server=prod;User=sa;Password=P@ss123"; // VI PHAM SEC-01 (line 20)
            var order = await repo.FindAsync(id);
            Console.WriteLine("order loaded " + id);       // VI PHAM LOG-01 (line 22)
            return order.Normalize();                       // BUG: order co the null (line 23)
        }

        public decimal SumFirstItems(Order order, int count)
        {
            decimal total = 0;
            for (var i = 0; i <= count; i++)                // BUG: off-by-one (line 29)
            {
                total += order.Items[i].Price;
            }
            return total;
        }

        public void Archive(Order order)
        {
            try { repo.Archive(order); }
            catch { }                                       // VI PHAM ERROR-01 (line 39)
        }
    }
}
