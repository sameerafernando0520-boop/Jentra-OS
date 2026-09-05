# Jentra Flow — Design System 02

Open [index.html](index.html) in a browser. The guide includes the supplied Jentra
icon and original wordmark lettering, Manrope interface typography, light and
dark themes, semantic colors, spacing, density, components and a working sample
business workspace. All assets and fonts load locally.

Use the theme toggle, density controls, swatch copy buttons, component tabs,
validation form, quotation search, status filters and sample draft dialog to
explore the system. **Export tokens** downloads the current v2 token specification
as JSON. Demonstration records live only in the browser session.

The accompanying Flutter implementation is in `packages/jentra_design_system`.
In the desktop app, choose **Design system** in the sidebar to open the native
component catalogue. See the [specification](../blueprint/04_DESIGN_SYSTEM.md)
and [verification record](VERIFICATION.md).

## Original brand artwork

`assets/brand/jentra-mark.png` is an unchanged copy of the supplied icon.
`assets/brand/jentra-logo-board.png` is an unchanged copy of the supplied brand
board. The wordmark is a viewport onto that image's existing lettering, with
the background matte made transparent at rendering time. It is never retyped
using a substitute font. The same treatment is implemented in Flutter.

## Typography

Manrope regular, medium, semibold and bold provide the interface family. IBM Plex
Mono remains the family for exact amounts and identifiers. The logo has its own
original lettering and is independent of the interface font.

Manrope source: [Google Fonts](https://github.com/google/fonts/tree/main/ofl/manrope).
The bundled static weights were instantiated from its OFL variable distribution.
Font licenses are included in `assets/fonts/`. The Flutter package additionally
bundles Noto Sans Sinhala and Tamil for localization fallback.
