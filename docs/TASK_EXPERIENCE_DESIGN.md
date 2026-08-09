# Minute Task Experience Design

## Product contract

This change strengthens one task experience across capture, execution, and planning without creating a second planning model. A task still has one `dueDate`, which remains a deadline. The forecast reads deadlines and capacity but never writes dates. There is no `plannedDate`, Today flag, priority matrix, nested task tree, timebox, habit game, or automatic task-suggestion engine.

The interaction model stays progressive-disclosure and keyboard-friendly:

- capture remains a one-line fast path;
- the row exposes only completion plus a primary work control and an overflow control on hover/focus;
- the same actions are available from the context menu;
- double-click still opens details, title editing remains inline, and existing keyboard submission/cancellation behavior is preserved;
- destructive or broad mutations are undoable in the current app session, with explicit persistence errors surfaced rather than silently ignored.

## 1. Task actions

### Row and menu hierarchy

The resting row remains visually quiet. Hovering or keyboard focus reveals:

1. **Start Work / Stop Working** as the single primary action.
2. An **Actions** overflow menu containing:
   - Reschedule: Today, Tomorrow, Next Saturday, and Choose Date;
   - Clear Date when a date exists;
   - Move to Project;
   - Duplicate;
   - Edit Task;
   - Delete.

The context menu mirrors this command set. Existing editable project/date/duration/recurrence badges remain direct manipulation paths. Each control has a tooltip and accessibility label, and opening a menu must not steal the inline-title keyboard path.

### Semantics and reversibility

- `dueDate` keeps its existing meaning. Presets use the existing day-only normalization. Moving a timed deadline to another day preserves its wall-clock time when possible; moving a day-only deadline remains day-only.
- Clear Date sets only `dueDate` to `nil`.
- Move Project changes only the relationship and records the existing project-inference memory signal.
- Duplicate creates an incomplete sibling in the same project with the same deadline, duration, recurrence, notes, and checklist titles/completion state. It receives a fresh task UUID, fresh checklist UUIDs, no completion timestamp, and no active-work state.
- Start Work stores an optional `workStartedAt`. Starting one task clears `workStartedAt` on any other task, making the current work focus unambiguous. Stop Working clears it. This is an execution cue only: it does not create a timer entry, alter duration, change order, or mutate the deadline.
- Completion uses the centralized data service. Completing a task stops work on it and completes remaining checklist items. Reopening the task keeps the checklist content and allows checklist state to be edited.
- Mutating row actions register an undo operation where practical. Duplicate undo deletes the new copy; delete undo is implemented through a captured task snapshot rather than attempting to reinsert an invalidated SwiftData object.

## 2. Academic task structure

### Data model and migration

`TaskItem` gains two additive optional/defaulted fields:

- `notes: String?`
- `workStartedAt: Date?`

It also gains an optional to-many relationship to a new `TaskChecklistItem` model. A checklist item has a stable UUID, title, completion state/timestamp, order index, creation date, and an optional inverse task relationship. The relationship is cascade-delete and exposed through a compatibility facade that treats missing storage as an empty list.

The schema change is intentionally lightweight and backward-compatible:

- no existing property is renamed or retyped;
- every new scalar is optional or defaulted;
- new relationships are optional with explicit inverses for SwiftData/CloudKit compatibility;
- the existing store URL is unchanged;
- migration is verified against a copy/backup of the user's current store before the Release app is installed.

### Editing and capture

The edit sheet becomes the progressive details surface:

- title, project, due date, duration, and recurrence remain compact at the top;
- Notes is a lightweight multiline field with no rich-text system;
- Checklist is one ordered level with quick add, inline rename, check/uncheck, reorder, and remove;
- there is no nesting, dependency graph, or conversion into child `TaskItem` records;
- Save applies the draft atomically; Cancel leaves the task and its checklist unchanged.

Fast capture stays one-line. After creation, the existing edit-created-task route remains the way to add notes/checklist details; no required modal interrupts capture. Task rows may show a compact notes/checklist summary, but not the full notes body.

### Completion behavior

- Completing the parent marks every checklist item complete and stops active work.
- Completing the final remaining checklist item completes the parent.
- Unchecking any checklist item reopens the parent, because an assignment with unfinished required steps is not complete.
- Reopening the parent directly does not erase checklist progress.
- Checklist order and state survive task duplication and local API round trips.

### Local command API

The version-1 protocol is extended additively so existing clients remain valid:

- task create/update accepts `notes`, `clearNotes`, and a shallow `checklist` array;
- task snapshots include notes, work state, and ordered checklist snapshots;
- a checklist supplied on update replaces the shallow list atomically, which keeps request semantics deterministic and idempotent;
- CLI flags cover notes and repeatable checklist items while raw JSON remains available for exact state;
- no existing field, action, or receipt shape is removed.

## 3. Seven-day deadline forecast

### Question answered

The forecast answers: **“Given what is due and the time actually available, where will deadline pressure appear, and by which day does that work need to begin?”** It does not answer “What should I do next?” and does not mutate tasks.

### Inputs and calculations

For the current planning day plus six upcoming planning days, the forecast uses:

- incomplete tasks in active projects;
- each task's existing `dueDate` and positive `estimatedDuration`;
- the optional duration fallback only when the user already enabled it;
- sleep-aware planning windows from `DayCapacityService`;
- merged calendar busy intervals from `CalendarManager` when full read access exists;
- project identity/color for workload attribution.

Each day reports:

- available work time after calendar commitments;
- work whose deadline falls on that day;
- cumulative work due by that day versus cumulative capacity through that day;
- unknown-duration task count, which prevents an unqualified “safe” status;
- pressure state: comfortable, tight (at least 85% cumulative utilization), or overloaded.

Overdue work rolls into the first forecast day. Day-only deadlines remain associated with their visible calendar day; timed deadlines use their actual time when determining available capacity before the deadline.

“Begin by” is a derived warning, not a stored plan. For each deadline/project cohort, the service walks available daily capacity backward from the deadline until it can cover cumulative known work due by then. The earliest day touched is shown as the latest safe start. Unknown durations are called out separately and never treated as zero effort.

### Presentation

The right-side Pulse dashboard gains a **7-Day Forecast** card above Areas & Projects:

- a headline identifies the next tight/overloaded deadline horizon or confirms known work fits;
- seven compact day rows show required versus available time and a pressure bar;
- expanded/high-pressure rows show project-level workload and a plain-language “Work due Friday needs to begin by Wednesday” explanation;
- calendar-disabled state labels capacity as schedule-only rather than pretending calendar time is free;
- the card has no buttons that reschedule, pull forward, or suggest individual tasks.

This keeps the forecast informational and deadline-centered, leaving the separate task-suggestion experience to its own design.

## Ownership and integration boundaries

Implementation is partitioned so workers do not edit the same files:

- **Academic foundation worker:** model, schema, service, command protocol/CLI/docs, and foundation/API tests.
- **Academic editor worker:** edit-sheet notes/checklist presentation and atomic draft behavior.
- **Task actions worker:** stream-row hover/context actions, work-focus presentation, undo behavior, and action-focused tests.
- **Forecast worker:** capacity forecast calculations, Pulse forecast presentation, and forecast tests.

Sol owns cross-slice contracts, project-wide integration, migration/store validation, conflict resolution, final diff review, all build/test escalation, visual QA, Release installation, process/API readiness, and rollback documentation.
