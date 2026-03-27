# Linear

## Purpose

Give developer-heavy users compact issue visibility and quick status awareness from the notch.

## Why It Fits NotchApp

Linear is a useful later integration because it provides high-value, low-friction triage for a focused audience without needing a full client experience inside the widget.

## Target v1 Scope

- Match the mock widget visually and functionally in commit `88688469eb510fa87ff8b238c2babe349fa84595`
- Assigned issues
- Compact status visibility
- Priority bar indicators
- Status pill affordance
- Quick jump-out to full issue pages

## Likely UI Shape

- Scrollable list of issue rows
- Priority bars on the left
- Monospaced issue ID, compact title, and trailing status pill
- Bottom fade treatment as content scrolls out

The mock in commit `88688469eb510fa87ff8b238c2babe349fa84595` should be treated as the parity target.

## Needed Generic Host APIs

- `fetch`
- `preferences` for configuration or auth inputs
- `storage`
- `openURL`
- `environment`
- `logger`

Likely host UI primitives:

- `ScrollView`
- styled `Row`
- `Badge`
- `Text`
- `Divider`
- fade mask support
- simple mini bar indicator support

## Current Feasibility / Open Questions

Feasible without shell access.

This widget can stay self-contained if it owns its API integration through generic fetch and preference-based configuration, rather than relying on host-specific Linear support.

Open questions:

- Whether v1 includes read-only issue visibility or a small set of state-changing actions
- What the preferred auth and token storage model should be for integration widgets
