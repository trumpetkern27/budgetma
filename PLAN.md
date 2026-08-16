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
stored, in three shapes:

- `OccurrenceOverride` — *this one occurrence* was skipped, moved or re-priced
- `ScheduleAmendment` — *from this date on* it's a different **amount**
- `ScheduleSuspension` — between these dates it didn't **exist** at all

The second one exists because editing an amount is ambiguous and getting it
wrong corrupts history. You get a raise; if that rewrote the base amount, every
paycheck you'd already reconciled would retroactively restate itself as
underpaid, and six months of correct budgets would silently become wrong.
**History is a fact, not a projection, and must not move when the future does.**

So an occurrence's amount resolves in three layers: the item's original amount,
then the latest amendment effective on or before it, then any per-occurrence
override. The specific exception wins over the standing change — otherwise you
could never record a one-off deviation from a post-raise salary.

All three are keyed on the base `ExpectedTransaction`, so one model each covers
income, expenses and envelopes.

**Archiving is a suspension, not a delete.** You really did pay for Hulu for
eight months, and those occurrences have been reconciled against real
transactions — deleting the expected item would orphan that history and silently
restate eight months of budgets. An open-ended suspension (`until == nil`) *is*
what "archived" means; the flag isn't stored separately, so the two can't
disagree. Restoring closes the span rather than removing it, which keeps the gap
a fact: cancel in March, come back in December at a new price (an amendment), and
the projector correctly produces nothing at all for those nine months. Cancelling
again opens another span, so it survives a subscription you keep flip-flopping
on.

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
   │  RecommendationEngine   plan vs reality, across many windows
   │  GoalSimulator          contributions + compound interest, what-if
   │
Domain/               Sendable value types. no SwiftData, no SwiftUI.
   │  Schedulable / ScheduleSnapshot / ScheduledEvent
   │  Projection / ProjectionBucket / ProjectionGranularity
   │  DateWindow / FlowSign / EventKind
   │  PeriodRule / BudgetPeriod  <- "which window am i in"
   │
Data/                 SwiftData @Model types + the ingestion seam.
```

`Schedulable` is the seam everything hangs off. Expected income, expected
expenses, envelope funding, goal contributions and *hypothetical* purchases all
conform, so the projector takes `[ScheduleSnapshot]` and has no idea what any of
them are. Adding a new kind of scheduled money means writing one conformance.

## The period, and why it's arithmetic

`PeriodRule` (anchor + frequency + interval) is the single definition of "the
window you're standing in". Home's calendar and Budget's expected-vs-actual both
read it from the same three `calendarView*` defaults, so the two screens can't
disagree about what "this period" means.

Boundaries are computed as `anchor + n × interval` units for any integer `n`,
**including negative ones**. That matters more than it sounds:

- the previous Home generated recurrences *forward* from the anchor, so with the
  anchor defaulted to `.now` there was literally nothing behind you — paging back
  was impossible on a fresh install
- the previous Budget snapped to a calendar week/month boundary, which sits a
  fortnightly budget permanently off-cycle from the fortnight you're actually
  paid on

Each boundary is measured from the anchor rather than by stepping one period at a
time, so a monthly rule anchored on the 31st doesn't ratchet down to the 28th in
February and stay there. There's no bounded search range, so paging back ten
years costs what paging back one does.

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

### Compute once, hold it in state

The other half of performance has nothing to do with the engine: **a computed
property that projects is re-evaluated on every access**, and SwiftUI accesses it
once per mention in the body.

Budget's `summary` used to be exactly that. The body touched it about twenty-five
times per render (eleven in the stat tiles alone, once more per schedule line),
and each touch re-projected every schedule *and* re-ran reconciliation. The
envelope card added a `currentPeriod` call — two years of funding occurrences —
per envelope per render.

Measured on a store the size two years of use produces (49 schedules, 2000
actuals, Debug/simulator):

| | per render |
|---|---|
| before | ~429 ms blocking the main thread |
| after | ~16 ms, and **once per data change**, not per render |

The pattern to keep: hold results in `@State`, recompute in `.task(id:)` keyed on
a signature of the inputs. Home does the same — its `dayCell` used to re-project
the whole period once per calendar cell, thirty-odd times over.

The calendar grid is also drawn eagerly rather than in a `LazyVGrid`: lazy
containers discard and rebuild cells as they leave the viewport, which is what
made the cell borders flicker out and back during a scroll. A period is at most
six rows of seven — there was never anything to be lazy about.

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

**Goal contributions settle through the goal, not through `expected`.** This is
the one asymmetry in the model and it's worth knowing about: `Transaction.expected`
is typed to the `ExpectedTransaction` family, but a scheduled contribution is
sourced from a `Goal`, which isn't one. The old code cast the event's `sourceID`
to `ExpectedTransaction?` and quietly got `nil`, so a contribution was the single
scheduled thing in the app that nothing could ever settle — logging it as an
expense *or* as savings both silently failed. A `Savings` names its `goal`
instead, and reconciliation buckets it by goal id into the same `OccurrenceSlot`
keyspace, so the rest of the matching is one code path as before.

That's also why `LogTransactionView.EntryKind` maps `EventKind` explicitly rather
than matching on `FlowSign`: sign alone put contributions, envelope funding and
ordinary expenses in one undifferentiated pile of outflows, which is how tapping
a contribution landed you on the expense form.

Drift is computed against the *elapsed* part of the window
(`expectedNet(through:)`). Comparing a whole window's plan against actuals
logged so far reads as a catastrophe on day one of the window.

**Envelope funding dates are days, not instants.** An envelope's start date
carries whatever time of day it was created at, and the projector faithfully
preserves it — so a fortnightly envelope created at 15:47 produced cycles like
`[Aug 1 15:47, Aug 15 15:47)` while the budget window is
`[Aug 15 00:00, Aug 29 00:00)`. Two visible bugs fell out of that one mismatch:
the previous cycle ended *after* the window began and leaked in as a phantom
second envelope, and every cycle's exclusive end landed a day late in its label
(`Aug 29` for a cycle that really ends on the 28th). `EnvelopeLedger` and
`ReconciliationService` both snap funding dates to `startOfDay` now, which also
fixes spending logged in the morning of a funding day being counted against the
*previous* cycle.

Envelope rows on the Budget screen are per *funding cycle*, not per envelope: a
fortnightly window can contain two grocery cycles or half of one six-weekly
barber cycle, so every cycle overlapping the window gets a row captioned with the
dates it actually covers. The cycles are generated over a range wider than the
window on both sides — back two years so the carryover chain is honest, forward a
year so the last overlapping cycle reports its true end instead of being
truncated at the window edge.

Picking a slot in the log screen's **Settles** list fills the form from the plan
— name, amount, date, category, and the envelope when it's envelope funding. The
autofill only writes to a field you haven't touched or one it filled itself last
time, tracked in `Autofill`, so changing your mind between two slots re-fills but
typing a name and *then* picking a slot never throws your name away.

That list is drawn as plain rows, deliberately. It was a `Picker(.inline)`, which
outside a `List` renders as a wheel whose rows draw in the system label colour and
vanish against a custom dark theme — you saw a tall blank well with a selection
capsule floating in it.

## Ingestion (designed, not implemented)

`Data/Ingestion/ActualsImporter.swift` is the seam for CSV or a bank feed.
Adding one means writing an `ActualsImporter` conformance and a
`TransactionSource` case — nothing else. Already done and provider-agnostic:

- dedup on `(source, externalID)`
- `ImportPipeline` persistence
- `ActualMatcher`, which decides what an incoming actual settles — and is the
  *same* matcher the manual log screen uses, so the two can't drift apart

## Adjusting several things at once

`PlanAdjustView` exists because the per-item editors answer "add a subscription"
and not the thing people actually do when money is tight: sit down, look at
everything at once, and trade one thing off against another — drop a
subscription, add £10 to groceries, take £20 off dining out. That's one decision
across several items and it needs one screen.

Rows are ordered by **projected cost over the horizon**, not by the headline
amount, because £15/week quietly outranks £40/month and the sticker price hides
that. The running total is the point of the screen: it says whether the
trade-offs you just made actually add up to enough. Nothing is written until you
save, and what's written is an amendment from today.

Goal contributions appear in the list too, but take a different path on save —
a goal's schedule lives on the `Goal` and has no amendment mechanism, so editing
one is a straight edit. Without that branch the field would accept a change and
silently drop it.

## Recommendations

`RecommendationEngine` is the only thing in the app that looks across *many*
windows at once. Everything else asks "how am I doing against the plan"; this
asks whether the plan itself is wrong.

The whole design turns on one distinction: **a one-off miss is noise, a repeated
one is information.** Budgeting £10 and paying £10.20 once means nothing; paying
£10.20 every month for six months means the number is £10.20. So:

- nothing is flagged from a single occurrence (`minimumOccurrences = 3`)
- a difference must clear *both* an absolute floor (£1) and a proportional one
  (5%) to count at all
- most of the sample must be off, *and* leaning the same way — an item that runs
  over one month and under the next is volatility, not a wrong number
- "typical" is the **median**, so one forgotten annual payment can't drag it
  somewhere no individual month ever was
- ordering is by annualised impact, because £600/yr matters more than £6/yr
  however neatly the £6 repeats

Applying a recommendation writes an **amendment**, never a base-amount edit —
rewriting history would destroy the very evidence the recommendation came from.
Applying also *silences* it, and has to: the amendment applies from today
forward while past occurrences keep their old planned figure by design, so the
drift stays detectable forever and the advice would otherwise reappear every
visit no matter how faithfully you followed it.

Any recommendation can be silenced by hand (`DismissedRecommendations`, kept in
UserDefaults — it's a few strings, not budget data, and doesn't deserve a schema
migration). Silenced ones stay listed under a fold rather than vanishing;
dismissals you can't find again are dismissals you can't undo.

The second detector groups *unplanned* spending by normalised name and checks
whether the spacing is regular enough to deserve a recurrence rule, so the
suggestion can name an actual interval instead of "you spend a lot here".

## Goals hold two kinds of money

`contributedAmount` is the sum of logged `Savings` — money that moved through
your cashflow and shows up in the budget as an outflow. `seedAmount` is money
that was already in the pot: a goal you started tracking half-full, or savings
you shuffled across without a transaction happening.

They're separate because folding the second into the first would invent an
outflow that never occurred and make the window it landed in read as overspent.
`currentAmount` is the two added together, and it's the only one the progress bar
cares about.

A goal also carries an **APY**, because a house deposit in a 4% HYSA does not sit
still and over the years it takes to save one, compounding is not a rounding
error. `GoalSimulator` runs the what-if. Two things there are easy to get wrong
and are deliberate:

1. **Interest accrues on time, not per contribution.** Growth depends on how long
   money has been in the account, so the balance rolls forward day by day between
   deposits rather than being multiplied once per deposit.
2. **APY already includes compounding**, so the daily factor is the 365th root of
   (1 + rate), *not* rate/365. The naive version turns a quoted 4% into an actual
   4.08% — small, wrong, and invisible to the eye. Verified: £1,000 at 4% for a
   year comes out at exactly £1,040.00.

Because the cashflow projector deals in money *leaving* your account, it knows
nothing about any of this: interest lives entirely on the goal side.

## Drilling in

Every aggregate on screen opens into the rows it was summed from — Budget's four
stat tiles, its envelope cycles, a calendar day on Home. The rows themselves are
`ScheduledEventRow` and `TransactionRow` in `Components/MoneyRows.swift`, and the
sheet chrome is `DetailSheet`; a planned occurrence and a logged actual should
look the same wherever you meet them, so they're defined once.

Home's "Coming up" hides anything already settled, using the *same*
`ReconciliationService.summary` the Budget screen runs — there is one definition
of "settled" in the app and both screens read it.

## Money on screen

Amounts are stored as bare `Decimal`s and formatted as **symbol + locale-formatted
number**, never through `.currency(code:)` — the symbol is a user setting
(Settings › Currency symbol) and needn't be one any locale knows about. Changing
it re-labels the whole app without touching a stored value. Everything routes
through `Decimal.money` / `.moneyRounded` / `.moneyCompact` / `.moneySigned` in
`Extensions/Formatting.swift`; don't format money anywhere else.

`InputFieldCurrency` is the only money *input*. The symbol is a separate
non-editable label, the `0.00` is a placeholder occupying no text storage (the old
version bound a `TextField` straight to a `Decimal`, so the whole "$0.00" was real
text you had to delete before typing), and keystrokes are filtered to digits plus
at most one decimal separator with two digits behind it.

Any screen with a text field wants `.dismissableKeyboard()` — the decimal pad has
no return key, so without it there is no way to put the keyboard away.

## Adding a @Model

**Put it in `BudgetmaApp`'s `.modelContainer(for:)` list.** SwiftData discovers
models reachable through a relationship *from* something already in the schema —
but `ScheduleAmendment` only points outward, at `ExpectedTransaction`, so nothing
pointed at it and it was silently absent. Inserting one would have thrown at
save time on device. If a new entity isn't in that list, assume it doesn't exist.

The same trap bites in-memory containers used for testing: omit the *base*
`ExpectedTransaction` and the subclass entities come up missing every attribute
they inherit from it, failing with a bewildering
`not key value coding-compliant for the key "amount"`.

## Known gaps

- **No account balance.** Projections are net-flow: the curve starts at zero and
  shows drift. `openingBalance` is plumbed through the whole engine as an
  optional offset — setting it turns every projection absolute without touching
  any maths. This is a deliberate choice, not an oversight.
- Affordability trough is approximate at very long horizons (see above).
- `History` loads every `Transaction` and filters in memory. Fine for years of
  manual entry; if a bank feed ever lands, move the search and the date filter
  into the `@Query` predicate.
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

### What free provisioning actually costs you

Nothing about the *running app* is slowed down or feature-limited. Developer Mode
is a launch permission, not a performance mode, and the install script builds
Release, so the projections run at full speed. The app declares no entitlements
at all (no `.entitlements` file, no capabilities in the project), so there is
nothing currently being withheld from it.

What you actually lose is all about distribution and capability *headroom*:

- the build **expires after ~7 days** and refuses to launch until you rerun the
  script
- **Developer Mode must stay enabled**, and it resets if you erase the device
- **three sideloaded apps at a time**, and ten new App IDs per 7 days
- **no paid-team entitlements** — which today costs nothing, but is the wall
  you'd hit the moment you want iCloud/CloudKit sync of the SwiftData store,
  push notifications, App Groups (a home-screen widget sharing the budget), or
  Sign in with Apple. Local notifications and everything else the app does today
  are unaffected.
- no TestFlight, so no way to put it on a second phone that isn't cabled to this
  Mac

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
