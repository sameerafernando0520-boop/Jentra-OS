# Assurance A10 — Reminders and Notification Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Due-soon, overdue and escalated audit work reaches people as in-app notices they can see and act on, from a real notification inbox in the desktop shell.

**Architecture:** A candidate API scans the scope's open work (A9's tenant-aware `assurance.work_items`) and inserts at most one `workflow.notifications` row per item, level and recipient (partial unique index), pointing at the engagement through `aggregate_type = 'assurance_engagement'`. The desktop shell replaces the placeholder bell with an inbox over the existing `api.my_notifications` view and `api.mark_notification_read`, and shows the signed-in user's initials. The Governance workspace gains an Overdue summary, a Send reminders action and a once-a-day automatic scan for leads.

**Tech Stack:** PostgreSQL / Supabase, Dart 3, Flutter, Riverpod, shared_preferences (already a dependency).

**Spec:** `docs/superpowers/specs/2026-10-20-assurance-completion-design.md` (section A10)

## Global Constraints

- Scan authority: `assurance.engagement.manage` in scope; authority before replay; recent MFA not required (no data changes, idempotent).
- Notice type `assurance.reminder`; `source_context = {due_key: '<item_id>:<level>', level, kind, engagement_id}`; unique per (tenant, recipient, type, due_key). Titles and bodies name the engagement and item kind only — never evidence text or finding detail.
- Recipients: the item owner for every level; for `escalated` also the engagement's lead auditor; only active members.
- 100 items per call ordered by item id; receipt `{examined, emitted, has_more, next_after}`; idempotency in `assurance.command_receipts`.
- Inbox: newest first, 20 per page, unread count badge hidden at 0, mark one read, mark all read (one call per unread notice, sequential, stops on first failure), link opens `/governance/audit` with the engagement for `assurance_engagement` notices.
- Automatic scan: at most once per calendar day per (tenant, entity, branch) per device, only for holders of `assurance.engagement.manage`, never blocking the workspace; failures are shown, not retried in a loop.
- Candidate file `supabase/candidates/20261020150000_assurance_reminders.sql`; builder `-Slice A10` = A9 + this.

## Review Focus

1. Two leads open the workspace the same morning — expected: one notice per item/level/recipient (unique index), both scans succeed; test in Task 1.
2. Owner is also the lead of an escalated item — expected: one notice, not two; test in Task 1.
3. More than 100 open items — expected: paging with `next_after`, the client keeps calling until `has_more` is false (bounded to 20 pages); test in Tasks 1 and 3.
4. Inbox while offline or signed out — expected: bell shows no badge and the list explains it is unavailable; no errors thrown; test in Task 4.
5. Marking a notice that changed elsewhere (version conflict) — expected: list refreshes, no crash; test in Task 4.

---

### Task 1: Candidate migration and rollback suite

**Files:** Create `supabase/candidates/20261020150000_assurance_reminders.sql`, `supabase/assurance_tests/assurance_reminders_test.sql`; modify the builder (A10) and regenerate the CI file from `-Slice A10 -Pgtap`.

**Interfaces (SQL):** `api.assurance_scan_reminders(p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid, p_idempotency_key uuid, p_payload jsonb) returns jsonb` — payload exactly `{after_id: uuid|null}`; partial unique index `assurance_reminder_identity` on `workflow.notifications(tenant_id, recipient_id, notification_type, (source_context->>'due_key')) where notification_type = 'assurance.reminder'`.

- [ ] Fragment (≈20 assertions, self-contained on A1 fixtures): authority (owner refused, outsider refused); an engagement in fieldwork with an evidence request due tomorrow (`due_soon`), one 2 days late (`overdue`) and one 10 days late (`escalated`) owned by `owner`; first scan emits 4 (3 to owner + 1 to the lead for the escalated one), a second scan with a new key emits 0; replay with the same key returns the same receipt; changed body on the same key → `IDEMPOTENCY_MISMATCH`; notice fields (type, aggregate type/id, title without request text, source_context level and due_key); owner as lead of an escalated item receives one notice; a request on track emits nothing; 101 due items page as 100 + 1 with `next_after`.
- [ ] RED on the development project (function absent), write the candidate, GREEN, commit `Add assurance A10 reminders candidate`.

### Task 2: Domain and platform

**Files:** Create `packages/jentra_domain/lib/src/notification_inbox.dart` (export from `jentra_domain.dart`), `packages/jentra_domain/lib/src/assurance_reminders.dart` (export from `jentra_assurance.dart`); create `packages/jentra_platform/lib/src/supabase_notification_inbox_gateway.dart` (export from `jentra_platform.dart`); extend `AssuranceGateway`? No — add `AssuranceReminderGateway` in `supabase_assurance_reminder_gateway.dart` (export from `jentra_assurance_platform.dart`). Tests alongside.

**Interfaces:**
- `final class InboxNotice { InboxNotice.fromJson(Map); final String id, type, title, body; final String? aggregateType, aggregateId; final bool unread; final int version; final DateTime createdAt; String? get engagementId; }` (engagementId only for `assurance_engagement`).
- `abstract interface class NotificationInboxGateway { Future<List<InboxNotice>> latest(String tenantId, {int limit = 20}); Future<int> unreadCount(String tenantId); Future<void> markRead(String tenantId, InboxNotice notice); }` and `SupabaseNotificationInboxGateway(SupabaseClient)`; `markRead` maps a version conflict to `DomainError('VERSION_CONFLICT')`.
- `typedef ReminderScan = ({int examined, int emitted, bool hasMore, String? nextAfter});` `ReminderScan assuranceReminderScanFromJson(Map)`.
- `abstract interface class AssuranceReminderGateway { Future<ReminderScan> scan(TenantContext scope, String idempotencyKey, {String? after}); }` and `SupabaseAssuranceReminderGateway`.

- [ ] TDD each parser and gateway (request shape, invalid responses rejected, error mapping). Commit `Add notification inbox and reminder scan clients`.

### Task 3: Workspace reminders

**Files:** Modify `assurance_workspace_controller.dart`, `assurance_workspace_screen.dart`, `lib/main.dart`; create `lib/src/features/assurance/reminder_scan_log.dart`. Test: extend `assurance_workspace_test.dart`; goldens updated only if the workspace layout changes intentionally.

**Interfaces:** `abstract interface class ReminderScanLog { Future<String?> lastScan(String scopeKey); Future<void> record(String scopeKey, String date); }`, `SharedPreferencesReminderScanLog`, `MemoryReminderScanLog` (tests); providers `assuranceReminderGatewayProvider`, `reminderScanLogProvider`; controller `Future<void> sendReminders()` (pages until done, max 20 calls, message "Sent N reminders." / "Everyone is already reminded."), automatic `sendReminders` once per day from `initialize()` when the capability is held.

- [ ] Failing tests: Overdue card shows counts by level; Send reminders pages twice when `has_more`; auto-scan runs once per day per scope and not for viewers; scan failure shows an error and leaves the queue visible. Implement; run file + analyzer. Commit `Send audit reminders from the workspace`.

### Task 4: Shell inbox and avatar

**Files:** Create `lib/src/shell/notification_inbox.dart`; modify `lib/src/shell/jentra_shell.dart` (bell and avatar), `lib/main.dart`. Test `test/notification_inbox_test.dart` with 200% light/dark goldens of the open inbox.

**Interfaces:** `notificationInboxGatewayProvider`, `inboxControllerProvider` (`InboxController extends ChangeNotifier`: `refresh()`, `markRead(InboxNotice)`, `markAllRead()`, `notices`, `unread`, `error`), `NotificationBell` widget (badge with count, opens an anchored panel), `signedInUserProvider` → `({String initials, String tooltip})` from the session user's name or e-mail.

- [ ] Failing tests: badge hidden at 0 and shows the count; opening lists notices newest first with unread styling; tapping an assurance reminder marks it read and navigates to the engagement; mark all read; offline shows "Notifications are unavailable offline"; version conflict refreshes; avatar initials from name, then e-mail. Implement; full desktop suite; analyzer. Commit `Add the notification inbox and signed-in avatar to the shell`.

### Task 5: Docs and PR

- [ ] Status "Slice A10" table, verification JSON; push `assurance/a10-reminders`; PR against `assurance/a9-settings`.
