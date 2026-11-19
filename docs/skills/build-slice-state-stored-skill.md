---
name: build-event-model-slice-state-stored
description: Build one slice of an event model into a state-stored (CRUD) Phoenix LiveView + Ash app — no event sourcing — where commands are Ash actions on tables, events are the state changes (optionally recorded in an outbox), and read models are read actions or queries, with every Given/When/Then scenario as a test, then open a pull request. Use when the slice's stream is state stored, typically in an existing codebase, instead of the event-sourced build skill.
---

# Build a slice (state stored)

Event Modeling doesn't require event sourcing. In a state-stored app, tables hold the **current state**, and the model's events describe the **changes** to that state. This skill builds one slice that way. The model is the same contract as in the event-sourced skill (`build-slice-skill.md`): the same names, fields and scenarios, built with plain Ash on tables.

**Which skill to use.** The builder sends the brief to this skill when the slice's stream is state stored:
- the project's storage setting is **State stored**; or
- it's **Mixed** and this stream isn't ticked as event sourced.

Everything about the brief, the build steps, the status messages, the pull request template and "when the spec and the code disagree" is the same as in the event-sourced skill. Only the mapping to code and the tests differ, and those are below.

## What's different in the brief

```json
{
  "project": {"stack": "Elixir: Phoenix LiveView + Ash", "persistence": {"mode": "state_stored", "outbox": true}},
  "slice": { /* the same slice structure as the event-sourced skill */ },
  "context": {"tables": [{"resource": "Edgemastery.LiveSessions.OfficeHoursSlot", "table": "office_hours_slots", "fields": ["id", "coach_id", "starts_at", "duration_minutes", "booked_by", "booked_at"]}]}
}
```

- `persistence.outbox`: when true, each command's events are also written as rows in an outbox table, in the same transaction. Automations, notifications and audit use them.
- `context.tables`: what's already stored for the slice's stream. An existing codebase may already have tables with different names; use them.

## How the model maps to code

| Model | State stored, with Ash (no AshCommanded) |
|---|---|
| Stream (`OfficeHours`) | The Ash resource and table for the thing the events are about. In an existing codebase, the resource that already exists |
| Command (`BookOfficeHours`) | An Ash action on that resource (`update :book_office_hours`, `create :open_office_hours_slot`), with a code interface (`define :book_office_hours`) |
| Event (`OfficeHoursBooked`) | **The state change the action makes.** The event's fields are what changes, plus what readers need. With `outbox`, a `DomainEvent` row with type `"OfficeHoursBooked"` and those fields, written by a change in the same transaction |
| Rule (an `error:` scenario) | An Ash validation on the action (custom module or built-in). Rules that two requests could race on also get a **database constraint**: a unique index (Ash `identities`), a check constraint, or a row lock |
| Read model (`LiveSessions`) | A read action (filters, sort, arguments, `calculations`, `aggregates`) that returns exactly the read model's fields. A separate table only when a query is too slow, kept up to date by the same actions |
| Projection | Usually nothing. The read action is the projection. When there's a read table, the actions that change state update it in the same transaction |
| Automation | An Oban job (or AshOban trigger). It reads the outbox for events from inside the app, or is started by a webhook controller for facts from outside |
| Screen (`uiElement`) | The LiveView: a `handle_event` that calls the action through its code interface, with assigns from the read action. Optional live updates through `Ash.Notifier.PubSub`, which publishes after the transaction commits |
| Scenario | One ExUnit test with the same title. **Given** = prior state reached by running the earlier actions; **When** = the action or read; **Then** = the result, the stored state, and the outbox row |
| Field types | The same as the event-sourced skill: `uuid`, `string`, `integer`, `decimal`, `boolean`, `date`, `utc_datetime`, `map`, `{:array, _}`, and atoms with `one_of`. Names change from camelCase to snake_case |

## Steps

Follow the event-sourced skill's ten steps, with these differences:

- **Step 2 (read):** also read the existing schema: migrations, resources, and any Ecto schemas the codebase still uses. **Reuse existing tables and columns** when they already hold the slice's state; don't create a parallel table.
- **Step 3 (check the spec):** the same spec questions as the event-sourced skill. In a state-stored stream, a unique value also needs a database guarantee (a unique index or identity), so a missing "taken" scenario is always a question: the agent needs the on-screen text for the constraint error.
- **Step 5 (write side):** add the action, its validations, constraints for raceable rules, and the outbox change. Add a migration with `mix ash.codegen <name>` if columns or tables are new.
- **Step 6 (read side):** a read action with exactly the read model's fields, and calculations or aggregates for derived values. Add a read table only with a reason in the PR.
- **Migrations are additive** (see "Changing tables safely"). Never drop or rename a column in a slice's pull request.

## Example: the write side

```elixir
# lib/edgemastery/live_sessions/office_hours_slot.ex
defmodule Edgemastery.LiveSessions.OfficeHoursSlot do
  use Ash.Resource,
    domain: Edgemastery.LiveSessions,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "office_hours_slots"
    repo Edgemastery.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :coach_id, :uuid, allow_nil?: false, public?: true
    attribute :starts_at, :utc_datetime, allow_nil?: false, public?: true
    attribute :duration_minutes, :integer, allow_nil?: false, public?: true
    attribute :booked_by, :uuid, public?: true
    attribute :booked_at, :utc_datetime, public?: true
  end

  actions do
    defaults [:read]

    # Command BookOfficeHours → event OfficeHoursBooked
    update :book_office_hours do
      require_atomic? false
      argument :student_id, :uuid, allow_nil?: false
      validate Edgemastery.LiveSessions.Validations.SlotIsFree
      change set_attribute(:booked_by, arg(:student_id))
      change set_attribute(:booked_at, &DateTime.utc_now/0)
      change {Edgemastery.Changes.RecordEvent,
              type: "OfficeHoursBooked", stream: "OfficeHours",
              fields: [:id, :booked_by, :coach_id, :starts_at, :booked_at]}
    end
  end

  code_interface do
    define :book_office_hours, args: [:student_id]
  end

  pub_sub do
    module EdgemasteryWeb.Endpoint
    prefix "office_hours"
    publish :book_office_hours, ["booked", :id]
  end
end
```

```elixir
# lib/edgemastery/live_sessions/validations/slot_is_free.ex
defmodule Edgemastery.LiveSessions.Validations.SlotIsFree do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_data(changeset, :booked_by) do
      nil -> :ok
      _ -> {:error, field: :booked_by, message: "this slot is taken"}
    end
  end
end
```

**Races.** A validation alone can't stop two students booking the same free slot at the same moment. For rules like this:
- add a database guarantee, for example a conditional update that only books when `booked_by IS NULL`, or a row lock (`lock: "FOR UPDATE"` on the read inside the action);
- or add a unique index through `identities` when the rule is "only one X per Y".

Name the guarantee in the PR's "Model → code" table.

## The outbox (when `persistence.outbox` is on)

One small table records the model's events as facts, in the same transaction as the state change. If the change rolls back, so does the event.

```elixir
# lib/edgemastery/changes/record_event.ex
defmodule Edgemastery.Changes.RecordEvent do
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      Edgemastery.Events.DomainEvent
      |> Ash.Changeset.for_create(:record, %{
        type: opts[:type],
        stream: opts[:stream],
        stream_id: record.id,
        data: Map.take(record, opts[:fields])
      })
      |> Ash.create!()

      {:ok, record}
    end)
  end
end
```

`Edgemastery.Events.DomainEvent` is one resource for the whole app: `id`, `type`, `stream`, `stream_id`, `data` (map), `occurred_at`, `processed_at`.
- Add it once, in the first slice that needs it.
- Automations read it through Oban, marking rows processed. That's how automations run reliably without event sourcing.
- Later, any stream can move to full event sourcing using the outbox's history as its starting point.

## Example: the read side

```elixir
# in the same resource: read model LiveSessions → a read action returning its fields
read :live_sessions do
  argument :viewer_id, :uuid, allow_nil?: false
  filter expr(starts_at > now())
  prepare build(sort: [starts_at: :asc], load: [:taken, :mine])
end

calculations do
  calculate :taken, :boolean, expr(not is_nil(booked_by))
  calculate :mine, :boolean, expr(booked_by == ^arg(:viewer_id)), arguments: [viewer_id: [type: :uuid]]
end
```

Check the exact calculation and argument syntax against the installed Ash version. The rule is that the read action returns what the read model lists, computed from stored state.

## Scenarios become tests

**Given** is prior state, reached by running the actions that produce the Given events. Add one helper module per stream, with functions named after the events, so tests read like the scenarios:

```elixir
# test/support/given/office_hours.ex
defmodule Edgemastery.Given.OfficeHours do
  alias Edgemastery.LiveSessions.OfficeHoursSlot

  # Given OfficeHoursSlotOpened(...)
  def office_hours_slot_opened(attrs \\ %{}) do
    OfficeHoursSlot.open_office_hours_slot!(Map.merge(%{coach_id: Ecto.UUID.generate(),
      starts_at: DateTime.add(DateTime.utc_now(), 2, :day) |> DateTime.truncate(:second), duration_minutes: 30}, attrs))
  end

  # Given OfficeHoursBooked(...)
  def office_hours_booked(slot, student_id \\ Ecto.UUID.generate()),
    do: OfficeHoursSlot.book_office_hours!(slot, student_id)
end
```

```elixir
defmodule Edgemastery.LiveSessions.BookOfficeHoursTest do
  use Edgemastery.DataCase, async: true
  import Edgemastery.Given.OfficeHours
  alias Edgemastery.LiveSessions.OfficeHoursSlot

  test "Free slot booked" do
    slot = office_hours_slot_opened()
    student = Ecto.UUID.generate()

    assert {:ok, booked} = OfficeHoursSlot.book_office_hours(slot, student)
    assert booked.booked_by == student
    assert_event "OfficeHoursBooked", stream_id: slot.id, data: %{booked_by: student, coach_id: slot.coach_id}
  end

  test "Already taken" do
    slot = office_hours_slot_opened() |> office_hours_booked()

    assert {:error, error} = OfficeHoursSlot.book_office_hours(slot, Ecto.UUID.generate())
    assert error_message?(error, "this slot is taken")
    refute_event "OfficeHoursBooked", count: 2, stream_id: slot.id
  end
end
```

- `assert_event`, `refute_event` and `error_message?` live in `test/support/scenario_case.ex`. They query the outbox, and walk `Ash.Error.Invalid` errors for the message. Without the outbox, **Then** for a state change asserts the stored record only.
- Read models are tested through their read action, with the Given state set up through helpers. LiveView tests are the same as in the event-sourced skill.
- **Races:** for each rule with a database guarantee, add one test that two concurrent attempts produce exactly one success.

## Files for a slice

| Pattern | Files |
|---|---|
| state_change | `lib/<app>/<domain>/<resource>.ex` (action and code interface), `…/validations/*.ex`, `lib/<app>/changes/record_event.ex` (once), `lib/<app>/events/domain_event.ex` (once), a migration if needed, the LiveView, `test/support/given/<stream>.ex`, `test/<app>/<domain>/<slice>_test.exs` |
| state_view | The read action, calculations and aggregates on the resource (or a read-table resource with a reason), the LiveView, tests |
| automation | `lib/<app>/workers/<slice>.ex` (Oban worker, reading the outbox), or a webhook controller that calls the action. It must ignore repeats: record the provider's id and check it first |

## Screens with Hologram

On a stack with Hologram, screens are Hologram pages instead of LiveViews. The page's server `command/3` calls the Ash action through its code interface, with the actor taken from the session. It then sends back either the refreshed read model or the validation message:

```elixir
def command(:book, params, server) do
  student = get_session(server, :user_id)
  slot = Edgemastery.LiveSessions.get_slot!(params.slot_id)

  case OfficeHoursSlot.book_office_hours(slot, student) do
    {:ok, _} -> put_action(server, :booked, slots: Edgemastery.LiveSessions.live_sessions_for(student))
    {:error, error} -> put_action(server, :failed, message: Edgemastery.Errors.text(error))
  end
end
```

**Rules for Hologram screens**
- **Writes happen only in server `command/3` handlers.** A client `action/3` may check input for quick feedback, but the rule must also be enforced on the server: in the aggregate (event sourced) or the Ash action (state stored).
- **Who acts comes from the session** (`get_session(server, :user_id)`), never from parameters the browser sends.
- **State goes to the browser.** Put only the read model's fields into state, as plain maps. Never put Ash records, structs with metadata, or secrets there.
- **Read with strong consistency.** Dispatch with `consistency: :strong` (event sourced) so the read model is current when `put_action` sends it back, or re-read after the Ash action (state stored).
- **Show errors with the scenario's exact text**, mapped from the error atom or validation message in one place.
- **No LiveView syntax in Hologram modules:** no `assign`, `handle_event`, `phx-*`, `~H` or `<.component>`. Use `put_state`, `action/3`, `$click` and `~HOLO`.

The Hologram page example and its version caveats are in `build-slice-skill.md`, under "Stack profile: Phoenix + Ash + Commanded + Hologram".

## Screens with Elm

On a stack with Elm, the write endpoint's controller calls the Ash action through its code interface, with the actor from `conn.assigns.current_user`. It answers 200 with the fresh read model, or 422 with `{"error": …}` taken from the validation message. Read endpoints return the read action's result with exactly the read model's fields. The Elm page, the decoders, the error handling, the shared JSON fixtures and the rules are the same as in `build-slice-skill.md`, under "Screens: Elm".

## Changing tables safely

State-stored apps have no event history to protect, but they do have data. In a slice's pull request:
- **Add only:** new tables; new columns that are nullable or have a default; new indexes (concurrently on large tables).
- **Never** drop, rename or retype a column, or remove a default that existing rows rely on. Those changes go through the event-change skill's state-stored section: expand, migrate the data, then contract, across releases.
- If the outbox is on, a `DomainEvent`'s `data` keys are a contract with automations and other systems. Add keys freely; never rename or remove one in a slice's pull request.

## Done means
- Every scenario has a passing test with the same title: Given reached through actions, Then checking the result, the stored state and (with the outbox) the event row.
- Every rule is on the action, with the scenario's exact error text, and raceable rules also have a database guarantee.
- Every rule in the code has a scenario in the model, and no spec question is still open.
- Every value a screen shows comes from a read action, returning the read model's fields.
- Migrations only add.
- The pull request is open with the template filled in, and `checks` were reported.
