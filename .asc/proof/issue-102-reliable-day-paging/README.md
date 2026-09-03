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

The original PR #103 fix retained stable semantic scroll target IDs (`older`,
`selected`, and `newer`) throughout each gesture and its deceleration. Its
iOS 18+ path resolves the requested date only after native scrolling reports
idle, then recenters without animation. The recovery audit below supersedes the
original claim for the iOS 17 fallback. No custom drag gesture is used.

## Real-dashboard limitation

A local Worker/D1 attempt successfully created a local account and seeded the
local database, but the unsigned proof install remained on its cached
subscription paywall instead of reaching `DashboardView`. No production auth
hook was added. Existing build-36 real-dashboard screenshots are visual context
only and are not presented as evidence for this gesture fix.

## 2026-09-04 recovery audit

Issue #104 supplied a 23.55-second build-37 recording that still showed the
original cascade. Repository ancestry proved build 37 did not include this
branch: PR #103 was closed without merging, and its commit was not an ancestor
of `main`.

The recovery audit recreated the build-37 implementation in an isolated
worktree and added a production-shaped moving-date fixture. One slow swipe from
Today deterministically failed at day offset 17 instead of day offset 1. The
stable-slot implementation passed the modern scroll-phase case, but a new
three-repetition audit exposed an iOS 17 fallback defect: two of three runs
advanced from day 1 to day 2 after the first recenter.

The fallback now locks native scrolling as soon as the first semantic target is
selected, debounces for 350 ms, commits and recenters while locked, retains the
lock for a 750 ms queued-position drain, and reasserts the centered semantic
slot before accepting another gesture. The fallback regression also waits for
the final settled state, and a separate test sends overlapping coordinate-based
input without serializing on each expected day. Five repeated modern-path runs,
five repeated final-settle fallback runs, and five repeated overlapping-input
runs passed on the owned iPhone 14 Simulator
`62A72CE1-839F-4C2A-B227-80510F8C0428`.

The final integration seam renders the real `DashboardView` with a real
`DashboardStore` and deterministic delayed loader. It verifies that Today loads
coherently, a delayed day-1 selection aligns the store, loaded card, and
navigation title, and a delayed day-2 failure returns all three to day 1 while
showing the refresh error. Three repeated integration runs passed.
