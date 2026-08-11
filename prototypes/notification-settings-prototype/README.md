# PROTOTYPE — Notification settings

Throwaway UI answering one question:

> After connecting a payment source is complete, what should the separate notification-customization experience look like?

Three variants of the notification settings screen are switchable with `?variant=A|B|C` and the floating bottom control.

Run it with:

```bash
pnpm prototype:notifications
```

Then open `http://127.0.0.1:4173/?variant=A`.

This prototype has no backend and no persistence. Once a direction is chosen, rewrite that decision in SwiftUI and remove this directory from the product branch.
