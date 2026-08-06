# Jentra OS — Enterprise Design System Specification

**Version:** 1.0.0  
**Design Lead:** Principal Product Designer & Design System Architect  
**Inspiration Benchmark:** Linear • Stripe Dashboard • Vercel • Notion • Framer  
**Target Platforms:** Flutter Web • Flutter Mobile (iOS / Android) • Desktop Native  

---

## Executive Summary & Design Tokens Overview

Jentra OS is designed to reject legacy ERP visual debt (corporate grey, crowded table densities, generic Material Design defaults) in favor of a crisp, modern, ultra-responsive design language. It combines the sleek aesthetic of Linear and Vercel with the financial clarity of Stripe Dashboard.

```
       Primary Navy (#081A4B)          Cyan/Teal Gradient (#14C6C7 -> #33E1B3)
 ┌────────────────────────────────┐    ┌────────────────────────────────────────┐
 │                                │    │                                        │
 └────────────────────────────────┘    └────────────────────────────────────────┘
       Secondary Navy (#113A8F)                   Accent Blue (#2F6DFF)
 ┌────────────────────────────────┐    ┌────────────────────────────────────────┐
 │                                │    │                                        │
 └────────────────────────────────┘    └────────────────────────────────────────┘
```

---

## 1. Brand Philosophy

- **Intelligent Simplicity:** Reduce visual noise. Highlight key actionable data (KPIs, active status tags, anomaly warnings) while muting structural containers.
- **Precision Engineering:** 4px baseline grid alignment, pixel-perfect borders, zero arbitrary layout offsets.
- **Dynamic Vitality:** Subtle micro-interactions, sleek 1px glassmorphic borders, crisp linear gradients, and stateful hover/active transitions.
- **Enterprise Trust:** High-contrast WCAG AAA readable typography (`Manrope`), fail-closed validation states, clear error recovery.

---

## 2. Color System

### Base Color Palette

```json
{
  "color": {
    "brand": {
      "primaryNavy": { "value": "#081A4B", "type": "color" },
      "secondaryNavy": { "value": "#113A8F", "type": "color" },
      "accentBlue": { "value": "#2F6DFF", "type": "color" },
      "gradientStart": { "value": "#14C6C7", "type": "color" },
      "gradientEnd": { "value": "#33E1B3", "type": "color" }
    },
    "semantic": {
      "success": { "value": "#00C48C", "type": "color" },
      "warning": { "value": "#F6A609", "type": "color" },
      "danger": { "value": "#E5484D", "type": "color" }
    },
    "neutral": {
      "backgroundLight": { "value": "#F8FAFC", "type": "color" },
      "cardLight": { "value": "#FFFFFF", "type": "color" },
      "borderLight": { "value": "#E2E8F0", "type": "color" },
      "textPrimary": { "value": "#081A4B", "type": "color" },
      "textSecondary": { "value": "#64748B", "type": "color" },
      "textMuted": { "value": "#94A3B8", "type": "color" }
    },
    "dark": {
      "backgroundDark": { "value": "#0B0F19", "type": "color" },
      "cardDark": { "value": "#111827", "type": "color" },
      "borderDark": { "value": "#1F2937", "type": "color" },
      "textPrimaryDark": { "value": "#F8FAFC", "type": "color" },
      "textSecondaryDark": { "value": "#94A3B8", "type": "color" }
    }
  }
}
```

---

## 3. Typography

- **Primary Font Family:** `Manrope` (Google Fonts)
- **Fallback Chain:** `Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`

| Token | Size | Weight | Line Height | Tracking | Usage |
| --- | --- | --- | --- | --- | --- |
| `displayLarge` | 36px | 800 (ExtraBold) | 44px | -0.02em | Hero headers, Main metric numbers |
| `displayMedium` | 28px | 700 (Bold) | 36px | -0.01em | Section headlines |
| `titleLarge` | 22px | 700 (Bold) | 28px | -0.01em | Card headers, Modal titles |
| `titleMedium` | 18px | 600 (SemiBold) | 24px | 0.00em | Module titles, Sub-headers |
| `titleSmall` | 14px | 600 (SemiBold) | 20px | 0.01em | Table headers, Group titles |
| `bodyLarge` | 16px | 400 (Regular) | 24px | 0.00em | Long text, Descriptions |
| `bodyMedium` | 14px | 400 (Regular) | 20px | 0.00em | Primary input labels, Table cells |
| `bodySmall` | 12px | 500 (Medium) | 16px | 0.01em | Helper text, Secondary info |
| `caption` | 11px | 600 (SemiBold) | 14px | 0.02em | Badges, Timestamp tags |

---

## 4. Grid System

- **Desktop (>= 1200px):** 12-Column fluid grid, 24px margin, 24px gutter. Max container width: 1440px.
- **Tablet (600px - 1199px):** 8-Column grid, 20px margin, 16px gutter.
- **Mobile (< 600px):** 4-Column grid, 16px margin, 12px gutter.

---

## 5. Spacing System

Baseline 4px grid scale tokens:
- `space-4` (4px): Micro spacing (icon-text gaps, badge padding)
- `space-8` (8px): Dense spacing (chip gaps, compact button padding)
- `space-12` (12px): Standard element padding
- `space-16` (16px): Card internal padding, Form item gaps
- `space-20` (20px): Section inner padding
- `space-24` (24px): Card gap, Layout grid spacing
- `space-32` (32px): Major component separation
- `space-40` (40px): Section breaks
- `space-48` (48px): Page section padding
- `space-64` (64px): Hero & Landing breaks

---

## 6. Elevation System

- **`elevation-sm`:** `0px 1px 2px rgba(8, 26, 75, 0.05)` (Cards, Small Dropdowns)
- **`elevation-md`:** `0px 4px 12px rgba(8, 26, 75, 0.08)` (Floating Nav, Menus, Hover Cards)
- **`elevation-lg`:** `0px 12px 32px rgba(8, 26, 75, 0.12)` (Modals, Dialogs, Drawers)
- **`glass-elevation`:** `backdrop-filter: blur(12px); background: rgba(255, 255, 255, 0.85); border: 1px solid rgba(226, 232, 240, 0.8);`

---

## 7. Buttons

- **Primary Button:** Navy gradient / Solid `#081A4B` background, White text (`#FFFFFF`), `radius-8` (8px), height 40px (desktop) / 48px (mobile). Hover: `#113A8F`.
- **Accent Button:** Teal Gradient (`#14C6C7` -> `#33E1B3`), Navy text (`#081A4B`), font-weight 700.
- **Secondary Button:** White background (`#FFFFFF`), 1px border `#E2E8F0`, Navy text (`#081A4B`). Hover background `#F8FAFC`.
- **Ghost Button:** Transparent background, Navy/Slate text (`#64748B`). Hover background `rgba(8, 26, 75, 0.04)`.
- **Danger Button:** Crimson Red (`#E5484D`) background, White text.

---

## 8. Inputs

- **Default State:** Height 40px, Background `#FFFFFF`, Border 1px `#E2E8F0`, Radius 8px, Text `#081A4B`, Placeholder `#94A3B8`.
- **Focus State:** Border 2px `#2F6DFF`, Box-shadow `0 0 0 3px rgba(47, 109, 255, 0.15)`.
- **Error State:** Border 1px `#E5484D`, Helper text `#E5484D`.

---

## 9. Dropdowns

- **Container:** Background `#FFFFFF`, Radius 12px, Border 1px `#E2E8F0`, Shadow `elevation-md`.
- **Item State:** Height 36px, Hover background `#F8FAFC`, Selected text `#2F6DFF` with check icon.

---

## 10. Tables

- **Header Row:** Height 44px, Background `#F8FAFC`, Text `#64748B` uppercase 11px semi-bold.
- **Data Rows:** Height 52px (Standard) / 44px (Compact), Border bottom 1px `#E2E8F0`, Hover background `#F8FAFC`.

---

## 11. Cards

- **Standard Card:** Background `#FFFFFF`, Border 1px `#E2E8F0`, Radius 12px, Padding 20px, Shadow `elevation-sm`.
- **Interactive Card:** Radius 12px, Transition `all 0.2s ease`, Hover shadow `elevation-md`, Hover border `#2F6DFF`.

---

## 12. Dialogs

- **Modal Backdrop:** `rgba(8, 26, 75, 0.4)` with 4px backdrop blur.
- **Modal Container:** Background `#FFFFFF`, Radius 20px, Border 1px `#E2E8F0`, Padding 24px, Shadow `elevation-lg`.

---

## 13. Navigation

- **Primary Structure:** Sidebar (Left fixed 260px desktop) + TopBar (Header 64px) + Main Content Area + BottomBar (Mobile only 64px).

---

## 14. Sidebar

- **Width:** 260px (Expanded) / 72px (Collapsed).
- **Background:** `#081A4B` (Primary Navy) in dark branding mode or `#FFFFFF` in light mode with `#E2E8F0` border.
- **Active Nav Item:** Background `#113A8F` or Cyan tint `rgba(20, 198, 199, 0.10)`, Left indicator border 3px `#14C6C7`.

---

## 15. Top Navigation

- **Height:** 64px.
- **Elements:** Breadcrumb track, Global Quick Search bar (`Ctrl + K`), Company/Branch Selector, Notification Bell, User Avatar dropdown.

---

## 16. Bottom Navigation

- **Target:** Mobile (< 600px).
- **Height:** 64px.
- **Items:** 5 Core destinations (Home/Dashboard, Sales, Inventory, Finance, AI Assistant). Active item highlighted in `#2F6DFF` or Cyan.

---

## 17. Tabs

- **Underline Style:** Active tab border-bottom 2px `#2F6DFF`, Text `#081A4B` semi-bold. Inactive text `#64748B`.
- **Pill / Segmented Style:** Container `#F8FAFC`, Radius 8px. Active segment `#FFFFFF` with `elevation-sm`.

---

## 18. Breadcrumbs

- **Typography:** `bodySmall` (12px), Neutral Slate (`#64748B`).
- **Separator:** Chevron `/` or `>` in `#94A3B8`. Active terminal page in `#081A4B` semi-bold.

---

## 19. Charts

- **Palette:** Primary Accent Cyan (`#14C6C7`), Secondary Teal (`#33E1B3`), Blue (`#2F6DFF`), Warning Amber (`#F6A609`), Crimson (`#E5484D`).
- **Style:** Smooth curves (monotone spline), subtle gradient area fills (opacity 0.15 to 0.0), crisp gridlines `#F1F5F9`.

---

## 20. KPIs

- **Layout:** Card container, Top row: Label (`bodySmall` Slate) + Icon Badge, Middle row: Value (`displayLarge` Navy 32px), Bottom row: Trend Indicator (+12.4% green pill / -2.1% red pill).

---

## 21. Dashboards

- **Grid Layout:** Responsive 12-column grid. Top: 4 KPI Cards (3 cols each). Middle: Main Chart (8 cols) + Recent Activity / AI Insights (4 cols). Bottom: Data Table (12 cols).

---

## 22. Calendar

- **Cell Style:** Radius 8px, Current day marked with `#2F6DFF` border. Event badges with status pill colors (`#00C48C`, `#F6A609`, `#E5484D`).

---

## 23. Data Tables

- **Features:** Column sorting indicators, Row selection checkboxes, Batch action floating bar, Pagination controls (`Page X of Y`), Column density toggle.

---

## 24. Search Components

- **Global Command Palette (`Ctrl + K` / `Cmd + K`):** Modal search overlay searching across Invoices, Customers, Products, and Commands with keyboard arrow navigation.

---

## 25. Filters

- **Filter Bar:** Inline pill chips (`Status: Posted x`, `Category: Electronics x`), + Add Filter dropdown button, Clear All button.

---

## 26. Forms

- **Form Layout:** 2-Column layout on desktop, 1-Column on mobile. Field label above input, error text below input, explicit required asterisk (`*`).

---

## 27. Loading States

- **Skeletons:** Shimmer animation (`rgba(226, 232, 240, 0.6)` to `rgba(241, 245, 249, 0.9)`), matching card and row border-radius.

---

## 28. Empty States

- **Illustration:** Crisp monochrome line illustration + Headline (`titleMedium`) + Subtitle (`bodyMedium` Slate) + Primary Call to Action Button.

---

## 29. Error States

- **Alert Box:** Background `#FEF2F2`, Border `#FCA5A5`, Icon `#E5484D`, Text `#991B1B`. Includes retry button.

---

## 30. Success States

- **Confirmation Card:** Checkmark circle badge (`#00C48C`), Success message, Action summary, Done/View Document buttons.

---

## 31. Notifications

- **Notification Center Drawer:** Slide-over right drawer (360px width), grouped by "Unread" and "All", timestamp tags, mark-all-as-read control.

---

## 32. Snackbars

- **Floating Banner:** Bottom-right alignment (desktop) or Bottom-center (mobile), Dark Navy background (`#081A4B`), White text, Action button in Cyan (`#14C6C7`). Auto-dismiss after 4s.

---

## 33. Toasts

- **Toast Container:** Top-right stacked alerts with slide-in animation, color-coded left border (Green = Success, Amber = Warning, Red = Danger).

---

## 34. File Upload

- **Dropzone Card:** Dashed border 2px `#CBD5E1`, Background `#F8FAFC`, Upload icon, "Drag & drop files here or browse", Progress bar indicator for active uploads.

---

## 35. Avatar System

- **User Avatar:** Circle / Radius 8px square, Initials fallback (e.g., "JS" on `#113A8F` background with white text), Online status dot indicator (Green `#00C48C`).
- **Sizes:** XS (24px), SM (32px), MD (40px), LG (56px), XL (80px).

---

## 36. Icons

- **Icon Set:** Lucide Icons / Feather Icons outline set (2px stroke weight). Standard size: 20px x 20px.

---

## 37. Illustration Style

- **Vector Aesthetics:** Minimal 2D vector line art with Primary Navy (`#081A4B`) and Cyan (`#14C6C7`) accent fills. Avoid cartoonish or 3D render clutter.

---

## 38. Dark Theme

- **Background:** `#0B0F19` (Deep Charcoal)
- **Cards / Containers:** `#111827` (Rich Slate)
- **Borders:** `#1F2937`
- **Primary Text:** `#F8FAFC`
- **Secondary Text:** `#94A3B8`
- **Accent Glow:** Subtle cyan glow (`rgba(20, 198, 199, 0.15)`) around focused elements.

---

## 39. Light Theme

- **Background:** `#F8FAFC` (Slate Tint)
- **Cards / Containers:** `#FFFFFF` (Pure White)
- **Borders:** `#E2E8F0`
- **Primary Text:** `#081A4B` (Primary Navy)
- **Secondary Text:** `#64748B` (Slate)

---

## 40. Accessibility

- **Contrast Ratios:** Minimum 4.5:1 for standard body text; 3:1 for large display titles (WCAG AAA target).
- **Keyboard Focus Ring:** 2px solid `#2F6DFF` focus outline on all interactive buttons, inputs, and links.
- **Screen Reader Support:** Semantic HTML / Flutter Semantics tags on all icon-only buttons.

---

## 41. Responsive Design

- **Breakpoints:**
  - `mobile`: `< 600px`
  - `tablet`: `600px - 1199px`
  - `desktop`: `>= 1200px`
- **Layout Adapters:** Sidebar converts to drawer on mobile/tablet; Data tables convert to card lists or horizontal scroll containers.

---

## 42. Animation Guidelines

- **Duration Tokens:**
  - `fast`: 150ms (Button hovers, checkbox toggles)
  - `normal`: 250ms (Dropdown expansions, tab switches)
  - `slow`: 350ms (Modal overlays, page transitions)
- **Easing Curve:** `cubic-bezier(0.16, 1, 0.3, 1)` (Custom ease-out curve matching Apple / Linear).

---

## 43. Micro Interactions

- **Button Press:** Scale down `transform: scale(0.98)` on click.
- **Card Hover:** Lift `-2px` translateY with smooth shadow expansion.
- **Switch Toggle:** Smooth 150ms spring slide.

---

## 44. Motion Principles

- **Purposeful:** Motion directs user attention to state changes; no decorative animation lag.
- **Consistent:** All enter animations fade and slide up from 8px offset.

---

## 45. AI Assistant UI

- **AI Chat Drawer / Pane:** Floating glassmorphic panel with gradient border (`#14C6C7` -> `#33E1B3`).
- **AI Response Bubble:** Distinct background tint `rgba(20, 198, 199, 0.08)`, spark icon badge, explicit evidence citation footer.

---

## 46. CRM Screens

- **Customer Detail Screen:** Header summary (Company name, Total revenue, Balance due) + Tabbed workspace (Overview, Invoices, Contacts, Addresses, Activities, Attachments).

---

## 47. Inventory Screens

- **Stock Overview Screen:** Warehouse filter dropdown + Stock balance grid (Product SKU, Name, Warehouse, On Hand, Available, Reorder Alert Badge).

---

## 48. Accounting Screens

- **Manual Journal Editor:** Header (Entry Date, Period Check Status, Narration) + Multi-line table (Account Code, Account Name, Debit input, Credit input) + Live Balanced Counter (`Total Debit == Total Credit`).

---

## 49. Reports

- **Statutory Report Viewer:** Date range picker + Report header (Company legal name, Report title, Currency) + Export PDF / CSV buttons + Consolidated financial table.

---

## 50. Mobile Adaptation

- Navigation converts to 5-destination bottom navigation bar.
- Table columns prioritize primary fields (e.g., Invoice Number & Total) with expandable row drawers for detail view.
- Floating Action Button (FAB) for primary creation tasks (`+ New Invoice`).

---

## Flutter Theme Implementation (`lib/core/theme/jentra_theme.dart`)

```dart
import 'package:flutter/material.dart';

abstract final class JentraTheme {
  // Brand Colors
  static const primaryNavy = Color(0xFF081A4B);
  static const secondaryNavy = Color(0xFF113A8F);
  static const accentBlue = Color(0xFF2F6DFF);
  static const gradientStart = Color(0xFF14C6C7);
  static const gradientEnd = Color(0xFF33E1B3);

  // Semantic Colors
  static const success = Color(0xFF00C48C);
  static const warning = Color(0xFFF6A609);
  static const danger = Color(0xFFE5484D);

  // Light Theme Palette
  static const backgroundLight = Color(0xFFF8FAFC);
  static const cardLight = Color(0xFFFFFFFF);
  static const borderLight = Color(0xFFE2E8F0);

  // Dark Theme Palette
  static const backgroundDark = Color(0xFF0B0F19);
  static const cardDark = Color(0xFF111827);
  static const borderDark = Color(0xFF1F2937);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Manrope',
      scaffoldBackgroundColor: backgroundLight,
      colorScheme: const ColorScheme.light(
        primary: primaryNavy,
        secondary: secondaryNavy,
        surface: cardLight,
        error: danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: primaryNavy,
      ),
      cardTheme: const CardThemeData(
        color: cardLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderLight, width: 1),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accentBlue, width: 2),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Manrope',
      scaffoldBackgroundColor: backgroundDark,
      colorScheme: const ColorScheme.dark(
        primary: accentBlue,
        secondary: gradientStart,
        surface: cardDark,
        error: danger,
        onPrimary: Colors.white,
        onSurface: Colors.white,
      ),
      cardTheme: const CardThemeData(
        color: cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderDark, width: 1),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }
}
```
