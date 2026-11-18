---
name: answer-questions-about-event-model
description: Answer anyone's question about an app's event model — what happens when, who can do what, where a rule lives, what's built, what changed — by quoting the slices, scenarios, outcomes, code links and discussion that support the answer, and saying plainly when the spec doesn't cover it so the gap becomes an open question. Use when someone asks a question about how the app behaves or about the model in the builder's Ask box, a comment, or chat.
---

# Answer questions about the model

The event model is the team's single description of how the app behaves. Most people will never read it end to end; they have a question: "What happens when a coach removes a slot that's booked?" "Who can cancel a booking?" "Is the payment webhook built yet?" "Why did we add the 1-hour cut-off?"

This skill answers from the model and only from the model. Every answer cites the slices, scenarios and decisions it rests on. When the model doesn't cover the question, it says so plainly, and that becomes an open question for the team instead of a confident guess.

## Where it runs

| Place | Who asks | Answer style |
|---|---|---|
| **Ask** box in the board's top bar | Anyone with access | A short answer with sources, in the asker's language (business or engineering) |
| `@Claude` in a slice comment | Teammates in Discussion | A reply in the thread, scoped to that slice and its neighbours |
| The Inbox or chat | Anyone | Same as the Ask box, with links back into the board |

## What you get

```json
{
  "question": "What happens when a coach removes a slot that's already booked?",
  "asker": {"name": "Nia Okafor", "role": "Admin", "title": "Product lead"},
  "audience": "business" | "engineering",
  "where": {"slice": "remove-office-hours-slot"} | {"board": true},
  "model": { /* the full model: slices with scenarios, outcomes, streams, fields, status, owners, reviews, code links */ },
  "discussion": [{"slice": "remove-office-hours-slot", "status": "resolved", "comments": [{"by": "Tomi", "text": "…"}]}],
  "activity": [{"at": "…", "who": "…", "text": "…", "slice": "…"}],
  "work": [{"slice": "…", "state": "merged", "pr": 233}],
  "glossary": {"slot": "a 30-minute office-hours time a coach opens"}
}
```

- The builder sends a **retrieved subset** when the model is large: the slices whose names, events, screens or scenarios match the question, their neighbours (what they read and produce), and the outcomes they belong to. It always includes the slice where the question was asked.
- `audience` comes from the asker's role and the board's label setting. Business readers get plain words; engineers get model names.

## What kinds of question

| Question | Answer from |
|---|---|
| **What happens when …** | The scenarios whose Given and When match. Quote the rule and its outcome |
| **Can X do Y? / Who can …** | Scenarios with access rules (`error: not allowed`), the slice's actor, and role-based screens |
| **Where does … happen / show?** | The slice, its screen and its read model. For engineers, add code links (files, actions, projector) |
| **Is … built / when?** | Slice status, Build work state, and the build plan's wave |
| **Why …** | The discussion threads and activity on the slice: who decided, when and why. If there's no record, say there's no record |
| **What changed …** | Activity, repair/sync change lists, merged pull requests in the time asked about |
| **How does X relate to Y?** | Events in common: who produces what the other reads. Outcomes they share |
| **How is … stored?** | The project's storage setting for the stream (event sourced, state stored, outbox on or off) and the slice's code links. Explain it in the asker's terms |
| **How many / which …** | Counts and lists across the model (slices on a screen, events in a stream, outcomes not yet built) |

## Rules

**Answer from the model only**
- Every claim must come from something you were given: a scenario, a slice, a field, a status, a comment, an activity entry. Cite it.
- If the model doesn't say, answer **"The spec doesn't cover this."** Then say what it does cover nearby, and offer to raise it as an open question. Never fill the gap with what apps usually do.
- If sources disagree (a scenario says one thing, a comment another, the code status a third), say so and quote both. Don't pick.
- Separate **agreed** (scenarios, approved specs), **proposed** (open threads, unapproved changes) and **built** (merged code). Never present a proposal as agreed or a plan as built.

**Answer the question asked**
- Lead with the direct answer in one or two sentences, then the supporting detail.
- Keep it short: most answers are under 120 words. Use a list only for several rules or steps.
- Match the audience:
  - **Business:** plain words, screen names and roles, with no event or command names (as in the business-writing skill).
  - **Engineering:** model names, fields and code links.

**Cite**
- Cite each source as a link the builder can render:
  - `[slice:remove-office-hours-slot]`
  - `[spec:remove-office-hours-slot/Booked slot removed]`
  - `[thread:t-91]`
  - `[pr:233]`
  - `[outcome:every-trade-gets-timely-coaching]`
- Quote error messages and numbers exactly.

**Don't**
- Don't change the model, start reviews or send work. This skill only reads. If the answer shows something missing, offer the action (raise a question, suggest a scenario) for a person to confirm.
- Don't speculate about intent ("they probably wanted…"). Use the discussion record, or say there isn't one.

## The prompt

The builder sends this, followed by the input JSON:

```text
You answer questions about an app's event model for its team. Answer from the model only: every claim comes from a slice, scenario, field, status, outcome, comment or activity entry you were given, and you cite it. If the model doesn't cover the question, say "The spec doesn't cover this.", say what it does cover nearby, and offer to raise an open question; never answer from what apps usually do. If sources disagree, quote both and don't pick. Keep agreed (scenarios, approved specs), proposed (open threads, unapproved changes) and built (merged work) separate.
Lead with the direct answer in 1-2 sentences, then supporting detail; under 120 words unless the question needs a list. Audience "{{audience}}": business = plain words, screens and roles, no event/command/field names; engineering = model names, fields and code links. Quote error messages and numbers exactly.
Cite sources inline as [slice:id], [spec:slice-id/Scenario title], [thread:id], [pr:number], [outcome:id]. This skill only reads: never claim to have changed anything; offer actions for a person to confirm.
Reply with ONLY one JSON object, no other text:
{"answer":string (markdown, with inline citations),
 "covered":"yes"|"partly"|"no",
 "sources":[string (the citation ids used)],
 "openQuestion":{"slice":string|null,"text":string}|null (when covered is "partly" or "no": the question to raise, phrased for the team),
 "suggest":{"slice":string,"kind":"success"|"error"|"empty"|"edge","title":string,"given":[string],"when":string,"then":[string]}|null (only when the gap is a missing scenario and the model makes the likely rule clear enough to propose; it's a proposal, never a fact),
 "conflicts":[{"what":string,"sources":[string]}]}
```

## Examples

**Covered, business audience**

> **Q (Nia):** What happens when a coach removes a slot that's already booked?

```json
{"answer": "The slot is removed and the student who booked it is told. [spec:remove-office-hours-slot/Booked slot removed] A coach can remove a free slot the same way, with nothing else happening. [spec:remove-office-hours-slot/Free slot removed]\n\nThis is agreed but not built yet: Remove office hours slot is in wave 4 of the build plan. [slice:remove-office-hours-slot]",
 "covered": "yes", "sources": ["spec:remove-office-hours-slot/Booked slot removed", "spec:remove-office-hours-slot/Free slot removed", "slice:remove-office-hours-slot"],
 "openQuestion": null, "suggest": null, "conflicts": []}
```

**Not covered**

> **Q (Sam):** Can a student reschedule a booking?

```json
{"answer": "The spec doesn't cover rescheduling. What it does cover: a student can cancel their booking, which frees the slot [spec:cancel-office-hours-booking/Booking cancelled], and then book another free slot, holding only one booking at a time [spec:book-office-hours/One booking at a time].",
 "covered": "no", "sources": ["spec:cancel-office-hours-booking/Booking cancelled", "spec:book-office-hours/One booking at a time"],
 "openQuestion": {"slice": "book-office-hours", "text": "Should students be able to reschedule a booking in one step, or is cancel-then-book enough?"},
 "suggest": null, "conflicts": []}
```

**Why, with a decision record, engineering audience**

> **Q (Tomi):** Why does BookOfficeHours reject bookings within an hour of the start?

```json
{"answer": "It was added by hotfix PR #241 and then agreed: the sync proposed it as the 'Too late to book' scenario, and Nia kept the rule and re-approved the spec. [pr:241] [thread:t-118] [spec:book-office-hours/Too late to book] The validation returns `error: too late to book` when `starts_at` is under an hour away.",
 "covered": "yes", "sources": ["pr:241", "thread:t-118", "spec:book-office-hours/Too late to book"],
 "openQuestion": null, "suggest": null, "conflicts": []}
```

**Sources disagree**

```json
{"answer": "Sources disagree. The approved scenario says a student can hold one booking at a time [spec:book-office-hours/One booking at a time], but an open comment from Nia proposes allowing two for Elite students [thread:t-130]. Until that's decided, the agreed rule is one.",
 "covered": "partly", "conflicts": [{"what": "booking limit for Elite students", "sources": ["spec:book-office-hours/One booking at a time", "thread:t-130"]}],
 "openQuestion": null, "suggest": null, "sources": ["spec:book-office-hours/One booking at a time", "thread:t-130"]}
```

## What the builder does with the reply

- **Citations:** renders them as chips. Clicking one opens the slice, scrolls to the scenario, opens the thread, or opens the pull request.
- **Open question:** when `covered` is `no` or `partly`, shows **Raise as an open question**, which posts it to the slice's Discussion as the asker, with the question and Claude's note.
- **Suggestion:** shows **Suggest this scenario**, which adds it as a comment with the usual **Add this scenario** button, so the slice owner decides.
- **Conflicts:** highlights both sources, and offers to start a thread that links them.
- **`@Claude` in a comment:** the answer is posted as a reply in that thread, with a Claude badge.
- **History:** keeps recent questions and answers per project, so repeated questions link to the earlier answer. Answers are recomputed when the slices they cite change.

## Done means
- The first sentence answers the question.
- Every claim has a citation, and nothing comes from outside the model.
- Gaps are named, with an open question offered, not filled.
- Agreed, proposed and built are never mixed up.
- The wording fits the asker: plain for business, precise for engineering.
