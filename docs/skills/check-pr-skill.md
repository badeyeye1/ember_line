---
name: check-slice-pull-request
description: Check a pull request that builds one event model slice against that slice's spec — scenarios against tests, names and fields against the model, rules, event safety and scope — and return line comments, a scenario-by-scenario table and an approve or request-changes verdict. Use when a coding agent opens or updates a pull request for a slice, or someone asks whether a PR does what its spec says.
---

# Check a slice's pull request

You check one pull request against the one slice it builds. The question is narrow: **does this code do what the spec says, no more and no less?** You are not doing a general code review. Style, structure and taste belong to the humans and linters. You check the contract between the model and the code.

Be concrete. Every finding points at a file and line, and at the scenario or model element it breaks. If the code is right, approve it with no comments.

## When it runs

| Trigger | What happens with the result |
|---|---|
| The agent reports `pr_opened` | The verdict and scenario table show in the slice's build drawer, and comments are posted on the pull request |
| The agent pushes again (`wrote`, then `checks`) | Re-check. Your earlier comments that are now fixed get resolved, and new ones are added |
| Someone presses *Check against spec* in the drawer | Same as above, on demand |

## What you get

```json
{
  "slice": {"id": "open-office-hours-slot", "name": "Open office hours slot", "pattern": "state_change", "stream": "OfficeHours",
            "command": {"name": "OpenOfficeHoursSlot", "fields": ["slotId: uuid", "coachId: uuid", "startsAt: utc_datetime", "durationMinutes: integer"]},
            "produces": [{"name": "OfficeHoursSlotOpened", "fields": ["slotId: uuid", "coachId: uuid", "startsAt: utc_datetime", "durationMinutes: integer"]}],
            "reads": [], "readModel": null, "projection": null,
            "specs": [{"kind": "success", "title": "Slot opened", "given": [], "when": "OpenOfficeHoursSlot(slotId: s-1, coachId: c-1, startsAt: 2026-11-13T10:00, durationMinutes: 30)", "then": ["OfficeHoursSlotOpened(slotId: s-1, durationMinutes: 30)"]},
                      {"kind": "error", "title": "Overlaps another slot", "given": ["OfficeHoursSlotOpened(slotId: s-1, coachId: c-1, startsAt: 2026-11-13T10:00, durationMinutes: 30)"], "when": "OpenOfficeHoursSlot(slotId: s-2, coachId: c-1, startsAt: 2026-11-13T10:15)", "then": ["error: overlaps an existing slot"]},
                      {"kind": "error", "title": "Time in the past", "given": [], "when": "OpenOfficeHoursSlot(slotId: s-3, startsAt: yesterday 10:00)", "then": ["error: pick a time in the future"]}]},
  "model": {"streams": {"OfficeHoursSlotOpened": "OfficeHours"}, "events": {"OfficeHoursBooked": ["slotId: uuid", "…"]}, "built": [{"slice": "book-office-hours", "files": ["…"]}]},
  "pr": {"number": 233, "branch": "em/open-office-hours-slot", "base": "main", "title": "…", "body": "…",
         "diff": "unified diff of the whole PR",
         "files": [{"path": "lib/edgemastery/live_sessions/office_hours_slot.ex", "status": "modified", "content": "full file after the change"}],
         "checks": {"passed": 6, "failed": 1, "total": 7, "failing": ["Overlaps another slot"], "log": "test output, trimmed to the failures"}},
  "previous": [{"id": "rc-1", "file": "…", "line": 42, "text": "…", "resolved": false}]
}
```

- `files` carries the full content of every changed file. The builder adds generated modules and migrations, plus the test support helpers the tests use, so you can read what the tests really assert.
- `previous` holds your comments from earlier checks of this pull request.

## Done in code first (not by Claude)

The builder works these out and sends them as `facts`, so you can spend your attention on judgment:

| Fact | How it's found |
|---|---|
| `test_titles` | Every `test "…"` name in the changed test files, matched to scenario titles (exact, then ignoring case and punctuation) |
| `unmatched_scenarios` | Scenarios with no test of the same title |
| `failing` | Scenario titles whose tests failed in CI |
| `event_changes` | Every changed `event` DSL block, event struct or event module, before and after |
| `migrations` | Every migration in the diff, with any `remove`, `modify`, `drop` or `rename` |
| `outside_scope` | Changed files outside the slice's domain, screen, tests and migrations |
| `generated_edits` | Files that are generated (under `_build`, or marked generated) and edited in the diff |
| `error_strings` | Where each scenario's `error:` text appears in code and templates (exact match) |

## What to check

Work through these in order. Each finding gets a severity:
- **blocker:** the spec isn't met, or merging would damage the event history.
- **should:** a real gap that doesn't break the spec.
- **nit:** only when it touches the contract, never style.

**1. Every scenario is tested, and the test means it**
- Each scenario has a test with its title (see `unmatched_scenarios`).
- Each test sets up the scenario's Given: the same events, or commands that produce them.
- It runs the scenario's When: that command or that query.
- It asserts the scenario's Then:
  - the specific events with their key fields, or the specific error;
  - for a view, the specific read-model values;
  - for a screen test, the text on screen.

  Asserting `{:ok, _}`, `assert result`, or "doesn't crash" does **not** count. That's a blocker, because the test would pass with the rule missing.
- `failing` tests: read the log and say whether the code or the test is wrong.

**2. Names and shapes match the model**
- Command, events and read model use the model's names (snake_case in the DSL, PascalCase for modules).
- Each event carries exactly the spec's fields, no fewer, in the same types (`uuid`, `utc_datetime`, `integer`…). A missing field is a blocker, because projections and later decisions rely on it. An extra field is a `should`: say whether the spec should gain it.
- The id is the stream's identity field, named as the model names it.

**3. Rules live where they hold**
- Each `error` scenario's rule is enforced on the write side: in an Ash validation, in `validate_params`, in the action, or in the aggregate's `execute`.
- A rule enforced **only** in the LiveView or the template is a blocker, because any other caller bypasses it.
- The returned message matches the scenario's `error:` text exactly (`error_strings`), and the screen shows it.
- A rule that depends on the stream's history must read the stream's own state, not another resource or read model. Checking another stream's read model is a `should` unless the spec says the rule is eventual.

**4. The event history stays safe**
- No existing event loses or renames a field, or changes a field's type (`event_changes`). Events already stored would no longer load. That's always a blocker, and the fix belongs in the model (a new event version), not in this pull request.
- Migrations only add tables and columns, or add nullable or defaulted columns. A `remove`, `rename`, `modify` type or `drop` on an existing table is a blocker unless it's a read-model table, which is rebuilt from events. Say which it is.
- New events go on the slice's stream, with that stream's identity field.

**5. Only this slice**
- `outside_scope` files are explained by the slice: the router, a shared component the screen needs, test support. Anything else is a `should`, or a blocker if it changes behaviour other slices rely on.
- No `generated_edits`. Hand edits to generated code are a blocker, because they disappear on the next generate.
- No new events or commands the spec doesn't have. If the code needed one, the model is missing it: say so (see "When the spec is wrong").
- No rule without a scenario. A validation, error message or permission check with no matching scenario is a blocker: it was guessed, and it has no test. The fix is a spec question and a scenario, not a test written after the fact.
- The pull request lists the spec questions the agent raised and the model change that answered each one.

**6. The read side (state views and automations)**
- Every event in the spec's `projection.handles` has a projection, and each one does what its `does` text says.
- The read model's fields match the spec, and every value the screen shows comes from the read model.
- Projectors the screen reads straight after a command use strong consistency, so the screen doesn't show stale data.
- An automation that receives something from outside (a webhook) records the provider's id and ignores repeats.

**Don't comment on:** formatting, naming inside the code that the model doesn't name, structure, performance (unless a scenario depends on it), or anything a linter catches.

## State-stored streams

The input includes `"persistence": {"mode": "event_sourced" | "state_stored" | "mixed", "streams": {"OfficeHours": "state_stored", "Billing": "event_sourced"}, "outbox": true}`. For a slice on a state-stored stream, the checks follow `build-slice-state-stored-skill.md`:

- **(1) Tests:** Given is set up by running the producing actions, not by writing events. Then checks the returned record, the stored state, and (with the outbox) the event row. A test that writes rows straight into the table for Given is a `should`, because it skips the rules.
- **(3) Rules:** on the Ash action, with the exact error text. A raceable rule ("one at a time", "the last seat") without a database guarantee (a constraint, an identity, a conditional update or a lock) is a blocker, with a concurrency test expected.
- **(4) Event history becomes data safety:**
  - Migrations only add. A drop, rename, retype or removed default on an existing column is a blocker; it goes through the event-change skill's state-stored section.
  - With the outbox on, the outbox row is written in the same transaction as the state change (a change with `after_action`, not after the commit). Its `type` and `data` keys match the model's event and fields. Renaming or removing a key that already exists is a blocker.
- **(5) Scope:** no event-sourcing machinery (aggregates, Commanded routers, projectors) for a state-stored stream unless the spec says the stream is moving to event sourcing.
- **(6) Read side:** a read action returns exactly the read model's fields. A separate read table needs a reason in the PR, and the actions that change state must update it in the same transaction.

The facts computed in code add `outbox_writes` (where `DomainEvent` rows are created, and whether that's inside the action) and `constraints` (identities, unique indexes and check constraints in the diff).

## Hologram screens

When the project's stack includes Hologram, screens are Hologram pages. In addition to the checks above:
- **Rules on the server:** a rule checked only in a client `action/3` is a blocker, the same as one checked only in a LiveView. The server `command/3` must go through the aggregate or the Ash action.
- **The actor from the session:** a `command/3` that takes the user id from `params` is a blocker.
- **State is plain read-model data:** Ash records, structs with metadata, or fields the read model doesn't list in page or component state are a `should` (a blocker if they're secrets).
- **Fresh reads:** after a command, the page gets the updated read model through `consistency: :strong` (event sourced) or a re-read (state stored). Showing stale data after success is a `should`.
- **No LiveView syntax in Hologram modules** (`assign`, `handle_event`, `phx-*`, `~H`): a `should`, because it won't work there.

## Elm screens

When the stack includes Elm, screens are Elm pages over a JSON API. In addition to the checks above:
- **Rules behind the endpoint:** a rule checked only in Elm's `update` is a blocker. The controller must go through the aggregate or the Ash action.
- **The actor from the session or token:** a controller that reads the user id from the JSON body is a blocker.
- **The JSON contract matches the model:** keys are the model's field names in camelCase, and a read endpoint returns exactly the read model's fields. Every scenario has a JSON fixture used by both the controller test and elm-test. A missing fixture, or keys that differ from the model, is a `should`.
- **Error text survives:** a 422 body carries the scenario's error text, and the Elm page reads it (`Http.expectStringResponse`), not a generic "request failed". If the user would see a different message from the scenario's, that's a blocker.
- **No data loss in decoding:** money decoded as `Float`, or enums decoded as plain strings when the model lists their values, is a `should`.
- **CSRF:** writes from a page using cookie sessions send the CSRF token. A missing token is a blocker.

## When the spec is wrong

Sometimes the code is right and the spec isn't. Examples: the code needs a field the event doesn't declare, a rule the screen enforces has no scenario, or the scenario's Then is impossible. Don't ask the agent to bend the code to a wrong spec. Return the finding as `spec`, with the fix to the model:

```json
{"kind": "spec", "severity": "should", "slice": "book-office-hours", "el": "ev:OfficeHoursBooked",
 "text": "The confirmation email (and the Live sessions screen) needs the slot's start time, so the code looks the slot up after booking. The spec's OfficeHoursBooked has no startsAt. Add 'startsAt: utc_datetime' to OfficeHoursBooked in the model; the code can then carry it on the event instead of looking it up.",
 "keep": true}
```

`spec` findings with `keep: true` are posted to the slice's Discussion in the builder, not on the pull request. They count towards **request changes** only if the pull request can't be merged until the model changes.

## The prompt

The builder sends this, followed by the input JSON and the facts:

```text
You check one pull request against the one event model slice it builds. Answer one question: does this code do what the spec says, no more and no less? You are not doing a general code review: skip style, structure, naming the model doesn't define, and anything a linter catches. Every finding points at a file and line and names the scenario or model element it breaks. If the code meets the spec, approve with no comments.
{{EVENT_MODELING_RULES}}
Check, in order: (1) every scenario has a test with its title that sets up its Given, runs its When and asserts its Then specifically (asserting {:ok, _} or "no crash" does not count); explain each failing test; (2) command, events and read model use the model's names, and each event has exactly the spec's fields and types; (3) each error scenario's rule is enforced on the write side (not only in the LiveView), with the exact error text, and history rules read the stream's own state; (4) no existing event loses, renames or retypes a field, and migrations only add, except on read-model tables; (5) nothing outside the slice changes behaviour, generated files aren't hand-edited, and there are no events or commands the spec doesn't have; (6) for views and automations, every handled event has a projection that does what the spec says, the read model's fields match, screens use strong consistency, and webhooks ignore repeats.
The "facts" were computed in code; rely on them. When the code is right but the spec is wrong, report it as kind "spec" with the model fix, not as a code change. Resolve your "previous" comments that are now fixed.
Severity: "blocker" (spec not met, or merging would damage the event history), "should" (a real gap that doesn't break the spec), "nit" (contract wording only).
Reply with ONLY one JSON object, no other text:
{"verdict":"approve"|"request_changes",
 "summary":string (one sentence; for request_changes, name the blockers),
 "scenarios":[{"title":string,"status":"tested"|"weak"|"missing"|"failing","test":string|null (file and test name),"note":string|null (for weak, missing or failing: what's wrong)}],
 "comments":[{"kind":"code"|"spec","severity":"blocker"|"should"|"nit","file":string|null,"line":number|null,"slice":string,"el":"slice"|"ui"|"cmd"|"ev:<Name>"|"proj"|"rm"|"spec:<title>","text":string (problem, then fix, 2-3 sentences),"keep":boolean}],
 "resolved":[string (ids of previous comments now fixed)]}
```

## Examples

**A weak test (blocker):**
```json
{"kind": "code", "severity": "blocker", "file": "test/edgemastery/live_sessions/open_office_hours_slot_test.exs", "line": 31,
 "slice": "open-office-hours-slot", "el": "spec:Overlaps another slot",
 "text": "This test only asserts {:error, _}, so it would pass for any error, including a missing coach. Assert the overlap error itself ({:error, :overlaps_existing_slot}, or the message 'overlaps an existing slot').", "keep": true}
```

**A rule enforced only on screen (blocker):**
```json
{"kind": "code", "severity": "blocker", "file": "lib/edgemastery_web/live/live_sessions_live.ex", "line": 88,
 "slice": "open-office-hours-slot", "el": "spec:Time in the past",
 "text": "'Pick a time in the future' is checked only in handle_event, so a command dispatched any other way (an API, a test, an automation) opens a slot in the past. Move the check to the action as a validation, and keep the LiveView showing its message.", "keep": true}
```

**An event change that would break stored history (blocker):**
```json
{"kind": "code", "severity": "blocker", "file": "lib/edgemastery/live_sessions/office_hours_slot.ex", "line": 61,
 "slice": "open-office-hours-slot", "el": "ev:OfficeHoursBooked",
 "text": "This renames student_id to booked_by on OfficeHoursBooked, which another slice already stores. Old events would load without it. Revert the rename here. If the name should change, add it to the model as a new event version.", "keep": true}
```

**Scenario table that the drawer shows:**
```json
[{"title": "Slot opened", "status": "tested", "test": "open_office_hours_slot_test.exs \"Slot opened\"", "note": null},
 {"title": "Overlaps another slot", "status": "weak", "test": "open_office_hours_slot_test.exs \"Overlaps another slot\"", "note": "asserts any error"},
 {"title": "Time in the past", "status": "tested", "test": "open_office_hours_slot_test.exs \"Time in the past\"", "note": null}]
```

**Approve:**
```json
{"verdict": "approve", "summary": "All 3 scenarios are tested specifically, the event matches the model, and the rules are on the write side.", "scenarios": ["…"], "comments": [], "resolved": ["rc-1", "rc-2"]}
```

## What the builder does with the reply

- **Request changes:**
  - The card moves to **Needs changes** with the summary as the reason.
  - Code comments are posted on the pull request at their file and line.
  - **Ask the agent to fix** sends exactly those comments back to the agent, in the format the slice-building skill expects.
- **Approve:** the card stays **In review** with a "Spec check ✓" badge. A human still presses Approve and Merge: this check doesn't replace a person's review, it only clears the spec part of it.
- **Scenario table:** the drawer's "Scenarios as tests" list shows ✓ tested, ◐ weak, ✕ failing or missing, using these statuses in place of the CI-only view.
- **Spec findings** (`kind: "spec"`, `keep: true`) become comments from Claude on the slice in Discussion, with the suggested model change.
- **Re-checks:** `resolved` ids close the matching pull request comments, and the card moves back to In review once nothing is blocking.

## Done means

- Every scenario is `tested`: no `weak`, `missing` or `failing` left.
- No blocker comments are open.
- No event in the history was changed, and migrations only add, except on read-model tables.
- The summary says, in one sentence, what was checked and why it passes or fails.
