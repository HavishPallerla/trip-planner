# Trip Planner — Visual Design Spec (Phase 1: Coordination Core)

**Date:** 2026-09-21
**Status:** Draft, for frontend implementation reference
**Companion to:** `2026-09-21-coordination-core-design.md`

## Design direction

Audience is ~10 friends studying abroad — casual, mobile-heavy usage,
checked between classes or on a train. The product should read as
**warm and a little playful**, not enterprise SaaS: rounded shapes,
saturated-but-friendly color, generous whitespace, no dense tables.
Every screen should be scannable in a few seconds — "what's happening,
what needs my input, what did I already do."

Two design moves carry most of the personality:
1. **Trip color as identity.** Each trip's assigned color (already in
   the data model as `trips.color`) shows up everywhere that trip is
   referenced — dashboard card accent, calendar bar, detail-page
   header — so color becomes a wayfinding device across the whole app.
2. **Soft, tactile surfaces.** Cards with large radii, soft shadows,
   and pastel-tinted backgrounds instead of hard borders/lines.

## Color

### Base palette (Tailwind config tokens)

| Token | Hex | Usage |
|---|---|---|
| `stone-50` | `#FAF9F7` | App background |
| `stone-100` | `#F3F1ED` | Section/card alt background |
| `stone-200` | `#E7E3DC` | Dividers, input borders |
| `stone-500` | `#8B8578` | Secondary text |
| `stone-800` | `#332F28` | Primary text |
| `coral-500` | `#FF6B5E` | Primary actions, "I'm in" active state |
| `coral-600` | `#E85347` | Primary action hover/pressed |
| `coral-50` | `#FFEFEE` | Primary action tint background |
| `amber-400` | `#F5B03B` | Warning / overlap-flag accent |
| `sage-500` | `#6FA37D` | Success / confirmed state |

Base palette lives in `tailwind.config.ts` under `theme.extend.colors`
as `stone`, `coral`, `amber`, `sage` (amber/sage can alias Tailwind's
built-in `amber`/`emerald` scales directly rather than redefining
them — only `stone` and `coral` are custom).

### Trip color palette (`trips.color`, round-robin assigned)

Eight colors, chosen for mutual distinguishability at low saturation
(soft enough to use as full-card tints, strong enough to read as a
calendar-bar accent). Store the **name** in `trips.color`; look up hex
values client-side from this fixed table so the palette can be
retuned without a migration.

| Name | Swatch | Bar/accent hex | Tint background hex |
|---|---|---|---|
| `coral` | 🟠 | `#FF6B5E` | `#FFEFEE` |
| `sunflower` | 🟡 | `#F5B03B` | `#FFF7E6` |
| `sage` | 🟢 | `#6FA37D` | `#EEF6F0` |
| `teal` | 🔵 | `#3FA9A0` | `#E8F6F5` |
| `periwinkle` | 🟣 | `#7B8CDE` | `#EEF0FC` |
| `plum` | 🟣 | `#A874B8` | `#F6EEF8` |
| `rose` | 🌸 | `#E5789E` | `#FCEEF3` |
| `clay` | 🟤 | `#C97C5D` | `#F8EEE8` |

Assignment: `trips` table stores the name; a `TRIP_COLORS` constant in
`lib/trip-colors.ts` maps name → `{ accent, tint }`. Round-robin index
= `trip count so far % 8` at creation time.

### Dark mode

Not required for Phase 1 (no dark-mode toggle in scope), but the
tokens above are named so a dark variant can be added later by
swapping `stone-50/800` roles without touching component code.

## Typography

- **Font:** `Inter` (variable), loaded via `next/font/google`. Fallback
  stack: `ui-sans-serif, system-ui, sans-serif`.
- **Scale** (Tailwind default scale, specific sizes pinned per role):

| Role | Class | Size/line-height | Weight |
|---|---|---|---|
| Page title (e.g. "Your Trips") | `text-2xl leading-tight` | 24px/30px | `font-semibold` |
| Trip/section title | `text-lg leading-snug` | 18px/26px | `font-semibold` |
| Body | `text-sm leading-relaxed` | 14px/22px | `font-normal` |
| Label / metadata (dates, proposer name) | `text-xs` | 12px/16px | `font-medium`, `text-stone-500` |
| Numeric emphasis (cost figures) | `text-xl tabular-nums` | 20px | `font-semibold` |

Headings use `text-stone-800`; body copy `text-stone-700`; all
metadata `text-stone-500`. Never use pure black or pure white text.

## Spacing & shape

- **Radius:** cards and primary buttons `rounded-2xl` (16px); pills,
  chips, and avatar badges `rounded-full`; inputs `rounded-xl` (12px).
- **Shadow:** one soft elevation for raised surfaces —
  `shadow-[0_2px_12px_rgba(51,47,40,0.06)]` — used on cards; no
  shadow on flat/inline elements. Avoid Tailwind's default `shadow-md`
  (too hard-edged for this aesthetic).
- **Spacing rhythm:** page gutters `px-4` mobile / `px-8` desktop;
  card padding `p-5`; stack gaps `space-y-3` within a card,
  `space-y-6` between page sections.
- **Grid:** dashboard trip cards as a responsive grid
  (`grid-cols-1 sm:grid-cols-2 lg:grid-cols-3`, `gap-4`).

## Components

- **Buttons:** primary = solid `coral-500` bg, white text,
  `rounded-2xl`, `px-4 py-2.5`, `font-medium`; hover `coral-600`.
  Secondary = `stone-100` bg, `stone-800` text, same shape. Ghost =
  transparent, `text-stone-600`, used for tertiary actions like
  "decline."
- **Avatars:** circular, initials on a tinted background derived from
  a hash of the person's name (stable per person, drawn from the trip
  color palette tints so avatars feel native to the palette without a
  photo upload feature).
- **Trip card (dashboard):** full card tinted with the trip's `tint`
  color, `accent` color as a 4px left border and as the small date
  range badge; shows name, destination, date range, and a row of
  participant avatars overlapping slightly (`-space-x-2`).
- **Confirmation controls (item proposal):** "I'm in" is a pill
  toggle — outlined `stone-200` when off, solid `coral-500` fill with
  a checkmark when the current user has toggled it on. Upvote is a
  small heart/arrow icon-count pill, `stone-100` background,
  increments on click, no distinct "already voted" visual beyond a
  filled icon.
- **Cost breakdown panel:** right-rail card (desktop) / bottom sheet
  section (mobile) titled "Your split," large `tabular-nums` total per
  person, itemized list below in `text-xs` with each line's per-person
  share.
- **Calendar bars:** each trip renders as a `rounded-full` pill
  spanning its date columns, filled with `accent`, white text for the
  trip name truncated to fit. Overlapping trips stack vertically
  within the day cell with a small `amber-400` triangle badge in the
  corner of any day that has 2+ trips.

## Per-screen notes

**Dashboard (`/`):** Greeting header ("Hey Havish 👋"), primary "New
Trip" button top-right, trip card grid below. Empty state: a single
centered illustration-style placeholder + "Plan something" CTA rather
than a bare empty table.

**Trip detail (`/trips/[id]`):** Header band tinted with the trip's
color (tint bg, accent as a thin bottom border) showing name,
destination, dates, and stacked participant avatars with status
(confirmed/invited shown as a ring color, not a text label, to save
space). Below: two-column layout desktop (item list left, cost
breakdown right), single column mobile with cost breakdown collapsed
into a sticky bottom summary bar that expands on tap.

**New Trip form:** Single-column modal/sheet, not a full page —
keeps trip creation low-friction. Date range as a single inline
two-handle range picker rather than two separate date inputs.
Participant multi-select as tappable avatar chips, not a dropdown.

**Calendar (`/calendar`):** Month grid default, with a legend strip
at the top mapping each active trip's color chip to its name (since
color is the only encoding of "which trip"). Week view is a simplified
Phase-1-optional variant of the same bar treatment.

## Accessibility notes

- Trip-color coding is reinforced with the legend strip and trip name
  text — color is never the only signal.
- All interactive pill/toggle states have a minimum 3:1 contrast ratio
  against their background at both on/off states (validated against
  the hex values above).
- Minimum tap target 40x40px for all icon-only controls (upvote,
  avatar toggles) despite the compact visual size.
