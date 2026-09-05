# Jentra design system · v2

The Flutter foundations for Jentra OS, built around the supplied folded J symbol.
Deep navy creates structure; accessible blue identifies actions; cyan and teal
connect the interface to the original mark. Lime is reserved for brand decoration.

```dart
MaterialApp(
  theme: JentraTheme.light(),
  darkTheme: JentraTheme.dark(),
  home: const Scaffold(body: JentraBrandLockup(size: 40)),
)
```

## Foundations

- Use `context.jentraColors` for theme-aware text, surfaces, actions, statuses,
  focus rings, and control borders. Use each status foreground with its matching
  surface; the dark theme has independent opaque status pairs.
- `border` separates panels. `borderStrong` defines editable controls and other
  boundaries that must remain identifiable. Interactive focus uses a 2 px border.
- Actions use blue `#0064D9` with white text in light mode, and sky blue with navy
  text in dark mode. Teal and lime are never substitutes for action semantics.
- Local Manrope serves interface copy; IBM Plex Mono serves exact amounts
  and identifiers. Local Noto Sans Sinhala and Tamil remain available as fallbacks.
- Spacing follows a 4 px base; controls use 8 px corners, panels 14 px, dialogs
  20 px. Dense tables retain 32 px rows; comfortable tables retain 40 px rows.
  Compact controls are 36 px high and comfortable controls 44 px high.
- Compact density is for pointer-driven data work. Preserve Material's padded
  touch targets when designing mobile navigation and actions.

## Brand assets

`assets/brand/jentra-mark.png` is a byte-identical copy of the user-supplied
`Jentra Mark.png`. Do not trace, recolor, distort, or apply gradients to the asset.

`JentraBrandMark(size: 40)` preserves the mark's proportions and clips only its
transparent outer canvas with Flutter layout. Set `compact: false` to retain the
full square canvas. `inverse: true` adds a light backing for a standalone icon on
a dark surface; the symbol itself remains unchanged.

`JentraBrandLockup(size: 36, inverse: true)` pairs the original icon with the exact
wordmark lettering in the supplied logo board. `compact: true` displays just the
icon; `showTagline: true` includes the original “Operate · Connect · Grow” line.
`JentraBrandWordmark` displays the lettering separately. Both light and dark
versions clip the unchanged source `assets/brand/jentra-logo-board.png` through
Flutter layout. Accessible labels identify the artwork for screen readers.

The wordmark is artwork, not typeset Manrope. Manrope is the interface family,
bundled in regular, medium, semibold and bold weights from the Google Fonts OFL
distribution. See `assets/fonts/OFL-Manrope.txt` for its license. The original
board is a raster source; retain it for fidelity and use a supplied vector master
if one becomes available for large-format reproduction.

## Components and accessibility

`JentraPanel`, `JentraSectionHeader`, `JentraPrimaryButton`, `JentraStatusBadge`,
`JentraKpiCard`, and `JentraEmptyState` retain their original public constructors.
Status badges include an icon and spoken status label. Loading primary actions
keep their label, announce progress, and disable duplicate submission. KPI values
use tabular numerals and preserve the full amount in their accessible label.

The package tests verify light/dark text and status pairs at 4.5:1 or higher,
control boundaries and focus at 3:1 or higher, loading behavior, and logo loading
and semantics. These checks do not substitute for application-level keyboard,
responsive, text-scale, or assistive-technology review.
