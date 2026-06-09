# Minute

**Minute** is a beautiful, local-first macOS menu bar utility and task manager designed to help you turn intent into a realistic day plan, then execute it with low friction.

---

## Key Features

* **Instant Swift Capture (`Cmd + Shift + J`):** Capture a new task in under 10 seconds. The smart input parser supports natural language parsing for projects, dates, durations, and recurrence.
* **Capacity-Aware Planning:** The app continuously compares required work vs. available time in the active planning day. Overload is surfaced early with one-click deferral suggestions, while spare capacity is highlighted with one-click pull-forward suggestions from upcoming work.
* **Execution Clarity (Task Stream):** A clean feed that answers "what should I do next" without manual triage, showing calendar events alongside tasks to reduce planning blind spots.
* **Menu Bar Extra:** A native macOS menu bar status item that counts down time remaining in your active calendar event or shows the time until your next meeting.
* **Life Areas & Projects:** Simple management of projects grouped by life areas to ensure sustainable progress across all domains of life.
* **Local Command API:** A lightweight `minute` CLI lets Codex and local scripts create areas, projects, and tasks without UI automation or a network server.

---

## Architecture & Tech Stack

* **OS:** macOS 14.0+ (Sonoma) or newer
* **Framework:** Native **SwiftUI**
* **Persistence:** Local-first data model powered by **SwiftData** (`Area.self`, `Project.self`, `TaskItem.self`)
* **Calendar Integration:** Integrated with the macOS calendar store using **EventKit** via `CalendarManager` to display meetings alongside tasks

---

## How to Build & Run

1. Open `Minute.xcodeproj` in Xcode.
2. Select your macOS target.
3. Build and run (`Cmd + R`).
4. Grant Calendar access to enable the menu bar meeting integration.

## Local Command API

Install the repository's CLI:

```bash
./scripts/install-minute-cli.sh
```

Then create any of Minute's persisted entity types:

```bash
minute area "School" --color 5856D6 --icon graduationcap
minute project "COSMOS" --area "School" --weekly-goal 5h
minute task "Draft the abstract tomorrow for 45m" --project "COSMOS" --json
minute list tasks --project "COSMOS" --incomplete --json
minute update task TASK_UUID --completed --json
```

Minute launches automatically when needed and returns machine-readable entity snapshots. It supports create, list, get, update, and guarded delete operations. See [docs/LOCAL_COMMAND_API.md](docs/LOCAL_COMMAND_API.md) for the request schema, idempotency behavior, and automation examples.
