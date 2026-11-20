---
name: plan-event-model-build-order
description: Plan the order in which an event model's slices should be built — dependencies from events read and produced, waves that can run in parallel, outcome-first sequencing so each business outcome works end to end early, and blockers to resolve before sending — for a coding agent or a team. Use when someone presses Send all on the Build page, asks what to build first, or wants a build plan or roadmap from an event model.
---

# Plan the build order

Slices depend on each other through events. A slice that **reads** `OfficeHoursSlotOpened` can't be tested until the slice that **produces** it exists. Send slices in timeline order, or all at once, and the agent gets blocked, stubs a neighbour, or builds a slice against an event nobody records yet.

This skill orders the slices so that:
- every slice is built after the slices it depends on;
- slices that don't depend on each other are built at the same time;
- each business outcome works end to end as early as possible;
- anything that would block the agent is caught before it's sent.

## When it runs

| Trigger | Scope | Result |
|---|---|---|
| **Send all** on the Build page | All slices ready to send | Sends wave 1 now, and queues later waves to send as earlier ones merge |
| **Send** on one slice | One slice and what it depends on | Sends it if its dependencies are built, otherwise offers to send them first |
| **Plan the build** on the board | All slices not yet built, or one outcome | A build plan to review: waves, outcome milestones, blockers |
| A slice merges, or the model changes | The remaining plan | Re-plans and moves queued slices up when they become unblocked |

## What you get

```json
{
  "slices": [{"id": "book-office-hours", "name": "Book office hours", "pattern": "state_change", "screen": "live", "status": "planned",
              "produces": ["OfficeHoursBooked"], "reads": [], "readModel": null,
              "specGiven": ["OfficeHoursSlotOpened", "OfficeHoursBooked"],
              "review": "approved", "ready": true, "work": null}],
  "outcomes": [{"id": "every-trade-gets-timely-coaching", "name": "Every trade gets timely coaching", "slices": ["request-ai-review", "post-coach-review", "book-office-hours"]}],
  "streams": {"OfficeHoursSlotOpened": "OfficeHours", "OfficeHoursBooked": "OfficeHours"},
  "built": ["create-account", "sign-in", "log-trade"],
  "inFlight": [{"slice": "schedule-group-call", "state": "review"}],
  "capacity": {"parallel": 2},
  "priorities": ["every-trade-gets-timely-coaching"],
  "graph": { /* computed in code, see below */ }
}
```

- `specGiven` is every event named in the slice's scenarios. A scenario's Given events must exist too, even if the slice doesn't read them.
- `capacity.parallel` is how many slices the agent (or team) builds at once.
- `priorities` lists outcomes someone has marked to go first, if any.

## Done in code first (not by Claude)

The dependency graph is mechanical, so the builder computes it and passes it in as `graph`:

| Step | Rule |
|---|---|
| Edges | Slice B **depends on** slice A when B reads, or names in a scenario's Given, an event that A produces |
| Built and in-flight slices | Satisfy their edges. Built ones are done; in-flight ones finish first |
| Events from several producers | Any one built producer satisfies the edge. Otherwise the first producer in timeline order is the dependency |
| Orphans | An event read or used in a Given that no slice produces. Every slice that needs it is **blocked** |
| Cycles | Strongly connected slices (A reads B's event and B reads A's) |
| Waves | Topological layers: wave 1 has no unbuilt dependencies, wave 2 depends only on wave 1, and so on |
| Critical path | The longest dependency chain per outcome |

Your job is the judgment:
- order slices within and across waves by business value;
- break cycles sensibly;
- decide what to do about orphans and slices that aren't ready;
- split large waves to fit the capacity;
- explain the plan in a few lines a team can agree to.

## Rules

- **Check ahead before handing over.** Before the agent starts the next slices in this order, run `review-spec-skill.md` in **ahead** mode on the next 3 to 5 of them, plus every slice that shares a command or an event with them. Fix the model until they're ready, then hand them over. A slice that isn't ready stays out of the agent's queue.

**1. Dependencies are hard; everything else is preference**
- Never place a slice before a slice it depends on.
- In-flight slices count as coming first. Don't re-send them.

**2. Outcome first**
- Within what dependencies allow, finish one outcome end to end before spreading across many. A working thread through the app beats eight half-built screens.
- Order outcomes by:
  1. `priorities`, if set;
  2. outcomes closest to done (fewest unbuilt slices);
  3. outcomes whose slices unblock the most other slices.
- Within an outcome, follow the timeline: state changes that produce events first, then the views and automations that read them.

**3. Fit the capacity**
- Each wave holds at most `capacity.parallel` slices, preferring slices from the current outcome.
- Two slices that write to the same stream in the same wave risk merge conflicts in the same resource file. Put them in separate waves unless capacity would otherwise sit idle, and say so when you do.

**4. Blockers before sending**
- **Orphan events:** the slice can't be built. Name the missing source, and point to the reviewer's or repair skill's fix ("add an automation that receives PaymentFailed from the payment provider").
- **Not ready** (fails the Done checks, has no scenarios, or its review asks for changes): hold it, and say what's missing.
- **Cycle:** pick the slice to build first, the one whose read can start empty (a view or check that tolerates no data yet). Say why, and note that its scenarios with the other slice's events in Given are written against the first slice's tests until both exist.
- Never quietly drop a slice from the plan. Everything ends up in a wave, on hold, or blocked.

**5. Explain**
- One line per wave: what it delivers, in business terms.
- Mark the milestone where each outcome works end to end.
- Keep the whole explanation to a few short paragraphs. The waves carry the detail.

## State-stored streams

The dependency rule is the same: a slice waits for the slices that produce what it reads or names in a Given. In a state-stored app, "produces" means the action that creates or changes the rows the reader needs, which is the same slice in the model.

Two extra rules:
- **The outbox:** the first state-stored slice with events creates the shared `DomainEvent` resource. Put it in the earliest wave, or let a later slice in the same wave wait for it, and say so in that wave's note.
- **One resource file per stream:** state-stored slices on the same stream usually edit the same Ash resource file, so the merge-conflict rule ("not two writers on one stream in a wave") matters more. Apply it strictly unless capacity would otherwise sit idle.

## The prompt

The builder sends this, followed by the input JSON and the graph:

```text
You plan the order in which an app's event model slices are built by a coding agent working {{capacity.parallel}} slices at a time. The dependency graph ("graph") was computed in code: a slice depends on the slices that produce the events it reads or names in a scenario's Given. Rely on it.
Rules: never place a slice before one it depends on; in-flight slices come first and are not re-sent. Within what dependencies allow, finish one business outcome end to end before spreading across many: order outcomes by "priorities", then by fewest unbuilt slices, then by how many other slices they unblock; within an outcome, follow the timeline (state changes that produce events, then views and automations that read them). Each wave holds at most {{capacity.parallel}} slices; avoid two slices writing the same stream in one wave unless capacity would sit idle, and say so. Slices that read an event nothing produces are blocked: name the missing source. Slices not ready (failing Done checks, no scenarios, review asked for changes) are on hold: say what's missing. For a cycle, build first the slice whose read tolerates no data yet and say why. Every slice ends up in a wave, on hold, or blocked; drop nothing.
Write for the team: one line per wave on what it delivers in business terms, and mark the wave where each outcome works end to end. Use slice names, not ids, in the text.
Reply with ONLY one JSON object, no other text:
{"waves":[{"n":number,"slices":[string (slice ids)],"delivers":string (one line, business terms),"completes":[string (outcome ids that work end to end after this wave)],"note":string|null (e.g. why two same-stream slices share the wave)}],
 "onHold":[{"slice":string,"missing":string (what must change before it can be sent)}],
 "blocked":[{"slice":string,"event":string,"fix":string (the source to add)}],
 "cycles":[{"slices":[string],"first":string,"why":string}],
 "milestones":[{"outcome":string,"wave":number}],
 "summary":string (2-4 sentences: how many waves, what works when, what's blocked)}
```

## Example: Edgemastery, coaching first

Input: 143 slices, with 9 built and 1 in review. Capacity is 2, and "Every trade gets timely coaching" is the priority. Abridged:

```json
{"summary": "Coaching works end to end after wave 4: students can request reviews, coaches can review, and office hours can be opened, booked and cancelled. Trade journalling and analytics follow in waves 5–9. Two slices are blocked on events nothing records yet, and one is on hold until its review is answered.",
 "waves": [
  {"n": 1, "slices": ["request-ai-review", "open-office-hours-slot"], "delivers": "Students can ask for an AI review of a trade; coaches can open office-hours slots.", "completes": [], "note": null},
  {"n": 2, "slices": ["post-coach-review", "book-office-hours"], "delivers": "Coaches can review trades; students can book a free slot.", "completes": [], "note": null},
  {"n": 3, "slices": ["cancel-office-hours-booking", "live-sessions"], "delivers": "Students can cancel a booking and see their upcoming calls and slots.", "completes": [], "note": "Both touch OfficeHours: cancel writes the stream, Live sessions only reads it, so they don't collide."},
  {"n": 4, "slices": ["trade-detail", "remove-office-hours-slot"], "delivers": "The trade page shows AI and coach reviews; coaches can remove a slot.", "completes": ["every-trade-gets-timely-coaching"], "note": null}],
 "onHold": [{"slice": "schedule-group-call", "missing": "Already in review (PR #236); merges before anything that reads GroupCallScheduled is sent."}],
 "blocked": [
  {"slice": "billing", "event": "PaymentFailed", "fix": "Add an automation that receives failed-payment notices from the payment provider (the repair skill proposes one)."},
  {"slice": "replay-attempt", "event": "ReplaySessionPlayed", "fix": "Add the 'Finish replay session' slice on the replay screen."}],
 "cycles": [],
 "milestones": [{"outcome": "every-trade-gets-timely-coaching", "wave": 4}]}
```

## Example: a cycle

```json
{"cycles": [{"slices": ["promote-from-waitlist", "waitlist-queue"], "first": "waitlist-queue",
  "why": "The waitlist view can start empty; promotion needs the queue to pick who's next. Build the view first, then promotion, whose scenarios fill the queue through Join waitlist."}]}
```

## What the builder does with the reply

- **Plan the build:** shows the waves as columns on the Build page, with each outcome's milestone marked ("Coaching works after wave 4"). Blocked and on-hold slices are listed with their fix. Each blocker links to the slice's Discussion, or to **Repair model** when the fix is a missing source.
- **Send all:**
  - Sends wave 1.
  - When every slice in a wave merges, sends the next wave automatically, unless the team turns auto-send off.
  - When a slice gets stuck in Needs changes, slices that depend on it wait, and the rest of the wave carries on.
- **Send on one slice** whose dependencies aren't built: offers **Send with its dependencies**, which sends the missing producers first.
- **Re-planning:** after every merge, model change or answered question, the plan is recomputed. Slices move up as they're unblocked, and the change is noted in Activity ("Book office hours moved to wave 2: Open office hours slot merged").
- **The plan is a proposal.** People can drag a slice to another wave. Moves that would break a dependency are refused, with the reason.

## Done means
- No slice comes before a slice it depends on.
- Every slice is in a wave, on hold with what's missing, or blocked with the source to add.
- The priority outcome, or the outcome closest to done, works end to end at the earliest wave the dependencies allow.
- No wave is larger than the capacity.
- The team can read the summary and the per-wave lines and agree to the plan without opening the model.
