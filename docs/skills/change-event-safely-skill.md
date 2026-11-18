---
name: change-stored-event-safely
description: Plan and hand off a safe change to an event that's already stored — or, for state-stored streams, to a table column or a published outbox event — — rename, add, remove or retype a field, split or merge events — choosing between an additive change, a new event version with an upcaster, or a new event, and covering every projection, read model rebuild, scenario, automation and rollout step. Use when someone needs to change a built event, or when the spec reviewer, PR checker or repair skill refuses a change to stored history.
---

# Change a stored event safely

Events are the history of the app. Once an event is stored, it stays exactly as it was written. Code that reads it later (aggregates rebuilding their state, projections rebuilding read models, automations replaying) must still understand every version ever written.

So a built event can't simply be renamed or reshaped. Three skills refuse those changes and point here:
- the **spec reviewer** flags them;
- the **PR checker** blocks them;
- **repair-and-merge** refuses them.

This skill turns the requested change into a plan that keeps old history loadable, and hands the work to the coding agent.

## What you get

```json
{
  "event": {"name": "OfficeHoursBooked", "stream": "OfficeHours", "fields": ["slotId: uuid", "studentId: uuid", "coachId: uuid", "bookedAt: utc_datetime"],
            "module": "Edgemastery.Events.OfficeHoursBooked", "versions": [], "stored": {"count": 18240, "first": "2026-03-02", "last": "2026-11-17"}},
  "change": {"kind": "rename_field", "from": "studentId", "to": "memberId", "why": "Academies now book office hours for coaches-in-training, not only students."},
  "producers": [{"slice": "book-office-hours", "command": "BookOfficeHours"}],
  "readers": [
    {"slice": "live-sessions", "kind": "projection", "readModel": "LiveSessions", "handles": "mark the slot taken; set myBooking"},
    {"slice": "office-hours-reminder", "kind": "automation", "does": "email the student 1 h before"},
    {"slice": "book-office-hours", "kind": "aggregate", "does": "one booking at a time"}],
  "scenarios": [{"slice": "book-office-hours", "title": "Already taken", "uses": ["OfficeHoursBooked(slotId: s-1, studentId: u-3)"]}],
  "stack": "Elixir: Phoenix LiveView + Ash + AshCommanded",
  "deploy": {"rolling": true, "readModelRebuildMinutes": 4}
}
```

The builder fills in `stored` from the event store when it can reach it. When it can't, plan as if the history is large and old.

## The kinds of change, and the default approach

| Change | Default approach | Why |
|---|---|---|
| **Add a field** that can be missing in old events | **Additive.** Same event, new optional field | Old events load with `nil`. Readers must handle `nil` |
| **Add a required field** | **Additive with an upcaster** that sets it on old events, if history can supply it (a default or a derived value). Otherwise a **new version** | Never pretend old events had a value they didn't |
| **Rename a field** | **New version** plus an upcaster that copies the old field to the new name | Old events keep the old key forever |
| **Remove a field** | **Stop reading it.** Keep it on the event, deprecated and no longer written | Removing it gains nothing, and old events still have it |
| **Change a field's type** | **New version** plus an upcaster that converts. If the conversion can lose data, ask first | `integer` → `decimal` is safe. `string` → `enum` may not be |
| **Rename the event** | **New event version** under the new name. The old module stays, and upcasts to the new one | Stored events name their module, so the old module must still exist |
| **Split one event into two** | **New events going forward.** Old events either upcast to the main new one, or readers keep handling the old event | Upcasting one stored event into two is usually wrong: history had one fact |
| **Merge two events into one** | **New event going forward.** Both old ones upcast to it | Only when they really were the same fact (repair-and-merge asks) |
| **Change what the event means** | **New event.** The old one stays as history, and readers handle both | Upcasting would rewrite the past |

**Upcasters never invent facts.** When old events can't supply a value the new shape needs, the field stays optional in the new version, or the change becomes a new event from now on. Say which, and why.

## What the plan covers

1. **Approach:** additive, new version or new event, with the reason in one sentence.
2. **The model change:** the new or changed event, its fields and stream, and the old version marked `deprecated: true` but kept. This goes to repair-and-merge as a diff.
3. **Upcaster:** old shape to new shape, field by field, with what happens to each old event.
4. **Producers:** commands that should write the new version from now on.
5. **Readers**, each checked:
   - **projections:** update, then rebuild the read model;
   - **aggregates:** their `apply/2` must handle the new version, and decisions must work across a history that mixes both;
   - **automations:** decide whether they handle both versions, and make sure they don't act again when history is replayed during a rebuild.
6. **Scenarios:** rewrite those that mention the event in the new shape, keep one scenario that uses the old version to prove upcasting works, and add one for a history that mixes both.
7. **Rebuild:** which read models to rebuild, in what order, and how long it takes. Say whether a screen reads stale or empty data meanwhile.
8. **Rollout order** (below).
9. **Agent brief:** the work as a slice in the build-slice skill's format, with tests.

## Rollout order

Never let new events reach code that can't read them. With a rolling deploy, old and new code run side by side.

1. **Release 1, readers first.** Ship the upcaster, the new event module, and readers that handle both versions. Nothing writes the new version yet.
2. **Rebuild** affected read models, if their shape changed.
3. **Release 2, writers.** Producers start writing the new version.
4. **Later, optional.** Once you're sure you'll never roll back to before release 2, stop handling the old version in readers that only need the upcast form. Never delete the old module or the upcaster, because stored history still uses them.

An additive optional field can ship in one release: readers that treat it as optional, plus writers that set it.

## Commanded and AshCommanded specifics

- **Upcasting:** implement the `Commanded.Event.Upcaster` protocol for the old event module, returning the new struct. Commanded applies it when it reads events from the store, so aggregates, handlers and projectors see only the new version.

```elixir
defimpl Commanded.Event.Upcaster, for: Edgemastery.Events.OfficeHoursBooked do
  alias Edgemastery.Events.{OfficeHoursBooked, OfficeHoursBookedV2}

  # v1 stored studentId; v2 calls the person who booked memberId (students and coaches-in-training).
  def upcast(%OfficeHoursBooked{} = e, _metadata) do
    %OfficeHoursBookedV2{slot_id: e.slot_id, member_id: e.student_id, member_kind: :student,
                         coach_id: e.coach_id, booked_at: e.booked_at}
  end
end
```

- **Keep the old module.** Stored events record their module name as the event type, so `Edgemastery.Events.OfficeHoursBooked` must stay defined (deprecated) for as long as its events exist. With AshCommanded, keep the old `event` block in the DSL (or a hand-written struct with the same module name) next to the new one, and check the installed version's generated module names first.
- **Rebuilding a read model:** a projector started under a new name replays the stream from the start. Rename the projector, or reset its stored position, and clear its table, then let it catch up. With AshCommanded's generated projectors, check how the installed version names them (`projector_name`) before relying on that.
- **Automations and replays:** event handlers that send email, take payments or dispatch commands must not act again on old events. Keep their existing name so they continue from where they were, and never reset them during a rebuild.
- **Strong consistency:** while a read model rebuilds, screens reading it may show stale data. Say so in the plan, and add a "catching up" state to the screen if the rebuild takes long.

## State-stored streams: change a table or a published event

With no event store, there's no history to upcast, but there is **data in tables**, and possibly **events in the outbox** that automations and other systems consume. The same principle applies: never break what's already stored or what others rely on.

**Table changes use expand, migrate, contract**, each step a separate release:
1. **Expand:** add the new column or table (nullable or defaulted). Code writes both old and new, and reads the old.
2. **Migrate:** backfill the new column from the old one, in batches for large tables. Then code reads the new one.
3. **Contract:** once nothing reads the old column, and only then, drop it in a later release.

| Change | State-stored approach |
|---|---|
| Add a field | Add a nullable or defaulted column. One release |
| Rename a field | Expand, migrate, contract: add the new column, write both, backfill, switch reads, drop the old one later |
| Change a type | The same as a rename, with a conversion in the backfill. Ask first if the conversion can lose data |
| Remove a field | Stop reading it, then drop it in a later release. Never in the same release as the code change |
| Rename an event | Only a model name, unless the outbox is on (see below) |

**Published outbox events are a contract.** With the outbox on, `DomainEvent.type` and its `data` keys are read by Oban jobs and possibly other systems:
- Adding keys is safe.
- Renaming or removing a key, or renaming the type, needs a **new type version** (`OfficeHoursBooked.v2`). Write both versions for a while, move consumers to v2, then stop writing v1.
- Outbox rows already written are never rewritten. Consumers that replay old rows handle v1.

The reply uses the same structure: `approach` is `"expand_contract"` for table changes or `"new_version"` for outbox types, `upcaster` is null, and `rollout` lists the expand, migrate and contract releases.

## The prompt

The builder sends this, followed by the input JSON:

```text
You plan a safe change to an event that is already stored in an event-sourced app (Commanded / AshCommanded). Stored events never change: every version ever written must still load and replay correctly. Choose the smallest safe approach: additive (new optional field), a new event version with an upcaster, or a new event when the meaning changes. Upcasters never invent facts: if old events can't supply a value, keep the field optional or make it a new event from now on, and say why. Never delete an old event module or upcaster.
Cover: the model change (new or changed event, old version deprecated but kept); the upcaster field by field; producers that write the new version; every reader (projections, which must be updated and rebuilt; aggregates, whose apply/decisions must work on a mixed history; automations, which must not act again during replay); scenarios to rewrite, plus one using the old version and one using a mixed history; read models to rebuild, in what order, with what users see meanwhile; rollout in two releases (readers and upcaster first, writers second) unless the change is purely additive; and a build brief for the coding agent with tests.
If the change could lose data, would rewrite history's meaning, or the requested approach is unsafe, ask a question instead of choosing.
Reply with ONLY one JSON object, no other text:
{"approach":"additive"|"new_version"|"new_event"|"expand_contract","why":string,
 "model":{"add":[{"name":string,"stream":string,"fields":[string],"replaces":string|null}],"deprecate":[string],"changeFields":[{"event":string,"add":[string]}]},
 "upcaster":{"from":string,"to":string,"fields":[{"from":string|null,"to":string,"how":string (copy | default <value> | derived from <...> | left empty: <why>)}]}|null,
 "producers":[{"slice":string,"change":string}],
 "readers":[{"slice":string,"kind":"projection"|"aggregate"|"automation","change":string,"rebuild":boolean,"replaySafe":string|null}],
 "scenarios":[{"slice":string,"title":string,"action":"rewrite"|"add","given":[string],"when":string,"then":[string]}],
 "rebuild":[{"readModel":string,"order":number,"minutes":number|null,"meanwhile":string}],
 "rollout":[{"step":number,"ships":string,"safeBecause":string}],
 "brief":{"id":string,"name":string,"pattern":"state_change","story":string,"files":[string],"specs":[{"kind":string,"title":string,"given":[string],"when":string,"then":[string]}]},
 "questions":[{"text":string,"options":[string]}],
 "summary":string (2-3 sentences a teammate understands)}
```

## Example: rename a field (abridged)

```json
{"approach": "new_version",
 "why": "studentId is stored in 18,240 events; renaming it in place would leave every one of them without memberId.",
 "model": {"add": [{"name": "OfficeHoursBookedV2", "stream": "OfficeHours", "fields": ["slotId: uuid", "memberId: uuid", "memberKind: enum(student|coach_in_training)", "coachId: uuid", "bookedAt: utc_datetime"], "replaces": "OfficeHoursBooked"}],
           "deprecate": ["OfficeHoursBooked"], "changeFields": []},
 "upcaster": {"from": "OfficeHoursBooked", "to": "OfficeHoursBookedV2",
              "fields": [{"from": "slotId", "to": "slotId", "how": "copy"},
                         {"from": "studentId", "to": "memberId", "how": "copy"},
                         {"from": null, "to": "memberKind", "how": "default student: every booking before this change was made by a student"},
                         {"from": "coachId", "to": "coachId", "how": "copy"},
                         {"from": "bookedAt", "to": "bookedAt", "how": "copy"}]},
 "readers": [
  {"slice": "live-sessions", "kind": "projection", "change": "Handle OfficeHoursBookedV2: set myBooking from memberId.", "rebuild": false, "replaySafe": null},
  {"slice": "book-office-hours", "kind": "aggregate", "change": "apply/2 handles V2 only (the upcaster converts old events); 'one booking at a time' keys on memberId.", "rebuild": false, "replaySafe": null},
  {"slice": "office-hours-reminder", "kind": "automation", "change": "Handle V2; email memberId.", "rebuild": false, "replaySafe": "Keeps its name, so it isn't replayed and never re-sends reminders."}],
 "scenarios": [
  {"slice": "book-office-hours", "title": "Already taken", "action": "rewrite", "given": ["OfficeHoursSlotOpened(slotId: s-1)", "OfficeHoursBookedV2(slotId: s-1, memberId: u-3, memberKind: student)"], "when": "BookOfficeHours(slotId: s-1, memberId: u-2)", "then": ["error: this slot is taken"]},
  {"slice": "book-office-hours", "title": "Old booking still blocks the slot", "action": "add", "given": ["OfficeHoursSlotOpened(slotId: s-1)", "OfficeHoursBooked(slotId: s-1, studentId: u-3)"], "when": "BookOfficeHours(slotId: s-1, memberId: u-2)", "then": ["error: this slot is taken"]}],
 "rebuild": [],
 "rollout": [
  {"step": 1, "ships": "OfficeHoursBookedV2, the upcaster, and readers that handle V2.", "safeBecause": "Nothing writes V2 yet, and old events are upcast as they're read."},
  {"step": 2, "ships": "BookOfficeHours writes V2 with memberId.", "safeBecause": "Every reader already understands V2."}],
 "questions": [],
 "summary": "Bookings get a new version that says who booked (memberId) and whether they're a student. Old bookings are read as students' bookings, so nothing in the history changes. It ships in two releases, readers first, and no read model needs rebuilding."}
```

## What the builder does with the reply

- **Shows the plan** on the event's sticky: approach, rollout steps, readers affected, rebuild time.
- **Model change:** sends it to repair-and-merge as a diff, so the new event appears on the board with the old one greyed out as deprecated, still listed under every reader that handles it.
- **Questions:** posted to the slice's Discussion with the options as buttons.
- **Build:** adds the brief to the Build page as a slice with a "Event change" badge, already ordered by the build-order planner after anything it depends on. Its two releases become two pull requests (readers first, then writers), and the planner holds the second until the first merges.
- **The PR checker:** knows the change is planned, so it allows the new version and the upcaster instead of flagging them. It still blocks anything that alters the old event.

## Done means
- Every stored version still loads: the old module and the upcaster exist and are tested.
- Every reader handles the new version, and none acts again on replayed history.
- Scenarios cover the new shape, the old version, and a mixed history.
- The rollout never lets a new event reach code that can't read it.
- Nothing in history was invented. Anything old events couldn't supply is optional or explained.
