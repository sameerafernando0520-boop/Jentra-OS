# Assurance A16 — UI/UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Governance workspace and Audit planning look and behave like the newer audit screens (Audit access, Audit metrics): dates are picked, not typed; lists are design-system panels with status badges; every empty, loading, offline, denied and error state says what happened and what to do next; every audit screen shares one header.

**Decision:** owner's review of the built product, 20 October 2026 (area 4 of the spec-change review: date pickers, card layouts, empty and error states, header consistency). Roles, settings, reminders and metrics stay as built.

**Tech Stack:** Flutter, `jentra_design_system` (JentraPanel, JentraStatusBadge, JentraEmptyState, JentraSectionHeader).

## Global Constraints

- No behaviour change: the same commands, payloads and drafts; only presentation and input.
- Dates are stored as `YYYY-MM-DD` exactly as before; the picker shows "8 Oct 2026".
- Every interactive element stays keyboard-reachable with a visible focus and a semantic label; 200% text without clipping; light and dark.
- Goldens are refreshed only for these intentional changes.

## Tasks

### Task 1: Shared widgets
**Files:** `assurance_format.dart` (or `assurance_widgets.dart`), test.
- [x] `AuditDateField` (label, ISO value, onChanged, enabled; opens the date picker on tap, Enter or Space; announces "label, 8 Oct 2026").
- [x] `auditStatusTone(String)` mapping statuses to badge tones.
- [x] `AuditScreenHeader` (title, description, refresh icon button with tooltip).

### Task 2: Governance workspace
- [x] Header; empty/denied/offline/error states with next steps; work items and the engagement register as panels with status badges; engagement detail rows as panels with status badges and actions; date pickers for the response due date and evidence due date. Tests and goldens.

### Task 3: Audit planning
- [x] Header; empty/denied/offline/error states; universe areas, plans and planned areas as panels with status badges; date pickers for the plan period. Tests and goldens.

### Task 4: Full suite, analyzer, docs, PR against A15.
