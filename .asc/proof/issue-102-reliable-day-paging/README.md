# Issue #102 paging proof

This retained proof verifies the native horizontal paging mechanics in the
production-shaped `SummaryPagingUITestFixture`. It uses the same
`DailySummaryCarousel` as `DashboardView`, including the surrounding vertical
`ScrollView`, but synthetic summaries make the selected day deterministic.
These images are not TestFlight or real-backend proof.

- Branch: `codex/issue-102-reliable-day-paging`
- Base: `d65e0d6` (TestFlight build 37)
- Simulator: `Cha-Ching Issue 102 Agent`
- UDID: `62A72CE1-839F-4C2A-B227-80510F8C0428`
- Device/runtime: iPhone 14, iOS 26.0.1
- Viewport: 1170 x 2532 pixels

## Red reproduction

Before the fix, the focused UI test performed one slow right swipe from Today
and expected day offset 1. It failed after 8.09 seconds because the moving
2–3-target window kept rebuilding during deceleration:

```text
XCTAssertEqual failed: ("Day offset: 18") is not equal to ("Day offset: 1")
```

The retained command/output is in the archived Codex session
`rollout-2026-09-04T07-37-04-01a0696b-23ca-7c00-a165-12cede592400.jsonl`.

## Green verification

- `01-one-swipe-offset-1.png`: one slow swipe from Today selected exactly day 1.
- `02-rapid-alternating-back-at-today.png`: four rapid alternating swipes each
  completed one recenter and ended coherently at Today.
- `03-vertical-gestures-still-today.png`: vertical pull and vertical scroll,
  followed by a one-second settle window, left selection at Today.
- The Today-boundary test proved no negative/future target exists.
- The forced debounce test exercised the iOS 17-compatible 350 ms commit path.
- A three-iteration stress run passed all six slow/rapid paging invocations.
- Full scheme: 77 tests, 76 passed, 1 intentionally skipped, 0 failed.
- Unsigned Release Simulator build: passed.

The fix retains stable semantic scroll target IDs (`older`, `selected`, and
`newer`) throughout each gesture and its deceleration. Only after scrolling is
idle does it resolve the requested date, recenter the selected semantic slot
without animation, and re-enable interaction. No custom drag gesture is used.

## Real-dashboard limitation

A local Worker/D1 attempt successfully created a local account and seeded the
local database, but the unsigned proof install remained on its cached
subscription paywall instead of reaching `DashboardView`. No production auth
hook was added. Existing build-36 real-dashboard screenshots are visual context
only and are not presented as evidence for this gesture fix.
