# Jentra Sales UX and brand review — 30 October 2026

Method: dual-agent. Assessment A `/root/sales_ux_assessment` independently
reviewed the current source and six compiled r5 captures before Assessment B
`/root/sales_ux_evidence` delivered its detector findings. The existing Jentra
mobile design brief and original artwork remain the visual authority.

## Review of the initial preview

The product feels specific to a relationship-led sales workflow: next customer
visit, follow-up orders, exact LKR values and independent approval states.
The shell is conventional but coherent. The initial review scored **25/40**;
this is a design judgment, not production or business acceptance.

| Nielsen heuristic | Initial score /4 | Main observation |
| --- | --- | --- |
| Visibility of system status | 3 | Preview and independent order states clear; review copy premature |
| Match with real world | 3 | Customers, visits and exact values match the work |
| User control and freedom | 2 | Dirty editor could be dismissed without warning |
| Consistency and standards | 3 | Cohesive themes and components; tablet captions absent |
| Error prevention | 2 | Good validation; filtered customer detail could target an old selection |
| Recognition rather than recall | 2 | Tablet icon interpretation required |
| Flexibility and efficiency | 2 | Search and contextual entry work; expert accelerators limited |
| Aesthetic and minimalist design | 3 | Calm hierarchy; narrow Today is long |
| Error recovery | 3 | Clear validation/storage recovery |
| Help and documentation | 2 | Contextual explanations; task help is limited |

Cognitive load is moderate. Seven wider navigation destinations and optional
discount inputs can compete with the primary task. First-time tablet users need
labels; interrupted field users need unsaved-edit protection. Power users will
benefit from faster repeated product entry in a later slice. Entry is calm and
review is reassuring, but silent loss would undermine that reassurance.

## Priorities and implementation response

1. **P1 — Unsaved order loss:** Close, Back and Cancel need a keep/discard
   decision when changed. Added a signature-bound dirty editor guard and tests.
   Drafts still require explicit review/save; no autosave or process-death
   recovery for incomplete unsaved forms is claimed.
2. **P1 — Filtered customer mismatch:** the detail pane must resolve only to a
   visible filtered customer. Added selection reconciliation and a regression
   that searches Metro after selecting Lanka and proves Lanka's contact is gone.
3. **P2 — Phone task density:** the first phone capture put four summary rows
   before the next visit. Two-column normal-text summaries reduce the height;
   large text reflows to one. Agenda-first ordering is a future usability choice.
4. **P2 — Tablet recognition:** added visible captions to the compact rail,
   retaining accessible controls and tooltips.
5. **P2 — Truthful draft copy:** review now says Not saved yet and explains
   the 24-hour local lifetime before the save action.

Remaining refinements: contextual draft filtering, streamlined repeated product
entry, incomplete-form recovery, fuller task help and translated copy. Native
screen-reader, keyboard-only, physical-device and real-company acceptance are
not established by this review.

## Deterministic and browser evidence

Assessment B ran `impeccable detect --json apps/jentra_sales/lib
apps/jentra_sales/web` once: exit 0, complete result `[]`, zero primary findings
or advisories. It provides no scanned-file inventory or demonstrated
Flutter-aware widget analysis. It cannot certify contrast, touch targets,
layout or screen-reader behavior. The output is retained in
`build/sales-release/ux-detector-20261030.json`.

Earlier r5 Chrome evidence passed 1440×1000, 1024×900 and 390×844 with zero
runtime errors, failed requests or backend requests. It demonstrates exact draft
review and reload recovery but predates the final UX edits. The final release
record must bind new captures to the final compiled artifacts.

The [final release record](../verification/jentra-sales-20261030/README.md),
assembled October 31, binds fresh screenshots and source/public SHA-256
manifests to the reviewed build. Ordinary Chrome preview checks pass at all
three sizes. All live flows pass with HTTP/3 disabled; ordinary Chrome live
startup/reload remains intermittent and its latest run passed two of three.
The live screenshots come from the passing TCP run. These results do not close
normal-browser or physical-device acceptance.

Assessment B's fresh localhost tab returned connection refused after the prior
server session ended. No overlay or injected detector ran; no CSP test is claimed
from that attempt. Final deployed browser verification is separate evidence.

## Brand and design-system review

The Marketing brand-guidelines pass applies the existing Jentra identity rather
than creating another brand. Original symbol and wordmark artwork, Manrope,
navy/blue action language, calm surfaces and plain task-specific copy are
retained. No fabricated revenue, quota or conversion benefit is introduced.
The implemented token/component rules are documented in
[`apps/jentra_sales/DESIGN.md`](../../apps/jentra_sales/DESIGN.md).

Questions skipped: the user asked to continue implementation and deployment
under the existing Jentra design brief; no new brand direction is required.
