---
name: build-event-model-slice
description: Build one slice of an event model into working code in an event-sourced Phoenix + Ash app (AshCommanded, or plain Commanded with LiveView, Hologram or Elm screens), turning each Given/When/Then scenario into a test, then open a pull request. Use when a coding agent receives a slice from the Event-Model Builder's Build page, or anyone asks to implement a slice from an event model spec.
---

# Build a slice

You receive **one slice** from an event model: its command, events, read model, projection, fields and scenarios. You build exactly that slice in the project's codebase, prove it with tests written from its scenarios, and open a pull request. The Build board follows you through the status messages you send.

The spec is the contract. Names, fields and scenarios come from the model. When the code needs something the spec doesn't say, ask; don't invent it quietly.

## Which build skill

This skill is for **event-sourced** streams: events are the source of truth. The builder picks the skill per slice from the project's storage setting:

| The slice's stream is | Skill |
|---|---|
| Event sourced (project setting **Event sourced**, or **Mixed** with this stream ticked) | This one |
| State stored (project setting **State stored**, or **Mixed** without this stream ticked) | `build-slice-state-stored-skill.md`: Ash actions on tables, events as state changes, optional outbox |

The brief carries `project.persistence` so the agent can check, and the two skills share the brief format, the status messages and the pull request template.

## What you get

The Build page sends this brief when someone presses **Send**:

```json
{
  "project": {"name": "Edgemastery", "stack": "Elixir: Phoenix LiveView + Ash + AshCommanded", "repo": "acme/edgemastery", "baseBranch": "main", "branchPrefix": "em/"},
  "slice": {
    "id": "book-office-hours", "name": "Book office hours", "pattern": "state_change",
    "screen": {"id": "live", "name": "Live sessions", "source": "live.html"},
    "actor": "Student", "uiElement": "Book button on a free slot",
    "story": "A student on a tier that includes coaching books a free office hours slot.",
    "command":  {"name": "BookOfficeHours", "fields": ["slotId: uuid", "studentId: uuid"]},
    "produces": [{"name": "OfficeHoursBooked", "fields": ["slotId: uuid", "studentId: uuid", "coachId: uuid", "startsAt: utc_datetime", "bookedAt: utc_datetime"]}],
    "reads": [], "readModel": null, "projection": null,
    "specs": [
      {"kind": "success", "title": "Free slot booked", "given": ["OfficeHoursSlotOpened(slotId: s-1, coachId: c-1)"], "when": "BookOfficeHours(slotId: s-1, studentId: u-2)", "then": ["OfficeHoursBooked(slotId: s-1, studentId: u-2, coachId: c-1)"]},
      {"kind": "error", "title": "Already taken", "given": ["OfficeHoursSlotOpened(slotId: s-1)", "OfficeHoursBooked(slotId: s-1, studentId: u-3)"], "when": "BookOfficeHours(slotId: s-1, studentId: u-2)", "then": ["error: this slot is taken"]}
    ]
  },
  "context": {
    "streams": {"OfficeHoursSlotOpened": "OfficeHours", "OfficeHoursBooked": "OfficeHours"},
    "neighbours": "slices that produce the events this one reads, or read the events it produces (names and fields only)",
    "built": "slices already merged, with the files they live in"
  }
}
```

## How the model maps to the code

| Model | Phoenix + Ash + AshCommanded |
|---|---|
| Stream (`OfficeHours`) | One Ash resource with the `AshCommanded.Commanded.Dsl` extension, in the domain for that area. The resource's identity is the stream id (`slotId` becomes `:slot_id`). |
| Command (`BookOfficeHours`) | `command :book_office_hours` in `commanded do commands do … end end`, with `fields` and `identity_field`, plus the Ash action it runs. |
| Event (`OfficeHoursBooked`) | `event :office_hours_booked` with `fields`. |
| Business rule (an `error:` scenario) | A rule that needs only the command's own data goes in `validate_params` or an Ash validation. A rule that needs earlier events of the same stream goes in the aggregate (see "When a rule needs history"). |
| Projection and read model (`LiveSessions`) | `projection :<event>` blocks with `action` and `changes` on a read-side resource that has its own table, one per read model. |
| Automation | An `event_handlers do handler … end` block that reacts to events and dispatches the next command. For something from outside the app, like a webhook, it's a controller or job that dispatches the command. |
| Screen (`uiElement`) | The LiveView for the screen: a `handle_event` that dispatches the command, with assigns read from the read model. |
| Scenario | One ExUnit test with the same title. |
| Field types | `"name: type"` becomes an Ash attribute: `uuid`, `string`, `integer`, `decimal`, `boolean`, `date`, `utc_datetime`, `map`, `{:array, _}` for `list`, and an atom with `one_of` for `enum(a|b)`. Names change from camelCase to snake_case. |

**Check the installed version first.** AshCommanded is young: v0.2.0 at the time of writing, and its pages disagree in places. They differ on the default Ash action a command runs, on `command_name` vs `handler_name`, and on how projectors are supervised. Before writing DSL:
1. Read `mix.lock` for the version.
2. Open the docs for that version in `deps/ash_commanded`.
3. Look at the code it generates for a resource that's already built: compile, then read the generated command handler and projector.

Follow what you find there over the examples below.

## Stack profile: Phoenix + Ash + Commanded (LiveView, Hologram or Elm screens)

Three stacks share this profile:
- **Elixir: Phoenix LiveView + Ash + Commanded**, with LiveView screens;
- **… + Hologram**, with Hologram pages;
- **… + Elm**, with Elm pages over a JSON API.

In all three, the write side uses **plain Commanded** (not AshCommanded), and Ash holds the read models. Only the screens differ. The model maps like this:

| Model | This stack |
|---|---|
| Command | A plain struct (`Edgemastery.Commands.BookOfficeHours`), routed in the Commanded router (`dispatch BookOfficeHours, to: OfficeHoursAggregate, identity: :slot_id`) |
| Event | A plain struct with `@derive Jason.Encoder` (`Edgemastery.Events.OfficeHoursBooked`) |
| Rule | The aggregate's `execute/2` (see "When a rule needs history" below; that's the default here, not the fallback) |
| Projection | A `Commanded.Projections.Ecto` projector with `project %OfficeHoursBooked{} = e, fn multi -> … end`, writing to the read model's table. Use `consistency: :strong` for projectors a screen reads straight after a command |
| Read model | An Ash resource over the projector's table, read-only from the app: read actions, calculations and a code interface (`live_sessions_for/1`). The projector writes, Ash reads |
| Automation | A Commanded event handler (one event, one reaction) or a process manager (several steps), dispatching the next command |
| Screen | **LiveView:** `handle_event` dispatches the command, and assigns come from the Ash read action. **Hologram:** `init/3` reads through Ash, a button's `action/3` calls `put_command`, and the server's `command/3` dispatches. **Elm:** a `Msg` posts to a JSON endpoint whose controller dispatches, and the page reads through a JSON read endpoint |

### Screens: LiveView

```elixir
# lib/edgemastery_web/live/live_sessions_live.ex (excerpt)
def mount(_params, _session, socket) do
  {:ok, assign(socket, slots: Edgemastery.LiveSessions.live_sessions_for(socket.assigns.current_user.id), error: nil)}
end

def handle_event("book", %{"slot-id" => slot_id}, socket) do
  student = socket.assigns.current_user.id

  case Edgemastery.App.dispatch(%BookOfficeHours{slot_id: slot_id, student_id: student}, consistency: :strong) do
    :ok -> {:noreply, assign(socket, slots: Edgemastery.LiveSessions.live_sessions_for(student), error: nil)}
    {:error, reason} -> {:noreply, assign(socket, error: Edgemastery.Errors.text(reason))}
  end
end
```

The template renders `@slots`, a **Book** button with `phx-click="book" phx-value-slot-id={slot.id}`, and `@error` in the scenario's words. The rules are the same as for the other screen types: the actor comes from the session, rules are enforced in the aggregate, and reads use strong consistency.

### Screens: Hologram

```elixir
# lib/edgemastery_web/pages/live_sessions_page.ex
defmodule EdgemasteryWeb.LiveSessionsPage do
  use Hologram.Page
  alias Edgemastery.Commands.BookOfficeHours

  route "/live"
  layout EdgemasteryWeb.MainLayout

  # Runs on the server: read the read model through Ash, put plain data into state.
  def init(_params, component, server) do
    viewer = get_session(server, :user_id)
    put_state(component, slots: Edgemastery.LiveSessions.live_sessions_for(viewer), error: nil)
  end

  def template do
    ~HOLO"""
    <ul>
      {%for slot <- @slots}
        <li>{slot.starts_at} {%if slot.taken}Taken{%else}<button $click={:book, slot_id: slot.id}>Book</button>{/if}</li>
      {/for}
    </ul>
    {%if @error}<p class="error">{@error}</p>{/if}
    """
  end

  # Client action (runs in the browser): hand the write to the server.
  def action(:book, params, component), do: put_command(component, :book, slot_id: params.slot_id)

  # Server command: the actor comes from the session, never from the browser.
  def command(:book, params, server) do
    student = get_session(server, :user_id)
    command = %BookOfficeHours{slot_id: params.slot_id, student_id: student}

    case Edgemastery.App.dispatch(command, consistency: :strong) do
      :ok -> put_action(server, :booked, slots: Edgemastery.LiveSessions.live_sessions_for(student))
      {:error, reason} -> put_action(server, :failed, message: Edgemastery.Errors.text(reason))
    end
  end

  def action(:booked, params, component), do: put_state(component, slots: params.slots, error: nil)
  def action(:failed, params, component), do: put_state(component, :error, params.message)
end
```

**Rules for Hologram screens**
- **Writes happen only in server `command/3` handlers.** A client `action/3` may check input for quick feedback, but the rule must also be enforced on the server: in the aggregate (event sourced) or the Ash action (state stored).
- **Who acts comes from the session** (`get_session(server, :user_id)`), never from parameters the browser sends.
- **State goes to the browser.** Put only the read model's fields into state, as plain maps. Never put Ash records, structs with metadata, or secrets there.
- **Read with strong consistency.** Dispatch with `consistency: :strong` (event sourced) so the read model is current when `put_action` sends it back, or re-read after the Ash action (state stored).
- **Show errors with the scenario's exact text**, mapped from the error atom or validation message in one place.
- **No LiveView syntax in Hologram modules:** no `assign`, `handle_event`, `phx-*`, `~H` or `<.component>`. Use `put_state`, `action/3`, `$click` and `~HOLO`.

**Check the installed Hologram first.** Hologram is pre-1.0 (v0.12.x when this was written), so its template syntax and test helpers may change. Read `deps/hologram/usage-rules.md` (and `llms-full.txt` if present) before writing pages, and follow it over this example. Hologram mounts as a plug in front of the Phoenix router and passes on requests it doesn't own, so existing LiveViews can stay. Confirm this works in your app before building new screens next to old ones.

### Screens: Elm

Each screen is an Elm page module, mounted where the screen lives: from a Phoenix template or a LiveView hook (`Elm.Page.LiveSessions.init({ node, flags })`), or as part of an Elm single-page app. Flags carry the initial read model and the CSRF token. Elm talks to Phoenix over JSON:
- **One write endpoint per command:** `POST /api/office-hours/book`. The controller builds the Commanded command, with the actor from the session, and dispatches it with `consistency: :strong`. It answers 200 with the fresh read model, or 422 with the scenario's error.
- **One read endpoint per read model:** `GET /api/live-sessions`. An Ash read action returns exactly the read model's fields as JSON. AshJsonApi can serve these if the project already uses it.

```elixir
# lib/edgemastery_web/controllers/api/office_hours_controller.ex
defmodule EdgemasteryWeb.Api.OfficeHoursController do
  use EdgemasteryWeb, :controller
  alias Edgemastery.Commands.BookOfficeHours

  def book(conn, %{"slotId" => slot_id}) do
    student = conn.assigns.current_user.id
    command = %BookOfficeHours{slot_id: slot_id, student_id: student}

    case Edgemastery.App.dispatch(command, consistency: :strong) do
      :ok -> json(conn, EdgemasteryWeb.Api.LiveSessionsJSON.index(Edgemastery.LiveSessions.live_sessions_for(student)))
      {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: Edgemastery.Errors.text(reason)})
    end
  end
end
```

```elm
-- assets/elm/src/Page/LiveSessions.elm
module Page.LiveSessions exposing (Model, Msg, init, update, view)

import Api.OfficeHours exposing (Slot, expectResult, slotsDecoder)
import Html exposing (Html, button, div, li, p, text, ul)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Http
import Json.Encode as E


type alias Model =
    { slots : List Slot, error : Maybe String, csrf : String }


type Msg
    = Book String
    | Booked (Result String (List Slot))


init : { slots : List Slot, csrf : String } -> ( Model, Cmd Msg )
init flags =
    ( { slots = flags.slots, error = Nothing, csrf = flags.csrf }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Book slotId ->
            ( model
            , Http.request
                { method = "POST"
                , headers = [ Http.header "x-csrf-token" model.csrf ]
                , url = "/api/office-hours/book"
                , body = Http.jsonBody (E.object [ ( "slotId", E.string slotId ) ])
                , expect = expectResult Booked slotsDecoder
                , timeout = Nothing
                , tracker = Nothing
                }
            )

        Booked (Ok slots) ->
            ( { model | slots = slots, error = Nothing }, Cmd.none )

        Booked (Err message) ->
            ( { model | error = Just message }, Cmd.none )


view : Model -> Html Msg
view model =
    div []
        [ ul [] (List.map viewSlot model.slots)
        , case model.error of
            Just message ->
                p [ class "error" ] [ text message ]

            Nothing ->
                text ""
        ]


viewSlot : Slot -> Html Msg
viewSlot slot =
    li []
        [ text slot.startsAt
        , if slot.taken then
            text " Taken"

          else
            button [ onClick (Book slot.id) ] [ text "Book" ]
        ]
```

```elm
-- assets/elm/src/Api/OfficeHours.elm (excerpt): read model LiveSessions, and errors with the scenario's text
type alias Slot =
    { id : String, startsAt : String, taken : Bool }


slotsDecoder : Decoder (List Slot)
slotsDecoder =
    Decode.list (Decode.map3 Slot (Decode.field "id" Decode.string) (Decode.field "startsAt" Decode.string) (Decode.field "taken" Decode.bool))


expectResult : (Result String a -> msg) -> Decoder a -> Http.Expect msg
expectResult toMsg decoder =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.GoodStatus_ _ body ->
                    Decode.decodeString decoder body |> Result.mapError Decode.errorToString

                Http.BadStatus_ _ body ->
                    Err (Decode.decodeString (Decode.field "error" Decode.string) body |> Result.withDefault "Something went wrong. Try again.")

                _ ->
                    Err "Couldn't reach the server. Check your connection and try again."
```

**Rules for Elm screens**
- **The server decides.** Elm may check input for quick feedback, but every rule is enforced behind the endpoint: in the aggregate (event sourced) or the Ash action (state stored).
- **Who acts comes from the session or token** on the server (`conn.assigns.current_user`), never from the JSON body.
- **JSON uses the model's names.** Request and response keys are the model's field names in camelCase (`slotId`, `startsAt`), and a read endpoint returns exactly the read model's fields.
- **Types that don't lose data:** money is a decimal string, never a `Float`; times are ISO 8601 strings; enums decode to Elm custom types, and an unknown value fails the decoder.
- **Errors keep the scenario's words.** A rejected command returns 422 with `{"error": "<the scenario's error text>"}`, and Elm reads the body with `Http.expectStringResponse` (plain `expectJson` throws the body away).
- **CSRF:** with cookie sessions, the page gets the CSRF token in its flags and sends it as `x-csrf-token` on every write.
- **One JSON fixture per scenario** in `test/fixtures/api/`, used by both the controller tests (the response must equal it) and elm-test (the decoder must accept it). A mix task copies the fixtures into a generated `tests/Fixtures.elm`.

### Tests on these stacks
- **Decisions:** `assert_decides` against the aggregate (below), one test per scenario.
- **Projections:** dispatch the Given commands with `consistency: :strong`, then read through the Ash read action.
- **Screens, LiveView:** `Phoenix.LiveViewTest`: click the trigger, and assert the scenario's result or error text.
- **Screens, Hologram:**
  - Call the page's `command/3` directly where the installed Hologram version allows building a server struct, and assert on the action it queues.
  - Cover success and error end to end with Hologram's feature tests (`Hologram.Test.setup/0` in `test_helper.exs`).
- **Screens, Elm:**
  - Controller tests (`Phoenix.ConnTest`), one per scenario: status code, and a body equal to the scenario's JSON fixture.
  - elm-test: every fixture decodes.
  - elm-program-test: the page flow with simulated HTTP responses, for success and for the 422 that shows the scenario's error.

## Steps

Send a status message at each step (see "Talking to the Build board").

1. **Pick it up.** Create the branch `{{branchPrefix}}{{slice.id}}` from `{{baseBranch}}`. Send `picked_up`.

2. **Read before you write.** Read the domain and resource for the slice's stream, if they exist, and any slice already built on the same stream. Read the screen's LiveView, the router, the test support modules and `mix.lock`. Copy the conventions you find: module naming, domain layout, how existing commands are dispatched, test helpers. Send `read`.

3. **Check the spec before writing tests.** Run the checklist in `review-spec-skill.md`, "What to look for" (5), on this slice, plus the code checks below. Stop and ask (see "Spec questions") if any of these are true:
   - an event this slice reads isn't produced anywhere in the code or the model;
   - a field name contradicts an existing one (`customerId` where the stream uses `accountId`);
   - a scenario needs a rule the spec doesn't define;
   - an event field has no source: it isn't in the command, in the stream's earlier events, or a timestamp or generated id;
   - one value has two names (`actorId` on the command, `memberId` on the event);
   - a unique value has no "taken" scenario, or a code, password or token has no wrong, expired and too-many-tries scenarios;
   - a string field should be one of a fixed list;
   - the screen's reference (`docs/design/screens/<screen>.*`) shows a button, link or number this slice doesn't cover and no other slice does;
   - a rule depends on a slice that isn't built yet, and no scenario says what holds until then;
   - a value the system works out (slug, default name, expiry) has no scenario showing how;
   - anything under "What to look for" (6) in `review-spec-skill.md`: no order when several errors apply, a limit that doesn't say what counts or what's kept, a message with a number or name missing its 0/1/many wording, work outside the aggregate without its results or storage, a repeat or restart with no answer, a missing or deleted parent, another slice that sends the same command with different rules.

   Read the slice's **Rules** list first: build from the rules, and test with the scenarios.

   Ask everything in one go, then wait. Don't write a guessed rule, even provisionally: a rule with no scenario has no test, and it tends to stay.

4. **Write the tests first,** one per scenario, keeping the scenario titles (see "Scenarios become tests"). They should fail. Send `wrote` with the test file.

5. **Build the write side.** For a state change: the command, its events and its rules on the stream's resource; the Ash action; and a migration if the resource or table is new (`mix ash.codegen <name>`). Send `wrote` per file.

6. **Build the read side.** For a state view or automation: the read-model resource and table, `projection` blocks for every event in `projection.handles`, and the event handler for automations. Projectors that a screen reads straight after a command use strong consistency, so a dispatch with `consistency: :strong` returns after the read model is updated.

7. **Wire the screen.** Add or update the LiveView: the `uiElement` dispatches the command, and the screen shows the read model. Use the screen's own wording, including the error text from `error:` scenarios. Add the route if it's new.

8. **Run everything.** Run `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test` for the new tests, then the whole suite. Fix until green. Send `tests` with counts.

9. **Open the pull request** with the template below. Send `pr_opened`. Then report CI results as `checks` while they come in.

10. **When changes are requested** (a failing check or a review comment), fix it on the same branch, rerun step 8, push, and send `wrote` / `tests` / `checks` again.

### What's in scope
- Only this slice. If a missing neighbour blocks you (an event the slice reads that nothing produces yet), ask; don't build the neighbour.
- Don't rename anything the model names. Don't refactor code outside the slice. Don't change existing events' fields. Events are kept forever, so changing their shape is a migration decision for a human.
- Never hand-edit generated files. Change the DSL and regenerate.

## Example: the write side (AshCommanded DSL)

```elixir
# lib/edgemastery/live_sessions/office_hours_slot.ex
defmodule Edgemastery.LiveSessions.OfficeHoursSlot do
  use Ash.Resource,
    domain: Edgemastery.LiveSessions,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshCommanded.Commanded.Dsl]

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

    update :book_office_hours do
      accept [:booked_by]
      validate Edgemastery.LiveSessions.Validations.SlotIsFree
      change set_attribute(:booked_at, &DateTime.utc_now/0)
    end
  end

  commanded do
    commands do
      command :book_office_hours do
        fields [:id, :student_id]
        identity_field :id
      end
    end

    events do
      event :office_hours_booked do
        fields [:id, :student_id, :coach_id, :starts_at, :booked_at]
      end
    end
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
      _ -> {:error, field: :id, message: "this slot is taken"}
    end
  end
end
```

The `error:` text in the scenario (`this slot is taken`) is the message the code returns and the LiveView shows. Keep them identical.

### When a rule needs history
Some rules depend on earlier events of the stream, such as "already taken", "only one booking at a time" or "can't cancel twice". If the installed AshCommanded runs commands through an Ash action, the record's current state can enforce the rule, as above. If the rule needs facts the record doesn't keep, set `autogenerate_handler? false` for that command. Then decide in an aggregate, with plain Commanded:

```elixir
defmodule Edgemastery.LiveSessions.OfficeHoursAggregate do
  defstruct [:slot_id, :coach_id, :starts_at, :booked_by]

  alias Edgemastery.Commands.BookOfficeHours
  alias Edgemastery.Events.{OfficeHoursSlotOpened, OfficeHoursBooked}

  def execute(%__MODULE__{slot_id: nil}, %BookOfficeHours{}), do: {:error, :slot_not_found}
  def execute(%__MODULE__{booked_by: by}, %BookOfficeHours{}) when not is_nil(by), do: {:error, :slot_taken}

  def execute(%__MODULE__{} = slot, %BookOfficeHours{} = cmd) do
    %OfficeHoursBooked{slot_id: slot.slot_id, student_id: cmd.student_id, coach_id: slot.coach_id,
                       starts_at: slot.starts_at, booked_at: DateTime.utc_now()}
  end

  def apply(slot, %OfficeHoursSlotOpened{} = e), do: %{slot | slot_id: e.slot_id, coach_id: e.coach_id, starts_at: e.starts_at}
  def apply(slot, %OfficeHoursBooked{} = e), do: %{slot | booked_by: e.student_id}
end
```

Map error atoms to the scenario's words in one place, for example `slot_taken: "this slot is taken"`. Say in the PR that this command uses a hand-written aggregate.

## Example: the read side

```elixir
# lib/edgemastery/live_sessions/live_session_entry.ex  (read model LiveSessions, own table)
defmodule Edgemastery.LiveSessions.LiveSessionEntry do
  use Ash.Resource,
    domain: Edgemastery.LiveSessions,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshCommanded.Commanded.Dsl]

  postgres do
    table "live_session_entries"
    repo Edgemastery.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :kind, :atom, constraints: [one_of: [:group_call, :office_hours]], public?: true
    attribute :starts_at, :utc_datetime, public?: true
    attribute :taken, :boolean, default: false, public?: true
    attribute :booked_by, :uuid, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  commanded do
    projections do
      # "OfficeHoursSlotOpened → add a free slot"
      projection :office_hours_slot_opened do
        action :create
        changes &%{id: &1.id, kind: :office_hours, starts_at: &1.starts_at}
      end

      # "OfficeHoursBooked → mark the slot taken"
      projection :office_hours_booked do
        action :update
        changes &%{taken: true, booked_by: &1.student_id}
      end
    end
  end
end
```

Write one projection per entry in the slice's `projection.handles`, and quote the `does` text from the spec as a comment above it. Read models are thrown away and rebuilt from events, so they must never be the only place a fact lives.

## Scenarios become tests

Each scenario becomes one test, using the scenario's title as the test name, so the board can match tests to scenarios. Given → events that already happened. When → the command, or `query <ReadModel>`. Then → the events emitted, `error: …`, or what the read model contains.

If the project has no helper for this yet, add one once at `test/support/event_model_case.ex`:

```elixir
defmodule Edgemastery.EventModelCase do
  @moduledoc "Given/When/Then for slices: aggregate decisions without an event store, read models through the app."
  use ExUnit.CaseTemplate
  import ExUnit.Assertions

  using do
    quote do
      import Edgemastery.EventModelCase
    end
  end

  @time_fields ~w(booked_at opened_at recorded_at inserted_at updated_at)a

  @doc "Given events, when a command: assert the events or the error the aggregate decides."
  def assert_decides(aggregate, given, command, expected) do
    state = Enum.reduce(given, struct(aggregate), &aggregate.apply(&2, &1))

    case {aggregate.execute(state, command), expected} do
      {{:error, reason}, {:error, want}} -> assert reason == want
      {result, {:error, want}} -> flunk("expected error #{inspect(want)}, got #{inspect(result)}")
      {result, events} -> assert strip(List.wrap(result)) == strip(List.wrap(events))
    end
  end

  defp strip(events), do: Enum.map(events, &Map.drop(&1, @time_fields))
end
```

A state change, tested as a decision:

```elixir
defmodule Edgemastery.LiveSessions.BookOfficeHoursTest do
  use ExUnit.Case, async: true
  use Edgemastery.EventModelCase
  alias Edgemastery.LiveSessions.OfficeHoursAggregate, as: Slot
  alias Edgemastery.Commands.BookOfficeHours
  alias Edgemastery.Events.{OfficeHoursSlotOpened, OfficeHoursBooked}

  @slot "5f0c…-s1"; @coach "…-c1"; @student "…-u2"; @other "…-u3"

  test "Free slot booked" do
    assert_decides Slot,
      [%OfficeHoursSlotOpened{slot_id: @slot, coach_id: @coach}],
      %BookOfficeHours{slot_id: @slot, student_id: @student},
      [%OfficeHoursBooked{slot_id: @slot, student_id: @student, coach_id: @coach}]
  end

  test "Already taken" do
    assert_decides Slot,
      [%OfficeHoursSlotOpened{slot_id: @slot}, %OfficeHoursBooked{slot_id: @slot, student_id: @other}],
      %BookOfficeHours{slot_id: @slot, student_id: @student},
      {:error, :slot_taken}
  end
end
```

When the rule lives in an Ash action instead of an aggregate, write the same scenarios through the router. Set the given state by dispatching the commands that produce the Given events, dispatch the When command with `consistency: :strong`, and assert on `{:error, …}` or on the record.

A state view, tested through the read model:

```elixir
test "Taken slot shows as taken to others" do
  open_slot!(id: @slot)                       # dispatches OpenOfficeHoursSlot
  book!(slot: @slot, student: @other)         # dispatches BookOfficeHours, consistency: :strong
  [entry] = Edgemastery.LiveSessions.list_live_sessions!(viewer_id: @student)
  assert entry.taken
end
```

The screen gets one LiveView test per success and error scenario:

```elixir
test "Already taken: the student sees the error", %{conn: conn} do
  slot = slot_booked_by!(@other)
  {:ok, view, _html} = live(log_in(conn, @student), ~p"/live")
  view |> element("#slot-#{slot.id} button", "Book") |> render_click()
  assert render(view) =~ "this slot is taken"
end
```

`empty` scenarios assert the screen's empty-state text. `edge` scenarios test the boundary itself: the same command twice, the last seat, a limit.

## Files for a slice

Follow the repo's layout if it has one. Otherwise:

| Pattern | Files |
|---|---|
| state_change | `lib/<app>/<domain>/<resource>.ex` (command, event, action), `lib/<app>/<domain>/validations/*.ex`, `priv/repo/migrations/*` if the table is new, `lib/<app>_web/live/<screen>_live.ex`, `test/<app>/<domain>/<slice>_test.exs`, `test/<app>_web/live/<screen>_live_test.exs` |
| state_view | `lib/<app>/<domain>/<read_model>.ex` (resource and projections), migration, a code interface on the domain (`list_<read_model>`), the LiveView, tests |
| automation | `event_handlers` on the resource that reacts, or a webhook controller or Oban job that dispatches the command, plus tests. A webhook command records `providerEventId` so that a repeat delivery does nothing. |

## Spec questions

When step 3 finds gaps, post them together as one message on the slice (and in the pull request or issue, if there is one), send `blocked`, and wait. Number the questions. For each, say what's missing, why the code needs it, and a suggested answer in the model's terms (a scenario with the exact error text, a field to drop or rename, a list of values):

```text
Spec questions for rename-workshop:
1. hostName: WorkshopRenamed has a hostName that RenameWorkshop doesn't take, so it would be recorded empty. Drop it from the event, or say where it comes from?
2. Taken address: no scenario covers an address another workshop already uses. Suggested: "Address already taken" → error: That address is taken. Try another.
3. level is a plain string. Should the model list the allowed levels?
```

The answers come back as a change to `docs/model.json` (made in the builder and exported). Pull it, re-read the slice, and carry on from step 4. If the person answers in chat instead, ask them to put it in the model first, so the next slice and the reviewer see the same thing.

## When the spec and the code disagree

Don't guess silently. Post a question on the slice (it shows as a comment in the builder's Discussion), send `blocked`, and wait:

```json
{"type": "blocked", "slice": "book-office-hours", "question": "OfficeHoursBooked reads coachId, but the slot stream doesn't record a coach until OfficeHoursSlotOpened exists, and that slice isn't built yet. Build Open office hours slot first, or should I stub it?", "options": ["Build open-office-hours-slot first", "Stub the slot in tests only"]}
```

Ask when an event the slice reads isn't produced anywhere, when a name or field contradicts existing code, or when a scenario needs a rule nobody wrote down. Don't ask about naming inside your own code, file layout, or anything the conventions you read already answer.

## Talking to the Build board

Send one JSON line per step. The board moves the card between columns and fills its activity log from these.

```json
{"type": "picked_up", "slice": "book-office-hours", "branch": "em/book-office-hours"}
{"type": "read", "slice": "book-office-hours", "note": "Read the slice, its scenarios and the existing code"}
{"type": "wrote", "slice": "book-office-hours", "file": "lib/edgemastery/live_sessions/office_hours_slot.ex"}
{"type": "tests", "slice": "book-office-hours", "passed": 4, "failed": 0, "total": 4}
{"type": "pr_opened", "slice": "book-office-hours", "number": 236, "url": "https://github.com/acme/edgemastery/pull/236", "files": 5, "additions": 327, "deletions": 21}
{"type": "checks", "slice": "book-office-hours", "passed": 6, "failed": 0, "running": 1, "total": 7, "failing": []}
{"type": "blocked", "slice": "book-office-hours", "question": "…"}
```

`failing` lists the scenario titles of failing tests. That's how the board shows ✕ against the right scenario.

## Pull request template

```markdown
## Book office hours

A student on a tier that includes coaching books a free office hours slot.

**Slice** `book-office-hours` · state change · screen: Live sessions · stream: `OfficeHours`

### Model → code
| Model | Code |
|---|---|
| Command `BookOfficeHours` | `OfficeHoursSlot` · `command :book_office_hours` → action `:book_office_hours` |
| Event `OfficeHoursBooked` | `OfficeHoursSlot` · `event :office_hours_booked` |
| Rule "this slot is taken" | `Validations.SlotIsFree` |
| Screen: Book button | `LiveSessionsLive.handle_event("book", …)` |

### Scenarios → tests
| Scenario | Kind | Test |
|---|---|---|
| Free slot booked | success | `test/edgemastery/live_sessions/book_office_hours_test.exs` "Free slot booked" ✓ |
| Already taken | error | same file, "Already taken" ✓ · LiveView test ✓ |

### Notes for the reviewer
- New table `office_hours_slots` (migration included).
- Questions asked on the slice: none.

Built from the event model by the Event-Model Builder.
```

## Done means
- Every scenario has a passing test with the same title, and the full suite is green.
- Every name in the code matches the model: command, events, read model, and fields in snake_case.
- Every rule in the code has a scenario in the model, and no spec question is still open.
- Every error message on screen matches the `error:` text in its scenario.
- No generated files were edited by hand, there are no warnings, and the code is formatted.
- The pull request is open with the template filled in, and `checks` were reported.

When the PR is merged, the builder marks the slice Done on the board.
