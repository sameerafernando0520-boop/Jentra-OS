# Assurance A14 — UI/UX and Accessibility Pass

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Governance & Audit screens read as one product: people are chosen by name, not typed IDs; dates, statuses and digests are human-readable; status colours match the design system; nothing is signalled by colour alone; headings are announced; destructive local actions confirm their consequence.

**Inputs:** design-critique and accessibility-review (WCAG 2.1 AA) over the 200% light/dark goldens and source of the Governance workspace, engagement detail, Audit planning, Audit access, Audit metrics and the shell inbox, 20 October 2026.

**Spec:** `docs/superpowers/specs/2026-10-20-assurance-completion-design.md` (section A14)

## Design critique

| Finding | Severity | Recommendation |
|---|---|---|
| Planning asks for "Area owner user ID" and "Lead auditor user ID": a person has to paste a UUID | 🔴 Critical | People picker fed by `api.assurance_access` (planners and engagement managers may read it); labels are names or "Unlinked member ····1234", never e-mails |
| Engagement detail prints full 64-character digests inline; they wrap and dominate each row | 🟡 Moderate | Show `SHA-256 aaaaaaaaaaaa…` with the full value selectable and in a tooltip |
| Statuses and history are raw codes (`fieldwork`, `create_engagement → planning · 2026-10-01T09:00:00Z`) | 🟡 Moderate | Sentence-case labels ("Fieldwork", "Engagement created") and "1 Oct 2026 09:00" |
| Work-item reminder chips use Material `tertiaryContainer` (pink) and `errorContainer`, unlike the KPI cards above them | 🟡 Moderate | `JentraStatusBadge` with the KPI tones: due soon info, overdue warning, escalated danger |
| Dates are ISO in the workspace and planning but "23 Jul 2026" on Audit metrics | 🟢 Minor | One `d MMM y` format across assurance screens |
| "Decide" on a submitted plan does not say what happens | 🟢 Minor | "Approve or return" |

What works: the KPI summary, the access change card that states its consequence before confirming, the metrics cards' samples and definitions, and the inbox's unread semantics.

## Accessibility audit (WCAG 2.1 AA)

| # | Issue | Criterion | Severity | Fix |
|---|---|---|---|---|
| 1 | "High-risk areas not covered" is conveyed by red text only | 1.4.1 Use of colour | 🟡 Major | Warning badge with icon and the word "Not covered" |
| 2 | Engagement-detail and planning section titles are plain text, not headings | 1.3.1 Info and relationships | 🟡 Major | `Semantics(header: true)` on section headings |
| 3 | Raw IDs as the only way to name a person | 3.3.2 Labels or instructions | 🟡 Major | People picker (critique item 1) |
| 4 | Digests are read character by character by screen readers | 4.1.2 Name, role, value | 🟢 Minor | Semantic label "SHA-256 starting …" on the short form |
| 5 | "Discard draft" discards an encrypted local draft immediately | 3.3.4 Error prevention (guidance) | 🟢 Minor | Confirmation dialog stating what is lost |

Contrast (computed from tokens): textSecondary on panel 5.34:1, on app background 4.97:1; info/warning/danger/success on their surfaces 6.29/6.29/5.98/5.93:1; dark textSecondary on dark panel 8.47:1; strong input border 3.41:1 (1.4.11). All pass AA. Keyboard: period chips, change-access and response controls are reachable (existing tests).

## Tasks

### Task 1: Shared formatting
**Files:** `apps/jentra_desktop/lib/src/features/assurance/assurance_format.dart`, test.
**Interface:** `auditDate(String iso)`, `auditDateTime(String iso)`, `auditLabel(String code)`, `shortDigest(String sha)`, `DigestText` widget.
- [ ] Tests, implement, commit.

### Task 2: Workspace and engagement detail
- [ ] Reminder badges with KPI tones; formatted dates; labelled statuses; short digests; humanised history; heading semantics; Discard draft confirmation. Goldens refreshed (intentional). Commit.

### Task 3: Planning
- [ ] People picker for area owner and lead auditor from `AssuranceAccessGateway.access` (all pages); uncovered high-risk badge; "Approve or return"; heading semantics; formatted dates; Discard draft confirmation. Goldens refreshed. Commit.

### Task 4: Full suite, analyzer, docs, PR against A13.
