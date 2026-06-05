# Minute

**Minute** is a beautiful, local-first macOS menu bar utility and task manager designed to help you turn intent into a realistic day plan, then execute it with low friction.

---

## Key Features

* **Instant Swift Capture (`Cmd + Shift + J`):** Capture a new task in under 10 seconds. The smart input parser supports natural language parsing for projects, dates, durations, and recurrence.
* **Capacity-Aware Planning:** The app continuously compares required work vs. available time in the active planning day. Overload is surfaced early with one-click deferral suggestions, while spare capacity is highlighted with one-click pull-forward suggestions from upcoming work.
* **Execution Clarity (Task Stream):** A clean feed that answers "what should I do next" without manual triage, showing calendar events alongside tasks to reduce planning blind spots.
* **Menu Bar Extra:** A native macOS menu bar status item that counts down time remaining in your active calendar event or shows the time until your next meeting.
* **Life Areas & Projects:** Simple management of projects grouped by life areas to ensure sustainable progress across all domains of life.

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
