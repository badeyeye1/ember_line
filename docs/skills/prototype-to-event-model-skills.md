---
name: prototype-to-event-model
description: Turn a clickable app prototype (HTML files, screenshots or a .zip) into an event model spec — screens, slices, commands, events, projections, read models, business outcomes and Given/When/Then scenarios. Use when someone wants a spec, event model or Event Modeling board derived from a prototype or an existing codebase.
---

# Prototype → Event Model spec

These are the Claude skills the Event-Model Builder uses to derive a spec from a prototype. Each one is a single structured call that returns JSON only. The builder chains them into a pipeline, and its own code does the deterministic work between calls (splitting, merging, tidying).

| # | Skill | When it runs | Returns |
|---|-------|--------------|---------|
| 0 | [Event Modeling rules](#0-event-modeling-rules-shared) | Included in every modelling prompt | — |
| 1 | [Scan a large prototype](#1-scan-a-large-prototype) | Source is too big for one request | Notes per part |
| 2 | [Outline the whole app](#2-outline-the-whole-app-pass-1) | Always | Screens, slices, streams, outcomes |
| 3 | [Fill coverage gaps](#3-fill-coverage-gaps) | Some screens got no slices | Extra slices |
| 4 | [Detail one screen](#4-detail-one-screen-pass-2) | Once per screen | Stories, fields, projections, scenarios |
| 5 | [Map how to open each screen](#5-map-how-to-open-each-screen) | One file renders several screens | Click paths |
| 6 | [Read an existing codebase](#6-read-an-existing-codebase) | Project points at code | Model of what's already built |
| 7 | [Illustrate a scenario](#7-illustrate-a-scenario) | A scenario is opened | Edits to the real screen |

Placeholders in the prompts below are written `{{like_this}}`.

---

## Pipeline

```
prototype files ──► clean ──► fits in one request (≤170,000 chars)? ─ no ──► split into one HTML page per screen (crawl)
                                    │                                        └─► or Skill 1 per 115,000-char part
                                    ▼ yes
                           Skill 2 Outline (whole app)
                                    │  + existing model, if the project has one
                                    ▼
                           Skill 3 Coverage (screens with no slices, 12 at a time)
                                    │
                                    ▼
                    merge with existing model (keep ids, status, code, fields)
                                    │
                                    ▼
                           Skill 4 Detail (per screen, 2 in parallel)
                                    │
                                    ▼
                    tidy: one shape per event, fields from scenarios,
                    drop dangling streams/outcomes, flag orphan events
```

### Preparing the input
- **Clean the HTML.** Keep the prototype's own inline scripts: in script-driven prototypes (React, routers) that's where the screens are. Drop library bundles (any inline script whose lines average over 400 characters, or that starts with a React, Vue, jQuery, Babel or Tailwind banner). Drop `<style>` blocks, collapse inline SVG to `<svg/>`, and cut `data:` URIs longer than 200 characters.
- **Size limits.** Up to 170,000 characters goes in one request. Above that, split it:
  - **Preferred: split into pages.** Open the running prototype in a sandbox and crawl every route, hash link and role or persona switch. Save one HTML snapshot per distinct screen, deduplicated by content. Then derive from those pages, one screen per page, instead of the original file.
    - The preview frame gets `<base href="about:srcdoc">`, so a prototype that changes its own address (`location.replace("#signin")`, router pushes) stays inside the frame.
    - Only real persona pickers ("view as", "role", "user", "acting as") count as roles. Project, workspace, theme and filter pickers don't.
    - It follows `#` links (hidden ones included) and the nav, sidebar and header buttons, and names each page by its first *visible* heading.
    - Apps behind a sign-in can help: when storage isn't available (as in a sandboxed preview), start a demo session. A hidden `<nav hidden>` site map of `#` links lists every page. The builder does both for itself, which is how it can derive its own model from its own file.
  - **Fallback: scan in parts.** Cut the source into parts of 115,000 characters or less, run Skill 1 on each, and pass the combined notes (capped at 150,000 characters) to Skill 2.
- **Screenshots** are attached as images, listed in order in the prompt.

### After the model comes back (done in code, not by Claude)
- **Merge with an existing model.** Match slices by id, or by name ignoring case. Keep the old status, code links, scenarios, and the command, event and read-model fields when the new outline has none. Keep slices the prototype doesn't show. The new outcomes replace the old ones, and an old outcome survives only for slices that no new outcome covers.
- **Never merge sample or template content** into another project.
- **One shape per event:** every place an event appears gets the combined field list, with the producer's fields first.
- **Recover missing fields from scenarios:** `CreateAccount(customerId: c-1, plan: free)` gives `customerId: uuid` and `plan: enum(free|…)`. Types come from the example values first, then from the field name.
- **Drop dangling references:** streams for events that no longer exist, outcome links to deleted slices, and outcomes that duplicate earlier ones.
- **Flag orphan events** (read but never produced), and offer to add an automation slice that receives them from outside the app.

---

## Event sourced or state stored

Deriving the model is the same either way. Event Modeling describes behaviour (what people ask for, what happens, what they see), not how it's stored. The project's storage setting (event sourced, state stored, or mixed per stream) is used later, by the build, check, change and example-data skills.

- **Events are named the same in both cases.** In a state-stored app, an event is the state change an action makes (`RsvpConfirmed` is "an RSVP row was created with status confirmed"), so it's still a past-tense fact.
- **Reading a codebase** (skill 6) records how each slice is built in `code.style` (`event_sourced` or `crud`). The builder turns that into the project's storage setting per stream, unless someone has already chosen it, in which case it's shown as "Reading the code found: …".
- **Projections** are still modelled for state views. On a state-stored stream, the board labels that lane **Queries**, and the build skill turns it into a read action instead of a projector.

---

## 0. Event Modeling rules (shared)

Included in Skills 2, 3, 4 and 6.

```text
Event Modeling rules (Adam Dymitruk's method):
- A slice is exactly one pattern. "state_change": a UI action sends a command that emits one or more events. "state_view": a read model built from events and shown on a screen. "automation": a background processor reacts to events, reads a todo-list read model, sends a command, emits events.
- Commands are imperative PascalCase (ConfirmRsvp). Events are past-tense PascalCase (RsvpConfirmed). Read models are nouns (AttendeeList). Fields are short camelCase with an Ecto type, written "name: type", e.g. "workshopId: uuid", "capacity: integer", "startsAt: utc_datetime", "price: decimal", "side: enum(long|short)".
- The same business fact is the same event everywhere in the app. Do not model pure navigation (opening a page) as a command.
- Group events into streams: the aggregate or entity they belong to (e.g. "Order", "Customer"). Name the identity field after its stream and use that one name everywhere: events in the "Account" stream carry "accountId", not "customerId" or "userId".
- Every event a slice reads must be produced by some slice. Facts that arrive from outside the app (payment provider webhooks, emails, schedulers, devices) get an "automation" slice that receives them and produces the event.
- Keep the write side and the read side apart: a command only changes state by emitting events; a read model is only built by a projection that handles events. A command never reads a read model directly and a read model is never written by a command.
- Every event field comes from the command, from earlier events of the same stream, or from the system (generated ids, timestamps). A value the system works out (a slug, a default name, an expiry) gets a scenario that shows the rule. Don't add a field nothing supplies.
- One name per value: the command field and the event field for the same value have the same name. Who did it is "<verb>By" on both (savedBy, deletedBy).
- A field that can only be one of a set is an enum listing the set, e.g. "plan: enum(free|team|business)", never a plain string.
```

### Reach rules (shared by Skills 2 and 5)

```text
For each screen, "reach" says how to open it in the RUNNING prototype, starting from what that file shows on first load, by reading its code (routers, state, onClick handlers).
"steps" is a list of STEP objects, each one of:
  {"click":"exact visible text of the button, link, tab or menu item to click"}
  {"fill":{"field":"label, placeholder or name of the input","value":"a valid value"}} (for required fields before a submit)
  {"hash":"#/route"} (only for hash routers)
  {"css":"a CSS selector"} (only when the element has no visible text, e.g. an icon button)
  {"wait":500}
Use [] for the screen shown on first load, and for screens that are their own file. For a modal or dialog, include the click that opens it.
```

---

## 1. Scan a large prototype

**Runs** once per part when the cleaned source is over 170,000 characters and wasn't split into pages. Parts run two at a time, and their notes feed Skill 2.

```text
You are helping build an event model of an app prototype that is too large to read in one request. This is part {{i}} of {{n}} of its source ({{file, lines from–to}}). Other parts are read separately, so note everything useful here even if it is incomplete.
Extract compact notes:
- "navigation": how screens are switched (hash routes, router, state variables, tabs) and any role, persona or sign-in switch that changes which screens exist. Give exact route names and option labels.
- "screens": every screen, view, route, tab or dialog defined or rendered in this part.
- "automations": behaviour that runs by itself (timers, reminders, notifications, auto-assignments).
- "data": the main entities and the fields used here.
- "rules": business rules and validations, with their error messages.
Use the exact visible text of buttons, links, tabs and fields. Keep the whole answer under 3,000 words.
Reply with ONLY one JSON object, no other text:
{"navigation":string,
 "screens":[{"name":string,"route":string,"roles":[string],"how":string (how a person reaches it: role to pick, exact link or button text, route),"shows":[string],"actions":[{"ui":string (exact text),"does":string,"fields":[string]}]}],
 "automations":[string],"data":[{"entity":string,"fields":[string]}],"rules":[string]}

SOURCE PART {{i}} OF {{n}}:

{{part_text}}
```

---

## 2. Outline the whole app (pass 1)

**Runs** once for the whole prototype. It returns the map only: names, no fields and no scenarios. The input is the source, the split pages, or the scan notes, plus any screenshots.

```text
You are an expert in Event Modeling. You get a WHOLE application prototype: one or more HTML files and/or screenshots.
1. Identify every distinct screen: a page, route, view, tab, modal, or clearly different UI state. One HTML file can hold several screens (sections, hidden views, routes in script, dialogs).
2. Lay out the event model as a timeline of slices in the order people move through the app, across all screens. Include automations the UI implies (emails, expiry, promotions, syncs).
{{EVENT_MODELING_RULES}}
{{REACH_RULES}}
BUSINESS OUTCOMES: group the slices into 3 to 12 outcomes the business cares about (e.g. "Members secure a seat", "Coaches review every trade"). An outcome is usually delivered by several slices and often spans several screens and roles; a slice can serve more than one outcome; every slice belongs to at least one. Name outcomes as results, not features.
COVERAGE: every screen gets at least one slice: a state_view for what it shows, and a state_change for each action it offers (forms, buttons that change something). The only exception is a screen of purely static content (legal text, marketing copy with no data and no actions): set "static": true on it and give it no slices. Screens several roles see can share slices. Return up to 150 slices; keep names short so they fit.
Reply with ONLY one JSON object, no other text:
{"app":{"name":string,"summary":string (one sentence)},
 "screens":[{"id":string (short kebab-case),"name":string,"summary":string (one sentence),"source":string (the file or screenshot name it comes from, exactly as given),"static":boolean,"reach":{"steps":[STEP]}}],
 "streams":{"EventName":"StreamName"},
 "outcomes":[{"id":string (kebab-case),"name":string (a business result in plain words, e.g. "Members secure a seat"),"slices":[slice ids that together deliver it]}],
 "slices":[{"id":string (short kebab-case, unique),"name":string,"pattern":"state_change"|"state_view"|"automation","screen":string (screen id),"actor":string (who uses it, e.g. "Customer"; "Automation" for automations),"uiElement":string (the element that triggers or shows it),"command":string|null,"produces":[string],"reads":[string],"readModel":string|null}]}
```

**Appended when screenshots are attached:**

```text
Screenshots attached, in this order: 1. {{name}}; 2. {{name}}; …
```

**Appended when the project already has a model** (read from code or an earlier derive). Sample or template slices are never included.

```text
THIS PROJECT ALREADY HAS A MODEL (from its codebase or earlier work). Keep these slices: reuse their exact ids and names (and their command, event and read model names) wherever the prototype shows the same behaviour, and add new slices only for what isn't there yet.
{{existing slices as JSON: id, name, pattern, status, command, produces, reads, readModel — capped at 60,000 chars}}
```

Then comes `PROTOTYPE SOURCE:` followed by the cleaned source, the split pages or the scan notes.

---

## 3. Fill coverage gaps

**Runs** after Skill 2 for any non-static screen with no slices, 12 screens per call. Each screen gets a short outline of its own page or notes, up to 3,000 characters.

```text
You are an expert in Event Modeling. An event model was drafted for an app, but these screens got no slices. Add slices for them.
{{EVENT_MODELING_RULES}}
For each screen: a state_view for the data it shows and a state_change for each action it offers. Reuse existing event, command and read model names where the same business fact is involved; add new ones only when needed. If a screen is purely static content (legal text, marketing copy with no data and no actions), list its id in "static" instead.
Reply with ONLY one JSON object, no other text:
{"slices":[{"id":string (new, unique, kebab-case),"name":string,"pattern":"state_change"|"state_view"|"automation","screen":string (screen id),"actor":string,"uiElement":string,"command":string|null,"produces":[string],"reads":[string],"readModel":string|null,"outcome":string (id of an existing business outcome it serves, or the name of a new one)}],"static":[string],"streams":{"EventName":"StreamName"}}

SCREENS WITHOUT SLICES:
- id "{{screen.id}}": {{screen.name}} ({{screen.summary}})
{{that screen's page outline or scan notes}}

EXISTING MODEL:
{{streams, outcomes and slice outlines as JSON — capped at 120,000 chars}}
```

The builder inserts each new slice after the last slice on an earlier or the same screen, so the timeline order holds.

---

## 4. Detail one screen (pass 2)

**Runs** once per screen that has new slices, two screens at a time.
- **Skipped** for slices carried over from code or an earlier derive that already have scenarios and fields.
- **Context:** the screen's own page or source and its screenshots. When the source was scanned in parts, it gets the app-wide navigation, rules, data and automation notes instead.

```text
You are an expert in Event Modeling. Below is the outline of an event model for a whole app, and the source of the prototype.
Fill in the detail for every slice whose "screen" is "{{screen.id}}" ({{screen.name}}). Keep every slice id, command, event and read model name EXACTLY as in the outline.
{{EVENT_MODELING_RULES}}
For each slice give:
- "story": one plain-language sentence a business person understands, with no technical names.
- fields for the command, each produced and read event, and the read model, taken from what the screen shows or collects.
- 2 to 6 specs covering different scenarios: "success" (happy path), "error" (business rule violations), "empty" (no data yet) where it applies, and at least one "edge" case (boundaries, repeats, races, duplicates).
- Always include these when they apply, even if the screen doesn't show them: a value that must be unique gets an "already taken" error with the words to show; a code, password or token gets "wrong", "expired" (say how long it lasts) and "too many tries" (say how many); a rule that needs something a later part of the app adds (roles, plans) says what holds until then.
- Every button, link, form and number on this screen is covered by a slice: its trigger ("uiElement") or a read-model field.
Specs are Given/When/Then. given: prior events as strings, e.g. "OrderPlaced(total: 40)" or "ItemAdded × 3"; empty list if nothing happened. when: the command call, e.g. "PlaceOrder(cartId: c-1)", or "query ReadModelName(...)" for views. then: resulting events or read-model states as strings; errors start with "error: ".
Reply with ONLY one JSON object, no other text:
{"slices":[{"id":string,"story":string,"uiElement":string,
  "command":{"name":string,"fields":[string]}|null,
  "produces":[{"name":string,"fields":[string]}],
  "reads":[{"name":string,"fields":[string]}],
  "projection":{"name":string (e.g. AttendeeListProjection),"handles":[{"event":string,"does":string (how this event changes the read model, e.g. "add member to list")}]}|null (required for every slice that has a read model; null for state_change slices),
  "readModel":{"name":string,"fields":[string]}|null,
  "specs":[{"kind":"success"|"error"|"empty"|"edge","title":string,"given":[string],"when":string,"then":[string]}]}]}

OUTLINE:
{{outline JSON from Skill 2: app, screens, streams, slices}}

{{THIS SCREEN'S PAGE … | NOTES SHARED ACROSS THE APP … | PROTOTYPE SOURCE …}}
```

**Merging the result:**
- Names stay as the outline gave them.
- Fields, story, UI element, projection and scenarios are taken from the reply.
- Event fields are matched by event name.
- A screen whose call fails keeps its outline, and is reported so it can be derived again.

---

## 5. Map how to open each screen

**Runs** on demand when one live HTML file draws several screens and the preview doesn't know how to reach them. The builder replays the steps in a sandboxed iframe to take each screenshot.

```text
You are given a prototype's source code (or notes extracted from it) and the list of screens found in it.
{{REACH_RULES}}
Reply with ONLY one JSON object, no other text: {"screens":[{"id":string,"reach":{"steps":[STEP]}}]}

SCREENS:
{{[{id, name, summary, source}] as JSON}}

{{PROTOTYPE SOURCE … | PROTOTYPE NOTES …}}
```

---

## 6. Read an existing codebase

Use this when the project points at a local folder or GitHub repository. It works for CRUD systems too, not only event-sourced ones. It runs in two steps: a scan per part, two at a time, then one map. The result is merged with any prototype-derived model, with slices that already exist in code marked Done or In progress.

### 6a. Scan a code part

```text
You are reading part {{i}} of {{n}} of an application's codebase to recover an EVENT MODEL of what it does. The system may or may not be event sourced: it could be CRUD (Rails, Django, Phoenix with Ecto, Laravel, .NET, Node), a front end talking to an API, or Commanded/Ash. Derive the model from the SCREENS (templates, LiveViews, Hologram pages and components, Elm modules, pages, components) and what they do; use the backend only to name things, find fields and rules.
For a non-event-sourced system, translate: every form submit, button action, mutation or write endpoint is a COMMAND (in Hologram, client action/3 handlers are UI only; the server command/3 handlers that write are the COMMANDS; in Elm, a Msg that sends an HTTP request to a write endpoint marks a COMMAND, and the endpoint behind it says what it does); the state change it causes (insert, update, delete, status change, email sent) is an EVENT named in the past tense (e.g. a POST /rsvps that inserts an Rsvp row becomes RsvpConfirmed); every query or list a screen shows is a READ MODEL; scheduled jobs, callbacks, webhooks and background workers are AUTOMATIONS.
Note everything in this part even if incomplete. Give fields with Ecto-style types ("name: type": string, integer, decimal, boolean, uuid, date, utc_datetime, map, list, enum(...)).
Reply with ONLY one JSON object, no other text:
{"commands":[{"module":string,"fields":[string],"aggregate":string,"emits":[string],"errors":[string]}],
 "events":[{"module":string,"fields":[string],"aggregate":string}],
 "aggregates":[{"module":string,"identity":string,"rules":[string]}],
 "projectors":[{"module":string,"handles":[{"event":string,"does":string}],"readModel":string}],
 "readModels":[{"module":string,"table":string,"fields":[string]}],
 "automations":[{"module":string,"kind":"process_manager"|"event_handler","reactsTo":[string],"dispatches":[string]}],
 "screens":[{"module":string (the file or component),"route":string,"name":string,"dispatches":[string] (actions it triggers, as commands),"reads":[string] (data it shows),"roles":[string],"fields":[string] (inputs on its forms)}],
 "writes":[{"where":string (controller/handler/mutation),"command":string,"event":string (past tense),"fields":[string],"rules":[string],"errors":[string]}],
 "tests":[{"file":string,"title":string,"given":[string],"when":string,"then":[string]}]}

CODE PART {{i}} OF {{n}}:

{{code_text}}
```

### 6b. Map the notes to a model

```text
You are an expert in Event Modeling. Below are notes extracted from an existing codebase. Turn them into an event model of what is ALREADY BUILT. The system may not be event sourced: model it as if it were, deriving commands from what screens let people do, events from the state changes those actions cause (past tense), and read models from what screens show.
{{EVENT_MODELING_RULES}}
- One slice per command (state_change), per read model shown on a screen (state_view), and per process manager or event handler that dispatches (automation).
- Use the code's own names where they exist (without module paths); otherwise name commands and events from what the screen does. Streams are the aggregates, or the main entity/table being changed.
- Screens are the pages, templates, LiveViews or components (source = that file or route). A slice no screen uses goes on a screen called "No screen yet".
- "status": "done" when the behaviour exists end to end (screen, write or query, storage) and tests cover it; otherwise "in_progress". It doesn't need to be event sourced to count as done.
- In "code", say where it lives: "command" = the handler/controller action/mutation, "aggregate" = the entity or aggregate, "projector" = the query or projector, "readModel" = the table/schema/view, "liveView" = the screen file, and add "style": "event_sourced" or "crud".
- Scenarios come from the tests when they exist; otherwise write 1-3 from the aggregate rules and error atoms.
- Group slices into 3-12 business outcomes (results the business cares about, spanning screens).
Reply with ONLY one JSON object, no other text:
{"app":{"name":string,"summary":string},
 "screens":[{"id":string,"name":string,"summary":string,"source":string}],
 "streams":{"EventName":"AggregateName"},
 "outcomes":[{"id":string,"name":string,"slices":[slice ids]}],
 "slices":[{"id":string,"name":string,"pattern":"state_change"|"state_view"|"automation","screen":string,"actor":string,"uiElement":string,"story":string,"status":"done"|"in_progress",
   "command":{"name":string,"fields":[string]}|null,"produces":[{"name":string,"fields":[string]}],"reads":[{"name":string,"fields":[string]}],
   "projection":{"name":string,"handles":[{"event":string,"does":string}]}|null,"readModel":{"name":string,"fields":[string]}|null,
   "specs":[{"kind":"success"|"error"|"empty"|"edge","title":string,"given":[string],"when":string,"then":[string]}],
   "code":{"style":"event_sourced"|"crud","command":string,"aggregate":string,"projector":string,"readModel":string,"liveView":string,"files":[string]}}]}

{{combined scan notes as JSON, capped at 190,000 chars}}
```

---

## 7. Illustrate a scenario

This makes each Given/When/Then visible on the real screen, so the business can check it. It runs in three steps:
1. **Edit the real screen:** Claude returns a few edits to the screen's own HTML, and the builder applies them.
2. **Check the result:** Claude gets back all the text now on screen and lists anything that doesn't follow from Given and Then.
3. **Fix:** the builder applies that check's edits.

When there's no HTML for the screen, Claude draws a standalone mock instead.

### Shared screen rules

```text
Show the single moment the scenario is about:
- state change, success: the screen right after the When: the confirmation the person sees and the data as it now stands.
- state change, error: the error message the person sees, next to the control that triggered it; data unchanged.
- state view: the data exactly as the Given events imply (counts, rows, labels).
- empty: what the screen shows when there is no data yet.
- edge: the boundary case made visible (last seat, duplicate, limit reached).
Use the screen's own wording style. Use concrete values from the scenario.
CONSISTENCY (most important): after your edits, EVERY value, count, list and status on the screen must follow from the Given events and nothing else. The screen you are given shows some other situation, so:
- remove every row, card, count, badge or chart that depends on events not in Given;
- if Given is empty or the scenario is an empty state, nothing that depends on data may remain: no items, no counts like "16 of 20", no seat bars; show the screen's empty-state message instead (write one in the page's style if it has none);
- recompute every number from Given (e.g. capacity 20 with no RSVPs is "0 of 20 taken, 20 left").
Prefer replacing a whole list or panel with "replace" over many small edits.
```

### Scenario facts block (appended to every call below)

```text
SLICE: {{slice.name}} ({{pattern}}) on screen "{{screen.name}}"
Command: {{command}} · Emits: {{events}} · Read model: {{read model}}
SCENARIO ({{kind}}): {{title}}
Given: {{given; …}}  (or "nothing has happened")
When: {{when}}
Then: {{then; …}}
```

### 7a. Edit the real screen (when there's HTML)

```text
You are illustrating one Given/When/Then scenario on a real screen of an app prototype. Below is the screen's HTML (styles removed) and the scenario.
Describe the FEW edits that make this screen show the scenario. {{SHOT_RULES}}
For new elements (an error banner, a confirmation), copy the class names of a similar element already on the page so it matches the design.
Reply with ONLY one JSON object, no other text:
{"caption":string (one sentence: what this screenshot shows),
 "highlight":string (exact visible text of the element to outline after the edits, e.g. the error message),
 "edits":[ {"op":"replace_text","find":string (short exact text now on screen),"with":string}
         | {"op":"insert","near":string (exact text of an element on screen),"where":"before"|"after"|"inside_start"|"inside_end","html":string}
         | {"op":"replace","near":string (exact text inside the element to swap, e.g. a list or panel),"html":string (its new content, same tag and classes)}
         | {"op":"remove","near":string (exact text of the element to remove)}
         | {"op":"remove_all","near":string (text that every element to remove contains, e.g. "seats left")}
         | {"op":"set_value","field":string (field label or placeholder),"value":string} ]}

{{SCENARIO FACTS}}

SCREEN HTML:
{{cleaned screen HTML without scripts, capped at 90,000 chars}}
```

### 7b. Check the edited screen

```text
You check a drawing of one scenario on an app screen. Below is all the text the screen now shows, and the scenario.
List every value, count, list item, status or message on the screen that does NOT follow from the Given events and the Then of this scenario (for example seat counts or items shown when nothing has happened yet), and the edits that fix them. {{SHOT_RULES}}
Reply with ONLY one JSON object, no other text:
{"ok":boolean,"problems":[string],"edits":[same edit objects as before: replace_text | insert | replace | remove | remove_all | set_value]}
Edit objects: {"op":"replace_text","find":string,"with":string} {"op":"insert","near":string,"where":"before"|"after"|"inside_start"|"inside_end","html":string} {"op":"replace","near":string,"html":string} {"op":"remove","near":string} {"op":"remove_all","near":string}

SCENARIO ({{kind}}): {{title}}
Given: {{given}}
When: {{when}}
Then: {{then}}

{{all visible text on the edited screen}}
```

### 7c. Draw a mock (no HTML, screenshot only or nothing)

```text
You are illustrating one Given/When/Then scenario as a screenshot-like mock of an app screen (the attached image is the real screen). {{SHOT_RULES}}
Draw the whole screen as one standalone HTML document with inline CSS, desktop width about 1200px, matching the attached screenshot's layout, colours and text. No scripts.
Reply with ONLY one JSON object, no other text:
{"caption":string (one sentence: what this screenshot shows),"highlight":string (exact visible text of the element to outline),"html":string}

{{SCENARIO FACTS}}
```

---

## Output: the spec

The combined result is one model, which exports as JSON, as a CSV for Miro (one row per sticky) or as an SVG of the timeline:

```json
{
  "app": {"name": "…", "summary": "…"},
  "screens": [{"id": "…", "name": "…", "summary": "…", "source": "page.html", "static": false, "reach": {"steps": []}}],
  "streams": {"OfficeHoursBooked": "OfficeHours"},
  "outcomes": [{"id": "…", "name": "Every trade gets timely coaching", "slices": ["…"]}],
  "slices": [{
    "id": "book-office-hours", "name": "Book office hours", "pattern": "state_change",
    "screen": "live", "actor": "Student", "uiElement": "Book button", "story": "…",
    "command":   {"name": "BookOfficeHours", "fields": ["slotId: uuid", "studentId: uuid"]},
    "produces":  [{"name": "OfficeHoursBooked", "fields": ["slotId: uuid", "studentId: uuid", "bookedAt: utc_datetime"]}],
    "reads": [], "readModel": null, "projection": null,
    "specs": [{"kind": "error", "title": "Already taken",
               "given": ["OfficeHoursBooked(slotId: s-1, studentId: u-3)"],
               "when": "BookOfficeHours(slotId: s-1, studentId: u-2)",
               "then": ["error: this slot is taken"]}]
  }]
}
```

## Quality checklist (what the builder checks after deriving)

- Every non-static screen has at least one slice.
- Every slice is in at least one business outcome.
- Every command, event and read model has typed fields.
- Each event has one field list everywhere it appears.
- Every event that's read is produced by some slice, or by an automation that receives it from outside the app.
- Identity fields are named after their stream (`accountId` in the `Account` stream).
- Each slice has 2–6 scenarios covering success, error, empty where it applies, and at least one edge case.
- No navigation-only commands; no command reads a read model; no read model is written by a command.
- No sample or template slices, streams or outcomes leak into a real project.
- Every event field has a source (command, earlier event, or system), and one value has one name across command and event.
- Unique values have a "taken" scenario; codes, passwords and tokens have wrong, expired and too-many-tries scenarios.
- Fields that are one of a set are enums.
- Every button, link and number on a screen is covered by a slice.
- These are the review skill's `field_source`, `name_split`, `taken_case`, `secret_case`, `open_values` and `screen_gap` checks: see `review-spec-skill.md`.
