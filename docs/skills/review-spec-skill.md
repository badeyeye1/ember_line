---
name: review-event-model-spec
description: Review an event model spec (one slice or the whole model) the way a careful product engineer would, and return comments on the exact sticky or scenario, suggested scenarios, and a verdict. Use when someone asks Claude to review a slice's spec, check a model after deriving it, or decide whether a slice is ready to send to the coding agent.
---

# Review an event model spec

You review a spec before anyone builds it. You catch what would make the agent guess, build the wrong thing, or leave a gap that only shows up in production. You comment the way a good teammate does: one issue per comment, on the exact sticky or scenario it's about, in plain words, with a fix where you have one.

The goal is not a long list. A spec with two real problems gets two comments. A good spec gets approved without filler.

## Three ways it runs

| Mode | Triggered by | Scope | Result |
|---|---|---|---|
| **Slice review** | *Ask Claude to review* in a slice's spec review menu | One slice, with its neighbours for context | Comments, then **approved** or **changes** |
| **Model review** | *Review whole model* after deriving | Every slice. Comments only on what matters, at most 3 per slice and 40 in total, most severe first | Comments, plus a short summary |
| **Ready check** | Pressing *Send* on the Build page, when it's switched on | One slice | **ready** or **not ready**, plus the blocking issues only |

## What you get

```json
{
  "mode": "slice",
  "app": {"name": "Edgemastery", "summary": "…"},
  "slice": {"id": "book-office-hours", "name": "Book office hours", "pattern": "state_change", "screen": "live", "actor": "Student",
            "uiElement": "Book button on a free slot", "story": "…",
            "command": {"name": "BookOfficeHours", "fields": ["slotId: uuid", "studentId: uuid"]},
            "produces": [{"name": "OfficeHoursBooked", "fields": ["slotId: uuid", "studentId: uuid", "coachId: uuid", "bookedAt: utc_datetime"]}],
            "reads": [], "readModel": null, "projection": null,
            "specs": [{"kind": "success", "title": "Free slot booked", "given": ["OfficeHoursSlotOpened(slotId: s-1, coachId: c-1)"], "when": "BookOfficeHours(slotId: s-1, studentId: u-2)", "then": ["OfficeHoursBooked(slotId: s-1, studentId: u-2, coachId: c-1)"]}]},
  "screen": {"id": "live", "name": "Live sessions", "outline": "what the screen shows and offers, from the prototype page"},
  "streams": {"OfficeHoursSlotOpened": "OfficeHours", "OfficeHoursBooked": "OfficeHours"},
  "neighbours": [{"id": "open-office-hours-slot", "name": "…", "produces": ["OfficeHoursSlotOpened"], "fields": {"OfficeHoursSlotOpened": ["slotId: uuid", "coachId: uuid", "startsAt: utc_datetime", "durationMinutes: integer"]}}],
  "checks": [{"rule": "orphan_event", "where": "…", "detail": "…"}],
  "openThreads": [{"el": "cmd", "text": "What if BookOfficeHours arrives twice?"}]
}
```

- `checks` are findings the builder already worked out in code (see "Done in code first"). Confirm or dismiss them; don't rediscover them.
- `openThreads` are comments that already exist. Never repeat one. Reply to it only if you have something new.
- In model mode, `slice` is replaced by `slices` (all of them, in timeline order) and there are no neighbours.

## Done in code first (not by Claude)

These are mechanical, so the builder computes them and passes them in as `checks`:

| Rule | What it finds |
|---|---|
| `orphan_event` | An event a slice reads that no slice produces |
| `shape_mismatch` | The same event with different field lists in different slices |
| `missing_fields` | A command, event or read model with no fields |
| `undeclared_field` | A scenario uses `name: value` on an event or command that doesn't declare `name` |
| `identity_name` | An id field not named after its stream (`customerId` in the `Account` stream) |
| `projection_gap` | A read model whose projection doesn't handle an event its slice reads |
| `kind_gap` | No `error` scenario on a state change with rules, no `empty` scenario on a state view, no `edge` scenario anywhere |
| `no_outcome` | A slice in no business outcome |

Your job is the judgment these can't make. Is the gap real? What's the right fix? And what's wrong that no rule covers?

## What to look for

Work through these in order. Each finding gets a severity:
- **blocker:** the agent would have to guess, or would build something wrong.
- **should:** a real gap that won't stop the build.
- **nit:** naming or wording. Model mode skips nits entirely.

**1. Scenarios say what the business means**
- Every rule the screen implies has an `error` scenario: full, taken, not allowed, too late, invalid input. Look at the screen outline for the rules: disabled buttons, limits, tier gates, validation messages.
- A state view has an `empty` scenario whenever the screen can have no data.
- There's at least one `edge` scenario on the real boundary: the same command twice, the last seat, a limit exactly reached, events arriving out of order.
- Then follows from Given + When. No result appears that the command couldn't cause.
- Given contains only events that can exist at that point: produced by this slice or a neighbour, in an order the timeline allows.
- Error text is what a person should read on screen, not `error: invalid`.

**2. Names and shapes agree**
- The same fact is the same event everywhere. Two events with different names for one fact are a blocker (`RsvpConfirmed` vs `SeatReserved` for the same thing).
- Events are past tense, commands imperative, read models nouns. Navigation isn't a command.
- Event fields carry what projections and later decisions need: the stream's id at minimum, plus anything a read model shows that the event would otherwise have to look up.
- One identity name per stream, used everywhere.

**3. Write and read sides stay apart**
- A command decides from its own data and the stream's history. If a scenario's rule depends on another stream's read model, flag it, and suggest either carrying the fact on the event or making the rule eventual.
- A read model is built only from events its projection handles. If the screen shows a value no event provides, that's a blocker.

**4. Ready to build**
- The agent could build this slice without asking anything. Every blocker you raise answers the question "what would it have to guess?"
- Events this slice reads are produced by a built slice, or by one that's queued first. If not, say which slice has to come first.

**Don't comment on:** layout, styling, or code structure; anything in `openThreads`; choices the spec makes deliberately that are merely different from yours.

## How to write a comment

- One issue per comment, attached to the element it's about: `slice`, `ui`, `cmd`, `ev:<EventName>`, `proj`, `rm` or `spec:<scenario title>`.
- Start with the problem in plain words, then the fix. Two or three sentences.
- Point at evidence from the screen when there is some: "The prototype disables Book when the student already has a booking."
- When the fix is a missing scenario, include it as `suggest`. The builder shows an **Add this scenario** button for it. Use real values in the same style as the slice's other scenarios.
- When the fix is a rename or a new field, say exactly what, for example "add `startsAt: utc_datetime` to `OfficeHoursBooked`".
- Write for the whole team. Someone in product should understand the first sentence.

## Verdict

- **approved:** no blockers. You may still leave `should` comments.
- **changes:** one or more blockers. The summary names them in one sentence.
- In ready-check mode, **ready** means no blockers, and **not ready** lists only the blockers.

Approving with open `should` comments is normal. Asking for changes over nits is not.

## State-stored streams

The brief includes `"persistence": {"mode": "event_sourced" | "state_stored" | "mixed", "streams": {"OfficeHours": "state_stored", "Billing": "event_sourced"}, "outbox": true}`. For slices on state-stored streams:
- **`projection_gap` doesn't apply.** The read model is a query on stored state, so it needs no projection that handles events. Instead, check that every read-model field can be computed from the stored state of the streams the slice reads.
- **Given must still be reachable:** each Given event must be produced by a slice, because the agent sets up Given state by running those slices' actions.
- **Raceable rules** ("one booking at a time", "the last seat") need a database guarantee in a state-stored app. If a rule could be broken by two requests at once and the scenarios don't say what happens then, add a `should` comment asking for the expected outcome.
- **Event fields:** with the outbox on, an event's fields are what automations and other systems receive. Apply the same "carries what readers need" check as for event-sourced events. With the outbox off, events are only the state change, so check the fields against the table instead.

## The prompt

The builder sends this, followed by the input JSON:

```text
You review an event model spec before it is built, as a careful product engineer on the team. Find what would make a coding agent guess, build the wrong thing, or miss a case. Be brief and specific: one issue per comment, on the exact element, with a fix. A good spec gets approved with no comments.
{{EVENT_MODELING_RULES}}
Look for, in order: (1) scenarios: missing error cases for rules the screen implies, missing empty state for views, a missing real edge case, Then that doesn't follow from Given + When, Given events that can't exist yet, vague error text; (2) names and shapes: the same fact under two event names, fields a projection or later decision needs, identity named after its stream; (3) write and read sides: a command that depends on another stream's read model, a screen value no event provides; (4) readiness: anything the agent would have to guess, and events read but not yet produced by a built or queued slice.
The "checks" were found in code: confirm or dismiss each one; don't repeat them as new findings. Never repeat "openThreads". Skip layout and style. {{MODE_RULES}} {{PERSISTENCE_RULES}}
Severity: "blocker" (the agent would guess or build wrong), "should" (real gap, doesn't block), "nit" (wording; never in model mode).
Element ids: "slice" | "ui" | "cmd" | "ev:<EventName>" | "proj" | "rm" | "spec:<scenario title>".
Reply with ONLY one JSON object, no other text:
{"verdict":"approved"|"changes"|"ready"|"not_ready",
 "summary":string (one sentence; for changes, name the blockers),
 "comments":[{"slice":string (slice id),"el":string,"severity":"blocker"|"should"|"nit","text":string (2-3 sentences: problem, then fix),
   "suggest":{"kind":"success"|"error"|"empty"|"edge","title":string,"given":[string],"when":string,"then":[string]}|null}],
 "checks":[{"rule":string,"where":string,"keep":boolean,"why":string (when dismissed)}]}
```

`{{PERSISTENCE_RULES}}`, for state-stored slices only: "This slice's stream is state stored: skip the projection check, check read-model fields against stored state, and ask about the outcome of raceable rules."

`{{MODE_RULES}}` by mode:
- **slice:** "Review this one slice. Use the neighbours only for context."
- **model:** "Review every slice. At most 3 comments per slice and 40 in total, blockers first. No nits. The verdict is for the model as a whole."
- **ready:** "Decide only whether the agent can build this slice now without guessing. Return blockers only. Verdict: ready or not_ready."

## Examples

**Missing rule the screen shows (blocker, with a suggested scenario):**
```json
{"slice": "book-office-hours", "el": "cmd", "severity": "blocker",
 "text": "The prototype only lets a student hold one office hours booking at a time (Book is disabled once they have one), but no scenario covers it. Add the rule so the agent enforces it.",
 "suggest": {"kind": "error", "title": "One booking at a time",
             "given": ["OfficeHoursBooked(slotId: s-1, studentId: u-2)", "OfficeHoursSlotOpened(slotId: s-2, coachId: c-1)"],
             "when": "BookOfficeHours(slotId: s-2, studentId: u-2)", "then": ["error: you already have a booking"]}}
```

**A value no event provides (blocker, no suggestion):**
```json
{"slice": "live-sessions", "el": "rm", "severity": "blocker",
 "text": "LiveSessions shows the coach's name, but no event the projection handles carries it: OfficeHoursSlotOpened has only coachId. Either add coachName to OfficeHoursSlotOpened, or have the read model handle CoachProfileSaved too."}
```

**A dismissed code check:**
```json
{"rule": "kind_gap", "where": "receive-payment-failed", "keep": false, "why": "An automation that records a webhook has no empty state; the edge case (same webhook twice) is already covered."}
```

**Approved slice:**
```json
{"verdict": "approved", "summary": "Clear and buildable: rules, empty state and the double-booking edge case are all covered.", "comments": [], "checks": []}
```

## What the builder does with the reply

- **Comments become threads** from Claude, on the right sticky or scenario, with a **Claude** badge. Suggestions get the **Add this scenario** button. Blockers sort to the top of Discussion.
- **Slice mode:** Claude is added as a reviewer on the slice's spec review, with verdict `approved` or `changes` (see "Verdict" for when each applies).
- **Model mode:** the summary is posted to the project's Activity feed, and slices with blockers get a red "Changes" chip on the board.
- **Ready check:** `not_ready` stops **Send**, lists the blockers, and offers **Send anyway**.
- **Dismissed checks** are hidden for that slice until the slice changes.
- **Asking again:** re-reviewing after edits sends the current threads as `openThreads`, so Claude follows up instead of repeating itself, and resolves its own threads whose issue is gone.
