# Capture

## Purpose

Quickly capture thoughts, tasks, and loose inputs without breaking focus.

## Why It Fits NotchApp

Capture is the clearest expression of NotchApp's original product motivation. It is compact, glanceable, and naturally suited to a notch-sized surface.

## Target v1 Scope

- Match the mock widget visually and functionally in commit `88688469eb510fa87ff8b238c2babe349fa84595`
- Placeholder-style capture field with trailing mic affordance
- Checklist rows with complete and delete actions
- Strikethrough styling for completed items
- Fast add, review, complete, and remove flows
- Keep the mic affordance visually present, but defer active voice input until the platform direction is clearer

## Likely UI Shape

- Top input row with placeholder text and a small circular mic affordance
- Compact stacked checklist rows below
- Each row includes a check control, single-line text, and trailing delete affordance
- Completed rows are dimmed and struck through

The mock in commit `88688469eb510fa87ff8b238c2babe349fa84595` should be treated as the parity target, not just a directional reference.

## Needed Generic Host APIs

- `storage`
- `environment`
- `logger`

Likely host UI primitives:

- `Input`
- styled `Row` or `ListItem`
- `Checkbox`
- `IconButton`
- `Spacer`
- `Divider`

## Current Feasibility / Open Questions

Feasible without shell access.

This widget can be self-contained if it owns local state and persists items through widget-scoped storage. It does not need widget-specific host logic.

Open questions:

- Whether the mic affordance stays decorative in v1 or later graduates into a generic input capability
- Whether capture items remain widget-local in v1 or later sync into a broader app model
