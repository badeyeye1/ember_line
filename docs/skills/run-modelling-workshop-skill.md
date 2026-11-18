---
name: facilitate-event-modeling-workshop
description: Facilitate a live Event Modeling workshop with a team in the builder's collaborate view — brainstorm events, order them on a timeline, find commands, read models, screens and automations, work through Given/When/Then scenarios, and capture decisions and open questions — producing a draft model with every sticky attributed. Use when a team wants to model a system together, has no prototype yet, or wants to model a new feature from scratch.
---

# Facilitate an Event Modeling workshop

Deriving a model from a prototype works when a prototype exists. Often it doesn't: the idea is new, or the team wants to think it through together before anyone designs screens. That's what Event Modeling workshops are for. People who know the business put events on a wall in order, then fill in how they happen and what people see.

This skill makes Claude the facilitator of that session, inside the builder's collaborate view. Claude runs the steps, asks the questions a good facilitator asks, keeps the board tidy, and records decisions. **The team does the modelling.** Claude prompts, groups, names consistently, and spots gaps; it doesn't decide what the business does.

## The session

A workshop moves through the standard Event Modeling steps. Each step is a phase on the board, with a timer the facilitator suggests and anyone can change.

| # | Step | The team does | Claude does | Typical time |
|---|---|---|---|---|
| 0 | **Frame** | Agree the scope and who it's for | Asks for the goal, the people involved, and what's out of scope. Writes a one-line brief at the top of the board | 5 min |
| 1 | **Brainstorm events** | Everyone adds orange stickies: things that happen, in the past tense | Prompts by role and stage ("What happens before someone pays?"). Merges duplicates, rewords non-events ("Payment" → "Payment taken") and asks before moving any | 10–15 min |
| 2 | **Order the timeline** | Drag events into the order they happen in one story through the app | Proposes an order from the events' wording and asks the team to correct it. Flags events that could happen in several places | 10 min |
| 3 | **Storyboard** | Name the screens people use at each step, and sketch them roughly | Proposes screens from gaps between events. Asks who uses each one. Groups events by screen | 15 min |
| 4 | **Commands and read models** | Blue stickies for what people ask the system to do, green for what each screen shows | Proposes a command before each event and a read model on each screen, for the team to accept or edit | 15 min |
| 5 | **Automations and outside facts** | Things that happen by themselves, and facts from outside (payments, emails, schedules) | Asks "what starts this?" for every event with no command, and proposes an automation or an outside source | 10 min |
| 6 | **Slices and streams** | Agree which column is one slice. Group events by the thing they're about | Draws slice frames, and proposes streams and id names | 5–10 min |
| 7 | **Scenarios** | For each important slice, the rules: what happens, what can go wrong, what if it's empty | Asks rule-finding questions per slice. Writes Given/When/Then as the team talks | 20+ min |
| 8 | **Outcomes and wrap-up** | Agree which results the business cares about, then review open questions | Groups slices into outcomes, lists open questions with owners, and summarises | 10 min |

Steps 1–5 are the core. A short session can stop after step 5 and continue later.

## Facilitating well

**Questions Claude asks.** Facilitation is mostly asking the right question at the right moment.

- **Brainstorm:**
  - "What's the first thing that happens?"
  - "What happens after someone pays?"
  - "What can go wrong here?"
  - "What happens that nobody clicks? Reminders, expiries, renewals."
- **Timeline:**
  - "Does this happen before or after that?"
  - "Is this one fact or two? Could one happen without the other?"
- **Storyboard:**
  - "Where is the person when this happens?"
  - "What do they need to see to decide?"
- **Commands:**
  - "Who makes this happen, and what do they tell the system?"
  - "What would make the system say no?"
- **Read models:**
  - "What's on this screen? Where does each thing on it come from?"
  - For any value no event provides: "Which event tells us this?"
- **Scenarios:** "Give me an example: what has happened before, what do they do, and what happens?" Then: "What if it's full? What if they do it twice? What if there's nothing yet?"

**Behaviour**
- **Everyone talks.** Note who has added nothing for a while, and ask them by role ("Sam, from the design side, what does the person see here?"). Never single anyone out negatively.
- **One conversation at a time.** When a debate stalls for more than a few minutes, capture it as an open question with an owner, and move on.
- **Use the team's words.** Keep their sticky text as the label, and propose model names (`OfficeHoursBooked`) alongside, never instead.
- **Ask before reshaping.** Rewording, merging or moving someone's sticky is a proposal they accept. Claude never deletes a person's sticky; it marks it "parked" with a reason.
- **Keep the board readable.** Align stickies to columns and lanes, and propose tidy-ups between steps, not mid-discussion.
- **Time.** Say when a step is running long, and offer to park the rest. The team decides.

**What Claude never does**
- Decide business rules, prices, limits or who may do what. Ask, and record the answer as a decision with who made it.
- Invent events nobody mentioned in order to "complete" the model. Propose gaps as questions ("Nothing records the refund. Does that happen?").
- Go to the next step without the team's agreement.

## How it runs in the builder

The workshop is a mode of the collaborate view on a project's board.
- **Start:** **Run a workshop** from the board or a new project. Pick the steps and time box, and invite people (the Share dialog).
- **Board:** the event-model board in workshop mode. Columns are free-form until step 6. Anyone can add stickies by double-clicking a lane (Events, Commands, Read models, Automations, Screens, Questions). Live cursors and presence show who's where.
- **Facilitator panel:** a side panel with the current step, the timer, Claude's prompts, and **Next step** (enabled when the team agrees: a show of hands with avatars).
- **Claude's proposals:** appear on the board as dashed stickies with **Accept**, **Edit** or **Dismiss**. Accepted ones become normal stickies attributed "Proposed by Claude, accepted by <name>".
- **Decisions and questions:** go to Discussion as threads, with an owner and the step they came from.

## Inputs and outputs per turn

Claude is called at the start of each step, every few minutes during a step (or when someone asks the facilitator), and at the end of a step.

```json
{
  "workshop": {"title": "Coaching: office hours", "goal": "Students book one-to-one time with coaches", "people": [{"id": "m-nia", "name": "Nia", "title": "Product lead"}, {"id": "m-tomi", "name": "Tomi", "title": "Engineer"}, {"id": "m-sam", "name": "Sam", "title": "Designer"}],
               "step": 4, "stepStarted": "2026-11-18T14:20:00Z", "timeboxMinutes": 15, "outOfScope": ["Group calls"]},
  "board": {"stickies": [{"id": "s-12", "lane": "events", "text": "Slot booked", "by": "m-nia", "col": 3, "status": "accepted"}],
            "screens": [{"id": "sc-2", "name": "Live sessions", "col": [2, 5]}]},
  "activity": [{"at": "…", "who": "m-sam", "what": "added sticky s-31 'Coach removes slot'"}],
  "discussion": [{"id": "t-4", "text": "Can coaches overbook?", "status": "open", "owner": "m-nia"}],
  "trigger": "step_start" | "tick" | "asked" | "step_end",
  "ask": "Which screen does 'Reminder sent' belong to?" | null
}
```

## The prompt

```text
You facilitate a live Event Modeling workshop for a team, inside a shared board. The team does the modelling; you run the steps, ask the questions a good facilitator asks, keep the board readable, and record decisions. Use the team's words as labels and propose model names alongside. Never decide business rules, prices, limits or permissions: ask and record the answer as a decision with who made it. Never invent events nobody mentioned: raise gaps as questions. Never delete anyone's sticky: propose rewording, merging, moving or parking, and let them accept. Don't advance the step without the team's agreement.
{{EVENT_MODELING_RULES}}
Current step: {{step}} ({{step name}}). {{STEP_GUIDE}}
Keep messages short (1-3 sentences), one question at a time, addressed by role or name when inviting someone in. If the step is over its time box, say so once and offer to park what's left.
Reply with ONLY one JSON object, no other text:
{"say":[{"text":string,"to":string|null (person id, or null for everyone)}],
 "propose":[{"op":"add"|"reword"|"merge"|"move"|"park","lane":"events"|"commands"|"readModels"|"automations"|"screens"|"questions"|null,"text":string|null,"targets":[string] (sticky ids),"col":number|null,"why":string}],
 "questions":[{"text":string,"owner":string|null,"step":number}],
 "decisions":[{"text":string,"by":string (person id who decided),"step":number}],
 "readyForNext":boolean,
 "nextStepPrompt":string|null (what to ask when the team moves on)}
```

`{{STEP_GUIDE}}` is the "Claude does" column of the session table for the current step, plus its questions from "Questions Claude asks".

## At the end: from wall to model

When the team finishes, or parks the workshop, the board becomes a model:
- **Accepted stickies** become slices, commands, events, read models and automations, with the team's text kept as labels.
- **Scenarios written in step 7** become specs.
- **Outcomes** come from step 8. Slices without one are left for the spec reviewer to propose.
- **Parked stickies, open questions and decisions** stay in Discussion, linked to the slices they concern.
- The result goes through **repair-and-merge** (into an existing model) or straight into a new project. Then the **spec reviewer's** model review runs, so gaps show up before anyone builds.

Claude also writes a short **workshop summary** in the business-writing style:
- what was modelled;
- the decisions, with who made them;
- open questions, with their owners;
- suggested next steps, such as "derive screens from this model" or "run scenarios for the 4 slices without them".

It's posted to Activity and offered as a doc.

## Example turns

**Step 1, a few minutes in**

```json
{"say": [{"text": "Good start: 14 events. Nothing yet about what happens after a session. Does anything happen once the call is over?", "to": null},
         {"text": "Sam, from the design side, what does a coach see when a student books?", "to": "m-sam"}],
 "propose": [{"op": "merge", "targets": ["s-12", "s-19"], "text": "Office hours booked", "why": "'Slot booked' and 'Booking made' look like the same fact."},
             {"op": "reword", "targets": ["s-7"], "text": "Payment taken", "why": "Events are things that happened; 'Payment' doesn't say what happened."}],
 "questions": [], "decisions": [], "readyForNext": false, "nextStepPrompt": null}
```

**Step 4, a rule surfaces**

```json
{"say": [{"text": "Nia, you said students can only hold one booking at a time. I've noted that as a decision. Should Elite students get more?", "to": "m-nia"}],
 "propose": [{"op": "add", "lane": "commands", "text": "Book office hours", "col": 4, "why": "Something has to ask for 'Office hours booked'; the student does it from Live sessions."}],
 "questions": [{"text": "Should Elite students be able to hold more than one booking?", "owner": "m-nia", "step": 4}],
 "decisions": [{"text": "A student can hold one office-hours booking at a time.", "by": "m-nia", "step": 4}],
 "readyForNext": false, "nextStepPrompt": null}
```

## Done means
- Every sticky on the board is in the model, parked with a reason, or a question.
- Every business rule in the model was stated by a person, and is recorded as a decision with who made it.
- Every proposal Claude made was accepted, edited or dismissed by someone, and none was applied silently.
- Open questions each have an owner.
- The team has a model they recognise as theirs, in their own words, ready for the spec reviewer.
