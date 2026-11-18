---
name: draw-screens-from-event-model
description: Draw clickable screens for an event model's slices that have no screen — from a workshop, a codebase read, hand-added slices or new outcomes — matching an existing prototype's style when there is one, showing exactly what the read models contain and offering exactly the commands the slices define, with scenario states (empty, error, success) wired in. Use when slices sit on "No screen yet", when a team models without a prototype, or when someone asks to sketch or update screens for part of a model.
---

# Draw screens from the event model

The builder is screen-first. Every slice page opens with its screen, the business reads the model through screens, and scenarios are illustrated on them. But many models end up with slices that have no screen:
- a workshop leaves only stickies;
- a codebase read finds behaviour with no page;
- someone adds slices by hand;
- an import brings commands with no UI.

Those slices sit on **"No screen yet"**.

This skill draws the missing screens from the model itself:
- **What a screen shows** comes from its read models.
- **What a person can do on it** comes from its commands.
- **What it looks like in each case** comes from its scenarios.

The result is a clickable prototype page, in the existing prototype's style when there is one. The business gets something to react to, and the board is whole again.

## When it runs

| Trigger | Scope |
|---|---|
| **Draw screens** on the "No screen yet" chip | Every slice without a screen |
| **Draw a screen** on one slice | That slice, plus slices that belong on the same screen |
| A workshop finishes (step 3 named screens but nobody sketched them) | All workshop screens |
| **Redraw** on a screen after the model changed | That screen. A redraw is a new version: the old one is kept and you can compare the two |

## What you get

```json
{
  "screens": [{"id": "office-hours", "name": "Office hours", "actor": ["Student", "Coach"], "fromWorkshop": "a column note: list of slots with Book buttons"}],
  "slices": [ /* the slices to place: pattern, actor, uiElement, command and fields, read model and fields, scenarios with error text, outcome */ ],
  "style": {"source": "edgemastery-live.html", "html": "a cleaned page from the existing prototype (styles kept)", "tokens": {"font": "…", "accent": "…", "radius": "…"}} | null,
  "navigation": [{"screen": "trade-detail", "links": ["coaching", "live"]}],
  "glossary": {"slot": "a 30-minute office-hours time a coach opens"}
}
```

- **With an existing prototype,** `style` carries one of its pages with styles intact, and its design tokens. The new screens must look like they belong to it.
- **Without one,** `style` is null and Claude uses the builder's plain wireframe style: neutral, clearly a sketch, and not mistakable for a finished design.

## Done in code first (not by Claude)

| Step | Rule |
|---|---|
| Group slices into screens | Slices with the same screen name. Failing that, state views and state changes by the same actor that read or change the same stream, next to each other on the timeline |
| What each screen needs | A list of: read-model fields to show, commands to offer (with their fields as inputs), and scenario states to support (empty, error messages, success) |
| Navigation | Links between screens that come one after another in the timeline for the same actor, plus links already in the prototype |
| The style page | The prototype page whose layout is closest (lists, forms or details) |

## Rules

**The screen is the model, drawn**
- **Show** exactly the read-model fields of the screen's state views. Nothing on the screen may be a value no read model provides. If the layout needs one (a coach's name), leave a visible placeholder `[coach name: not in the model]` and report it as a gap.
- **Offer** exactly the commands of the screen's state changes, as buttons or forms. A form's inputs are the command's fields, minus ids the app knows already (the slot being clicked, the person signed in). Label each with the business's words.
- **Name** the trigger with the slice's `uiElement` when it has one ("Book button on a free slot" means a **Book** button on each free slot).
- **Automations** aren't screen controls. If an automation's result shows on a screen (a reminder was sent), show it where its read model puts it.
- No extra features: no search, filters, settings or navigation items the model doesn't imply.

**Scenario states are built in**
- **Empty:** each list or panel fed by a read model shows the empty-state text from its `empty` scenario. If there's no such scenario, it shows a neutral placeholder, reported as a gap.
- **Errors:** each command's `error:` messages, exactly as written, appear next to the control that triggers them. Mark them as states the page can switch to, not visible all at once.
- **Success:** what the person sees after the command, from the success scenario's Then (a confirmation, the list updated).
- The page includes a small state switcher (Normal · Empty · each error · After success), so reviewers can see every scenario. In illustration mode, the builder's scenario screenshots drive it.

**Style**
- **With a prototype:** reuse its layout pattern, class names, components, spacing and tone. Copy a similar existing element rather than inventing a new one. Same fonts, colours and header and navigation.
- **Without one:** use the plain wireframe style: system font, greys, one accent colour, boxes and rules, clearly a sketch.
- **Example data:** realistic but invented, consistent with the scenarios (if a scenario says capacity 20, show 20). No real people's names or details.

**Clickable, not real**
- Buttons switch states or move between the new screens. Forms validate the obvious (required inputs), and show the scenario's error text when the switcher is on that error.
- No network calls, no storage. It's a prototype page, the same as the user's other prototype pages.

## Output

One HTML page per screen, self-contained, plus a report:

```json
{
  "screens": [{"id": "office-hours", "name": "Office hours", "file": "office-hours.html",
               "slices": ["office-hours-list", "book-office-hours", "cancel-office-hours-booking"],
               "states": ["normal", "empty", "error:this slot is taken", "error:you already have a booking", "after:book"],
               "html": "<!doctype html>…"}],
  "placements": [{"slice": "book-office-hours", "screen": "office-hours", "uiElement": "Book button on each free slot"}],
  "gaps": [{"slice": "office-hours-list", "what": "The design needs the coach's name; LiveSessions has only coachId.", "suggest": "Add coachName to the read model, or have it handle CoachProfileSaved."}],
  "summary": "Drew 2 screens for 6 slices that had none. Both use the Edgemastery prototype's style. 1 gap: the slot list can't show the coach's name from the current model."
}
```

## The prompt

The builder sends this once per screen, followed by the input JSON for that screen:

```text
You draw one screen of an app's prototype from its event model, for slices that have no screen yet. The screen is the model, drawn: show exactly the fields of its read models (nothing the model doesn't provide; where the layout needs a missing value, show a visible "[<what>: not in the model]" placeholder and report a gap), and offer exactly its commands as buttons or forms whose inputs are the command's fields minus ids the app already knows, labelled in the business's words and placed where the slice's uiElement says. Add no features the model doesn't imply.
Build in the scenario states: each list's empty state with the text from its empty scenario; each command's error messages exactly as written, next to the control that triggers them; what the person sees after success, from the success scenario. Add a small state switcher (Normal, Empty, each error, After success) so reviewers can see every scenario.
{{STYLE_RULES}}
Example data is invented but realistic and consistent with the scenarios' values; never real people. The page is self-contained HTML with inline CSS and a little inline script for states and navigation between the screens listed; no network calls, no storage.
Reply with ONLY one JSON object, no other text:
{"id":string,"name":string,"html":string (a complete standalone page),
 "states":[string],
 "placements":[{"slice":string,"uiElement":string}],
 "gaps":[{"slice":string,"what":string,"suggest":string}]}
```

`{{STYLE_RULES}}`:
- **With a prototype:** "Match the attached prototype page: reuse its layout pattern, class names, components, header and navigation, fonts, colours and tone, copying a similar existing element rather than inventing one. Here is the page: {{style.html}}"
- **Without one:** "Use a plain wireframe style: system font, greys, one accent colour, simple boxes and rules. It should read as a sketch, not a finished design."

## Example (abridged)

Six workshop slices about office hours: Office hours list (view), Book office hours, Cancel office hours booking (Student), Open office hours slot and Remove office hours slot (Coach), and Office hours reminder (automation).

Code groups them into two screens: **Office hours** (student) and **My office hours** (coach). Claude draws them in the Edgemastery style:

- **Office hours:** the list of slots (time, length, Free or Taken), each free one with a **Book** button.
  - The student's own booking sits at the top with **Cancel booking**.
  - The states: Normal, Empty ("No office hours open yet."), "This slot is taken", "You already have a booking", and After booking ("Booked. It's in your upcoming calls.").
  - The reminder isn't a control. It shows as "Reminder sent" on the booking, from the read model.
- **My office hours:** a form to open a slot (start time, length in minutes), the coach's slots with who booked them, and **Remove** on each. The states: Normal, Empty, "Overlaps an existing slot", "Pick a time in the future".
- **Gap:** the student list wants the coach's name, but the read model has only `coachId`. Shown as `[coach name: not in the model]` and reported.

## What the builder does with the reply

- **Adds each page to the project's inputs** as a prototype page with a "Drawn from model" badge, so it works like any other prototype page: preview, scenario screenshots, and derive again.
- **Moves the slices** from "No screen yet" to their new screen, and records each slice's trigger.
- **Gaps:** posts them to the slice's Discussion with their suggestion. The spec reviewer and repair-and-merge can then apply it.
- **Scenario illustrations:** use the page's states directly, so they're exact instead of edited after the fact.
- **When a designer replaces a drawn page** with a real one, the drawn page is archived and the slices move to the real page, matched by screen id.

## Done means
- Every slice that had no screen is placed on one, or reported as not needing one (a pure automation).
- Every value on screen comes from a read model, and anything missing is a visible placeholder and a gap.
- Every command is offered, with exactly its inputs, and with its error messages exactly as the scenarios state them.
- Every scenario's state can be shown with the switcher.
- With a prototype, the new pages look like they belong to it. Without one, they're clearly sketches.
