# Invitation rejection feedback

2026-09-12; synthetic development only. User supplied a screenshot of the generic
"Invitation was not confirmed" message after trying test@lh.com. Read-only live
checks confirm zero invitations and zero stock-opening approver roles, and that
authenticated has EXECUTE on the invitation RPC. The underlying rejection has
not yet been identified. Do not infer MFA failure from the generic screenshot.

The gateway now maps known server rejections to safe actionable messages and
reports only a validated diagnostic code for unknown server errors. Raw server
details are not displayed. Invitation and acceptance dialogs display that feedback.
Uncertain transport failures retain their original generic recovery message.
Request keys and submitted email stay unchanged for retry.

Verification: seven desktop tests and four gateway tests passed, including the
new rejection-message and stable-retry checks. Existing 200% golden passes without
baseline updates. Full analyzer: no issues found (145.5 seconds). Four changed
Dart files pass formatting with zero changes. Development Windows release built
successfully in 120.1 seconds using .env.acceptance.json; not launched or manually
accepted by the agent. No migration or database write.

Manual verification after the development rebuild:
1. Open Business setup in JAT / Head Office as the owner.
2. Open Invite stock opening approver, enter test@lh.com and submit once.
3. Report the exact new message or confirm that an invitation and role ID appear.
4. The agent must requery saved state before any subsequent setup action.

The user requested no Computer Use. All native interaction and authentication
are manual. No email delivery is implemented. Root-cause resolution and native
acceptance remain pending until the actual response is observed.
