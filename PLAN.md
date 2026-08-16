# Budgetma — architecture

Everything the old roadmap listed is built. This is now a map of how the app is
put together and where the sharp edges are.

## The one idea

**Recurrence rules are the source of truth. Occurrences are computed, never
stored.**

That single decision is why arbitrary intervals work. A haircut every 6 weeks, a
biweekly paycheck and monthly rent all flow through the same
`occurrences(in:)` call — nothing in the app has a concept of "a month" that
other periods are defined against. It's also what lets a projection run to any
horizon without the database growing at all.

Real life deviates from rules, so deviations — and *only* deviations — get
stored, as `OccurrenceOverride` rows (skipped / moved / re-priced).

## Layers

```
Views/                SwiftUI. @Query for data, no maths.
   │
Services/             the engines. pure functions over value types.
   │  CashflowProjector      rules + overrides -> events / bucketed curve
   │  AffordabilityEngine    "can i afford it", judged on the curve
   │  ReconciliationService  expected occurrences <-> logged actuals
   │  EnvelopeLedger         envelope funding cycles + carryover
   │  BudgetService          the ONLY place that touches ModelContext
   │
Domain/               Sendable value types. no SwiftData, no SwiftUI.
   │  Schedulable / ScheduleSnapshot / ScheduledEvent
   │  Projection / ProjectionBucket / ProjectionGranularity
   │  DateWindow / FlowSign / EventKind
   │
Data/                 SwiftData @Model types + the ingestion seam.
```

`Schedulable` is the seam everything hangs off. Expected income, expected
expenses, envelope funding, goal contributions and *hypothetical* purchases all
conform, so the projector takes `[ScheduleSnapshot]` and has no idea what any of
them are. Adding a new kind of scheduled money means writing one conformance.

## Two things that are easy to get wrong

**1. Actor isolation.** This project builds with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so *every type is implicitly
`@MainActor` unless it says otherwise*. The domain layer and the projection
engines are explicitly marked `nonisolated` for exactly this reason — without
that, `Task.detached` and `withTaskGroup` hop straight back onto the main actor
and a long projection freezes the UI while *appearing* responsive (the spinner
is drawn by the render server, not the main thread). If you add to `Domain/` or
`Services/`, mark it `nonisolated` and check the build for
`main actor-isolated ... cannot be called from outside of the actor`.

**2. Bucketing hides intra-bucket dips.** The projection is bucketed so a
1000-year chart draws as few points as a 30-day one. But affordability turns
entirely on the *trough*, and a dip inside a bucket is invisible. That's why
`AffordabilityEngine.verdictTargetBuckets = 500` — the verdict is computed at
finer resolution than the chart needs. It is still not per-day; at very long
horizons the trough is approximate.

## Performance

Foundation's `Calendar.RecurrenceRule.recurrences` generates roughly **9,000
occurrences/sec** (measured, release build). That is the binding constraint on
long horizons, not anything in this codebase. Mitigations in place:

- occurrences stream into buckets and are discarded — memory is O(buckets)
- schedules are projected concurrently (`projectConcurrently`)
- the per-occurrence override lookup is skipped entirely when no overrides exist
- a hard `occurrenceCap` stops a pathological rule spinning forever

Practical horizons are fine (~30 years is about a second). A 1000-year horizon
takes tens of seconds in a Debug simulator build. If that ever matters, the fix
is an analytic fast path: for a rule with no weekday/month constraints, the
count of occurrences per bucket is computable arithmetically without generating
each date.

## Expected vs actual

An actual settles a scheduled occurrence when it points at the same expected
item **and** the same `occurrenceDate`. Both live on the `Transaction` base
class, so reconciliation is one code path for income, expenses and envelopes.

Envelopes reconcile differently on purpose: you don't settle a grocery envelope
with one matching payment, you fund it once and spend against it many times. So
an envelope line's "actual" is everything drawn from it during that funding
cycle.

Drift is computed against the *elapsed* part of the window
(`expectedNet(through:)`). Comparing a whole window's plan against actuals
logged so far reads as a catastrophe on day one of the window.

## Ingestion (designed, not implemented)

`Data/Ingestion/ActualsImporter.swift` is the seam for CSV or a bank feed.
Adding one means writing an `ActualsImporter` conformance and a
`TransactionSource` case — nothing else. Already done and provider-agnostic:

- dedup on `(source, externalID)`
- `ImportPipeline` persistence
- `ActualMatcher`, which decides what an incoming actual settles — and is the
  *same* matcher the manual log screen uses, so the two can't drift apart

## Known gaps

- **No account balance.** Projections are net-flow: the curve starts at zero and
  shows drift. `openingBalance` is plumbed through the whole engine as an
  optional offset — setting it turns every projection absolute without touching
  any maths. This is a deliberate choice, not an oversight.
- Affordability trough is approximate at very long horizons (see above).
- `Data/SampleData.swift` is DEBUG-only dev scaffolding
  (`-seed-sample-data`, `-start-tab <name>`). Delete it whenever it stops being
  useful; nothing depends on it.

## Getting it on a phone

Signed with a **free personal team** (`DEVELOPMENT_TEAM = 7S2U6WC5CH`, set on
both configs). Run `./scripts/install-to-phone.sh` — it finds the connected
device, builds Release, reinstalls over the existing app and launches.

Living with free provisioning:

- the build **expires after ~7 days** and stops launching; rerun the script
- **Developer Mode must stay enabled** on the phone. iOS requires it to *launch*
  development-signed apps, not just install them
- **never delete the app to fix a signing problem** — reinstalling over the top
  preserves the SwiftData store, deleting wipes your real budget
- Release, not Debug, on purpose: debug Swift is far slower and the long-horizon
  projections are exactly the part that feels it

### Moving to TestFlight (when you pay the $99)

Everything above goes away — distribution-signed builds don't need Developer
Mode, and builds last 90 days instead of 7.

1. Enrol at developer.apple.com/programs, then add the account in
   Xcode → Settings → Accounts. Replace `DEVELOPMENT_TEAM` with the new team ID
   (the personal-team one stops applying).
2. Register the bundle ID `the-kern.com.Budgetma` in the developer portal, and
   create the app record in App Store Connect.
3. Bump `CURRENT_PROJECT_VERSION` (build number) — App Store Connect rejects a
   build number it has already seen, which is the single most common upload
   failure.
4. Xcode → Product → **Archive** (needs a "Any iOS Device" destination, not a
   simulator) → Distribute App → **TestFlight & App Store**.
5. Internal testers (up to 100, your own account included) get builds with no
   review. External testers need a short Beta App Review first.

## Charts

Series colours are chosen by job, not taste, and validated for colour-blind
separation on both light and dark surfaces. **Money in reads blue, not green** —
green↔red separate by ΔE 6.5 under protanopia (below the safe floor of 8), while
blue↔red manage 19.2. Swap `ChartPalette.inflow` if you'd rather have the
convention; nothing else depends on it. The palette picks light or dark steps
from the luminance of the theme background, since the theme lets you choose any
colour.
