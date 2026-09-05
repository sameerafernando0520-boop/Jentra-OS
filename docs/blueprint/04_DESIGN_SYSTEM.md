# Jentra Flow — Design System 02

Rebuilt on 5 September 2026 at the user's request around the supplied Jentra logo.
This replaces the earlier navy/green visual foundation. Product permissions,
business contracts and the synthetic-development boundary remain as defined in
the product and architecture dossier.

Open [the interactive guide](../design-system/index.html) for the visual language,
working component specimens, a sample business workspace and token export. In the
Flutter app, choose **Design system** in the sidebar or open `/catalogue`.

## Design direction

**Operate. Connect. Grow.** The folded J connects a solid navy base to blue, cyan,
teal and a bright green tip. Translate that identity into a precise, calm business
workspace: navy for structure, blue for decisions, white for working surfaces,
and controlled teal/cyan accents. Lime is an identity accent.

Use strong hierarchy and generous separation between tasks. Keep documents and
financial data visually quiet. Prefer descriptive labels and one primary next
step per task. Preserve exact values, ownership, currency and state.

## Brand assets

- The original `Jentra Mark.png` is the master symbol. The package copy at
  `packages/jentra_design_system/assets/brand/jentra-mark.png` is byte-identical.
- `Jentra os logo.png` supplies the authoritative wordmark lettering in light
  and dark versions. A byte-identical package copy is displayed through a clipped
  viewport; the surrounding concept-board content is outside that viewport.
- Never stretch, recolor, redraw or add effects to the master symbol. Flutter
  may clip transparent canvas margins while preserving the visible artwork.
- Keep at least one quarter of the visible mark's height around standalone
  identity applications. Aim for 28–40px visible height in navigation; 24px is
  the minimum for the detailed mark. Reserve larger applications for brand moments.
- `JentraBrandMark` preserves the master symbol. `JentraBrandLockup` pairs it with
  `JentraBrandWordmark`, which displays the actual supplied lettering. Never
  substitute a typed font for the wordmark. `inverse` selects the original light
  lettering on navy. Accessible semantics identify the logo. An inverse
  standalone mark uses a quiet light backing to preserve its dark lower fold.
- In a constrained navigation slot the complete lockup scales together. Product
  text continues to follow the user's text scaling preference.

## Brand palette

| Role | Color | Application |
|---|---|---|
| Deep midnight | `#041321` | Dark canvas |
| Jentra navy | `#061B31` | Navigation, identity, brand surfaces |
| Navigation active | `#102F4C` | Selected navigation surface |
| Action blue | `#0064D9` | Primary action on light surfaces |
| Action hover | `#0051B0` | Primary hover in light mode |
| Sky blue | `#68B7FF` | Primary action in dark mode |
| Connect cyan | `#00B8D9` | Selection marker, chart accent, identity |
| Flow teal | `#008C82` | Secondary graphics and identity |
| Growth lime | `#77E52D` | Small decorative brand accents |

Bright brand hues are not interchangeable status colors. Cyan/lime fills use
navy foregrounds. Core buttons, tables and operational charts use solid colors.
A narrow spectrum rule or restrained brand composition may accompany onboarding,
the command-centre welcome area or the design guide. Avoid gradients beneath data.

## Semantic colors

Use `context.jentraColors` in Flutter. Never apply a light status foreground to
a dark status surface.

| Token | Light | Dark |
|---|---|---|
| Canvas | `#F4F7FA` | `#041321` |
| Panel | `#FFFFFF` | `#0B2238` |
| Elevated panel | `#FFFFFF` | `#122D45` |
| Grouped / neutral surface | `#EEF2F6` | `#122D45` |
| Primary text | `#10283F` | `#F4F7FA` |
| Secondary text | `#5B6D7E` | `#ACBECE` |
| Decorative border | `#DCE5ED` | `#294158` |
| Control boundary | `#7C8D9E` | `#71889D` |
| Primary action | `#0064D9` | `#68B7FF` |
| On primary action | `#FFFFFF` | `#041321` |
| Action hover | `#0051B0` | `#91CAFF` |
| Success / surface | `#00695C` / `#E7F6F0` | `#95E4C4` / `#12392F` |
| Information / surface | `#0757B2` / `#ECF4FF` | `#A4D1FF` / `#173650` |
| Warning / surface | `#8A4A00` / `#FFF4DE` | `#FFD58A` / `#3C2D15` |
| Danger / surface | `#B42318` / `#FFF1F0` | `#FFB4AE` / `#41282D` |

`border` separates surfaces; `borderStrong` identifies controls. Success uses a
check, warning a warning symbol, danger an error symbol, information an info
symbol, and neutral a distinct neutral icon. Include visible text and semantics.

## Typography

- **Manrope:** locally bundled regular, medium, semibold and bold. Its geometric
  forms complement the original wordmark without impersonating it. Interface
  body 14px; dense body 13px; supporting labels 11–12px.
- **IBM Plex Mono:** locally bundled. Financial values and IDs use tabular
  figures. Amounts align right and state their currency. Abbreviations are useful
  on overview cards; transaction tables retain exact amounts.
- **Noto Sans Sinhala / Tamil:** locally bundled localization fallbacks.
- Page title 32px / 1.2 / 600; section title 24px / 1.25 / 600; panel title
  18px / 1.35 / 600; title/field label 14px / 600; body 14px / 1.45 / 400.
- Guide-only editorial display sizes may reach 48–64px. They are not the default
  application page heading.
- Font family tokens already include the Flutter package prefix. Do not set
  `package` again when applying them or copying theme typography.
- Font provenance: [Google Fonts Manrope distribution](https://github.com/google/fonts/tree/main/ofl/manrope),
  with its accompanying SIL Open Font License. Static weights are instantiated
  from the bundled variable source. Manrope applies to UI text; brand lettering
  always comes from the original image.

## Geometry, density and motion

| Foundation | Values |
|---|---|
| Spacing | 4, 8, 12, 16, 20, 24, 32, 40, 48px |
| Radius | 8px controls, 14px panels, 20px dialogs |
| Compact | 32px data rows, 36px controls |
| Comfortable | 40px data rows, 44px controls |
| Motion | 120ms micro, 180ms standard, 240ms deliberate |

Pills are reserved for status/filter chips. Use flat panels and subtle borders;
reserve elevation for floating menus and dialogs. Allow rows and controls to grow
when text is enlarged. Reduce columns before shrinking text. Disable nonessential
animation when reduced motion is requested. Future touch interfaces use at least
44px interactive targets regardless of desktop density.

## Desktop shell and layouts

- Windows first. Minimum reference viewport 1024×720; primary reference 1440×900.
- Expanded navigation 248px; collapsed rail 72px; command bar 56px; content gutters
  24px. The HTML guide uses an editorial navigation layout around its app specimen.
- Collapse application navigation below 1220px or above 140% text scale.
- Show the existing 360px context inspector from 1740px, except at enlarged text.
  Its sample scope is explicitly labeled as preview context.
- Keep navigation group headings when permission filtering removes destinations.
  Route, capability and MFA checks remain authoritative.
- `Ctrl+K` opens the module/command palette; `Esc` dismisses its dialog. Advertise
  additional keyboard shortcuts only when their behavior is implemented.
- Reflow dashboard metrics into two or one columns. Stack charts and attention
  panels when their combined content cannot remain readable.
- Tables may scroll horizontally inside their panel. Keep filter and primary
  actions reachable. Do not shrink transaction values to fit a narrow viewport.

## Components and state contracts

| Component | Contract |
|---|---|
| Primary action | Solid blue, descriptive verb, explicit disabled/loading state |
| Secondary action | Quiet surface, visible boundary, clear keyboard focus |
| Destructive action | Specific label, explicit confirmation, danger semantics |
| Status badge | Icon + visible text + semantic label; paired theme colors |
| Panel | Material surface so contained rows preserve interaction feedback |
| KPI | Label, value, unit/currency, qualifier; label sample metrics honestly |
| Form | Persistent label, helper, inline validation; errors explain correction |
| Table | Left-aligned text, right-aligned exact amounts, readable state |
| Empty/error | Explain the state and expose an appropriate next action |
| Modal | Descriptive title, explicit buttons, Escape and focus return |
| Brand | Original mark and accessible name; no temporary letter tile |

The catalogue has Foundations, Components and Data patterns sections. Swatches
copy values, sample approval/reset actions give feedback, forms validate locally,
and the date field opens a date picker. These specimens never invoke business RPCs.
The HTML workspace supports in-memory sample quotation creation, literal search,
status filters, density/theme controls and token export. Reload resets its samples.

## Accessibility and verification

WCAG 2.2 AA remains the product target: at least 4.5:1 for normal text and 3:1 for
meaningful control boundaries and large text. Status semantics, contrast tests,
visible focus, logical keyboard order, persistent labels and 200% text checks are
part of the foundation. These checks do not certify the entire application.

Validate the catalogue at 1024×720 light compact, 1440×900 light comfortable,
1440×900 dark compact and 1920×1080 dark comfortable. Existing dashboard/setup
goldens also cover 1024, 1440 and 1920 widths. Inspect rendered output, including
financial glyphs and original artwork, before accepting updated goldens.

See [verification and delivery notes](../design-system/VERIFICATION.md) for what
was checked. Source checks, deterministic screenshots, Windows compilation and
native runtime observation are distinct evidence. This redesign is local work;
production deployment or release is not implied.

## Adoption

The shared package preserves existing APIs and the 32/40px row contract. Legacy
green constants remain for source compatibility; new actions use semantic blue.
Replace local action/status colors with semantic colors as each feature is touched.
This delivery updates the shared foundation, app shell, login identity, dashboard,
catalogue, guide and affected visual baselines. It does not expand business modules.
