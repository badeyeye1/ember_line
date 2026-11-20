# Emberline

Emberline turns a clickable prototype into an Event Modeling spec, then builds the spec one slice at a time.
This repo is Emberline built with itself: `docs/model.json` is its event model, exported from the Event-Model Builder prototype.

## Source of truth

- `docs/model.json` is the spec. Every command, event, read model, screen and Given/When/Then scenario comes from it.
- Don't invent events, fields or slices that aren't in the model. If the code needs something the model lacks, stop and say so. Propose the model change, and change the code only after the model is updated and re-exported.
- Names in the code match the model exactly: `CreateProject` → `ProjectCreated` → `ProjectList`.
- `docs/skills/` holds the skills from the Event-Model Builder kit. Use them:
  - `build-slice-skill.md`: event-sourced slices
  - `build-slice-state-stored-skill.md`: state-stored slices
  - `plan-build-order-skill.md`: what to build next
  - `check-pr-skill.md`: before opening a pull request
  - `change-event-safely-skill.md`: before changing an event that has already shipped
  - `sync-model-with-code-skill.md`: when the code and the model drift apart

## Stack

- Elixir and Phoenix LiveView
- Ash 3 with AshPostgres; AshAuthentication for accounts
- Commanded with the EventStore (Postgres) for event-sourced streams
- `Commanded.Projections.Ecto`, or Ash resources over projection tables, for read models
- Oban for background jobs
- OTP app: `:ember_line`; modules: `EmberLine`, `EmberLineWeb`

## Persistence: mixed

| Stream | Storage | How |
|---|---|---|
| Project | **event sourced** | Commanded aggregate, events in the EventStore, read models built by projections |
| Slice | **event sourced** | Commanded aggregate, events in the EventStore, read models built by projections |
| Feature | **event sourced** | Commanded aggregate, like Project and Slice |
| Account, Member, Notification, Thread, Workspace | state stored | Ash resources on AshPostgres tables; Ash actions write directly |

- **Account** is the AshAuthentication `User` resource. Don't event source it.
- **Building, screens and boards** are recorded in the Project and Slice streams for now. Don't add Build or Screen streams unless the model adds them.
- Before building a slice, check its storage on the slice page or in `model.json`, then pick the matching build-slice skill.
- When a state-stored slice must trigger something in an event-sourced stream, use an Ash `after_action` hook or an outbox event in the same transaction. Never call it as a separate step that can fail on its own.
- Commands whose result the next screen reads straight away are dispatched with `consistency: :strong`.

## Event rules

- Events are named in the past tense and are permanent. Never change or delete a shipped event; follow `change-event-safely-skill.md` and use an upcaster or a new version.
- Events carry ids, not personal data. Refer to `account_id`; never put emails or names in events.
- One aggregate per stream: `EmberLine.Modeling.Project`, `EmberLine.Modeling.Slice` and `EmberLine.Modeling.Feature`.
- Aggregates decide (`execute/2`) and record (`apply/2`). They don't query the database, call other services or read the clock. Time and ids arrive in the command.

## Folder layout

```
lib/ember_line/
  accounts/            # Ash: User (AshAuthentication), Workspace, Member
  collaboration/       # Ash: Thread, Notification
  modeling/            # event sourced
    project/           #   aggregate, commands, events
    slice/             #   aggregate, commands, events
    projections/       #   read models
    router.ex          #   Commanded router
  commanded_app.ex
lib/ember_line_web/live/  # one LiveView per screen in the model
test/ember_line/modeling/ # one test file per slice, written from its scenarios
```

## Screens look like the prototype

- `docs/design/` is the visual spec: a desktop and phone PNG plus the markup for every screen in the model, the
  design tokens and the prototype's CSS. Read `docs/design/README.md` before building any screen.
- A slice's screen is done only when it matches `docs/design/screens/<screen>.*`: same layout, components, spacing,
  colours and copy. Generic generator forms (`<.simple_form>`, unstyled `<.input>`, the default Phoenix pages) don't count.
- Use the shared components in `lib/ember_line_web/components/ui.ex` and the theme in `assets/css/app.css`. Add a
  component there rather than styling one screen by hand. Don't add colours that aren't in `docs/design/tokens.css`.
- Each pull request with a screen includes screenshots at 1440 and 390 px wide next to the reference.

## Working on a slice

1. Read the slice in `docs/model.json`: its command, events, read model, screen and scenarios.
   Each slice belongs to the feature named in `model.json`. A pull request only touches one feature's slices.
2. Check the spec before writing tests: run `docs/skills/review-spec-skill.md` "What to look for" (5) and (6) on the slice, and read its Rules list. Every event field needs a source, one value one name, "taken" cases for unique values, wrong/expired/too-many-tries for codes and passwords, closed lists for fixed sets, a slice for everything on the screen's reference, and a scenario for anything that waits on a later slice. If anything is missing, post numbered spec questions with suggested answers and stop. Answers arrive as a change to `docs/model.json`; pull it and re-read the slice.
3. Turn each Given/When/Then scenario into a test before writing any code: Given = earlier events, When = the command, Then = the new events or the error.
4. Build only that slice: command, aggregate handling, event, projection or read model, screen, and its router entry.
   Build the screen from `docs/design/screens/<screen>.*` using the shared UI components.
5. Run `mix format`, `mix compile --warnings-as-errors`, `mix credo --strict` and `mix test`. All must pass.
6. Check the work against `check-pr-skill.md`, then open a pull request that names the slice, lists its scenarios, and lists any spec questions with the model change that answered each.

One slice per pull request. Don't refactor other slices in the same pull request.

## Commands

```bash
mix setup                                          # deps, database, EventStore
mix event_store.create && mix event_store.init     # first run only
mix ash.codegen <name> && mix ash.migrate          # after changing an Ash resource
mix test
mix phx.server
```

## Don'ts

- Don't write a rule, validation or error message that no scenario describes, not even provisionally. Ask a spec question instead.
- Don't edit `docs/model.json` by hand. Change it in the builder and re-export it.
- Don't put Phoenix or Ash code inside aggregates.
- Don't read the EventStore directly from LiveViews. Use read models.
- Don't add dependencies without saying why in the pull request.
