# Mobile design brief — Jentra Employee and Jentra Sales

**Date:** 2026-10-08  
**Status:** Draft mobile extension of Jentra Flow; no mobile screens have been implemented or visually accepted.  
**Source of truth:** [Jentra design system](../04_DESIGN_SYSTEM.md), [current tokens](../../../packages/jentra_design_system/lib/src/tokens.dart), [theme](../../../packages/jentra_design_system/lib/src/theme.dart), [components](../../../packages/jentra_design_system/lib/src/components.dart) and supplied brand assets.

## Overview

Keep Jentra's existing identity: **Operate. Connect. Grow.** Calm navy foundations, clear blue actions, exact values and restrained cyan/teal identity accents support practical work. Both apps should feel like Jentra while making their different daily tasks immediately clear.

The employee app is personal and private: today's work, own requests and understandable pay. The salesman app supports fast field work: select an assigned customer, build an order and follow its real next step. Neither app should reuse the desktop sidebar, dense administrative editors or unrestricted employee/customer lists.

The existing desktop employee light and quotation dark golden images were inspected as historical visual references and compared with the current palette/source. They establish an incumbent brand direction, not fresh phone render evidence. Mobile navigation, layouts and sizes below are proposed extensions. New mobile screen previews and physical-device walkthroughs remain release gates.

## Colors

Use the existing semantic tokens; validate both themes. This table records extracted values rather than creating a replacement palette.

| Role | Light | Dark | Application |
|---|---|---|---|
| Canvas | `#F4F7FA` | `#041321` | Quiet app background |
| Panel | `#FFFFFF` | `#0B2238` | Readable operational content |
| Primary text | `#10283F` | `#F4F7FA` | Titles and values |
| Secondary text | `#5B6D7E` | `#ACBECE` | Supporting labels and source dates |
| Primary action | `#0064D9` | `#68B7FF` | One clear next step |
| Control boundary | `#7C8D9E` | `#71889D` | Field/button outlines |
| Success foreground / surface | `#00695C` / `#E7F6F0` | `#95E4C4` / `#12392F` | Verified business result with icon and text |
| Warning foreground / surface | `#8A4A00` / `#FFF4DE` | `#FFD58A` / `#3C2D15` | Reviewable stale/conflict/hold state |
| Danger foreground / surface | `#B42318` / `#FFF1F0` | `#FFB4AE` / `#41282D` | Failed/rejected action with recovery |

Jentra navy, connect cyan, flow teal and growth lime retain their existing identity roles. Lime is a small brand accent, not the primary button or an automatic approval signal. Use the original folded J and wordmark assets without redrawing, stretching or recoloring. Gradients belong to a restrained identity moment, not under pay, prices or state information.

**State rule:** Color never establishes whether a salary is paid, an order is approved or goods are delivered. Use exact label, icon, actor/source and timestamp when needed.

## Typography

Retain bundled **Manrope** for UI, **IBM Plex Mono** for exact amounts/identifiers, and **Noto Sans Sinhala/Tamil** fallbacks. The actual supplied wordmark remains an image asset; a typed app title may identify Employee or Sales beside it without imitating the lettering.

Proposed phone scale: page title 24–28 logical px, section title 20, body 16, persistent field label 14 and supporting text 13. These are mobile proposals, not claims about existing desktop sizes. Use 1.4–1.5 line height and allow content to grow at 200% text. Never shrink a salary or quantity to fit.

Right-align amounts in comparisons, show currency and unit, preserve exact values in detail, and format overview summaries only under the authoritative policy. For entry, use appropriate numeric keyboards and explicit localized parsing/validation; a decimal/group separator must not silently change the intended number. Show the normalized value before material submission.

## Layout

Proposed phone reference widths: 360, 390 and 430 logical px. Test the actual lowest-spec devices and OS minimums selected in release planning. Use safe-area insets, 16 logical-px content gutters, the existing 4/8/12/16/20/24/32 spacing scale and one-column task flows. At 600+ logical px, use an adaptive rail and two-pane list/detail only where readable; this does not alter the Windows shell.

Touch controls use at least 48 logical px on Android and 44 pt on iPhone; never inherit compact desktop control height. Sticky actions must remain above the keyboard/safe area, must not obscure validation, and must scroll into a reachable position at enlarged text. Use full pages for long forms and limited bottom sheets for short choices.

| Employee Home order | Sales Today order |
|---|---|
| Workspace/employee context and inbox | Workspace/portfolio context and inbox |
| Today's published work and next action | New order and next assigned visit |
| Own pending leave/attendance/HR requests | Customer acceptance/company decision tasks |
| Latest available payslip entry, amounts hidden until authorized/opened | Dispatch/delivery exceptions and next follow-up |
| Quiet access to profile/documents/help | Scoped customer search and draft recovery |

Employee navigation is Home, My work, Leave, Pay and More. Sales navigation is Today, Customers, Orders and More. Keep labels visible; if text scaling prevents a usable five-item layout, move secondary employee destinations into More without removing access.

For order entry, select the customer first, then add/search products, edit unit/quantity and permitted discount, review terms/totals, and submit. Avoid a spreadsheet reduced to phone width. For payroll, summary leads to components and linked correction history, then Ask payroll. In confirmation detail, show customer acceptance, company approval and delivery acknowledgement as three separate records.

## Elevation & Depth

Follow the incumbent flat panels, subtle borders and tonal layers. Reserve elevation for floating menus/dialogs/sheets. Do not use large shadows, glass effects or decorative charts behind operational content. Match native back navigation, keyboard and focus expectations.

Existing motion tokens are 120/180/240 ms. Use them for local transition feedback without postponing state updates; reduce nonessential animation when the system requests reduced motion. Do not animate a pending action into an apparent success before server confirmation.

## Shapes

Retain the existing 8px control, 14px panel and 20px dialog radii. Use pills for status/filter chips; navigation and action buttons retain clear touch regions and visible labels. At high text scale, chips and rows wrap or grow instead of clipping or shrinking their contents.

## Components

Existing brand, semantic colors, panel, button and status primitives are reusable after mobile verification. These additional patterns are proposed, not shipped widgets:

| Pattern | Required states and behavior |
|---|---|
| Mobile scope header | Exact employee/portfolio context, allowed workspace switch, inbox; no combined cross-tenant totals |
| Work/status card | Published/recorded/pending/exception labels, source date and next allowed action |
| Leave balance panel | Available/used/pending, expiry/carry context; provider error distinct from zero |
| Payslip explanation | Period/currency/totals then line basis/rate/rounding and correction links; hide app-switcher preview |
| Customer row/detail | Assigned customer, useful contact/context and next action; no unsourced priority score |
| Product/quantity editor | Authorized unit/price, exact quantity and discount rules, inline errors and visible saved-local state |
| Before/after comparison | Material local-versus-current fields, source revisions and explicit Review updated terms action |
| Confirmation timeline | Distinct customer/company/delivery records; Pending response, Credit hold and Partial receipt remain separate |
| Draft/recovery state | Saved on this device, Ready to review, Sending, Outcome unknown, Confirmed or Rejected; one safe next action |
| Attachment control | Permission denial, reserved/uploading/scanning/available/failed; no fake completed upload |
| Private inbox | Real events, unread/read state and current authorized route; generic lock-screen notification |

Every screen specifies loading, empty, denied, offline, stale, validation failure, outcome unknown and confirmed states as applicable. Say **Saved on this device — submit when connected**, **Checking whether your order was saved**, **Price changed — review updated terms**, or **Request submitted — awaiting HR**. Do not expose RPC names or internal evidence-check terminology to app users.

## Do's and Don'ts

- Do reuse Jentra's supplied identity, semantic tokens and source currency/state labels.
- Do keep personal salary/documents online and private by default; show sharing/export consequences clearly.
- Do make thumb targets, keyboard-safe actions, screen-reader focus and large-text reflow part of each screen's acceptance.
- Do render real Android/iPhone previews of Home, leave form, payslip detail, order review, conflict and all-three-confirmation states in both themes before visual sign-off.
- Don't compress the desktop shell, expose broad staff editors or import another product's navigation kit.
- Don't label a local draft Submitted, a customer acceptance Approved by company, a reservation Delivered, or a payslip Paid without the corresponding authoritative fact.
- Don't fill missing targets, balances or charts with fabricated examples in production UI.
- Don't consider a static mockup, widget golden or successful build proof of physical-device behavior or business owner acceptance.
