---
name: repair-merge-event-model
description: Merge two or more versions of an event model (from a prototype, a codebase, an import or board edits) into one consistent model, repair what drifted (wiped fields, sample leftovers, duplicate outcomes, orphan events, naming drift) and rename across the model, returning every change with its reason and source. Use after a re-derive, when combining prototype- and code-derived models, when importing a model into an existing project, or when someone asks to clean up or rename things in a model.
---

# Repair and merge event models

A project's model comes from several places that drift apart over time:
- deriving from the prototype, possibly more than once;
- reading the codebase;
- importing a JSON file;
- people editing the board.

This skill turns two or more versions into **one consistent model**, and says exactly what it changed and why.

**Nothing changes silently.** Every change is listed with its reason and the version it came from, so the builder can show it as a diff and undo any change. Where the right answer is a judgment call, it becomes a question for the team instead of a guess.

## When it runs

| Trigger | Versions it gets | Result |
|---|---|---|
| A re-derive finishes | `current` (the board) and `derived` (the new outline and details) | Replaces today's merge code. The diff is shown before it's applied |
| *Read the codebase* on a project that already has a model | `current` and `code` | Slices that exist in code are linked to their files and get a status |
| *Import JSON* into a project that has a model | `current` and `imported` | Choose: merge, or replace |
| *Repair model* on the board | `current`, plus earlier `history` snapshots when there are any | Repairs only, no merging |
| *Rename* on any sticky, field or stream | `current` and a `rename` request | A rename across the whole model |

## What you get

```json
{
  "versions": [
    {"id": "current", "source": "board", "at": "2026-11-17T09:12:00Z", "model": {"app": {}, "screens": [], "streams": {}, "outcomes": [], "slices": []}},
    {"id": "derived", "source": "prototype", "at": "2026-11-17T09:40:00Z", "model": {}},
    {"id": "code", "source": "codebase", "at": "2026-11-15T16:03:00Z", "model": {}},
    {"id": "v-2026-11-08", "source": "history", "at": "2026-11-08T18:20:00Z", "model": {}}
  ],
  "base": "current",
  "built": [{"slice": "book-office-hours", "events": ["OfficeHoursBooked"], "merged": true}],
  "sample": {"slice_ids": ["schedule-workshop", "…"], "events": ["WorkshopScheduled", "…"], "outcomes": ["Members secure a seat"]},
  "rename": null,
  "checks": [{"rule": "orphan_event", "where": "PaymentFailed", "detail": "read by 9 slices, produced by none"}],
  "decisions": [{"question": "q-3", "answer": "Treat RsvpConfirmed and SeatReserved as one event: RsvpConfirmed"}]
}
```

- **`base`** is the version people work in. Its ids, order and human edits win unless a rule below says otherwise.
- **`built`** lists events already merged into code. They're stored in the event store, so they can't be renamed or have fields removed.
- **`sample`** is the template content that must never appear in a real project.
- **`decisions`** are answers to questions this skill asked on an earlier run. Apply them; don't ask again.

## Done in code first (not by Claude)

Most of the work is mechanical. The builder does it before calling Claude, and passes the results in as a draft `plan`:

| Step | Rule |
|---|---|
| Match slices | Same id, then the same name ignoring case and punctuation, then the same command name, then the same read-model name on the same screen |
| Strip sample content | Drop slices whose id and name both match the sample (and that have no code links), plus their outcomes. Drop reads of sample events nothing else produces |
| One field list per event | The union of every field list the event appears with, producers' fields first, then readers' |
| Fill empty fields | From earlier versions with the same name, else from the `name: value` pairs in scenarios, with types from the values |
| Dangling references | Drop streams for events that no longer exist, outcome links to missing slices, and outcomes whose slices all belong to earlier outcomes |
| Orphans | List events read but never produced |

Your job is everything that needs judgment:
- matching slices that have different names but the same behaviour;
- choosing between conflicting values;
- reconciling the prototype with the code;
- giving orphan events a sensible source;
- spotting two events that are really one fact;
- carrying out renames safely;
- writing the reason for each change.

## Rules

**1. Who wins, field by field**

| What | Winner |
|---|---|
| Slice id, order, name | `base`. A person may have renamed or reordered it |
| Status, owner, review, comments | `base`. Never reset by a merge |
| Code links (`code`), and Done status for slices that exist in code | `code` |
| Fields | The most complete list, then made into one list per event. Never shrink a list `base` already has |
| Scenarios | Keep every scenario `base` has. Add new ones from other versions only if no scenario with the same title and kind exists. Never delete one |
| Story, ui element, projection | `base` if set, else the newest version that has one |
| Screens and their reach steps | The newest prototype-derived version |
| Outcomes | The newest derive's outcomes replace older ones. An older outcome survives only for slices no newer outcome covers, and a person's own edits to outcomes in `base` win |

**2. Matching slices that don't share a name**
- Treat two slices as the same behaviour when they have the same pattern, on the same screen or the screen of the same route, and either the same event under different names or the same command fields.
- Merge them under `base`'s names, and record `merged_slice` with both ids.
- When you aren't sure, ask (see "Questions") instead of merging.

**3. Reconciling the prototype with the code**
- **Code has it, prototype doesn't:** keep it, because it's built. Put it on its screen, or on "No screen yet".
- **Prototype has it, code doesn't:** keep it as Planned.
- **Both have it, with different names:** use the code's name when that event is in `built`, because it's stored. Otherwise use `base`'s name. Record the rename.
- **Both have it, and they disagree on a rule or a field:** don't pick. Ask, quoting both.

**4. Repairs**
- **Orphan events:**
  - if a slice in any version produces the event, restore that slice;
  - if it comes from outside the app (a webhook, an email, a scheduler, a device), add an automation slice that receives it;
  - if it's a user action the model is missing, add a state change slice on the screen where the prototype shows that action;
  - if it's a sample event, or a typo of another event, unhook it, or point the reads at the real event.
- **Identity names:** each stream gets one id name, from the stream's name (`Account` → `accountId`). Rename that field in every event, command and read model that refers to the stream, and in scenario text, unless the field belongs to a built event.
- **Duplicate facts:** two events that record the same business fact (same stream, overlapping fields, produced by the same kind of action) are a question, not an automatic merge.

**5. Renames**
- **What a rename updates:** every reference, including commands, events, read models, projections and their handles, streams, outcome slice lists, scenario text (`Name(` and `field:` tokens only, never inside quoted words), comment targets, Build work items, and `code` links (where they're names, not paths).
- **Built events can't be renamed.** They're stored, and a renamed module would no longer load old events. Refuse the rename with the reason, and offer the alternative: a new event (for example `CustomerRegisteredV2`), with an upcaster noted for the agent.
- **Field renames on built events** are refused the same way.
- **A name collision** is refused, or becomes a question when the target is an existing different thing.

**6. Never**
- Never delete a scenario, comment, review or code link without listing it as a `remove` change with a reason.
- Never change a built event's name or fields.
- Never carry sample content into a real project.
- Never invent rules or scenarios. Repairs may add slices to give events a source, with scenarios derived from facts already in the model, and nothing more.

## Storage setting per stream

The model carries the project's storage setting (`event_sourced`, `state_stored` or `mixed`, with a per-stream map).
- **Who wins:** a setting someone chose (`set: true`) wins. Otherwise the `code` version's detected style wins for streams that exist in code. New streams take the project's default.
- **A stream whose code style changed** (it was CRUD and now has an aggregate, or the other way round) is a question, not an automatic switch.
- **Renames on state-stored streams:** a model name with no stored history can be renamed freely, unless the outbox is on and that event type already has rows or listeners. Then it's treated like a built event: refused, with a new event type proposed through the event-change skill.

## Questions

When a choice is a judgment call, don't make it. Return a question, and leave that part of the model as `base` has it:

```json
{"id": "q-3", "slice": "rsvp-to-workshop", "el": "ev:SeatReserved",
 "text": "RsvpConfirmed (from the prototype) and SeatReserved (from the code) are both produced when a member takes a seat on the same workshop, with nearly the same fields. Are they the same fact?",
 "options": ["Same fact: keep RsvpConfirmed", "Same fact: keep SeatReserved (it's built)", "Different facts: keep both"]}
```

The builder posts each question in that slice's Discussion, with the options as buttons. The answer comes back in `decisions` on the next run.

## The prompt

The builder sends this, followed by the input JSON and the draft plan:

```text
You merge and repair versions of one app's event model into a single consistent model, as a careful engineer who owns its history. Every change you make is listed with its reason and the version it came from; nothing changes silently. When the right answer is a judgment call, ask a question instead of choosing.
{{EVENT_MODELING_RULES}}
The draft "plan" was computed in code (slice matches, sample stripping, one field list per event, empty fields filled, dangling references dropped, orphans listed): accept it, correct it where it is wrong, and add what needs judgment: matching slices with different names but the same behaviour, choosing between conflicting values, reconciling prototype and code, giving orphan events a sensible source, spotting duplicate facts, carrying out renames, writing reasons.
Who wins: base keeps ids, order, names, status, owners, reviews and comments; code wins for code links and Done status; fields take the most complete list and never shrink; keep every scenario base has and add new ones only if no scenario with that title and kind exists; the newest derive's screens and outcomes replace older ones, except outcomes a person edited.
Never rename or remove fields of an event listed in "built"; refuse and propose a new event version instead. Never carry sample content into the project. Never delete a scenario, comment, review or code link without a "remove" change and a reason. Never invent rules; new slices only give orphan events a source, with scenarios from facts already in the model.
Apply "decisions" from earlier runs. {{RENAME_RULES}}
Reply with ONLY one JSON object, no other text:
{"model":{app, screens, streams, outcomes, slices} (the full merged model, in the same shape as the input),
 "changes":[{"op":"merge_slice"|"add_slice"|"remove"|"rename"|"set_fields"|"add_scenario"|"move_outcome"|"set_status"|"link_code"|"unhook"|"set_stream",
   "target":string (e.g. "slice:book-office-hours", "ev:OfficeHoursBooked", "field:Account.customerId", "outcome:members-secure-a-seat"),
   "from":any,"to":any,"source":string (version id),"reason":string (one sentence a teammate understands)}],
 "questions":[{"id":string,"slice":string,"el":string,"text":string,"options":[string]}],
 "refused":[{"request":string,"reason":string,"alternative":string}],
 "summary":string (one or two sentences: what was merged, repaired and still open)}
```

`{{RENAME_RULES}}` is only added for a rename:

```text
Rename request: {{from}} → {{to}} ({{kind: event|command|read_model|stream|field|slice}}). Update every reference: commands, events, read models, projections and handles, streams, outcome slice lists, scenario text (only Name( and field: tokens), comment targets, Build work items and code names. Refuse if the event is built, or if the new name collides with something different.
```

## Example: the Edgemastery repair

Run with `current` (135 slices, fields wiped by a re-derive) and `history` (the earlier 139-slice version):

```json
{"summary": "Restored field lists for 85 commands, 85 events and 48 read models from the 8 Nov version, removed 8 workshop slices left over from the sample and 10 duplicate outcomes, and gave PaymentFailed and ReplaySessionPlayed a source. One question is open: whether customerId should become accountId everywhere.",
 "changes": [
  {"op": "set_fields", "target": "cmd:CreateAccount", "from": [], "to": ["customerId: uuid", "name: string", "email: string", "…"], "source": "v-2026-11-08", "reason": "The re-derive outlined names only; the 8 Nov version has this command's fields."},
  {"op": "remove", "target": "slice:schedule-workshop", "from": "Schedule workshop", "to": null, "source": "sample", "reason": "Sample content; the Edgemastery prototype never mentions workshops."},
  {"op": "remove", "target": "outcome:visitors-become-signed-in-customers", "from": "Visitors become signed-in customers", "to": null, "source": "current", "reason": "Every slice in it already belongs to 'Visitors become signed-in members' from the newer derive."},
  {"op": "add_slice", "target": "slice:receive-payment-failed", "from": null, "to": "Receive failed payment (automation)", "source": "repair", "reason": "PaymentFailed was read by 9 slices and produced by none; it comes from the payment provider's webhook."},
  {"op": "add_slice", "target": "slice:finish-replay-session", "from": null, "to": "Finish replay session", "source": "repair", "reason": "ReplaySessionPlayed was read but never produced; the replay screen's Finish button records it."}],
 "questions": [
  {"id": "q-1", "slice": "create-account", "el": "cmd", "text": "Customers in this app are accounts (personal or academy), and the stream is Account, but 343 fields and scenario lines say customerId. Rename customerId to accountId everywhere?", "options": ["Rename to accountId", "Keep customerId"]}],
 "refused": []}
```

## Example: a refused rename

```json
{"refused": [{"request": "rename event OfficeHoursBooked → OfficeHoursReserved",
  "reason": "OfficeHoursBooked is merged into code and stored in the event store; existing events would no longer load under the new name.",
  "alternative": "Keep OfficeHoursBooked, or add OfficeHoursReserved as a new event and have the agent write an upcaster from the old one. Say which, and I'll update the model."}]}
```

## What the builder does with the reply

- **Shows the diff first.** It lists the changes grouped by kind (merged, renamed, restored, added, removed), each with its reason and source. You can untick any change before applying.
- **Applies the result as one step** that can be undone, and logs it in the project's Activity ("Claude repaired the model: …").
- **Posts each question** to its slice's Discussion with the options as buttons. Answers feed the next run as `decisions`.
- **Shows refused requests** with their alternative, and a button to apply it.
- **Re-runs the spec reviewer's code checks** afterwards, so anything still wrong shows on the board.

## Done means
- One model, with nothing lost that any version had, unless it's listed as a `remove` with a reason.
- Every event has one field list, every event that's read has a source, and every id name follows its stream (or there's an open question about it).
- No sample content, no dangling streams or outcome links, and no duplicate outcomes.
- No built event was renamed or lost a field.
- Every change has a reason a teammate understands.
