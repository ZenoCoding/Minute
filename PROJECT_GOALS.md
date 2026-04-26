# Minute Project Goals

Last updated: February 13, 2026

## Product Mission
Minute helps a single user turn intent into a realistic day plan, then execute it with low friction.

## Primary Goals

1. Fast capture into structured work
- A new task can be captured in under 10 seconds.
- Capture supports natural language for project, date, duration, and recurrence.
- Every captured task lands in an active project.

2. Realistic day planning (capacity-aware)
- The app continuously compares required work vs available time in the active planning day.
- Overload is surfaced early with one-click deferral suggestions.
- Spare capacity is surfaced with one-click pull-forward suggestions from upcoming work.

3. Execution clarity during the day
- The Task Stream answers "what should I do next" without manual triage.
- Completed tasks stay visible for the current planning window to reinforce momentum.
- Calendar context is visible alongside tasks to reduce planning blind spots.

4. Sustainable weekly progress across life areas
- Areas and projects stay easy to manage and reorder.
- Work due this week remains visible and actionable before it becomes urgent.

## Success Signals

- Capture quality: at least 80% of new tasks include either due date or duration.
- Planning quality: fewer end-of-day overdue tasks in "Today" over time.
- Capacity quality: users act on deferral or pull-forward suggestions when prompted.
- Execution quality: consistent daily completion activity in the active planning window.

## Current Scope Boundaries

- Single-user macOS experience first.
- Local-first data model with SwiftData.
- Calendar integration used for planning context, not full calendar replacement.

## Feature Fit Checklist

A new feature is in scope if it clearly improves at least one of these:
- capture speed,
- plan realism,
- execution clarity,
- weekly progress visibility.

If a feature does not move one of those goals, it should be deferred.
