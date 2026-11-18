---
name: write-event-model-for-business
description: Turn an event model (slices, scenarios, outcomes) into plain-language writing a product owner, founder or client can read and sign off — slice stories, scenarios as rules, outcome write-ups, sign-off summaries and change notes — with no technical names and nothing the model doesn't contain. Use when someone needs the spec explained to non-engineers, a sign-off brief before building, or a plain summary of what changed.
---

# Write the event model for the business

The model is precise but written for engineers: `BookOfficeHours`, `OfficeHoursBooked`, `LiveSessionsProjection`. People who decide what gets built think in screens, actions and rules: "a student books a slot", "you can't book a taken slot". This skill writes the model in their words, so they can read it, correct it and sign it off before anyone builds.

**It translates; it never adds.** Everything you write comes from the model. When the model is silent on something a reader will ask about, say so as an open question. Don't fill the gap.

## What it writes

| Output | For | Length |
|---|---|---|
| **Story** | Each slice | One sentence |
| **Rules** | Each scenario | One or two sentences |
| **Outcome write-up** | Each business outcome | Half a page |
| **Sign-off summary** | A slice, an outcome or the whole app | One page |
| **Change note** | After a derive, repair, merge, review or merged build | A few lines |

## What you get

```json
{
  "task": "story" | "rules" | "outcome" | "signoff" | "changes",
  "scope": {"slice": "book-office-hours"} | {"outcome": "every-trade-gets-timely-coaching"} | {"app": true},
  "app": {"name": "Edgemastery", "summary": "…"},
  "audience": "business",
  "glossary": {"Student": "a trader learning in an academy", "Coach": "…", "slot": "a 30-minute office-hours time a coach opens"},
  "screens": [{"id": "live", "name": "Live sessions", "words": ["Book", "Taken", "Upcoming calls", "Office hours", "Nothing scheduled."]}],
  "slices": [ /* the slices in scope, in timeline order, with status, owner, review and scenarios */ ],
  "outcomes": [ /* the outcomes in scope, with their slice ids */ ],
  "openThreads": [{"slice": "book-office-hours", "text": "Can coaches cancel a booked slot?", "status": "open"}],
  "changes": [ /* for task "changes": the change list from the repair/merge skill, the reviewer's verdict, or merged pull requests */ ]
}
```

- `screens[].words` are the visible words from the prototype: buttons, headings, labels, empty-state messages. **Use them.** They're the business's own vocabulary.
- `glossary` holds terms the team has agreed. It always wins over your own wording.

## Rules for every output

**Words**
- Never use an event, command, read model, projection, stream, field or slice-id name. Not in quotes, not in brackets, not "also known as". `OfficeHoursBooked` becomes "the booking".
- Use the screen's words for things on screen: say "Book", not "submit a booking request".
- Name people by role, from the slice's actor and the glossary: "the student", "the coach", "an admin". Say "the app" for automations: "the app sends a reminder".
- Use plain verbs: book, cancel, see, pay, get. Avoid "leverage", "facilitate", "enable" and "seamlessly".
- Keep to active voice and short sentences, one idea each.

**Rules and numbers**
- Write scenarios as cause and effect: "If … , … ." "When … , … ."
- Keep numbers, limits, times and amounts exactly as the scenario states them: "30 minutes", "one booking at a time", "the last seat". Never round them or add one.
- Quote error messages as the person sees them: "they see 'This slot is taken'".
- Say what doesn't happen too, when the scenario implies it: "and nothing is booked".

**Honesty**
- Describe only what the model contains. If a rule a reader would expect is missing (what happens when the coach cancels?), list it under **Open questions**. Don't write it as if it were decided.
- State status as it is: built, being built (with the agent, in review) or planned. Never call something done that isn't merged.
- Include open discussion threads as open questions, in plain words.
- Never mention Claude, the agent's internals, or "the model" as a document. Write about the app.

**Format**
- Plain headings and short paragraphs. Lists only for steps and rules.
- No emoji, no marketing tone, and no exclamation marks.

## 1. Story (one per slice)

One sentence: who, what, and why it matters when that isn't obvious. State changes say what someone does, state views say what someone sees, and automations say what the app does by itself.

| Slice | Story |
|---|---|
| Book office hours (state change, Student) | A student on a plan with coaching books a free office-hours slot with their coach. |
| Live sessions (state view, Student) | Students see upcoming group calls and the office-hours slots they can book or have booked. |
| Receive failed payment (automation) | When a card payment fails, the app records it so billing, admins and the customer all see it. |

## 2. Rules (one per scenario)

Retell each Given/When/Then as a rule a person would recognise. Lead with the condition, then what happens. Use the scenario's own values.

| Scenario | Rule |
|---|---|
| success · Free slot booked | When a student books a free slot, it's theirs and the coach sees who booked it. |
| error · Already taken | If someone else has already booked the slot, the student sees "This slot is taken" and nothing is booked. |
| error · Tier has no office hours | Students on a plan without office hours can't book. They see "Office hours come with the Mentorship and Elite tiers". |
| edge · One booking at a time | A student can hold only one office-hours booking at a time. |
| empty · Nothing scheduled | When no calls are scheduled, the page says "Nothing scheduled." |

## 3. Outcome write-up

```markdown
## Every trade gets timely coaching

**What it achieves.** Every trade a student logs gets feedback: from AI within minutes, and from a coach within the week.

**Who it serves.** Students, who learn faster, and coaches, who see what each student needs.

**How it works**
1. On *Trade detail*, the student asks for an AI review of a trade.
2. The coach sees new trades on *Coaching* and writes a review.
3. The student books one-to-one office hours on *Live sessions* to talk it through.

**Rules that protect it**
- If someone else has already booked the slot, the student sees "This slot is taken" and nothing is booked.
- A student can hold only one office-hours booking at a time.
- …

**Where it stands.** 2 of 5 steps are built, 1 is in review, 2 are planned.

**Open questions**
- What happens to a booking when the coach removes the slot?
```

Order the steps by the timeline. Name each screen as the prototype names it, in italics. Give each rule once, even when several slices share it.

## 4. Sign-off summary

The page someone approves before building starts. It works for one slice, one outcome or the whole app (one section per outcome).

```markdown
# Office-hours booking: for sign-off

**In one line.** Students on coaching plans book one-to-one time with their coach, one booking at a time.

**What will be built**
- Coaches open 30-minute office-hours slots on *Live sessions*.
- Students see free and taken slots, and book a free one.
- Students can cancel their own booking, which frees the slot.

**Rules we've agreed**
- If someone else has already booked the slot, the student sees "This slot is taken" and nothing is booked.
- A student can hold only one booking at a time.
- Office hours come with the Mentorship and Elite plans only.

**Not included**
- Rescheduling a booking (cancel and book again instead).
- Reminders before the session.

**Open questions**
- What happens to a booking when the coach removes the slot?

**Status.** Spec reviewed by Nia (product). Nothing built yet.

Approving this means the team builds exactly what's above.
```

- **"Not included"** lists only things the model shows are out of scope, or that a discussion thread has decided. Never guess at scope.
- **The status line** reports the spec review and the build state.

## 5. Change note

What changed, in the reader's terms, grouped by what it means for them, not by what changed technically. Leave out pure renames and internal fixes unless they change what someone sees or does.

```markdown
**What changed in Edgemastery's spec (17 Nov)**
- **Added:** coaches can schedule group calls and open office-hours slots, and students can book them. These were missing before.
- **Fixed:** failed card payments now show up in billing and the admin dashboard. The spec had no way to record them.
- **Removed:** workshop booking and waitlists. They came from a template, not from your app.
- **To decide:** whether "customer" and "account" mean the same thing. Engineering wants one name.
```

## The prompt

The builder sends this, followed by the input JSON:

```text
You write an app's event model for the business people who decide what gets built: a product owner, founder or client. They don't know Event Modeling and must be able to read, correct and sign off what you write.
Translate; never add. Everything you write comes from the model. When the model is silent on something a reader will ask about, list it under Open questions; never fill the gap.
Never use an event, command, read model, projection, stream, field or id name. Use the screen's own words ("screens[].words") and the glossary, and name people by role. Plain verbs, active voice, short sentences. Rules are cause and effect ("If …, …"), with numbers, limits and error messages exactly as the scenarios state them, and say what doesn't happen when it matters. State the status as it is (built, being built, planned). Include open discussion threads as open questions. No emoji, no marketing tone, no exclamation marks. Don't mention Claude, the agent or "the model".
Task: {{task}}. {{TASK_RULES}}
Reply with ONLY one JSON object, no other text:
{"stories":[{"slice":string,"text":string}]|null,
 "rules":[{"slice":string,"scenario":string (title),"text":string}]|null,
 "markdown":string|null (outcome write-up, sign-off summary or change note),
 "openQuestions":[{"slice":string|null,"text":string}],
 "unclear":[{"slice":string,"what":string (a scenario or name you couldn't translate without guessing)}]}
```

`{{TASK_RULES}}` by task:
- **story:** "One sentence per slice in scope: who does or sees what, and why if it's not obvious. Automations: what the app does by itself."
- **rules:** "One rule per scenario, condition first, using the scenario's values and error text."
- **outcome:** "Write the outcome: what it achieves, who it serves, the steps in timeline order with screen names in italics, rules that protect it (each once), where it stands, and open questions. Half a page."
- **signoff:** "Write a one-page sign-off: one line, what will be built, rules agreed, not included (only what the model or threads show is out of scope), open questions, status, and the closing line 'Approving this means the team builds exactly what's above.'"
- **changes:** "Write a short change note grouped as Added, Fixed, Removed and To decide, in terms of what people can do or see. Leave out renames and internal fixes that change nothing for them."

## What the builder does with the reply

- **Stories** fill the "For the business" panel on each slice, and the board's **Business labels** view.
- **Rules** show under each scenario on the slice page, in place of the raw Given/When/Then when **Business labels** is on.
- **Outcome write-ups** show when an outcome chip on the board is clicked.
- **Sign-off summary:**
  - It opens as a doc from the slice's or outcome's review menu, ready to share, and can be downloaded as Word or PDF.
  - Approving it records a business sign-off in the slice's spec review, alongside the engineering reviewers.
- **Change notes** are posted to the project's Activity, and can be sent to the people who follow the project.
- **`unclear` items** become comments on the slice. A rule nobody can explain in plain words is usually a rule the team hasn't agreed.

## Done means
- A non-engineer can read every line without asking what a word means.
- No technical name appears anywhere.
- Every rule matches a scenario, with the same numbers and the same error text.
- Nothing is described that the model doesn't contain. Gaps are listed as open questions.
- Status is stated honestly.
