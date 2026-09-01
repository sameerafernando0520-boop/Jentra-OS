# Jentra OS Corporate Desktop Design System

## Design posture

Jentra OS is a light enterprise command centre: calm, precise, information-rich, and
keyboard-efficient. Deep navy establishes structure. Green identifies progress and primary
action. Decoration never competes with operational or financial truth.

## Semantic palette

| Token | Light | Dark | Use |
|---|---|---|---|
| `brand.navy.950` | `#071426` | `#071426` | Dark canvas |
| `brand.navy.900` | `#0B1F3A` | `#0B1F3A` | Sidebar, brand |
| `brand.navy.800` | `#12345B` | `#12345B` | Active navigation |
| `brand.navy.700` | `#1B4B7A` | `#4E86BE` | Information emphasis |
| `brand.green.700` | `#08663F` | `#36C984` | High-contrast action |
| `brand.green.600` | `#0B7A4B` | `#2FBC78` | Primary action |
| `brand.green.500` | `#12965B` | `#3DCF8A` | Active/accent |
| `brand.green.400` | `#22B573` | `#53DB9B` | Highlights/charts |
| `surface.app` | `#F5F7FA` | `#071426` | App canvas |
| `surface.panel` | `#FFFFFF` | `#0D223B` | Panels and dialogs |
| `surface.subtle` | `#EEF2F6` | `#142B45` | Hover/grouped surfaces |
| `border.default` | `#D7E0E8` | `#29415A` | Boundaries |
| `text.primary` | `#15202B` | `#E8EEF5` | Body/data |
| `text.secondary` | `#5B6978` | `#AAB8C7` | Supporting text |
| `status.info` | `#2563EB` | `#60A5FA` | Information |
| `status.warning` | `#B66A00` | `#F2B84B` | Warning |
| `status.danger` | `#C33E4D` | `#FF7B88` | Error/destructive |

Status always includes text or an icon. Brand gradients are allowed only for onboarding and AI
moments, never tables, charts, or core buttons.

## Typography

- Primary: IBM Plex Sans, with Segoe UI/system fallback during development.
- Financial/identifier: IBM Plex Mono with tabular numerals.
- Localization fallbacks: Noto Sans Sinhala and Noto Sans Tamil.
- Default desktop body: 14px/20px. Dense labels: 12px/16px. Title levels: 18, 24, and 32px.
- Monetary values align right and use tabular figures. Codes and immutable IDs may use mono.

Font binaries must be bundled and licensed before a signed release; runtime font fetching is
not allowed in production.

## Geometry and motion

- Spacing: 4, 8, 12, 16, 20, 24, 32, 40, 48.
- Radius: 6px controls, 10px cards, 14px dialogs, full pill only for status/filter chips.
- Compact rows/controls: 32px. Comfortable rows: 40px; primary actions remain at least 40px.
- Motion durations: 120ms micro, 180ms standard, 240ms panel. Use ease-out entry and ease-in
  exit. Disable nonessential movement when reduced motion is active.
- Shadows are subtle and limited to floating menus, dialogs, and inspectors; hierarchy relies
  primarily on surface and border tokens.

## Desktop shell

- Minimum supported viewport: 1024x720; reference viewport: 1440x900.
- Expanded sidebar: 248px. Collapsed rail: 72px. Command bar: 56px.
- Desktop content uses a 24px outer gutter and an 8px layout grid.
- Optional context inspector: 360px at widths of 1280px or more; drawer below that threshold.
- Navigation groups: Workspace, Operations, Finance, People & Delivery, Intelligence, System.
- `Ctrl+K` opens the command palette; `Ctrl+/` shows shortcuts; `Esc` closes the top overlay.

## Component inventory

Wave 1 implements:

- App shell, sidebar item/group, command bar, context switcher, breadcrumb, workspace header.
- Primary/secondary/ghost/destructive buttons and icon buttons.
- Text, password, search, select, money/date-shell, checkbox, and validation message.
- Panel/card, KPI card, status badge, avatar, empty/error/loading state, toast/banner.
- Command palette, modal dialog, drawer, tooltip, theme and density controls.
- Data-table shell with header, filters, pagination state, empty state, and row density tokens.

Later waves add full server data-grid behavior, approval timeline, audit trail, attachment viewer,
chart library, filter builder, saved views, and document forms.

## Accessibility contract

- WCAG 2.2 AA contrast for all foreground/background and interactive states.
- Logical keyboard order, visible focus ring, semantic labels, tooltips for collapsed icons.
- No icon-only meaning without accessible label.
- Errors appear inline and in an announced summary.
- Zoom/text scale to 200% without clipped primary actions.
- Touch-size exceptions are desktop-only; future mobile components use at least 44px targets.

## Visual verification matrix

Render and inspect the shell/component catalogue at:

- 1024x720 light compact
- 1440x900 light comfortable
- 1440x900 dark compact
- 1920x1080 dark comfortable

Golden tests establish deterministic structure, but actual Windows rendering remains a release
gate for typography, focus, scaling, and GPU behavior.
