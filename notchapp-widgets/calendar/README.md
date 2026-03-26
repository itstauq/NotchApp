# Calendar

## Purpose

Provide lightweight schedule awareness for the current day and the next few upcoming events.

## Why It Fits NotchApp

Calendar is a strong planning and awareness widget when kept compact. It brings useful context into the notch without trying to become a full calendar client.

## Target v1 Scope

- Match the mock widget visually and functionally in commit `88688469eb510fa87ff8b238c2babe349fa84595`
- Today's schedule
- Current and upcoming events
- Short scrollable agenda
- Colored event bars
- Quick jump-out into the full calendar destination when needed

## Likely UI Shape

- Vertical agenda list with time column on the left
- Colored event accent bar per row
- Title and metadata column on the right
- Bottom fade treatment as content scrolls out

The mock agenda in commit `88688469eb510fa87ff8b238c2babe349fa84595` should be treated as the parity target.

## Needed Generic Host APIs

- `storage`
- `environment`
- `logger`
- `openURL`
- Either generic `fetch` for remote integrations or a generic `calendar` capability for native calendar access

Likely host UI primitives:

- `ScrollView`
- styled `Row` layout
- `Text`
- `Divider`
- `Badge`
- fade mask support
- simple colored bar primitive

## Current Feasibility / Open Questions

Feasible without shell access.

This widget can stay self-contained if it fetches and renders its own data through generic host APIs rather than relying on hardcoded host calendar logic.

Open questions:

- Whether v1 should use a generic calendar capability or a narrower authenticated data source path
- How much event caching should live in widget storage versus refresh live on mount
