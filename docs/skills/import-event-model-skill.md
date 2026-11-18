---
name: import-event-model
description: Import an existing event model from another tool — an EM-Studio export, a Miro or FigJam board, a spreadsheet or CSV of stickies, Gherkin feature files, or the builder's own JSON/CSV — into the builder's model, with slices, fields, scenarios and outcomes, flagging what couldn't be read with confidence and handing the result to repair-and-merge. Use when a team moves an event model into the builder instead of starting from a prototype, or brings in work done in a workshop tool.
---

# Import an event model from another tool

Teams that already do Event Modeling have their models elsewhere:
- a dedicated tool like EM-Studio;
- a Miro or FigJam board from a workshop;
- a spreadsheet of stickies;
- Gherkin files written alongside the code.

This skill brings that work into the builder, so nobody has to retype a model, and the team can keep going from where they were.

Imports are messy: colours mean types, positions mean order, lanes mean actors, and half the stickies are notes or questions. The import keeps everything it can read with confidence, and **lists what it couldn't, instead of guessing.**

## Sources

| Source | How it arrives | What the structure means |
|---|---|---|
| **The builder's own JSON or CSV** | Export from this or another workspace | Exact. No interpretation needed |
| **EM-Studio export** | The tool's JSON export | Element types, slices, fields and specs, by field names. See "Unknown formats" |
| **Miro board** | Board items and connectors through Miro's REST API (when the Miro integration is connected), or a JSON or CSV of items | Sticky colour is the type, x is the timeline, y is the lane, frames are slices or screens, connectors are flows |
| **FigJam board** | A JSON export from a plugin, or a copied selection | Same as Miro |
| **Spreadsheet or CSV** | `.xlsx`, `.csv` or a pasted table | One row per sticky or per slice. Columns are mapped (see "Spreadsheets") |
| **Gherkin** | `.feature` files | Scenarios. Matched to slices by the commands and events named in them |
| **Screenshot or photo of a board** | An image | Read as a board: colours, positions, text. Confidence is lower, so more goes to review |

## Pipeline

```
file(s) ──► detect the format (in code)
        ──► parse into elements (in code): {id, text, colour, shape, x, y, w, h, frame, lane, links, notes}
        ──► interpret (Claude): types, slices, names, fields, scenarios, outcomes, actors, screens
        ──► repair-and-merge: into the project's current model, or as a new model
        ──► spec reviewer: model review, so the team sees what's thin
```

## Done in code first (not by Claude)

| Step | Rule |
|---|---|
| Detect the format | By extension and structure: the builder's export has `format: "event-model"`, Miro items have `type: "sticky_note"`, Gherkin starts with `Feature:`, and so on |
| Normalise elements | Every sticky, shape, frame and connector becomes `{id, text, colour, shape, x, y, w, h, frame, links}`. Colours are reduced to the nearest of: blue, orange, green, yellow, purple, red, pink, grey, white |
| Lanes | Cluster elements by `y` into horizontal bands. Label a band from a sticky or text at its left edge, if there is one |
| Columns | Cluster by `x` into vertical bands, ordered left to right. That's the timeline |
| Text clean-up | Strip formatting, split a sticky's first line (the name) from the rest (fields or notes) |
| The builder's own formats | Mapped directly, with no Claude call |

## Interpreting a board

**Types.** Event Modeling's colour conventions decide the type first, then the text confirms it:

| Colour | Usually | Confirm with the text |
|---|---|---|
| Blue | Command | Imperative verb: "Book office hours", `BookOfficeHours` |
| Orange | Event | Past tense: "Office hours booked" |
| Green | Read model or view | A noun: "Live sessions", "Booking list" |
| Teal | Projection | "…Projection", or "handles X" |
| Yellow | Actor, or a note | A person or role ("Student") on a lane label, otherwise a note |
| Purple or pink | Automation or processor | "When X, then Y", a gear, "Process…" |
| Red | Error, question or hotspot | "?", "error", "what if…" |
| White, grey or frame | Screen, wireframe or slice frame | A UI sketch, a screen name, a slice title |

When colour and text disagree, the text wins if it's clearly one type ("Office hours booked" on a blue sticky is an event), and the element is listed under `uncertain`.

**Slices.**
- A frame or bordered group around a column is a slice, and its title is the slice name.
- Without frames, each column that has a command, or a read model under a screen, is a slice. The pattern comes from what's in the column: a command and events make a state change, a read model a state view, and a processor an automation.

**Order and lanes.** Columns left to right are the timeline. Lanes labelled with a role become actors. A lane of orange stickies is the events lane, and its sub-lanes (if any) are streams.

**Names.** Turn sticky text into model names: "Office hours booked" becomes `OfficeHoursBooked`, and "book office hours" becomes `BookOfficeHours`. Keep the original text as the label the business sees.

**Fields.** Lines under a sticky's name ("slotId", "coach: uuid", "• starts at") become fields with types. Use the type when it's written. Otherwise guess it from the name and mark the field `guessed`.

**Flows.** Connectors confirm what a slice reads and produces. An arrow from an event to a read model means the read model's projection handles that event.

**Scenarios.** Given/When/Then tables or stickies on the board, rows in a spreadsheet, and Gherkin scenarios each become a scenario on the slice whose command or read model they name.

**Red stickies and questions** aren't model elements. They become comments in the slice's Discussion, attributed to "Imported from <source>".

**Outcomes.** Frames or labels that group several slices around a goal ("Booking", "Members get a seat") become outcomes. If the board has none, leave outcomes empty; the reviewer's model review proposes them.

## Spreadsheets

Map columns by their header, case and spacing ignored:

| Header contains | Maps to |
|---|---|
| `type`, `kind`, `lane`, `colour` | Element type |
| `name`, `title`, `sticky`, `text` | Name |
| `slice`, `step`, `column`, `order` | Slice and timeline order |
| `screen`, `page`, `view` | Screen |
| `actor`, `role`, `who` | Actor |
| `fields`, `attributes`, `data` | Fields (split on `,`, `;` or new lines) |
| `given`, `when`, `then` | Scenario parts |
| `stream`, `aggregate`, `entity` | Stream |
| `outcome`, `goal`, `epic` | Outcome |

If a needed column can't be mapped with confidence, ask which column means what before importing. Don't guess a mapping for a whole sheet.

## Unknown formats (including EM-Studio)

The builder doesn't hard-code another tool's schema, because those change between versions. For JSON from another modelling tool:
1. **Look for the shape.** Find arrays of elements with type-like fields (`type`, `kind`, `elementType`, `category`), names, fields or properties, positions, and links or relations. Find group-like objects (`slices`, `chapters`, `swimlanes`, `frames`).
2. **Map types by name:** `command`, `event`, `readmodel`/`read_model`/`view`, `automation`/`processor`, `screen`/`ui`, `spec`/`specification`/`scenario`.
3. **Say what you assumed.** Return the mapping you used (`"elementType" → type`, `"data.fields" → fields`) in `mapping`, so the team can confirm it. The builder saves a confirmed mapping per tool, so the next import from the same tool is exact.

When a team first imports from EM-Studio, ask for one real export. Confirm the mapping on it, then reuse that mapping for the rest of the team's files.

## The prompt

The builder sends this, followed by the source description and the normalised elements:

```text
You import an existing event model from another tool into a standard structure. The elements were parsed in code: each has text, a normalised colour, shape, position (x = timeline, y = lane), frame, lane and column clusters, and links. Interpret them using Event Modeling conventions, keep everything you can read with confidence, and list what you couldn't instead of guessing.
{{EVENT_MODELING_RULES}}
Types: colour first (blue command, orange event, green read model or view, teal projection, yellow actor or note, purple/pink automation, red question or hotspot, white/grey/frames screens or slices), confirmed by the text (imperative = command, past tense = event, noun = read model). When colour and text disagree, the text wins if it's clearly one type; list the element under "uncertain". Slices: frames or bordered groups around a column, else one per column that has a command, a read model under a screen, or a processor. Order: columns left to right. Lanes labelled with a role are actors. Names: PascalCase from the sticky text, keeping the original text as the label. Fields: from lines under the name, with written types, else guessed and marked. Connectors confirm reads and produces. Given/When/Then tables, rows or Gherkin become scenarios on the slice they name. Red stickies and questions become comments, not model elements. Groups around a goal become outcomes; otherwise leave outcomes empty.
For a format you don't recognise, infer the mapping from field names and return it in "mapping". {{SOURCE_RULES}}
Reply with ONLY one JSON object, no other text:
{"model":{"app":{"name":string,"summary":string},"screens":[{"id":string,"name":string,"source":string}],"streams":{"EventName":"StreamName"},"outcomes":[{"id":string,"name":string,"slices":[string]}],
   "slices":[{"id":string,"name":string,"pattern":"state_change"|"state_view"|"automation","screen":string,"actor":string,"uiElement":string,
     "command":{"name":string,"fields":[string]}|null,"produces":[{"name":string,"fields":[string]}],"reads":[{"name":string,"fields":[string]}],
     "projection":{"name":string,"handles":[{"event":string,"does":string}]}|null,"readModel":{"name":string,"fields":[string]}|null,
     "specs":[{"kind":"success"|"error"|"empty"|"edge","title":string,"given":[string],"when":string,"then":[string]}],
     "labels":{"command":string,"events":{"EventName":string},"readModel":string} (original sticky text),
     "from":[string] (source element ids)}]},
 "comments":[{"slice":string|null,"el":string,"text":string,"from":string (element id)}],
 "uncertain":[{"element":string,"text":string,"chosen":string,"why":string}],
 "skipped":[{"element":string,"text":string,"why":string}],
 "guessedFields":[{"where":string,"field":string}],
 "mapping":{"sourceField":"meaning"}|null,
 "summary":string (2-3 sentences: what was imported, what needs a look)}
```

`{{SOURCE_RULES}}` per source:
- **Miro/FigJam:** "Frames are slices when they span one column, outcomes or screens when they span several. Ignore stickies outside every lane."
- **Spreadsheet:** "Use this column mapping: {{mapping}}. Each row is one element, or one slice when the row has a command and events."
- **Gherkin:** "Each Scenario is a spec. Match it to a slice by the command in When or the events in Then. Background steps are Given for every scenario in the feature."
- **Screenshot:** "Read colours, positions and text from the image. Confidence is lower: put anything unclear under 'uncertain'."

## Example: a Miro workshop board (abridged)

```json
{"summary": "Imported 23 slices across 4 screens from the 'Coaching workshop' board, with 31 events and 12 scenarios from the Given/When/Then frames. 3 stickies need a look (colour and text disagreed), 9 questions became comments, and 14 fields have guessed types.",
 "uncertain": [{"element": "3458764512", "text": "Slot booked", "chosen": "event OfficeHoursBooked", "why": "Blue sticky, but the text is past tense; placed in the events lane."}],
 "skipped": [{"element": "3458764590", "text": "lunch 12:30!", "why": "Not part of the model."}],
 "comments": [{"slice": "book-office-hours", "el": "slice", "text": "What if the coach cancels the slot after it's booked?", "from": "3458764533"}],
 "mapping": null}
```

## What the builder does with the reply

- **Shows a preview** before anything changes:
  - the imported timeline;
  - `uncertain` items, each with a type you can change;
  - `skipped` items, each of which you can bring back;
  - guessed fields, highlighted.
- **Into an existing project:** hands the model to **repair-and-merge** (as the `imported` version), so names, scenarios and reviews already on the board are kept, and conflicts become questions.
- **As a new project:** creates it with the imported model, and keeps the original files in the project's inputs.
- **Comments:** posts them to each slice's Discussion as "Imported from Miro".
- **After import:** runs the spec reviewer's model review, so missing scenarios, events nothing produces and naming drift show up straight away.
- **Mappings:** saves a confirmed mapping for an unknown format (for example EM-Studio) to the workspace, so the next import from that tool needs no guessing.

## Done means
- Every element of the source is in the model, a comment, `uncertain`, or `skipped`, with a reason.
- Slices follow the board's left-to-right order, and types follow Event Modeling colours unless the text clearly says otherwise.
- Original sticky text is kept as labels, so the business sees its own words.
- Guessed fields and mappings are marked for the team to confirm.
- Nothing already on the board is overwritten: merges go through repair-and-merge.
