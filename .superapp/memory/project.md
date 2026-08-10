# Sales Ping

iPhone-only (iOS 17+) app for indie founders/SaaS makers: connect payment processors
(Stripe, PayPal, Gumroad first) and get a "cha-ching" push notification on every sale.
Planned monetization: subscription ($x/mo or /yr), prices to be tested later.

## Structure
- `Sales Ping/App/SalesPingApp.swift` — entry point, injects `SalesStore`.
- `Sales Ping/Design/Theme.swift` — money-green + gold adaptive palette, `cardStyle()`.
- `Sales Ping/Models/Sale.swift` — `Sale`, `Processor`, `ProcessorConnection`.
- `Sales Ping/Models/SalesStore.swift` — in-memory sample data + derived stats.
- `Sales Ping/Views/RootTabView.swift` — 4 tabs (Today, History, Connect, Settings);
  History/Connect/Settings are `PlaceholderView` stubs.
- `Sales Ping/Views/Home/` — HomeView, HomeComponents (hero, stat tiles, Swift Charts
  weekly bar chart, connections strip, empty state), SaleRow + SaleDetailView.

## Notes
- Data is local/dummy only; no backend, no push infra yet.
- Launch screen (storyboard) matches home theme: green wordmark + gold tagline.
