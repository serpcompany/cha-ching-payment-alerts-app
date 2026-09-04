# Issue #104 dashboard UI audit

## Source evidence

- GitHub attachment: `fac00cfe-669a-4581-bd5f-fd35e7b9d223`
- Duration: 23.55 seconds
- Resolution: 1320 x 2868 at 60 fps
- The recording is evidence from TestFlight build 37; it is not stored in git.

Observed failures:

1. Around 00:06-00:09, one horizontal interaction moves from Sep 3 to Aug 31
   and then returns to Today instead of advancing one day.
2. Around 00:10-00:17, further swipes move non-monotonically among Sep 2,
   Aug 31, Sep 1, and Today while partially transitioned cards are visible.

## Repository reconciliation

- Issue #92's responsive card fix merged through PR #93 and is already an
  ancestor of `main`.
- PR #103's paging fix was closed unmerged, so neither build 37 nor canonical
  `main` contained it.
- The build-37 paging code was reproduced in an isolated worktree. A single
  slow swipe failed at day offset 17 instead of day offset 1.
- PR #103's modern scroll-phase path fixed that repro, but its iOS 17 debounce
  fallback failed two of three stress repetitions by advancing to day 2.
- The recovery branch locks the scroll before changing a semantic slot's date,
  drains queued position updates before unlock, strengthens the fallback test
  to assert the final settled day, and adds non-serialized overlapping input.
- A real `DashboardView` + `DashboardStore` integration fixture verifies delayed
  day selection and delayed failure/reversion keep the store offset, loaded
  card, and navigation title coherent. Three repeated runs passed.

## Verification target

Focused paging stress, the real Dashboard integration, the complete iOS suite,
and an unsigned Release Simulator build pass on the owned Simulator. TestFlight
verification must use the first build cut from canonical merged `main`
containing the recovery.
