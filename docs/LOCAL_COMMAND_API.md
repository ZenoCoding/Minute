# Minute Local Command API

Minute exposes a local, file-backed command API for trusted scripts and coding agents on the same Mac. It does not run an HTTP server and does not require UI automation.

The API currently supports every persisted Minute entity:

- `Area`
- `Project`
- `TaskItem`

Each entity can be created, listed, retrieved, updated, and deleted.

## Install

Build and run the current Minute app, then install the CLI:

```bash
./scripts/install-minute-cli.sh
```

The installer symlinks `bin/minute` to `~/.local/bin/minute`. If that directory is not on `PATH`, invoke the repository script directly or add it to your shell path.

## CLI

Check that the installed app can process commands:

```bash
minute ping --json
```

Create an area:

```bash
minute area "School" \
  --color 5856D6 \
  --icon graduationcap \
  --json
```

Create a project:

```bash
minute project "COSMOS" \
  --area "School" \
  --status active \
  --weekly-goal 5h \
  --json
```

Create a task using Minute's natural-language parser:

```bash
minute task "Draft the research abstract tomorrow for 45m" \
  --project "COSMOS" \
  --json
```

Create a task using explicit structured values:

```bash
minute task "Submit research abstract" \
  --project "COSMOS" \
  --due "2026-06-08T17:00:00-07:00" \
  --duration 45m \
  --recurrence weekly \
  --no-parse \
  --json
```

View current data:

```bash
minute list areas --json
minute list projects --area "School" --status active --json
minute list tasks --project "COSMOS" --incomplete --json
minute get task TASK_UUID --json
```

Update data:

```bash
minute update area "School" --name "Academics" --color 007AFF --json
minute update project "COSMOS" --status backlog --weekly-goal 3h --json
minute update task TASK_UUID --title "Submit final abstract" --completed --json
minute update task TASK_UUID --clear-due --clear-duration --json
```

Delete data:

```bash
minute delete task TASK_UUID --yes --json
minute delete project PROJECT_UUID --recursive --yes --json
```

Areas and projects use cascading SwiftData relationships. Deleting either one when it contains child data requires `--recursive`; every CLI deletion also requires `--yes`.

Durations accept minutes (`45`), compact units (`45m`, `2h`), or combinations (`1h30m`). Explicit dates use ISO-8601. Without `--project`, project parsing is attempted and weak or missing matches fall back to `Inbox`.

An explicitly named project or area must already exist. This makes spelling errors fail visibly instead of silently creating or misfiling data. Projects without `--area` are placed under `Unsorted`.

## Codex Usage

Codex should use the CLI and request JSON output:

```bash
minute task "Review pull request tomorrow for 30m" --project "Minute" --json
```

Before editing existing data, list or retrieve it and use the returned UUID:

```bash
minute list tasks --project "Minute" --incomplete --json
minute update task 778FB302-1EF5-4F97-80BA-D3CC6E6541FB \
  --due "2026-06-08T17:00:00-07:00" \
  --json
```

For multiple related entities, create them in dependency order:

```bash
minute area "Research" --json
minute project "Agent Evaluation" --area "Research" --json
minute task "Define the first benchmark" --project "Agent Evaluation" --json
```

No computer-use tool, accessibility permission, browser, or network request is required.

## Request Protocol

The CLI atomically writes requests to:

```text
~/Library/Containers/com.tychoyoung.Minute/Data/Library/Application Support/Minute/Commands/inbox/
```

Minute processes them through `MinuteDataService`, saves SwiftData, and writes receipts to:

```text
~/Library/Containers/com.tychoyoung.Minute/Data/Library/Application Support/Minute/Commands/receipts/
```

The CLI launches `com.tychoyoung.Minute` when necessary and waits for the receipt.

Supported action values are `create`, `list`, `get`, `update`, `delete`, and `ping`.

### Task Request

```json
{
  "version": 1,
  "requestID": "0ba23718-f92c-44b4-9769-6267015ee406",
  "action": "create",
  "entity": "task",
  "payload": {
    "text": "Submit research abstract",
    "project": "COSMOS",
    "dueDate": "2026-06-08T17:00:00-07:00",
    "durationSeconds": 2700,
    "recurrence": "weekly",
    "parseNaturalLanguage": false,
    "orderIndex": 0
  }
}
```

Task fields:

| Field | Required | Meaning |
| --- | --- | --- |
| `text` | yes | Task text or literal title |
| `project` | no | Exact existing project name |
| `dueDate` | no | ISO-8601 date and time |
| `durationSeconds` | no | Estimated duration |
| `recurrence` | no | `daily` or `weekly` |
| `parseNaturalLanguage` | no | Defaults to `true` |
| `orderIndex` | no | Explicit task ordering value |

### Project Request

```json
{
  "version": 1,
  "requestID": "04eb73f6-fdf9-4088-9589-6c306594ce34",
  "action": "create",
  "entity": "project",
  "payload": {
    "name": "COSMOS",
    "area": "School",
    "status": "active",
    "weeklyGoalSeconds": 18000,
    "orderIndex": 0
  }
}
```

Project status may be `active`, `backlog`, `completed`, or `archived`. The named area must exist. Omitting `area` uses `Unsorted`.

### Area Request

```json
{
  "version": 1,
  "requestID": "a2fd5048-f1d2-45dd-a5c4-c1642406b0c0",
  "action": "create",
  "entity": "area",
  "payload": {
    "name": "School",
    "themeColor": "5856D6",
    "iconName": "graduationcap",
    "orderIndex": 0
  }
}
```

### Receipt

```json
{
  "displayName": "Submit research abstract",
  "entity": "task",
  "entityID": "778FB302-1EF5-4F97-80BA-D3CC6E6541FB",
  "message": "Created task 'Submit research abstract'.",
  "processedAt": "2026-06-07T00:00:00Z",
  "requestID": "0ba23718-f92c-44b4-9769-6267015ee406",
  "status": "success",
  "version": 1,
  "items": [
    {
      "entity": "task",
      "id": "778FB302-1EF5-4F97-80BA-D3CC6E6541FB",
      "name": "Submit research abstract",
      "project": "COSMOS",
      "area": "School",
      "isCompleted": false,
      "estimatedDuration": 2700,
      "dueDate": "2026-06-09T00:00:00Z"
    }
  ]
}
```

`list` returns every matching snapshot in `items`; `get`, `create`, `update`, and `delete` return one snapshot. Error receipts use `"status": "error"` and put the failure reason in `message`.

## Selection and Safety

- UUIDs are the preferred identifiers for reads and mutations.
- Exact case-insensitive area/project names are accepted when unique.
- Exact case-insensitive task titles are accepted only when unique.
- Ambiguous labels return an error and require a UUID.
- Explicit project and area references must exist.
- Project deletion requires `recursive: true` when tasks exist.
- Area deletion requires `recursive: true` when projects exist.
- The CLI requires `--yes` for every delete operation.

## Raw Requests

Send a complete request from a file:

```bash
minute request request.json --json
```

Or use stdin:

```bash
printf '%s\n' '{"version":1,"requestID":"test-ready","action":"ping"}' |
  minute request --json
```

## Reliability

- Request files are written with an atomic rename, so Minute never reads partial JSON.
- `requestID` is an idempotency key stored on created entities.
- Reusing a request ID returns the existing receipt instead of creating a duplicate.
- If Minute saves an entity and exits before writing its receipt, retrying the request finds the entity by `requestID`.
- Commands are local to the current macOS account and inherit the security of that account.

Calendar events are deliberately not accepted by this API. A task command cannot silently turn into an EventKit event.
