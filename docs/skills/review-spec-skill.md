---
name: review-event-model-spec
description: Review an event model spec (one slice, one feature or the whole model) the way a careful product engineer would, and return comments on the exact sticky or scenario, suggested scenarios, and a verdict. Use when someone asks Claude to review a slice's spec, check a model after deriving it, check a feature before building it, or decide whether a slice is ready to send to the coding agent. The coding agent also uses its checklist before writing tests.
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
| **Feature check** | *Check this feature* in a feature's boundary panel, before the team starts building it | One feature's slices, plus the events it reads from and owes other features | Comments, and **ready** or **not ready** per slice |
| **Ahead check** | Before the coding agent starts a stretch of work: the next slices in its build order (see `plan-build-order-skill.md`) | The next 3 to 5 slices, plus every slice that shares a command or an event with them | Comments, and **ready** or **not ready** per slice. Fix the model, then hand the slices over |

The coding agent runs the same checklist on its own slice before writing tests (see the build skills, step 3). Anything it finds comes back as spec questions, and the answers go into the model.

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
| `field_source` | An event field that isn't a command field, isn't a timestamp (`…At`) or generated id, and isn't carried from an earlier event of the same stream. Nobody has said where its value comes from. |
| `name_split` | A command field with no event field of the same name, while the event has a field the command lacks that plays the same part (`actorId` on the command, `memberId` on the event) |
| `taken_case` | A command field that must be unique (`slug`, `email`, `url`, `handle`, `domain`, or a `name` the screen says is unique) with no error scenario for a value already in use |
| `secret_case` | A command with a `code`, `password`, `token` or `pin` and no scenarios for wrong, expired and too many tries |
| `open_values` | A `string` field whose name says it's one of a set: `stack`, `plan`, `role`, `status`, `kind`, `type`, `method`, `tier`, `channel` |
| `screen_gap` | A button, link, form or data area on the screen's prototype page that no slice on that screen covers, by trigger (`uiElement`) or by a read-model field |
| `build_order` | A scenario whose Given uses an event that only a later slice produces (in build order), with no scenario for the time before that slice exists |
| `derived_rule` | An event field the command doesn't supply but the system works out (a slug, a default name, a count, an expiry), with no scenario showing how |
| `shared_command` | Two slices send the same command but with different field lists, or give different error text for the same case |
| `message_variants` | A message with a count or a name in it, with no scenario or rule for 1 (singular), 0, or several names |
| `missing_parent` | A command on something inside a project or workspace with no "doesn't exist" scenario |

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

**5. Every value has a source, and every case has a scenario**

These are the gaps that coding agents hit most often, because a prototype shows the happy path and nothing else. Each one stops a build and costs a round trip, so in a ready, feature or ahead check they are blockers. The examples come from a workshop-booking app and a SaaS admin area; the patterns hold for any app.
- **Where a value comes from.** Every event field comes from the command, from the stream's earlier events, or from the system (ids, timestamps). Anything else must be explained, or dropped. *Example: `WorkshopScheduled` has a `hostName` that `ScheduleWorkshop` never receives.*
- **One name per value.** The command field and the event field for the same value share a name. Who did it is `<verb>By` on both (`bookedBy`, `cancelledBy`). *Example: `actorId` on the command becomes `memberId` on the event.*
- **Taken, wrong, expired, too many.** A unique value needs a "taken" scenario with the on-screen text. A secret (code, password, token) needs "wrong", "expired" (and for how long), and "too many tries" (and how many). *Examples: a web address another account already uses; a 6-digit code that doesn't match.*
- **Closed lists.** A field that can only be one of a set lists the set as an `enum`, and an error scenario rejects anything else. *Example: a `plan` or `level` field typed as plain text.*
- **Everything on screen.** Every button, link and number on the screen's prototype page is covered by a slice: a trigger, or a read-model field with a projection behind it. *Example: a card's progress bar, Open and Delete buttons with no slices.*
- **What holds until a later slice exists.** If a rule depends on something a later slice adds (roles, plans, integrations), there's a scenario for now and one for after. *Example: "admins can cancel" before member roles exist.*
- **Worked-out values.** Anything the system works out (slugs, default names, expiry times, counts) has a scenario showing the rule, including what happens on a clash. *Example: a workshop's web address made from its title, when that address is taken.*

**6. Rules, not just examples**

Scenarios are examples; the agent needs the rules behind them. Every slice whose behaviour goes beyond one example per case has a **Rules** list in its story: numbered, plain sentences that say what always happens. Each rule has at least one scenario as its example, and each scenario follows from a rule. These are the gaps that remain once (5) is in place:
- **Several at once: which wins.** When more than one error can apply, the rules give the order. *Example: an upload with an unreadable file and a file over the size limit: which message shows?*
- **Limits.** For every limit: what counts towards it, which items are kept (first by name? in the order received?), what happens to the rest, what the person is told, and whether the other limits count the dropped items. *Examples: at most 80 files per upload; 50 invites at a time; a waitlist of 20.*
- **Sentences with numbers or names.** Any message with a count or a name needs its variants: 0, 1 and many ("1 seat", "5 seats", nothing about seats when there are none), and how several names are listed ("a and b", "a, b and c"). *Example: "3 seats left" with no wording for one seat or none.*
- **Work done outside the aggregate.** When something happens before or after the command (the browser reads a file, a background job calls another service, an email is sent), the rules say: where it runs, what results the command carries, where large results are stored (a state-stored record, never an event), how progress, Stop and failure are shown, and the time limit. *Examples: importing a spreadsheet; asking an AI service to draft something; a payment provider's callback.*
- **Everything the event records arrives in the command.** Including values taken from a stored record or a job's result. *Example: an automation adds items from an imported file, but its command lacks fields the event records.*
- **Matching and "already exists".** Any rule that compares against what's already there names the read model that holds it, and says what makes two things the same. *Example: "skip attendees already on the list" with no read model of who is on the list, and no rule for matching (email? name?).*
- **Repeats and restarts.** The same command twice, the same id twice, a restart half way: does it record nothing, fail, or replace? *Example: a booking command arriving twice after a network retry.*
- **Missing or deleted parents.** A command on something inside a parent (a workspace, a project, a course) has a scenario for "doesn't exist" and "was deleted". *Example: booking a workshop that was cancelled and removed.*
- **One command, one behaviour.** Slices that send the same command (a page and an onboarding screen, a manual add and an automation) share the same rules. Read every slice that sends it. *Example: inviting people from the members page and from the welcome screen, with different handling of people already invited.*
- **What people receive and see.** Emails and links say their subject, the key line, the link and what the link's token is for. Screens say how each thing is shown and what's shown again after a reload. *Examples: an invite email and its join link; a notice that must still show after the page is reopened.*
- **Scenarios that stand on their own.** Every value in a Then appears in the Given or When, or follows from a rule. *Example: a Then names a read model or a price the setup never mentions.*
- **Other features' events.** A scenario that needs an event from another feature that isn't built is marked "(built with <slice>)", so one pull request touches one feature.

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
Look for, in order: (1) scenarios: missing error cases for rules the screen implies, missing empty state for views, a missing real edge case, Then that doesn't follow from Given + When, Given events that can't exist yet, vague error text; (2) names and shapes: the same fact under two event names, fields a projection or later decision needs, identity named after its stream; (3) write and read sides: a command that depends on another stream's read model, a screen value no event provides; (4) readiness: anything the agent would have to guess, and events read but not yet produced by a built or queued slice; (5) every value has a source and every case a scenario: event fields nobody supplies, one value under two names, unique values with no "taken" case, secrets with no wrong/expired/too-many-tries cases, strings that should be a closed list, things on screen no slice covers, rules that depend on a later slice, worked-out values with no rule; (6) rules, not just examples: a missing Rules list, no order when several errors apply, limits that don't say what counts and what's kept, sentences with numbers or names missing their 0/1/many or several-names wording, work outside the aggregate without its results, storage, progress, Stop and failure, an event value the command doesn't carry, matching with no read model to match against, repeats and restarts, missing or deleted parents, slices sharing a command with different rules, emails and links without their content, scenarios whose Then names something the setup doesn't.
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
- **feature:** "Review every slice in this feature, plus the events it reads from and owes other features. Findings under (5) are blockers. At most 5 comments per slice. Give a verdict per slice in the summary: ready or not_ready."
- **ahead:** "Review these slices as the coding agent will meet them next, in build order, plus every slice that shares a command or an event with them. Findings under (5) and (6) are blockers. Give a verdict per slice: ready or not_ready."

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

**A field with no source (blocker):**
```json
{"slice": "schedule-workshop", "el": "ev:WorkshopScheduled", "severity": "blocker",
 "text": "WorkshopScheduled has a hostName, but ScheduleWorkshop doesn't take one, so the agent would record it empty. The host is already on the Host stream: carry hostId on the command and read the name in the read model, or drop hostName."}
```

**A unique value with no "taken" case (blocker, with a suggested scenario):**
```json
{"slice": "rename-workshop", "el": "cmd", "severity": "blocker",
 "text": "Workshop web addresses are unique, but no scenario says what happens when another workshop already uses one. Add the case with the words the screen should show.",
 "suggest": {"kind": "error", "title": "Address already taken",
             "given": ["WorkshopScheduled(workshopId: w-1, slug: pottery)", "WorkshopScheduled(workshopId: w-2, slug: pottery-101)"],
             "when": "RenameWorkshop(workshopId: w-1, title: Pottery 101, slug: pottery-101, renamedBy: host-1)", "then": ["error: That address is taken. Try another."]}}
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
- **Feature check:** slices that are not ready get a red "Changes" chip, and the feature's card on the board shows how many are ready.

## Answering spec questions

An answer can open a new gap: a new error message with a file name in it needs "and if there are several?"; a new field on an event needs to be on the command; a new scenario on one slice may contradict another slice that sends the same command. So after writing answers into the model:
1. Write each answer as a rule in the slice's Rules list, not only as a new scenario. Add scenarios for its variants (0, 1, many; several names; which wins).
2. Run the Spec check and an ahead check on the changed slices and on every slice that shares a command or event with them.
3. Only then publish the model and tell the agent.

## Learning from the build

When the coding agent stops with a spec question that this review didn't catch, the review missed a pattern. After the answer goes into the model:
1. Say which question in "What to look for" should have caught it, or add a new bullet under (5) or (6). Write its example so it isn't tied to one project: these skills are used on every app the builder models.
2. If the pattern is mechanical, add a row to "Done in code first", so the builder finds it without Claude next time.
3. Run the feature check again on the slices not built yet: the same gap usually appears in more than one place.
4. Run the ahead check before every stretch of building, not after the agent stops. Hand over a slice only when the ahead check says ready.
