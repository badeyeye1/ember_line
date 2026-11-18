---
name: generate-example-data-from-event-model
description: Generate realistic, rule-abiding example data from an event model — histories of commands and events built from its scenarios — for demos, preview environments, prototype screens and test fixtures, as a seed script that dispatches commands, event-builder fixtures for ExUnit, and JSON for drawn screens. Use when someone needs demo or seed data, fixtures for the agent's tests, or believable data in prototype screens.
---

# Generate example data from the event model

Demos, preview environments, drawn screens and tests all need data. Hand-made data drifts from the rules: a slot booked twice, a refund with no payment, a seat count that doesn't add up. In an event-sourced app, the data **is** the history of events, so example data should be a believable history that the app's own rules would have allowed.

This skill writes that history from the model:
- **People and things** come from the streams.
- **What happened to them** comes from the commands and events.
- **What's allowed** comes from the scenarios.
- **The shapes** come from the event fields.

Every generated history replays through the real code without breaking a rule, unless it's deliberately an error example.

## Outputs

| Output | For | Form |
|---|---|---|
| **Seed script** | Demos, preview environments, local development | `priv/repo/seeds/<profile>.exs`, which dispatches **commands** through the app, so rules are checked and events, read models and projections all come out right |
| **Event fixtures** | The coding agent's and the team's tests | `test/support/fixtures/<stream>_events.ex`: builder functions that return event structs with sensible defaults (`office_hours_booked(slot_id: …)`) |
| **Screen data** | Drawn screens and prototype pages | JSON per read model, matching its fields, for the page's Normal state |
| **Scenario histories** | Illustrating scenarios and reviewing them | The Given events of each scenario, filled out with consistent ids and values |

## Profiles

| Profile | Size | Shape |
|---|---|---|
| `demo` | Small: about 5 people, about 20 things per stream | Tells a story a presenter can walk through. Every outcome has at least one complete thread, and every screen has data. Includes one example of each interesting state (a full slot, a cancelled booking, a failed payment) |
| `preview` | Medium: about 50 people, a few hundred events per stream | Realistic spread over the last 90 days, mixed statuses, some edge cases |
| `load` | Large, set by the team | Volume for performance checks. Same rules, generated in batches |
| `fixtures` | Per test | Minimal. Only what a scenario needs |

## What you get

```json
{
  "profile": "demo",
  "model": { /* slices with commands, events, fields, scenarios; streams; outcomes */ },
  "story": "A coaching academy, Apex Trading Academy, two coaches and five students, during one busy week in November." | null,
  "now": "2026-11-18T09:00:00Z",
  "seed": 4211,
  "locale": "en-GB",
  "built": ["create-account", "log-trade", "book-office-hours"],
  "dispatch": {"module": "Edgemastery.CommandedApplication", "router": "AshCommanded.Router"}
}
```

- `story` is optional. With one, the data follows it. Without one, Claude proposes a short one from the app summary.
- `seed` makes the output repeatable: the same seed gives the same data.
- `built` limits the seed script to commands that exist in code. Unbuilt slices only get screen data.

## Done in code first (not by Claude)

| Step | Rule |
|---|---|
| Order of streams | Producers before readers, using the build-order graph: accounts before bookings, slots before bookings |
| Rules as constraints | Collected from each slice's `error` scenarios and their messages, to check every generated command against |
| Value generators by type | `uuid` (deterministic from the seed), `utc_datetime` (relative to `now`), `integer` and `decimal` ranges from scenario values, `enum` from the listed options |
| Replay check | After generating, the builder replays the history through the aggregates (or dispatches against a test event store). Anything rejected is reported, never silently dropped |

Claude's job is the believable part:
- the cast and the story;
- names, titles and text that sound real for this app;
- which things happen to whom and when;
- making sure every screen and outcome has something to show;
- placing deliberate edge cases.

## Rules

**Obey the model**
- Only commands and events the model has, with exactly their fields.
- Every generated command must pass every rule in its slice's `error` scenarios. Deliberate error examples are listed separately (`rejected`), and the seed script dispatches them only in the `demo` profile's "show an error" moments, expecting the error.
- Histories are causally ordered: nothing is booked before its slot opens, nothing refunded before it's paid. Timestamps go forwards along each stream.
- Ids are consistent everywhere: the same `slotId` in the slot's events, the booking and the read-model rows.

**Be believable, not real**
- Invent people, organisations, emails and text. Never use real people's names, real companies' details, or real contact data. Emails use the `example.com` or `example.org` domains.
- Match the app's world: an academy for traders has coaches, cohorts and trading setups, not lorem ipsum.
- Spread activity the way real use is spread: most things recent, a few old, a few in the future where the model has scheduling.

**Cover every screen and outcome**
- Each read model gets enough rows to look used, and at least one state that matches its `empty` scenario is reachable (a new student with nothing booked).
- Each outcome has at least one complete thread from start to end.
- Include one example of each edge case the scenarios name (the last seat, a booking cancelled and rebooked, a webhook delivered twice).

**Keep it repeatable**
- The same `seed` and `now` give identical output.
- The seed script can run twice without creating duplicates: commands with natural ids are skipped if the stream already exists.

## State-stored streams

The history is still built from commands, so the rules are checked the same way. Only the outputs change:
- **Seed script:** calls the Ash actions through their code interfaces (`OfficeHoursSlot.book_office_hours!(slot, student_id)`) instead of dispatching commands. Rows, and outbox events when the outbox is on, come out of the actions themselves. Never insert rows directly, because that skips the rules.
- **Fixtures:** become **Given helpers** (`test/support/given/<stream>.ex`). They're functions named after events that reach that state by running the producing actions, as in `build-slice-state-stored-skill.md`. They aren't event structs.
- **Running twice:** a state-stored seed can't rely on streams already existing. It checks for its natural keys (an email, a slot's coach and time) before creating anything.
- **Mixed projects:** each stream uses its own style, and producers still come before readers.

## The prompt

The builder sends this, followed by the input JSON and the constraints computed in code:

```text
You write example data for an event-sourced app as a believable history of commands, built from its event model. Use only the model's commands and events with exactly their fields. Every command must pass every rule in its slice's error scenarios; deliberate error examples go in "rejected". Order histories causally, keep ids consistent everywhere, and move timestamps forward per stream, relative to "now".
Invent everything: people, organisations, emails (example.com/example.org only) and text; never real people or real companies' details. Match the app's world and the story (propose a short one if none is given). Spread activity like real use. Cover every read model with enough rows to look used, keep each empty state reachable, give every outcome at least one complete thread, and include one example of each edge case the scenarios name.
Profile "{{profile}}": {{PROFILE_RULES}}. Seed {{seed}}: be deterministic.
Reply with ONLY one JSON object, no other text:
{"story":string,
 "cast":[{"id":string,"kind":string (stream or role),"name":string,"about":string}],
 "commands":[{"at":string (ISO time),"slice":string,"command":string,"as":string (cast id),"fields":{},"expect":"ok"}],
 "rejected":[{"at":string,"slice":string,"command":string,"as":string,"fields":{},"expect":string (the error text from the scenario),"why":string}],
 "screenData":[{"readModel":string,"rows":[{}]}] (only for read models of unbuilt slices, or when asked),
 "coverage":{"readModels":{"<name>":number},"outcomes":{"<id>":"complete"|"partial"},"edges":[string]},
 "notes":[string] (anything the model couldn't support, e.g. a screen value no event provides)}
```

`{{PROFILE_RULES}}`:
- **demo:** "about 5 people and 20 things per stream, one walkable story, one example of each interesting state."
- **preview:** "about 50 people, a few hundred events per stream over the last 90 days, mixed statuses."
- **load:** "{{n}} things per stream in batches, same rules."
- **fixtures:** "the minimum each scenario's Given needs."

## What the builder makes from the reply

**Seed script** (built slices only, dispatching through the app):

```elixir
# priv/repo/seeds/demo.exs  (generated from the event model, seed 4211, now 2026-11-18T09:00Z)
alias Edgemastery.Commands.{OpenOfficeHoursSlot, BookOfficeHours}
import Edgemastery.Seeds.Helpers   # dispatch!/1 skips streams that already exist; expect_error!/2

# Apex Trading Academy, week of 16 Nov: Coach Ama opens Thursday slots; Ife books one.
dispatch!(%OpenOfficeHoursSlot{slot_id: "0b6c…", coach_id: "a3f1…", starts_at: ~U[2026-11-19 10:00:00Z], duration_minutes: 30})
dispatch!(%BookOfficeHours{slot_id: "0b6c…", student_id: "77d2…"})

# Shows the "This slot is taken" state on the Office hours screen.
expect_error!(%BookOfficeHours{slot_id: "0b6c…", student_id: "9e40…"}, "this slot is taken")
```

**Event fixtures** (one module per stream, defaults from the cast):

```elixir
defmodule Edgemastery.Fixtures.OfficeHoursEvents do
  alias Edgemastery.Events.{OfficeHoursSlotOpened, OfficeHoursBooked}

  def office_hours_slot_opened(attrs \\ []) do
    struct!(OfficeHoursSlotOpened, Keyword.merge([slot_id: Ecto.UUID.generate(), coach_id: Ecto.UUID.generate(),
      starts_at: DateTime.add(DateTime.utc_now(), 2, :day) |> DateTime.truncate(:second), duration_minutes: 30], attrs))
  end

  def office_hours_booked(attrs \\ []) do
    struct!(OfficeHoursBooked, Keyword.merge([slot_id: Ecto.UUID.generate(), student_id: Ecto.UUID.generate(),
      coach_id: Ecto.UUID.generate(), booked_at: DateTime.utc_now() |> DateTime.truncate(:second)], attrs))
  end
end
```

The build-slice skill's tests use these fixtures for Given events, so every slice's tests share one set of defaults.

**Screen data:** goes to drawn screens and prototype pages for their Normal state. Their Empty states stay empty.

**The coverage report** shows next to the profile: rows per read model, outcomes with a complete thread, and edge cases included. **Notes** go to the relevant slice's Discussion.

**Running it:** **Load demo data** on a preview environment runs the seed script. Commands that are rejected unexpectedly stop the run and are listed with their slice and error, because that means the data or the code disagrees with the spec.

## Done means
- The history replays through the real code with no unexpected rejections.
- Every command and event matches the model's fields, and every id agrees everywhere it appears.
- Every read model has data, every empty state is still reachable, and every outcome has a complete thread.
- Nothing refers to real people or real companies.
- The same seed gives the same data, and running the seed script twice changes nothing.
