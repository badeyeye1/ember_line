---
name: sync-event-model-with-code
description: Keep an event model true to the codebase after slices are built — read changes merged outside the builder, find events, commands, read models, rules and tests the model doesn't know about or no longer matches, and propose model updates as a reviewed diff, flagging edits to stored events and contradictions of approved specs instead of applying them. Use when code changes land on the main branch outside the builder, on a scheduled drift check, or when someone asks whether the model still matches the code.
---

# Keep the model in sync with the code

The builder's skills all trust the board: the reviewer checks it, the agent builds from it, the PR checker compares code against it, and the business signs it off. Once slices are built, though, people change code outside the builder: a hotfix adds a validation, someone adds a field to a read model, a handler is renamed. Each change is small, but the board slowly stops being the truth.

This skill reads what changed in the code and brings the model back in line. It proposes, never imposes:
- **Code that adds or clarifies behaviour** becomes a proposed model update, which a person approves.
- **Code that breaks the history or contradicts an agreed spec** becomes a question for the team, not a silent update.

## When it runs

| Trigger | Scope |
|---|---|
| A pull request merges into the main branch **without** a builder slice link (no `em/` branch and no slice in the description) | That merge's diff |
| A builder-made pull request merges with extra commits made after the PR checker last ran | Those commits |
| Weekly drift check (scheduled) | Everything merged since the last sync |
| **Check against code** on the board | The whole codebase against the whole model |

## What you get

```json
{
  "model": { /* the current model, with each slice's code links: files, modules, actions, tests */ },
  "built": [{"slice": "book-office-hours", "events": ["OfficeHoursBooked"], "approvedSpec": true}],
  "changes": [{"commit": "a1b2c3d", "pr": 241, "author": "tomi", "title": "Hotfix: block booking within 1 hour of start", "mergedAt": "2026-11-18T10:02:00Z",
               "files": [{"path": "lib/edgemastery/live_sessions/office_hours_slot.ex", "status": "modified", "diff": "…", "after": "full file"}]}],
  "notes": { /* code-scan notes for changed files: commands, events, aggregates, projectors, read models, screens, writes, tests (the codebase-reading skill's format) */ },
  "lastSync": "2026-11-11T09:00:00Z"
}
```

`notes` reuses the codebase-reading skill's scan of each changed file, so this skill works on what the code does, not on raw diffs alone.

## Done in code first (not by Claude)

| Step | Rule |
|---|---|
| Which changes count | Merges since `lastSync`, minus builder-made pull requests the PR checker approved with no later commits |
| Link changes to slices | A changed file belongs to every slice whose code links name it. Unlinked files that define commands, events, projectors or LiveViews are "new code" |
| Event diffs | Before and after for every event definition (DSL `event` blocks and event structs): fields added, removed, renamed or retyped |
| Error atoms and messages | Every new `{:error, …}`, validation message or error atom in a changed write-side file |
| Test titles | New, renamed and removed `test "…"` names, matched to scenario titles |
| Migrations | Added, altered or dropped tables and columns |

## What to look for

**1. New behaviour the model doesn't have**
- **A new command, event or read model:**
  - inside an existing slice's scope, it's an addition to that slice;
  - otherwise it's a new slice, with its pattern, screen, actor and stream taken from the code.
- **A new rule** (validation, error return, aggregate check) with no matching scenario. Propose an `error` scenario using the rule's own message and condition. Example: "If the session starts within 1 hour, the student sees 'Too late to book' and nothing is booked."
- **A new screen behaviour** (a LiveView event that dispatches a command, a new list on a page). Link it to its slice, or propose a new slice.

**2. Changed behaviour**
- **A field added to a command or read model:** propose adding it to the model.
- **A field added to an event:** acceptable only if it's optional. Propose it as an additive change. If it's required and old events can't have it, it's a history problem (see 3).
- **A rule changed** (a limit, a message, a condition): propose updating the scenario to match, and quote both versions.
- **Renamed handlers, modules or actions:** update the code links only. Model names don't change because a module was renamed.

**3. Things that must not be applied quietly**
- **A stored event edited in place** (a field removed, renamed or retyped, or a module renamed): stored history may no longer load. Don't update the model. Raise it as urgent, and hand it to the event-change skill to plan a proper new version, or a fix-forward if it's already deployed.
- **Code that contradicts an approved spec:** a scenario says one thing and the code now does another. Don't pick a side. Ask the team, quoting both: either the spec changes (and goes back through review) or the code is reverted.
- **Removed behaviour:** a command or handler deleted, or a scenario's test removed. Don't delete the slice. Mark it as possibly removed and ask, because removing behaviour is a product decision.

**4. Tests**
- A new test whose name matches no scenario: propose the scenario it describes, if it reads as a business rule. Otherwise ignore it as a technical test.
- A renamed test: propose renaming the scenario only if the behaviour changed. Otherwise suggest renaming the test back so they stay matched.

**Don't propose:** refactors, formatting, internal helpers, logging, or performance changes. Anything that changes neither what a command decides, what an event records nor what a screen shows is out of scope.

## State-stored streams

For streams the project stores as state, events are the state changes the code makes, the same way the codebase-reading skill reads CRUD code.
- **A new write** (an action, changeset or controller update that changes state) is a command and its event. Name the event as a past-tense fact.
- **Don't propose projectors.** A new query or read action is a read model on its slice.
- **New outbox types** (`DomainEvent` rows with a type the model doesn't have) are events the model is missing. Propose them on the slice whose action writes them.
- **Destructive migrations** (drop, rename, retype) are questions with the data risk spelled out, handed to the event-change skill's state-stored section. With the outbox on, a renamed or removed outbox key is urgent.
- **Storage drift:** if a stream's code changes style (CRUD code gains an aggregate, or event-sourced code is replaced by a table), propose updating the project's storage setting for that stream, as a question.

## Hologram screens

On stacks with Hologram, screen behaviour lives in pages and components (`use Hologram.Page`, `~HOLO` templates, `.holo` files). A new `command/3` that dispatches a command or calls a write action is a new or changed command on the screen's slice. A new `action/3` that only changes client state is UI, not a model change. A rule added only to a client action is flagged as a question ("this rule isn't enforced on the server"), not proposed as a scenario.

## Elm screens

On stacks with Elm, screen behaviour is split between the Elm page and the JSON endpoints behind it.
- A new `Msg` that sends a request to a write endpoint, together with that endpoint's controller, is a new or changed command on the screen's slice. The controller says what it does.
- A new read endpoint, or new fields in its JSON, is a read-model change.
- A changed decoder alone is UI, unless it drops or renames a field the model has. That's a question, because the page no longer shows something the read model provides.
- A rule added only in Elm's `update` is flagged as "not enforced on the server", not proposed as a scenario.

## The prompt

The builder sends this, followed by the input JSON:

```text
You keep an app's event model true to its codebase. Code changed outside the model builder; find what the model no longer describes and propose updates. Propose, never impose: additions and clarifications become model changes a person approves; anything that breaks stored history or contradicts an approved spec becomes a question for the team, never a silent update.
{{EVENT_MODELING_RULES}}
The facts were computed in code (changes linked to slices, event before/after, new error returns, test title matches, migrations): rely on them.
Look for: (1) new commands, events, read models, rules (validations, error returns, aggregate checks) and screen behaviour the model lacks; new rules become error scenarios using the code's own message and condition; (2) changed fields, rules and names: fields added to commands or read models are proposed; fields added to events only if optional; changed rules update their scenario, quoting before and after; renamed modules update code links only; (3) stored events edited in place are urgent and go to the event-change skill; code contradicting an approved spec and removed behaviour become questions; (4) new tests that read as business rules become scenarios; renamed tests keep scenario and test matched. Skip refactors, formatting, helpers, logging and performance.
Every change names the commit it came from and gives a reason a teammate understands.
Reply with ONLY one JSON object, no other text:
{"changes":[{"op":"add_slice"|"add_scenario"|"update_scenario"|"set_fields"|"link_code"|"mark_possibly_removed","target":string,"from":any,"to":any,"commit":string,"reason":string}],
 "questions":[{"slice":string,"el":string,"text":string (quote the spec and the code),"options":[string],"commit":string}],
 "urgent":[{"event":string,"commit":string,"what":string,"risk":string,"handoff":"change-stored-event-safely"}],
 "ignored":[{"commit":string,"why":string}],
 "summary":string (2-3 sentences: what drifted, what's proposed, what needs a decision)}
```

## Example: a hotfix outside the builder

The input is PR #241 by Tomi, "Hotfix: block booking within 1 hour of start". It adds a validation returning "Too late to book" when `starts_at` is less than an hour away, and a test called "too late to book".

```json
{"summary": "One hotfix added a booking rule the model didn't have; it's proposed as a new scenario on Book office hours. Book office hours had an approved spec, so the new rule also needs a quick re-approval.",
 "changes": [
  {"op": "add_scenario", "target": "slice:book-office-hours", "from": null,
   "to": {"kind": "error", "title": "Too late to book", "given": ["OfficeHoursSlotOpened(slotId: s-1, startsAt: in 30 minutes)"], "when": "BookOfficeHours(slotId: s-1, studentId: u-2)", "then": ["error: too late to book"]},
   "commit": "a1b2c3d", "reason": "PR #241 added a rule that blocks booking within an hour of the start; its test is named 'too late to book'."}],
 "questions": [
  {"slice": "book-office-hours", "el": "slice", "text": "The approved spec for Book office hours didn't have the 1-hour cut-off that PR #241 added. Keep the rule and re-approve the spec, or revert it?", "options": ["Keep the rule, re-approve", "Revert PR #241"], "commit": "a1b2c3d"}],
 "urgent": [], "ignored": []}
```

## Example: a stored event edited in place

```json
{"urgent": [{"event": "OfficeHoursBooked", "commit": "f9e8d7c",
  "what": "student_id was renamed to member_id directly on the event module.",
  "risk": "18,240 stored OfficeHoursBooked events have student_id. Once this deploys, aggregates and projections that read them get member_id = nil, so double-booking checks and Live sessions will be wrong.",
  "handoff": "change-stored-event-safely"}]}
```

## What the builder does with the reply

- **Proposed changes:** go to repair-and-merge as a `code` version, so they appear as one diff with commit links. People approve or untick each one. Nothing changes until someone approves.
- **Urgent items:**
  - a red banner on the board and the Build page;
  - a notification to the project's admins and the slice owner;
  - a **Plan a fix** button that runs the event-change skill.
- **Questions:** posted to each slice's Discussion with the options as buttons, with the commit linked.
- **Approved specs touched by a change** go back to "In review" with a note, so the business re-approves what the code now does.
- **Activity:** each sync posts one line to the project's Activity ("Synced with main: 1 rule added, 1 question"). Slices with unresolved drift show a "Code differs" chip.
- **Next sync:** `lastSync` moves forward only after every proposed change is approved or rejected, so nothing is missed.

## Done means
- Every behavioural change merged since the last sync is a proposed change, a question, an urgent item, or ignored with a reason.
- No model change is applied without a person approving it.
- Edits to stored events are raised as urgent and handed to the event-change skill, never applied to the model.
- Approved specs the code no longer matches are reopened for review.
- Each change links to the commit it came from.
