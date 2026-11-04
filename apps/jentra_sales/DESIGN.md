---
name: Jentra Sales
description: Existing Jentra Flow identity adapted for field sales on phones, tablets and desktop browsers.
colors:
  navigation-navy: "#061B31"
  action-blue: "#0064D9"
  canvas: "#F4F7FA"
  panel: "#FFFFFF"
  text-primary: "#10283F"
  text-secondary: "#5B6D7E"
typography:
  headline:
    fontFamily: Manrope
    fontSize: 28px
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: -0.8px
  body:
    fontFamily: Manrope
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.5
rounded:
  control: 8px
  panel: 14px
spacing:
  small: 8px
  standard: 16px
  section: 24px
  desktop-gutter: 32px
components:
  button-primary:
    backgroundColor: "{colors.action-blue}"
    textColor: "{colors.panel}"
    rounded: "{rounded.control}"
    padding: 14px 20px
  panel:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.panel}"
    padding: 24px
---

# Jentra Sales design system

## Overview

This documents the implemented app, using the established Jentra Flow brand.
It introduces no new brand identity. The app helps a representative find a
customer, prepare an order and follow the next distinct business step.
The current release explicitly separates sample preview activity from live sales.

## Colors

The native Flutter source remains authoritative: shared `JentraTheme`, semantic
tokens, `ui/components.dart` and supplied brand artwork. Navy anchors navigation;
blue indicates the primary action. Status color always accompanies text.
Dark appearance uses the shared dark canvas, panel and semantic status colors.
No gradient, glass effect or decorative chart sits behind commercial amounts.

## Typography

Bundled Manrope is used throughout, with the existing Sinhala/Tamil font
fallbacks. Those fonts do not imply translated product copy. Body text is 14–15
logical pixels; page headings are 28. Quantity and money values retain full
exact decimal representations. Text wraps and grows at 200 percent scaling.

## Layout

Below 700 logical pixels use Today, Customers, Orders and More in a bottom bar.
At 700 and above use an 84-pixel rail with visible captions. At 1180 and above, with normal text scale,
use a 232-pixel labeled sidebar. Main content is capped at 1560 pixels with
16-pixel phone and 32-pixel wider gutters. Customer lists pair with detail when
the content area is at least 820 pixels. Phone metrics use two columns when
readable; enlarged text reflows to one. Order editing and review scroll, while
primary footer controls remain reachable. Long phone dialogs are full-screen.
Leaving an edited order requires an explicit discard decision; review clearly
states that the draft is not saved until the save operation succeeds.

## Elevation & Depth

Panels are flat Material surfaces with subtle boundaries. Material owns panel
paint so ink/focus feedback remains visible. Elevation is reserved for dialogs,
menus and snackbars. The next-visit navy panel establishes focus without charts.

## Shapes

Controls use 8-pixel corners, panels 14 and status labels 6. The original Jentra
symbol and wordmark keep their proportions and source artwork. Buttons provide
at least a 48-pixel minimum target; enlarged text may increase their height.

## Components

`SalesPanel`, `PageHeading`, `SectionTitle`, `StatusPill`, `CustomerAvatar`,
`ProductIcon`, `SalesNotice`, `SalesEmpty` and the shared dialog helper provide
the local component vocabulary. Business state, source freshness and recovery
remain explicit. `Customer response`, `Company decision` and `Delivery` are three
separate records. Discount entry is a request and cannot change the selling price.

## Do's and Don'ts

- Reuse the shared brand assets, semantic theme and exact domain arithmetic.
- Keep preview labels visible; never replace denied live data with sample data.
- Label local drafts as local and require a confirmed storage write before success.
- Keep final tax, credit, stock and commercial totals tied to authoritative review.
- Do not imply that fonts, a build or a screenshot prove translated, accessible
  physical-device or company-accepted behavior.
